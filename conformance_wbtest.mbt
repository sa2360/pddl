// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

// Conformance battery for the supported endpoint: PDDL 2.1 Level 1
// (classical with full numeric fluents) plus :action-costs. Each test pins
// one grammatical or semantic rule of the endpoint.

///|
test "functions may share one return type annotation" {
  let domain = try! parse_domain(
    (
      #|(define (domain d)
      #|  (:functions (f) (g) (h ?x) - number)
      #|  (:predicates (p))
      #|  (:action a
      #|    :parameters ()
      #|    :precondition ()
      #|    :effect (p)))
    ),
  )
  @test.assert_eq(domain.functions.length(), 3)
  @test.assert_eq(domain.functions[2].name, "h")
}

///|
test "total-cost works without an explicit :functions declaration" {
  let problem = try! ground(
    parse_domain(
      (
        #|(define (domain d)
        #|  (:requirements :action-costs)
        #|  (:predicates (done))
        #|  (:action go
        #|    :parameters ()
        #|    :precondition ()
        #|    :effect (and (done) (increase (total-cost) 7))))
      ),
    ),
    parse_problem(
      (
        #|(define (problem p)
        #|  (:domain d)
        #|  (:goal (done))
        #|  (:metric minimize (total-cost)))
      ),
    ),
  )
  @test.assert_eq(problem.uses_action_costs, true)
  @test.assert_eq(problem.actions[0].cost, 7.0)
}

///|
test "negated numeric comparisons flip in conditions" {
  let problem = try! ground(
    parse_domain(
      (
        #|(define (domain d)
        #|  (:requirements :fluents)
        #|  (:predicates (low) (high))
        #|  (:functions (level) - number)
        #|  (:action tag-low
        #|    :parameters ()
        #|    :precondition ()
        #|    :effect (when (not (>= (level) 5)) (low)))
        #|  (:action tag-high
        #|    :parameters ()
        #|    :precondition ()
        #|    :effect (when (not (>= (level) 5)) (high))))
      ),
    ),
    parse_problem(
      (
        #|(define (problem p)
        #|  (:domain d)
        #|  (:init (= (level) 3))
        #|  (:goal (low)))
      ),
    ),
  )
  let tag_low = find_ground_action(problem, "tag-low", [])
  let tag_high = find_ground_action(problem, "tag-high", [])
  let state = apply_action(tag_low, problem.initial)
  // (not (>= 3 5)) is true, so both conditional tags fire; a negation bug
  // would leave both conditions false.
  @test.assert_eq(state.contains(find_atom(problem, "(low)")), true)
  @test.assert_eq(state.contains(find_atom(problem, "(high)")), false)
  let state_high = apply_action(tag_high, problem.initial)
  @test.assert_eq(state_high.contains(find_atom(problem, "(high)")), true)
}

///|
test "imply combines numeric and propositional parts" {
  let problem = try! ground(
    parse_domain(
      (
        #|(define (domain d)
        #|  (:requirements :disjunctive-preconditions :fluents)
        #|  (:predicates (p) (q))
        #|  (:functions (level) - number)
        #|  (:action a
        #|    :parameters ()
        #|    :precondition (imply (p) (> (level) 2))
        #|    :effect (q)))
      ),
    ),
    parse_problem(
      (
        #|(define (problem p)
        #|  (:domain d)
        #|  (:init (p) (= (level) 1))
        #|  (:goal (q)))
      ),
    ),
  )
  let action = problem.actions[0]
  // p holds but (level > 2) fails, so the implication is false.
  @test.assert_eq(action_is_applicable(action, problem.initial), false)
}

///|
test "either types in constants restrict grounding" {
  let domain = try! parse_domain(
    (
      #|(define (domain d)
      #|  (:types box ball)
      #|  (:constants b1 - box k1 - ball)
      #|  (:predicates (holds ?x - (either box ball)))
      #|  (:action grab
      #|    :parameters (?x - (either box ball))
      #|    :precondition ()
      #|    :effect (holds ?x)))
    ),
  )
  @test.assert_eq(domain.constants[0].types, ["box"])
  let problem = try! ground(
    domain,
    parse_problem(
      (
        #|(define (problem p)
        #|  (:domain d)
        #|  (:objects k2 - ball)
        #|  (:init)
        #|  (:goal (holds k2)))
      ),
    ),
  )
  // b1, k1, k2 are all grabbable; 3 ground actions.
  @test.assert_eq(problem.actions.length(), 3)
}

