// SPDX-License-Identifier: GPL-2.0-only
// Bundle for live runs: the loopback server plus the session view, with
// the between-cases gate that serves requests and blocks while paused
// (the is_paused / Runner loop interlock of upstream sessions).

///|
pub struct WebUi {
  server : HttpServer
  session : LiveSession
}

///|
pub fn WebUi::open(port~ : Int, limit~ : Int) -> WebUi raise {
  let server = HttpServer::bind(port~)
  { server, session: LiveSession::new(limit~), }
}

///|
pub fn WebUi::port(self : WebUi) -> Int {
  self.server.port()
}

///|
pub fn WebUi::session(self : WebUi) -> LiveSession {
  self.session
}

///|
pub fn WebUi::serve(self : WebUi) -> Unit raise {
  self.server.serve_pending(request => handle_request(self.session, request))
}

///|
/// Called before every test case: services pending requests and, while
/// paused, keeps serving and sleeps until resumed.
pub fn WebUi::gate(self : WebUi) -> Unit raise {
  for ;; {
    self.serve()
    if !SessionView::is_paused(self.session) {
      return
    }
    @transport.sleep_ms(50)
  }
}
