///|
pub(all) suberror StorageError {
  InvalidPath
  OpenFailure(Int)
  ReadFailure(Int)
  WriteFailure(Int)
} derive(Debug)

///|
pub struct Writer {
  file : FileHandle
}

///|
pub fn print_error(message : String) -> Unit {
  let bytes = @utf8.encode(message + "\n")
  print_error_ffi(bytes, bytes.length())
}

///|
fn check_path(path : String) -> Bytes raise StorageError {
  guard !path.is_empty() && !path.contains("\u0000") else { raise InvalidPath }
  @utf8.encode(path)
}

///|
pub fn Writer::open(path : String) -> Writer raise StorageError {
  let file = open_file(check_path(path), 1)
  let code = file_error(file)
  if code != 0 {
    close_file(file)
    raise OpenFailure(code)
  }
  { file, }
}

///|
pub fn Writer::append(
  self : Writer,
  record : @records.CaseRecord,
) -> Unit raise {
  let bytes = @utf8.encode(record.encode() + "\n")
  if write_file(self.file, bytes, bytes.length()) != 0 {
    raise WriteFailure(file_error(self.file))
  }
}

///|
pub fn Writer::close(self : Writer) -> Unit {
  close_file(self.file)
}

///|
pub fn read_bytes(
  path : String,
  max_bytes? : Int = 67108864,
) -> Bytes raise StorageError {
  guard max_bytes >= 0 else { raise InvalidPath }
  let file = open_file(check_path(path), 0)
  defer close_file(file)
  if file_error(file) != 0 {
    raise OpenFailure(file_error(file))
  }
  let bytes = read_file(file, max_bytes)
  if file_error(file) != 0 {
    raise ReadFailure(file_error(file))
  }
  bytes
}

///|
pub fn read_records(
  path : String,
  max_bytes? : Int = 67108864,
) -> @records.RecordRead raise StorageError {
  @records.parse_jsonl_bytes(read_bytes(path, max_bytes~))
}

///|
/// Stop immediately if persistence fails; no subsequent case is executed.
pub fn capture(runner : @runner.Runner, writer : Writer) -> Int raise {
  errdefer runner.stop()
  let mut count = 0
  while runner.next() is Some(result) {
    writer.append(runner.record(result))
    count += 1
  }
  count
}

///|
/// Create/truncate a file with raw bytes — the escape hatch for non-JSONL
/// outputs such as CSV reports.
pub fn write_file_raw(path : String, bytes : Bytes) -> Unit raise StorageError {
  let handle = create_file(@utf8.encode(path) + b"\x00")
  errdefer close_file(handle)
  guard write_file(handle, bytes, bytes.length()) == 0 else {
    raise WriteFailure(file_error(handle))
  }
  close_file(handle)
}
