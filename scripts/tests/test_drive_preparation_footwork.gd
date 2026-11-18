extends "res://scripts/tests/test_scaled_body_gait.gd"
const Drive = preload("res://scripts/drive_preparation_state.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Paddle = preload("res://scripts/paddle_dimensions.gd")

func run() -> void:
	output = "/tmp/drive-preparation-footwork.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	for frame in range(5): await process_frame
	game.game_serve.cleanup(); game.process_mode = Node.PROCESS_MODE_DISABLED
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false); node.set_physics_process(false)
	_test_state_rules()
	for p in [game.player_left, game.player_right]:
		if p.posture.human_contact == null: p.posture.human_contact = load("res://scripts/human_contact_controller.gd").new(p, p.posture)
		for hz in [30, 60, 120]:
			_idle_ball_tracking(p, hz)
			for id in [0, 2]:
				for style in ["authored", "open", "closed"]: _drive_case(p, hz, id, style)
			for style in ["open", "closed"]:
				_after_split_setup(p, hz, style)
				for diagonal in [false, true]:
					for wall in [false, true]: _retreat_transition(p, hz, style, diagonal, wall)
		_test_editor_bypass(p)
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "records": records}, "\t")); file.close()
	for failure in failures: push_error(failure)
	print("DRIVE PREPARATION FOOTWORK: %d checks, %d failures -> %s" % [checks, failures.size(), output])
	game.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)

func _test_state_rules() -> void:
	var state := Drive.new()
	var candidate := {"flight": 10, "family": 0, "time": 1.0}
	for i in 12: state.update(1.0 / 60, {}, "receive", false, false)
	check(state.state == "idle", "ball gaze without selected contact cannot request setup")
	for i in 12: state.update(1.0 / 60, candidate, "receive", true, false)
	check(state.state == "idle", "moving player retains travel state")
	var late := candidate.duplicate(); late.time = 0.3
	for i in 12: state.update(1.0 / 60, late, "receive", false, false)
	check(state.state == "idle", "fast wall/late ball uses compact existing support")
	for i in 12: state.update(1.0 / 60, candidate, "receive", false, false)
	check(state.state == "setup" and state.facing_deg == 0.0 and state.stance_kind == "open", "reachable forehand defaults to deliberate open setup")
	state.mark_settled()
	var backhand := candidate.duplicate(); backhand.family = 1
	for i in 60: state.update(1.0 / 60, backhand, "receive", false, false)
	check(state.state == "hold" and state.family == 0 and state.entered_serial == 1, "same-flight side jitter cannot flip planted stance")
	state.update(1.0 / 60, {}, "swing", false, true)
	check(state.state == "hold" and not state.body_alignment_active, "authored contact owns body while stance stays planted")
	state.update(1.0 / 60, {}, "finish", false, true)
	check(state.state == "hold", "finish retains support")
	state.update(1.0 / 60, {}, "recover", false, false)
	check(state.state == "recover" and state.facing_deg == 0.0, "explicit recovery turns back using steps")
	state.mark_settled(); check(state.state == "idle", "recovery completes only after planted settlement")
	for i in 12: state.update(1.0 / 60, candidate, "receive", false, false)
	state.update(1.0 / 60, candidate, "cancel", false, false); state.mark_settled()
	for i in 60: state.update(1.0 / 60, candidate, "receive", false, false)
	check(state.state == "idle", "cancel cannot immediately restart a stance on the same flight")
	for i in 12: state.update(1.0 / 60, candidate, "receive", false, true)
	check(state.state == "setup", "fresh deliberate repress can request a new same-flight setup")

func _fixture(p) -> PostureDefinition:
	var ready: PostureDefinition = PostureLibrary.instance().get_def(20).duplicate(true)
	var h = p.posture.human_contact
	h.phase = -1; h.contact = {}; h.anticipated_contact = {}; h.superblock_hint = {}; h._charge_cancel_recovering = false; h.footwork.cancel()
	p.hitting.charge_visual_active = false; p.hitting.serving_visual_active = false; p.hitting.is_in_follow_through = false
	p.posture._committed_incoming_posture = -1; p._head_gaze._rest_body_angle = 0.0
	p.leg_ik.drive_preparation.reset(); reset(p, ready)
	p.global_position = Vector3(0, p.ground_y, 3.8 if p.player_num == 0 else -3.8)
	p.leg_ik.feet_initialized = false; tick(p, ready, Vector3.ZERO, 1.0 / 60)
	game.practice_launcher.is_active = false; game.ball.wall_practice_active = false; game.ball.wall_return_ready = false
	game.ball.reset_rally_state(); game.ball.is_in_play = true; game.ball.both_bounces_complete = true; game.ball.bounces_since_last_hit = 1; game.ball.flight_id += 1
	h._flight_id = game.ball.flight_id
	return ready

