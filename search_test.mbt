// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

///|
fn assert_plan_valid(problem : GroundProblem, plan : Array[Int]) -> Unit {
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
  @test.assert_eq(heuristic_value(problem, Blind, problem.initial), 0)
  @test.assert_eq(heuristic_value(problem, GoalCount, problem.initial), 2)
  @test.assert_eq(heuristic_value(problem, HMax, problem.initial), 2)
  @test.assert_eq(heuristic_value(problem, HAdd, problem.initial), 4)
  @test.assert_eq(heuristic_value(problem, HFF, problem.initial), 4)
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
    @test.assert_eq(heuristic_value(problem, kind, state), 0)
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
  @test.assert_eq(blind.cost, 4)
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
  @test.assert_eq(result.cost > 0, true)
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
  @test.assert_eq(optimal.cost, 2)
  @test.assert_eq(optimal.plan.length(), 3)
  assert_plan_valid(problem, optimal.plan)
  let weighted = solve(problem, HFF, WeightedAStar(3))
  @test.assert_eq(weighted.status, Solved)
  @test.assert_eq(weighted.cost, 2)
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
  @test.assert_eq(result.cost, 10)
  @test.assert_eq(result.plan.length(), 1)
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
  @test.assert_eq(result.cost, 0)
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
  @test.assert_eq(heuristic_value(problem, HMax, problem.initial), -1)
  @test.assert_eq(heuristic_value(problem, HAdd, problem.initial), -1)
  @test.assert_eq(heuristic_value(problem, HFF, problem.initial), -1)
  @test.assert_eq(heuristic_value(problem, GoalCount, problem.initial), 1)
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
