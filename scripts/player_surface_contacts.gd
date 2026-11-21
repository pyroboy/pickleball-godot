extends RefCounted
## Physical contacts against the displayed rigid/skinned rig, not root proxies.
## Ground and net queries clip triangles. Ball sweeps use the real ball radius.
const PaddleShape = preload("res://scripts/paddle_clearance.gd")
const Geometry = preload("res://scripts/contact_surface_geometry.gd")
const Net = preload("res://scripts/net_profile.gd")
const FLOOR_EPSILON := 0.006
const LINE_EPSILON := 0.0001
static var _surfaces: Dictionary = {}
static var _surface_revisions: Dictionary = {}
static var _surface_keys: Dictionary = {}
static var _source_bounds: Dictionary = {}

static func _surface_changed(identity: int) -> void:
	_surface_revisions[identity] = int(_surface_revisions.get(identity, 0)) + 1

static func _surface_key(mesh: Mesh) -> Array:
	var identity := mesh.get_instance_id()
	if not _surface_revisions.has(identity):
		_surface_revisions[identity] = 0
		mesh.changed.connect(_surface_changed.bind(identity))
	# ArrayMesh.clear_surfaces does not emit changed in Godot 4.6.
	return [identity, _surface_revisions[identity], mesh.get_surface_count()]

static func meshes(player, include_paddle: bool = true) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if not (player is Node3D): return result
	var base = player.body_pivot if "body_pivot" in player else player
	if base != null: _collect(base, result, include_paddle)
	return result

static func _collect(node: Node, result: Array[MeshInstance3D], include_paddle: bool) -> void:
	if not include_paddle and node.name == &"Paddle": return
	if node is MeshInstance3D and node.mesh != null and node.is_visible_in_tree() and node.layers != 0:
		result.append(node)
	for child in node.get_children(): _collect(child, result, include_paddle)

static func world_triangles(instance: MeshInstance3D) -> PackedVector3Array:
	return posed_triangles(instance.mesh, instance.global_transform, _skin_palette(instance))

static func _source_arrays(mesh: Mesh) -> Array:
	var key := _surface_key(mesh)
	if not _surfaces.has(mesh) or _surface_keys.get(mesh, []) != key:
		var entries: Array = []
		for surface in range(mesh.get_surface_count()):
			if mesh is ArrayMesh and mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
			var arrays: Array = mesh.surface_get_arrays(surface)
			arrays.make_read_only()
			entries.append(arrays)
		entries.make_read_only()
		var minimum := Vector3.INF; var maximum := -Vector3.INF
		for arrays in entries:
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				minimum = minimum.min(vertex); maximum = maximum.max(vertex)
		_source_bounds[mesh] = {"valid": minimum.is_finite(), "bounds": AABB(minimum, maximum - minimum) if minimum.is_finite() else AABB()}
		_surfaces[mesh] = entries
		var current_key := _surface_key(mesh)
		current_key.make_read_only()
		_surface_keys[mesh] = current_key
	return _surfaces[mesh]

static func mesh_geometry_key(mesh: Mesh) -> Array:
	if mesh == null: return []
	_source_arrays(mesh)
	return _surface_keys[mesh]

static func posed_triangles(mesh: Mesh, transform: Transform3D, palette: Array[Transform3D]) -> PackedVector3Array:
	if mesh == null: return PackedVector3Array()
	return _posed_source_arrays(_source_arrays(mesh), transform, palette)

static func _posed_source_arrays(entries: Array, transform: Transform3D, palette: Array[Transform3D]) -> PackedVector3Array:
	var output := PackedVector3Array()
	for arrays in entries:
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var posed := PackedVector3Array()
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		var skinned: bool = not palette.is_empty() and bones != null and weights != null and bones.size() >= vertices.size() * 4
		var stride: int = bones.size() / vertices.size() if skinned else 0
		for index in vertices.size():
			var point: Vector3 = transform * vertices[index]
			if skinned:
				point = Vector3.ZERO
				for slot in stride:
					var offset: int = index * stride + slot
					var bone: int = int(bones[offset])
					if weights[offset] > 0.0 and bone < palette.size(): point += (palette[bone] * vertices[index]) * weights[offset]
			posed.append(point)
		if indices.is_empty(): output.append_array(posed)
		else:
			for index in indices: output.append(posed[index])
	return output

