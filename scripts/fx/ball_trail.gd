extends MeshInstance3D
class_name BallTrail
## Short speed streak behind a fast ball (visual only). One fixed tapered quad, placed
## every frame from the drawn (interpolated) ball back along its recent path: about two
## drawn-ball diameters long (5-12 render pixels), mostly hidden behind the ball, a
## darker tint of the ball colour fading to clear at the tail. Plain alpha blend, no glow.
## Shown only above TRAIL_SPEED_FROM, at full strength from TRAIL_SPEED_FULL.
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")
const PixelPost = preload("res://scripts/graphics/pixel_post.gd")

const MAX_POINTS: int = 4          # 30 Hz path samples; the streak never needs more
const MIN_SPEED: float = 1.0       # below this the path history drains
const TRAIL_SPEED_FROM: float = 7.0
const TRAIL_SPEED_FULL: float = 12.0
const LENGTH_BALLS: float = 2.0    # streak length in drawn-ball diameters (from the ball centre)
const LENGTH_MIN_PIXELS: float = 5.0
const LENGTH_MAX_PIXELS: float = 12.0
const WIDTH_BALLS: float = 0.6     # head width in drawn-ball diameters
const WIDTH_MIN_PIXELS: float = 1.5
const TAIL_WIDTH: float = 0.35     # tail width / head width
const HEAD_ALPHA: float = 0.9    # at the ball centre: ~0.6 where the streak leaves the outline
const BALL_MIN_PIXELS: float = 3.0 # shaders/ball_shape.gdshaderinc min_pixels
const OUTLINE_PIXELS: float = 1.0  # shaders/ball_shape.gdshaderinc outline_pixels
# Ball mid tone (Ball.BALL_MID x gain 2.2) darkened to 85 %: the ball stays the brightest.
const TINT: float = 0.85

var _ball: RigidBody3D
var _points: PackedVector3Array = PackedVector3Array()
var _material: StandardMaterial3D
var _previous_position: Vector3 = Vector3.INF
var _previous_delta: float = 0.0

func setup(ball: RigidBody3D) -> void :
	_ball = ball
	if ball.has_signal("bounced") and not ball.bounced.is_connected(_on_bounced):
		ball.bounced.connect(_on_bounced)

## Restart the path at the contact point: a streak through the bounce corner would
## point the wrong way.
func _on_bounced(point: Vector3) -> void:
	_points.clear()
	_points.append(point)

func _ready() -> void :
	name = "BallTrail"
	# Unit streak along +x (tail at -0.5, head at +0.5), width along y, tapered and
	# fading toward the tail. Built once; each frame only moves it.
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var t: float = TAIL_WIDTH * 0.5
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, -t, 0), Vector3(0.5, -0.5, 0), Vector3(0.5, 0.5, 0), Vector3(-0.5, t, 0)])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var quad: = ArrayMesh.new()
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.vertex_color_use_as_albedo = true
	_material.disable_receive_shadows = true
	_material.disable_fog = true
	var c: Color = Ball.BALL_MID * (Ball.VISUAL_GAIN * TINT)
	_material.albedo_color = Color(c.r, c.g, c.b, HEAD_ALPHA)
	material_override = _material
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # placed every frame in world space
	visible = false
	RenderingServer.frame_pre_draw.connect(_before_draw)
	if RuntimePolicy.developer_tools: print("[BallTrail] ready (streak)")

func _physics_process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_physics_process(delta)
	PerfMonitor.record("ball_trail.physics", Time.get_ticks_usec() - _pt)

func _perf_physics_process(delta: float) -> void:
	if _ball == null:
		return
	var position: Vector3 = _ball.global_position
	if _is_discontinuous(position, delta):
		_clear_history()
	_previous_position = position
	_previous_delta = maxf(delta, 0.0)
	if not _settings_allows_trail():
		_clear_history()
		return

	# Sharp turn (paddle hit, net, wall): restart from the turning point, same reason.
	var count: int = _points.size()
	if count >= 2 and (position - _points[count - 1]).dot(_points[count - 1] - _points[count - 2]) < 0.0:
		var turn: Vector3 = _points[count - 1]
		_points.clear()
		_points.append(turn)
	if _ball.linear_velocity.length() > MIN_SPEED:
		if _points.size() >= MAX_POINTS:
			for i in range(MAX_POINTS - 1):
				_points[i] = _points[i + 1]
			_points[MAX_POINTS - 1] = position
		else:
			_points.append(position)
	elif _points.size() > 0:
		_points.remove_at(0)
	# Placed every frame in _process (ends at the interpolated ball), not here.

