///|
pub(all) struct FailedCase {
  line : Int
  case_id : String
  outcome : String
  failed_step : Int?
  detail : String
} derive(Debug, Eq, ToJson)

///|
pub extend FailedCase with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FailedCase with Eq::{not_equal, equal}

///|
pub extend FailedCase with ToJson::{to_json}

///|
pub(all) struct Report {
  total : Int
  outcomes : Map[String, Int]
  failures : Array[FailedCase]
} derive(Debug, ToJson)

///|
pub extend Report with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Report with ToJson::{to_json}

///|
pub fn summarize(records : Array[CaseRecord]) -> Report raise RecordError {
  let outcomes : Map[String, Int] = Map([])
  let failures : Array[FailedCase] = []
  for index, record in records {
    record.validate()
    outcomes[record.outcome] = outcomes.get(record.outcome).unwrap_or(0) + 1
    if record.outcome != "passed" {
      failures.push({
        line: index + 1,
        case_id: record.case_id,
        outcome: record.outcome,
        failed_step: record.failed_step,
        detail: record.detail,
      })
    }
  }
  { total: records.length(), outcomes, failures, }
}
