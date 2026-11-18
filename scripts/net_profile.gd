class_name NetProfile
extends RefCounted



const FLOOR_Y: = 0.075
const CENTER_HEIGHT: = 0.8636
const SIDELINE_HEIGHT: = 0.9144
const HALF_COURT_WIDTH: = 3.05
const HALF_SPAN: = 3.3528
const THICKNESS: = 0.024
const COLLISION_SEGMENTS: = 32
const TAPE_WIDTH: = 0.0508

static func height_at(x: float) -> float:
	var ratio: float = clampf(x, - HALF_SPAN, HALF_SPAN) / HALF_COURT_WIDTH
	return CENTER_HEIGHT + (SIDELINE_HEIGHT - CENTER_HEIGHT) * ratio * ratio

static func top_y_at(x: float) -> float:
	return FLOOR_Y + height_at(x)

static func clear_y_at(x: float, ball_radius: float = 0.0375) -> float:


	return top_y_at(minf(absf(x) + ball_radius, HALF_SPAN)) + ball_radius + 0.001

static func spans_x(x: float, radius: float = 0.0) -> bool:
	return absf(x) <= HALF_SPAN + radius

# Shared with Net._add_posts: actual tapered, ten-sided rendered posts.
const POST_BOTTOM_RADIUS := 0.04
const POST_TOP_RADIUS := 0.035
const POST_RADIUS := POST_BOTTOM_RADIUS
const POST_EXTRA_HEIGHT := 0.045
const POST_RADIAL_SEGMENTS := 10
const Geometry = preload("res://scripts/contact_surface_geometry.gd")
static var _post_faces := PackedVector3Array()
static var _post_planes: Array[Plane] = []

static func post_height() -> float:
	return height_at(HALF_SPAN) + POST_EXTRA_HEIGHT

static func post_top_y() -> float:
	return FLOOR_Y + post_height()

static func post_mesh() -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = POST_TOP_RADIUS
	mesh.bottom_radius = POST_BOTTOM_RADIUS
	mesh.height = post_height()
	mesh.radial_segments = POST_RADIAL_SEGMENTS
	return mesh

static func crossing_clear(crossing: Vector3, ball_radius: float = 0.0375, margin: float = 0.0, allow_around_post: bool = true) -> bool:
	if not crossing.is_finite() or crossing.y < FLOOR_Y + ball_radius: return false
	if post_sweep(crossing, crossing, ball_radius).get("hit", false): return false
	if not spans_x(crossing.x, ball_radius): return allow_around_post
	return crossing.y >= clear_y_at(crossing.x, ball_radius) + margin

static func post_sweep(from: Vector3, to: Vector3, radius: float = 0.0375) -> Dictionary:
	var result := {"hit": false, "fraction": -1.0}
	var earliest := 1.0
	var minimum: Vector3 = from.min(to)
	var maximum: Vector3 = from.max(to)
	if minimum.y > post_top_y() + radius or maximum.y < FLOOR_Y - radius: return result
	if minimum.z > POST_RADIUS + radius or maximum.z < -POST_RADIUS - radius: return result
	if _post_faces.is_empty(): _post_faces = post_mesh().get_faces()
	for side in [-1.0, 1.0]:
		var x: float = side * HALF_SPAN
		if minimum.x > x + POST_RADIUS + radius or maximum.x < x - POST_RADIUS - radius: continue
		var offset := Vector3(x, FLOOR_Y + post_height() * 0.5, 0.0)
		var local_from := from - offset; var local_to := to - offset
		if _post_contains(local_from):
			var normal := Vector3(local_from.x, 0.0, local_from.z).normalized()
			if normal.length_squared() < 0.5: normal = Vector3.FORWARD
			return {"hit": true, "fraction": 0.0, "point": from, "surface": from, "normal": normal, "post": side}
		for index in range(0, _post_faces.size() - 2, 3):
			var a: Vector3 = _post_faces[index]; var b: Vector3 = _post_faces[index + 1]; var c: Vector3 = _post_faces[index + 2]
			if Geometry.segment_triangle_distance(local_from, local_from.lerp(local_to, earliest), a, b, c) > radius: continue
			var low := 0.0; var high := earliest
			if local_from.distance_to(Geometry.closest_triangle(local_from, a, b, c)) <= radius: high = 0.0
			else:
				for step in 12:
					var middle: float = (low + high) * 0.5
					if Geometry.segment_triangle_distance(local_from, local_from.lerp(local_to, middle), a, b, c) <= radius: high = middle
					else: low = middle
			earliest = high
			var center: Vector3 = local_from.lerp(local_to, earliest)
			var surface: Vector3 = Geometry.closest_triangle(center, a, b, c)
			var normal: Vector3 = (center - surface).normalized()
			if normal.length_squared() < 0.5: normal = (b - a).cross(c - a).normalized()
			result = {"hit": true, "fraction": earliest, "point": center + offset, "surface": surface + offset, "normal": normal, "post": side}
	return result

static func triangle_touches_post(a: Vector3, b: Vector3, c: Vector3, tolerance: float = 0.001) -> bool:
	var minimum: Vector3 = a.min(b).min(c)
	var maximum: Vector3 = a.max(b).max(c)
	if minimum.y > post_top_y() + tolerance or maximum.y < FLOOR_Y - tolerance: return false
	if minimum.z > POST_RADIUS + tolerance or maximum.z < -POST_RADIUS - tolerance: return false
	_ensure_post_planes()
	for side in [-1.0, 1.0]:
		var x: float = side * HALF_SPAN
		if minimum.x > x + POST_RADIUS + tolerance or maximum.x < x - POST_RADIUS - tolerance: continue
		var offset := Vector3(x, FLOOR_Y + post_height() * 0.5, 0.0)
		var polygon := PackedVector3Array([a - offset, b - offset, c - offset])
		# Exact convex intersection against the rendered post's twelve planes.
		# This also covers a large triangle spanning the whole post interior.
		for plane in _post_planes:
			if polygon.is_empty(): break
			var clipped := PackedVector3Array()
			var previous: Vector3 = polygon[-1]
			var previous_distance: float = plane.distance_to(previous) - tolerance
			for point in polygon:
				var distance: float = plane.distance_to(point) - tolerance
				if (distance <= 0.0) != (previous_distance <= 0.0):
					clipped.append(previous.lerp(point, -previous_distance / (distance - previous_distance)))
				if distance <= 0.0: clipped.append(point)
				previous = point; previous_distance = distance
			polygon = clipped
		if not polygon.is_empty(): return true
	return false

static func _ensure_post_planes() -> void:
	if not _post_planes.is_empty(): return
	if _post_faces.is_empty(): _post_faces = post_mesh().get_faces()
	for index in range(0, _post_faces.size() - 2, 3):
		var a: Vector3 = _post_faces[index]; var b: Vector3 = _post_faces[index + 1]; var c: Vector3 = _post_faces[index + 2]
		var normal: Vector3 = (b - a).cross(c - a)
		if normal.length_squared() < 1e-16: continue
		normal = normal.normalized()
		if normal.dot(-a) > 0.0: normal = -normal
		var plane := Plane(normal, normal.dot(a))
		var duplicate := false
		for existing in _post_planes:
			if normal.dot(existing.normal) > 0.999999 and absf(plane.d - existing.d) < 0.000001:
				duplicate = true; break
		if not duplicate: _post_planes.append(plane)

static func _post_contains(point: Vector3) -> bool:
	_ensure_post_planes()
	for plane in _post_planes:
		if plane.distance_to(point) > 0.000001: return false
	return true
