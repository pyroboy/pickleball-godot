extends RigidBody3D
class_name Ball

# Physics constants
const BALL_MASS := 0.024
const BALL_RADIUS := 0.0375  # USAPA 73-75.5mm diameter → r=0.0365-0.03775m. Was 0.06 (2.56× too large).
const GRAVITY_SCALE := 1.0  # was 1.5 — that was a pre-aero hack to simulate missing drag;
							 # now that drag + Magnus are live, real gravity (1.0) plus them
							 # feels correct. Without this, effective ~2.5g "Jupiter feel".
const MAX_SPEED := 20.0
const SERVE_SPEED := 8.0
const BOUNCE_COR := 0.640  # calibrated against USAPA 30-34" drop-test spec (rev 8.1)
const FLOOR_Y := 0.075

## Canonical effective gravity for all predictors. Reads ProjectSettings and
## multiplies by this class's GRAVITY_SCALE so prediction code never diverges
## from the live ball. Assumes GRAVITY_SCALE stays a const — if it ever becomes
## per-instance runtime-mutable, switch callers to an instance method.
static func get_effective_gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity")) * GRAVITY_SCALE

## Velocity-dependent coefficient of restitution for pickleball balls.
## Cross (1999) + USAPA equipment testing: COR drops from ~0.78 at 3 m/s impact
## to ~0.56 at 18 m/s. Pickleball's hollow plastic construction with holes
## has a steeper drop than tennis balls. GAP-21.
static func cor_for_impact_speed(v_impact: float) -> float:
	return lerpf(0.78, 0.56, clampf((v_impact - 3.0) / 15.0, 0.0, 1.0))  # Cross 1999 + USAPA GAP-21: COR 0.78→0.56 from 3→18 m/s.

# ── Aero + Spin calibration constants (tunable via BallPhysicsProbe / key 4) ──
# References:
#   Cross (1999) Dynamic Properties of Tennis Balls — Sports Engineering 2(1)
#   Mehta (1985) Aerodynamics of Sports Balls — Annu. Rev. Fluid Mech. 17
#   USAPA ball spec — diameter 73-75.5 mm, mass 22.1-26.5 g, 30-34" bounce @ 78"
# Real pickleball drag coefficient for a perforated plastic ball is Cd ~0.45-0.55
# at rally speeds. Real Magnus coefficient ~1e-4 produces visible curl on hit spin.
const AIR_DENSITY := 1.225                # kg/m³ at sea level
const DRAG_COEFFICIENT := 0.47            # perforated pickleball, speed-averaged
# Magnus: F = k × (ω × v). For a smooth sphere, k ≈ ρ × V_ball (Kutta-Joukowski).
# Game ball (r=0.06): ρ×V = 1.225 × (4/3)π × 0.06³ ≈ 0.00111 kg.
# Perforated balls have empirically higher effective Magnus (~1.3-2× K-J) due to
# asymmetric boundary-layer separation. Default 0.0015 so curl is visible. Lower
# to ~0.0005 if the game feels too twitchy.
const MAGNUS_COEFFICIENT := 0.0003  # was 0.0008 — 0.0008 × ω×v = ~17 m/s² Magnus at (ω=40, v=13); 4× Cross tennis ball value. Halved to 0.0003 for visible but not dominant curl.
									# at typical rally speeds (v=12, ω=25), stacking with
									# gravity. Halved so Magnus tops out around 0.5g,
									# visible curve without dominating flight.
const SPIN_DAMPING_HALFLIFE := 150.0      # was 66.0 — spin decay still too fast even with HL=66. Raw trajectory
											 # shows decay rate ~0.133/s (HL_eff~5.2s) vs intended 0.0399/s (HL_eff~17s).
											 # Empirical: need HL~150 to get effective decay rate of ~0.0099/s ≈ 1/AERO_SCALE
											 # of what HL=22 should produce, suggesting Godot applies an extra
											 # ~AERO_SCALE^-1 factor from its physics sub-stepping.
