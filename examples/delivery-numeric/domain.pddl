(define (domain delivery-numeric)
  (:requirements :strips :typing :negative-preconditions :fluents :action-costs)
  (:types place truck)
  (:predicates
    (at ?t - truck ?p - place)
    (visited ?p - place))
  (:functions
    (fuel ?t - truck) - number
    (distance ?from - place ?to - place) - number
    (fuel-price) - number
    (total-cost) - number)
  (:action drive
    :parameters (?t - truck ?from - place ?to - place)
    :precondition (and (at ?t ?from)
                       (>= (fuel ?t) (distance ?from ?to)))
    :effect (and (not (at ?t ?from)) (at ?t ?to) (visited ?to)
                 (decrease (fuel ?t) (distance ?from ?to))
                 (increase (total-cost) (* (fuel-price) (distance ?from ?to)))))
  (:action refuel
    :parameters (?t - truck ?p - place)
    :precondition (at ?t ?p)
    :effect (and (increase (fuel ?t) 10)
                 (increase (total-cost) (* (fuel-price) 10)))))
