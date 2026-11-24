extends SceneTree
var Flight
func _initialize():
	Flight = load("res://scripts/ball_flight_predictor.gd")
	for base in [[Vector3(0.64,1.05,-2.74), Vector3(-2.99,4.32,5.11)], [Vector3(2.27,0.61,-1.96), Vector3(-3.42,4.43,3.99)], [Vector3(-1.26,0.66,1.78), Vector3(3.4,4.35,-3.54)]]:
		for vy_k in [1.6, 2.2]:
			for len_k in [0.2, 0.35]:
				var line := "vy%.1f len%.2f:" % [vy_k, len_k]
				for c in [0.0, 0.3, 0.5, 0.8]:
					var v: Vector3 = base[1]
					var h: Vector3 = Vector3(v.x,0,v.z)*(1.0+len_k*c)
					var v2: Vector3 = h + Vector3.UP*(v.y+vy_k*c)
					var fl: Dictionary = Flight.trace(base[0], v2, Vector3.ZERO, 3.0, 1, false)
					var at := -1.0
					for smp in fl.samples:
						if absf(smp.pos.z) >= 2.55 and smp.pos.z * base[0].z < 0: at = smp.pos.y; break
					line += "  c%.1f land %.2f h@2.55 %.2f net %s" % [c, absf(fl.first_bounce.z), at, "HIT" if fl.net_hit else "ok"]
				print(line)
	quit()
