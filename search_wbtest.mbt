// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

///|
fn assert_plan_valid(problem : GroundProblem, plan : Array[Int32]) -> Unit {
  let mut state = problem.initial.copy()
  for id in plan {
    let action = problem.actions[id]
    if !action_is_applicable(action, state) {
      abort("plan step is not applicable: \{action.render()}")
    }
    state = apply_action(action, state)
  }
  if !problem.goal_holds(state) {
    abort("plan does not reach the goal")
  }
}

///|
test "heuristics on blocksworld" {
  let problem = try! ground(
    parse_domain(blocksworld_domain),
    parse_problem(blocksworld_problem),
  )
  @test.assert_eq(heuristic_value(problem, Blind, problem.initial), 0.0)
  @test.assert_eq(heuristic_value(problem, GoalCount, problem.initial), 2.0)
  @test.assert_eq(heuristic_value(problem, HMax, problem.initial), 2.0)
  @test.assert_eq(heuristic_value(problem, HAdd, problem.initial), 4.0)
  @test.assert_eq(heuristic_value(problem, HFF, problem.initial), 4.0)
  let pick_b = find_ground_action(problem, "pick-up", ["b"])
  let stack_bc = find_ground_action(problem, "stack", ["b", "c"])
  let pick_a = find_ground_action(problem, "pick-up", ["a"])
  let stack_ab = find_ground_action(problem, "stack", ["a", "b"])
  let mut state = apply_action(pick_b, problem.initial)
  state = apply_action(stack_bc, state)
  state = apply_action(pick_a, state)
  state = apply_action(stack_ab, state)
  @test.assert_eq(problem.goal_holds(state), true)
  let kinds : Array[HeuristicKind] = [Blind, GoalCount, HMax, HAdd, HFF]
  for kind in kinds {
    @test.assert_eq(heuristic_value(problem, kind, state), 0.0)
  }
}

///|
test "a-star with hmax is optimal on blocksworld" {
  let problem = try! ground(
    parse_domain(blocksworld_domain),
    parse_problem(blocksworld_problem),
  )
  let blind = solve(problem, Blind, AStar)
  let informed = solve(problem, HMax, AStar)
  @test.assert_eq(blind.status, Solved)
  @test.assert_eq(informed.status, Solved)
  @test.assert_eq(blind.cost, 4.0)
  @test.assert_eq(informed.cost, blind.cost)
  @test.assert_eq(informed.plan.length(), 4)
  @test.assert_eq(informed.is_solved(), true)
  assert_plan_valid(problem, informed.plan)
  let rendered = informed.render_plan(problem)
  @test.assert_eq(rendered.contains("(stack a b)"), true)
  @test.assert_eq(rendered.contains("(stack b c)"), true)
}

///|
test "greedy best first finds a valid blocksworld plan" {
  let problem = try! ground(
    parse_domain(blocksworld_domain),
    parse_problem(blocksworld_problem),
  )
  let result = solve(problem, HFF, GBFS)
  @test.assert_eq(result.status, Solved)
  @test.assert_eq(result.expanded > 0, true)
  @test.assert_eq(result.cost > 0.0, true)
  assert_plan_valid(problem, result.plan)
}

///|
test "weighted a-star solves a cost domain" {
  let problem = try! ground(
    parse_domain(conditional_domain),
    parse_problem(conditional_problem),
  )
  let optimal = solve(problem, HMax, AStar)
  @test.assert_eq(optimal.status, Solved)
  @test.assert_eq(optimal.cost, 2.0)
  @test.assert_eq(optimal.plan.length(), 3)
  assert_plan_valid(problem, optimal.plan)
  let weighted = solve(problem, HFF, WeightedAStar(3))
  @test.assert_eq(weighted.status, Solved)
  @test.assert_eq(weighted.cost, 2.0)
  assert_plan_valid(problem, weighted.plan)
}

///|
test "search includes the initial total cost" {
  let domain_source =
    #|(define (domain cost-demo)
    #|  (:requirements :strips :action-costs)
    #|  (:predicates (done))
    #|  (:functions (total-cost) - number)
    #|  (:action finish
    #|    :parameters ()
    #|    :precondition ()
    #|    :effect (and (done) (increase (total-cost) 3))))
  let problem_source =
    #|(define (problem cost-1)
    #|  (:domain cost-demo)
    #|  (:init (= (total-cost) 7))
    #|  (:goal (done))
    #|  (:metric minimize (total-cost)))
  let problem = try! ground(
    parse_domain(domain_source),
    parse_problem(problem_source),
  )
  let result = solve(problem, HMax, AStar)
  @test.assert_eq(result.status, Solved)
  @test.assert_eq(result.cost, 10.0)
  @test.assert_eq(result.plan.length(), 1)
  assert_plan_valid(problem, result.plan)
}

