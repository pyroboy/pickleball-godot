extends RefCounted

## Tests for PostureEditorUI control wiring.
##
## Verifies that every control (slider, dropdown, checkbox, Vector3 editor)
## properly emits field_changed signal with correct field_name and value.
##
## Scene-less tests: pure logic paths only.
## Tests requiring PlayerController with full scene tree are skipped.

const PADDLE_TAB_PATH := "res://scripts/posture_editor/tabs/paddle_tab.gd"
const LEGS_TAB_PATH := "res://scripts/posture_editor/tabs/legs_tab.gd"
const ARMS_TAB_PATH := "res://scripts/posture_editor/tabs/arms_tab.gd"
const HEAD_TAB_PATH := "res://scripts/posture_editor/tabs/head_tab.gd"
const TORSO_TAB_PATH := "res://scripts/posture_editor/tabs/torso_tab.gd"
const CHARGE_TAB_PATH := "res://scripts/posture_editor/tabs/charge_tab.gd"
const FOLLOW_THROUGH_TAB_PATH := "res://scripts/posture_editor/tabs/follow_through_tab.gd"

## Track all emitted (field_name, value) pairs for verification.
var _captured_fields: Array = []

func run_all(totals: Dictionary) -> void:
	_captured_fields.clear()
	_test_paddle_tab_fields(totals)
	_test_legs_tab_fields(totals)
	_test_arms_tab_fields(totals)
	_test_head_tab_fields(totals)
	_test_torso_tab_fields(totals)
	_test_charge_tab_fields(totals)
	_test_follow_through_tab_fields(totals)
	_test_signal_connections_integrity(totals)


## ── Paddle Tab ────────────────────────────────────────────────────────────────

func _test_paddle_tab_fields(totals: Dictionary) -> void:
	var tab = load(PADDLE_TAB_PATH).new()
	tab.field_changed.connect(_on_capture_field)

	# Position sliders
	_test_slider_field(tab, "_forehand_slider", "paddle_forehand_mul", 0.5, totals)
	_test_slider_field(tab, "_forward_slider", "paddle_forward_mul", -1.0, totals)
	_test_slider_field(tab, "_y_offset_slider", "paddle_y_offset", 0.25, totals)

	# Rotation base sliders
	_test_slider_field(tab, "_pitch_slider", "paddle_pitch_base_deg", 45.0, totals)
	_test_slider_field(tab, "_yaw_slider", "paddle_yaw_base_deg", -30.0, totals)
	_test_slider_field(tab, "_roll_slider", "paddle_roll_base_deg", 90.0, totals)

	# Signed rotation sliders
	_test_slider_field(tab, "_pitch_signed_slider", "paddle_pitch_signed_deg", 15.0, totals)
	_test_slider_field(tab, "_yaw_signed_slider", "paddle_yaw_signed_deg", -15.0, totals)
	_test_slider_field(tab, "_roll_signed_slider", "paddle_roll_signed_deg", 180.0, totals)

	# Floor & zone sliders
	_test_slider_field(tab, "_floor_clear_slider", "paddle_floor_clearance", 0.3, totals)
	_test_slider_field(tab, "_zone_xmin", "zone_x_min", -0.5, totals)
	_test_slider_field(tab, "_zone_xmax", "zone_x_max", 1.5, totals)
	_test_slider_field(tab, "_zone_ymin", "zone_y_min", 0.2, totals)
	_test_slider_field(tab, "_zone_ymax", "zone_y_max", 2.0, totals)

	# Dropdowns (sign source options)
	_test_dropdown_field(tab, "_pitch_sign_opt", "paddle_pitch_sign_source", 1, totals)
	_test_dropdown_field(tab, "_yaw_sign_opt", "paddle_yaw_sign_source", 2, totals)
	_test_dropdown_field(tab, "_roll_sign_opt", "paddle_roll_sign_source", 1, totals)

	# Checkbox
	_test_checkbox_field(tab, "_has_zone_check", "has_zone", true, totals)

	tab.free()


## ── Legs Tab ────────────────────────────────────────────────────────────────

func _test_legs_tab_fields(totals: Dictionary) -> void:
	var tab = load(LEGS_TAB_PATH).new()
	tab.field_changed.connect(_on_capture_field)

	# Stance sliders
	_test_slider_field(tab, "_stance_slider", "stance_width", 0.7, totals)
	_test_slider_field(tab, "_front_foot_slider", "front_foot_forward", 0.2, totals)
	_test_slider_field(tab, "_back_foot_slider", "back_foot_back", -0.15, totals)

	# Foot yaw sliders
	_test_slider_field(tab, "_right_yaw_slider", "right_foot_yaw_deg", 30.0, totals)
	_test_slider_field(tab, "_left_yaw_slider", "left_foot_yaw_deg", -45.0, totals)

	# Crouch & weight
	_test_slider_field(tab, "_crouch_slider", "crouch_amount", 0.5, totals)
	_test_slider_field(tab, "_weight_shift_slider", "weight_shift", 0.3, totals)

	# Vector3 editors (knee poles, foot offsets)
	_test_vector3_field(tab, "_right_knee_editor", "right_knee_pole", Vector3(0.1, 0.2, -0.3), totals)
	_test_vector3_field(tab, "_left_knee_editor", "left_knee_pole", Vector3(-0.1, 0.25, 0.15), totals)
	_test_vector3_field(tab, "_right_foot_off", "right_foot_offset", Vector3(0.05, 0.0, -0.1), totals)
	_test_vector3_field(tab, "_left_foot_off", "left_foot_offset", Vector3(-0.05, 0.0, 0.1), totals)

	# Dropdown (lead foot)
	_test_dropdown_field(tab, "_lead_foot_opt", "lead_foot", 1, totals)  # Left

	tab.free()