func _process(_delta: float) -> void:
	_rebuild_mesh()

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_before_draw):
		RenderingServer.frame_pre_draw.disconnect(_before_draw)

func reset() -> void:
	_clear_history()
	_previous_position = Vector3.INF
	_previous_delta = 0.0

func _clear_history() -> void:
	_points.clear()
	visible = false

func _is_discontinuous(position: Vector3, delta: float) -> bool:
	# Sampled displacement can belong to the previous tick when slow motion
	# or the physics rate changes. Allow two of the larger adjacent ticks
	# plus a ball diameter for collision correction.
	var limit: float = Ball.MAX_SPEED * maxf(maxf(delta, _previous_delta), 0.0) * 2.0 + Ball.BALL_RADIUS * 2.0
	return _previous_position.is_finite() and position.distance_to(_previous_position) > limit

func _before_draw() -> void:
	# A menu can reset/feed after the last physics callback. Clear stale
	# geometry before rendering that frame; do not append or move the ball.
	if _points.is_empty(): return
	if not is_instance_valid(_ball) or not _settings_allows_trail() or _is_discontinuous(_ball.global_position, get_physics_process_delta_time()):
		_clear_history()

func _rebuild_mesh() -> void :
	visible = _place()

## Places the streak for this frame; false when there is nothing to show.
func _place() -> bool:
	if _points.size() < 2 or not is_instance_valid(_ball):
		return false
	var strength: float = clampf((_ball.linear_velocity.length() - TRAIL_SPEED_FROM) / (TRAIL_SPEED_FULL - TRAIL_SPEED_FROM), 0.0, 1.0)
	if strength <= 0.0:
		return false
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return false
	# The drawn ball (ball_bounce_snap.gd), not the 30 Hz tick.
	var head: Vector3 = _ball.get_meta("render_origin", _ball.get_global_transform_interpolated().origin)
	var cam_xf: Transform3D = cam.get_camera_transform()
	var depth: float = maxf((head - cam_xf.origin).dot(-cam_xf.basis.z), 0.05)
	var px_per_m: float = absf(cam.get_camera_projection().y.y) * float(get_window().size.y) * PixelPost.scale_in_use * 0.5 / depth
	var ball_radius: float = Ball.BALL_RADIUS * Ball.VISUAL_SCALE
	var ball_px: float = maxf(2.0 * ball_radius * px_per_m, BALL_MIN_PIXELS)
	var length_m: float = clampf(ball_px * LENGTH_BALLS, LENGTH_MIN_PIXELS, LENGTH_MAX_PIXELS) * strength / px_per_m
	var width_m: float = maxf(ball_px * WIDTH_BALLS, WIDTH_MIN_PIXELS) / px_per_m

	# Walk back from the drawn ball along the path. The newest sample is skipped: the
	# drawn ball is interpolated up to one tick behind it.
	var tail: Vector3 = head
	var remaining: float = length_m
	var i: int = _points.size() - 2
	while i >= 0 and remaining > 0.0:
		var p: Vector3 = _points[i]
		var seg: float = tail.distance_to(p)
		if seg >= remaining:
			tail = tail.lerp(p, remaining / seg)
			remaining = 0.0
		else:
			remaining -= seg
			tail = p
		i -= 1
	var axis: Vector3 = head - tail
	if axis.length_squared() < 1e-8:
		return false
	var to_cam: Vector3 = cam_xf.origin - head
	var side: Vector3 = axis.cross(to_cam)
	if side.length_squared() < 1e-10:
		return false   # flying straight at the camera: nothing to streak
	to_cam = to_cam.normalized()
	side = side.normalized()
	# Set back behind the drawn ball and its outline hull (radius in pixels + the 1 px
	# outline), so both cover the head end.
	var centre: Vector3 = (head + tail) * 0.5 - to_cam * ((ball_px * 0.5 + OUTLINE_PIXELS + 0.5) / px_per_m)
	global_transform = Transform3D(Basis(axis, side * width_m, axis.normalized().cross(side)), centre)
	_material.albedo_color.a = HEAD_ALPHA * strength
	return true

func _settings_allows_trail() -> bool:
	var settings_node: Node = get_node_or_null("/root/Settings")
	if settings_node == null or not settings_node.has_method("get_value"):
		return true
	var density: int = int(settings_node.call("get_value", "video.particle_density", 2))
	return density > 0
