class_name GameDropTest
extends Node

## Kinematic Drop Test — isolates ball.gd's BOUNCE_COR in isolation.
## Purpose: measure ball bounce against USAPA spec (30-34 in from 78 in drop)
## without air drag, arcade gravity, or Godot collision solver interference.

signal test_complete

# External reference
var _ball_ref: RigidBody3D = null

# Visual sphere for drop test
var _drop_test_visual: MeshInstance3D = null

# Kinematic state
var _drop_test_pos: Vector3 = Vector3.ZERO
var _drop_test_vel: Vector3 = Vector3.ZERO
var _drop_cor_used: float = 0.0
var _drop_has_impacted: bool = false
var _drop_awaiting_peak: bool = false

# Shared test state (from game.gd — now owned by this node)
var _test_active: bool = false
var _test_peak_y: float = 0.0
var _test_bounces: Array[float] = []
var _test_frame: int = 0

# Physics constants
const _DROP_FLOOR_Y: float = 0.075
const _DROP_BALL_RADIUS: float = 0.06
const _DROP_REAL_GRAVITY: float = 9.81  # USAPA spec is measured at real g
const _DROP_HEIGHT_M: float = 78.0 * 0.0254  # 1.9812 m


func setup(ball: RigidBody3D) -> void:
	_ball_ref = ball


func start() -> void:
	_start_drop_test()


func tick() -> void:
	_drop_test_tick()


func is_active() -> bool:
	return _test_active


func cleanup() -> void:
	if _test_active:
		_end_drop_test()


## ── Internal ────────────────────────────────────────────────────────────────

func _start_drop_test() -> void:
	if _test_active:
		print("Drop test already running...")
		return
	_test_active = true
	_test_peak_y = 0.0
	_test_bounces.clear()
	_test_frame = 0

	# Clean up any previous visual
	if _drop_test_visual != null:
		_drop_test_visual.queue_free()
		_drop_test_visual = null

	var ball_coran: float = _ball_ref.BOUNCE_COR if _ball_ref != null else 0.685
	_drop_cor_used = ball_coran
	_drop_test_pos = Vector3(0.0, _DROP_FLOOR_Y + _DROP_BALL_RADIUS + _DROP_HEIGHT_M, 4.0)
	_drop_test_vel = Vector3.ZERO
	_drop_has_impacted = false
	_drop_awaiting_peak = false

	# Visible cyan sphere so you can see the test happening.
	_drop_test_visual = MeshInstance3D.new()
	_drop_test_visual.name = "DropTestVisual"
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = _DROP_BALL_RADIUS
	sm.height = _DROP_BALL_RADIUS * 2.0
	_drop_test_visual.mesh = sm
	var mt: StandardMaterial3D = StandardMaterial3D.new()
	mt.albedo_color = Color(0.0, 1.0, 1.0)
	mt.emission_enabled = true
	mt.emission = Color(0.0, 1.0, 1.0)
	mt.emission_energy_multiplier = 1.2
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_drop_test_visual.material_override = mt
	_drop_test_visual.position = _drop_test_pos
	add_child(_drop_test_visual)

	var theoretical_rebound: float = _DROP_HEIGHT_M * _drop_cor_used * _drop_cor_used / 0.0254
	var gravity_display: float = 9.81 * (_ball_ref.gravity_scale if _ball_ref != null else 1.5)
	print("")
	print("=== DROP TEST STARTED (kinematic, isolates BOUNCE_COR) ===")
	print("  Reads ball.BOUNCE_COR = %.3f" % _drop_cor_used)
	print("  Uses REAL gravity 9.81 m/s² (not arcade %.2f — drop test must match USAPA spec)" % gravity_display)
	print("  No air drag applied (measuring bounce in isolation)")
	print("  Drop height: 78 in (%.4f m)" % _DROP_HEIGHT_M)
	print("  Theoretical rebound (pure BOUNCE_COR): %.1f in" % theoretical_rebound)
	print("  USAPA spec: 30-34 in (COR 0.620-0.660)")


