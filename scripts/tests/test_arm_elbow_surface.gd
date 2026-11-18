extends SceneTree


const Visual = preload("res://scripts/player_arm_visual.gd")
const Clearance = preload("res://scripts/body_clearance.gd")
const Right = preload("res://scenes/right_arm.tscn")
const Left = preload("res://scenes/left_arm.tscn")
var checks: = 0
var failures: Array[String] = []
var report: Array[Dictionary] = []
class Pair extends Node3D:
	var right_arm_node
	var left_arm_node
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func posed_normal(bridge, arrays: Array, index: int) -> Vector3:
	var normal: Vector3 = arrays[Mesh.ARRAY_NORMAL][index]
	var result: = Vector3.ZERO
	for slot in range(4): result += bridge.palette[arrays[Mesh.ARRAY_BONES][index * 4 + slot]].basis * normal * arrays[Mesh.ARRAY_WEIGHTS][index * 4 + slot]
	return result.normalized()
func inspect(arm, label: String) -> void :
	var bridge = arm.get_meta(Visual.BRIDGE_META)
	var arrays: Array = arm.upper_mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = bridge.vertices()
	var fore_arrays: Array = arm.fore_mesh.mesh.surface_get_arrays(0)
	var fore_vertices: PackedVector3Array = fore_arrays[Mesh.ARRAY_VERTEX]
	var matched: = 0
	var max_gap: = 0.0
	var max_normal_delta: = 0.0
	for index in range(vertices.size()):
		var bind: Vector3 = arrays[Mesh.ARRAY_VERTEX][index]
		if absf(bind.y - (arm.upper_arm_length * 0.5 + Visual.JOIN_FROM_ELBOW)) > 1e-06: continue
		var point: Vector3 = arm.upper_mesh.global_transform * vertices[index]
		var normal: Vector3 = (arm.upper_mesh.global_basis * posed_normal(bridge, arrays, index)).normalized()
		var nearest: = INF
		var delta: = INF
		for other in range(fore_vertices.size()):
			if absf(fore_vertices[other].y - ( - arm.forearm_length * 0.5 + Visual.JOIN_FROM_ELBOW)) > 1e-06: continue
			var gap: float = point.distance_to(arm.fore_mesh.global_transform * fore_vertices[other])
			if gap < nearest:
				nearest = gap
				delta = normal.distance_to((arm.fore_mesh.global_basis * fore_arrays[Mesh.ARRAY_NORMAL][other]).normalized())
		max_gap = maxf(max_gap, nearest);max_normal_delta = maxf(max_normal_delta, delta);matched += 1
	check(matched == Visual.SIDES, label + " matching ring count")
	check(max_gap < 2e-06, label + " continuous positional join")
	check(max_normal_delta < 1e-05, label + " continuous shading normals")
	var triangles: PackedVector3Array = Clearance.mesh_surface_triangles(arm.upper_mesh)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	check(triangles.size() == indices.size(), label + " complete rendered topology exposed")
	var max_skin_error: = 0.0
	for index in range(triangles.size()): max_skin_error = maxf(max_skin_error, triangles[index].distance_to(vertices[indices[index]]))
	check(max_skin_error < 1e-08, label + " diagnostics use exact GPU bind math")
	var minimum_area: = INF
	var minimum_normal_dot: = 1.0
	for index in range(0, indices.size(), 3):
		var a: Vector3 = vertices[indices[index]]; var b: Vector3 = vertices[indices[index + 1]]; var c: Vector3 = vertices[indices[index + 2]]

		var normal: Vector3 = (c - a).cross(b - a)
		minimum_area = minf(minimum_area, normal.length() * 0.5)
		var expected: Vector3 = posed_normal(bridge, arrays, indices[index]) + posed_normal(bridge, arrays, indices[index + 1]) + posed_normal(bridge, arrays, indices[index + 2])
		minimum_normal_dot = minf(minimum_normal_dot, normal.normalized().dot(expected.normalized()))
	check(minimum_area > 1e-09, label + " nondegenerate bridge triangles")
	check(minimum_normal_dot > 0, label + " no inverted bridge faces")
	var before: int = bridge.bone_pose_write_count
	var builds: int = Visual.mesh_build_count
	for repeat in range(30): Visual.update_arm(arm);Clearance.mesh_surface_triangles(arm.upper_mesh);Clearance.mesh_surface_points(arm.upper_mesh)
	check(before == bridge.bone_pose_write_count, label + " idle bone writes remain zero")
	check(builds == Visual.mesh_build_count, label + " idle rebuilds remain zero")
	check(arm.upper_mesh.mesh.get_surface_count() == 1 and arm.fore_mesh.mesh.get_surface_count() == 1, label + " two original single-surface meshes")
	check(bridge.skeleton.get_bone_count() == 3, label + " fixed three-entry visual palette")
	report.append({"case": label, "join_gap_m": max_gap, "normal_delta": max_normal_delta, "minimum_triangle_area": minimum_area, "minimum_normal_dot": minimum_normal_dot, "triangles": triangles.size() / 3, "bone_writes": before})