static func _skin_palette(instance: MeshInstance3D) -> Array[Transform3D]:
	var skeleton: Skeleton3D = instance.get_node_or_null(instance.skeleton) as Skeleton3D if instance.skin != null else null
	var palette: Array[Transform3D] = []
	if skeleton != null:
		for binding in range(instance.skin.get_bind_count()):
			var bone: int = instance.skin.get_bind_bone(binding)
			if bone < 0: bone = skeleton.find_bone(instance.skin.get_bind_name(binding))
			palette.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * instance.skin.get_bind_pose(binding) if bone >= 0 else instance.global_transform)
	return palette

static func world_bounds(instance: MeshInstance3D) -> AABB:
	return posed_bounds(instance.mesh, instance.global_transform, _skin_palette(instance))

static func posed_bounds(mesh: Mesh, transform: Transform3D, skin_palette: Array[Transform3D]) -> AABB:
	# Convex weighted skinning lies within the union of transformed bind
	# bounds. This broad phase is conservative; narrow phase uses triangles.
	var box: AABB = mesh.get_aabb()
	# ArrayMesh region writes leave the engine AABB unchanged. Actual source
	# bounds are rebuilt once per revision and preserve every displayed vertex.
	_source_arrays(mesh)
	if _source_bounds[mesh].valid: box = box.merge(_source_bounds[mesh].bounds)
	var palette: Array[Transform3D] = skin_palette.duplicate()
	if palette.is_empty(): palette.append(transform)
	var minimum := Vector3.INF; var maximum := -Vector3.INF
	for frame in palette:
		for corner in 8:
			var point: Vector3 = frame * box.get_endpoint(corner)
			minimum = minimum.min(point); maximum = maximum.max(point)
	return AABB(minimum, maximum - minimum)

static func snapshot(player, include_paddle: bool = false) -> Dictionary:
	var _pt := Time.get_ticks_usec()
	var _pr = _perf_snapshot(player, include_paddle)
	PerfMonitor.record("surface.snapshot", Time.get_ticks_usec() - _pt)
	return _pr

static func _perf_snapshot(player, include_paddle: bool = false) -> Dictionary:
	var parts := {}
	for instance in meshes(player, include_paddle):
		var palette: Array[Transform3D] = _skin_palette(instance)
		parts[instance.get_instance_id()] = {"mesh": instance.mesh, "source_arrays": _source_arrays(instance.mesh), "mesh_key": mesh_geometry_key(instance.mesh), "transform": instance.global_transform,
			"palette": palette, "bounds": posed_bounds(instance.mesh, instance.global_transform, palette),
			"part": String(instance.name), "hand": hand_geometry(instance),
			"equipment": "paddle_node" in player and player.paddle_node != null and player.paddle_node.is_ancestor_of(instance)}
	var paddle: Transform3D = player.paddle_node.global_transform if "paddle_node" in player and player.paddle_node != null else Transform3D.IDENTITY
	return {"parts": parts, "root": player.global_position, "paddle": paddle, "has_paddle": "paddle_node" in player and player.paddle_node != null}

static func snapshot_triangles(part: Dictionary) -> PackedVector3Array:
	## A snapshot's transform and skin palette are immutable. Reuse its actual
	## posed surface within all queries/remainders of the same physics sample.
	if not part.has("posed_triangles"):
		part["posed_triangles"] = _posed_source_arrays(part.source_arrays, part.transform, part.palette) if part.has("source_arrays") else posed_triangles(part.mesh, part.transform, part.palette)
	return part.posed_triangles