const SPIN_BOUNCE_TRANSFER := 0.25        # fraction of (v_tangent - r*ω) absorbed per bounce
const SPIN_BOUNCE_DECAY := 0.70           # fraction of |ω| surviving a bounce
# MASTER SCALE for all new aero + spin effects. 0.0 = disabled (pre-change behavior),
# 1.0 = fully realistic. Start at 0.5 so the game feels close to current, then tune
# up with the physics probe (press 4) until measured decel matches the real reference.
const AERO_EFFECT_SCALE := 0.79  # was 0.85 — high-speed decel too draggy (delta -0.44); probe suggested ~0.79.
# Set true to draw an axis arrow + equator marker so spin is visible on the ball.
const SHOW_SPIN_DEBUG := true

# State
var is_in_play: bool = false
var last_hit_by: int = -1
var serve_team: int = 0
var can_register_floor_bounce: bool = true
var was_above_bounce_height: bool = true
var bounce_count: int = 0

# Rally rule tracking
var serving_side_bounced: bool = false
var receiving_side_bounced: bool = false
var both_bounces_complete: bool = false
var ball_bounced_since_last_hit: bool = false
var bounces_since_last_hit: int = 0
var was_volley: bool = false  # True if the last hit was a volley (ball hadn't bounced since prior hit)

signal hit_by_paddle(player_num: int)
signal bounced(position: Vector3)
## Fires when the ball physically contacts a player's body collider (capsule)
## rather than their paddle. Used for the "ball hits player = fault" rule.
signal hit_player_body(player_num: int)

# Audio synth child node
var audio_synth: Node = null

# Spin visualizers (set up in _ready when SHOW_SPIN_DEBUG is true).
var _spin_axis_node: MeshInstance3D = null   # cylinder aligned with ω
var _equator_marker: MeshInstance3D = null    # small sphere at local (0,0,-r)
var _equator_marker_2: MeshInstance3D = null  # second marker at local (r,0,0)

func _ready() -> void:
	var synth := preload("res://scripts/ball_audio_synth.gd").new()
	synth.name = "BallAudioSynth"
	add_child(synth)
	audio_synth = synth

	# BallTrail is a game-root child created by game.gd — not a ball child.
	_setup_ball()

	# Wire signals to audio synth
	hit_by_paddle.connect(_on_paddle_hit)
	bounced.connect(_on_floor_bounce)
	body_entered.connect(_on_body_entered)

func _setup_ball() -> void:
	name = "Ball"
	collision_layer = 1
	# Mask 7 = layers 1 (other balls) + 2 (players) + 3 (court/net).
	# Layer 2 lets the ball physically bounce off the player's capsule collider,
	# which is how the "ball hits body = fault" rule is detected — the paddle is
	# a separate Area3D so normal swings are unaffected.
	collision_mask = 7

	mass = BALL_MASS
	gravity_scale = GRAVITY_SCALE

	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 1.0   # neutral — our manual bounce code is the sole COR authority
	physics_material_override.friction = 0.25

	contact_monitor = true
	max_contacts_reported = 4

	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = BALL_RADIUS
	col.shape = shape
	add_child(col)

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = BALL_RADIUS
	mesh.height = BALL_RADIUS * 2
	mesh_inst.mesh = mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0)
	mat.roughness = 0.3
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	if SHOW_SPIN_DEBUG:
		_setup_spin_debug_visuals()

	reset()

