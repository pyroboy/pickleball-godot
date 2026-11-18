extends SceneTree


const P = preload("res://scripts/stroke_swing_path.gd")
const F = preload("res://scripts/paddle_grip_frame.gd")
const Ready = preload("res://scripts/incoming_ready_motion.gd")
const Support = preload("res://scripts/groundstroke_support_motion.gd")
var checks: = 0
var errors: Array[String] = []
var maximum_orientation_step: = 0.0
var maximum_finger_step: = 0.0
var maximum_elbow_step: = 0.0
var critical_pairs: Array = []
func vector_data(v: Vector3) -> Array: return [v.x, v.y, v.z]
func basis_data(b: Basis) -> Array: return [vector_data(b.x), vector_data(b.y), vector_data(b.z)]
func arm_record(arm, pose: PostureDefinition) -> Dictionary:
	return {"shoulder": vector_data(arm.upper_pivot.global_position), "elbow": vector_data(arm.forearm_pivot.global_position), 
		"wrist": vector_data(arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket), "hand_basis": basis_data(arm.hand_mesh.global_basis), 
		"grip_weight": P.support_grip_weight(pose), "support_mode": P._support_mode(pose), "left_pole": vector_data(pose.left_elbow_pole), "right_pole": vector_data(pose.right_elbow_pole)}
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok and errors.size() < 60: errors.append(label)
func run():
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	for p in [game.player_left, game.player_right]:
		p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false;p.current_velocity = Vector3.ZERO
		p.posture.editor_preview_mode = true
		var stance: = Basis(p._get_forehand_axis(), Vector3.UP, - p._get_forward_axis())
		for dominant in [0, 1]:
			var ready: PostureDefinition = PostureLibrary.instance().get_def(2).duplicate(true);ready.paddle_hand = dominant


			ready.left_hand_mode = 1;ready.left_hand_offset = Vector3.ZERO;ready.right_hand_offset = Vector3.ZERO
			var free: PostureDefinition = PostureLibrary.instance().get_def(0).duplicate(true);free.paddle_hand = dominant;free.left_hand_mode = 4
			if dominant == 1: free.left_hand_offset = Vector3.ZERO
			for reverse in [false, true]:
				var a: PostureDefinition = free if reverse else ready; var b: PostureDefinition = ready if reverse else free
				var previous: = Basis.IDENTITY
				var previous_elbow: = Vector3.ZERO
				var previous_fingers: Array[Quaternion] = []
				var previous_record: Dictionary = {}
				for step in range(101):
					var t: float = step / 100.0; var pose: PostureDefinition = P.blend_pose(a, b, t)
					var tag: String = "court%d dominant%d reverse%s step%d" % [p.player_num, dominant, str(reverse), step]
					p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
					var arm = p.right_arm_node if dominant == 1 else p.left_arm_node; var model = arm.articulated_hand
					var wrist: Vector3 = model.hand_mesh.global_transform * model.wrist_socket
					var expected: Vector3 = p.global_position + stance * P.support_wrist_offset(a).lerp(P.support_wrist_offset(b), t)
					check(wrist.distance_to(expected) < 1e-05, "actual wrist follows one continuous coordinate space")
					check(P.support_wrist_offset(pose).distance_to(P.support_wrist_offset(a).lerp(P.support_wrist_offset(b), t)) < 1e-05, "pure wrist query agrees with blend")
					check(absf(P.support_grip_weight(pose) - (t if reverse else 1.0 - t)) < 1e-05, "release and regrip retain continuous presentation weight")
					var main = p.left_arm_node if dominant == 1 else p.right_arm_node
					check(main.hand_mesh.global_basis.is_equal_approx(F.basis(p.paddle_node.global_basis, dominant == 1)), "anatomical hand keeps fixed bevel when roles swap")
					if step > 0:
						var angle: float = rad_to_deg(previous.get_rotation_quaternion().angle_to(model.hand_mesh.global_basis.get_rotation_quaternion()))
						maximum_orientation_step = maxf(maximum_orientation_step, angle)
						check(angle < 10.0, tag + " release/regrip mount step %.4f deg" % angle)
						var elbow_step: float = previous_elbow.distance_to(arm.forearm_pivot.global_position)
						maximum_elbow_step = maxf(maximum_elbow_step, elbow_step)
						check(elbow_step < 0.035, tag + " support elbow step %.5f m" % elbow_step)
						if angle >= 10.0 or elbow_step >= 0.035: critical_pairs.append({"tag": tag, "angle_deg": angle, "elbow_step_m": elbow_step, "previous": previous_record, "current": arm_record(arm, pose)})
					for bone in range(1, model.skeleton.get_bone_count()):


						if model.skeleton.get_bone_name(bone) == "wrist_cuff": continue
						var rotation: Quaternion = model.skeleton.get_bone_pose_rotation(bone)
						if step > 0:
							var angle: float = rad_to_deg(previous_fingers[bone - 1].angle_to(rotation))
							maximum_finger_step = maxf(maximum_finger_step, angle)
							check(angle < 5.0, "finger joints close continuously across support modes")
						if step == 0: previous_fingers.append(rotation)
						else: previous_fingers[bone - 1] = rotation
					previous = model.hand_mesh.global_basis
					previous_elbow = arm.forearm_pivot.global_position
					previous_record = arm_record(arm, pose)


			var recursive: PostureDefinition = P.blend_pose(ready, free, 0.5)
			var previous_weight: float = P.support_grip_weight(recursive)
			for step in range(120):
				recursive = Ready.blend_pose(recursive, ready, 1.0 / 60.0)
				var current_weight: float = P.support_grip_weight(recursive)
				check(current_weight >= previous_weight and current_weight - previous_weight < 0.1, "recursive Ready preserves and smoothly approaches grip weight")
				if current_weight < 0.999: check(P._support_mode(recursive) == 4, "regrip waits for orientation and closure")
				previous_weight = current_weight
			check(P._support_mode(recursive) == 1 and is_equal_approx(previous_weight, 1.0), "recursive Ready eventually regrips")
			var releasing: PostureDefinition = P.blend_pose(ready, free, 0.25)
			Support._apply(releasing, Support.tuck_target(free), 0.4)
			check(absf(P.support_grip_weight(releasing) - 0.45) < 1e-05, "off-hand tracking releases existing grip weight")
			for source in [ready, P.blend_pose(ready, free, 0.4), free]:
				p.posture.transition_pose_blend = source;p.posture.force_posture_update(source)
				var arm = p.right_arm_node if dominant == 1 else p.left_arm_node
				var socket: Vector3 = arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket
				var captured: PostureDefinition = p.posture.capture_displayed_pose()
				check((p.global_position + stance * P.support_wrist_offset(captured)).distance_to(socket) < 1e-05, "displayed capture keeps actual support socket for either dominant hand")
				check(absf(P.support_grip_weight(captured) - P.support_grip_weight(source)) < 1e-05, "displayed capture keeps support rotation/closure weight")
				var previous_mount: Basis = arm.hand_mesh.global_basis
				for step in range(21):
					var weight: float = step / 20.0
					var recovery: PostureDefinition = P.blend_pose(captured, ready, weight)
					p.posture.transition_pose_blend = recovery;p.posture.force_posture_update(recovery)
					var actual: Vector3 = arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket
					var expected: Vector3 = socket.lerp(p.global_position + stance * P.support_wrist_offset(ready), weight)
					check(actual.distance_to(expected) < 1e-05, "captured pose recovery stays in anatomical wrist space")
					var angle: float = rad_to_deg(previous_mount.get_rotation_quaternion().angle_to(arm.hand_mesh.global_basis.get_rotation_quaternion()))
					check(angle < 15.0, "court%d dominant%d source_weight%.2f recovery%d mount step%.3f deg" % [p.player_num, dominant, P.support_grip_weight(source), step, angle])
					previous_mount = arm.hand_mesh.global_basis
			check(P._support_mode(ready) == 1 and P._support_mode(free) == 4, "source support modes immutable")
	print("SUPPORT WRIST BLEND: ", checks, " checks, ", errors.size(), " failures; maximum1% support orientation step ", maximum_orientation_step, " deg; finger step ", maximum_finger_step, " deg; elbow step ", maximum_elbow_step, " m")
	var report: = FileAccess.open("/workspace/shared/pickleball-hands/support-wrist-critical-pairs.json", FileAccess.WRITE)
	if report: report.store_string(JSON.stringify({"critical_pairs": critical_pairs, "errors": errors}, "\t"));report.close()
	for error in errors: push_error(error)
	game.queue_free(); await process_frame;quit(0 if errors.is_empty() else 1)
