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
pub fn[T : SessionView] handle_request(
  view : T,
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
fn[T : SessionView] num_mutations_json(view : T) -> Json {
  match SessionView::num_mutations(view) {
    Some(total) => Json::number(total.to_double(), repr="\{total}")
    None => Json::null()
  }
}

///|
/// /api/current-run — the index_update payload
/// (web/app.py:68-87). Element-level progress is served as null: the
/// port keeps element state inside the model, not the session.
pub fn[T : SessionView] api_current_run(view : T) -> HttpResponse raise {
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
      "state": SessionView::state(view),
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
pub fn[T : SessionView] api_test_case(
  view : T,
  index : Int,
) -> HttpResponse raise {
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
/// equivalent; crash details stay out of the port). Unknown or
/// not-persisted cases render a notice page instead of a 404 so crash
/// links stay clickable during a live run, like upstream's empty page.
pub fn[T : SessionView] render_test_case(
  view : T,
  index : Int,
) -> HttpResponse raise {
  let builder = StringBuilder()
  builder.write_string(
    page_start("Test case #" + index.to_string(), "Case inspector", "/"),
  )
  builder.write_string(
    "<a class=\"back-link\" href=\"/\">← Back to run overview</a>",
  )
  let case_data = SessionView::test_case_data(view, index) catch {
    @db.NoSuchCase(_) => {
      builder.write_string(
        page_heading(
          "Results / Case inspector",
          "Test case #" + index.to_string(),
          "The recorded traffic for this case is not available.",
          "<span class=\"status finished\">No data</span>",
        ),
      )
      builder.write_string(
        "<section class=\"panel empty-state\"><span class=\"empty-symbol\" aria-hidden=\"true\">—</span><strong>No recorded data for this test case</strong><p>During a live run this case has not been executed yet — details appear as soon as it completes. In an offline view the record is not part of the results file.</p></section>",
      )
      builder.write_string(page_end(PAGE_SCRIPT))
      return HttpResponse::html(builder.to_string())
    }
    error => raise error
  }
  builder.write_string(
    page_heading(
      "Results / Case inspector",
      "Test case #" + index.to_string(),
      case_data.name,
      "<span class=\"status finished\">Recorded</span>",
    ),
  )
  builder.write_string(
    "<section class=\"panel\"><div class=\"panel-head\"><div><h2>Traffic &amp; checks</h2><p class=\"hint\">" +
    html_escape(
      if case_data.timestamp.is_empty() {
        "Exact bytes from the saved run"
      } else {
        case_data.timestamp
      },
    ) +
    "</p></div><button type=\"button\" class=\"button small\" id=\"copy-log\">Copy visible log</button></div><div class=\"log-toolbar\"><div class=\"log-filters\" role=\"group\" aria-label=\"Log filters\"><button type=\"button\" data-log-filter=\"all\" aria-pressed=\"true\">All events</button><button type=\"button\" data-log-filter=\"traffic\" aria-pressed=\"false\">Traffic</button><button type=\"button\" data-log-filter=\"checks\" aria-pressed=\"false\">Checks</button><button type=\"button\" data-log-filter=\"errors\" aria-pressed=\"false\">Failures</button></div><span id=\"log-copy-status\" class=\"copy-status\" role=\"status\"></span></div><div class=\"log-lines\" id=\"case-log\">",
  )
  for line in case_log_lines(case_data) {
    let label = match line.css_class {
      "log-send" => "SEND"
      "log-receive" => "RECV"
      "log-fail" => "FAIL"
      "log-error" => "ERROR"
      "log-pass" => "PASS"
      "log-check" => "CHECK"
      "log-step" => "STEP"
      "log-case" => "CASE"
      _ => "INFO"
    }
    builder.write_string(
      "<div class=\"log-line " +
      line.css_class +
      "\"><span class=\"log-marker\">" +
      label +
      "</span><pre class=\"log-text\">" +
      html_escape(line.log_line) +
      "</pre></div>",
    )
  }
  builder.write_string(
    "</div><div class=\"empty-state\" id=\"log-empty\" hidden><strong>No events in this filter</strong><p>Choose another event type to inspect this case.</p></div></section>",
  )
  builder.write_string(page_end(PAGE_SCRIPT))
  HttpResponse::html(builder.to_string())
}

///|
/// / — the index page: progress bars, pause form and crash list with
/// links into the per-case views (the index.html template subset).
pub fn[T : SessionView] render_index(view : T) -> HttpResponse raise {
  let count = SessionView::current_index(view)
  let limit = SessionView::num_mutations(view)
  let failures = SessionView::crashes(view)
  let offline = SessionView::state(view) == "finished"
  let paused = SessionView::is_paused(view)
  let state = if offline {
    "finished"
  } else if paused {
    "paused"
  } else {
    "running"
  }
  let status = "<span id=\"is_paused_indicator\" class=\"status " +
    state +
    "\">" +
    (if offline { "Saved run" } else if paused { "Paused" } else { "Running" }) +
    "</span>"
  let action = if offline {
    status
  } else {
    status +
    "<form method=\"get\" action=\"/togglepause\"><button id=\"pause-button\" class=\"button\" type=\"submit\">" +
    (if paused { "Resume run" } else { "Pause run" }) +
    "</button></form>"
  }
  let builder = StringBuilder()
  builder.write_string(page_start("Run overview", "Results viewer", "/"))
  builder.write_string("<div id=\"run-overview\" data-mode=\"" + state + "\">")
  builder.write_string(
    page_heading(
      "Workspace / Results",
      "Run overview",
      if offline {
        "Inspect saved traffic, locate failures and review individual test cases."
      } else {
        "Follow the current run and inspect the cases that need attention."
      },
      action,
    ),
  )
  builder.write_string(
    "<section class=\"panel metrics" +
    (if offline { " offline" } else { "" }) +
    "\" aria-label=\"Run metrics\"><div class=\"metric\"><div class=\"metric-label\">" +
    (if offline { "Recorded cases" } else { "Executed cases" }) +
    "</div><div class=\"metric-value\" id=\"current_index\">" +
    count.to_string() +
    "</div><div class=\"metric-caption\">" +
    (if offline {
      "Available in the saved run"
    } else {
      "Completed in this session"
    }) +
    "</div></div><div class=\"metric\"><div class=\"metric-label\">Failure cases</div><div class=\"metric-value error\" id=\"failure-count\">" +
    failures.length().to_string() +
    "</div><div class=\"metric-caption\">Recorded failures, including response issues</div></div>",
  )
  if !offline {
    builder.write_string(
      "<div class=\"metric\"><div class=\"metric-label\">Elapsed</div><div class=\"metric-value small-value\" id=\"run_time\">" +
      SessionView::runtime_seconds(view).to_int().to_string() +
      "s</div><div class=\"metric-caption\">Includes paused time</div></div><div class=\"metric\"><div class=\"metric-label\">Execution rate</div><div class=\"metric-value small-value\" id=\"exec_speed\">" +
      speed_text(SessionView::exec_speed(view)) +
      "</div><div class=\"metric-caption\">Cases per second</div></div>",
    )
  }
  builder.write_string("</section><div class=\"overview-grid\">")
  if offline {
    builder.write_string(
      "<section class=\"panel\"><div class=\"panel-head\"><h2>Saved results</h2><span class=\"status finished\">Read-only</span></div><div class=\"panel-body\"><p class=\"muted\" style=\"margin:0\">This is a saved run. Open a case to inspect the exact recorded request, response and check results.</p><p class=\"connection\">Run controls and live timing are available while a runner is active.</p></div></section>",
    )
  } else {
    let progress = match limit {
      Some(total) if total > 0 =>
        min_of(count.to_double() / total.to_double(), 1.0)
      _ => 0.0
    }
    let budget = match limit {
      Some(total) => total.to_string()
      None => "Unbounded"
    }
    let percent = match limit {
      Some(total) if total > 0 => progress_percent(progress)
      _ => "No fixed limit"
    }
    builder.write_string(
      "<section class=\"panel\"><div class=\"panel-head\"><h2>Run progress</h2><span id=\"progress_percentage_total\" class=\"mono muted\">" +
      percent +
      "</span></div><div class=\"panel-body\"><div class=\"progress-labels\"><span>Configured case limit</span><strong id=\"num_mutations\">" +
      budget +
      "</strong></div><progress class=\"run-progress\" id=\"progress_bar_total\" max=\"100\"" +
      (match limit {
        Some(total) if total > 0 =>
          " value=\"" + (progress * 100.0).to_string() + "\""
        _ => ""
      }) +
      " aria-label=\"Run progress\"></progress><div class=\"run-context\"><span>Last request</span><code id=\"current_test_case_name\">" +
      html_escape(
        if SessionView::current_case_name(view).is_empty() {
          "Waiting for the first case"
        } else {
          SessionView::current_case_name(view)
        },
      ) +
      "</code></div><span id=\"current_element\" hidden>" +
      html_escape(SessionView::current_element(view)) +
      "</span><div class=\"connection\" id=\"connection-status\">Connected · updates every 2 seconds</div></div></section>",
    )
  }
  builder.write_string(
    "<section class=\"panel\"><div class=\"panel-head\"><h2>Case inspector</h2></div><div class=\"panel-body\"><form class=\"lookup\" id=\"case-lookup\" action=\"/test-case/0\"><div class=\"field\"><label for=\"case-index\">Case index</label><input id=\"case-index\" type=\"number\" min=\"0\" max=\"999999999\" placeholder=\"e.g. 12\" required></div><button class=\"button\" type=\"submit\">Open case →</button></form><p class=\"hint\">Use the index from a failure record or saved log.</p></div></section></div>",
  )
  builder.write_string(
    "<section id=\"failures\"><div class=\"section-heading\"><div><h2>Failure records<span class=\"count-label\" id=\"failure-count-heading\">" +
    failures.length().to_string() +
    "</span></h2><p class=\"hint\">Inspect the request and response behind a recorded failure.</p></div><label><span class=\"field-label\" hidden>Filter failure records</span><input class=\"search-input\" id=\"failure-filter\" type=\"search\" aria-label=\"Filter failure records\" placeholder=\"Filter by case or reason…\"></label></div><div class=\"panel\"><div class=\"table-wrap\"><table id=\"crashes\" class=\"data-table\"><thead><tr><th style=\"width:120px\">CASE INDEX</th><th>REASON</th><th style=\"width:120px\"></th></tr></thead><tbody id=\"failure-rows\">",
  )
  let indices = failures.keys().to_array()
  indices.sort()
  for index in indices {
    let reasons = failures.get(index).unwrap_or([])
    builder.write_string(
      "<tr><td><a href=\"/test-case/" +
      index.to_string() +
      "\" class=\"case-link\">" +
      index.to_string() +
      "</a></td><td class=\"failure-reason\">" +
      html_escape(reasons.join(" | ")) +
      "</td><td><a class=\"row-action\" href=\"/test-case/" +
      index.to_string() +
      "\">View log →</a></td></tr>",
    )
  }
  builder.write_string(
    "</tbody></table></div><div class=\"empty-state\" id=\"failure-empty\"" +
    (if failures.is_empty() { "" } else { " hidden" }) +
    "><span class=\"empty-symbol\" aria-hidden=\"true\">✓</span><strong id=\"failure-empty-title\">No failures recorded</strong><p id=\"failure-empty-description\">Failure records will appear here with a link to their traffic log.</p></div></div></section></div>",
  )
  builder.write_string(page_end(PAGE_SCRIPT))
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
