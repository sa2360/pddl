// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

///|
/// Bits packed per state word. `Int32` is 32-bit in MoonBit; 31 bits keep
/// every word non-negative so string keys stay simple and stable.
const BITS_PER_WORD : Int32 = 31

///|
/// Upper bound on the size of a compiled DNF. Grounding rejects formulas
/// whose expansion would explode combinatorially.
const MAX_DNF_ALTERNATIVES : Int32 = 8192

///|
/// Upper bound on the number of grounded actions.
const MAX_GROUND_ACTIONS : Int32 = 200_000

///|
/// Largest value accepted for a single action cost or the initial
/// total-cost. Sums stay exact well below the 2^53 integer limit of
/// `Double`.
const MAX_COST_VALUE : Double = 1_000_000_000_000.0

///|
/// Sentinel for an atom the delete relaxation cannot reach and for a
/// saturated cost sum. Any sum at or beyond this value is treated as
/// unreachable, which keeps every intermediate sum exactly representable.
const HEURISTIC_INF : Double = 1_000_000_000_000_000.0

///|
/// Tolerance used when comparing numeric fluent values. PDDL numbers are
/// exact in the common integer case; the tolerance only absorbs rounding
/// noise from chained fractional arithmetic.
const NUM_EPSILON : Double = 0.000000001

///|
/// A signed ground literal or a numeric constraint.
pub(all) enum CondLit {
  Pos(Int32)
  Neg(Int32)
  Num(CompareOp, NumValue, NumValue)
} derive(Eq, Debug)

///|
/// A compiled numeric expression over ground fluents.
pub(all) enum NumValue {
  NConst(Double)
  NFluent(Int32)
  NNeg(NumValue)
  NAdd(NumValue, NumValue)
  NSub(NumValue, NumValue)
  NMul(NumValue, NumValue)
  NDiv(NumValue, NumValue)
} derive(Eq, Debug)

///|
/// Numeric effect operator after grounding.
pub(all) enum GroundNumOp {
  GInc
  GDec
  GAssign
  GScaleUp
  GScaleDown
} derive(Eq, Debug)

///|
/// One ground numeric effect. `rhs` is evaluated in the state before the
/// action is applied.
pub(all) struct GroundNumEffect {
  op : GroundNumOp
  fluent : Int32
  rhs : NumValue
} derive(Eq, Debug)

///|
/// One conditional effect after grounding and quantifier expansion.
/// `condition` is a DNF; `[[]]` means unconditional.
pub(all) struct GroundEffect {
  condition : Array[Array[CondLit]]
  adds : Array[Int32]
  deletes : Array[Int32]
  numeric : Array[GroundNumEffect]
} derive(Eq, Debug)

///|
/// A ground predicate application. Atom ids index `GroundProblem::atoms`.
pub(all) struct GroundAtom {
  predicate : String
  args : Array[String]
} derive(Eq, Debug)

///|
/// A ground function application. Fluent ids index the `fluents` array of
/// every `State` built from the owning `GroundProblem`.
pub(all) struct GroundFunc {
  predicate : String
  args : Array[String]
} derive(Eq, Debug)

///|
/// A fully ground action. `cost` is the static action cost: the sum of the
/// unconditional `increase (total-cost ...)` contributions evaluated over
/// the initial fluent values.
pub(all) struct GroundAction {
  mut id : Int32
  name : String
  args : Array[String]
  precondition : Array[Array[CondLit]]
  effects : Array[GroundEffect]
  cost : Double
} derive(Eq, Debug)

///|
/// A bitset over atom ids plus the values of all numeric fluents.
pub(all) struct State {
  words : Array[Int32]
  fluents : Array[Double]
} derive(Debug)

///|
/// A domain and problem compiled into a ground planning task.
pub(all) struct GroundProblem {
  domain_name : String
  problem_name : String
  objects : Array[TypedName]
  atoms : Array[GroundAtom]
  funcs : Array[GroundFunc]
  actions : Array[GroundAction]
  initial : State
  initial_cost : Double
  goal : Array[Array[CondLit]]
  uses_action_costs : Bool
  has_metric : Bool
  metric_minimize : Bool
} derive(Debug)

///|
pub fn State::empty(num_atoms : Int32, num_fluents : Int32) -> State {
  let words = Array::make((num_atoms + BITS_PER_WORD - 1) / BITS_PER_WORD, 0)
  let fluents = Array::make(num_fluents, 0.0)
  { words, fluents, }
}

///|
pub fn State::contains(self : State, atom : Int32) -> Bool {
  let word = atom / BITS_PER_WORD
  if word < 0 || word >= self.words.length() {
    return false
  }
  (self.words[word] & (1 << (atom % BITS_PER_WORD))) != 0
}

///|
pub fn State::add(self : State, atom : Int32) -> Unit {
  let word = atom / BITS_PER_WORD
  if word >= 0 && word < self.words.length() {
    self.words[word] = self.words[word] | (1 << (atom % BITS_PER_WORD))
  }
}

///|
pub fn State::remove(self : State, atom : Int32) -> Unit {
  let word = atom / BITS_PER_WORD
  if word >= 0 && word < self.words.length() {
    let mask = 1 << (atom % BITS_PER_WORD)
    if (self.words[word] & mask) != 0 {
      self.words[word] = self.words[word] - mask
    }
  }
}

///|
pub fn State::fluent(self : State, id : Int32) -> Double {
  if id >= 0 && id < self.fluents.length() {
    self.fluents[id]
  } else {
    0.0
  }
}

///|
pub fn State::set_fluent(self : State, id : Int32, value : Double) -> Unit {
  if id >= 0 && id < self.fluents.length() {
    self.fluents[id] = value
  }
}

///|
pub fn State::copy(self : State) -> State {
  { words: self.words.copy(), fluents: self.fluents.copy(), }
}

///|
/// Number of true atoms.
pub fn State::num_true(self : State) -> Int32 {
  let mut count = 0
  for word in self.words {
    let mut bits = word
    while bits != 0 {
      count += bits & 1
      bits = bits >> 1
    }
  }
  count
}

