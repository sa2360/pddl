(define (domain logistics)
  (:requirements :strips :typing)
  (:types city location package truck airplane)
  (:predicates
    (in-city ?l - location ?c - city)
    (at ?p - package ?l - location)
    (at-truck ?t - truck ?l - location)
    (at-airplane ?a - airplane ?l - location)
    (in-truck ?p - package ?t - truck)
    (in-airplane ?p - package ?a - airplane))
  (:action load-truck
    :parameters (?p - package ?t - truck ?l - location)
    :precondition (and (at ?p ?l) (at-truck ?t ?l))
    :effect (and (not (at ?p ?l)) (in-truck ?p ?t)))
  (:action unload-truck
    :parameters (?p - package ?t - truck ?l - location)
    :precondition (and (in-truck ?p ?t) (at-truck ?t ?l))
    :effect (and (at ?p ?l) (not (in-truck ?p ?t))))
  (:action drive-truck
    :parameters (?t - truck ?from - location ?to - location ?c - city)
    :precondition (and (at-truck ?t ?from)
                       (in-city ?from ?c) (in-city ?to ?c))
    :effect (and (not (at-truck ?t ?from)) (at-truck ?t ?to)))
  (:action load-airplane
    :parameters (?p - package ?a - airplane ?l - location)
    :precondition (and (at ?p ?l) (at-airplane ?a ?l))
    :effect (and (not (at ?p ?l)) (in-airplane ?p ?a)))
  (:action unload-airplane
    :parameters (?p - package ?a - airplane ?l - location)
    :precondition (and (in-airplane ?p ?a) (at-airplane ?a ?l))
    :effect (and (at ?p ?l) (not (in-airplane ?p ?a))))
  (:action fly-airplane
    :parameters (?a - airplane ?from - location ?to - location)
    :precondition (at-airplane ?a ?from)
    :effect (and (not (at-airplane ?a ?from)) (at-airplane ?a ?to))))
