extends Node3D
## Realistic paddle look (visual only). The gameplay paddle stays under BodyPivot with
## its meshes moved to a render layer the camera does not draw (gameplay still scans
## them); this node lives OUTSIDE the player and copies the paddle's interpolated
## transform every rendered frame. Designs: data/paddles.json. Shape = regulation
## outline from paddle_dimensions.gd, so the look always matches the hitbox.

const D = preload("res://scripts/paddle_dimensions.gd")
const DATA_PATH: = "res://data/paddles.json"
const SETTING_KEY: = "video.paddle"
const CLASSIC_LAYER: = 20   # same hidden layer as pixel_card_rig.gd
const FACE_W: = 40          # ~4.8 mm per texel: pixel look at gameplay zoom
const FACE_H: = 60
const GRIP_W: = 16
const GRIP_H: = 24
const EDGE_WRAP: = 0.005    # metres of edge guard visible on the face
# Wrist lag (visual only, see _wrist_lag): the head is a damped pendulum on the grip.
# Like tennis lag it is passive: the hand speeds up, the head's inertia keeps it behind,
# a relaxed wrist lets gravity drop it, and it whips past the true face after contact.
# How relaxed the wrist is comes from the shot charge and shot type (_grip_relax).
const LAG_HZ_FIRM: = 18.0     # wrist natural frequency, firm grip (dinks, ready)
const LAG_HZ_LOOSE: = 2.2     # relaxed grip, full charge drive / smash
const LAG_ZETA_FIRM: = 0.9    # damping ratio, firm wrist: no wobble on quick pose changes
const LAG_ZETA_LOOSE: = 0.5   # relaxed wrist: whips past the face after contact
const LAG_GRAVITY: = 45.0     # m/s2 on the head at full relax (~12 degree drop when held flat)
const LAG_MAX_DEG: = 40.0     # largest bend shown at the wrist
const LAG_SUBSTEPS: = 3       # fewest substeps per frame (60 / 120 fps)
const LAG_MAX_STEP: = 1.0 / 180.0  # longest substep: the firm 18 Hz spring is unstable past
                                   # ~1/90 s, so 30 fps (iPhone Low Power Mode) fluttered
const RELEASE_NEAR: = 0.45    # m, incoming ball to paddle head: lag fully released (true face)
const RELEASE_FAR: = 1.4      # m, incoming ball further than this: full lag
const LAG_RESET_M: = 0.5      # head jumped this far in one frame (reset / teleport): no lag
const AI_CHARGE_TIME: = 0.32  # player_ai_brain.gd AI_CHARGE_DURATION
const RELAX_IDLE: = 0.2       # ready / between swings: paddle held up
const RELAX_HALFLIFE: = 0.05
const SHOT_RELAX: = {"DINK": 0.15, "DROP": 0.15, "VOLLEY": 0.45, "LOB": 0.6,
	"GROUNDSTROKE": 1.0, "RETURN": 1.0, "SMASH": 1.0}
const SHOT_RELAX_UNKNOWN: = 0.45
# Pre-lag (deliberate): while preparing for an incoming ball the wrist is laid back, head
# set behind the hand along the ball's travel, then let go as the ball arrives so the
# spring whips it through to the true face.
const PRELAG_DEG: = 28.0      # lay-back at full charge on a drive
const PRELAG_LET_GO_FAR: = 2.2  # m, incoming ball to head: start letting go of the lay-back
const PRELAG_LET_GO_NEAR: = 1.1 # m: lay-back fully let go (spring now whips the head through)
const PRELAG_SHOT: = {"DINK": 0.2, "DROP": 0.2, "VOLLEY": 0.5, "LOB": 0.5,
	"GROUNDSTROKE": 1.0, "RETURN": 1.0, "SMASH": 0.8}
