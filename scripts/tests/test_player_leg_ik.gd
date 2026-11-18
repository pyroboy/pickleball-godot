class_name TestPlayerLegIK extends TestBase

const IK = preload("res://scripts/player_leg_ik.gd")
const Motion = preload("res://scripts/incoming_ready_motion.gd")

class MockPivot extends RefCounted:
	var position: = Vector3.ZERO
	var global_rotation: = Vector3.ZERO
class MockLeg extends RefCounted:
	var foot_pivot: = MockPivot.new()
	var solved: = Vector3.ZERO
	func solve_ik(foot: Vector3, _pole: Vector3, _tilt: float) -> void :
		solved = foot
		foot_pivot.global_rotation = Vector3.ZERO
class MockHitting extends RefCounted:
	var serving_visual_active: = false
class MockPosture extends RefCounted:
	var editor_preview_mode: = false
class MockPlayer extends RefCounted:
	var global_position: = Vector3(0, 1, 0)
	var current_velocity: = Vector3.ZERO
	var move_speed: = 5.8
	var player_num: = 0
	var posture: = MockPosture.new()
	var hitting: = MockHitting.new()
	var body_pivot: = MockPivot.new()
	var right_leg_node: = MockLeg.new()
	var left_leg_node: = MockLeg.new()
	func _get_forehand_axis() -> Vector3: return Vector3.RIGHT if player_num == 0 else Vector3.LEFT
	func _get_forward_axis() -> Vector3: return Vector3.FORWARD if player_num == 0 else Vector3.BACK
	func _get_swing_sign() -> float: return -1.0 if player_num == 0 else 1.0
	func get_runtime_posture_def(): return null
	func _draw_step_debug(_a, _b, _c, _d, _e, _f) -> void : pass

func run_all(totals: Dictionary) -> void :
	_run_test_list(totals, [test_world_space_plants_and_alternation, 
		test_reversals_never_cross_or_drag_support, test_teleport_rebases_both_feet, 
		test_stop_finishes_airborne_foot_first, test_resume_during_stance_step, 
		test_stationary_prediction_jitter_does_not_shuffle, 
		test_blocked_movement_settles, test_editor_preserves_exact_authored_stance, 
		test_yaw_converges_despite_solver_rotation_reset, 
		test_frame_rate_and_hitch_stability, test_render_physics_rate_mismatch, test_source_posture_is_immutable, 
		test_lock_helper_is_exact, test_speed_scaled_steps_are_compact, 
		test_run_to_shuffle_and_idle_transitions, test_run_rapid_turns_keep_contact_and_clearance, 
		test_serve_setup_initializes_legal_stance])

func ready_pose() -> PostureDefinition:
	return Motion.ready_pose(PostureLibrary.instance().get_def(20))

func fixture(player_num: int = 0) -> Array:
	var p: = MockPlayer.new()
	p.player_num = player_num
	var ik: = IK.new()
	ik._player = p
	ik.update_leg_ik(1.0 / 60.0, ready_pose())
	return [p, ik]

func tick(p, ik, dt: float, def, move: bool = true) -> void :
	if move: p.global_position += p.current_velocity * dt
	p.body_pivot.position = Vector3.ZERO
	ik.update_leg_ik(dt, def)

func planar_gap(foot: Vector3, body: Vector3) -> float:
	return Vector3(foot.x - body.x, 0, foot.z - body.z).length()

