extends RefCounted


const Dimensions = preload("res://scripts/player_body_dimensions.gd")
const HAIR: = Color("4a362a")
const BROW: = Color("423027")
const EYE_WHITE: = Color("f6eadb")
const IRIS: = Color("302c28")
const PUPIL: = Color("131820")
const MOUTH: = Color("835546")
const HEAD_PROFILE: = [Vector3(0.032, - 0.11, 0.041), Vector3(0.057, - 0.099, 0.052), 
	Vector3(0.073, - 0.075, 0.064), Vector3(0.081, - 0.043, 0.073), 
	Vector3(0.087, - 0.005, 0.08), Vector3(0.087, 0.03, 0.079), 
	Vector3(0.079, 0.064, 0.072), Vector3(0.059, 0.094, 0.055), 
	Vector3(0.027, 0.113, 0.028), Vector3(0, 0.118, 0)]
static var _meshes: Dictionary = {}

static func apply(head: MeshInstance3D, skin: Color, forward: Vector3, kit_material: Material) -> void :
	head.mesh = mesh(skin, forward)
	head.material_override = kit_material


	for child in head.get_children():
		if child is MeshInstance3D and child.mesh is SphereMesh:
			head.remove_child(child)
			child.queue_free()

static func mesh(skin: Color, forward: Vector3 = Vector3.FORWARD) -> ArrayMesh:
	var key: = "%s:%s" % [skin.to_html(), forward]
	if not _meshes.has(key):
		_meshes[key] = _build(skin, forward)
	return _meshes[key]

static func _build(skin: Color, forward: Vector3) -> ArrayMesh:
	var surface: = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)


	_head(surface, skin)
	for side in [-1.0, 1.0]:
		_ellipsoid(surface, Vector3(side * 0.087, - 0.006, 0.001), Vector3(0.014, 0.025, 0.012), skin, 8, 6)
		_ellipsoid(surface, Vector3(side * 0.093, - 0.006, - 0.008), Vector3(0.006, 0.014, 0.005), skin.darkened(0.15), 6, 4)


		var eye_frame: = Basis(Vector3.UP, - side * 0.38)
		var eye_front: = eye_frame * Vector3.FORWARD
		var eye_center: = Vector3(side * 0.033, 0.022, - 0.0735)
		_ellipsoid(surface, eye_center, Vector3(0.019, 0.009, 0.0045), EYE_WHITE, 10, 6, eye_frame)
		_ellipsoid(surface, eye_center + eye_front * 0.004, Vector3(0.0075, 0.0075, 0.0018), IRIS, 8, 6, eye_frame)
		_ellipsoid(surface, eye_center + eye_front * 0.0055, Vector3(0.0035, 0.0048, 0.0007), PUPIL, 8, 4, eye_frame)
		_ellipsoid(surface, eye_center + eye_front * 0.0062 + Vector3( - side * 0.0022, 0.0035, 0), Vector3(0.0016, 0.0019, 0.0006), EYE_WHITE, 6, 4, eye_frame)

		_ribbon(surface, [Vector3(side * 0.014, 0.041, - 0.077), Vector3(side * 0.029, 0.043, - 0.077), Vector3(side * 0.048, 0.038, - 0.069)], 0.006, BROW)
	_nose(surface, skin)

	_ribbon(surface, [Vector3( - 0.025, - 0.047, - 0.071), Vector3( - 0.009, - 0.051, - 0.08), Vector3(0.01, - 0.051, - 0.08), Vector3(0.024, - 0.046, - 0.071)], 0.0035, MOUTH)
	_ribbon(surface, [Vector3( - 0.013, - 0.056, - 0.077), Vector3(0.012, - 0.055, - 0.077)], 0.003, skin.lightened(0.09))
	_hair(surface)
	surface.index()
	var result: ArrayMesh = surface.commit()
	var arrays: = result.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var front: = Vector3(forward.x, 0, forward.z).normalized()
	if front.length_squared() < 0.5: front = Vector3.FORWARD
	var facing: = Basis(front.cross(Vector3.UP), Vector3.UP, - front)
	var scale: = Vector3(Dimensions.HEAD_RADIUS / 0.089, Dimensions.HEAD_HEIGHT / 0.24, Dimensions.HEAD_RADIUS / 0.089)
	for i in range(vertices.size()):
		vertices[i] = facing * (vertices[i] * scale)
		normals[i] = (facing * (normals[i] / scale)).normalized()
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	result.clear_surfaces()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

