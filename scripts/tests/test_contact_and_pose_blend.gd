extends TestBase
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Sweep = preload("res://scripts/contact_sweep.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Side = preload("res://scripts/tests/test_stroke_orientation.gd").CourtSide
func run_all(totals: Dictionary) -> void :
	_run_test_list(totals, [test_same_radius_continuous_contact, test_recovery_grip_path, test_pose_basis_endpoints, test_rear_ball_guard_turn_keeps_grip, test_body_yaw_wrap_is_continuous, test_preparation_rotation_rate, test_progressive_charge_has_no_threshold_jump, test_support_mode_transition])
func test_same_radius_continuous_contact() -> void :
	_assert_in_range(Sweep.closest_fraction(Vector3(0, 0, -0.23), Vector3(0, 0, 0.17), Vector3.ZERO, Vector3.ZERO, 0.099), 0.0, 1.0, "fast ball passes through unchanged radius")
	_assert_eq(Sweep.closest_fraction(Vector3(0.101, 0, -1), Vector3(0.101, 0, 1), Vector3.ZERO, Vector3.ZERO, 0.099), -1.0, "near miss must not become a hit")
	_assert_eq(Sweep.closest_fraction(Vector3.ONE, Vector3.ONE, Vector3.ZERO, Vector3.ZERO, 0.099), -1.0, "stationary miss")
	_assert_eq(Sweep.closest_fraction(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 0.099), -1.0, "stationary overlap belongs to the direct contact check, not a subframe sweep")
func test_recovery_grip_path() -> void :
	var ready = PostureLibrary.instance().get_def(20)
	for def in PostureLibrary.instance().all_definitions():
		var finish = Motion.sample_drive(def, 1.0, 0.65, true)
		for side in [0, 1]:
			var player = Side.new(side)


			var from_offset: Vector3 = finish.left_hand_offset if finish.paddle_hand == 1 else finish.right_hand_offset
			var to_offset: Vector3 = ready.left_hand_offset if ready.paddle_hand == 1 else ready.right_hand_offset
			var a: Vector3 = Path.world_transform(player, finish) * (PaddleSize.MAIN_GRIP_OFFSET + from_offset)
			var b: Vector3 = Path.world_transform(player, ready) * (PaddleSize.MAIN_GRIP_OFFSET + to_offset)
			for step in range(65):
				var t: float = step / 64.0
				var pose = Path.blend_pose(finish, ready, t)
				var offset: Vector3 = pose.left_hand_offset if pose.paddle_hand == 1 else pose.right_hand_offset
				var grip: Vector3 = Path.world_transform(player, pose) * (PaddleSize.MAIN_GRIP_OFFSET + offset)
				_assert_lt(grip.distance_to(a.lerp(b, t)), 0.001, "recovery rotates paddle around interpolated grip, " + def.display_name)
func test_pose_basis_endpoints() -> void :
	var ready = PostureLibrary.instance().get_def(20)
	for def in PostureLibrary.instance().all_definitions():
		for side in [0, 1]:
			var player = Side.new(side)
			for t in [0.0, 1.0]:
				var expected: Basis = Path.paddle_basis(player, def if t == 0.0 else ready)
				var actual: Basis = Path.paddle_basis(player, Path.blend_pose(def, ready, t))
				_assert_lt(actual.x.distance_to(expected.x), 0.0002, "basis endpoint width")
				_assert_lt(actual.y.distance_to(expected.y), 0.0002, "basis endpoint shaft")
				_assert_lt(actual.z.distance_to(expected.z), 0.0002, "basis endpoint face")

func test_rear_ball_guard_turn_keeps_grip() -> void :
	var ready = PostureLibrary.instance().get_def(20)
	for side in [0, 1]:
		var player = Side.new(side)
		var expected: float = (Path.world_transform(player, ready) * PaddleSize.MAIN_GRIP_OFFSET).distance_to(Path.BodyPose.shoulder_world(player, ready))
		for yaw in [-95, -70, -45, 0, 45, 70, 95]:
			var pose = Path.rotate_guard(ready, yaw)
			var actual: float = (Path.world_transform(player, pose) * PaddleSize.MAIN_GRIP_OFFSET).distance_to(Path.BodyPose.shoulder_world(player, pose))
			_assert_eq_f(actual, expected, 0.0001, "turning to follow a rear ball keeps paddle with body")

func test_body_yaw_wrap_is_continuous() -> void :
	var a = PostureLibrary.instance().get_def(20).duplicate(true)
	var b = a.duplicate(true)
	a.body_yaw_deg = 170.0
	b.body_yaw_deg = -170.0
	var middle = Path.blend_pose(a, b, 0.5)
	_assert_lt(absf(absf(middle.body_yaw_deg) - 180.0), 0.001, "rear wrap must not turn torso through forward while paddle turns behind")

func test_preparation_rotation_rate() -> void :
	var ReadyMotion = preload("res://scripts/incoming_ready_motion.gd")
	var ready = PostureLibrary.instance().get_def(20)
	var player = Side.new(0)
	for id in [0, 2, 4, 5, 7, 13, 14, 16, 19]:
		var target = PostureLibrary.instance().get_def(id)
		for fps in [30, 60, 120]:
			var pose = ReadyMotion.blend_pose(ready, target, 1.0 / fps, 0.001)
			var angle: float = Path.paddle_basis(player, ready).get_rotation_quaternion().angle_to(Path.paddle_basis(player, pose).get_rotation_quaternion())
			_assert_le(rad_to_deg(angle), ReadyMotion.MAX_PREPARATION_ANGULAR_SPEED_DEG / fps + 0.01, "prepare rotates at bounded speed, pose%d %dfps" % [id, fps])

func test_progressive_charge_has_no_threshold_jump() -> void :
	for id in [0, 2, 10, 11]:
		for mode in range(3):
			for side in [0, 1]:
				var player = Side.new(side)
				var base = PostureLibrary.instance().get_def(id)
				var previous: Transform3D = Path.world_transform(player, Motion.held_drive_pose(base, 0.0, false, mode))
				for step in range(1, 101):
					var pose = Motion.held_drive_pose(base, step / 100.0, false, mode)
					var current: Transform3D = Path.world_transform(player, pose)
					_assert_lt((current * PaddleSize.MAIN_GRIP_OFFSET).distance_to(previous * PaddleSize.MAIN_GRIP_OFFSET), 0.035, "progressive charge wrist continuity")
					_assert_lt(rad_to_deg(previous.basis.get_rotation_quaternion().angle_to(current.basis.get_rotation_quaternion())), 8.0, "progressive charge shortest rotation")
					previous = current

func test_support_mode_transition() -> void :
	var ready = PostureLibrary.instance().get_def(20)
	var low = PostureLibrary.instance().get_def(7)
	var a: Vector3 = Path.support_wrist_offset(low)
	var b: Vector3 = Path.support_wrist_offset(ready)
	for step in range(21):
		var t: float = step / 20.0
		var pose = Path.blend_pose(low, ready, t)
		_assert_lt(Path.support_wrist_offset(pose).distance_to(a.lerp(b, t)), 0.0001, "free hand blends in one coordinate space before regripping")