func _idle_ball_tracking(p, hz: int) -> void:
	_fixture(p)
	game.ball.last_hit_by = p.player_num
	var ik = p.leg_ik; var h = p.posture.human_contact
	var initial: Array[Vector3] = [ik.right_foot_smooth, ik.left_foot_smooth]
	var contacts: int = ik.right_contact_serial + ik.left_contact_serial
	var maximum_motion := 0.0
	for frame in range(hz * 4):
		var x := 1.8 if int(float(frame) / hz * 2.0) % 2 == 0 else -1.8
		game.ball.global_position = p.global_position + p._get_forward_axis() * 2.4 + p._get_forehand_axis() * x
		var pose: PostureDefinition = h._ready_pose(1.0 / hz)
		tick(p, pose, Vector3.ZERO, 1.0 / hz)
		maximum_motion = maxf(maximum_motion, maxf(initial[0].distance_to(ik.right_foot_smooth), initial[1].distance_to(ik.left_foot_smooth)))
	check(contacts == ik.right_contact_serial + ik.left_contact_serial, "P%d %dHz no ball-only replants" % [p.player_num, hz])
	check(maximum_motion < 0.00001, "P%d %dHz planted neutral feet ignore ball gaze" % [p.player_num, hz])
	records.append({"case": "idle P%d %dHz" % [p.player_num, hz], "replants": ik.right_contact_serial + ik.left_contact_serial - contacts, "max_foot_motion_m": maximum_motion})

func _drive_case(p, hz: int, id: int, style: String = "authored") -> void:
	var ready := _fixture(p)
	var h = p.posture.human_contact; var ik = p.leg_ik
	var source := _source_for_stance(id, style)
	var selected_profile: Dictionary = Drive.profile_from(Path.sample(source, 0.0))
	var point: Vector3 = Path.world_transform(p, source) * Paddle.HEAD_OFFSET
	game.ball.last_hit_by = 1 - p.player_num; game.ball.global_position = point; game.ball.linear_velocity = Vector3.ZERO
	h.contact = {"posture": id, "def": source, "point": point, "time": 1.2, "bounces": 0}
	var tag := "P%d %dHz family%d %s" % [p.player_num, hz, source.family, style]
	var maximum_drift := 0.0; var maximum_yaw := 0.0; var maximum_root_motion := 0.0
	var root_position: Vector3 = p.global_position
	var old_feet: Array[Vector3] = [ik.right_foot_smooth, ik.left_foot_smooth]
	var old_yaws: Array[float] = [ik._right_yaw, ik._left_yaw]
	var old_contacts: Array[int] = [ik.right_contact_serial, ik.left_contact_serial]
	for frame in range(hz):
		tick(p, ready, Vector3.ZERO, 1.0 / hz)
		var now: Array[Vector3] = [ik.right_foot_smooth, ik.left_foot_smooth]
		var turns: Array[float] = [ik._right_yaw, ik._left_yaw]
		var serials: Array[int] = [ik.right_contact_serial, ik.left_contact_serial]
		for side in [0, 1]:
			if (ik.right_foot_locked if side == 0 else ik.left_foot_locked) and old_contacts[side] == serials[side]:
				maximum_drift = maxf(maximum_drift, old_feet[side].distance_to(now[side])); maximum_yaw = maxf(maximum_yaw, absf(angle_difference(old_yaws[side], turns[side])))
		old_feet = now; old_yaws = turns; old_contacts = serials
		maximum_root_motion = maxf(maximum_root_motion, root_position.distance_to(p.global_position))
	check(ik.drive_preparation.state == "hold", tag + " deliberate setup failed " + ik.drive_preparation.state)
	check(absf(angle_difference(deg_to_rad(ik.locomotion_hip_yaw_deg), deg_to_rad(selected_profile.facing))) < deg_to_rad(1.0), tag + " setup ignored selected authored heading")
	if style != "authored": check(ik.drive_preparation.stance_kind == style, tag + " selected stance kind lost")
	var hold_contacts: int = ik.right_contact_serial + ik.left_contact_serial
	var hold_feet: Array[Vector3] = [ik.right_foot_smooth, ik.left_foot_smooth]
	for frame in range(hz):
		h.contact.def = PostureLibrary.instance().get_def(2 if id == 0 else 0) if frame % 2 == 0 else source
		game.ball.global_position = point + p._get_forehand_axis() * (0.2 if frame % 2 == 0 else -0.2)
		tick(p, h._ready_pose(1.0 / hz), Vector3.ZERO, 1.0 / hz)
	check(hold_contacts == ik.right_contact_serial + ik.left_contact_serial, tag + " held setup chased the moving prediction")
	check(hold_feet[0].distance_to(ik.right_foot_smooth) < 0.00001 and hold_feet[1].distance_to(ik.left_foot_smooth) < 0.00001, tag + " hold plants changed")
	h.phase = 1; p.hitting.charge_visual_active = true
	for frame in range(hz / 3): tick(p, Path.sample(source, float(frame) / maxf(hz / 3.0, 1)), Vector3.ZERO, 1.0 / hz)
	check(hold_contacts == ik.right_contact_serial + ik.left_contact_serial and not ik.drive_preparation.body_alignment_active, tag + " actual swing moved stance or took body ownership")
	h.phase = -1; h._charge_cancel_recovering = true; p.hitting.charge_visual_active = false
	for frame in range(hz): tick(p, ready, Vector3.ZERO, 1.0 / hz)
	h._charge_cancel_recovering = false; h.contact = {}
	for frame in range(hz): tick(p, ready, Vector3.ZERO, 1.0 / hz)
	check(ik.drive_preparation.state == "idle" and ik.is_support_ready(0) and ik.is_support_ready(1), tag + " canceled setup failed planted recovery")
	check(maximum_drift < 0.00001 and maximum_yaw < 0.00001 and maximum_root_motion == 0.0, tag + " setup slid/spun a support or moved gameplay root")
	records.append({"case": tag, "max_locked_drift_m": maximum_drift, "max_locked_yaw_deg": rad_to_deg(maximum_yaw), "root_motion_m": maximum_root_motion, "entered": ik.drive_preparation.entered_serial})

