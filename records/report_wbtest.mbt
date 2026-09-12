///|
test "report groups outcomes and locates failed cases" {
  let passed = sample_record()
  let failed = {
    ..passed,
    case_id: "failed",
    outcome: "receive_timeout",
    failed_step: Some(0),
    steps: [
      { request_name: "r", sent: b"\xff", received: b"", completed: false, },
    ],
  }
  let report = summarize([passed, failed, failed])
  assert_eq(report.total, 3)
  assert_eq(report.outcomes.get("passed"), Some(1))
  assert_eq(report.outcomes.get("receive_timeout"), Some(2))
  assert_eq(report.failures[0].line, 2)
  assert_eq(report.failures[1].line, 3)
  assert_eq(report.failures[0].case_id, "failed")
}
