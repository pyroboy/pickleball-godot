extends SceneTree
const Accuracy = preload("res://scripts/shot_accuracy.gd")
const Physics = preload("res://scripts/shot_physics.gd")
const Styles = preload("res://scripts/serve_style.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
var maximum_norm: = 0.0
var maximum_residual: = 0.0
var unreliable: = 0
var outside: = 0
var checks: = 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func run():
	var accuracy = Accuracy.new()
	accuracy.rng.seed = 19473
	var sum: = Vector2.ZERO
	var radial_second: = 0.0
	for i in range(20000):
		var s: Dictionary = accuracy.sample(Vector3.ZERO, 0.6, 1)
		var unit: = Vector2(s.sampled.x / s.radii.x, s.sampled.z / s.radii.y)
		check(unit.length() <= 1.000001, "bounded sample")
		sum += unit
		radial_second += unit.length_squared()
	check((sum / 20000.0).length() < 0.02, "unbiased center")
	check(absf(radial_second / 20000.0 - 1.0 / 3.0) < 0.015, "uniform radius distribution")
	accuracy.rng.seed = 77
	var a: Dictionary = accuracy.sample(Vector3.ZERO, 0.5)
	accuracy.rng.seed = 77
	for i in range(100): Accuracy.display_radii(0.5)
	var b: Dictionary = accuracy.sample(Vector3.ZERO, 0.5)
	check(a.sampled.is_equal_approx(b.sampled), "preview/focus cannot consume random numbers")
	var physics = Physics.new()
	for side in range(2):
		var sign_z: float = -1 if side == 0 else 1
		for intent in ["AUTO", "DROP"]:
			for mode in range(3):
				for height in [0.55, 2.2]:
					for charge in [0.15, 0.9]:
						var target: = Vector3(2.3, Flight.FLOOR_REST_Y, sign_z * (1.15 if intent == "DROP" else 5.7))
						var sample: Dictionary = accuracy.sample(target, charge, mode, intent)
						var launch: Dictionary = physics.solve_aimed_launch(Vector3(-1.2, height, -sign_z * 5), sample.sampled, charge, side, mode, intent, "SMASH" if height > 2 else "GROUNDSTROKE", 0, true)
						Accuracy.annotate(launch, sample)
						check(launch.target.is_equal_approx(target), "intent preserved")
						check(launch.sampled_target.is_equal_approx(sample.sampled), "sample not clamped")
						check_zone(launch, target, Accuracy.display_radii(charge, mode, intent))
		# Other automatic shot classifications share dispersion, but retain their own solver profile.
		for kind in ["RETURN", "VOLLEY", "DINK", "LOB", "GROUNDSTROKE", "SMASH"]:
			for mode in range(3):
				var target: = Vector3(-1.7, Flight.FLOOR_REST_Y, sign_z * 4.4)
				var sample: Dictionary = accuracy.sample(target, 0.6, mode)
				var launch: Dictionary = physics.solve_aimed_launch(Vector3(1.2, 1.4, -sign_z * 3.2), sample.sampled, 0.6, side, mode, "AUTO", kind, 0, true)
				Accuracy.annotate(launch, sample)
				check_zone(launch, target, Accuracy.display_radii(0.6, mode))
		for style in range(7):
			for box in [-1, 1]:
				var target: = Vector3(box * 1.5, Flight.FLOOR_REST_Y, sign_z * 4.6)
				var sample: Dictionary = accuracy.sample(target, 0.8, Styles.spin_mode(style), "AUTO", true)
				var launch: Dictionary = Styles.solve_launch(physics, Vector3(-box * 1.5, 0.7, -sign_z * 6.8), sample.sampled, 0.8, side, style, 0, true)
				Accuracy.annotate(launch, sample)
				check_zone(launch, target, Accuracy.display_radii(0.8, Styles.spin_mode(style), "AUTO", true))
				check(launch.landing.x * box > 0 and absf(launch.landing.x) < 3.048 and absf(launch.landing.z) > 2.134 and absf(launch.landing.z) < 6.705, "centered serve remains legal")
	print("SHOT ACCURACY: ", checks, " checks; failures=", failures, " max_norm=", maximum_norm, " max_residual=", maximum_residual, " unreliable=", unreliable, " outside=", outside)
	quit(0 if failures.is_empty() else 1)
func check_zone(launch: Dictionary, target: Vector3, axes: Vector2):
	var offset: Vector3 = launch.landing - target
	var norm: = Vector2(offset.x / axes.x, offset.z / axes.y).length()
	maximum_norm = maxf(maximum_norm, norm)
	maximum_residual = maxf(maximum_residual, launch.landing.distance_to(launch.sampled_target))
	if not launch.profile.accuracy_region_reliable: unreliable += 1
	if norm > 1.0001: outside += 1
	check(not launch.profile.accuracy_region_reliable or norm <= 1.0001, "reliable landing inside displayed ellipse")
