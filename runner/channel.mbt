///|
/// Injection point for deterministic runner tests or custom synchronous transports.
pub(open) trait Channel {
  fn send(Self, Bytes) -> Unit raise @transport.TransportError
  fn receive(Self, Int, Int) -> @transport.Received raise @transport.TransportError
  fn last_sent_len(Self) -> Int
  fn close(Self) -> Unit
}

///|
pub impl Channel for @transport.Connection with fn send(self, bytes) {
  @transport.Connection::send(self, bytes)
}

///|
pub impl Channel for @transport.Connection with fn receive(self, limit, timeout) {
  @transport.Connection::receive(self, max_bytes=limit, timeout_ms=timeout)
}

///|
pub impl Channel for @transport.Connection with fn last_sent_len(self) {
  @transport.Connection::last_sent_len(self)
}

///|
pub impl Channel for @transport.Connection with fn close(self) {
  @transport.Connection::close(self)
}

///|
pub(all) enum ReadPolicy {
  NoResponse
  Fixed(Int)
  Until(Bytes)
  Datagram
} derive(Debug, Eq, ToJson)

///|
pub suberror RunError {
  Invalid(String)
} derive(Debug)

///|
fn validate_policy(policy : ReadPolicy, limit : Int) -> Unit raise RunError {
  match policy {
    Fixed(n) => {
      guard n >= 0 && n <= limit else {
        raise Invalid("fixed response length exceeds bound")
      }
    }
    Until(delimiter) => {
      guard !delimiter.is_empty() && delimiter.length() <= limit else {
        raise Invalid("invalid response delimiter")
      }
    }
    NoResponse | Datagram => ()
  }
}

///|
fn read_response(
  channel : &Channel,
  policy : ReadPolicy,
  pending : Ref[Bytes],
  received : Ref[Bytes],
  limit : Int,
  timeout : Int,
) -> Bool raise @transport.TransportError {
  if policy == NoResponse {
    return true
  }
  let deadline = @transport.monotonic_ms() + timeout.to_int64()
  if policy == Datagram {
    match channel.receive(limit, timeout) {
      Data(bytes) => {
        received.val = bytes
        return true
      }
      Closed => return false
    }
  }
  for ;; {
    let enough = match policy {
      Fixed(n) => if pending.val.length() >= n { Some(n) } else { None }
      Until(delimiter) =>
        pending.val.find(delimiter).map(i => i + delimiter.length())
      _ => None
    }
    if enough is Some(n) {
      received.val = pending.val[:n].to_owned()
      pending.val = pending.val[n:].to_owned()
      return true
    }
    received.val = pending.val
    guard pending.val.length() < limit else {
      raise @transport.TransportError::InvalidConfiguration(
        "response limit reached before delimiter",
      )
    }
    let left = deadline - @transport.monotonic_ms()
    guard left > 0L else { raise @transport.TransportError::Timeout(Receive) }
    match channel.receive(limit - pending.val.length(), left.to_int()) {
      Closed => return false
      Data(bytes) => {
        guard !bytes.is_empty() else { return false }
        pending.val = pending.val + bytes
      }
    }
  }
}
