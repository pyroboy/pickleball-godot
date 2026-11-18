extends RefCounted







const PaddleDimensions = preload("res://scripts/paddle_dimensions.gd")
const HANDLE_RADIUS: = PaddleDimensions.HANDLE_RADIUS
const PAD_CONTACT_GAP: = 0.00055
const BALL_RADIUS: = 0.0375
const RELAXED_CLOSURE: = 0.45
const WRIST_SOCKET: = Vector3(-0.035, -0.055, 0.034)


const MCP_ANGLES: = [0.0, 23.0, 46.0, 69.0]
const MCP_HEIGHTS: = [0.03, 0.017, 0.004, - 0.01]
const ORBIT_RADII: = [0.0368, 0.0368, 0.0368, 0.0347]



const FINGER_LENGTHS: = [[0.039, 0.023, 0.017], [0.042, 0.025, 0.019], [0.04, 0.024, 0.018], [0.031, 0.017, 0.016]]
const PALM_CONTACT_POINT: = Vector3(-0.017, -0.006, 0.022)
const CUP_BALL_CENTER: = PALM_CONTACT_POINT + Vector3(0, 0, - BALL_RADIUS)
const SKIN_COLOR: = Color("dbb18b")
const NAIL_COLOR: = Color("dfbb9c")
const FINGER_NAMES: = ["index", "middle", "ring", "little", "thumb"]
const SIDES: = 8
const WRIST_BRIDGE_BONE: = 16
const BONE_COUNT: = 17
static var _cache: Dictionary = {}
static var mesh_build_count: int = 0

var hand_mesh: MeshInstance3D
var skeleton: Skeleton3D
var is_left: bool = false
var wrist_socket: = WRIST_SOCKET
var cup_ball_center: = CUP_BALL_CENTER
var palm_contact_point: = PALM_CONTACT_POINT

var palm_normal: = Vector3.FORWARD
var radial_sign: float = 1.0




var anatomical_basis: = Basis.IDENTITY


var palm_contact_basis: = Basis.IDENTITY
var middle_mcp_rest: = Vector3.ZERO
var palm_length: float = 0.0
var pose_update_count: int = 0
var bone_pose_write_count: int = 0
var wrist_bridge_update_count: int = 0
var _last_wrist_axis: = Vector3.INF
var _data: Dictionary
var _mode: String = ""
var _closure: float = -1.0

func initialize(arm, left: bool) -> void :
	assert (hand_mesh == null, "An articulated hand is initialized only once")
	is_left = left
	hand_mesh = arm.hand_mesh
	assert (hand_mesh != null)
	if not _cache.has(left):
		_cache[left] = _build(left)
		mesh_build_count += 1
	_data = _cache[left]
	wrist_socket = _mirror(WRIST_SOCKET, left)
	cup_ball_center = _mirror(CUP_BALL_CENTER, left)
	palm_contact_point = _mirror(PALM_CONTACT_POINT, left)
	radial_sign = -1.0 if left else 1.0
	middle_mcp_rest = _data.rest_local[4].origin
	palm_length = wrist_socket.distance_to(middle_mcp_rest)
	var length_axis: Vector3 = (middle_mcp_rest - wrist_socket).normalized()
	var index_mcp: Vector3 = _data.rest_local[1].origin
	var little_mcp: Vector3 = _data.rest_local[10].origin
	var transverse: Vector3 = (index_mcp - little_mcp) * radial_sign
	transverse = (transverse - length_axis * transverse.dot(length_axis)).normalized()
	anatomical_basis = Basis(length_axis, transverse, length_axis.cross(transverse).normalized())
	var contact_dorsal: Vector3 = - palm_normal
	var contact_distal: Vector3 = middle_mcp_rest - wrist_socket
	contact_distal = (contact_distal - contact_dorsal * contact_distal.dot(contact_dorsal)).normalized()
	palm_contact_basis = Basis(contact_distal, contact_dorsal.cross(contact_distal), contact_dorsal)
	skeleton = Skeleton3D.new()
	skeleton.name = "HandSkeleton"

	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	hand_mesh.add_child(skeleton)
	for bone in range(BONE_COUNT):
		skeleton.add_bone(_data.names[bone])
		skeleton.set_bone_parent(bone, _data.parents[bone])
		skeleton.set_bone_rest(bone, _data.rest_local[bone])
		skeleton.set_bone_pose(bone, _data.rest_local[bone])
	hand_mesh.mesh = _data.mesh
	hand_mesh.skin = _data.skin
	hand_mesh.skeleton = NodePath("HandSkeleton")
	hand_mesh.material_override = preload("res://scripts/player_athlete_visual.gd").material()

	hand_mesh.custom_aabb = AABB(Vector3( - 0.21, - 0.17, - 0.16), Vector3(0.42, 0.34, 0.32))
	hand_mesh.set_meta("articulated_hand", self)
	set_pose("GRIP")

