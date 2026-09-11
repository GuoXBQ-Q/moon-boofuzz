///|
fn sample_record() -> CaseRecord {
  {
    format_version: 1,
    case_id: "case:1",
    generator_version: "v1",
    request_name: "r",
    field_path: "r.x",
    mutation_index: 0,
    ordinal: 0,
    path: ["r"],
    config: { "transport": "custom" },
    steps: [
      {
        request_name: "r",
        sent: b"\x00\xff",
        received: b"\xfe\x00",
        completed: true,
      },
    ],
    outcome: "passed",
    detail: "",
    failed_step: None,
  }
}

///|
test "binary records round trip and JSONL retains complete prefix" {
  let record = sample_record()
  let encoded = record.encode()
  assert_true(encoded.contains("00ff") && encoded.contains("fe00"))
  assert_eq(CaseRecord::decode(encoded), record)
  let read = parse_jsonl(encoded + "\n" + encoded + "\n{")
  assert_eq(read.records, [record, record])
  assert_true(read.error is Some(issue) && issue.line == 3)
  let invalid_utf8 = parse_jsonl_bytes(@utf8.encode(encoded + "\n") + b"\xff\n")
  assert_eq(invalid_utf8.records, [record])
  assert_true(invalid_utf8.error is Some(_))
}

///|
test "corrupt hex unknown versions and missing identity fail explicitly" {
  for text in ["0", "gg", "你好"] {
    assert_true(
      try {
        ignore(hex_decode(text))
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      ignore(CaseRecord::decode("{\"format_version\":2}"))
      false
    } catch {
      UnsupportedVersion(2) => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(CaseRecord::decode("{}"))
      false
    } catch {
      _ => true
    },
  )
  let bad = { ..sample_record(), case_id: "", }
  assert_true(
    try {
      ignore(bad.encode())
      false
    } catch {
      _ => true
    },
  )
}
