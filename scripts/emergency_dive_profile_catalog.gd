extends RefCounted
## Data-only finite-profile catalog. A certificate admits rigid world translation
## of an unchanged, versioned rig/entry; it never retargets or awards a ball hit.
const PATH := "res://data/emergency_dive_profiles.bin"
const SCHEMA := 3
const ENTRY_EPSILON := 0.0
const Surface = preload("res://scripts/player_surface_contacts.gd")
static var _loaded := false
static var _data: Dictionary = {}
static var _code := ""
static var _mesh_keys: Dictionary = {}

static func _files(directory: String, output: Array[String]) -> void:
	var dir := DirAccess.open(directory)
	if dir == null: return
	for file in dir.get_files():
		if file.ends_with(".gd") or file.ends_with(".tscn") or file.ends_with(".tres"): output.append(directory.path_join(file))
	for child in dir.get_directories(): _files(directory.path_join(child), output)

static func code_fingerprint() -> String:
	if not _code.is_empty(): return _code
	var files: Array[String] = []
	for folder in ["res://scripts", "res://scenes", "res://resources", "res://data/postures"]: _files(folder, files)
	files.sort()
	var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(Engine.get_version_info()))
	for file in files:
		digest.update(file.to_utf8_buffer()); digest.update(FileAccess.get_file_as_bytes(file))
	_code = digest.finish().hex_encode()
	return _code

static func _digest(bytes: PackedByteArray) -> String:
	var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256); digest.update(bytes)
	return digest.finish().hex_encode()

static func _mesh_key(mesh: Mesh) -> String:
	var identity := mesh.get_instance_id()
	if _mesh_keys.has(identity): return _mesh_keys[identity]
	var arrays: Array = []
	for index in mesh.get_surface_count(): arrays.append(mesh.surface_get_arrays(index))
	var key := _digest(var_to_bytes(arrays))
	_mesh_keys[identity] = key
	mesh.changed.connect(func(): _mesh_keys.erase(identity))
	return key

static func _inert_simulator(node: Node) -> bool:
	return node is PhysicalBoneSimulator3D and node.get_child_count(true) == 0 and not node.is_simulating_physics() and node.get_script() == null

static func simulation_signature(actor) -> Dictionary:
	var result := {}
	for node in actor.body_pivot.find_children("*", "PhysicalBoneSimulator3D", true, false):
		var parent := String(actor.body_pivot.get_path_to(node.get_parent()))
		if not result.has(parent): result[parent] = []
		result[parent].append({"simulating": node.is_simulating_physics(), "children": node.get_child_count(true), "script": str(node.get_script().resource_path) if node.get_script() != null else ""})
	return result

static func entry_state(actor) -> Dictionary:
	var nodes: Dictionary = {}; var bones: Dictionary = {}; var meshes: Dictionary = {}; var configuration: Dictionary = {}
	var body: Node3D = actor.body_pivot
	var all: Array = [body]; all.append_array(body.find_children("*", "Node3D", true, false))
	for node: Node3D in all:
		# Godot auto-creates an empty simulator under each skeleton with a
		# process-specific name. With no physical bones or descendants it
		# cannot alter any displayed surface; do not key inert node IDs.
		if _inert_simulator(node): continue
		var key := String(body.get_path_to(node))
		nodes[key] = node.transform
		if node is Skeleton3D:
			var poses: Array[Transform3D] = []
			for index in node.get_bone_count(): poses.append(node.get_bone_pose(index))
			bones[key] = poses
			var rests: Array = []
			for index in node.get_bone_count(): rests.append([node.get_bone_rest(index), node.get_bone_parent(index)])
			configuration[key] = {"rests": rests}
		if node is MeshInstance3D and node.mesh != null:
			meshes[key] = _mesh_key(node.mesh)
			var bind: Array = []; var blend: Array = []
			if node.skin != null:
				for index in node.skin.get_bind_count(): bind.append([node.skin.get_bind_bone(index), String(node.skin.get_bind_name(index)), node.skin.get_bind_pose(index)])
			for index in node.get_blend_shape_count(): blend.append(node.get_blend_shape_value(index))
			configuration[key] = {"skin": bind, "skeleton": String(node.skeleton), "blend": blend}
		# The certified visual rig has no such collision objects. Their addition
		# changes the key even when they use identity transforms or no mesh.
		if node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D:
			configuration[key] = {"physics_class": node.get_class()}
		if node is SkeletonModifier3D:
			configuration[key] = {"active": node.active, "influence": node.influence, "script": str(node.get_script().resource_path) if node.get_script() != null else ""}
	var lengths: Array = []; var hand_state: Array = []
	for arm in [actor.right_arm_node, actor.left_arm_node]: lengths.append([arm.upper_arm_length, arm.forearm_length, arm.articulated_hand.wrist_socket, arm.articulated_hand.anatomical_basis])
	for arm in [actor.right_arm_node, actor.left_arm_node]:
		var model = arm.articulated_hand
		hand_state.append([model._mode, model._closure, model._index_closure, model._support_style_weight, model.radial_sign])
	var skin = actor.body_pivot.get_meta("articulated_torso")
	var posture = actor.get_runtime_posture_def()
	for leg in [actor.right_leg_node, actor.left_leg_node]: lengths.append([leg.thigh_length, leg.shin_length])
	return {"player_num": actor.player_num, "nodes": nodes, "bones": bones, "meshes": meshes, "lengths": lengths,
		"ground_y": actor.ground_y, "root_basis": actor.global_basis, "physics_simulators": simulation_signature(actor),
		"configuration": configuration, "hand_state": hand_state, "body_frames": [skin._last_pelvis, skin._last_abdomen, skin._last_chest],
		"grip_rotation": float(posture.main_grip_rotation_deg - posture.paddle_in_hand_rotation_deg)}