func _test_editor_bypass(p) -> void:
	var ready := _fixture(p)
	var ik = p.leg_ik
	ik.drive_preparation.state = "hold"; ik.drive_preparation.facing_deg = -32.0
	var authored: PostureDefinition = ready.duplicate(true)
	authored.stance_width = 0.73; authored.right_foot_offset = Vector3(0.04, 0, 0)
	p.posture.editor_preview_mode = true
	ik.update_leg_ik(0.0, authored)
	var targets: Array[Vector3] = ik._stance_targets(authored, Vector3(p.global_position.x, ik.ANKLE_HEIGHT, p.global_position.z), true)
	check(ik.drive_preparation.state == "idle", "editor clears runtime setup ownership")
	check(ik.right_foot_smooth.is_equal_approx(targets[0]) and ik.left_foot_smooth.is_equal_approx(targets[1]), "editor shows exact user-authored feet after live setup")
	p.posture.editor_preview_mode = false

func _source_for_stance(id: int, style: String) -> PostureDefinition:
	var source: PostureDefinition = PostureLibrary.instance().get_def(id).duplicate(true)
	if style != "authored":
		var facing: float = 45.0 if source.family == 0 else -45.0
		var fields := {"stance_width": 0.66 if style == "open" else 0.44, "front_foot_forward": 0.0 if style == "open" else 0.22, "back_foot_back": 0.0 if style == "open" else -0.22, "right_foot_offset": Vector3.ZERO, "left_foot_offset": Vector3.ZERO, "right_foot_yaw_deg": 0.0 if style == "open" else facing, "left_foot_yaw_deg": 0.0 if style == "open" else facing, "body_yaw_deg": 0.0 if style == "open" else facing, "hip_yaw_deg": 0.0, "torso_yaw_deg": 0.0, "crouch_amount": 0.18 if style == "open" else 0.14, "lead_foot": 1 if source.family == 0 else 0}
		if source.windup_body == null: source.windup_body = preload("res://scripts/stroke_body_keyframe.gd").new()
		else: source.windup_body = source.windup_body.duplicate(true)
		for key in fields: source.windup_body.values[key] = fields[key]
	return source

