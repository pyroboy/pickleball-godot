class_name TestIncomingReadyMotion extends TestBase
const Motion = preload("res://scripts/incoming_ready_motion.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Clearance = preload("res://scripts/paddle_clearance.gd")
const Side = preload("res://scripts/tests/test_stroke_orientation.gd").CourtSide

func run_all(totals: Dictionary) -> void :
	_run_test_list(totals, [test_ready_guard, test_far_ball_keeps_guard, 
		test_forehand_prepares_before_contact, test_backhand_keeps_identity, 
		test_volley_is_more_compact, test_blend_is_frame_rate_independent, 
		test_source_contact_is_immutable, test_split_load_is_bounded])

func ready() -> PostureDefinition:
	return Motion.ready_pose(PostureLibrary.instance().get_def(20))

func test_ready_guard() -> void :
	var source: PostureDefinition = PostureLibrary.instance().get_def(20)
	var pose: = ready()
	for field in ["paddle_forehand_mul", "paddle_forward_mul", "paddle_y_offset", "paddle_pitch_base_deg", "paddle_yaw_base_deg", "paddle_roll_base_deg", "main_grip_rotation_deg", "support_grip_rotation_deg", "support_grip_slide_m", "support_index_closure", "stance_width", "crouch_amount"]:
		_assert_eq_f(float(pose.get(field)), float(source.get(field)), 1e-06, "Ready preserves authored " + field)
	_assert_eq(pose.left_hand_mode, source.left_hand_mode, "Ready preserves authored two-handed mode")
	_assert_eq_v3(pose.right_hand_offset, source.right_hand_offset, 1e-06, "Ready preserves main grip anchor")
	_assert_eq_v3(pose.left_hand_offset, source.left_hand_offset, 1e-06, "Ready preserves support anchor")
	_assert_in_range(pose.paddle_forward_mul, 0.4, 0.6, "paddle ahead of forward-leaning chest")
	for side in [0, 1]:
		_assert_ge(Clearance.face_clearance(Side.new(side), pose), 0.1, "relaxed ready guard clears the actual face envelope")
		var basis: Basis = Path.paddle_basis(Side.new(side), pose)
		_assert_in_range(basis.y.y, 0.4, 0.8, "approved tip tilts up without a head-high vertical guard")
		_assert_in_range(basis.y.dot(Side.new(side)._get_forward_axis()), 0.5, 0.85, "approved shaft points modestly forward")
	_assert_in_range(pose.crouch_amount, 0.08, 0.16, "approved soft-knee load")
	_assert_in_range(pose.stance_width, 0.5, 0.62, "approved broad athletic base")

func test_far_ball_keeps_guard() -> void :
	var pose: PostureDefinition = Motion.prepare(PostureLibrary.instance().get_def(0), ready(), 1.5, false)
	_assert_eq_f(pose.paddle_forward_mul, ready().paddle_forward_mul, 0.0001)
	_assert_eq_f(pose.paddle_y_offset, ready().paddle_y_offset, 0.0001)

func test_forehand_prepares_before_contact() -> void :
	var def: PostureDefinition = PostureLibrary.instance().get_def(0)
	var pose: PostureDefinition = Motion.prepare(def, ready(), 0.2, false)
	_assert_gt(pose.paddle_forehand_mul, 0.25, "forehand side prepared")
	_assert_lt(pose.paddle_forward_mul, def.paddle_forward_mul - 0.1, "load before impact")
	_assert_gt(pose.paddle_forward_mul, Path.endpoint(def, 0).paddle_forward_mul, "compact automatic prep")

func test_backhand_keeps_identity() -> void :
	var def: PostureDefinition = PostureLibrary.instance().get_def(2)
	var target: PostureDefinition = Motion.prepare(def, ready(), 0.3, false)
	var pose: PostureDefinition = Motion.blend_pose(ready(), target, 1.0 / 60.0)
	_assert_eq(pose.posture_id, 2, "incoming family updates without delayed metadata")
	_assert_eq(pose.paddle_hand, def.paddle_hand, "authored grip preserved")
	_assert_gt(pose.paddle_forehand_mul, target.paddle_forehand_mul, "motion does not snap")

func test_volley_is_more_compact() -> void :
	var def: PostureDefinition = PostureLibrary.instance().get_def(0)
	var volley: PostureDefinition = Motion.prepare(def, ready(), 0.2, true)
	var drive: PostureDefinition = Motion.prepare(def, ready(), 0.2, false)
	_assert_gt(volley.paddle_forward_mul, drive.paddle_forward_mul, "volley stays in front")

func test_blend_is_frame_rate_independent() -> void :
	var target: PostureDefinition = Motion.prepare(PostureLibrary.instance().get_def(0), ready(), 0.2, false)
	var whole: PostureDefinition = Motion.blend_pose(ready(), target, 0.1)
	var halves: PostureDefinition = Motion.blend_pose(Motion.blend_pose(ready(), target, 0.05), target, 0.05)
	_assert_eq_f(whole.paddle_forward_mul, halves.paddle_forward_mul, 1e-05)
	_assert_eq_f(whole.body_yaw_deg, halves.body_yaw_deg, 1e-05)

func test_source_contact_is_immutable() -> void :
	var def: PostureDefinition = PostureLibrary.instance().get_def(0)
	var original: Vector3 = def.resolve_paddle_offset(Vector3.RIGHT, Vector3.FORWARD)
	Motion.prepare(def, ready(), 0.2, false)
	_assert_eq_v3(def.resolve_paddle_offset(Vector3.RIGHT, Vector3.FORWARD), original, 1e-05, "visual preparation does not move collision target")

func test_split_load_is_bounded() -> void :
	_assert_eq_f(Motion.split_load(0), 0, 1e-05)
	_assert_eq_f(Motion.split_load(Motion.SPLIT_DURATION), 0, 1e-05)
	_assert_in_range(Motion.split_load(Motion.SPLIT_DURATION / 2), 0.03, 0.04, "small load, no large hop")
