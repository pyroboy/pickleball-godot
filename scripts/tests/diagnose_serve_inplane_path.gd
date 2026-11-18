extends SceneTree



const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Styles = preload("res://scripts/serve_style.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Orientation = preload("res://scripts/stroke_preparation_orientation.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const Body = preload("res://scripts/body_clearance.gd")
const Paddle = preload("res://scripts/paddle_clearance.gd")
const FLAT_POLE = Vector3(0.405203580856323, 0.059627890586853, 0.034146785736084)
const DROP_POLE = Vector3(0.442943334579468, 0.0938082933425903, 0.100467205047607)
var rows: Array = []
var surface: Array[Vector3] = []
var output: = "/workspace/shared/pickleball-hands/serve-inplane-path.json"
var angle: = -70.0
func _initialize(): call_deferred("run")
func sample(p, source: PostureDefinition, style: int, charge: float, phase: String, progress: float):
	var pose: PostureDefinition = source.duplicate(true)
	var before: Transform3D = Path.world_transform(p, source)
	Orientation.set_canonical_basis(pose, Orientation.canonical_basis(source) * Basis(Vector3.BACK, deg_to_rad(angle)))
	pose.right_elbow_pole = DROP_POLE if Styles.is_drop(style) else FLAT_POLE
	p.posture.editor_preview_mode = false;p.leg_ik.feet_initialized = false
	p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
	var arm = p.right_arm_node; var model = arm.articulated_hand
	var shoulder: Vector3 = arm.upper_pivot.global_position; var elbow: Vector3 = arm.forearm_pivot.global_position
	var wrist: Vector3 = model.hand_mesh.global_transform * model.wrist_socket
	var channels: Dictionary = Anatomy.decompose(Anatomy.forearm_reference(shoulder, elbow, wrist, Vector3.UP, false), model.hand_mesh.global_basis * model.anatomical_basis, model.radial_sign)
	var geometry: Dictionary = Body.volumes(p, pose, p.body_pivot.global_transform)
	var upper: Dictionary = Body.mesh_surface_margins(arm.upper_mesh, geometry, shoulder, elbow, 0.08)
	var fore: Dictionary = Body.mesh_surface_margins(arm.fore_mesh, geometry)
	var skin: = INF
	for region in Body.REGIONS: skin = minf(skin, minf(upper[region], fore[region]))
	var paddle: Transform3D = p.paddle_node.global_transform
	rows.append({"team": p.player_num, "style": style, "charge": charge, "phase": phase, "progress": progress, "angle": angle, "channels": channels, "arm_surface": skin, "upper": upper, "forearm": fore, "score": maxf(channels.coupled_budget_ratio, pow(channels.forearm_axial_deg / 90.0, 2)), "maximum_link_scale": arm.visual_stretch, "elbow_y_below_shoulder": shoulder.y - elbow.y, "head_delta": (before * PaddleSize.HEAD_OFFSET).distance_to(paddle * PaddleSize.HEAD_OFFSET), "normal_delta": before.basis.z.distance_to(paddle.basis.z), "paddle_body": Body.sample_paddle(paddle, surface, geometry), "face": Paddle.distance_to_paddle_shape(paddle.affine_inverse() * p.body_pivot.get_node("TorsoMesh/HeadMesh").global_position) - 0.12})
func run():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		if arg.begins_with("--angle="): angle = float(arg.trim_prefix("--angle="))
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	surface = Paddle.sample_head_surface()
	for p in [game.player_left, game.player_right]:
		p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
		p.current_velocity = Vector3.ZERO;p.posture._committed_incoming_posture = -1
		for style in range(7):
			var plan: Dictionary = Styles.release_plan(p.global_position, p.player_num == 1, style)
			var relative: Vector3 = plan.contact_position - p.global_position
			var contact: = Vector3(relative.dot(p._get_forehand_axis()), relative.y, relative.dot(p._get_forward_axis()))
			for charge in [0.0, 0.5, 1.0]:
				var prep: PostureDefinition = Motion.serve_style_preparation(style, charge, Styles.hold_offset(style))
				var loaded: PostureDefinition = Motion.serve_style_wait(prep, 1.0, style, contact)
				sample(p, prep, style, charge, "HELD", 0.0)
				for progress in [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]:
					sample(p, Motion.serve_style_wait(prep, progress, style, contact), style, charge, "WAIT", progress)
					sample(p, Motion.serve_style_strike(loaded, progress, style, contact), style, charge, "STRIKE", progress)
					sample(p, Motion.serve_style_follow_through(style, charge, progress, contact), style, charge, "FOLLOW", progress)
	var file: = FileAccess.open(output, FileAccess.WRITE);file.store_string(JSON.stringify(rows, "\t"));file.close()
	print("SERVE INPLANE PATH ", rows.size(), " -> ", output)
	game.queue_free(); await process_frame;quit()
