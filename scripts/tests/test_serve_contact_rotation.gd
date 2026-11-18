extends SceneTree
const Store = preload("res://scripts/mobile_serve_pose_store.gd")
const PoseStore = preload("res://scripts/mobile_pose_store.gd")
const Grips = preload("res://scripts/mobile_paddle_grip_store.gd")
const Preview = preload("res://scripts/ui/mobile_pose_preview.gd")
const Runtime = preload("res://scripts/posture_editor_v2/runtime_motion_preview.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Size = preload("res://scripts/paddle_dimensions.gd")
const Wrist = preload("res://scripts/paddle_wrist_reach.gd")
const Surface = preload("res://scripts/paddle_clearance.gd")
const Orientation = preload("res://scripts/stroke_preparation_orientation.gd")
const Contact = preload("res://scripts/serve_contact_orientation.gd")
var checks := 0
var failures: Array[String] = []
var preview
var save_path := ""
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	create_timer(100).timeout.connect(func(): quit(2))
	save_path = "user://pose_store_tests/serve_rotation_%d/serves.json" % OS.get_process_id()
	Store.set_test_path(save_path); Grips.set_test_path(save_path.replace("serves", "grips"))
	preview = Preview.new(); root.add_child(preview)
	await process_frame; await process_frame
	for style in range(7):
		var def: PostureDefinition = Store.get_default(style)
		var reference: PostureDefinition = Runtime.sample_serve(style, .5, 1, 1, null, false)
		var face := Size.HEAD_OFFSET + Vector3.BACK * Contact.CONTACT_DISTANCE
		var ball: Vector3 = Path.canonical_transform(reference) * face
		for field in Store.PADDLE_FIELDS.slice(3):
			check(Store.is_field_editable(1, field), "Contact exposes " + field)
			for degrees in [-8.0, 8.0]:
				for spin in [0.0, 7.0]:
					var edited: PostureDefinition = def.duplicate(true)
					edited.set(field, edited.get(field) + degrees)
					var component: int = Store.PADDLE_FIELDS.slice(3).find(field)
					edited.charge_paddle_rotation_deg[component] -= degrees
					edited.ft_paddle_rotation_deg[component] -= degrees
					edited.paddle_in_hand_rotation_deg = spin
					edited.main_grip_rotation_deg = spin - 9
					check(Store.save(edited) == OK, "all-axis spin/grip edit saves")
					check(Store.copy_values(edited, Store.get_def(style)) == OK, "rotation publishes")
					var sampled: PostureDefinition = Store.sample(edited, .5)
					check(is_equal_approx(sampled.get(field), edited.get(field)), "requested Contact axis remains active")
					check(is_equal_approx(sampled.paddle_in_hand_rotation_deg, spin), "Contact shaft spin is never silently removed")
					var frame: Transform3D = Path.canonical_transform(sampled)
					check((frame * face).distance_to(ball) < .000002, "displayed spun face pivots around fixed ball")
					check(absf(Surface.distance_to_head_shape(frame.affine_inverse() * ball) - Ball.BALL_RADIUS) < .000002, "finite head contact remains tangent")
					for side in [0, 1]:
						preview.player.player_num = side
						preview.show_pose(sampled)
						var player = preview.player
						var actual: Transform3D = player.paddle_node.global_transform
						var world_ball: Vector3 = player.global_position + player._get_forehand_axis() * ball.x + Vector3.UP * ball.y - player._get_forward_axis() * ball.z
						check(absf(Surface.distance_to_head_shape(actual.affine_inverse() * world_ball) - Ball.BALL_RADIUS) < .00001, "actual rig tangent both court sides")
						var wrist_gap: float = Wrist.displayed_wrist(player, sampled).distance_to(Wrist.wrist_world(actual, sampled))
						check(wrist_gap < .00001, "actual dominant hand remains seated")
						check(actual.basis.is_equal_approx(Path.paddle_basis(player, sampled)), "rendered axes equal persisted requested frame")
					check(PoseStore._encode_fields(Runtime.sample_serve(style, .5, 1)) == PoseStore._encode_fields(sampled), "live sampler equals unsaved preview")
					for t in [.0, .15, .49, .5, .51, .7, 1.0]:
						var pose: PostureDefinition = Store.sample(edited, t)
						check(Path.canonical_transform(pose).is_finite(), "finite complete rotation path")
					check(Store.reset(Store.get_def(style)) == OK and Store.copy_values(def, Store.get_def(style)) == OK, "reset restores authored rotation")
		var extreme: PostureDefinition = def.duplicate(true)
		extreme.paddle_pitch_base_deg += 180; extreme.paddle_yaw_base_deg += 90
		extreme.body_position_offset = Vector3(-2, 2, -2)
		check(not Store.contact_warning(extreme).is_empty(), "impossible orientation/body reach gives explicit warning")
		check(Store.contact_diagnostics(extreme).limited, "impossible orientation report remains available")
	# Store is right-handed by design; unsupported paddle-hand changes fail clearly.
	var invalid: PostureDefinition = Store.get_default(0); invalid.paddle_hand = 1
	check(Store.save(invalid) == ERR_INVALID_DATA, "unsupported handedness is rejected rather than silently ignored")
	DirAccess.remove_absolute(save_path)
	preview.queue_free(); await process_frame; await process_frame
	print("SERVE CONTACT ROTATION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
