// SPDX-License-Identifier: GPL-2.0-only
// Router, porting boofuzz/web/app.py at 518c139: index (progress +
// crashes), togglepause, test-case detail, and the current-run /
// test-case JSON APIs. Non-GET requests and unknown paths 404.

///|
/// Parse a decimal path segment; None unless it is all digits.
fn parse_index(text : String) -> Int? {
  if text.is_empty() || text.length() > 9 {
    return None
  }
  let mut value = 0
  for ch in text {
    guard ch >= '0' && ch <= '9' else { return None }
    value = value * 10 + (ch.to_int() - '0'.to_int())
  }
  Some(value)
}

///|
fn path_tail(path : String, prefix : String) -> String {
  path[prefix.length():].to_owned()
}

///|
/// Dispatch one request against a session view. Non-GET requests and
/// unknown paths 404.
pub fn handle_request(
  view : &SessionView,
  request : HttpRequest,
) -> HttpResponse raise {
  if request.verb != "GET" {
    return HttpResponse::not_found()
  }
  let path = request.path
  if path == "/" || path == "" {
    return render_index(view)
  }
  if path == "/togglepause" {
    SessionView::toggle_pause(view)
    return HttpResponse::redirect("/")
  }
  if path == "/api/current-run" {
    return api_current_run(view)
  }
  if path == "/api/current-test-case" {
    return api_test_case(view, SessionView::current_index(view))
  }
  if path.has_prefix("/api/test-case/") {
    return match parse_index(path_tail(path, "/api/test-case/")) {
      Some(index) => api_test_case(view, index)
      None => HttpResponse::not_found()
    }
  }
  if path.has_prefix("/test-case/") {
    return match parse_index(path_tail(path, "/test-case/")) {
      Some(index) => render_test_case(view, index)
      None => HttpResponse::not_found()
    }
  }
  HttpResponse::not_found()
}

///|
fn line_to_json(line : LogLine) -> Json {
  let entry : Json = { "css_class": line.css_class, "log_line": line.log_line }
  entry
}

///|
fn num_mutations_json(view : &SessionView) -> Json {
  match SessionView::num_mutations(view) {
    Some(total) => Json::number(total.to_double(), repr="\{total}")
    None => Json::null()
  }
}

///|
/// /api/current-run — the index_update payload
/// (web/app.py:68-87). Element-level progress is served as null: the
/// port keeps element state inside the model, not the session.
pub fn api_current_run(view : &SessionView) -> HttpResponse raise {
  let crashes : Array[Json] = []
  for index, reasons in SessionView::crashes(view) {
    crashes.push({
      "key": index,
      "reasons": reasons,
      "status_bytes": Json::null(),
    })
  }
  let payload : Json = {
    "session_info": {
      "is_paused": SessionView::is_paused(view),
      "current_index": SessionView::current_index(view),
      "num_mutations": num_mutations_json(view),
      "current_index_element": Json::null(),
      "num_mutations_element": Json::null(),
      "current_element": Json::null(),
      "current_test_case_name": SessionView::current_case_name(view),
      "crashes": crashes,
      "runtime": SessionView::runtime_seconds(view),
      "exec_speed": SessionView::exec_speed(view),
    },
  }
  HttpResponse::json(payload.stringify())
}

///|
/// /api/test-case/<index> and /api/current-test-case
/// (web/app.py:42-65). log_data is null for unknown indexes.
pub fn api_test_case(view : &SessionView, index : Int) -> HttpResponse raise {
  let payload : Json = try {
    let entries : Array[Json] = case_log_lines(
      SessionView::test_case_data(view, index),
    ).map(line_to_json)
    let ok : Json = { "index": index, "log_data": entries }
    ok
  } catch {
    @db.NoSuchCase(_) => {
      let missing : Json = { "index": index, "log_data": Json::null() }
      missing
    }
    error => raise error
  }
  HttpResponse::json(payload.stringify())
}

///|
/// /test-case/<index> — server-rendered log view (the test-case.html
/// equivalent; crash details stay out of the port).
pub fn render_test_case(view : &SessionView, index : Int) -> HttpResponse raise {
  let case_data = SessionView::test_case_data(view, index) catch {
    @db.NoSuchCase(_) => return HttpResponse::not_found()
    error => raise error
  }
  let builder = StringBuilder()
  builder.write_string(
    "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>",
  )
  builder.write_string(html_escape("Test Case \{index}"))
  builder.write_string("</title><style>")
  builder.write_string(PAGE_CSS)
  builder.write_string("</style></head><body><div class=\"main-wrapper\">")
  builder.write_string("<h1>boofuzz Test Case \{index}</h1>")
  builder.write_string("<p><a href=\"/\">&larr; back to fuzz control</a></p>")
  for line in case_log_lines(case_data) {
    builder.write_string("<div class=\"log-line ")
    builder.write_string(line.css_class)
    builder.write_string("\">")
    builder.write_string(html_escape(line.log_line))
    builder.write_string("</div>")
  }
  builder.write_string("</div></body></html>\n")
  HttpResponse::html(builder.to_string())
}

