extends MeshInstance3D
class_name BallTrail
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")


























const MAX_POINTS: int = 8
const WIDTH_HEAD: float = 0.06    # narrower than the ball (0.075 m): the ribbon never sticks out of it
const FADE_LENGTH: float = 0.8    # m behind the ball over which width and colour ramp
const WIDTH_TAIL: float = 0.01
const MIN_SPEED: float = 1.0
const COLOR_HEAD: Color = Color(1.0, 0.95, 0.35, 1.0)
const COLOR_TAIL: Color = Color(1.0, 0.45, 0.05, 0.0)

var _ball: RigidBody3D
var _points: PackedVector3Array = PackedVector3Array()
var _imesh: ImmediateMesh
var _material: StandardMaterial3D
var _debug_printed: bool = false
var _previous_position: Vector3 = Vector3.INF
var _previous_delta: float = 0.0

func setup(ball: RigidBody3D) -> void :
	_ball = ball
	if ball.has_signal("bounced") and not ball.bounced.is_connected(_on_bounced):
		ball.bounced.connect(_on_bounced)

## Restart the ribbon at the contact point: a trail through the bounce corner folds
## back on itself (its head is wider than the ball) and reads as a blob.
func _on_bounced(point: Vector3) -> void:
	_points = PackedVector3Array([point])

func _ready() -> void :
	name = "BallTrail"

	_imesh = ImmediateMesh.new()
	mesh = _imesh
	custom_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 10, 40))

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.vertex_color_use_as_albedo = true
	_material.disable_receive_shadows = true
	material_override = _material
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # rebuilt every frame in world space
	RenderingServer.frame_pre_draw.connect(_before_draw)
	if RuntimePolicy.developer_tools: print("[BallTrail] ready (ribbon)")

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

	var speed: float = _ball.linear_velocity.length()
	# Sharp turn (paddle hit, net, wall): restart from the turning point, same reason.
	var count: int = _points.size()
	if count >= 2 and (position - _points[count - 1]).dot(_points[count - 1] - _points[count - 2]) < 0.0:
		_points = PackedVector3Array([_points[count - 1]])
	if speed > MIN_SPEED:

		if _points.size() >= MAX_POINTS:

			for i in range(MAX_POINTS - 1):
				_points[i] = _points[i + 1]
			_points[MAX_POINTS - 1] = _ball.global_position
		else:
			_points.append(_ball.global_position)
	elif _points.size() > 0:
		_points.remove_at(0)
	# Drawn every frame in _process (ends at the interpolated ball), not here.

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
	_imesh.clear_surfaces()

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
	_imesh.clear_surfaces()
	if _points.size() < 2 or not is_instance_valid(_ball):
		return
	# History comes from 30 Hz physics ticks; the ball is drawn interpolated,
	# up to one tick behind the newest sample. Drop that sample and end the
	# ribbon exactly at the drawn ball, so trail and ball move together.
	var pts: PackedVector3Array = _points.slice(0, _points.size() - 1)
	pts.append(_ball.get_meta("render_origin", _ball.get_global_transform_interpolated().origin))   # ball_bounce_snap.gd
	var n: int = pts.size()
	if n < 2:
		return

	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var cam_pos: Vector3 = cam.global_position

	if not _debug_printed:
		_debug_printed = true
		if RuntimePolicy.developer_tools: print("[BallTrail] first rebuild n=", n, " head=", pts[n - 1])

	# Width and colour follow distance behind the ball, not the sample index, and a
	# short ribbon (just after a bounce or hit) stays thin instead of drawing a blob.
	var along: PackedFloat32Array = PackedFloat32Array(); along.resize(n)
	for i in range(1, n): along[i] = along[i - 1] + pts[i].distance_to(pts[i - 1])
	var total: float = along[n - 1]
	var grow: float = clampf(total / FADE_LENGTH, 0.0, 1.0)
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(n):
		var t: float = clampf(1.0 - (total - along[i]) / FADE_LENGTH, 0.0, 1.0) * grow
		var width: float = lerpf(WIDTH_TAIL, WIDTH_HEAD, t)
		var col: Color = COLOR_TAIL.lerp(COLOR_HEAD, t)

		var p: Vector3 = pts[i]
		var forward: Vector3
		if i < n - 1:
			forward = pts[i + 1] - p
		else:
			forward = p - pts[i - 1]
		if forward.length_squared() < 0.0001:
			forward = Vector3.FORWARD
		else:
			forward = forward.normalized()

		var to_cam: Vector3 = cam_pos - p
		if to_cam.length_squared() < 0.0001:
			to_cam = Vector3.UP
		to_cam = to_cam.normalized()

		var side: Vector3 = forward.cross(to_cam)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		else:
			side = side.normalized()

		var half: float = width * 0.5
		_imesh.surface_set_color(col)
		_imesh.surface_add_vertex(p + side * half)
		_imesh.surface_set_color(col)
		_imesh.surface_add_vertex(p - side * half)
	_imesh.surface_end()

func _settings_allows_trail() -> bool:
	var settings_node: Node = get_node_or_null("/root/Settings")
	if settings_node == null or not settings_node.has_method("get_value"):
		return true
	var density: int = int(settings_node.call("get_value", "video.particle_density", 2))
	return density > 0
