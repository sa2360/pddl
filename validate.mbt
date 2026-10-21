// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

///|
/// Categories of validation problems.
pub(all) enum ValidationIssueKind {
  PlanSyntax
  UnknownAction
  Inapplicable
  GoalNotReached
  CostMismatch
} derive(Eq, Debug)

///|
/// One diagnostic produced while parsing or executing a plan. `line` and
/// `step` are 1-based and are `0` when the issue is not tied to a line or a
/// step.
pub(all) struct ValidationIssue {
  kind : ValidationIssueKind
  line : Int
  step : Int
  message : String
} derive(Debug)

///|
/// The result of checking a plan. A cost comment mismatch is an error: the
/// plan file makes a claim that the validator could not reproduce.
pub(all) struct ValidationReport {
  valid : Bool
  steps : Int
  executed : Int
  cost : Int64
  declared_cost : Int64?
  issues : Array[ValidationIssue]
} derive(Debug)

///|
pub fn ValidationReport::message(self : ValidationReport) -> String {
  if self.valid {
    if self.issues.length() > 0 {
      "plan valid: \{self.executed} step(s), cost \{self.cost} (\{self.issues.length()} warning(s))"
    } else {
      "plan valid: \{self.executed} step(s), cost \{self.cost}"
    }
  } else {
    "plan invalid"
  }
}

