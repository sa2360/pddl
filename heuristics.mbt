// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

///|
/// Sentinel for an atom that the delete relaxation cannot reach. Costs are
/// `Int64`, so this value is far above any supported action cost and far
/// below `Int64::max_value()`.
const HEURISTIC_INF : Int64 = 4_000_000_000_000_000_000L

///|
/// Heuristics supported by the planner.
///
/// `HMax` is admissible for non-negative action costs; `HAdd` and `HFF` are
/// informative but may overestimate or underestimate.
pub(all) enum HeuristicKind {
  Blind
  GoalCount
  HMax
  HAdd
  HFF
} derive(Eq, Debug)

///|
pub fn HeuristicKind::parse(text : String) -> HeuristicKind? {
  match text {
    "blind" | "none" => Some(Blind)
    "goal-count" | "goalcount" | "gc" => Some(GoalCount)
    "hmax" | "h-max" | "max" => Some(HMax)
    "hadd" | "h-add" | "add" => Some(HAdd)
    "hff" | "h-ff" | "ff" => Some(HFF)
    _ => None
  }
}

///|
pub fn HeuristicKind::name(self : HeuristicKind) -> String {
  match self {
    Blind => "blind"
    GoalCount => "goal-count"
    HMax => "hmax"
    HAdd => "hadd"
    HFF => "hff"
  }
}

///|
/// One action of the delete-relaxed task. Negative literals are dropped from
/// preconditions and effect conditions; deletions are ignored entirely.
priv struct RelaxedAction {
  pre : Array[Int32]
  adds : Array[Int32]
  cost : Int64
}

///|
/// The delete-relaxed task cached for a whole search. `goal` holds the
/// positive atom ids of every goal disjunct; empty alternatives mean a goal
/// that is trivially true under the relaxation.
priv struct RelaxedTask {
  num_atoms : Int32
  goal : Array[Array[Int32]]
  actions : Array[RelaxedAction]
}

///|
fn positive_atoms(alternative : Array[Literal]) -> Array[Int32] {
  let result : Array[Int32] = []
  for literal in alternative {
    match literal {
      Positive(atom) => result.push(atom)
      Negative(_) => ()
    }
  }
  result
}

///|
fn RelaxedTask::make(problem : GroundProblem) -> RelaxedTask {
  let goal : Array[Array[Int32]] = []
  for alternative in problem.goal {
    goal.push(positive_atoms(alternative))
  }
  let actions : Array[RelaxedAction] = []
  for action in problem.actions {
    for pre_alternative in action.precondition {
      let pre = positive_atoms(pre_alternative)
      for effect in action.effects {
        if effect.adds.length() == 0 {
          continue
        }
        for condition_alternative in effect.condition {
          let combined = pre.copy()
          combined.append(positive_atoms(condition_alternative))
          actions.push({
            pre: combined,
            adds: effect.adds.copy(),
            cost: action.cost,
          })
        }
      }
    }
  }
  { num_atoms: problem.atoms.length(), goal, actions, }
}

///|
fn capped_add(left : Int64, right : Int64) -> Int64 {
  if left < 0L || right < 0L {
    return HEURISTIC_INF
  }
  if left >= HEURISTIC_INF || right >= HEURISTIC_INF {
    return HEURISTIC_INF
  }
  let sum = left + right
  if sum < left || sum >= HEURISTIC_INF {
    HEURISTIC_INF
  } else {
    sum
  }
}

///|
fn initial_costs(task : RelaxedTask, state : State) -> Array[Int64] {
  let costs = Array::make(task.num_atoms, HEURISTIC_INF)
  for atom in 0..<task.num_atoms {
    if state.contains(atom) {
      costs[atom] = 0L
    }
  }
  costs
}

///|
/// Least fixed point of the max-aggregation equations.
fn hmax_costs(task : RelaxedTask, state : State) -> Array[Int64] {
  let costs = initial_costs(task, state)
  let mut changed = true
  while changed {
    changed = false
    for action in task.actions {
      let mut worst = 0L
      let mut reachable = true
      for atom in action.pre {
        let cost = costs[atom]
        if cost >= HEURISTIC_INF {
          reachable = false
          break
        }
        if cost > worst {
          worst = cost
        }
      }
      if reachable {
        let candidate = capped_add(worst, action.cost)
        for atom in action.adds {
          if candidate < costs[atom] {
            costs[atom] = candidate
            changed = true
          }
        }
      }
    }
  }
  costs
}

///|
/// Least fixed point of the additive equations. The second component records
/// the relaxed action that last improved each atom, which `hff` reuses.
fn hadd_costs(
  task : RelaxedTask,
  state : State,
) -> (Array[Int64], Array[Int32]) {
  let costs = initial_costs(task, state)
  let achievers : Array[Int32] = Array::make(task.num_atoms, -1)
  let mut changed = true
  while changed {
    changed = false
    for index in 0..<task.actions.length() {
      let action = task.actions[index]
      let mut total = action.cost
      let mut reachable = true
      for atom in action.pre {
        let cost = costs[atom]
        if cost >= HEURISTIC_INF {
          reachable = false
          break
        }
        total = capped_add(total, cost)
      }
      if reachable {
        for atom in action.adds {
          if total < costs[atom] {
            costs[atom] = total
            achievers[atom] = index
            changed = true
          }
        }
      }
    }
  }
  (costs, achievers)
}

