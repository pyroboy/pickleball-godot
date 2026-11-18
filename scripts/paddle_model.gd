extends StaticBody3D


const D = preload("res://scripts/paddle_dimensions.gd")
static var _head_mesh: ArrayMesh
static var _head_shape: ConvexPolygonShape3D
static var _handle_mesh: CylinderMesh
static var _handle_shape: CylinderShape3D
static var mesh_build_count: = 0

func _ready() -> void :
	if _head_mesh == null:
		_head_mesh = _build_head()
		_head_shape = ConvexPolygonShape3D.new()
		_head_shape.points = D.head_hull_points()
		_head_shape.margin = 0.001
		_handle_mesh = CylinderMesh.new()
		_handle_mesh.top_radius = D.HANDLE_RADIUS
		_handle_mesh.bottom_radius = D.HANDLE_RADIUS
		_handle_mesh.height = D.HANDLE_LENGTH
		_handle_mesh.radial_segments = 24
		_handle_shape = CylinderShape3D.new()
		_handle_shape.radius = D.HANDLE_RADIUS
		_handle_shape.height = D.HANDLE_LENGTH
		_handle_shape.margin = 0.001
		mesh_build_count += 2
	$Head.mesh = _head_mesh
	$Head.position = D.HEAD_OFFSET
	$Handle.mesh = _handle_mesh
	$Handle.position = Vector3(0, D.HANDLE_CENTER_Y, 0)
	_apply_shape("CollisionShape3D", _head_shape, Vector3.ZERO)
	_apply_shape("HandleCollision", _handle_shape, Vector3(0, D.HANDLE_CENTER_Y, 0))


	_apply_shape("PaddleHitbox/CollisionShape3D", _head_shape, Vector3.ZERO)
	_apply_shape("PaddleHitbox/HandleCollision", _handle_shape, Vector3(0, D.HANDLE_CENTER_Y, 0))

func _apply_shape(path: NodePath, shape: Shape3D, origin: Vector3) -> void :

	var node: = get_node_or_null(path) as CollisionShape3D
	if node != null and not node.is_queued_for_deletion():
		node.shape = shape
		node.position = origin

static func _build_head() -> ArrayMesh:
	var surface: = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline: PackedVector2Array = D.head_outline()
	for index in range(outline.size()):
		var following: int = (index + 1) % outline.size()
		var a: Vector2 = outline[index] - Vector2(0, D.HEAD_CENTER_Y)
		var b: Vector2 = outline[following] - Vector2(0, D.HEAD_CENTER_Y)
		var af: = Vector3(a.x, a.y, D.HEAD_HALF_THICKNESS)
		var bf: = Vector3(b.x, b.y, D.HEAD_HALF_THICKNESS)
		var ab: = Vector3(a.x, a.y, - D.HEAD_HALF_THICKNESS)
		var bb: = Vector3(b.x, b.y, - D.HEAD_HALF_THICKNESS)
		_triangle(surface, Vector3(0, 0, D.HEAD_HALF_THICKNESS), bf, af, Vector3.BACK)
		_triangle(surface, Vector3(0, 0, - D.HEAD_HALF_THICKNESS), ab, bb, Vector3.FORWARD)
		var edge: Vector2 = b - a
		var normal: = Vector3(edge.y, - edge.x, 0).normalized()
		_triangle(surface, af, bf, bb, normal)
		_triangle(surface, af, bb, ab, normal)
	surface.index()
	return surface.commit()

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void :
	surface.set_normal(normal)
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
