// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

///|
let blocksworld_domain =
  #|(define (domain blocksworld)
  #|  (:requirements :strips :typing)
  #|  (:types block)
  #|  (:predicates
  #|    (on ?x - block ?y - block)
  #|    (ontable ?x - block)
  #|    (clear ?x - block)
  #|    (handempty)
  #|    (holding ?x - block))
  #|  (:action pick-up
  #|    :parameters (?x - block)
  #|    :precondition (and (clear ?x) (ontable ?x) (handempty))
  #|    :effect (and (not (ontable ?x)) (not (clear ?x))
  #|                 (not (handempty)) (holding ?x)))
  #|  (:action put-down
  #|    :parameters (?x - block)
  #|    :precondition (holding ?x)
  #|    :effect (and (not (holding ?x)) (clear ?x)
  #|                 (handempty) (ontable ?x)))
  #|  (:action stack
  #|    :parameters (?x - block ?y - block)
  #|    :precondition (and (holding ?x) (clear ?y))
  #|    :effect (and (not (holding ?x)) (not (clear ?y))
  #|                 (clear ?x) (handempty) (on ?x ?y)))
  #|  (:action unstack
  #|    :parameters (?x - block ?y - block)
  #|    :precondition (and (on ?x ?y) (clear ?x) (handempty))
  #|    :effect (and (holding ?x) (clear ?y)
  #|                 (not (clear ?x)) (not (handempty)) (not (on ?x ?y)))))
  #|

///|
let blocksworld_problem =
  #|(define (problem blocks-3)
  #|  (:domain blocksworld)
  #|  (:objects a b c - block)
  #|  (:init (ontable a) (ontable b) (ontable c)
  #|         (clear a) (clear b) (clear c) (handempty))
  #|  (:goal (and (on a b) (on b c))))
  #|

///|
let quantifier_domain =
  #|(define (domain quantifier-demo)
  #|  (:requirements :typing :negative-preconditions
  #|               :universal-preconditions :existential-preconditions)
  #|  (:types item)
  #|  (:predicates (marked ?x - item))
  #|  (:action mark-all
  #|    :parameters ()
  #|    :precondition (forall (?x - item) (not (marked ?x)))
  #|    :effect (forall (?x - item) (marked ?x)))
  #|  (:action mark-some
  #|    :parameters ()
  #|    :precondition (exists (?x - item) (marked ?x))
  #|    :effect (and)))
  #|

///|
let quantifier_problem =
  #|(define (problem quantifier-1)
  #|  (:domain quantifier-demo)
  #|  (:objects a b - item)
  #|  (:init)
  #|  (:goal (and (marked a) (marked b))))
  #|

///|
let equality_domain =
  #|(define (domain equality-demo)
  #|  (:requirements :typing :equality)
  #|  (:types item)
  #|  (:predicates (same ?x - item ?y - item))
  #|  (:action pair
  #|    :parameters (?x - item ?y - item)
  #|    :precondition (not (= ?x ?y))
  #|    :effect (same ?x ?y)))
  #|

///|
let equality_problem =
  #|(define (problem equality-1)
  #|  (:domain equality-demo)
  #|  (:objects a b - item)
  #|  (:init)
  #|  (:goal (same a b)))
  #|

///|
let conditional_domain =
  #|(define (domain conditional-demo)
  #|  (:requirements :typing :conditional-effects :action-costs)
  #|  (:types item)
  #|  (:predicates (marked ?x - item) (done))
  #|  (:functions (total-cost) - number)
  #|  (:action finish
  #|    :parameters ()
  #|    :precondition ()
  #|    :effect (when (forall (?x - item) (marked ?x)) (done)))
  #|  (:action mark
  #|    :parameters (?x - item)
  #|    :precondition (not (marked ?x))
  #|    :effect (and (marked ?x) (increase (total-cost) 1))))
  #|

///|
let conditional_problem =
  #|(define (problem conditional-1)
  #|  (:domain conditional-demo)
  #|  (:objects a b - item)
  #|  (:init (= (total-cost) 0))
  #|  (:goal (done))
  #|  (:metric minimize (total-cost)))
  #|

///|
let delivery_domain =
  #|(define (domain delivery-numeric)
  #|  (:requirements :strips :typing :negative-preconditions :fluents :action-costs)
  #|  (:types place truck)
  #|  (:predicates
  #|    (at ?t - truck ?p - place)
  #|    (visited ?p - place))
  #|  (:functions
  #|    (fuel ?t - truck) - number
  #|    (distance ?from - place ?to - place) - number
  #|    (fuel-price) - number
  #|    (total-cost) - number)
  #|  (:action drive
  #|    :parameters (?t - truck ?from - place ?to - place)
  #|    :precondition (and (at ?t ?from)
  #|                       (>= (fuel ?t) (distance ?from ?to)))
  #|    :effect (and (not (at ?t ?from)) (at ?t ?to) (visited ?to)
  #|                 (decrease (fuel ?t) (distance ?from ?to))
  #|                 (increase (total-cost) (* (fuel-price) (distance ?from ?to)))))
  #|  (:action refuel
  #|    :parameters (?t - truck ?p - place)
  #|    :precondition (at ?t ?p)
  #|    :effect (and (increase (fuel ?t) 10)
  #|                 (increase (total-cost) (* (fuel-price) 10)))))
  #|

///|
let delivery_problem =
  #|(define (problem delivery-1)
  #|  (:domain delivery-numeric)
  #|  (:objects a b c - place t1 - truck)
  #|  (:init
  #|    (at t1 a)
  #|    (= (fuel t1) 6)
  #|    (= (distance a b) 4)
  #|    (= (distance b c) 3)
  #|    (= (distance a c) 9)
  #|    (= (fuel-price) 2)
  #|    (= (total-cost) 0))
  #|  (:goal (and (visited b) (visited c)))
  #|  (:metric minimize (total-cost)))
  #|

///|
let either_domain =
  #|(define (domain either-demo)
  #|  (:requirements :typing :negative-preconditions)
  #|  (:types block ball container)
  #|  (:predicates (held ?x - (either block ball)))
  #|  (:action grab
  #|    :parameters (?x - (either block ball))
  #|    :precondition (not (held ?x))
  #|    :effect (held ?x)))
  #|

///|
let either_problem =
  #|(define (problem either-1)
  #|  (:domain either-demo)
  #|  (:objects a - block b - ball c - container)
  #|  (:init)
  #|  (:goal (and (held a) (held b))))
  #|

///|
fn find_ground_action(
  problem : GroundProblem,
  name : String,
  args : Array[String],
) -> GroundAction {
  for action in problem.actions {
    if action.name == name && action.args == args {
      return action
    }
  }
  abort("ground action not found: \{name}")
}

///|
fn find_atom(problem : GroundProblem, text : String) -> Int32 {
  for i in 0..<problem.atoms.length() {
    if problem.atoms[i].render() == text {
      return i
    }
  }
  abort("atom not found: \{text}")
}

///|
fn find_fluent(problem : GroundProblem, text : String) -> Int32 {
  for i in 0..<problem.funcs.length() {
    if problem.funcs[i].render() == text {
      return i
    }
  }
  abort("fluent not found: \{text}")
}