func measure(p, ik, def, frames: int, dt: float, reverse_every: int = 0) -> Dictionary:
	var data: = {"drift": 0.0, "gap": 0.0, "separation": 100.0, "floor": 100.0, "both": 0, "sequence": [], "running": false, "shoe_gap": 100.0, "max_flight": 0.0, "max_spread": 0.0, "lift": 0.0, "run_contacts": 0, "turning": false}
	var old_r: Vector3 = ik.right_foot_smooth
	var old_l: Vector3 = ik.left_foot_smooth
	var rt: float = ik.right_step_t
	var lt: float = ik.left_step_t
	var flight: = 0.0
	for frame in range(frames):
		if reverse_every > 0 and frame > 0 and frame % reverse_every == 0: p.current_velocity = - p.current_velocity
		tick(p, ik, dt, def)
		if rt >= 1.0 and ik.right_step_t < 1.0: data.sequence.append(0)
		if lt >= 1.0 and ik.left_step_t < 1.0: data.sequence.append(1)
		if rt >= 1.0 and ik.right_step_t >= 1.0: data.drift = maxf(data.drift, old_r.distance_to(ik.right_foot_smooth))
		if lt >= 1.0 and ik.left_step_t >= 1.0: data.drift = maxf(data.drift, old_l.distance_to(ik.left_foot_smooth))
		data.running = data.running or ik._run_active
		data.turning = data.turning or absf(ik.locomotion_hip_yaw_deg) > 15.0
		if ik.right_step_t < 1.0 and ik.left_step_t < 1.0:
			data.both += 1
			flight += dt
			data.max_flight = maxf(data.max_flight, flight)
		else:
			flight = 0.0
		if rt < 1.0 and ik.right_step_t >= 1.0: data.run_contacts += 1
		if lt < 1.0 and ik.left_step_t >= 1.0: data.run_contacts += 1
		data.shoe_gap = minf(data.shoe_gap, ik.right_foot_smooth.distance_to(ik.left_foot_smooth))
		data.max_spread = maxf(data.max_spread, ik.get_feet_gap())
		data.lift = maxf(data.lift, maxf(ik.right_foot_smooth.y, ik.left_foot_smooth.y) - IK.ANKLE_HEIGHT)
		data.separation = minf(data.separation, (ik.right_foot_smooth - ik.left_foot_smooth).dot(p._get_forehand_axis()))
		for foot in [ik.right_foot_smooth, ik.left_foot_smooth]:
			data.floor = minf(data.floor, foot.y)
			data.gap = maxf(data.gap, planar_gap(foot, p.global_position))
		old_r = ik.right_foot_smooth;old_l = ik.left_foot_smooth
		rt = ik.right_step_t;lt = ik.left_step_t
	return data

func assert_trace(data: Dictionary, tag: String) -> void :
	_assert_le(data.drift, 1e-05, tag + " planted feet never slide")
	_assert_le(data.gap, 0.88, tag + " no overextended trailing foot")
	if data.running:
		_assert_ge(data.shoe_gap, 0.095, tag + " crossover shoes stay physically separate")
		_assert_le(data.max_flight, 0.16, tag + " running flight is brief")
	elif data.turning:
		_assert_ge(data.shoe_gap, 0.095, tag + " turning shuffle shoes remain physically separate")
	else:
		_assert_ge(data.separation, IK.MIN_FOOT_SEPARATION - 1e-05, tag + " court-facing shuffle feet never cross")
	_assert_ge(data.floor, IK.ANKLE_HEIGHT - 1e-05, tag + " shoes never sink below floor")
	if not data.running: _assert_eq(data.both, 0, tag + " shuffle retains grounded support")

func test_world_space_plants_and_alternation() -> void :
	for num in [0, 1]:
		for fps in [30, 60, 120]:
			for speed in [0.35, 0.8, 1.3, 2.0, 5.8, 6.5]:
				for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3(1, 0, 1).normalized()]:
					var pair: = fixture(num); var p = pair[0]; var ik = pair[1]
					p.move_speed = speed if speed > 5.8 else 5.8
					p.current_velocity = direction * speed
					var data: = measure(p, ik, ready_pose(), fps * 2, 1.0 / fps)
					var tag: = "P%d %dfps %.1fm/s %s" % [num, fps, speed, direction]
					assert_trace(data, tag)
					_assert_ge(data.sequence.size(), 4, tag + " both feet take repeated steps")
					for i in range(1, data.sequence.size()): _assert_true(data.sequence[i] != data.sequence[i - 1], tag + " alternates without starvation")
					ik.free()

