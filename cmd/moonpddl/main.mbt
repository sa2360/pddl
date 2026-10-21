// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

///|
const VERSION : String = "0.1.0"

///|
fn usage() -> String {
  let text =
    #|moonpddl - PDDL planning engine and independent plan validator
    #|Usage:
    #|  moonpddl solve <domain.pddl> <problem.pddl> [options]
    #|  moonpddl validate <domain.pddl> <problem.pddl> <plan.txt> [--json]
    #|  moonpddl check <domain.pddl> <problem.pddl> [--json]
    #|  moonpddl ground <domain.pddl> <problem.pddl> [--json]
    #|  moonpddl version
    #|
    #|Solve options:
    #|  -s, --search <gbfs|astar|wastar>   Search strategy (default: gbfs)
    #|  -H, --heuristic <name>             blind, goal-count, hmax, hadd, hff
    #|                                     (default: hff)
    #|      --weight <n>                   Weight for wastar (default: 5)
    #|      --max-expanded <n>             Expansion limit (default: 1000000)
    #|      --json                         Machine-readable output
    #|      --out <path>                   Write the plan to a file
    #|  -q, --quiet                        Do not print solver statistics
    #|  -h, --help                         Show this help
    #|
    #|Exit codes: 0 success, 1 no plan or invalid plan, 2 usage/model error.
    #|
  text
}

///|
fn usage_error(message : String) -> Int {
  println("error: \{message}")
  println("")
  println(usage())
  2
}