///|
test "action costs beyond 32 bits stay exact" {
  let domain_source =
    #|(define (domain big-cost)
    #|  (:requirements :strips :action-costs)
    #|  (:predicates (done))
    #|  (:functions (total-cost) - number)
    #|  (:action finish
    #|    :parameters ()
    #|    :precondition ()
    #|    :effect (and (done)
    #|                 (increase (total-cost) 1000000000)
    #|                 (increase (total-cost) 1000000000)
    #|                 (increase (total-cost) 1000000000))))
  let problem_source =
    #|(define (problem big-cost-1)
    #|  (:domain big-cost)
    #|  (:init (= (total-cost) 0))
    #|  (:goal (done))
    #|  (:metric minimize (total-cost)))
  let problem = try! ground(
    parse_domain(domain_source),
    parse_problem(problem_source),
  )
  @test.assert_eq(problem.actions[0].cost, 3000000000.0)
  let result = solve(problem, HMax, AStar)
  @test.assert_eq(result.status, Solved)
  @test.assert_eq(result.cost, 3000000000.0)
}

///|
test "sentinel-sized action costs remain reachable" {
  let domain_source =
    #|(define (domain billion-cost)
    #|  (:requirements :strips :action-costs)
    #|  (:predicates (done))
    #|  (:functions (total-cost) - number)
    #|  (:action finish
    #|    :parameters ()
    #|    :precondition ()
    #|    :effect (and (done) (increase (total-cost) 1000000000))))
  let problem_source =
    #|(define (problem billion-cost-1)
    #|  (:domain billion-cost)
    #|  (:init (= (total-cost) 1000000009))
    #|  (:goal (done))
    #|  (:metric minimize (total-cost)))
  let problem = try! ground(
    parse_domain(domain_source),
    parse_problem(problem_source),
  )
  let result = solve(problem, HFF, AStar)
  @test.assert_eq(result.status, Solved)
  @test.assert_eq(result.cost, 2000000009.0)
  @test.assert_eq(result.plan.length(), 1)
}

///|
test "cumulative plan cost is not capped" {
  let domain_source =
    #|(define (domain two-step-cost)
    #|  (:requirements :strips :action-costs)
    #|  (:predicates (middle) (done))
    #|  (:functions (total-cost) - number)
    #|  (:action first
    #|    :parameters ()
    #|    :precondition ()
    #|    :effect (and (middle) (increase (total-cost) 600000000)))
    #|  (:action second
    #|    :parameters ()
    #|    :precondition (middle)
    #|    :effect (and (done) (increase (total-cost) 600000000))))
  let problem_source =
    #|(define (problem two-step-cost-1)
    #|  (:domain two-step-cost)
    #|  (:init (= (total-cost) 0))
    #|  (:goal (done))
    #|  (:metric minimize (total-cost)))
  let problem = try! ground(
    parse_domain(domain_source),
    parse_problem(problem_source),
  )
  let result = solve(problem, HFF, AStar)
  @test.assert_eq(result.status, Solved)
  @test.assert_eq(result.cost, 1200000000.0)
  @test.assert_eq(result.plan.length(), 2)
}

///|
test "greedy best first orders by h, not by g plus h" {
  let domain_source =
    #|(define (domain gbfs-demo)
    #|  (:requirements :strips :action-costs)
    #|  (:predicates (start) (p) (done))
    #|  (:functions (total-cost) - number)
    #|  (:action expensive
    #|    :parameters ()
    #|    :precondition (start)
    #|    :effect (and (done) (increase (total-cost) 100)))
    #|  (:action begin-cheap
    #|    :parameters ()
    #|    :precondition (start)
    #|    :effect (and (p) (increase (total-cost) 1)))
    #|  (:action finish-cheap
    #|    :parameters ()
    #|    :precondition (p)
    #|    :effect (and (done) (increase (total-cost) 10))))
  let problem_source =
    #|(define (problem gbfs-demo-1)
    #|  (:domain gbfs-demo)
    #|  (:init (start) (= (total-cost) 0))
    #|  (:goal (done))
    #|  (:metric minimize (total-cost)))
  let problem = try! ground(
    parse_domain(domain_source),
    parse_problem(problem_source),
  )
  let greedy = solve(problem, HFF, GBFS)
  @test.assert_eq(greedy.status, Solved)
  @test.assert_eq(greedy.cost, 100.0)
  @test.assert_eq(greedy.plan.length(), 1)
  let optimal = solve(problem, HFF, AStar)
  @test.assert_eq(optimal.status, Solved)
  @test.assert_eq(optimal.cost, 11.0)
}

