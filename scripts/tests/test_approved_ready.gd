extends SceneTree
## Exact approved static Ready resource and finite isolated rig; migration is
## covered separately by the shared approved-import persistence regression.
const Store = preload("res://scripts/mobile_pose_store.gd")
const GripStore = preload("res://scripts/mobile_paddle_grip_store.gd")
const ServeStore = preload("res://scripts/mobile_serve_pose_store.gd")
const Approved = preload("res://scripts/approved_ready_import.gd")
const Preview = preload("res://scripts/ui/mobile_pose_preview.gd")
const Editor = preload("res://scripts/ui/mobile_pose_editor.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
var checks := 0
var failures: Array[String] = []
var payload: Dictionary = JSON.parse_string(Approved.JSON_TEXT)

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func frames(count: int = 3) -> void:
	for index in range(count): await process_frame

func run() -> void:
	create_timer(90, true).timeout.connect(func(): quit(2))
	var directory := "user://pose_store_tests/approved_ready_%d/" % OS.get_process_id()
	check(Store.set_test_path(directory + "poses.json") == OK, "isolated pose save path")
	check(GripStore.set_test_path(directory + "grips.json") == OK, "isolated global grip path")
	check(ServeStore.set_test_path(directory + "serves.json") == OK, "isolated serve path")
	check(Approved.JSON_TEXT.sha256_text() == Approved.SOURCE_SHA256, "embedded approved JSON preserves provenance bytes")
	var provenance_path:="res://docs/pose-imports/ready-2026-10-02.json"
	if FileAccess.file_exists(provenance_path):
		check(FileAccess.get_file_as_string(provenance_path) == Approved.JSON_TEXT, "embedded payload equals retained source")
	else:
		# The APK exports the fixed, hashed data module; human-readable JSON stays
		# in the source archive. Missing provenance is never accepted in source QA.
		check(get_script().resource_path.ends_with(".gdc"), "compiled APK uses independently hashed embedded provenance")
	check(payload.baseline_sha256 == Approved.BASELINE_SHA256, "payload retains independently verified old exporter baseline")
	check(payload.schema == "pickleball.pose" and payload.version == 1 and payload.id == 20 and payload.kind == "stroke" and payload.scope == "whole_pose", "fixed whole static Ready identity")
	check(payload.selected_stage == 1 and payload.selected_stage_name == "Contact", "historical Contact label is retained as context")
	check(Store._valid_fields(payload.fields, false), "all supplied old-schema fields validate")
	check(payload.fields.size() == 79 and payload.fields.windup_body.size() == 41 and payload.fields.follow_through_body.size() == 41, "complete approved field counts")
	var authored: PostureDefinition = Store._export_packaged_default(20, false)
	_check_supplied(Store._encode_fields(authored), "packaged Ready")
	check(authored.posture_id == 20 and authored.display_name == "Ready" and authored.family == payload.family, "packaged identity is unchanged")
	check(authored.paddle_in_hand_rotation_deg == 0.0 and authored.contact_curve == 0.5, "omitted new channels retain defaults")
	var live: PostureDefinition = PostureLibrary.new().get_def(20)
	_check_supplied(Store._encode_fields(live), "fresh Ready")
	check(not FileAccess.file_exists(Store.storage_path()), "fresh Ready creates no private pose save")
	var exported: Dictionary = JSON.parse_string(Store.export_pose_json(live, 1))
	_check_supplied(exported.fields, "copy Ready", true)
	check(not FileAccess.file_exists(Store.storage_path()), "copy remains read-only")
	var editor = Editor.new()
	editor._current = live
	check(not editor._has_motion(), "Ready editor disables motion phases")
	editor.free()
	_test_static_sampling(live)
	var displayed: PostureDefinition = Path.sample(live, 0.5)
	for field in ["body_pitch_deg", "head_pitch_deg", "main_grip_rotation_deg", "support_grip_rotation_deg", "paddle_forehand_mul", "paddle_forward_mul", "paddle_pitch_base_deg", "paddle_yaw_base_deg", "paddle_roll_base_deg"]:
		check(is_equal_approx(float(displayed.get(field)), float(live.get(field))), "static midpoint uses top-level " + field)
	check(displayed.right_hand_offset == live.right_hand_offset, "static midpoint uses top-level hand offset")
	check(displayed.body_pitch_deg == 18.0 and displayed.head_pitch_deg == -21.0, "static Ready does not substitute zero-pitch historical keyframes")
	check(displayed.main_grip_rotation_deg == -131.0 and displayed.support_grip_rotation_deg == -115.0, "static Ready keeps approved main and support grips")
	var preview = Preview.new()
	preview.size = Vector2(640, 480)
	root.add_child(preview)
	await frames()
	preview.show_pose(displayed)
	preview.select_joint("paddle")
	preview.set_motion(live, true)
	check(not preview._motion_enabled and preview.selected_joint_samples.is_empty(), "Ready has no generated stroke arc")
	check(preview.motion_root == null or not preview.motion_root.visible, "Ready hides phase ghosts")
	for court in range(2):
		preview.player.player_num = court
		preview.player.leg_ik.feet_initialized = false
		var paddle_frame := Transform3D.IDENTITY
		for progress in [0.0, 0.25, 0.5, 0.75, 1.0, 0.7, 0.1, 0.9, 0.0]:
			preview.show_pose(Path.sample(live, progress))
			await frames(2)
			_check_rig(preview, "static court%d t%.2f" % [court, progress])
			if paddle_frame == Transform3D.IDENTITY: paddle_frame = preview.player.paddle_node.global_transform
			check(preview.player.paddle_node.global_transform.is_equal_approx(paddle_frame), "static sampling keeps actual paddle frame at every progress")
		for id in Preview.JOINT_NAMES:
			preview.select_joint(id)
			check(preview.selected_joint_samples.is_empty() and not preview.selected_joint_has_motion, "Ready selected joint stays static " + id)
	# Existing gameplay overlays remain intentional: movement/body stances blend
	# only their body channels over Ready while its paddle/grips remain authored.
	var controller = preview.player.pose_controller
	controller.base_pose_state = 0
	controller.invalidate_cache()
	var base: Resource = controller.get_base_pose_def()
	var runtime: PostureDefinition = controller.compose_runtime_posture(live)
	check(is_equal_approx(runtime.body_pitch_deg, lerpf(live.body_pitch_deg, base.body_pitch_deg, base.stroke_overlay_mix)), "runtime preserves existing Body stance pitch blend")
	check(is_equal_approx(runtime.stance_width, lerpf(live.stance_width, base.stance_width, base.stroke_overlay_mix)), "runtime preserves existing Body stance width blend")
	check(not is_equal_approx(runtime.body_pitch_deg, live.body_pitch_deg), "default gameplay Body stance visibly differs from exact editor pitch")
	for field in ["main_grip_rotation_deg", "support_grip_rotation_deg", "paddle_pitch_base_deg", "paddle_yaw_base_deg", "paddle_roll_base_deg"]:
		check(is_equal_approx(float(runtime.get(field)), float(live.get(field))), "runtime body composition retains Ready " + field)
	print("READY BODY BLEND: static pitch=", live.body_pitch_deg, ", runtime pitch=", runtime.body_pitch_deg, ", base weight=", base.stroke_overlay_mix)
	preview.show_pose(runtime)
	_check_rig(preview, "runtime Body blend")
	_check_supplied(Store._encode_fields(live), "live Ready after previews")
	check(not FileAccess.file_exists(Store.storage_path()) and not FileAccess.file_exists(GripStore.storage_path()), "preview does not write private pose or global grip")
	preview.queue_free()
	await frames()
	print("APPROVED READY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_static_sampling(live: PostureDefinition) -> void:
	var before := Store._encode_fields(live)
	var progression: Array[float] = [-1.0, 2.0]
	for index in range(33): progression.append(index / 32.0)
	for index in range(32, -1, -1): progression.append(index / 32.0)
	var random := RandomNumberGenerator.new()
	random.seed = 20261002
	for index in range(48): progression.append(random.randf())
	for progress in progression:
		var sampled: PostureDefinition = Path.sample(live, progress)
		check(Store._encode_fields(sampled) == before, "all Ready fields remain exact at progress %.8f" % progress)
		check(sampled != live and sampled.windup_body != live.windup_body and sampled.follow_through_body != live.follow_through_body, "static sampling returns detached pose and preserved body dictionaries")
	check(Store._encode_fields(live) == before, "forward, reverse and random sampling never alter source Ready")
	var sampled: PostureDefinition = Path.sample(live, 0.23)
	sampled.windup_body.values.main_grip_rotation_deg = 12.0
	check(live.windup_body.values.main_grip_rotation_deg == payload.fields.windup_body.main_grip_rotation_deg, "sampled historical body dictionary cannot mutate approved source")
	var stroke: PostureDefinition = Store._export_packaged_default(10, false)
	check(Store._encode_fields(Path.sample(stroke, 0.0)) != Store._encode_fields(Path.sample(stroke, 0.5)), "ordinary strokes still sample their actual motion")

func _check_supplied(actual: Dictionary, label: String, serialized: bool = false) -> void:
	for field in payload.fields:
		if field in ["windup_body", "follow_through_body"]:
			var expected: Dictionary = payload.fields[field]
			for key in expected:
				check(actual[field].get(key) == _expected_value(key, expected[key], serialized), "%s: exact %s.%s" % [label, field, key])
			var keys: Array = actual[field].keys(); keys.erase("paddle_in_hand_rotation_deg"); keys.sort()
			var expected_keys: Array = expected.keys(); expected_keys.sort()
			check(keys == expected_keys, label + ": replaces sparse legacy dictionary " + field)
		else:
			check(actual[field] == _expected_value(field, payload.fields[field], serialized), label + ": exact supplied field " + field)

func _expected_value(field: String, value, serialized: bool):
	# Vector3 stores float32, whereas JSON parses decimal doubles. Compare the
	# precise stored vector value without tolerances; exported decimals must also
	# match the approved JSON. This avoids a JSON-parser double-ULP false failure.
	return value if serialized or not value is Array else Store._encode_value(Store._decode_value(field, value))

func _check_rig(preview, label: String) -> void:
	for node in preview.player.find_children("*", "Node3D", true, false):
		check(node.global_transform.is_finite(), label + ": finite rig " + str(node.name))
	for id in Preview.JOINT_NAMES:
		check(preview.joint_world_position(id).is_finite(), label + ": finite displayed " + id)
	for arm in [preview.player.right_arm_node, preview.player.left_arm_node]:
		var shoulder: Vector3 = arm.upper_pivot.global_position
		var elbow: Vector3 = arm.forearm_pivot.global_position
		var wrist: Vector3 = arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket
		check(absf(shoulder.distance_to(elbow) - 0.35) < 0.00002, label + ": fixed upper-arm length")
		check(absf(elbow.distance_to(wrist) - 0.35) < 0.00002, label + ": fixed forearm length")