func test_reversals_never_cross_or_drag_support() -> void :
	for num in [0, 1]:
		for direction in [Vector3.RIGHT, Vector3.FORWARD, Vector3(1, 0, -1).normalized()]:
			for fps in [30, 60, 120]:
				var pair: = fixture(num); var p = pair[0]; var ik = pair[1]
				p.current_velocity = direction * 5.8
				assert_trace(measure(p, ik, ready_pose(), fps * 3, 1.0 / fps, int(fps * 0.5)), "reverse %d %s" % [fps, direction])
				ik.free()

func test_teleport_rebases_both_feet() -> void :
	for moving in [false, true]:
		var pair: = fixture(); var p = pair[0]; var ik = pair[1]
		if moving:
			p.current_velocity = Vector3.RIGHT * 5.8
			for frame in range(3): tick(p, ik, 1.0 / 60.0, ready_pose())
		p.global_position += Vector3(-5, 0, 7)
		tick(p, ik, 1.0 / 60.0, ready_pose(), false)
		_assert_lt(planar_gap(ik.right_foot_smooth, p.global_position), 0.4, "right rebased in one frame")
		_assert_lt(planar_gap(ik.left_foot_smooth, p.global_position), 0.4, "left rebased in one frame")
		_assert_eq(ik._active_side, -1, "stale swing cleared")
		_assert_eq_f(ik.gait_arc_length, 0, 1e-05, "stale odometer cleared")
		ik.free()

func test_stop_finishes_airborne_foot_first() -> void :
	for stop_frame in range(1, 21):
		var pair: = fixture(); var p = pair[0]; var ik = pair[1]
		p.current_velocity = Vector3.RIGHT * 5.8
		for frame in range(stop_frame): tick(p, ik, 1.0 / 60.0, ready_pose())
		var airborne: int = ik._active_side
		p.current_velocity = Vector3.ZERO
		tick(p, ik, 1.0 / 60.0, ready_pose())
		if airborne >= 0: _assert_eq(ik._active_side, airborne, "finish original airborne foot first")
		# Neutral turn-back replants now bound captured yaw speed; allow 1.5 seconds
		# for both sequential feet while preserving exact support and completion checks.
		for frame in range(90):
			if ik.right_foot_locked: _assert_eq_f(ik.right_foot_smooth.y, IK.ANKLE_HEIGHT, 1e-05, "right support cannot hang above floor")
			if ik.left_foot_locked: _assert_eq_f(ik.left_foot_smooth.y, IK.ANKLE_HEIGHT, 1e-05, "left support cannot hang above floor")
			tick(p, ik, 1.0 / 60.0, ready_pose())
		_assert_eq(ik._active_side, -1, "both feet finish settling")
		_assert_eq_f(ik.right_foot_smooth.y, IK.ANKLE_HEIGHT, 1e-05)
		_assert_eq_f(ik.left_foot_smooth.y, IK.ANKLE_HEIGHT, 1e-05)
		_assert_eq_f(ik.gait_arc_length, 0, 1e-05)
		ik.free()

func test_resume_during_stance_step() -> void :
	var pair: = fixture(); var p = pair[0]; var ik = pair[1]
	var def: = ready_pose();def.front_foot_forward = 0.45
	for frame in range(3): tick(p, ik, 1.0 / 60.0, def)
	p.current_velocity = Vector3.LEFT * 5.8
	assert_trace(measure(p, ik, def, 120, 1.0 / 60.0), "resume")
	ik.free()

func test_stationary_prediction_jitter_does_not_shuffle() -> void :
	var pair: = fixture(); var p = pair[0]; var ik = pair[1]
	var start_r: Vector3 = ik.right_foot_smooth
	var start_l: Vector3 = ik.left_foot_smooth
	for frame in range(120):
		var def: = ready_pose();def.stance_width += sin(frame) * 0.03
		tick(p, ik, 1.0 / 60.0, def)
	_assert_eq_v3(ik.right_foot_smooth, start_r, 1e-05)
	_assert_eq_v3(ik.left_foot_smooth, start_l, 1e-05)
	ik.free()