///|
fn json_escape(text : String) -> String {
  let sb = StringBuilder::StringBuilder()
  for c in text.to_array() {
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      _ => sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
fn report_error(json : Bool, message : String) -> Int {
  if json {
    println("{\"error\":\"\{json_escape(message)}\"}")
  } else {
    println("error: \{message}")
  }
  2
}

///|
fn usage_error_mode(json : Bool, message : String) -> Int {
  if json {
    report_error(true, message)
  } else {
    usage_error(message)
  }
}

///|
fn parse_count(text : String) -> Int? {
  if text == "" {
    return None
  }
  let mut value = 0
  for c in text.to_array() {
    if c < '0' || c > '9' {
      return None
    }
    let digit = c.to_int() - 48
    if value > (1_000_000_000 - digit) / 10 {
      return None
    }
    value = value * 10 + digit
  }
  Some(value)
}

///|
fn load_grounded(
  domain_path : String,
  problem_path : String,
) -> @pddl.GroundProblem raise {
  let domain = @pddl.parse_domain(@fs.read_file_to_string(domain_path))
  let problem = @pddl.parse_problem(@fs.read_file_to_string(problem_path))
  @pddl.ground(domain, problem)
}

///|
fn cost_mode(problem : @pddl.GroundProblem) -> String {
  if problem.uses_action_costs {
    "total-cost"
  } else {
    "unit"
  }
}

///|
fn search_status_name(status : @pddl.SearchStatus) -> String {
  match status {
    @pddl.Solved => "solved"
    @pddl.Exhausted => "exhausted"
    @pddl.NodeLimitReached => "limit"
  }
}

///|
fn search_json(
  result : @pddl.SearchResult,
  problem : @pddl.GroundProblem,
  heuristic : @pddl.HeuristicKind,
  search : @pddl.SearchAlgorithm,
) -> String {
  let sb = StringBuilder::StringBuilder()
  sb.write_string("{\"status\":\"")
  sb.write_string(search_status_name(result.status))
  sb.write_string("\",\"cost\":")
  sb.write_string(result.cost.to_string())
  sb.write_string(",\"steps\":")
  sb.write_string(result.plan.length().to_string())
  sb.write_string(",\"expanded\":")
  sb.write_string(result.expanded.to_string())
  sb.write_string(",\"generated\":")
  sb.write_string(result.generated.to_string())
  sb.write_string(",\"heuristic\":\"")
  sb.write_string(heuristic.name())
  sb.write_string("\",\"search\":\"")
  sb.write_string(search.name())
  sb.write_string("\",\"plan\":[")
  for index in 0..<result.plan.length() {
    if index > 0 {
      sb.write_char(',')
    }
    sb.write_char('"')
    sb.write_string(json_escape(problem.actions[result.plan[index]].render()))
    sb.write_char('"')
  }
  sb.write_string("]}")
  sb.to_string()
}

///|
fn model_json(problem : @pddl.GroundProblem, detailed : Bool) -> String {
  let sb = StringBuilder::StringBuilder()
  sb.write_string("{\"domain\":\"")
  sb.write_string(json_escape(problem.domain_name))
  sb.write_string("\",\"problem\":\"")
  sb.write_string(json_escape(problem.problem_name))
  sb.write_string("\",\"objects\":")
  sb.write_string(problem.objects.length().to_string())
  sb.write_string(",\"atoms\":")
  sb.write_string(problem.atoms.length().to_string())
  sb.write_string(",\"actions\":")
  sb.write_string(problem.actions.length().to_string())
  sb.write_string(",\"goal_disjuncts\":")
  sb.write_string(problem.goal.length().to_string())
  sb.write_string(",\"initial_cost\":")
  sb.write_string(problem.initial_cost.to_string())
  sb.write_string(",\"costs\":\"")
  sb.write_string(cost_mode(problem))
  sb.write_char('"')
  if detailed {
    sb.write_string(",\"ground_actions\":[")
    for index in 0..<problem.actions.length() {
      if index > 0 {
        sb.write_char(',')
      }
      let action = problem.actions[index]
      sb.write_string("{\"id\":")
      sb.write_string(action.id.to_string())
      sb.write_string(",\"action\":\"")
      sb.write_string(json_escape(action.render()))
      sb.write_string("\",\"cost\":")
      sb.write_string(action.cost.to_string())
      sb.write_char('}')
    }
    sb.write_char(']')
  }
  sb.write_char('}')
  sb.to_string()
}

///|
fn cmd_solve(args : Array[String]) -> Int {
  let positionals : Array[String] = []
  let mut heuristic : @pddl.HeuristicKind = @pddl.HFF
  let mut search : @pddl.SearchAlgorithm = @pddl.GBFS
  let mut weight : Int? = None
  let mut max_expanded = 1_000_000
  let mut json = args.contains("--json")
  let mut out_path = ""
  let mut quiet = false
  let mut index = 2
  while index < args.length() {
    let arg = args[index]
    match arg {
      "-h" | "--help" => {
        println(usage())
        return 0
      }
      "-s" | "--search" => {
        if index + 1 >= args.length() {
          return usage_error_mode(json, "option '\{arg}' needs a value")
        }
        index += 1
        match @pddl.SearchAlgorithm::parse(args[index]) {
          Some(value) => search = value
          None =>
            return usage_error_mode(
              json,
              "unknown search strategy '\{args[index]}'; use gbfs, astar or wastar",
            )
        }
      }
      "-H" | "--heuristic" => {
        if index + 1 >= args.length() {
          return usage_error_mode(json, "option '\{arg}' needs a value")
        }
        index += 1
        match @pddl.HeuristicKind::parse(args[index]) {
          Some(value) => heuristic = value
          None =>
            return usage_error_mode(
              json,
              "unknown heuristic '\{args[index]}'; use blind, goal-count, hmax, hadd or hff",
            )
        }
      }
      "--weight" => {
        if index + 1 >= args.length() {
          return usage_error_mode(json, "option '--weight' needs a value")
        }
        index += 1
        match parse_count(args[index]) {
          Some(value) =>
            if value <= 0 {
              return usage_error_mode(
                json, "--weight must be a positive integer",
              )
            } else {
              weight = Some(value)
            }
          None =>
            return usage_error_mode(json, "--weight expects a positive integer")
        }
      }
      "--max-expanded" => {
        if index + 1 >= args.length() {
          return usage_error_mode(json, "option '--max-expanded' needs a value")
        }
        index += 1
        match parse_count(args[index]) {
          Some(value) => max_expanded = value
          None =>
            return usage_error_mode(json, "--max-expanded expects an integer")
        }
      }
      "--out" => {
        if index + 1 >= args.length() {
          return usage_error_mode(json, "option '--out' needs a value")
        }
        index += 1
        out_path = args[index]
      }
      "--json" => json = true
      "-q" | "--quiet" => quiet = true
      _ => {
        if arg.has_prefix("-") {
          return usage_error_mode(json, "unknown option '\{arg}'")
        }
        positionals.push(arg)
      }
    }
    index += 1
  }
  if positionals.length() != 2 {
    return usage_error_mode(
      json, "solve expects a domain file and a problem file",
    )
  }
  match weight {
    Some(value) =>
      match search {
        @pddl.WeightedAStar(_) => search = @pddl.WeightedAStar(value)
        _ =>
          return usage_error_mode(
            json, "--weight can only be used with --search wastar",
          )
      }
    None => ()
  }
  let domain_path = positionals[0]
  let problem_path = positionals[1]
  try {
    let grounded = load_grounded(domain_path, problem_path)
    let result = @pddl.solve(grounded, heuristic, search, max_expanded~)
    let plan_text = result.render_plan(grounded)
    if result.is_solved() && out_path != "" {
      let content = "; cost = \{result.cost}\n" + plan_text
      @fs.write_string_to_file(out_path, content) catch {
        @fs.IOError(message) =>
          return report_error(json, "cannot write plan: \{message}")
      }
    }
    if json {
      println(search_json(result, grounded, heuristic, search))
    } else if result.is_solved() {
      if !quiet {
        println("; moonpddl: solved")
        println("; cost = \{result.cost}")
        println(
          "; expanded = \{result.expanded}, generated = \{result.generated}",
        )
        println("; heuristic = \{heuristic.name()}, search = \{search.name()}")
        if out_path != "" {
          println("; plan written to \{out_path}")
        }
      }
      println(plan_text.trim_end().to_owned())
    } else {
      let reason = match result.status {
        @pddl.Exhausted => "search space exhausted"
        @pddl.NodeLimitReached => "node limit reached"
        _ => "no plan"
      }
      println(
        "no plan found: \{reason} (expanded \{result.expanded}, generated \{result.generated})",
      )
    }
    if result.is_solved() {
      0
    } else {
      1
    }
  } catch {
    @fs.IOError(message) => report_error(json, "cannot read input: \{message}")
    err => report_error(json, err.to_string())
  }
}

///|
fn cmd_validate(args : Array[String]) -> Int {
  let positionals : Array[String] = []
  let mut json = args.contains("--json")
  let mut index = 2
  while index < args.length() {
    let arg = args[index]
    match arg {
      "-h" | "--help" => {
        println(usage())
        return 0
      }
      "--json" => json = true
      _ => {
        if arg.has_prefix("-") {
          return usage_error_mode(json, "unknown option '\{arg}'")
        }
        positionals.push(arg)
      }
    }
    index += 1
  }
  if positionals.length() != 3 {
    return usage_error_mode(
      json, "validate expects a domain file, a problem file and a plan file",
    )
  }
  let domain_path = positionals[0]
  let problem_path = positionals[1]
  let plan_path = positionals[2]
  try {
    let report = @pddl.validate(
      @pddl.parse_domain(@fs.read_file_to_string(domain_path)),
      @pddl.parse_problem(@fs.read_file_to_string(problem_path)),
      @fs.read_file_to_string(plan_path),
    )
    if json {
      println(report.to_json())
    } else {
      println(report.message())
      for issue in report.issues {
        if issue.line > 0 {
          println(
            "  line \{issue.line}: [\{issue.kind.name()}] \{issue.message}",
          )
        } else {
          println("  [\{issue.kind.name()}] \{issue.message}")
        }
      }
    }
    if report.valid {
      0
    } else {
      1
    }
  } catch {
    @fs.IOError(message) => report_error(json, "cannot read input: \{message}")
    err => report_error(json, err.to_string())
  }
}

///|
fn model_summary(args : Array[String], detailed : Bool) -> Int {
  let positionals : Array[String] = []
  let mut json = args.contains("--json")
  let mut index = 2
  while index < args.length() {
    let arg = args[index]
    match arg {
      "-h" | "--help" => {
        println(usage())
        return 0
      }
      "--json" => json = true
      _ => {
        if arg.has_prefix("-") {
          return usage_error_mode(json, "unknown option '\{arg}'")
        }
        positionals.push(arg)
      }
    }
    index += 1
  }
  if positionals.length() != 2 {
    return usage_error_mode(
      json, "this command expects a domain file and a problem file",
    )
  }
  try {
    let grounded = load_grounded(positionals[0], positionals[1])
    if json {
      println(model_json(grounded, detailed))
    } else {
      println("model ok")
      println("  domain: \{grounded.domain_name}")
      println("  problem: \{grounded.problem_name}")
      println("  objects: \{grounded.objects.length()}")
      println("  atoms: \{grounded.atoms.length()}")
      println("  actions: \{grounded.actions.length()}")
      println("  goal disjuncts: \{grounded.goal.length()}")
      println("  initial cost: \{grounded.initial_cost}")
      println("  cost mode: \{cost_mode(grounded)}")
      if detailed {
        println("")
        println("ground actions:")
        for action in grounded.actions {
          println("#\{action.id} cost=\{action.cost} \{action.render()}")
        }
      }
    }
    0
  } catch {
    @fs.IOError(message) => report_error(json, "cannot read input: \{message}")
    err => report_error(json, err.to_string())
  }
}

///|
fn run(args : Array[String]) -> Int {
  if args.length() < 2 {
    println(usage())
    return 0
  }
  let command = args[1]
  match command {
    "solve" => cmd_solve(args)
    "validate" => cmd_validate(args)
    "check" => model_summary(args, false)
    "ground" => model_summary(args, true)
    "version" | "--version" => {
      println("moonpddl \{VERSION}")
      0
    }
    "help" | "--help" | "-h" => {
      println(usage())
      0
    }
    _ => {
      println("error: unknown command '\{command}'")
      println("")
      println(usage())
      2
    }
  }
}

///|
fn main {
  @sys.exit(run(@env.args()))
}
