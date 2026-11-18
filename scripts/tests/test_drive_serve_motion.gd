extends TestBase
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")

class PosePlayer extends RefCounted:
	var player_num: int = 0
	var global_position: = Vector3(0, 1, 0)
	var global_transform: = Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	const COURT_FLOOR_Y: = 0.075
	func _get_swing_sign() -> float: return -1.0 if player_num == 0 else 1.0
	func _get_forehand_axis() -> Vector3: return Vector3.RIGHT if player_num == 0 else Vector3.LEFT
	func _get_forward_axis() -> Vector3: return Vector3.FORWARD if player_num == 0 else Vector3.BACK

func run_all(totals: Dictionary) -> void :
	_run_test_list(totals, [test_drive_context, test_drive_contact_and_charge, test_drive_continuity_and_reach, 
		test_serve_contact_legality_and_mirror, test_serve_preparation_and_finish, test_distinct_dink_and_smash, test_spin_variants_reach, test_kitchen_profiles, test_drop_charge_stays_compact])

func _forehand() -> PostureDefinition:
	return load("res://data/postures/00_forehand.tres")

func test_drive_context() -> void :
	var base: PostureDefinition = _forehand()
	_assert_eq_f(Motion.drive_strength(base, 1, true), 0, 0.0001, "volley stays compact")
	_assert_eq_f(Motion.drive_strength(base, 0.5), 0, 0.0001, "soft stroke retains authored path")
	for tier in [0, 1, 3]:
		var other: PostureDefinition = base.lerp_with(base, 0)
		other.height_tier = tier
		_assert_eq_f(Motion.drive_strength(other, 1), 0, 0.0001, "low/overhead retains distinct path")
	_assert_eq_f(Motion.drive_strength(base, 1), 1, 0.0001, "charged waist drive gets full profile")

func test_drive_contact_and_charge() -> void :
	var base: PostureDefinition = _forehand()
	var original: Vector3 = base.charge_paddle_offset
	for charge in [0.25, 0.5, 0.65, 0.8, 1.0]:
		var held: PostureDefinition = Motion.held_drive_pose(base, charge)
		var start: PostureDefinition = Motion.sample_drive(base, 0, charge)
		var contact: PostureDefinition = Motion.sample_drive(base, 0.5, charge)
		_assert_eq_v3(_position(held), _position(start), 0.0001, "held and released stroke meet")
		_assert_eq_f(held.hip_yaw_deg, start.hip_yaw_deg, 0.0001, "no body snap on release")
		_assert_eq_v3(_position(contact), _position(base), 0.0001, "contact head stays on predicted point")
		_assert_eq(contact.paddle_hand, base.paddle_hand, "dominant hand never changes")
	var load: PostureDefinition = Motion.held_drive_pose(base, 1)
	var slot: PostureDefinition = Motion.sample_drive(base, 0.3, 1)
	var finish: PostureDefinition = Motion.sample_drive(base, 1, 1)
	_assert_lt(load.weight_shift, -0.5, "rear leg loaded")
	_assert_gt(absf(load.body_yaw_deg + load.hip_yaw_deg + load.torso_yaw_deg), 40, "whole upper body unit turn")
	_assert_lt(slot.paddle_y_offset, load.paddle_y_offset - 0.1, "moving paddle enters lower slot")
	_assert_gt(finish.paddle_y_offset, base.paddle_y_offset + 0.3, "high finish")
	_assert_lt(finish.paddle_forehand_mul, -0.1, "forehand wraps toward opposite shoulder")
	_assert_eq_v3(base.charge_paddle_offset, original, 0.0001, "profile never changes persisted resource")

func test_drive_continuity_and_reach() -> void :
	for file in ["00_forehand", "02_backhand", "10_wide_forehand", "11_wide_backhand"]:
		var base: PostureDefinition = load("res://data/postures/%s.tres" % file)
		for side in [0, 1]:
			var player: = PosePlayer.new()
			player.player_num = side
			for charge in [0.25, 0.5, 0.65, 0.8, 1.0]:
				var prev: Vector3 = Vector3.INF
				for step in range(65):
					var pose: PostureDefinition = Motion.sample_drive(base, step / 64.0, charge)
					var tx: Transform3D = Path.world_transform(player, pose)
					var grip: Vector3 = tx * PaddleSize.MAIN_GRIP_OFFSET
					_assert_le(grip.distance_to(Body.shoulder_world(player, pose)), 0.705, "%s charge%.2f side%d sample%d grip reach" % [file, charge, side, step])
					var head: Vector3 = tx * PaddleSize.HEAD_OFFSET
					_assert_ge(head.y, 0.075 + pose.paddle_floor_clearance - 0.0001, "paddle stays above court")
					if prev != Vector3.INF: _assert_lt(head.distance_to(prev), 0.07, "continuous drive path")
					prev = head

