extends RefCounted
## Read-only, exact displayed hand/paddle/torso separation. No motion admission,
## mount, anatomy, foot or contact/rule authority is granted by this helper.
const Clear = preload("res://scripts/live_ready_clearance.gd")
const Surface = preload("res://scripts/player_surface_contacts.gd")
const HAND_GAP := 0.0002
const MAX_PAIRS := 12
const MAX_GEOMETRIES := 6
const MAX_TOPOLOGIES := 8
const MAX_PAIR_KEY_BYTES := 2097152
const MAX_GEOMETRY_KEY_BYTES := 2097152
const MAX_TOPOLOGY_TRIANGLES := 8192
var actor
var _pairs: Dictionary = {}
var _geometries: Dictionary = {}
var _topologies: Dictionary = {}
var _pair_key_bytes := 0
var _geometry_key_bytes := 0
var _topology_triangles := 0
var counts := {"pair_hit": 0, "pair_miss": 0, "broad_clear": 0, "geometry_hit": 0, "geometry_miss": 0, "triangle_queries": 0}

func _init(player = null): actor = player

func reset() -> void:
	_pairs.clear(); _geometries.clear(); _topologies.clear()
	_pair_key_bytes = 0; _geometry_key_bytes = 0; _topology_triangles = 0

func cache_report() -> Dictionary:
	var point_bytes := 0; var bound_values := 0
	for value: Dictionary in _geometries.values():
		point_bytes += value.points.size() * 12; bound_values += value.bounds.size()
	return {"pair_entries": _pairs.size(), "pair_key_bytes": _pair_key_bytes,
		"geometry_entries": _geometries.size(), "geometry_key_bytes": _geometry_key_bytes,
		"geometry_point_bytes": point_bytes, "geometry_aabb_values": bound_values,
		"topologies": _topologies.size(), "topology_triangles": _topology_triangles,
		"counts": counts.duplicate()}

static func _bounds(points: PackedVector3Array) -> AABB:
	var minimum := points[0]; var maximum := points[0]
	for point in points:
		minimum = minimum.min(point); maximum = maximum.max(point)
	# Float32 reserve applies only to broad rejection, never the narrow gap.
	var scale := maxf(minimum.abs()[minimum.abs().max_axis_index()], maximum.abs()[maximum.abs().max_axis_index()])
	return AABB(minimum, maximum - minimum).grow(maxf(0.000001, scale * 0.000001))

static func _identity(instance: MeshInstance3D) -> Array:
	if instance == null or instance.mesh == null: return []
	# Actual points below are also part of the key. A changed deformation,
	# source write, triangle order or transform never inherits a cached result.
	return [instance.get_instance_id(), Surface.mesh_geometry_key(instance.mesh), instance.global_transform, Surface._skin_palette(instance)]

static func _valid(points: PackedVector3Array) -> bool:
	if points.is_empty() or points.size() % 3 != 0: return false
	for point in points:
		if not point.is_finite(): return false
	return true

func _geometry(points: PackedVector3Array, point_key: PackedByteArray) -> Dictionary:
	if _geometries.has(point_key):
		counts.geometry_hit += 1
		var cached: Dictionary = _geometries[point_key]
		_geometries.erase(point_key); _geometries[point_key] = cached
		return cached
	counts.geometry_miss += 1
	var boxes: Array[AABB] = []; var indices: Array[int] = []
	for offset in range(0, points.size(), 3):
		boxes.append(AABB(points[offset], Vector3.ZERO).expand(points[offset + 1]).expand(points[offset + 2]))
		indices.append(offset / 3)
	var count := boxes.size()
	if count > MAX_TOPOLOGY_TRIANGLES:
		return {"points": points, "bounds": boxes, "tree": Clear._tree(indices, boxes)}
	if not _topologies.has(count):
		if _topologies.size() >= MAX_TOPOLOGIES or _topology_triangles + count > MAX_TOPOLOGY_TRIANGLES:
			_topologies.clear(); _topology_triangles = 0
		# This cache stores indices only; every bound is refitted from actual
		# points. Different triangle order/count cannot retain old bounds.
		_topologies[count] = Clear._tree(indices, boxes)
		_topology_triangles += count
	var result := {"points": points.duplicate(), "bounds": boxes, "tree": Clear._refit(_topologies[count], boxes)}
	if point_key.size() <= MAX_GEOMETRY_KEY_BYTES:
		while _geometries.size() >= MAX_GEOMETRIES or _geometry_key_bytes + point_key.size() > MAX_GEOMETRY_KEY_BYTES:
			var oldest: PackedByteArray = _geometries.keys()[0]
			_geometry_key_bytes -= oldest.size(); _geometries.erase(oldest)
		_geometries[point_key] = result; _geometry_key_bytes += point_key.size()
	return result

