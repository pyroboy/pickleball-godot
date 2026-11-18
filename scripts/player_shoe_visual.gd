extends RefCounted


const SOLE: = Color("edf1f5")
const RUBBER: = Color("58616e")
const UPPER: = Color("d8e1e9")
const LACE: = Color("fcf7e9")
const LINING: = Color("323c4a")
const EXPECTED_BOUNDS: = AABB(Vector3( - 0.05, - 0.025, - 0.08), Vector3(0.1, 0.05, 0.16))
static var _meshes: Dictionary = {}

static func apply(foot: MeshInstance3D, jersey: Color, shorts: Color, kit_material: Material) -> void :
	foot.mesh = mesh(jersey, shorts)
	foot.material_override = kit_material

static func mesh(jersey: Color, shorts: Color) -> ArrayMesh:
	var key: = "%s:%s" % [jersey.to_html(), shorts.to_html()]
	if not _meshes.has(key): _meshes[key] = _build(jersey, shorts)
	return _meshes[key]

static func _build(jersey: Color, shorts: Color) -> ArrayMesh:
	var surface: = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)


	var outline: = [Vector2(0, - 0.08), Vector2(0.024, - 0.076), Vector2(0.041, - 0.062), 
		Vector2(0.049, - 0.042), Vector2(0.05, - 0.014), Vector2(0.047, 0.021), 
		Vector2(0.042, 0.052), Vector2(0.026, 0.075), Vector2(0, 0.08), 
		Vector2( - 0.026, 0.075), Vector2( - 0.042, 0.052), Vector2( - 0.047, 0.021), 
		Vector2( - 0.05, - 0.014), Vector2( - 0.049, - 0.042), Vector2( - 0.041, - 0.062), Vector2( - 0.024, - 0.076)]
	var sole_bottom: = PackedVector3Array()
	var sole_belt: = PackedVector3Array()
	var sole_top: = PackedVector3Array()
	var upper_base: = PackedVector3Array()
	var upper_toe: = PackedVector3Array()
	var upper_vamp: = PackedVector3Array()
	var collar_outer: = PackedVector3Array()
	var collar_inner: = PackedVector3Array()
	var lining_bottom: = PackedVector3Array()
	for i in range(outline.size()):
		var p: Vector2 = outline[i]
		var angle: = TAU * i / outline.size()
		sole_bottom.append(Vector3(p.x * 0.97, - 0.025, p.y * 0.98))
		sole_belt.append(Vector3(p.x, - 0.021, p.y))
		sole_top.append(Vector3(p.x * 0.985, - 0.009, p.y * 0.985))
		var base: = Vector3(p.x * 0.94, - 0.008, p.y * 0.94)
		var outer: = Vector3(sin(angle) * 0.04, 0.025, 0.028 - cos(angle) * 0.033)
		upper_base.append(base)
		var toe: Vector3 = base.lerp(outer, 0.27)
		toe.y = lerpf(0.008, 0.016, (1.0 - cos(angle)) * 0.5)
		upper_toe.append(toe)
		var vamp: Vector3 = base.lerp(outer, 0.66)
		vamp.y = lerpf(0.018, 0.023, (1.0 - cos(angle)) * 0.5)
		upper_vamp.append(vamp)
		collar_outer.append(outer)
		collar_inner.append(Vector3(sin(angle) * 0.032, 0.024, 0.028 - cos(angle) * 0.026))
		lining_bottom.append(Vector3(sin(angle) * 0.03, 0.002, 0.028 - cos(angle) * 0.024))
	_connect(surface, sole_bottom, sole_belt, RUBBER)
	_connect(surface, sole_belt, sole_top, SOLE)
	_connect(surface, sole_top, upper_base, SOLE)
	_cap(surface, sole_bottom, Vector3(0, - 0.025, 0), RUBBER, false)
	var upper_rows: = [upper_base, upper_toe, upper_vamp, collar_outer]
	for row in range(upper_rows.size() - 1):
		for i in range(outline.size()):
			var next: = (i + 1) % outline.size()
			var color: = UPPER
			if row == 0 and ((i >= 3 and i <= 5) or (i >= 10 and i <= 12)): color = jersey
			if row <= 1 and i >= 6 and i <= 9: color = shorts
			_quad(surface, upper_rows[row][i], upper_rows[row][next], upper_rows[row + 1][next], upper_rows[row + 1][i], color)

	_connect(surface, collar_outer, collar_inner, jersey)
	_connect(surface, collar_inner, lining_bottom, LINING)
	_cap(surface, lining_bottom, Vector3(0, 0.002, 0.028), LINING, true)


	_vamp_strip(surface, upper_rows, Vector2(0, - 0.046), Vector2(0, - 0.008), 0.03, SOLE, 0.0004)
	for row in range(3):
		var z: = - 0.042 + row * 0.011
		for side in [-1.0, 1.0]:
			_vamp_strip(surface, upper_rows, Vector2(side * 0.013, z), Vector2( - side * 0.013, z + 0.007), 0.0023, LACE, 0.0011)
			_eyelet(surface, upper_rows, Vector2(side * 0.015, z - 0.001), shorts)
	surface.index()
	return surface.commit()