func test_blocked_movement_settles() -> void :
	var pair: = fixture(); var p = pair[0]; var ik = pair[1]
	p.current_velocity = Vector3.RIGHT * 5.8
	for frame in range(4): tick(p, ik, 1.0 / 60.0, ready_pose())
	for frame in range(90): tick(p, ik, 1.0 / 60.0, ready_pose(), false)
	_assert_false(ik._moving, "holding against boundary cannot run in place")
	_assert_eq(ik._active_side, -1, "blocked steps settle")
	_assert_eq_f(ik.gait_arc_length, 0, 1e-05)
	ik.free()

func test_editor_preserves_exact_authored_stance() -> void :
	for num in [0, 1]:
		var pair: = fixture(num); var p = pair[0]; var ik = pair[1]
		p.posture.editor_preview_mode = true
		var def: = ready_pose();def.right_foot_offset = Vector3(0.1, 0.2, 0.15)
		def.left_foot_offset = Vector3(-0.1, -0.03, -0.1)
		def.right_foot_yaw_deg = 41;def.left_foot_yaw_deg = -29
		var base: = Vector3(p.global_position.x, IK.ANKLE_HEIGHT, p.global_position.z)
		var expected: Array[Vector3] = ik._stance_targets(def, base, true)
		tick(p, ik, 1.0 / 60.0, def)
		_assert_eq_v3(ik.right_foot_smooth, expected[0], 1e-05)
		_assert_eq_v3(ik.left_foot_smooth, expected[1], 1e-05)
		var fwd: Vector3 = p._get_forward_axis()
		_assert_eq_f(p.right_leg_node.foot_pivot.global_rotation.y, atan2( - fwd.x, - fwd.z) - deg_to_rad(41.0), 1e-05)
		p.posture.editor_preview_mode = false
		tick(p, ik, 1.0 / 60.0, def)
		_assert_eq_f(ik.right_foot_smooth.y, IK.ANKLE_HEIGHT + .2, 1e-05, "editor exit preserves explicit lift")
		_assert_eq_f(ik.left_foot_smooth.y, IK.ANKLE_HEIGHT, 1e-05, "runtime clamps negative authored lift")
		_assert_true(not ik.right_foot_locked, "elevated authored foot has no ground contact")
		def.right_foot_offset.y = 0.0
		tick(p, ik, 1.0 / 60.0, def)
		_assert_true(not ik.right_foot_locked, "lowering foot stays released during settling step")
		for frame in range(30): tick(p, ik, 1.0 / 60.0, def)
		_assert_eq_f(ik.right_foot_smooth.y, IK.ANKLE_HEIGHT, 1e-05, "explicit lift clearing settles to floor")
		_assert_true(ik.right_foot_locked, "completed ground arrival reacquires contact")
		ik.free()

func test_yaw_converges_despite_solver_rotation_reset() -> void :
	var pair: = fixture(); var p = pair[0]; var ik = pair[1]
	var def: = ready_pose();def.right_foot_yaw_deg = 60
	for frame in range(120): tick(p, ik, 1.0 / 60.0, def)
	_assert_eq_f(p.right_leg_node.foot_pivot.global_rotation.y, deg_to_rad(-60), 0.0001)
	ik.free()

func test_frame_rate_and_hitch_stability() -> void :
	var ends: Array[Vector3] = []
	for fps in [30, 60, 120]:
		var pair: = fixture(); var p = pair[0]; var ik = pair[1]
		p.current_velocity = Vector3.RIGHT * 5.8
		measure(p, ik, ready_pose(), fps * 2, 1.0 / fps)
		ends.append(ik.right_foot_smooth)

		tick(p, ik, 0.15, ready_pose())
		_assert_lt(planar_gap(ik.right_foot_smooth, p.global_position), 0.88)
		_assert_lt(planar_gap(ik.left_foot_smooth, p.global_position), 0.88)
		_assert_ge(ik.right_foot_smooth.distance_to(ik.left_foot_smooth), 0.095)
		ik.free()
	_assert_eq_v3(ends[0], ends[1], 0.035, "30/60Hz travel gives equivalent feet")
	_assert_eq_v3(ends[1], ends[2], 0.035, "60/120Hz travel gives equivalent feet")

