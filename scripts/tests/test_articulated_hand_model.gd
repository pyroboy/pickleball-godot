extends SceneTree

const Hand = preload("res://scripts/articulated_hand.gd")
const PaddleDimensions = preload("res://scripts/paddle_dimensions.gd")
const Presentation = preload("res://scripts/player_hand_presentation.gd")
var checks: int = 0
var failures: Array[String] = []

class MockArm extends Node3D:
	var hand_mesh: MeshInstance3D
	func _init() -> void :
		hand_mesh = MeshInstance3D.new()
		hand_mesh.name = "HandMesh"
		hand_mesh.mesh = BoxMesh.new()
		add_child(hand_mesh)

class MockPlayer extends RefCounted:
	var forward: = Vector3.FORWARD
	var forehand: = Vector3.RIGHT
	func _get_forward_axis() -> Vector3:
		return forward
	func _get_forehand_axis() -> Vector3:
		return forehand

func _initialize() -> void :
	call_deferred("run")

func check(condition: bool, label: String) -> void :
	checks += 1
	if not condition:
		failures.append(label)

func run() -> void :
	var hands: Array = []
	var arms: Array = []
	for left in [false, true, false, true]:
		var arm: = MockArm.new()
		root.add_child(arm)
		var model: = Hand.new()
		model.initialize(arm, left)
		hands.append(model)
		arms.append(arm)
		var stats: Dictionary = model.debug_metadata()
		check(stats.surface_count == 1, "one surface")
		check(stats.triangles <= 900, "rounded-wrist hand triangle budget")
		check(stats.triangles == 702, "narrower handle retains existing hand topology")
		check(is_equal_approx(stats.handle_radius, PaddleDimensions.HANDLE_RADIUS), "hand skin uses shared paddle handle radius")
		check(absf(stats.handle_radius * TAU - PaddleDimensions.GRIP_CIRCUMFERENCE) < 1e-07, "circular grip circumference matches shared vendor specification")
		check(Hand.WRIST_SOCKET.is_equal_approx(Vector3( - 0.035, - 0.055, 0.034)), "narrower handle does not scale the adult wrist landmark")
		check(Hand.CUP_BALL_CENTER.is_equal_approx(Vector3( - 0.017, - 0.006, - 0.0155)), "narrower handle preserves the exact cup seat")
		check(stats.bones == 17, "one palm, fifteen digit joints and one cuff bridge")
		check(arm.hand_mesh.get_child_count() == 1 and arm.hand_mesh.get_child(0) is Skeleton3D, "only one skeleton node")
		check(arm.hand_mesh.mesh is ArrayMesh, "original box fully replaced")
		check(model.anatomical_basis.determinant() > 0.999, "proper anatomical basis")
		check(model.skeleton.transform.is_equal_approx(Transform3D.IDENTITY), "skeleton uses mesh frame")
		for bone in range(Hand.BONE_COUNT):
			check(model.skeleton.get_bone_global_pose(bone).basis.determinant() > 0.999, "proper bone basis")
		var before: int = model.bone_pose_write_count
		for repeat in range(120):
			model.set_pose("GRIP")
		check(model.bone_pose_write_count == before, "idle does zero bone writes")
		var minimum: = INF
		var triangles: PackedVector3Array = model.sampled_triangles()



		for face in range(0, triangles.size(), 3):
			minimum = minf(minimum, _triangle_axis_distance(triangles[face], triangles[face + 1], triangles[face + 2]) - Hand.HANDLE_RADIUS)
		check(minimum >= - 5e-05, "grip skin clears entire handle surface: %.6f" % minimum)
		check(minimum <= 0.00085, "finger pads visibly contact cylinder: %.6f" % minimum)
		_assert_each_finger_pad_contact(model)
		var grip: Dictionary = model.joint_positions()
		_assert_semantic_chirality(model, grip, left)
		_assert_landmark_frames(model, grip, left)
		_assert_cup_mount_invariance(model, grip)
		if not left: _assert_right_continental_bevel(grip)
		check(grip.index_mcp.y > grip.thumb_mcp.y + 0.006, "index above opposing thumb")
		check(grip.wrist.y < grip.little_mcp.y - 0.015, "actual wrist heel is buttward of pinky knuckle")
		var knuckle_axis: Vector3 = (grip.index_mcp - grip.little_mcp).normalized()
		var knuckle_obliquity: = rad_to_deg(acos(clampf(knuckle_axis.dot(Vector3.UP), -1, 1)))
		check(knuckle_obliquity > 25 and knuckle_obliquity < 60, "bounded oblique coaching-style knuckle row")
		check(model.palm_length > 0.075 and model.palm_length < 0.095, "oblique grip retains palm scale")
		_assert_anatomical_digit_lengths(stats)
		_assert_relaxed_pose_and_transition(model)
		var sign_x: = -1.0 if left else 1.0
		check(grip.index_pip.x * sign_x > 0 and grip.thumb_mcp.x * sign_x < 0, "thumb opposes fingers")
		model.set_pose("OPEN")
		var opened: Dictionary = model.joint_positions()
		_assert_open_nail_side(model, opened)
		check(opened.middle_tip.distance_to(grip.middle_tip) > 0.065, "three-joint articulation visibly opens")
		for mode in ["RELAXED", "CUP", "OPEN", "GRIP"]:
			model.set_pose(mode)
			for bone in range(Hand.BONE_COUNT):
				check(model.skeleton.get_bone_global_pose(bone).basis.determinant() > 0.999, mode + " proper bone basis")
		model.set_pose("CUP")
		check(absf(model.palm_surface_gap(model.cup_ball_center)) < 1e-06, "cheap palm query matches exact cup seat")
		check(model.palm_surface_gap(model.cup_ball_center + Vector3(0.2, 0, 0)) > 0.1, "finite palm rejects laterally distant ball")
		check(model.palm_surface_gap(model.cup_ball_center + Vector3(0, 0.2, 0)) > 0.1, "finite palm rejects longitudinally distant ball")
		var gap: float = model.ball_surface_gap(model.cup_ball_center)
		check(absf(gap) <= 0.0001, "actual skinned palm tangent to held ball: %.6f" % gap)
		var cup_vertices: PackedVector3Array = model.sampled_vertices()
		for point in cup_vertices:
			check(point.distance_to(model.cup_ball_center) >= Hand.BALL_RADIUS - 0.0001, "cup vertex stays outside ball")

		for amount in [1.0, 0.75, 0.5, 0.25, 0.0]:
			model.set_pose("CUP", amount)
			check(model.ball_surface_gap(model.cup_ball_center) >= - 0.00015, "cup release avoids ball at %.2f" % amount)
		var mount: = Transform3D(Basis(Vector3.UP, 0.73), Vector3(0.3, 0.8, - 0.4))
		model.set_mesh_world_transform(mount)
		check(model.skeleton.global_transform.is_equal_approx(mount), "GPU skeleton frame follows calibrated mesh mount")
		_assert_wrist_bridge(model)
		print("HAND MODEL left=%s tris=%s grip_gap=%.6f cup_gap=%.6f" % [left, stats.triangles, minimum, gap])
	check(hands[0].hand_mesh.mesh == hands[2].hand_mesh.mesh, "right geometry cache shared")
	check(hands[1].hand_mesh.mesh == hands[3].hand_mesh.mesh, "left geometry cache shared")
	check(hands[0].hand_mesh.skin == hands[2].hand_mesh.skin, "right bind skin shared")
	check(hands[1].hand_mesh.skin == hands[3].hand_mesh.skin, "left bind skin shared")
	check(Hand.mesh_build_count == 2, "only two hand meshes generated")
	for arm in arms:
		arm.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("ARTICULATED HAND MODEL: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _triangle_axis_distance(a: Vector3, b: Vector3, c: Vector3) -> float:
	var x: = Vector2(a.x, a.z)
	var y: = Vector2(b.x, b.z)
	var z: = Vector2(c.x, c.z)
	var c1: = x.cross(y)
	var c2: = y.cross(z)
	var c3: = z.cross(x)
	var area: = absf((y - x).cross(z - x))
	if area > 1e-12 and ((c1 >= 0 and c2 >= 0 and c3 >= 0) or (c1 <= 0 and c2 <= 0 and c3 <= 0)):
		return 0.0
	return minf(_segment_axis_distance(x, y), minf(_segment_axis_distance(y, z), _segment_axis_distance(z, x)))

func _assert_each_finger_pad_contact(model) -> void :
	var arrays: Array = model.hand_mesh.mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var vertices: PackedVector3Array = model.sampled_vertices()
	for digit in range(4):
		var minimum: = INF
		for vertex in range(vertices.size()):
			var bone: int = bones[vertex * 4]
			if bone < 1 + digit * 3 or bone > 3 + digit * 3: continue
			minimum = minf(minimum, Vector2(vertices[vertex].x, vertices[vertex].z).length() - PaddleDimensions.HANDLE_RADIUS)
		check(absf(minimum - Hand.PAD_CONTACT_GAP) < 1e-05, "each adult finger has a calibrated pad on the narrower grip")

func _segment_axis_distance(a: Vector2, b: Vector2) -> float:
	var edge: = b - a
	if edge.length_squared() < 1e-12:
		return a.length()
	var t: = clampf( - a.dot(edge) / edge.length_squared(), 0, 1)
	return (a + edge * t).length()




func _assert_semantic_chirality(model, joints: Dictionary, left: bool) -> void :
	var expected: = -1.0 if left else 1.0
	check(is_equal_approx(model.radial_sign, expected), "semantic radial sign agrees with handedness")
	check(joints.index_mcp.y > joints.middle_mcp.y and joints.middle_mcp.y > joints.ring_mcp.y and joints.ring_mcp.y > joints.little_mcp.y, "index-to-pinky order runs throat to butt")
	check(joints.thumb_cmc.distance_to(joints.index_mcp) < joints.thumb_cmc.distance_to(joints.little_mcp), "thenar thumb is on index radial side")
	check(model.palm_normal.dot(model.anatomical_basis.z) < - 0.85, "cup contact normal is in anatomical palmar hemisphere")
	for court_side in [0, 1]:
		for rotation in [Basis.IDENTITY, Basis.from_euler(Vector3(0.47, - 0.81, 0.22)), Basis.from_euler(Vector3(-1.12, 0.39, - 0.63))]:
			var world: Basis = Basis(Vector3.UP, PI * court_side) * rotation
			check(world.determinant() > 0.999, "semantic test mount and court turn are proper")
			var distal: Vector3 = (world * (joints.middle_mcp - joints.wrist)).normalized()
			var radial: Vector3 = (world * (joints.index_mcp - joints.little_mcp)).normalized()
			var thenar: Vector3 = (world * (joints.thumb_cmc - joints.wrist)).normalized()
			var dorsal: Vector3 = world * Vector3.BACK
			check(distal.cross(radial).dot(dorsal) * expected > 0.8, "actual world digit landmarks establish anatomical chirality")
			check(distal.cross(thenar).dot(dorsal) * expected > 0.3, "independent actual thumb landmark establishes chirality")

func _assert_landmark_frames(model, joints: Dictionary, left: bool) -> void :
	var expected_sign: float = -1.0 if left else 1.0
	check(model.palm_contact_basis.determinant() > 0.999999, "contact frame has proper determinant")
	check(model.palm_contact_basis.z.is_equal_approx( - model.palm_normal), "contact dorsal exactly opposes calibrated support direction")
	check((model.palm_contact_point + model.palm_normal * Hand.BALL_RADIUS).is_equal_approx(model.cup_ball_center), "contact direction follows actual seat-to-ball geometry")
	for court_side in [0, 1]:
		for rotation in [Basis.IDENTITY, Basis.from_euler(Vector3(0.47, - 0.81, 0.22)), Basis.from_euler(Vector3(-1.12, 0.39, - 0.63))]:
			var world: Basis = Basis(Vector3.UP, PI * court_side) * rotation
			var expected_x: Vector3 = (world * (joints.middle_mcp - joints.wrist)).normalized()
			var radial: Vector3 = world * (joints.index_mcp - joints.little_mcp) * expected_sign
			var expected_y: Vector3 = (radial - expected_x * radial.dot(expected_x)).normalized()
			var expected_z: Vector3 = expected_x.cross(expected_y).normalized()
			var actual: Basis = world * model.anatomical_basis
			check(actual.determinant() > 0.999999, "landmark anatomical frame is proper after world and court rotations")
			check(actual.x.is_equal_approx(expected_x), "anatomical distal is exact 3D wrist-to-middle landmark axis")
			check(actual.y.is_equal_approx(expected_y), "anatomical transverse follows projected actual knuckle row and chirality")
			check(actual.z.is_equal_approx(expected_z), "anatomical dorsum is the proper landmark cross product")

func _assert_cup_mount_invariance(model, joints: Dictionary) -> void :


	var legacy_x: Vector3 = joints.middle_mcp - joints.wrist
	legacy_x.z = 0.0
	legacy_x = legacy_x.normalized()
	var legacy_frame: = Basis(legacy_x, Vector3.BACK.cross(legacy_x), Vector3.BACK)
	check(model.palm_contact_basis.is_equal_approx(legacy_frame), "contact frame preserves the original cup/cuff frame")
	var player: = MockPlayer.new()
	var presentation: = Presentation.new()
	presentation._player = player
	var center: = Vector3(0.37, 1.14, - 0.82)
	for rotation in [Basis.IDENTITY, Basis.from_euler(Vector3(0.47, - 0.81, 0.22)), Basis(Vector3.UP, PI)]:
		player.forward = rotation * Vector3.FORWARD
		player.forehand = rotation * Vector3.RIGHT
		for normal in [Vector3.UP, Vector3(0.31, 0.89, - 0.34).normalized(), Vector3.FORWARD]:
			var dorsal: Vector3 = - normal.normalized()
			var distal: Vector3 = player.forward
			distal = (distal - dorsal * distal.dot(dorsal)).normalized()
			if distal.length_squared() < 0.01: distal = player.forehand
			var transverse: Vector3 = dorsal.cross(distal).normalized()
			var basis: Basis = Basis(distal, transverse, dorsal) * legacy_frame.inverse()
			var expected: = Transform3D(basis, center - basis * model.cup_ball_center)
			var actual: Transform3D = presentation._cup_mount(model, center, normal)
			check(actual.is_equal_approx(expected), "actual cup world transform is invariant to anatomical recalibration")
			check((actual * model.cup_ball_center).is_equal_approx(center), "cup ball centre remains at requested world centre")
			check((actual.basis * model.palm_normal).is_equal_approx(normal), "actual support direction follows requested world normal")

func _assert_right_continental_bevel(joints: Dictionary) -> void :





	for court_side in [0, 1]:
		for rotation in [Basis.IDENTITY, Basis.from_euler(Vector3(0.47, - 0.81, 0.22)), Basis.from_euler(Vector3(-1.12, 0.39, - 0.63))]:
			var paddle: Basis = Basis(Vector3.UP, PI * court_side) * rotation
			var view_forward: Vector3 = paddle.y
			var screen_up: Vector3 = paddle.x
			var screen_right: Vector3 = view_forward.cross(screen_up).normalized()
			check(screen_right.is_equal_approx( - paddle.z), "proper butt-view screen-right is paddle minus-Z")
			var bevel2: Vector3 = (screen_up + screen_right).normalized()
			check(bevel2.dot(screen_up) > 0.7 and bevel2.dot(screen_right) > 0.7, "right continental bevel2 is clockwise upper-right from bevel1")
			var mount: Basis = paddle * Basis(Vector3.UP, deg_to_rad(Presentation.GRIP_BEVEL_DEG))
			var index_radial: Vector3 = mount * joints.index_mcp
			index_radial = (index_radial - view_forward * index_radial.dot(view_forward)).normalized()
			check(index_radial.is_equal_approx(bevel2), "actual right index MCP is seated over semantic continental bevel2")

func _assert_open_nail_side(model, joints: Dictionary) -> void :
	var buffers: Array = model.hand_mesh.mesh.surface_get_arrays(0)
	var colors: PackedColorArray = buffers[Mesh.ARRAY_COLOR]
	var bones: PackedInt32Array = buffers[Mesh.ARRAY_BONES]
	var vertices: PackedVector3Array = model.sampled_vertices()
	for digit in range(5):
		var last_bone: = 3 + digit * 3
		var centre: = Vector3.ZERO
		var count: = 0
		for vertex in range(vertices.size()):
			if bones[vertex * 4] == last_bone and colors[vertex].is_equal_approx(Hand.NAIL_COLOR):
				centre += vertices[vertex]
				count += 1
		check(count >= 6, "actual nail-color vertices exist on each distal phalanx")
		if count == 0: continue
		centre /= count
		var joint_name: String = Hand.FINGER_NAMES[digit] + ("_dip" if digit < 4 else "_ip")
		var origin: Vector3 = joints[joint_name]
		var tip: Vector3 = joints[Hand.FINGER_NAMES[digit] + "_tip"]
		var axis: = (tip - origin).normalized()
		var shaft_point: = origin + axis * (centre - origin).dot(axis)
		check((centre - shaft_point).dot(Vector3.BACK) > 0.001, "actual OPEN nail lies on dorsal rather than palmar side")

func _assert_anatomical_digit_lengths(stats: Dictionary) -> void :
	var totals: Array[float] = []
	for digit in range(4):
		var segments: Array = stats.finger_lengths[digit]
		var total: float = segments[0] + segments[1] + segments[2]
		totals.append(total)
		check(total >= 0.06 and total <= 0.095, "bounded adult-scale exposed finger length")
		check(segments[0] > segments[1] * 1.5, "proximal phalanx is distinctly longest")
		check(segments[1] >= segments[2] and segments[1] <= segments[2] * 1.6, "middle/distal proportion avoids equal long rods")
		check(absf(segments[0] - (segments[1] + segments[2])) < 0.006, "proximal is approximately middle plus distal")
	check(totals[1] > totals[0] and totals[1] > totals[2] and totals[3] < totals[0], "middle longest and little distinctly shorter")
	check(stats.finger_lengths[4][2] < 0.025, "thumb distal phalanx is short")

func _assert_relaxed_pose_and_transition(model) -> void :
	var open_rotations: Array[Quaternion] = []
	var grip_rotations: Array[Quaternion] = []
	model.set_pose("OPEN")
	for bone in range(1, 1 + 5 * 3): open_rotations.append(model.skeleton.get_bone_pose_rotation(bone))
	model.set_pose("GRIP")
	for bone in range(1, 1 + 5 * 3): grip_rotations.append(model.skeleton.get_bone_pose_rotation(bone))
	model.set_pose("RELAXED")
	for bone in range(1, 1 + 5 * 3):
		var expected: Quaternion = open_rotations[bone - 1].slerp(grip_rotations[bone - 1], Hand.RELAXED_CLOSURE)
		var actual: Quaternion = model.skeleton.get_bone_pose_rotation(bone)
		check(absf(expected.dot(actual)) > 0.999998, "relaxed digit follows the shared closure constant")
	var before: int = model.bone_pose_write_count
	for repeat in range(120): model.set_pose("RELAXED")
	check(model.bone_pose_write_count == before, "idle relaxed hand performs no bone writes")
	model.set_pose("RELAXED", 0.0)
	var previous: Dictionary = model.joint_positions()
	for step in range(1, 17):
		model.set_pose("RELAXED", float(step) / 16.0)
		var current: Dictionary = model.joint_positions()
		for digit in Hand.FINGER_NAMES:
			check(current[digit + "_tip"].distance_to(previous[digit + "_tip"]) < 0.015, "relaxed transition has bounded continuous fingertip displacement")
		previous = current

func _assert_wrist_bridge(model) -> void :
	model.set_pose("GRIP")
	var mount: = Transform3D(Basis.from_euler(Vector3(0.31, - 0.46, 0.27)), Vector3(0.2, 0.9, - 0.3))
	model.set_mesh_world_transform(mount)
	var bind_forearm: Basis = Hand._direction_basis(model.palm_contact_basis.x, model.palm_contact_basis.z)
	check(model.update_wrist_bridge(mount.basis * bind_forearm), "first cuff alignment writes its one skin bone")
	var rest_vertices: PackedVector3Array = model.sampled_vertices()
	var before: int = model.bone_pose_write_count
	for repeat in range(120): model.update_wrist_bridge(mount.basis * bind_forearm)
	check(model.bone_pose_write_count == before, "idle wrist bridge performs no bone writes")
	var scaled_forearm: = Basis(bind_forearm.x, bind_forearm.y * 1.7, bind_forearm.z)
	check( not model.update_wrist_bridge(mount.basis * scaled_forearm), "cuff alignment ignores forearm mesh stretch scale")
	var arrays: Array = model.hand_mesh.mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	for bend in [-35.0, 35.0]:
		var forearm: Basis = Basis(model.palm_contact_basis.y, deg_to_rad(bend)) * bind_forearm
		check(model.update_wrist_bridge(mount.basis * forearm), "changed forearm bend updates cuff")
		var cuff: Transform3D = model.skeleton.get_bone_global_pose(Hand.WRIST_BRIDGE_BONE)
		check(cuff.basis.determinant() > 0.99999, "cuff bone rotation is proper on either hand")
		check(cuff.origin.is_equal_approx(model.wrist_socket), "cuff rotates about unchanged anatomical socket")
		check((cuff.basis * model.palm_contact_basis.x).is_equal_approx(forearm.y), "proximal cuff follows actual forearm distal direction")
		var moved: PackedVector3Array = model.sampled_vertices()
		var cuff_moved: = false
		for vertex in range(moved.size()):
			var influenced: = false
			for slot in range(4):
				if bones[vertex * 4 + slot] == Hand.WRIST_BRIDGE_BONE and weights[vertex * 4 + slot] > 0.0: influenced = true
			if influenced: cuff_moved = cuff_moved or moved[vertex].distance_to(rest_vertices[vertex]) > 0.001
			else: check(moved[vertex].distance_to(rest_vertices[vertex]) < 1e-06, "bridge leaves every palm/finger/contact vertex unchanged")
		check(cuff_moved, "bridge visibly changes existing cuff vertices")
		var rotation: Quaternion = model.skeleton.get_bone_pose_rotation(Hand.WRIST_BRIDGE_BONE)
		for mode in ["OPEN", "RELAXED", "CUP", "GRIP"]:
			model.set_pose(mode)
			check(model.skeleton.get_bone_pose_rotation(Hand.WRIST_BRIDGE_BONE).is_equal_approx(rotation), "finger pose never resets independent cuff")
			if mode == "CUP": check(absf(model.ball_surface_gap(model.cup_ball_center)) < 0.0001, "bent cuff preserves exact full-surface cup contact")
		var points: PackedVector3Array = model.sampled_triangles()
		var gap: = INF
		for face in range(0, points.size(), 3): gap = minf(gap, _triangle_axis_distance(points[face], points[face + 1], points[face + 2]) - Hand.HANDLE_RADIUS)
		check(gap >= - 5e-05, "bent cuff preserves exact cylinder clearance")
		var writes: int = model.bone_pose_write_count
		var turned: = Transform3D(Basis.from_euler(Vector3( - 0.22, 0.83, - 0.39)), Vector3( - 0.8, 0.6, 0.1))
		model.set_mesh_world_transform(turned)
		check( not model.update_wrist_bridge(turned.basis * forearm), "rigid world turn leaves relative cuff alignment cached")
		check(model.bone_pose_write_count == writes, "rigid world turn does no cuff bone write")
		model.set_mesh_world_transform(mount)
