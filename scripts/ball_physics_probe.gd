class_name BallPhysicsProbe extends Node

## Iterative calibration probe — same workflow as drop_test.gd.
## Press 4 to launch a practice ball, the probe captures initial state,
## samples the trajectory, detects the first bounce, and logs measured
## physics vs. real pickleball reference values.
##
## Tune these constants in ball.gd and press 4 again until measurements match:
##   DRAG_COEFFICIENT, MAGNUS_COEFFICIENT, SPIN_DAMPING_HALFLIFE,
##   SPIN_BOUNCE_TRANSFER, AERO_EFFECT_SCALE, BOUNCE_COR, BALL_RADIUS, mass

const _FLOOR_Y: float = 0.075
const _BALL_RADIUS: float = 0.0375  # USAPA 73-75.5mm diameter. Must match Ball.BALL_RADIUS in ball.gd.
const _REAL_BALL_RADIUS_MIN: float = 0.0365  # USAPA 73 mm diameter
const _REAL_BALL_RADIUS_MAX: float = 0.0378  # USAPA 75.5 mm diameter
const _REAL_MASS_MIN: float = 0.0221        # 22.1 g
const _REAL_MASS_MAX: float = 0.0265        # 26.5 g

var _ball: RigidBody3D = null
var _active: bool = false
var _t: float = 0.0
var _pos_initial: Vector3
var _vel_initial: Vector3
var _spin_initial: Vector3
var _samples: Array = []  # each entry: {t, pos, vel, spin}
var _bounced: bool = false
var _bounce_time: float = 0.0
var _bounce_pos: Vector3
var _bounce_vel_in: Vector3 = Vector3.ZERO
var _bounce_vel_out: Vector3 = Vector3.ZERO
var _bounce_spin_in: Vector3 = Vector3.ZERO
var _bounce_spin_out: Vector3 = Vector3.ZERO
var _post_bounce_frames: int = 0
var _sample_interval_frames: int = 3  # ~0.05 s at 60 Hz (tighter for fast flights)
var _bounce_signal_connected: bool = false

