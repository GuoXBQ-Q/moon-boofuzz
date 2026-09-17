///|
type Socket

///|
extern "c" fn socket_new() -> Socket = "bf_new"

///|
#borrow(socket)
extern "c" fn socket_close(socket : Socket) -> Unit = "bf_close"

///|
#borrow(socket)
extern "c" fn socket_error(socket : Socket) -> Int = "bf_error"

///|
extern "c" fn now_ms() -> Int64 = "bf_now"

///|
#borrow(socket, host)
extern "c" fn socket_connect(
  socket : Socket,
  host : Bytes,
  port : Int,
  timeout : Int,
  udp : Int,
) -> Int = "bf_connect"

///|
#borrow(socket)
extern "c" fn socket_wait(socket : Socket, writing : Int, timeout : Int) -> Int = "bf_wait"

///|
#borrow(socket, bytes)
extern "c" fn socket_send(
  socket : Socket,
  bytes : Bytes,
  offset : Int,
  length : Int,
) -> Int = "bf_send"

///|
#borrow(socket, bytes)
extern "c" fn socket_receive(
  socket : Socket,
  bytes : FixedArray[Byte],
  length : Int,
) -> Int = "bf_recv"

// Sleep for milliseconds; used for restart delays and case pacing.

///|
extern "c" fn bf_sleep(ms : Int) -> Unit = "bf_sleep"

///|
#borrow(socket, host)
extern "c" fn udp_server_bind(
  socket : Socket,
  host : Bytes,
  host_length : Int,
  port : Int,
) -> Int = "bf_udp_server"

///|
#borrow(socket)
extern "c" fn udp_broadcast_enable(socket : Socket) -> Int = "bf_udp_broadcast_enable"

///|
#borrow(socket)
extern "c" fn udp_local_port(socket : Socket) -> Int = "bf_udp_local_port"

///|
#borrow(socket, bytes)
extern "c" fn udp_receive_from(
  socket : Socket,
  bytes : FixedArray[Byte],
  length : Int,
) -> Int = "bf_udp_recvfrom"

///|
#borrow(socket, bytes)
extern "c" fn udp_send_to_peer(
  socket : Socket,
  bytes : Bytes,
  length : Int,
) -> Int = "bf_udp_send_peer"

///|
#borrow(socket, host, bytes)
extern "c" fn udp_send_to_address(
  socket : Socket,
  host : Bytes,
  host_length : Int,
  port : Int,
  bytes : Bytes,
  length : Int,
) -> Int = "bf_udp_send_address"

///|
pub fn sleep_ms(ms : Int) -> Unit {
  bf_sleep(ms)
}