///|
/// Canonical rendering of a numeric value for state keys and reports.
/// Values that are within `NUM_EPSILON` of an integer collapse to that
/// integer so chained arithmetic does not fragment duplicate detection.
/// Non-finite values (which well-formed models never produce) pass through
/// untouched.
pub fn format_number(value : Double) -> String {
  if value != value || value >= 1.0e18 || value <= -1.0e18 {
    return value.to_string()
  }
  let truncated = value.to_int64().to_double()
  let diff = value - truncated
  if diff.abs() < NUM_EPSILON {
    return truncated.to_int64().to_string()
  }
  if diff > 0.0 && (1.0 - diff).abs() < NUM_EPSILON {
    return (truncated.to_int64() + 1L).to_string()
  }
  if diff < 0.0 && (diff + 1.0).abs() < NUM_EPSILON {
    return (truncated.to_int64() - 1L).to_string()
  }
  value.to_string()
}

///|
/// A canonical key for closed-set duplicate detection. Fluent values are
/// part of the key: two states with the same atoms but different fluents
/// are different states.
pub fn State::key(self : State) -> String {
  let sb = StringBuilder::StringBuilder()
  for word in self.words {
    sb.write_string(word.to_string(radix=36))
    sb.write_char(',')
  }
  sb.write_char('|')
  for value in self.fluents {
    sb.write_string(format_number(value))
    sb.write_char(',')
  }
  sb.to_string()
}

///|
/// Evaluates a compiled numeric expression against a state's fluent values.
/// Division by zero yields `0.0`; models that can trigger it should guard
/// the corresponding condition instead.
pub fn eval_num_value(value : NumValue, fluents : Array[Double]) -> Double {
  match value {
    NConst(c) => c
    NFluent(id) =>
      if id >= 0 && id < fluents.length() {
        fluents[id]
      } else {
        0.0
      }
    NNeg(inner) => -eval_num_value(inner, fluents)
    NAdd(l, r) => eval_num_value(l, fluents) + eval_num_value(r, fluents)
    NSub(l, r) => eval_num_value(l, fluents) - eval_num_value(r, fluents)
    NMul(l, r) => eval_num_value(l, fluents) * eval_num_value(r, fluents)
    NDiv(l, r) => {
      let divisor = eval_num_value(r, fluents)
      if divisor == 0.0 {
        0.0
      } else {
        eval_num_value(l, fluents) / divisor
      }
    }
  }
}

///|
/// Compares two numeric values with the epsilon tolerance. The six
/// operators stay mutually consistent: `=` and `!=` are complementary, and
/// `<=`/`>=` agree with `<`/`>` at the boundary.
pub fn num_compare(op : CompareOp, left : Double, right : Double) -> Bool {
  let diff = left - right
  match op {
    CmpLT => diff < -NUM_EPSILON
    CmpLE => diff <= NUM_EPSILON
    CmpEQ => diff.abs() <= NUM_EPSILON
    CmpNE => diff.abs() > NUM_EPSILON
    CmpGT => diff > NUM_EPSILON
    CmpGE => diff >= -NUM_EPSILON
  }
}

///|
fn compare_op_flip(op : CompareOp) -> CompareOp {
  match op {
    CmpLT => CmpGE
    CmpLE => CmpGT
    CmpEQ => CmpNE
    CmpNE => CmpEQ
    CmpGT => CmpLE
    CmpGE => CmpLT
  }
}

///|
pub fn CondLit::holds(self : CondLit, state : State) -> Bool {
  match self {
    Pos(atom) => state.contains(atom)
    Neg(atom) => !state.contains(atom)
    Num(op, l, r) =>
      num_compare(
        op,
        eval_num_value(l, state.fluents),
        eval_num_value(r, state.fluents),
      )
  }
}

///|
fn alternative_holds(alternative : Array[CondLit], state : State) -> Bool {
  for literal in alternative {
    if !literal.holds(state) {
      return false
    }
  }
  true
}

///|
/// Evaluates a DNF condition against a state. `[[]]` is true and `[]` is
/// false.
pub fn condition_holds(
  condition : Array[Array[CondLit]],
  state : State,
) -> Bool {
  for alternative in condition {
    if alternative_holds(alternative, state) {
      return true
    }
  }
  false
}

///|
/// Renders a ground atom as `(predicate arg1 arg2)`.
pub fn GroundAtom::render(self : GroundAtom) -> String {
  let sb = StringBuilder::StringBuilder()
  sb.write_char('(')
  sb.write_string(self.predicate)
  for arg in self.args {
    sb.write_char(' ')
    sb.write_string(arg)
  }
  sb.write_char(')')
  sb.to_string()
}

///|
/// Renders a ground fluent as `(function arg1 arg2)`.
pub fn GroundFunc::render(self : GroundFunc) -> String {
  let sb = StringBuilder::StringBuilder()
  sb.write_char('(')
  sb.write_string(self.predicate)
  for arg in self.args {
    sb.write_char(' ')
    sb.write_string(arg)
  }
  sb.write_char(')')
  sb.to_string()
}

///|
/// Renders a ground action as `(name arg1 arg2)`.
pub fn GroundAction::render(self : GroundAction) -> String {
  let sb = StringBuilder::StringBuilder()
  sb.write_char('(')
  sb.write_string(self.name)
  for arg in self.args {
    sb.write_char(' ')
    sb.write_string(arg)
  }
  sb.write_char(')')
  sb.to_string()
}

///|
/// Renders a compiled numeric expression for diagnostics.
pub fn num_value_text(problem : GroundProblem, value : NumValue) -> String {
  match value {
    NConst(c) => format_number(c)
    NFluent(id) =>
      if id >= 0 && id < problem.funcs.length() {
        problem.funcs[id].render()
      } else {
        "<fluent #\{id}>"
      }
    NNeg(inner) => "(- \{num_value_text(problem, inner)})"
    NAdd(l, r) =>
      "(+ \{num_value_text(problem, l)} \{num_value_text(problem, r)})"
    NSub(l, r) =>
      "(- \{num_value_text(problem, l)} \{num_value_text(problem, r)})"
    NMul(l, r) =>
      "(* \{num_value_text(problem, l)} \{num_value_text(problem, r)})"
    NDiv(l, r) =>
      "(/ \{num_value_text(problem, l)} \{num_value_text(problem, r)})"
  }
}