func run() -> void :
	var pair: = Pair.new();pair.right_arm_node = Right.instantiate();pair.left_arm_node = Left.instantiate()
	pair.add_child(pair.right_arm_node);pair.add_child(pair.left_arm_node);root.add_child(pair)
	var material: = StandardMaterial3D.new()
	Visual.apply(pair, Color.BLUE, Color("dbb18b"), material)
	check(pair.right_arm_node.upper_mesh.mesh == pair.left_arm_node.upper_mesh.mesh, "same cached upper mesh per kit")
	check(pair.right_arm_node.fore_mesh.mesh == pair.left_arm_node.fore_mesh.mesh, "same cached forearm mesh")
	for court in [0, 1]:
		pair.rotation.y = PI * float(court)
		for arm in [pair.right_arm_node, pair.left_arm_node]:
			var left: bool = arm == pair.left_arm_node
			arm.position.x = - 0.2 if left else 0.2
			for degrees in [0.0, 30.0, 60.0, 90.0, 110.0, 130.0]:
				var shoulder: Vector3 = arm.upper_pivot.global_position
				var down: Vector3 = pair.global_basis * Vector3.DOWN
				var hinge: Vector3 = pair.global_basis * Vector3.RIGHT
				var elbow: Vector3 = shoulder + down * 0.35
				var wrist: Vector3 = elbow + Basis(hinge, deg_to_rad(degrees)) * down * 0.35
				arm.solve_ik(wrist, elbow, Transform3D(Basis.IDENTITY, wrist), wrist)
				var before_elbow: Vector3 = arm.forearm_pivot.global_position
				Visual.update_arm(arm)
				check(before_elbow == arm.forearm_pivot.global_position, "visual update preserves actual elbow exactly")
				check(absf(shoulder.distance_to(before_elbow) - 0.35) < 2e-06, "true upper link retained")
				check(arm.hand_pivot.global_position.distance_to(wrist) < 2e-06, "exact wrist endpoint")
				inspect(arm, "court%d/left%s/bend%.0f" % [court, left, degrees])

	pair.rotation = Vector3.ZERO
	var arm = pair.right_arm_node
	arm.position = Vector3(1.68475294113159, 1.32858562469483, 6.72631549835205)
	var elbow: = Vector3(1.87643659114838, 1.03580486774445, 6.72024726867676)
	var wrist: = Vector3(1.85985803604126, 0.821474611759186, 6.44404554367065)
	arm.solve_ik(wrist, elbow, Transform3D(Basis.IDENTITY, wrist), wrist)
	inspect(arm, "actual_vendor_natural_contact")
	var path: = "/workspace/shared/pickleball-hands/vendor-elbow-surface-test.json"
	var file: = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "records": report}, "  "))
	pair.free(); await process_frame
	for failure in failures: push_error(failure)
	print("ARM ELBOW SURFACE: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
