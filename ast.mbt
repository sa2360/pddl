// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

///|
/// A name decorated with its type, e.g. `?x - block` or `b1 - block`.
pub(all) struct TypedName {
  name : String
  type_name : String
} derive(Eq, Debug)

///|
/// A term occurring in a predicate: either a quantified variable or a
/// problem constant.
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
} derive(Eq, Debug)

///|
/// An action effect.
pub(all) enum Effect {
  AddEffect(PAtom)
  DeleteEffect(PAtom)
  AndEffect(Array[Effect])
  ForallEffect(Array[TypedName], Effect)
  WhenEffect(Formula, Effect)
  /// `(increase (total-cost) N)`.
  IncreaseEffect(String, Int)
} derive(Eq, Debug)

///|
/// A type declaration with its direct supertype (`object` for root types).
pub(all) struct TypeDecl {
  name : String
  parent : String
} derive(Eq, Debug)

///|
/// A predicate declaration.
pub(all) struct Predicate {
  name : String
  params : Array[TypedName]
} derive(Eq, Debug)

///|
/// A function declaration. Only the 0-ary `total-cost` function is supported.
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
  InitCost(Int)
} derive(Eq, Debug)

///|
/// The supported optimization metric.
pub(all) enum Metric {
  MinimizeTotalCost
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
