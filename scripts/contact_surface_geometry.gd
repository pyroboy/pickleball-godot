extends RefCounted
## Exact triangle / swept-sphere geometry shared by finite contact queries.

static func closest_triangle(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	# Ericson's triangle Voronoi-region test, including edges and vertices.
	var ab := b - a; var ac := c - a; var ap := point - a
	var d1 := ab.dot(ap); var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0: return a
	var bp := point - b; var d3 := ab.dot(bp); var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3: return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0: return a + ab * d1 / maxf(d1 - d3, 1e-12)
	var cp := point - c; var d5 := ab.dot(cp); var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6: return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0: return a + ac * d2 / maxf(d2 - d6, 1e-12)
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0: return b + (c - b) * (d4 - d3) / maxf(d4 - d3 + d5 - d6, 1e-12)
	var denom := va + vb + vc
	if absf(denom) < 1e-12: return a
	return a + ab * vb / denom + ac * vc / denom

static func segment_triangle_distance(from: Vector3, to: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	if from.distance_squared_to(to) > 1e-16 and Geometry3D.segment_intersects_triangle(from, to, a, b, c) != null: return 0.0
	var distance: float = minf(from.distance_to(closest_triangle(from, a, b, c)), to.distance_to(closest_triangle(to, a, b, c)))
	for edge in [[a, b], [b, c], [c, a]]:
		var pair := Geometry3D.get_closest_points_between_segments(from, to, edge[0], edge[1])
		distance = minf(distance, pair[0].distance_to(pair[1]))
	return distance


static func barycentric(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var first := b - a; var second := c - a; var relative := point - a
	var d00 := first.dot(first); var d01 := first.dot(second); var d11 := second.dot(second)
	var d20 := relative.dot(first); var d21 := relative.dot(second)
	var denominator := d00 * d11 - d01 * d01
	if absf(denominator) < 1e-16: return Vector3(1, 0, 0)
	var v := (d11 * d20 - d01 * d21) / denominator
	var w := (d00 * d21 - d01 * d20) / denominator
	return Vector3(1.0 - v - w, v, w)