///|
pub fn GroundProblem::goal_holds(self : GroundProblem, state : State) -> Bool {
  condition_holds(self.goal, state)
}

///|
/// Renders an atom id for diagnostics.
pub fn GroundProblem::atom_text(self : GroundProblem, atom : Int32) -> String {
  if atom >= 0 && atom < self.atoms.length() {
    self.atoms[atom].render()
  } else {
    "<atom #\{atom}>"
  }
}

///|
fn cond_lit_text(problem : GroundProblem, literal : CondLit) -> String {
  match literal {
    Pos(atom) => problem.atom_text(atom)
    Neg(atom) => "(not \{problem.atom_text(atom)})"
    Num(op, l, r) => {
      let symbol = match op {
        CmpLT => "<"
        CmpLE => "<="
        CmpEQ => "="
        CmpNE => "!="
        CmpGT => ">"
        CmpGE => ">="
      }
      "(\{symbol} \{num_value_text(problem, l)} \{num_value_text(problem, r)})"
    }
  }
}

///|
pub fn action_is_applicable(action : GroundAction, state : State) -> Bool {
  condition_holds(action.precondition, state)
}

///|
/// Numeric contributions collected for one fluent while applying an action.
priv struct FluentUpdate {
  fluent : Int32
  mut delta : Double
  mut scale_up : Double
  mut scale_down : Double
  mut assigned : Bool
  mut assign_value : Double
}

///|
fn FluentUpdate::make(fluent : Int32) -> FluentUpdate {
  {
    fluent,
    delta: 0.0,
    scale_up: 1.0,
    scale_down: 1.0,
    assigned: false,
    assign_value: 0.0,
  }
}

///|
/// Applies an action. Conditions and numeric right-hand sides are evaluated
/// in the input state; then all deletions, additions and numeric updates are
/// applied simultaneously:
///
/// - `increase`/`decrease` sum additively;
/// - `scale-up`/`scale-down` multiply/divide the summed value (division by
///   zero leaves the fluent unchanged);
/// - `assign` overrides everything else; with several assignments the last
///   one wins.
pub fn apply_action(action : GroundAction, state : State) -> State {
  let next = state.copy()
  let deletes : Array[Int32] = []
  let adds : Array[Int32] = []
  let updates : Array[FluentUpdate] = []
  let update_index : Map[Int32, Int32] = Map([])
  for effect in action.effects {
    if condition_holds(effect.condition, state) {
      for atom in effect.deletes {
        deletes.push(atom)
      }
      for atom in effect.adds {
        adds.push(atom)
      }
      for numeric in effect.numeric {
        let rhs = eval_num_value(numeric.rhs, state.fluents)
        let update = match update_index.get(numeric.fluent) {
          Some(index) => updates[index]
          None => {
            let created = FluentUpdate::make(numeric.fluent)
            update_index.set(numeric.fluent, updates.length())
            updates.push(created)
            created
          }
        }
        match numeric.op {
          GInc => update.delta = update.delta + rhs
          GDec => update.delta = update.delta - rhs
          GScaleUp => update.scale_up = update.scale_up * rhs
          GScaleDown =>
            if rhs != 0.0 {
              update.scale_down = update.scale_down * rhs
            }
          GAssign => {
            update.assigned = true
            update.assign_value = rhs
          }
        }
      }
    }
  }
  for atom in deletes {
    next.remove(atom)
  }
  for atom in adds {
    next.add(atom)
  }
  for update in updates {
    if update.assigned {
      next.set_fluent(update.fluent, update.assign_value)
    } else {
      let base = state.fluent(update.fluent) + update.delta
      let scaled = base * update.scale_up / update.scale_down
      next.set_fluent(update.fluent, scaled)
    }
  }
  next
}

///|
priv struct AtomTable {
  atoms : Array[GroundAtom]
  index : Map[String, Int32]
}

///|
fn AtomTable::make() -> AtomTable {
  let index : Map[String, Int32] = Map([])
  { atoms: [], index, }
}

///|
/// Names in PDDL cannot contain whitespace, so a space separated key is
/// unambiguous.
fn atom_key(predicate : String, args : Array[String]) -> String {
  let sb = StringBuilder::StringBuilder()
  sb.write_string(predicate)
  for arg in args {
    sb.write_char(' ')
    sb.write_string(arg)
  }
  sb.to_string()
}

///|
fn AtomTable::intern(
  self : AtomTable,
  predicate : String,
  args : Array[String],
) -> Int32 {
  let key = atom_key(predicate, args)
  match self.index.get(key) {
    Some(id) => id
    None => {
      let id = self.atoms.length()
      self.atoms.push({ predicate, args: args.copy(), })
      self.index.set(key, id)
      id
    }
  }
}

///|
priv struct FuncTable {
  funcs : Array[GroundFunc]
  index : Map[String, Int32]
  /// Initial value of every interned fluent; zero when never assigned.
  values : Array[Double]
  assigned : Map[Int32, Bool]
}

///|
fn FuncTable::make() -> FuncTable {
  let index : Map[String, Int32] = Map([])
  let assigned : Map[Int32, Bool] = Map([])
  { funcs: [], index, values: [], assigned, }
}

///|
fn FuncTable::intern(
  self : FuncTable,
  predicate : String,
  args : Array[String],
) -> Int32 {
  let key = atom_key(predicate, args)
  match self.index.get(key) {
    Some(id) => id
    None => {
      let id = self.funcs.length()
      self.funcs.push({ predicate, args: args.copy(), })
      self.values.push(0.0)
      self.index.set(key, id)
      id
    }
  }
}