func test_source_posture_is_immutable() -> void :
	var pair: = fixture(); var p = pair[0]; var ik = pair[1]
	var def: = ready_pose(); var offset: = Vector3(0.1, 0.3, -0.2)
	var original_width: float = def.stance_width
	def.right_foot_offset = offset
	p.current_velocity = Vector3.RIGHT * 5.8
	for frame in range(30): tick(p, ik, 1.0 / 60.0, def)
	_assert_eq_v3(def.right_foot_offset, offset, 1e-05)
	_assert_eq_f(def.stance_width, original_width, 1e-05, "step planning must not mutate the supplied stance")
	ik.free()

func test_lock_helper_is_exact() -> void :
	var ik: = IK.new()
	var locked: = Vector3(1, IK.ANKLE_HEIGHT, 2)
	var result: Array = ik._apply_foot_lock(locked + Vector3(0.2, 0, 0.1), false, false, true, locked, 1.0 / 60.0)
	_assert_eq_v3(result[0], locked, 1e-05, "locked means locked, not damped")
	ik.free()

func test_render_physics_rate_mismatch() -> void :
	for render_fps in [30, 90, 144, 240]:
		var pair: = fixture(); var p = pair[0]; var ik = pair[1]
		p.current_velocity = Vector3.RIGHT * 5.8
		var pending: = 0.0
		var old_r: Vector3 = ik.right_foot_smooth
		var old_l: Vector3 = ik.left_foot_smooth
		var rt: = 1.0; var lt: = 1.0
		var max_gap: = 0.0; var drift: = 0.0
		for frame in range(render_fps * 3):
			pending += 1.0 / render_fps
			while pending >= 1.0 / 60.0 - 1e-06:
				p.global_position += p.current_velocity / 60.0
				pending -= 1.0 / 60.0
			tick(p, ik, 1.0 / render_fps, ready_pose(), false)
			if rt >= 1.0 and ik.right_step_t >= 1.0: drift = maxf(drift, old_r.distance_to(ik.right_foot_smooth))
			if lt >= 1.0 and ik.left_step_t >= 1.0: drift = maxf(drift, old_l.distance_to(ik.left_foot_smooth))
			max_gap = maxf(max_gap, maxf(planar_gap(ik.right_foot_smooth, p.global_position), planar_gap(ik.left_foot_smooth, p.global_position)))
			old_r = ik.right_foot_smooth;old_l = ik.left_foot_smooth
			rt = ik.right_step_t;lt = ik.left_step_t
		_assert_le(drift, 1e-05, "%dHz renderer cannot unplant feet" % render_fps)
		_assert_le(max_gap, 0.88, "%dHz renderer remains within reach" % render_fps)
		_assert_gt(ik.gait_arc_length, 15.0, "zero-displacement render frames cannot reset the gait")
		ik.free()

func test_speed_scaled_steps_are_compact() -> void :
	for speed in [0.35, 0.8, 1.3, 2.0, 5.8, 6.5]:
		for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3(1, 0, -1).normalized()]:
			var pair: = fixture(); var p = pair[0]; var ik = pair[1]
			p.current_velocity = direction * speed
			var data: = measure(p, ik, ready_pose(), 600, 1.0 / 120.0)
			var tag: = "compact %.2fm/s %s" % [speed, direction]
			assert_trace(data, tag)
			_assert_le(data.max_spread, 0.86, tag + " no metre-wide split")
			_assert_le(data.gap, 0.62, tag + " knees stay under the body")
			if speed >= IK.RUN_ENTER_SPEED:
				_assert_true(data.running, tag + " uses running recovery")
				_assert_in_range(data.run_contacts / 5.0, 2.8, 4.8, tag + " natural run cadence")
				_assert_le(data.lift, 0.165, tag + " no high-knee marching")
			else:
				_assert_false(data.running, tag + " adjustment stays a shuffle")
				_assert_le(data.lift, 0.045, tag + " small adjustment lift")
			ik.free()

