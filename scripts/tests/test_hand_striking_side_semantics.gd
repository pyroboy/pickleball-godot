extends SceneTree






const Hand = preload("res://scripts/articulated_hand.gd")
var checks: = 0
var failures: Array[String] = []
class MockArm extends Node3D:
	var hand_mesh: = MeshInstance3D.new()
	func _init() -> void : add_child(hand_mesh)
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)



static func contact_side(model, mesh_world_basis: Basis, ball_side_normal: Vector3, is_forehand: bool) -> Dictionary:
	var surface: Dictionary = dorsal_surface(model)
	var dorsal: Vector3 = (mesh_world_basis.orthonormalized() * surface.normal).normalized()
	var dot_value: float = dorsal.dot(ball_side_normal.normalized())
	return {"dot": dot_value, "hemisphere": "PALMAR" if dot_value < - 0.001 else ("DORSAL" if dot_value > 0.001 else "EDGE_ON"), 
		"expected": "PALMAR" if is_forehand else "DORSAL", "matches": dot_value < - 0.001 if is_forehand else dot_value > 0.001, 
		"dorsal_world": dorsal, "surface_faces": surface.faces}




static func dorsal_surface(model) -> Dictionary:
	var arrays: Array = model.hand_mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var total: = Vector3.ZERO
	var area_total: = 0.0
	var faces: = 0
	for offset in range(0, indices.size(), 3):
		var ids: Array[int] = [indices[offset], indices[offset + 1], indices[offset + 2]]
		var rigid: = true
		for vertex in ids:
			for slot in range(4):
				if weights[vertex * 4 + slot] > 1e-06 and bones[vertex * 4 + slot] != 0: rigid = false
		if not rigid: continue
		var a: Vector3 = vertices[ids[0]]; var b: Vector3 = vertices[ids[1]]; var c: Vector3 = vertices[ids[2]]
		var center: Vector3 = (a + b + c) / 3.0
		var radial: = Vector3(center.x, 0, center.z)
		var normal: Vector3 = (normals[ids[0]] + normals[ids[1]] + normals[ids[2]]).normalized()


		if radial.length() < 0.046 or center.z < 0.024 or normal.dot(radial.normalized()) < 0.7: continue
		var area: float = (b - a).cross(c - a).length() * 0.5
		total += normal * area;area_total += area;faces += 1
	return {"normal": total.normalized(), "area": area_total, "faces": faces}

func run() -> void :
	var hard_gate: bool = "--audit-production-frame" in OS.get_cmdline_user_args()
	var models: Array = []
	var arms: Array = []
	for left in [false, true]:
		var arm: = MockArm.new();root.add_child(arm)
		var model: = Hand.new();model.initialize(arm, left);model.set_pose("GRIP")
		models.append(model);arms.append(arm)
		var surface: Dictionary = dorsal_surface(model)
		check(surface.faces >= 6 and surface.area > 0.0001, "independent real dorsal shell has measurable area")
		check(surface.normal.dot(model.anatomical_basis.z) > 0.8, "actual dorsal skin agrees with landmark axis on both hands")
		var arrays: Array = arm.hand_mesh.mesh.surface_get_arrays(0)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var nail_count: = 0
		for vertex in range(vertices.size()):
			if colors[vertex].is_equal_approx(Hand.NAIL_COLOR) and bones[vertex * 4] >= 1 and bones[vertex * 4] <= 12:
				nail_count += 1
				var outward: = Vector3(vertices[vertex].x, 0, vertices[vertex].z).normalized()
				check(normals[vertex].dot(outward) > 0.25, "real curled-finger nail faces away from shaft, unlike contact pad")
		check(nail_count >= 24, "four genuine nail patches participate")
		for court in [0, 1]:
			for turn in [Basis.IDENTITY, Basis.from_euler(Vector3(0.37, - 0.63, 0.24)), Basis.from_euler(Vector3( - 0.82, 0.19, - 0.47))]:
				var world: Basis = Basis(Vector3.UP, PI * court) * turn
				check(world.determinant() > 0.99999, "proper court rotation never mirrors mesh")
				var normal: Vector3 = world * surface.normal
				check(contact_side(model, world, - normal, true).matches, "true palmar-facing forehand stays palmar under proper rotation")
				check(contact_side(model, world, normal, false).matches, "true dorsal-facing backhand stays dorsal under proper rotation")
				check( not contact_side(model, world, normal, true).matches, "actual dorsal skin cannot be relabeled as forehand palm")
				if not left:


					var old: Basis = world * Basis(Vector3.UP, deg_to_rad(135.0))
					var rejected: Dictionary = contact_side(model, old, - world.z, true)
					check( not rejected.matches and rejected.dot > 0.5, "known old dorsal-leading forehand is explicitly rejected")
	if hard_gate: _audit_export(models)
	for arm in arms: arm.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("HAND STRIKING-SIDE ORACLE: ", checks, " checks, ", failures.size(), " failures; production_frame_gate=", hard_gate)
	print("Known old FH is rejected; mesh-only checks are NOT live-stroke or left-dominant-motion acceptance.")
	quit(0 if failures.is_empty() else 1)

