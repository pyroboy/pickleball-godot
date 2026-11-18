extends SceneTree

const Path = preload("res://scripts/stroke_swing_path.gd")
var checks: = 0
var failures: Array[String] = []
var maximum_step: = 0.0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok and failures.size() < 20: failures.append(label)
func run():
	create_timer(30).timeout.connect( func(): push_error("Elbow continuity timeout");quit(2))
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame; await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	var ready = PostureLibrary.instance().get_def(20)
	var explicit = ready.lerp_with(ready, 0)
	explicit.right_elbow_pole = Vector3(0.48, - 0.35, - 0.22);explicit.left_elbow_pole = Vector3( - 0.48, - 0.35, - 0.22)
	var unset = explicit.lerp_with(explicit, 0);unset.right_elbow_pole = Vector3.ZERO;unset.left_elbow_pole = Vector3.ZERO
	for actor in [game.player_left, game.player_right]:
		actor.hitting.clear_charge_visual()
		for reverse in [false, true]:
			var pose: PostureDefinition = unset if reverse else explicit
			var target: PostureDefinition = explicit if reverse else unset
			actor.posture.transition_pose_blend = pose;actor.posture.force_posture_update(pose)
			var previous: Array[Vector3] = [actor.right_arm_node.forearm_pivot.global_position, actor.left_arm_node.forearm_pivot.global_position]
			for step in range(180):
				pose = Path.blend_pose(pose, target, 0.12)
				actor.posture.transition_pose_blend = pose;actor.posture.force_posture_update(pose)
				for arm_index in [0, 1]:
					var arm = [actor.right_arm_node, actor.left_arm_node][arm_index]
					var elbow: Vector3 = arm.forearm_pivot.global_position
					var distance: float = elbow.distance_to(previous[arm_index]);maximum_step = maxf(maximum_step, distance)
					check(distance < 0.025, "court%d arm%d direction%s step%d elbow jump%.4fm" % [actor.player_num, arm_index, reverse, step, distance])
					check(arm.upper_pivot.global_position.distance_to(arm.hand_pivot.global_position) <= 0.705, "actual arm reach")
					previous[arm_index] = elbow

			actor.posture.transition_pose_blend = target;actor.posture.force_posture_update(target)
			check(actor.right_arm_node.forearm_pivot.global_position.distance_to(previous[0]) < 0.0001, "right endpoint same physical fallback")
			check(actor.left_arm_node.forearm_pivot.global_position.distance_to(previous[1]) < 0.0001, "left endpoint same physical fallback")
	check(unset.right_elbow_pole == Vector3.ZERO and unset.left_elbow_pole == Vector3.ZERO, "source unset fields preserved")
	check(explicit.right_elbow_pole == Vector3(0.48, - 0.35, - 0.22), "source explicit field preserved")
	for right in [false, true]:
		var pole = Vector3(0.2, - 0.4, 0.1)
		check(PostureDefinition.blend_elbow_pole(pole, Vector3.ZERO, 0, right) == pole, "start field preserved")
		check(PostureDefinition.blend_elbow_pole(pole, Vector3.ZERO, 1, right) == Vector3.ZERO, "end sentinel preserved")
		check(PostureDefinition.blend_elbow_pole(Vector3.ZERO, Vector3.ZERO, 0.5, right) == Vector3.ZERO, "unset to unset preserved")
	game.queue_free(); await process_frame
	print("ELBOW POLE CONTINUITY: ", checks, " checks; maxstep=", maximum_step, "; failures=", failures)
	quit(0 if failures.is_empty() else 1)
