// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

///|
/// Bits packed per state word. `Int` is 32-bit in MoonBit; 31 bits keep
/// every word non-negative so string keys stay simple and stable.
const BITS_PER_WORD : Int = 31

///|
/// Upper bound on the size of a compiled DNF. Grounding rejects formulas
/// whose expansion would explode combinatorially.
const MAX_DNF_ALTERNATIVES : Int = 8192

///|
/// Upper bound on the number of grounded actions.
const MAX_GROUND_ACTIONS : Int = 200_000

///|
/// A signed ground literal.
pub(all) enum Literal {
  Positive(Int)
  Negative(Int)
} derive(Eq, Debug)

///|
/// A ground predicate application. Atom ids index `GroundProblem::atoms`.
pub(all) struct GroundAtom {
  predicate : String
  args : Array[String]
} derive(Eq, Debug)

///|
/// One conditional effect after grounding and quantifier expansion.
/// `condition` is a DNF; `[[]]` means unconditional.
pub(all) struct GroundEffect {
  condition : Array[Array[Literal]]
  adds : Array[Int]
  deletes : Array[Int]
} derive(Eq, Debug)

///|
/// A fully ground action.
pub(all) struct GroundAction {
  mut id : Int
  name : String
  args : Array[String]
  precondition : Array[Array[Literal]]
  effects : Array[GroundEffect]
  cost : Int64
} derive(Eq, Debug)

///|
/// A bitset over atom ids.
pub(all) struct State {
  words : Array[Int]
} derive(Debug)

///|
/// A domain and problem compiled into a ground planning task.
pub(all) struct GroundProblem {
  domain_name : String
  problem_name : String
  objects : Array[TypedName]
  atoms : Array[GroundAtom]
  actions : Array[GroundAction]
  initial : State
  initial_cost : Int64
  goal : Array[Array[Literal]]
  uses_action_costs : Bool
  has_metric : Bool
} derive(Debug)

///|
pub fn State::empty(num_atoms : Int) -> State {
  let words = Array::make((num_atoms + BITS_PER_WORD - 1) / BITS_PER_WORD, 0)
  { words, }
}

///|
pub fn State::contains(self : State, atom : Int) -> Bool {
  let word = atom / BITS_PER_WORD
  if word < 0 || word >= self.words.length() {
    return false
  }
  (self.words[word] & (1 << (atom % BITS_PER_WORD))) != 0
}

///|
pub fn State::add(self : State, atom : Int) -> Unit {
  let word = atom / BITS_PER_WORD
  if word >= 0 && word < self.words.length() {
    self.words[word] = self.words[word] | (1 << (atom % BITS_PER_WORD))
  }
}

///|
pub fn State::remove(self : State, atom : Int) -> Unit {
  let word = atom / BITS_PER_WORD
  if word >= 0 && word < self.words.length() {
    let mask = 1 << (atom % BITS_PER_WORD)
    if (self.words[word] & mask) != 0 {
      self.words[word] = self.words[word] - mask
    }
  }
}

///|
pub fn State::copy(self : State) -> State {
  { words: self.words.copy(), }
}

