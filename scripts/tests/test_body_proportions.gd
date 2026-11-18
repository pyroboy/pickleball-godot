extends TestBase
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Dimensions = preload("res://scripts/player_body_dimensions.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Geometry = preload("res://scripts/paddle_clearance.gd")
const Side = preload("res://scripts/tests/test_stroke_orientation.gd").CourtSide
const Wrist = preload("res://scripts/tests/pose_anatomical_wrist.gd")

func run_all(totals: Dictionary) -> void :
	_run_test_list(totals, [test_ready_has_natural_knee_flex, test_ready_hands_and_face_clearance])

func test_ready_has_natural_knee_flex() -> void :
	var pose = PostureLibrary.instance().get_def(20)
	for id in [0, 1]:
		var player = Side.new(id)
		for side in [-1, 1]:
			var hip: Vector3 = player.global_transform * Body.pivot_transform(player, pose) * (Body.pelvis_transform(player, pose) * (Vector3.UP * (Dimensions.HIP_HEIGHT - Dimensions.PELVIS_CENTER_Y) + player._get_forehand_axis() * side * Dimensions.HIP_HALF_WIDTH))
			var lead: bool = side == -1 if pose.lead_foot == 1 else side == 1
			var foot: Vector3 = Vector3(0, player.COURT_FLOOR_Y + 0.04, 0) + player._get_forehand_axis() * side * pose.stance_width * 0.5 + player._get_forward_axis() * (pose.front_foot_forward if lead else pose.back_foot_back)
			var distance: float = hip.distance_to(foot)
			var knee: float = rad_to_deg(PI - acos(clampf((Dimensions.THIGH_LENGTH * Dimensions.THIGH_LENGTH + Dimensions.SHIN_LENGTH * Dimensions.SHIN_LENGTH - distance * distance) / (2.0 * Dimensions.THIGH_LENGTH * Dimensions.SHIN_LENGTH), -1.0, 1.0)))


			_assert_in_range(knee, 55.0, 58.0, "joined Ready retains approved lower knee load")
			_assert_le(distance, Dimensions.THIGH_LENGTH + Dimensions.SHIN_LENGTH, "ready leg does not stretch")

func test_ready_hands_and_face_clearance() -> void :
	var pose = PostureLibrary.instance().get_def(20)
	for side in [0, 1]:
		var player = Side.new(side)
		var tx: Transform3D = Path.world_transform(player, pose)
		var hand: Vector3 = Wrist.main_world(player, pose)
		var head: Vector3 = player.global_transform * Body.pivot_transform(player, pose) * Body.torso_transform(player, pose) * Vector3(0, 0.28, 0)
		_assert_in_range(head.y, 1.45, 1.47, "joined Ready retains approved lower head height")
		_assert_lt(hand.y, Body.shoulder_world(player, pose).y, "raised guard keeps wrists below shoulders")
		_assert_ge(Geometry.face_clearance(player, pose), 0.1, "whole paddle clears face")
		_assert_le(hand.distance_to(Body.shoulder_world(player, pose)), 0.705, "ready arm retains natural reach")
