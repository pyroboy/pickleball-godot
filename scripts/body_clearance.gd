extends RefCounted




const Body = preload("res://scripts/stroke_body_pose.gd")
const D = preload("res://scripts/player_body_dimensions.gd")
const Profile = preload("res://scripts/body_surface_profile.gd")
const REGIONS: = ["pelvis", "abdomen", "ribcage", "neck"]

static func volumes(player, pose: PostureDefinition, actual_body_transform = null, explicit_skin_frames = null) -> Dictionary:
	var root: Transform3D = player.global_transform * Body.pivot_transform(player, pose) if actual_body_transform == null else actual_body_transform
	var rest: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3(0, D.PELVIS_CENTER_Y, 0)), 
		Transform3D(Basis.IDENTITY, Vector3(0, D.PELVIS_CENTER_Y + D.PELVIS_HALF_HEIGHT, 0)), Transform3D(Basis.IDENTITY, Vector3(0, D.CHEST_CENTER_Y, 0))]
	var frames: Array[Transform3D] = []
	if explicit_skin_frames != null:



		assert (explicit_skin_frames.size() == 3, "Expected pelvis/abdomen/chest skin frames")
		for frame in explicit_skin_frames: frames.append(frame)
	else:
		frames = [Body.pelvis_transform(player, pose), Body.abdomen_transform(player, pose), Body.torso_transform(player, pose)]
	for index in range(3): frames[index] = root * frames[index] * rest[index].affine_inverse()
	var profile: Array[Vector3] = Profile.rings()
	var weights: Array[Vector3] = Profile.weights()
	var bind_rings: Array[PackedVector3Array] = Profile.surface_rings(player._get_forward_axis().z > 0.0)
	var rings: Array[PackedVector3Array] = []
	for row in range(profile.size()):
		var ring: = PackedVector3Array()
		for point in bind_rings[row]:
			ring.append((frames[0] * point) * weights[row].x + (frames[1] * point) * weights[row].y + (frames[2] * point) * weights[row].z)
		rings.append(ring)
	var cells: Array[Dictionary] = []
	var fallbacks: = 0
	for row in range(rings.size() - 1):
		var points: = PackedVector3Array(rings[row]);points.append_array(rings[row + 1])
		var center: = Vector3.ZERO
		var bounds: = AABB(points[0], Vector3.ZERO)
		for point in points: center += point;bounds = bounds.expand(point)
		center /= points.size()




		var planes: Array[Plane] = []
		_add_hull_plane(planes, rings[row][0], rings[row][1], rings[row][2], center, points)
		_add_hull_plane(planes, rings[row + 1][0], rings[row + 1][1], rings[row + 1][2], center, points)
		for side in range(bind_rings[row].size()):
			var next: int = (side + 1) % bind_rings[row].size()
			var quad: = [rings[row][side], rings[row][next], rings[row + 1][next], rings[row + 1][side]]
			for omitted in range(4):
				_add_hull_plane(planes, quad[(omitted + 1) % 4], quad[(omitted + 2) % 4], quad[(omitted + 3) % 4], center, points)
		var convex: bool = planes.size() >= 6 and _ring_is_planar(rings[row]) and _ring_is_planar(rings[row + 1])
		if not convex:
			fallbacks += 1
			planes = _box_planes(bounds)
		cells.append({"region": Profile.region(row), "planes": planes, "bounds": bounds, "points": points, "conservative_fallback": not convex})
	return {"cells": cells, "rings": rings, "fallback_cells": fallbacks, "frame_source": "displayed_skin" if explicit_skin_frames != null else "pose_query", "note": "Diagnostic conservative skin-cell margins; not gameplay physics"}

static func _ring_is_planar(points: PackedVector3Array) -> bool:



	if points.size() < 3: return false
	var normal: Vector3 = (points[1] - points[0]).cross(points[2] - points[0])
	if normal.length_squared() < 1e-14: return false
	normal = normal.normalized()
	for point in points:
		if absf(normal.dot(point - points[0])) > 3e-05: return false
	return true

static func _add_hull_plane(planes: Array[Plane], a: Vector3, b: Vector3, c: Vector3, inside: Vector3, points: PackedVector3Array) -> void :
	var normal: = (b - a).cross(c - a)
	if normal.length_squared() < 1e-12: return
	normal = normal.normalized()
	if normal.dot(inside - a) > 0: normal = - normal
	var plane: = Plane(normal, normal.dot(a))
	for point in points:
		if plane.distance_to(point) > 3e-05: return
	for previous in planes:
		if previous.normal.dot(normal) > 0.999999 and absf(previous.d - plane.d) < 1e-05: return
	planes.append(plane)

