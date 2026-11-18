extends SceneTree


const Shape = preload("res://scripts/body_clearance.gd")
const Geometry = preload("res://scripts/paddle_clearance.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Preview = preload("res://scripts/posture_editor_v2/runtime_motion_preview.gd")
var output: = "/workspace/shared/pickleball-hands/body-clearance-sweep.json"
var records: Array = []
var surface: Array[Vector3] = []
func _initialize() -> void : call_deferred("run")
func sample(p, pose: PostureDefinition, label: String) -> void :
	p.posture.editor_preview_mode = false;p.current_velocity = Vector3.ZERO;p.posture.transition_pose_blend = pose
	p.leg_ik.feet_initialized = false;p.posture.force_posture_update(pose)
	var geometry: Dictionary = Shape.volumes(p, pose, p.body_pivot.global_transform)
	var paddle: Transform3D = p.paddle_node.global_transform
	var old_chest: Node3D = p.body_pivot.get_node("TorsoMesh")
	var into_chest: Transform3D = old_chest.global_transform.affine_inverse() * paddle
	var old_margin: = INF
	for point in surface: old_margin = minf(old_margin, Geometry.signed_box_distance(into_chest * point, Vector3(0.18, 0.16, 0.1)))
	var arm_margins: Dictionary = {}
	for side in range(2):
		var arm = p.right_arm_node if side == 0 else p.left_arm_node
		var shoulder: Vector3 = arm.upper_pivot.global_position
		var elbow: Vector3 = arm.forearm_pivot.global_position
		var wrist: Vector3 = arm.hand_pivot.global_position
		if arm.articulated_hand != null: wrist = arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket


		var upper_box: AABB = arm.upper_mesh.mesh.get_aabb()
		var fore_box: AABB = arm.fore_mesh.mesh.get_aabb()
		var upper_radius: float = maxf(upper_box.size.x, upper_box.size.z) * 0.5
		var fore_radius: float = maxf(fore_box.size.x, fore_box.size.z) * 0.5
		arm_margins["%d_upper" % side] = Shape.sample_segment(shoulder, elbow, upper_radius, geometry, upper_radius + 0.07)
		arm_margins["%d_forearm" % side] = Shape.sample_segment(elbow, wrist, fore_radius, geometry)
	var legs: Array = []
	for leg in [p.right_leg_node, p.left_leg_node]: legs.append(Shape.leg_metrics(leg.thigh_pivot.global_position, leg.shin_pivot.global_position, leg.foot_pivot.global_position))
	var head: Vector3 = old_chest.get_node("HeadMesh").global_position
	records.append({"label": label, "side": p.player_num, "old_chest_margin": old_margin, 
		"face_margin": Geometry.distance_to_paddle_shape(paddle.affine_inverse() * head) - 0.12, 
		"paddle_body_margins": Shape.sample_paddle(paddle, surface, geometry), "arm_body_margins": arm_margins, 
		"conservative_fallback_cells": geometry.fallback_cells, "legs": legs, 
		"supported_shoulder_query_error": p.right_arm_node.upper_pivot.global_position.distance_to(Shape.Body.shoulder_world(p, pose, p.body_pivot.global_transform))})
func run() -> void :
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	surface = Geometry.sample_head_surface()
	for p in [game.player_left, game.player_right]:
		p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false
		for id in [0, 2, 10, 11, 3, 4]:
			var base: PostureDefinition = PostureLibrary.instance().get_def(id)
			for progress in [0.0, 0.5, 0.8, 0.85, 0.9, 0.95, 1.0]:
				sample(p, Path.sample(base, progress), "authored_%02d_t%.2f" % [id, progress])
				for charge in [0.25, 1.0]: sample(p, Motion.sample_drive(base, progress, charge), "runtime_%02d_q%.2f_t%.2f" % [id, charge, progress])
		for style in range(7):
			for charge in [0.0, 0.5, 0.8, 1.0]:
				var plan: Dictionary = Preview.serve_plan(style, p.global_position.y)
				for progress in [0.0, 0.4, 0.8, 1.0]: sample(p, Preview.sample_serve_elapsed(style, float(plan.contact_time) * progress, charge, p.global_position.y), "serve_%d_q%.2f_release%.2f" % [style, charge, progress])
	var file: = FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"records": records, "notes": "Actual supported rig; shared skinned body-cell diagnostic margins. Negative conservative capsule/plane margins require rendered confirmation. No gameplay gates changed."}, "\t"));file.close()
	print("BODY CLEARANCE SWEEP ", records.size(), " samples -> ", output)
	game.queue_free(); await process_frame;quit()
