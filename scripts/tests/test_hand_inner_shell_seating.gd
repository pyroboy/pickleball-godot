extends SceneTree

const Hand = preload("res://scripts/articulated_hand.gd")
const Before = preload("res://scripts/tests/fixtures/articulated_hand_preview3.gd")
const D = preload("res://scripts/paddle_dimensions.gd")
const OUT: = "/workspace/shared/pickleball-hands/postpreview-palm-shell-actual.json"
var checks: = 0
var failures: Array[String] = []
var records: Array[Dictionary] = []
class MockArm extends Node3D:
	var hand_mesh: = MeshInstance3D.new()
	func _init() -> void : add_child(hand_mesh)
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func clip_y(poly: PackedVector3Array, threshold: float, above: bool) -> PackedVector3Array:
	var result: = PackedVector3Array()
	for i in range(poly.size()):
		var a: Vector3 = poly[i]; var b: Vector3 = poly[(i + 1) % poly.size()]
		var da: float = (a.y - threshold) * (1.0 if above else -1.0)
		var db: float = (b.y - threshold) * (1.0 if above else -1.0)
		if da >= 0: result.append(a)
		if da * db < 0: result.append(a + (b - a) * (da / (da - db)))
	return result
func triangle_handle_gap(triangle: PackedVector3Array) -> float:
	var poly: = clip_y(triangle, - D.MAIN_GRIP_Y, true)
	if poly.size() < 3: return INF
	poly = clip_y(poly, D.HANDLE_LENGTH - D.MAIN_GRIP_Y, false)
	if poly.size() < 3: return INF
	var flat: = PackedVector2Array()
	for p in poly: flat.append(Vector2(p.x, p.z))
	if Geometry2D.is_point_in_polygon(Vector2.ZERO, flat): return - D.HANDLE_RADIUS
	var nearest: = INF
	for i in range(flat.size()):
		var a: Vector2 = flat[i]; var v: Vector2 = flat[(i + 1) % flat.size()] - a
		var t: float = clampf( - a.dot(v) / maxf(v.length_squared(), 1e-15), 0, 1)
		nearest = minf(nearest, (a + v * t).length())
	return nearest - D.HANDLE_RADIUS
func handle_gap(triangles: PackedVector3Array, first: int = 0, last: int = -1) -> float:
	var result: = INF
	if last < 0: last = triangles.size() / 3
	for i in range(first, last): result = minf(result, triangle_handle_gap(PackedVector3Array([triangles[i * 3], triangles[i * 3 + 1], triangles[i * 3 + 2]])))
	return result
func sphere_gap(triangles: PackedVector3Array, center: Vector3, first: int, last: int) -> float:
	var result: = INF
	for i in range(first, last):
		var closest: Vector3 = Hand._closest_triangle_point(center, triangles[i * 3], triangles[i * 3 + 1], triangles[i * 3 + 2])
		result = minf(result, center.distance_to(closest) - Hand.BALL_RADIUS)
	return result
func bind_triangles(model) -> PackedVector3Array:


	var result: = PackedVector3Array()
	for index in model._data.indices: result.append(model._data.vertices[index])
	return result
func run() -> void :
	for left in [false, true]:
		var arm: = MockArm.new();root.add_child(arm)
		var old_arm: = MockArm.new();root.add_child(old_arm)
		var model: = Hand.new();model.initialize(arm, left);model.set_pose("GRIP")
		var old: = Before.new();old.initialize(old_arm, left);old.set_pose("GRIP")
		var new_bind: PackedVector3Array = bind_triangles(model)
		var old_bind: PackedVector3Array = bind_triangles(old)
		check(new_bind.size() == old_bind.size() and new_bind.size() / 3 == 702, "unchanged triangle topology")
		check(model.wrist_socket == old.wrist_socket and model.middle_mcp_rest == old.middle_mcp_rest, "unchanged wrist/MCP landmarks")
		check(model.anatomical_basis == old.anatomical_basis and model.palm_contact_basis == old.palm_contact_basis, "unchanged anatomical/contact frames")
		check(model._data.palm_patch == old._data.palm_patch, "all CUP patch triangles exactly preserved")
		check(model.cup_ball_center == old.cup_ball_center, "exact CUP anchor")
		var changed: Dictionary = {}; var affected: Array[int] = []; var maximum_delta: = 0.0
		for i in range(new_bind.size()):
			var delta: float = new_bind[i].distance_to(old_bind[i])
			if delta < 1e-07: continue
			changed[old_bind[i]] = new_bind[i];maximum_delta = maxf(maximum_delta, delta)
			var triangle: int = i / 3
			if not affected.has(triangle): affected.append(triangle)
			check(triangle in [44, 45, 46, 60, 61, 62, 63, 76, 77, 78, 79, 93, 94, 95, 592, 593, 594, 595, 596, 597, 598, 609, 610, 611, 612, 613, 614, 615], "only authorized inner shell triangles change")
		check(changed.size() == 6, "exactly six unique inner vertices")
		check(maximum_delta < 0.0056, "local correction bounded below5.6mm")
		for triangle in range(32):
			for corner in range(3): check(new_bind[triangle * 3 + corner] == old_bind[triangle * 3 + corner], "cuff triangles unchanged")
		var grip: PackedVector3Array = model.sampled_triangles()
		var whole_gap: float = handle_gap(grip)
		var palm_gap: float = handle_gap(grip, 32, 96)
		var thumb_gap: float = handle_gap(grip, 584, 702)
		check(whole_gap > 0.0005 and whole_gap < 0.0006, "whole actual grip retains0.55mm clearance")
		check(palm_gap > 0.0005 and palm_gap < 0.00075, "inner palm seats without chord penetration")
		check(thumb_gap > 0.0011 and thumb_gap < 0.0016, "opposed thumb shell gap is bounded")
		var minimum_thumb_gap: = INF
		var max_full_sphere_error: = 0.0
		for step in range(65):
			model.set_pose("CUP", float(step) / 64.0)
			var triangles: PackedVector3Array = model.sampled_triangles()
			var gap: float = sphere_gap(triangles, model.cup_ball_center, 0, 702)
			var thumb_sphere_gap: float = sphere_gap(triangles, model.cup_ball_center, 584, 702)
			minimum_thumb_gap = minf(minimum_thumb_gap, thumb_sphere_gap);max_full_sphere_error = maxf(max_full_sphere_error, absf(gap))
			check(absf(gap) < 2e-06, "full CUP/release skin retains exact sphere tangency")
			check(thumb_sphere_gap > 0.0023, "opposed thumb remains outside sphere throughout release")
		model.set_pose("GRIP")
		var writes: int = model.bone_pose_write_count; var builds: int = Hand.mesh_build_count
		for repeat in range(30): model.set_pose("GRIP")
		check(writes == model.bone_pose_write_count and builds == Hand.mesh_build_count, "no idle bone writes or geometry rebuilds")
		records.append({"left": left, "changed_unique_vertices": changed.size(), "affected_triangles": affected, "maximum_displacement_m": maximum_delta, "grip_gap_m": whole_gap, "palm_gap_m": palm_gap, "thumb_gap_m": thumb_gap, "minimum_release_thumb_gap_m": minimum_thumb_gap, "maximum_sphere_error_m": max_full_sphere_error})
		arm.free();old_arm.free()
	var file: = FileAccess.open(OUT, FileAccess.WRITE);file.store_string(JSON.stringify({"checks": checks, "failures": failures, "records": records}, "  "));file.close()
	await process_frame
	for failure in failures: push_error(failure)
	print("HAND INNER SHELL: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
