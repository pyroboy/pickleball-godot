extends SceneTree

const D = preload("res://scripts/paddle_dimensions.gd")
const G = preload("res://scripts/paddle_clearance.gd")
const W = preload("res://scripts/paddle_wrist_reach.gd")
var game
var checks: = 0
var failures: Array[String] = []
var rows: Array = []
var hits: = 0
var query: PhysicsShapeQueryParameters3D
func _initialize(): call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func run_case(label: String, local: Vector3, expected: bool, mode: String = "normal") -> void :
	game._reset_ball();game.game_serve.cleanup();game._set_game_state(game.GameState.PLAYING)
	var p = game.player_right
	var ai = p.ai_brain
	p.hitting.clear_charge_visual();p.hitting.serving_visual_active = false
	if p.hitting.paddle_swing_tween: p.hitting.paddle_swing_tween.kill()
	p.hitting.is_in_follow_through = false
	p.global_position = Vector3(0, p.ground_y, -1.7 if mode == "nvz" else -3.3)
	p.current_velocity = Vector3.ZERO;p.leg_ik.feet_initialized = false
	var pose: PostureDefinition = PostureLibrary.instance().get_def(0).duplicate(true)
	p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose);p.can_volley_from_feet()
	if mode == "overreach":
		var shift: Vector3 = W.live_shoulder(p, pose) + Vector3.RIGHT * 0.72 - W.wrist_world(p.paddle_node.global_transform, pose)
		pose.paddle_forehand_mul += shift.dot(p._get_forehand_axis());pose.paddle_forward_mul += shift.dot(p._get_forward_axis());pose.paddle_y_offset += shift.y
		p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
	ai.incoming_pose_override = pose;ai.ai_desired_posture = 0;ai._perception_ready = true
	ai.ai_is_charging = true;ai.ai_charge_time = 0.0;ai.ai_swing_threshold = 1.0
	ai.ai_hit_cooldown = 0.25 if mode == "cooldown" else 0.0
	ai.ai_selected_contact_reachable = false;ai.ai_selected_contact_time = 0.1
	ai.ai_predicted_contact_position = PaddleReach.head_world(p) + Vector3(0, 0, -1)
	ai.ai_ball_bounced_on_side = mode != "opening"
	var b = game.ball
	b.reset_rally_state();b.freeze = true;b.is_in_play = mode != "dead";b.last_hit_by = 1 if mode == "same_hitter" else 0
	b.both_bounces_complete = mode != "opening";b.bounces_since_last_hit = 0 if mode in ["opening", "nvz"] else (2 if mode == "second_bounce" else 1)
	b.ball_bounced_since_last_hit = b.bounces_since_last_hit > 0;b.flight_id += 1
	ai._observed_flight_id = b.flight_id - 1 if mode == "wrong_flight" else b.flight_id
	b.global_position = p.paddle_node.to_global(local);b.linear_velocity = - p.paddle_node.global_basis.z * 5;b.angular_velocity = Vector3.ZERO
	var point: Vector3 = b.global_position
	await physics_frame; await physics_frame
	query.transform = Transform3D(Basis.IDENTITY, point)
	var physical: Dictionary = {"head": false, "handle": false}
	for overlap in p.get_world_3d().direct_space_state.intersect_shape(query, 8):
		if overlap.collider != p.paddle_node: continue
		if overlap.shape == 0: physical.head = true
		elif overlap.shape == 1: physical.handle = true
	var before: int = hits
	var raw_gap: float = G.distance_to_head_shape(p.paddle_node.to_local(point)) - Ball.BALL_RADIUS
	var center_distance: float = PaddleReach.head_world(p).distance_to(point)
	ai._try_ai_hit_ball()
	var returned: bool = hits > before
	check(returned == expected, label + " registered contact result")
	if expected:
		check(physical.head and not physical.handle, label + " independent real-head overlap")
		check(center_distance > 0.1, label + " not beyond old center shortcut")
		check(raw_gap <= G.contact_surface_tolerance(), label + " raw head gap")
		check(hits == before + 1, label + " singular registered hit")
		check(ai.ai_predicted_contact_position.distance_to(point) > 0.34, label + " indicator-distance fixture")
	else:
		check(b.last_hit_by == (1 if mode == "same_hitter" else 0), label + " rejected contact changed hitter")
	rows.append({"label": label, "mode": mode, "returned": returned, "physical": physical, "raw_gap": raw_gap, "center_distance": center_distance})
func run() -> void :
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.player_right.paddle_node.process_mode = Node.PROCESS_MODE_ALWAYS
	game.ball.hit_by_paddle.connect( func(team):
		if team == 1: hits += 1
	)
	query = PhysicsShapeQueryParameters3D.new();query.collision_mask = 4;query.margin = 0
	var sphere: = SphereShape3D.new();sphere.radius = Ball.BALL_RADIUS;query.shape = sphere
	var center: = Vector3(0, D.HEAD_CENTER_Y, 0.0445)
	await run_case("AI upper face", center + Vector3(0, 0.1, 0), true)
	await run_case("AI lower face", center - Vector3(0, 0.1, 0), true)
	await run_case("AI rim", Vector3(D.HEAD_RADIUS + Ball.BALL_RADIUS - 0.001, D.HEAD_CENTER_Y, 0), true)
	await run_case("AI handle only", Vector3(0.006319, 0.130699, - 0.052816), false)
	await run_case("AI separated", center + Vector3(0, 0, 0.02), false)
	await run_case("AI remote", center + Vector3(1, 0, 0), false)
	for mode in ["overreach", "dead", "same_hitter", "cooldown", "opening", "nvz", "second_bounce", "wrong_flight"]:
		await run_case("AI " + mode, center, false, mode)
	var file = FileAccess.open("/tmp/ai-finite-head-gate.json", FileAccess.WRITE);file.store_string(JSON.stringify({"checks": checks, "failures": failures, "rows": rows}, "\t"));file.close()
	game.queue_free(); await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	for failure in failures: push_error(failure)
	print("AI FINITE HEAD GATE: %d checks, %d failures; contacts=%d" % [checks, failures.size(), hits])
	quit(0 if failures.is_empty() else 1)
