// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

///|
test "validate a correct blocksworld plan" {
  let problem = try! ground(
    parse_domain(blocksworld_domain),
    parse_problem(blocksworld_problem),
  )
  let source =
    #|(pick-up b)
    #|(stack b c)
    #|(pick-up a)
    #|(stack a b)
    #|; cost = 4 (unit cost)
  let report = validate_plan(problem, source)
  @test.assert_eq(report.valid, true)
  @test.assert_eq(report.steps, 4)
  @test.assert_eq(report.executed, 4)
  @test.assert_eq(report.cost, 4.0)
  @test.assert_eq(report.declared_cost, Some(4.0))
  @test.assert_eq(report.issues.length(), 0)
  @test.assert_eq(report.message().contains("plan valid"), true)
  let json = report.to_json()
  @test.assert_eq(json.contains("\"valid\":true"), true)
  @test.assert_eq(json.contains("\"cost\":4"), true)
  @test.assert_eq(json.contains("\"declared_cost\":4"), true)
  @test.assert_eq(json.contains("\"issues\":[]"), true)
}

///|
test "validate plan steps without parentheses and in upper case" {
  let problem = try! ground(
    parse_domain(blocksworld_domain),
    parse_problem(blocksworld_problem),
  )
  let source =
    #|PICK-UP B
    #|STACK B C
    #|PICK-UP A
    #|STACK A B
  let report = validate_plan(problem, source)
  @test.assert_eq(report.valid, true)
  @test.assert_eq(report.cost, 4.0)
}

///|
test "validate reports an inapplicable step" {
  let problem = try! ground(
    parse_domain(blocksworld_domain),
    parse_problem(blocksworld_problem),
  )
  let source =
    #|(pick-up a)
    #|(pick-up b)
  let report = validate_plan(problem, source)
  @test.assert_eq(report.valid, false)
  @test.assert_eq(report.steps, 2)
  @test.assert_eq(report.executed, 1)
  @test.assert_eq(report.cost, 1.0)
  @test.assert_eq(report.issues.length(), 1)
  @test.assert_eq(report.issues[0].kind, Inapplicable)
  @test.assert_eq(report.issues[0].line, 2)
  @test.assert_eq(report.issues[0].step, 2)
  @test.assert_eq(report.issues[0].message.contains("not applicable"), true)
  @test.assert_eq(report.issues[0].message.contains("handempty"), true)
}

///|
test "validate reports unknown actions and bad arguments" {
  let problem = try! ground(
    parse_domain(blocksworld_domain),
    parse_problem(blocksworld_problem),
  )
  let unknown_source =
    #|(teleport a)
  let unknown = validate_plan(problem, unknown_source)
  @test.assert_eq(unknown.valid, false)
  @test.assert_eq(unknown.executed, 0)
  @test.assert_eq(unknown.issues[0].kind, UnknownAction)
  @test.assert_eq(
    unknown.issues[0].message.contains("unknown action 'teleport'"),
    true,
  )
  let bad_args_source =
    #|(pick-up z)
  let bad_args = validate_plan(problem, bad_args_source)
  @test.assert_eq(bad_args.valid, false)
  @test.assert_eq(bad_args.issues[0].kind, UnknownAction)
  @test.assert_eq(
    bad_args.issues[0].message.contains("does not match any grounded action"),
    true,
  )
}

///|
test "validate reports an unreached goal" {
  let problem = try! ground(
    parse_domain(blocksworld_domain),
    parse_problem(blocksworld_problem),
  )
  let source =
    #|(pick-up b)
  let report = validate_plan(problem, source)
  @test.assert_eq(report.valid, false)
  @test.assert_eq(report.steps, 1)
  @test.assert_eq(report.executed, 1)
  @test.assert_eq(report.issues[0].kind, GoalNotReached)
  @test.assert_eq(report.issues[0].message.contains("(on a b)"), true)
  let empty = validate_plan(problem, "")
  @test.assert_eq(empty.valid, false)
  @test.assert_eq(empty.steps, 0)
  @test.assert_eq(empty.executed, 0)
  @test.assert_eq(empty.issues[0].kind, GoalNotReached)
}

///|
test "validate reports syntax errors" {
  let problem = try! ground(
    parse_domain(blocksworld_domain),
    parse_problem(blocksworld_problem),
  )
  let source =
    #|(pick-up a
  let report = validate_plan(problem, source)
  @test.assert_eq(report.valid, false)
  @test.assert_eq(report.steps, 0)
  @test.assert_eq(report.executed, 0)
  @test.assert_eq(report.issues[0].kind, PlanSyntax)
  @test.assert_eq(report.issues[0].line, 1)
  @test.assert_eq(report.issues[0].message.contains("missing ')'"), true)
  let stray = validate_plan(problem, "pick-up a)")
  @test.assert_eq(stray.issues[0].kind, PlanSyntax)
  @test.assert_eq(
    stray.issues[0].message.contains("unexpected parenthesis"),
    true,
  )
}

///|
test "validate flags a mismatched cost comment" {
  let problem = try! ground(
    parse_domain(blocksworld_domain),
    parse_problem(blocksworld_problem),
  )
  let source =
    #|(pick-up b)
    #|(stack b c)
    #|(pick-up a)
    #|(stack a b)
    #|; cost = 99
  let report = validate_plan(problem, source)
  @test.assert_eq(report.valid, false)
  @test.assert_eq(report.cost, 4.0)
  @test.assert_eq(report.declared_cost, Some(99.0))
  @test.assert_eq(report.issues.length(), 1)
  @test.assert_eq(report.issues[0].kind, CostMismatch)
  @test.assert_eq(report.message(), "plan invalid")
}

