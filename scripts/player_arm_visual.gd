extends RefCounted



static var _cache: Dictionary = {}
static var mesh_build_count: = 0
const SIDES: = 12
const JOIN_FROM_ELBOW: = 0.075
const BRIDGE_META: = &"arm_elbow_bridge"

class ElbowBridge extends RefCounted:
	var upper: MeshInstance3D
	var fore: MeshInstance3D
	var skeleton: Skeleton3D
	var elbow_local: = Vector3.ZERO
	var fore_half: = 0.175
	var last_relative: = Transform3D.IDENTITY
	var initialized: = false
	var bone_pose_write_count: = 0
	var pose_version: = 0
	var sampled_version: = -1
	var sampled_vertices: = PackedVector3Array()
	var _triangles: = PackedVector3Array()
	var _points: = PackedVector3Array()
	var palette: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY, Transform3D.IDENTITY]
	func update() -> void :
		var relative: Transform3D = upper.global_transform.affine_inverse() * fore.global_transform
		if initialized and relative.is_equal_approx(last_relative): return


		var rotation: Basis = relative.basis.orthonormalized()
		var elbow: Vector3 = relative * Vector3(0, - fore_half, 0)
		var halfway: = Basis(Quaternion.IDENTITY.slerp(rotation.get_rotation_quaternion(), 0.5))
		var rest_inverse: = Transform3D(Basis.IDENTITY, - elbow_local)
		var middle_pose: = Transform3D(halfway, elbow)
		var fore_pose: = Transform3D(rotation, elbow)
		skeleton.set_bone_pose(1, middle_pose)
		skeleton.set_bone_pose(2, fore_pose)
		palette[1] = middle_pose * rest_inverse
		palette[2] = fore_pose * rest_inverse
		last_relative = relative;initialized = true
		bone_pose_write_count += 2;pose_version += 1
	func vertices() -> PackedVector3Array:
		update()
		if sampled_version == pose_version: return sampled_vertices
		var arrays: Array = upper.mesh.surface_get_arrays(0)
		var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		sampled_vertices.resize(source.size())
		for index in range(source.size()):
			var point: = Vector3.ZERO
			for slot in range(4):
				point += (palette[bones[index * 4 + slot]] * source[index]) * weights[index * 4 + slot]
			sampled_vertices[index] = point
		_triangles = PackedVector3Array();_points = PackedVector3Array(sampled_vertices)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index in indices: _triangles.append(sampled_vertices[index])
		for index in range(0, _triangles.size(), 3):
			var a: Vector3 = _triangles[index]; var b: Vector3 = _triangles[index + 1]; var c: Vector3 = _triangles[index + 2]
			_points.append((a + b + c) / 3.0);_points.append((a + b) * 0.5);_points.append((a + c) * 0.5);_points.append((b + c) * 0.5)
		sampled_version = pose_version
		return sampled_vertices
	func triangles() -> PackedVector3Array:
		vertices();return _triangles
	func points() -> PackedVector3Array:
		vertices();return _points

static func apply(player, jersey: Color, skin: Color, material: Material) -> void :
	for arm in [player.right_arm_node, player.left_arm_node]:
		for part in [0, 1]:
			var length: float = arm.upper_arm_length if part == 0 else arm.forearm_length
			var key: = "%d/%.5f/%s/%s" % [part, length, jersey.to_html() if part == 0 else "skin", skin.to_html()]
			if not _cache.has(key):
				_cache[key] = _build(length, part == 0, jersey, skin)
				mesh_build_count += 1
			var node: MeshInstance3D = arm.upper_mesh if part == 0 else arm.fore_mesh
			node.mesh = _cache[key]
			node.material_override = material
			node.set_meta("rounded_arm_surface", true)
		if not arm.has_meta(BRIDGE_META):
			var bridge: = ElbowBridge.new()
			bridge.upper = arm.upper_mesh;bridge.fore = arm.fore_mesh
			bridge.elbow_local = Vector3(0, arm.upper_arm_length * 0.5, 0)
			bridge.fore_half = arm.forearm_length * 0.5
			bridge.skeleton = Skeleton3D.new();bridge.skeleton.name = "ElbowSurfaceSkeleton"
			bridge.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
			bridge.upper.add_child(bridge.skeleton)
			var skin_resource: = Skin.new()
			for index in range(3):
				bridge.skeleton.add_bone(["Upper", "ElbowBisector", "Forearm"][index])
				var rest: = Transform3D.IDENTITY if index == 0 else Transform3D(Basis.IDENTITY, bridge.elbow_local)
				bridge.skeleton.set_bone_rest(index, rest)
				bridge.skeleton.set_bone_pose(index, rest)
				skin_resource.add_bind(index, rest.affine_inverse())
			bridge.upper.skin = skin_resource
			bridge.upper.skeleton = NodePath("ElbowSurfaceSkeleton")
			bridge.upper.custom_aabb = AABB(Vector3( - 0.45, - 0.25, - 0.45), Vector3(0.9, 0.9, 0.9))
			bridge.upper.set_meta(BRIDGE_META, bridge)
			arm.set_meta(BRIDGE_META, bridge)
		update_arm(arm)

