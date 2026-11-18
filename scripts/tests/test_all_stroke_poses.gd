extends SceneTree

const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Wrist = preload("res://scripts/tests/pose_anatomical_wrist.gd")
const WristReach = preload("res://scripts/paddle_wrist_reach.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const StrikingSide = preload("res://scripts/tests/test_hand_striking_side_semantics.gd")
var failures: Array[String] = []
var checks: int = 0
func _initialize(): call_deferred("run")
func check(value: bool, message: String):
	checks += 1
	if not value: failures.append(message)
func run():
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	create_timer(40).timeout.connect( func(): quit(2))
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
		var linked: bool = def.posture_id in [2, 9]
		if def.family == 1:
			check(def.paddle_hand == 0, tag + " must retain right dominant hand")
			check(def.left_hand_mode == (1 if linked else 4), tag + " linked standard backhand/free wide-low support contract")
		if linked:
			check(is_equal_approx(def.support_grip_style, 1.0), tag + " uses blade-clearing support articulation")
		if def.has_zone:
			check(def.paddle_forward_mul > 0, tag + " contact is behind player")
			var height: float = 1.0 + def.paddle_y_offset - PickleballConstants.FLOOR_Y
			check(height >= def.zone_y_min - 0.03 and height <= def.zone_y_max + 0.03, tag + " contact head outside height area")
			check(def.paddle_forehand_mul >= def.zone_x_min and def.paddle_forehand_mul <= def.zone_x_max, tag + " contact head outside lateral area")
			if def.family in [0, 1] and def.height_tier == 2:
				check(Path.endpoint(def, 0).paddle_forward_mul < 0, tag + " wind-up never loads behind body")
				if linked:
					check(Path.endpoint(def, 2).paddle_forehand_mul > def.paddle_forehand_mul, tag + " joined finish does not move inward")
					check(Path.endpoint(def, 2).paddle_forward_mul > def.paddle_forward_mul, tag + " joined finish does not extend forward")
				else:
					check(Path.endpoint(def, 2).paddle_forehand_mul * def.paddle_forehand_mul < 0, tag + " finish never crosses body")
			if def.family == 3: check(Path.endpoint(def, 2).paddle_y_offset < def.paddle_y_offset - 0.3, tag + " overhead does not swing down")
		for player in [game.player_left, game.player_right]:
			var maximum_grip: float = 0
			var maximum_clip: float = 0
			var maximum_support: float = 0
			for step in range(41):
				var pose = Path.sample(def, step / 40.0)
				var transform = Path.world_transform(player, pose)
				var grip: Vector3 = Wrist.main_world(player, pose)
				var head: Vector3 = transform * PaddleSize.HEAD_OFFSET
				var raw_head: Vector3 = player.global_position + pose.resolve_paddle_offset(player._get_forehand_axis(), player._get_forward_axis())
				maximum_grip = maxf(maximum_grip, grip.distance_to(Body.shoulder_world(player, pose)))
				maximum_clip = maxf(maximum_clip, raw_head.distance_to(head))
				var support: Vector3 = Wrist.support_world(player, pose)
				var support_pose = pose.duplicate()
				support_pose.paddle_hand = 1 - pose.paddle_hand
				maximum_support = maxf(maximum_support, support.distance_to(Body.shoulder_world(player, support_pose)))
				check(head.y >= player.COURT_FLOOR_Y + pose.paddle_floor_clearance - 0.001, tag + " paddle under floor")
				check(head.distance_to(Body.shoulder_world(player, pose)) <= PaddleReach.MAX_HEAD_DISTANCE + 0.001, tag + " paddle exceeds reach")
				if linked:
					player.posture.transition_pose_blend = pose
					player.posture.force_posture_update(pose)
					var mounted_main: Vector3 = WristReach.displayed_wrist(player, pose)
					var mounted_support: Vector3 = player.left_arm_node.hand_mesh.global_transform * player.left_arm_node.articulated_hand.wrist_socket
					check(mounted_main.distance_to(WristReach.wrist_world(player.paddle_node.global_transform, pose)) < 1e-05, tag + " rendered/pure main socket mismatch")
					check(mounted_support.distance_to(support) < 1e-05, tag + " rendered/pure support socket mismatch")
					check(pose.left_hand_mode == 1 and pose.left_hand_offset.is_zero_approx(), tag + " support leaves the joined shaft")
					for arm in [player.right_arm_node, player.left_arm_node]:
						var wrist: Vector3 = arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket
						var shoulder: Vector3 = arm.upper_pivot.global_position
						var elbow: Vector3 = arm.forearm_pivot.global_position
						check(absf(shoulder.distance_to(elbow) - arm.upper_arm_length) < 1e-05 and absf(elbow.distance_to(wrist) - arm.forearm_length) < 1e-05, "%s player%d sample%d fixed arm links" % [tag, player.player_num, step])
						var channels: Dictionary = Anatomy.decompose(Anatomy.forearm_reference_for_arm(arm, wrist, arm == player.left_arm_node), arm.hand_mesh.global_basis * arm.articulated_hand.anatomical_basis, arm.articulated_hand.radial_sign)
						check(channels.within_animation_budget, "%s player%d sample%d %s wrist budget %s" % [tag, player.player_num, step, arm.name, channels])
					if def.posture_id == 2 and step == 20:
						check(head.distance_to(raw_head) < 1e-05, tag + " exact original contact head is clipped")
						var face: Vector3 = player.paddle_node.global_basis.z
						if face.dot(player._get_forward_axis()) < 0.0: face = - face
						check(StrikingSide.contact_side(player.right_arm_node.articulated_hand, player.right_arm_node.hand_mesh.global_basis, face, false).matches, tag + " dominant dorsal surface must lead contact")
						check(StrikingSide.contact_side(player.left_arm_node.articulated_hand, player.left_arm_node.hand_mesh.global_basis, face, true).matches, tag + " support palmar surface must lead contact")
			check(maximum_grip <= 0.71, "%s player%d grip too far %.3f m" % [tag, player.player_num, maximum_grip])
			check(maximum_support <= 0.71, "%s player%d support arm too far %.3f m" % [tag, player.player_num, maximum_support])
			check(maximum_clip <= 0.015, "%s player%d curve requires clipping %.3f m" % [tag, player.player_num, maximum_clip])
			print("POSE REACH %s player%d grip=%.3f clip=%.3f" % [tag, player.player_num, maximum_grip, maximum_clip])

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
			if linked:
				for field in ["main_grip_rotation_deg", "support_grip_rotation_deg", "support_grip_slide_m", "support_index_closure", "support_grip_style"]:
					check(is_equal_approx(reloaded.get(field), def.get(field)), tag + " loses linked " + field + " after reload")
				check(reloaded.right_elbow_path == def.right_elbow_path and reloaded.left_elbow_path == def.left_elbow_path, tag + " loses linked elbow route after reload")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	game.queue_free()
	await process_frame
	for message in failures: push_error(message)
	print("ALL STROKE POSES: %d checks, %d failures; 21 poses in both court directions" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
