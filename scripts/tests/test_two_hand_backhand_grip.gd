extends "res://scripts/tests/test_two_hand_vendor_grip.gd"



const Presentation = preload("res://scripts/player_hand_presentation.gd")
const Reach = preload("res://scripts/paddle_wrist_reach.gd")
const SwingPath = preload("res://scripts/stroke_swing_path.gd")

class GripArm extends Node3D:
	var hand_mesh: = MeshInstance3D.new()
	var articulated_hand
	func _init() -> void : add_child(hand_mesh)

class GripPlayer extends Node3D:
	var right_arm_node: = GripArm.new()
	var left_arm_node: = GripArm.new()
	var paddle_node: = Node3D.new()
	func _init() -> void :
		add_child(right_arm_node);add_child(left_arm_node);add_child(paddle_node)




func _small_triangle_hit(origin: Vector3, direction: Vector3, a: Vector3, b: Vector3, c: Vector3, segment: bool = false):
	var e1: Vector3 = b - a; var e2: Vector3 = c - a
	var h: Vector3 = direction.cross(e2)
	var determinant: float = e1.dot(h)
	if absf(determinant) < 1e-12: return null
	var inverse: float = 1.0 / determinant
	var s: Vector3 = origin - a
	var u: float = inverse * s.dot(h)
	if u < - 1e-07 or u > 1.0000001: return null
	var q: Vector3 = s.cross(e1)
	var v: float = inverse * direction.dot(q)
	if v < - 1e-07 or u + v > 1.0000001: return null
	var t: float = inverse * e2.dot(q)
	if t <= 1e-07 or (segment and t >= 0.9999999): return null
	return origin + direction * t

func _inside_component(point: Vector3, triangles: PackedVector3Array) -> bool:


	var directions: Array[Vector3] = [Vector3(0.931, 0.217, 0.293).normalized(), Vector3(0.173, 0.947, 0.272).normalized(), Vector3(0.311, 0.191, 0.931).normalized()]
	var votes: = 0
	for direction in directions:
		var distances: Array[float] = []
		for i in range(0, triangles.size(), 3):
			var hit = _small_triangle_hit(point, direction, triangles[i], triangles[i + 1], triangles[i + 2])
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
				var hit = _small_triangle_hit(a_points[i + edge], a_points[i + (edge + 1) % 3] - a_points[i + edge], other[j], other[j + 1], other[j + 2], true)
				if hit != null: crossings += 1;break
	return {"penetrating_vertices": hits.size(), "max_verified_vertex_depth_m": deepest, "surface_crossings": crossings, "points": hits, "bounds_disjoint": false}

func _geometry(model, mount: Transform3D) -> Dictionary:
	model.set_mesh_world_transform(mount)
	var points: = PackedVector3Array()
	for point in model.sampled_triangles(): points.append(mount * point)
	var arrays: Array = model.hand_mesh.mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var skin: = PackedVector3Array()
	var parts: Array = []
	for unused in range(6): parts.append(PackedVector3Array())
	var shaft_gap: = INF
	for i in range(0, points.size(), 3):
		shaft_gap = minf(shaft_gap, _axis_distance(points[i], points[i + 1], points[i + 2]) - D.HANDLE_RADIUS)
		if colors[indices[i]].is_equal_approx(Hand.NAIL_COLOR): continue
		var component: int = _component(bones[indices[i] * 4])
		var component_points: PackedVector3Array = parts[component]
		for j in range(3):
			component_points.append(points[i + j]);skin.append(points[i + j])
		parts[component] = component_points
	return {"triangles": points, "skin": skin, "parts": parts, "shaft_gap": shaft_gap}

func _check_index_cache(model) -> void :
	model.set_pose("GRIP")
	var original: PackedVector3Array = model.sampled_triangles()
	var cuff: Transform3D = model.skeleton.get_bone_pose(Hand.WRIST_BRIDGE_BONE)
	var other: Array[Transform3D] = []
	for bone in range(4, Hand.BONE_COUNT): other.append(model.skeleton.get_bone_pose(bone))
	var writes: int = model.bone_pose_write_count
	check(model.set_pose("GRIP", 1.0, 0.8), "index-only request applies")
	check(model.bone_pose_write_count - writes == 3, "index-only change writes only three index bones")
	for bone in range(4, Hand.BONE_COUNT):
		check(model.skeleton.get_bone_pose(bone).is_equal_approx(other[bone - 4]), "index-only change preserves bone %d" % bone)
	check(model.skeleton.get_bone_pose(Hand.WRIST_BRIDGE_BONE).is_equal_approx(cuff), "index-only closure preserves cuff")
	writes = model.bone_pose_write_count
	for repeat in range(60): model.set_pose("GRIP", 1.0, 0.8)
	check(model.bone_pose_write_count == writes, "identical index closure is cached")
	model.set_pose("GRIP")
	check(model.sampled_triangles() == original, "default GRIP restores exact original forehand triangles")
	for mode in ["OPEN", "RELAXED", "CUP"]:
		model.set_pose(mode, 0.6)
		var normal: PackedVector3Array = model.sampled_triangles()
		writes = model.bone_pose_write_count
		check( not model.set_pose(mode, 0.6, 0.2), "index override is ignored outside GRIP")
		check(model.bone_pose_write_count == writes and model.sampled_triangles() == normal, "non-GRIP default geometry remains exact")
	model.set_pose("GRIP")