///|
fn goal_max(task : RelaxedTask, costs : Array[Int64]) -> Int64 {
  if task.goal.length() == 0 {
    return -1L
  }
  let mut best = HEURISTIC_INF
  for alternative in task.goal {
    let mut worst = 0L
    let mut reachable = true
    for atom in alternative {
      let cost = costs[atom]
      if cost >= HEURISTIC_INF {
        reachable = false
        break
      }
      if cost > worst {
        worst = cost
      }
    }
    if reachable && worst < best {
      best = worst
    }
  }
  if best >= HEURISTIC_INF {
    -1L
  } else {
    best
  }
}

///|
fn goal_sum(task : RelaxedTask, costs : Array[Int64]) -> Int64 {
  if task.goal.length() == 0 {
    return -1L
  }
  let mut best = HEURISTIC_INF
  for alternative in task.goal {
    let mut total = 0L
    let mut reachable = true
    for atom in alternative {
      let cost = costs[atom]
      if cost >= HEURISTIC_INF {
        reachable = false
        break
      }
      total = capped_add(total, cost)
    }
    if reachable && total < best {
      best = total
    }
  }
  if best >= HEURISTIC_INF {
    -1L
  } else {
    best
  }
}

///|
fn goal_count(problem : GroundProblem, state : State) -> Int32 {
  if problem.goal.length() == 0 {
    return -1
  }
  let mut best = 0
  let mut found = false
  for alternative in problem.goal {
    let mut count = 0
    for literal in alternative {
      let satisfied = match literal {
        Positive(atom) => state.contains(atom)
        Negative(atom) => !state.contains(atom)
      }
      if !satisfied {
        count += 1
      }
    }
    if !found || count < best {
      found = true
      best = count
    }
  }
  if !found {
    -1
  } else {
    best
  }
}

///|
/// Returns the cost of a relaxed plan extracted greedily from the `hadd`
/// supporters, or `-1` if the relaxed goal is unreachable.
fn hff_value(task : RelaxedTask, state : State) -> Int64 {
  let (costs, achievers) = hadd_costs(task, state)
  if task.goal.length() == 0 {
    return -1L
  }
  let mut goal_alternative : Array[Int32] = []
  let mut goal_cost = HEURISTIC_INF
  let mut found = false
  for alternative in task.goal {
    let mut total = 0L
    let mut reachable = true
    for atom in alternative {
      let cost = costs[atom]
      if cost >= HEURISTIC_INF {
        reachable = false
        break
      }
      total = capped_add(total, cost)
    }
    if reachable && (!found || total < goal_cost) {
      found = true
      goal_cost = total
      goal_alternative = alternative
    }
  }
  if !found {
    return -1L
  }
  let achieved : Map[Int32, Bool] = Map([])
  for atom in 0..<task.num_atoms {
    if state.contains(atom) {
      achieved.set(atom, true)
    }
  }
  let selected : Map[Int32, Bool] = Map([])
  let pending : Array[Int32] = []
  for atom in goal_alternative {
    pending.push(atom)
  }
  while pending.length() > 0 {
    let atom = match pending.pop() {
      Some(atom) => atom
      None => break
    }
    if achieved.contains(atom) {
      continue
    }
    let index = achievers[atom]
    if index < 0 {
      return -1L
    }
    selected.set(index, true)
    let action = task.actions[index]
    for add in action.adds {
      achieved.set(add, true)
    }
    for pre in action.pre {
      if !achieved.contains(pre) {
        pending.push(pre)
      }
    }
  }
  let mut total = 0L
  for index in 0..<task.actions.length() {
    if selected.contains(index) {
      total = capped_add(total, task.actions[index].cost)
    }
  }
  if total >= HEURISTIC_INF {
    -1L
  } else {
    total
  }
}

///|
fn estimate(
  kind : HeuristicKind,
  task : RelaxedTask,
  problem : GroundProblem,
  state : State,
) -> Int64 {
  match kind {
    Blind => 0L
    GoalCount => Int64::from_int(goal_count(problem, state))
    HMax => goal_max(task, hmax_costs(task, state))
    HAdd => {
      let (costs, _) = hadd_costs(task, state)
      goal_sum(task, costs)
    }
    HFF => hff_value(task, state)
  }
}

///|
/// Estimates the remaining cost from `state` with the selected heuristic.
/// Returns `-1` when the delete relaxation proves that the goal is
/// unreachable. Useful for inspection and for tests; the planner caches the
/// relaxed task internally.
pub fn heuristic_value(
  problem : GroundProblem,
  kind : HeuristicKind,
  state : State,
) -> Int64 {
  estimate(kind, RelaxedTask::make(problem), problem, state)
}
