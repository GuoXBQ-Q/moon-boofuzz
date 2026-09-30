///|
suberror CliError {
  InvalidArguments(String)
} derive(Debug)

///|
extern "c" fn exit_process(code : Int) -> Unit = "exit"

///|
/// Upstream constants.RESULTS_DIR (constants.py:8): default home of the
/// run-stamped SQLite results database.
const RESULTS_DIR : String = "boofuzz-results"

///|
/// Printed by --version. Must stay equal to `version` in moon.mod;
/// version_wbtest.mbt fails the test suite when the two drift apart.
const CLI_VERSION : String = "0.1.3"

///|
/// Accept a case id in either form: the bare "v1:request.field:index"
/// position_of_id resolves, or the full "[\"path\"]/v1:..." form the
/// generate output and run records print (everything after the last '/').
fn inner_case_id(id : String) -> String {
  if id.has_prefix("v1:") {
    return id
  }
  let mut cut = -1
  let mut index = 0
  for ch in id {
    if ch == '/' {
      cut = index
    }
    index += 1
  }
  if cut >= 0 {
    id[cut + 1:].to_owned()
  } else {
    id
  }
}

///|
fn options(
  args : ArrayView[String],
  allowed : Array[String],
) -> Map[String, String] raise CliError {
  let result : Map[String, String] = Map([])
  guard args.length() % 2 == 0 else {
    raise InvalidArguments("each option requires a value")
  }
  for i in 0..<(args.length() / 2) {
    let key = args[i * 2]
    guard allowed.contains(key) && !result.contains(key) else {
      raise InvalidArguments("unknown or duplicate option: " + key)
    }
    result[key] = args[i * 2 + 1]
  }
  result
}

///|
fn int_option(options : Map[String, String], name : String) -> Int? raise {
  options
  .get(name)
  .map(text => {
    let n = @definition.decimal_u64(text)
    guard n <= 2147483647UL else {
      raise InvalidArguments("option is too large: " + name)
    }
    n.to_int()
  })
}

///|
fn state_name(state : @core.EnumerationState) -> String {
  match state {
    Running => "running"
    Exhausted => "exhausted"
    Limited => "limited"
    Stopped => "stopped"
  }
}