## Creates two child meshes so ball rotation is visually obvious:
##   1. A cylinder that always points along ω (spin axis arrow) — color-coded
##      green for topspin, red for backspin, cyan for sidespin.
##   2. Two small spheres bolted to the ball local frame — one at +X, one at +Z.
##      Because these are parented to the RigidBody3D, they automatically rotate
##      with angular_velocity (Godot physics spins the body, mesh children
##      inherit the rotation). Without markers on a uniform yellow sphere you
##      can't see rotation; these make it obvious.
func _setup_spin_debug_visuals() -> void:
	# Spin-axis arrow (NOT parented under the RigidBody so it doesn't rotate
	# with the body — we reorient it manually every frame in _physics_process).
	_spin_axis_node = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.008
	cyl.bottom_radius = 0.008
	cyl.height = BALL_RADIUS * 3.0  # extends ~18cm, clearly visible
	_spin_axis_node.mesh = cyl
	var axis_mat: StandardMaterial3D = StandardMaterial3D.new()
	axis_mat.albedo_color = Color(0.0, 1.0, 0.3)
	axis_mat.emission_enabled = true
	axis_mat.emission = Color(0.0, 1.0, 0.3)
	axis_mat.emission_energy_multiplier = 1.5
	axis_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spin_axis_node.material_override = axis_mat
	add_child(_spin_axis_node)
	_spin_axis_node.top_level = true  # Ignore parent transform so we can orient manually.

	# Equator markers: small red + blue dots parented to the ball. Because
	# they're children of the RigidBody3D, Godot automatically rotates them
	# with the ball's angular_velocity. You SEE rotation by watching these.
	_equator_marker = MeshInstance3D.new()
	var m1: SphereMesh = SphereMesh.new()
	m1.radius = 0.022
	m1.height = 0.044
	_equator_marker.mesh = m1
	var emat: StandardMaterial3D = StandardMaterial3D.new()
	emat.albedo_color = Color(1.0, 0.0, 0.0)
	emat.emission_enabled = true
	emat.emission = Color(1.0, 0.0, 0.0)
	emat.emission_energy_multiplier = 1.2
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_equator_marker.material_override = emat
	_equator_marker.position = Vector3(BALL_RADIUS * 0.95, 0, 0)
	add_child(_equator_marker)

	_equator_marker_2 = MeshInstance3D.new()
	_equator_marker_2.mesh = m1
	var emat2: StandardMaterial3D = StandardMaterial3D.new()
	emat2.albedo_color = Color(0.0, 0.4, 1.0)
	emat2.emission_enabled = true
	emat2.emission = Color(0.0, 0.4, 1.0)
	emat2.emission_energy_multiplier = 1.2
	emat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_equator_marker_2.material_override = emat2
	_equator_marker_2.position = Vector3(0, 0, BALL_RADIUS * 0.95)
	add_child(_equator_marker_2)

## Update the spin-axis arrow to point along angular_velocity. Called each frame.
## Length scales with |ω|; color indicates topspin/backspin/sidespin relative to
## current horizontal velocity direction.
func _update_spin_visualizer() -> void:
	if _spin_axis_node == null:
		return
	var omega: Vector3 = angular_velocity
	var omega_mag: float = omega.length()
	if omega_mag < 0.1:
		_spin_axis_node.visible = false
		return
	_spin_axis_node.visible = true
	_spin_axis_node.global_position = global_position
	# Orient cylinder along ω (default cylinder is along +Y).
	var omega_dir: Vector3 = omega / omega_mag
	var up: Vector3 = Vector3.UP
	if absf(omega_dir.dot(up)) > 0.99:
		up = Vector3.RIGHT  # avoid degenerate look_at basis
	_spin_axis_node.look_at(global_position + omega_dir, up)
	_spin_axis_node.rotate_object_local(Vector3.RIGHT, PI * 0.5)  # align cylinder axis (Y) to ω
	# Scale length with spin magnitude (clamped so it stays readable).
	var scale_len: float = clampf(omega_mag / 25.0, 0.3, 2.0)
	_spin_axis_node.scale = Vector3(1.0, scale_len, 1.0)
	# Color: green topspin, red backspin, cyan sidespin.
	var h_vel: Vector3 = Vector3(linear_velocity.x, 0, linear_velocity.z)
	var tier: Color = Color(0.0, 1.0, 0.3)  # default green
	if h_vel.length() > 0.5:
		var roll_axis: Vector3 = Vector3.UP.cross(h_vel.normalized())
		var roll_c: float = omega.dot(roll_axis)
		var side_c: float = absf(omega.dot(Vector3.UP))
		var roll_abs: float = absf(roll_c)
		if side_c > roll_abs:
			tier = Color(0.0, 0.8, 1.0)  # cyan sidespin
		elif roll_c > 0:
			tier = Color(0.0, 1.0, 0.3)  # green topspin
		else:
			tier = Color(1.0, 0.2, 0.2)  # red backspin
	var axis_mat: StandardMaterial3D = _spin_axis_node.material_override as StandardMaterial3D
	if axis_mat:
		axis_mat.albedo_color = tier
		axis_mat.emission = tier

