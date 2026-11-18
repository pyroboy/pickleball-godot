extends SceneTree
const Preview = preload("res://scripts/posture_editor_v2/runtime_motion_preview.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Styles = preload("res://scripts/serve_style.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Transition = preload("res://scripts/posture_editor/transition_player.gd")
var checks: = 0
var failures: Array[String] = []
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok and failures.size() < 80: failures.append(label)
func same(a: PostureDefinition, b: PostureDefinition, label: String) -> void :
	check(Vector3(a.paddle_forehand_mul, a.paddle_y_offset, a.paddle_forward_mul).distance_to(Vector3(b.paddle_forehand_mul, b.paddle_y_offset, b.paddle_forward_mul)) < 1e-05, label + " paddle position")
	var aa: Vector3 = a.resolve_paddle_rotation_deg(-1, -1) * (PI / 180.0)
	var bb: Vector3 = b.resolve_paddle_rotation_deg(-1, -1) * (PI / 180.0)
	var ba: = Basis(Vector3.RIGHT, aa.x) * Basis(Vector3.UP, aa.y) * Basis(Vector3.FORWARD, aa.z)
	var bc: = Basis(Vector3.RIGHT, bb.x) * Basis(Vector3.UP, bb.y) * Basis(Vector3.FORWARD, bb.z)
	check(ba.is_equal_approx(bc), label + " physical orientation")
	check(Path.support_hand_offset(a).distance_to(Path.support_hand_offset(b)) < 1e-05, label + " support hand")
	for field in ["body_yaw_deg", "hip_yaw_deg", "torso_yaw_deg", "crouch_amount", "weight_shift", "front_foot_forward", "back_foot_back"]:
		check(is_equal_approx(a.get(field), b.get(field)), label + " " + field)
func run() -> void :
	var ready: PostureDefinition = PostureLibrary.instance().get_def(20)
	var old_front: float = ready.front_foot_forward; var old_back: float = ready.back_foot_back
	for style in range(7):
		for height in [1.0, 1.1]:
			var source: Dictionary = Styles.release_plan(Vector3(0, height, 0), false, style)
			var plan: Dictionary = Preview.serve_plan(style, height)
			check(is_equal_approx(plan.contact_time, source.contact_time), "shared release plan contact time")
			check(plan.is_read_only(), "cached preview plan is immutable")
			var point: Vector3 = source.contact_position
			var local: = Vector3(point.x, point.y - height, - point.z)
			check(local.distance_to(plan.contact_offset) < 1e-05, "shared release plan contact offset")
			for charge in [0.0, 0.25, 1.0]:
				var prep: PostureDefinition = Motion.serve_style_preparation(style, charge, Styles.hold_offset(style))
				var held: PostureDefinition = Preview.sample_serve(style, 0, charge, height)
				same(held, prep, "exact style-held preparation")
				check((held.get_meta("preview_serve_held_offset") as Vector3).distance_to(Styles.hold_offset(style)) < 1e-05, "preview held centre uses shared stance coordinates")
				check(is_zero_approx(float(held.get_meta("preview_serve_release_elapsed"))), "preview held hand has zero release clock")
				same(Preview.sample_serve(style, 0.5, charge, height), Motion.serve_style_contact(style, local), "exact style contact")
				same(Preview.sample_serve(style, 1, charge, height), Motion.serve_style_follow_through(style, charge, 1, local), "exact style finish")
				for step in range(1, 20):
					var elapsed: float = float(plan.contact_time) * step / 20.0
					var remaining: float = float(plan.contact_time) - elapsed
					var waiting: PostureDefinition = Motion.serve_style_wait(prep, elapsed / 0.12, style, local)
					var can_swing: bool = not Styles.is_drop(style) or elapsed >= float(plan.bounce_time)
					var expected: PostureDefinition = Motion.serve_style_strike(waiting, 1 - remaining / Styles.stroke_duration(style), style, local) if can_swing and remaining <= Styles.stroke_duration(style) else waiting
					var actual: PostureDefinition = Preview.sample_serve_elapsed(style, elapsed, charge, height)
					same(actual, expected, "delivery/bounce/strike parity")
					check(is_equal_approx(float(actual.get_meta("preview_serve_release_elapsed")), elapsed), "preview hand clock uses release seconds")
					if not can_swing: check(actual.get_meta("preview_serve_phase") == "DROP", "drop never swings before bounce")
				var sweep: float = Styles.sweep_duration(style)
				for progress in [0.25, 0.5, 0.75, 1.0]:
					var elapsed: float = float(plan.contact_time) + sweep * progress
					same(Preview.sample_serve_elapsed(style, elapsed, charge, height), Motion.serve_style_follow_through(style, charge, 1 - pow(1 - progress, 2), local), "live quadratic sweep parity")
				var finish: PostureDefinition = Motion.serve_style_follow_through(style, charge, 1, local)
				same(Preview.sample_serve_elapsed(style, float(plan.contact_time) + sweep + Motion.SERVE_HOLD_TIME * 0.5, charge, height), finish, "live hold parity")
				for progress in [0.0, 0.25, 0.5, 0.75, 1.0]:
					var elapsed: float = float(plan.contact_time) + sweep + Motion.SERVE_HOLD_TIME + Motion.SERVE_RECOVERY_TIME * progress
					same(Preview.sample_serve_elapsed(style, elapsed, charge, height), Motion.ServeJoint.recover_to_ready(finish, Preview.serve_recovery_target(), progress), "live behind-baseline recovery parity")
				var contact: PostureDefinition = Preview.sample_serve(style, 0.5, charge, height)
				var tp: = Transition.new()
				tp.setup(null, ready, prep, contact, [finish]);tp.linear_path_time = true
				check(is_equal_approx(tp.phase_durations[Transition.Phase.CONTACT], float(plan.contact_time)), "preview delivery phase duration")
				check(is_equal_approx(tp.phase_durations[Transition.Phase.FOLLOW_THROUGH], sweep), "preview sweep duration")
				check(is_equal_approx(tp.path_progress(0, 0.42), 0.21) and is_equal_approx(tp.path_progress(1, 0.42), 0.71), "no duplicate serve easing")
				tp.setup(null, ready, prep, contact, [finish])
				check( not tp.linear_path_time and not tp.charge_sampler.is_valid() and not tp.settle_sampler.is_valid(), "non-serve setup clears preview callbacks")
				tp.free()
	check(is_equal_approx(ready.front_foot_forward, old_front) and is_equal_approx(ready.back_foot_back, old_back), "preview does not modify saved Ready stance")
	var techniques: Array[int] = [Preview.Technique.SERVE, Preview.Technique.SERVE, Preview.Technique.SERVE, Preview.Technique.SERVE_HIGH_SOFT, Preview.Technique.SERVE_DROP_DRIVE, Preview.Technique.SERVE_BANANA, Preview.Technique.SERVE_SCREWBALL]
	for style in range(7):
		var technique: int = techniques[style]
		check(Preview.is_serve(technique) and Preview.serve_style(technique, style if style < 3 else 0) == style, "all seven serve styles exposed")
		check(technique < Preview.NAMES.size(), "serve style has editor label")
	print("SERVE PREVIEW TIMELINE: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
