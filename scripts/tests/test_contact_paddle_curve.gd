extends SceneTree
## Isolated scalar-curve regression: geometry, migration, live/preview and serve contact.
const ContactCurve = preload("res://scripts/contact_paddle_curve.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Store = preload("res://scripts/mobile_pose_store.gd")
const ServeStore = preload("res://scripts/mobile_serve_pose_store.gd")
const Preview = preload("res://scripts/posture_editor_v2/runtime_motion_preview.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Styles = preload("res://scripts/serve_style.gd")
var checks := 0
var failures: Array[String] = []
var pose_file: String
var serve_file: String
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func near(a: Vector3, b: Vector3, label: String, tolerance: float = 0.000001) -> void:
	check(a.distance_to(b) <= tolerance, label)
func pos(pose: PostureDefinition) -> Vector3: return ContactCurve.position(pose)
func run() -> void:
	var id := str(OS.get_process_id()); var child := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--curve-id="): id = arg.trim_prefix("--curve-id="); child = true
	pose_file = "user://pose_store_tests/contact_curve_%s/poses.json" % id
	serve_file = "user://pose_store_tests/contact_curve_%s/serves.json" % id
	check(Store.set_test_path(pose_file) == OK and ServeStore.set_test_path(serve_file) == OK, "isolated private paths")
	if child:
		var library := PostureLibrary.new()
		check(library.get_def(0).contact_curve == 1.0, "stroke survives independent process")
		for style in range(7): check(ServeStore.get_def(style).contact_curve == float(style % 2), "serve survives independent process")
		finish(); return
	DirAccess.remove_absolute(pose_file); DirAccess.remove_absolute(serve_file)
	var normal := ContactCurve.bend(Vector3(-0.5, 0, 0), Vector3(0, 0.3, 0), Vector3(0.5, 0, 0))
	near(ContactCurve.bend(Vector3(-1, 0, 0), Vector3.ZERO, Vector3(1, 0, 0)), Vector3.ZERO, "straight path has no arbitrary sideways bend")
	for amount in [0.0, 0.5, 1.0]:
		for t in [0.0, 0.5, 1.0]:
			near(ContactCurve.offset(normal, t, amount), Vector3.ZERO, "exact key correction zero")
			var h := 0.0001
			near((ContactCurve.offset(normal, t + h, amount) - ContactCurve.offset(normal, t - h, amount)) / (2.0 * h), Vector3.ZERO, "correction preserves contact and endpoint tangent", 0.0001)
		for i in range(101): check(ContactCurve.offset(normal, float(i) / 100.0, amount).length() <= normal.length() * 0.10547, "correction envelope is bounded")
	var synthetic := PostureDefinition.new()
	synthetic.paddle_forehand_mul = 0; synthetic.paddle_y_offset = 0.3; synthetic.paddle_forward_mul = 0
	synthetic.charge_paddle_offset = Vector3(-0.5, -0.3, 0); synthetic.ft_paddle_offset = Vector3(0.5, -0.3, 0)
	var curvatures: Array[float] = []
	for amount in [0.0, 0.5, 1.0]:
		synthetic.contact_curve = amount
		var h := 0.001
		curvatures.append((pos(Path.sample(synthetic, 0.5-h)) - 2.0*pos(Path.sample(synthetic, 0.5)) + pos(Path.sample(synthetic, 0.5+h))).length() / (h*h))
	check(curvatures[0] < curvatures[1] * 0.1 and curvatures[2] > curvatures[1] * 1.8, "slider monotonically straightens/rounds Contact curvature")
	var library := PostureLibrary.new()
	for id_value in range(21):
		var original: PostureDefinition = library.get_def(id_value)
		var def: PostureDefinition = original.duplicate(true)
		check(def.contact_curve == (0.0 if id_value == 2 else 0.5), "packaged curve matches approved Backhand or unchanged neutral default")
		for amount in [0.0, 1.0]:
			def.contact_curve = amount
			for t in [0.0, 0.5, 1.0]: near(pos(Path.sample(def, t)), pos(Path.sample(original, t)), "all stroke keys preserved")
			for t in [0.25, 0.4999, 0.5, 0.5001, 0.75]:
				var sample := Path.sample(def, t)
				check(pos(sample).is_finite(), "stroke finite at extrema")
				var reference := Path.sample(original, t)
				check(sample.paddle_pitch_base_deg == reference.paddle_pitch_base_deg and sample.body_yaw_deg == reference.body_yaw_deg, "curve does not change orientation/body")
				for charge in [0.0, 0.4, 1.0]: near(pos(Preview.sample(def, t, Preview.Technique.DRIVE, charge, 0)), pos(Motion.sample_drive(def, t, charge)), "stroke runtime preview parity")
		check(Store.save(def) == OK, "stroke curve persists")
		var exported = JSON.parse_string(Store.export_pose_json(def))
		check(exported.fields.contact_curve == 1.0, "stroke JSON includes curve")
		var legacy: Dictionary = Store._encode_fields(original)
		legacy.erase("contact_curve")
		check(Store._valid_fields(legacy, false), "legacy stroke schema accepted")
		Store._apply_fields(def, legacy)
		check(def.contact_curve == 0.5, "legacy stroke migrates to neutral")
		legacy.erase("paddle_in_hand_rotation_deg")
		check(Store._valid_fields(legacy, false), "pre-spin/pre-curve schema accepted together")
		for invalid in [-0.01, 1.01, NAN, INF]:
			def.contact_curve = invalid
			check(Store.save(def) == ERR_INVALID_DATA, "invalid curve rejected")
	for style in range(7):
		var original: PostureDefinition = ServeStore.get_default(style)
		for amount in [0.0, 0.5, 1.0]:
			var edit: PostureDefinition = original.duplicate(true); edit.contact_curve = amount
			check(ServeStore.save(edit) == OK, "serve curve accepted without editing locked contact")
			check(ServeStore.copy_values(edit, ServeStore.get_def(style)) == OK, "serve curve publishes live")
			for height in [0.9, 1.0, 1.1]:
				for charge in [0.0, 0.4, 1.0]:
					for t in [0.0, 0.5, 1.0]:
						var current: PostureDefinition = Preview.sample_serve(style, t, charge, height, edit, false)
						# A curve adjustment preserves the same packaged authored keys.
						# Flat now has an approved whole-pose default beyond the old generator.
						var raw: PostureDefinition = Preview.sample_serve(style, t, charge, height, original if style == 0 else null, false)
						near(pos(current), pos(raw), "serve windup/contact/finish fixed at every height/charge")
						for field in ServeStore.PADDLE_FIELDS: check(current.get(field) == raw.get(field), "serve exact Contact face and all key rotations unchanged")
					for t in [0.25, 0.49, 0.4999, 0.5001, 0.65, 0.75]:
						var live: PostureDefinition = Preview.sample_serve(style, t, charge, height)
						var custom: PostureDefinition = Preview.sample_serve(style, t, charge, height, edit, false)
						near(pos(live), pos(custom), "serve live/custom curve parity")
						check(pos(live).is_finite(), "serve finite at slider extrema")
			var preview_sample := ServeStore.sample(edit, 0.65)
			near(pos(preview_sample), pos(Preview.sample_serve(style, 0.65, 1.0)), "editor ServeStore uses exact live path")
			if amount != 0.5:
				var neutral: PostureDefinition = original.duplicate(true); neutral.contact_curve = .5
				check(pos(preview_sample).distance_to(pos(Preview.sample_serve(style, 0.65, 1.0, 1.0, neutral, false))) > 0.001, "each serve visibly responds to Contact curve")
		# Verify the actual generated serve, rather than only the synthetic curve:
		# more bend increases geometric curvature on both sides of Contact.
		for side in [-1.0, 1.0]:
			var default_curve := serve_curvature(original, side)
			var rounder: PostureDefinition = original.duplicate(true); rounder.contact_curve = 1.0
			check(serve_curvature(rounder, side) > default_curve, "rounder setting increases generated serve Contact curvature")
		var saved: PostureDefinition = original.duplicate(true); saved.contact_curve = float(style % 2)
		check(ServeStore.save(saved) == OK, "save distinct per-serve setting")
		check(JSON.parse_string(ServeStore.export_pose_json(saved)).fields.contact_curve == saved.contact_curve, "serve JSON includes curve")
		var legacy: Dictionary = Store._encode_fields(original); legacy.erase("contact_curve")
		check(ServeStore._valid_document({"version": 1, "serves": {str(style): legacy}}), "legacy serve snapshots accepted")
	var output: Array = []
	var result := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/tests/test_contact_paddle_curve.gd", "--", "--mobile-runtime", "--curve-id=" + id], output, true)
	check(result == 0, "independent process persistence: " + "".join(output))
	DirAccess.remove_absolute(pose_file); DirAccess.remove_absolute(serve_file)
	finish()
func serve_curvature(def: PostureDefinition, side: float) -> float:
	var step: float = 0.001 * side
	var p0: Vector3 = pos(ServeStore.sample(def, 0.5))
	var p1: Vector3 = pos(ServeStore.sample(def, 0.5 + step))
	var p2: Vector3 = pos(ServeStore.sample(def, 0.5 + 2.0 * step))
	var velocity: Vector3 = (p1 - p0) / step
	var acceleration: Vector3 = (p2 - 2.0 * p1 + p0) / (step * step)
	return velocity.cross(acceleration).length() / maxf(pow(velocity.length(), 3.0), 0.000001)
func finish() -> void:
	print("CONTACT PADDLE CURVE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
