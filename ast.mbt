// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

///|
/// A name with one or more declared types. `?x - (either a b)` produces the
/// two entries `a` and `b`; a plain `?x - a` produces a single entry.
pub(all) struct TypedName {
  name : String
  types : Array[String]
} derive(Eq, Debug)

///|
/// A term occurring in a predicate or function application: either a
/// quantified variable or a problem constant.
pub(all) enum Term {
  Var(String)
  Const(String)
} derive(Eq, Debug)

///|
/// A (possibly non-ground) predicate application.
pub(all) struct PAtom {
  name : String
  args : Array[Term]
} derive(Eq, Debug)

///|
/// A numeric expression over function fluents and literals, as defined by
/// the PDDL 2.1 `<f-exp>` grammar.
pub(all) enum NumExpr {
  NumLit(Double)
  NumFunc(PAtom)
  NumNeg(NumExpr)
  NumAdd(NumExpr, NumExpr)
  NumSub(NumExpr, NumExpr)
  NumMul(NumExpr, NumExpr)
  NumDiv(NumExpr, NumExpr)
} derive(Eq, Debug)

///|
/// Comparison operators allowed between numeric expressions.
pub(all) enum CompareOp {
  CmpLT
  CmpLE
  CmpEQ
  CmpNE
  CmpGT
  CmpGE
} derive(Eq, Debug)

///|
/// A goal description / precondition formula.
pub(all) enum Formula {
  Atom(PAtom)
  Not(Formula)
  And(Array[Formula])
  Or(Array[Formula])
  Imply(Formula, Formula)
  Exists(Array[TypedName], Formula)
  Forall(Array[TypedName], Formula)
  Equal(Term, Term)
  Compare(CompareOp, NumExpr, NumExpr)
} derive(Eq, Debug)

///|
/// Numeric effect operators of PDDL 2.1.
pub(all) enum NumOp {
  OpIncrease
  OpDecrease
  OpAssign
  OpScaleUp
  OpScaleDown
} derive(Eq, Debug)

///|
/// An action effect.
pub(all) enum Effect {
  AddEffect(PAtom)
  DeleteEffect(PAtom)
  AndEffect(Array[Effect])
  ForallEffect(Array[TypedName], Effect)
  WhenEffect(Formula, Effect)
  /// `(increase|decrease|assign|scale-up|scale-down (<function> ...) expr)`
  NumEffect(NumOp, PAtom, NumExpr)
} derive(Eq, Debug)

///|
/// A type declaration with its direct supertypes (`object` for root types).
pub(all) struct TypeDecl {
  name : String
  parents : Array[String]
} derive(Eq, Debug)

///|
/// A predicate declaration.
pub(all) struct Predicate {
  name : String
  params : Array[TypedName]
} derive(Eq, Debug)

///|
/// A function declaration. Functions return `number`; `object` fluents are
/// outside the supported endpoint.
pub(all) struct FunctionDecl {
  name : String
  params : Array[TypedName]
} derive(Eq, Debug)

///|
/// An action schema.
pub(all) struct Action {
  name : String
  params : Array[TypedName]
  precondition : Formula
  effect : Effect
} derive(Eq, Debug)

///|
/// A PDDL domain.
pub(all) struct Domain {
  name : String
  requirements : Array[String]
  types : Array[TypeDecl]
  constants : Array[TypedName]
  predicates : Array[Predicate]
  functions : Array[FunctionDecl]
  actions : Array[Action]
} derive(Eq, Debug)

///|
/// One entry of a problem's `:init` section.
pub(all) enum InitElem {
  InitFact(PAtom)
  /// `(= (<function> args) value)`
  InitFunc(PAtom, Double)
} derive(Eq, Debug)

///|
/// Direction of the optimization metric.
pub(all) enum MetricDir {
  Minimize
  Maximize
} derive(Eq, Debug)

///|
/// The optimization metric with its numeric expression.
pub(all) enum Metric {
  Metric(MetricDir, NumExpr)
} derive(Eq, Debug)

///|
/// A PDDL problem instance.
pub(all) struct Problem {
  name : String
  domain_name : String
  requirements : Array[String]
  objects : Array[TypedName]
  init : Array[InitElem]
  goal : Formula
  metric : Metric?
} derive(Eq, Debug)
