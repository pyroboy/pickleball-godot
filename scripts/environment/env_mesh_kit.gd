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


# ------------------------------------------------------------- pull-in (pavement cut)
# The pavement was cut to 80 % (barangay_world SLAB). Everything authored around the old
# slab is drawn pulled toward the court by `pull`: a smooth map that leaves the court and
# the pavement around it alone and shifts whatever stood beyond the old curb in by the
# amount cut. It is odd-symmetric (pull(-v) = -pull(v)), so it works the same in the
# world node's space and in the turned pandesal end. Objects move rigidly: static meshes
# by connected group (see `warp_arrays`), people, animals and vehicles by their anchor.
const PULL_Z := Vector3(10.0, 14.4, 2.8)     # ramp start, ramp end, metres moved in
const PULL_X := Vector3(6.0, 8.4, 1.5)

static func pull(v: Vector3) -> Vector3:
	var az := absf(v.z)
	var ax := absf(v.x)
	var z := v.z - signf(v.z) * PULL_Z.z * smoothstep(PULL_Z.x, PULL_Z.y, az)
	var x := v.x - signf(v.x) * PULL_X.z * smoothstep(PULL_X.x, PULL_X.y, ax)
	return Vector3(x, v.y, z)

# Each outermost primitive (box, quad, tri, cylinder, beam, rope segment) is recorded with
# its vertex range and bounds, so a committed mesh can be pulled object by object.
static var _depth := 0
static var _lo := Vector3.ZERO
static var _hi := Vector3.ZERO
static var _start := 0
static var _records := {}   # SurfaceTool instance id -> Array of [start, end, lo, hi, links]

static func _count(st: SurfaceTool) -> int:
	return int(st.get_meta("n", 0))

static func _open(st: SurfaceTool) -> void:
	if _depth == 0:
		_start = _count(st)
		_lo = Vector3(INF, INF, INF)
		_hi = -_lo
	_depth += 1

static func _close(st: SurfaceTool, links := true) -> void:
	_depth -= 1
	if _depth > 0 or _count(st) == _start: return
	var id := st.get_instance_id()
	if not _records.has(id): _records[id] = []
	_records[id].append([_start, _count(st), _lo, _hi, links])

## Pulls the vertices of a committed static mesh (arrays from `commit_to_arrays`) built
## with `st`. Touching primitives form one object (a bench and its legs, a building);
## each object moves by `pull` of its centre, so nothing is stretched. Ropes do not link
## objects; each segment follows `pull` on its own, so wires stretch smoothly.
static func warp_arrays(st: SurfaceTool, arrays: Array) -> void:
	var recs: Array = _records.get(st.get_instance_id(), [])
	if recs.is_empty(): return
	var n := recs.size()
	var parent := PackedInt32Array()
	parent.resize(n)
	for i in n: parent[i] = i
	var cells := {}
	const CELL := 1.0
	const EPS := 0.015
	for i in n:
		var r: Array = recs[i]
		if not r[4]: continue
		var lo: Vector3 = r[2]
		var hi: Vector3 = r[3]
		for cx in range(floori((lo.x - EPS) / CELL), floori((hi.x + EPS) / CELL) + 1):
			for cz in range(floori((lo.z - EPS) / CELL), floori((hi.z + EPS) / CELL) + 1):
				var key := Vector2i(cx, cz)
				if not cells.has(key): cells[key] = PackedInt32Array()
				var list: PackedInt32Array = cells[key]
				for j in list:
					var o: Array = recs[j]
					var olo: Vector3 = o[2]
					var ohi: Vector3 = o[3]
					if lo.x - EPS <= ohi.x and olo.x <= hi.x + EPS and lo.y - EPS <= ohi.y and olo.y <= hi.y + EPS and lo.z - EPS <= ohi.z and olo.z <= hi.z + EPS:
						var a := _find(parent, i)
						var b := _find(parent, j)
						if a != b: parent[a] = b
				list.append(i)
				cells[key] = list
	var glo := {}
	var ghi := {}
	for i in n:
		var g := _find(parent, i)
		var r: Array = recs[i]
		glo[g] = (glo[g] as Vector3).min(r[2]) if glo.has(g) else r[2]
		ghi[g] = (ghi[g] as Vector3).max(r[3]) if ghi.has(g) else r[3]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in n:
		var g := _find(parent, i)
		var c: Vector3 = ((glo[g] as Vector3) + (ghi[g] as Vector3)) * 0.5
		var off := pull(c) - c
		off.y = 0.0
		if off.length_squared() < 1e-8: continue
		var r: Array = recs[i]
		for k in range(int(r[0]), int(r[1])): verts[k] += off
	# wires: every vertex on its own, so a rope across the ramp stays unbroken
	for i in n:
		var r: Array = recs[i]
		if r[4]: continue
		var g := _find(parent, i)
		var c: Vector3 = ((glo[g] as Vector3) + (ghi[g] as Vector3)) * 0.5
		var undo := pull(c) - c
		undo.y = 0.0
		for k in range(int(r[0]), int(r[1])):
			var v: Vector3 = verts[k] - undo
			var q := pull(v)
			verts[k] = Vector3(q.x, v.y, q.z)
	arrays[Mesh.ARRAY_VERTEX] = verts
	_records.erase(st.get_instance_id())

