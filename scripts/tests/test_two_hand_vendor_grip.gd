extends SceneTree


const Hand = preload("res://scripts/articulated_hand.gd")
const D = preload("res://scripts/paddle_dimensions.gd")
const Clearance = preload("res://scripts/paddle_clearance.gd")
var checks: = 0
var failures: Array[String] = []
class MockArm extends Node3D:
	var hand_mesh: = MeshInstance3D.new()
	func _init() -> void : add_child(hand_mesh)
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func _v(p: Vector3) -> Array: return [p.x, p.y, p.z]
func _vectors(points: PackedVector3Array) -> Array:
	var result: Array = []
	for p in points: result.append(_v(p))
	return result
func _head_planes() -> Array[Plane]:
	var planes: Array[Plane] = [Plane(Vector3.BACK, D.HEAD_HALF_THICKNESS), Plane(Vector3.FORWARD, D.HEAD_HALF_THICKNESS)]
	var outline: PackedVector2Array = D.head_outline()
	for i in range(outline.size()):
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		var delta: Vector2 = b - a
		var n: = Vector3(delta.y, - delta.x, 0).normalized()
		planes.append(Plane(n, n.dot(Vector3(a.x, a.y, 0))))
	return planes
func _clip_polygon(points: PackedVector3Array, plane: Plane) -> PackedVector3Array:
	var clipped: = PackedVector3Array()
	for i in range(points.size()):
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % points.size()]
		var da: float = plane.distance_to(a)
		var db: float = plane.distance_to(b)
		if da <= 0: clipped.append(a)
		if (da < 0 and db > 0) or (da > 0 and db < 0): clipped.append(a + (b - a) * (da / (da - db)))
	return clipped
func _head_intersections(points: PackedVector3Array, planes: Array[Plane]) -> Dictionary:
	var penetrations: Array = []
	var deepest: = 0.0
	for i in range(0, points.size(), 3):
		var polygon: = PackedVector3Array([points[i], points[i + 1], points[i + 2]])
		for plane in planes:
			polygon = _clip_polygon(polygon, plane)
			if polygon.size() < 3: break
		if polygon.size() < 3: continue
		var area: = 0.0
		for j in range(1, polygon.size() - 1): area += (polygon[j] - polygon[0]).cross(polygon[j + 1] - polygon[0]).length() * 0.5
		if area < 1e-12: continue
		var centre: = Vector3.ZERO
		for point in polygon: centre += point / float(polygon.size())
		var signed_distance: float = - INF
		for plane in planes: signed_distance = maxf(signed_distance, plane.distance_to(centre))
		if signed_distance >= - 1e-06: continue
		deepest = minf(deepest, signed_distance)
		penetrations.append({"triangle": i / 3, "interior_point": _v(centre), "signed_convex_hull_distance_m": signed_distance, "clipped_polygon": _vectors(polygon)})
	return {"penetrating_triangles": penetrations.size(), "deepest_verified_point_m": deepest, "points": penetrations}
func _component(bone: int) -> int: return 0 if bone == 0 or bone == Hand.WRIST_BRIDGE_BONE else 1 + (bone - 1) / 3
func _axis_distance(a: Vector3, b: Vector3, c: Vector3) -> float:
	var p: Array[Vector2] = [Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)]
	var sides: = Vector3(p[0].cross(p[1]), p[1].cross(p[2]), p[2].cross(p[0]))
	if absf((p[1] - p[0]).cross(p[2] - p[0])) > 1e-12 and (minf(sides.x, minf(sides.y, sides.z)) >= 0 or maxf(sides.x, maxf(sides.y, sides.z)) <= 0): return 0.0
	var distance: = INF
	for i in range(3):
		var delta: Vector2 = p[(i + 1) % 3] - p[i]
		var t: float = clampf( - p[i].dot(delta) / delta.length_squared(), 0, 1) if delta.length_squared() > 1e-12 else 0.0
		distance = minf(distance, (p[i] + delta * t).length())
	return distance
func _rigid_palm_fit(world: PackedVector3Array, arrays: Array, thumb: bool = false) -> Dictionary:
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var nearest: = INF
	var closest: Dictionary = {}
	var count: = 0
	for i in range(0, indices.size(), 3):
		var rigid: = true
		for j in range(3):
			for slot in range(4):
				if weights[indices[i + j] * 4 + slot] <= 0: continue
				var bone: int = bones[indices[i + j] * 4 + slot]
				if ( not thumb and bone != 0) or (thumb and (bone < 13 or bone > 15)): rigid = false
		if not rigid: continue
		var a: Vector3 = world[i]
		var b: Vector3 = world[i + 1]
		var c: Vector3 = world[i + 2]
		var centre: Vector3 = (a + b + c) / 3.0
		var radial: = Vector3(centre.x, 0, centre.z).normalized()
		var normal: Vector3 = (c - a).cross(b - a).normalized()
		if normal.dot(radial) >= - 0.15: continue
		count += 1
		var gap: float = _axis_distance(a, b, c) - D.HANDLE_RADIUS
		if gap < nearest:
			nearest = gap
			closest = {"triangle": i / 3, "points": [_v(a), _v(b), _v(c)], "outward_normal": _v(normal), "centre": _v(centre)}
	return {"handle_facing_triangle_count": count, "minimum_infinite_cylinder_gap_m": nearest, "nearest_triangle": closest, "note": "Actual opposed thumb shell" if thumb else "Actual rigid palmar/heel shell; excludes cuff and articulated finger pads. Infinite cylinder gives conservative seating distance; inspect closeup for appearance."}
