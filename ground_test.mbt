// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

///|
test "ground blocksworld" {
  let problem = try! ground(
    parse_domain(blocksworld_domain),
    parse_problem(blocksworld_problem),
  )
  @test.assert_eq(problem.objects.length(), 3)
  @test.assert_eq(problem.actions.length(), 24)
  @test.assert_eq(problem.initial.num_true(), 7)
  @test.assert_eq(problem.uses_action_costs, false)
  @test.assert_eq(problem.has_metric, false)
  for action in problem.actions {
    @test.assert_eq(action.cost, 1)
  }
  @test.assert_eq(problem.goal_holds(problem.initial), false)
  @test.assert_eq(problem.initial.key(), problem.initial.copy().key())
  let holding_b = find_atom(problem, "(holding b)")
  let ontable_b = find_atom(problem, "(ontable b)")
  let pick_b = find_ground_action(problem, "pick-up", ["b"])
  @test.assert_eq(action_is_applicable(pick_b, problem.initial), true)
  let state1 = apply_action(pick_b, problem.initial)
  @test.assert_eq(state1.contains(holding_b), true)
  @test.assert_eq(state1.contains(ontable_b), false)
  @test.assert_eq(state1.key() != problem.initial.key(), true)
  let stack_bc = find_ground_action(problem, "stack", ["b", "c"])
  let state2 = apply_action(stack_bc, state1)
  let pick_a = find_ground_action(problem, "pick-up", ["a"])
  let state3 = apply_action(pick_a, state2)
  let stack_ab = find_ground_action(problem, "stack", ["a", "b"])
  let state4 = apply_action(stack_ab, state3)
  @test.assert_eq(problem.goal_holds(state4), true)
  @test.assert_eq(state4.contains(find_atom(problem, "(on a b)")), true)
  @test.assert_eq(state4.contains(find_atom(problem, "(on b c)")), true)
}

///|
test "ground quantifiers" {
  let problem = try! ground(
    parse_domain(quantifier_domain),
    parse_problem(quantifier_problem),
  )
  let mark_all = find_ground_action(problem, "mark-all", [])
  let mark_some = find_ground_action(problem, "mark-some", [])
  @test.assert_eq(mark_all.precondition.length(), 1)
  @test.assert_eq(mark_all.precondition[0].length(), 2)
  @test.assert_eq(mark_all.effects.length(), 2)
  @test.assert_eq(action_is_applicable(mark_all, problem.initial), true)
  @test.assert_eq(action_is_applicable(mark_some, problem.initial), false)
  let state = apply_action(mark_all, problem.initial)
  @test.assert_eq(problem.goal_holds(state), true)
  @test.assert_eq(action_is_applicable(mark_some, state), true)
  @test.assert_eq(action_is_applicable(mark_all, state), false)
}

///|
test "ground equality" {
  let problem = try! ground(
    parse_domain(equality_domain),
    parse_problem(equality_problem),
  )
  @test.assert_eq(problem.actions.length(), 4)
  let pair_ab = find_ground_action(problem, "pair", ["a", "b"])
  let pair_aa = find_ground_action(problem, "pair", ["a", "a"])
  @test.assert_eq(action_is_applicable(pair_ab, problem.initial), true)
  @test.assert_eq(action_is_applicable(pair_aa, problem.initial), false)
  @test.assert_eq(problem.goal_holds(problem.initial), false)
  let state = apply_action(pair_ab, problem.initial)
  @test.assert_eq(problem.goal_holds(state), true)
}

///|
test "ground conditional effects and costs" {
  let problem = try! ground(
    parse_domain(conditional_domain),
    parse_problem(conditional_problem),
  )
  @test.assert_eq(problem.actions.length(), 3)
  @test.assert_eq(problem.uses_action_costs, true)
  @test.assert_eq(problem.has_metric, true)
  @test.assert_eq(problem.initial_cost, 0)
  let finish = find_ground_action(problem, "finish", [])
  let mark_a = find_ground_action(problem, "mark", ["a"])
  let mark_b = find_ground_action(problem, "mark", ["b"])
  @test.assert_eq(finish.cost, 0)
  @test.assert_eq(mark_a.cost, 1)
  @test.assert_eq(finish.effects.length(), 1)
  @test.assert_eq(finish.effects[0].condition.length(), 1)
  @test.assert_eq(finish.effects[0].condition[0].length(), 2)
  let state0 = problem.initial
  let after_finish = apply_action(finish, state0)
  @test.assert_eq(problem.goal_holds(after_finish), false)
  let state1 = apply_action(mark_a, state0)
  @test.assert_eq(action_is_applicable(mark_a, state1), false)
  let state2 = apply_action(mark_b, state1)
  @test.assert_eq(problem.goal_holds(state2), false)
  let state3 = apply_action(finish, state2)
  @test.assert_eq(problem.goal_holds(state3), true)
  let done = find_atom(problem, "(done)")
  @test.assert_eq(state2.contains(done), false)
  @test.assert_eq(state3.contains(done), true)
}

