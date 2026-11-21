extends RefCounted

const Motion = preload("res://scripts/drive_serve_motion.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Styles = preload("res://scripts/serve_style.gd")
const ReadyGuard = preload("res://scripts/ready_guard_profile.gd")
enum Technique{AUTHORED, DRIVE, DINK, VOLLEY, DROP, SERVE, KITCHEN_READY, SERVE_HIGH_SOFT, SERVE_DROP_DRIVE, SERVE_BANANA, SERVE_SCREWBALL}
const NAMES = ["Authored keyframes", "Runtime drive / smash", "Runtime kitchen dink", "Runtime volley", "Runtime Drop", "Serve: Flat / Topspin / Slice", "Runtime kitchen ready", "Serve: High Soft", "Serve: Drop Drive", "Serve: Banana", "Serve: Screwball"]
static var _serve_plans: Dictionary = {}

static func sample(base: PostureDefinition, t: float, technique: int, charge: float, spin: int, server_height: float = 1.0) -> PostureDefinition:
	if technique == Technique.AUTHORED: return Path.sample(base, t)
	if technique == Technique.KITCHEN_READY: return Motion.kitchen_ready(base if base.posture_id == 20 else ReadyGuard.authored_guard(base.paddle_hand))
	if is_serve(technique): return sample_serve(serve_style(technique, spin), t, charge, server_height)
	return Motion.sample_drive(base, t, charge, technique == Technique.VOLLEY, spin, technique == Technique.DINK, "DROP" if technique == Technique.DROP else "AUTO")

static func is_serve(technique: int) -> bool:
	return technique == Technique.SERVE or technique in [Technique.SERVE_HIGH_SOFT, Technique.SERVE_DROP_DRIVE, Technique.SERVE_BANANA, Technique.SERVE_SCREWBALL]

static func serve_style(technique: int, spin: int) -> int:
	match technique:
		Technique.SERVE_HIGH_SOFT: return Styles.Style.HIGH_SOFT
		Technique.SERVE_DROP_DRIVE: return Styles.Style.DROP_DRIVE
		Technique.SERVE_BANANA: return Styles.Style.BANANA
		Technique.SERVE_SCREWBALL: return Styles.Style.SCREWBALL
		_: return clampi(spin, Styles.Style.FLAT, Styles.Style.SLICE)




static func serve_plan(style: int, server_height: float = 1.0) -> Dictionary:
	style = Styles.valid_style(style)
	var key: = "%d:%.6f" % [style, server_height]
	if not _serve_plans.has(key):
		var full: Dictionary = Styles.release_plan(Vector3(0, server_height, 0), false, style)
		var point: Vector3 = full.contact_position
		var compact: = {"contact_time": float(full.contact_time), "bounce_time": float(full.bounce_time), 
			"contact_offset": Vector3(point.x, point.y - server_height, - point.z)}
		compact.make_read_only()
		_serve_plans[key] = compact
	return _serve_plans[key]




static func sample_serve(style: int, t: float, charge: float, server_height: float = 1.0, custom: PostureDefinition = null, use_saved: bool = true) -> PostureDefinition:
	style = Styles.valid_style(style)
	var plan: Dictionary = serve_plan(style, server_height)
	var progress: float = clampf(t, 0.0, 1.0)
	var elapsed: float = float(plan.contact_time) * progress * 2.0 if progress <= 0.5 else float(plan.contact_time) + Styles.sweep_duration(style) * (progress - 0.5) * 2.0
	return sample_serve_elapsed(style, elapsed, charge, server_height, custom, use_saved)

static func serve_recovery_target() -> PostureDefinition:
	var ready: PostureDefinition = PostureLibrary.instance().get_def(20)
	ready = ready.lerp_with(ready, 0.0)
	ready.front_foot_forward = - 0.12
	ready.back_foot_back = - 0.24
	return ready

static func sample_serve_elapsed(style: int, elapsed: float, charge: float, server_height: float = 1.0, custom: PostureDefinition = null, use_saved: bool = true) -> PostureDefinition:
	style = Styles.valid_style(style)
	var plan: Dictionary = serve_plan(style, server_height)
	var local: Vector3 = plan.contact_offset
	var contact_time: float = float(plan.contact_time)
	var prep: PostureDefinition = Motion.serve_style_preparation(style, charge, Styles.hold_offset(style), custom, use_saved)
	if elapsed <= 0.0 or contact_time <= 0.0: return _serve_context(prep, style, "HELD", plan, 0.0, charge, 0.0)
	if elapsed < contact_time:
		var waiting: PostureDefinition = Motion.serve_style_wait(prep, elapsed / 0.12, style, local, custom, use_saved)
		var bounced: bool = Styles.is_drop(style) and elapsed >= float(plan.bounce_time)
		var remaining: float = contact_time - elapsed
		if ( not Styles.is_drop(style) or bounced) and remaining <= Styles.stroke_duration(style):
			return _serve_context(Motion.serve_style_strike(waiting, 1.0 - remaining / Styles.stroke_duration(style), style, local, custom, use_saved), style, "SWING", plan, elapsed / 0.12, charge, elapsed)
		return _serve_context(waiting, style, "DROP" if Styles.is_drop(style) and not bounced else "RELEASE", plan, elapsed / 0.12, charge, elapsed)
	if is_equal_approx(elapsed, contact_time): return _serve_context(Motion.serve_style_contact(style, local, custom, use_saved), style, "CONTACT", plan, 1.0, charge, elapsed)
	var after: float = elapsed - contact_time
	var sweep: float = Styles.sweep_duration(style)
	if after <= sweep:
		var factor: float = 1.0 - pow(1.0 - after / sweep, 2.0)
		return _serve_context(Motion.serve_style_follow_through(style, charge, factor, local, custom, use_saved), style, "FOLLOW_THROUGH", plan, 1.0, charge, elapsed)
	var finish: PostureDefinition = Motion.serve_style_follow_through(style, charge, 1.0, local, custom, use_saved)
	if after <= sweep + Motion.SERVE_HOLD_TIME: return _serve_context(finish, style, "HOLD", plan, 1.0, charge, elapsed)
	var recover: float = clampf((after - sweep - Motion.SERVE_HOLD_TIME) / Motion.SERVE_RECOVERY_TIME, 0.0, 1.0)
	return _serve_context(Motion.ServeJoint.recover_to_ready(finish, serve_recovery_target(), recover), style, "READY" if recover >= 1.0 else "RECOVERY", plan, 1.0, charge, elapsed)

static func _serve_context(pose: PostureDefinition, style: int, phase: String, plan: Dictionary, release_progress: float, charge: float, release_elapsed: float) -> PostureDefinition:
	pose.charge_duration = maxf(0.01, PickleballConstants.MAX_SERVE_CHARGE_TIME * clampf(charge, 0.0, 1.0))
	pose.ft_duration_strike = maxf(0.025, float(plan.contact_time))
	pose.ft_duration_sweep = Styles.sweep_duration(style)
	pose.ft_duration_hold = Motion.SERVE_HOLD_TIME
	pose.ft_duration_settle = Motion.SERVE_RECOVERY_TIME
	pose.set_meta("runtime_preview_serve", true)
	pose.set_meta("preview_serve_style", style)
	pose.set_meta("preview_serve_charge", clampf(charge, 0.0, 1.0))
	pose.set_meta("preview_serve_phase", phase)
	pose.set_meta("preview_serve_release_progress", clampf(release_progress, 0.0, 1.0))



	pose.set_meta("preview_serve_held_offset", Styles.hold_offset(style))
	pose.set_meta("preview_serve_release_elapsed", maxf(0.0, release_elapsed))
	return pose