///|
fn dnf_product(
  left : Array[Array[CondLit]],
  right : Array[Array[CondLit]],
  context : String,
) -> Array[Array[CondLit]] raise PddlError {
  if left.length() == 0 || right.length() == 0 {
    return []
  }
  if left.length() * right.length() > MAX_DNF_ALTERNATIVES {
    raise model_error(
      "formula expansion in \{context} exceeds \{MAX_DNF_ALTERNATIVES} disjuncts",
    )
  }
  let result : Array[Array[CondLit]] = []
  for a in left {
    for b in right {
      let merged = a.copy()
      merged.append(b)
      result.push(merged)
    }
  }
  result
}

///|
fn dnf_union(
  left : Array[Array[CondLit]],
  right : Array[Array[CondLit]],
  context : String,
) -> Array[Array[CondLit]] raise PddlError {
  if left.length() + right.length() > MAX_DNF_ALTERNATIVES {
    raise model_error(
      "formula expansion in \{context} exceeds \{MAX_DNF_ALTERNATIVES} disjuncts",
    )
  }
  let result = left.copy()
  for alternative in right {
    result.push(alternative)
  }
  result
}

///|
/// The compiler owns the object/type/predicate/function context and interns
/// atoms and fluents while walking formulas.
priv struct Compiler {
  objects : Array[TypedName]
  object_types : Map[String, Array[String]]
  type_parents : Map[String, Array[String]]
  predicates : Map[String, Predicate]
  functions : Map[String, FunctionDecl]
  /// Functions modified by some numeric effect; their values change
  /// between states.
  dynamic_functions : Map[String, Bool]
  table : AtomTable
  ftable : FuncTable
}

///|
fn validate_type_decl(
  parents : Map[String, Array[String]],
  type_name : String,
  context : String,
) -> Unit raise PddlError {
  if type_name == "object" {
    return
  }
  if !parents.contains(type_name) {
    raise model_error("unknown type '\{type_name}' in \{context}")
  }
}

///|
fn Compiler::validate_type(
  self : Compiler,
  types : Array[String],
  context : String,
) -> Unit raise PddlError {
  for type_name in types {
    validate_type_decl(self.type_parents, type_name, context)
  }
}

///|
fn type_matches_single(
  parents : Map[String, Array[String]],
  child : String,
  parent : String,
) -> Bool {
  if parent == "object" {
    return true
  }
  let queue : Array[String] = [child]
  let visited : Map[String, Bool] = Map([])
  let mut steps = 0
  while queue.length() > 0 && steps <= parents.length() + 1 {
    let current = queue.remove(0)
    steps += 1
    if current == parent {
      return true
    }
    if visited.contains(current) {
      continue
    }
    visited.set(current, true)
    match parents.get(current) {
      Some(next) =>
        for p in next {
          queue.push(p)
        }
      None => ()
    }
  }
  false
}

///|
/// An object matches a type declaration when any of its declared types
/// (an `(either ...)` is a union) is a subtype of the wanted type.
fn type_matches(
  parents : Map[String, Array[String]],
  declared : Array[String],
  wanted : String,
) -> Bool {
  for type_name in declared {
    if type_matches_single(parents, type_name, wanted) {
      return true
    }
  }
  false
}

///|
fn Compiler::object_type(
  self : Compiler,
  name : String,
  context : String,
) -> Array[String] raise PddlError {
  match self.object_types.get(name) {
    Some(types) => types
    None => raise model_error("unknown object '\{name}' in \{context}")
  }
}

///|
fn Compiler::objects_of_types(
  self : Compiler,
  types : Array[String],
  context : String,
) -> Array[TypedName] raise PddlError {
  self.validate_type(types, context)
  let result : Array[TypedName] = []
  let seen : Map[String, Bool] = Map([])
  for type_name in types {
    for object_ in self.objects {
      if !seen.contains(object_.name) &&
        type_matches(self.type_parents, object_.types, type_name) {
        seen.set(object_.name, true)
        result.push(object_)
      }
    }
  }
  result
}

///|
fn Compiler::resolve_term(
  self : Compiler,
  term : Term,
  env : Map[String, String],
  context : String,
) -> String raise PddlError {
  match term {
    Var(name) =>
      match env.get(name) {
        Some(object_) => object_
        None => raise model_error("unbound variable '?\{name}' in \{context}")
      }
    Const(name) => {
      if !self.object_types.contains(name) {
        raise model_error("unknown object '\{name}' in \{context}")
      }
      name
    }
  }
}

///|
/// Shared argument resolution and type checking for predicates and
/// functions.
fn Compiler::check_args(
  self : Compiler,
  entity : String,
  params : Array[TypedName],
  args : Array[Term],
  env : Map[String, String],
  context : String,
) -> Array[String] raise PddlError {
  if args.length() != params.length() {
    raise model_error(
      "'\{entity}' expects \{params.length()} argument(s), but \{args.length()} were given in \{context}",
    )
  }
  let resolved : Array[String] = []
  for i in 0..<args.length() {
    let object_ = self.resolve_term(args[i], env, context)
    let actual_types = self.object_type(object_, context)
    let expected = params[i].types
    self.validate_type(expected, entity)
    let mut ok = false
    for expected_type in expected {
      if type_matches(self.type_parents, actual_types, expected_type) {
        ok = true
        break
      }
    }
    if !ok {
      let actual_text = if actual_types.length() == 1 {
        actual_types[0]
      } else {
        "either"
      }
      raise model_error(
        "'\{entity}' expects argument \{i + 1} of type '\{expected[0]}', but '\{object_}' has type '\{actual_text}' (in \{context})",
      )
    }
    resolved.push(object_)
  }
  resolved
}

///|
/// Resolves and type-checks a predicate application.
fn Compiler::check_atom(
  self : Compiler,
  atom : PAtom,
  env : Map[String, String],
  context : String,
) -> (String, Array[String]) raise PddlError {
  let predicate = match self.predicates.get(atom.name) {
    Some(predicate) => predicate
    None => raise model_error("unknown predicate '\{atom.name}' in \{context}")
  }
  let args = self.check_args(
    "predicate '\{atom.name}'",
    predicate.params,
    atom.args,
    env,
    context,
  )
  (predicate.name, args)
}

