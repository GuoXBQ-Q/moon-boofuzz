///|
suberror CliError {
  InvalidArguments(String)
} derive(Debug)

///|
extern "c" fn exit_process(code : Int) -> Unit = "exit"

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
  if args.is_empty() || args == ["--help"] {
    println(
      "moon-boofuzz generate DEFINITION.json [--limit N] [--start N] [--id CASE_ID] [--combinatorial true|false] [--max-depth N]\nmoon-boofuzz run DEFINITION.json --output CASES.jsonl [--limit N] [--combinatorial true|false] [--max-depth N] [--target-cmd CMD] [--start N] [--end N] [--sleep-between-ms N] [--text-dump true|false]\nmoon-boofuzz replay CASES.jsonl --id CASE_ID [--host HOST --port PORT]\nmoon-boofuzz report CASES.jsonl [--max-bytes N]",
    )
    return 0
  }
  if args == ["--version"] {
    println("moon-boofuzz 0.1.0")
    return 0
  }
  guard args is [command, input, .. flags] else {
    raise InvalidArguments("expected a command and input path")
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
        "--sleep-between-ms", "--text-dump", "--target-cmd",
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
        Some(id) => definition.position_of_id(id)
        None => int_option(opts, "--start").unwrap_or(0)
      },
      limit=limit.unwrap_or(10000),
      combinatorial=combinatorial.unwrap_or(false),
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
      combinatorial=combinatorial.unwrap_or(false),
      max_depth?,
      start~,
      end~,
      sleep_between=sleep_ms_value.unwrap_or(0),
    )
  } else {
    match limit {
      Some(n) =>
        config.runner(
          definition.paths(),
          limit=n,
          combinatorial?,
          max_depth?,
          start~,
          end~,
          sleep_between=sleep_ms_value.unwrap_or(0),
          monitor~,
        )
      None =>
        config.runner(
          definition.paths(),
          combinatorial?,
          max_depth?,
          start~,
          end~,
          sleep_between=sleep_ms_value.unwrap_or(0),
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
  let count = @recordio.capture(runner, writer)
  let summary : Json = {
    "kind": "run_summary",
    "executed": count,
    "state": state_name(runner.state()),
    "records": output,
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
