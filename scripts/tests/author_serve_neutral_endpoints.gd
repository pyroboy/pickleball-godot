extends SceneTree



const Motion = preload("res://scripts/drive_serve_motion.gd")
const Styles = preload("res://scripts/serve_style.gd")
const Orientation = preload("res://scripts/stroke_preparation_orientation.gd")
const Grip = preload("res://scripts/paddle_grip_frame.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const Body = preload("res://scripts/body_clearance.gd")
const Paddle = preload("res://scripts/paddle_clearance.gd")
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
var rows: Array = []
var surface: Array[Vector3] = []
var output: = "/workspace/shared/pickleball-hands/neutral-serve-endpoint-rig.json"
var source_phase: = "HELD"
func _initialize(): call_deferred("run")
func vec(v: Vector3) -> Array: return [v.x, v.y, v.z]
func adjusted_body_pose(pose: PostureDefinition, _config: Dictionary) -> PostureDefinition: return pose
func sample(p, config: Dictionary, style: int, charge: float, protraction: float):
	var pose: PostureDefinition = Motion.serve_style_preparation(style, charge, Styles.hold_offset(style)) if source_phase == "HELD" else Motion.serve_style_follow_through(style, charge, 1.0)
	var dominant: int = int(config.get("dominant", 0))
	if source_phase == "READY":
		pose = PostureLibrary.instance().get_def(20).duplicate(true)
		if style == 1: pose = Motion.kitchen_ready(pose)
		pose.left_hand_mode = 4
		pose.paddle_hand = dominant
		pose.right_hand_offset = Vector3(0.08, 0, - 0.22) if dominant == 1 else Vector3.ZERO
		pose.left_hand_offset = Vector3.ZERO if dominant == 1 else Vector3( - 0.08, 0, - 0.22)
	pose = adjusted_body_pose(pose, config)
	pose.shoulder_protraction_m = protraction
	p.leg_ik.feet_initialized = false;p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
	var arm = p.left_arm_node if dominant == 1 else p.right_arm_node; var model = arm.articulated_hand
	var fh: Vector3 = p._get_forehand_axis(); var fwd: Vector3 = p._get_forward_axis(); var stance: = Basis(fh, Vector3.UP, - fwd)
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var wrist: Vector3 = p.global_position + fh * float(config.wrist_x) + Vector3.UP * (float(config.wrist_y) + float(config.get("wrist_upshift", 0.0)) * charge) + fwd * (float(config.wrist_forward0) - float(config.load_backshift) * charge)
	var hint: Vector3 = p.global_position + fh * float(config.pole_x) + Vector3.UP * float(config.pole_y) + fwd * float(config.pole_forward)
	if config.has("pole_relative_to_shoulder"):
		var radial: Vector3 = config.pole_relative_to_shoulder
		hint = shoulder + fh * radial.x + Vector3.UP * radial.y + fwd * radial.z
	var span: Vector3 = wrist - shoulder; var distance: float = span.length(); var axis: Vector3 = span.normalized()
	if distance >= arm.upper_arm_length + arm.forearm_length - 0.01: return
	var along: float = (pow(arm.upper_arm_length, 2) - pow(arm.forearm_length, 2) + distance * distance) / (2 * distance)
	var radius: float = sqrt(maxf(0, pow(arm.upper_arm_length, 2) - along * along))
	var pole_direction: Vector3 = hint - shoulder;pole_direction = (pole_direction - axis * pole_direction.dot(axis)).normalized()
	var elbow: Vector3 = shoulder + axis * along + pole_direction * radius
	var neutral: Basis = Anatomy.forearm_reference(shoulder, elbow, wrist, Vector3.UP, dominant == 1)
	var relative_hand: Basis = config.get("relative_hand_basis", Basis(Vector3.RIGHT, deg_to_rad(float(config.axial))))
	var mount: Basis = neutral * relative_hand * model.anatomical_basis.inverse()
	var paddle_basis: Basis = mount * Grip.basis(Basis.IDENTITY, dominant == 1).inverse()
	var anchor: Vector3 = wrist - mount * model.wrist_socket
	var main_offset: Vector3 = pose.left_hand_offset if dominant == 1 else pose.right_hand_offset
	var head: Vector3 = anchor + paddle_basis * ((PaddleSize.HEAD_OFFSET - PaddleSize.MAIN_GRIP_OFFSET) - main_offset) - p.global_position
	Orientation.set_canonical_basis(pose, stance.inverse() * paddle_basis)
	pose.paddle_forehand_mul = head.dot(fh);pose.paddle_y_offset = head.y;pose.paddle_forward_mul = head.dot(fwd)
	var rotation: Vector3 = pose.left_shoulder_rotation_deg if dominant == 1 else pose.right_shoulder_rotation_deg
	var shoulder_rotation: Basis = stance * Basis.from_euler(rotation * (PI / 180.0)) * stance.inverse()
	var authored: Vector3 = shoulder + shoulder_rotation.inverse() * (elbow - shoulder) - p.global_position
	if dominant == 1: pose.left_elbow_pole = Vector3(authored.dot(fh), authored.y, authored.dot(fwd))
	else: pose.right_elbow_pole = Vector3(authored.dot(fh), authored.y, authored.dot(fwd))
	p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
	var actual_wrist: Vector3 = arm.hand_mesh.global_transform * model.wrist_socket
	var actual_elbow: Vector3 = arm.forearm_pivot.global_position
	var channels: Dictionary = Anatomy.decompose(Anatomy.forearm_reference(arm.upper_pivot.global_position, actual_elbow, actual_wrist, Vector3.UP, dominant == 1), arm.hand_mesh.global_basis * model.anatomical_basis, model.radial_sign)
	var geometry: Dictionary = Body.volumes(p, pose, p.body_pivot.global_transform)
	var upper: Dictionary = Body.mesh_surface_margins(arm.upper_mesh, geometry, arm.upper_pivot.global_position, actual_elbow, 0.08)
	var fore: Dictionary = Body.mesh_surface_margins(arm.fore_mesh, geometry)
	var skin: = INF
	for region in Body.REGIONS: skin = minf(skin, minf(upper[region], fore[region]))
	var tx: Transform3D = p.paddle_node.global_transform
	var arm_paddle: Dictionary = {}
	var support = p.right_arm_node if dominant == 1 else p.left_arm_node
	var support_upper: Dictionary = Body.mesh_surface_margins(support.upper_mesh, geometry, support.upper_pivot.global_position, support.forearm_pivot.global_position, 0.08)
	var support_fore: Dictionary = Body.mesh_surface_margins(support.fore_mesh, geometry)
	var support_skin: = INF
	for region in Body.REGIONS: support_skin = minf(support_skin, minf(support_upper[region], support_fore[region]))
	var limb_meshes: Array = [arm.upper_mesh, arm.fore_mesh, support.upper_mesh, support.fore_mesh, 
		p.right_leg_node.thigh_mesh, p.right_leg_node.shin_mesh, p.left_leg_node.thigh_mesh, p.left_leg_node.shin_mesh]
	for index in range(limb_meshes.size()):
		var mesh: MeshInstance3D = limb_meshes[index]
		var nearest: = INF
		var local: Transform3D = tx.affine_inverse() * mesh.global_transform
		for point in Body.mesh_surface_points(mesh): nearest = minf(nearest, Paddle.distance_to_paddle_shape(local * point))
		arm_paddle["%d_%s" % [index, mesh.name]] = nearest
	var local_ball: Vector3 = Styles.hold_offset(style); var ball: Vector3 = p.global_position + fh * local_ball.x + Vector3.UP * local_ball.y + fwd * local_ball.z
	var floor: = INF
	for point in surface: floor = minf(floor, (tx * point).y - p.COURT_FLOOR_Y)
	rows.append({"config": config, "style": style, "charge": charge, "phase": source_phase, "protraction": protraction, "channels": channels, "arm_surface": skin, "support_arm_surface": support_skin, "upper": upper, "forearm": fore, "arm_paddle": arm_paddle, "maximum_link_scale": maxf(arm.visual_stretch, support.visual_stretch), "wrist_error": actual_wrist.distance_to(wrist), "elbow_error": actual_elbow.distance_to(elbow), "head": vec(Vector3(pose.paddle_forehand_mul, pose.paddle_y_offset, pose.paddle_forward_mul)), "rotation": vec(pose.resolve_paddle_rotation_deg(-1, -1)), "pole": vec(pose.left_elbow_pole if dominant == 1 else pose.right_elbow_pole), "paddle_body": Body.sample_paddle(tx, surface, geometry), "floor": floor, "held_ball_gap": Paddle.distance_to_paddle_shape(tx.affine_inverse() * ball) - 0.0375, "face": Paddle.distance_to_paddle_shape(tx.affine_inverse() * p.body_pivot.get_node("TorsoMesh/HeadMesh").global_position) - 0.12})
func run():
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	var p = game.player_left;p.posture.editor_preview_mode = false
	p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
	p.current_velocity = Vector3.ZERO;p.posture._committed_incoming_posture = -1
	surface = Paddle.sample_head_surface()
	var configs: Array = JSON.parse_string(FileAccess.get_file_as_string("/workspace/shared/pickleball-hands/neutral-serve-endpoint-candidates.json"))
	for index in range(mini(6, configs.size())):
		for protraction in [0.0, 0.025, 0.05]:
			for style in [0, 2, 4]:
				for charge in [0.0, 0.5, 1.0]: sample(p, configs[index], style, charge, protraction)
	var file: = FileAccess.open(output, FileAccess.WRITE);file.store_string(JSON.stringify(rows, "\t"));file.close()
	print("NEUTRAL SERVE ENDPOINT RIG ", rows.size(), " -> ", output)
	game.queue_free(); await process_frame;quit()
