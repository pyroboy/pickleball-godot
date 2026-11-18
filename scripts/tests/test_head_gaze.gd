extends SceneTree
const Gaze = preload("res://scripts/player_head_gaze.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
var checks: = 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(value: bool, message: String):
	checks += 1
	if not value: failures.append(message)

func run():
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await physics_frame
	await process_frame
	game.input_handler.set_process(false)
	game.game_serve.set_process(false)
	game.ball.set_physics_process(false)
	for player in [game.player_left, game.player_right]:
		player.set_process(false)
		player.set_physics_process(false)
		player.hitting.set_process(false)
		var gaze = Gaze.new()
		var head: Node3D = player.body_pivot.get_node("TorsoMesh/HeadMesh")
		var torso: Node3D = head.get_parent()
		var forward: Vector3 = player._get_forward_axis()
		for pose_id in [0, 2, 4, 20]:
			for stage in [0, 1, 2]:
				var pose = Path.endpoint(PostureLibrary.instance().get_def(pose_id), stage)
				player.posture.force_posture_update(pose)
				var paddle: Transform3D = player.paddle_node.global_transform
				var target: Vector3 = forward * 2.0 + player._get_forehand_axis() * 0.4 + Vector3.UP * 0.3
				game.ball.global_position = head.global_position + target
				gaze.update(player, game.ball, 1.0)
				var actual: Vector3 = head.global_transform.basis * forward
				check(actual.normalized().dot(target.normalized()) > 0.995, "gaze misses ball side%d pose%d stage%d" % [player.player_num, pose_id, stage])
				check(player.paddle_node.global_transform.is_equal_approx(paddle), "head tracking changes paddle/contact")
				for eye in head.get_children(): check(eye.position.dot(forward) > 0.1, "eye on back of head")
		var ready: PostureDefinition = PostureLibrary.instance().get_def(20).lerp_with(PostureLibrary.instance().get_def(20), 0)
		player.posture.force_posture_update(ready)
		game.ball.global_position = player.global_position - forward * 3.0 + Vector3.UP * 0.3
		gaze.update(player, game.ball, 1.0)
		var local_front: Vector3 = head.basis * forward
		check(local_front.dot(forward) >= -0.001, "neck must not spin backwards")
		ready.body_yaw_deg = Gaze.rest_body_yaw(player, game.ball, 1.0)
		player.posture.force_posture_update(ready)
		gaze.update(player, game.ball, 1.0)
		check((head.global_basis * forward).normalized().dot((game.ball.global_position - head.global_position).normalized()) > 0.995, "neutral body turn must assist behind-ball gaze")
		for vertical in [-10.0, 10.0]:
			game.ball.global_position = head.global_position + forward * 0.1 + Vector3.UP * vertical
			gaze.update(player, game.ball, 1.0)
			var local: Vector3 = head.basis * forward
			var pitch: float = atan2(local.y, Vector2(local.x, local.z).length())
			check(pitch <= Gaze.PITCH_UP_LIMIT + 0.001 and pitch >= - Gaze.PITCH_DOWN_LIMIT - 0.001, "high/low ball exceeds neck pitch")
		var before: Basis = head.basis
		game.ball.global_position = head.global_position
		gaze.update(player, game.ball, 1.0 / 60.0)
		check(head.basis.is_finite() and head.basis.is_equal_approx(before), "coincident ball destabilizes head")
		player.global_position.x += 5.0
		game.ball.global_position = head.global_position + forward * 2.0
		gaze.update(player, game.ball, 1.0 / 240.0)
		var expected: Basis = Gaze.local_gaze_basis(torso.global_basis, forward, game.ball.global_position - head.global_position)
		check(head.basis.is_equal_approx(expected), "teleport retained stale gaze")

	var halfway: Vector3 = Gaze.smooth_direction(Vector3.FORWARD, Vector3.BACK, 0.05)
	check(halfway.is_finite() and absf(halfway.length() - 1.0) < 1e-05, "antipodal gaze invalid")
	check(absf(halfway.x) > 0.1, "antipodal gaze did not turn")
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("HEAD GAZE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