func begin_probe(ball: RigidBody3D) -> void:
	if ball == null:
		return
	_ball = ball
	_active = true
	_t = 0.0
	_pos_initial = ball.global_position
	_vel_initial = ball.linear_velocity
	_spin_initial = ball.angular_velocity
	_samples.clear()
	_bounced = false
	_bounce_vel_in = Vector3.ZERO
	_bounce_vel_out = Vector3.ZERO
	_bounce_spin_in = Vector3.ZERO
	_bounce_spin_out = Vector3.ZERO
	_post_bounce_frames = 0
	# Subscribe to the ball's own bounce signal — authoritative detection.
	# Disconnect any existing connection first to prevent stacking
	if _bounce_signal_connected and _ball and _ball.bounced.is_connected(_on_ball_bounced):
		_ball.bounced.disconnect(_on_ball_bounced)
	if _ball.bounced.connect(_on_ball_bounced) == OK:
		_bounce_signal_connected = true

	var speed: float = _vel_initial.length()
	var h_speed: float = Vector2(_vel_initial.x, _vel_initial.z).length()
	var spin_mag: float = _spin_initial.length()
	var eff_grav: float = 9.81 * ball.gravity_scale

	print("")
	print("══════════════════════════════════════════════════════")
	print("  BALL PHYSICS PROBE — press 4 again to re-measure")
	print("══════════════════════════════════════════════════════")
	print("  Initial pos  : (%.2f, %.2f, %.2f)" % [_pos_initial.x, _pos_initial.y, _pos_initial.z])
	print("  Initial vel  : (%.2f, %.2f, %.2f)  |v|=%.2f m/s  |v_h|=%.2f m/s" % [
		_vel_initial.x, _vel_initial.y, _vel_initial.z, speed, h_speed])
	print("  Initial spin : (%.2f, %.2f, %.2f)  |ω|=%.2f rad/s  (%s)" % [
		_spin_initial.x, _spin_initial.y, _spin_initial.z, spin_mag, _spin_type(_vel_initial, _spin_initial)])
	print("")
	print("  ─── Config snapshot ──────────────────────────────")
	print("  Mass            : %.4f kg    (USAPA: %.4f–%.4f)  %s" % [
		ball.mass, _REAL_MASS_MIN, _REAL_MASS_MAX, _pass_range(ball.mass, _REAL_MASS_MIN, _REAL_MASS_MAX)])
	print("  Radius          : %.4f m     (USAPA: %.4f–%.4f)  %s" % [
		_BALL_RADIUS, _REAL_BALL_RADIUS_MIN, _REAL_BALL_RADIUS_MAX, _pass_range(_BALL_RADIUS, _REAL_BALL_RADIUS_MIN, _REAL_BALL_RADIUS_MAX)])
	var cor_mat: float = 0.0
	if ball.physics_material_override:
		cor_mat = ball.physics_material_override.bounce
	print("  BOUNCE_COR      : velocity-dependent  (GAP-21: 0.78 @ 3 m/s → 0.56 @ 18 m/s)")
	print("                     ball.cor_for_impact_speed(v) = lerp(0.78, 0.56, clamp((v-3)/15, 0, 1))")
	print("  PhysMat bounce  : %.3f        (not used — manual bounce in ball.gd)" % cor_mat)
	print("  Gravity scale   : %.2f        → effective g = %.2f m/s² (real: 9.81)" % [
		ball.gravity_scale, eff_grav])
	print("  DRAG_COEFFICIENT: %.3f        (Lindsey 2025: outdoor=0.33, indoor=0.45)" % ball.DRAG_COEFFICIENT)
	print("  MAGNUS_COEFF    : %.5f      (real tennis ball ~1.2e-4)" % ball.MAGNUS_COEFFICIENT)
	print("  SPIN_DAMP halfl : %.2f s" % ball.SPIN_DAMPING_HALFLIFE)
	print("  SPIN_BOUNCE_XFR : %.3f" % ball.SPIN_BOUNCE_TRANSFER)
	print("  AERO_EFFECT_SCL : %.2f        (0=off, 1=full real)" % ball.AERO_EFFECT_SCALE)
	print("")
	print("  ─── Godot built-in damping (should be 0 to let aero code own it)")
	print("  linear_damp : %.3f  %s" % [ball.linear_damp, "⚠ non-zero stacks extra drag" if ball.linear_damp > 0.001 else "✓"])
	print("  angular_damp: %.3f  %s" % [ball.angular_damp, "⚠ non-zero stacks extra spin decay" if ball.angular_damp > 0.001 else "✓"])
	print("")
	print("  ─── Real-pickleball expected values (HORIZONTAL) ─")
	if h_speed > 0.1:
		# Theoretical horizontal decel at launch. Note: drag's horizontal
		# component scales with v_h * v_total, not v_h² — real lobs arc have
		# much more horizontal drag than a naïve v_h² formula predicts.
		var ref_decel: float = _ref_drag_decel(h_speed, speed, ball.mass, _REAL_BALL_RADIUS_MAX)
		var game_decel: float = _game_drag_decel(h_speed, speed, ball.mass, _BALL_RADIUS, ball.DRAG_COEFFICIENT, ball.AERO_EFFECT_SCALE)
		print("  Real-ball horizontal decel @ launch: %.2f m/s²  (v_h=%.1f, v_tot=%.1f)" % [ref_decel, h_speed, speed])
		print("  Game-ball horizontal decel @ launch: %.2f m/s²  (cross-section %.2f× real)" % [
			game_decel, pow(_BALL_RADIUS / _REAL_BALL_RADIUS_MAX, 2)])
	print("  Expected COR at impact: will compute when bounce hits")
	print("  Expected topspin curl (Magnus): subtle downward bias during flight")
	print("")
	print("  ─── Live trajectory samples ──────────────────────")

func _physics_process(delta: float) -> void:
	tick(delta)