///|
fn Compiler::intern_atom(
  self : Compiler,
  atom : PAtom,
  env : Map[String, String],
  context : String,
) -> Int32 raise PddlError {
  let (predicate, args) = self.check_atom(atom, env, context)
  self.table.intern(predicate, args)
}

///|
/// Resolves and type-checks a function application and interns its ground
/// fluent. `total-cost` never becomes a fluent: it is tracked as the plan
/// cost outside the state.
fn Compiler::intern_fluent(
  self : Compiler,
  atom : PAtom,
  env : Map[String, String],
  context : String,
) -> Int32 raise PddlError {
  if atom.name == "total-cost" {
    raise model_error(
      "total-cost cannot appear in \{context}; it is the plan cost and is not a state fluent",
    )
  }
  let function = match self.functions.get(atom.name) {
    Some(function) => function
    None => raise model_error("unknown function '\{atom.name}' in \{context}")
  }
  let args = self.check_args(
    "function '\{atom.name}'",
    function.params,
    atom.args,
    env,
    context,
  )
  self.ftable.intern(function.name, args)
}

///|
/// Rejects compiled cost expressions that read a fluent some action
/// modifies; action costs must be static so that they stay constant per
/// ground action. Static functions (assigned in `:init` and never changed)
/// are fine and are the standard way to feed per-model constants into
/// action costs.
fn Compiler::assert_static_cost(
  self : Compiler,
  value : NumValue,
  context : String,
) -> Unit raise PddlError {
  let stack : Array[NumValue] = [value]
  while stack.length() > 0 {
    let current = stack.unsafe_pop()
    match current {
      NConst(_) => ()
      NFluent(id) => {
        let name = if id >= 0 && id < self.ftable.funcs.length() {
          self.ftable.funcs[id].predicate
        } else {
          ""
        }
        if self.dynamic_functions.contains(name) {
          let rendered = if id >= 0 && id < self.ftable.funcs.length() {
            self.ftable.funcs[id].render()
          } else {
            "<fluent #\{id}>"
          }
          raise model_error(
            "state-dependent action cost in \{context}: '\{rendered}' changes during execution; action costs may only read static functions",
          )
        }
      }
      NNeg(inner) => stack.push(inner)
      NAdd(l, r) => {
        stack.push(l)
        stack.push(r)
      }
      NSub(l, r) => {
        stack.push(l)
        stack.push(r)
      }
      NMul(l, r) => {
        stack.push(l)
        stack.push(r)
      }
      NDiv(l, r) => {
        stack.push(l)
        stack.push(r)
      }
    }
  }
}

///|
/// Compiles a numeric expression to a ground `NumValue`.
fn Compiler::compile_num_expr(
  self : Compiler,
  node : NumExpr,
  env : Map[String, String],
  context : String,
) -> NumValue raise PddlError {
  match node {
    NumLit(value) => NConst(value)
    NumFunc(atom) => NFluent(self.intern_fluent(atom, env, context))
    NumNeg(inner) => NNeg(self.compile_num_expr(inner, env, context))
    NumAdd(l, r) =>
      NAdd(
        self.compile_num_expr(l, env, context),
        self.compile_num_expr(r, env, context),
      )
    NumSub(l, r) =>
      NSub(
        self.compile_num_expr(l, env, context),
        self.compile_num_expr(r, env, context),
      )
    NumMul(l, r) =>
      NMul(
        self.compile_num_expr(l, env, context),
        self.compile_num_expr(r, env, context),
      )
    NumDiv(l, r) =>
      NDiv(
        self.compile_num_expr(l, env, context),
        self.compile_num_expr(r, env, context),
      )
  }
}

///|
/// Compiles a formula to DNF, optionally under negation.
fn Compiler::compile_formula(
  self : Compiler,
  node : Formula,
  env : Map[String, String],
  negate : Bool,
  context : String,
) -> Array[Array[CondLit]] raise PddlError {
  match node {
    Atom(atom) => {
      let id = self.intern_atom(atom, env, context)
      let literal = if negate { Neg(id) } else { Pos(id) }
      let alternative : Array[CondLit] = [literal]
      [alternative]
    }
    Not(inner) => self.compile_formula(inner, env, !negate, context)
    And(children) => self.compile_and_or(children, true, env, negate, context)
    Or(children) => self.compile_and_or(children, false, env, negate, context)
    Imply(lhs, rhs) =>
      if negate {
        let left = self.compile_formula(lhs, env, false, context)
        let right = self.compile_formula(rhs, env, true, context)
        dnf_product(left, right, context)
      } else {
        let left = self.compile_formula(lhs, env, true, context)
        let right = self.compile_formula(rhs, env, false, context)
        dnf_union(left, right, context)
      }
    Exists(vars, body) =>
      self.compile_quantifier(vars, body, env, false, negate, context)
    Forall(vars, body) =>
      self.compile_quantifier(vars, body, env, true, negate, context)
    Equal(lhs, rhs) => {
      let left = self.resolve_term(lhs, env, context)
      let right = self.resolve_term(rhs, env, context)
      let equal = left == right
      let truth = if negate { !equal } else { equal }
      if truth {
        let dnf : Array[Array[CondLit]] = [[]]
        dnf
      } else {
        let dnf : Array[Array[CondLit]] = []
        dnf
      }
    }
    Compare(op, l, r) => {
      let left = self.compile_num_expr(l, env, context)
      let right = self.compile_num_expr(r, env, context)
      let op = if negate { compare_op_flip(op) } else { op }
      let alternative : Array[CondLit] = [Num(op, left, right)]
      [alternative]
    }
  }
}

///|
fn Compiler::compile_and_or(
  self : Compiler,
  children : Array[Formula],
  is_and : Bool,
  env : Map[String, String],
  negate : Bool,
  context : String,
) -> Array[Array[CondLit]] raise PddlError {
  let conjunction = is_and != negate
  let mut result : Array[Array[CondLit]] = if conjunction { [[]] } else { [] }
  for child in children {
    let part = self.compile_formula(child, env, negate, context)
    if conjunction {
      result = dnf_product(result, part, context)
    } else {
      result = dnf_union(result, part, context)
    }
  }
  result
}

