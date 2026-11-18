extends SceneTree

const Shape = preload("res://scripts/body_clearance.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const PoseApplier = preload("res://scripts/posture_skeleton_applier.gd")
var records: Array = []
func _initialize() -> void : call_deferred("run")
func v(p: Vector3) -> Array: return [p.x, p.y, p.z]
func b(p: Basis) -> Array: return [v(p.x), v(p.y), v(p.z)]
func sample(p, pose: PostureDefinition, label: String) -> void :
	p.posture.editor_preview_mode = false;p.current_velocity = Vector3.ZERO
	p.leg_ik.feet_initialized = false;p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
	var geometry: Dictionary = Shape.volumes(p, pose, p.body_pivot.global_transform)
	var cells: Array = []
	for cell in geometry.cells:
		var planes: Array = []
		for plane in cell.planes: planes.append([plane.normal.x, plane.normal.y, plane.normal.z, plane.d])
		cells.append({"region": cell.region, "planes": planes})
	for side in [0, 1]:
		var arm = p.right_arm_node if side == 0 else p.left_arm_node
		var pole: Vector3 = pose.right_elbow_pole if side == 0 else pose.left_elbow_pole
		var hint: Vector3 = p.global_position + PoseApplier.stance_offset(pole, p._get_forehand_axis(), p._get_forward_axis())
		if pole.length_squared() < 1e-07: hint = p.global_position + p._get_forehand_axis() * (0.5 if side == 0 else - 0.5) + Vector3.DOWN - p._get_forward_axis() * 0.5
		hint = p.arm_ik._rotate_shoulder_pole(arm, hint, pose.right_shoulder_rotation_deg if side == 0 else pose.left_shoulder_rotation_deg)
		var mount: Transform3D = arm.hand_mesh.global_transform
		records.append({"label": label, "side": side, "team": p.player_num, "shoulder": v(arm.upper_pivot.global_position), "elbow": v(arm.forearm_pivot.global_position), "wrist": v(mount * arm.articulated_hand.wrist_socket), "hand_frame": b(mount.basis * arm.articulated_hand.anatomical_basis), "paddle_basis": b(p.paddle_node.global_basis), "anchor": v(arm.hand_pivot.global_position), "model_basis": b(arm.articulated_hand.anatomical_basis), "wrist_socket": v(arm.articulated_hand.wrist_socket), "authored_pole": v(hint), "upper_length": arm.upper_arm_length, "fore_length": arm.forearm_length, "upper_radius": 0.058, "fore_radius": 0.037, "body_cells": cells})
func run() -> void :
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	for p in [game.player_left, game.player_right]:
		p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false
		for id in [20, 0, 2, 5, 7, 10, 11, 13, 14, 3, 4]:
			var base: PostureDefinition = PostureLibrary.instance().get_def(id)
			sample(p, base, "contact_%02d" % id)
			if id != 20:
				sample(p, Motion.held_drive_pose(base, 1.0), "load_%02d" % id)
				sample(p, Motion.sample_drive(base, 1.0, 1.0), "finish_%02d" % id)
		for style in range(7):
			for charge in [0.0, 0.5, 1.0]: sample(p, Motion.serve_style_preparation(style, charge, preload("res://scripts/serve_style.gd").hold_offset(style)), "serve%d_q%.1f" % [style, charge])
	var file: = FileAccess.open("/workspace/shared/pickleball-hands/arm-constraint-frames.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(records));file.close()
	print("ARM CONSTRAINT FRAMES ", records.size())
	game.queue_free(); await process_frame;quit()