const PRELAG_UNKNOWN: = 0.3
# Auto lag (passive): driving the head forward fast during a swing loosens the wrist on
# its own, so quick volleys and hand battles trail even without charge. Only speed along
# the swing (against the incoming ball, else court-forward) counts, not repositioning.
const AUTO_SPEED_LO: = 1.5    # m/s, forward head speed (body-relative) where auto lag starts
const AUTO_SPEED_HI: = 5.0    # m/s: full auto lag
const AUTO_LOOSE: = 0.75      # looseness auto lag can reach
const SPEED_HALFLIFE: = 0.04  # s, smooths one-frame pose snaps out of the speed
const SUNSET: = [Color("#993c1d"), Color("#d85a30"), Color("#ef9f27"), Color("#f0997b")]

static var _data: Dictionary = {}
static var _materials: Dictionary = {}   # design id -> {face, edge, grip, cap}
static var _head_mesh: ArrayMesh

var design_id: = ""
var _player
var _paddle: Node3D
var _hide_timer: = 0.0
var _culled_cam: Camera3D
var _lag_tip: = Vector3.INF   # lagged head centre, relative to the body origin
var _lag_vel: = Vector3.ZERO
var _prev_tip: = Vector3.INF  # real head centre last frame, relative to the body origin
var _relax: = RELAX_IDLE
var _charge_latch: = 0.0      # highest charge seen this stroke
var _shot_type: = ""
var _swinging: = false        # this player is in a stroke (charge, strike or follow-through)
var _preparing: = false       # swinging and not yet in the follow-through
var _speed: = 0.0             # smoothed forward head speed relative to the body

static func attach(player) -> Node3D:
	if player == null or player.get("paddle_node") == null: return null
	var host: Node = player.get_parent()
	if host == null: return null
	var skin_name: = "PaddleSkin_%d" % player.get_instance_id()
	var existing: Node = host.get_node_or_null(skin_name)
	if existing != null: existing.queue_free()
	var id: = _pick_design(player, host)
	if id == "": return null
	var skin: Node3D = (load("res://scripts/graphics/paddle_skin.gd") as GDScript).new()
	skin.name = skin_name
	skin.design_id = id
	skin._player = player
	skin._paddle = player.paddle_node
	skin.set_meta("paddle_design", id)
	host.add_child(skin)
	return skin