# ── Signal handlers (delegate to audio_synth) ────────────────────────────────

func _on_paddle_hit(_player_num: int) -> void:
	if audio_synth:
		audio_synth.on_paddle_hit(linear_velocity.length())

func _on_floor_bounce(_position: Vector3) -> void:
	if audio_synth:
		audio_synth.on_floor_bounce(linear_velocity.length())

func _on_body_entered(body: Node) -> void:
	if audio_synth:
		audio_synth.on_body_entered(body, global_position.y, linear_velocity)
	# Body-hit fault: if the ball touches a PlayerController capsule (not the
	# paddle Area3D), emit hit_player_body so game.gd can fault the rally.
	# A post-paddle-hit cooldown (in game.gd) suppresses false positives from
	# swing follow-through where the paddle may briefly pass through body space.
	if body is CharacterBody3D and body.has_method("get_player_num"):
		hit_player_body.emit(body.get_player_num())

var _time_frozen: bool = false
var _frozen_position: Vector3 = Vector3.ZERO
var _frozen_velocity: Vector3 = Vector3.ZERO
var _frozen_omega: Vector3 = Vector3.ZERO
var _frozen_basis: Basis = Basis.IDENTITY

func set_time_frozen(frozen: bool) -> void:
	_time_frozen = frozen

func set_frozen_state(pos: Vector3, vel: Vector3, omega: Vector3) -> void:
	_frozen_position = pos
	_frozen_velocity = vel
	_frozen_omega = omega
	_frozen_basis = transform.basis

func is_time_frozen() -> bool:
	return _time_frozen

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _time_frozen:
		state.transform = Transform3D(_frozen_basis, _frozen_position)
		state.linear_velocity = _frozen_velocity
		state.angular_velocity = _frozen_omega

# ── Physics ──────────────────────────────────────────────────────────────────

