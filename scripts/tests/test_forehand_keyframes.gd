extends SceneTree
const SwingPath = preload("res://scripts/stroke_swing_path.gd")
const BodyPose = preload("res://scripts/stroke_body_pose.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func run() -> void:
	create_timer(25.0).timeout.connect(func(): quit(2))
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await physics_frame
	await process_frame
	game._toggle_posture_editor_v2()
	var editor = game.posture_editor_v2
	editor._on_posture_selected(0)
	var def: PostureDefinition = editor._current_def
	check(not editor._reach_visual.visible, "reach overlay ignores default-off switch")
	editor._show_reach_limits.button_pressed = true
	check(editor._reach_visual.visible, "reach switch does not show boundary")
	editor._show_reach_limits.button_pressed = false
	check(not editor._reach_visual.visible, "reach switch does not hide boundary")
	var before: PostureDefinition = def.duplicate(true)
	var windup: PostureDefinition = SwingPath.endpoint(def, 0)
	var finish: PostureDefinition = SwingPath.endpoint(def, 2)
	check(windup.paddle_forward_mul < -0.2, "forehand wind-up is not behind body")
	check(def.paddle_forward_mul > 0.3, "contact is not in front")
	check(finish.paddle_forehand_mul < -0.15 and finish.paddle_forward_mul > 0.2 and finish.paddle_y_offset > def.paddle_y_offset + 0.3, "finish must cross upward to opposite shoulder")
	check(def.lead_foot == 1 and def.left_hand_mode == 4, "forehand needs left foot leading and support hand released")
	for player in [game.player_left, game.player_right]:
		var maximum_hand_distance: float = 0
		for step in range(65):
			var pose: PostureDefinition = SwingPath.sample(def, step / 64.0)
			var transform: Transform3D = SwingPath.world_transform(player, pose)
			var hand: Vector3 = transform * Vector3(0, 0.07, 0)
			maximum_hand_distance = maxf(maximum_hand_distance, hand.distance_to(BodyPose.shoulder_world(player, pose)))
			check(hand.distance_to(BodyPose.shoulder_world(player, pose)) <= 0.71, "tuned forehand stretches arm at sample %d, player %d" % [step, player.player_num])
			var head: Vector3 = transform * Vector3(0, 0.4, 0)
			check(head.y >= player.COURT_FLOOR_Y + pose.paddle_floor_clearance, "paddle crosses floor")
		print("FOREHAND HAND REACH player %d: %.3f m" % [player.player_num, maximum_hand_distance])
	# Keep the selected stage stable after several rendered/physics frames.
	for stage in [0, 1, 2]:
		editor._select_keyframe(stage)
		await create_timer(0.35).timeout
		var actual: Transform3D = game.player_left.paddle_node.global_transform
		var expected: Transform3D = SwingPath.world_transform(game.player_left, SwingPath.endpoint(def, stage))
		check(actual.is_equal_approx(expected), "stage preview drifts after waiting, stage %d" % stage)
	# Actual control signal paths for three body and paddle keyframes.
	for stage in [0, 1, 2]:
		editor._select_keyframe(stage)
		editor._select_section(0)
		var old_hip: float = SwingPath.endpoint(def, stage).hip_yaw_deg
		editor._body_tab._widgets["hip_yaw_deg"]._spin.value = old_hip + 3
		check(is_equal_approx(SwingPath.endpoint(def, stage).hip_yaw_deg, old_hip + 3), "hip edit misses selected keyframe")
		if stage != 1: check(is_equal_approx(def.hip_yaw_deg, before.hip_yaw_deg), "wind-up/finish changes contact hip")
		await process_frame
		var pose: PostureDefinition = game.player_left.posture.transition_pose_blend
		check(is_equal_approx(game.player_left.body_pivot.get_node("HipsMesh").rotation_degrees.y, pose.hip_yaw_deg * game.player_left._get_swing_sign()), "visible hips ignore authored rotation")
		editor._body_tab._widgets["torso_yaw_deg"]._spin.value += 5
		editor._body_tab._widgets["head_yaw_deg"]._spin.value += 4
		editor._body_tab._widgets["right_foot_yaw_deg"]._spin.value += 6
		await process_frame
		pose = game.player_left.posture.transition_pose_blend
		var torso = game.player_left.body_pivot.get_node("TorsoMesh")
		check(torso.transform.is_equal_approx(BodyPose.torso_transform(game.player_left, pose)), "visible torso ignores keyframe")
		check(is_equal_approx(torso.get_node("HeadMesh").rotation_degrees.y, pose.head_yaw_deg * game.player_left._get_swing_sign()), "visible head ignores keyframe")
		var foot = game.player_left.right_leg_node.foot_pivot
		check(absf(foot.global_position.y - (game.player_left.COURT_FLOOR_Y + 0.04)) < 0.02, "authored foot is not planted")
		editor._select_section(1)
		var old_x: float = SwingPath.endpoint(def, stage).paddle_forehand_mul
		editor._paddle_tab._widgets["paddle_forehand_mul"]._spin.value = old_x + 0.02
		check(is_equal_approx(SwingPath.endpoint(def, stage).paddle_forehand_mul, old_x + 0.02), "paddle edit misses selected keyframe")
		if stage != 1: check(is_equal_approx(def.paddle_forehand_mul, before.paddle_forehand_mul), "endpoint paddle edit changes contact")
		editor._paddle_tab._widgets["paddle_pitch_base_deg"]._spin.value += 7
		await process_frame
		var expected: Transform3D = SwingPath.world_transform(game.player_left, SwingPath.endpoint(def, stage))
		check(game.player_left.paddle_node.global_transform.is_equal_approx(expected), "visible paddle does not match selected keyframe")
		# Persistent nested keyframes must survive resource serialization and repeatable revert.
		var path: String = "user://forehand_keyframe_test.tres"
		check(ResourceSaver.save(def, path) == OK, "keyframe save failed")
		var reloaded: PostureDefinition = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		check(is_equal_approx(SwingPath.endpoint(reloaded, stage).hip_yaw_deg, old_hip + 3), "body keyframe did not reload")
		check(is_equal_approx(SwingPath.endpoint(reloaded, stage).paddle_forehand_mul, old_x + 0.02), "paddle keyframe did not reload")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		editor._on_revert_pose()
		check(is_equal_approx(SwingPath.endpoint(def, stage).hip_yaw_deg, old_hip), "nested revert failed")
	# Shoulder rotation steers the elbow while keeping the gripping hand on the paddle.
	editor._select_keyframe(1)
	editor._select_section(0)
	await process_frame
	var arm = game.player_left.right_arm_node
	var elbow_before: Vector3 = arm.forearm_pivot.global_position
	var shoulders = editor._body_tab._widgets["right_shoulder_rotation_deg"]
	shoulders._y_spin.value += 25
	await process_frame
	check(arm.forearm_pivot.global_position.distance_to(elbow_before) > 0.01, "shoulder control has no visible elbow effect")
	check(arm.hand_pivot.global_position.distance_to(game.player_left.paddle_node.to_global(Vector3(0, 0.07, 0))) < 0.02, "shoulder edit loses grip")
	editor._on_revert_pose()
	# Test real gizmo path at non-contact stages.
	for stage in [0, 2]:
		editor._select_keyframe(stage)
		var pose: PostureDefinition = SwingPath.endpoint(def, stage)
		var head: Vector3 = game.player_left.global_position + pose.resolve_paddle_offset(game.player_left._get_forehand_axis(), game.player_left._get_forward_axis())
		editor._on_gizmo_moved("paddle_position", head + Vector3.UP * 0.025)
		check(is_equal_approx(SwingPath.endpoint(def, stage).paddle_y_offset, pose.paddle_y_offset + 0.025), "gizmo edits wrong keyframe")
		check(is_equal_approx(def.paddle_y_offset, before.paddle_y_offset), "endpoint gizmo edits contact")
		editor._on_revert_pose()
	# Holding and releasing partial charge must begin from the same full-body state.
	editor._select_keyframe(1)
	editor.close()
	var player = game.player_left
	player.paddle_posture = 0
	for ratio in [0.25, 0.5, 1.0]:
		player.hitting.set_serve_charge_visual(ratio)
		var held: PostureDefinition = player.posture.transition_pose_blend
		check(is_equal_approx(held.paddle_forward_mul, lerpf(def.paddle_forward_mul, windup.paddle_forward_mul, ratio)), "charge ratio applied more than once")
		check(is_equal_approx(held.hip_yaw_deg, lerpf(def.hip_yaw_deg, windup.hip_yaw_deg, ratio)), "charge body ignores ratio")
		player.hitting._animate_authored_swing(0, ratio)
		check(is_equal_approx(player.posture.transition_pose_blend.hip_yaw_deg, held.hip_yaw_deg), "release body snaps from partial charge")
		check(is_equal_approx(player.posture.transition_pose_blend.paddle_forward_mul, held.paddle_forward_mul), "release paddle snaps from partial charge")
		player.hitting.clear_charge_visual()
	check(player.posture.transition_pose_blend == null, "aborted charge leaves stale preview override")
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("FOREHAND KEYFRAMES: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
