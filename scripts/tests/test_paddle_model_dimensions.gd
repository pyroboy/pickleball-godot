extends SceneTree

const D = preload("res://scripts/paddle_dimensions.gd")
const PaddleScene = preload("res://scenes/paddle.tscn")
const Model = preload("res://scripts/paddle_model.gd")
var checks: = 0
var failures: Array[String] = []

func _initialize() -> void :
	call_deferred("run")

func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(message)

func run() -> void :
	var first = PaddleScene.instantiate()
	var second = PaddleScene.instantiate()
	root.add_child(first)
	root.add_child(second)
	second.position.x = 3.0
	await physics_frame
	await physics_frame
	var head: MeshInstance3D = first.get_node("Head")
	var handle: MeshInstance3D = first.get_node("Handle")
	var head_bounds: AABB = head.transform * head.mesh.get_aabb()
	var handle_bounds: AABB = handle.transform * handle.mesh.get_aabb()
	var bounds: AABB = head_bounds.merge(handle_bounds)
	check(absf(bounds.size.y - 16.5 * 0.0254) < 1e-05, "actual overall length is manufacturer16.5in")
	check(absf(bounds.size.x - 7.5 * 0.0254) < 1e-05, "actual maximum width is manufacturer7.5in")
	check(absf(head_bounds.size.z - 0.016) < 1e-05, "actual blade is16mm thick")
	check(absf(handle_bounds.size.y - 5.5 * 0.0254) < 1e-05, "actual grip length is5.5in")
	check(absf(handle.mesh.top_radius * TAU - 4.25 * 0.0254) < 1e-05, "actual circular handle circumference is4.25in")
	check(bounds.size.y <= 0.4318 + 1e-05 and bounds.size.x + bounds.size.y <= 0.6096 + 1e-05, "actual envelope meets published equipment size limits")
	var head_shape: ConvexPolygonShape3D = first.get_node("CollisionShape3D").shape
	var handle_shape: CylinderShape3D = first.get_node("HandleCollision").shape
	var arrays: Array = head.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for point in head_shape.points:
		var nearest: = INF
		for vertex in vertices: nearest = minf(nearest, point.distance_to(head.transform * vertex))
		check(nearest < 1e-06, "every physical hull vertex is a rendered blade vertex")
	for offset in range(0, indices.size(), 3):
		var a: int = indices[offset]
		var b: int = indices[offset + 1]
		var c: int = indices[offset + 2]
		var winding: Vector3 = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).normalized()
		check(winding.dot(normals[a]) < - 0.999, "render triangles use consistent clockwise outward winding")
	check(absf(handle_shape.radius - handle.mesh.top_radius) < 1e-06 and absf(handle_shape.height - handle.mesh.height) < 1e-06, "physical handle matches rendered grip")
	check(first.get_node("Head").mesh == second.get_node("Head").mesh, "athletes share cached head mesh")
	check(first.get_node("CollisionShape3D").shape == second.get_node("CollisionShape3D").shape, "athletes share immutable collision shape")
	var space: PhysicsDirectSpaceState3D = first.get_world_3d().direct_space_state
	for row in [{"point": Vector3(0, D.HEAD_CENTER_Y, 0), "hit": true}, {"point": Vector3(0, 0.54, 0), "hit": false}, {"point": Vector3(0.12, D.HEAD_CENTER_Y, 0), "hit": false}, {"point": Vector3(0, D.HANDLE_CENTER_Y, 0), "hit": true}]:
		var point: Vector3 = row.point
		var query: = PhysicsRayQueryParameters3D.create(point + Vector3(0, 0, 0.3), point - Vector3(0, 0, 0.3), 4)
		var hit: Dictionary = space.intersect_ray(query)
		check(( not hit.is_empty()) == row.hit, "real physics ray rejects oversized old envelope and hits current surfaces")
	var build_count: int = Model.mesh_build_count
	for frame in range(8): await process_frame
	check(Model.mesh_build_count == build_count, "settled paddle does not rebuild geometry")
	first.queue_free()
	second.queue_free()
	await process_frame
	await process_frame
	for failure in failures: push_error(failure)
	print("PADDLE ACTUAL DIMENSIONS ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
