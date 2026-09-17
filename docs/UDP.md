# UDP datagrams

`Connection::udp(endpoint)` uses a connected unicast IPv4/IPv6 socket. Every
`send(bytes)` is one datagram, including zero-length input. Unlike TCP, it never
splits a request into chunks. Payloads over 65,507 bytes are rejected before
sending. Connected sockets discard datagrams from other source endpoints.

`receive()` returns one `Data` event, including `Data(b"")` for an empty
datagram. An oversized datagram relative to the receive buffer is consumed and
raises `DatagramTooLarge`; no truncated payload is reported as complete.
Linux uses `MSG_TRUNC`; Windows uses the returned `WSAEMSGSIZE` error. A
Windows SDK definition of MSG_TRUNC must not be passed as a recv input flag.
Timeout and system failure remain distinct.

# 服务端模式与广播(阶段 5c)

`Connection::udp_server(endpoint)` 对齐上游 server 语义
(udp_socket_connection.py:36-133):绑定 `host:port`(SO_REUSEADDR),
空 host 绑定通配地址(INADDR_ANY)、端口 0 由系统分配临时端口
(经 `local_port()` 读取实际端口,连接对象内 endpoint 同步为真实端口);
每次 `receive()` 用 `recvfrom` 记录最后对端,`send()` 经 `sendto` 回发该
对端;未收到任何请求就 `send` 直接失败(上游 BoofuzzError 的
"recv() must be called before send")。Runner 集成:每例拨号后先做一次
受限时的预接收等待目标请求(消耗该报文,不入步骤记录),然后发送变异
载荷——即"收到请求→模糊应答"的服务端模糊流程;预接收超时记为
`receive_timeout`(连接阶段失败,无步骤)。server/broadcast 接收路径的
超长报文与连接路径一致:整个报文被消耗并抛出 `DatagramTooLarge`
(POSIX 经 `MSG_TRUNC` 取真实长度,Windows 经 `WSAEMSGSIZE`)。

`Connection::udp_broadcast(endpoint)` 开启 SO_BROADCAST 的非连接套接字:
每个 `send()` 都是到 `endpoint.host:port` 的 `sendto`(host 须为 IPv4
字面量广播地址),`receive()` 接受任意来源。JSON 执行配置以
`"udp_server": true` / `"udp_broadcast": true` 启用(仅 UDP 传输,二者
互斥)。多播、IPv6 广播与通配目的仍不支持。

Source: `boofuzz/connections/udp_socket_connection.py`
(__init__ :36-45、open :48-67、recv :70-100、send :103-133),revision
`518c13904fc32e7f2cc88c9dec934e509062953e` (GPL-2.0-only)。预接收的
Runner 集成与"消耗请求报文"为 MoonBit 适配(上游连接层直接抛错)。
回环测试覆盖:server 记录对端并应答、send-before-recv 失败、广播数据报
到达未连接接收方、CLI `udp_server` 端到端。

CI initializes the MoonBit registry before invoking standalone `.mbtx` tools.
This fixes the clean-runner failure to resolve the developer-only async module;
the production module still has no async runtime dependency.