///|
test "strict comparisons at the boundary" {
  let problem = try! ground(
    parse_domain(
      (
        #|(define (domain d)
        #|  (:requirements :fluents)
        #|  (:predicates (p) (q) (r))
        #|  (:functions (f) - number)
        #|  (:action a
        #|    :parameters ()
        #|    :precondition (and (>= (f) 0.5) (<= (f) 0.5))
        #|    :effect (p))
        #|  (:action b
        #|    :parameters ()
        #|    :precondition (< (f) 0.5)
        #|    :effect (q))
        #|  (:action c
        #|    :parameters ()
        #|    :precondition (> (f) 0.5)
        #|    :effect (r)))
      ),
    ),
    parse_problem(
      (
        #|(define (problem p)
        #|  (:domain d)
        #|  (:init (= (f) 0.5))
        #|  (:goal (or (p) (q) (r))))
      ),
    ),
  )
  let a = find_ground_action(problem, "a", [])
  let b = find_ground_action(problem, "b", [])
  let c = find_ground_action(problem, "c", [])
  // f = 0.5: >= and <= hold at the boundary; > and < do not.
  @test.assert_eq(action_is_applicable(a, problem.initial), true)
  @test.assert_eq(action_is_applicable(b, problem.initial), false)
  @test.assert_eq(action_is_applicable(c, problem.initial), false)
}

///|
test "scale-down by zero leaves the fluent unchanged" {
  let problem = try! ground(
    parse_domain(
      (
        #|(define (domain d)
        #|  (:requirements :fluents)
        #|  (:predicates (p))
        #|  (:functions (f) - number)
        #|  (:action halve
        #|    :parameters ()
        #|    :precondition ()
        #|    :effect (and (p) (scale-down (f) 0))))
      ),
    ),
    parse_problem(
      (
        #|(define (problem p)
        #|  (:domain d)
        #|  (:init (= (f) 8))
        #|  (:goal (p)))
      ),
    ),
  )
  let f = find_fluent(problem, "(f)")
  let state = apply_action(problem.actions[0], problem.initial)
  @test.assert_eq(state.fluent(f), 8.0)
}

///|
test "division by zero in a condition evaluates to zero" {
  let problem = try! ground(
    parse_domain(
      (
        #|(define (domain d)
        #|  (:requirements :fluents)
        #|  (:predicates (p))
        #|  (:functions (f) - number)
        #|  (:action a
        #|    :parameters ()
        #|    :precondition (> (/ (f) 0) 1)
        #|    :effect (p)))
      ),
    ),
    parse_problem(
      (
        #|(define (problem p)
        #|  (:domain d)
        #|  (:init (= (f) 5))
        #|  (:goal (p)))
      ),
    ),
  )
  // 5 / 0 evaluates to 0, and 0 > 1 is false.
  @test.assert_eq(
    action_is_applicable(problem.actions[0], problem.initial),
    false,
  )
}

///|
test "arithmetic in init assignments and negative fluents" {
  let problem = try! ground(
    parse_domain(
      (
        #|(define (domain d)
        #|  (:requirements :fluents)
        #|  (:predicates (p))
        #|  (:functions (balance) - number)
        #|  (:action spend
        #|    :parameters ()
        #|    :precondition (>= (balance) 10)
        #|    :effect (decrease (balance) 10)))
      ),
    ),
    parse_problem(
      (
        #|(define (problem p)
        #|  (:domain d)
        #|  (:init (= (balance) 25.5))
        #|  (:goal (p))
        #|  (:metric minimize (total-cost)))
      ),
    ),
  )
  let balance = find_fluent(problem, "(balance)")
  @test.assert_eq(problem.initial.fluent(balance), 25.5)
  let s1 = apply_action(problem.actions[0], problem.initial)
  @test.assert_eq(s1.fluent(balance), 15.5)
  let s2 = apply_action(problem.actions[0], s1)
  @test.assert_eq(s2.fluent(balance), 5.5)
  // 5.5 < 10: the third spend is not applicable.
  @test.assert_eq(action_is_applicable(problem.actions[0], s2), false)
}