func set_mesh_world_transform(world_transform: Transform3D) -> void :
	assert (world_transform.basis.determinant() > 0.0, "Never mirror a runtime hand transform")
	hand_mesh.global_transform = world_transform






func update_wrist_bridge(forearm_mesh_world_basis: Basis) -> bool:
	assert (forearm_mesh_world_basis.determinant() > 0.0, "Forearm bridge requires a proper frame")
	var relative: Basis = hand_mesh.global_basis.orthonormalized().inverse() * forearm_mesh_world_basis.orthonormalized()
	var target_axis: Vector3 = relative.y.normalized()
	if _last_wrist_axis.is_equal_approx(target_axis): return false
	var bind_axis: Vector3 = palm_contact_basis.x
	var cross_axis: Vector3 = bind_axis.cross(target_axis)
	var cosine: float = clampf(bind_axis.dot(target_axis), -1.0, 1.0)
	var swing: = Quaternion.IDENTITY
	if cross_axis.length_squared() > 1e-10:
		swing = Quaternion(cross_axis.normalized(), acos(cosine))
	elif cosine < 0.0:
		swing = Quaternion(palm_contact_basis.z, PI)
	skeleton.set_bone_pose_rotation(WRIST_BRIDGE_BONE, swing)
	_last_wrist_axis = target_axis
	wrist_bridge_update_count += 1
	bone_pose_write_count += 1
	return true



func set_pose(mode: String, closure: float = 1.0) -> bool:
	var requested: = mode.to_upper()
	assert (requested in ["GRIP", "OPEN", "RELAXED", "CUP"], "Unknown hand pose")
	var amount: = 0.0 if requested == "OPEN" else snappedf(clampf(closure, 0.0, 1.0), 1.0 / 256.0)
	if _mode == requested and is_equal_approx(_closure, amount):
		return false
	_mode = requested
	_closure = amount
	var rotations: Array = _data.poses[requested]

	for bone in range(1, WRIST_BRIDGE_BONE):
		var open_rotation: Quaternion = _data.poses.OPEN[bone]
		skeleton.set_bone_pose_rotation(bone, open_rotation.slerp(rotations[bone], amount))
		bone_pose_write_count += 1
	pose_update_count += 1
	return true


func sampled_vertices() -> PackedVector3Array:
	var result: = PackedVector3Array()
	var matrices: Array[Transform3D] = []
	for bone in range(BONE_COUNT):
		matrices.append(skeleton.get_bone_global_pose(bone) * _data.inverse_bind[bone])
	var vertices: PackedVector3Array = _data.vertices
	var bones: PackedInt32Array = _data.bones
	var weights: PackedFloat32Array = _data.weights
	result.resize(vertices.size())
	for vertex in range(vertices.size()):
		var point: = Vector3.ZERO
		for influence in range(4):
			var slot: = vertex * 4 + influence
			if weights[slot] > 0.0:
				point += (matrices[bones[slot]] * vertices[vertex]) * weights[slot]
		result[vertex] = point
	return result

