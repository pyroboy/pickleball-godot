extends MeshInstance3D
class_name BallTrail
## Smooth ribbon trail for the ball.
##
## ARCHITECTURE:
##   - Attached as a direct child of the Game root (not the ball).
##     Game root transform is identity, so local space == world space and
##     we can write vertices directly in world coordinates — no top_level
##     hack, no inherited physics-body transforms to fight.
##   - game.gd calls setup(ball) to bind the ball reference.
##
## GEOMETRY:
##   - Ring buffer of recent ball world positions (MAX_POINTS).
##   - Every physics tick: push current position if ball is moving; drain
##     oldest when stationary so the trail fades away.
##   - ImmediateMesh TRIANGLE_STRIP forms a camera-facing ribbon.
##     For each point p:
##       forward = direction to next point (or previous at the head)
##       to_cam  = direction from p to the active camera
##       side    = normalize(forward × to_cam)
##     This makes the ribbon face the camera regardless of ball direction.
##
## LOOK:
##   - Width tapers from WIDTH_HEAD at the newest point to WIDTH_TAIL at
##     the oldest. Color fades yellow → orange with alpha to 0.
##   - Unshaded mix-blend so it reads on the bright court.
##   - Large custom_aabb to prevent frustum culling.

const MAX_POINTS: int = 8  # Mobile: reduced from 22
const WIDTH_HEAD: float = 0.10   # ball diameter ≈ 0.12m; trail slightly thinner
const WIDTH_TAIL: float = 0.01
const MIN_SPEED: float = 1.0
const COLOR_HEAD: Color = Color(1.0, 0.95, 0.35, 1.0)
const COLOR_TAIL: Color = Color(1.0, 0.45, 0.05, 0.0)

var _ball: RigidBody3D
var _points: PackedVector3Array = PackedVector3Array()
var _imesh: ImmediateMesh
var _material: StandardMaterial3D
var _debug_printed: bool = false

func setup(ball: RigidBody3D) -> void:
	_ball = ball

func _ready() -> void:
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
	print("[BallTrail] ready (ribbon)")

func _physics_process(_delta: float) -> void:
	if _ball == null:
		return
	if not _settings_allows_trail():
		if _points.size() > 0:
			_points.clear()
			_imesh.clear_surfaces()
		return

	var speed: float = _ball.linear_velocity.length()
	if speed > MIN_SPEED:
		# Use ring buffer pattern - overwrite oldest instead of remove
		if _points.size() >= MAX_POINTS:
			# Shift values manually (cheaper than remove_at for PackedVector3Array)
			for i in range(MAX_POINTS - 1):
				_points[i] = _points[i + 1]
			_points[MAX_POINTS - 1] = _ball.global_position
		else:
			_points.append(_ball.global_position)
	elif _points.size() > 0:
		_points.remove_at(0)

	_rebuild_mesh()

func _rebuild_mesh() -> void:
	_imesh.clear_surfaces()
	var n: int = _points.size()
	if n < 2:
		return

	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var cam_pos: Vector3 = cam.global_position

	if not _debug_printed:
		_debug_printed = true
		print("[BallTrail] first rebuild n=", n, " head=", _points[n - 1])

	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(n):
		var t: float = float(i) / float(n - 1)  # 0 at tail, 1 at head
		var width: float = lerpf(WIDTH_TAIL, WIDTH_HEAD, t)
		var col: Color = COLOR_TAIL.lerp(COLOR_HEAD, t)

		var p: Vector3 = _points[i]
		var forward: Vector3
		if i < n - 1:
			forward = _points[i + 1] - p
		else:
			forward = p - _points[i - 1]
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