static func _same(a: Variant, b: Variant, epsilon: float) -> bool:
	if typeof(a) != typeof(b): return false
	match typeof(a):
		TYPE_FLOAT: return absf(a - b) <= epsilon
		TYPE_VECTOR3: return a.distance_to(b) <= epsilon
		TYPE_BASIS: return (a.x - b.x).length() <= epsilon and (a.y - b.y).length() <= epsilon and (a.z - b.z).length() <= epsilon
		TYPE_TRANSFORM3D: return _same(a.origin, b.origin, epsilon) and _same(a.basis, b.basis, epsilon)
		TYPE_ARRAY:
			if a.size() != b.size(): return false
			for index in a.size():
				if not _same(a[index], b[index], epsilon): return false
			return true
		TYPE_DICTIONARY:
			if a.size() != b.size(): return false
			for key in a:
				if not b.has(key) or not _same(a[key], b[key], epsilon): return false
			return true
	return a == b

static func entry_match_report(actor, expected: Dictionary, actual: Dictionary = {}) -> Dictionary:
	if actual.is_empty(): actual = entry_state(actor)
	var failures: Array[String] = []
	var details: Array[Dictionary] = []
	for key in expected:
		var epsilon := 0.0 if key in ["lengths", "ground_y", "meshes", "player_num"] else ENTRY_EPSILON
		if not actual.has(key) or not _same(actual[key], expected[key], epsilon):
			failures.append(str(key))
			if key in ["nodes", "bones", "meshes"] and actual.get(key) is Dictionary:
				for path in expected[key]:
					if details.size() >= 12: break
					if actual[key].has(path) and _same(actual[key][path], expected[key][path], epsilon): continue
					var item := {"component": str(key), "path": str(path)}
					if key == "nodes" and actual[key].get(path) is Transform3D:
						item["position_error_m"] = actual[key][path].origin.distance_to(expected[key][path].origin)
						item["rotation_error_deg"] = rad_to_deg(actual[key][path].basis.orthonormalized().get_rotation_quaternion().angle_to(expected[key][path].basis.orthonormalized().get_rotation_quaternion()))
					details.append(item)
	return {"matches": failures.is_empty(), "different_components": failures, "entry_mismatches": details, "transform_epsilon_m": ENTRY_EPSILON,
		"entry_policy": "actual matching presentation required; no pose reset or automatic bridge"}

static func profile_payload_fingerprint(profile: Dictionary) -> String:
	# Bind the certificate to its complete entry, finite motion, and paddle
	# samples. A source-code key alone must not bless changed profile data.
	var evidence: Dictionary = profile.get("certificate", {}).duplicate(true)
	evidence.erase("payload_sha256")
	return _digest(var_to_bytes([profile.get("entry", {}), profile.get("plan", {}), profile.get("paddles", []), evidence]))

static func profile_integrity_valid(profile: Dictionary) -> bool:
	return str(profile.get("certificate", {}).get("payload_sha256", "")) == profile_payload_fingerprint(profile)

static func certificate_complete(profile: Dictionary) -> bool:
	# A dense sleeve/floor replay alone is useful module evidence, not a
	# releasable full-body profile. Missing tests must fail closed.
	var evidence: Dictionary = profile.get("certificate", {})
	return int(evidence.get("samples", 0)) >= 5377 \
		and int(evidence.get("full_surface_samples", 0)) >= 5377 \
		and bool(evidence.get("entry_handoff_surfaces_clear", false)) \
		and bool(evidence.get("all_nonjoint_surfaces_clear", false)) \
		and bool(evidence.get("real_support_path_clear", false)) \
		and str(evidence.get("head_rotation_policy", "")) == "exact_entry" \
		and float(evidence.get("sleeve_gap_m", 0.0)) >= 0.00025 \
		and float(evidence.get("hand_triangle_gap_m", 0.0)) >= 0.0001 \
		and float(evidence.get("maximum_joint_deg_s", INF)) <= 720.1 \
		and float(evidence.get("maximum_finger_step_deg_s", INF)) <= 720.1

static func load_profiles() -> Dictionary:
	if _loaded: return _data
	_loaded = true
	if not FileAccess.file_exists(PATH): return {}
	var file := FileAccess.open(PATH, FileAccess.READ)
	var data: Variant = file.get_var(false); file.close()
	if not data is Dictionary or int(data.get("schema", -1)) != SCHEMA or data.get("code", "") != code_fingerprint(): return {}
	if not data.get("profiles", []) is Array: return {}
	for profile: Variant in data.profiles:
		if not profile is Dictionary or not profile_integrity_valid(profile) or not certificate_complete(profile): return {}
	_data = data
	return _data

static func warm_cache() -> bool: return not load_profiles().is_empty()