static func _head(surface: SurfaceTool, skin: Color) -> void :

	var profile: = HEAD_PROFILE
	const SIDES: = 20
	for row in range(profile.size() - 1):
		for i in range(SIDES):
			var a: = TAU * i / SIDES
			var b: = TAU * (i + 1) / SIDES
			var p0: Vector3 = _ring_point(profile[row], a)
			var p1: Vector3 = _ring_point(profile[row], b)
			var p2: Vector3 = _ring_point(profile[row + 1], b)
			var p3: Vector3 = _ring_point(profile[row + 1], a)
			var n0: = _head_normal(profile, row, a)
			var n1: = _head_normal(profile, row, b)
			var n2: = _head_normal(profile, row + 1, b)
			var n3: = _head_normal(profile, row + 1, a)
			_triangle(surface, p0, p1, p2, n0, n1, n2, skin)
			_triangle(surface, p0, p2, p3, n0, n2, n3, skin)
	for i in range(SIDES):
		var a: = TAU * i / SIDES
		var b: = TAU * (i + 1) / SIDES
		var center: = Vector3(0, - 0.094, 0.008)
		var pa: = _ring_point(profile[0], b); var pb: = _ring_point(profile[0], a)
		var normal: Vector3 = (pb - center).cross(pa - center).normalized()
		_triangle(surface, center, pa, pb, normal, normal, normal, skin)

static func _ring_point(section: Vector3, angle: float) -> Vector3:
	var point: = Vector3(sin(angle) * section.x, section.y, - cos(angle) * section.z)


	var jaw: float = clampf(( - 0.043 - section.y) / 0.075, 0.0, 1.0)
	var front: float = maxf(cos(angle), 0.0)
	point.z -= 0.02 * jaw * pow(front, 4.0)
	point.y += 0.02 * jaw * (1.0 - front)
	return point

static func _head_normal(profile: Array, row: int, angle: float) -> Vector3:
	if profile[row].x < 1e-05: return Vector3.UP
	var vertical: Vector3 = _ring_point(profile[mini(row + 1, profile.size() - 1)], angle) - _ring_point(profile[maxi(row - 1, 0)], angle)
	var tangent: Vector3 = _ring_point(profile[row], angle + 0.002) - _ring_point(profile[row], angle - 0.002)
	return vertical.cross(tangent).normalized()

static func _nose(surface: SurfaceTool, skin: Color) -> void :

	var bridge: = Vector3(0, 0.03, - 0.078)
	var left: = Vector3( - 0.011, - 0.018, - 0.078)
	var right: = Vector3(0.011, - 0.018, - 0.078)
	var tip: = Vector3(0, - 0.01, - 0.108)
	var bottom: = Vector3(0, - 0.028, - 0.089)
	_flat_triangle(surface, bridge, left, tip, skin.lightened(0.035))
	_flat_triangle(surface, bridge, tip, right, skin)
	_flat_triangle(surface, left, bottom, tip, skin.darkened(0.08))
	_flat_triangle(surface, tip, bottom, right, skin.darkened(0.06))
	_ellipsoid(surface, Vector3(0, - 0.011, - 0.102), Vector3(0.009, 0.009, 0.007), skin, 8, 4)
	for side in [-1.0, 1.0]:
		_ellipsoid(surface, Vector3(side * 0.007, - 0.021, - 0.092), Vector3(0.003, 0.0018, 0.002), skin.darkened(0.25), 6, 4)

static func _hair(surface: SurfaceTool) -> void :
	const SIDES: = 20
	const ROWS: = 12
	for row in range(ROWS):
		for i in range(SIDES):
			var a: = TAU * i / SIDES
			var b: = TAU * (i + 1) / SIDES
			var p0: = _hair_point(a, float(row) / ROWS)
			var p1: = _hair_point(b, float(row) / ROWS)
			var p2: = _hair_point(b, float(row + 1) / ROWS)
			var p3: = _hair_point(a, float(row + 1) / ROWS)
			var color: = HAIR.lightened(0.055 if i >= 2 and i <= 7 else 0.0)
			var n0: = Vector3(p0.x / 0.094, p0.y / 0.12, p0.z / 0.09).normalized()
			var n1: = Vector3(p1.x / 0.094, p1.y / 0.12, p1.z / 0.09).normalized()
			var n2: = Vector3(p2.x / 0.094, p2.y / 0.12, p2.z / 0.09).normalized()
			var n3: = Vector3(p3.x / 0.094, p3.y / 0.12, p3.z / 0.09).normalized()
			_triangle(surface, p0, p1, p2, n0, n1, n2, color)
			if row < ROWS - 1: _triangle(surface, p0, p2, p3, n0, n2, n3, color)


	_flat_triangle(surface, Vector3( - 0.049, 0.074, - 0.066), Vector3(0.042, 0.069, - 0.072), Vector3( - 0.024, 0.053, - 0.08), HAIR)
	_flat_triangle(surface, Vector3( - 0.049, 0.074, - 0.066), Vector3(0.052, 0.076, - 0.06), Vector3(0.042, 0.069, - 0.072), HAIR.lightened(0.035))

