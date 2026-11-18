extends SceneTree


const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Rule = preload("res://scripts/player_nvz_state.gd")
var checks: = 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func verify(p, label: String):
	var grip: Vector3 = p.paddle_node.to_global(PaddleSize.MAIN_GRIP_OFFSET)
	check(p.right_arm_node.hand_pivot.global_position.distance_to(grip) < 0.001, label + " grip solved in same callback")
	for foot in Rule.footprints(p):
		check(foot.min.y >= PickleballConstants.FLOOR_Y - 0.002, label + " shoe stays above court")
		check(foot.min.y <= PickleballConstants.FLOOR_Y + 0.015, label + " planted shoe stays grounded")
func run():
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game)
	await process_frame; await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.game_serve.cleanup()
	for p in [game.player_left, game.player_right]:
		p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false
		p.current_velocity = Vector3.ZERO
		var ready = PostureLibrary.instance().get_def(20)
		p.posture.transition_pose_blend = ready;p.posture.force_posture_update(ready)
		p.leg_ik.update_leg_ik(0.3, ready)
		for id in [0, 2, 5, 7, 13, 14, 3, 4, 20]:
			var pose = PostureLibrary.instance().get_def(id)
			p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
			verify(p, "pose%d p%d" % [id, p.player_num])
		p.posture.transition_pose_blend = ready;p.posture.force_posture_update(ready)
		p.hitting.is_in_follow_through = true
		p.hitting._on_paddle_release_finished()
		verify(p, "completion p%d" % p.player_num)
		p.global_position.x += 2.0
		p.posture.force_posture_update(ready)
		verify(p, "reset teleport p%d" % p.player_num)
		check(p.right_arm_node.global_position.y > 1.0, "teleport must not compress body toward stale feet")
	game.queue_free(); await process_frame
	print("POSE PRESENTATION ORDER: ", checks, " checks; failures=", failures)
	quit(0 if failures.is_empty() else 1)