func _drop_test_tick() -> void:
	if not _test_active:
		return
	_test_frame += 1
	var dt: float = 1.0 / 60.0  # fixed 60 Hz integration
	_drop_test_vel.y -= _DROP_REAL_GRAVITY * dt
	_drop_test_pos += _drop_test_vel * dt

	var h: float = _drop_test_pos.y - _DROP_BALL_RADIUS - _DROP_FLOOR_Y
	if _test_frame % 20 == 0:
		print("  [F%d] h=%.3fm vy=%.2f" % [_test_frame, h, _drop_test_vel.y])

	# Manual bounce at floor — uses ball.gd's exact formula.
	# Compute the rebound peak ANALYTICALLY from v_out: h_peak = v² / (2g).
	# This gives zero integration noise — each recorded bounce height is the
	# exact theoretical rebound for the v_out produced by BOUNCE_COR. The
	# visual sphere still frame-integrates for display, but we don't rely on
	# sampling to find the apex.
	if h <= 0.0 and _drop_test_vel.y < 0.0:
		_drop_test_pos.y = _DROP_FLOOR_Y + _DROP_BALL_RADIUS
		var v_in_abs: float = abs(_drop_test_vel.y)
		var v_out: float = v_in_abs * _drop_cor_used
		_drop_test_vel.y = v_out
		var peak_m: float = (v_out * v_out) / (2.0 * _DROP_REAL_GRAVITY)
		var peak_in_a: float = peak_m / 0.0254
		_test_bounces.append(peak_in_a)
		print("  IMPACT frame %d  v_in=%.3f  v_out=%.3f  COR=%.4f  rebound=%.2f in" % [
			_test_frame, v_in_abs, v_out, v_out / v_in_abs, peak_in_a])
		_drop_has_impacted = true
		_drop_awaiting_peak = false
		_test_peak_y = 0.0
		if _test_bounces.size() >= 3:
			_end_drop_test()

	# (No sample-based peak detection — analytic path above records each bounce
	# the moment the impact fires, giving exact theoretical rebound heights.)

	if _drop_test_visual:
		_drop_test_visual.position = _drop_test_pos


func _end_drop_test() -> void:
	_test_active = false
	var b1: float = _test_bounces[0] if not _test_bounces.is_empty() else 0.0
	var measured_cor: float = sqrt(b1 / 78.0) if b1 > 0.0 else 0.0
	var theoretical_b1: float = 78.0 * _drop_cor_used * _drop_cor_used
	print("")
	print("=== DROP TEST RESULTS (kinematic) ===")
	print("  BOUNCE_COR tested : %.3f" % _drop_cor_used)
	print("  Theoretical b1    : %.1f in  (78 × COR²)" % theoretical_b1)
	print("  Measured b1       : %.1f in" % b1)
	if _test_bounces.size() > 1:
		print("  Measured b2       : %.1f in" % _test_bounces[1])
	if _test_bounces.size() > 2:
		print("  Measured b3       : %.1f in" % _test_bounces[2])
	print("  Measured COR      : %.3f" % measured_cor)
	var integration_err: float = abs(measured_cor - _drop_cor_used)
	if integration_err < 0.01:
		print("  ✓ Integration matches BOUNCE_COR within %.3f" % integration_err)
	else:
		print("  ⚠ Integration error: %.3f (numerical noise)" % integration_err)
	print("")
	print("  USAPA spec        : 30-34 in  (COR 0.620-0.660)")
	if b1 >= 30.0 and b1 <= 34.0:
		print("  ✓ PASS — matches USAPA spec")
	elif b1 < 30.0:
		var target_cor: float = sqrt(32.0 / 78.0)
		print("  ✗ FAIL — too dead. Raise BOUNCE_COR in ball.gd.")
		print("    Try BOUNCE_COR := %.3f  (mid-spec 32 in rebound)" % target_cor)
	else:
		var target_cor2: float = sqrt(32.0 / 78.0)
		print("  ✗ FAIL — too bouncy. Lower BOUNCE_COR in ball.gd.")
		print("    Try BOUNCE_COR := %.3f  (mid-spec 32 in rebound)" % target_cor2)
	print("=========================")
	print("  Press T to re-test, 4 to launch practice ball, SPACE to resume")

	if _drop_test_visual:
		_drop_test_visual.queue_free()
		_drop_test_visual = null

	test_complete.emit()