func test_serve_contact_legality_and_mirror() -> void :
	var pose: PostureDefinition = Motion.serve_contact()
	var blue: Transform3D
	for side in [0, 1]:
		var player: = PosePlayer.new()
		player.player_num = side
		var tx: Transform3D = Path.world_transform(player, pose)
		var head: Vector3 = tx * PaddleSize.HEAD_OFFSET
		var wrist: Vector3 = tx * PaddleSize.MAIN_GRIP_OFFSET
		var ball_center: Vector3 = player.global_position + Motion.serve_launch_offset(side == 1)
		var ball_local: Vector3 = tx.affine_inverse() * ball_center
		_assert_eq_f(head.distance_to(ball_center), PaddleSize.HEAD_HALF_THICKNESS + 0.0375, 0.0001, "serve ball sphere touches paddle face")
		_assert_eq_f(absf(ball_local.z), PaddleSize.HEAD_HALF_THICKNESS + 0.0375, 0.0001, "normal separation is ball radius plus paddle half thickness")
		_assert_eq_f(ball_local.y, PaddleSize.HEAD_CENTER_Y, 0.0001, "serve impact centered on paddle surface")
		_assert_lt(head.y, player.global_position.y, "contact below waist")
		_assert_lt(tx.basis.y.y, -0.75, "shaft down with head below grip")
		_assert_gt(absf(tx.basis.z.dot(player._get_forward_axis())), 0.95, "broad face points through ball")
		var highest: float = - INF
		for point in PaddleSize.head_hull_points(): highest = maxf(highest, (tx * point).y)
		_assert_lt(highest, wrist.y, "entire head, not just center, remains below wrist")
		if side == 0: blue = tx
		else:
			var rotation: = Basis(Vector3.UP, PI)
			_assert_eq_v3(head - player.global_position, rotation * (blue * PaddleSize.HEAD_OFFSET - player.global_position), 0.0001, "court mirror preserves contact")
			_assert_eq_v3(tx.basis.y, rotation * blue.basis.y, 0.0001, "shaft mirror")
	_assert_eq(pose.paddle_hand, 0, "serve remains right dominant")
	_assert_lt(pose.front_foot_forward, -0.1, "lead foot behind server root")
	_assert_lt(pose.back_foot_back, -0.3, "rear foot loaded behind baseline")

func test_serve_preparation_and_finish() -> void :
	var loaded: PostureDefinition = Motion.serve_preparation(1)
	_assert_lt(loaded.weight_shift, -0.5, "charged serve loads rear leg")
	_assert_gt(loaded.crouch_amount, Motion.serve_preparation(0).crouch_amount, "charge bends knees")
	_assert_eq_v3(Vector3(-0.15, 0.15, 0.55) + loaded.left_hand_offset, Motion.SERVE_CONTACT + Vector3.UP * (Motion.SERVE_HOLD_HEIGHT - Motion.serve_palm_depth(1.0)), 0.0001, "wrist holds the ball above the palm surface")
	var contact: PostureDefinition = Motion.serve_contact()
	var next: PostureDefinition = Motion.serve_follow_through(1, 0.01)
	_assert_gt(next.paddle_y_offset, contact.paddle_y_offset, "upward path through impact")
	_assert_gt(next.paddle_forward_mul, contact.paddle_forward_mul, "forward extension through impact")
	for side in [0, 1]:
		var player: = PosePlayer.new()
		player.player_num = side
		for step in range(65):
			var pose: PostureDefinition = Motion.serve_follow_through(1, step / 64.0)
			var tx: Transform3D = Path.world_transform(player, pose)
			_assert_le((tx * PaddleSize.MAIN_GRIP_OFFSET).distance_to(Body.shoulder_world(player, pose)), 0.705, "serve sweep grip reach")
	var finish: PostureDefinition = Motion.serve_follow_through(1, 1)
	_assert_lt(finish.paddle_forehand_mul, 0, "serve finishes across body")
	_assert_gt(finish.paddle_y_offset, 0.4, "serve finishes up")

func _position(pose: PostureDefinition) -> Vector3:
	return Vector3(pose.paddle_forehand_mul, pose.paddle_y_offset, pose.paddle_forward_mul)

func test_distinct_dink_and_smash() -> void :
	var dink: PostureDefinition = load("res://data/postures/13_mid_low_forehand.tres")
	var dload: PostureDefinition = Motion.held_drive_pose(dink, 1)
	var dfinish: PostureDefinition = Motion.sample_drive(dink, 1, 1)
	_assert_eq(Motion.motion_kind(dink, 1), "DINK", "low ball uses compact touch motion")
	_assert_lt(absf(dload.paddle_forward_mul - dink.paddle_forward_mul), 0.15, "dink has small backswing")
	_assert_lt(absf(dfinish.paddle_y_offset - dink.paddle_y_offset), 0.15, "dink avoids shoulder-high finish")
	var smash: PostureDefinition = load("res://data/postures/04_high_overhead.tres")
	var sload: PostureDefinition = Motion.held_drive_pose(smash, 1)
	var sfinish: PostureDefinition = Motion.sample_drive(smash, 1, 1)
	_assert_eq(Motion.motion_kind(smash, 1), "SMASH", "overhead remains distinct")
	_assert_lt(sload.paddle_forward_mul, -0.2, "smash loads behind body")
	_assert_gt(sload.paddle_y_offset, 0.55, "smash loads above shoulder")
	_assert_gt(sload.paddle_forehand_mul, 0.25, "smash avoids head center")
	_assert_lt(sfinish.paddle_y_offset, smash.paddle_y_offset - 0.5, "smash finishes down")