func _mount(model, anchor_y: float) -> Dictionary:
	model.set_pose("GRIP")
	var mount: = Transform3D(Basis(Vector3.UP, deg_to_rad(315.0 if model.is_left else 135.0)), Vector3(0, anchor_y, 0))
	model.set_mesh_world_transform(mount)
	var local: PackedVector3Array = model.sampled_triangles()
	var world: = PackedVector3Array()
	for p in local: world.append(mount * p)
	var arrays: Array = model.hand_mesh.mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var parts: Array = []
	for unused in range(6): parts.append(PackedVector3Array())
	var skin: = PackedVector3Array()
	var radial_gap: = INF
	var triangle_radial_gap: = INF
	var sample_gap: = INF
	var highest: float = - INF
	var lowest: = INF
	for p in world:
		radial_gap = minf(radial_gap, Vector2(p.x, p.z).length() - D.HANDLE_RADIUS)
		sample_gap = minf(sample_gap, Clearance.distance_to_paddle_shape(p))
		highest = maxf(highest, p.y);lowest = minf(lowest, p.y)
	for i in range(0, indices.size(), 3):
		triangle_radial_gap = minf(triangle_radial_gap, _axis_distance(world[i], world[i + 1], world[i + 2]) - D.HANDLE_RADIUS)
		if colors[indices[i]].is_equal_approx(Hand.NAIL_COLOR): continue
		var part: int = _component(bones[indices[i] * 4])
		var component_points: PackedVector3Array = parts[part]
		for j in range(3): component_points.append(world[i + j]);skin.append(world[i + j])
		parts[part] = component_points
	return {"left": model.is_left, "anchor_y": anchor_y, "mount": mount, "triangles": world, "skin": skin, "parts": parts, "rigid_palm_fit": _rigid_palm_fit(world, arrays), "opposed_thumb_shell_fit": _rigid_palm_fit(world, arrays, true), "radial_triangle_gap_m": triangle_radial_gap, "radial_vertex_gap_m": radial_gap, "paddle_vertex_gap_m": sample_gap, "highest_skin_y": highest, "lowest_skin_y": lowest}
func _aabb(points: PackedVector3Array) -> AABB:
	var result: = AABB(points[0], Vector3.ZERO)
	for p in points: result = result.expand(p)
	return result
func _inside_component(point: Vector3, triangles: PackedVector3Array) -> bool:


	var directions: Array[Vector3] = [Vector3(0.931, 0.217, 0.293).normalized(), Vector3(0.173, 0.947, 0.272).normalized(), Vector3(0.311, 0.191, 0.931).normalized()]
	var votes: = 0
	for direction in directions:
		var distances: Array[float] = []
		for i in range(0, triangles.size(), 3):
			var hit = Geometry3D.ray_intersects_triangle(point, direction, triangles[i], triangles[i + 1], triangles[i + 2])
			if hit == null: continue
			var distance: float = point.distance_to(hit)
			if distance < 1e-06: continue
			distances.append(distance)
		distances.sort()
		var distinct: = 0
		var prior: float = - INF
		for d in distances:
			if d - prior > 1e-06: distinct += 1;prior = d
		if distinct % 2 == 1: votes += 1
	return votes >= 2
