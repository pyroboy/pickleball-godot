extends SceneTree
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Side = preload("res://scripts/tests/test_stroke_orientation.gd").CourtSide
var failures: = 0
var checks: = 0
func _initialize() -> void :
	var old_script: Script
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--original="): old_script = load(arg.trim_prefix("--original="))


	for side in [0, 1]:
		var player = Side.new(side)
		for style in range(7):
			for y in [0.08, 0.17, 0.265, 0.37, 0.45]:
				for q in [0.0, 0.025, 0.1, 0.25, 0.44, 0.45, 0.65, 1.0]:
					var pose = Motion.serve_style_preparation(style, q, Vector3(0.22, y, 0.48))
					var original = Motion.original_serve_load(pose)
					var expected = original
					if q < 0.45:
						var hold = original.lerp_with(original, 0.0)
						hold.paddle_forehand_mul = 0.55;hold.paddle_y_offset = 0.02;hold.paddle_forward_mul = 0.15;hold.paddle_roll_base_deg = 58
						expected = Path.blend_pose(hold, original, smoothstep(0, 0.45, q))
					checks += 2
					if not Path.world_transform(player, pose).is_equal_approx(Path.world_transform(player, expected)): failures += 1
					if not pose.left_hand_offset.is_equal_approx(expected.left_hand_offset): failures += 1
					if old_script:
						var old_pose = old_script.serve_style_preparation(style, q, Vector3(0.22, y, 0.48))
						checks += 2
						if not Path.world_transform(player, pose).is_equal_approx(Path.world_transform(player, old_pose)): failures += 1
						if not pose.left_hand_offset.is_equal_approx(old_pose.left_hand_offset): failures += 1
					var prior: float = pose.paddle_y_offset
					pose.paddle_y_offset = 999
					var fresh = Motion.serve_style_preparation(style, q, Vector3(0.22, y, 0.48))
					checks += 1
					if not is_equal_approx(fresh.paddle_y_offset, prior): failures += 1
	print("HOLD ALLOCATION PARITY: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