## ── Arms Tab ────────────────────────────────────────────────────────────────

func _test_arms_tab_fields(totals: Dictionary) -> void:
	var tab = load(ARMS_TAB_PATH).new()
	tab.field_changed.connect(_on_capture_field)

	# Shoulder rotations
	_test_vector3_field(tab, "_right_shoulder_editor", "right_shoulder_rotation_deg", Vector3(10, 20, -5), totals)
	_test_vector3_field(tab, "_left_shoulder_editor", "left_shoulder_rotation_deg", Vector3(-10, -20, 5), totals)

	# Hand offsets
	_test_vector3_field(tab, "_right_hand_editor", "right_hand_offset", Vector3(0.1, -0.05, 0.15), totals)
	_test_vector3_field(tab, "_left_hand_editor", "left_hand_offset", Vector3(-0.1, -0.05, 0.15), totals)

	# Elbow poles
	_test_vector3_field(tab, "_right_elbow_editor", "right_elbow_pole", Vector3(0.2, -0.1, -0.2), totals)
	_test_vector3_field(tab, "_left_elbow_editor", "left_elbow_pole", Vector3(-0.2, -0.1, -0.2), totals)

	# Dropdown (hand mode)
	_test_dropdown_field(tab, "_hand_mode_dropdown", "left_hand_mode", 2, totals)  # 2-Hand

	tab.free()


## ── Head Tab ────────────────────────────────────────────────────────────────────

func _test_head_tab_fields(totals: Dictionary) -> void:
	var tab = load(HEAD_TAB_PATH).new()
	tab.field_changed.connect(_on_capture_field)

	_test_slider_field(tab, "_yaw_slider", "head_yaw_deg", 15.0, totals)
	_test_slider_field(tab, "_pitch_slider", "head_pitch_deg", -10.0, totals)
	_test_slider_field(tab, "_track_weight_slider", "head_track_ball_weight", 0.75, totals)

	tab.free()


## ── Torso Tab ─────────────────────────────────────────────────────────────────

func _test_torso_tab_fields(totals: Dictionary) -> void:
	var tab = load(TORSO_TAB_PATH).new()
	tab.field_changed.connect(_on_capture_field)

	_test_slider_field(tab, "_hip_yaw_slider", "hip_yaw_deg", 20.0, totals)
	_test_slider_field(tab, "_torso_yaw_slider", "torso_yaw_deg", -15.0, totals)
	_test_slider_field(tab, "_torso_pitch_slider", "torso_pitch_deg", 10.0, totals)
	_test_slider_field(tab, "_torso_roll_slider", "torso_roll_deg", -5.0, totals)
	_test_slider_field(tab, "_spine_curve_slider", "spine_curve_deg", 8.0, totals)
	_test_slider_field(tab, "_body_yaw_slider", "body_yaw_deg", 30.0, totals)
	_test_slider_field(tab, "_body_pitch_slider", "body_pitch_deg", -10.0, totals)
	_test_slider_field(tab, "_body_roll_slider", "body_roll_deg", 5.0, totals)

	tab.free()


## ── Charge Tab ────────────────────────────────────────────────────────────────

func _test_charge_tab_fields(totals: Dictionary) -> void:
	var tab = load(CHARGE_TAB_PATH).new()
	tab.field_changed.connect(_on_capture_field)

	_test_slider_field(tab, "_body_rot", "charge_body_rotation_deg", 45.0, totals)
	_test_slider_field(tab, "_hip_coil", "charge_hip_coil_deg", 25.0, totals)
	_test_slider_field(tab, "_back_foot_load", "charge_back_foot_load", 0.85, totals)

	_test_vector3_field(tab, "_paddle_off", "charge_paddle_offset", Vector3(0.1, -0.2, 0.3), totals)
	_test_vector3_field(tab, "_paddle_rot", "charge_paddle_rotation_deg", Vector3(15, -30, 45), totals)

	tab.free()


## ── Follow-Through Tab ────────────────────────────────────────────────────────