///|
test "numeric action costs from static functions search optimally" {
  let problem = try! ground(
    parse_domain(delivery_domain),
    parse_problem(delivery_problem),
  )
  // Optimum: refuel (2 * 10) + drive a->b (2 * 4) + drive b->c (2 * 3) = 34.
  let optimal = solve(problem, HMax, AStar)
  @test.assert_eq(optimal.status, Solved)
  @test.assert_eq(optimal.cost, 34.0)
  @test.assert_eq(optimal.plan.length(), 3)
  assert_plan_valid(problem, optimal.plan)
  let greedy = solve(problem, HFF, GBFS)
  @test.assert_eq(greedy.status, Solved)
  assert_plan_valid(problem, greedy.plan)
}

///|
test "numeric preconditions gate applicability during search" {
  let domain_source =
    #|(define (domain gated)
    #|  (:requirements :fluents)
    #|  (:predicates (done))
    #|  (:functions (charge) - number)
    #|  (:action fire
    #|    :parameters ()
    #|    :precondition (>= (charge) 10)
    #|    :effect (done))
    #|  (:action charge-up
    #|    :parameters ()
    #|    :precondition ()
    #|    :effect (increase (charge) 5)))
  let problem_source =
    #|(define (problem gated-1)
    #|  (:domain gated)
    #|  (:init (= (charge) 0))
    #|  (:goal (done)))
  let problem = try! ground(
    parse_domain(domain_source),
    parse_problem(problem_source),
  )
  let result = solve(problem, HMax, AStar)
  @test.assert_eq(result.status, Solved)
  @test.assert_eq(result.plan.length(), 3)
  assert_plan_valid(problem, result.plan)
}

///|
test "goal that already holds yields an empty plan" {
  let problem_source =
    #|(define (problem blocks-empty)
    #|  (:domain blocksworld)
    #|  (:objects a - block)
    #|  (:init)
    #|  (:goal (and)))
  let problem = try! ground(
    parse_domain(blocksworld_domain),
    parse_problem(problem_source),
  )
  let result = solve(problem, HMax, AStar)
  @test.assert_eq(result.status, Solved)
  @test.assert_eq(result.plan.length(), 0)
  @test.assert_eq(result.cost, 0.0)
  @test.assert_eq(result.expanded, 0)
}

///|
test "unreachable goal is detected by the relaxation" {
  let domain_source =
    #|(define (domain dead-end)
    #|  (:requirements :strips)
    #|  (:predicates (q))
    #|  (:action wait
    #|    :parameters ()
    #|    :precondition ()
    #|    :effect (and)))
  let problem_source =
    #|(define (problem dead-end-1)
    #|  (:domain dead-end)
    #|  (:init)
    #|  (:goal (q)))
  let problem = try! ground(
    parse_domain(domain_source),
    parse_problem(problem_source),
  )
  @test.assert_eq(heuristic_value(problem, HMax, problem.initial), -1.0)
  @test.assert_eq(heuristic_value(problem, HAdd, problem.initial), -1.0)
  @test.assert_eq(heuristic_value(problem, HFF, problem.initial), -1.0)
  @test.assert_eq(heuristic_value(problem, GoalCount, problem.initial), 1.0)
  let informed = solve(problem, HMax, GBFS)
  @test.assert_eq(informed.status, Exhausted)
  @test.assert_eq(informed.generated, 1)
  let blind = solve(problem, Blind, AStar)
  @test.assert_eq(blind.status, Exhausted)
  @test.assert_eq(blind.expanded, 1)
}

///|
test "search reports node limits" {
  let problem = try! ground(
    parse_domain(blocksworld_domain),
    parse_problem(blocksworld_problem),
  )
  let result = solve(problem, HMax, AStar, max_expanded=0)
  @test.assert_eq(result.status, NodeLimitReached)
  @test.assert_eq(result.expanded, 0)
  @test.assert_eq(result.plan.length(), 0)
}

///|
test "heuristic and algorithm names parse" {
  @test.assert_eq(HeuristicKind::parse("hmax"), Some(HMax))
  @test.assert_eq(HeuristicKind::parse("ff"), Some(HFF))
  @test.assert_eq(HeuristicKind::parse("unknown"), None)
  @test.assert_eq(SearchAlgorithm::parse("astar"), Some(AStar))
  @test.assert_eq(SearchAlgorithm::parse("wastar"), Some(WeightedAStar(5)))
  @test.assert_eq(SearchAlgorithm::parse("unknown"), None)
  let hmax : HeuristicKind = HMax
  @test.assert_eq(hmax.name(), "hmax")
  let weighted : SearchAlgorithm = WeightedAStar(3)
  @test.assert_eq(weighted.name(), "wastar(3)")
}
