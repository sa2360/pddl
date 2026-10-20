(define (problem logistics-1)
  (:domain logistics)
  (:objects
    c1 c2 - city
    a b - location
    x y - location
    p1 p2 - package
    t1 - truck
    pl1 - airplane)
  (:init
    (in-city a c1) (in-city b c1)
    (in-city x c2) (in-city y c2)
    (at p1 a) (at p2 x)
    (at-truck t1 a)
    (at-airplane pl1 b))
  (:goal (and (at p1 x) (at p2 b))))