func _hand_overlap(a: Dictionary, b: Dictionary) -> Dictionary:
	var a_points: PackedVector3Array = a.skin
	var a_bounds: AABB = _aabb(a_points)
	var b_bounds: AABB = _aabb(b.skin)
	if not a_bounds.intersects(b_bounds): return {"penetrating_vertices": 0, "max_verified_vertex_depth_m": 0.0, "surface_crossings": 0, "bounds_disjoint": true}
	var part_bounds: Array[AABB] = []
	for part in b.parts: part_bounds.append(_aabb(part))
	var hits: Array = []
	var deepest: = 0.0
	var unique: Dictionary = {}
	for point in a_points:
		if unique.has(point): continue
		unique[point] = true
		for part_id in range(b.parts.size()):
			if not part_bounds[part_id].has_point(point): continue
			var triangles: PackedVector3Array = b.parts[part_id]
			if not _inside_component(point, triangles): continue
			var depth: = INF
			for i in range(0, triangles.size(), 3): depth = minf(depth, point.distance_to(Hand._closest_triangle_point(point, triangles[i], triangles[i + 1], triangles[i + 2])))
			if depth > 1e-06: hits.append({"point": _v(point), "inside_other_component": part_id, "surface_depth_m": depth});deepest = maxf(deepest, depth)


	var other: PackedVector3Array = b.skin
	var other_bounds: Array[AABB] = []
	for j in range(0, other.size(), 3): other_bounds.append(_aabb(PackedVector3Array([other[j], other[j + 1], other[j + 2]])).grow(1e-07))
	var crossings: = 0
	for i in range(0, a_points.size(), 3):
		var bounds: AABB = _aabb(PackedVector3Array([a_points[i], a_points[i + 1], a_points[i + 2]])).grow(1e-07)
		for j in range(0, other.size(), 3):
			if not bounds.intersects(other_bounds[j / 3]): continue
			for edge in range(3):
				var hit = Geometry3D.segment_intersects_triangle(a_points[i + edge], a_points[i + (edge + 1) % 3], other[j], other[j + 1], other[j + 2])
				if hit != null: crossings += 1;break
	return {"penetrating_vertices": hits.size(), "max_verified_vertex_depth_m": deepest, "surface_crossings": crossings, "points": hits, "bounds_disjoint": false}
func run() -> void :
	var arms: Array = []
	var models: Array = []
	for left in [false, true]:
		var arm: = MockArm.new();root.add_child(arm);arms.append(arm)
		var model: = Hand.new();model.initialize(arm, left);models.append(model)
	var planes: Array[Plane] = _head_planes()
	var rows: Array = []
	for main_left in [false, true]:
		var right: Dictionary = _mount(models[0], D.SUPPORT_GRIP_Y if main_left else D.MAIN_GRIP_Y)
		var left: Dictionary = _mount(models[1], D.MAIN_GRIP_Y if main_left else D.SUPPORT_GRIP_Y)
		var role: Dictionary = {"main_left": main_left, "hands": []}
		for hand in [right, left]:
			var blade: Dictionary = _head_intersections(hand.triangles, planes)
			check(blade.penetrating_triangles == 0, "blade intersection at left=%s main_left=%s depth=%.6f" % [hand.left, main_left, blade.deepest_verified_point_m])
			check(hand.radial_triangle_gap_m >= - 5e-05, "mounted complete triangles clear the handle cylinder")
			role.hands.append({"left": hand.left, "anchor_y": hand.anchor_y, "paddle_basis": [_v(hand.mount.basis.x), _v(hand.mount.basis.y), _v(hand.mount.basis.z)], "blade": blade, "rigid_palm_fit": hand.rigid_palm_fit, "opposed_thumb_shell_fit": hand.opposed_thumb_shell_fit, "radial_triangle_gap_m": hand.radial_triangle_gap_m, "radial_vertex_gap_m": hand.radial_vertex_gap_m, "paddle_vertex_gap_m": hand.paddle_vertex_gap_m, "highest_skin_y": hand.highest_skin_y, "lowest_skin_y": hand.lowest_skin_y, "triangles": _vectors(hand.triangles), "skin_components": hand.parts.map( func(part): return _vectors(part))})
		role["right_inside_left"] = _hand_overlap(right, left)
		role["left_inside_right"] = _hand_overlap(left, right)
		check(role.right_inside_left.penetrating_vertices == 0 and role.left_inside_right.penetrating_vertices == 0, "two adult GRIP hands do not overlap")
		check(role.right_inside_left.surface_crossings == 0 and role.left_inside_right.surface_crossings == 0, "two adult GRIP surfaces do not cross")
		rows.append(role)
	var out: = "/workspace/shared/pickleball-hands/vendor-two-hand-grip.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): out = arg.trim_prefix("--output=")
	var file: = FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify({"status": "Diagnostic mounted geometry; failures are not waived", "dimensions": {"handle_radius": D.HANDLE_RADIUS, "handle_length": D.HANDLE_LENGTH, "head_half_thickness": D.HEAD_HALF_THICKNESS, "head_outline": D.head_outline(), "main_anchor_y": D.MAIN_GRIP_Y, "support_anchor_y": D.SUPPORT_GRIP_Y}, "rows": rows, "failures": failures}, "\t"));file.close()
	for failure in failures: push_error(failure)
	for arm in arms: arm.queue_free()
	await process_frame
	print("VENDOR TWO-HAND GRIP: ", checks, " checks, ", failures.size(), " failures; ", out)
	quit(0 if failures.is_empty() else 1)
