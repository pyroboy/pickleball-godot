extends SceneTree


const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Model = preload("res://scripts/ball.gd")
var checks: = 0
var failures: Array[String] = []
var rows: Array = []
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok and failures.size() < 30: failures.append(label)
func run() -> void :
	for data in [
		{"name": "flat", "spin": Vector3.ZERO}, 
		{"name": "topspin", "spin": Vector3(40, 0, 0)}, 
		{"name": "backspin", "spin": Vector3(-40, 0, 0)}, 
		{"name": "sidespin", "spin": Vector3(0, 40, 0)}, 
		{"name": "mixed_spin", "spin": Vector3(-40, 30, 10)}]:
		var scene: = Node3D.new();root.add_child(scene);current_scene = scene
		var ball = Model.new();scene.add_child(ball)
		ball.collision_layer = 0;ball.collision_mask = 0
		ball.global_position = Vector3(0, 4, -3)
		ball.linear_velocity = Vector3(2, 3, 9)
		ball.angular_velocity = data.spin
		ball.is_in_play = true
		await physics_frame; await physics_frame
		check(ball.angular_damp_mode == RigidBody3D.DAMP_MODE_COMBINE and is_zero_approx(ball.angular_damp), data.name + " production angular damping contract changed")
		check(ball.linear_damp_mode == RigidBody3D.DAMP_MODE_COMBINE and is_zero_approx(ball.linear_damp), data.name + " production linear damping contract changed")
		var dt: = 1.0 / float(Engine.physics_ticks_per_second)
		var trace: Dictionary = Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity, 1.05, 2, false)
		var max_position: = 0.0; var max_velocity: = 0.0; var max_spin: = 0.0; var max_step_position: = 0.0
		for frame in range(1, 61):
			var step: Array = Model.predict_aero_step(ball.global_position, ball.linear_velocity, ball.angular_velocity, Model.get_effective_gravity(), dt)
			await physics_frame
			check(ball.global_position.y > Flight.FLOOR_REST_Y and ball.global_position.y < Model.FLIGHT_CEILING_Y, data.name + " free-flight fixture reached clamp/bounce")
			max_step_position = maxf(max_step_position, ball.global_position.distance_to(step[0]))
			max_velocity = maxf(max_velocity, ball.linear_velocity.distance_to(step[1]))
			max_spin = maxf(max_spin, ball.angular_velocity.distance_to(trace.samples[frame].omega))
			max_position = maxf(max_position, ball.global_position.distance_to(trace.samples[frame].pos))
		check(max_step_position < 2e-05, data.name + " one-step position order mismatch: " + str(max_step_position))
		check(max_velocity < 2e-05, data.name + " one-step force order mismatch: " + str(max_velocity))
		check(max_spin < 0.0001, data.name + " engine angular damping missing/doubled: " + str(max_spin))
		check(max_position < 0.0002, data.name + " one-second open-loop prediction drift: " + str(max_position))
		rows.append({"name": data.name, "seconds": 1.0, "max_step_position_error": max_step_position, "max_step_velocity_error": max_velocity, "max_spin_error": max_spin, "max_position_error": max_position})
		scene.queue_free(); await process_frame; await process_frame
	var f = FileAccess.open("/tmp/early-rigidbody-parity-evidence.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks": checks, "failures": failures, "rows": rows}, "\t"));f.close()
	for failure in failures: push_error(failure)
	print("RIGIDBODY PREDICTION PARITY: %d checks, %d failures; %s" % [checks, failures.size(), JSON.stringify(rows)])
	quit(0 if failures.is_empty() else 1)
