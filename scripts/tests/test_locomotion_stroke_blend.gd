extends SceneTree


const Body = preload("res://scripts/stroke_body_pose.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
var checks: = 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok and failures.size() < 30: failures.append(label)
func run():
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	for player in [game.player_left, game.player_right]:
		player.posture.editor_preview_mode = false
		for heading in [-120.0, -55.0, 55.0, 120.0]:
			for posture_id in [0, 2, 3]:
				var ready: PostureDefinition = PostureLibrary.instance().get_def(20)
				var contact: PostureDefinition = PostureLibrary.instance().get_def(posture_id)
				player.leg_ik.locomotion_mode = "run";player.leg_ik.locomotion_hip_yaw_deg = heading
				player.leg_ik.locomotion_body_weight = 1.0 # Established run fixture
				player.hitting.charge_visual_active = false;player.hitting.serving_visual_active = false;player.hitting.is_in_follow_through = false
				player.posture._committed_incoming_posture = -1
				var initial_pelvis: Basis = Body.pelvis_transform(player, ready).basis
				var initial_shoulder: Vector3 = Body.shoulder_world(player, ready)
				player.hitting.charge_visual_active = true
				player.posture._committed_incoming_posture = posture_id
				var exact_contact: Transform3D = Path.world_transform(player, contact)
				var previous: Basis = initial_pelvis
				for step in range(101):
					var pose: PostureDefinition = Path.blend_pose(ready, contact, step / 100.0)
					var pelvis: Basis = Body.pelvis_transform(player, pose).basis
					if step == 0:
						check(pelvis.is_equal_approx(initial_pelvis), "claiming stroke owner preserves displayed pelvis on first blend frame")
						check(Body.shoulder_world(player, pose).distance_to(initial_shoulder) < 1e-05, "first preparation frame preserves shoulder query")
					else: check(rad_to_deg(previous.get_rotation_quaternion().angle_to(pelvis.get_rotation_quaternion())) < 3.0, "travel pelvis turns continuously into authored stroke")
					if step == 100:
						check(Path.world_transform(player, pose).is_equal_approx(exact_contact), "locomotion contributes zero to exact contact")
						check(pelvis.is_equal_approx(Body.pelvis_transform(player, contact).basis), "contact retains authored pelvis")
					previous = pelvis
	print("LOCOMOTION STROKE BLEND: ", checks, " checks, ", failures.size(), " failures")
	for failure in failures: push_error(failure)
	game.queue_free(); await process_frame;quit(0 if failures.is_empty() else 1)