func tick(delta: float) -> void:
	if not _active or _ball == null:
		return
	_t += delta

	var pos: Vector3 = _ball.global_position
	var vel: Vector3 = _ball.linear_velocity
	var spin: Vector3 = _ball.angular_velocity
	var h: float = pos.y - _FLOOR_Y - _BALL_RADIUS
	var speed: float = vel.length()
	var frame_num: int = int(round(_t * 60.0))

	# Sample tightly (every 3 frames = ~0.05 s) BEFORE bounce so v_in can be
	# captured accurately when _on_ball_bounced fires.
	var should_sample: bool = false
	if _samples.is_empty():
		should_sample = true
	else:
		var last_frame: int = _samples[_samples.size() - 1]["f"]
		if frame_num - last_frame >= _sample_interval_frames:
			should_sample = true

	if should_sample and not _bounced:
		_samples.append({"f": frame_num, "t": _t, "pos": pos, "vel": vel, "spin": spin})
		# Only print every other sample to keep the log readable.
		if _samples.size() % 2 == 1:
			print("  [t=%.2f] h=%.2f |v|=%.2f (%.2f,%.2f,%.2f)  |ω|=%.1f" % [
				_t, h, speed, vel.x, vel.y, vel.z, spin.length()])

	if _bounced:
		_post_bounce_frames += 1
		# Capture v_out on the first post-bounce frame.
		if _post_bounce_frames == 1:
			_bounce_vel_out = vel
			_bounce_spin_out = spin
			print("    v_out (post): (%.2f,%.2f,%.2f)  |v|=%.2f" % [
				_bounce_vel_out.x, _bounce_vel_out.y, _bounce_vel_out.z, _bounce_vel_out.length()])
			print("    ω_in  : %.2f rad/s   ω_out: %.2f rad/s   Δ=%.2f" % [
				_bounce_spin_in.length(), _bounce_spin_out.length(), _bounce_spin_out.length() - _bounce_spin_in.length()])
		if _post_bounce_frames > 2:
			_finalize()

## Authoritative bounce detection — fires at the exact physics frame of the
## first floor contact, guaranteed not to miss fast bounces.
func _on_ball_bounced(_bounce_world_pos: Vector3) -> void:
	if not _active or _bounced:
		return
	_bounced = true
	_bounce_time = _t
	_bounce_pos = _ball.global_position
	# v_in / ω_in = ball state on the same frame, which is POST-bounce already
	# (the signal fires AFTER linear_velocity.y flip). Use the last sample as
	# the pre-bounce reference.
	if not _samples.is_empty():
		_bounce_vel_in = _samples[_samples.size() - 1]["vel"]
		_bounce_spin_in = _samples[_samples.size() - 1]["spin"]
	else:
		_bounce_vel_in = _vel_initial
		_bounce_spin_in = _spin_initial
	print("")
	print("  ▼ FIRST BOUNCE at t=%.3f s" % _t)
	print("    pos=(%.2f, %.2f, %.2f)" % [_bounce_pos.x, _bounce_pos.y, _bounce_pos.z])
	print("    v_in  (pre) : (%.2f,%.2f,%.2f)  |v|=%.2f" % [
		_bounce_vel_in.x, _bounce_vel_in.y, _bounce_vel_in.z, _bounce_vel_in.length()])

