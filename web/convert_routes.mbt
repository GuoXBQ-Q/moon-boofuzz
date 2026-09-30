// SPDX-License-Identifier: GPL-2.0-only
// Converter web app: paste a raw HTTP request, pick the segments to
// fuzz (with optional explicit candidates), and get a moon-boofuzz
// protocol-definition JSON document, validated and previewed. Fully
// stateless: the raw message and options ride along in hidden fields.

///|
/// Dispatch one request against the converter app.
pub fn handle_convert_request(request : HttpRequest) -> HttpResponse {
  let path = request.path
  if path == "/convert" || path == "/convert/" {
    if request.verb == "GET" {
      return render_convert_input("")
    }
    return method_not_allowed("GET")
  }
  if path == "/convert/segments" {
    if request.verb == "POST" {
      return convert_segments(parse_form(request.body))
    }
    return method_not_allowed("POST")
  }
  if path == "/convert/generate" {
    if request.verb == "POST" {
      return convert_generate(parse_form(request.body))
    }
    return method_not_allowed("POST")
  }
  HttpResponse::not_found()
}

///|
struct ConvertForm {
  rawtext : String
  request_name : String
  host : String
  port : String
  policy : String
  fixed_length : String
  case_limit : String
} derive(Debug)

///|
pub extend ConvertForm with @moonbitlang/core/debug.Debug::{to_repr}

///|
fn form_of(fields : Map[String, String]) -> ConvertForm {
  {
    rawtext: fields.get("rawtext").unwrap_or(""),
    request_name: fields.get("request_name").unwrap_or("request"),
    host: fields.get("host").unwrap_or("127.0.0.1"),
    port: fields.get("port").unwrap_or("9000"),
    policy: fields.get("policy").unwrap_or("until"),
    fixed_length: fields.get("fixed_length").unwrap_or("2"),
    case_limit: fields.get("case_limit").unwrap_or("0"),
  }
}

///|
fn convert_segments(fields : Map[String, String]) -> HttpResponse {
  let form = form_of(fields)
  let message = if form.rawtext.is_empty() {
    return convert_error("the message text is empty")
  } else {
    @httpgen.HttpMessage::parse(form.rawtext) catch {
      @httpgen.Invalid(text) => return convert_error(text)
    }
  }
  let rows = StringBuilder()
  for segment in message.segments() {
    let open = "<tr><td><input type=\"checkbox\" aria-label=\"Fuzz " +
      html_escape(segment.label) +
      "\" name=\"f_" +
      segment.id +
      "\"></td><td class=\"segment-name\">"
    rows.write_string(open)
    rows.write_string(html_escape(segment.label))
    rows.write_string("</td><td><code class=\"segment-value\">")
    rows.write_string(html_escape(segment.value))
    rows.write_string("</code></td><td>")
    rows.write_string(primitive_select(segment.id, segment.kind))
    rows.write_string(primitive_params(segment.id))
    let close = "</td><td><textarea name=\"c_" +
      segment.id +
      "\" aria-label=\"Custom candidates for " +
      html_escape(segment.label) +
      "\" rows=\"2\" placeholder=\"one candidate per line (optional)\"></textarea></td></tr>"
    rows.write_string(close)
  }
  let hint = match message.header("content-length") {
    Some(_) =>
      "<div class=\"notice warning\">Note: the message declares a Content-Length header. When a body " +
      "segment is fuzzed, its candidates may change the body length while the " +
      "header stays frozen at the original value unless that header is also " +
      "fuzzed.</div>"
    None => ""
  }
  let body = "<p>Parsed " +
    message.headers.length().to_string() +
    " headers" +
    (if message.has_body {
      " and a body of " + message.body.length().to_string() + " characters."
    } else {
      "."
    }) +
    "</p>" +
    hint +
    "<form method=\"post\" action=\"/convert/generate\">" +
    hidden_message(form) +
    "<section class=\"panel\"><div class=\"panel-head\"><div><h2>Mutation surface</h2><p class=\"hint\"><span id=\"selected-count\">0 selected</span> · select only the fields you want to fuzz</p></div><div class=\"actions\"><button type=\"button\" class=\"button ghost small\" data-select-fields=\"all\">Select all</button><button type=\"button\" class=\"button ghost small\" data-select-fields=\"none\">Clear</button></div></div><div class=\"table-wrap\"><table class=\"summary segments-table\"><thead><tr><th>FUZZ</th><th>SEGMENT</th><th>ORIGINAL VALUE</th><th>MUTATION STRATEGY</th><th>CUSTOM CANDIDATES</th></tr></thead><tbody>" +
    rows.to_string() +
    "</tbody></table></div></section>" +
    "<p class=\"actions\"><input class=\"input primary\" type=\"submit\" value=\"Generate definition →\"> " +
    "<a href=\"/convert\">Start over</a></p>" +
    "</form>"
  convert_page("Pick fuzzed segments", body)
}