func _physics_process(_delta: float) -> void:
	if _time_frozen:
		return
	if audio_synth:
		audio_synth.update_cooldown(_delta)
	if SHOW_SPIN_DEBUG:
		_update_spin_visualizer()

	# ── Aero: quadratic air drag (GAP-55) ──────────────────────────────────
	# F_drag = -0.5 * rho * Cd * A * |v| * v   (opposes motion)
	# Gated by AERO_EFFECT_SCALE so the user can ramp from 0 (disabled) to 1 (real).
	var speed: float = linear_velocity.length()
	if speed > 0.1 and AERO_EFFECT_SCALE > 0.0:
		var cross_section: float = PI * BALL_RADIUS * BALL_RADIUS
		var drag_force_mag: float = 0.5 * AIR_DENSITY * DRAG_COEFFICIENT * cross_section * speed * speed
		var drag_accel: Vector3 = -linear_velocity.normalized() * (drag_force_mag / mass)
		linear_velocity += drag_accel * _delta * AERO_EFFECT_SCALE

	# ── Aero: Magnus curl force from spin (GAP-59) ─────────────────────────
	# F_magnus = k * (ω × v). For topspin on a ball moving +Z with ω=+X, this
	# pushes the ball downward (−Y) — curling topspin dips. Backspin lifts it.
	# NOTE: Serve (ball.serve()) intentionally sets angular_velocity = Vector3.ZERO
	# because pickleball serves are flat (unlike tennis). The serve uses
	# linear_velocity for direction and intentionally omits spin.
	# For regular shots, angular_velocity is set by the hitting code via
	# compute_shot_spin() + compute_sweet_spot_spin() and IS consumed here.
	if angular_velocity.length_squared() > 0.01 and speed > 0.5 and AERO_EFFECT_SCALE > 0.0:
		var magnus_force: Vector3 = MAGNUS_COEFFICIENT * angular_velocity.cross(linear_velocity)
		linear_velocity += (magnus_force / mass) * _delta * AERO_EFFECT_SCALE

	# ── Spin damping from air viscosity (GAP-61) ───────────────────────────
	# Exponential decay toward zero with SPIN_DAMPING_HALFLIFE.
	if angular_velocity.length_squared() > 0.001 and AERO_EFFECT_SCALE > 0.0:
		var spin_decay: float = exp(-_delta * 0.693 / (SPIN_DAMPING_HALFLIFE * AERO_EFFECT_SCALE))
		angular_velocity *= spin_decay

	if linear_velocity.length() > MAX_SPEED:
		linear_velocity = linear_velocity.normalized() * MAX_SPEED

	if global_position.y > 5:
		global_position.y = 5
		linear_velocity.y = min(linear_velocity.y, 0)

	# Manual floor bounce — Godot's PhysicsMaterial.bounce doesn't apply COR reliably
	var floor_rest_y: float = FLOOR_Y + BALL_RADIUS  # 0.135
	if global_position.y < floor_rest_y and linear_velocity.y < 0:
		global_position.y = floor_rest_y
		# ── Spin-tangential coupling on bounce (GAP-60) ────────────────────
		# Topspin transfers rolling energy forward; backspin subtracts.
		# Surface velocity at bottom contact point = ω × (−r * ŷ) → (-ω_z * r, 0, ω_x * r)
		# Tangential velocity moves toward this surface velocity by SPIN_BOUNCE_TRANSFER.
		if AERO_EFFECT_SCALE > 0.0:
			var tang_v: Vector3 = Vector3(linear_velocity.x, 0, linear_velocity.z)
			var spin_surface: Vector3 = Vector3(
				-angular_velocity.z * BALL_RADIUS,
				0,
				angular_velocity.x * BALL_RADIUS
			)
			var new_tang: Vector3 = tang_v - SPIN_BOUNCE_TRANSFER * (tang_v - spin_surface) * AERO_EFFECT_SCALE
			linear_velocity.x = new_tang.x
			linear_velocity.z = new_tang.z
			angular_velocity *= lerpf(1.0, SPIN_BOUNCE_DECAY, AERO_EFFECT_SCALE)
		linear_velocity.y = abs(linear_velocity.y) * cor_for_impact_speed(abs(linear_velocity.y))
		# Register the bounce here — where it actually happens
		if can_register_floor_bounce:
			bounce_count += 1
			bounced.emit(Vector3(global_position.x, 0.082, global_position.z))
			can_register_floor_bounce = false

	# Re-arm the per-contact debounce as soon as the ball lifts clear of the
	# resting floor level. Previous threshold (+0.14m) required the ball to
	# peak above ~0.20m, which meant soft dinks with vy < ~2 m/s never re-armed
	# and subsequent bounces silently failed to emit, breaking double-bounce
	# fault detection for low-energy balls.
	if global_position.y > floor_rest_y + 0.015:
		can_register_floor_bounce = true

# ── Public API ───────────────────────────────────────────────────────────────

func serve(team: int, direction: Vector3) -> void:
	serve_team = team
	is_in_play = true
	last_hit_by = team

	linear_velocity = direction.normalized() * SERVE_SPEED
	# GAP-41: removed vestigial angular_velocity randomization — no consumers
	# in physics (no Magnus force, no spin-to-bounce transfer). Was visual
	# rotation only, but also unseen since ball texture is uniform.

