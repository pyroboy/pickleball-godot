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

static func sample_paddle(paddle: Transform3D, points: Array[Vector3], geometry: Dictionary) -> Dictionary:
	var result: = {"pelvis": INF, "abdomen": INF, "ribcage": INF, "neck": INF}
	for point in points:
		var world: Vector3 = paddle * point
		for cell in geometry.cells: result[cell.region] = minf(result[cell.region], cell_margin(world, cell))
	return result

static var _surface_cache: Dictionary = {}