///|
test "quantified preconditions combine with numeric constraints" {
  let problem = try! ground(
    parse_domain(
      (
        #|(define (domain d)
        #|  (:requirements :universal-preconditions :fluents)
        #|  (:types t)
        #|  (:predicates (p ?x - t))
        #|  (:functions (level ?x - t) - number)
        #|  (:action all-ready
        #|    :parameters ()
        #|    :precondition (forall (?x - t) (>= (level ?x) 3))
        #|    :effect (and)))
      ),
    ),
    parse_problem(
      (
        #|(define (problem p)
        #|  (:domain d)
        #|  (:objects a b - t)
        #|  (:init (= (level a) 3) (= (level b) 2))
        #|  (:goal (and)))
      ),
    ),
  )
  let action = find_ground_action(problem, "all-ready", [])
  @test.assert_eq(action_is_applicable(action, problem.initial), false)
}

///|
test "numeric equality and inequality" {
  let problem = try! ground(
    parse_domain(
      (
        #|(define (domain d)
        #|  (:requirements :fluents)
        #|  (:predicates (p) (q))
        #|  (:functions (f) - number)
        #|  (:action a
        #|    :parameters ()
        #|    :precondition (= (f) 3)
        #|    :effect (p))
        #|  (:action b
        #|    :parameters ()
        #|    :precondition (not (= (f) 3))
        #|    :effect (q)))
      ),
    ),
    parse_problem(
      (
        #|(define (problem p)
        #|  (:domain d)
        #|  (:init (= (f) 3))
        #|  (:goal (and)))
      ),
    ),
  )
  @test.assert_eq(
    action_is_applicable(find_ground_action(problem, "a", []), problem.initial),
    true,
  )
  @test.assert_eq(
    action_is_applicable(find_ground_action(problem, "b", []), problem.initial),
    false,
  )
}

///|
test "deep formula nesting raises a clean error instead of crashing" {
  let mut body = "(p)"
  let mut i = 0
  while i < 500 {
    body = "(and \{body})"
    i += 1
  }
  let domain = "(define (domain deep) (:predicates (p)) (:action a :parameters () :precondition \{body} :effect (and)))"
  let err = try {
    ignore(parse_domain(domain))
    abort("expected a parse error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("nesting exceeds"), true)
}

///|
test "deep numeric nesting raises a clean error instead of crashing" {
  let mut body = "(f)"
  let mut i = 0
  while i < 500 {
    body = "(+ \{body} 1)"
    i += 1
  }
  let domain = "(define (domain deep) (:functions (f) - number) (:action a :parameters () :precondition (>= \{body} 0) :effect (and)))"
  let err = try {
    ignore(parse_domain(domain))
    abort("expected a parse error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("nesting exceeds"), true)
}

///|
test "deep effect nesting raises a clean error instead of crashing" {
  let mut body = "(done)"
  let mut i = 0
  while i < 500 {
    body = "(and \{body})"
    i += 1
  }
  let domain = "(define (domain deep) (:predicates (done)) (:action a :parameters () :precondition () :effect \{body}))"
  let err = try {
    ignore(parse_domain(domain))
    abort("expected a parse error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("nesting exceeds"), true)
}

///|
test "moderately deep formulas still parse and ground" {
  let mut body = "(p)"
  let mut i = 0
  while i < 100 {
    body = "(and \{body})"
    i += 1
  }
  let domain = try! parse_domain(
    "(define (domain deep) (:predicates (p)) (:action a :parameters () :precondition \{body} :effect (and)))",
  )
  let problem = try! ground(
    domain,
    parse_problem(
      "(define (problem deep1) (:domain deep) (:init (p)) (:goal (p)))",
    ),
  )
  // 100 nested ands collapse to a single-literal DNF.
  @test.assert_eq(problem.actions[0].precondition.length(), 1)
  @test.assert_eq(problem.actions[0].precondition[0].length(), 1)
}
