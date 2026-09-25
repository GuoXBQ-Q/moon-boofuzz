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
fn form_of(fields : Map[String, String]) -> ConvertForm {
  {
    rawtext: fields.get("rawtext").unwrap_or(""),
    request_name: fields.get("request_name").unwrap_or("request"),
    host: fields.get("host").unwrap_or("127.0.0.1"),
    port: fields.get("port").unwrap_or("9000"),
    policy: fields.get("policy").unwrap_or("until"),
    fixed_length: fields.get("fixed_length").unwrap_or("2"),
    case_limit: fields.get("case_limit").unwrap_or("100"),
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
    let open = "<tr><td><input type=\"checkbox\" name=\"f_" +
      segment.id +
      "\"></td><td>"
    rows.write_string(open)
    rows.write_string(html_escape(segment.label))
    rows.write_string("</td><td><code>")
    rows.write_string(html_escape(segment.value))
    rows.write_string("</code></td><td>")
    rows.write_string(primitive_select(segment.id, segment.kind))
    rows.write_string(primitive_params(segment.id))
    let close = "</td><td><textarea name=\"c_" +
      segment.id +
      "\" rows=\"2\" placeholder=\"one candidate per line (optional)\"></textarea></td></tr>"
    rows.write_string(close)
  }
  let hint = match message.header("content-length") {
    Some(_) =>
      "<p>Note: the message declares a Content-Length header. When a body " +
      "segment is fuzzed, its candidates may change the body length while the " +
      "header stays frozen at the original value unless that header is also " +
      "fuzzed.</p>"
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
    "<table class=\"summary\"><tr><th>Fuzz</th><th>Segment</th><th>Original value</th><th>Mutation primitive</th><th>Custom candidates</th></tr>" +
    rows.to_string() +
    "</table>" +
    "<p><input class=\"input\" type=\"submit\" value=\"Generate definition\"> " +
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
  let previews = StringBuilder()
  for i, payload in result.previews {
    let head = "<h2>Preview case " +
      i.to_string() +
      "</h2><pre class=\"fixed\">"
    previews.write_string(head)
    previews.write_string(html_escape(ascii_dump(payload)))
    previews.write_string("</pre><p>hex: <code>")
    previews.write_string(@records.hex_encode(payload))
    previews.write_string("</code></p>")
  }
  let body = "<p>Definition validated: <b>" +
    result.case_count.to_string() +
    " fuzzing cases</b> will be generated for target " +
    html_escape(form.host) +
    ":" +
    html_escape(form.port) +
    ". Adjust the endpoint in the JSON if needed.</p>" +
    previews.to_string() +
    "<h2>Definition JSON</h2>" +
    "<textarea id=\"definition-json\" rows=\"16\" class=\"fixed\" readonly style=\"width:100%\">" +
    html_escape(result.definition_text) +
    "</textarea>" +
    "<input type=\"hidden\" id=\"download-name\" value=\"" +
    html_escape(form.request_name) +
    "\">" +
    "<p><button class=\"input\" onclick=\"copyDefinition()\">Copy JSON</button> " +
    "<button class=\"input\" onclick=\"downloadDefinition()\">Download JSON</button> " +
    "<a href=\"/convert\">Convert another message</a></p>"
  convert_page("Generated definition", body)
}

///|
fn render_convert_input(rawtext : String) -> HttpResponse {
  let sample = "GET /index.html HTTP/1.1\r\nHost: 127.0.0.1:9000\r\nUser-Agent: moon-boofuzz\r\n\r\n"
  let body = "<p>Paste a raw HTTP request message. On the next page you choose the " +
    "segments to fuzz and optionally provide explicit candidate values; the " +
    "converted definition targets the message over TCP.</p>" +
    "<form method=\"post\" action=\"/convert/segments\">" +
    "<p><textarea name=\"rawtext\" rows=\"14\" style=\"width:100%\" placeholder=\"" +
    html_escape(sample) +
    "\">" +
    html_escape(rawtext) +
    "</textarea></p>" +
    "<table class=\"summary\">" +
    "<tr><td>Request name</td><td><input class=\"input\" name=\"request_name\" value=\"request\"></td></tr>" +
    "<tr><td>Target host</td><td><input class=\"input\" name=\"host\" value=\"127.0.0.1\"></td></tr>" +
    "<tr><td>Target port</td><td><input class=\"input\" name=\"port\" value=\"9000\"></td></tr>" +
    "<tr><td>Read policy</td><td><select name=\"policy\" class=\"input\">" +
    "<option value=\"until\">until CRLFCRLF (HTTP responses)</option>" +
    "<option value=\"none\">none</option>" +
    "<option value=\"fixed\">fixed length</option>" +
    "</select></td></tr>" +
    "<tr><td>Fixed length</td><td><input class=\"input\" name=\"fixed_length\" value=\"2\"></td></tr>" +
    "<tr><td>Case limit</td><td><input class=\"input\" name=\"case_limit\" value=\"100\"></td></tr>" +
    "</table>" +
    "<p><input class=\"input\" type=\"submit\" value=\"Parse message\"></p>" +
    "</form>"
  convert_page("HTTP to fuzz definition", body)
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
  HttpResponse::html(
    "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>" +
    html_escape(title) +
    " - moon-boofuzz converter</title><style>" +
    PAGE_CSS +
    "textarea{background:#222;color:#ddd;border:1px solid #555;font-family:monospace}</style></head>" +
    "<body><div class=\"main-wrapper\"><h1>moon-boofuzz HTTP converter</h1>" +
    body +
    "</div>" +
    CONVERT_SCRIPT +
    "</body></html>",
  )
}

///|
fn convert_error(message : String) -> HttpResponse {
  let body = "<p>The request could not be processed: " +
    html_escape(message) +
    "</p><p><a href=\"/convert\">Back to the converter</a></p>"
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
  "<span id=\"params_integer_" +
  html_escape(id) +
  "\"> width " +
  number_input("p_" + id + "_width", 32) +
  " <select name=\"p_" +
  html_escape(id) +
  "_endian\" class=\"input\"><option value=\"little\">little</option><option value=\"big\">big</option></select></span>" +
  "<span id=\"params_bytes_" +
  html_escape(id) +
  "\"> max_len " +
  number_input("p_" + id + "_maxlen", 16) +
  "</span>" +
  "<span id=\"params_random_" +
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