static func _box_planes(box: AABB) -> Array[Plane]:
	return [Plane(Vector3.RIGHT, box.end.x), Plane(Vector3.LEFT, - box.position.x), Plane(Vector3.UP, box.end.y), 
		Plane(Vector3.DOWN, - box.position.y), Plane(Vector3.BACK, box.end.z), Plane(Vector3.FORWARD, - box.position.z)]

static func cell_margin(point: Vector3, cell: Dictionary) -> float:
	var margin: = - INF
	for plane in cell.planes: margin = maxf(margin, plane.distance_to(point))
	return margin

static func point_margins(point: Vector3, geometry: Dictionary) -> Dictionary:
	var result: = {"pelvis": INF, "abdomen": INF, "ribcage": INF, "neck": INF}
	for cell in geometry.cells: result[cell.region] = minf(result[cell.region], cell_margin(point, cell))
	return result

static func sample_paddle(paddle: Transform3D, points: Array[Vector3], geometry: Dictionary) -> Dictionary:
	var result: = {"pelvis": INF, "abdomen": INF, "ribcage": INF, "neck": INF}
	for point in points:
		var world: Vector3 = paddle * point
		for cell in geometry.cells: result[cell.region] = minf(result[cell.region], cell_margin(world, cell))
	return result

static func sample_segment(a: Vector3, b: Vector3, radius: float, geometry: Dictionary, exclude_start_m: float = 0.0, steps: int = 12) -> Dictionary:
	var result: = {"pelvis": INF, "abdomen": INF, "ribcage": INF, "neck": INF}
	var start: float = clampf(exclude_start_m / maxf(a.distance_to(b), 1e-05), 0.0, 1.0)
	for step in range(steps + 1):
		var point: Vector3 = a.lerp(b, lerpf(start, 1.0, float(step) / maxi(steps, 1)))
		for cell in geometry.cells: result[cell.region] = minf(result[cell.region], cell_margin(point, cell) - radius)
	return result

static func leg_metrics(hip: Vector3, knee: Vector3, ankle: Vector3) -> Dictionary:
	return {"thigh_scale": hip.distance_to(knee) / D.THIGH_LENGTH, "shin_scale": knee.distance_to(ankle) / D.SHIN_LENGTH, 
		"span_ratio": hip.distance_to(ankle) / (D.THIGH_LENGTH + D.SHIN_LENGTH)}

static var _surface_cache: Dictionary = {}



static func mesh_surface_triangles(mesh: MeshInstance3D) -> PackedVector3Array:
	if mesh.has_meta(&"leg_knee_bridge"): return mesh.get_meta(&"leg_knee_bridge").triangles()
	return preload("res://scripts/player_arm_visual.gd").posed_triangles(mesh)

static func mesh_surface_points(mesh: MeshInstance3D) -> PackedVector3Array:
	if mesh.has_meta(&"leg_knee_bridge"): return mesh.get_meta(&"leg_knee_bridge").points()
	if mesh.has_meta(&"arm_elbow_bridge"):
		return mesh.get_meta(&"arm_elbow_bridge").points()
	var key: int = mesh.mesh.get_instance_id()
	if not _surface_cache.has(key):
		var points: = PackedVector3Array()
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			points.append_array(vertices)
			var count: int = indices.size() if not indices.is_empty() else vertices.size()
			for offset in range(0, count - 2, 3):
				var a: Vector3 = vertices[indices[offset] if not indices.is_empty() else offset]
				var b: Vector3 = vertices[indices[offset + 1] if not indices.is_empty() else offset + 1]
				var c: Vector3 = vertices[indices[offset + 2] if not indices.is_empty() else offset + 2]
				points.append((a + b + c) / 3.0);points.append((a + b) * 0.5);points.append((a + c) * 0.5);points.append((b + c) * 0.5)
		_surface_cache[key] = points
	return _surface_cache[key]

static func mesh_surface_margins(mesh: MeshInstance3D, geometry: Dictionary, shoulder: Vector3 = Vector3.INF, elbow: Vector3 = Vector3.INF, shoulder_band_m: float = 0.0, sample_details = null) -> Dictionary:
	var result: = {"pelvis": INF, "abdomen": INF, "ribcage": INF, "neck": INF}
	var axis: Vector3 = (elbow - shoulder).normalized() if shoulder.is_finite() and elbow.is_finite() else Vector3.ZERO
	for point in mesh_surface_points(mesh):
		var world: Vector3 = mesh.global_transform * point
		if shoulder_band_m > 0 and (world - shoulder).dot(axis) < shoulder_band_m: continue
		for cell in geometry.cells:
			var margin: float = cell_margin(world, cell)
			if margin < result[cell.region]:
				result[cell.region] = margin
				if sample_details != null:
					sample_details[cell.region] = {"point": [world.x, world.y, world.z], "along_arm_m": (world - shoulder).dot(axis) if shoulder.is_finite() else -1.0}
	return result