func sampled_triangles() -> PackedVector3Array:
	var vertices: = sampled_vertices()
	var result: = PackedVector3Array()
	var indices: PackedInt32Array = _data.indices
	result.resize(indices.size())
	for index in range(indices.size()):
		result[index] = vertices[indices[index]]
	return result

func joint_positions() -> Dictionary:
	var result: Dictionary = {"wrist": wrist_socket}
	for bone in range(BONE_COUNT):
		result[_data.names[bone]] = skeleton.get_bone_global_pose(bone).origin
	for digit in range(5):
		var bone: = 3 + digit * 3
		result[FINGER_NAMES[digit] + "_tip"] = skeleton.get_bone_global_pose(bone) * _data.tip_local[digit]
	return result





func palm_surface_gap(local_center: Vector3, radius: float = BALL_RADIUS) -> float:
	var patch: PackedVector3Array = _data.palm_patch
	var distance_squared: = INF
	for index in range(0, patch.size(), 3):
		var nearest: = _closest_triangle_point(local_center, patch[index], patch[index + 1], patch[index + 2])
		distance_squared = minf(distance_squared, nearest.distance_squared_to(local_center))
	return sqrt(distance_squared) - radius

func ball_surface_gap(local_center: Vector3, radius: float = BALL_RADIUS) -> float:
	var points: = sampled_triangles()
	var distance_squared: = INF
	for index in range(0, points.size(), 3):
		var nearest: = _closest_triangle_point(local_center, points[index], points[index + 1], points[index + 2])
		distance_squared = minf(distance_squared, nearest.distance_squared_to(local_center))
	return sqrt(distance_squared) - radius

func debug_metadata() -> Dictionary:
	return {"surface_count": hand_mesh.mesh.get_surface_count(), 
		"triangles": _data.indices.size() / 3, "vertices": _data.vertices.size(), 
		"bones": skeleton.get_bone_count(), "mesh_build_count": mesh_build_count, 
		"pose_update_count": pose_update_count, "bone_pose_write_count": bone_pose_write_count, 
		"wrist_bridge_bone": WRIST_BRIDGE_BONE, "wrist_bridge_update_count": wrist_bridge_update_count, 
		"wrist_bridge_definition": "Shortest proper cuff-distal swing to actual forearm mesh +Y; no axial skin wringing", 
		"pose": _mode, "closure": _closure, "wrist_socket": wrist_socket, 
		"relaxed_closure": RELAXED_CLOSURE, 
		"cup_ball_center": cup_ball_center, "palm_contact_point": palm_contact_point, 
		"palm_normal": palm_normal, "radial_sign": radial_sign, 
		"anatomical_basis": anatomical_basis, "palm_contact_basis": palm_contact_basis, 
		"anatomical_basis_definition": "X wrist-to-middle MCP; Y projected index-minus-little times radial_sign; Z X cross Y", 
		"palm_contact_basis_definition": "Z opposite calibrated cup contact normal; X projected wrist-to-middle MCP", 
		"middle_mcp_rest": middle_mcp_rest, "palm_length": palm_length, 
		"bind_aabb": hand_mesh.mesh.get_aabb(), "mesh_id": hand_mesh.mesh.get_instance_id(), 
		"skin_id": hand_mesh.skin.get_instance_id(), "handle_radius": HANDLE_RADIUS, 
		"grip_fit_definition": "Pad-only fit to shared circular handle radius; adult landmarks, lengths and cup seat unchanged", 
		"pad_contact_gap_target": PAD_CONTACT_GAP, "palm_contact_triangles": _data.palm_patch.size() / 3, 
		"bone_names": _data.names.duplicate(), "finger_lengths": _data.lengths.duplicate(true)}

