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

static var _surface_total := 0   # any body mesh changed: the native floor lists are rebuilt
static func _surface_changed(identity: int) -> void:
	_surface_total += 1
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

## 1b (PerfToggles.contact_lean): same snapshot, less work per tick. The body's mesh nodes
## are found once per scene-tree change instead of walking the tree each call; each mesh's
## source arrays are validated once (were three times); the paddle lookup is hoisted.
static var _tree_revision := 0
static var _tree_hooked := false
static var _mesh_nodes: Dictionary = {}   # player instance id * 2 + include_paddle -> [revision, Array[MeshInstance3D]]

static func _on_tree_changed() -> void:
	_tree_revision += 1

static func _mesh_candidates(player, include_paddle: bool) -> Array[MeshInstance3D]:
	if not _tree_hooked and player.is_inside_tree():
		player.get_tree().tree_changed.connect(_on_tree_changed)
		_tree_hooked = true
	var key: int = player.get_instance_id() * 2 + (1 if include_paddle else 0)
	var cached: Array = _mesh_nodes.get(key, [])
	if _tree_hooked and not cached.is_empty() and int(cached[0]) == _tree_revision: return cached[1]
	if _mesh_nodes.size() > 64: _mesh_nodes.clear()   # players of earlier matches
	var found: Array[MeshInstance3D] = []
	var base = player.body_pivot if "body_pivot" in player else player
	if base != null: _collect_all(base, found, include_paddle)
	_mesh_nodes[key] = [_tree_revision, found]
	return found

## _collect without the per-tick filters (mesh, visibility, layers), which meshes() applies.
static func _collect_all(node: Node, result: Array[MeshInstance3D], include_paddle: bool) -> void:
	if not include_paddle and node.name == &"Paddle": return
	if node is MeshInstance3D: result.append(node)
	for child in node.get_children(): _collect_all(child, result, include_paddle)

static func _lean_snapshot(player, include_paddle: bool) -> Dictionary:
	var parts := {}
	var paddle_node: Node3D = player.paddle_node if "paddle_node" in player else null
	if player is Node3D:
		for instance: MeshInstance3D in _mesh_candidates(player, include_paddle):
			if not is_instance_valid(instance) or instance.mesh == null or not instance.is_visible_in_tree() or instance.layers == 0: continue
			var mesh: Mesh = instance.mesh
			var entries: Array = _source_arrays(mesh)
			var transform: Transform3D = instance.global_transform
			var palette: Array[Transform3D] = _skin_palette(instance)
			var box: AABB = mesh.get_aabb()
			if _source_bounds[mesh].valid: box = box.merge(_source_bounds[mesh].bounds)
			parts[instance.get_instance_id()] = {"mesh": mesh, "source_arrays": entries, "mesh_key": _surface_keys[mesh], "transform": transform,
				"palette": palette, "bounds": _palette_bounds(box, transform, palette),
				"part": String(instance.name), "hand": hand_geometry(instance),
				"equipment": paddle_node != null and paddle_node.is_ancestor_of(instance)}
	var paddle: Transform3D = paddle_node.global_transform if paddle_node != null else Transform3D.IDENTITY
	return {"parts": parts, "root": player.global_position, "paddle": paddle, "has_paddle": paddle_node != null}

## posed_bounds after the source arrays were validated: box through every palette frame.
static func _palette_bounds(box: AABB, transform: Transform3D, palette: Array[Transform3D]) -> AABB:
	var minimum := Vector3.INF; var maximum := -Vector3.INF
	if palette.is_empty():
		for corner in 8:
			var point: Vector3 = transform * box.get_endpoint(corner)
			minimum = minimum.min(point); maximum = maximum.max(point)
	else:
		for frame in palette:
			for corner in 8:
				var point: Vector3 = frame * box.get_endpoint(corner)
				minimum = minimum.min(point); maximum = maximum.max(point)
	return AABB(minimum, maximum - minimum)

static func _perf_snapshot(player, include_paddle: bool = false) -> Dictionary:
	if PerfToggles.contact_lean: return _lean_snapshot(player, include_paddle)
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
	# Perf (PerfToggles.contact_lean): this runs for every player near the kitchen every tick.
	# The candidates come from a per-player list (visible body meshes without the shoes, rebuilt
	# when the tree or a visibility changes) instead of a walk of the whole body, and a mesh
	# whose box is clearly above the floor is dropped by a cheap exact bound instead of
	# transforming its box corners (through every bone for a skinned mesh). Same meshes, same
	# order, same result.
	var lean: bool = PerfToggles.contact_lean and player is Node3D and not include_shoes
	var scan: Array[MeshInstance3D] = []
	if lean:
		var candidates: Array[MeshInstance3D] = _ground_candidates(player)
		# The same per-mesh floor test in C++ (PickleNative.floor_scan) from a cached list of the
		# meshes' boxes; -1 = the list no longer matches the scene, the loop below decides.
		var native_scan: int = _native_floor_scan(player, candidates, floor_y)
		if native_scan >= 0:
			if native_scan != 0:
				for index in candidates.size():
					if native_scan & (1 << index): scan.append(candidates[index])
		else:
			for instance: MeshInstance3D in candidates:
				var mesh: Mesh = instance.mesh
				if mesh == null or instance.layers == 0: continue
				if _clear_of_floor(instance, mesh, floor_y): continue
				scan.append(instance)
	else: scan = meshes(player)
	for instance in scan:
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