static func _hair_point(angle: float, fraction: float) -> Vector3:
	var hairline: = lerpf( - 0.022, 0.066, (cos(angle) + 1.0) * 0.5) + 0.006 * sin(angle)


	var y: = lerpf(hairline, 0.12, 1.0 - pow(1.0 - fraction, 1.5))
	var radii: = Vector2.ZERO
	for row in range(HEAD_PROFILE.size() - 1):
		var lower: Vector3 = HEAD_PROFILE[row]
		var upper: Vector3 = HEAD_PROFILE[row + 1]
		if y >= lower.y and y <= upper.y:
			radii = Vector2(lower.x, lower.z).lerp(Vector2(upper.x, upper.z), (y - lower.y) / (upper.y - lower.y))
			break
	var clearance: = 0.0075 * clampf((0.12 - y) / 0.002, 0.0, 1.0)
	radii += Vector2.ONE * clearance
	return Vector3(sin(angle) * radii.x, y, - cos(angle) * radii.y)

static func _ellipsoid(surface: SurfaceTool, center: Vector3, radii: Vector3, color: Color, sides: int, rows: int, orientation: Basis = Basis.IDENTITY) -> void :
	for row in range(rows):
		var latitude_a: = - PI * 0.5 + PI * row / rows
		var latitude_b: = - PI * 0.5 + PI * (row + 1) / rows
		for i in range(sides):
			var longitude_a: = TAU * i / sides
			var longitude_b: = TAU * (i + 1) / sides
			var a: = Vector3(cos(latitude_a) * sin(longitude_a), sin(latitude_a), - cos(latitude_a) * cos(longitude_a))
			var b: = Vector3(cos(latitude_a) * sin(longitude_b), sin(latitude_a), - cos(latitude_a) * cos(longitude_b))
			var c: = Vector3(cos(latitude_b) * sin(longitude_b), sin(latitude_b), - cos(latitude_b) * cos(longitude_b))
			var d: = Vector3(cos(latitude_b) * sin(longitude_a), sin(latitude_b), - cos(latitude_b) * cos(longitude_a))
			if row > 0: _triangle(surface, center + orientation * (a * radii), center + orientation * (b * radii), center + orientation * (c * radii), orientation * (a / radii).normalized(), orientation * (b / radii).normalized(), orientation * (c / radii).normalized(), color)
			if row < rows - 1: _triangle(surface, center + orientation * (a * radii), center + orientation * (c * radii), center + orientation * (d * radii), orientation * (a / radii).normalized(), orientation * (c / radii).normalized(), orientation * (d / radii).normalized(), color)

static func _ribbon(surface: SurfaceTool, points: Array, width: float, color: Color) -> void :
	for i in range(points.size() - 1):
		var a: Vector3 = points[i] + Vector3.UP * width * 0.5
		var b: Vector3 = points[i] - Vector3.UP * width * 0.5
		var c: Vector3 = points[i + 1] - Vector3.UP * width * 0.5
		var d: Vector3 = points[i + 1] + Vector3.UP * width * 0.5
		_flat_triangle(surface, a, b, c, color)
		_flat_triangle(surface, a, c, d, color)

static func _flat_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void :
	var normal: = (c - a).cross(b - a).normalized()


	if normal.z > 0:
		_triangle(surface, a, c, b, - normal, - normal, - normal, color)
	else:
		_triangle(surface, a, b, c, normal, normal, normal, color)

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, color: Color) -> void :


	surface.set_color(color)
	surface.set_normal(na);surface.add_vertex(a)
	surface.set_normal(nb);surface.add_vertex(b)
	surface.set_normal(nc);surface.add_vertex(c)
