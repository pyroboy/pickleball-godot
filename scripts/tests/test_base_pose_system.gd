extends RefCounted

func run_all(totals: Dictionary) -> void:
	_test_base_pose_library_loads(totals)
	_test_base_pose_blend_preserves_stroke_paddle_fields(totals)
	_test_preview_blend_uses_full_body_override(totals)
	_test_runtime_override_passthrough(totals)


func _test_base_pose_library_loads(totals: Dictionary) -> void:
	var library := BasePoseLibrary.instance()
	_assert(library.all_definitions().size() >= 22, "base pose library exposes the full authored taxonomy", totals)
	_assert(library.has_def(0), "base pose library includes ATHLETIC_READY", totals)
	_assert(library.has_def(14), "base pose library includes OVERHEAD_PREP", totals)


func _test_base_pose_blend_preserves_stroke_paddle_fields(totals: Dictionary) -> void:
	var stroke := PostureDefinition.new()
	stroke.posture_id = 12
	stroke.display_name = "Volley Ready"
	stroke.paddle_forehand_mul = 0.4
	stroke.paddle_forward_mul = 0.55
	stroke.paddle_y_offset = 0.18
	stroke.stance_width = 0.35
	stroke.crouch_amount = 0.02
	stroke.body_pitch_deg = 0.0

	var base_pose := BasePoseDefinition.new()
	base_pose.stroke_overlay_mix = 1.0
	base_pose.stance_width = 0.64
	base_pose.crouch_amount = 0.26
	base_pose.body_pitch_deg = 12.0

	var blended := base_pose.blend_onto_stroke(stroke)
	_assert(blended != null, "base pose blend returns a posture definition", totals)
	_assert(is_equal_approx(blended.paddle_forehand_mul, 0.4), "base pose blend keeps authored paddle sideways offset", totals)
	_assert(is_equal_approx(blended.paddle_forward_mul, 0.55), "base pose blend keeps authored paddle forward offset", totals)
	_assert(is_equal_approx(blended.paddle_y_offset, 0.18), "base pose blend keeps authored paddle height", totals)
	_assert(is_equal_approx(blended.stance_width, 0.64), "base pose blend overrides body stance width", totals)
	_assert(is_equal_approx(blended.crouch_amount, 0.26), "base pose blend overrides crouch amount", totals)
	_assert(is_equal_approx(blended.body_pitch_deg, 12.0), "base pose blend overrides body pitch", totals)


func _test_preview_blend_uses_full_body_override(totals: Dictionary) -> void:
	var stroke := PostureDefinition.new()
	stroke.left_hand_mode = 0
	stroke.head_track_ball_weight = 0.25
	stroke.right_foot_offset = Vector3.ZERO

	var base_pose := BasePoseDefinition.new()
	base_pose.stroke_overlay_mix = 1.0
	base_pose.left_hand_mode = 3
	base_pose.head_track_ball_weight = 1.0
	base_pose.right_foot_offset = Vector3(0.18, 0.0, 0.12)

	var preview := base_pose.to_preview_posture(stroke)
	_assert(preview.left_hand_mode == 3, "preview posture adopts support-hand mode from the base pose", totals)
	_assert(is_equal_approx(preview.head_track_ball_weight, 1.0), "preview posture adopts head tracking from the base pose", totals)
	_assert(preview.right_foot_offset.is_equal_approx(Vector3(0.18, 0.0, 0.12)), "preview posture adopts foot offsets from the base pose", totals)


func _test_runtime_override_passthrough(totals: Dictionary) -> void:
	var player := PlayerController.new()
	var override_def := PostureDefinition.new()
	override_def.posture_id = 99
	override_def.body_pitch_deg = 14.0

	var resolved := player.get_runtime_posture_def(override_def)
	_assert(resolved == override_def, "runtime posture helper returns explicit preview overrides unchanged", totals)


func _assert(condition: bool, label: String, totals: Dictionary) -> void:
	if condition:
		totals.pass += 1
	else:
		totals.fail += 1
		totals.errors.append(label)
