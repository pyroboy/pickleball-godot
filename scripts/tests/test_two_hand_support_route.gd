extends "res://scripts/tests/test_two_hand_backhand_grip.gd"


func run() -> void :
	var right_arm: = GripArm.new();root.add_child(right_arm)
	var left_arm: = GripArm.new();root.add_child(left_arm)
	var right_model: = Hand.new();right_model.initialize(right_arm, false)
	var left_model: = Hand.new();left_model.initialize(left_arm, true)
	var main: = Transform3D(Basis(Vector3.UP, deg_to_rad(105.0)), Vector3(0, 0.005, 0))
	var support: = Transform3D(Basis(Vector3.UP, deg_to_rad(315.0)), Vector3(0, 0.11825, 0))
	for model in [right_model, left_model]:
		var original: PackedVector3Array = model.sampled_triangles()
		var palm_basis: Basis = model.anatomical_basis
		var socket: Vector3 = model.wrist_socket
		var original_bones: Array[Transform3D] = []
		for bone in range(Hand.BONE_COUNT): original_bones.append(model.skeleton.get_bone_pose(bone))
		model.set_recovery_pose(1.0, 0.0, 0.4)
		var recovery_writes: int = model.bone_pose_write_count
		for repeat in range(60): model.set_recovery_pose(1.0, 0.0, 0.4)
		check(model.bone_pose_write_count == recovery_writes, "outward recovery pose caches unchanged requests")
		for open_weight in [0.0, 0.25, 0.5, 0.75, 1.0]:
			model.set_recovery_pose(open_weight, 0.0, 0.4)
			check(model.skeleton.get_bone_pose(0).is_equal_approx(original_bones[0]) and model.skeleton.get_bone_pose(16).is_equal_approx(original_bones[16]), "recovery articulation preserves rigid palm and wrist bridge")
			for digit in range(5):
				for joint in range(3):
					var bone: int = 1 + digit * 3 + joint
					var a: Vector3 = model.skeleton.get_bone_global_pose(bone).origin
					var b: Vector3 = model.skeleton.get_bone_global_pose(bone + 1).origin if joint < 2 else model.skeleton.get_bone_global_pose(bone) * model._data.tip_local[digit]
					check(absf(a.distance_to(b) - model._data.lengths[digit][joint]) < 1e-06, "recovery retains every finger segment length")
		model.set_pose("GRIP")
		check(model.sampled_triangles() == original, "recovery restores default GRIP exactly")
		model.set_pose("SUPPORT_GRIP")
		for bone in [0, 4, 5, 6, 7, 8, 9, 10, 11, 12, 16]:
			check(model.skeleton.get_bone_pose(bone).is_equal_approx(original_bones[bone]), "support route preserves palm, wrapped fingers and cuff %d" % bone)
		for digit in range(5):
			for joint in range(3):
				var bone: int = 1 + digit * 3 + joint
				var a: Vector3 = model.skeleton.get_bone_global_pose(bone).origin
				var b: Vector3 = model.skeleton.get_bone_global_pose(bone + 1).origin if joint < 2 else model.skeleton.get_bone_global_pose(bone) * model._data.tip_local[digit]
				check(absf(a.distance_to(b) - model._data.lengths[digit][joint]) < 1e-06, "support route preserves every fixed finger length")
		for bone in [13, 14, 15]: check(model.skeleton.get_bone_pose_rotation(bone).is_equal_approx(model._data.poses.OPEN[bone]), "support thumb retains verified OPEN")
		check(model.anatomical_basis.is_equal_approx(palm_basis) and model.wrist_socket == socket, "support route keeps rigid palm semantics and real wrist")
		var writes: int = model.bone_pose_write_count
		for repeat in range(60): model.set_pose("SUPPORT_GRIP")
		check(model.bone_pose_write_count == writes, "support route caches repeated requests")
		var dedicated: PackedVector3Array = model.sampled_triangles()
		model.set_pose("GRIP", 1.0, 0.4, 1.0)
		var blended: PackedVector3Array = model.sampled_triangles()
		var max_error: = 0.0
		for i in range(blended.size()): max_error = maxf(max_error, blended[i].distance_to(dedicated[i]))
		check(max_error < 1e-06, "GRIP style1 equals dedicated support endpoint regardless of old index closure")
		writes = model.bone_pose_write_count
		for repeat in range(60): model.set_pose("GRIP", 1.0, 0.4, 1.0)
		check(model.bone_pose_write_count == writes, "style requests cache")
		writes = model.bone_pose_write_count
		model.set_pose("GRIP", 1.0, 0.4, 0.5)
		check(model.bone_pose_write_count - writes == 6, "style-only change writes exactly index and thumb joints")
		for bone in [0, 4, 5, 6, 7, 8, 9, 10, 11, 12, 16]:
			check(model.skeleton.get_bone_pose(bone).is_equal_approx(original_bones[bone]), "style-only blend preserves palm, wrapped fingers and cuff")
		model.set_pose("GRIP")
		check(model.sampled_triangles() == original, "default GRIP geometry restores bit-for-bit")
		for mode in ["OPEN", "RELAXED", "CUP"]:
			model.set_pose(mode, 0.6)
			var normal: PackedVector3Array = model.sampled_triangles()
			writes = model.bone_pose_write_count
			check( not model.set_pose(mode, 0.6, 0.4, 1.0), "style ignored outside GRIP")
			check(model.bone_pose_write_count == writes and model.sampled_triangles() == normal, "non-GRIP mode remains exact")
		model.set_pose("GRIP")
	left_model.set_pose("SUPPORT_GRIP")
	var right: Dictionary = _geometry(right_model, main)
	var left: Dictionary = _geometry(left_model, support)
	for part in [0, 1, 3, 4, 5]:
		var hit: Dictionary = _head_intersections(left.parts[part], _head_planes())
		check(hit.penetrating_triangles == 0, "support component %d clears finite blade" % part)
	var middle: Dictionary = _head_intersections(left.parts[2], _head_planes())
	check(absf(middle.deepest_verified_point_m) < 0.0001, "unchanged middle throat contact remains below0.1mm")
	check(left.shaft_gap >= 0.00054, "support pads preserve actual handle seating gap")
	var ab: Dictionary = _hand_overlap(right, left); var ba: Dictionary = _hand_overlap(left, right)
	check(ab.penetrating_vertices + ba.penetrating_vertices == 0, "dedicated support route has no inter-hand contained skin vertices")
	check(ab.surface_crossings + ba.surface_crossings == 0, "dedicated support route has no inter-hand triangle crossing")
	var joints: Dictionary = left_model.joint_positions()
	var last: Vector3 = support * joints.index_mcp
	for key in ["index_pip", "index_dip", "index_tip"]:
		var point: Vector3 = support * joints[key]
		check(point.y > last.y and point.z > 0.023, "index follows +Y behind blade face")
		last = point
	for failure in failures: push_error(failure)
	print("Two-hand support route: %d checks, %d failures" % [checks, failures.size()])
	right_arm.queue_free();left_arm.queue_free(); await process_frame;quit(0 if failures.is_empty() else 1)