static func update_arm(arm) -> void :
	if arm.has_meta(BRIDGE_META): arm.get_meta(BRIDGE_META).update()

static func posed_triangles(mesh: MeshInstance3D) -> PackedVector3Array:
	if mesh.has_meta(BRIDGE_META): return mesh.get_meta(BRIDGE_META).triangles()
	return mesh.mesh.get_faces()

static func _profiles(length: float, upper: bool) -> Dictionary:
	var half: = length * 0.5
	var rings: Array[Vector3]
	var weights: Array[Vector3]
	if upper:
		rings = [Vector3(0.006, - half - 0.028, 0.006), Vector3(0.04, - half - 0.01, 0.038), 
			Vector3(0.058, - half + 0.024, 0.056), Vector3(0.056, - half + 0.075, 0.054), 
			Vector3(0.049, - 0.012, 0.047), Vector3(0.04, 0.001, 0.04), Vector3(0.039, half - 0.09, 0.039), 
			Vector3(0.036, half - 0.045, 0.036), Vector3(0.034, half, 0.034), 
			Vector3(0.037, half + 0.045, 0.037), Vector3(0.037, half + JOIN_FROM_ELBOW, 0.037), 

			Vector3(0.031, half + length * 0.5 + 0.018, 0.032)]
		weights = [Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, 
			Vector3(0.5, 0.5, 0), Vector3.UP, Vector3(0, 0.5, 0.5), Vector3(0, 0, 1), Vector3(0, 0, 1)]
	else:
		rings = [Vector3(0.037, - half + 0.045, 0.037), 
			Vector3(0.037, - half + JOIN_FROM_ELBOW, 0.037), Vector3(0.031, 0.018, 0.032), Vector3(0.023, half - 0.035, 0.024), 
			Vector3(0.013, half - 0.005, 0.014), Vector3(0.004, half + 0.006, 0.004)]
	return {"rings": rings, "weights": weights, "first": 0 if upper else 1, "last": rings.size() - 2 if upper else rings.size() - 1}

static func _build(length: float, upper: bool, jersey: Color, skin: Color) -> ArrayMesh:
	var profile: = _profiles(length, upper)
	var rings: Array[Vector3] = profile.rings
	var surface: = SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(profile.first, profile.last):
		for side in range(SIDES):
			var next: = (side + 1) % SIDES
			for pair in [[row, side], [row + 1, next], [row + 1, side], [row, side], [row, next], [row + 1, next]]:
				_vertex(surface, rings, profile.weights, upper, pair[0], pair[1], jersey if upper and pair[0] < 5 else skin)


	var cap: int = profile.first if upper else profile.last
	for side in range(SIDES):
		var next: = (side + 1) % SIDES
		var normal: = Vector3.DOWN if upper else Vector3.UP
		for point in [Vector3(0, rings[cap].y, 0), _point(rings[cap], next if upper else side), _point(rings[cap], side if upper else next)]:
			surface.set_normal(normal);surface.set_color(jersey if upper else skin)
			if upper: surface.set_bones(PackedInt32Array([0, 1, 2, 0]));surface.set_weights(PackedFloat32Array([1, 0, 0, 0]))
			surface.add_vertex(point)
	surface.index()
	return surface.commit()

static func _normal(rings: Array[Vector3], row: int, side: int) -> Vector3:
	var before: Vector3 = rings[maxi(0, row - 1)]; var after: Vector3 = rings[mini(rings.size() - 1, row + 1)]
	var slope: Vector3 = (after - before) / maxf(after.y - before.y, 1e-06)
	var a: = TAU * side / SIDES
	var radial: = Vector3(cos(a) / rings[row].x, 0, sin(a) / rings[row].z)
	radial.y = - (cos(a) * cos(a) * slope.x / rings[row].x + sin(a) * sin(a) * slope.z / rings[row].z)
	return radial.normalized()

static func _vertex(surface: SurfaceTool, rings: Array[Vector3], weights: Array[Vector3], upper: bool, row: int, side: int, color: Color) -> void :
	surface.set_normal(_normal(rings, row, side));surface.set_color(color)
	if upper:
		var w: Vector3 = weights[row]
		surface.set_bones(PackedInt32Array([0, 1, 2, 0]));surface.set_weights(PackedFloat32Array([w.x, w.y, w.z, 0]))
	surface.add_vertex(_point(rings[row], side))

static func _point(ring: Vector3, side: int) -> Vector3:
	var angle: = TAU * side / SIDES
	return Vector3(cos(angle) * ring.x, ring.y, sin(angle) * ring.z)