///|
fn Compiler::compile_quantifier(
  self : Compiler,
  vars : Array[TypedName],
  body : Formula,
  env : Map[String, String],
  universal : Bool,
  negate : Bool,
  context : String,
) -> Array[Array[CondLit]] raise PddlError {
  self.quantifier_step(vars, 0, body, env, universal, negate, context)
}

///|
fn Compiler::quantifier_step(
  self : Compiler,
  vars : Array[TypedName],
  index : Int32,
  body : Formula,
  env : Map[String, String],
  universal : Bool,
  negate : Bool,
  context : String,
) -> Array[Array[CondLit]] raise PddlError {
  if index >= vars.length() {
    return self.compile_formula(body, env, negate, context)
  }
  let variable = vars[index]
  let quantifier_name = if universal { "forall" } else { "exists" }
  let candidates = self.objects_of_types(
    variable.types,
    "\{quantifier_name} in \{context}",
  )
  let conjunction = universal != negate
  let mut result : Array[Array[CondLit]] = if conjunction { [[]] } else { [] }
  for object_ in candidates {
    let inner = env.copy()
    inner.set(variable.name, object_.name)
    let part = self.quantifier_step(
      vars,
      index + 1,
      body,
      inner,
      universal,
      negate,
      context,
    )
    if conjunction {
      result = dnf_product(result, part, context)
    } else {
      result = dnf_union(result, part, context)
    }
  }
  result
}

///|
priv struct EffectBuilder {
  effects : Array[GroundEffect]
  mut cost : Double
}

///|
fn Compiler::compile_effects(
  self : Compiler,
  effect : Effect,
  env : Map[String, String],
  context : String,
) -> EffectBuilder raise PddlError {
  let builder = { effects: [], cost: 0.0, }
  let condition : Array[Array[CondLit]] = [[]]
  self.collect_effect(effect, condition, env, context, builder)
  builder
}

///|
fn is_unconditional(condition : Array[Array[CondLit]]) -> Bool {
  condition.length() == 1 && condition[0].length() == 0
}

///|
fn num_op_name(op : NumOp) -> String {
  match op {
    OpIncrease => "increase"
    OpDecrease => "decrease"
    OpAssign => "assign"
    OpScaleUp => "scale-up"
    OpScaleDown => "scale-down"
  }
}

///|
fn Compiler::collect_effect(
  self : Compiler,
  effect : Effect,
  condition : Array[Array[CondLit]],
  env : Map[String, String],
  context : String,
  builder : EffectBuilder,
) -> Unit raise PddlError {
  match effect {
    AddEffect(atom) => {
      let id = self.intern_atom(atom, env, context)
      builder.effects.push({ condition, adds: [id], deletes: [], numeric: [], })
    }
    DeleteEffect(atom) => {
      let id = self.intern_atom(atom, env, context)
      builder.effects.push({ condition, adds: [], deletes: [id], numeric: [], })
    }
    AndEffect(children) =>
      for child in children {
        self.collect_effect(child, condition, env, context, builder)
      }
    ForallEffect(vars, body) =>
      self.collect_forall_effect(
        vars, 0, body, condition, env, context, builder,
      )
    WhenEffect(condition_formula, body) => {
      let extra = self.compile_formula(condition_formula, env, false, context)
      let combined = dnf_product(condition, extra, context)
      if combined.length() > 0 {
        self.collect_effect(body, combined, env, context, builder)
      }
    }
    NumEffect(op, fluent, expr) =>
      if fluent.name == "total-cost" {
        match op {
          OpIncrease => {
            if !is_unconditional(condition) {
              raise model_error(
                "conditional action cost in \{context}; increase must be unconditional",
              )
            }
            let compiled = self.compile_num_expr(expr, env, context)
            self.assert_static_cost(compiled, context)
            let amount = eval_num_value(compiled, self.ftable.values)
            if amount < 0.0 {
              raise model_error("negative action cost in \{context}")
            }
            if builder.cost > MAX_COST_VALUE - amount {
              raise model_error(
                "action cost in \{context} exceeds the supported maximum \{format_number(MAX_COST_VALUE)}",
              )
            }
            builder.cost = builder.cost + amount
          }
          _ =>
            raise model_error(
              "'\{num_op_name(op)}' on total-cost in \{context}; total-cost may only be increased",
            )
        }
      } else {
        let id = self.intern_fluent(fluent, env, context)
        let rhs = self.compile_num_expr(expr, env, context)
        builder.effects.push({
          condition,
          adds: [],
          deletes: [],
          numeric: [{ op: ground_num_op(op), fluent: id, rhs, }],
        })
      }
  }
}

///|
fn ground_num_op(op : NumOp) -> GroundNumOp {
  match op {
    OpIncrease => GInc
    OpDecrease => GDec
    OpAssign => GAssign
    OpScaleUp => GScaleUp
    OpScaleDown => GScaleDown
  }
}

///|
fn Compiler::collect_forall_effect(
  self : Compiler,
  vars : Array[TypedName],
  index : Int32,
  body : Effect,
  condition : Array[Array[CondLit]],
  env : Map[String, String],
  context : String,
  builder : EffectBuilder,
) -> Unit raise PddlError {
  if index >= vars.length() {
    self.collect_effect(body, condition, env, context, builder)
    return
  }
  let variable = vars[index]
  let candidates = self.objects_of_types(
    variable.types,
    "forall effect in \{context}",
  )
  for object_ in candidates {
    let inner = env.copy()
    inner.set(variable.name, object_.name)
    self.collect_forall_effect(
      vars,
      index + 1,
      body,
      condition,
      inner,
      context,
      builder,
    )
  }
}

///|
fn binding_of(
  env : Map[String, String],
  name : String,
  context : String,
) -> String raise PddlError {
  match env.get(name) {
    Some(object_) => object_
    None =>
      raise model_error(
        "internal error: unbound parameter '\{name}' in \{context}",
      )
  }
}

