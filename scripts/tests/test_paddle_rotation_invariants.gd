extends SceneTree
## Focused paddle/grip regression. No UI rendering or real private saves are used.
## godot --headless --path . --script res://scripts/tests/test_paddle_rotation_invariants.gd -- --mobile-runtime
const Store = preload("res://scripts/mobile_pose_store.gd")
const Keyframe = preload("res://scripts/stroke_body_keyframe.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Grip = preload("res://scripts/paddle_grip_frame.gd")
const Orientation = preload("res://scripts/stroke_preparation_orientation.gd")
const Wrist = preload("res://scripts/paddle_wrist_reach.gd")
const Size = preload("res://scripts/paddle_dimensions.gd")
const Styles = preload("res://scripts/paddle_grip_styles.gd")
const POS = ["paddle_forehand_mul", "paddle_y_offset", "paddle_forward_mul"]
const ROT = ["paddle_pitch_base_deg", "paddle_yaw_base_deg", "paddle_roll_base_deg"]
const GRIP = ["main_grip_rotation_deg", "paddle_in_hand_rotation_deg", "support_grip_rotation_deg", "support_grip_slide_m"]
var checks := 0
var failures: Array[String] = []
var test_path := ""

class FramePlayer extends Node3D:
	const COURT_FLOOR_Y := 0.0
	func _get_forehand_axis() -> Vector3: return Vector3.RIGHT
	func _get_forward_axis() -> Vector3: return Vector3.FORWARD

class PreviewHarness extends RefCounted:
	var player: Node3D
	func _init(value: Node3D) -> void: player = value

class EditHarness extends "res://scripts/ui/mobile_pose_editor.gd":
	var preview_refreshes := 0
	var status_refreshes := 0
	func _ready() -> void: pass
	func _stop() -> void: pass
	func _sync_rotation_controls() -> void: pass
	func _refresh_preview() -> void: preview_refreshes += 1
	func _refresh_status(_message: String = "") -> void: status_refreshes += 1
	func initialize(pose: PostureDefinition, stage: int) -> void:
		_group = OptionButton.new()
		add_child(_group)
		for i in range(7): _group.add_item(str(i))
		_group.select(4)
		_scrub = HSlider.new()
		add_child(_scrub)
		_current = pose
		_stage = stage
		_key = "stroke:" + str(pose.posture_id)
		_edit = pose if stage == 1 else Path.endpoint(pose, stage)

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func fixture(kind: String = "partial") -> PostureDefinition:
	var pose := PostureDefinition.new()
	pose.posture_id = 0
	pose.paddle_forehand_mul = 0.6
	pose.paddle_y_offset = 0.2
	pose.paddle_forward_mul = 0.4
	pose.paddle_pitch_base_deg = 11.0
	pose.paddle_yaw_base_deg = -13.0
	pose.paddle_roll_base_deg = 17.0
	pose.charge_paddle_offset = Vector3(-0.1, 0.3, -0.2)
	pose.ft_paddle_offset = Vector3(0.2, -0.1, 0.3)
	pose.charge_paddle_rotation_deg = Vector3(20, -30, 40)
	pose.ft_paddle_rotation_deg = Vector3(-50, 60, -70)
	pose.main_grip_rotation_deg = 23.0
	pose.support_grip_rotation_deg = -37.0
	pose.support_grip_slide_m = 0.012
	pose.right_hand_offset = Vector3(0.01, 0.02, 0.03)
	pose.left_hand_offset = Vector3(-0.01, 0.03, 0.02)
	if kind != "null":
		pose.windup_body = Keyframe.new()
		pose.follow_through_body = Keyframe.new()
		pose.windup_body.values = {"torso_yaw_deg": 31.0}
		pose.follow_through_body.values = {"torso_yaw_deg": -29.0}
		if kind == "authored":
			pose.windup_body.values["main_grip_rotation_deg"] = 71.0
			pose.follow_through_body.values["main_grip_rotation_deg"] = -89.0
	return pose

func same(a, b) -> bool:
	if a is Vector3: return a.is_equal_approx(b)
	if a is float or a is int: return is_equal_approx(float(a), float(b))
	return a == b

func snapshot(pose: PostureDefinition) -> Array:
	var result: Array = []
	for stage in range(3):
		var endpoint: PostureDefinition = Path.endpoint(pose, stage)
		var fields: Dictionary = {}
		for field in POS + ROT + Keyframe.FIELDS:
			fields[field] = endpoint.get(field)
		result.append(fields)
	return result

func assert_unchanged(before: Array, after: Array, edited_stage: int, edited_field: String, label: String) -> void:
	for stage in range(3):
		for field in before[stage]:
			if stage == edited_stage and field == edited_field: continue
			check(same(before[stage][field], after[stage][field]), "%s preserves stage %d %s" % [label, stage, field])

func test_stage_isolation() -> void:
	for field in POS + ROT + GRIP + ["right_hand_offset", "left_hand_offset", "paddle_pitch_signed_deg", "paddle_pitch_sign_source"]:
		for kind in ["null", "partial", "authored"]:
			var pose := fixture(kind)
			var before := snapshot(pose)
			var key_fields: Array = []
			for property in ["windup_body", "follow_through_body"]:
				var key: Resource = pose.get(property)
				key_fields.append([] if key == null else key.values.keys())
			var edit := EditHarness.new()
			edit.initialize(pose, 1)
			var value = pose.get(field)
			if value is Vector3: value += Vector3(0.005, 0.015, -0.005)
			elif field == "paddle_pitch_sign_source": value = 1
			elif field == "support_grip_slide_m": value += 0.006
			else: value += 28.0
			edit._changed(field, value)
			var after := snapshot(pose)
			check(same(after[1][field], value), "Contact changes selected %s (%s keys)" % [field, kind])
			assert_unchanged(before, after, 1, field, "Contact %s (%s keys)" % [field, kind])
			check(edit._dirty.has(edit._key), "Contact edit marks working pose dirty")
			for index in range(2):
				var expected_keys: Array = key_fields[index].duplicate()
				if field in Keyframe.FIELDS and not field in expected_keys: expected_keys.append(field)
				var key: Resource = pose.get("windup_body" if index == 0 else "follow_through_body")
				var actual_keys: Array = [] if key == null else key.values.keys()
				actual_keys.sort(); expected_keys.sort()
				check(actual_keys == expected_keys, "Contact freezes only edited field; no unrelated materialized defaults")
			edit.free()
	for stage in [0, 2]:
		for field in POS + ROT + GRIP + ["right_hand_offset", "left_hand_offset"]:
			var pose := fixture()
			var before := snapshot(pose)
			var edit := EditHarness.new()
			edit.initialize(pose, stage)
			var value = edit._edit.get(field)
			if value is Vector3: value += Vector3(0.005, 0.015, -0.005)
			elif field == "support_grip_slide_m": value += 0.006
			else: value += 10.0 if field in ROT + GRIP else 0.07
			edit._changed(field, value)
			var after := snapshot(pose)
			check(same(after[stage][field], value), "stage %d changes selected %s" % [stage, field])
			assert_unchanged(before, after, stage, field, "stage %d %s" % [stage, field])
			edit.free()

func test_batched_change() -> void:
	var pose := fixture()
	var before := snapshot(pose)
	var edit := EditHarness.new()
	edit.initialize(pose, 1)
	var updated := POS + ROT
	for field in updated:
		edit._changed(field, float(pose.get(field)) + 0.125, false)
	check(edit.preview_refreshes == 0 and edit.status_refreshes == 0, "batch defers expensive visual refresh")
	check(edit._dirty.has(edit._key) and edit._motion_dirty, "batch still invalidates private working pose and motion")
	var after := snapshot(pose)
	for stage in range(3):
		for field in before[stage]:
			var expected = before[stage][field]
			if stage == 1 and field in updated: expected += 0.125
			check(same(after[stage][field], expected), "batch isolates stage %d %s" % [stage, field])
	edit._changed("paddle_pitch_base_deg", pose.paddle_pitch_base_deg + 1.0)
	check(edit.preview_refreshes == 1 and edit.status_refreshes == 1, "default single-field edit refreshes once")
	edit.free()

func test_grip_frames() -> void:
	var pose := fixture()
	var authored: Basis = Orientation.canonical_basis(pose)
	for left in [false, true]:
		for degrees in [-1080.0, -405.0, -45.0, 0.0, 45.0, 405.0, 1080.0]:
			var frame: Basis = Grip.basis(authored, left, degrees)
			check(frame.is_finite() and is_equal_approx(frame.determinant(), 1.0), "grip frame is a finite proper rotation")
			check(frame.y.is_equal_approx(authored.y), "grip twist preserves paddle shaft axis")
			check(frame.is_equal_approx(Grip.basis(authored, left, degrees + 360.0)), "grip supports multi-turn equivalent input")
			var next: Basis = Grip.basis(authored, left, degrees + 45.0)
			check(next.is_equal_approx(frame * Basis(Vector3.UP, deg_to_rad(45.0))), "grip increment rotates about local handle Y")
			check(authored.is_equal_approx(Orientation.canonical_basis(pose)), "changing grip frame never mutates paddle")
	check(Grip.basis(authored, true).is_equal_approx(Grip.basis(authored, false, 180.0)), "left hand has explicit 180-degree handedness offset")

func test_gimbal_seated_wrist() -> void:
	var player := FramePlayer.new()
	root.add_child(player)
	player.position = Vector3(0.3, 0.0, -0.2)
	for dominance in [0, 1]:
		for stage in range(3):
			for spin in [-95.0, 45.0, 125.0]:
				for axis in range(3):
					var pose := fixture()
					pose.paddle_hand = dominance
					pose.paddle_in_hand_rotation_deg = spin
					pose.charge_paddle_offset = Vector3.ZERO
					pose.ft_paddle_offset = Vector3.ZERO
					var shoulder: Vector3 = Path.BodyPose.shoulder_world(player, pose) - player.global_position
					pose.paddle_forehand_mul = shoulder.x + 0.08
					pose.paddle_y_offset = shoulder.y - 0.15
					pose.paddle_forward_mul = -shoulder.z + 0.2
					var edit := EditHarness.new()
					edit.initialize(pose, stage)
					edit._preview = PreviewHarness.new(player)
					var original: Vector3 = Wrist.wrist_world(Path.world_transform(player, edit._edit), edit._edit)
					var before := snapshot(pose)
					edit._set_paddle_angle(axis, float(edit._edit.get(ROT[axis])) + 7.0)
					var after: Vector3 = Wrist.wrist_world(Path.world_transform(player, edit._edit), edit._edit)
					check(after.distance_to(original) < 0.000002, "gimbal preserves actual seated wrist with spin %.1f, dominance %d, stage %d, axis %d" % [spin, dominance, stage, axis])
					var endpoints := snapshot(pose)
					for other in range(3):
						if other == stage: continue
						for field in POS + ROT + GRIP:
							check(same(before[other][field], endpoints[other][field]), "gimbal batch preserves other stages after nonzero in-hand spin")
					edit.free()
	player.free()

func test_in_hand_rotation() -> void:
	for dominance in [0, 1]:
		var pose := fixture()
		pose.paddle_hand = dominance
		var old: Transform3D = Path.canonical_transform(pose)
		var old_wrist: Vector3 = Wrist.wrist_world(old, pose)
		var old_main: Basis = Grip.basis(old.basis, dominance == 1, pose.main_grip_rotation_deg)
		var old_support: Basis = Grip.basis(old.basis, dominance == 0, pose.support_grip_rotation_deg)
		for degrees in [-180.0, -90.0, -45.0, 45.0, 90.0, 179.0]:
			pose.paddle_in_hand_rotation_deg = degrees
			var spun: Transform3D = Path.canonical_transform(pose)
			check(Wrist.wrist_world(spun, pose).distance_to(old_wrist) < 0.000001, "in-hand rotation keeps seated wrist for each dominance")
			check(Grip.basis(spun.basis, dominance == 1, pose.main_grip_rotation_deg - degrees).is_equal_approx(old_main), "in-hand spin leaves dominant hand orientation fixed")
			check(Grip.basis(spun.basis, dominance == 0, pose.support_grip_rotation_deg - degrees).is_equal_approx(old_support), "in-hand spin leaves support hand orientation fixed")
			check(Path.remove_in_hand_transform(spun, pose).is_equal_approx(old), "in-hand transform is exactly reversible")
		for preset in range(Styles.PRESET_ANGLES.size()):
			var before := snapshot(pose)
			Styles.apply_preset(pose, preset)
			check(Styles.preset_index(pose) == preset, "preset detection agrees with mirrored role angle")
			check(is_equal_approx(Styles.relative_rotation(pose), Styles.PRESET_ANGLES[preset]), "preset relative angle is independent of dominant handedness")
			for field in POS + ROT + ["main_grip_rotation_deg", "support_grip_rotation_deg"]:
				check(same(pose.get(field), before[1][field]), "grip preset changes no authored world orientation/body field")

func test_persistence() -> void:
	var pose := fixture()
	for field in ROT + ["paddle_pitch_signed_deg", "paddle_yaw_signed_deg", "paddle_roll_signed_deg", "main_grip_rotation_deg", "paddle_in_hand_rotation_deg", "support_grip_rotation_deg"]:
		pose.set(field, 405.25)
	pose.charge_paddle_rotation_deg = Vector3(-540.5, 405.25, 630.75)
	pose.ft_paddle_rotation_deg = Vector3(540.5, -405.25, -630.75)
	pose.windup_body.values["main_grip_rotation_deg"] = -585.25
	pose.follow_through_body.values["support_grip_rotation_deg"] = 675.75
	var before: Dictionary = Store._encode_fields(pose)
	check(not before.is_empty(), "finite multi-turn paddle and grip values pass schema")
	check(before.has("paddle_in_hand_rotation_deg"), "new in-hand field participates in whole-pose snapshots")
	var encoded := Store.export_pose_json(pose)
	check(not encoded.is_empty(), "finite multi-turn values export")
	if not encoded.is_empty():
		var decoded: Dictionary = JSON.parse_string(encoded)
		check(decoded.fields.paddle_pitch_base_deg == 45.25, "export normalizes equivalent full paddle turns")
		check(decoded.fields.windup_body.main_grip_rotation_deg == 134.75, "export normalizes equivalent nested grip turns")
	check(Store.save(pose) == OK, "multi-turn pose saves")
	if FileAccess.file_exists(test_path):
		var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(test_path))
		check(Store._valid_document(document), "multi-turn save passes reload validator")
		var reloaded := fixture()
		Store._apply_fields(reloaded, document.postures["0"])
		check(Store._encode_fields(reloaded) == before, "multi-turn fields round-trip exactly")
		var good_bytes := FileAccess.get_file_as_string(test_path)
		for invalid in [NAN, INF, -INF]:
			var invalid_pose: PostureDefinition = pose.duplicate(true)
			invalid_pose.main_grip_rotation_deg = invalid
			check(Store.save(invalid_pose) == ERR_INVALID_DATA, "non-finite scalar remains rejected")
			check(Store.export_pose_json(invalid_pose).is_empty(), "non-finite scalar cannot be exported")
			invalid_pose = pose.duplicate(true)
			invalid_pose.windup_body.values["support_grip_rotation_deg"] = invalid
			check(Store.save(invalid_pose) == ERR_INVALID_DATA, "non-finite nested scalar remains rejected")
		check(FileAccess.get_file_as_string(test_path) == good_bytes, "invalid edits preserve good file")
	check(not Store._valid_number("paddle_pitch_base_deg", 1440.0), "raw save envelopes remain defensive; unbounded input normalizes at editor boundary")
	check(not Store._valid_number("paddle_hand", 2), "handedness enum remains bounded")
	check(not Store._valid_number("support_index_closure", 1.1), "finger blend remains physically bounded")