static func _build(left: bool) -> Dictionary:
	var names: Array[String] = ["palm"]
	var parents: = PackedInt32Array([-1])
	var global_rest: Array[Transform3D] = [Transform3D.IDENTITY]
	var open_global: Array[Basis] = [Basis.IDENTITY]
	var cup_global: Array[Basis] = [Basis.IDENTITY]
	var digit_points: Array = []
	var radii: Array = []
	var lengths: Array = []


	var distal_axis: = _mcp_point(1) - WRIST_SOCKET
	distal_axis.z = 0.0
	distal_axis = distal_axis.normalized()
	var radial_axis: = Vector3.BACK.cross(distal_axis)
	var thicknesses: = [0.0082, 0.0088, 0.0082, 0.007, 0.0102]
	for digit in range(5):
		var points: Array[Vector3] = []
		if digit < 4:
			var theta: = deg_to_rad(MCP_ANGLES[digit])
			points.append(_mcp_point(digit))
			for length in FINGER_LENGTHS[digit]:
				theta += 2.0 * asin(float(length) / (2.0 * ORBIT_RADII[digit]))
				points.append(Vector3(sin(theta) * ORBIT_RADII[digit], MCP_HEIGHTS[digit], cos(theta) * ORBIT_RADII[digit]))
		else:

			points = _thumb_rest_points()
		var digit_lengths: Array[float] = []
		for joint in range(3):
			digit_lengths.append(points[joint].distance_to(points[joint + 1]))
		lengths.append(digit_lengths)
		var cup_points: = _cup_points(points[0], digit_lengths, digit == 4)
		for joint in range(3):
			var bone: = names.size()
			var suffix: String = ["mcp", "pip", "dip"][joint] if digit < 4 else ["cmc", "mcp", "ip"][joint]
			names.append(FINGER_NAMES[digit] + "_" + suffix)
			parents.append(0 if joint == 0 else bone - 1)
			var direction: = _mirror(points[joint + 1] - points[joint], left)
			var dorsal: = _mirror(Vector3(points[joint].x, 0, points[joint].z).normalized(), left)
			global_rest.append(Transform3D(_direction_basis(direction, dorsal), _mirror(points[joint], left)))
			var open_direction: Vector3 = distal_axis + radial_axis * [0.18, 0.05, - 0.09, - 0.24][mini(digit, 3)] + Vector3.BACK * 0.02
			if digit == 4:
				open_direction = [Vector3( - 0.35, 0.92, - 0.05), Vector3(0.15, 0.55, - 0.82), Vector3(0.65, 0.02, - 0.76)][joint]
			open_global.append(_direction_basis(_mirror(open_direction, left), Vector3.BACK))
			var cup_direction: = _mirror(cup_points[joint + 1] - cup_points[joint], left)
			var cup_dorsal: = _mirror(cup_points[joint] - CUP_BALL_CENTER, left)
			cup_dorsal.y = 0.0
			cup_global.append(_direction_basis(cup_direction, cup_dorsal))
		digit_points.append(points)
		radii.append(thicknesses[digit])

	names.append("wrist_cuff")
	parents.append(0)
	global_rest.append(Transform3D(Basis.IDENTITY, _mirror(WRIST_SOCKET, left)))
	open_global.append(Basis.IDENTITY)
	cup_global.append(Basis.IDENTITY)
	var rest_local: Array[Transform3D] = []
	var inverse_bind: Array[Transform3D] = []
	var poses: = {"GRIP": [], "OPEN": [], "RELAXED": [], "CUP": []}
	var skin: = Skin.new()
	for bone in range(BONE_COUNT):
		var parent: int = parents[bone]
		var local: Transform3D = global_rest[bone] if parent < 0 else global_rest[parent].affine_inverse() * global_rest[bone]
		rest_local.append(local)
		inverse_bind.append(global_rest[bone].affine_inverse())
		skin.add_bind(bone, inverse_bind[bone])
		var open_basis: Basis = open_global[bone] if parent < 0 else open_global[parent].inverse() * open_global[bone]
		var cup_basis: Basis = cup_global[bone] if parent < 0 else cup_global[parent].inverse() * cup_global[bone]
		var grip_rotation: = local.basis.get_rotation_quaternion()
		var open_rotation: = open_basis.get_rotation_quaternion()
		poses.GRIP.append(grip_rotation)
		poses.OPEN.append(open_rotation)
		poses.CUP.append(cup_basis.get_rotation_quaternion())
		poses.RELAXED.append(open_rotation.slerp(grip_rotation, RELAXED_CLOSURE))
	var surface: = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var palm_patch: = _add_palm(surface, left)
	var tip_local: Array[Vector3] = []
	for digit in range(5):
		_add_digit(surface, digit_points[digit], radii[digit], 1 + digit * 3, left)
		tip_local.append(inverse_bind[3 + digit * 3] * _mirror(digit_points[digit][3], left))
	surface.generate_normals()
	surface.index()
	var mesh: = surface.commit()
	var arrays: Array = mesh.surface_get_arrays(0)
	return {"mesh": mesh, "skin": skin, "names": names, "parents": parents, 
		"rest_local": rest_local, "inverse_bind": inverse_bind, "poses": poses, 
		"vertices": arrays[Mesh.ARRAY_VERTEX], "bones": arrays[Mesh.ARRAY_BONES], 
		"weights": arrays[Mesh.ARRAY_WEIGHTS], "indices": arrays[Mesh.ARRAY_INDEX], 
		"tip_local": tip_local, "lengths": lengths, "palm_patch": palm_patch}