///|
pub fn ValidationIssueKind::name(self : ValidationIssueKind) -> String {
  match self {
    PlanSyntax => "plan-syntax"
    UnknownAction => "unknown-action"
    Inapplicable => "inapplicable"
    GoalNotReached => "goal-not-reached"
    CostMismatch => "cost-mismatch"
  }
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
/// Serializes the report as a single JSON object.
pub fn ValidationReport::to_json(self : ValidationReport) -> String {
  let sb = StringBuilder::StringBuilder()
  sb.write_string("{\"valid\":")
  if self.valid {
    sb.write_string("true")
  } else {
    sb.write_string("false")
  }
  sb.write_string(",\"steps\":")
  sb.write_string(self.steps.to_string())
  sb.write_string(",\"executed\":")
  sb.write_string(self.executed.to_string())
  sb.write_string(",\"cost\":")
  sb.write_string(self.cost.to_string())
  sb.write_string(",\"declared_cost\":")
  match self.declared_cost {
    Some(value) => sb.write_string(value.to_string())
    None => sb.write_string("null")
  }
  sb.write_string(",\"issues\":[")
  for index in 0..<self.issues.length() {
    if index > 0 {
      sb.write_char(',')
    }
    let issue = self.issues[index]
    sb.write_string("{\"kind\":\"")
    sb.write_string(issue.kind.name())
    sb.write_string("\",\"line\":")
    sb.write_string(issue.line.to_string())
    sb.write_string(",\"step\":")
    sb.write_string(issue.step.to_string())
    sb.write_string(",\"message\":\"")
    sb.write_string(json_escape(issue.message))
    sb.write_string("\"}")
  }
  sb.write_string("]}")
  sb.to_string()
}

///|
priv struct PlanStep {
  name : String
  args : Array[String]
  line : Int
}

///|
priv struct ParsedPlan {
  steps : Array[PlanStep]
  issues : Array[ValidationIssue]
  declared_cost : Int64?
  declared_line : Int
}

///|
fn split_comment(line : String) -> (String, String) {
  match line.find(";") {
    Some(index) => (line[:index].to_owned(), line[index + 1:].to_owned())
    None => (line, "")
  }
}

///|
fn parse_declared_cost(comment : String) -> (Bool, Int64?) {
  let lower = comment.to_lower()
  if !lower.contains("cost") {
    return (false, None)
  }
  let equals = match lower.find("=") {
    Some(index) => index
    None => return (false, None)
  }
  let tail = lower[equals + 1:].trim().to_owned()
  if tail.length() == 0 {
    return (true, None)
  }
  let chars = tail.to_array()
  if chars[0] < '0' || chars[0] > '9' {
    return (true, None)
  }
  let mut index = 0
  while index < chars.length() && chars[index] >= '0' && chars[index] <= '9' {
    index += 1
  }
  if index < chars.length() {
    let next = chars[index]
    if !next.is_whitespace() && next != ',' && next != ')' && next != ';' {
      return (true, None)
    }
  }
  (true, parse_int(tail[:index].to_owned()))
}

///|
fn tokenize_plan_step(text : String) -> Array[String] {
  let tokens : Array[String] = []
  let mut builder = StringBuilder::StringBuilder()
  let mut has_token = false
  for c in text.to_array() {
    if c.is_whitespace() {
      if has_token {
        tokens.push(builder.to_string())
        builder = StringBuilder::StringBuilder()
        has_token = false
      }
    } else {
      builder.write_char(c)
      has_token = true
    }
  }
  if has_token {
    tokens.push(builder.to_string())
  }
  tokens
}

///|
fn syntax_issue(line : Int, message : String) -> ValidationIssue {
  { kind: PlanSyntax, line, step: 0, message, }
}

///|
fn parse_plan_step(
  body : String,
  line : Int,
  issues : Array[ValidationIssue],
) -> PlanStep? {
  let trimmed = body.trim().to_owned()
  if trimmed.length() == 0 {
    return None
  }
  let mut inner = trimmed
  if trimmed.has_prefix("(") {
    if !trimmed.has_suffix(")") {
      issues.push(
        syntax_issue(
          line,
          "line \{line}: missing ')' in plan step '\{trimmed}'",
        ),
      )
      return None
    }
    inner = trimmed[1:trimmed.length() - 1].to_owned()
    if inner.contains("(") || inner.contains(")") {
      issues.push(
        syntax_issue(
          line,
          "line \{line}: nested parentheses in plan step '\{trimmed}'",
        ),
      )
      return None
    }
  } else if trimmed.contains("(") || trimmed.contains(")") {
    issues.push(
      syntax_issue(
        line,
        "line \{line}: unexpected parenthesis in plan step '\{trimmed}'",
      ),
    )
    return None
  }
  let tokens = tokenize_plan_step(inner)
  if tokens.length() == 0 {
    issues.push(syntax_issue(line, "line \{line}: empty plan step"))
    return None
  }
  let name = tokens[0].to_lower()
  let args : Array[String] = []
  for index in 1..<tokens.length() {
    args.push(tokens[index].to_lower())
  }
  Some({ name, args, line, })
}

///|
fn parse_plan(source : String) -> ParsedPlan {
  let steps : Array[PlanStep] = []
  let issues : Array[ValidationIssue] = []
  let mut declared_cost : Int64? = None
  let mut declared_line = 0
  let mut line_number = 0
  for raw_line in source.split("\n") {
    line_number += 1
    let raw_text = raw_line.to_owned()
    let line = raw_text.trim().to_owned()
    let (body, comment) = split_comment(line)
    let (mentions_cost, parsed_cost) = parse_declared_cost(comment)
    match parsed_cost {
      Some(value) => {
        declared_cost = Some(value)
        declared_line = line_number
      }
      None =>
        if mentions_cost {
          issues.push(
            syntax_issue(
              line_number,
              "line \{line_number}: malformed cost comment; expected '; cost = <non-negative integer>'",
            ),
          )
        }
    }
    match parse_plan_step(body, line_number, issues) {
      Some(step) => steps.push(step)
      None => ()
    }
  }
  { steps, issues, declared_cost, declared_line, }
}

///|
fn render_plan_step(step : PlanStep) -> String {
  let sb = StringBuilder::StringBuilder()
  sb.write_char('(')
  sb.write_string(step.name)
  for arg in step.args {
    sb.write_char(' ')
    sb.write_string(arg)
  }
  sb.write_char(')')
  sb.to_string()
}

///|
fn literal_text(problem : GroundProblem, literal : Literal) -> String {
  match literal {
    Positive(atom) => problem.atom_text(atom)
    Negative(atom) => "(not \{problem.atom_text(atom)})"
  }
}

///|
/// Describes the unsatisfied literals of the closest DNF alternative.
fn closest_unsatisfied(
  problem : GroundProblem,
  condition : Array[Array[Literal]],
  state : State,
) -> String {
  if condition.length() == 0 {
    return "the condition has no satisfiable disjunct"
  }
  let mut chosen : Array[String] = []
  let mut chosen_count = -1
  for alternative in condition {
    let missing : Array[String] = []
    for literal in alternative {
      if !literal.holds(state) {
        missing.push(literal_text(problem, literal))
      }
    }
    if chosen_count < 0 || missing.length() < chosen_count {
      chosen_count = missing.length()
      chosen = missing
    }
  }
  if chosen.length() == 0 {
    return "none"
  }
  let sb = StringBuilder::StringBuilder()
  let limit = if chosen.length() < 6 { chosen.length() } else { 6 }
  for index in 0..<limit {
    if index > 0 {
      sb.write_string(", ")
    }
    sb.write_string(chosen[index])
  }
  if chosen.length() > limit {
    sb.write_string(", ...")
  }
  sb.to_string()
}

///|
fn issue(
  kind : ValidationIssueKind,
  line : Int,
  step : Int,
  message : String,
) -> ValidationIssue {
  { kind, line, step, message, }
}

///|
/// Executes `source` against an already grounded problem and reports the
/// first failure together with the plan cost.
pub fn validate_plan(
  problem : GroundProblem,
  source : String,
) -> ValidationReport {
  let parsed = parse_plan(source)
  if parsed.issues.length() > 0 {
    return {
      valid: false,
      steps: parsed.steps.length(),
      executed: 0,
      cost: 0L,
      declared_cost: parsed.declared_cost,
      issues: parsed.issues,
    }
  }
  let lookup : Map[String, Int] = Map([])
  let names : Map[String, Bool] = Map([])
  for index in 0..<problem.actions.length() {
    let action = problem.actions[index]
    lookup.set(atom_key(action.name, action.args), index)
    names.set(action.name, true)
  }
  let issues : Array[ValidationIssue] = []
  let mut state = problem.initial.copy()
  let mut executed = 0
  let mut cost = problem.initial_cost
  for step in parsed.steps {
    let index = match lookup.get(atom_key(step.name, step.args)) {
      Some(index) => index
      None => {
        let message = if names.contains(step.name) {
          "step \{executed + 1} (\{render_plan_step(step)}) does not match any grounded action; check the arguments and their types"
        } else {
          "step \{executed + 1} (\{render_plan_step(step)}) uses unknown action '\{step.name}'"
        }
        issues.push(issue(UnknownAction, step.line, executed + 1, message))
        return {
          valid: false,
          steps: parsed.steps.length(),
          executed,
          cost,
          declared_cost: parsed.declared_cost,
          issues,
        }
      }
    }
    let action = problem.actions[index]
    if !action_is_applicable(action, state) {
      let detail = closest_unsatisfied(problem, action.precondition, state)
      let message = "step \{executed + 1} (\{action.render()}) is not applicable; unsatisfied preconditions: \{detail}"
      issues.push(issue(Inapplicable, step.line, executed + 1, message))
      return {
        valid: false,
        steps: parsed.steps.length(),
        executed,
        cost,
        declared_cost: parsed.declared_cost,
        issues,
      }
    }
    state = apply_action(action, state)
    cost = capped_add(cost, action.cost)
    executed += 1
  }
  let mut valid = problem.goal_holds(state)
  if !valid {
    let detail = closest_unsatisfied(problem, problem.goal, state)
    let message = "goal is not satisfied after \{executed} step(s); unsatisfied goal literals: \{detail}"
    issues.push(issue(GoalNotReached, 0, 0, message))
  } else {
    match parsed.declared_cost {
      Some(declared) =>
        if declared != cost {
          let message = "declared plan cost \{declared} does not match computed cost \{cost}"
          issues.push(issue(CostMismatch, parsed.declared_line, 0, message))
          valid = false
        }
      None => ()
    }
  }
  {
    valid,
    steps: parsed.steps.length(),
    executed,
    cost,
    declared_cost: parsed.declared_cost,
    issues,
  }
}

///|
/// Parses and grounds the model, then validates the plan against it.
pub fn validate(
  domain : Domain,
  problem : Problem,
  source : String,
) -> ValidationReport raise PddlError {
  validate_plan(ground(domain, problem), source)
}