func _finalize() -> void:
	_active = false
	if _bounce_signal_connected and _ball and _ball.bounced.is_connected(_on_ball_bounced):
		_ball.bounced.disconnect(_on_ball_bounced)
		_bounce_signal_connected = false

	# Horizontal deceleration — measured ONLY on pre-bounce samples (pure flight).
	if _samples.size() >= 2:
		var first: Dictionary = _samples[0]
		var last: Dictionary = _samples[_samples.size() - 1]
		var dt: float = last["t"] - first["t"]
		var v0: Vector3 = first["vel"]
		var v1: Vector3 = last["vel"]
		var v0_h: float = Vector2(v0.x, v0.z).length()
		var v1_h: float = Vector2(v1.x, v1.z).length()
		if dt > 0.02:
			var measured_decel: float = (v0_h - v1_h) / dt
			var v_h_avg: float = (v0_h + v1_h) * 0.5
			# Compute the average TOTAL speed across all pre-bounce samples.
			# Drag's horizontal component scales with v_h × v_total, so the
			# reference must be computed at average v_total not just v_h.
			var v_total_sum: float = 0.0
			for s in _samples:
				var sv: Vector3 = s["vel"]
				v_total_sum += sv.length()
			var v_total_avg: float = v_total_sum / float(_samples.size())
			var ref_decel: float = _ref_drag_decel(v_h_avg, v_total_avg, _ball.mass, _REAL_BALL_RADIUS_MAX)
			var game_expected: float = _game_drag_decel(v_h_avg, v_total_avg, _ball.mass, _BALL_RADIUS, _ball.DRAG_COEFFICIENT, _ball.AERO_EFFECT_SCALE)
			print("")
			print("  ═══ Measurements (pre-bounce flight only) ═══════")
			print("  Flight duration    : %.3f s (to first bounce)" % _bounce_time)
			print("  Samples in flight  : %d" % _samples.size())
			print("  Horizontal v       : %.2f → %.2f m/s (avg %.2f)" % [v0_h, v1_h, v_h_avg])
			print("  Total v (avg)      : %.2f m/s" % v_total_avg)
			print("  Horizontal decel   : %.3f m/s²  ← MEASURED" % measured_decel)
			print("  Game expected decel: %.3f m/s²  (from ball.gd aero code @ AERO_SCALE=%.2f)" % [game_expected, _ball.AERO_EFFECT_SCALE])
			print("  Real-ball ref decel: %.3f m/s²  (USAPA-spec ball at same avg speed)" % ref_decel)
			# Drift between measured and game expected = contribution from OTHER sources
			# (linear_damp, gravity coupling to horizontal, numeric noise).
			var other_sources: float = measured_decel - game_expected
			print("  Other sources      : %+.3f m/s² (linear_damp + coupling + noise)" % other_sources)
			# Suggestion: tune AERO_EFFECT_SCALE so measured matches real ref.
			var delta_decel: float = ref_decel - measured_decel
			print("  Measured vs real   : %+.3f m/s² (+ = too fast, - = too draggy)" % delta_decel)
			if abs(delta_decel) < 0.3:
				print("                       → MATCHES real reference ✓")
			else:
				# Solve: new_game_expected + other_sources ≈ ref_decel
				# new_game_expected = ref_decel - other_sources
				# new_scale = (ref_decel - other_sources) / (game_expected / current_scale)
				var unscaled_game_drag: float = game_expected / maxf(_ball.AERO_EFFECT_SCALE, 0.0001)
				var target_game_drag: float = ref_decel - other_sources
				var suggested_scale: float = clampf(target_game_drag / unscaled_game_drag, 0.0, 2.0)
				print("                       → Try AERO_EFFECT_SCALE ≈ %.2f to match real ref" % suggested_scale)

	# Bounce COR analysis
	if _bounce_vel_in.y < -0.05:
		var cor_vertical: float = abs(_bounce_vel_out.y) / abs(_bounce_vel_in.y)
		var impact_speed: float = abs(_bounce_vel_in.y)
		var ref_cor: float = _ref_cor_for_speed(impact_speed)
		print("")
		print("  Bounce COR (vert)  : %.3f  (impact speed %.2f m/s)" % [cor_vertical, impact_speed])
		print("  Bounce COR ref     : %.3f  (Cross 1999 curve, pickleball-calibrated)" % ref_cor)
		var delta_cor: float = cor_vertical - ref_cor
		print("  Delta              : %+.3f" % delta_cor)
		if abs(delta_cor) < 0.03:
			print("                       → MATCHES velocity-dependent ref ✓")
		elif delta_cor > 0:
			print("                       → TOO BOUNCY: game COR > ref at this speed")
		else:
			print("                       → TOO DEAD: game COR < ref at this speed")

		# Tangential bounce analysis (spin transfer)
		var tang_in: Vector2 = Vector2(_bounce_vel_in.x, _bounce_vel_in.z)
		var tang_out: Vector2 = Vector2(_bounce_vel_out.x, _bounce_vel_out.z)
		var tang_delta: float = tang_out.length() - tang_in.length()
		print("  Tangential |v_in|  : %.2f m/s" % tang_in.length())
		print("  Tangential |v_out| : %.2f m/s" % tang_out.length())
		print("  Tangential delta   : %+.2f m/s (topspin adds, backspin subtracts)" % tang_delta)

	# Spin decay check — ONLY over the pre-bounce flight (bounces also decay spin).
	if _spin_initial.length() > 0.1 and not _samples.is_empty():
		var last_sample: Dictionary = _samples[_samples.size() - 1]
		var last_spin: Vector3 = last_sample["spin"]
		var spin_decay_ratio: float = last_spin.length() / _spin_initial.length()
		var t_decay: float = last_sample["t"]
		var ref_decay: float = exp(-t_decay * 0.693 / (_ball.SPIN_DAMPING_HALFLIFE * _ball.AERO_EFFECT_SCALE))
		print("")
		print("  Pre-bounce spin decay over %.2f s: measured %.3f, ref %.3f" % [t_decay, spin_decay_ratio, ref_decay])
		var spin_delta: float = spin_decay_ratio - ref_decay
		if abs(spin_delta) < 0.05:
			print("                       → MATCHES ✓")
		elif spin_delta > 0:
			print("                       → spin lasts too long. Lower SPIN_DAMPING_HALFLIFE.")
		else:
			print("                       → spin decays too fast. Raise SPIN_DAMPING_HALFLIFE.")

	print("")
	print("  ─── To iterate ───────────────────────────────────")
	print("  Edit constants in scripts/ball.gd at the top block.")
	print("  Press 4 to launch again. Goal: all deltas ≈ 0.")
	print("══════════════════════════════════════════════════════")
	print("")

