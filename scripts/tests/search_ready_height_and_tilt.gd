extends SceneTree


const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const A = preload("res://scripts/arm_anatomy.gd")
const C = preload("res://scripts/body_clearance.gd")
const G = preload("res://scripts/paddle_clearance.gd")
const O = preload("res://scripts/stroke_preparation_orientation.gd")
const M = preload("res://scripts/drive_serve_motion.gd")
const Applier = preload("res://scripts/posture_skeleton_applier.gd")
const D = preload("res://scripts/player_body_dimensions.gd")
var opposite_mount: = true
var output: = "/workspace/shared/pickleball-hands/ready-height-tilt-search.json"
var records: Array = []
var surface: Array[Vector3] = []
func _initialize(): call_deferred("run")
func rotate_grip(pose: PostureDefinition, degrees: float) -> PostureDefinition:
	var result: PostureDefinition = pose.lerp_with(pose, 0)
	var old: Basis = O.canonical_basis(pose); var shaft: Basis = Basis(Vector3.UP, PI) if opposite_mount else Basis.IDENTITY
	var basis: Basis = old * shaft * Basis(Vector3.BACK, deg_to_rad(degrees))
	var offset: Vector3 = pose.right_hand_offset if pose.paddle_hand == 0 else pose.left_hand_offset
	var from_head: = (PaddleSize.MAIN_GRIP_OFFSET - PaddleSize.HEAD_OFFSET) + offset
	var grip: = Vector3(pose.paddle_forehand_mul, pose.paddle_y_offset, - pose.paddle_forward_mul) + old * from_head
	var head: Vector3 = grip - basis * from_head
	O.set_canonical_basis(result, basis);result.paddle_forehand_mul = head.x;result.paddle_y_offset = head.y;result.paddle_forward_mul = - head.z
	return result
func apply_trial_mounts(p, pose: PostureDefinition):
	if not opposite_mount: return
	for side in [0, 1]:
		var arm = p.right_arm_node if side == 0 else p.left_arm_node
		var bevel: float = 315.0 if side == 0 else 135.0
		var anchor: Vector3 = arm.hand_pivot.global_position
		var mount: = Transform3D(p.paddle_node.global_basis * Basis(Vector3.UP, deg_to_rad(bevel)), anchor)
		var wrist: Vector3 = mount * arm.articulated_hand.wrist_socket
		var raw: Vector3 = pose.right_elbow_pole if side == 0 else pose.left_elbow_pole
		var hint: Vector3 = p.global_position + Applier.stance_offset(raw, p._get_forehand_axis(), p._get_forward_axis())
		hint = p.arm_ik._rotate_shoulder_pole(arm, hint, pose.right_shoulder_rotation_deg if side == 0 else pose.left_shoulder_rotation_deg)
		var pole: Vector3 = A.conditioned_pole(arm.upper_pivot.global_position, wrist, hint, mount.basis * arm.articulated_hand.anatomical_basis.x, 0.35, 0.35)
		arm.solve_ik(anchor, pole, p.paddle_node.global_transform if side == pose.paddle_hand else null, wrist)
		p.arm_ik._hands.apply_mount(arm, mount, side != pose.paddle_hand)
func vision_margin(p, head: Node3D, paddle: Transform3D) -> float:


	var forward: Vector3 = p._get_forward_axis(); var facing: = Basis(forward.cross(Vector3.UP), Vector3.UP, - forward)
	var scale: = Vector3(D.HEAD_RADIUS / 0.089, D.HEAD_HEIGHT / 0.24, D.HEAD_RADIUS / 0.089)
	var direction: Vector3 = head.global_basis * facing * Vector3.FORWARD
	var nearest: = INF
	for side in [-1.0, 1.0]:
		var eye: Vector3 = Vector3(side * 0.033, 0.022, - 0.0735) + (Basis(Vector3.UP, - side * 0.38) * Vector3.FORWARD) * 0.0055
		var pupil: Vector3 = head.global_transform * (facing * (eye * scale))
		for step in range(101): nearest = minf(nearest, G.distance_to_paddle_shape(paddle.affine_inverse() * (pupil + direction * step * 0.01)))
	return nearest
func sample(p, pose: PostureDefinition, key: Dictionary):
	p.posture.editor_preview_mode = false;p.leg_ik.feet_initialized = false;p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
	apply_trial_mounts(p, pose)
	var geometry: Dictionary = C.volumes(p, pose, p.body_pivot.global_transform)
	var tx: Transform3D = p.paddle_node.global_transform; var head: Node3D = p.body_pivot.get_node("TorsoMesh/HeadMesh")
	var score: = 0.0; var skin: = INF; var scale: = 1.0; var arms: Array = []
	for side in [0, 1]:
		var arm = p.right_arm_node if side == 0 else p.left_arm_node; var model = arm.articulated_hand
		var s: Vector3 = arm.upper_pivot.global_position; var e: Vector3 = arm.forearm_pivot.global_position; var w: Vector3 = model.hand_mesh.global_transform * model.wrist_socket
		var channels: Dictionary = A.decompose(A.forearm_reference(s, e, w, Vector3.UP, side == 1), model.hand_mesh.global_basis * model.anatomical_basis, model.radial_sign)
		var upper: Dictionary = C.mesh_surface_margins(arm.upper_mesh, geometry, s, e, 0.08); var fore: Dictionary = C.mesh_surface_margins(arm.fore_mesh, geometry)
		for region in C.REGIONS: skin = minf(skin, minf(upper[region], fore[region]))
		score = maxf(score, maxf(channels.coupled_budget_ratio, pow(channels.forearm_axial_deg / 90, 2)))
		scale = maxf(scale, maxf(s.distance_to(e) / 0.35, e.distance_to(w) / 0.35))
		arms.append({"channels": channels, "upper": upper, "forearm": fore})
	var row: Dictionary = key.duplicate()
	row.merge({"score": score, "arm_surface": skin, "maximum_link_scale": scale, "face": G.distance_to_paddle_shape(tx.affine_inverse() * head.global_position) - 0.12, "vision_margin": vision_margin(p, head, tx), "paddle_body": C.sample_paddle(tx, surface, geometry), "arms": arms})
	records.append(row)
func run():
	for arg in OS.get_cmdline_user_args():
		if arg == "--current-mount": opposite_mount = false
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	var p = game.player_left;p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false;p.current_velocity = Vector3.ZERO;p.posture._committed_incoming_posture = -1
	var source: PostureDefinition = PostureLibrary.instance().get_def(20)
	surface = G.sample_head_surface()
	for lower in [0.0, 0.05, 0.1, 0.15]:
		for tilt in [-30.0, -20.0, -10.0, 0.0, 10.0, 20.0, 30.0]:
			for pole_forward in [ - 0.05, 0.0, 0.05]:
				for dominant in [0, 1]:
					for kitchen in [false, true]:
						var pose: PostureDefinition = source.duplicate(true);pose.paddle_hand = dominant
						if kitchen: pose = M.kitchen_ready(pose)
						pose = rotate_grip(pose, tilt);pose.paddle_y_offset -= lower
						pose.right_elbow_pole.z += pole_forward;pose.left_elbow_pole.z += pole_forward
						sample(p, pose, {"lower": lower, "tilt": tilt, "pole_forward_delta": pole_forward, "dominant": dominant, "kitchen": kitchen, "right_mount": 315 if opposite_mount else 135})
	var file: = FileAccess.open(output, FileAccess.WRITE);file.store_string(JSON.stringify(records, "\t"));file.close()
	print("READY HEIGHT/TILT SEARCH ", records.size(), " -> ", output);game.queue_free(); await process_frame;quit()
