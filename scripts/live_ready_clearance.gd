extends RefCounted
## Exact displayed sleeve / torso surface test (skinned torso triangles, closed-body inside test)
## and a bounded body-shift search, used by between-point arm paths, the checker
## (debug/pose_data.gd) and runtime_court_frame. No authored pose/resource is modified.
const Surface = preload("res://scripts/player_surface_contacts.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const Foot = preload("res://scripts/pose_foot_contacts.gd")
const Geometry = preload("res://scripts/contact_surface_geometry.gd")
const REQUIRED_GAP := 0.001
const WRIST_RESERVE := 0.98
const JointSeam := 0.12
const MAX_SHIFT := 0.10
const STEP := 0.005
# Perf: coarser clearance search. Was 9 dirs x 21 shifts of 5 mm, each re-building body
# geometry and sweeping both elbows at 5 deg with triangle-level collision tests (up to
# ~130 ms in one frame at point end). Now 1 cm shifts, 10 deg elbow sweep, max 12 tries.
const SEARCH_STEP := 0.01
const SEARCH_MAX_TRIALS := 12
const ELBOW_STEP_DEG := 10.0   # wide sweeps only; short precise calls (attempts <= 3) keep 5 deg
static var _bvh_topologies: Dictionary = {}
static var _resource_versions: Dictionary = {}

static func body_geometry(player) -> Dictionary:
	var _pt := Time.get_ticks_usec()
	var _pr = _perf_body_geometry(player)
	PerfMonitor.record("geo.body_geometry", Time.get_ticks_usec() - _pt)
	return _pr

static func _perf_body_geometry(player) -> Dictionary:
	var skin = player.body_pivot.get_meta("articulated_torso")
	var inverse: Transform3D = player.body_pivot.global_transform.affine_inverse()
	# Perf: the torso's body-local triangles only change when the torso bones bend.
	# Searches move the whole body many times per frame, which used to re-skin every
	# torso triangle each time. Key the result on the body-relative bone transforms
	# and reuse it; only `inverse` changes when the body merely translates.
	var instance: MeshInstance3D = skin.body_mesh
	var palette: Array[Transform3D] = Surface._skin_palette(instance)
	var pose_key: Array[Transform3D] = [inverse * instance.global_transform]
	for bone in palette: pose_key.append(inverse * bone)
	var hit: Dictionary = _torso_local_cache.get(instance.get_instance_id(), {})
	if not hit.is_empty() and _same_pose(hit.key, pose_key):
		return {"valid": true, "points": hit.points, "bounds": hit.bounds, "inverse": inverse, "tree": hit.tree}
	var world := Surface.posed_triangles(instance.mesh, instance.global_transform, palette)
	var local := PackedVector3Array()
	for point in world: local.append(inverse * point)
	var bounds: Array[AABB] = []
	for index in range(0, local.size() - 2, 3): bounds.append(AABB(local[index], Vector3.ZERO).expand(local[index + 1]).expand(local[index + 2]))
	var indices: Array[int] = []
	for index in bounds.size(): indices.append(index)
	var mesh: Mesh = skin.body_mesh.mesh
	if bounds.is_empty(): return {"valid": false, "reason": "missing torso triangles", "points": local, "bounds": bounds, "inverse": inverse}
	var key: Array = [_resource_version(mesh), bounds.size()]
	var cached: Dictionary = _bvh_topologies.get(mesh, {})
	if cached.get("key", []) != key:
		cached = {"key": key, "tree": _tree(indices, bounds)}
		_bvh_topologies[mesh] = cached
	var tree: Dictionary = _refit(cached.tree, bounds)
	_torso_local_cache[instance.get_instance_id()] = {"key": pose_key, "points": local, "bounds": bounds, "tree": tree}
	return {"valid": true, "points": local, "bounds": bounds, "inverse": inverse, "tree": tree}

static var _torso_local_cache: Dictionary = {}   # torso MeshInstance id -> body-local geometry

static func _same_pose(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if not (a[i] as Transform3D).is_equal_approx(b[i]): return false
	return true

static func _overlap(a: Vector3, b: Vector3, c: Vector3, d: Vector3, e: Vector3, f: Vector3) -> bool:
	var first: Array[Vector3] = [b - a, c - b, a - c]
	var second: Array[Vector3] = [e - d, f - e, d - f]
	var na := first[0].cross(first[1]); var nb := second[0].cross(second[1])
	var axes: Array[Vector3] = [na, nb]
	for x in first:
		for y in second: axes.append(x.cross(y))
	# Coplanar triangles need in-plane separating axes too.
	if na.cross(nb).length_squared() < 0.000000000001:
		for x in first: axes.append(na.cross(x))
		for y in second: axes.append(nb.cross(y))
	for axis in axes:
		if axis.length_squared() < 0.000000000001: continue
		var lo_a := minf(a.dot(axis), minf(b.dot(axis), c.dot(axis)))
		var hi_a := maxf(a.dot(axis), maxf(b.dot(axis), c.dot(axis)))
		var lo_b := minf(d.dot(axis), minf(e.dot(axis), f.dot(axis)))
		var hi_b := maxf(d.dot(axis), maxf(e.dot(axis), f.dot(axis)))
		if lo_a > hi_b or lo_b > hi_a: return false
	return true

static func _tree(indices: Array[int], boxes: Array[AABB]) -> Dictionary:
	if indices.is_empty(): return {}
	var bound: AABB = boxes[indices[0]]
	for index in indices: bound = bound.merge(boxes[index])
	if indices.size() <= 8: return {"bounds": bound, "indices": indices}
	var axis: int = bound.size.max_axis_index()
	indices.sort_custom(func(a: int, b: int) -> bool: return boxes[a].get_center()[axis] < boxes[b].get_center()[axis])
	var middle := indices.size() / 2
	return {"bounds": bound, "children": [_tree(indices.slice(0, middle), boxes), _tree(indices.slice(middle), boxes)]}

static func _refit(topology: Dictionary, boxes: Array[AABB]) -> Dictionary:
	# Resource revision/count identity was checked before reuse; bone motion only refits bounds.
	if topology.has("indices"):
		var bound: AABB = boxes[topology.indices[0]]
		for index: int in topology.indices: bound = bound.merge(boxes[index])
		return {"bounds": bound, "indices": topology.indices}
	var first := _refit(topology.children[0], boxes)
	var second := _refit(topology.children[1], boxes)
	return {"bounds": first.bounds.merge(second.bounds), "children": [first, second]}

static func _ray_count(point: Vector3, finish: Vector3, geometry: Dictionary, tree: Dictionary) -> int:
	if not tree.bounds.grow(0.000001).intersects_segment(point, finish): return 0
	var count := 0
	if tree.has("children"):
		for child in tree.children: count += _ray_count(point, finish, geometry, child)
		return count
	var points: PackedVector3Array = geometry.points
	for index: int in tree.indices:
		if not geometry.bounds[index].grow(0.000001).intersects_segment(point, finish): continue
		var offset := index * 3
		if Geometry3D.segment_intersects_triangle(point, finish, points[offset], points[offset + 1], points[offset + 2]) != null: count += 1
	return count

static func _inside(point: Vector3, geometry: Dictionary) -> bool:
	return _ray_count(point, point + Vector3(2.0, 0.06283, 0.03419), geometry, geometry.tree) % 2 == 1

static func _clear_triangle(a: Vector3, b: Vector3, c: Vector3, broad: AABB, geometry: Dictionary, tree: Dictionary, required_gap: float) -> bool:
	if not broad.intersects(tree.bounds): return true
	if tree.has("children"):
		for child in tree.children:
			if not _clear_triangle(a, b, c, broad, geometry, child, required_gap): return false
		return true
	var body: PackedVector3Array = geometry.points
	for item: int in tree.indices:
		if not broad.intersects(geometry.bounds[item]): continue
		var offset := item * 3
		if _overlap(a, b, c, body[offset], body[offset + 1], body[offset + 2]): return false
		if required_gap > 0.0 and triangle_distance(a, b, c, body[offset], body[offset + 1], body[offset + 2]) < required_gap: return false
	return true

static func arm_clear(arm, geometry: Dictionary, required_gap: float = 0.0) -> bool:
	var _pt := Time.get_ticks_usec()
	var _pr = _perf_arm_clear(arm, geometry, required_gap)
	PerfMonitor.record("geo.arm_clear", Time.get_ticks_usec() - _pt)
	return _pr

static func _perf_arm_clear(arm, geometry: Dictionary, required_gap: float = 0.0) -> bool:
	if not geometry.get("valid", false): return false
	var inverse: Transform3D = geometry.inverse
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var elbow: Vector3 = arm.forearm_pivot.global_position
	var axis := (elbow - shoulder).normalized()
	var displayed_wrist: Vector3 = arm.forearm_pivot.to_global(Vector3(0, 0, -arm.forearm_length))
	if _inside(inverse * elbow, geometry) or _inside(inverse * displayed_wrist, geometry): return false
	var body: PackedVector3Array = geometry.points
	for mesh in [arm.upper_mesh, arm.fore_mesh]:
		var points := Surface.world_triangles(mesh)
		for index in range(0, points.size() - 2, 3):
			var polygon := PackedVector3Array([points[index], points[index + 1], points[index + 2]])
			if mesh == arm.upper_mesh:
				var clipped := PackedVector3Array()
				var previous := polygon[-1]; var before := (previous - shoulder).dot(axis) >= JointSeam
				for point in polygon:
					var after := (point - shoulder).dot(axis) >= JointSeam
					if before != after: clipped.append(previous.lerp(point, (JointSeam - (previous - shoulder).dot(axis)) / (point - previous).dot(axis)))
					if after: clipped.append(point)
					previous = point; before = after
				polygon = clipped
			if polygon.size() < 3: continue
			for i in range(polygon.size()): polygon[i] = inverse * polygon[i]
			for fan in range(1, polygon.size() - 1):
				var a: Vector3 = polygon[0]; var b: Vector3 = polygon[fan]; var c: Vector3 = polygon[fan + 1]
				var broad := AABB(a, Vector3.ZERO).expand(b).expand(c).grow(required_gap)
				if not _clear_triangle(a, b, c, broad, geometry, geometry.tree, required_gap): return false
	return true

static func triangle_distance(a: Vector3, b: Vector3, c: Vector3, d: Vector3, e: Vector3, f: Vector3) -> float:
	var value := INF
	for edge in [[a, b], [b, c], [c, a]]: value = minf(value, Geometry.segment_triangle_distance(edge[0], edge[1], d, e, f))
	for edge in [[d, e], [e, f], [f, d]]: value = minf(value, Geometry.segment_triangle_distance(edge[0], edge[1], a, b, c))
	return value

static func clearance_report(player) -> Dictionary:
	var geometry := body_geometry(player)
	var main := arm_clear(player.right_arm_node, geometry)
	var support := arm_clear(player.left_arm_node, geometry)
	return {"valid": main and support, "main_clear": main, "support_clear": support,
		"source": "displayed sleeve triangles vs displayed skinned torso triangles; closed-body inside test", "proximal_joint_seam_m": JointSeam}

static func _solve_arm(arm, mount: Transform3D, preferred: Vector3, geometry: Dictionary, left: bool, attempts: int = 73, verify_clearance: bool = true) -> Dictionary:
	var _pt := Time.get_ticks_usec()
	var _pr = _perf_solve_arm(arm, mount, preferred, geometry, left, attempts, verify_clearance)
	PerfMonitor.record("clear.solve_arm", Time.get_ticks_usec() - _pt)
	return _pr

static func _perf_solve_arm(arm, mount: Transform3D, preferred: Vector3, geometry: Dictionary, left: bool, attempts: int = 73, verify_clearance: bool = true) -> Dictionary:
	if verify_clearance and not geometry.get("valid", false): return {}
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var wrist: Vector3 = mount * arm.articulated_hand.wrist_socket
	var span := wrist - shoulder; var length := span.length()
	var upper: float = arm.upper_arm_length; var fore: float = arm.forearm_length
	if length >= upper + fore - 0.0001 or length <= absf(upper - fore) + 0.0001: return {}
	var axis := span / length
	var along := (upper * upper - fore * fore + length * length) / (2.0 * length)
	var center := shoulder + axis * along; var radius := sqrt(maxf(0.0, upper * upper - along * along))
	var radial := preferred - center; radial -= axis * radial.dot(axis)
	if radial.length_squared() < 0.000001: radial = Vector3.UP - axis * axis.y
	radial = radial.normalized()
	# Same +/- range as before, sampled every ELBOW_STEP_DEG instead of 5 deg.
	var stride := ELBOW_STEP_DEG / 5.0 if attempts > 3 else 1.0
	for index in range(ceili(attempts / stride)):
		var step := ceili(float(index) * 0.5) * (1.0 if index % 2 else -1.0) * stride
		var elbow := center + radial.rotated(axis, deg_to_rad(step * 5.0)) * radius
		var reference := Anatomy.forearm_reference(shoulder, elbow, wrist, Vector3.UP, left)
		var channels := Anatomy.decompose(reference, mount.basis * arm.articulated_hand.anatomical_basis, -1.0 if left else 1.0)
		if not channels.within_animation_budget or float(channels.coupled_budget_ratio) > WRIST_RESERVE: continue
		arm.upper_pivot.basis = Basis.IDENTITY
		arm.forearm_pivot.basis = Basis.IDENTITY
		arm.solve_ik(mount.origin, elbow, mount, wrist)
		if not verify_clearance or arm_clear(arm, geometry, REQUIRED_GAP): return {"elbow": elbow, "wrist": wrist, "channels": channels, "elbow_circle_deg": step * 5.0, "clearance_at_least_m": REQUIRED_GAP}
	return {}

static func search(player, snapshot_owner, pose) -> Dictionary:
	## The caller supplies its existing transactional rig snapshot adapter.
	## This search never leaves the actor in a trial state.
	if pose == null or int(pose.posture_id) != 20 or player.posture.editor_preview_mode: return {}
	var saved: Dictionary = snapshot_owner._snapshot()
	var origin: Transform3D = player.body_pivot.global_transform
	var paddle: Transform3D = player.paddle_node.global_transform
	var mounts: Array[Transform3D] = [player.right_arm_node.hand_mesh.global_transform, player.left_arm_node.hand_mesh.global_transform]
	var poles: Array[Vector3] = [player.right_arm_node.forearm_pivot.global_position, player.left_arm_node.forearm_pivot.global_position]
	var feet: Array[Vector3] = [player.right_leg_node.foot_pivot.global_position, player.left_leg_node.foot_pivot.global_position]
	var leg_bases: Array[Basis] = [player.right_leg_node.foot_pivot.global_basis, player.left_leg_node.foot_pivot.global_basis]
	var knees: Array[Vector3] = [player.right_leg_node.shin_pivot.global_position, player.left_leg_node.shin_pivot.global_position]
	var forward: Vector3 = player._get_forward_axis(); var lateral: Vector3 = player._get_forehand_axis()
	var directions: Array[Vector3] = [-forward, Vector3.DOWN, (-forward + Vector3.DOWN).normalized(), (-forward + lateral).normalized(), (-forward - lateral).normalized(), (Vector3.DOWN + lateral).normalized(), (Vector3.DOWN - lateral).normalized(), forward, (forward + Vector3.DOWN).normalized()]
	var existing: Vector3 = player.body_pivot.get_meta("live_transition_arm_reach", {}).get("world_offset", Vector3.ZERO)
	var result := {}; var best := INF; var trials := 0
	for direction in directions:
		if trials >= SEARCH_MAX_TRIALS: break
		for step in range(0, ceili(MAX_SHIFT / SEARCH_STEP) + 1):
			if trials >= SEARCH_MAX_TRIALS: break
			var distance := step * SEARCH_STEP
			if distance >= best: break
			if (existing + direction * distance).length() > load("res://scripts/live_transition_arm_reach.gd").MAX_BODY_SHIFT_M: continue
			snapshot_owner._restore(saved)
			player.body_pivot.global_transform = origin.translated(direction * distance)
			player.paddle_node.global_transform = paddle
			var feasible := true
			for side in [0, 1]:
				var leg = player.right_leg_node if side == 0 else player.left_leg_node
				if not Foot.reach_report(leg.thigh_pivot.global_position, feet[side], leg.thigh_length, leg.shin_length).feasible: feasible = false; break
			if not feasible: continue
			trials += 1
			var geometry := body_geometry(player)
			var solved: Array = []
			for side in [0, 1]:
				var arm = player.right_arm_node if side == 0 else player.left_arm_node
				var fit := _solve_arm(arm, mounts[side], poles[side], geometry, side == 1)
				if fit.is_empty(): feasible = false; break
				solved.append(fit)
			if not feasible: continue
			result = {"offset": direction * distance, "arms": solved, "mounts": mounts, "feet": feet, "foot_bases": leg_bases, "knees": knees, "paddle": paddle, "body": origin, "distance": distance, "trials": trials}
			best = distance; break
	snapshot_owner._restore(saved)
	return result

static func apply(player, candidate: Dictionary) -> bool:
	if candidate.is_empty(): return false
	player.body_pivot.global_transform = candidate.body.translated(candidate.offset)
	player.paddle_node.global_transform = candidate.paddle
	for side in [0, 1]:
		var arm = player.right_arm_node if side == 0 else player.left_arm_node
		var data: Dictionary = candidate.arms[side]
		var mount: Transform3D = candidate.mounts[side]
		arm.upper_pivot.basis = Basis.IDENTITY
		arm.forearm_pivot.basis = Basis.IDENTITY
		arm.solve_ik(mount.origin, data.elbow, mount, data.wrist)
		arm.articulated_hand.set_mesh_world_transform(mount)
		arm.articulated_hand.update_wrist_bridge(arm.fore_mesh.global_basis)
		var leg = player.right_leg_node if side == 0 else player.left_leg_node
		leg.solve_ik(candidate.feet[side], candidate.get("knees", [candidate.feet[0] + player._get_forward_axis() * 0.65 + Vector3.UP * 0.35, candidate.feet[1] + player._get_forward_axis() * 0.65 + Vector3.UP * 0.35])[side], 0.0)
		leg.foot_pivot.global_basis = candidate.foot_bases[side]
		leg._keep_sole_above_floor()
	return true

class Transaction:
	var actor
	func _init(owner): actor = owner
	func _snapshot(narrow: bool = false) -> Dictionary:
		var _pt := Time.get_ticks_usec()
		var _pr = _perf_snapshot(narrow)
		PerfMonitor.record("rig.snapshot", Time.get_ticks_usec() - _pt)
		return _pr

	func _perf_snapshot(narrow: bool = false) -> Dictionary:
		var nodes: Array = [{"node": actor, "transform": actor.transform}]
		var bones: Array = []
		var changed: Array = actor.find_children("*", "Node3D", true, false) if not narrow else [actor.body_pivot, actor.paddle_node]
		if narrow:
			for arm in [actor.right_arm_node, actor.left_arm_node]:
				changed.append_array([arm.upper_pivot, arm.forearm_pivot, arm.hand_pivot, arm.upper_mesh, arm.fore_mesh, arm.hand_mesh, arm.articulated_hand.skeleton])
				if arm.has_meta("arm_elbow_bridge"): changed.append(arm.get_meta("arm_elbow_bridge").skeleton)
			for leg in [actor.right_leg_node, actor.left_leg_node]:
				changed.append_array([leg.thigh_pivot, leg.shin_pivot, leg.foot_pivot, leg.thigh_mesh, leg.shin_mesh, leg.foot_mesh])
				if leg.has_meta("leg_knee_bridge"): changed.append(leg.get_meta("leg_knee_bridge").skeleton)
		for node in changed:
			nodes.append({"node": node, "transform": node.transform})
			if node is Skeleton3D:
				var poses: Array[Transform3D] = []; var channels: Array = []
				for index in node.get_bone_count():
					poses.append(node.get_bone_pose(index))
					channels.append([node.get_bone_pose_position(index), node.get_bone_pose_rotation(index), node.get_bone_pose_scale(index)])
				bones.append({"node": node, "poses": poses, "channels": channels})
		var arms: Array = []
		for arm in [actor.right_arm_node, actor.left_arm_node]:
			var model = arm.articulated_hand
			var fields: Dictionary = {}
			for key in ["_mode", "_closure", "_index_closure", "_support_style_weight", "_recovery_pose_key", "_last_wrist_axis", "pose_update_count", "bone_pose_write_count", "wrist_bridge_update_count"]: fields[key] = model.get(key)
			arms.append({"arm": arm, "wrist": arm.anatomical_wrist_world, "stretch": arm.visual_stretch, "lag": arm.visual_wrist_lag_deg, "fields": fields, "support_frame_present": arm.has_meta("live_support_frame"), "support_frame": arm.get_meta("live_support_frame", {}).duplicate(true)})
		var bridges: Array = []
		for pair in [[actor.right_arm_node, "arm_elbow_bridge"], [actor.left_arm_node, "arm_elbow_bridge"], [actor.right_leg_node, "leg_knee_bridge"], [actor.left_leg_node, "leg_knee_bridge"]]:
			if not pair[0].has_meta(pair[1]): continue
			var bridge = pair[0].get_meta(pair[1])
			var fields: Dictionary = {}
			for key in ["last_relative", "initialized", "bone_pose_write_count", "pose_version", "sampled_version", "sampled_vertices", "_triangles", "_points", "palette"]:
				var value: Variant = bridge.get(key)
				fields[key] = value.duplicate() if value is Array else value
			bridges.append({"bridge": bridge, "fields": fields})
		var skin = actor.body_pivot.get_meta("articulated_torso")
		return {"bridges": bridges, "nodes": nodes, "bones": bones, "arms": arms, "skin": skin, "pelvis": skin._last_pelvis,
			"abdomen": skin._last_abdomen, "chest": skin._last_chest, "skin_writes": skin.bone_pose_write_count,
			"right_report": actor.right_leg_node.reach_report.duplicate(true), "left_report": actor.left_leg_node.reach_report.duplicate(true)}
	
	func _restore(saved: Dictionary) -> void:
		var _pt := Time.get_ticks_usec()
		_perf_restore(saved)
		PerfMonitor.record("rig.restore", Time.get_ticks_usec() - _pt)

	func _perf_restore(saved: Dictionary) -> void:
		for item in saved.nodes: item.node.transform = item.transform
		for item in saved.bones:
			for index in item.poses.size():
				if item.has("channels"):
					item.node.set_bone_pose_position(index, item.channels[index][0])
					item.node.set_bone_pose_rotation(index, item.channels[index][1])
					item.node.set_bone_pose_scale(index, item.channels[index][2])
				else: item.node.set_bone_pose(index, item.poses[index])
		for item in saved.bridges:
			for key in item.fields: item.bridge.set(key, item.fields[key].duplicate() if item.fields[key] is Array else item.fields[key])
		for item in saved.arms:
			item.arm.anatomical_wrist_world = item.wrist; item.arm.visual_stretch = item.stretch; item.arm.visual_wrist_lag_deg = item.lag
			for key in item.fields: item.arm.articulated_hand.set(key, item.fields[key])
			if item.support_frame_present: item.arm.set_meta("live_support_frame", item.support_frame.duplicate(true))
			elif item.arm.has_meta("live_support_frame"): item.arm.remove_meta("live_support_frame")
		saved.skin._last_pelvis = saved.pelvis; saved.skin._last_abdomen = saved.abdomen; saved.skin._last_chest = saved.chest; saved.skin.bone_pose_write_count = saved.skin_writes
		actor.right_leg_node.reach_report = saved.right_report; actor.left_leg_node.reach_report = saved.left_report

static func _same_transform(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) <= 0.00002 and (a.basis.x - b.basis.x).length() <= 0.00002 and (a.basis.y - b.basis.y).length() <= 0.00002 and (a.basis.z - b.basis.z).length() <= 0.00002

static func _resource_changed(identity: int) -> void:
	_resource_versions[identity] = int(_resource_versions.get(identity, 0)) + 1

static func _resource_version(resource: Resource) -> Array:
	if resource == null: return []
	var identity := resource.get_instance_id()
	if not _resource_versions.has(identity):
		_resource_versions[identity] = 0
		resource.changed.connect(_resource_changed.bind(identity))
	return [identity, _resource_versions[identity], resource.get_surface_count()] if resource is Mesh else [identity, _resource_versions[identity]]