func test_spin_variants_reach() -> void :
	for file in ["00_forehand", "02_backhand", "03_medium_overhead", "04_high_overhead", "05_low_forehand", "07_low_backhand", "13_mid_low_forehand", "14_mid_low_backhand", "16_mid_low_wide_forehand", "17_mid_low_wide_backhand"]:
		var base: PostureDefinition = load("res://data/postures/%s.tres" % file)
		for mode in range(3):
			for side in range(2):
				var player: = PosePlayer.new()
				player.player_num = side
				for step in range(65):
					var pose: PostureDefinition = Motion.sample_drive(base, step / 64.0, 1, false, mode)
					var tx: Transform3D = Path.world_transform(player, pose)
					_assert_le((tx * PaddleSize.MAIN_GRIP_OFFSET).distance_to(Body.shoulder_world(player, pose)), 0.705, "%s mode%d side%d step%d grip reach" % [file, mode, side, step])
	var flat: PostureDefinition = Motion.sample_drive(_forehand(), 1, 1, false, 0)
	var slice: PostureDefinition = Motion.sample_drive(_forehand(), 1, 1, false, 2)
	_assert_lt(slice.paddle_y_offset, flat.paddle_y_offset - 0.15, "slice finish is shallower than drive")
	for mode in range(3):
		var player: = PosePlayer.new()
		for step in range(65):
			var pose: PostureDefinition = Motion.serve_follow_through(1, step / 64.0, mode)
			var tx: Transform3D = Path.world_transform(player, pose)
			_assert_le((tx * PaddleSize.MAIN_GRIP_OFFSET).distance_to(Body.shoulder_world(player, pose)), 0.705, "serve mode%d sample%d grip reach" % [mode, step])

func test_kitchen_profiles() -> void :
	var base: PostureDefinition = _forehand()
	var drive: PostureDefinition = Motion.held_drive_pose(base, 1)
	var dink: PostureDefinition = Motion.held_drive_pose(base, 1, false, 0, true)
	var block: PostureDefinition = Motion.held_drive_pose(base, 1, true, 0, true)
	_assert_gt(dink.paddle_forward_mul, drive.paddle_forward_mul + 0.4, "kitchen charge avoids long backswing")
	_assert_gt(block.paddle_forward_mul, dink.paddle_forward_mul, "volley block stays more compact than dink")
	_assert_eq(Motion.motion_kind(base, 1, false, true), "DINK", "kitchen ground contact uses dink")
	_assert_eq(Motion.motion_kind(base, 1, true, true), "VOLLEY", "kitchen incoming volley uses block")
	var ready_base: PostureDefinition = load("res://data/postures/20_ready.tres")
	var ready: PostureDefinition = Motion.kitchen_ready(ready_base)
	_assert_ge(ready.crouch_amount, 0.1, "kitchen ready loads more than neutral without a deep squat")
	_assert_ge(ready.stance_width, 0.5, "kitchen ready has a stable, compact lateral base")
	_assert_eq_f(ready.paddle_yaw_signed_deg, ready_base.paddle_yaw_signed_deg, 0.0001, "kitchen preserves authored neutral orientation")
	for file in ["00_forehand", "02_backhand", "10_wide_forehand", "11_wide_backhand", "05_low_forehand", "07_low_backhand"]:
		var contact: PostureDefinition = load("res://data/postures/%s.tres" % file)
		for volley in [false, true]:
			var player: = PosePlayer.new()
			for step in range(65):
				var pose: PostureDefinition = Motion.sample_drive(contact, step / 64.0, 1, volley, 0, true)
				var tx: Transform3D = Path.world_transform(player, pose)
				_assert_le((tx * PaddleSize.MAIN_GRIP_OFFSET).distance_to(Body.shoulder_world(player, pose)), 0.705, "%s kitchen volley%s step%d grip reach" % [file, volley, step])

func test_drop_charge_stays_compact() -> void :
	var base: PostureDefinition = _forehand()
	var full: PostureDefinition = Motion.held_drive_pose(base, 1, false, 0, false, "DROP")
	var finish: PostureDefinition = Motion.sample_drive(base, 1, 1, false, 0, false, "DROP")
	_assert_gt(full.paddle_forward_mul, 0.3, "full drop charge never winds behind body")
	_assert_lt(absf(full.body_yaw_deg - base.body_yaw_deg), 0.01, "drop charge avoids drive unit turn")
	_assert_lt(finish.paddle_y_offset, base.paddle_y_offset + 0.15, "drop has short soft finish")
	for step in range(65):
		var pose: PostureDefinition = Motion.sample_drive(base, step / 64.0, 1, false, 0, false, "DROP")
		_assert_gt(pose.paddle_forward_mul, 0.3, "drop stays in front across path")
