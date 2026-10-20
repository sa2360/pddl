; solution for logistics-1
(load-truck p1 t1 a)
(drive-truck t1 a b c1)
(unload-truck p1 t1 b)
(load-airplane p1 pl1 b)
(fly-airplane pl1 b x)
(unload-airplane p1 pl1 x)
(load-airplane p2 pl1 x)
(fly-airplane pl1 x b)
(unload-airplane p2 pl1 b)
; cost = 9
