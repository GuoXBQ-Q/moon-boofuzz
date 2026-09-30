///|
pub(all) suberror StorageError {
  InvalidPath
  OpenFailure(Int)
  ReadFailure(Int)
  WriteFailure(Int)
} derive(Debug)

///|
pub extend StorageError with @moonbitlang/core/debug.Debug::{to_repr}

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

///|
/// Create every missing directory level along path, tolerating levels
/// that already exist — the equivalent of upstream helpers.mkdir_safe /
/// os.makedirs(exist_ok=True). Both '/' and '\' act as separators.
pub fn ensure_directory(path : String) -> Unit raise StorageError {
  ignore(check_path(path))
  let buffer = StringBuilder()
  for ch in path {
    if ch == '/' || ch == '\\' {
      make_directory_prefix(buffer.to_string())
      buffer.write_char(ch)
    } else {
      buffer.write_char(ch)
    }
  }
  make_directory_prefix(buffer.to_string())
}

///|
/// Create one directory level, skipping roots that always exist (empty,
/// ".", "/" and drive roots like "C:") and tolerating an existing
/// directory (bf_file_mkdir accepts EEXIST).
fn make_directory_prefix(body : String) -> Unit raise StorageError {
  if body.is_empty() || body == "." {
    return
  }
  if body.length() == 2 && body[1] == ':' {
    return
  }
  let bytes = @utf8.encode(body) + b"\x00"
  guard make_directory(bytes) == 0 else { raise WriteFailure(-1) }
}

///|
/// Directory portion of a path — everything before the last separator.
/// Empty when the path contains no separator.
pub fn parent_directory(path : String) -> String {
  let mut last = -1
  let mut index = 0
  for ch in path {
    if ch == '/' || ch == '\\' {
      last = index
    }
    index += 1
  }
  if last <= 0 {
    return ""
  }
  path[0:last].to_owned()
}

///|
/// Read at most max_bytes from the beginning of a file. Larger files are
/// valid; read_bytes retains its separate whole-file size-limit contract.
pub fn read_prefix(
  path : String,
  max_bytes? : Int = 16,
) -> Bytes raise StorageError {
  guard max_bytes >= 0 && max_bytes <= 67108864 else { raise InvalidPath }
  let file = open_file(check_path(path), 0)
  defer close_file(file)
  if file_error(file) != 0 {
    raise OpenFailure(file_error(file))
  }
  let buffer : FixedArray[Byte] = FixedArray::make(max_bytes, b'\x00')
  let length = read_prefix_into(file, buffer, max_bytes)
  guard length >= 0 else { raise ReadFailure(file_error(file)) }
  Bytes::makei(length, i => buffer[i])
}
