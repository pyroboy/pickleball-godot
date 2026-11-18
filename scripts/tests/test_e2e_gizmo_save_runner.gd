extends SceneTree

const SAVE_PATH := "user://test_posture_gizmo_e2e_temp.tres"
const EXPECTED_FOREHAND := 0.123
const EXPECTED_FORWARD  := 0.456
const EXPECTED_Y_OFFSET := -0.789


func _init() -> void:
	var errors: Array[String] = []

	# posture_definition.gd declares `class_name PostureDefinition` at global scope.
	# We reference it directly — no local variable needed.
	var def := PostureDefinition.new()
	def.paddle_forehand_mul = EXPECTED_FOREHAND
	def.paddle_forward_mul  = EXPECTED_FORWARD
	def.paddle_y_offset     = EXPECTED_Y_OFFSET
	def.display_name = "E2E_Test"

	var save_err: int = ResourceSaver.save(def, SAVE_PATH, ResourceSaver.FLAG_CHANGE_PATH)
	if save_err != OK:
		_print_result(false, 0.0, 0.0, 0.0, "ResourceSaver.save returned %d" % save_err)
		quit(1)
		return

	var loaded: Resource = load(SAVE_PATH)
	if loaded == null:
		_print_result(false, 0.0, 0.0, 0.0, "load() returned null")
		quit(1)
		return

	var loaded_def = loaded as PostureDefinition
	if loaded_def == null:
		_print_result(false, 0.0, 0.0, 0.0, "loaded resource is not PostureDefinition")
		quit(1)
		return

	var ok := true
	if not is_equal_approx(loaded_def.paddle_forehand_mul, EXPECTED_FOREHAND):
		errors.append("fh_mismatch")
		ok = false
	if not is_equal_approx(loaded_def.paddle_forward_mul, EXPECTED_FORWARD):
		errors.append("fw_mismatch")
		ok = false
	if not is_equal_approx(loaded_def.paddle_y_offset, EXPECTED_Y_OFFSET):
		errors.append("y_mismatch")
		ok = false

	var dir := DirAccess.open("user://")
	if dir:
		dir.remove(SAVE_PATH)

	var err_str := ""
	if errors.size() > 0:
		err_str = errors[0]
		for i in range(1, errors.size()):
			err_str = err_str + "|" + errors[i]

	if ok:
		_print_result(true, EXPECTED_FOREHAND, EXPECTED_FORWARD, EXPECTED_Y_OFFSET, err_str)
		quit(0)
	else:
		_print_result(false, loaded_def.paddle_forehand_mul, loaded_def.paddle_forward_mul, loaded_def.paddle_y_offset, err_str)
		quit(1)


func _print_result(ok: bool, fh: float, fw: float, yo: float, err: String) -> void:
	print("RESULT ok:=%s forehand:=%s forward:=%s y_offset:=%s error:=%s" % [
		"True" if ok else "False",
		str(fh),
		str(fw),
		str(yo),
		err
	])
