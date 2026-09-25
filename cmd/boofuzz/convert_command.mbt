// SPDX-License-Identifier: GPL-2.0-only
// `convert` — serve the HTTP-message-to-definition converter web app on
// loopback until interrupted. Stateless: paste a raw request, pick the
// fuzzed segments, download the protocol-definition JSON.

///|
fn convert_command(flags : ArrayView[String]) -> Unit raise {
  let opts = options(flags.to_owned(), ["--ui-port"])
  let port = int_option(opts, "--ui-port").unwrap_or(26001)
  // Port 0 asks the OS for a free port; the bound port is printed below.
  guard port >= 0 && port <= 65535 else {
    raise InvalidArguments(
      "--ui-port must be a port number (0 picks a free port)",
    )
  }
  let server = @web.HttpServer::bind(port~)
  println(
    "Serving the HTTP converter at http://localhost:\{server.port()}/convert. Hit Ctrl+C to quit.",
  )
  for ;; {
    // One failed connection must not take the app down; report and
    // keep serving, like the results viewer.
    let _ = try {
      server.serve_pending(request => @web.handle_convert_request(request))
      true
    } catch {
      error => {
        @recordio.print_error("moon-boofuzz: \{Repr(error)}")
        false
      }
    }
    @transport.sleep_ms(20)
  }
}
