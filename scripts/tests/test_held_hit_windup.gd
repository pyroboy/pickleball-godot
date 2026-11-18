extends SceneTree
const Held = preload("res://scripts/held_hit_motion.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const D = preload("res://scripts/paddle_dimensions.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Reach = preload("res://scripts/paddle_wrist_reach.gd")
const Store = preload("res://scripts/mobile_pose_store.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Hand = preload("res://scripts/player_hand_presentation.gd")
const ReadyTracking = preload("res://scripts/ready_ball_tracking.gd")
var checks := 0
var failures: Array[String] = []
var game
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func same(a: PostureDefinition, b: PostureDefinition) -> bool:
	return Path.canonical_transform(a).is_equal_approx(Path.canonical_transform(b))
func stop_input() -> void:
	Input.action_release("ui_accept")
	game.input_handler.cancel_charge_input()
	game.input_handler._handle_swing_charge(0.0)
func rally_fixture(id: int = 10) -> void:
	stop_input()
	game.between_point_controller.cancel()
	game._set_game_state(game.GameState.PLAYING)
	var p = game.player_left
	p.global_position = Vector3(0, p.ground_y, 3.8)
	p.current_velocity = Vector3.ZERO
	if p.posture.human_contact == null: p.posture.human_contact = load("res://scripts/human_contact_controller.gd").new(p, p.posture)
	var h = p.posture.human_contact
	var b = game.ball
	b.reset_rally_state(); b.both_bounces_complete = true; b.bounces_since_last_hit = 1
	b.is_in_play = true; b.last_hit_by = 1; b.flight_id += 1
	b.global_position = Vector3(.65, 1.0, 2.5); b.linear_velocity = Vector3(0, 0, 4)
	h._flight_id = b.flight_id
	var def: PostureDefinition = PostureLibrary.instance().get_def(id)
	h.contact = {"posture": id, "def": def, "time": 2.0, "point": b.global_position, "bounces": 0}
	h.visual_pose = h._ready_pose(0.0)
	h._apply_visual()
func run() -> void:
	create_timer(120, true).timeout.connect(func(): quit(2))
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.reaction_button.auto_fire_on_perfect = false
	game.pvp_mode = true; game.aim_focus._sync_realtime_mode()
	var p = game.player_left
	var ready: PostureDefinition = PostureLibrary.instance().get_def(20)
	var ready_bytes: PackedByteArray = var_to_bytes(Store._encode_fields(ready))
	var helper = Held.new()
	for id in range(20):
		var def: PostureDefinition = PostureLibrary.instance().get_def(id)
		var saved: PackedByteArray = var_to_bytes(Store._encode_fields(def))
		check(same(helper.sample(def, ready, 0.0, p), ready), "Ready endpoint geometry id%d" % id)
		var windup: PostureDefinition = Path.sample(def, 0.0)
		check(same(helper.sample(def, ready, Held.WINDUP_SECONDS, p), windup), "authored Windup endpoint id%d" % id)
		var strong: PostureDefinition = helper.sample(def, ready, Held.STRONG_SECONDS, p)
		check(same(strong, helper.sample(def, ready, 30.0, p)), "full hold stabilizes id%d" % id)
		for index in range(41):
			var pose: PostureDefinition = helper.sample(def, ready, float(index) * Held.STRONG_SECONDS / 40.0, p)
			check((Path.world_transform(p, pose) * D.HEAD_OFFSET).is_finite(), "finite hold path id%d sample%d" % [id, index])
		check(var_to_bytes(Store._encode_fields(def)) == saved, "authored keys unchanged id%d" % id)
	check(var_to_bytes(Store._encode_fields(ready)) == ready_bytes, "approved Ready unchanged")

	for step in [1.0 / 60.0, 0.1]:
		rally_fixture()
		var h = p.posture.human_contact
		Input.action_press("ui_accept")
		game.input_handler._handle_swing_charge(0.0)
		check(h.held_hit_seconds == 0.0 and same(h._charge_target_pose, h._ready_pose(0.0)), "press starts at Ready")
		for frame in range(roundi(Held.STRONG_SECONDS / step)):
			game.input_handler._handle_swing_charge(step)
			var before: float = h.held_hit_seconds
			var displayed: Transform3D = Path.canonical_transform(h.visual_pose)
			h._update_charge_pose(step * 0.001)
			check(is_equal_approx(h.held_hit_seconds, before) and Path.canonical_transform(h.visual_pose).is_equal_approx(displayed), "world tick cannot double-advance hold")
		check(is_equal_approx(h.held_hit_seconds, Held.STRONG_SECONDS), "same visual duration at different frame rates")
		check(is_equal_approx(game.input_handler.serve_charge_time, PickleballConstants.MAX_SERVE_CHARGE_TIME) and h.charge_ratio == 1.0, "power retains original cap")
		var before_cancel: Transform3D = Path.canonical_transform(h.visual_pose)
		game.input_handler.cancel_charge_input()
		check(Path.canonical_transform(h.visual_pose).is_equal_approx(before_cancel), "cancel preserves current visual without snap")
		check(h.held_hit_seconds == 0.0 and not p.hitting.charge_visual_active and h._charge_cancel_recovering, "cancel resets clock and enables recovery")
		for frame in range(60): h.update(1.0 / 60.0)
		# The recovered authored pose still converges on the same clock. Its live
		# tip/chest tracking is an intentional grip-anchored presentation overlay.
		var recovered: PostureDefinition = ReadyTracking.untracked(h.visual_pose)
		var recovered_frame: Transform3D = Path.canonical_transform(recovered)
		var ready_frame: Transform3D = Path.canonical_transform(h._ready_pose(0.0))
		check((recovered_frame * D.HEAD_OFFSET).distance_to(ready_frame * D.HEAD_OFFSET) < .01, "cancel smoothly reaches underlying Ready")
		check(recovered_frame.basis.get_rotation_quaternion().angle_to(ready_frame.basis.get_rotation_quaternion()) < deg_to_rad(.5), "cancel restores underlying Ready orientation")
		check(h.held_hit_seconds == 0.0 and not p.hitting.charge_visual_active and is_equal_approx(h._charge_recovery_seconds, 1.0), "recovery retains the reset hold clock and one-second recovery interval")
		check(h.visual_pose.has_meta(ReadyTracking.BASE_META), "recovered Ready retains explicit live tracking ownership")
		var live_ready: PostureDefinition = p._ready_tracking.apply(recovered, p, game.ball.global_position, 0.0)
		check(same(h.visual_pose, live_ready) and is_equal_approx(h.visual_pose.torso_yaw_deg, live_ready.torso_yaw_deg), "displayed recovery is exactly the recovered base plus current tracking")
		check(Reach.virtual_grip_world(Path.canonical_transform(h.visual_pose), h.visual_pose).distance_to(Reach.virtual_grip_world(recovered_frame, recovered)) < .00001, "recovered tip tracking preserves the grip anchor")
		check(p.paddle_node.global_transform.is_equal_approx(Path.world_transform(p, h.visual_pose)), "actual recovered paddle follows the owned live Ready pose")
		stop_input(); rally_fixture()
		Input.action_press("ui_accept"); game.input_handler._handle_swing_charge(.04)
		check(is_equal_approx(h.held_hit_seconds, .04), "fresh press does not inherit prior hold")
		Input.action_release("ui_accept"); game.input_handler._handle_swing_charge(0.0)
		check(h.phase == 0 and is_equal_approx(h.charge_ratio, .04 / PickleballConstants.MAX_SERVE_CHARGE_TIME), "quick tap queues original weak power")
		h.contact.time = .025
		h._advance_swing(0.0, game.ball)
		check(h.phase == 1 and h.strike_time == .025, "contact-imminent quick tap never waits for visual windup")

	for style in range(7):
		stop_input(); game._reset_match(); game.game_serve.select_serve_style(style)
		game.game_serve._prepare_server(0.0)
		Input.action_press("ui_accept"); game.input_handler._handle_swing_charge(0.0)
		for index in range(13):
			if index > 0: game.input_handler._handle_swing_charge(.1)
			var serve = game.game_serve
			var pose: PostureDefinition = p.posture.transition_pose_blend
			check(is_equal_approx(serve.held_hit_seconds, minf(index * .1, 1.2)), "serve visual interval counted once style%d" % style)
			check(is_equal_approx(serve.get_charge_ratio(), game.input_handler.serve_charge_time / PickleballConstants.MAX_SERVE_CHARGE_TIME), "serve power clocks agree style%d" % style)
			check(is_equal_approx(float(pose.get_meta("serve_phase_charge", -1)), smoothstep(0.0, .6, serve.held_hit_seconds)), "serve grasp follows visual preparation style%d" % style)
			check(absf(Hand.ball_surface_gap(p.left_arm_node, serve.get_held_ball_position(), Ball.BALL_RADIUS)) < .001, "held serve palm stays seated style%d" % style)
		var before: Transform3D = p.paddle_node.global_transform
		var committed: PostureDefinition = game.game_serve.get_preparation_pose(1.0)
		var wait: PostureDefinition = Motion.serve_style_wait(committed, 0.0, style)
		check(same(committed, wait), "extended serve survives baseline/saved-delta release sampling style%d" % style)
		print("HELD_SERVE ", style, " ", game.game_serve._held_visual_motion.report)
		Input.action_release("ui_accept"); game.input_handler._handle_swing_charge(0.0)
		check(game.game_serve.is_release_pending(), "long-held serve releases immediately style%d" % style)
		check(p.paddle_node.global_transform.is_equal_approx(before), "strong held serve release has no paddle snap style%d" % style)
		check(game.game_serve._pending_release.charge == 1.0, "long-held serve power unchanged style%d" % style)
	stop_input(); game._reset_match(); game.game_serve._prepare_server(0.0)
	Input.action_press("ui_accept"); game.input_handler._handle_swing_charge(1.2)
	var before_cancel_serve: PostureDefinition = p.posture.transition_pose_blend
	game.input_handler.cancel_charge_input()
	check(game.game_serve.held_hit_seconds == 0.0 and not game.game_serve.is_charging(), "serve cancel resets visual and power ownership")
	check(same(before_cancel_serve, game.game_serve.get_preparation_pose(0.0)), "serve cancel keeps displayed starting pose")
	for frame in range(25): game.game_serve._process(1.0 / 60.0)
	check(game.game_serve._held_recover_seconds == 0.0 and p.posture.transition_pose_blend.get_meta("serve_phase_charge", -1) == 0.0, "serve cancel returns smoothly to serve-ready")
	stop_input()
	# Advance the actual delivery physics after a full held Strong preparation.
	# The already-existing bounce/launch owner must still produce each contact.
	game.process_mode = Node.PROCESS_MODE_INHERIT
	game.input_handler.set_process(false)
	for style in range(7):
		game._reset_match(); game.game_serve.select_serve_style(style)
		game.player_right.set_ai_movement_enabled(false)
		for frame in range(20): await physics_frame
		Input.action_press("ui_accept"); game.input_handler._handle_swing_charge(1.2)
		var launches: Array[Dictionary] = []
		var launched = func(team: int):
			var local: Vector3 = p.paddle_node.to_local(game.ball.global_position)
			launches.append({"team": team, "gap": absf(preload("res://scripts/paddle_clearance.gd").distance_to_head_shape(local) - Ball.BALL_RADIUS), "power": game.ball.get_meta("shot_profile", {}).get("charge", -1)})
		game.game_serve.serve_launched.connect(launched)
		Input.action_release("ui_accept"); game.input_handler._handle_swing_charge(0.0)
		for frame in range(120):
			await physics_frame
			if not launches.is_empty(): break
		check(launches.size() == 1 and launches[0].team == 0, "full held Strong serves make exactly one actual launch style%d" % style)
		if not launches.is_empty():
			check(float(launches[0].gap) < .003, "Strong hold retains physical Contact style%d" % style)
			check(is_equal_approx(float(launches[0].power), 1.0), "Strong hold retains launched power style%d" % style)
		game.game_serve.serve_launched.disconnect(launched)
		stop_input()
	print("HELD HIT WINDUP: %d checks, %d failures" % [checks, failures.size()])
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game)
	quit(0 if failures.is_empty() else 1)