func run() -> void :
	var fixture: = GripPlayer.new();root.add_child(fixture)
	var presentation: = Presentation.new();presentation.initialize(fixture)
	for arm in [fixture.right_arm_node, fixture.left_arm_node]: _check_index_cache(arm.articulated_hand)
	var rows: Array = []
	for profile in [Vector4(105, 15, 0.4, 0.02), Vector4(110, 20, 0.4, 0.02), Vector4(120, 30, 0.6, 0.02), Vector4(150, 60, 0.8, 0.02), Vector4(160, 65, 0.8, 0.02), Vector4(105, 195, 0.4, 0.005), Vector4(135, 225, 0.6, 0.005)]:
		var angles: = Vector2(profile.x, profile.y)
		for support_y in [0.11825 if profile.w < 0.01 else 0.1175]:
			var pose: = PostureDefinition.new()
			pose.paddle_hand = 0;pose.left_hand_mode = 1
			pose.paddle_forehand_mul = 0.0;pose.paddle_forward_mul = 0.0;pose.paddle_y_offset = D.HEAD_CENTER_Y
			pose.paddle_pitch_base_deg = 0.0;pose.paddle_yaw_base_deg = 0.0;pose.paddle_roll_base_deg = 0.0
			pose.paddle_pitch_signed_deg = 0.0;pose.paddle_yaw_signed_deg = 0.0;pose.paddle_roll_signed_deg = 0.0
			pose.right_hand_offset = Vector3(0, profile.w - D.MAIN_GRIP_Y, 0)
			pose.main_grip_rotation_deg = angles.x - 135.0
			pose.support_grip_rotation_deg = angles.y + 45.0
			pose.support_grip_slide_m = support_y - D.SUPPORT_GRIP_Y
			pose.support_index_closure = profile.z
			var main: Transform3D = presentation.main_mount(fixture.right_arm_node, D.MAIN_GRIP_OFFSET + pose.right_hand_offset, Basis.IDENTITY, pose)
			var support: Transform3D = presentation.support_mount(fixture.left_arm_node, D.SUPPORT_GRIP_OFFSET + Vector3.UP * pose.support_grip_slide_m, pose, true)
			var right: Dictionary = _geometry(fixture.right_arm_node.articulated_hand, main)
			var left: Dictionary = _geometry(fixture.left_arm_node.articulated_hand, support)
			var label: = "main%.0f support%.0f y%.4f" % [angles.x, angles.y, support_y]
			check(main.basis.determinant() > 0.99999 and support.basis.determinant() > 0.99999, label + " proper rigid bases")
			check((main * fixture.right_arm_node.articulated_hand.wrist_socket).distance_to(Reach.wrist_world(Transform3D.IDENTITY, pose)) < 1e-06, label + " visible/pure main real wrist agree")
			check((support * fixture.left_arm_node.articulated_hand.wrist_socket).distance_to(SwingPath.support_wrist_offset(pose)) < 1e-06, label + " visible/pure support real wrist agree")
			var blades: Array = []
			for hand in [right, left]:
				var blade: Dictionary = _head_intersections(hand.triangles, _head_planes());blades.append(blade)
				check(blade.penetrating_triangles == 0, label + " exact triangles clear blade")
				check(hand.shaft_gap >= 0.0005, label + " complete triangles retain calibrated shaft gap")
			var ab: Dictionary = _hand_overlap(right, left)
			var ba: Dictionary = _hand_overlap(left, right)
			check(ab.penetrating_vertices == 0 and ba.penetrating_vertices == 0, label + " closed skin volumes do not overlap")
			check(ab.surface_crossings == 0 and ba.surface_crossings == 0, label + " skin surfaces do not cross")
			if profile.w > 0.01:
				check(_aabb(right.parts[4]).position.y > 0.0027, label + " entire main little-finger skin remains on finite handle")
			else:
				check(_aabb(right.parts[3]).position.y > 0.00047, label + " ring finger stays on handle despite honest little-finger overhang")
				check(_aabb(right.parts[4]).position.y > - 0.01229, label + " little-finger overhang is at most12.29mm")
			if angles == Vector2(105, 15):
				var tight_mount: = Transform3D(support.basis, support.origin - Vector3.UP * 0.0025)
				var tight: Dictionary = _geometry(fixture.left_arm_node.articulated_hand, tight_mount)
				check(_hand_overlap(right, tight).surface_crossings > 0, "strengthened oracle rejects old115mm support false-pass")
			rows.append({"label": label, "main_wrist": _v(main * fixture.right_arm_node.articulated_hand.wrist_socket), "support_wrist": _v(support * fixture.left_arm_node.articulated_hand.wrist_socket), "main_triangles": _vectors(right.triangles), "support_triangles": _vectors(left.triangles), "main_parts": right.parts.map( func(part): return _vectors(part)), "support_parts": left.parts.map( func(part): return _vectors(part)), "main_shaft_gap_m": right.shaft_gap, "support_shaft_gap_m": left.shaft_gap, "blades": blades, "right_inside_left": ab, "left_inside_right": ba})
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			var output: = FileAccess.open(argument.trim_prefix("--output="), FileAccess.WRITE)
			output.store_string(JSON.stringify({"checks": checks, "failures": failures, "rows": rows}, "\t"));output.close()
	for failure in failures: push_error(failure)
	print("TWO-HAND BACKHAND GRIP: ", checks, " checks, ", failures.size(), " failures")
	fixture.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
