extends SceneTree


const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Styles = preload("res://scripts/serve_style.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const Body = preload("res://scripts/body_clearance.gd")
const Paddle = preload("res://scripts/paddle_clearance.gd")
const Applier = preload("res://scripts/posture_skeleton_applier.gd")
var rows: Array = []
var surface: Array[Vector3] = []
var output: = "/workspace/shared/pickleball-hands/serve-load-space-search.json"
var bevel: = 315.0
func _initialize(): call_deferred("run")
func sample(p, source: PostureDefinition, key: Dictionary):
	var pose: PostureDefinition = source.lerp_with(source, 0)


	var envelope: float = smoothstep(0.0, 0.65, key.charge)
	pose.paddle_forehand_mul += float(key.outward) * envelope
	pose.paddle_forward_mul -= float(key.back) * envelope
	pose.body_yaw_deg += float(key.turn) * envelope
	p.posture.editor_preview_mode = false;p.leg_ik.feet_initialized = false
	p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
	var arm = p.right_arm_node; var model = arm.articulated_hand
	var anchor: Vector3 = arm.hand_pivot.global_position
	var mount: = Transform3D(p.paddle_node.global_basis * Basis(Vector3.UP, deg_to_rad(bevel)), anchor)
	var wrist: Vector3 = mount * model.wrist_socket
	var hint: Vector3 = p.global_position + Applier.stance_offset(pose.right_elbow_pole, p._get_forehand_axis(), p._get_forward_axis())
	hint = p.arm_ik._rotate_shoulder_pole(arm, hint, pose.right_shoulder_rotation_deg)
	var pole: Vector3 = Anatomy.conditioned_pole(arm.upper_pivot.global_position, wrist, hint, mount.basis * model.anatomical_basis.x, arm.upper_arm_length, arm.forearm_length)
	arm.solve_ik(anchor, pole, p.paddle_node.global_transform, wrist)
	p.arm_ik._hands.apply_mount(arm, mount, false)
	var shoulder: Vector3 = arm.upper_pivot.global_position; var elbow: Vector3 = arm.forearm_pivot.global_position
	var channels: Dictionary = Anatomy.decompose(Anatomy.forearm_reference(shoulder, elbow, wrist, Vector3.UP, false), mount.basis * model.anatomical_basis, model.radial_sign)
	var geometry: Dictionary = Body.volumes(p, pose, p.body_pivot.global_transform)
	var upper: Dictionary = Body.mesh_surface_margins(arm.upper_mesh, geometry, shoulder, elbow, 0.08)
	var fore: Dictionary = Body.mesh_surface_margins(arm.fore_mesh, geometry)
	var skin: = INF
	for region in Body.REGIONS: skin = minf(skin, minf(upper[region], fore[region]))
	var paddle: Transform3D = p.paddle_node.global_transform
	var requested: Vector3 = p.global_position + pose.resolve_paddle_offset(p._get_forehand_axis(), p._get_forward_axis())
	var row: Dictionary = key.duplicate()
	row.merge({"bevel": bevel, "channels": channels, "arm_surface": skin, "upper": upper, "forearm": fore, "score": maxf(channels.coupled_budget_ratio, pow(channels.forearm_axial_deg / 90.0, 2)), "maximum_link_scale": arm.visual_stretch, "paddle_clamp_m": requested.distance_to(paddle * PaddleSize.HEAD_OFFSET), "paddle_body": Body.sample_paddle(paddle, surface, geometry), "face": Paddle.distance_to_paddle_shape(paddle.affine_inverse() * p.body_pivot.get_node("TorsoMesh/HeadMesh").global_position) - 0.12})
	rows.append(row)
func run():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		if arg == "--current-mount": bevel = 135.0
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	var p = game.player_left
	p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
	p.current_velocity = Vector3.ZERO;p.posture._committed_incoming_posture = -1
	surface = Paddle.sample_head_surface()
	for outward in [0.0, 0.1, 0.14, 0.18]:
		for back in [0.0, 0.04, 0.08]:
			for turn in [-8.0, 0.0, 8.0]:
				for style in range(7):
					for q in [0.5, 0.75, 1.0]:
						var source: PostureDefinition = Motion.serve_style_preparation(style, q, Styles.hold_offset(style))
						sample(p, source, {"outward": outward, "back": back, "turn": turn, "style": style, "charge": q})
	var file: = FileAccess.open(output, FileAccess.WRITE);file.store_string(JSON.stringify(rows, "\t"));file.close()
	print("SERVE LOAD SPACE SEARCH ", rows.size(), " -> ", output)
	game.queue_free(); await process_frame;quit()
