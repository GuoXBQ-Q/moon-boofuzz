///|
fn replay_or_report(
  command : String,
  input : String,
  flags : ArrayView[String],
) -> Int raise {
  let opts = options(
    flags,
    if command == "report" {
      ["--max-bytes"]
    } else {
      ["--id", "--host", "--port", "--max-bytes"]
    },
  )
  let read = @recordio.read_records(
    input,
    max_bytes=int_option(opts, "--max-bytes").unwrap_or(67108864),
  )
  if command == "report" {
    let report = @records.summarize(read.records)
    let issue : Json = match read.error {
      None => Json::null()
      Some(error) => { "line": error.line, "message": error.message }
    }
    let output : Json = {
      "kind": "report",
      "summary": ToJson::to_json(report),
      "error": issue,
    }
    println(output.stringify())
    return if read.error is None { 0 } else { 2 }
  }
  if read.error is Some(error) {
    raise InvalidArguments(
      "invalid JSONL at line \{error.line}: " + error.message,
    )
  }
  let id = opts
    .get("--id")
    .unwrap_or_else(() => raise InvalidArguments("replay requires --id CASE_ID"))
  let record = @records.select_case(read.records, id)
  let host = opts.get("--host")
  let port = int_option(opts, "--port")
  let result = match (host, port) {
    (None, None) => @runner.replay(record)
    (Some(host), Some(port)) =>
      @runner.replay(record, override_target=(host, port))
    _ => raise InvalidArguments("--host and --port must be supplied together")
  }
  let steps : Array[Json] = result.steps.map(step => {
    "request_name": step.request_name,
    "sent_hex": @records.hex_encode(step.sent),
    "received_hex": @records.hex_encode(step.received),
    "completed": step.completed,
  })
  let failed_step : Json = match result.failed_step {
    Some(index) => ToJson::to_json(index)
    None => Json::null()
  }
  let output : Json = {
    "kind": "replay_result",
    "case_id": result.case_id,
    "outcome": result.outcome.name(),
    "detail": "\{Repr(result.outcome)}",
    "failed_step": failed_step,
    "steps": steps,
  }
  println(output.stringify())
  if result.outcome == @runner.Passed {
    0
  } else {
    1
  }
}
