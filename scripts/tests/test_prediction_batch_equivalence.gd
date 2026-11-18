extends SceneTree
const BallModel = preload("res://scripts/ball.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
var checks: = 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func run():
	var rng: = RandomNumberGenerator.new()
	rng.seed = 617831
	var settings: Array = [ProjectSettings.get_setting("physics/3d/default_linear_damp"),ProjectSettings.get_setting("physics/3d/default_angular_damp"),ProjectSettings.get_setting("physics/3d/default_gravity")]
	for tick_rate in [60,120]:
		Engine.physics_ticks_per_second = tick_rate
		for damping in [0.0,0.1,0.8]:
			ProjectSettings.set_setting("physics/3d/default_linear_damp",damping)
			ProjectSettings.set_setting("physics/3d/default_angular_damp",damping*0.6)
			ProjectSettings.set_setting("physics/3d/default_gravity",9.8+damping)
			for index in range(150):
				var start: = Vector3(rng.randf_range(-4,4),rng.randf_range(0.11,5.5),rng.randf_range(-8,8))
				var velocity: = Vector3(rng.randf_range(-18,18),rng.randf_range(-5,18),rng.randf_range(-20,20))
				var spin: = Vector3(rng.randf_range(-60,60),rng.randf_range(-30,30),rng.randf_range(-40,40))
				if index%10 == 0: velocity = Vector3.ZERO
				if index%7 == 0: spin = Vector3.ZERO
				var dt: float = 1.0/tick_rate
				var count: int = index%140
				var expected: Array = [start,velocity,spin]
				for step in count: expected = BallModel.predict_aero_step(expected[0],expected[1],expected[2],BallModel.get_effective_gravity(),dt)
				var actual: Array = BallModel.predict_aero_steps(start,velocity,spin,BallModel.get_effective_gravity(),dt,count)
				check(var_to_bytes(expected)==var_to_bytes(actual),"batch bitwise equivalent tick=%s index=%s"%[tick_rate,index])
				for stop_net in [false,true]:
					var full: Dictionary = Flight.trace(start,velocity,spin,3,2,stop_net)
					var summary: Dictionary = Flight.trace(start,velocity,spin,3,2,stop_net,false)
					for key in ["first_bounce","first_bounce_time","net_crossing","net_hit"]: check(var_to_bytes(full[key])==var_to_bytes(summary[key]),"summary "+key)
					var peak: float = start.y
					for sample in full.samples: peak = maxf(peak,sample.pos.y)
					check(peak==summary.peak_y,"peak includes precise sampled/clamped/net-stop height")
					check(summary.samples.is_empty() and summary.bounce_events.is_empty(),"no discarded sample allocations")
	for i in range(3): ProjectSettings.set_setting(["physics/3d/default_linear_damp","physics/3d/default_angular_damp","physics/3d/default_gravity"][i],settings[i])
	print("PREDICTION EQUIVALENCE: ",checks," checks, ",failures.size()," failures ",failures.slice(0,10))
	quit(0 if failures.is_empty() else 1)
