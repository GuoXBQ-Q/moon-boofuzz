// SPDX-License-Identifier: GPL-2.0-only
// Loopback target for examples/stateful.json. Each connection must send
// HELLO, AUTH test, and one DATA request in that order.

///|
/// TCP may split or combine writes. Preserve unread bytes between lines so
/// one receive never accidentally consumes the next protocol step.
fn read_line(
  conn : @web.RawConn,
  pending : Array[Byte],
) -> Bytes? raise @web.WebError {
  let scratch : FixedArray[Byte] = FixedArray::make(256, b'\x00')
  for ;; {
    for index, byte in pending {
      if byte == b'\n' {
        guard index < 512 else { return None }
        let line = Bytes::makei(index + 1, i => pending[i])
        for _ in 0..<(index + 1) {
          ignore(pending.remove(0))
        }
        return Some(line)
      }
    }
    guard pending.length() < 512 && conn.wait(timeout_ms=2000) else {
      return None
    }
    let count = conn.recv(scratch)
    guard count > 0 else { return None }
    for i in 0..<count {
      pending.push(scratch[i])
    }
  }
}

///|
fn expect_step(
  conn : @web.RawConn,
  pending : Array[Byte],
  expected : Bytes,
  reply : Bytes,
) -> Bool raise @web.WebError {
  match read_line(conn, pending) {
    Some(line) => {
      println("stateful target received: \{@records.hex_encode(line)}")
      if line == expected {
        conn.write(reply)
        true
      } else {
        conn.write(b"ERR\n")
        false
      }
    }
    None => false
  }
}

///|
fn serve_connection_inner(conn : @web.RawConn) -> Unit raise @web.WebError {
  let pending : Array[Byte] = []
  guard expect_step(conn, pending, b"HELLO\n", b"HELLO-OK\n") else { return }
  guard expect_step(conn, pending, b"AUTH test\n", b"AUTH-OK\n") else { return }
  match read_line(conn, pending) {
    Some(line) => {
      println("stateful target received: \{@records.hex_encode(line)}")
      if line == b"DATA one\n" || line == b"DATA two\n" {
        conn.write(b"DATA-OK\n")
      } else {
        conn.write(b"ERR\n")
      }
    }
    None => ()
  }
}

///|
fn serve_connection(conn : @web.RawConn) -> Unit {
  serve_connection_inner(conn) catch {
    _ => ()
  }
  conn.close()
}

///|
extern "c" fn exit_process(code : Int) -> Unit = "exit"

///|
fn main {
  let server = @web.RawServer::bind(port=9000) catch {
    _ => {
      println("stateful target: cannot bind 127.0.0.1:9000")
      exit_process(2)
      return
    }
  }
  println("stateful target listening on 127.0.0.1:\{server.port()}")
  for ;; {
    let incoming = server.accept(timeout_ms=1000) catch { _ => None }
    match incoming {
      Some(conn) => serve_connection(conn)
      None => ()
    }
  }
}