func _vector(values: Array) -> Vector3: return Vector3(values[0], values[1], values[2])
func _basis(values: Array) -> Basis: return Basis(_vector(values[0]), _vector(values[1]), _vector(values[2]))

func _audit_export(models: Array) -> void :
	var path: = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--contact-export="): path = argument.trim_prefix("--contact-export=")
	check( not path.is_empty() and FileAccess.file_exists(path), "production audit requires an explicit actual-contact export")
	if path.is_empty() or not FileAccess.file_exists(path): return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(parsed is Dictionary, "actual-contact export is an object")
	if not parsed is Dictionary: return
	var data: Dictionary = parsed
	var hashes: Dictionary = data.get("source_hashes", {})
	check( not hashes.is_empty(), "actual-contact export records its source versions")
	var drift: Array[String] = []
	for source in hashes:
		var source_path: String = str(source) if str(source).begins_with("res://") else ("res://" + str(source) if str(source).begins_with("data/") else "res://scripts/" + str(source))
		if not FileAccess.file_exists(source_path) or FileAccess.get_sha256(source_path) != str(hashes[source]): drift.append(str(source))
	check(drift.is_empty(), "actual-contact export matches current recorded source versions: " + str(drift))
	if not drift.is_empty(): return
	var review_path: String = path.get_base_dir().path_join("review.json")
	if FileAccess.file_exists(review_path):
		var review = JSON.parse_string(FileAccess.get_file_as_string(review_path))
		if review is Dictionary: check(review.get("source_hashes_at_start", {}) == review.get("source_hashes_at_report", {}), "actual contact run has no source drift")
	var snapshots: Array = data.get("snapshots", [])
	check( not snapshots.is_empty(), "actual contact snapshots are present")
	var counted: = 0
	var skipped_overhead: = 0
	for value in snapshots:
		var row: Dictionary = value
		var fields: Dictionary = row.get("pose_fields", {})
		var pose_id: int = int(fields.get("posture_id", -1))
		var pose: PostureDefinition = PostureLibrary.instance().get_def(pose_id)
		if pose == null: check(false, "observed contact resolves an authored posture");continue
		if pose.family not in [0, 1]: skipped_overhead += 1;continue
		check(str(row.get("capture_phase", "")) == "presented_hit_frame", "contact uses a presented actual hit frame")
		var hit: Dictionary = {}
		for entry in row.get("hits_recorded", []):
			if int(entry.get("frame", -1)) == int(row.get("hit_frame", -2)): hit = entry;break
		check( not hit.is_empty(), "contact includes its actual physics-hit face position")
		if hit.is_empty(): continue
		var local_ball: Vector3 = _vector(hit.ball_local)
		check(absf(local_ball.z) > 0.015, "broad striking face is signed by actual hit point")
		var paddle: Basis = _basis(row.paddle_transform)
		var mesh: Basis = _basis(row.hand_transform)
		var left: bool = str(row.arm_side) == "left"
		var model = models[1 if left else 0]
		var surface_normal: Vector3 = paddle.z.normalized() * signf(local_ball.z)
		var result: Dictionary = contact_side(model, mesh, surface_normal, pose.family == 0)
		counted += 1
		print("ACTUAL STRIKING SIDE ", row.case, " hand=", row.arm_side, " family=", pose.family, " face_z=", local_ball.z, " surface_dot=", result.dot, " expected=", result.expected)
		check(result.matches, "actual " + str(row.case) + " requires " + str(result.expected) + "; observed " + str(result.hemisphere) + " dot=" + str(result.dot))
	check(counted > 0, "production audit evaluates observed FH/BH contacts")
	print("ACTUAL CONTACT AUDIT ", counted, " FH/BH; ", skipped_overhead, " overheads outside this signed-hemisphere contract. Left-mesh unit tests do not claim left-dominant live retuning.")
