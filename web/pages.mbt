// SPDX-License-Identifier: GPL-2.0-only
// Inline page assets: a minimal handwritten subset of upstream's
// web/static CSS and the index.js live-update poll. Kept inline because
// the ported server only renders text, no static files.

///|
const PAGE_CSS : String = "body{font-family:monospace;margin:2em;background:#111;color:#ddd}" +
  ".main-wrapper{max-width:60em;margin:auto}" +
  "h1{color:#fff}" +
  ".summary{border-collapse:collapse;margin:1em 0}" +
  ".summary td{padding:.2em .6em;border:1px solid #333}" +
  ".summary-content-row-header-text{font-weight:bold}" +
  ".fixed{white-space:pre}" +
  "#is_paused_indicator{display:inline-block;padding:.2em .8em;border-radius:4px;font-weight:bold}" +
  "#is_paused_indicator.running{background:#143d14;color:#7f7}" +
  "#is_paused_indicator.paused{background:#5a1414;color:#f88}" +
  ".input{background:#222;color:#ddd;border:1px solid #555;padding:.4em 1em;font-size:1em}" +
  "table#crashes td,table#crashes th{border:1px solid #333;padding:.2em .6em}" +
  "a{color:#7cf}" +
  ".log-line{white-space:pre-wrap;border-bottom:1px dotted #222;padding:.1em 0}" +
  ".log-case{font-weight:bold;color:#fd5}" +
  ".log-step{color:#f8f}" +
  ".log-info{color:#ddd}" +
  ".log-error{color:#f55}" +
  ".log-send,.log-receive{color:#5dd}" +
  ".log-check{color:#ddd}" +
  ".log-fail{color:#f55}" +
  ".log-pass{color:#5f5}"

///|
/// index.js equivalent: refresh the counters from /api/current-run.
const PAGE_SCRIPT : String = "<script>\n" +
  "function refresh() {\n" +
  "  fetch('/api/current-run').then(r => r.json()).then(data => {\n" +
  "    var s = data.session_info;\n" +
  "    document.getElementById('current_index').textContent = s.current_index;\n" +
  "    document.getElementById('num_mutations').textContent = s.num_mutations === null ? 'many' : s.num_mutations;\n" +
  "    var indicator = document.getElementById('is_paused_indicator');\n" +
  "    indicator.textContent = s.is_paused ? 'paused' : 'running';\n" +
  "    indicator.className = s.is_paused ? 'paused' : 'running';\n" +
  "    document.getElementById('run_time').textContent = Math.round(s.runtime) + ' sec';\n" +
  "    document.getElementById('exec_speed').textContent = s.exec_speed.toFixed(1) + '/sec';\n" +
  "  }).catch(() => {});\n" +
  "}\n" +
  "setInterval(refresh, 2000);\n" +
  "</script>\n"