static var _floor_lists: Dictionary = {}   # player instance id -> [candidates, surface total, nodes, skeletons, meshes, counts, boxes, reach]
static func _native_floor_scan(player, candidates: Array[MeshInstance3D], floor_y: float) -> int:
	var lib = NativeMath.lib()
	if lib == null or candidates.size() > 62: return -1
	var key: int = player.get_instance_id()
	var cached = _floor_lists.get(key)
	if cached == null or not is_same(cached[0], candidates) or cached[1] != _surface_total:
		# Built with the script test, so its caches (box per mesh, reach per skinned mesh) are
		# what the list holds. A new candidates array means the tree or a visibility changed.
		var nodes := PackedInt64Array(); var skeletons := PackedInt64Array(); var meshes := PackedInt64Array()
		var counts := PackedInt32Array(); var boxes := PackedVector3Array(); var reach := PackedFloat32Array()
		for instance: MeshInstance3D in candidates:
			var mesh: Mesh = instance.mesh
			nodes.append(instance.get_instance_id())
			if mesh == null:
				skeletons.append(0); meshes.append(0); counts.append(0); boxes.append(Vector3.ZERO); boxes.append(Vector3.ZERO)
				reach.append(-2.0 if instance.skin == null else -1.0)
				continue
			_clear_of_floor(instance, mesh, floor_y)
			var box: AABB = _floor_boxes[mesh.get_instance_id()][2]
			meshes.append(mesh.get_instance_id()); counts.append(mesh.get_surface_count())
			boxes.append(box.position); boxes.append(box.size)
			if instance.skin == null:
				skeletons.append(0); reach.append(-2.0)
			else:
				var reach_entry: Array = _skin_reach[instance.get_instance_id()]
				skeletons.append(reach_entry[2].get_instance_id() if reach_entry[2] != null else 0)
				reach.append(float(reach_entry[3]) if reach_entry[2] != null else -1.0)
		if _floor_lists.size() > 64: _floor_lists.clear()
		cached = [candidates, _surface_total, nodes, skeletons, meshes, counts, boxes, reach]
		_floor_lists[key] = cached
	return lib.floor_scan(cached[2], cached[3], cached[4], cached[5], cached[6], cached[7], floor_y)

## Visible body meshes of a player without the shoes, in tree order: the ground scan's list.
## Rebuilt when the scene tree changes or any body mesh's visibility changes (the meshes'
## visibility_changed signals, which also fire for a hidden ancestor).
static var _visibility_revision := 0
static var _visibility_hooked: Dictionary = {}   # mesh node instance id -> true
static var _ground_lists: Dictionary = {}        # player instance id -> [tree revision, visibility revision, nodes]

static func _on_visibility_changed() -> void:
	_visibility_revision += 1

static func _ground_candidates(player) -> Array[MeshInstance3D]:
	var all: Array[MeshInstance3D] = _mesh_candidates(player, true)   # also hooks the tree signal
	var key: int = player.get_instance_id()
	var cached = _ground_lists.get(key)
	if _tree_hooked and cached != null and cached[0] == _tree_revision and cached[1] == _visibility_revision: return cached[2]
	if _visibility_hooked.size() > 4096: _visibility_hooked.clear()   # nodes of earlier matches
	if _ground_lists.size() > 64: _ground_lists.clear()
	var found: Array[MeshInstance3D] = []
	for instance: MeshInstance3D in all:
		if not is_instance_valid(instance): continue
		var id: int = instance.get_instance_id()
		if not _visibility_hooked.has(id):
			_visibility_hooked[id] = true
			if not instance.visibility_changed.is_connected(_on_visibility_changed): instance.visibility_changed.connect(_on_visibility_changed)
		if instance.name == &"FootMesh" or not instance.is_visible_in_tree(): continue
		found.append(instance)
	_ground_lists[key] = [_tree_revision, _visibility_revision, found]
	return found

