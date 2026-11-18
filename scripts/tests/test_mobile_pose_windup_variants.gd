extends SceneTree
const Variants = preload("res://scripts/ui/mobile_pose_windup_variants.gd")
const Preview = preload("res://scripts/ui/mobile_pose_preview.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const D = preload("res://scripts/paddle_dimensions.gd")
const ServeStore = preload("res://scripts/mobile_serve_pose_store.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func curve_sample(definition: PostureDefinition, progress: float) -> PostureDefinition:
	var pose: PostureDefinition = definition.duplicate(true)
	pose.paddle_forehand_mul = 0.45 * cos(progress * PI)
	pose.paddle_y_offset = .1 + .015 * sin(progress * 6.0 * PI)
	pose.paddle_forward_mul = 0.45 * sin(progress * PI)
	pose.paddle_pitch_base_deg = 20.0 + progress * 30.0
	pose.paddle_yaw_base_deg = progress * 40.0
	pose.paddle_roll_base_deg = 10.0
	pose.right_elbow_pole = Vector3(progress, 0.1, -progress)
	pose.body_yaw_deg = progress * 30.0
	return pose

func short_sample(definition: PostureDefinition, progress: float) -> PostureDefinition:
	var pose: PostureDefinition = definition.duplicate(true)
	pose.paddle_forehand_mul = 0.2 + progress * .02
	pose.paddle_forward_mul = .3
	pose.paddle_y_offset = .2
	return pose

func stationary_sample(definition: PostureDefinition, _progress: float) -> PostureDefinition:
	return definition.duplicate(true)

func head(pose: PostureDefinition) -> Vector3:
	return Path.canonical_transform(pose) * D.HEAD_OFFSET

func length_of(definition: PostureDefinition, sampler: Callable) -> float:
	var previous: Vector3 = head(sampler.call(definition, 0.0))
	var length := 0.0
	for index in range(1, 1201):
		var next: Vector3 = head(sampler.call(definition, index / 2400.0))
		length += previous.distance_to(next)
		previous = next
	return length

func run() -> void:
	var definition: PostureDefinition = PostureLibrary.instance().get_def(0).duplicate(true)
	definition.right_hand_offset = Vector3(.055, .02, -.04)
	definition.paddle_in_hand_rotation_deg = 42.0
	definition.main_grip_rotation_deg = 18.0
	definition.right_elbow_path = PackedVector3Array([Vector3(.1, 0, 0), Vector3(.2, .3, 0), Vector3(.1, .1, .1)])
	var inspector = Preview.new()
	var snapshot: PackedByteArray = var_to_bytes(inspector._resource_state(definition))
	inspector.free()
	var original_length: float = length_of(definition, curve_sample)
	for mode in [Variants.NORMAL, Variants.STRONG, Variants.WEAK]:
		var variant = Variants.new()
		variant.configure(definition, mode, curve_sample)
		check(not variant.report.limited, "unconstrained curve supports full mode %d" % mode)
		var length: float = length_of(definition, variant.sample)
		var difference: float = length - original_length
		var expected: float = 0.0 if mode == Variants.NORMAL else Variants.SIX_INCHES_M * (1.0 if mode == Variants.STRONG else -1.0)
		check(absf(difference - expected) < .001, "actual visible curve arc shifts six inches mode %d: %.6f" % [mode, difference])
		for index in range(101):
			var t: float = index / 100.0
			var sample: PostureDefinition = variant.sample(definition, t)
			var baseline: PostureDefinition = curve_sample(definition, t)
			check(head(sample).is_finite(), "finite sampled transform")
			check(sample.right_elbow_pole.is_equal_approx(baseline.right_elbow_pole) and is_equal_approx(sample.body_yaw_deg, baseline.body_yaw_deg), "authored body and elbow retain their clocks")
			check(sample.right_elbow_path == definition.right_elbow_path, "authored in-between array preserved")
			if t >= .5 or mode == Variants.NORMAL:
				check(Path.canonical_transform(sample).is_equal_approx(Path.canonical_transform(baseline)), "Contact and finish half exactly unchanged")
		var epsilon := 0.0001
		var before: Vector3 = (head(variant.sample(definition, .5)) - head(variant.sample(definition, .5 - epsilon))) / epsilon
		var normal: Vector3 = (head(curve_sample(definition, .5)) - head(curve_sample(definition, .5 - epsilon))) / epsilon
		check(before.distance_to(normal) < .015, "velocity smoothly rejoins original Contact mode %d" % mode)
	var weak = Variants.new()
	weak.configure(definition, Variants.WEAK, short_sample)
	check(weak.report.limited and weak.report.applied_distance_m < Variants.SIX_INCHES_M, "short curve honestly limits weak windup")
	var last := -INF
	for index in range(101):
		var sample: PostureDefinition = weak.sample(definition, index / 200.0)
		check(sample.paddle_forehand_mul >= last - .00001, "shortening a short path never reverses")
		last = sample.paddle_forehand_mul
	var still = Variants.new()
	still.configure(definition, Variants.STRONG, stationary_sample)
	check(still.report.limited and still.report.applied_distance_m == 0.0, "stationary path has no invented extension direction")
	var ready: PostureDefinition = PostureLibrary.instance().get_def(20).duplicate(true)
	still.configure(ready, Variants.STRONG)
	check(still.report.limited and still.sample(ready, 0.0).paddle_forehand_mul == still.sample(ready, 1.0).paddle_forehand_mul, "Ready remains static")

	var preview = Preview.new()
	preview.size = Vector2(640, 480)
	root.add_child(preview)
	await process_frame
	await process_frame
	check(var_to_bytes(preview._resource_state(definition)) == snapshot, "helpers never mutate authored resources")
	for serve in [false, true]:
		var ids: Array = range(7) if serve else range(20)
		for id in ids:
			var original: PostureDefinition = ServeStore.get_default(id) if serve else PostureLibrary.instance().get_def(id).duplicate(true)
			var sampler: Callable = ServeStore.sample if serve else Path.sample
			for mode in [Variants.STRONG, Variants.WEAK]:
				var variant = Variants.new()
				var began: int = Time.get_ticks_usec()
				variant.configure(original, mode, sampler, preview.player)
				print("VARIANT ", "serve " if serve else "stroke ", id, " ", variant.status_text(), " prepare ms=", (Time.get_ticks_usec() - began) / 1000.0)
				preview.set_motion_sampler(variant.sample)
				preview.show_pose(variant.sample(original, .27))
				preview.set_motion(original)
				for index in range(65):
					var t: float = index / 64.0
					var sample: PostureDefinition = variant.sample(original, t)
					preview.show_pose(sample)
					check(preview.sample_heads[index].distance_to(preview.joint_world_position("paddle")) < .00001, "variant rendered head equals overlay")
					for joint in ["right_hand", "right_elbow", "left_hand", "hips"]:
						check(preview.joint_samples[joint][index].distance_to(preview.joint_world_position(joint)) < .00001, "variant IK and joint curve agree: " + joint)
					if index in [0, 32, 64]:
						check(preview.ghost_transforms[index / 32].is_equal_approx(preview.player.paddle_node.global_transform), "variant ghost agrees with rig")
					if index >= 32:
						check(Path.world_transform(preview.player, sample).is_equal_approx(Path.world_transform(preview.player, sampler.call(original, t))), "real stroke or serve Contact onward unchanged")
	# Non-default Contact shaping remains part of the baseline exactly once.
	for serve in [false, true]:
		var original: PostureDefinition = ServeStore.get_default(0) if serve else PostureLibrary.instance().get_def(0).duplicate(true)
		var sampler: Callable = ServeStore.sample if serve else Path.sample
		for curve in [0.15, 0.85]:
			original.contact_curve = curve
			for mode in [Variants.STRONG, Variants.WEAK]:
				var variant = Variants.new()
				variant.configure(original, mode, sampler, preview.player)
				for index in [0, 32, 64, 96, 128]:
					var t: float = index / 256.0
					check(variant._transforms[index].is_equal_approx(Path.world_transform(preview.player, sampler.call(original, t))), "variant samples existing non-default Contact curve once")
				check(is_equal_approx(original.contact_curve, curve), "variant leaves Contact curve setting unchanged")
				check(Path.world_transform(preview.player, variant.sample(original, .5)).is_equal_approx(Path.world_transform(preview.player, sampler.call(original, .5))), "shaped curve Contact remains fixed")
	preview.queue_free()
	await process_frame
	print("MOBILE POSE WINDUP VARIANTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
