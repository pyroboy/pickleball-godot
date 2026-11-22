extends RefCounted
## Low-poly 3D building blocks for the environment (visual only). Everything is written
## into one SurfaceTool per material with flat normals and per-vertex colour, so a whole
## street of props is a single draw call. Vertex alpha < 1 marks swaying vertices
## (shaders/env_toon.gdshader: weight = 1 - alpha).

const _CUBE_FACES := [
	[Vector3(1, 0, 0), [Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(1, -1, 1)]],
	[Vector3(-1, 0, 0), [Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1), Vector3(-1, -1, -1)]],
	[Vector3(0, 1, 0), [Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)]],
	[Vector3(0, -1, 0), [Vector3(-1, -1, 1), Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1)]],
	[Vector3(0, 0, 1), [Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1), Vector3(-1, -1, 1)]],
	[Vector3(0, 0, -1), [Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, -1, -1)]],
]


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _v(st: SurfaceTool, p: Vector3, n: Vector3, c: Color, sway: float) -> void:
	st.set_normal(n)
	st.set_color(Color(c.r, c.g, c.b, 1.0 - sway))
	st.add_vertex(p)


## Quad a-b-c-d (counter-clockwise seen from the front).
static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, sway := 0.0, two_sided := false) -> void:
	var n := (b - a).cross(c - a).normalized()
	for p in [a, b, c, a, c, d]: _v(st, p, n, col, sway)
	if two_sided:
		for p in [a, c, b, a, d, c]: _v(st, p, -n, col, sway)


static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, sway := 0.0, two_sided := false) -> void:
	var n := (b - a).cross(c - a).normalized()
	for p in [a, b, c]: _v(st, p, n, col, sway)
	if two_sided:
		for p in [a, c, b]: _v(st, p, -n, col, sway)


## Box of `size` at `center`, rotated by `basis`. `skip_bottom` drops the unseen floor face.
static func box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color, basis := Basis.IDENTITY, skip_bottom := true, sway := 0.0) -> void:
	var h := size * 0.5
	for face in _CUBE_FACES:
		var n: Vector3 = face[0]
		if skip_bottom and n.y < -0.5: continue
		var pts: Array = []
		for corner in face[1]:
			pts.append(center + basis * (corner * h))
		var wn := (basis * n).normalized()
		for i in [0, 1, 2, 0, 2, 3]: _v(st, pts[i], wn, col, sway)


## Box spanning from `a` to `b` (a beam, pole, leg or rope) with a square cross-section.
static func beam(st: SurfaceTool, a: Vector3, b: Vector3, thickness: float, col: Color, sway := 0.0) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.0001: return
	var y := dir / length
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	box(st, (a + b) * 0.5, Vector3(thickness, length, thickness), col, Basis(x, y, z), false, sway)


## Upright cylinder (or cone) from `base` up `height`, with a top cap.
static func cylinder(st: SurfaceTool, base: Vector3, r_bottom: float, r_top: float, height: float, col: Color, segments := 6, cap := true) -> void:
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var p0 := base + Vector3(cos(a0) * r_bottom, 0, sin(a0) * r_bottom)
		var p1 := base + Vector3(cos(a1) * r_bottom, 0, sin(a1) * r_bottom)
		var q0 := base + Vector3(cos(a0) * r_top, height, sin(a0) * r_top)
		var q1 := base + Vector3(cos(a1) * r_top, height, sin(a1) * r_top)
		quad(st, p1, q1, q0, p0, col)
		if cap: tri(st, base + Vector3(0, height, 0), q0, q1, col)


## Sagging rope/wire from a to b, as `steps` thin beams.
static func rope(st: SurfaceTool, a: Vector3, b: Vector3, sag: float, thickness: float, col: Color, steps := 6, sway := 0.0) -> void:
	var prev := a
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var p := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		beam(st, prev, p, thickness, col, sway)
		prev = p


## Point on the same sag curve (for hanging things off a rope).
static func rope_point(a: Vector3, b: Vector3, sag: float, t: float) -> Vector3:
	return a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)


static func commit(st: SurfaceTool) -> ArrayMesh:
	return st.commit()