///|
fn convert_generate(fields : Map[String, String]) -> HttpResponse {
  let form = form_of(fields)
  let message = if form.rawtext.is_empty() {
    return convert_error("the message text is empty")
  } else {
    @httpgen.HttpMessage::parse(form.rawtext) catch {
      @httpgen.Invalid(text) => return convert_error(text)
    }
  }
  let port = match option_int(form.port) {
    Some(value) => value
    None => return convert_error("port must be a decimal number")
  }
  guard port >= 1 && port <= 65535 else {
    return convert_error("port must be between 1 and 65535")
  }
  let case_limit = match option_int(form.case_limit) {
    Some(value) => value
    None => return convert_error("case limit must be a decimal number")
  }
  let fixed_length = match option_int(form.fixed_length) {
    Some(value) => value
    None => return convert_error("fixed length must be a decimal number")
  }
  let options : @httpgen.ConvertOptions = {
    request_name: form.request_name,
    host: form.host,
    port,
    policy_kind: form.policy,
    fixed_length,
    case_limit,
  }
  let selections : Array[@httpgen.FieldSelection] = []
  for segment in message.segments() {
    if fields.contains("f_" + segment.id) {
      match selection_from_fields(fields, segment.id) {
        Ok(selection) => selections.push(selection)
        Err(text) => return convert_error(text)
      }
    }
  }
  let result = @httpgen.to_definition(message, selections, options) catch {
    @httpgen.Invalid(text) => return convert_error(text)
  }

  let definition_json = try! @json.parse(result.definition_text)
  let pretty_definition = definition_json.stringify(indent=2)
  let previews = StringBuilder()
  for i, payload in result.previews {
    previews.write_string(
      "<details class=\"payload-preview\"" +
      (if i == 0 { " open" } else { "" }) +
      "><summary>Preview case " +
      i.to_string() +
      " · " +
      payload.length().to_string() +
      " bytes</summary><pre>",
    )
    previews.write_string(html_escape(ascii_dump(payload)))
    previews.write_string(
      "</pre><div class=\"hex-preview\">" +
      @records.hex_encode(payload) +
      "</div></details>",
    )
  }
  let body = "<div class=\"result-grid\"><section class=\"panel\"><div class=\"panel-head\"><h2>Definition JSON</h2><span class=\"status\">Validated</span></div><textarea id=\"definition-json\" class=\"definition-json\" aria-label=\"Generated definition JSON\" rows=\"22\" readonly spellcheck=\"false\">" +
    html_escape(pretty_definition) +
    "</textarea><input type=\"hidden\" id=\"download-name\" value=\"" +
    html_escape(form.request_name) +
    "\"><div class=\"json-actions\"><button class=\"button primary\" type=\"button\" onclick=\"downloadDefinition()\">Download JSON ↓</button><button class=\"button\" type=\"button\" onclick=\"copyDefinition()\">Copy JSON</button><span id=\"copy-status\" class=\"copy-status\" role=\"status\"></span></div></section><aside class=\"panel\"><div class=\"panel-head\"><h2>Ready to run</h2></div><div class=\"panel-body\"><div class=\"muted\">Fuzzing cases</div><div class=\"result-stat\">" +
    result.case_count.to_string() +
    "</div><p class=\"hint\">fuzzing cases in the generated definition</p><hr style=\"border:0;border-top:1px solid var(--line);margin:24px 0\"><div class=\"metric-label\">Target endpoint</div><div class=\"result-target\">" +
    html_escape(form.host) +
    ":" +
    html_escape(form.port) +
    "</div><ul class=\"result-notes\"><li>Selected segments receive mutations.</li><li>Unselected segments keep their original bytes.</li><li>The endpoint can be changed in the JSON.</li></ul><a class=\"button ghost\" href=\"/convert\">Convert another request</a></div></aside></div><div class=\"section-heading\"><div><h2>Payload previews</h2><p class=\"hint\">Inspect the exact bytes before running the definition.</p></div></div>" +
    previews.to_string()
  convert_page("Generated definition", body)
}

