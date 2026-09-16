// SPDX-License-Identifier: GPL-2.0-only
// SQLite results logging, standing in for upstream's fuzz_logger_db.py at
// 518c139: `run --db FILE` writes the same records to JSONL and to the
// upstream-compatible cases/steps tables in one capture loop. Both sides
// honor --record-passes keep-only-n throttling.

///|
/// Capture every executed case into JSONL and, when present, the SQLite
/// results database. `record_passes` > 0 routes JSONL writes through the
/// keep-only-n throttle. Like @recordio.capture, execution stops
/// immediately if persistence fails.
fn capture_all(
  runner : @runner.Runner,
  writer : @recordio.Writer,
  logger : @db.DbLogger?,
  record_passes : Int,
) -> Int raise {
  errdefer runner.stop()
  let throttled = @recordio.ThrottledWriter::new(writer, keep=record_passes)
  let mut count = 0
  while runner.next() is Some(result) {
    let record = runner.record(result)
    if record_passes > 0 {
      throttled.append(record)
    } else {
      writer.append(record)
    }
    match logger {
      Some(active) => active.log_record(record)
      None => ()
    }
    count += 1
  }
  if record_passes > 0 {
    throttled.close_test()
  }
  count
}
