// SPDX-License-Identifier: GPL-2.0-only
// Session state behind the web UI, standing in for upstream's Session
// (live runs) and sessions/session_info.py SessionInfo (offline viewing).
// The shape mirrors web/app.py's app.session usage.

///|
/// What the router needs from a session. Offline views report
/// is_paused=false, state="finished" and no element progress, exactly
/// like SessionInfo (session_info.py:64-86).
pub trait SessionView {
  fn is_paused(Self) -> Bool
  fn toggle_pause(Self) -> Unit
  fn current_index(Self) -> Int raise
  fn num_mutations(Self) -> Int?
  fn current_element(Self) -> String
  fn current_case_name(Self) -> String
  fn state(Self) -> String
  fn runtime_seconds(Self) -> Double
  fn exec_speed(Self) -> Double
  fn crashes(Self) -> Map[Int, Array[String]] raise
  fn test_case_data(Self, Int) -> @db.DbCase raise
}

///|
/// Live view for `run --web-port`: counters live in Refs the capture loop
/// refreshes; pause is the flag checked before every case. `total` is the
/// primitive-count denominator (upstream num_mutations). When `db_path`
/// names the results database the run is writing, /test-case details are
/// served from it live — upstream's approach, constant memory; the
/// in-memory record cache remains only as the fallback for sessions
/// without a database (throttled runs evict passing cases from the db,
/// so their details vanish exactly like upstream's).
pub struct LiveSession {
  paused : @ref.Ref[Bool]
  executed : @ref.Ref[Int]
  total : Int
  started_ms : Int64
  failures : @ref.Ref[Map[Int, Array[String]]]
  current_name : @ref.Ref[String]
  reader : @db.DbReader?
  cases : @ref.Ref[Map[Int, @records.CaseRecord]]
}

///|
pub fn LiveSession::new(
  total~ : Int,
  db_path? : String? = None,
) -> LiveSession raise {
  let reader = match db_path {
    Some(path) => Some(@db.DbReader::open(path))
    None => None
  }
  {
    paused: @ref.Ref(false),
    executed: @ref.Ref(0),
    total,
    started_ms: web_now_ms(),
    failures: @ref.Ref(Map([])),
    current_name: @ref.Ref(""),
    reader,
    cases: @ref.Ref(Map([])),
  }
}

///|
/// Release the results-database reader, if any.
pub fn LiveSession::close(self : LiveSession) -> Unit {
  match self.reader {
    Some(reader) => reader.close()
    None => ()
  }
}

///|
/// Observe one executed case: advances the counters, records failures
/// for the crash list and, without a database reader, keeps the record
/// for the detail pages. Memory in fallback mode grows with the number
/// of executed cases.
pub fn LiveSession::observe(
  self : LiveSession,
  record : @records.CaseRecord,
) -> Unit {
  self.executed.val += 1
  self.current_name.val = record.request_name
  if self.reader is None {
    self.cases.val[record.ordinal] = record
  }
  if record.outcome != "passed" {
    match record.failed_step {
      Some(-1) => ()
      _ =>
        match self.failures.val.get(record.ordinal) {
          Some(list) => list.push(record.detail)
          None => self.failures.val[record.ordinal] = [record.detail]
        }
    }
  }
}

///|
pub impl SessionView for LiveSession with fn is_paused(self) {
  self.paused.val
}

///|
#deprecated
pub extend LiveSession with SessionView::{
  state,
  toggle_pause,
  current_index,
  current_element,
  exec_speed,
  current_case_name,
  num_mutations,
  crashes,
  test_case_data,
  is_paused,
  runtime_seconds,
}

///|
pub impl SessionView for LiveSession with fn toggle_pause(self) {
  self.paused.val = !self.paused.val
}

///|
pub impl SessionView for LiveSession with fn current_index(self) {
  self.executed.val
}

///|
pub impl SessionView for LiveSession with fn num_mutations(self) {
  // The denominator the caller computed from the definition's primitive
  // counts (upstream Session.num_mutations); combinatorial blasting may
  // execute past it, and a zero total renders as Unbounded.
  if self.total > 0 {
    Some(self.total)
  } else {
    None
  }
}

///|
pub impl SessionView for LiveSession with fn current_element(self) {
  element_name(self.current_name.val)
}

///|
pub impl SessionView for LiveSession with fn current_case_name(self) {
  self.current_name.val
}

///|
pub impl SessionView for LiveSession with fn state(_self) {
  "running"
}

///|
pub impl SessionView for LiveSession with fn runtime_seconds(self) {
  elapsed_seconds(self.started_ms)
}

///|
pub impl SessionView for LiveSession with fn exec_speed(self) {
  let runtime = elapsed_seconds(self.started_ms)
  if runtime <= 0.0 {
    0.0
  } else {
    self.executed.val.to_double() / runtime
  }
}

///|
pub impl SessionView for LiveSession with fn crashes(self) {
  self.failures.val
}

///|
pub impl SessionView for LiveSession with fn test_case_data(self, index) {
  // Database-backed sessions read the live-written results file (the
  // single-threaded capture loop commits and serves between cases); the
  // fallback keeps observed records in memory. Missing cases raise and
  // the page explains the case has not run yet (or was evicted by the
  // keep-only-n throttle, like upstream).
  match self.reader {
    Some(reader) => reader.get_test_case_data(index)
    None =>
      match self.cases.val.get(index) {
        Some(record) => record_case(record)
        None => raise @db.NoSuchCase(index)
      }
  }
}