static func _cup_points(root: Vector3, lengths: Array[float], thumb: bool) -> Array[Vector3]:
	var points: Array[Vector3] = [root]
	if thumb:


		var directions: = [Vector3( - 0.5, 0.78, - 0.05), Vector3(0.3, 0.08, - 0.95), Vector3(0.8, - 0.15, - 0.58)]
		for joint in range(3):
			points.append(points[-1] + directions[joint].normalized() * lengths[joint])
		return points
	var delta: = root - CUP_BALL_CENTER
	var radius: = Vector2(delta.x, delta.z).length()
	var theta: = atan2(delta.x, delta.z)
	for length in lengths:
		theta += (-1.0 if thumb else 1.0) * 2.0 * asin(clampf(length / (2.0 * radius), 0, 1))
		points.append(CUP_BALL_CENTER + Vector3(sin(theta) * radius, root.y - CUP_BALL_CENTER.y, cos(theta) * radius))
	return points

static func _mcp_point(digit: int) -> Vector3:
	var theta: = deg_to_rad(MCP_ANGLES[digit])
	return Vector3(sin(theta) * ORBIT_RADII[digit], MCP_HEIGHTS[digit], cos(theta) * ORBIT_RADII[digit])

static func _thumb_rest_points() -> Array[Vector3]:



	return [Vector3( - 0.034, - 0.007, 0.034), Vector3( - 0.0315, 0.018, - 0.014), 
		Vector3( - 0.005, 0.025, - 0.037), Vector3(0.014, 0.024, - 0.046)]

