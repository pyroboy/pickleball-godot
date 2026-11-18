extends SceneTree

const IK = preload("res://scripts/player_leg_ik.gd")
const Scorer = preload("res://scripts/rally_scorer.gd")
const Planner = preload("res://scripts/incoming_contact_planner.gd")
const LegTests = preload("res://scripts/tests/test_player_leg_ik.gd")
const FakeBallScript = preload("res://scripts/tests/fakes/fake_ball.gd")
class AirPlayer extends LegTests.MockPlayer:
	var is_jumping: = false
	var ground_y: = 1.0
	var jump_landing_remaining: = 0.0
	var jump_takeoff_position: = Vector3.ZERO
	var leg_ik
var failures: Array[String] = []
var checks: = 0
func check(condition: bool, label: String) -> void :
	checks += 1
	if not condition: failures.append(label)
func _initialize() -> void : call_deferred("run")
func step_jump(p, delta: float) -> void :
	p._update_jump_state(delta)
	p.global_position.y += p.vertical_velocity * delta
	if p.global_position.y <= p.ground_y:
		p.global_position.y = p.ground_y
		p.vertical_velocity = 0.0
		p.is_jumping = false
func prepare(game, p, side: int) -> Dictionary:
	p.player_num = side
	p.global_position = Vector3(0, p.ground_y, 3.5 if side == 0 else -3.5)
	p.current_velocity = Vector3.ZERO
	p.vertical_velocity = 0.0
	p.is_jumping = false
	p.jump_landing_remaining = 0.0
	p._contextual_jump.clear()
	p._jump_was_airborne = false
	p._jump_position_initialized = false
	var ball = game.ball
	ball.freeze = true
	ball.is_in_play = true
	ball.last_hit_by = 1 - side
	ball.both_bounces_complete = true
	ball.bounces_since_last_hit = 0
	ball.flight_id += 1
	var point: Vector3 = p.global_position + p._get_forward_axis() * 0.6 + Vector3.UP * 1.0
	var def = PostureLibrary.instance().get_def(4)
	var contact: = {"point": point, "time": 0.42, "posture": 4, "def": Planner.pose_at(p, def, point), "bounces": 0}
	if p.posture.human_contact == null:
		p.posture.human_contact = load("res://scripts/human_contact_controller.gd").new(p, p.posture)
	p.posture.human_contact.contact = contact
	p.posture.human_contact.phase = 0
	p.leg_ik.feet_initialized = false
	p.leg_ik.update_leg_ik(1.0 / 60, def)
	return contact
