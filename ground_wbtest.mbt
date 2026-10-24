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
  @test.assert_eq(problem.funcs.length(), 0)
  for action in problem.actions {
    @test.assert_eq(action.cost, 1.0)
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
  // Self-pairs are dropped by reachability pruning: (not (= a a)) can
  // never hold, so only the 2 ordered distinct pairs remain grounded.
  @test.assert_eq(problem.actions.length(), 2)
  let pair_ab = find_ground_action(problem, "pair", ["a", "b"])
  @test.assert_eq(action_is_applicable(pair_ab, problem.initial), true)
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
  @test.assert_eq(problem.initial_cost, 0.0)
  let finish = find_ground_action(problem, "finish", [])
  let mark_a = find_ground_action(problem, "mark", ["a"])
  let mark_b = find_ground_action(problem, "mark", ["b"])
  @test.assert_eq(finish.cost, 0.0)
  @test.assert_eq(mark_a.cost, 1.0)
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
test "ground numeric fluents with static cost inputs" {
  let problem = try! ground(
    parse_domain(delivery_domain),
    parse_problem(delivery_problem),
  )
  @test.assert_eq(problem.uses_action_costs, true)
  @test.assert_eq(problem.has_metric, true)
  @test.assert_eq(problem.initial_cost, 0.0)
  // Grounding interns every fluent referenced anywhere: fuel t1,
  // fuel-price and all nine distance combinations (self-distances default
  // to 0).
  @test.assert_eq(problem.funcs.length(), 11)
  @test.assert_eq(
    problem.initial.fluent(find_fluent(problem, "(fuel t1)")),
    6.0,
  )
  @test.assert_eq(
    problem.initial.fluent(find_fluent(problem, "(fuel-price)")),
    2.0,
  )
  @test.assert_eq(problem.actions.length(), 12)
  let drive_ab = find_ground_action(problem, "drive", ["t1", "a", "b"])
  // cost = fuel-price * distance(a,b) = 2 * 4
  @test.assert_eq(drive_ab.cost, 8.0)
  let drive_ac = find_ground_action(problem, "drive", ["t1", "a", "c"])
  @test.assert_eq(drive_ac.cost, 18.0)
  let refuel_b = find_ground_action(problem, "refuel", ["t1", "b"])
  @test.assert_eq(refuel_b.cost, 20.0)
  // fuel 6 < distance(a,c) 9: direct drive is not applicable
  @test.assert_eq(action_is_applicable(drive_ab, problem.initial), true)
  @test.assert_eq(action_is_applicable(drive_ac, problem.initial), false)
  let state1 = apply_action(drive_ab, problem.initial)
  @test.assert_eq(state1.fluent(find_fluent(problem, "(fuel t1)")), 2.0)
  @test.assert_eq(action_is_applicable(drive_ac, state1), false)
  let refueled = apply_action(refuel_b, state1)
  @test.assert_eq(refueled.fluent(find_fluent(problem, "(fuel t1)")), 12.0)
  @test.assert_eq(
    action_is_applicable(
      find_ground_action(problem, "drive", ["t1", "c", "a"]),
      refueled,
    ),
    false,
  )
  // (at t1 c) is false, so c -> a stays inapplicable despite enough fuel
  let state2 = apply_action(
    find_ground_action(problem, "drive", ["t1", "b", "c"]),
    refueled,
  )
  @test.assert_eq(state2.fluent(find_fluent(problem, "(fuel t1)")), 9.0)
  @test.assert_eq(problem.goal_holds(state2), true)
}

///|
test "state keys separate different fluent values" {
  let problem = try! ground(
    parse_domain(delivery_domain),
    parse_problem(delivery_problem),
  )
  let drive_ab = find_ground_action(problem, "drive", ["t1", "a", "b"])
  let state1 = apply_action(drive_ab, problem.initial)
  @test.assert_eq(state1.key() != problem.initial.key(), true)
  let refuel_a = find_ground_action(problem, "refuel", ["t1", "a"])
  let state2 = apply_action(refuel_a, state1)
  @test.assert_eq(state2.key() != state1.key(), true)
  // The atom bitset alone cannot distinguish them; the fluent part must.
  @test.assert_eq(state1.key().contains("|"), true)
}

///|
test "numeric effects: assign, scale-up and scale-down" {
  let domain_source =
    #|(define (domain ops)
    #|  (:requirements :fluents :typing)
    #|  (:types t)
    #|  (:predicates (p ?x - t))
    #|  (:functions (f ?x - t) - number)
    #|  (:action assign
    #|    :parameters (?x - t)
    #|    :precondition ()
    #|    :effect (assign (f ?x) 7))
    #|  (:action grow
    #|    :parameters (?x - t)
    #|    :precondition ()
    #|    :effect (and (scale-up (f ?x) 3) (scale-down (f ?x) 2))))
  let problem_source =
    #|(define (problem ops-1)
    #|  (:domain ops)
    #|  (:objects a - t)
    #|  (:init (= (f a) 4))
    #|  (:goal (p a)))
  let problem = try! ground(
    parse_domain(domain_source),
    parse_problem(problem_source),
  )
  let assign = find_ground_action(problem, "assign", ["a"])
  let grow = find_ground_action(problem, "grow", ["a"])
  let f = find_fluent(problem, "(f a)")
  @test.assert_eq(problem.initial.fluent(f), 4.0)
  let s1 = apply_action(assign, problem.initial)
  @test.assert_eq(s1.fluent(f), 7.0)
  let s2 = apply_action(grow, s1)
  // scale-up then scale-down: (7 * 3) / 2 = 10.5
  @test.assert_eq(s2.fluent(f), 10.5)
  // a second assign overrides the scales
  let s3 = apply_action(assign, s2)
  @test.assert_eq(s3.fluent(f), 7.0)
}

///|
test "ground either types" {
  let problem = try! ground(
    parse_domain(either_domain),
    parse_problem(either_problem),
  )
  @test.assert_eq(problem.actions.length(), 2)
  @test.assert_eq(
    action_is_applicable(
      find_ground_action(problem, "grab", ["a"]),
      problem.initial,
    ),
    true,
  )
  @test.assert_eq(
    action_is_applicable(
      find_ground_action(problem, "grab", ["b"]),
      problem.initial,
    ),
    true,
  )
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
test "error: state-dependent action cost" {
  let domain_source =
    #|(define (domain d)
    #|  (:types t)
    #|  (:predicates (p ?x - t))
    #|  (:functions (fuel ?x - t) - number (total-cost) - number)
    #|  (:action a
    #|    :parameters (?x - t)
    #|    :precondition ()
    #|    :effect (and (p ?x) (decrease (fuel ?x) 1)
    #|                 (increase (total-cost) (fuel ?x)))))
  let problem_source =
    #|(define (problem p)
    #|  (:domain d)
    #|  (:objects a - t)
    #|  (:init (= (fuel a) 5))
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
  @test.assert_eq(err.message().contains("state-dependent action cost"), true)
}

///|
test "static function inputs are fine when the function never changes" {
  let domain_source =
    #|(define (domain d)
    #|  (:types t)
    #|  (:predicates (p ?x - t))
    #|  (:functions (price ?x - t) - number (total-cost) - number)
    #|  (:action a
    #|    :parameters (?x - t)
    #|    :precondition ()
    #|    :effect (and (p ?x) (increase (total-cost) (* 2 (price ?x))))))
  let problem_source =
    #|(define (problem p)
    #|  (:domain d)
    #|  (:objects a - t)
    #|  (:init (= (price a) 2.5))
    #|  (:goal (p a))
    #|  (:metric minimize (total-cost)))
  let problem = try! ground(
    parse_domain(domain_source),
    parse_problem(problem_source),
  )
  @test.assert_eq(problem.actions[0].cost, 5.0)
}

///|
test "error: decrease on total-cost" {
  let domain_source =
    #|(define (domain d)
    #|  (:predicates (done))
    #|  (:functions (total-cost) - number)
    #|  (:action a
    #|    :parameters ()
    #|    :precondition ()
    #|    :effect (and (done) (decrease (total-cost) 1))))
  let problem_source =
    #|(define (problem p)
    #|  (:domain d)
    #|  (:init (= (total-cost) 5))
    #|  (:goal (done))
    #|  (:metric minimize (total-cost)))
  let domain = try! parse_domain(domain_source)
  let problem = try! parse_problem(problem_source)
  let err = try {
    ignore(ground(domain, problem))
    abort("expected a grounding error")
  } catch {
    err => err
  }
  @test.assert_eq(
    err.message().contains("total-cost may only be increased"),
    true,
  )
}

///|
test "error: total-cost in a condition" {
  let domain_source =
    #|(define (domain d)
    #|  (:predicates (done))
    #|  (:functions (total-cost) - number)
    #|  (:action a
    #|    :parameters ()
    #|    :precondition (>= (total-cost) 0)
    #|    :effect (done)))
  let problem_source =
    #|(define (problem p)
    #|  (:domain d)
    #|  (:init (= (total-cost) 0))
    #|  (:goal (done)))
  let domain = try! parse_domain(domain_source)
  let problem = try! parse_problem(problem_source)
  let err = try {
    ignore(ground(domain, problem))
    abort("expected a grounding error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("total-cost cannot appear"), true)
}

///|
test "error: action cost above the supported maximum" {
  let domain_source =
    #|(define (domain d)
    #|  (:predicates (done))
    #|  (:functions (total-cost) - number)
    #|  (:action a
    #|    :parameters ()
    #|    :precondition ()
    #|    :effect (and (done)
    #|                 (increase (total-cost) 1000000000000)
    #|                 (increase (total-cost) 1000000000000))))
  let problem_source =
    #|(define (problem p)
    #|  (:domain d)
    #|  (:init (= (total-cost) 0))
    #|  (:goal (done))
    #|  (:metric minimize (total-cost)))
  let domain = try! parse_domain(domain_source)
  let problem = try! parse_problem(problem_source)
  let err = try {
    ignore(ground(domain, problem))
    abort("expected a grounding error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("exceeds the supported maximum"), true)
}

///|
test "error: unknown function" {
  let domain_source =
    #|(define (domain d)
    #|  (:types t)
    #|  (:predicates (p ?x - t))
    #|  (:action a
    #|    :parameters (?x - t)
    #|    :precondition (>= (fuel ?x) 1)
    #|    :effect (p ?x)))
  let problem_source =
    #|(define (problem p)
    #|  (:domain d)
    #|  (:objects a - t)
    #|  (:init)
    #|  (:goal (p a)))
  let domain = try! parse_domain(domain_source)
  let problem = try! parse_problem(problem_source)
  let err = try {
    ignore(ground(domain, problem))
    abort("expected a grounding error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("unknown function 'fuel'"), true)
}

///|
test "error: numeric comparison in the goal is evaluated" {
  let domain_source =
    #|(define (domain d)
    #|  (:predicates (done))
    #|  (:functions (level) - number)
    #|  (:action raise
    #|    :parameters ()
    #|    :precondition ()
    #|    :effect (and (done) (increase (level) 5))))
  let problem_source =
    #|(define (problem p)
    #|  (:domain d)
    #|  (:init (= (level) 1))
    #|  (:goal (and (done) (>= (level) 6))))
  let problem = try! ground(
    parse_domain(domain_source),
    parse_problem(problem_source),
  )
  @test.assert_eq(problem.goal_holds(problem.initial), false)
  let raised = apply_action(problem.actions[0], problem.initial)
  @test.assert_eq(problem.goal_holds(raised), true)
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

///|
test "unreachable actions are pruned by the relaxed reachability filter" {
  let domain_source =
    #|(define (domain d)
    #|  (:types t)
    #|  (:predicates (start) (unreachable) (goal))
    #|  (:functions (level) - number)
    #|  (:action dead
    #|    :parameters ()
    #|    :precondition (unreachable)
    #|    :effect (goal))
    #|  (:action dead-chain
    #|    :parameters ()
    #|    :precondition (goal)
    #|    :effect (and))
    #|  (:action numeric-only
    #|    :parameters ()
    #|    :precondition (>= (level) 0)
    #|    :effect (goal))
    #|  (:action alive
    #|    :parameters ()
    #|    :precondition (start)
    #|    :effect (goal)))
  let problem_source =
    #|(define (problem p)
    #|  (:domain d)
    #|  (:objects a - t)
    #|  (:init (start) (= (level) 1))
    #|  (:goal (goal)))
  let problem = try! ground(
    parse_domain(domain_source),
    parse_problem(problem_source),
  )
  // dead needs (unreachable), which no effect produces, so it is dropped.
  // dead-chain needs (goal), which alive can add: the over-approximation
  // keeps it. alive and the numeric-only action are kept.
  @test.assert_eq(problem.actions.length(), 3)
  ignore(find_ground_action(problem, "alive", []))
  ignore(find_ground_action(problem, "numeric-only", []))
  ignore(find_ground_action(problem, "dead-chain", []))
}
