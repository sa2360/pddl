// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

///|
/// Search strategies. `AStar` is optimal when the heuristic is admissible
/// (for example `HMax`); `GBFS` and `WeightedAStar` trade optimality for
/// speed.
pub(all) enum SearchAlgorithm {
  GBFS
  AStar
  WeightedAStar(Int32)
} derive(Eq, Debug)

///|
pub fn SearchAlgorithm::parse(text : String) -> SearchAlgorithm? {
  match text {
    "gbfs" | "greedy" | "greedy-best-first" => Some(GBFS)
    "astar" | "a-star" | "a*" => Some(AStar)
    "wastar" | "weighted-astar" | "weighted" => Some(WeightedAStar(5))
    _ => None
  }
}

///|
pub fn SearchAlgorithm::name(self : SearchAlgorithm) -> String {
  match self {
    GBFS => "gbfs"
    AStar => "astar"
    WeightedAStar(weight) => "wastar(\{weight})"
  }
}

///|
/// Why a search stopped.
pub(all) enum SearchStatus {
  Solved
  Exhausted
  NodeLimitReached
} derive(Eq, Debug)

///|
/// The outcome of a search. `plan` holds indices into
/// `GroundProblem::actions`; `cost` includes the problem's initial
/// total-cost value.
pub(all) struct SearchResult {
  status : SearchStatus
  plan : Array[Int32]
  cost : Int64
  expanded : Int32
  generated : Int32
} derive(Debug)

///|
pub fn SearchResult::is_solved(self : SearchResult) -> Bool {
  match self.status {
    Solved => true
    _ => false
  }
}

///|
/// Renders a plan as one `(action args)` line per step.
pub fn SearchResult::render_plan(
  self : SearchResult,
  problem : GroundProblem,
) -> String {
  let sb = StringBuilder::StringBuilder()
  for id in self.plan {
    if id >= 0 && id < problem.actions.length() {
      sb.write_string(problem.actions[id].render())
      sb.write_char('\n')
    }
  }
  sb.to_string()
}

///|
priv struct SearchNode {
  state : State
  parent : Int32
  action : Int32
  g : Int64
  h : Int64
}

///|
priv struct OpenEntry {
  node : Int32
  f : Int64
  h : Int64
  g : Int64
  order : Int32
}

///|
priv struct OpenList {
  items : Array[OpenEntry]
}

///|
fn OpenList::make() -> OpenList {
  { items: [], }
}

///|
fn open_entry_before(left : OpenEntry, right : OpenEntry) -> Bool {
  if left.f != right.f {
    left.f < right.f
  } else if left.h != right.h {
    left.h < right.h
  } else if left.g != right.g {
    left.g < right.g
  } else {
    left.order < right.order
  }
}

///|
fn OpenList::push(self : OpenList, entry : OpenEntry) -> Unit {
  self.items.push(entry)
  let mut index = self.items.length() - 1
  while index > 0 {
    let parent = (index - 1) / 2
    if !open_entry_before(self.items[index], self.items[parent]) {
      break
    }
    let temp = self.items[index]
    self.items[index] = self.items[parent]
    self.items[parent] = temp
    index = parent
  }
}

///|
fn OpenList::pop(self : OpenList) -> OpenEntry? {
  if self.items.length() == 0 {
    return None
  }
  let top = self.items[0]
  let last = self.items.unsafe_pop()
  if self.items.length() > 0 {
    self.items[0] = last
    let mut index = 0
    while true {
      let left = index * 2 + 1
      let right = left + 1
      let mut smallest = index
      if left < self.items.length() &&
        open_entry_before(self.items[left], self.items[smallest]) {
        smallest = left
      }
      if right < self.items.length() &&
        open_entry_before(self.items[right], self.items[smallest]) {
        smallest = right
      }
      if smallest == index {
        break
      }
      let temp = self.items[index]
      self.items[index] = self.items[smallest]
      self.items[smallest] = temp
      index = smallest
    }
  }
  Some(top)
}

///|
fn search_priority(
  g : Int64,
  h : Int64,
  weight : Int32,
  greedy : Bool,
) -> Int64 {
  if greedy {
    return h
  }
  if h <= 0L {
    return g
  }
  let weight64 = Int64::from_int(weight)
  if weight64 > 1L && h > HEURISTIC_INF / weight64 {
    return HEURISTIC_INF
  }
  capped_add(g, h * weight64)
}