///|
fn render_convert_input(rawtext : String) -> HttpResponse {
  let sample = "GET /api/items HTTP/1.1\r\nHost: 127.0.0.1:9000\r\nUser-Agent: moon-boofuzz\r\nAccept: application/json\r\n\r\n"
  let body = "<form class=\"builder-grid\" method=\"post\" action=\"/convert/segments\"><section class=\"panel request-panel\"><div class=\"panel-head\"><div><h2>Raw HTTP request</h2><p class=\"hint\">The starting point for your fuzz definition</p></div><button class=\"button ghost small\" id=\"use-sample\" type=\"button\">Use sample</button></div><div class=\"panel-body\"><label class=\"field-label\" for=\"raw-request\" hidden>Raw HTTP request</label><textarea class=\"code-input\" id=\"raw-request\" name=\"rawtext\" rows=\"16\" spellcheck=\"false\" required placeholder=\"" +
    html_escape(sample) +
    "\">" +
    html_escape(rawtext) +
    "</textarea></div><div class=\"panel-foot\">HTTP request line / headers / optional body</div></section><aside class=\"panel settings-panel\"><div class=\"panel-head\"><h2>Execution settings</h2></div><div class=\"panel-body\"><div class=\"field\"><label for=\"request-name\">Request name</label><input id=\"request-name\" name=\"request_name\" value=\"request\" required></div><div class=\"field-row\"><div class=\"field\"><label for=\"target-host\">Target host</label><input id=\"target-host\" name=\"host\" value=\"127.0.0.1\" required></div><div class=\"field\"><label for=\"target-port\">Port</label><input id=\"target-port\" name=\"port\" type=\"number\" min=\"1\" max=\"65535\" value=\"9000\" required></div></div><div class=\"field\"><label for=\"read-policy\">Read policy</label><select id=\"read-policy\" name=\"policy\" onchange=\"syncReadPolicy()\"><option value=\"until\">Until HTTP header boundary</option><option value=\"none\">No response</option><option value=\"fixed\">Fixed length</option></select><p class=\"hint\">Choose how the runner reads each response.</p></div><div class=\"field\" id=\"fixed-length-field\"><label for=\"fixed-length\">Response length (bytes)</label><input id=\"fixed-length\" name=\"fixed_length\" type=\"number\" min=\"0\" value=\"2\"></div><div class=\"field\"><label for=\"case-limit\">Case limit</label><input id=\"case-limit\" name=\"case_limit\" type=\"number\" min=\"0\" value=\"0\" required><p class=\"hint\">0 runs every generated case (no cap).</p></div></div></aside><div class=\"wizard-actions\"><p class=\"hint\">Next: choose the segments and mutation strategies.</p><button class=\"button primary\" type=\"submit\">Parse request →</button></div></form>"
  convert_page("HTTP request builder", body)
}

///|
fn hidden_message(form : ConvertForm) -> String {
  let hidden_input = fn(name : String, value : String) -> String {
    "<input type=\"hidden\" name=\"" +
    html_escape(name) +
    "\" value=\"" +
    html_escape(value) +
    "\">"
  }
  "<textarea name=\"rawtext\" style=\"display:none\">" +
  html_escape(form.rawtext) +
  "</textarea>" +
  hidden_input("request_name", form.request_name) +
  hidden_input("host", form.host) +
  hidden_input("port", form.port) +
  hidden_input("policy", form.policy) +
  hidden_input("fixed_length", form.fixed_length) +
  hidden_input("case_limit", form.case_limit)
}

