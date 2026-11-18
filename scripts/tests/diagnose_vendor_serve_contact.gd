extends "res://scripts/tests/diagnose_receiving_face_candidate.gd"



const Motion = preload("res://scripts/drive_serve_motion.gd")
const Styles = preload("res://scripts/serve_style.gd")
const Size = preload("res://scripts/paddle_dimensions.gd")
func transform_data(value: Transform3D) -> Array:
	var result: Array = bd(value.basis);result.append(vd(value.origin));return result
func fields(pose: PostureDefinition) -> Dictionary:
	var result: Dictionary = {}
	for property in pose.get_property_list():
		if not (property.usage & PROPERTY_USAGE_STORAGE): continue
		var value = pose.get(property.name)
		if value is Vector3: result[property.name] = vd(value)
		elif value is float or value is int or value is bool or value is String: result[property.name] = value
	return result
func run():
	var pause = root.get_node_or_null("PauseController")
	if pause:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
		pause.close()
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	game.ball.is_in_play = true;game.ball.freeze = true;game.game_state = game.GameState.PLAYING
	for p in [game.player_left, game.player_right]:
		p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
		p.current_velocity = Vector3.ZERO;p.posture._committed_incoming_posture = -1;p.posture.editor_preview_mode = false
		for style in [0, 4]:
			var plan: Dictionary = Styles.release_plan(p.global_position, p.player_num == 1, style)
			var ball: Vector3 = plan.contact_position
			var relative: Vector3 = ball - p.global_position
			var ball_offset: = Vector3(relative.dot(p._get_forehand_axis()), relative.y, relative.dot(p._get_forward_axis()))
			for correct_face in [false, true]:
				var pose: PostureDefinition = Motion._raw_serve_style_contact(style, ball_offset) if correct_face else Motion.serve_style_contact(style, ball_offset)
				var raw: Transform3D = Path.world_transform(p, pose)
				if correct_face: O.set_canonical_basis(pose, O.canonical_basis(pose) * Basis(Vector3.UP, PI))
				p.leg_ik.feet_initialized = false;p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
				var result: Dictionary = measured(p, pose)
				var tx: Transform3D = p.paddle_node.global_transform
				var head: Vector3 = tx * Size.HEAD_OFFSET
				var ball_side: Vector3 = tx.basis.z * signf((ball - head).dot(tx.basis.z))
				var arm = p.right_arm_node; var model = arm.articulated_hand
				var geometry: Dictionary = C.volumes(p, pose, p.body_pivot.global_transform)
				var cells: Array = []
				for cell in geometry.cells:
					var planes: Array = []
					for plane in cell.planes: planes.append([plane.normal.x, plane.normal.y, plane.normal.z, plane.d])
					cells.append({"region": cell.region, "planes": planes})
				var meshes: Dictionary = {}
				for key in ["upper", "forearm"]:
					var mesh: MeshInstance3D = arm.upper_mesh if key == "upper" else arm.fore_mesh
					var vertices: Array = []
					for point in C.mesh_surface_triangles(mesh): vertices.append(vd(point))
					meshes[key] = {"transform": transform_data(mesh.global_transform), "triangles": vertices}
				var pole: Vector3 = p.global_position + p._get_forehand_axis() * pose.right_elbow_pole.x + Vector3.UP * pose.right_elbow_pole.y + p._get_forward_axis() * pose.right_elbow_pole.z
				pole = p.arm_ik._rotate_shoulder_pole(arm, pole, pose.right_shoulder_rotation_deg)
				result.merge({"case": "serve_%d_court%d_%s" % [style, p.player_num, "palmar_raw" if correct_face else "inherited_contact"], "style": style, "team": p.player_num, "correct_face_candidate": correct_face, 
					"player_origin": vd(p.global_position), "pose_fields": fields(pose), "body_transform": transform_data(p.body_pivot.global_transform), 
					"paddle_transform": transform_data(tx), "raw_paddle_transform": transform_data(raw), "head": vd(head), "ball_position": vd(ball), 
					"head_delta_m": head.distance_to(raw * Size.HEAD_OFFSET), "physical_normal_dot": absf(tx.basis.z.dot(raw.basis.z)), 
					"dorsal_dot_ball_side": (arm.hand_mesh.global_basis * model.anatomical_basis.z).dot(ball_side), 
					"ball_surface_gap_m": P.distance_to_head_shape(tx.affine_inverse() * ball) - 0.0375, 
					"hand_transform": transform_data(arm.hand_mesh.global_transform), "model_basis": bd(model.anatomical_basis), "radial_sign": model.radial_sign, 
					"wrist_socket": vd(model.wrist_socket), "authored_pole": vd(pole), "upper_length": arm.upper_arm_length, "fore_length": arm.forearm_length, 
					"body_cells": cells, "arm_meshes": meshes, "paddle_dimensions": [Size.LENGTH, Size.WIDTH, Size.THICKNESS, Size.HANDLE_LENGTH]})
				check(result.head_delta_m < 1e-05, result.case + " sphere-seated head unchanged")
				check(result.physical_normal_dot > 0.99999, result.case + " physical face plane unchanged")
				check(absf(result.ball_surface_gap_m) < 1e-05, result.case + " finite sphere remains seated")
				if correct_face: check(result.dorsal_dot_ball_side < - 0.5, result.case + " palmar striking side")
				records.append(result)
	var shape: Dictionary = {"length": Size.LENGTH, "width": Size.WIDTH, "thickness": Size.THICKNESS, "handle_length": Size.HANDLE_LENGTH, "handle_radius": Size.HANDLE_RADIUS, "head_center_y": Size.HEAD_CENTER_Y, "head_radius": Size.HEAD_RADIUS, "head_spine_half": Size.HEAD_SPINE_HALF, "head_half_thickness": Size.HEAD_HALF_THICKNESS, "main_grip_y": Size.MAIN_GRIP_Y, "support_grip_y": Size.SUPPORT_GRIP_Y, "head_outline": [], "head_hull_points": []}
	for point in Size.head_outline(): shape.head_outline.append([point.x, point.y])
	for point in Size.head_hull_points(): shape.head_hull_points.append(vd(point))
	var hashes: Dictionary = {}
	for source in ["res://scripts/paddle_dimensions.gd", "res://scripts/paddle_model.gd", "res://scripts/paddle_clearance.gd", "res://scenes/paddle.tscn"]: hashes[source] = FileAccess.get_sha256(source)
	var output: = "/workspace/shared/pickleball-hands/vendor-serve-contact-first.json"
	var file: = FileAccess.open(output, FileAccess.WRITE);file.store_string(JSON.stringify({"records": records, "invariant_errors": errors, "paddle_geometry": shape, "geometry_source_sha256": hashes}, "\t"));file.close()
	for error in errors: push_error(error)
	print("VENDOR SERVE CONTACT ", records.size(), " samples; ", errors.size(), " contact invariant failures; anatomy recorded separately")
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game)
	quit(0 if errors.is_empty() else 1)