func test_legacy_snapshot() -> void:
	var encoded: Dictionary = Store._encode_fields(fixture())
	check(not encoded.is_empty(), "complete fixture fits current schema")
	var legacy: Dictionary = encoded.duplicate(true)
	legacy.erase("paddle_in_hand_rotation_deg")
	check(Store._valid_fields(legacy, false), "legacy whole-pose snapshot without new spin remains valid")
	var decoded := PostureDefinition.new()
	Store._apply_fields(decoded, legacy)
	check(decoded.paddle_in_hand_rotation_deg == 0.0, "legacy snapshot preserves original zero-spin behavior")
	legacy.erase("paddle_pitch_base_deg")
	check(not Store._valid_fields(legacy, false), "legacy exception does not permit arbitrary partial snapshots")

func run() -> void:
	test_path = "user://pose_store_tests/rotation_invariants_%d_%d/poses.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(Store.set_test_path(test_path) == OK, "save fixture is isolated")
	test_stage_isolation()
	test_batched_change()
	test_grip_frames()
	test_in_hand_rotation()
	test_gimbal_seated_wrist()
	test_persistence()
	test_legacy_snapshot()
	if FileAccess.file_exists(test_path): DirAccess.remove_absolute(test_path)
	print("[PADDLE ROTATION INVARIANTS] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
