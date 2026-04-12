class_name DropTest extends Node

## Kinematic drop test — measures BOUNCE_COR constant in isolation.
##
## Why kinematic instead of a RigidBody3D? The real game ball in ball.gd runs
## manual bounce code inside _physics_process — it sets Godot's built-in
## physics_material.bounce to 0 and applies `linear_velocity.y *= BOUNCE_COR`
## itself. If we create a vanilla RigidBody3D test ball, we end up measuring
## Godot's default collision response with zero restitution, which is NOT what
## the game actually uses. Instead we integrate position/velocity manually here
## using the same constants the game uses (BOUNCE_COR, gravity), so the test
## measures the real knob.
##
## USAPA spec: 78" drop on granite → 30-34" rebound → COR 0.620-0.660.

const _FLOOR_Y: float = 0.075
const _BALL_RADIUS: float = 0.06
const _DROP_METERS: float = 78.0 * 0.0254  # 1.9812 m

var _test_visual: MeshInstance3D = null  # visible sphere for the test
var _test_pos: Vector3 = Vector3.ZERO
var _test_vel: Vector3 = Vector3.ZERO
var _test_active: bool = false
var _test_phase: String = "falling"
var _test_peak_y: float = 0.0
var _test_bounces: Array = []
var _test_frame: int = 0
var _t_was_pressed: bool = false

# Captured at test start so the result printout knows what was tested.
var _cor_used: float = 0.0
var _gravity_eff: float = 0.0

var _main: Node3D

func _ready() -> void:
	_main = get_parent() as Node3D

func tick(delta: float) -> void:
	var t_pressed: bool = Input.is_key_pressed(KEY_T)
	if t_pressed and not _t_was_pressed:
		print("T PRESSED")
		_start_drop_test()
	_t_was_pressed = t_pressed
	_drop_test_tick(delta)

func _start_drop_test() -> void:
	if _test_active:
		print("Drop test already running...")
		return

	# Clean up previous visual
	if _test_visual != null:
		_test_visual.queue_free()
		_test_visual = null

	# Pull the exact constants the game ball uses. These are class constants,
	# not instance vars, so we can reference them directly through the ball.
	_cor_used = _main.ball.BOUNCE_COR
	var grav_scale: float = _main.ball.gravity_scale
	_gravity_eff = float(ProjectSettings.get_setting("physics/3d/default_gravity")) * grav_scale

	# Reset simulation state
	var start_x: float = 3.5
	var start_z: float = 0.0
	_test_pos = Vector3(start_x, _FLOOR_Y + _BALL_RADIUS + _DROP_METERS, start_z)
	_test_vel = Vector3.ZERO
	_test_active = true
	_test_phase = "falling"
	_test_peak_y = 0.0
	_test_bounces.clear()
	_test_frame = 0

	# Create a visible sphere so you can see the test happening.
	_test_visual = MeshInstance3D.new()
	_test_visual.name = "DropTestVisual"
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = _BALL_RADIUS
	mesh.height = _BALL_RADIUS * 2.0
	_test_visual.mesh = mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 1.0, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.0, 1.0, 1.0)
	mat.emission_energy_multiplier = 1.0
	_test_visual.material_override = mat
	_test_visual.position = _test_pos
	_main.add_child(_test_visual)

	print("")
	print("=== DROP TEST STARTED (kinematic, tests ball.gd BOUNCE_COR) ===")
	print("  BOUNCE_COR        : %.3f" % _cor_used)
	print("  gravity_scale     : %.2f" % grav_scale)
	print("  effective gravity : %.2f m/s² (real pickleball: 9.81)" % _gravity_eff)
	print("  drop height       : 78 in (%.4f m)" % _DROP_METERS)
	print("  theoretical impact: v = sqrt(2·g·h) = %.2f m/s" % sqrt(2.0 * _gravity_eff * _DROP_METERS))
	print("  theoretical rebound: %.1f in  (v²_out / (2g) with perfect COR)" % (_DROP_METERS * _cor_used * _cor_used / 0.0254))
	print("  Waiting for impacts...")

