extends Node3D

const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const PaddleScene = preload("res://scenes/paddle.tscn")
const WINDUP: = Color("bd80ff")
const CONTACT: = Color("ffdc62")
const FINISH: = Color("58dfdb")
var sample_heads: Array[Vector3] = []

func rebuild(player, def: PostureDefinition, sampler: Callable = Callable()) -> void :
	for child in get_children():
		remove_child(child)
		child.queue_free()
	sample_heads.clear()
	var mesh: = ImmediateMesh.new()
	var line: = MeshInstance3D.new()
	line.mesh = mesh
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material: = _material(Color.WHITE, 1.0)
	material.vertex_color_use_as_albedo = true
	line.material_override = material
	add_child(line)
	for i in range(65):
		var t: float = i / 64.0
		var transform: Transform3D = Path.world_transform(player, (sampler.call(t) if sampler.is_valid() else Path.sample(def, t)))
		var head: Vector3 = transform.origin + transform.basis.y * PaddleSize.HEAD_CENTER_Y
		sample_heads.append(head)
	var has_motion: bool = false
	for i in range(64):
		if sample_heads[i].distance_squared_to(sample_heads[i + 1]) > 1e-08:
			has_motion = true
	if has_motion:
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(64):
			_add_curve_segment(mesh, to_local(sample_heads[i]), to_local(sample_heads[i + 1]), _color(i / 64.0), _color((i + 1) / 64.0))
		mesh.surface_end()

	for i in range(11 if has_motion else 1):
		var t: float = i / 10.0 if has_motion else 0.5
		var ghost: Node3D = PaddleScene.instantiate()
		for node_name in ["CollisionShape3D", "PaddleHitbox"]:
			var collision = ghost.get_node_or_null(node_name)
			if collision:
				ghost.remove_child(collision)
				collision.queue_free()
		ghost.set_script(null)
		var keyframe: bool = i in [0, 5, 10]
		_paint_meshes(ghost, _material(_color(t), 0.22 if keyframe else 0.055))
		add_child(ghost)
		ghost.global_transform = Path.world_transform(player, (sampler.call(t) if sampler.is_valid() else Path.sample(def, t)))

func _color(t: float) -> Color:
	return WINDUP.lerp(CONTACT, t * 2.0) if t <= 0.5 else CONTACT.lerp(FINISH, (t - 0.5) * 2.0)

func _add_curve_segment(mesh: ImmediateMesh, a: Vector3, b: Vector3, ca: Color, cb: Color) -> void :
	var tangent: Vector3 = b - a
	if tangent.length_squared() < 1e-08: return
	var side: Vector3 = tangent.normalized().cross(Vector3.UP)
	if side.length_squared() < 0.001: side = tangent.normalized().cross(Vector3.RIGHT)
	side = side.normalized() * 0.007
	var up: Vector3 = tangent.normalized().cross(side).normalized() * 0.007
	for face in range(6):
		var angle: float = TAU * face / 6.0
		var next: float = TAU * (face + 1) / 6.0
		var v0: Vector3 = side * cos(angle) + up * sin(angle)
		var v1: Vector3 = side * cos(next) + up * sin(next)
		for vertex in [[a + v0, ca], [b + v0, cb], [b + v1, cb], [a + v0, ca], [b + v1, cb], [a + v1, ca]]:
			mesh.surface_set_color(vertex[1])
			mesh.surface_add_vertex(vertex[0])

func _material(color: Color, alpha: float) -> StandardMaterial3D:
	var material: = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color, alpha)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _paint_meshes(node: Node, material: Material) -> void :
	if node is MeshInstance3D:
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_paint_meshes(child, material)