///|
fn convert_page(title : String, body : String) -> HttpResponse {
  let stage = match title {
    "Pick fuzzed segments" => 2
    "Generated definition" => 3
    _ => 1
  }
  let description = match stage {
    2 =>
      "Choose the fields to mutate. Everything else keeps its original bytes."
    3 => "Your definition is validated and ready to copy, download or inspect."
    _ => "Turn a raw HTTP request into a reproducible fuzz definition."
  }
  HttpResponse::html(
    page_start(title, "HTTP request builder", "/convert") +
    page_heading(
      "Workspace / Request builder", title, description, "<span class=\"status finished\">HTTP / TCP</span>",
    ) +
    converter_steps(stage) +
    body +
    page_end(PAGE_SCRIPT + CONVERT_SCRIPT),
  )
}

///|
fn convert_error(message : String) -> HttpResponse {
  let body = "<div class=\"notice error\" role=\"alert\">The request could not be processed: " +
    html_escape(message) +
    "</div><p><a class=\"button\" href=\"/convert\">Back to the converter</a></p>"
  let response = convert_page("Conversion failed", body)
  {
    status: 400,
    content_type: response.content_type,
    body: response.body,
    headers: response.headers,
  }
}

///|
fn method_not_allowed(allow : String) -> HttpResponse {
  {
    status: 405,
    content_type: "text/plain; charset=utf-8",
    body: @utf8.encode("405 method not allowed"),
    headers: ["Allow: " + allow],
  }
}

///|
fn option_int(text : String) -> Int? {
  if text.is_empty() {
    return None
  }
  let mut value = 0
  for ch in text {
    guard ch >= '0' && ch <= '9' else { return None }
    value = value * 10 + (ch.to_int() - '0'.to_int())
    guard value <= 2147483647 else { return None }
  }
  Some(value)
}

///|
fn candidates_from(text : String) -> Array[String] {
  let result : Array[String] = []
  for raw_line in text.split("\n") {
    let line = strip_line_ending(raw_line.to_owned())
    if !line.is_empty() {
      result.push(line)
    }
  }
  result
}

///|
/// The mutation-primitive dropdown for one segment. The method segment
/// defaults to candidates (the built-in HTTP method table); every other
/// segment defaults to the string library.
fn primitive_select(id : String, kind : String) -> String {
  let option = fn(value : String, label : String, selected : Bool) -> String {
    "<option value=\"" +
    value +
    "\"" +
    (if selected { " selected" } else { "" }) +
    ">" +
    label +
    "</option>"
  }
  let is_method = kind == "method"
  "<select name=\"p_" +
  html_escape(id) +
  "\" aria-label=\"Mutation strategy for " +
  html_escape(id) +
  "\" class=\"input\" onchange=\"syncPrimitive('" +
  html_escape(id) +
  "')\">" +
  option("text", "string library", !is_method) +
  option("integer", "integer", false) +
  option("bytes", "bytes", false) +
  option("random", "random", false) +
  option(
    "candidates",
    if is_method {
      "candidates (built-in HTTP methods)"
    } else {
      "candidates"
    },
    is_method,
  ) +
  "</select>"
}

///|
/// Per-primitive parameter inputs; the inline script shows only the ones
/// matching the selected primitive (all show when scripts are off).
fn primitive_params(id : String) -> String {
  let number_input = fn(name : String, value : Int) -> String {
    "<input class=\"input\" type=\"text\" name=\"" +
    html_escape(name) +
    "\" value=\"" +
    value.to_string() +
    "\" style=\"width:5em\">"
  }
  "<span class=\"primitive-params\" id=\"params_integer_" +
  html_escape(id) +
  "\"> width " +
  number_input("p_" + id + "_width", 32) +
  " <select name=\"p_" +
  html_escape(id) +
  "_endian\" class=\"input\"><option value=\"little\">little</option><option value=\"big\">big</option></select></span>" +
  "<span class=\"primitive-params\" id=\"params_bytes_" +
  html_escape(id) +
  "\"> max_len " +
  number_input("p_" + id + "_maxlen", 16) +
  "</span>" +
  "<span class=\"primitive-params\" id=\"params_random_" +
  html_escape(id) +
  "\"> max_len " +
  number_input("p_" + id + "_rlength", 16) +
  " count " +
  number_input("p_" + id + "_count", 25) +
  "</span>"
}

