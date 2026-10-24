; optimal plan for delivery-1:
; refuel costs fuel-price * 10 = 20, drive a->b costs 2 * 4 = 8,
; drive b->c costs 2 * 3 = 6
(refuel t1 a)
(drive t1 a b)
(drive t1 b c)
; cost = 34
