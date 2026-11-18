extends SceneTree
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Styles = preload("res://scripts/serve_style.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Geometry = preload("res://scripts/paddle_clearance.gd")
const Dimensions = preload("res://scripts/player_body_dimensions.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const GripFrame = preload("res://scripts/paddle_grip_frame.gd")
const HandModel = preload("res://scripts/articulated_hand.gd")
const Side = preload("res://scripts/tests/test_stroke_orientation.gd").CourtSide
var checks: = 0
var failures: Array[String] = []
var max_rotation: = 0.0
var minimum_clearance: = INF
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func inspect_pose(player, pose, tag: String) -> Transform3D:
	var tx: Transform3D = Path.world_transform(player, pose)
	var is_left: bool = pose.paddle_hand == 1
	var socket: Vector3 = HandModel.WRIST_SOCKET
	if is_left: socket.x = - socket.x
	var offset: Vector3 = pose.left_hand_offset if is_left else pose.right_hand_offset
	var wrist: Vector3 = tx * (PaddleSize.MAIN_GRIP_OFFSET + offset) + GripFrame.basis(tx.basis, is_left) * socket
	check(wrist.distance_to(Body.shoulder_world(player, pose)) <= 0.7001, tag + " anatomical wrist reach")
	check(Geometry.face_clearance(player, pose) >= 0.04, tag + " face clearance")
	var surface = Geometry.sample_head_surface()
	var chest_gap: = Geometry.sampled_chest_clearance(player, pose, surface)
	minimum_clearance = minf(minimum_clearance, chest_gap)
	check(chest_gap >= 0.025, tag + " chest clearance")
	return tx
func run() -> void :
	create_timer(90).timeout.connect( func(): quit(2))
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game); await physics_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	for player in [game.player_left, game.player_right]:
		var torso: MeshInstance3D = player.body_pivot.get_node("TorsoMesh")
		var head: MeshInstance3D = torso.get_node("HeadMesh")
		check(head.mesh.get_aabb().size.x < 0.21, "narrower athletic head silhouette")
		check(torso.mesh.get_aabb().size.x <= 0.361, "unchanged shoulder clearance envelope")
		check(head.mesh.get_surface_count() == 1 and head.mesh.surface_get_array_index_len(0) / 3 < 2200, "head features remain in one draw with bounded geometry")
		check(torso.mesh.get_aabb().size.y >= 0.32, "tapered torso retains body length")
		var collision: CollisionShape3D
		for child in player.get_children():
			if child is CollisionShape3D: collision = child
		check(collision != null and is_equal_approx(collision.shape.radius, 0.2), "body collider radius unchanged")
		var triangles: = 0
		for node in player.body_pivot.find_children("*", "MeshInstance3D", true, false):
			if node.mesh is ArrayMesh and node.layers != 0:
				check(node.mesh.get_surface_count() == 1, "one surface per original garment limb")
				triangles += node.mesh.surface_get_array_index_len(0) / 3
		check(triangles < 6400, "visible athlete including detailed head/hands stays below 6400 triangles")
		for arm in [player.right_arm_node, player.left_arm_node]:
			check(is_equal_approx(arm.upper_arm_length, 0.35) and is_equal_approx(arm.forearm_length, 0.35), "arm IK dimensions unchanged")
			check(arm.hand_mesh.mesh is ArrayMesh and arm.hand_mesh.mesh.get_surface_count() == 1, "articulated palm uses one surface")
			check(arm.articulated_hand != null, "hand model initialized")
		for leg in [player.right_leg_node, player.left_leg_node]:
			check(is_equal_approx(leg.thigh_length, Dimensions.THIGH_LENGTH) and is_equal_approx(leg.shin_length, Dimensions.SHIN_LENGTH), "leg IK uses central true segment dimensions")
			check(leg.foot_mesh.mesh.get_aabb().size.is_equal_approx(Vector3(0.1, 0.05, 0.16)), "exact shoe service-foot envelope retained")
	var arena = game.get_node("CourtArenaVisual")
	check(arena.get_child_count() == 5, "arena budget is two combined meshes, one brand and two signs")
	for child in arena.get_children(): check( not child is CollisionObject3D and not child is Light3D, "arena has no collision/light overhead")
	game.queue_free(); await process_frame
	for side in [0, 1]:
		var player = Side.new(side)
		for style in range(7):
			var hold: Vector3 = Styles.hold_offset(style)
			var plan: Dictionary = Styles.release_plan(player.global_position, side == 1, style)
			var stroke: float = Styles.stroke_duration(style)
			for charge in [0.0, 0.025, 0.1, 0.25, 0.44, 0.45, 0.65, 1.0]:
				var prep: PostureDefinition = Motion.serve_style_preparation(style, charge, hold)
				var tag: = "style%d side%d q%.3f" % [style, side, charge]
				var tx: = inspect_pose(player, prep, tag + " hold")


				if charge >= 0.45: check( not prep.has_meta("reference_serve_load"), tag + " full load unmodified")
				var previous: = tx.basis.get_rotation_quaternion()
				for step in range(1, ceili(float(plan.contact_time) * 60) + 1):
					var elapsed: float = minf(step / 60.0, plan.contact_time)
					var waiting: PostureDefinition = Motion.serve_style_wait(prep, elapsed / 0.12, style)
					var t: float = clampf(1.0 - (float(plan.contact_time) - elapsed) / stroke, 0, 1)
					var pose: PostureDefinition = Motion.serve_style_strike(waiting, t, style) if t > 0 else waiting
					tx = inspect_pose(player, pose, tag + " release%d" % step)
					var angle: float = rad_to_deg(previous.angle_to(tx.basis.get_rotation_quaternion()))
					max_rotation = maxf(max_rotation, angle)
					check(angle < 30.0, tag + " no one-frame paddle flip step%d angle%.3f" % [step, angle])
					previous = tx.basis.get_rotation_quaternion()
					if t >= 0.65:
						var expected: Transform3D = Path.world_transform(player, Motion._legacy_serve_style_strike(waiting, t, style))
						check((tx * PaddleSize.HEAD_OFFSET).distance_to(expected * PaddleSize.HEAD_OFFSET) < 1e-05 and tx.basis.z.distance_to(expected.basis.z) < 1e-05, tag + " exact original late head/face path")
	for failure in failures: push_error(failure)
	print("REFERENCE ATHLETE: %d checks, %d failures; maximum frame rotation %.3f degrees; chest gap %.4fm" % [checks, failures.size(), max_rotation, minimum_clearance])
	quit(0 if failures.is_empty() else 1)