static func _connect(surface: SurfaceTool, lower: PackedVector3Array, upper: PackedVector3Array, color: Color) -> void :
	for i in range(lower.size()):
		var next: = (i + 1) % lower.size()
		_quad(surface, lower[i], lower[next], upper[next], upper[i], color)

static func _cap(surface: SurfaceTool, ring: PackedVector3Array, center: Vector3, color: Color, top: bool) -> void :
	for i in range(ring.size()):
		var next: = (i + 1) % ring.size()
		if top: _triangle(surface, center, ring[i], ring[next], color)
		else: _triangle(surface, center, ring[next], ring[i], color)

static func _vamp_strip(surface: SurfaceTool, rows: Array, start: Vector2, finish: Vector2, width: float, color: Color, lift: float) -> void :
	var delta: = (finish - start).normalized()
	var perpendicular: = Vector2( - delta.y, delta.x) * width * 0.5
	var a: = _upper_point(rows, start + perpendicular, lift)
	var b: = _upper_point(rows, finish + perpendicular, lift)
	var c: = _upper_point(rows, finish - perpendicular, lift)
	var d: = _upper_point(rows, start - perpendicular, lift)

	_quad(surface, a, d, c, b, color)

static func _eyelet(surface: SurfaceTool, rows: Array, point: Vector2, color: Color) -> void :
	var center: = _upper_point(rows, point, 0.0008)
	for i in range(6):
		var angle_a: = TAU * i / 6
		var angle_b: = TAU * (i + 1) / 6
		var a: = _upper_point(rows, point + Vector2(sin(angle_a), - cos(angle_a)) * 0.0022, 0.0008)
		var b: = _upper_point(rows, point + Vector2(sin(angle_b), - cos(angle_b)) * 0.0022, 0.0008)
		_triangle(surface, center, a, b, color)

static func _upper_point(rows: Array, point: Vector2, lift: float) -> Vector3:
	var height: = - 0.008
	for row in range(rows.size() - 1):
		for i in range(rows[row].size()):
			var next: int = (i + 1) % rows[row].size()
			var a: Vector3 = rows[row][i]
			var b: Vector3 = rows[row][next]
			var c: Vector3 = rows[row + 1][next]
			var d: Vector3 = rows[row + 1][i]
			height = maxf(height, _triangle_height(point, a, b, c))
			height = maxf(height, _triangle_height(point, a, c, d))
	return Vector3(point.x, height + lift, point.y)

static func _triangle_height(point: Vector2, a: Vector3, b: Vector3, c: Vector3) -> float:
	var av: = Vector2(a.x, a.z)
	var bv: = Vector2(b.x, b.z)
	var cv: = Vector2(c.x, c.z)
	var denominator: = (bv.y - cv.y) * (av.x - cv.x) + (cv.x - bv.x) * (av.y - cv.y)
	if absf(denominator) < 1e-08: return - INF
	var wa: = ((bv.y - cv.y) * (point.x - cv.x) + (cv.x - bv.x) * (point.y - cv.y)) / denominator
	var wb: = ((cv.y - av.y) * (point.x - cv.x) + (av.x - cv.x) * (point.y - cv.y)) / denominator
	var wc: = 1.0 - wa - wb
	if minf(wa, minf(wb, wc)) < - 1e-05: return - INF
	return wa * a.y + wb * b.y + wc * c.y

static func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void :
	_triangle(surface, a, b, c, color)
	_triangle(surface, a, c, d, color)

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void :
	var normal: = (c - a).cross(b - a).normalized()
	surface.set_color(color)
	surface.set_normal(normal)
	surface.add_vertex(a);surface.add_vertex(b);surface.add_vertex(c)
