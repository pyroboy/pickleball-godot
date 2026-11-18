extends SceneTree
## Actual rig/editor validation for every authored stroke and both court directions.
const Path = preload("res://scripts/stroke_swing_path.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
var failures: Array[String] = []
var checks: int = 0
func _initialize(): call_deferred("run")
func check(value: bool, message: String):
	checks += 1
	if not value: failures.append(message)
func run():
	create_timer(40).timeout.connect(func(): quit(2))
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await physics_frame
	await process_frame
	game._toggle_posture_editor_v2()
	var editor = game.posture_editor_v2
	for def in PostureLibrary.instance().all_definitions():
		var tag: String = def.display_name
		check(def.windup_body != null and def.follow_through_body != null, tag + " lacks body keyframes")
		if def.family == 1: check(def.paddle_hand == 1 and def.left_hand_mode == 4, tag + " ignores left hand/released support")
		if def.has_zone:
			check(def.paddle_forward_mul > 0, tag + " contact is behind player")
			var height: float = 1.0 + def.paddle_y_offset - PickleballConstants.FLOOR_Y
			check(height >= def.zone_y_min - 0.03 and height <= def.zone_y_max + 0.03, tag + " contact head outside height area")
			check(def.paddle_forehand_mul >= def.zone_x_min and def.paddle_forehand_mul <= def.zone_x_max, tag + " contact head outside lateral area")
			if def.family in [0, 1] and def.height_tier == 2:
				check(Path.endpoint(def, 0).paddle_forward_mul < 0, tag + " wind-up never loads behind body")
				check(Path.endpoint(def, 2).paddle_forehand_mul * def.paddle_forehand_mul < 0, tag + " finish never crosses body")
			if def.family == 3: check(Path.endpoint(def, 2).paddle_y_offset < def.paddle_y_offset - 0.3, tag + " overhead does not swing down")
		for player in [game.player_left, game.player_right]:
			var maximum_grip: float = 0
			var maximum_clip: float = 0
			var maximum_support: float = 0
			for step in range(41):
				var pose = Path.sample(def, step / 40.0)
				var transform = Path.world_transform(player, pose)
				var grip: Vector3 = transform * Vector3(0, 0.07, 0)
				var head: Vector3 = transform * Vector3(0, 0.4, 0)
				var raw_head: Vector3 = player.global_position + pose.resolve_paddle_offset(player._get_forehand_axis(), player._get_forward_axis())
				maximum_grip = maxf(maximum_grip, grip.distance_to(Body.shoulder_world(player, pose)))
				maximum_clip = maxf(maximum_clip, raw_head.distance_to(head))
				player.paddle_node.global_transform = transform
				var support: Vector3 = player.arm_ik.get_support_hand_target(pose)
				var offset: Vector3 = pose.right_hand_offset if pose.paddle_hand == 1 else pose.left_hand_offset
				support += player._get_forehand_axis() * offset.x + Vector3.UP * offset.y + player._get_forward_axis() * offset.z
				var support_pose = pose.duplicate()
				support_pose.paddle_hand = 1 - pose.paddle_hand
				maximum_support = maxf(maximum_support, support.distance_to(Body.shoulder_world(player, support_pose)))
				check(head.y >= player.COURT_FLOOR_Y + pose.paddle_floor_clearance - 0.001, tag + " paddle under floor")
				check(head.distance_to(Body.shoulder_world(player, pose)) <= PaddleReach.MAX_HEAD_DISTANCE + 0.001, tag + " paddle exceeds reach")
			check(maximum_grip <= 0.71, "%s player%d grip too far %.3f m" % [tag, player.player_num, maximum_grip])
			check(maximum_support <= 0.71, "%s player%d support arm too far %.3f m" % [tag, player.player_num, maximum_support])
			check(maximum_clip <= 0.015, "%s player%d curve requires clipping %.3f m" % [tag, player.player_num, maximum_clip])
			print("POSE REACH %s player%d grip=%.3f clip=%.3f" % [tag, player.player_num, maximum_grip, maximum_clip])
		# Real keyframe selection must match the same preview used in gameplay.
		editor._on_posture_selected(PostureLibrary.instance().all_definitions().find(def))
		for stage in range(3):
			editor._select_keyframe(stage)
			await process_frame
			await process_frame
			var expected = Path.world_transform(game.player_left, Path.endpoint(def, stage))
			check(game.player_left.paddle_node.global_transform.is_equal_approx(expected), "%s stage%d editor drift" % [tag, stage])
			var pose = game.player_left.posture.transition_pose_blend
			check(pose != null, tag + " missing body preview")
			if pose:
				check(game.player_left.body_pivot.transform.is_equal_approx(Body.pivot_transform(game.player_left, pose)), tag + " body ignores selected keyframe")
				var foot = game.player_left.left_leg_node.foot_pivot
				check(absf(foot.global_position.y - (game.player_left.COURT_FLOOR_Y + 0.04)) < 0.02, tag + " foot floats during preview")
		var file: String = "user://stroke_%d_keyframes_test.tres" % def.posture_id
		check(ResourceSaver.save(def, file) == OK, tag + " cannot serialize")
		var reloaded = ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_IGNORE)
		check(reloaded != null and reloaded.windup_body != null and reloaded.follow_through_body != null, tag + " loses body keyframes after reload")
		if reloaded:
			check(Path.endpoint(reloaded, 0).resolve_paddle_offset(Vector3.RIGHT, Vector3.FORWARD).is_equal_approx(Path.endpoint(def, 0).resolve_paddle_offset(Vector3.RIGHT, Vector3.FORWARD)), tag + " loses wind-up after reload")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	game.queue_free()
	await process_frame
	for message in failures: push_error(message)
	print("ALL STROKE POSES: %d checks, %d failures; 21 poses in both court directions" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
