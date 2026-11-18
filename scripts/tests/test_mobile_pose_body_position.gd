extends SceneTree
## Per-key body translation, fixed paddle targets, legacy data and actual IK.
const Store = preload("res://scripts/mobile_pose_store.gd")
const Serve = preload("res://scripts/mobile_serve_pose_store.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Key = preload("res://scripts/stroke_body_keyframe.gd")
const Preview = preload("res://scripts/ui/mobile_pose_preview.gd")
const WristReach = preload("res://scripts/paddle_wrist_reach.gd")
const Variants = preload("res://scripts/ui/mobile_pose_windup_variants.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func key(pose: PostureDefinition, offset: Vector3) -> Resource:
	var result := Key.new(); result.capture(pose)
	result.values.body_position_offset = offset
	return result
func edited() -> PostureDefinition:
	var pose: PostureDefinition = Store._export_packaged_default(0, false).duplicate(true)
	pose.body_position_offset = Vector3(.06, -.06, -.04)
	pose.windup_body = key(Path.endpoint(pose, 0), Vector3(-.02, -.04, -.02))
	pose.follow_through_body = key(Path.endpoint(pose, 2), Vector3(.03, -.03, .02))
	return pose
func floor_minimum(leg) -> float:
	var bounds: AABB = leg.foot_mesh.mesh.get_aabb()
	var result := INF
	for corner in range(8): result = minf(result, (leg.foot_mesh.global_transform * bounds.get_endpoint(corner)).y)
	return result
func run() -> void:
	var directory := "user://pose_store_tests/body_position_%d" % OS.get_process_id()
	Store.set_test_path(directory + "/poses.json"); Serve.set_test_path(directory + "/serves.json")
	var pose := edited()
	check("body_position_offset" in Key.FIELDS, "translation is a per-key channel")
	for original in PostureLibrary.new().definitions:
		var expected_position := Vector3(0.05700000002980232, 0, 0) if original.posture_id == 2 else Vector3.ZERO
		check(original.body_position_offset == expected_position, "packaged Contact matches approved Backhand offset or unchanged neutral default")
	var expected: Array[Vector3] = [pose.windup_body.values.body_position_offset, pose.body_position_offset, pose.follow_through_body.values.body_position_offset]
	for stage in range(3): check(Path.endpoint(pose, stage).body_position_offset.is_equal_approx(expected[stage]), "independent key %d" % stage)
	check(Path.sample(pose, .25).body_position_offset.is_equal_approx(expected[0].lerp(expected[1], .5)), "Wind-up interpolation")
	check(Path.sample(pose, .75).body_position_offset.is_equal_approx(expected[1].lerp(expected[2], .5)), "Finish interpolation")
	var no_offset: PostureDefinition = pose.duplicate(true)
	no_offset.body_position_offset = Vector3.ZERO
	no_offset.windup_body.values.body_position_offset = Vector3.ZERO
	no_offset.follow_through_body.values.body_position_offset = Vector3.ZERO
	for curve in [.0, .5, 1.0]:
		pose.contact_curve = curve; no_offset.contact_curve = curve
		for i in range(65):
			check(Path.canonical_transform(Path.sample(pose, i / 64.0)).is_equal_approx(Path.canonical_transform(Path.sample(no_offset, i / 64.0))), "body channel never translates authored paddle path")
	var fields := Store._encode_fields(pose)
	var legacy := fields.duplicate(true)
	legacy.erase("body_position_offset")
	for stage in ["windup_body", "follow_through_body"]: legacy[stage].erase("body_position_offset")
	check(Store._valid_fields(legacy, false), "old snapshots remain valid")
	var restored := edited(); Store._apply_fields(restored, legacy)
	for stage in range(3): check(Path.endpoint(restored, stage).body_position_offset == Vector3.ZERO, "legacy missing channel is zero")
	var invalid := fields.duplicate(true); invalid.body_position_offset = [0.0, NAN, 0.0]
	check(not Store._valid_fields(invalid, false), "nonfinite Contact translation rejected")
	invalid = fields.duplicate(true); invalid.windup_body.body_position_offset = [1.0, 2.0]
	check(not Store._valid_fields(invalid, false), "invalid nested translation rejected")
	check(Store.save(pose) == OK, "body edit persists")
	var reopened: PostureDefinition = PostureLibrary.new().get_def(0)
	for stage in range(3): check(Path.endpoint(reopened, stage).body_position_offset == expected[stage], "saved key reloads")
	var document: Dictionary = JSON.parse_string(Store.export_pose_json(pose, 0))
	check(document.fields.body_position_offset == Store._encode_value(pose.body_position_offset), "export contains Contact translation")
	check(Store._decode_value("body_position_offset", document.fields.windup_body.body_position_offset).is_equal_approx(expected[0]) and Store._decode_value("body_position_offset", document.fields.follow_through_body.body_position_offset).is_equal_approx(expected[2]), "export contains both endpoint translations")
	var ready: PostureDefinition = Store._export_packaged_default(20, false).duplicate(true)
	ready.body_position_offset = Vector3(.04, -.03, 0)
	check(Path.sample(ready, 0).body_position_offset == ready.body_position_offset and Path.sample(ready, 1).body_position_offset == ready.body_position_offset, "Ready translation stays static")
	var preview = Preview.new(); root.add_child(preview)
	var live = Preview.new(); root.add_child(live)
	await process_frame; await process_frame
	live.player.posture.editor_preview_mode = false
	for side in [0, 1]:
		preview.player.player_num = side; live.player.player_num = side
		for stage in range(3):
			var sample := Path.endpoint(pose, stage)
			live.player.leg_ik.feet_initialized = false
			var root_before: Transform3D = preview.player.global_transform
			preview.show_pose(sample); live.show_pose(sample)
			check(preview.player.global_transform == root_before, "pose never teleports player root")
			check(preview.player.body_pivot.global_transform.is_equal_approx(live.player.body_pivot.global_transform), "editor/live constrained body parity")
			for right in [true, false]:
				var a = preview.player.right_leg_node if right else preview.player.left_leg_node
				var b = live.player.right_leg_node if right else live.player.left_leg_node
				check(a.foot_pivot.global_position.distance_to(b.foot_pivot.global_position) < .00001, "editor/live settled feet parity")
				check(floor_minimum(a) >= PickleballConstants.FLOOR_Y - .00001, "translated pose sole stays above floor")
			check(preview.player.paddle_node.global_transform.is_equal_approx(Path.world_transform(preview.player, Path.endpoint(no_offset, stage))), "reachable paddle stays at fixed authored anchor")
			var captured: PostureDefinition = preview.player.posture.capture_displayed_pose()
			check(Body.pivot_transform(preview.player, captured).origin.distance_to(preview.player.body_pivot.position) < .00001, "capture does not double body translation")
		# Vertical translation has no effect on the authored foot targets.
		var high := pose.duplicate(true); high.body_position_offset.y = .3
		var low := pose.duplicate(true); low.body_position_offset.y = -.3
		var base := Vector3(0, preview.player.leg_ik.ANKLE_HEIGHT, 0)
		check(preview.player.leg_ik._stance_targets(high, base) == preview.player.leg_ik._stance_targets(low, base), "height changes leave target soles grounded")
		preview.show_pose(high)
		check(preview.player.body_pivot.position.y < Body.pivot_transform(preview.player, high).origin.y, "existing body-fit limits excessive upward motion")
		# Serve body edits at every key keep the existing initial foot planting.
		for style in range(7):
			var serve: PostureDefinition = Serve.get_default(style)
			serve.body_position_offset = Vector3(.02, -.03, -.02)
			serve.windup_body.values.body_position_offset = Vector3(-.01, -.02, 0)
			serve.follow_through_body.values.body_position_offset = Vector3(.03, -.01, .01)
			check(Serve.save(serve) == OK, "serve body channel saves")
			var initial := Serve.sample(serve, 0)
			live.show_pose(initial); live.player.leg_ik.initialize_serve_stance(initial)
			var foot_r: Vector3 = live.player.leg_ik.right_foot_smooth
			var foot_l: Vector3 = live.player.leg_ik.left_foot_smooth
			for stage in range(3):
				check(Serve.is_field_editable(stage, "body_position_offset"), "serve body offset editable at each key")
				var sample: PostureDefinition = Serve.sample(serve, stage * .5)
				preview.show_pose(sample)
				live.player.hitting.serving_visual_active = true; live.show_pose(sample)
				check(live.player.leg_ik.right_foot_smooth == foot_r and live.player.leg_ik.left_foot_smooth == foot_l, "live serve never replants for body movement")
				check(preview.player.leg_ik.right_foot_smooth.distance_to(foot_r) < .00001 and preview.player.leg_ik.left_foot_smooth.distance_to(foot_l) < .00001, "serve edited preview agrees with fixed planted feet")
				check(preview.player.body_pivot.global_transform.is_equal_approx(live.player.body_pivot.global_transform), "serve body-fit preview/live parity")
			live.player.hitting.serving_visual_active = false
	# Large requests cap the body, never move the pre-offset solved paddle.
	for side in [0, 1]:
		preview.player.player_num = side
		for id in [0, 2, 10, 20]:
			var base_pose: PostureDefinition = Store._export_packaged_default(id, false).duplicate(true)
			# Ground both comparisons; legacy anatomical error is not increased.
			base_pose.set_meta("mobile_serve_planted_stance", true)
			preview.show_pose(base_pose)
			var fixed: Transform3D = preview.player.paddle_node.global_transform
			var original_distance: float = WristReach.wrist_world(fixed, base_pose).distance_to(WristReach.live_shoulder(preview.player, base_pose))
			for offset in [Vector3(-5, 0, 0), Vector3(5, 0, 0), Vector3(0, 2, 0), Vector3(0, -2, 0), Vector3(0, 0, -5), Vector3(0, 0, 5), Vector3(.5, -.5, .5)]:
				var moved: PostureDefinition = base_pose.duplicate(true); moved.body_position_offset = offset
				preview.show_pose(moved)
				check(preview.player.paddle_node.global_transform.is_equal_approx(fixed), "excessive request keeps displayed Contact fixed")
				var report: Dictionary = Body.position_report(preview.player, moved)
				if offset.length() > 1.0: check(report.limited, "excessive request reports a body cap")
				var distance: float = WristReach.wrist_world(fixed, moved).distance_to(WristReach.live_shoulder(preview.player, moved))
				check(distance <= maxf(original_distance, WristReach.link_budget(preview.player, moved)) + .0001, "cap cannot worsen baseline arm reach")
				var body_before: Vector3 = preview.player.body_pivot.position
				for repeat in range(3): preview.player.leg_ik._solve_legs(0, moved)
				check(preview.player.body_pivot.position.distance_to(body_before) < .00001, "repeated support solve cannot accumulate translation cap")
				for leg in [preview.player.right_leg_node, preview.player.left_leg_node]:
					check(floor_minimum(leg) >= PickleballConstants.FLOOR_Y - .00001, "capped large request retains floor")
				moved.remove_meta("mobile_serve_planted_stance"); preview.show_pose(moved)
				check(preview.player.paddle_node.global_transform.is_equal_approx(fixed), "normal-stroke extreme body request also retains exact paddle target")
				PaddleReach.clamp_paddle_for_player(preview.player)
				check(preview.player.paddle_node.global_transform.is_equal_approx(fixed), "runtime reach refresh cannot move translated-pose Contact")
	# Changing the lead label does not jump either named foot mid-interpolation.
	var left_lead: PostureDefinition = no_offset.duplicate(true)
	left_lead.lead_foot = 1; left_lead.front_foot_forward = .25; left_lead.back_foot_back = -.2
	var right_lead: PostureDefinition = no_offset.duplicate(true)
	right_lead.lead_foot = 0; right_lead.front_foot_forward = .3; right_lead.back_foot_back = -.15
	var base_feet := Vector3(0, preview.player.leg_ik.ANKLE_HEIGHT, 0)
	var first_feet: Array[Vector3] = preview.player.leg_ik._stance_targets(left_lead, base_feet)
	var last_feet: Array[Vector3] = preview.player.leg_ik._stance_targets(right_lead, base_feet)
	for i in range(101):
		var t := i / 100.0
		var feet: Array[Vector3] = preview.player.leg_ik._stance_targets(left_lead.lerp_with(right_lead, t), base_feet)
		for index in range(2): check(feet[index].distance_to(first_feet[index].lerp(last_feet[index], t)) < .00001, "named-foot target stays continuous across lead swap")
	preview.player.player_num = 0
	for mode in [Variants.STRONG, Variants.WEAK]:
		var variant := Variants.new(); variant.configure(pose, mode, Path.sample, preview.player)
		for i in range(33):
			var t := i / 32.0
			check(variant.sample(pose, t).body_position_offset.is_equal_approx(Path.sample(pose, t).body_position_offset), "Strong/Weak keeps body clock")
		preview.set_motion_sampler(variant.sample); preview.set_motion(pose)
		for i in [0, 16, 32, 48, 64]:
			preview.show_pose(variant.sample(pose, i / 64.0))
			check(preview.joint_samples.hips[i].distance_to(preview.joint_world_position("hips")) < .00001, "body joint curve matches solved translated rig")
	preview.queue_free(); live.queue_free(); await process_frame
	DirAccess.remove_absolute(Store.storage_path()); DirAccess.remove_absolute(Serve.storage_path())
	print("MOBILE POSE BODY POSITION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