///|
fn reconstruct_plan(nodes : Array[SearchNode], goal : Int32) -> Array[Int32] {
  let reversed : Array[Int32] = []
  let mut current = goal
  while current >= 0 {
    let node = nodes[current]
    if node.action >= 0 {
      reversed.push(node.action)
    }
    current = node.parent
  }
  let plan : Array[Int32] = []
  let mut index = reversed.length() - 1
  while index >= 0 {
    plan.push(reversed[index])
    index -= 1
  }
  plan
}

///|
fn failed_result(
  status : SearchStatus,
  expanded : Int32,
  generated : Int32,
) -> SearchResult {
  let plan : Array[Int32] = []
  { status, plan, cost: 0L, expanded, generated, }
}

///|
/// Searches for a plan with the given heuristic and strategy.
///
/// `max_expanded` bounds the number of expanded states and `max_generated`
/// bounds the number of stored search nodes. Exceeding either limit returns
/// `NodeLimitReached` instead of continuing.
pub fn solve(
  problem : GroundProblem,
  heuristic : HeuristicKind,
  algorithm : SearchAlgorithm,
  max_expanded? : Int32 = 1_000_000,
  max_generated? : Int32 = 2_000_000,
) -> SearchResult {
  let task = RelaxedTask::make(problem)
  let weight = match algorithm {
    WeightedAStar(candidate) => if candidate < 1 { 1 } else { candidate }
    _ => 1
  }
  let greedy = match algorithm {
    GBFS => true
    _ => false
  }
  if problem.goal_holds(problem.initial) {
    let plan : Array[Int32] = []
    return {
      status: Solved,
      plan,
      cost: problem.initial_cost,
      expanded: 0,
      generated: 1,
    }
  }
  let initial_h = estimate(heuristic, task, problem, problem.initial)
  if initial_h < 0L {
    return failed_result(Exhausted, 0, 1)
  }
  let nodes : Array[SearchNode] = []
  nodes.push({
    state: problem.initial.copy(),
    parent: -1,
    action: -1,
    g: 0L,
    h: initial_h,
  })
  let open = OpenList::make()
  open.push({
    node: 0,
    f: search_priority(0L, initial_h, weight, greedy),
    h: initial_h,
    g: 0L,
    order: 0,
  })
  let best_g : Map[String, Int64] = Map([])
  best_g.set(problem.initial.key(), 0L)
  let closed : Map[String, Bool] = Map([])
  let mut next_order = 1
  let mut expanded = 0
  let mut generated = 1
  while true {
    let entry = match open.pop() {
      Some(entry) => entry
      None => return failed_result(Exhausted, expanded, generated)
    }
    let node = nodes[entry.node]
    let key = node.state.key()
    if greedy {
      if closed.contains(key) {
        continue
      }
    } else {
      let stale = match best_g.get(key) {
        Some(best) => entry.g > best
        None => false
      }
      if stale {
        continue
      }
    }
    if problem.goal_holds(node.state) {
      let plan = reconstruct_plan(nodes, entry.node)
      return {
        status: Solved,
        plan,
        cost: capped_add(problem.initial_cost, node.g),
        expanded,
        generated,
      }
    }
    if greedy {
      closed.set(key, true)
    }
    if node.h < 0L {
      continue
    }
    if expanded >= max_expanded {
      return failed_result(NodeLimitReached, expanded, generated)
    }
    expanded += 1
    for index in 0..<problem.actions.length() {
      let action = problem.actions[index]
      if !action_is_applicable(action, node.state) {
        continue
      }
      let next_state = apply_action(action, node.state)
      let next_key = next_state.key()
      if greedy && closed.contains(next_key) {
        continue
      }
      let next_g = capped_add(node.g, action.cost)
      let worse = match best_g.get(next_key) {
        Some(existing) => existing <= next_g
        None => false
      }
      if worse {
        continue
      }
      let next_h = estimate(heuristic, task, problem, next_state)
      let reaches_goal = problem.goal_holds(next_state)
      if next_h < 0L && !reaches_goal {
        continue
      }
      if nodes.length() >= max_generated {
        return failed_result(NodeLimitReached, expanded, generated)
      }
      best_g.set(next_key, next_g)
      let new_index = nodes.length()
      nodes.push({
        state: next_state,
        parent: entry.node,
        action: action.id,
        g: next_g,
        h: next_h,
      })
      generated += 1
      open.push({
        node: new_index,
        f: search_priority(next_g, next_h, weight, greedy),
        h: next_h,
        g: next_g,
        order: next_order,
      })
      next_order += 1
    }
  } nobreak {
    abort("unreachable: search loop never breaks")
  }
}
