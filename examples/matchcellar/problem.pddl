(define (problem matchcellar-2)
  (:domain matchcellar)
  (:objects
    m1 m2 - match
    f1 f2 - fuse)
  (:init
    (handfree)
    (unused m1) (unused m2)
    (fuse-unlit f1) (fuse-unlit f2)
    (= (total-cost) 0))
  (:goal (and (fuse-lit f1) (fuse-lit f2)))
  (:metric minimize (total-cost)))
