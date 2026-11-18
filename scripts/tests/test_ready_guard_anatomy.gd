extends SceneTree
const M = preload("res://scripts/drive_serve_motion.gd")
const P = preload("res://scripts/stroke_swing_path.gd")
const B = preload("res://scripts/stroke_body_pose.gd")
const A = preload("res://scripts/arm_anatomy.gd")
const C = preload("res://scripts/body_clearance.gd")
const G = preload("res://scripts/paddle_clearance.gd")
var checks: = 0
var errors: Array[String] = []
var records: Array = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok and errors.size() < 100: errors.append(label)
func run():
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	var surface: Array[Vector3] = G.sample_head_surface()
	for p in [game.player_left, game.player_right]:
		p.current_velocity = Vector3.ZERO;p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
		p.posture._committed_incoming_posture = -1
		for dominant in [0, 1]:
			for kitchen in [false, true]:
				for yaw in [0.0, -60.0, 60.0]:
					var pose: PostureDefinition = preload("res://scripts/ready_guard_profile.gd").authored_guard(dominant).duplicate(true)
					pose.paddle_hand = dominant
					if kitchen: pose = M.kitchen_ready(pose)
					pose = P.rotate_guard(pose, yaw)
					p.posture.editor_preview_mode = false;p.leg_ik.feet_initialized = false;p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
					var tag: = "court%d hand%d kitchen%s yaw%.0f" % [p.player_num, dominant, kitchen, yaw]
					var geometry: Dictionary = C.volumes(p, pose, p.body_pivot.global_transform)
					var paddle: Transform3D = p.paddle_node.global_transform
					var face: float = G.distance_to_paddle_shape(paddle.affine_inverse() * p.body_pivot.get_node("TorsoMesh/HeadMesh").global_position) - 0.12
					check(face >= 0.08, tag + " face clearance")
					var body: Dictionary = C.sample_paddle(paddle, surface, geometry)
					for region in C.REGIONS: check(body[region] >= 0, tag + " paddle clears " + region)
					for side in [0, 1]:
						var arm = p.right_arm_node if side == 0 else p.left_arm_node; var model = arm.articulated_hand
						var s: Vector3 = arm.upper_pivot.global_position; var e: Vector3 = arm.forearm_pivot.global_position; var w: Vector3 = model.hand_mesh.global_transform * model.wrist_socket
						var channels: Dictionary = A.decompose(A.forearm_reference_for_arm(arm, w, side == 1), model.hand_mesh.global_basis * model.anatomical_basis, model.radial_sign)
						check(absf(s.distance_to(e) - 0.35) < 1e-05 and absf(e.distance_to(w) - 0.35) < 1e-05, tag + " exact real arm links")
						var upper: Dictionary = C.sample_segment(s, e, 0.058, geometry, 0.128)
						var fore: Dictionary = C.sample_segment(e, w, 0.037, geometry)
						var upper_surface: Dictionary = C.mesh_surface_margins(arm.upper_mesh, geometry, s, e, 0.08)
						var fore_surface: Dictionary = C.mesh_surface_margins(arm.fore_mesh, geometry)
						for region in C.REGIONS:
							check(upper_surface[region] >= - 3e-05 and fore_surface[region] >= - 3e-05, tag + " arm%d clears %s" % [side, region])
						check(channels.within_animation_budget, tag + " arm%d anatomical budget %s" % [side, channels])
						records.append({"tag": tag, "arm": side, "channels": channels, "face": face, "body": body, "upper": upper, "forearm": fore, "upper_surface": upper_surface, "forearm_surface": fore_surface})
	var file: = FileAccess.open("/workspace/shared/pickleball-hands/ready-guard-anatomy.json", FileAccess.WRITE);file.store_string(JSON.stringify({"checks": checks, "errors": errors, "records": records}, "\t"));file.close()
	print("READY GUARD ANATOMY: ", checks, " checks, ", errors.size(), " failures")
	for error in errors: push_error(error)
	game.queue_free(); await process_frame;quit(0 if errors.is_empty() else 1)