func run() -> void :
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.input_handler.set_process(false)
	game.rally_scorer.set_active(false)
	game.player_left.set_process(false)
	game.player_left.set_physics_process(false)
	game.player_right.set_process(false)
	game.player_right.set_physics_process(false)
	for side in [0, 1]:
		var p = game.player_left if side == 0 else game.player_right
		var c: = prepare(game, p, side)
		check(p.request_contextual_jump(c, 0.9), "P%d accepts reachable high charged contact" % side)
		check( not p.request_contextual_jump(c, 0.9), "P%d refuses repeated queue" % side)
		var peak: = 0.0
		for i in range(75):
			step_jump(p, 1.0 / 120.0)
			p.leg_ik.update_leg_ik(1.0 / 120.0, c.def)
			peak = maxf(peak, p.global_position.y - p.ground_y)
			if i == 31:
				check(p.is_jumping, "P%d takes off before contact" % side)
				p.posture.human_contact.cancel()
				game.ball.flight_id += 1
				game.ball.is_in_play = false
				var before: Vector3 = p.global_position
				var before_velocity: float = p.vertical_velocity
				step_jump(p, 0.0)
				check(p.global_position == before and p.vertical_velocity == before_velocity, "paused jump state does not advance")
			if p.is_jumping and p.global_position.y > p.ground_y + 0.02:
				check( not p.leg_ik.right_foot_locked and not p.leg_ik.left_foot_locked, "airborne feet never claim court supports")
				check(p.leg_ik.right_foot_smooth.y > IK.ANKLE_HEIGHT + 0.01 and p.leg_ik.left_foot_smooth.y > IK.ANKLE_HEIGHT + 0.01, "both feet lift with body")
		check(peak > 0.2 and peak < 0.25, "P%d physical jump height %.3f" % [side, peak])
		for i in range(60):
			step_jump(p, 1.0 / 120.0)
			p.leg_ik.update_leg_ik(1.0 / 120.0, c.def)
		check( not p.is_jumping and p.global_position.y == p.ground_y and p.vertical_velocity == 0, "P%d cancelled/new-flight jump finishes landing" % side)
		check(p.jump_landing_remaining == 0.0, "P%d landing lock expires" % side)
		check(p.leg_ik.right_foot_locked and p.leg_ik.left_foot_locked, "P%d both feet replant" % side)
		for kind in ["low charge", "low ball", "late", "kitchen", "moving", "two bounce", "unreachable"]:
			c = prepare(game, p, side)
			var ratio: = 0.9
			if kind == "low charge": ratio = 0.2
			if kind == "low ball": c.posture = 3
			if kind == "late": c.time = 0.08
			if kind == "kitchen": p.global_position.z = (1.0 if side == 0 else -1.0) * PickleballConstants.NON_VOLLEY_ZONE
			if kind == "moving": p.current_velocity = Vector3.RIGHT * 5.8
			if kind == "two bounce": game.ball.both_bounces_complete = false
			if kind == "unreachable": c.point.x += 2.0
			check( not p.request_contextual_jump(c, ratio), "P%d rejects %s" % [side, kind])
		for interruption in ["flight", "low contact", "point end", "editor"]:
			c = prepare(game, p, side)
			check(p.request_contextual_jump(c, 1.0), "queues interruption check")
			if interruption == "flight": game.ball.flight_id += 1
			if interruption == "low contact": p.posture.human_contact.contact.posture = 3
			if interruption == "point end": game.ball.is_in_play = false
			if interruption == "editor": p.posture.editor_preview_mode = true
			step_jump(p, 0.3)
			check( not p.is_jumping and p._contextual_jump.is_empty(), "pending " + interruption + " cancels takeoff")
			p.posture.editor_preview_mode = false
		c = prepare(game, p, side)
		check(p.request_contextual_jump(c, 1.0), "queues cancellable jump")
		p.posture.human_contact.phase = -1
		step_jump(p, 0.3)
		check( not p.is_jumping and p._contextual_jump.is_empty(), "cancel before takeoff stays grounded")
		c = prepare(game, p, side)
		p.request_contextual_jump(c, 1.0)
		for i in range(40): step_jump(p, 1.0 / 120.0)
		check(p.is_jumping, "airborne before teleport")
		p.global_position = Vector3(1.5, p.ground_y, 6.8 if side == 0 else -6.8)
		step_jump(p, 1.0 / 120.0)
		p.leg_ik.update_leg_ik(1.0 / 120.0, c.def)
		check( not p.is_jumping and p.vertical_velocity == 0.0 and p.jump_landing_remaining == 0, "teleport resets jump without residual launch")
		check(p.leg_ik.right_foot_smooth.distance_to(p.global_position) < 1.1, "teleport rebases airborne feet")
		c = prepare(game, p, side)
		p.request_contextual_jump(c, 1.0)
		while not p.is_jumping: step_jump(p, 1.0 / 120.0)

		p.global_position.y = p.ground_y
		step_jump(p, 1.0 / 120.0)
		check( not p.is_jumping and p.vertical_velocity == 0.0, "same-position reset on first lift cannot relaunch")
	momentum_checks()
	game.queue_free()
	await process_frame
	print("[CONTEXTUAL JUMP] %d checks, %d failures" % [checks, failures.size()])
	for failure in failures: print("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
func momentum_checks() -> void :
	for side in [0, 1]:
		var p: = AirPlayer.new()
		p.player_num = side
		var sign_side: float = 1.0 if side == 0 else -1.0
		p.global_position = Vector3(0, 1.24, 3.5 * sign_side)
		p.jump_takeoff_position = Vector3(0, 1.0, 3.5 * sign_side)
		p.is_jumping = true
		var ik: = IK.new()
		ik._player = p
		p.leg_ik = ik
		ik.update_leg_ik(1.0 / 60.0)
		var scorer: = Scorer.new()
		var b = FakeBallScript.new()
		b.was_volley = true
		b.both_bounces_complete = true
		scorer.bind(b, p, p)
		scorer.start_rally(0, true)
		scorer._on_any_paddle_hit(side)
		scorer._volley_momentum_watches[side].time = Time.get_ticks_msec() - 2000
		check(scorer.check_momentum_fault().valid and scorer._volley_momentum_watches.has(side), "P%d airborne watch survives old 800ms expiry" % side)

		scorer._on_any_paddle_hit(1 - side)
		check(scorer._volley_momentum_watches.has(side), "opponent return preserves airborne watch")
		p.is_jumping = false
		p.jump_landing_remaining = 0.2
		p.global_position.y = p.ground_y
		p.global_position.z = (PickleballConstants.NON_VOLLEY_ZONE + 0.25) * sign_side
		ik.right_foot_smooth = Vector3(0.2, IK.ANKLE_HEIGHT, (PickleballConstants.NON_VOLLEY_ZONE + 0.05) * sign_side)
		ik.left_foot_smooth = Vector3(-0.2, IK.ANKLE_HEIGHT, 3.0 * sign_side)
		ik.right_foot_locked = true
		ik.left_foot_locked = true
		var result: Dictionary = scorer.check_momentum_fault()
		check( not result.valid and result.reason == Scorer.FAULT_MOMENTUM, "P%d shoe touching kitchen on landing faults with root outside" % side)
		b.was_volley = false
		check(scorer.check_kitchen_volley_at_hit(side, 1.0 * sign_side).valid, "P%d bounced dink remains legal in kitchen" % side)
		scorer.end_rally()
		check(scorer._volley_momentum_watches.is_empty(), "rally reset clears watches")


		p.global_position = Vector3(0, 1.0, 3.5 * sign_side)
		ik.right_foot_smooth.z = 3.4 * sign_side
		ik.left_foot_smooth.z = 3.6 * sign_side
		scorer.start_rally(0, true)
		b.was_volley = true
		scorer._on_any_paddle_hit(side)
		scorer._volley_momentum_watches[side].time = Time.get_ticks_msec() - 2000
		check(scorer.check_momentum_fault().valid and scorer._volley_momentum_watches.has(side), "landing absorption cannot expire momentum")
		p.jump_landing_remaining = 0.0
		p.current_velocity = Vector3.FORWARD * sign_side
		check(scorer.check_momentum_fault().valid and scorer._volley_momentum_watches.has(side), "continued forward momentum stays watched")
		p.current_velocity = Vector3.ZERO
		scorer.check_momentum_fault()
		scorer._volley_momentum_watches[side].stable_since = Time.get_ticks_msec() - 200
		check(scorer.check_momentum_fault().valid and scorer._volley_momentum_watches.is_empty(), "stable supported balance clears momentum")
		ik.right_foot_smooth.z = 1.5 * sign_side
		check(scorer.check_momentum_fault().valid, "new kitchen entry after balance is legal")
		ik.free();scorer.free()