///|
/// Number of true atoms.
pub fn State::num_true(self : State) -> Int {
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
/// A canonical key for closed-set duplicate detection.
pub fn State::key(self : State) -> String {
  let sb = StringBuilder::StringBuilder()
  for word in self.words {
    sb.write_string(word.to_string(radix=36))
    sb.write_char(',')
  }
  sb.to_string()
}

///|
pub fn Literal::holds(self : Literal, state : State) -> Bool {
  match self {
    Positive(atom) => state.contains(atom)
    Negative(atom) => !state.contains(atom)
  }
}

///|
fn alternative_holds(alternative : Array[Literal], state : State) -> Bool {
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
  condition : Array[Array[Literal]],
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
pub fn GroundProblem::goal_holds(self : GroundProblem, state : State) -> Bool {
  condition_holds(self.goal, state)
}

///|
/// Renders an atom id for diagnostics.
pub fn GroundProblem::atom_text(self : GroundProblem, atom : Int) -> String {
  if atom >= 0 && atom < self.atoms.length() {
    self.atoms[atom].render()
  } else {
    "<atom #\{atom}>"
  }
}

///|
pub fn action_is_applicable(action : GroundAction, state : State) -> Bool {
  condition_holds(action.precondition, state)
}

///|
/// Applies an action. Conditions are evaluated in the input state, then all
/// deletions and additions are applied simultaneously with adds winning.
pub fn apply_action(action : GroundAction, state : State) -> State {
  let next = state.copy()
  let deletes : Array[Int] = []
  let adds : Array[Int] = []
  for effect in action.effects {
    if condition_holds(effect.condition, state) {
      for atom in effect.deletes {
        deletes.push(atom)
      }
      for atom in effect.adds {
        adds.push(atom)
      }
    }
  }
  for atom in deletes {
    next.remove(atom)
  }
  for atom in adds {
    next.add(atom)
  }
  next
}

///|
priv struct AtomTable {
  atoms : Array[GroundAtom]
  index : Map[String, Int]
}

///|
fn AtomTable::make() -> AtomTable {
  let index : Map[String, Int] = Map([])
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
) -> Int {
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
fn dnf_product(
  left : Array[Array[Literal]],
  right : Array[Array[Literal]],
  context : String,
) -> Array[Array[Literal]] raise PddlError {
  if left.length() == 0 || right.length() == 0 {
    return []
  }
  if left.length() * right.length() > MAX_DNF_ALTERNATIVES {
    raise model_error(
      "formula expansion in \{context} exceeds \{MAX_DNF_ALTERNATIVES} disjuncts",
    )
  }
  let result : Array[Array[Literal]] = []
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
  left : Array[Array[Literal]],
  right : Array[Array[Literal]],
  context : String,
) -> Array[Array[Literal]] raise PddlError {
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
/// The compiler owns the object/type/predicate context and interns atoms
/// while walking formulas.
priv struct Compiler {
  objects : Array[TypedName]
  object_types : Map[String, String]
  type_parents : Map[String, String]
  predicates : Map[String, Predicate]
  table : AtomTable
}

///|
fn validate_type_decl(
  parents : Map[String, String],
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
  type_name : String,
  context : String,
) -> Unit raise PddlError {
  validate_type_decl(self.type_parents, type_name, context)
}

///|
fn Compiler::is_subtype(
  self : Compiler,
  child : String,
  parent : String,
) -> Bool {
  if parent == "object" {
    return true
  }
  let mut current = child
  let mut steps = 0
  while steps <= self.type_parents.length() {
    if current == parent {
      return true
    }
    if current == "object" {
      return false
    }
    current = match self.type_parents.get(current) {
      Some(next) => next
      None => return false
    }
    steps += 1
  }
  false
}

///|
fn Compiler::object_type(
  self : Compiler,
  name : String,
  context : String,
) -> String raise PddlError {
  match self.object_types.get(name) {
    Some(type_name) => type_name
    None => raise model_error("unknown object '\{name}' in \{context}")
  }
}

///|
fn Compiler::objects_of_type(
  self : Compiler,
  type_name : String,
  context : String,
) -> Array[TypedName] raise PddlError {
  self.validate_type(type_name, context)
  let result : Array[TypedName] = []
  for object_ in self.objects {
    if self.is_subtype(object_.type_name, type_name) {
      result.push(object_)
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
  if atom.args.length() != predicate.params.length() {
    raise model_error(
      "predicate '\{atom.name}' expects \{predicate.params.length()} argument(s), but \{atom.args.length()} were given in \{context}",
    )
  }
  let args : Array[String] = []
  for i in 0..<atom.args.length() {
    let object_ = self.resolve_term(atom.args[i], env, context)
    let actual_type = self.object_type(object_, context)
    let expected_type = predicate.params[i].type_name
    self.validate_type(expected_type, "predicate '\{atom.name}'")
    if !self.is_subtype(actual_type, expected_type) {
      raise model_error(
        "predicate '\{atom.name}' expects argument \{i + 1} of type '\{expected_type}', but '\{object_}' has type '\{actual_type}' (in \{context})",
      )
    }
    args.push(object_)
  }
  (predicate.name, args)
}

///|
fn Compiler::intern_atom(
  self : Compiler,
  atom : PAtom,
  env : Map[String, String],
  context : String,
) -> Int raise PddlError {
  let (predicate, args) = self.check_atom(atom, env, context)
  self.table.intern(predicate, args)
}

///|
/// Compiles a formula to DNF, optionally under negation.
fn Compiler::compile_formula(
  self : Compiler,
  node : Formula,
  env : Map[String, String],
  negate : Bool,
  context : String,
) -> Array[Array[Literal]] raise PddlError {
  match node {
    Atom(atom) => {
      let id = self.intern_atom(atom, env, context)
      let literal = if negate { Negative(id) } else { Positive(id) }
      let alternative : Array[Literal] = [literal]
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
        let dnf : Array[Array[Literal]] = [[]]
        dnf
      } else {
        let dnf : Array[Array[Literal]] = []
        dnf
      }
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
) -> Array[Array[Literal]] raise PddlError {
  let conjunction = is_and != negate
  let mut result : Array[Array[Literal]] = if conjunction { [[]] } else { [] }
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
) -> Array[Array[Literal]] raise PddlError {
  self.quantifier_step(vars, 0, body, env, universal, negate, context)
}

///|
fn Compiler::quantifier_step(
  self : Compiler,
  vars : Array[TypedName],
  index : Int,
  body : Formula,
  env : Map[String, String],
  universal : Bool,
  negate : Bool,
  context : String,
) -> Array[Array[Literal]] raise PddlError {
  if index >= vars.length() {
    return self.compile_formula(body, env, negate, context)
  }
  let variable = vars[index]
  let quantifier_name = if universal { "forall" } else { "exists" }
  let candidates = self.objects_of_type(
    variable.type_name,
    "\{quantifier_name} in \{context}",
  )
  let conjunction = universal != negate
  let mut result : Array[Array[Literal]] = if conjunction { [[]] } else { [] }
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
  mut cost : Int64
}

///|
fn Compiler::compile_effects(
  self : Compiler,
  effect : Effect,
  env : Map[String, String],
  context : String,
) -> EffectBuilder raise PddlError {
  let builder = { effects: [], cost: 0L, }
  let condition : Array[Array[Literal]] = [[]]
  self.collect_effect(effect, condition, env, context, builder)
  builder
}

///|
fn is_unconditional(condition : Array[Array[Literal]]) -> Bool {
  condition.length() == 1 && condition[0].length() == 0
}

///|
fn Compiler::collect_effect(
  self : Compiler,
  effect : Effect,
  condition : Array[Array[Literal]],
  env : Map[String, String],
  context : String,
  builder : EffectBuilder,
) -> Unit raise PddlError {
  match effect {
    AddEffect(atom) => {
      let id = self.intern_atom(atom, env, context)
      builder.effects.push({ condition, adds: [id], deletes: [], })
    }
    DeleteEffect(atom) => {
      let id = self.intern_atom(atom, env, context)
      builder.effects.push({ condition, adds: [], deletes: [id], })
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
    IncreaseEffect(fluent, amount) => {
      if fluent != "total-cost" {
        raise model_error(
          "unsupported numeric fluent '\{fluent}' in \{context}",
        )
      }
      if !is_unconditional(condition) {
        raise model_error(
          "conditional action cost in \{context}; increase must be unconditional",
        )
      }
      if amount < 0L {
        raise model_error("negative action cost in \{context}")
      }
      if builder.cost > MAX_COST_VALUE - amount {
        raise model_error(
          "action cost in \{context} exceeds the supported maximum \{MAX_COST_VALUE}",
        )
      }
      builder.cost += amount
    }
  }
}

///|
fn Compiler::collect_forall_effect(
  self : Compiler,
  vars : Array[TypedName],
  index : Int,
  body : Effect,
  condition : Array[Array[Literal]],
  env : Map[String, String],
  context : String,
  builder : EffectBuilder,
) -> Unit raise PddlError {
  if index >= vars.length() {
    self.collect_effect(body, condition, env, context, builder)
    return
  }
  let variable = vars[index]
  let candidates = self.objects_of_type(
    variable.type_name,
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
  index : Int,
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
  let candidates = self.objects_of_type(
    param.type_name,
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
  base_cost : Int64,
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
    if compiled_effects.cost > MAX_COST_VALUE - base_cost {
      raise model_error(
        "action cost in \{context} exceeds the supported maximum \{MAX_COST_VALUE}",
      )
    }
    result.push({
      id: 0,
      name: action.name,
      args,
      precondition,
      effects: compiled_effects.effects,
      cost: base_cost + compiled_effects.cost,
    })
  }
  result
}

///|
fn effect_has_increase(effect : Effect) -> Bool {
  match effect {
    IncreaseEffect(_, _) => true
    AddEffect(_) => false
    DeleteEffect(_) => false
    AndEffect(children) => {
      for child in children {
        if effect_has_increase(child) {
          return true
        }
      }
      false
    }
    ForallEffect(_, body) => effect_has_increase(body)
    WhenEffect(_, body) => effect_has_increase(body)
  }
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
  if domain.functions.length() > 0 || init_cost_seen {
    return true
  }
  if problem.metric is Some(_) {
    return true
  }
  for action in domain.actions {
    if effect_has_increase(action.effect) {
      return true
    }
  }
  false
}

///|
fn build_hierarchy(types : Array[TypeDecl]) -> Map[String, String] {
  let parents : Map[String, String] = Map([])
  parents.set("object", "object")
  for decl in types {
    parents.set(decl.name, decl.parent)
  }
  parents
}

///|
fn add_objects(
  entries : Array[TypedName],
  source : String,
  parents : Map[String, String],
  objects : Array[TypedName],
  types : Map[String, String],
  seen : Map[String, Bool],
) -> Unit raise PddlError {
  for entry in entries {
    validate_type_decl(parents, entry.type_name, "\{source} '\{entry.name}'")
    if seen.contains(entry.name) {
      raise model_error("object '\{entry.name}' is declared more than once")
    }
    seen.set(entry.name, true)
    types.set(entry.name, entry.type_name)
    objects.push(entry)
  }
}

///|
fn collect_objects(
  constants : Array[TypedName],
  problem_objects : Array[TypedName],
  parents : Map[String, String],
) -> (Array[TypedName], Map[String, String]) raise PddlError {
  let objects : Array[TypedName] = []
  let types : Map[String, String] = Map([])
  let seen : Map[String, Bool] = Map([])
  add_objects(constants, ":constants", parents, objects, types, seen)
  add_objects(problem_objects, ":objects", parents, objects, types, seen)
  (objects, types)
}

///|
/// Grounds a domain against a problem. Raises `PddlError` with an
/// `InvalidModel` payload when the two files disagree, a type is unknown,
/// or the supported subset is exceeded.
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
      validate_type_decl(
        parents,
        param.type_name,
        "predicate '\{predicate.name}'",
      )
    }
  }
  for action in domain.actions {
    for param in action.params {
      validate_type_decl(parents, param.type_name, "action '\{action.name}'")
    }
  }
  let predicates : Map[String, Predicate] = Map([])
  for predicate in domain.predicates {
    predicates.set(predicate.name, predicate)
  }
  let compiler : Compiler = {
    objects,
    object_types,
    type_parents: parents,
    predicates,
    table: AtomTable::make(),
  }
  let empty_env : Map[String, String] = Map([])
  let init_ids : Array[Int] = []
  let mut initial_cost = 0L
  let mut init_cost_seen = false
  for elem in problem.init {
    match elem {
      InitFact(atom) => {
        let id = compiler.intern_atom(atom, empty_env, ":init")
        init_ids.push(id)
      }
      InitCost(value) => {
        if init_cost_seen {
          raise model_error(
            "multiple (= (total-cost) ...) assignments in :init",
          )
        }
        if value < 0L {
          raise model_error("negative initial total-cost in :init")
        }
        initial_cost = value
        init_cost_seen = true
      }
    }
  }
  let goal = compiler.compile_formula(problem.goal, empty_env, false, "goal")
  let uses_action_costs = domain_uses_action_costs(
    domain, problem, init_cost_seen,
  )
  let base_cost = if uses_action_costs { 0L } else { 1L }
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
  for i in 0..<actions.length() {
    let action = actions[i]
    action.id = i
    actions[i] = action
  }
  let initial = State::empty(compiler.table.atoms.length())
  for id in init_ids {
    initial.add(id)
  }
  {
    domain_name: domain.name,
    problem_name: problem.name,
    objects: compiler.objects,
    atoms: compiler.table.atoms,
    actions,
    initial,
    initial_cost,
    goal,
    uses_action_costs,
    has_metric: problem.metric is Some(_),
  }
}