///|
/// / — the index page: progress bars, pause form and crash list with
/// links into the per-case views (the index.html template subset).
pub fn render_index(view : &SessionView) -> HttpResponse raise {
  let total = SessionView::current_index(view)
  let num_mutations = SessionView::num_mutations(view)
  let progress = match num_mutations {
    Some(limit) if limit > 0 =>
      min_of(total.to_double() / limit.to_double(), 1.0)
    _ => 0.0
  }
  let builder = StringBuilder()
  builder.write_string(
    "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>boofuzz</title>",
  )
  builder.write_string("<style>")
  builder.write_string(PAGE_CSS)
  builder.write_string("</style></head><body><div class=\"main-wrapper\">")
  builder.write_string("<h1>boofuzz Fuzz Control</h1>")
  builder.write_string("<div id=\"is_paused_indicator\" class=\"")
  builder.write_string(
    if SessionView::is_paused(view) {
      "paused"
    } else {
      "running"
    },
  )
  builder.write_string("\">")
  builder.write_string(
    if SessionView::is_paused(view) {
      "paused"
    } else {
      "running"
    },
  )
  builder.write_string("</div>")
  builder.write_string("<table class=\"summary\"><tr>")
  builder.write_string("<td>Total:</td><td id=\"current_index\">")
  builder.write_string("\{total}")
  builder.write_string("</td><td>of</td>")
  builder.write_string("<td id=\"num_mutations\">")
  builder.write_string(
    match num_mutations {
      Some(limit) => "\{limit}"
      None => "many"
    },
  )
  builder.write_string("</td>")
  builder.write_string("<td id=\"progress_bar_total\" class=\"fixed\">")
  builder.write_string(progress_bar(progress))
  builder.write_string("</td>")
  builder.write_string("<td id=\"progress_percentage_total\">")
  builder.write_string(progress_percent(progress))
  builder.write_string("</td></tr>")
  builder.write_string(
    "<tr><td id=\"current_element\" class=\"summary-content-row-header-text\">",
  )
  builder.write_string(html_escape(SessionView::current_element(view)))
  builder.write_string(":</td><td colspan=\"5\" id=\"current_test_case_name\">")
  builder.write_string(html_escape(SessionView::current_case_name(view)))
  builder.write_string("</td></tr>")
  builder.write_string(
    "<tr><td class=\"summary-content-row-header-text\">run time</td>",
  )
  builder.write_string("<td id=\"run_time\">")
  builder.write_string("\{SessionView::runtime_seconds(view).to_int()} sec")
  builder.write_string(
    "<td class=\"summary-content-row-header-text\">exec speed</td>",
  )
  builder.write_string("<td id=\"exec_speed\">")
  builder.write_string(speed_text(SessionView::exec_speed(view)))
  builder.write_string("</td></tr></table>")
  builder.write_string("<form method=\"get\" action=\"/togglepause\">")
  builder.write_string("<input class=\"input\" type=\"submit\" value=\"")
  builder.write_string(
    if SessionView::is_paused(view) {
      "Resume"
    } else {
      "Pause"
    },
  )
  builder.write_string("\"></form>")
  builder.write_string("<h2>Crashes</h2><table id=\"crashes\">")
  builder.write_string("<tr><th>test case</th><th>reasons</th></tr>")
  for index, reasons in SessionView::crashes(view) {
    builder.write_string("<tr><td><a href=\"/test-case/")
    builder.write_string("\{index}")
    builder.write_string("\">")
    builder.write_string("\{index}")
    builder.write_string("</a></td><td>")
    builder.write_string(html_escape(reasons.join(" | ")))
    builder.write_string("</td></tr>")
  }
  builder.write_string("</table>")
  builder.write_string(PAGE_SCRIPT)
  builder.write_string("</div></body></html>\n")
  HttpResponse::html(builder.to_string())
}

///|
fn min_of(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// The 50-character progress bar of the upstream template
/// (index.html: "=" fill plus &nbsp; padding).
fn progress_bar(progress : Double) -> String {
  let filled = (progress * 50.0).to_int()
  let mut bar = "["
  for _ in 0..<filled {
    bar = bar + "="
  }
  for _ in 0..<(50 - filled) {
    bar = bar + "&nbsp;"
  }
  bar + "]"
}

///|
fn progress_percent(progress : Double) -> String {
  // "%.3f%%" of the ratio.
  let thousandths = (progress * 100000.0).to_int()
  let whole = thousandths / 1000
  let fraction = thousandths % 1000
  "\{whole}.\{fraction.to_string().pad_start(3, '0')}%"
}

///|
fn speed_text(speed : Double) -> String {
  let tenths = (speed * 10.0).to_int()
  "\{tenths / 10}.\{tenths % 10}/sec"
}
