extends Node3D


## Ground shadows (visual only).
## Ball: a plain shadow-coloured oval straight under it, its height cue (never moved by the sun:
## players judge depth from it), smaller and lighter as it rises, drawn on top of every other
## shadow (render_priority).
## Players: no node here. Each player's card mesh draws itself a second time flattened onto the
## court along the sun (shaders/card_shadow.gdshader, the next_pass of the card material built
## by pixel_card_rig.gd via card_shadow_material / sync_card_sun below).
const Sun = preload("res://scripts/graphics/sun_light.gd")
const ShadowMask = preload("res://scripts/graphics/shadow_mask.gd")
const FLOOR_Y: = Ball.FLOOR_Y + 0.0045
## The player shadow shader (normal_match_visual_samples.gd reads this constant's path).
const ShaderSource = preload("res://shaders/card_shadow.gdshader")
const BallShaderSource = preload("res://shaders/ball_ground_shadow.gdshader")
# Matches the visible 16 x 40 m apron. The ball cue is also useful after an out.
const BALL_APRON_HALF_SIZE: = Vector2(8.0, 20.0)
const BALL_MIN_DIAMETER: = 0.10    # high in the air
const BALL_MAX_DIAMETER: = 0.16    # on the court: just wider than the drawn ball (0.1125 m)
const BALL_MIN_OPACITY: = 0.4
const BALL_MAX_OPACITY: = Sun.BALL_OPACITY
const BALL_FADE_HEIGHT: = 2.5      # metres above rest where it reaches its smallest / lightest
const BALL_SUN_STRETCH_MAX: = 2.2   # longest the ball's oval is drawn out along the light, over its width
const BALL_BLUR_SECONDS: = 1.0 / 40.0   # the ball shadow's exposure at blur strength 1
const BALL_BLUR_FROM_SPEED: = 3.0      # m/s over the court before its shadow blurs
const BALL_BLUR_MAX_M: = 0.3
const BALL_PRIORITY: = 20          # after the player and static shadows
## Player shadows: drawn first among transparent things (right after the ground), stencil value
## in card_shadow.gdshader, and how far above the court surface they lie.
const PLAYER_PRIORITY: = -20
const PLAYER_SHADOW_LIFT: = 0.01
var _targets: Array[Node3D] = []
var _blur_strength: float = -1.0
var _shadow_was := Vector3.INF
var _shadow_speed := Vector3.ZERO
var _shadows: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []

func setup(ball: Node3D, _left: Node3D = null, _right: Node3D = null, _roster: Array = []) -> void :
	name = "GroundShadows"
	_disconnect_ball_visibility()
	for shadow in _shadows: shadow.free()
	_shadows.clear()
	_materials.clear()
	_targets = [ball]
	var shadow: = MeshInstance3D.new()
	shadow.name = "BallShadow"
	var plane: = PlaneMesh.new()
	plane.size = Vector2.ONE
	shadow.mesh = plane
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material: = ShaderMaterial.new()
	material.shader = BallShaderSource
	material.render_priority = BALL_PRIORITY
	material.set_shader_parameter("apron_half_size", BALL_APRON_HALF_SIZE)
	material.set_shader_parameter("shadow_color", Sun.SHADOW_COLOR)
	shadow.material_override = material
	shadow.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved every frame
	add_child(shadow)
	_shadows.append(shadow)
	_materials.append(material)
	# Visibility can change during a paused editor or offscreen retrieval. These
	# signals prevent a stale sibling blob without making paused shadows process.
	if is_instance_valid(ball):
		ball.visibility_changed.connect(update_shadows)
		ball.tree_exiting.connect(_hide_ball_shadow)
	update_shadows()

func _disconnect_ball_visibility() -> void :
	if _targets.is_empty() or not is_instance_valid(_targets[0]): return
	var ball: Node3D = _targets[0]
	if ball.visibility_changed.is_connected(update_shadows):
		ball.visibility_changed.disconnect(update_shadows)
	if ball.tree_exiting.is_connected(_hide_ball_shadow):
		ball.tree_exiting.disconnect(_hide_ball_shadow)

func _hide_ball_shadow() -> void :
	if not _shadows.is_empty() and is_instance_valid(_shadows[0]): _shadows[0].hide()

func _exit_tree() -> void :
	_disconnect_ball_visibility()

