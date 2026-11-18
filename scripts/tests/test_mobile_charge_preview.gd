extends SceneTree
## Regression for the preview-only charge prefix. Run with --headless --script.
const Sequence = preload("res://scripts/ui/mobile_pose_sequence.gd")
const Clock = preload("res://scripts/stroke_playback_clock.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Runtime = preload("res://scripts/posture_editor_v2/runtime_motion_preview.gd")
const Styles = preload("res://scripts/serve_style.gd")
const Store = preload("res://scripts/mobile_pose_store.gd")
const ServeStore = preload("res://scripts/mobile_serve_pose_store.gd")
const Preview = preload("res://scripts/ui/mobile_pose_preview.gd")
const Contact = preload("res://scripts/ui/mobile_pose_contact_preview.gd")
var checks := 0
var failures: Array[String] = []
var configurations := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		if failures.size() <= 20: push_error(label)
func same(a: PostureDefinition, b: PostureDefinition, label: String) -> void:
	for field in ["paddle_forehand_mul", "paddle_y_offset", "paddle_forward_mul", "body_yaw_deg", "hip_yaw_deg", "torso_yaw_deg", "crouch_amount", "stance_width"]:
		var delta := float(a.get(field)) - float(b.get(field))
		if field.ends_with("_deg"): delta = wrapf(delta, -180.0, 180.0)
		check(absf(delta) < (.001 if field.ends_with("_deg") else .0001), label + " " + field + " delta=" + str(delta))
	# Blending folds signed channels into base Euler angles and can change the
	# Euler representation at gimbal lock; compare the resolved orientation.
	var ar := a.resolve_paddle_rotation_deg(-1.0, -1.0) * (PI / 180.0)
	var br := b.resolve_paddle_rotation_deg(-1.0, -1.0) * (PI / 180.0)
	var ab := Basis(Vector3.RIGHT, ar.x) * Basis(Vector3.UP, ar.y) * Basis(Vector3.FORWARD, ar.z)
	var bb := Basis(Vector3.RIGHT, br.x) * Basis(Vector3.UP, br.y) * Basis(Vector3.FORWARD, br.z)
	check(ab.x.distance_to(bb.x) < .0001 and ab.y.distance_to(bb.y) < .0001 and ab.z.distance_to(bb.z) < .0001, label + " resolved paddle orientation")
func motion_at(seq, progress: float) -> PostureDefinition:
	if seq.variant != null: return seq.variant.sample(seq.source, progress)
	if seq.style >= 0: return ServeStore.sample(seq.source, progress)
	return Motion.sample_drive(seq.source, progress, 1.0) if seq.runtime_motion else Path.sample(seq.source, progress)

func sequence_checks(definition: PostureDefinition) -> void:
	var before := var_to_bytes(Store._encode_fields(definition))
	var seq := Sequence.new()
	for runtime in [true, false]:
		for mode in [Sequence.Mode.STROKE, Sequence.Mode.TO_READY, Sequence.Mode.RECEIVE_STROKE, Sequence.Mode.SERVE_RECEIVE]:
			for variant in [0, Sequence.Variants.STRONG, Sequence.Variants.WEAK]:
				configurations += 1
				seq.configure(definition, mode, Sequence.Stance.AUTHORED, variant, runtime)
				var label := "%s mode%d variant%d runtime%s" % [definition.display_name, mode, variant, runtime]
				var charge := 1.2 if variant == Sequence.Variants.STRONG else .6
				var cue := Sequence.RECEIVE_SECONDS if mode == Sequence.Mode.RECEIVE_STROKE else 0.0
				var prefix := cue + charge
				check(is_equal_approx(seq.preparation_seconds, charge), label + " charge interval")
				check(is_equal_approx(seq.prefix_seconds, prefix), label + " full prefix")
				var release: float
				var stroke: float
				var full: float
				if seq.style >= 0:
					release = Runtime.serve_plan(seq.style).contact_time
					stroke = release + Styles.sweep_duration(seq.style)
					full = stroke + Motion.SERVE_HOLD_TIME + Motion.SERVE_RECOVERY_TIME
				else:
					var durations := Clock.durations(seq.source, seq.finish, seq.ready)
					release = durations.strike; stroke = durations.stroke; full = durations.total
				check(is_equal_approx(seq.release_seconds, release), label + " release clock unchanged")
				check(is_equal_approx(seq.stroke_seconds, stroke), label + " stroke clock unchanged")
				check(is_equal_approx(seq.full_seconds, full), label + " recovery clock unchanged")
				var expected_duration := prefix + (stroke if mode == Sequence.Mode.STROKE else full)
				if mode == Sequence.Mode.SERVE_RECEIVE: expected_duration += Sequence.RECEIVE_SECONDS
				check(is_equal_approx(seq.duration, expected_duration), label + " duration includes charge once")
				same(seq.sample(cue).pose, seq.ready, label + " charge begins Ready")
				var windup := motion_at(seq, 0.0)
				if variant == Sequence.Variants.STRONG: windup = seq.variant.sample_amount(seq.source, 0.0, 0.0)
				var halfway := Clock.Grip.sample(seq.ready, windup, .5) if Clock.Grip.supports_both_joined(seq.ready, windup) else Path.blend_pose(seq.ready, windup, .5)
				same(seq.sample(cue + .3).pose, halfway, label + " real Ready-to-windup blend")
				check(seq.sample(cue + .3).split.is_empty(), label + " charge has no receive hop")
				if variant == Sequence.Variants.STRONG:
					same(seq.sample(cue + .6).pose, windup, label + " Strong normal windup at 0.6")
					same(seq.sample(cue + .9).pose, seq.variant.sample_amount(seq.source, 0.0, .5), label + " Strong extension second interval")
				for t in [0.0, release * .37, release, stroke]:
					var expected: PostureDefinition
					if seq.style >= 0:
						var p: float = .5 * t / release if t <= release else .5 + .5 * minf((t - release) / Styles.sweep_duration(seq.style), 1.0)
						expected = Runtime.sample_serve_elapsed(seq.style, t, 1.0, 1.0, seq.source, false) if variant == 0 else motion_at(seq, p)
					else:
						expected = motion_at(seq, Clock.state(seq.source, t, seq.finish, seq.ready).progress)
					same(seq.sample(prefix + t).pose, expected, label + " shifted release parity %.4f" % t)
				if mode == Sequence.Mode.RECEIVE_STROKE:
					check(not seq.sample(.1).split.is_empty(), label + " receive cue first")
					check(seq.sample(prefix).split.is_empty(), label + " cue ends before release")
				if mode == Sequence.Mode.SERVE_RECEIVE:
					check(seq.sample(prefix + full - .001).split.is_empty(), label + " no early trailing cue")
					check(not seq.sample(prefix + full + .001).split.is_empty(), label + " trailing cue follows charge and recovery")
				if mode != Sequence.Mode.STROKE: same(seq.sample(seq.duration).pose, seq.ready, label + " ends Ready")
				var stable: PostureDefinition = seq.sample(prefix * .73).pose
				seq.sample(seq.duration); seq.sample(-1)
				same(seq.sample(prefix * .73).pose, stable, label + " reverse seek deterministic")
	check(before == var_to_bytes(Store._encode_fields(definition)), definition.display_name + " source immutable")

func visual_checks() -> void:
	var editor = load("res://scripts/ui/mobile_pose_editor.gd").new()
	for stage in range(3):
		var button := Button.new()
		editor._style_stage_button(button, stage)
		check(button.get_theme_color("font_color").is_equal_approx(Preview.STAGE_COLORS[stage]), "stage button normal color matches ghost")
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			check(button.get_theme_stylebox(state).border_color.is_equal_approx(Preview.STAGE_COLORS[stage]), "stage button border stays phase-colored " + state)
		button.free()
	editor.free()
	var preview := Preview.new(); preview.size = Vector2(640, 480); root.add_child(preview)
	await process_frame; await process_frame
	var definition: PostureDefinition = PostureLibrary.instance().get_def(0)
	var before := var_to_bytes(Store._encode_fields(definition))
	preview.show_pose(Path.sample(definition, .5)); preview.set_motion(definition)
	for stage in range(3):
		var ghost: Node3D = preview._ghosts[stage]
		var original: Transform3D = preview.ghost_transforms[stage]
		check((ghost.global_transform * Preview.PaddleSize.HEAD_OFFSET).is_equal_approx(original * Preview.PaddleSize.HEAD_OFFSET), "ghost %d keeps sampled anchor" % stage)
		for axis in range(3):
			check(is_equal_approx(ghost.global_transform.basis[axis].length(), original.basis[axis].length() * .65), "ghost %d visual scale only" % stage)
		for mesh in ghost.find_children("*", "MeshInstance3D", true, false):
			check(is_equal_approx(mesh.material_override.albedo_color.a, .12), "ghost %d subdued opacity" % stage)
		check(ghost.find_children("*", "CollisionObject3D", true, false).is_empty(), "ghost has no collision")
	var helper := Contact.new(); preview.player.get_parent().add_child(helper); helper.initialize(preview.player)
	helper.configure(definition, preview.ghost_transforms[1])
	check(is_equal_approx(helper.block.mesh.size.x, definition.zone_x_max - definition.zone_x_min), "hit zone width unchanged")
	var bottom := 0.0 if definition.height_tier == 0 else definition.zone_y_min
	check(is_equal_approx(helper.block.mesh.size.y, definition.zone_y_max - bottom), "hit zone height unchanged")
	check(before == var_to_bytes(Store._encode_fields(definition)), "visual shrinking never authors source")
	preview.queue_free(); await process_frame; await process_frame

func run() -> void:
	create_timer(180, true).timeout.connect(func(): quit(2))
	var isolate := "user://pose_store_tests/charge_preview_%d_%d/" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(Store.set_test_path(isolate + "poses.json") == OK, "isolated pose store")
	check(ServeStore.set_test_path(isolate + "serves.json") == OK, "isolated serve store")
	var original_scale := Engine.time_scale
	for definition in PostureLibrary.instance().all_definitions():
		if definition.posture_id != 20: sequence_checks(definition)
	for style in range(7): sequence_checks(ServeStore.get_def(style))
	await visual_checks()
	check(Engine.time_scale == original_scale, "no global time scale mutation")
	print(JSON.stringify({"suite": "mobile_charge_preview", "configurations": configurations, "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