static func clip_axis(points: PackedVector3Array, axis: int, bound: float, keep_less: bool) -> PackedVector3Array:
	var output := PackedVector3Array()
	if points.is_empty(): return output
	var previous: Vector3 = points[-1]
	var previous_in: bool = previous[axis] <= bound if keep_less else previous[axis] >= bound
	for point in points:
		var inside: bool = point[axis] <= bound if keep_less else point[axis] >= bound
		if inside != previous_in:
			output.append(previous.lerp(point, (bound - previous[axis]) / (point[axis] - previous[axis])))
		if inside: output.append(point)
		previous = point; previous_in = inside
	return output

static func _in_kitchen_polygon(points: PackedVector3Array) -> bool:
	var half_width: float = PickleballConstants.COURT_WIDTH * 0.5 + LINE_EPSILON
	var depth: float = PickleballConstants.NON_VOLLEY_ZONE + LINE_EPSILON
	var clipped := clip_axis(points, 0, half_width, true)
	clipped = clip_axis(clipped, 0, -half_width, false)
	clipped = clip_axis(clipped, 2, depth, true)
	clipped = clip_axis(clipped, 2, -depth, false)
	return not clipped.is_empty()

static func ground_contacts(player, include_shoes: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var floor_y: float = PickleballConstants.FLOOR_Y + FLOOR_EPSILON
	for instance in meshes(player):
		if not include_shoes and instance.name == &"FootMesh": continue
		if world_bounds(instance).position.y > floor_y: continue
		var triangles := world_triangles(instance)
		var lowest: float = INF
		for point in triangles: lowest = minf(lowest, point.y)
		if lowest > floor_y: continue
		var points := PackedVector3Array()
		var inside := false
		var court_sides: Array[int] = []
		for index in range(0, triangles.size() - 2, 3):
			var polygon := clip_axis(PackedVector3Array([triangles[index], triangles[index + 1], triangles[index + 2]]), 1, floor_y, true)
			if polygon.is_empty(): continue
			points.append_array(polygon)
			if _in_kitchen_polygon(polygon): inside = true
			for side in [0, 1]:
				var court := clip_axis(polygon, 0, PickleballConstants.COURT_WIDTH * 0.5, true)
				court = clip_axis(court, 0, -PickleballConstants.COURT_WIDTH * 0.5, false)
				court = clip_axis(court, 2, PickleballConstants.BASELINE_Z if side == 0 else -0.001, true)
				court = clip_axis(court, 2, 0.001 if side == 0 else -PickleballConstants.BASELINE_Z, false)
				if not court.is_empty() and side not in court_sides: court_sides.append(side)
		if points.is_empty(): continue
		var bounds := AABB(points[0], Vector3.ZERO)
		for point in points: bounds = bounds.expand(point)
		result.append({"grounded": true, "inside": inside, "min": bounds.position, "max": bounds.end,
			"court_sides": court_sides, "part": String(instance.name), "path": String(player.get_path_to(instance)), "source": "posed_mesh"})
	return result

static func net_contact(player) -> Dictionary:
	for instance in meshes(player):
		var bounds := world_bounds(instance)
		if bounds.position.x > Net.HALF_SPAN + Net.POST_RADIUS or bounds.end.x < -Net.HALF_SPAN - Net.POST_RADIUS: continue
		if bounds.position.z > Net.POST_RADIUS + 0.001 or bounds.end.z < -Net.POST_RADIUS - 0.001: continue
		if bounds.position.y > Net.post_top_y() or bounds.end.y < Net.FLOOR_Y: continue
		var triangles := world_triangles(instance)
		for index in range(0, triangles.size() - 2, 3):
			var triangle := PackedVector3Array([triangles[index], triangles[index + 1], triangles[index + 2]])
			var polygon := clip_axis(triangle, 0, Net.HALF_SPAN, true)
			polygon = clip_axis(polygon, 0, -Net.HALF_SPAN, false)
			polygon = clip_axis(polygon, 2, Net.THICKNESS * 0.5 + 0.001, true)
			polygon = clip_axis(polygon, 2, -Net.THICKNESS * 0.5 - 0.001, false)
			polygon = clip_axis(polygon, 1, Net.FLOOR_Y, false)
			for point in polygon:
				if point.y <= Net.top_y_at(point.x) + 0.001:
					return {"hit": true, "part": String(instance.name), "point": point}
			if Net.triangle_touches_post(triangle[0], triangle[1], triangle[2]):
				return {"hit": true, "part": String(instance.name), "post": true}
	return {"hit": false}

static func hand_geometry(instance: MeshInstance3D) -> Dictionary:
	if not instance.has_meta("articulated_hand"): return {}
	var model = instance.get_meta("articulated_hand")
	return {"wrist": instance.global_transform * model.wrist_socket,
		"distal": (instance.global_basis * model.palm_contact_basis.x).normalized()}

static func hand_contact_kind(hand: Dictionary, triangles: PackedVector3Array, contact: Vector3, paddle: Transform3D) -> String:
	if hand.is_empty() or (contact - Vector3(hand.wrist)).dot(hand.distal) < -0.0001: return "body"
	# Authored finger pads sit 0.55mm off the handle for stable rendering.
	# A 1.2mm mesh-contact tolerance admits that seating, not a free hand.
	# No pose label or declared grip state grants this exception.
	var inverse: Transform3D = paddle.affine_inverse()
	for point in triangles:
		if PaddleShape.distance_to_paddle_shape(inverse * point) <= 0.0012: return "legal_hand"
	return "body"

static func ball_contact(player, from: Vector3, to: Vector3, radius: float = 0.0375, max_fraction: float = 1.0, include_legal_hand: bool = false) -> Dictionary:
	## A swept ball against the current posed body. Caller must query before
	## awarding a paddle hit. Paddle is excluded; the arm/hand remain physical.
	## Does not substitute body-clearance diagnostic margins for contact.
	var earliest: float = clampf(max_fraction, 0.0, 1.0)
	var result := {"hit": false, "fraction": -1.0, "source": "posed_mesh"}
	for instance in meshes(player, false):
		var body_bounds := world_bounds(instance).grow(radius)
		if not body_bounds.has_point(from) and not body_bounds.has_point(to) and not body_bounds.intersects_segment(from, to): continue
		var triangles := world_triangles(instance)
		for index in range(0, triangles.size() - 2, 3):
			var a: Vector3 = triangles[index]; var b: Vector3 = triangles[index + 1]; var c: Vector3 = triangles[index + 2]
			var bounds := AABB(a, Vector3.ZERO).expand(b).expand(c).grow(radius)
			if not bounds.has_point(from) and not bounds.has_point(to) and not bounds.intersects_segment(from, to): continue
			if Geometry.segment_triangle_distance(from, from.lerp(to, earliest), a, b, c) > radius: continue
			var low := 0.0; var high := earliest
			if from.distance_to(Geometry.closest_triangle(from, a, b, c)) <= radius: high = 0.0
			else:
				for step in 12:
					var middle: float = (low + high) * 0.5
					if Geometry.segment_triangle_distance(from, from.lerp(to, middle), a, b, c) <= radius: high = middle
					else: low = middle
			var surface: Vector3 = Geometry.closest_triangle(from.lerp(to, high), a, b, c)
			var kind := "body"
			if "paddle_node" in player and player.paddle_node != null:
				kind = hand_contact_kind(hand_geometry(instance), triangles, surface, player.paddle_node.global_transform)
			if kind == "legal_hand" and not include_legal_hand: continue
			earliest = high
			result = {"hit": true, "fraction": earliest, "part": String(instance.name), "mesh_id": instance.get_instance_id(), "point": from.lerp(to, earliest), "surface": surface, "normal": (from.lerp(to, earliest) - surface).normalized(), "surface_displacement": Vector3.ZERO, "surface_motion_units": "meters_per_sample_interval", "kind": kind, "source": "posed_mesh"}
	return result

static func net_plane_extent(player, player_num: int, include_paddle: bool = true, tolerance: float = 0.001) -> Dictionary:
	## Positive signed z is the player's court side. This reports geometry,
	## not permission: contact timing and returned-across-net exception belong
	## to the rally/controller. Air above the NVZ alone is never a fault.
	var direction: float = 1.0 if player_num == 0 else -1.0
	var minimum := INF
	var crossed_parts: Array[String] = []
	var witness := Vector3.INF
	var exact := true
	for instance in meshes(player, include_paddle):
		var bounds := world_bounds(instance)
		var lower: float = bounds.position.z if direction > 0.0 else -bounds.end.z
		if lower >= -tolerance:
			# A safe conservative lower bound is enough to reject crossing.
			minimum = minf(minimum, lower)
			exact = false
			continue
		var part_minimum := INF
		for point in world_triangles(instance):
			if point.z * direction < part_minimum: part_minimum = point.z * direction
			if point.z * direction < minimum:
				minimum = point.z * direction; witness = point
		if part_minimum < -tolerance: crossed_parts.append(String(player.get_path_to(instance)))
	return {"crossed": not crossed_parts.is_empty(), "min_side_z": minimum, "parts": crossed_parts,
		"point": witness, "source": "posed_mesh", "extent_exact": exact, "tolerance": tolerance}

static var _planar_face_sources: Dictionary = {}
static var _planar_face_keys: Dictionary = {}
static func rigid_planar_face_sources(mesh: Mesh) -> PackedInt32Array:
	# Exact authored coordinate planes only. Under the SAME affine endpoint
	# transforms all their fan triangles share one moving plane polynomial.
	# No rounded world-normal grouping, mesh expansion, or skin assumption.
	var revision_key := mesh_geometry_key(mesh)
	if _planar_face_sources.has(mesh) and _planar_face_keys.get(mesh, []) == revision_key: return _planar_face_sources[mesh]
	var triangles: PackedVector3Array = posed_triangles(mesh, Transform3D.IDENTITY, [])
	var sources := PackedInt32Array(); sources.resize(triangles.size() / 3); sources.fill(-1)
	var groups: Dictionary = {}
	for offset in range(0, triangles.size() - 2, 3):
		var a: Vector3 = triangles[offset]; var b: Vector3 = triangles[offset + 1]; var c: Vector3 = triangles[offset + 2]
		if (b - a).cross(c - a).length_squared() < 1e-20: continue
		for axis in 3:
			if a[axis] == b[axis] and b[axis] == c[axis]:
				var key := Vector2(axis, a[axis])
				if not groups.has(key): groups[key] = offset
				sources[offset / 3] = int(groups[key]); break
		if sources[offset / 3] >= 0: continue
		# Exact authored extrusion planes: both triangles of a prism's side
		# use the same two projected endpoints. No rounded normal grouping.
		for axis in 3:
			var other: Array = [0, 1, 2]; other.erase(axis)
			var projected: Array = []
			for vertex in [a, b, c]:
				var point := Vector2(vertex[other[0]], vertex[other[1]])
				if not point in projected: projected.append(point)
			if projected.size() != 2: continue
			if projected[1].x < projected[0].x or projected[1].x == projected[0].x and projected[1].y < projected[0].y: projected.reverse()
			var key: Array = [axis, projected[0], projected[1]]
			if not groups.has(key): groups[key] = offset
			sources[offset / 3] = int(groups[key]); break
	_planar_face_sources[mesh] = sources
	_planar_face_keys[mesh] = revision_key
	return sources