///|
fn dispatch(args : Array[String]) -> Int raise {
  if args == ["--help"] || args.is_empty() {
    println(
      "moon-boofuzz generate DEFINITION.json [--limit N] [--start N] [--id CASE_ID] [--combinatorial true|false] [--max-depth N]\nmoon-boofuzz run DEFINITION.json --output CASES.jsonl [--limit N] [--combinatorial true|false] [--max-depth N] [--target-cmd CMD] [--start N] [--end N] [--sleep-between-ms N] [--text-dump true|false] [--csv-out FILE] [--db FILE] [--record-passes N] [--web-port N]\nmoon-boofuzz open FILE [--ui-port N]\nmoon-boofuzz convert [--ui-port N]\nmoon-boofuzz replay CASES.jsonl --id CASE_ID [--host HOST --port PORT]\nmoon-boofuzz report CASES.jsonl [--max-bytes N]",
    )
    return 0
  }
  if args == ["--version"] {
    println("moon-boofuzz \{CLI_VERSION}")
    return 0
  }
  if args is ["convert", .. flags] {
    convert_command(flags)
    return 0
  }
  guard args is [command, input, .. flags] else {
    raise InvalidArguments("expected a command and input path")
  }
  if command == "open" {
    open_viewer(input, flags)
    return 0
  }
  if command == "replay" || command == "report" {
    return replay_or_report(command, input, flags)
  }
  guard command == "generate" || command == "run" else {
    raise InvalidArguments("unknown command: " + command)
  }
  let opts = options(
    flags,
    if command == "generate" {
      ["--limit", "--start", "--id", "--combinatorial", "--max-depth"]
    } else {
      [
        "--limit", "--output", "--combinatorial", "--max-depth", "--start", "--end",
        "--sleep-between-ms", "--text-dump", "--target-cmd", "--csv-out", "--db",
        "--record-passes", "--web-port",
      ]
    },
  )
  let limit = int_option(opts, "--limit")
  let combinatorial : Bool? = opts
    .get("--combinatorial")
    .map(text => {
      guard text == "true" || text == "false" else {
        raise InvalidArguments("--combinatorial must be true or false")
      }
      text == "true"
    })
  let max_depth = int_option(opts, "--max-depth")
  let case_id : String? = opts.get("--id")
  let target_cmd : String? = opts.get("--target-cmd")
  let csv_out : String? = opts.get("--csv-out")
  let db_path : String? = opts.get("--db")
  let record_passes = int_option(opts, "--record-passes").unwrap_or(0)
  let web_port : Int? = opts
    .get("--web-port")
    .map(name => {
      let n = @definition.decimal_u64(name)
      guard n <= 65535UL else {
        raise InvalidArguments("--web-port must be a port number")
      }
      n.to_int()
    })
  let text_dump : Bool? = opts
    .get("--text-dump")
    .map(text => {
      guard text == "true" || text == "false" else {
        raise InvalidArguments("--text-dump must be true or false")
      }
      text == "true"
    })
  let sleep_ms_value = int_option(opts, "--sleep-between-ms")
  let end : Int? = int_option(opts, "--end")
  let definition = @definition.ProtocolDefinition::parse(
    @utf8.decode(@recordio.read_bytes(input)),
  )
  let execution = definition.execution().map(@runner.ExecutionConfig::parse)
  // Entry-point default mirrors upstream's CLI (cli.py:52-54): combinatorial
  // blasting is on unless the JSON execution config or the flag turns it off.
  // The flag wins; without it the JSON value applies (true when absent).
  let use_combinatorial = combinatorial.unwrap_or(
    execution.map(config => config.combinatorial).unwrap_or(true),
  )
  if command == "generate" {
    if execution is Some(config) {
      ignore(config.runner(definition.paths()))
    }
    let result = definition.generate(
      case => {
        let row : Json = {
          "kind": "generated_case",
          "case_id": case.case_id,
          "path": case.path,
          "field_path": case.case.field_path,
          "mutation_index": case.case.mutation_index,
          "ordinal": case.case.ordinal,
          "prefix_hex": case.prefix.map(@records.hex_encode),
          "payload_hex": @records.hex_encode(case.case.payload),
        }
        println(row.stringify())
        true
      },
      start=match case_id {
        Some(id) => {
          guard !use_combinatorial else {
            raise InvalidArguments(
              "--id cannot be combined with --combinatorial (pass --combinatorial false to resume by id)",
            )
          }
          guard int_option(opts, "--start") is None else {
            raise InvalidArguments("--id cannot be combined with --start")
          }
          // Both the bare and the full id forms resolve to the same inner
          // id, which is what position_of_id and the verification compare.
          let inner = inner_case_id(id)
          let offset = definition.position_of_id(inner)
          // Verify the position actually holds the requested id; the
          // offset walks the same stream tree generate enumerates (group
          // product replays included), so a mismatch means the definition
          // differs from the one that produced the id.
          let actual = definition.case_id_at(offset).map(inner_case_id)
          guard actual == Some(inner) else {
            let found = actual.unwrap_or("end of stream")
            raise InvalidArguments(
              "case id \{id} does not resolve to itself at position \{offset} (found \{found}); the definition differs from the one that produced the id",
            )
          }
          offset
        }
        None => int_option(opts, "--start").unwrap_or(0)
      },
      limit=limit.unwrap_or(@runner.NO_CASE_LIMIT),
      combinatorial=use_combinatorial,
      max_depth?,
    )
    let summary : Json = {
      "kind": "generation_summary",
      "generated": result.generated,
      "state": state_name(result.state),
    }
    println(summary.stringify())
    return 0
  }
  let config = execution.unwrap_or_else(() => {
    raise InvalidArguments("run requires an execution configuration")
  })
  let start = int_option(opts, "--start").unwrap_or(0)
  let text_monitor = if text_dump.unwrap_or(false) {
    Some(
      @runner.Monitor::new(after=fn(result) {
        println("Test Case: " + result.id)
        for step in result.steps {
          println("  sent " + step.sent.length().to_string() + " bytes")
          if step.received.length() > 0 {
            println(
              "  received " + step.received.length().to_string() + " bytes",
            )
          }
          if !step.completed {
            println("  step incomplete")
          }
        }
        println("  outcome: " + result.outcome.name())
      }),
    )
  } else {
    None
  }
  // Target lifecycle: the CLI flag wins over the JSON execution config; both
  // produce a process monitor owning spawn, fault detection and restarts.
  let process_monitor : @runner.Monitor? = match target_cmd {
    Some(command) => Some(@process.ProcessMonitor::new(command).monitor)
    None =>
      match execution {
        Some(config) =>
          match config.target_command {
            Some(command) => Some(@process.ProcessMonitor::new(command).monitor)
            None => None
          }
        None => None
      }
  }
  let monitor = match (text_monitor, process_monitor) {
    (Some(text), Some(process)) => @runner.Monitor::combine(text, process)
    (Some(text), None) => text
    (None, Some(process)) => process
    (None, None) => @runner.Monitor::new()
  }
  let runner = if config.file_path() is Some(_) {
    // File transport: each case writes its messages as numbered files.
    @recordio.file_runner(
      config,
      definition.paths(),
      monitor~,
      limit=limit.unwrap_or(config.limit),
      combinatorial=use_combinatorial,
      max_depth?,
      start~,
      end~,
      sleep_between=sleep_ms_value,
    )
  } else {
    match limit {
      Some(n) =>
        config.runner(
          definition.paths(),
          limit=n,
          combinatorial=use_combinatorial,
          max_depth?,
          start~,
          end~,
          sleep_between=sleep_ms_value,
          monitor~,
        )
      None =>
        config.runner(
          definition.paths(),
          combinatorial=use_combinatorial,
          max_depth?,
          start~,
          end~,
          sleep_between=sleep_ms_value,
          monitor~,
        )
    }
  }
  let output = opts
    .get("--output")
    .unwrap_or_else(() => {
      raise InvalidArguments("run requires --output CASES.jsonl")
    })
  let writer = @recordio.Writer::open(output)
  defer writer.close()
  // Always-on SQLite results database (upstream session.py:175-188): an
  // explicit --db chooses the file, otherwise a run-stamped file is created
  // under boofuzz-results/. Both paths create missing parent directories
  // like upstream helpers.mkdir_safe.
  let db_file = match db_path {
    Some(path) => {
      let parent = @recordio.parent_directory(path)
      if !parent.is_empty() {
        @recordio.ensure_directory(parent)
      }
      path
    }
    None => {
      @recordio.ensure_directory(RESULTS_DIR)
      RESULTS_DIR + "/run-\{@db.run_stamp()}.db"
    }
  }
  let db_logger = @db.DbLogger::open(db_file, num_log_cases=record_passes)
  // Progress denominator: the sum of every fuzzed target's primitive
  // counts (upstream Session.num_mutations), computed from the compiled
  // definition — not the case cap. Combinatorial blasting may run past it.
  let mut mutations = 0L
  for path in definition.paths() {
    mutations += path.target().raw_mutation_count()
  }
  if mutations > 2147483647L {
    mutations = 2147483647L
  }
  // Live web UI on upstream's default port: bound even before the first
  // case so the URL is known, mirroring upstream server_init before fuzz().
  // --web-port 0 still asks the OS for a free port. The live /test-case
  // pages read details from the results database this run writes
  // (upstream's live-db approach) instead of caching records in memory.
  let webui = @web.WebUi::open(
    port=web_port.unwrap_or(26000),
    total=mutations.to_int(),
    db_path=Some(db_file),
  )
  println("Web interface can be found at http://localhost:\{webui.port()}")
  let count = {
    defer db_logger.close()
    let executed = capture_all(runner, writer, db_logger, webui, record_passes)
    // Final flush of any throttled queue entries, mirroring the
    // upstream session close sequence.
    db_logger.close_test()
    executed
  }
  writer.close()
  // Serve anything still queued, then expose the final state; the process
  // exits right after (upstream's interactive keep-open ENTER wait is
  // deliberately not reproduced in a batch CLI).
  webui.serve()
  webui.session().close()
  match csv_out {
    Some(csv) => {
      let rows = write_csv_report(csv, output)
      let csv_summary : Json = {
        "kind": "csv_report",
        "path": csv,
        "rows": rows,
      }
      println(csv_summary.stringify())
    }
    None => ()
  }
  let summary : Json = {
    "kind": "run_summary",
    "executed": count,
    "state": state_name(runner.state()),
    "records": output,
    "database": db_file,
  }
  println(summary.stringify())
  0
}

///|
fn main {
  let code = dispatch(@env.args()[1:].to_owned()) catch {
    error => {
      @recordio.print_error("moon-boofuzz: \{Repr(error)}")
      2
    }
  }
  if code != 0 {
    exit_process(code)
  }
}
