// SPDX-License-Identifier: GPL-2.0-only
// CSV export of executed-case records, standing in for upstream's
// fuzz_logger_csv.py at 518c139: one row per case with identity, outcome
// and traffic hex. Hex and outcome names never contain commas or quotes,
// so plain joining is safe.

///|
fn csv_escape(field : String) -> String {
  if field.contains(",") || field.contains("\"") || field.contains("\n") {
    "\"" + field.replace(old="\"", new="\"\"") + "\""
  } else {
    field
  }
}

///|
/// Convert a JSONL records file into CSV and write it. Returns the row
/// count (excluding the header).
fn write_csv_report(output : String, records_path : String) -> Int raise {
  let read = @records.parse_jsonl_bytes(@recordio.read_bytes(records_path))
  let lines : Array[String] = []
  lines.push(
    "case_id,ordinal,request_name,field_path,mutation_index,outcome,failed_step,sent_hex,received_hex",
  )
  for record in read.records {
    let sent : Array[String] = []
    let received : Array[String] = []
    for step in record.steps {
      sent.push(@records.hex_encode(step.sent))
      received.push(@records.hex_encode(step.received))
    }
    let failed = match record.failed_step {
      Some(index) => index.to_string()
      None => ""
    }
    lines.push(
      [
        csv_escape(record.case_id),
        record.ordinal.to_string(),
        csv_escape(record.request_name),
        csv_escape(record.field_path),
        record.mutation_index.to_string(),
        record.outcome,
        failed,
        sent.join(" "),
        received.join(" "),
      ].join(","),
    )
  }
  let text = lines.join("\n") + "\n"
  @recordio.write_file_raw(output, @utf8.encode(text))
  read.records.length()
}
