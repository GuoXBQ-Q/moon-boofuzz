// SPDX-License-Identifier: GPL-2.0-only
// File transport: each sent message is written to its own numbered file,
// mirroring upstream connections/file_connection.py at 518c139 (recv is
// always empty, so pair this transport with a NoResponse policy).

///|
pub struct FileChannel {
  directory : String
  prefix : String
  /// Shared across dials so case files number continuously for the whole
  /// run (the runner dials a fresh channel per case).
  counter : Ref[Int]
  mut last_sent : Int
}

///|
/// Create the target directory (idempotent) and start numbering at 1.
pub fn FileChannel::open(
  directory~ : String,
  prefix? : String = "case-",
  counter? : Ref[Int] = Ref(0),
) -> FileChannel raise StorageError {
  // Explicit NUL keeps the C-side strlen within the buffer.
  let bytes = @utf8.encode(directory) + b"\x00"
  guard make_directory(bytes) == 0 else { raise WriteFailure(-1) }
  { directory, prefix, counter, last_sent: 0, }
}

///|
impl @runner.Channel for FileChannel with fn send(self, bytes) {
  self.counter.val += 1
  let path = @utf8.encode(
      self.directory + "/" + self.prefix + self.counter.val.to_string(),
    ) +
    b"\x00"
  let handle = create_file(path)
  errdefer close_file(handle)
  guard write_file(handle, bytes, bytes.length()) == 0 else {
    raise @transport.TransportError::SendFailure(file_error(handle))
  }
  close_file(handle)
  self.last_sent = bytes.length()
}

///|
impl @runner.Channel for FileChannel with fn receive(_self, _, _) {
  // File targets never respond; the runner's policy decides completion.
  @transport.Received::Closed
}

///|
impl @runner.Channel for FileChannel with fn last_sent_len(self) {
  self.last_sent
}

///|
impl @runner.Channel for FileChannel with fn close(_self) {
  // Files are opened and closed per send; nothing to release.
}

///|
/// Build a runner for a file-transport execution config: every case writes
/// its messages into the configured path as numbered files. Only the
/// NoResponse policy is accepted by the parser.
pub fn file_runner(
  config : @runner.ExecutionConfig,
  paths : Array[@core.SessionPath],
  monitor? : @runner.Monitor = @runner.Monitor::new(),
  limit~ : Int,
  combinatorial? : Bool = false,
  max_depth? : Int,
  start? : Int = 0,
  end? : Int? = None,
  sleep_between? : Int = 0,
) -> @runner.Runner raise {
  let directory = match config.file_path {
    Some(directory) => directory
    None => abort("file_runner requires a file-transport config")
  }
  let depth : Int? = max_depth
  let counter : Ref[Int] = Ref(0)
  let dial : () -> &@runner.Channel raise @transport.TransportError = fn() raise @transport.TransportError {
    FileChannel::open(directory~, counter~) catch {
      _ => raise @transport.TransportError::SendFailure(-1)
    }
  }
  match depth {
    Some(depth) =>
      @runner.Runner::with_dialer(
        paths,
        dial,
        policies=config.policies,
        limit~,
        monitor~,
        combinatorial~,
        max_depth=depth,
        variables=Some(config.variables),
        check_data_received=config.check_data_received,
        restart_threshold=config.restart_threshold,
        sleep_between_ms=sleep_between,
        crash_threshold_request=config.crash_threshold_request,
        crash_threshold_element=config.crash_threshold_element,
        start~,
        end~,
      )
    None =>
      @runner.Runner::with_dialer(
        paths,
        dial,
        policies=config.policies,
        limit~,
        monitor~,
        combinatorial~,
        variables=Some(config.variables),
        check_data_received=config.check_data_received,
        restart_threshold=config.restart_threshold,
        sleep_between_ms=sleep_between,
        crash_threshold_request=config.crash_threshold_request,
        crash_threshold_element=config.crash_threshold_element,
        start~,
        end~,
      )
  }
}
