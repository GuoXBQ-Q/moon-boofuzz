// SPDX-License-Identifier: GPL-2.0-only
// Raw externs over web/http.c. Conventions mirror transport/ffi.mbt:
// 0 = success, -1 = failure (platform errno in the error slot), -2 =
// "nothing ready yet" for nonblocking accept/wait/recv.

///|
type WebSocket

///|
extern "c" fn web_socket_new() -> WebSocket = "bf_web_new"

///|
#borrow(socket)
extern "c" fn web_socket_error(socket : WebSocket) -> Int = "bf_web_error"

///|
#borrow(socket)
extern "c" fn web_socket_close(socket : WebSocket) -> Unit = "bf_web_close"

///|
#borrow(socket)
extern "c" fn web_listen(socket : WebSocket, port : Int) -> Int = "bf_web_listen"

///|
#borrow(listener, client)
extern "c" fn web_accept(listener : WebSocket, client : WebSocket) -> Int = "bf_web_accept"

///|
#borrow(socket)
extern "c" fn web_wait(
  socket : WebSocket,
  writing : Int,
  timeout_ms : Int,
) -> Int = "bf_web_wait"

///|
#borrow(socket, buffer)
extern "c" fn web_recv(
  socket : WebSocket,
  buffer : FixedArray[Byte],
  length : Int,
) -> Int = "bf_web_recv"

///|
#borrow(socket, bytes)
extern "c" fn web_send(socket : WebSocket, bytes : Bytes, length : Int) -> Int = "bf_web_send"

///|
extern "c" fn web_now_ms() -> Int64 = "bf_web_now_ms"