## True when the mesh cannot be within reach of `floor_y`, by a bound that is never higher than
## the lowest corner posed_bounds would give (so nothing the full check keeps is dropped here).
## Rigid mesh: origin.y + row_y . centre - |row_y| . half size, the eight corners' lowest y
## without transforming them. Skinned mesh: every bone frame keeps its box within `reach` of
## the skeleton origin (bone chain length + the box in bone space, with margin).
static var _floor_boxes: Dictionary = {}   # mesh instance id -> [revision, surface count, AABB]
static var _skin_reach: Dictionary = {}    # skinned mesh node instance id -> [tree revision, mesh id, skeleton, reach]
static func _clear_of_floor(instance: MeshInstance3D, mesh: Mesh, floor_y: float) -> bool:
	var id: int = mesh.get_instance_id()
	var entry = _floor_boxes.get(id)
	if entry == null or entry[0] != int(_surface_revisions.get(id, -1)) or entry[1] != mesh.get_surface_count():
		_source_arrays(mesh)
		var box: AABB = mesh.get_aabb()
		if _source_bounds[mesh].valid: box = box.merge(_source_bounds[mesh].bounds)
		if _floor_boxes.size() > 256: _floor_boxes.clear()
		entry = [int(_surface_revisions[id]), mesh.get_surface_count(), box]
		_floor_boxes[id] = entry
	var bounds: AABB = entry[2]
	if instance.skin != null:
		var node_id: int = instance.get_instance_id()
		var reach_entry = _skin_reach.get(node_id)
		if reach_entry == null or reach_entry[0] != _tree_revision or reach_entry[1] != id or not is_instance_valid(reach_entry[2]):
			if _skin_reach.size() > 512: _skin_reach.clear()
			reach_entry = [_tree_revision, id, instance.get_node_or_null(instance.skeleton) as Skeleton3D, -1.0]
			if reach_entry[2] != null: reach_entry[3] = _skinned_reach(instance, reach_entry[2], bounds)
			_skin_reach[node_id] = reach_entry
		if reach_entry[2] == null or float(reach_entry[3]) < 0.0: return false   # full check decides
		var root: Transform3D = (reach_entry[2] as Skeleton3D).global_transform
		var scale: float = sqrt(maxf(root.basis.x.length_squared(), maxf(root.basis.y.length_squared(), root.basis.z.length_squared())))
		return root.origin.y - float(reach_entry[3]) * scale > floor_y
	var frame: Transform3D = instance.global_transform
	var row := Vector3(frame.basis.x.y, frame.basis.y.y, frame.basis.z.y)
	var half: Vector3 = bounds.size * 0.5
	var lowest: float = frame.origin.y + row.dot(bounds.position + half) - (absf(row.x) * half.x + absf(row.y) * half.y + absf(row.z) * half.z)
	return lowest - 0.00002 > floor_y

## Largest distance from the skeleton origin a bone frame can carry a corner of `box`: the bone's
## chain length (rest or posed offsets, whichever is longer, +25%) plus the box corner's distance
## from the bone in bone space, plus 5 cm. -1 when a bind has no bone (no cheap bound).
static func _skinned_reach(instance: MeshInstance3D, skeleton: Skeleton3D, box: AABB) -> float:
	var reach := 0.0
	for binding in range(instance.skin.get_bind_count()):
		var bone: int = instance.skin.get_bind_bone(binding)
		if bone < 0: bone = skeleton.find_bone(instance.skin.get_bind_name(binding))
		if bone < 0: return -1.0
		var chain := 0.0
		var walk: int = bone
		while walk >= 0:
			chain += maxf(skeleton.get_bone_rest(walk).origin.length(), skeleton.get_bone_pose_position(walk).length())
			walk = skeleton.get_bone_parent(walk)
		var bind: Transform3D = instance.skin.get_bind_pose(binding)
		var radius := 0.0
		for corner in 8: radius = maxf(radius, (bind * box.get_endpoint(corner)).length())
		reach = maxf(reach, chain * 1.25 + radius + 0.05)
	return reach

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
	var geometry := {"wrist": instance.global_transform * model.wrist_socket,
		"distal": (instance.global_basis * model.palm_contact_basis.x).normalized()}
	# Simple hand shape: no finger pads to find on the handle, so the hand's own grip point
	# (its origin, which a gripping hand has on the handle's axis) is carried for that test.
	if model.simple_shape: geometry["grip"] = instance.global_transform.origin
	return geometry

static func hand_contact_kind(hand: Dictionary, triangles: PackedVector3Array, contact: Vector3, paddle: Transform3D) -> String:
	if hand.is_empty() or (contact - Vector3(hand.wrist)).dot(hand.distal) < -0.0001: return "body"
	# Authored finger pads sit 0.55mm off the handle for stable rendering.
	# A 1.2mm mesh-contact tolerance admits that seating, not a free hand.
	# No pose label or declared grip state grants this exception.
	var inverse: Transform3D = paddle.affine_inverse()
	# Simple hand shape: the hand is on the paddle when its grip point is (same 1.2 mm; still a
	# measured position, never a pose label).
	if hand.has("grip") and PaddleShape.distance_to_paddle_shape(inverse * Vector3(hand.grip)) <= 0.0012: return "legal_hand"
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