## Real-pickleball drag deceleration reference (HORIZONTAL COMPONENT).
## Drag force is antiparallel to TOTAL velocity; its horizontal component is
##   F_h = |F_drag| * (v_h / v_total) = 0.5 * rho * Cd * A * v_total * v_h
## This is the correct formula for high-arc shots where v_total >> v_h.
func _ref_drag_decel(v_h: float, v_total: float, mass: float, real_radius: float) -> float:
	var cd: float = 0.33  # outdoor pickleball — Lindsey 2025 TWU
	var cross: float = PI * real_radius * real_radius
	var drag_force: float = 0.5 * 1.225 * cd * cross * v_total * v_h
	return drag_force / mass

## Game-ball drag deceleration expected from the current ball.gd constants
## (HORIZONTAL COMPONENT). Uses oversized game radius + AERO_EFFECT_SCALE.
func _game_drag_decel(v_h: float, v_total: float, mass: float, game_radius: float, cd: float, aero_scale: float) -> float:
	var cross: float = PI * game_radius * game_radius
	var drag_force: float = 0.5 * 1.225 * cd * cross * v_total * v_h
	return (drag_force / mass) * aero_scale

## Real-pickleball COR vs impact speed.
## USAPA equipment testing: COR ≈ 0.78 at 3 m/s, drops to 0.56 at 18 m/s.
## This is steeper than tennis balls due to pickleball's hollow perforated construction.
## Matches Ball.cor_for_impact_speed() in ball.gd.
func _ref_cor_for_speed(v_impact: float) -> float:
	return lerp(0.78, 0.56, clamp((v_impact - 3.0) / 15.0, 0.0, 1.0))

func _pass_range(v: float, lo: float, hi: float) -> String:
	if v >= lo and v <= hi:
		return "✓"
	elif v < lo:
		return "✗ too low"
	else:
		return "✗ too high"

## Decompose spin into roll (topspin/backspin) and yaw (sidespin curl) components.
## Returns e.g. "TOPSPIN (18.0 rad/s)" or "MIXED top=12.4 side=8.2R" or "SIDESPIN L (15.0)".
func _spin_type(vel: Vector3, spin: Vector3) -> String:
	if spin.length() < 0.5:
		return "none"
	var h_vel: Vector3 = Vector3(vel.x, 0, vel.z)
	if h_vel.length() < 0.5:
		return "unaligned"
	var h_dir: Vector3 = h_vel.normalized()
	# roll_axis points perpendicular to motion in the horizontal plane. A spin
	# along +roll_axis means topspin; along -roll_axis means backspin.
	var roll_axis: Vector3 = Vector3.UP.cross(h_dir)
	# Project spin onto roll_axis (signed) and onto UP (signed sidespin).
	var roll_component: float = spin.dot(roll_axis)
	var side_component: float = spin.dot(Vector3.UP)
	var roll_abs: float = absf(roll_component)
	var side_abs: float = absf(side_component)
	var roll_label: String = "top" if roll_component > 0 else "back"
	var side_label: String = "R" if side_component > 0 else "L"
	# Classify: "pure" if one component dominates (5:1+), else mixed.
	if roll_abs > 0.5 and side_abs < roll_abs * 0.20:
		return "%sSPIN (%.1f)" % [roll_label.to_upper(), roll_abs]
	elif side_abs > 0.5 and roll_abs < side_abs * 0.20:
		return "SIDESPIN %s (%.1f)" % [side_label, side_abs]
	else:
		return "MIXED %s=%.1f + side=%.1f%s" % [roll_label, roll_abs, side_abs, side_label]