func _drop_test_tick(delta: float) -> void:
	if not _test_active:
		return

	_test_frame += 1

	# Kinematic integration: gravity → velocity → position.
	# No air drag on purpose — we're isolating the bounce measurement.
	_test_vel.y -= _gravity_eff * delta
	_test_pos += _test_vel * delta

	var height_above_floor: float = _test_pos.y - _BALL_RADIUS - _FLOOR_Y

	# Log every 20 frames during flight.
	if _test_frame % 20 == 0:
		print("  [F%d] h=%.3fm vy=%.2f" % [_test_frame, height_above_floor, _test_vel.y])

	# Manual floor bounce — identical to ball.gd's formula.
	if height_above_floor <= 0.0 and _test_vel.y < 0.0:
		# Snap to floor and apply BOUNCE_COR.
		_test_pos.y = _FLOOR_Y + _BALL_RADIUS
		_test_vel.y = abs(_test_vel.y) * _cor_used
		print("  IMPACT at frame %d, vy_out=%.2f" % [_test_frame, _test_vel.y])
		_test_phase = "rising"
		_test_peak_y = 0.0

	# Peak detection while rising.
	match _test_phase:
		"rising":
			if height_above_floor > _test_peak_y:
				_test_peak_y = height_above_floor
			if _test_vel.y < -0.05 and _test_peak_y > 0.01:
				var peak_in: float = _test_peak_y / 0.0254
				_test_bounces.append(peak_in)
				var bnum: int = _test_bounces.size()
				print("  Bounce %d: %.1f in  (%.3f m)" % [bnum, peak_in, _test_peak_y])
				if bnum >= 3:
					_finish_drop_test()
				else:
					_test_phase = "falling"
					_test_peak_y = 0.0

	# Keep the visual synced with the simulated position.
	if _test_visual:
		_test_visual.position = _test_pos

func _finish_drop_test() -> void:
	_test_active = false
	var b1: float = _test_bounces[0]
	var measured_cor: float = sqrt(b1 / 78.0)
	var theoretical_b1: float = 78.0 * _cor_used * _cor_used

	print("")
	print("=== DROP TEST RESULTS (kinematic, BOUNCE_COR = %.3f) ===" % _cor_used)
	print("  Bounce 1         : %.1f in   (theoretical: %.1f in)" % [b1, theoretical_b1])
	print("  Bounce 2         : %.1f in" % _test_bounces[1])
	print("  Bounce 3         : %.1f in" % _test_bounces[2])
	print("  Measured COR     : %.3f" % measured_cor)
	print("  BOUNCE_COR const : %.3f" % _cor_used)
	var discrepancy: float = abs(measured_cor - _cor_used)
	if discrepancy < 0.01:
		print("  ✓ Measured matches the BOUNCE_COR constant (integration accurate)")
	else:
		print("  ⚠ Measured differs from BOUNCE_COR by %.3f — integration noise" % discrepancy)
	print("")
	print("  USA PB spec      : 30-34 in  (COR 0.620-0.660 at ~6 m/s impact)")
	if b1 >= 30.0 and b1 <= 34.0:
		print("  ✓ PASS — matches USAPA spec")
	elif b1 < 30.0:
		var suggested_cor: float = sqrt(32.0 / 78.0)  # target middle of spec
		print("  ✗ FAIL — too dead. Raise BOUNCE_COR in ball.gd.")
		print("    Try BOUNCE_COR := %.3f  (mid-spec 32 in rebound)" % suggested_cor)
	else:
		var suggested_cor2: float = sqrt(32.0 / 78.0)
		print("  ✗ FAIL — too bouncy. Lower BOUNCE_COR in ball.gd.")
		print("    Try BOUNCE_COR := %.3f  (mid-spec 32 in rebound)" % suggested_cor2)
	print("  Mass (ref)       : %.4f kg   Gravity scale: %.2f" % [_main.ball.mass, _main.ball.gravity_scale])
	print("=========================")
	print("")

	# Clean up visual
	if _test_visual:
		_test_visual.queue_free()
		_test_visual = null
