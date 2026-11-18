extends RefCounted
## Isolated candidate. Exact displayed sleeve/torso surface test and bounded
## READY-only correction search. No authored pose/resource is modified.
const Surface = preload("res://scripts/player_surface_contacts.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const Hands = preload("res://scripts/player_hand_presentation.gd")
const Foot = preload("res://scripts/pose_foot_contacts.gd")
const Paddle = preload("res://scripts/paddle_dimensions.gd")
const SwingPath = preload("res://scripts/stroke_swing_path.gd")
const Geometry = preload("res://scripts/contact_surface_geometry.gd")
const REQUIRED_GAP := 0.001
const CERTIFICATE_FLOAT_RESERVE := 0.00001
const WRIST_RESERVE := 0.98
const JointSeam := 0.12
const MAX_SHIFT := 0.10
const STEP := 0.005
static var _bvh_topologies: Dictionary = {}
static var _resource_versions: Dictionary = {}

static func body_geometry(player) -> Dictionary:
	var skin = player.body_pivot.get_meta("articulated_torso")
	var inverse: Transform3D = player.body_pivot.global_transform.affine_inverse()
	var world := Surface.world_triangles(skin.body_mesh)
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
	return {"valid": true, "points": local, "bounds": bounds, "inverse": inverse, "tree": _refit(cached.tree, bounds)}

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
	for index in range(attempts):
		var step := ceili(float(index) * 0.5) * (1.0 if index % 2 else -1.0)
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
		for step in range(0, ceili(MAX_SHIFT / STEP) + 1):
			var distance := step * STEP
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

static func _displayed_arms_valid(player) -> bool:
	for side in [0, 1]:
		var arm = player.right_arm_node if side == 0 else player.left_arm_node
		var wrist: Vector3 = arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket
		var shoulder: Vector3 = arm.upper_pivot.global_position; var elbow: Vector3 = arm.forearm_pivot.global_position
		if absf(shoulder.distance_to(elbow) - arm.upper_arm_length) > 0.00002 or absf(elbow.distance_to(wrist) - arm.forearm_length) > 0.00002: return false
		if wrist.distance_to(arm.forearm_pivot.to_global(Vector3(0, 0, -arm.forearm_length))) > 0.00002: return false
		var channels := Anatomy.decompose(Anatomy.forearm_reference_for_arm(arm, wrist, side == 1), arm.hand_mesh.global_basis * arm.articulated_hand.anatomical_basis, -1.0 if side == 1 else 1.0)
		if not channels.within_animation_budget: return false
	return true

static func _presented_ready(player, pose) -> bool:
	if pose == null or int(pose.posture_id) != 20 or not load("res://scripts/live_transition_arm_reach.gd").enabled(player, pose): return false
	var feet = player.leg_ik
	if feet == null or not feet.right_foot_locked or not feet.left_foot_locked or feet._active_side >= 0 or feet._airborne or feet._run_active: return false
	if player.current_velocity.length() > 0.18: return false
	var canonical = PostureLibrary.instance().get_def(20)
	var paddle: Transform3D = player.paddle_node.global_transform
	if not _same_transform(paddle, SwingPath.world_transform(player, canonical)): return false
	var main := Transform3D(Hands.GripFrame.basis(paddle.basis, false, canonical.main_grip_rotation_deg - canonical.paddle_in_hand_rotation_deg), paddle * (Paddle.MAIN_GRIP_OFFSET + canonical.right_hand_offset))
	var support_origin: Vector3 = paddle * (Paddle.SUPPORT_GRIP_OFFSET + Vector3.UP * canonical.support_grip_slide_m)
	support_origin += player._get_forehand_axis() * canonical.left_hand_offset.x + Vector3.UP * canonical.left_hand_offset.y + player._get_forward_axis() * canonical.left_hand_offset.z
	var support := Transform3D(Hands.GripFrame.basis(paddle.basis, true, canonical.support_grip_rotation_deg - canonical.paddle_in_hand_rotation_deg), support_origin)
	return _same_transform(main, player.right_arm_node.hand_mesh.global_transform) and _same_transform(support, player.left_arm_node.hand_mesh.global_transform) and _displayed_arms_valid(player)

static func _resource_changed(identity: int) -> void:
	_resource_versions[identity] = int(_resource_versions.get(identity, 0)) + 1

static func _resource_version(resource: Resource) -> Array:
	if resource == null: return []
	var identity := resource.get_instance_id()
	if not _resource_versions.has(identity):
		_resource_versions[identity] = 0
		resource.changed.connect(_resource_changed.bind(identity))
	return [identity, _resource_versions[identity], resource.get_surface_count()] if resource is Mesh else [identity, _resource_versions[identity]]

static func _ready_signature(player, target: Transform3D) -> PackedByteArray:
	var skin = player.body_pivot.get_meta("articulated_torso")
	var values: Array = [player.global_transform, target, player.body_pivot.scale, skin._last_pelvis, skin._last_abdomen, skin._last_chest,
		_resource_version(skin.body_mesh.mesh), _resource_version(skin.body_mesh.skin), player.paddle_node.global_transform]
	for arm in [player.right_arm_node, player.left_arm_node]:
		values.append([arm.transform, arm.upper_pivot.position, arm.upper_pivot.scale, arm.forearm_pivot.position, arm.forearm_pivot.scale, arm.upper_mesh.transform, arm.fore_mesh.transform, arm.hand_mesh.global_transform,
			arm.upper_arm_length, arm.forearm_length, arm.articulated_hand.wrist_socket, arm.articulated_hand.anatomical_basis,
			_resource_version(arm.upper_mesh.mesh), _resource_version(arm.upper_mesh.skin), _resource_version(arm.fore_mesh.mesh)])
	for leg in [player.right_leg_node, player.left_leg_node]:
		values.append([leg.transform, leg.thigh_pivot.position, leg.thigh_pivot.scale, leg.shin_pivot.position, leg.shin_pivot.scale, leg.foot_pivot.global_transform, leg.foot_mesh.transform,
			leg.thigh_length, leg.shin_length, _resource_version(leg.foot_mesh.mesh)])
	return var_to_bytes(values)

static func _clipped_sleeves(arm, inverse: Transform3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var axis: Vector3 = (arm.forearm_pivot.global_position - shoulder).normalized()
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
			for fan in range(1, polygon.size() - 1):
				result.append(inverse * polygon[0]); result.append(inverse * polygon[fan]); result.append(inverse * polygon[fan + 1])
	return result

static func _clearance_certificate(player, gap: float, geometry: Dictionary) -> Dictionary:
	if not geometry.get("valid", false): return {}
	var key: Array = []
	var skin = player.body_pivot.get_meta("articulated_torso")
	for resource in [skin.body_mesh.mesh, skin.body_mesh.skin, player.right_arm_node.upper_mesh.mesh, player.right_arm_node.upper_mesh.skin, player.right_arm_node.fore_mesh.mesh, player.left_arm_node.upper_mesh.mesh, player.left_arm_node.upper_mesh.skin, player.left_arm_node.fore_mesh.mesh]: key.append(_resource_version(resource))
	var world_body := PackedVector3Array()
	var frame: Transform3D = geometry.inverse.affine_inverse()
	for point in geometry.points: world_body.append(frame * point)
	return {"gap": gap, "resources": key, "body": world_body, "main": _clipped_sleeves(player.right_arm_node, Transform3D.IDENTITY), "support": _clipped_sleeves(player.left_arm_node, Transform3D.IDENTITY)}

static func _vertex_displacement(first: PackedVector3Array, second: PackedVector3Array) -> float:
	if first.size() != second.size(): return INF
	var maximum := 0.0
	for index in first.size(): maximum = maxf(maximum, first[index].distance_to(second[index]))
	return maximum

static func _certificate_still_clear(player, previous: Dictionary) -> bool:
	if previous.is_empty(): return false
	var current := _clearance_certificate(player, 0.0, body_geometry(player))
	if current.is_empty(): return false
	if var_to_bytes(current.resources) != var_to_bytes(previous.resources): return false
	var body_change := _vertex_displacement(previous.body, current.body)
	var main_change := _vertex_displacement(previous.main, current.main)
	var support_change := _vertex_displacement(previous.support, current.support)
	# A point in a corresponding triangle is a convex combination of its
	# vertices. Thus the whole surface moves by at most this maximum; minimum
	# separation can decrease by no more than the sum of both surface bounds.
	# Preserve ten extra micrometres for float arithmetic, never round a key.
	return body_change + maxf(main_change, support_change) + CERTIFICATE_FLOAT_RESERVE <= float(previous.gap) - REQUIRED_GAP

static func apply_presented_ready(player, pose) -> Dictionary:
	var _pt := Time.get_ticks_usec()
	var _pr = _perf_apply_presented_ready(player, pose)
	PerfMonitor.record("arm.ready_clearance", Time.get_ticks_usec() - _pt)
	return _pr

static func _perf_apply_presented_ready(player, pose) -> Dictionary:
	# Bounded post-Budget hook candidate. Never requests or resets a pose.
	var started := Time.get_ticks_usec()
	var report := {"eligible": false, "active": false, "feasible": false, "offset": Vector3.ZERO}
	if not _presented_ready(player, pose): report["reason"] = "actual presentation is not supported seated READY"; return report
	report.eligible = true
	var existing: Vector3 = player.body_pivot.get_meta("live_transition_arm_reach", {}).get("world_offset", Vector3.ZERO)
	var canonical_body: Transform3D = player.body_pivot.global_transform.translated(-existing)
	var previous: Dictionary = player.body_pivot.get_meta("live_ready_clearance", {})
	var target: Transform3D = player.body_pivot.global_transform.translated(Vector3.DOWN * 0.005)
	# The ordinary reach fitter's preferred elbow can change its minimum offset
	# after clearance conditioning. Keep the already certified target, rather
	# than stacking another relative shift on that changed minimum.
	if previous.get("active", false) and _same_transform(canonical_body, previous.get("canonical_body", Transform3D.IDENTITY)):
		target = previous.get("body_target", target)
	var signature := _ready_signature(player, target)
	var cache: Dictionary = player.body_pivot.get_meta("_ready_clearance_exact_cache", {})
	if cache.get("signature", PackedByteArray()) == signature:
		apply(player, cache.candidate)
		report = cache.report.duplicate(true); report["cached_exact_result"] = true
		report["microseconds"] = Time.get_ticks_usec() - started
		player.body_pivot.set_meta("live_ready_clearance", report.duplicate(true))
		return report
	# Reuse a previous separated surface only with a proved displacement bound.
	# Actual mounts and feet remain the current inputs, not cached contacts.
	var certificate: Dictionary = cache.get("certificate", {})
	if not certificate.is_empty() and _same_transform(target, cache.candidate.body.translated(cache.candidate.offset)):
		var trial_owner := Transaction.new(player); var trial_saved := trial_owner._snapshot(true)
		var trial: Dictionary = cache.candidate.duplicate(true)
		trial.body = target; trial.offset = Vector3.ZERO; trial.paddle = player.paddle_node.global_transform
		trial.mounts = [player.right_arm_node.hand_mesh.global_transform, player.left_arm_node.hand_mesh.global_transform]
		trial.feet = [player.right_leg_node.foot_pivot.global_position, player.left_leg_node.foot_pivot.global_position]
		trial.foot_bases = [player.right_leg_node.foot_pivot.global_basis, player.left_leg_node.foot_pivot.global_basis]
		trial.knees = [player.right_leg_node.shin_pivot.global_position, player.left_leg_node.shin_pivot.global_position]
		player.body_pivot.global_transform = target; player.paddle_node.global_transform = trial.paddle
		var allowed := true; var adjusted: Array = []
		for side in [0, 1]:
			var arm = player.right_arm_node if side == 0 else player.left_arm_node
			var leg = player.right_leg_node if side == 0 else player.left_leg_node
			if not Foot.reach_report(leg.thigh_pivot.global_position, trial.feet[side], leg.thigh_length, leg.shin_length).feasible: allowed = false; break
			var fit := _solve_arm(arm, trial.mounts[side], trial.arms[side].elbow, {}, side == 1, 1, false)
			if fit.is_empty(): allowed = false; break
			adjusted.append(fit)
		if allowed:
			trial.arms = adjusted; apply(player, trial)
			allowed = _displayed_arms_valid(player) and _certificate_still_clear(player, certificate)
		if allowed:
			report = cache.report.duplicate(true); report["certified_displacement_reuse"] = true
			report["microseconds"] = Time.get_ticks_usec() - started
			player.body_pivot.set_meta("live_ready_clearance", report.duplicate(true))
			return report
		trial_owner._restore(trial_saved)
	var geometry := body_geometry(player)
	if not geometry.get("valid", false): report["reason"] = "missing torso triangles"; report["microseconds"] = Time.get_ticks_usec() - started; return report
	if arm_clear(player.right_arm_node, geometry, REQUIRED_GAP) and arm_clear(player.left_arm_node, geometry, REQUIRED_GAP):
		report.feasible = true; report["microseconds"] = Time.get_ticks_usec() - started; return report
	var transaction := Transaction.new(player); var saved := transaction._snapshot(true)
	var offset: Vector3 = target.origin - player.body_pivot.global_position
	if (existing + offset).length() > load("res://scripts/live_transition_arm_reach.gd").MAX_BODY_SHIFT_M: report["reason"] = "existing body correction leaves no reserve"; return report
	var candidate := {"body": player.body_pivot.global_transform, "offset": offset, "paddle": player.paddle_node.global_transform,
		"mounts": [player.right_arm_node.hand_mesh.global_transform, player.left_arm_node.hand_mesh.global_transform],
		"feet": [player.right_leg_node.foot_pivot.global_position, player.left_leg_node.foot_pivot.global_position],
		"foot_bases": [player.right_leg_node.foot_pivot.global_basis, player.left_leg_node.foot_pivot.global_basis],
		"knees": [player.right_leg_node.shin_pivot.global_position, player.left_leg_node.shin_pivot.global_position], "arms": []}
	var poles: Array[Vector3] = [player.right_arm_node.forearm_pivot.global_position, player.left_arm_node.forearm_pivot.global_position]
	player.body_pivot.global_position += offset; player.paddle_node.global_transform = candidate.paddle
	geometry = body_geometry(player)
	var feasible := true
	for side in [0, 1]:
		var arm = player.right_arm_node if side == 0 else player.left_arm_node
		var leg = player.right_leg_node if side == 0 else player.left_leg_node
		if not Foot.reach_report(leg.thigh_pivot.global_position, candidate.feet[side], leg.thigh_length, leg.shin_length).feasible: feasible = false; break
		var fitted := _solve_arm(arm, candidate.mounts[side], poles[side], geometry, side == 1, 3)
		if fitted.is_empty(): feasible = false; break
		candidate.arms.append(fitted)
	transaction._restore(saved)
	if feasible:
		apply(player, candidate)
		report.active = true; report.feasible = true; report.offset = offset
		report["body_after"] = player.body_pivot.transform
		report["body_target"] = player.body_pivot.global_transform
		report["canonical_body"] = canonical_body
		report["clearance_at_least_m"] = REQUIRED_GAP; report["proximal_joint_seam_m"] = JointSeam
		player.body_pivot.set_meta("live_ready_clearance", report.duplicate(true))
		var certificate_geometry := body_geometry(player)
		var separated := arm_clear(player.right_arm_node, certificate_geometry, REQUIRED_GAP + 0.0001) and arm_clear(player.left_arm_node, certificate_geometry, REQUIRED_GAP + 0.0001)
		var proof := _clearance_certificate(player, REQUIRED_GAP + 0.0001, certificate_geometry) if separated else {}
		player.body_pivot.set_meta("_ready_clearance_exact_cache", {"signature": signature, "candidate": candidate.duplicate(true), "report": report.duplicate(true), "certificate": proof})
	else: report["reason"] = "bounded READY candidate is not physically feasible"
	report["microseconds"] = Time.get_ticks_usec() - started
	return report
