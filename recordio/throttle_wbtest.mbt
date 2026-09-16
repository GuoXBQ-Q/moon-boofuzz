// SPDX-License-Identifier: GPL-2.0-only
// Keep-only-n throttling over JSONL: first case + last-N window + fail
// flush, mirroring fuzz_logger_db.py:206-225 at the record level.

///|
fn throttled_record(ordinal : Int, outcome : String) -> @records.CaseRecord {
  let connect_failed = outcome == "connect_failed"
  {
    format_version: 1,
    case_id: "case-\{ordinal}",
    generator_version: "v1",
    request_name: "r",
    field_path: "r.x",
    mutation_index: ordinal,
    ordinal,
    path: ["r"],
    config: {},
    steps: if connect_failed {
      []
    } else {
      [
        {
          request_name: "r",
          sent: b"\x00",
          received: b"",
          completed: outcome == "passed",
        },
      ]
    },
    outcome,
    detail: outcome,
    failed_step: if outcome == "passed" {
      None
    } else if connect_failed {
      Some(-1)
    } else {
      Some(0)
    },
  }
}

///|
fn persisted_ordinals(keep : Int, outcomes : Array[String]) -> Array[Int] raise {
  let path = @utf8.decode(temp_path())
  defer remove_temp(@utf8.encode(path))
  let writer = Writer::open(path)
  defer writer.close()
  let throttled = ThrottledWriter::new(writer, keep~)
  for ordinal, outcome in outcomes {
    throttled.append(throttled_record(ordinal, outcome))
  }
  throttled.close_test()
  writer.close()
  read_records(path).records.map(record => record.ordinal)
}

///|
test "three passes and one failure keep the window plus the failure" {
  // fuzz_logger_db.py:206-225 with num_log_cases=2: case 0 persists as the
  // first case, case 1 is trimmed, the failure flushes cases 2 and 3.
  assert_eq(
    persisted_ordinals(2, ["passed", "passed", "passed", "send_failed"]),
    [0, 2, 3],
  )
}

///|
test "record-passes zero writes every case immediately" {
  assert_eq(
    persisted_ordinals(0, ["passed", "passed", "send_failed", "passed"]),
    [0, 1, 2, 3],
  )
}

///|
test "closing flushes the trimmed window of an all-pass run" {
  assert_eq(persisted_ordinals(2, ["passed", "passed", "passed", "passed"]), [
    0, 2, 3,
  ])
  assert_eq(persisted_ordinals(10, ["passed", "passed", "passed", "passed"]), [
    0, 1, 2, 3,
  ])
}

///|
test "failures flush before the window overflows" {
  // Every failure is written immediately together with the retained
  // passes; consecutive failures leave nothing buffered. With keep=3:
  // 0 (first case), 1 and 2 (failures), then the window before failure 6
  // keeps 4 and 5.
  assert_eq(
    persisted_ordinals(3, [
      "passed", "connect_failed", "connect_failed", "passed", "passed", "passed",
      "send_failed",
    ]),
    [0, 1, 2, 4, 5, 6],
  )
}