static func designs() -> Dictionary:
	if _data.is_empty():
		var f: = FileAccess.open(DATA_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary: _data = parsed
	return _data.get("designs", {})

## Human: saved choice (video.paddle) or the default. AI: a design nobody on court uses,
## picked with its own RNG so the global (bench-seeded) RNG is never touched.
static func _pick_design(player, host: Node) -> String:
	var all: = designs()
	if all.is_empty(): return ""
	# The player's sprite profile names a default paddle (pixel_card_rig.gd sets it).
	var rig: Node = host.get_node_or_null("PixelCards_%d" % player.get_instance_id())
	var own: = str(rig.get_meta("paddle", "")) if rig != null else ""
	var saved: = str(Settings.get_value(SETTING_KEY, ""))
	if not bool(player.get("is_ai")):
		for id in [saved, own, str(_data.get("default", ""))]:
			if all.has(id): return id
		return str(all.keys()[0])
	var used: Array = [saved]
	for child in host.get_children():
		if child.has_meta("paddle_design") and not child.is_queued_for_deletion():
			used.append(child.get_meta("paddle_design"))
	if all.has(own) and not used.has(own): return own
	var free: Array = all.keys().filter(func(k): return not used.has(k))
	if free.is_empty(): free = all.keys()
	var rng: = RandomNumberGenerator.new()
	rng.randomize()
	return str(free[rng.randi_range(0, free.size() - 1)])

func _ready() -> void:
	process_priority = 1001   # after posture / IK and the card rig
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var mats: Dictionary = _materials_for(design_id)
	if _head_mesh == null: _head_mesh = _build_head()
	var head: = _mesh_node(_head_mesh, Vector3.ZERO)
	head.set_surface_override_material(0, mats.face)
	head.set_surface_override_material(1, mats.face)
	head.set_surface_override_material(2, mats.edge)
	var grip_len: float = D.HANDLE_LENGTH - 0.008
	var grip: = CylinderMesh.new()
	grip.top_radius = D.HANDLE_RADIUS * 1.04   # tape sits proud of the handle
	grip.bottom_radius = grip.top_radius
	grip.height = grip_len
	grip.radial_segments = 6
	grip.rings = 1
	_mesh_node(grip, Vector3(0, 0.008 + grip_len * 0.5, 0)).material_override = mats.grip
	var cap: = CylinderMesh.new()
	cap.top_radius = D.HANDLE_RADIUS * 1.22
	cap.bottom_radius = cap.top_radius
	cap.height = 0.008
	cap.radial_segments = 6
	cap.rings = 1
	_mesh_node(cap, Vector3(0, 0.004, 0)).material_override = mats.cap
	var throat: = BoxMesh.new()
	throat.size = Vector3(0.028, 0.02, D.THICKNESS * 0.9)
	_mesh_node(throat, Vector3(0, D.HEAD_BOTTOM_Y + 0.004, 0)).material_override = mats.edge
	_hide_original()
	_follow()

func _mesh_node(mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var node: = MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(node)
	return node

func _process(delta: float) -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_paddle):
		queue_free()
		return
	# Mirror the original's visibility: hidden player, or first-person view (the
	# gameplay camera turns the avatar's meshes to shadows-only / layer 0 there).
	var head: = _paddle.get_node_or_null("Head") as GeometryInstance3D
	visible = _paddle.is_visible_in_tree() and head != null and head.layers != 0 \
		and head.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	if not visible: return
	var cam: = get_viewport().get_camera_3d()
	if cam != null and cam != _culled_cam:
		cam.set_cull_mask_value(CLASSIC_LAYER, false)
		_culled_cam = cam
	_hide_timer -= delta
	if _hide_timer <= 0.0:
		_hide_timer = 2.0
		_hide_original()
	_follow(delta)

func _follow(delta: float = 0.0) -> void:
	# Pose editors pause physics and pose directly: read live transforms there.
	var posture = _player.get("posture")
	var raw: bool = get_tree().paused or (posture != null and posture.editor_preview_mode)
	if raw:
		_lag_tip = Vector3.INF
		global_transform = _paddle.global_transform
		return
	# The card rig's visual-only motion (arm swing, shoulder turn) moves the shown hand.
	var rig: Node = get_parent().get_node_or_null("PixelCards_%d" % _player.get_instance_id()) if get_parent() else null
	var shown: Transform3D = _paddle.get_global_transform_interpolated()
	if rig != null and rig.has_method("paddle_delta"): shown = rig.paddle_delta() * shown
	global_transform = _wrist_lag(shown, delta)
	var spin: float = rig.paddle_spin() if rig != null and rig.has_method("paddle_spin") else 0.0
	if spin != 0.0: global_transform = global_transform * Transform3D(Basis(Vector3.UP, spin), Vector3.ZERO)

## Wrist lag: the shown paddle turns about the main grip so its head follows a damped
## pendulum (spring to the real head, damping, gravity) instead of the real head. Lag grows
## with the hand's acceleration and with how relaxed the wrist is. Tracked relative to the
## body origin so running does not tilt the paddle. Fades out while the ball comes in, so
## the face the player sees at contact is the real one; after contact the whip shows.
func _wrist_lag(xf: Transform3D, delta: float) -> Transform3D:
	var pivot: Node3D = _player.get("body_pivot")
	var body: Vector3 = pivot.get_global_transform_interpolated().origin if pivot else Vector3.ZERO
	var grip: Vector3 = xf * D.MAIN_GRIP_OFFSET - body
	var tip: Vector3 = xf * D.HEAD_OFFSET - body
	var relax: float = _grip_relax(delta)
	if delta <= 0.0 or _lag_tip == Vector3.INF or _prev_tip.distance_to(tip) > LAG_RESET_M:
		_lag_tip = tip
		_prev_tip = tip
		_lag_vel = Vector3.ZERO
		return xf
	delta = minf(delta, 0.05)
	var tip_vel: Vector3 = (tip - _prev_tip) / delta
	# Soft shots stay near the firm wrist; only charged drives / smashes go loose.
	var loose: float = smoothstep(0.25, 0.9, relax)
	var fwd_speed: float = maxf(0.0, tip_vel.dot(_swing_dir(tip + body)))
	_speed = lerpf(_speed, fwd_speed, 1.0 - exp(-0.693 * delta / SPEED_HALFLIFE))
	if _swinging:
		loose = maxf(loose, AUTO_LOOSE * smoothstep(AUTO_SPEED_LO, AUTO_SPEED_HI, _speed))
	var w: float = TAU * lerpf(LAG_HZ_FIRM, LAG_HZ_LOOSE, loose)
	var k: float = w * w
	var c: float = 2.0 * lerpf(LAG_ZETA_FIRM, LAG_ZETA_LOOSE, loose) * w
	var g: = Vector3.DOWN * LAG_GRAVITY * loose
	var radius: float = (tip - grip).length()
	var limit: float = deg_to_rad(LAG_MAX_DEG)
	var steps: int = maxi(LAG_SUBSTEPS, ceili(delta / LAG_MAX_STEP - 0.01))
	var h: float = delta / steps
	var pre: Vector4 = _prelag(tip + body, tip - grip)   # axis xyz, angle w
	var pre_axis: = Vector3(pre.x, pre.y, pre.z)
	for i in steps:
		var f: float = float(i + 1) / steps   # real head and grip move through the frame
		var t_i: Vector3 = _prev_tip.lerp(tip, f)
		var g_i: Vector3 = grip - (tip - t_i)
		var aim: Vector3 = t_i if pre.w <= 0.0 else g_i + (t_i - g_i).rotated(pre_axis, pre.w)
		_lag_vel += (k * (aim - _lag_tip) - c * (_lag_vel - tip_vel) + g) * h
		_lag_tip += _lag_vel * h
		# Stay on the head's circle round the grip, within the bend limit.
		var arm: Vector3 = t_i - g_i
		var lag_arm: Vector3 = (_lag_tip - g_i).normalized() * radius
		var bend: float = arm.angle_to(lag_arm)
		if bend > limit:
			var axis: Vector3 = arm.cross(lag_arm)
			if axis.length_squared() > 1e-10:
				lag_arm = arm.rotated(axis.normalized(), limit)
			_lag_vel = _lag_vel.lerp(tip_vel, 0.5)
		_lag_tip = g_i + lag_arm
		var radial: Vector3 = lag_arm / maxf(radius, 0.001)
		_lag_vel -= radial * (_lag_vel - tip_vel).dot(radial)
	_prev_tip = tip
	var real_arm: Vector3 = tip - grip
	var shown_arm: Vector3 = _lag_tip - grip
	var angle: float = real_arm.angle_to(shown_arm)
	var turn_axis: Vector3 = real_arm.cross(shown_arm)
	if angle < 0.001 or turn_axis.length_squared() < 1e-10: return xf
	var turn: = Basis(turn_axis.normalized(), angle * _release_weight(tip + body))
	var grip_w: Vector3 = grip + body
	return Transform3D(turn * xf.basis, grip_w + turn * (xf.origin - grip_w))

## Direction the stroke drives the head: against an incoming ball's travel, else court-forward.
func _swing_dir(head: Vector3) -> Vector3:
	var ball: = _player.call("_get_ball_ref") as RigidBody3D if _player.has_method("_get_ball_ref") else null
	if ball != null and is_instance_valid(ball):
		var vel: = Vector3(ball.linear_velocity.x, 0.0, ball.linear_velocity.z)
		if vel.length_squared() > 0.01 and ball.linear_velocity.dot(head - ball.get_global_transform_interpolated().origin) > 0.0:
			return -vel.normalized()
	return _player.call("_get_forward_axis") if _player.has_method("_get_forward_axis") else Vector3.ZERO

## Deliberate lay-back while preparing for an incoming ball: returns the rotation (axis,
## angle) that sets the head behind the hand along the ball's travel, let go as the ball
## nears. Zero when not preparing, no ball, or the ball is moving away.
func _prelag(head: Vector3, arm: Vector3) -> Vector4:
	if not _preparing: return Vector4.ZERO
	var ball: = _player.call("_get_ball_ref") as RigidBody3D if _player.has_method("_get_ball_ref") else null
	if ball == null or not is_instance_valid(ball): return Vector4.ZERO
	var vel: Vector3 = ball.linear_velocity
	var to_head: Vector3 = head - ball.get_global_transform_interpolated().origin
	if vel.dot(to_head) <= 0.0: return Vector4.ZERO
	var travel: = Vector3(vel.x, 0.0, vel.z)
	if travel.length_squared() < 0.01: return Vector4.ZERO
	var axis: Vector3 = arm.cross(travel.normalized())
	if axis.length_squared() < 1e-6: return Vector4.ZERO
	axis = axis.normalized()
	var amount: float = float(PRELAG_SHOT.get(_shot_type, PRELAG_UNKNOWN)) * (0.4 + 0.6 * _charge_latch)
	var hold: float = smoothstep(PRELAG_LET_GO_NEAR, PRELAG_LET_GO_FAR, to_head.length())
	return Vector4(axis.x, axis.y, axis.z, deg_to_rad(PRELAG_DEG) * amount * hold)

## 1 = full lag, 0 = true face. Only an incoming ball releases the lag, so the whip
## after contact still shows while the ball flies off.
func _release_weight(head: Vector3) -> float:
	var ball: = _player.call("_get_ball_ref") as RigidBody3D if _player.has_method("_get_ball_ref") else null
	if ball == null or not is_instance_valid(ball): return 1.0
	var to_head: Vector3 = head - ball.get_global_transform_interpolated().origin
	if ball.linear_velocity.dot(to_head) <= 0.0: return 1.0
	return smoothstep(RELEASE_NEAR, RELEASE_FAR, to_head.length())

## How loose the wrist is, 0 firm to 1 relaxed: shot charge and shot type of the
## current stroke (read only from the player), idle RELAX_IDLE between swings.
func _grip_relax(delta: float) -> float:
	var hitting: Object = _player.get("hitting")
	var human: Object = null
	var posture: Object = _player.get("posture")
	if posture != null: human = posture.get("human_contact")
	var is_ai: bool = bool(_player.get("is_ai"))
	var swinging: bool = false
	if hitting != null:
		swinging = bool(hitting.get("charge_visual_active")) or bool(hitting.get("is_in_follow_through")) \
			or bool(hitting.get("serving_visual_active"))
	var charge: float = 0.0
	var shot: = ""
	if is_ai:
		if bool(_player.get("ai_is_charging")):
			swinging = true
			charge = _num(_player.get("ai_charge_time"), 0.0) / AI_CHARGE_TIME
		# The AI plans shot type and charge before it starts charging.
		var brain: Object = _player.get("ai_brain")
		var plan: Variant = brain.get("_planned_shot") if brain != null else null
		var ctx: Variant = hitting.get("committed_motion_context") if hitting != null else null
		if plan is Dictionary and not plan.is_empty():
			charge = maxf(charge, _num(plan.get("charge"), 0.0))
			shot = str(plan.get("shot_type", ""))
		elif ctx is Dictionary and not ctx.is_empty():
			charge = maxf(charge, _num(ctx.get("charge"), 0.0))
			shot = str(ctx.get("shot_type", ""))
	elif human != null:
		if int(_num(human.get("phase"), -1.0)) >= 0: swinging = true
		charge = _num(human.get("charge_ratio"), 0.0)
		shot = str(human.get("_swing_shot_type")) if human.get("_swing_shot_type") != null else ""
	var preparing: bool = swinging and not (hitting != null and bool(hitting.get("is_in_follow_through")))
	# AI: a shot planned for this flight counts as preparing, before the charge starts.
	if is_ai and not swinging:
		var brain2: Object = _player.get("ai_brain")
		var ball2: Object = _player.call("_get_ball_ref") if _player.has_method("_get_ball_ref") else null
		var plan2: Variant = brain2.get("_planned_shot") if brain2 != null else null
		if ball2 != null and plan2 is Dictionary and not plan2.is_empty() \
				and _num(brain2.get("_planned_flight"), -1.0) == _num(ball2.get("flight_id"), -2.0):
			preparing = true
			_charge_latch = maxf(_charge_latch, clampf(charge, 0.0, 1.0))
			if shot != "": _shot_type = shot
	_swinging = swinging
	_preparing = preparing
	var target: float = RELAX_IDLE
	if swinging:
		_charge_latch = maxf(_charge_latch, clampf(charge, 0.0, 1.0))
		if shot != "": _shot_type = shot
		var factor: float = float(SHOT_RELAX.get(_shot_type, SHOT_RELAX_UNKNOWN))
		target = maxf(RELAX_IDLE, clampf((0.25 + 0.75 * _charge_latch) * factor, 0.0, 1.0))
	elif not preparing:
		_charge_latch = 0.0
		_shot_type = ""
	_relax = lerpf(_relax, target, 1.0 - exp(-0.693 * maxf(delta, 0.0) / RELAX_HALFLIFE))
	return _relax

static func _num(v: Variant, fallback: float) -> float:
	return float(v) if (v is float or v is int) else fallback

func _hide_original() -> void:
	# Layer 20, never 0: gameplay (player_surface_contacts.gd) only skips layer-0 meshes.
	for node in _paddle.find_children("*", "GeometryInstance3D", true, false):
		if node.layers != 0:
			node.layers = 1 << (CLASSIC_LAYER - 1)

# --- meshes and materials (shared per design) ---------------------------------

## Front face (+z), back face (-z, u mirrored so graphics read correctly), rim.
static func _build_head() -> ArrayMesh:
	# Every other outline point: half the triangles, same pixel silhouette (the gameplay paddle keeps the full outline).
	var full: PackedVector2Array = D.head_outline()
	var outline: = PackedVector2Array()
	for i in range(0, full.size(), 2): outline.append(full[i])
	var r: float = D.HEAD_RADIUS
	var t: float = D.HEAD_HALF_THICKNESS
	var centre: = Vector2(0, D.HEAD_CENTER_Y)
	var mesh: = ArrayMesh.new()
	for side in [1.0, -1.0]:
		var st: = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(outline.size()):
			var a: Vector2 = outline[i]
			var b: Vector2 = outline[(i + 1) % outline.size()]
			for p in ([centre, b, a] if side > 0.0 else [centre, a, b]):
				var u: float = (p.x + r) / (2.0 * r)
				st.set_normal(Vector3(0, 0, side))
				st.set_uv(Vector2(u if side > 0.0 else 1.0 - u, 1.0 - (p.y - D.HEAD_BOTTOM_Y) / D.HEAD_LENGTH))
				st.add_vertex(Vector3(p.x, p.y, side * t))
		mesh = st.commit(mesh)
	var rim: = SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(outline.size()):
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		var e: Vector2 = b - a
		var n: = Vector3(e.y, -e.x, 0).normalized()
		for p in [Vector3(a.x, a.y, t), Vector3(b.x, b.y, t), Vector3(b.x, b.y, -t),
				Vector3(a.x, a.y, t), Vector3(b.x, b.y, -t), Vector3(a.x, a.y, -t)]:
			rim.set_normal(n)
			rim.add_vertex(p)
	return rim.commit(mesh)

static func _materials_for(id: String) -> Dictionary:
	if _materials.has(id): return _materials[id]
	var d: Dictionary = designs().get(id, {})
	var face: = _material(Color(d.get("base", "#262626")), 0.75)
	face.albedo_color = Color.WHITE
	face.albedo_texture = _face_texture(d)
	face.cull_mode = BaseMaterial3D.CULL_DISABLED
	var grip: = _material(Color.WHITE, 0.9)
	grip.albedo_texture = _grip_texture(Color(d.get("grip", "#1a1a1a")), Color(d.get("seam", "#3a3a3a")))
	var mats: = {"face": face, "grip": grip,
		"edge": _material(Color(d.get("edge", "#121212")), 0.6),
		"cap": _material(Color(d.get("cap", "#222222")), 0.5)}
	_materials[id] = mats
	return mats

static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var m: = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return m

static func _face_texture(d: Dictionary) -> ImageTexture:
	var base: = Color(d.get("base", "#262626"))
	var alt: = Color(d.get("alt", "#3a3a3a"))
	var ink: = Color(d.get("ink", "#9a9a9a"))
	var edge: = Color(d.get("edge", "#121212"))
	var kind: = str(d.get("face", "flat"))
	var graphic: = str(d.get("graphic", "none"))
	var rng: = RandomNumberGenerator.new()
	rng.seed = hash(str(d.get("name", "")))   # own RNG: same texture every run
	var img: = Image.create(FACE_W, FACE_H, false, Image.FORMAT_RGBA8)
	var r: float = D.HEAD_RADIUS
	var spine: float = D.HEAD_SPINE_HALF
	for y in range(FACE_H):
		for x in range(FACE_W):
			var u: = (x + 0.5) / FACE_W
			var v: = (y + 0.5) / FACE_H
			var col: = _surface(kind, x, y, base, alt, rng)
			col = _graphic(graphic, x, y, u, v, col, ink, alt)
			# Edge guard wraps a few millimetres onto the face.
			var px: = (u * 2.0 - 1.0) * r
			var py: = (0.5 - v) * D.HEAD_LENGTH
			if Vector2(px, py - clampf(py, -spine, spine)).length() - r > -EDGE_WRAP: col = edge
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

static func _surface(kind: String, x: int, y: int, base: Color, alt: Color, rng: RandomNumberGenerator) -> Color:
	match kind:
		"carbon_twill": return alt if (x + y) % 4 < 2 else base
		"carbon_cross": return alt if (x / 2 + y / 2) % 2 == 0 else base
		"graphite": return base.lerp(alt, rng.randf() * 0.7)
		"fiberglass": return base.lerp(base.lightened(0.08), rng.randf())
		"wood":
			var grain: = sin(x * 1.05 + sin(y * 0.16) * 2.2)
			return alt if grain > 0.6 else base.lerp(alt, rng.randf() * 0.15)
	return base

static func _graphic(kind: String, x: int, y: int, u: float, v: float, col: Color, ink: Color, alt: Color) -> Color:
	match kind:
		"wordmark":
			if u > 0.28 and u < 0.72 and v > 0.80 and v < 0.84: return ink
		"slash":
			var s: = v + u * 0.3
			if s > 0.70 and s < 0.82: return ink
		"dots_band":
			if v > 0.36 and v < 0.43: return ink
			if x % 5 == 2 and y % 5 == 2: return alt
		"block":
			var outer: = u > 0.22 and u < 0.78 and v > 0.25 and v < 0.63
			var inner: = u > 0.27 and u < 0.73 and v > 0.285 and v < 0.595
			if outer and not inner: return ink
		"stamp":
			var d: = Vector2((u - 0.5) * D.WIDTH, (v - 0.78) * D.HEAD_LENGTH).length()
			if d > 0.018 and d < 0.023: return ink
		"sunset":
			if v > 0.66:
				var band: = clampi(int((v - 0.66) / 0.075), 0, 3)
				# One dithered row at each band boundary.
				if band > 0 and v - (0.66 + band * 0.075) < 1.0 / FACE_H and (x + y) % 2 == 0: band -= 1
				return SUNSET[band]
	return col

static func _grip_texture(grip: Color, seam: Color) -> ImageTexture:
	var img: = Image.create(GRIP_W, GRIP_H, false, Image.FORMAT_RGBA8)
	for y in range(GRIP_H):
		for x in range(GRIP_W):
			# Spiral wrap: one diagonal seam every 6 texels.
			img.set_pixel(x, y, seam if (x + y) % 6 == 0 else grip)
	return ImageTexture.create_from_image(img)