func _test_follow_through_tab_fields(totals: Dictionary) -> void:
	var tab = load(FOLLOW_THROUGH_TAB_PATH).new()
	tab.field_changed.connect(_on_capture_field)

	_test_slider_field(tab, "_hip_uncoil", "ft_hip_uncoil_deg", -20.0, totals)
	_test_slider_field(tab, "_front_foot_load", "ft_front_foot_load", 0.9, totals)
	_test_slider_field(tab, "_dur_strike", "ft_duration_strike", 0.15, totals)
	_test_slider_field(tab, "_dur_sweep", "ft_duration_sweep", 0.25, totals)
	_test_slider_field(tab, "_dur_settle", "ft_duration_settle", 0.2, totals)
	_test_slider_field(tab, "_dur_hold", "ft_duration_hold", 0.18, totals)

	_test_vector3_field(tab, "_paddle_off", "ft_paddle_offset", Vector3(-0.1, 0.15, -0.2), totals)
	_test_vector3_field(tab, "_paddle_rot", "ft_paddle_rotation_deg", Vector3(-10, 20, -30), totals)

	_test_dropdown_field(tab, "_ease_opt", "ft_ease_curve", 1, totals)  # QuadOut

	tab.free()


## ── Signal Connection Integrity ──────────────────────────────────────────────

func _test_signal_connections_integrity(totals: Dictionary) -> void:
	# Verify that field_changed signal fires for every control type
	_captured_fields.clear()

	var paddle_tab = load(PADDLE_TAB_PATH).new()
	paddle_tab.field_changed.connect(_on_capture_field)

	# Simulate a slider change
	paddle_tab._forehand_slider.set_value(1.0)
	var found := _captured_fields.filter(func(f): return f[0] == "paddle_forehand_mul" and is_equal_approx(f[1], 1.0))
	_assert(found.size() == 1, "paddle_tab slider emits field_changed with correct field_name and value", totals)

	# Simulate a dropdown change
	paddle_tab._pitch_sign_opt.select(2)
	found = _captured_fields.filter(func(f): return f[0] == "paddle_pitch_sign_source" and f[1] == 2)
	_assert(found.size() == 1, "paddle_tab dropdown emits field_changed with correct field_name and value", totals)

	# Simulate checkbox change
	paddle_tab._has_zone_check.set_pressed(true)
	found = _captured_fields.filter(func(f): return f[0] == "has_zone" and f[1] == true)
	_assert(found.size() == 1, "paddle_tab checkbox emits field_changed with correct field_name and value", totals)

	paddle_tab.free()


## ── Helper Methods ──────────────────────────────────────────────────────────

func _on_capture_field(field_name: String, value: Variant) -> void:
	_captured_fields.append([field_name, value])


func _test_slider_field(tab, slider_var: String, expected_field: String, test_value: float, totals: Dictionary) -> void:
	_captured_fields.clear()
	var slider = tab.get(slider_var)
	if slider == null:
		_assert(false, "%s slider exists" % slider_var, totals)
		return
	slider.set_value(test_value)
	var found := _captured_fields.filter(func(f): return f[0] == expected_field and is_equal_approx(float(f[1]), test_value))
	_assert(found.size() == 1, "%s slider emits field_changed('%s', %.2f)" % [slider_var, expected_field, test_value], totals)


func _test_vector3_field(tab, editor_var: String, expected_field: String, test_value: Vector3, totals: Dictionary) -> void:
	_captured_fields.clear()
	var editor = tab.get(editor_var)
	if editor == null:
		_assert(false, "%s Vector3Editor exists" % editor_var, totals)
		return
	editor.set_value(test_value)
	var found := _captured_fields.filter(func(f):
		return f[0] == expected_field and f[1] is Vector3 and is_equal_approx(f[1], test_value))
	_assert(found.size() == 1, "%s Vector3Editor emits field_changed('%s', %s)" % [editor_var, expected_field, test_value], totals)


func _test_dropdown_field(tab, dropdown_var: String, expected_field: String, test_index: int, totals: Dictionary) -> void:
	_captured_fields.clear()
	var dropdown = tab.get(dropdown_var)
	if dropdown == null:
		_assert(false, "%s OptionButton exists" % dropdown_var, totals)
		return
	dropdown.select(test_index)
	var found := _captured_fields.filter(func(f): return f[0] == expected_field and f[1] == test_index)
	_assert(found.size() == 1, "%s OptionButton emits field_changed('%s', %d)" % [dropdown_var, expected_field, test_index], totals)


func _test_checkbox_field(tab, checkbox_var: String, expected_field: String, test_value: bool, totals: Dictionary) -> void:
	_captured_fields.clear()
	var checkbox = tab.get(checkbox_var)
	if checkbox == null:
		_assert(false, "%s CheckButton exists" % checkbox_var, totals)
		return
	checkbox.set_pressed(test_value)
	var found := _captured_fields.filter(func(f): return f[0] == expected_field and f[1] == test_value)
	_assert(found.size() == 1, "%s CheckButton emits field_changed('%s', %s)" % [checkbox_var, expected_field, test_value], totals)


func _assert(condition: bool, label: String, totals: Dictionary) -> void:
	if condition:
		totals.pass += 1
		print("  ✓ " + label)
	else:
		totals.fail += 1
		totals.errors.append(label)
		print("  ✗ " + label)