func reset() -> void:
	global_position = Vector3(-1.5, 1.5, -4)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	is_in_play = false
	last_hit_by = -1
	can_register_floor_bounce = true
	was_above_bounce_height = true
	bounce_count = 0

func hit_by_player(player_num: int) -> void:
	was_volley = not ball_bounced_since_last_hit  # Capture before reset
	last_hit_by = player_num
	ball_bounced_since_last_hit = false
	bounces_since_last_hit = 0
	hit_by_paddle.emit(player_num)

func get_last_hit_by() -> int:
	return last_hit_by

func get_bounce_count() -> int:
	return bounce_count

func record_bounce_side(bounce_z: float) -> void:
	ball_bounced_since_last_hit = true
	bounces_since_last_hit += 1
	var is_positive_z: bool = bounce_z > 0.0
	if (serve_team == 0 and is_positive_z) or (serve_team == 1 and not is_positive_z):
		serving_side_bounced = true
	else:
		receiving_side_bounced = true
	if serving_side_bounced and receiving_side_bounced:
		both_bounces_complete = true

func can_volley() -> bool:
	return both_bounces_complete

func reset_rally_state() -> void:
	serving_side_bounced = false
	receiving_side_bounced = false
	both_bounces_complete = false
	ball_bounced_since_last_hit = false
	bounces_since_last_hit = 0
	bounce_count = 0
	last_hit_by = -1
	was_volley = false


# Shared predictor helpers. Mirror _physics_process aero + _bounce_floor so
# every forward-Euler predictor (debug_visual, ai_brain) stays in lockstep
# with the live ball. Change aero physics here, and predictors follow.

static func predict_aero_step(pos: Vector3, vel: Vector3, omega: Vector3, gravity: float, dt: float) -> Array:
	vel.y -= gravity * dt

	var speed: float = vel.length()
	if speed > 0.1 and AERO_EFFECT_SCALE > 0.0:
		var cross_section: float = PI * BALL_RADIUS * BALL_RADIUS
		var drag_force_mag: float = 0.5 * AIR_DENSITY * DRAG_COEFFICIENT * cross_section * speed * speed
		var drag_accel: Vector3 = -vel.normalized() * (drag_force_mag / BALL_MASS)
		vel += drag_accel * dt * AERO_EFFECT_SCALE

	if omega.length_squared() > 0.01 and speed > 0.5 and AERO_EFFECT_SCALE > 0.0:
		var magnus_force: Vector3 = MAGNUS_COEFFICIENT * omega.cross(vel)
		vel += (magnus_force / BALL_MASS) * dt * AERO_EFFECT_SCALE

	if omega.length_squared() > 0.001 and AERO_EFFECT_SCALE > 0.0:
		var spin_decay: float = exp(-dt * 0.693 / (SPIN_DAMPING_HALFLIFE * AERO_EFFECT_SCALE))
		omega *= spin_decay

	if vel.length() > MAX_SPEED:
		vel = vel.normalized() * MAX_SPEED

	pos += vel * dt
	return [pos, vel, omega]


static func predict_bounce_spin(vel: Vector3, omega: Vector3) -> Array:
	if AERO_EFFECT_SCALE > 0.0:
		var tang_v: Vector3 = Vector3(vel.x, 0, vel.z)
		var spin_surface: Vector3 = Vector3(
			-omega.z * BALL_RADIUS,
			0,
			omega.x * BALL_RADIUS
		)
		var new_tang: Vector3 = tang_v - SPIN_BOUNCE_TRANSFER * (tang_v - spin_surface) * AERO_EFFECT_SCALE
		vel.x = new_tang.x
		vel.z = new_tang.z
		omega *= lerpf(1.0, SPIN_BOUNCE_DECAY, AERO_EFFECT_SCALE)
	vel.y = abs(vel.y) * cor_for_impact_speed(abs(vel.y))
	return [vel, omega]