func test_run_to_shuffle_and_idle_transitions() -> void :
	for end_speed in [0.0, 0.8, 1.3]:
		for end_frame in range(1, 45):
			var pair: = fixture(); var p = pair[0]; var ik = pair[1]
			p.current_velocity = Vector3(1, 0, -1).normalized() * 5.8
			for frame in range(end_frame): tick(p, ik, 1.0 / 60.0, ready_pose())
			p.current_velocity = Vector3.LEFT * end_speed
			var data: = measure(p, ik, ready_pose(), 120, 1.0 / 60.0)
			_assert_le(data.drift, 1e-05, "run transition never drags a contact")
			_assert_le(data.gap, 0.78, "run transition remains reachable")
			_assert_ge(data.floor, IK.ANKLE_HEIGHT - 1e-05, "run transition floor")
			_assert_false(ik._run_active, "run finishes after deceleration")
			if end_speed == 0.0:
				_assert_true(ik.right_foot_locked and ik.left_foot_locked, "idle ends with both planted")
				_assert_eq(ik._active_side, -1, "idle finishes recovery")
			ik.free()

func test_run_rapid_turns_keep_contact_and_clearance() -> void :
	for num in [0, 1]:
		var pair: = fixture(num); var p = pair[0]; var ik = pair[1]
		var drift: = 0.0; var reach: = 0.0; var min_shoe: = 100.0
		var previous: Array[Vector3] = [ik.right_foot_smooth, ik.left_foot_smooth]
		var locked: = [ik.right_foot_locked, ik.left_foot_locked]
		for frame in range(600):
			var angle: float = floorf(frame / 23.0) * PI * 0.5
			p.current_velocity = Vector3(cos(angle), 0, sin(angle)) * 5.8
			tick(p, ik, 1.0 / 120.0, ready_pose())
			var feet: Array[Vector3] = [ik.right_foot_smooth, ik.left_foot_smooth]
			var current: = [ik.right_foot_locked, ik.left_foot_locked]
			for side in [0, 1]:
				if locked[side] and current[side]: drift = maxf(drift, previous[side].distance_to(feet[side]))
				reach = maxf(reach, planar_gap(feet[side], p.global_position))
			min_shoe = minf(min_shoe, feet[0].distance_to(feet[1]))
			previous = feet;locked = current
		_assert_le(drift, 1e-05, "hard turns preserve world contacts")
		_assert_le(reach, 0.78, "hard turns preserve reach")
		_assert_ge(min_shoe, 0.095, "hard turns keep shoes apart")
		ik.free()

func test_serve_setup_initializes_legal_stance() -> void :
	var pair: = fixture(); var p = pair[0]; var ik = pair[1]
	p.current_velocity = Vector3.RIGHT * 5.8
	for frame in range(15): tick(p, ik, 1.0 / 60.0, ready_pose())
	p.global_position = Vector3(0, 1, 6.8)
	var def: = ready_pose();def.front_foot_forward = -0.12;def.back_foot_back = -0.34
	ik.initialize_serve_stance(def)
	_assert_true(ik.right_foot_locked and ik.left_foot_locked)
	_assert_false(ik._run_active, "serve reset cancels old run")
	_assert_ge(ik.right_foot_smooth.z, 6.9, "right foot starts behind baseline")
	_assert_ge(ik.left_foot_smooth.z, 6.9, "left foot starts behind baseline")
	var serve_right: Vector3 = ik.right_foot_smooth
	var serve_left: Vector3 = ik.left_foot_smooth
	p.current_velocity = Vector3.ZERO
	p.hitting.serving_visual_active = true
	for frame in range(30): tick(p, ik, 1.0 / 60.0, ready_pose())
	_assert_eq_v3(ik.right_foot_smooth, serve_right, 1e-05, "AI ready guesses cannot move serve foot")
	_assert_eq_v3(ik.left_foot_smooth, serve_left, 1e-05, "serve anchor survives charge and contact")
	ik.free()
