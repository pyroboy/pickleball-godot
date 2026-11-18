extends "res://scripts/tests/test_scaled_body_gait.gd"

const Knee = preload("res://scripts/player_leg_visual.gd")
const Surface = preload("res://scripts/body_clearance.gd")
var knee_frames: = 0
var worst_join: = 0.0
var minimum_front_alignment: = 1.0
var knee_builds: = -1
func _initialize() -> void :
	output = "/workspace/shared/pickleball-hands/postpreview-knee-runtime.json"
	super._initialize()
func _test_model(p, pose: PostureDefinition) -> void :


	reset(p, pose)
	for leg in [p.right_leg_node, p.left_leg_node]:
		check(is_equal_approx(leg.thigh_length, D.THIGH_LENGTH) and is_equal_approx(leg.shin_length, D.SHIN_LENGTH), "unchanged true leg dimensions")
		check(leg.foot_mesh.mesh.get_aabb().size.is_equal_approx(Vector3(0.1, 0.05, 0.16)), "unchanged shoe envelope")
	if knee_builds < 0: knee_builds = Knee.mesh_build_count
	for id in [6, 7, 8, 9, 10, 11]:
		var path: String = ""
		for name in DirAccess.get_files_at("res://data/postures"):
			if name.begins_with("%02d_" % id): path = "res://data/postures/" + name;break
		if path.is_empty(): continue
		var candidate: PostureDefinition = load(path).duplicate(true)
		reset(p, candidate)
		for leg in [p.right_leg_node, p.left_leg_node]: _knee(leg, "planted/posture%d" % id)
	reset(p, pose)
func tick(p, pose: PostureDefinition, velocity: Vector3, delta: float) -> void :
	super.tick(p, pose, velocity, delta)
	for leg in [p.right_leg_node, p.left_leg_node]: _knee(leg, "actual gait")
func _knee(leg, label: String) -> void :
	knee_frames += 1
	var bridge = leg.get_meta(Knee.BRIDGE_META)
	var hip: Vector3 = leg.thigh_pivot.global_position; var knee: Vector3 = leg.shin_pivot.global_position; var ankle: Vector3 = leg.foot_pivot.global_position
	var thigh_before: Transform3D = leg.thigh_mesh.global_transform
	var shin_before: Transform3D = leg.shin_mesh.global_transform
	var foot_before: Transform3D = leg.foot_mesh.global_transform
	var writes: int = bridge.bone_pose_write_count
	Knee.update_leg(leg)
	check(writes == bridge.bone_pose_write_count, label + " no duplicate visual writes")
	check(Knee.mesh_build_count == knee_builds, label + " no mesh rebuilds")
	check(thigh_before == leg.thigh_mesh.global_transform and shin_before == leg.shin_mesh.global_transform and foot_before == leg.foot_mesh.global_transform, label + " visual update preserves exact limb/sole transforms")
	var arrays: Array = leg.thigh_mesh.mesh.surface_get_arrays(0)
	var posed: PackedVector3Array = bridge.vertices()
	var lower: Array = leg.shin_mesh.mesh.surface_get_arrays(0)
	var local_lower: PackedVector3Array = lower[Mesh.ARRAY_VERTEX]
	var gap: = 0.0
	for i in range(posed.size()):
		if absf(arrays[Mesh.ARRAY_VERTEX][i].y - (leg.thigh_length * 0.5 + Knee.JOIN_FROM_KNEE)) > 1e-06: continue
		var point: Vector3 = leg.thigh_mesh.global_transform * posed[i]
		var nearest: = INF
		for other in local_lower:
			if absf(other.y - ( - leg.shin_length * 0.5 + Knee.JOIN_FROM_KNEE)) > 1e-06: continue
			nearest = minf(nearest, point.distance_to(leg.shin_mesh.global_transform * other))
		gap = maxf(gap, nearest)
	worst_join = maxf(worst_join, gap)
	check(gap < 1e-05, label + " exact skin join under actual planner")
	var axis: Vector3 = (ankle - hip).normalized()
	var front: Vector3 = knee - hip - axis * (knee - hip).dot(axis)
	if front.length() > 0.003:
		var actual: Vector3 = (leg.thigh_mesh.global_basis * bridge.palette[1].basis * Vector3.BACK).normalized()
		var alignment: float = actual.dot(front.normalized())
		minimum_front_alignment = minf(minimum_front_alignment, alignment)
		check(alignment > 0.98, label + " patella faces actual knee pole")
	check(Surface.mesh_surface_triangles(leg.thigh_mesh).size() == arrays[Mesh.ARRAY_INDEX].size(), label + " actual skinned triangles remain visible to diagnostics")
	if knee_frames % 1000 == 0: print("KNEE RUNTIME samples=", knee_frames, " worst_join=", worst_join, " front=", minimum_front_alignment)