///|
fn Compiler::enumerate_params(
  self : Compiler,
  params : Array[TypedName],
  index : Int32,
  env : Map[String, String],
  out : Array[Map[String, String]],
  context : String,
) -> Unit raise PddlError {
  if index >= params.length() {
    if out.length() >= MAX_GROUND_ACTIONS {
      raise model_error(
        "too many ground bindings in \{context} (limit \{MAX_GROUND_ACTIONS})",
      )
    }
    out.push(env)
    return
  }
  let param = params[index]
  let candidates = self.objects_of_types(
    param.types,
    "parameter '\{param.name}' of \{context}",
  )
  for object_ in candidates {
    let inner = env.copy()
    inner.set(param.name, object_.name)
    self.enumerate_params(params, index + 1, inner, out, context)
  }
}

///|
fn Compiler::ground_action(
  self : Compiler,
  action : Action,
  base_cost : Double,
) -> Array[GroundAction] raise PddlError {
  let context = "action '\{action.name}'"
  let bindings : Array[Map[String, String]] = []
  let empty : Map[String, String] = Map([])
  self.enumerate_params(action.params, 0, empty, bindings, context)
  let result : Array[GroundAction] = []
  for binding in bindings {
    let precondition = self.compile_formula(
      action.precondition,
      binding,
      false,
      context,
    )
    let compiled_effects = self.compile_effects(action.effect, binding, context)
    let args : Array[String] = []
    for param in action.params {
      args.push(binding_of(binding, param.name, context))
    }
    let cost = base_cost + compiled_effects.cost
    if cost > MAX_COST_VALUE {
      raise model_error(
        "action cost in \{context} exceeds the supported maximum \{format_number(MAX_COST_VALUE)}",
      )
    }
    result.push({
      id: 0,
      name: action.name,
      args,
      precondition,
      effects: compiled_effects.effects,
      cost,
    })
  }
  result
}

///|
fn effect_changes_functions(
  effect : Effect,
  changed : Map[String, Bool],
) -> Unit {
  match effect {
    AddEffect(_) => ()
    DeleteEffect(_) => ()
    AndEffect(children) =>
      for child in children {
        effect_changes_functions(child, changed)
      }
    ForallEffect(_, body) => effect_changes_functions(body, changed)
    WhenEffect(_, body) => effect_changes_functions(body, changed)
    NumEffect(_, fluent, _) => changed.set(fluent.name, true)
  }
}

///|
fn effect_increases_total_cost(effect : Effect) -> Bool {
  match effect {
    NumEffect(op, fluent, _) => op is OpIncrease && fluent.name == "total-cost"
    AddEffect(_) => false
    DeleteEffect(_) => false
    AndEffect(children) => {
      for child in children {
        if effect_increases_total_cost(child) {
          return true
        }
      }
      false
    }
    ForallEffect(_, body) => effect_increases_total_cost(body)
    WhenEffect(_, body) => effect_increases_total_cost(body)
  }
}

///|
fn num_expr_mentions_total_cost(expr : NumExpr) -> Bool {
  let stack : Array[NumExpr] = [expr]
  while stack.length() > 0 {
    let current = stack.unsafe_pop()
    match current {
      NumLit(_) => ()
      NumFunc(atom) => if atom.name == "total-cost" { return true }
      NumNeg(inner) => stack.push(inner)
      NumAdd(l, r) => {
        stack.push(l)
        stack.push(r)
      }
      NumSub(l, r) => {
        stack.push(l)
        stack.push(r)
      }
      NumMul(l, r) => {
        stack.push(l)
        stack.push(r)
      }
      NumDiv(l, r) => {
        stack.push(l)
        stack.push(r)
      }
    }
  }
  false
}

///|
fn domain_uses_action_costs(
  domain : Domain,
  problem : Problem,
  init_cost_seen : Bool,
) -> Bool {
  if domain.requirements.contains(":action-costs") {
    return true
  }
  if problem.requirements.contains(":action-costs") {
    return true
  }
  if init_cost_seen {
    return true
  }
  match problem.metric {
    Some(Metric(_, expr)) => num_expr_mentions_total_cost(expr)
    None => false
  }
}

///|
fn build_hierarchy(types : Array[TypeDecl]) -> Map[String, Array[String]] {
  let parents : Map[String, Array[String]] = Map([])
  parents.set("object", ["object"])
  for decl in types {
    parents.set(decl.name, decl.parents)
  }
  parents
}

///|
fn add_objects(
  entries : Array[TypedName],
  source : String,
  parents : Map[String, Array[String]],
  objects : Array[TypedName],
  types : Map[String, Array[String]],
  seen : Map[String, Bool],
) -> Unit raise PddlError {
  for entry in entries {
    for type_name in entry.types {
      validate_type_decl(parents, type_name, "\{source} '\{entry.name}'")
    }
    if seen.contains(entry.name) {
      raise model_error("object '\{entry.name}' is declared more than once")
    }
    seen.set(entry.name, true)
    types.set(entry.name, entry.types)
    objects.push(entry)
  }
}

///|
fn collect_objects(
  constants : Array[TypedName],
  problem_objects : Array[TypedName],
  parents : Map[String, Array[String]],
) -> (Array[TypedName], Map[String, Array[String]]) raise PddlError {
  let objects : Array[TypedName] = []
  let types : Map[String, Array[String]] = Map([])
  let seen : Map[String, Bool] = Map([])
  add_objects(constants, ":constants", parents, objects, types, seen)
  add_objects(problem_objects, ":objects", parents, objects, types, seen)
  (objects, types)
}

