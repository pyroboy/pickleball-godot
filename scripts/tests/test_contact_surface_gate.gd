extends SceneTree
const WristReach = preload("res://scripts/paddle_wrist_reach.gd")
const PaddleDimensions = preload("res://scripts/paddle_dimensions.gd")


const Geometry = preload("res://scripts/paddle_clearance.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
var checks: = 0
var failures: Array[String] = []
var hits: = 0
var grades: = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func prepare(game):
	var b = game.ball
	game.game_state = game.GameState.PLAYING
	b.freeze = true;b.is_in_play = true;b.last_hit_by = 1;b.both_bounces_complete = true
	b.bounces_since_last_hit = 1;b.ball_bounced_since_last_hit = true
	b._clear_paddle_collision_exception()

	var human = game.player_left.posture.human_contact
	human.phase = 1;human.elapsed = 0.0;human.hit = false;human.swing_flight_id = b.flight_id
func run():
	create_timer(15.0).timeout.connect( func(): push_error("Contact surface test timeout");quit(2))
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame; await process_frame
	game.player_left.posture.update_paddle_tracking(true)
	if game.player_left.posture.human_contact == null:
		push_error("Human contact controller failed initialization")
		quit(2)
		return
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.game_serve.cleanup()
	var p = game.player_left; var b = game.ball; var human = p.posture.human_contact
	p.hitting.serving_visual_active = false
	b.hit_by_paddle.connect( func(_id): hits += 1)
	p.posture.grade_flashed.connect( func(_grade): grades += 1)
	var rejected: = 0
	for id in [0, 2, 5, 7, 10, 14, 16]:
		for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.UP]:
			var pose = PostureLibrary.instance().get_def(id).duplicate(true)
			p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
			var tx: Transform3D = Path.world_transform(p, pose)
			var shift: Vector3 = WristReach.live_shoulder(p, pose) + direction * 0.699 - WristReach.wrist_world(tx, pose)
			pose.paddle_forehand_mul += shift.dot(p._get_forehand_axis());pose.paddle_forward_mul += shift.dot(p._get_forward_axis());pose.paddle_y_offset += shift.y
			p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
			for normal_sign in [-1.0, 1.0]:
				prepare(game)
				b.global_position = PaddleReach.head_world(p) + p.paddle_node.global_basis.z * 0.095 * normal_sign
				b.linear_velocity = - p.paddle_node.global_basis.z * normal_sign * 5
				if Geometry.contact_surface_pose(p, pose, b.global_position, b.linear_velocity, WristReach.live_shoulder(p, pose)) != null: continue
				rejected += 1;human.visual_pose = pose
				var before: Vector3 = b.linear_velocity; var flight: int = b.flight_id
				var audio = b.audio_synth.paddle_hit_player.stream
				var scores = Vector2i(game.score_left, game.score_right)
				check( not human._align_contact_surface(b), "unreachable tangent reports failure")
				check( not game._apply_player_contact_hit(0.5, id), "surface gap cannot become hit through center window")
				check(b.linear_velocity == before and b.flight_id == flight and b.last_hit_by == 1, "rejection leaves physical flight unchanged")
				check(Vector2i(game.score_left, game.score_right) == scores, "rejection leaves score unchanged")
				check(hits == 0 and grades == 0, "rejection emits no hit/grade")
				check(b.audio_synth.paddle_hit_player.stream == audio and b._contact_paddle_grace == 0.0, "rejection emits no audio/collision grace")
	check(rejected > 0, "constructed boundary actually exercised")
	var normal = PostureLibrary.instance().get_def(0).duplicate(true)
	p.posture.transition_pose_blend = normal;p.posture.force_posture_update(normal);prepare(game)
	b.global_position = PaddleReach.head_world(p) + p.paddle_node.global_basis.z * (Ball.BALL_RADIUS + PaddleDimensions.HEAD_HALF_THICKNESS)
	b.linear_velocity = - p.paddle_node.global_basis.z * 5;human.visual_pose = normal
	check(human._align_contact_surface(b), "reachable physical contact aligns")
	check(game._apply_player_contact_hit(0.5, 0), "reachable physical contact still accepted")
	check(hits == 1 and grades == 1, "accepted contact emits exactly once")
	game.queue_free(); await process_frame
	print("CONTACT SURFACE GATE: ", checks, " checks; ", rejected, " rejected-boundary cases; failures=", failures)
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	quit(0 if failures.is_empty() else 1)