///|
/// Build one segment selection from form fields, validating the chosen
/// primitive and its parameters. Returns Err with a user-facing message.
fn selection_from_fields(
  fields : Map[String, String],
  id : String,
) -> Result[@httpgen.FieldSelection, String] {
  let candidates = candidates_from(fields.get("c_" + id).unwrap_or(""))
  let primitive = match fields.get("p_" + id) {
    Some("text") => @httpgen.Text
    Some("integer") => @httpgen.Integer
    Some("bytes") => @httpgen.Bytes
    Some("random") => @httpgen.RandomData
    Some("candidates") => @httpgen.Candidates
    // Forms without a primitive choice keep the historical behavior:
    // explicit candidates when given, string library otherwise.
    _ => if candidates.is_empty() { @httpgen.Text } else { @httpgen.Candidates }
  }
  // Only the parameters of the chosen primitive are read, so stray
  // values in hidden spans never reject an otherwise valid form.
  let mut width = 32
  let mut endian = "little"
  match primitive {
    @httpgen.Integer => {
      width = match fields.get("p_" + id + "_width") {
        Some(text) =>
          match option_int(text) {
            Some(value) =>
              if value == 8 || value == 16 || value == 32 || value == 64 {
                value
              } else {
                return Err("integer width must be 8, 16, 32 or 64")
              }
            None => return Err("integer width must be a decimal number")
          }
        None => 32
      }
      endian = match fields.get("p_" + id + "_endian") {
        Some(value) =>
          if value == "little" || value == "big" {
            value
          } else {
            return Err("integer endian must be little or big")
          }
        None => "little"
      }
    }
    _ => ()
  }
  let mut max_len = 16
  match primitive {
    @httpgen.Bytes =>
      max_len = match fields.get("p_" + id + "_maxlen") {
        Some(text) =>
          match option_int(text) {
            Some(value) =>
              if value >= 1 && value <= 1048576 {
                value
              } else {
                return Err("max_len must be between 1 and 1048576")
              }
            None => return Err("max_len must be a decimal number")
          }
        None => 16
      }
    @httpgen.RandomData =>
      max_len = match fields.get("p_" + id + "_rlength") {
        Some(text) =>
          match option_int(text) {
            Some(value) =>
              if value >= 1 && value <= 1048576 {
                value
              } else {
                return Err("random max_len must be between 1 and 1048576")
              }
            None => return Err("random max_len must be a decimal number")
          }
        None => 16
      }
    _ => ()
  }
  let mut max_mutations = 25
  if primitive is @httpgen.RandomData {
    max_mutations = match fields.get("p_" + id + "_count") {
      Some(text) =>
        match option_int(text) {
          Some(value) =>
            if value >= 1 && value <= 10000 {
              value
            } else {
              return Err("random count must be between 1 and 10000")
            }
          None => return Err("random count must be a decimal number")
        }
      None => 25
    }
  }
  Ok({ id, primitive, width, endian, max_len, max_mutations, candidates, })
}

///|
fn ascii_dump(bytes : Bytes) -> String {
  let text = StringBuilder()
  for byte in bytes {
    let code = byte.to_int()
    if code >= 32 && code <= 126 {
      text.write_string(ASCII_PRINTABLE[code - 32:code - 31].to_owned())
    } else if code == 13 {
      text.write_string("\\r")
    } else if code == 10 {
      text.write_string("\\n")
    } else {
      text.write_string(".")
    }
  }
  text.to_string()
}

///|
/// Printable ASCII from space (32) to tilde (126).
const ASCII_PRINTABLE : String = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