func pair_clear(first: PackedVector3Array, second: PackedVector3Array, identity: Array = []) -> bool:
	if not _valid(first) or not _valid(second): return false
	var first_bytes := first.to_byte_array(); var second_bytes := second.to_byte_array()
	# No hash-only equality, quantization, world-to-local conversion or residual
	# tolerance: PackedByteArray equality checks every supplied numeric byte.
	var key := var_to_bytes([identity, first_bytes, second_bytes, HAND_GAP])
	if _pairs.has(key):
		counts.pair_hit += 1
		var cached: bool = _pairs[key]
		_pairs.erase(key); _pairs[key] = cached
		return cached
	counts.pair_miss += 1
	var clear := true
	if not _bounds(first).grow(HAND_GAP).intersects(_bounds(second)):
		counts.broad_clear += 1
	else:
		var other := _geometry(second, second_bytes)
		for offset in range(0, first.size(), 3):
			var a := first[offset]; var b := first[offset + 1]; var c := first[offset + 2]
			counts.triangle_queries += 1
			if not Clear._clear_triangle(a, b, c, AABB(a, Vector3.ZERO).expand(b).expand(c).grow(HAND_GAP), other, other.tree, HAND_GAP):
				clear = false
				break
	if key.size() <= MAX_PAIR_KEY_BYTES:
		while _pairs.size() >= MAX_PAIRS or _pair_key_bytes + key.size() > MAX_PAIR_KEY_BYTES:
			var oldest: PackedByteArray = _pairs.keys()[0]
			_pair_key_bytes -= oldest.size(); _pairs.erase(oldest)
		_pairs[key] = clear; _pair_key_bytes += key.size()
	return clear

func report(torso: Dictionary = {}) -> Dictionary:
	if actor == null or not is_instance_valid(actor): return {"hand_pair_clear": false, "hand_paddle_clear": false, "hand_torso_clear": false}
	var main_mesh: MeshInstance3D = actor.right_arm_node.hand_mesh
	var support_mesh: MeshInstance3D = actor.left_arm_node.hand_mesh
	var main := Surface.world_triangles(main_mesh); var support := Surface.world_triangles(support_mesh)
	var main_key := _identity(main_mesh); var support_key := _identity(support_mesh)
	var paddle := PackedVector3Array(); var paddle_key: Array = []
	for mesh in actor.paddle_node.find_children("*", "MeshInstance3D", true, false):
		paddle.append_array(Surface.world_triangles(mesh)); paddle_key.append(_identity(mesh))
	var owner_key: Array = [actor.get_instance_id(), actor.get_actor_id(), actor.get_team_id(), actor.get_court_side()]
	var hand_pair := pair_clear(main, support, [owner_key, main_key, support_key])
	var paddle_clear := pair_clear(main, paddle, [owner_key, main_key, paddle_key]) and pair_clear(support, paddle, [owner_key, support_key, paddle_key])
	if torso.is_empty(): torso = Clear.body_geometry(actor)
	var hands_clear: bool = torso.get("valid", false)
	if hands_clear:
		var torso_key := _identity(actor.body_pivot.get_meta("articulated_torso").body_mesh)
		for item in [[main, main_key], [support, support_key]]:
			var local := PackedVector3Array()
			for point: Vector3 in item[0]: local.append(torso.inverse * point)
			if not pair_clear(local, torso.points, [owner_key, item[1], torso_key, torso.inverse]): hands_clear = false
	return {"hand_pair_clear": hand_pair, "hand_paddle_clear": paddle_clear, "hand_torso_clear": hands_clear}