static func _find(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _v(st: SurfaceTool, p: Vector3, n: Vector3, c: Color, sway: float) -> void:
	st.set_normal(n)
	st.set_color(Color(c.r, c.g, c.b, 1.0 - sway))
	st.add_vertex(p)
	st.set_meta("n", int(st.get_meta("n", 0)) + 1)
	if _depth > 0:
		_lo = _lo.min(p)
		_hi = _hi.max(p)


## Quad a-b-c-d (counter-clockwise seen from the front).
static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, sway := 0.0, two_sided := false) -> void:
	_open(st)
	_quad(st, a, b, c, d, col, sway, two_sided)
	_close(st)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, sway: float, two_sided: bool) -> void:
	var n := (b - a).cross(c - a).normalized()
	for p in [a, b, c, a, c, d]: _v(st, p, n, col, sway)
	if two_sided:
		for p in [a, c, b, a, d, c]: _v(st, p, -n, col, sway)


static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, sway := 0.0, two_sided := false) -> void:
	_open(st)
	_tri(st, a, b, c, col, sway, two_sided)
	_close(st)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, sway: float, two_sided: bool) -> void:
	var n := (b - a).cross(c - a).normalized()
	for p in [a, b, c]: _v(st, p, n, col, sway)
	if two_sided:
		for p in [a, c, b]: _v(st, p, -n, col, sway)


## Box of `size` at `center`, rotated by `basis`. `skip_bottom` drops the unseen floor face.
static func box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color, basis := Basis.IDENTITY, skip_bottom := true, sway := 0.0) -> void:
	_open(st)
	_box(st, center, size, col, basis, skip_bottom, sway)
	_close(st)

static func _box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color, basis: Basis, skip_bottom: bool, sway: float) -> void:
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


## A beam that never joins objects together (wires, ropes): it follows `pull` alone.
static func _wire(st: SurfaceTool, a: Vector3, b: Vector3, thickness: float, col: Color, sway: float) -> void:
	beam(st, a, b, thickness, col, sway)
	if _depth > 0: return
	var recs: Array = _records.get(st.get_instance_id(), [])
	if not recs.is_empty(): recs[-1][4] = false


## Upright cylinder (or cone) from `base` up `height`, with a top cap.
static func cylinder(st: SurfaceTool, base: Vector3, r_bottom: float, r_top: float, height: float, col: Color, segments := 6, cap := true) -> void:
	_open(st)
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var p0 := base + Vector3(cos(a0) * r_bottom, 0, sin(a0) * r_bottom)
		var p1 := base + Vector3(cos(a1) * r_bottom, 0, sin(a1) * r_bottom)
		var q0 := base + Vector3(cos(a0) * r_top, height, sin(a0) * r_top)
		var q1 := base + Vector3(cos(a1) * r_top, height, sin(a1) * r_top)
		quad(st, p1, q1, q0, p0, col)
		if cap: tri(st, base + Vector3(0, height, 0), q0, q1, col)
	_close(st)


## Sagging rope/wire from a to b, as `steps` thin beams.
static func rope(st: SurfaceTool, a: Vector3, b: Vector3, sag: float, thickness: float, col: Color, steps := 6, sway := 0.0) -> void:
	var prev := a
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var p := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		_wire(st, prev, p, thickness, col, sway)
		prev = p


## Point on the same sag curve (for hanging things off a rope).
static func rope_point(a: Vector3, b: Vector3, sag: float, t: float) -> Vector3:
	return a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)


static func commit(st: SurfaceTool) -> ArrayMesh:
	return st.commit()