func _process(_delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_process(_delta)
	PerfMonitor.record("proc.ground_shadows", Time.get_ticks_usec() - _pt)

func _perf_process(_delta: float) -> void:
	update_shadows()

## Ball cue: (diameter along x, diameter along z, opacity) for a height above rest.
static func cue_for_height(height: float, _ball: bool = true) -> Vector3:
	var lift: float = clampf(maxf(height, 0.0) / BALL_FADE_HEIGHT, 0.0, 1.0)
	var diameter: float = lerpf(BALL_MAX_DIAMETER, BALL_MIN_DIAMETER, lift)
	return Vector3(diameter, diameter, lerpf(BALL_MAX_OPACITY, BALL_MIN_OPACITY, lift))

func update_shadows() -> void :
	if _targets.is_empty(): return
	var target: Node3D = _targets[0]
	var shadow: MeshInstance3D = _shadows[0]
	if not is_instance_valid(target):
		shadow.visible = false
		return
	var pos: Vector3 = target.get_meta("render_origin", target.get_global_transform_interpolated().origin)   # drawn, not the 30 Hz tick
	shadow.visible = target.is_visible_in_tree() and pos.is_finite() and absf(pos.x) < BALL_APRON_HALF_SIZE.x and absf(pos.z) < BALL_APRON_HALF_SIZE.y
	if not shadow.visible: return
	var cue: Vector3 = cue_for_height(pos.y - (Ball.FLOOR_Y + Ball.BALL_RADIUS))
	# Cast by the sun like the players' shadows (user, 2026-11-25): the ball's place slid along
	# the light down to the court, and the round ball's shadow drawn out along the light as a
	# low sun does (an oval 1 / sin(sun height) long). It still shrinks and lightens with
	# height, and it meets the ball when the ball is on the court.
	var light: Vector3 = -Sun.to_sun()
	var drop: float = maxf(pos.y - Ball.BALL_RADIUS - FLOOR_Y, 0.0) / maxf(-light.y, 0.001)
	var along := Vector3(light.x, 0.0, light.z)
	var reach: float = along.length()
	along = along / reach if reach > 0.001 else Vector3.FORWARD
	var at := Vector3(pos.x + light.x * drop, FLOOR_Y, pos.z + light.z * drop)
	var stretch: float = minf(1.0 / maxf(-light.y, 0.001), BALL_SUN_STRETCH_MAX)
	var shape := Basis(along.cross(Vector3.UP) * cue.x, Vector3.UP, along * cue.y * stretch)
	var opacity: float = cue.z
	# Motion blur: the shadow of a fast ball is drawn out along the way the shadow itself moves
	# over the court, and lightened as the same shadow is spread over more ground. Shrinks with
	# slow motion like the ball's own blur; off with Settings > Video > Motion blur on the ball.
	var frame: int = Engine.get_process_frames()
	if frame % 30 == 0 or _blur_strength < 0.0:
		var settings: Node = get_node_or_null("/root/Settings")
		_blur_strength = (float(settings.call("get_value", "video.motion_smear", 1.0)) if bool(settings.call("get_value", "video.blur_ball", true)) else 0.0) if settings != null and settings.has_method("get_value") else 1.0
	var dt: float = get_process_delta_time()
	if get_tree().paused: pass   # photo mode / pause: the shadow keeps the blur it had
	elif _shadow_was.is_finite() and dt > 0.0 and at.distance_to(_shadow_was) < 2.0: _shadow_speed = _shadow_speed.lerp((at - _shadow_was) / dt, 0.6)
	else: _shadow_speed = Vector3.ZERO
	_shadow_was = at
	var speed: float = _shadow_speed.length()
	if _blur_strength > 0.0 and speed > BALL_BLUR_FROM_SPEED:
		var extra: float = minf(speed * BALL_BLUR_SECONDS * _blur_strength * clampf(Engine.time_scale, 0.0, 1.0), BALL_BLUR_MAX_M)
		var way: Vector3 = _shadow_speed / speed
		var longer: float = (cue.x + extra) / cue.x - 1.0
		shape = Basis(shape.x + way * way.dot(shape.x) * longer, Vector3.UP, shape.z + way * way.dot(shape.z) * longer)
		at -= way * extra * 0.5   # it trails behind where the shadow is now
		opacity *= sqrt(cue.x / (cue.x + extra))
	shadow.global_transform = Transform3D(shape, at)
	sync_mesh_shadow()
	_materials[0].set_shader_parameter("opacity", opacity)

# ------------------------------------------------- player shadows (pixel_card_rig.gd)

## The shadow pass for one player's card material (`card_material.next_pass`): same mesh,
## same atlas (the near one; the far tier's UVs are identical), flattened onto the court.
## How strongly the lens blur is on right now (scripts/solo_aim_focus.gd: serve aim and slow
## motion; 0 = off). Player shadows are drawn after the lens, so they soften themselves by it.
static var lens_soften: float = 0.0
const SoftShaderSource = preload("res://shaders/card_shadow_soft.gdshader")

## Sun shadow for solid 3D meshes (the paddle): one material for all of them, added as the next
## pass of the mesh's own material (shaders/mesh_shadow.gdshader). sync_mesh_shadow() keeps its
## sun direction and static shadow mask current (one int compare each per frame).
const MeshShadowSource = preload("res://shaders/mesh_shadow.gdshader")
static var _mesh_shadow: ShaderMaterial = null
static var _mesh_shadow_seen := Vector2i(-1, -1)

static func mesh_shadow_material() -> ShaderMaterial:
	if _mesh_shadow == null:
		_mesh_shadow = ShaderMaterial.new()
		_mesh_shadow.shader = MeshShadowSource
		_mesh_shadow.render_priority = PLAYER_PRIORITY
		_mesh_shadow.set_shader_parameter("ground_y", Ball.FLOOR_Y)
		_mesh_shadow.set_shader_parameter("shadow_y", Ball.FLOOR_Y + PLAYER_SHADOW_LIFT)
		_mesh_shadow.set_shader_parameter("shadow_color", Sun.SHADOW_COLOR)
		_mesh_shadow.set_shader_parameter("opacity", Sun.SHADOW_OPACITY)
		_mesh_shadow_seen = Vector2i(-1, -1)
		sync_mesh_shadow()
	return _mesh_shadow

static func sync_mesh_shadow() -> void:
	if _mesh_shadow == null: return
	if _mesh_shadow_seen.x != Sun.version:
		_mesh_shadow.set_shader_parameter("light_dir", -Sun.to_sun())
	if _mesh_shadow_seen.y != ShadowMask.version:
		var tex: Texture2D = ShadowMask.texture
		var r: Rect2 = ShadowMask.rect
		var ok: bool = tex != null and r.size.x > 0.0 and r.size.y > 0.0
		_mesh_shadow.set_shader_parameter("has_mask", ok)
		_mesh_shadow.set_shader_parameter("shadow_mask", tex if ok else null)
		_mesh_shadow.set_shader_parameter("mask_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y) if ok else Vector4(0, 0, 1, 1))
	_mesh_shadow_seen = Vector2i(Sun.version, ShadowMask.version)

static func card_shadow_material(atlas: Texture2D, soft_rim: bool = false) -> ShaderMaterial:
	var m: = ShaderMaterial.new()
	m.shader = SoftShaderSource if soft_rim else ShaderSource
	m.render_priority = PLAYER_PRIORITY + (1 if soft_rim else 0)   # rims after every solid shadow
	m.set_shader_parameter("atlas", atlas)
	m.set_shader_parameter("ground_y", Ball.FLOOR_Y)
	m.set_shader_parameter("shadow_y", Ball.FLOOR_Y + PLAYER_SHADOW_LIFT)
	m.set_shader_parameter("shadow_color", Sun.SHADOW_COLOR)
	m.set_shader_parameter("opacity", Sun.SHADOW_OPACITY)
	return m

## Per frame, per player: one int compare each for the sun and the static shadow mask; the
## materials are only touched when one of them moved. Returns the versions now applied
## (start from Vector2i(-1, -1)).
static func sync_card_sun(card_mat: ShaderMaterial, shadow_mat: ShaderMaterial, seen: Vector2i) -> Vector2i:
	if seen.x != Sun.version:
		card_mat.set_shader_parameter("to_sun", Sun.to_sun())
		shadow_mat.set_shader_parameter("light_dir", -Sun.to_sun())
	if seen.y != ShadowMask.version:
		var tex: Texture2D = ShadowMask.texture
		var r: Rect2 = ShadowMask.rect
		var ok: bool = tex != null and r.size.x > 0.0 and r.size.y > 0.0
		shadow_mat.set_shader_parameter("has_mask", ok)
		shadow_mat.set_shader_parameter("shadow_mask", tex if ok else null)
		shadow_mat.set_shader_parameter("mask_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y) if ok else Vector4(0, 0, 1, 1))
	return Vector2i(Sun.version, ShadowMask.version)