///|
test "goal disjunction holds if one branch holds" {
  let source =
    #|(define (problem disjunctive)
    #|  (:domain quantifier-demo)
    #|  (:objects a b - item)
    #|  (:init (marked a))
    #|  (:goal (or (marked a) (marked b))))
  let problem = try! ground(
    parse_domain(quantifier_domain),
    parse_problem(source),
  )
  @test.assert_eq(problem.goal.length(), 2)
  @test.assert_eq(problem.goal_holds(problem.initial), true)
}

///|
test "error: unknown predicate in init" {
  let domain_source =
    #|(define (domain d)
    #|  (:types t)
    #|  (:predicates (p ?x - t)))
  let problem_source =
    #|(define (problem p)
    #|  (:domain d)
    #|  (:objects a - t)
    #|  (:init (q a))
    #|  (:goal (p a)))
  let domain = try! parse_domain(domain_source)
  let problem = try! parse_problem(problem_source)
  let err = try {
    ignore(ground(domain, problem))
    abort("expected a grounding error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("unknown predicate 'q'"), true)
}

///|
test "error: predicate argument type mismatch" {
  let domain_source =
    #|(define (domain d)
    #|  (:types block table)
    #|  (:predicates (on ?x - block)))
  let problem_source =
    #|(define (problem p)
    #|  (:domain d)
    #|  (:objects t1 - table)
    #|  (:init (on t1))
    #|  (:goal (on t1)))
  let domain = try! parse_domain(domain_source)
  let problem = try! parse_problem(problem_source)
  let err = try {
    ignore(ground(domain, problem))
    abort("expected a grounding error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("expects argument 1"), true)
  @test.assert_eq(err.message().contains("table"), true)
}

///|
test "error: duplicate object across domain and problem" {
  let domain_source =
    #|(define (domain d)
    #|  (:types t)
    #|  (:constants a - t)
    #|  (:predicates (p ?x - t)))
  let problem_source =
    #|(define (problem p)
    #|  (:domain d)
    #|  (:objects a - t)
    #|  (:init (p a))
    #|  (:goal (p a)))
  let domain = try! parse_domain(domain_source)
  let problem = try! parse_problem(problem_source)
  let err = try {
    ignore(ground(domain, problem))
    abort("expected a grounding error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("declared more than once"), true)
}

///|
test "error: conditional action cost" {
  let domain_source =
    #|(define (domain d)
    #|  (:types t)
    #|  (:predicates (p ?x - t))
    #|  (:functions (total-cost) - number)
    #|  (:action a
    #|    :parameters (?x - t)
    #|    :precondition ()
    #|    :effect (when (p ?x) (increase (total-cost) 1))))
  let problem_source =
    #|(define (problem p)
    #|  (:domain d)
    #|  (:objects a - t)
    #|  (:init (= (total-cost) 0))
    #|  (:goal (p a))
    #|  (:metric minimize (total-cost)))
  let domain = try! parse_domain(domain_source)
  let problem = try! parse_problem(problem_source)
  let err = try {
    ignore(ground(domain, problem))
    abort("expected a grounding error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("conditional action cost"), true)
}

///|
test "error: problem targets another domain" {
  let domain_source =
    #|(define (domain d1)
    #|  (:predicates (p)))
  let problem_source =
    #|(define (problem p)
    #|  (:domain d2)
    #|  (:init (p))
    #|  (:goal (p)))
  let domain = try! parse_domain(domain_source)
  let problem = try! parse_problem(problem_source)
  let err = try {
    ignore(ground(domain, problem))
    abort("expected a grounding error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("targets domain"), true)
}
