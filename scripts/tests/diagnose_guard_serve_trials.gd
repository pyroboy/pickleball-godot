extends SceneTree

const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const M = preload("res://scripts/drive_serve_motion.gd")
const P = preload("res://scripts/stroke_swing_path.gd")
const O = preload("res://scripts/stroke_preparation_orientation.gd")
const A = preload("res://scripts/arm_anatomy.gd")
const G = preload("res://scripts/paddle_clearance.gd")
const C = preload("res://scripts/body_clearance.gd")
const Styles = preload("res://scripts/serve_style.gd")
var edge_only: = false
var output: = "/workspace/shared/pickleball-hands/guard-serve-trials.json"
var records: Array = []
var surface: Array[Vector3] = []
func _initialize(): call_deferred("run")
func rotate_grip(pose: PostureDefinition, turn: Basis, raise_m: float = 0.0, advance: float = 0.0) -> PostureDefinition:
	var result: PostureDefinition = pose.lerp_with(pose, 0)
	var old: Basis = O.canonical_basis(pose); var basis: Basis = old * turn
	var offset: Vector3 = pose.left_hand_offset if pose.paddle_hand == 1 else pose.right_hand_offset
	var from_head: Vector3 = (PaddleSize.MAIN_GRIP_OFFSET - PaddleSize.HEAD_OFFSET) + offset
	var grip: Vector3 = Vector3(pose.paddle_forehand_mul, pose.paddle_y_offset, - pose.paddle_forward_mul) + old * from_head
	var head: Vector3 = grip + Vector3.UP * raise_m + Vector3.FORWARD * advance - basis * from_head
	O.set_canonical_basis(result, basis)
	result.paddle_forehand_mul = head.x;result.paddle_y_offset = head.y;result.paddle_forward_mul = - head.z
	return result
func capture(p, pose: PostureDefinition, label: String):
	p.posture.editor_preview_mode = false;p.current_velocity = Vector3.ZERO;p.leg_ik.feet_initialized = false
	p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
	var arm = p.left_arm_node if pose.paddle_hand == 1 else p.right_arm_node; var model = arm.articulated_hand
	var wrist: Vector3 = model.hand_mesh.global_transform * model.wrist_socket
	var frame: Basis = A.forearm_reference(arm.upper_pivot.global_position, arm.forearm_pivot.global_position, wrist, Vector3.UP, pose.paddle_hand == 1)
	var channels: Dictionary = A.decompose(frame, model.hand_mesh.global_basis * model.anatomical_basis, model.radial_sign)
	var paddle: Transform3D = p.paddle_node.global_transform; var chest: Node3D = p.body_pivot.get_node("TorsoMesh")
	var geometry: Dictionary = C.volumes(p, pose, p.body_pivot.global_transform)
	var margins: Dictionary = C.sample_paddle(paddle, surface, geometry)
	records.append({"label": label, "side": p.player_num, "channels": channels, "face": G.distance_to_paddle_shape(paddle.affine_inverse() * chest.get_node("HeadMesh").global_position) - 0.12, "body": margins, "forearm_body": C.sample_segment(arm.forearm_pivot.global_position, wrist, 0.037, geometry), "wrist_reach": wrist.distance_to(arm.upper_pivot.global_position), "grip_error": arm.hand_pivot.global_position.distance_to(paddle * (PaddleSize.MAIN_GRIP_OFFSET + pose.right_hand_offset))})
func run():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		if arg == "--edge-only": edge_only = true
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	surface = G.sample_head_surface()
	var loaded: Basis = Basis(Vector3.UP, deg_to_rad(-45)) * Basis(Vector3.RIGHT, deg_to_rad(40)) * Basis(Vector3.BACK, deg_to_rad(-15))
	var rest: Basis = Basis(Vector3.UP, deg_to_rad(-30)) * Basis(Vector3.RIGHT, deg_to_rad(-40)) * Basis(Vector3.BACK, deg_to_rad(20))
	for p in [game.player_left, game.player_right]:
		p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
		p.posture._committed_incoming_posture = -1
		var ready: PostureDefinition = PostureLibrary.instance().get_def(20)
		capture(p, ready, "ready_original")
		for rise in [0.2, 0.25, 0.3]:
			for advance in [0.0, 0.03, 0.06]: capture(p, rotate_grip(ready, Basis.IDENTITY, rise, advance), "ready_raise%.2f_advance%.2f" % [rise, advance])
		for style in range(0 if edge_only else 7):
			for q in [0.0, 0.25, 0.5, 0.75, 1.0]:
				var source: PostureDefinition = M.serve_style_preparation(style, q, Styles.hold_offset(style))
				var held: PostureDefinition = rotate_grip(source, Basis(rest.get_rotation_quaternion().slerp(loaded.get_rotation_quaternion(), smoothstep(0, 0.45, q))))
				var load: PostureDefinition = rotate_grip(M.original_serve_load(source), loaded)
				capture(p, held, "serve%d_q%.2f_held" % [style, q])
				capture(p, load, "serve%d_q%.2f_loaded" % [style, q])
				for t in [0.2, 0.4, 0.65, 1.0]:
					var legacy: PostureDefinition = M.serve_style_strike(source, t, style)
					var trial: PostureDefinition = P.blend_pose(load, legacy, smoothstep(0, 0.65, t)) if t < 0.65 else legacy
					capture(p, trial, "serve%d_q%.2f_strike%.2f" % [style, q, t])
	var file: = FileAccess.open(output, FileAccess.WRITE);file.store_string(JSON.stringify({"records": records, "note": "Candidate geometry, actual solver and supported rig. No production guard/serve edit."}, "\t"));file.close()
	print("GUARD/SERVE TRIALS ", records.size(), " -> ", output);game.queue_free(); await process_frame;quit()