///|
fn element_name(name : String) -> String {
  if name.is_empty() {
    "[N/A]"
  } else {
    name
  }
}

///|
fn elapsed_seconds(started_ms : Int64) -> Double {
  (web_now_ms() - started_ms).to_double() / 1000.0
}

///|
/// Offline read-only view over a results file, the SessionInfo equivalent
/// (session_info.py): a SQLite results database, or the JSONL records the
/// CLI writes. current_index is the persisted case count, like upstream's
/// COUNT(*) FROM cases.
pub struct OfflineSession {
  reader : @db.DbReader?
  records : Array[@records.CaseRecord]
  names : Map[Int, String]
}

///|
pub fn OfflineSession::open_database(path : String) -> OfflineSession raise {
  let reader = @db.DbReader::open(path)
  errdefer reader.close()
  let rows = reader.query("SELECT number, name FROM cases")
  let names : Map[Int, String] = Map([])
  for row in rows {
    let number = value_index(row.values[0])
    let name = value_text(row.values[1])
    names[number] = name
  }
  { reader: Some(reader), records: [], names, }
}

///|
pub fn OfflineSession::open_jsonl(path : String) -> OfflineSession raise {
  let read = @records.parse_jsonl_bytes(@recordio.read_bytes(path))
  let names : Map[Int, String] = Map([])
  for record in read.records {
    names[record.ordinal] = record.request_name
  }
  { reader: None, records: read.records, names, }
}

///|
pub fn OfflineSession::close(self : OfflineSession) -> Unit {
  match self.reader {
    Some(reader) => reader.close()
    None => ()
  }
}

///|
fn value_index(value : @db.DbValue) -> Int {
  match value {
    @db.VInt(number) => number.to_int()
    _ => 0
  }
}

///|
fn value_text(value : @db.DbValue) -> String {
  match value {
    @db.VText(text) => text
    _ => ""
  }
}

///|
pub impl SessionView for OfflineSession with fn is_paused(_self) {
  false
}

///|
#deprecated
pub extend OfflineSession with SessionView::{
  state,
  toggle_pause,
  current_index,
  current_element,
  exec_speed,
  current_case_name,
  num_mutations,
  crashes,
  test_case_data,
  is_paused,
  runtime_seconds,
}

///|
pub impl SessionView for OfflineSession with fn toggle_pause(_self) {
  // Read-only view: SessionInfo.is_paused has no setter.
}

///|
pub impl SessionView for OfflineSession with fn current_index(self) {
  match self.reader {
    Some(_) => self.names.length()
    None => self.records.length()
  }
}

///|
pub impl SessionView for OfflineSession with fn num_mutations(_self) {
  None
}

///|
pub impl SessionView for OfflineSession with fn current_element(_self) {
  "[N/A]"
}

///|
pub impl SessionView for OfflineSession with fn current_case_name(_self) {
  ""
}

///|
pub impl SessionView for OfflineSession with fn state(_self) {
  "finished"
}

///|
pub impl SessionView for OfflineSession with fn runtime_seconds(_self) {
  0.0
}

///|
pub impl SessionView for OfflineSession with fn exec_speed(_self) {
  0.0
}

///|
pub impl SessionView for OfflineSession with fn crashes(self) {
  match self.reader {
    Some(reader) => reader.failure_map()
    None => jsonl_failures(self.records)
  }
}

///|
pub impl SessionView for OfflineSession with fn test_case_data(self, index) {
  match self.reader {
    Some(reader) => reader.get_test_case_data(index)
    None =>
      match jsonl_case(self.records, index) {
        Some(case) => case
        None => raise @db.NoSuchCase(index)
      }
  }
}

///|
/// The failure map collects non-passed outcomes except connection errors,
/// which the DB logger records as type "error" (see DbLogger::log_record).
fn jsonl_failures(
  records : Array[@records.CaseRecord],
) -> Map[Int, Array[String]] {
  let map : Map[Int, Array[String]] = Map([])
  for record in records {
    if record.outcome != "passed" {
      match record.failed_step {
        Some(-1) => ()
        _ =>
          match map.get(record.ordinal) {
            Some(list) => list.push(record.detail)
            None => map[record.ordinal] = [record.detail]
          }
      }
    }
  }
  map
}

///|
fn jsonl_case(records : Array[@records.CaseRecord], index : Int) -> @db.DbCase? {
  for record in records {
    if record.ordinal == index {
      return Some(record_case(record))
    }
  }
  None
}

///|
/// One CaseRecord rendered as the case inspector's data: the upstream log
/// sequence (step / send / receive per protocol step, then the verdict),
/// shared by the offline JSONL view and the live session.
fn record_case(record : @records.CaseRecord) -> @db.DbCase {
  let steps : Array[@db.DbStep] = []
  for step in record.steps {
    steps.push({
      step_type: "step",
      description: step.request_name,
      data: b"",
      timestamp: "",
      truncated: false,
    })
    steps.push({
      step_type: "send",
      description: "",
      data: step.sent,
      timestamp: "",
      truncated: false,
    })
    steps.push({
      step_type: "receive",
      description: "",
      data: step.received,
      timestamp: "",
      truncated: false,
    })
  }
  let step_type = if record.outcome == "passed" {
    "pass"
  } else if record.failed_step is Some(-1) {
    "error"
  } else {
    "fail"
  }
  steps.push({
    step_type,
    description: record.detail,
    data: b"",
    timestamp: "",
    truncated: false,
  })
  { name: record.request_name, index: record.ordinal, timestamp: "", steps, }
}