///|
test "validate rejects a malformed cost comment" {
  let problem = try! ground(
    parse_domain(blocksworld_domain),
    parse_problem(blocksworld_problem),
  )
  let source =
    #|(pick-up b)
    #|(stack b c)
    #|(pick-up a)
    #|(stack a b)
    #|; cost = -1
  let report = validate_plan(problem, source)
  @test.assert_eq(report.valid, false)
  @test.assert_eq(report.issues.length(), 1)
  @test.assert_eq(report.issues[0].kind, PlanSyntax)
  @test.assert_eq(report.issues[0].message.contains("malformed cost"), true)
}

///|
test "validate a plan for an action cost domain" {
  let problem = try! ground(
    parse_domain(conditional_domain),
    parse_problem(conditional_problem),
  )
  let source =
    #|(mark a)
    #|(mark b)
    #|(finish)
    #|; cost = 2
  let report = validate_plan(problem, source)
  @test.assert_eq(report.valid, true)
  @test.assert_eq(report.steps, 3)
  @test.assert_eq(report.executed, 3)
  @test.assert_eq(report.cost, 2.0)
  @test.assert_eq(report.issues.length(), 0)
}

///|
test "validate a numeric plan with static function cost inputs" {
  let problem = try! ground(
    parse_domain(delivery_domain),
    parse_problem(delivery_problem),
  )
  let source =
    #|(refuel t1 a)
    #|(drive t1 a b)
    #|(drive t1 b c)
    #|; cost = 34
  let report = validate_plan(problem, source)
  @test.assert_eq(report.valid, true)
  @test.assert_eq(report.steps, 3)
  @test.assert_eq(report.executed, 3)
  @test.assert_eq(report.cost, 34.0)
  @test.assert_eq(report.declared_cost, Some(34.0))
  @test.assert_eq(report.issues.length(), 0)
}

///|
test "validate reports an unmet numeric goal" {
  let domain_source =
    #|(define (domain d)
    #|  (:requirements :fluents)
    #|  (:predicates (done))
    #|  (:functions (level) - number)
    #|  (:action raise
    #|    :parameters ()
    #|    :precondition ()
    #|    :effect (and (done) (increase (level) 3))))
  let problem_source =
    #|(define (problem p)
    #|  (:domain d)
    #|  (:init (= (level) 0))
    #|  (:goal (and (done) (>= (level) 10))))
  let problem = try! ground(
    parse_domain(domain_source),
    parse_problem(problem_source),
  )
  let source =
    #|(raise)
    #|; cost = 1
  let report = validate_plan(problem, source)
  @test.assert_eq(report.valid, false)
  @test.assert_eq(report.issues[0].kind, GoalNotReached)
  @test.assert_eq(report.issues[0].message.contains("(>= (level) 10)"), true)
}

///|
test "validate accepts fractional declared costs" {
  let domain_source =
    #|(define (domain d)
    #|  (:requirements :action-costs)
    #|  (:predicates (done))
    #|  (:functions (total-cost) - number)
    #|  (:action go
    #|    :parameters ()
    #|    :precondition ()
    #|    :effect (and (done) (increase (total-cost) 0.5))))
  let problem_source =
    #|(define (problem p)
    #|  (:domain d)
    #|  (:init (= (total-cost) 0))
    #|  (:goal (done))
    #|  (:metric minimize (total-cost)))
  let problem = try! ground(
    parse_domain(domain_source),
    parse_problem(problem_source),
  )
  @test.assert_eq(problem.actions[0].cost, 0.5)
  let source =
    #|(go)
    #|; cost = 0.5
  let report = validate_plan(problem, source)
  @test.assert_eq(report.valid, true)
  @test.assert_eq(report.cost, 0.5)
  @test.assert_eq(report.declared_cost, Some(0.5))
  let json = report.to_json()
  @test.assert_eq(json.contains("\"cost\":0.5"), true)
}

///|
test "validate flags a fractional cost mismatch" {
  let domain_source =
    #|(define (domain d)
    #|  (:requirements :action-costs)
    #|  (:predicates (done))
    #|  (:functions (total-cost) - number)
    #|  (:action go
    #|    :parameters ()
    #|    :precondition ()
    #|    :effect (and (done) (increase (total-cost) 0.5))))
  let problem_source =
    #|(define (problem p)
    #|  (:domain d)
    #|  (:init (= (total-cost) 0))
    #|  (:goal (done))
    #|  (:metric minimize (total-cost)))
  let problem = try! ground(
    parse_domain(domain_source),
    parse_problem(problem_source),
  )
  let source =
    #|(go)
    #|; cost = 1
  let report = validate_plan(problem, source)
  @test.assert_eq(report.valid, false)
  @test.assert_eq(report.issues[0].kind, CostMismatch)
}

///|
test "validate convenience API parses and grounds the model" {
  let source =
    #|(pick-up b)
    #|(stack b c)
    #|(pick-up a)
    #|(stack a b)
  let report = try! validate(
    parse_domain(blocksworld_domain),
    parse_problem(blocksworld_problem),
    source,
  )
  @test.assert_eq(report.valid, true)
  @test.assert_eq(report.cost, 4.0)
}