func _retreat_transition(p, hz: int, style: String, diagonal: bool, wall: bool) -> void:
	var ready := _fixture(p)
	var source := _source_for_stance(0, style)
	var h = p.posture.human_contact; var ik = p.leg_ik
	var point: Vector3 = Path.world_transform(p, source) * Paddle.HEAD_OFFSET
	game.practice_launcher.is_active = wall; game.practice_launcher.drill_mode = "WALL"
	game.ball.wall_practice_active = wall; game.ball.wall_return_ready = wall
	game.ball.last_hit_by = 1 - p.player_num; game.ball.global_position = point
	h.contact = {"posture": 0, "def": source, "point": point, "time": 1.2, "bounces": 0}
	for frame in range(hz): tick(p, ready, Vector3.ZERO, 1.0 / hz)
	var tag := "P%d %dHz %s %s %s" % [p.player_num, hz, style, "diagonal" if diagonal else "backpedal", "wall" if wall else "match"]
	check(ik.drive_preparation.state == "hold", tag + " starts from settled selected stance")
	h.contact = {}; h.anticipated_contact = {}; h.superblock_hint = {}
	var old_feet: Array[Vector3] = [ik.right_foot_smooth, ik.left_foot_smooth]
	var old_serials: Array[int] = [ik.right_contact_serial, ik.left_contact_serial]
	var old_yaws: Array[float] = [ik._right_yaw, ik._left_yaw]
	var max_drift := 0.0; var max_yaw_drift := 0.0; var minimum_gap := INF
	var max_heading := 0.0; var saw_state := false
	for frame in range(hz * 3):
		var t := float(frame) / hz
		var fwd: Vector3 = p._get_forward_axis(); var side: Vector3 = p._get_forehand_axis()
		var velocity := Vector3.ZERO
		if t < 1.2:
			if diagonal: velocity = (-fwd + side * (0.7 if int(t / 0.2) % 2 == 0 else -0.7)).normalized() * 4.2
			else: velocity = (-fwd if int(t / 0.3) % 2 == 0 else fwd) * 4.2
		tick(p, ready, velocity, 1.0 / hz)
		saw_state = saw_state or ik.locomotion_state == ("backward_strafe" if diagonal else "backpedal")
		max_heading = maxf(max_heading, absf(ik.locomotion_hip_yaw_deg))
		var now: Array[Vector3] = [ik.right_foot_smooth, ik.left_foot_smooth]
		var serials: Array[int] = [ik.right_contact_serial, ik.left_contact_serial]
		var yaws: Array[float] = [ik._right_yaw, ik._left_yaw]
		minimum_gap = minf(minimum_gap, now[0].distance_to(now[1]))
		for foot_side in [0, 1]:
			if (ik.right_foot_locked if foot_side == 0 else ik.left_foot_locked) and old_serials[foot_side] == serials[foot_side]:
				max_drift = maxf(max_drift, old_feet[foot_side].distance_to(now[foot_side]))
				max_yaw_drift = maxf(max_yaw_drift, absf(angle_difference(old_yaws[foot_side], yaws[foot_side])))
		old_feet = now; old_serials = serials; old_yaws = yaws
	check(saw_state, tag + " missing named retreat state")
	check(max_heading <= 45.1, tag + " turned away from play during retreat")
	check(max_drift < 0.00001 and max_yaw_drift < 0.00001, tag + " planted support moved during quick reversal")
	check(minimum_gap >= 0.095, tag + " reversal shoes intersected")
	check(ik.drive_preparation.state == "idle" and ik.is_support_ready(0) and ik.is_support_ready(1), tag + " stop failed court-facing recovery")
	records.append({"case": tag, "max_planted_drift_m": max_drift, "max_planted_yaw_drift_deg": rad_to_deg(max_yaw_drift), "max_heading_deg": max_heading, "minimum_shoe_gap_m": minimum_gap})

func _after_split_setup(p, hz: int, style: String) -> void:
	var ready := _fixture(p)
	var source := _source_for_stance(0, style)
	var h = p.posture.human_contact; var ik = p.leg_ik
	var point: Vector3 = Path.world_transform(p, source) * Paddle.HEAD_OFFSET
	game.ball.last_hit_by = 1 - p.player_num; game.ball.global_position = point
	h.contact = {"posture": 0, "def": source, "point": point, "time": 1.2, "bounces": 0}
	var split = preload("res://scripts/split_step_timing.gd").new(); p.pose_controller.split_step = split
	p.pose_controller.split_observer.last_context = {}
	var saw_split := false
	for frame in range(hz * 2):
		var context := {"live": true, "hop_allowed": true}
		if frame == 0: context.merge({"cue_id": 1, "cue_lead": 0.15})
		if frame == ceili(0.15 * hz): context.strike_id = 1
		split.update(1.0 / hz, context)
		tick(p, ready, Vector3.ZERO, 1.0 / hz)
		saw_split = saw_split or ik._split_pose_active
	var tag := "P%d %dHz split -> %s" % [p.player_num, hz, style]
	check(saw_split and split.hop_count == 1, tag + " missing one real small split")
	check(ik.drive_preparation.state == "hold" and ik.drive_preparation.stance_kind == style, tag + " stationary split landing blocked selected stance")
	check(split.phase == "ready" and ik.right_foot_locked and ik.left_foot_locked, tag + " stance takeover left split airborne")