///|
/// Grounds a domain against a problem. Raises `PddlError` with an
/// `InvalidModel` payload when the two files disagree, a type is unknown,
/// or the supported endpoint is exceeded.
pub fn ground(
  domain : Domain,
  problem : Problem,
) -> GroundProblem raise PddlError {
  if domain.name != problem.domain_name {
    raise model_error(
      "problem '\{problem.name}' targets domain '\{problem.domain_name}', but the domain is '\{domain.name}'",
    )
  }
  let parents = build_hierarchy(domain.types)
  let (objects, object_types) = collect_objects(
    domain.constants,
    problem.objects,
    parents,
  )
  for predicate in domain.predicates {
    for param in predicate.params {
      for type_name in param.types {
        validate_type_decl(parents, type_name, "predicate '\{predicate.name}'")
      }
    }
  }
  let predicates : Map[String, Predicate] = Map([])
  for predicate in domain.predicates {
    predicates.set(predicate.name, predicate)
  }
  let functions : Map[String, FunctionDecl] = Map([])
  for function in domain.functions {
    if predicates.contains(function.name) {
      raise model_error(
        "function '\{function.name}' shares its name with a predicate",
      )
    }
    functions.set(function.name, function)
  }
  let dynamic_functions : Map[String, Bool] = Map([])
  dynamic_functions.set("total-cost", true)
  for action in domain.actions {
    for param in action.params {
      for type_name in param.types {
        validate_type_decl(parents, type_name, "action '\{action.name}'")
      }
    }
    effect_changes_functions(action.effect, dynamic_functions)
  }
  for function in domain.functions {
    for param in function.params {
      for type_name in param.types {
        validate_type_decl(parents, type_name, "function '\{function.name}'")
      }
    }
  }
  let compiler : Compiler = {
    objects,
    object_types,
    type_parents: parents,
    predicates,
    functions,
    dynamic_functions,
    table: AtomTable::make(),
    ftable: FuncTable::make(),
  }
  let empty_env : Map[String, String] = Map([])
  let init_ids : Array[Int32] = []
  let mut initial_cost = 0.0
  let mut init_cost_seen = false
  for elem in problem.init {
    match elem {
      InitFact(atom) => {
        let id = compiler.intern_atom(atom, empty_env, ":init")
        init_ids.push(id)
      }
      InitFunc(atom, value) =>
        if atom.name == "total-cost" {
          if atom.args.length() > 0 {
            raise model_error("total-cost takes no arguments in :init")
          }
          if init_cost_seen {
            raise model_error(
              "multiple (= (total-cost) ...) assignments in :init",
            )
          }
          if value < 0.0 {
            raise model_error("negative initial total-cost in :init")
          }
          if value > MAX_COST_VALUE {
            raise model_error(
              "initial total-cost in :init exceeds the supported maximum \{format_number(MAX_COST_VALUE)}",
            )
          }
          initial_cost = value
          init_cost_seen = true
        } else {
          let id = compiler.intern_fluent(atom, empty_env, ":init")
          if compiler.ftable.assigned.contains(id) {
            raise model_error(
              "fluent '\{compiler.ftable.funcs[id].render()}' is assigned more than once in :init",
            )
          }
          compiler.ftable.assigned.set(id, true)
          compiler.ftable.values[id] = value
        }
    }
  }
  let goal = compiler.compile_formula(problem.goal, empty_env, false, "goal")
  let mut uses_action_costs = domain_uses_action_costs(
    domain, problem, init_cost_seen,
  )
  for action in domain.actions {
    if effect_increases_total_cost(action.effect) {
      uses_action_costs = true
    }
  }
  let metric_minimize = match problem.metric {
    Some(Metric(dir, _)) => dir is Minimize
    None => true
  }
  let base_cost = if uses_action_costs { 0.0 } else { 1.0 }
  let actions : Array[GroundAction] = []
  for action in domain.actions {
    for grounded in compiler.ground_action(action, base_cost) {
      if actions.length() >= MAX_GROUND_ACTIONS {
        raise model_error(
          "grounding produced more than \{MAX_GROUND_ACTIONS} actions",
        )
      }
      actions.push(grounded)
    }
  }
  let initial = State::empty(
    compiler.table.atoms.length(),
    compiler.ftable.funcs.length(),
  )
  for id in init_ids {
    initial.add(id)
  }
  for i in 0..<compiler.ftable.values.length() {
    initial.set_fluent(i, compiler.ftable.values[i])
  }
  let reachable = relaxed_reachable_atoms(
    actions,
    initial,
    compiler.table.atoms.length(),
  )
  let kept : Array[GroundAction] = []
  for action in actions {
    if action_is_relaxed_applicable(action, reachable) {
      kept.push(action)
    }
  }
  for i in 0..<kept.length() {
    let action = kept[i]
    action.id = i
    kept[i] = action
  }
  {
    domain_name: domain.name,
    problem_name: problem.name,
    objects: compiler.objects,
    atoms: compiler.table.atoms,
    funcs: compiler.ftable.funcs,
    actions: kept,
    initial,
    initial_cost,
    goal,
    uses_action_costs,
    has_metric: problem.metric is Some(_),
    metric_minimize,
  }
}

///|
/// Forward delete-relaxation reachability over atoms, starting from the
/// initial state. Negative literals and numeric constraints are ignored, so
/// the result is a sound over-approximation of the reachable atom set.
fn relaxed_reachable_atoms(
  actions : Array[GroundAction],
  initial : State,
  num_atoms : Int32,
) -> Array[Bool] {
  let reachable = Array::make(num_atoms, false)
  for atom in 0..<num_atoms {
    if initial.contains(atom) {
      reachable[atom] = true
    }
  }
  let mut changed = true
  while changed {
    changed = false
    for action in actions {
      if !action_is_relaxed_applicable(action, reachable) {
        continue
      }
      for effect in action.effects {
        for atom in effect.adds {
          if !reachable[atom] {
            reachable[atom] = true
            changed = true
          }
        }
      }
    }
  }
  reachable
}

///|
/// True when some precondition disjunct has all of its positive atoms in
/// the relaxed-reachable set. Actions without such a disjunct can never be
/// applied in any reachable state and are dropped by grounding.
fn action_is_relaxed_applicable(
  action : GroundAction,
  reachable : Array[Bool],
) -> Bool {
  for alternative in action.precondition {
    let mut ok = true
    for literal in alternative {
      match literal {
        Pos(atom) =>
          if atom >= 0 && atom < reachable.length() && !reachable[atom] {
            ok = false
            break
          }
        Neg(_) => ()
        Num(_, _, _) => ()
      }
    }
    if ok {
      return true
    }
  }
  false
}