static func _add_palm(surface: SurfaceTool, left: bool) -> PackedVector3Array:



	var distal: = _mcp_point(1) - WRIST_SOCKET
	distal.z = 0.0
	distal = distal.normalized()
	var radial_axis: = Vector3.BACK.cross(distal)
	var rings: Array = []


	for section in range(2):
		var centre: Vector3 = WRIST_SOCKET - distal * (0.023 if section == 0 else 0.008)


		var width: = 0.0245 if section == 0 else 0.027
		var depth: = 0.022 if section == 0 else 0.024
		var ring: Array = []
		for side in range(8):
			var angle: = deg_to_rad(157.5 - 45.0 * side)
			var point: = centre + radial_axis * cos(angle) * width + Vector3.BACK * sin(angle) * depth
			ring.append(_vertex(point, WRIST_BRIDGE_BONE, WRIST_BRIDGE_BONE if section == 0 else 0, 1.0 if section == 0 else 0.65, SKIN_COLOR, left))
		rings.append(ring)
	var ulnar_to_radial: = [3, 2, 1, 0]
	var spans: = [ - 0.023, - 0.008, 0.008, 0.023]
	for row in range(5):
		var t: = float(row) / 4.0
		var top: Array = []
		var bottom: Array = []
		for column in range(4):
			var digit: int = ulnar_to_radial[column]
			var start: Vector3 = WRIST_SOCKET + radial_axis * spans[column]
			var finish: = _mcp_point(digit)
			var theta: = lerpf(atan2(start.x, start.z), deg_to_rad(MCP_ANGLES[digit]), t)
			var radius: = lerpf(Vector2(start.x, start.z).length(), ORBIT_RADII[digit], t)
			var centre: = Vector3(sin(theta) * radius, lerpf(start.y, finish.y, t), cos(theta) * radius)
			var thenar: = sin(PI * t) if column == 3 else 0.0
			centre += radial_axis * 0.006 * thenar
			var dorsal: = Vector3.BACK.lerp(Vector3(sin(theta), 0, cos(theta)), t).normalized()
			var depth: = lerpf(0.016, 0.008, t) + 0.003 * thenar
			top.append(_vertex(centre + dorsal * depth, 0, 0, 1.0, SKIN_COLOR, left))
			var underside: = centre - dorsal * depth

			if row == 2 and column == 2: underside = PALM_CONTACT_POINT
			bottom.append(_vertex(underside, 0, 0, 1.0, SKIN_COLOR, left))
		var ring: Array = top.duplicate()
		bottom.reverse()
		ring.append_array(bottom)
		rings.append(ring)
	_join_rings(surface, rings, left)

	var patch: = PackedVector3Array()
	for row in range(3, 5):
		for side in [4, 5]:
			patch.append_array(PackedVector3Array([rings[row][side].point, rings[row + 1][side].point, rings[row + 1][side + 1].point, 
				rings[row][side].point, rings[row + 1][side + 1].point, rings[row][side + 1].point]))
	return patch

static func _add_digit(surface: SurfaceTool, points: Array, radius: float, first_bone: int, left: bool) -> void :
	var ring_points: Array = [points[0], points[0].lerp(points[1], 0.48), points[1], 
		points[1].lerp(points[2], 0.5), points[2], points[2].lerp(points[3], 0.6), points[3]]
	var scales: = [1.04, 1.0, 0.94, 0.89, 0.83, 0.74, 0.42]
	if first_bone == 13:
		scales = [1.32, 1.18, 0.98, 0.92, 0.82, 0.7, 0.36]
	var bones_a: = [first_bone, first_bone, first_bone, first_bone + 1, first_bone + 1, first_bone + 2, first_bone + 2]
	var bones_b: = [first_bone, first_bone, first_bone + 1, first_bone + 1, first_bone + 2, first_bone + 2, first_bone + 2]
	var blend: = [1.0, 1.0, 0.5, 1.0, 0.5, 1.0, 1.0]
	var rings: Array = []
	for row in range(ring_points.size()):
		var previous: Vector3 = ring_points[maxi(row - 1, 0)]
		var following: Vector3 = ring_points[mini(row + 1, ring_points.size() - 1)]
		var centre: Vector3 = ring_points[row]
		var frame: = _direction_basis(following - previous, Vector3(centre.x, 0, centre.z))
		var ring: Array = []
		for side in range(SIDES):
			var angle: = TAU * side / SIDES
			var point: Vector3 = centre + (frame.x * cos(angle) + frame.z * sin(angle) * 0.93) * radius * scales[row]



			if first_bone < 13 and row in [1, 3] and side in [5, 6, 7]:
				var target_radius: = HANDLE_RADIUS + PAD_CONTACT_GAP + (0.00025 if side != 6 else 0.0)
				var radial: = Vector2(point.x, point.z).normalized() * target_radius
				point.x = radial.x
				point.z = radial.y
			ring.append(_vertex(point, bones_a[row], bones_b[row], blend[row], SKIN_COLOR, left))
		rings.append(ring)
	_join_rings(surface, rings, left)

	var distal: Vector3 = points[3] - points[2]
	var centre: Vector3 = points[2].lerp(points[3], 0.6)
	var frame: = _direction_basis(distal, Vector3(centre.x, 0, centre.z))
	centre += frame.z * (radius * (0.7 if first_bone == 13 else 0.74) * 0.93 + 0.0001)
	var centre_vertex: = _vertex(centre, first_bone + 2, first_bone + 2, 1.0, NAIL_COLOR, left)
	for side in range(6):
		var a: = TAU * side / 6.0
		var b: = TAU * (side + 1) / 6.0
		var pa: = centre + frame.x * cos(a) * radius * 0.36 + frame.y * sin(a) * distal.length() * 0.18
		var pb: = centre + frame.x * cos(b) * radius * 0.36 + frame.y * sin(b) * distal.length() * 0.18
		_emit_triangle(surface, centre_vertex, _vertex(pa, first_bone + 2, first_bone + 2, 1.0, NAIL_COLOR, left), _vertex(pb, first_bone + 2, first_bone + 2, 1.0, NAIL_COLOR, left), left)

