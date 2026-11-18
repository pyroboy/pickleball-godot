extends SceneTree

const Hand = preload("res://scripts/articulated_hand.gd")
const PaddleDimensions = preload("res://scripts/paddle_dimensions.gd")
var checks: = 0
var failures: Array[String] = []
var minimum_grip_gap: = INF
var minimum_cup_gap: = INF
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func _check_frame(arm, label: String) -> void :
	var model = arm.articulated_hand
	var wrist: Vector3 = arm.hand_mesh.global_transform * model.wrist_socket
	var actual_distal: Vector3 = (wrist - arm.forearm_pivot.global_position).normalized()
	var mesh_distal: Vector3 = arm.fore_mesh.global_basis.y.normalized()
	check(mesh_distal.dot(actual_distal) > 0.99999, label + " actual forearm mesh +Y is elbow-to-socket distal")
	var cuff: Transform3D = model.skeleton.get_bone_global_pose(Hand.WRIST_BRIDGE_BONE)
	var cuff_distal: Vector3 = (arm.hand_mesh.global_basis * cuff.basis * model.palm_contact_basis.x).normalized()
	check(cuff_distal.dot(actual_distal) > 0.99999, label + " actual bridge follows distal forearm")
	check(cuff.basis.determinant() > 0.99999, label + " proper cuff frame")
	check(model.skeleton.get_bone_count() == 17, label + "17 bones")
	var writes: int = model.wrist_bridge_update_count
	for repeat in range(30): model.update_wrist_bridge(arm.fore_mesh.global_basis)
	check(model.wrist_bridge_update_count == writes, label + " idle actual frame is cached")
func run() -> void :
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	for tween in get_processed_tweens(): tween.kill()
	game.game_serve.cleanup()
	for player in [game.player_left, game.player_right]:
		player.hitting.serving_visual_active = false;player.hitting.charge_visual_active = false;player.hitting.is_in_follow_through = false
		player.current_velocity = Vector3.ZERO;player.posture.editor_preview_mode = false;player.leg_ik.feet_initialized = false
		var ready: PostureDefinition = PostureLibrary.instance().get_def(20)
		player.posture.transition_pose_blend = ready;player.posture.force_posture_update(ready)
		for arm in [player.right_arm_node, player.left_arm_node]:
			var label: String = "court%d_%s" % [player.player_num, "left" if arm == player.left_arm_node else "right"]
			_check_frame(arm, label + " grip")
			var model = arm.articulated_hand
			var vertices: PackedVector3Array = model.sampled_triangles()
			var into_paddle: Transform3D = player.paddle_node.global_transform.affine_inverse() * arm.hand_mesh.global_transform
			var gap: = INF
			for face in range(0, vertices.size(), 3): gap = minf(gap, _triangle_axis_distance(into_paddle * vertices[face], into_paddle * vertices[face + 1], into_paddle * vertices[face + 2]) - PaddleDimensions.HANDLE_RADIUS)
			minimum_grip_gap = minf(minimum_grip_gap, gap)
			check(gap >= - 5e-05, label + " posed grip clears actual paddle cylinder %.7f" % gap)
			var normal: = Vector3.UP
			var side: float = -1.0 if arm == player.left_arm_node else 1.0
			var center: Vector3 = player.global_position + Vector3.UP * 0.15 + player._get_forward_axis() * 0.4 + player._get_forehand_axis() * 0.15 * side
			var presentation = player.arm_ik._hands
			presentation.mode = "CUP";model.set_pose("CUP")
			var mount: Transform3D = presentation._cup_mount(model, center, normal)
			var wrist: Vector3 = mount * model.wrist_socket
			var pole: Vector3 = player.global_position + player._get_forehand_axis() * 0.5 * side + Vector3.DOWN - player._get_forward_axis() * 0.5
			arm.solve_ik(mount.origin, pole, null, wrist);presentation.apply_mount(arm, mount, true)
			_check_frame(arm, label + " cup")
			var cup_gap: float = model.ball_surface_gap(arm.hand_mesh.to_local(center))
			minimum_cup_gap = minf(minimum_cup_gap, cup_gap)
			check(absf(cup_gap) < 0.0001, label + " posed cup stays tangent without skin penetration %.7f" % cup_gap)
			print("WRIST BRIDGE ", label, " grip_gap=", gap, " cup_gap=", cup_gap)
	for failure in failures: push_error(failure)
	print("WRIST BRIDGE REAL RIG: ", checks, " checks, ", failures.size(), " failures; min grip=", minimum_grip_gap, " min cup=", minimum_cup_gap)
	game.queue_free(); await process_frame
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

func _segment_axis_distance(a: Vector2, b: Vector2) -> float:
	var edge: = b - a
	if edge.length_squared() < 1e-12:
		return a.length()
	var t: = clampf( - a.dot(edge) / edge.length_squared(), 0, 1)
	return (a + edge * t).length()