static func _join_rings(surface: SurfaceTool, rings: Array, left: bool) -> void :
	for row in range(rings.size() - 1):
		for side in range(SIDES):
			var next: = (side + 1) % SIDES
			_emit_triangle(surface, rings[row][side], rings[row + 1][side], rings[row + 1][next], left)
			_emit_triangle(surface, rings[row][side], rings[row + 1][next], rings[row][next], left)
	for end in [0, rings.size() - 1]:
		var ring: Array = rings[end]
		var cap: Dictionary = ring[0].duplicate()
		cap.point = Vector3.ZERO
		for vertex in ring:
			cap.point += vertex.point / SIDES
		for side in range(SIDES):
			var next: = (side + 1) % SIDES
			if end == 0:
				_emit_triangle(surface, cap, ring[side], ring[next], left)
			else:
				_emit_triangle(surface, cap, ring[next], ring[side], left)

static func _vertex(point: Vector3, a: int, b: int, weight: float, color: Color, left: bool) -> Dictionary:
	return {"point": _mirror(point, left), "a": a, "b": b, "weight": weight, "color": color}

static func _emit_triangle(surface: SurfaceTool, a: Dictionary, b: Dictionary, c: Dictionary, left: bool) -> void :

	var vertices: Array = [a, b, c] if left else [a, c, b]
	for vertex in vertices:
		surface.set_smooth_group(0)
		surface.set_color(vertex.color)
		surface.set_bones(PackedInt32Array([vertex.a, vertex.b, 0, 0]))
		surface.set_weights(PackedFloat32Array([vertex.weight, 1.0 - vertex.weight, 0, 0]))
		surface.add_vertex(vertex.point)

static func _direction_basis(direction: Vector3, dorsal: Vector3) -> Basis:
	var y: = direction.normalized()
	var x: = y.cross(dorsal).normalized()
	if x.length_squared() < 0.5:
		x = y.cross(Vector3.UP).normalized()
	return Basis(x, y, x.cross(y).normalized())

static func _mirror(point: Vector3, left: bool) -> Vector3:
	return Vector3( - point.x, point.y, point.z) if left else point

static func _closest_triangle_point(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab: = b - a
	var ac: = c - a
	var ap: = p - a
	var d1: = ab.dot(ap)
	var d2: = ac.dot(ap)
	if d1 <= 0 and d2 <= 0: return a
	var bp: = p - b
	var d3: = ab.dot(bp)
	var d4: = ac.dot(bp)
	if d3 >= 0 and d4 <= d3: return b
	var vc: = d1 * d4 - d3 * d2
	if vc <= 0 and d1 >= 0 and d3 <= 0: return a + ab * (d1 / (d1 - d3))
	var cp: = p - c
	var d5: = ab.dot(cp)
	var d6: = ac.dot(cp)
	if d6 >= 0 and d5 <= d6: return c
	var vb: = d5 * d2 - d1 * d6
	if vb <= 0 and d2 >= 0 and d6 <= 0: return a + ac * (d2 / (d2 - d6))
	var va: = d3 * d6 - d5 * d4
	if va <= 0 and d4 - d3 >= 0 and d5 - d6 >= 0: return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denominator: = 1.0 / (va + vb + vc)
	return a + ab * (vb * denominator) + ac * (vc * denominator)
