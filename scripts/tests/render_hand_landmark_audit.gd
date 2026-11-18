extends SceneTree



const Motion = preload("res://scripts/drive_serve_motion.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const PoseApplier = preload("res://scripts/posture_skeleton_applier.gd")
const Clearance = preload("res://scripts/body_clearance.gd")
const PaddleClearance = preload("res://scripts/paddle_clearance.gd")
const Styles = preload("res://scripts/serve_style.gd")
const PaddleDimensions = preload("res://scripts/paddle_dimensions.gd")
const OUT: = "/workspace/shared/pickleball-hands/opposite-edge-audit"
var game
var overlay: CanvasLayer
var lines: MarkerLines
var records: Array = []
var _saved_processing: Array = []
var metrics_only: bool = false
var export_swivels: bool = false

class MarkerLines extends Node2D:
	var segments: Array = []
	func _draw() -> void :
		for item in segments:
			draw_line(item.point, item.label, item.color, float(item.get("width", 1.5)), true)
			draw_circle(item.point, 5.0, Color.BLACK)
			draw_circle(item.point, 3.5, item.color)

func _initialize() -> void :
	call_deferred("run")

func _v(p: Vector3) -> Array:
	return [p.x, p.y, p.z]

func _tx(value: Transform3D) -> Array:
	return [_v(value.basis.x), _v(value.basis.y), _v(value.basis.z), _v(value.origin)]

func _text(text: String, position: Vector2, color: Color, font_size: int = 20) -> void :
	var label: = Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	overlay.add_child(label)

func _annotations(camera: Camera3D, points: Dictionary, caption: String, chirality: float) -> void :
	for child in overlay.get_children():
		child.queue_free()
	lines = MarkerLines.new()
	overlay.add_child(lines)
	_text(caption + " | ACTUAL RIGHT ARM", Vector2(22, 18), Color.WHITE, 25)
	_text("Landmark-normal chirality: %+0.5f (right = positive)" % chirality, Vector2(22, 52), Color("bfead9"), 18)
	var colors: Array[Color] = [Color("ffffff"), Color("55e5ff"), Color("ff80e8"), Color("ffb35d"), Color("7cff7b"), Color("d8dff0"), Color("ffe56b"), Color("c8b3ff"), Color("ff5252"), Color("48f5ae"), Color("ffda90"), Color("9fd7ff")]
	var index: = 0
	for name in points:
		var point: Vector2 = camera.unproject_position(points[name])
		var right: = index % 2 == 1
		var label_at: = Vector2(710 if right else 22, 114 + int(index / 2) * 68)
		_text(str(name), label_at, colors[index], 20)
		lines.segments.append({"point": point, "label": label_at + Vector2(-6 if right else 170, 13), "color": colors[index]})
		index += 1
	var wrist_screen: = camera.unproject_position(points["Wrist socket"])
	lines.segments.append({"point": wrist_screen, "label": camera.unproject_position(points["Neutral thumb axis"]), "color": Color("ff5252"), "width": 3.0})
	lines.segments.append({"point": wrist_screen, "label": camera.unproject_position(points["Actual thumb axis"]), "color": Color("48f5ae"), "width": 3.0})
	lines.queue_redraw()
	_text("Cameras use landmark anatomical Z; throat +Y / butt -Y are the original paddle", Vector2(22, 758), Color.WHITE, 17)

func _reference_overlay(caption: String) -> void :
	for child in overlay.get_children(): child.queue_free()
	_text(caption, Vector2(22, 18), Color.WHITE, 24)
	_text("Coaching photo", Vector2(18, 112), Color.WHITE, 18)
	var photo: = Image.new()
	if photo.load("/workspace/shared/pickleball-hands/reference-right-grip.jpg") == OK:
		var rectangle: = TextureRect.new()
		rectangle.texture = ImageTexture.create_from_image(photo)
		rectangle.position = Vector2(18, 145)
		rectangle.size = Vector2(238, 334)
		rectangle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rectangle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		overlay.add_child(rectangle)
	_text("Actual game rig", Vector2(360, 72), Color.WHITE, 20)
	_text("Game camera uses landmark anatomical dorsal Z; shaft points up", Vector2(22, 730), Color.WHITE, 18)
	_text("Production paddle, mesh handedness, and shoulder remain unchanged", Vector2(22, 758), Color.WHITE, 18)

func _capture(name: String, player, expected_mount: Transform3D, context: Dictionary) -> void :
	await _synchronize_render(player)
	var arm = player.right_arm_node
	if expected_mount != Transform3D.IDENTITY:
		assert (arm.hand_mesh.global_transform.is_equal_approx(expected_mount), "Trial mount changed while awaiting renderer")
	var model = arm.articulated_hand
	var mount: Transform3D = arm.hand_mesh.global_transform
	var joints: Dictionary = model.joint_positions()
	var handle: MeshInstance3D = player.paddle_node.get_node("Handle")
	var handle_bounds: AABB = handle.mesh.get_aabb()
	var handle_throat: = handle.to_global(Vector3(0, handle_bounds.end.y, 0))
	var handle_butt: = handle.to_global(Vector3(0, handle_bounds.position.y, 0))
	var points: = {"Wrist socket": mount * joints.wrist, 
		"Index MCP": mount * joints.index_mcp, "Pinky MCP": mount * joints.little_mcp, 
		"Thumb tip": mount * joints.thumb_tip, 
		"Paddle throat +Y": handle_throat, 
		"Paddle butt -Y": handle_butt, 
		"Middle MCP": mount * joints.middle_mcp, "Thumb CMC": mount * joints.thumb_cmc}
	var wrist: Vector3 = points["Wrist socket"]
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var distal: Vector3 = (points["Middle MCP"] - wrist).normalized()
	var radial: Vector3 = (points["Index MCP"] - points["Pinky MCP"]).normalized()
	var dorsal: Vector3 = mount.basis * model.anatomical_basis.z
	var contact_dorsal: Vector3 = mount.basis * model.palm_contact_basis.z
	var contact_normal: Vector3 = mount.basis * model.palm_normal
	var shaft: Vector3 = player.paddle_node.global_basis.y.normalized()
	var chirality: = distal.cross(radial).dot(dorsal)
	var camera: Camera3D = game.main_camera
	var target: Vector3 = mount.origin.lerp(wrist, 0.3)
	var elbow: Vector3 = arm.forearm_pivot.global_position
	var forearm_distal: = (wrist - elbow).normalized()
	var upper: Vector3 = (elbow - arm.upper_pivot.global_position).normalized()
	var neutral_thumb: = ( - upper + forearm_distal * upper.dot(forearm_distal)).normalized()
	var actual_thumb: Vector3 = mount.basis * model.anatomical_basis.y * model.radial_sign
	var projected_thumb: = (actual_thumb - forearm_distal * actual_thumb.dot(forearm_distal)).normalized()
	var axial: = rad_to_deg(atan2(forearm_distal.dot(neutral_thumb.cross(projected_thumb)), neutral_thumb.dot(projected_thumb)))
	var anatomical_channels: Dictionary = Anatomy.decompose(Anatomy.forearm_reference(shoulder, elbow, wrist, Vector3.UP, false), mount.basis * model.anatomical_basis, model.radial_sign)
	var geometry: Dictionary = Clearance.volumes(player, context.definition, player.body_pivot.global_transform)
	var paddle: Transform3D = player.paddle_node.global_transform
	var baseline_paddle: Transform3D = context.paddle
	var basis_column_deltas: = Vector3(paddle.basis.x.distance_to(baseline_paddle.basis.x), 
		paddle.basis.y.distance_to(baseline_paddle.basis.y), paddle.basis.z.distance_to(baseline_paddle.basis.z))
	var body_metrics: = {"upper_surface": Clearance.mesh_surface_margins(arm.upper_mesh, geometry, shoulder, elbow, 0.08), 
		"forearm_surface": Clearance.mesh_surface_margins(arm.fore_mesh, geometry), 
		"upper_conservative_capsule": Clearance.sample_segment(shoulder, elbow, 0.058, geometry, 0.128), 
		"forearm_conservative_capsule": Clearance.sample_segment(elbow, wrist, 0.037, geometry), 
		"paddle_surface": Clearance.sample_paddle(paddle, PaddleClearance.sample_head_surface(), geometry), 
		"conservative_fallback_cells": geometry.fallback_cells, 
		"note": "Read-only skin-cell diagnostics; negative margins require visual review, not a gameplay physics result"}
	var endpoint_metrics: = {"paddle_translation_delta_m": paddle.origin.distance_to(baseline_paddle.origin), 



		"paddle_basis_delta_rad": 2.0 * asin(clampf(basis_column_deltas.length() / (2.0 * sqrt(2.0)), 0.0, 1.0)), 
		"paddle_basis_column_max_delta": maxf(basis_column_deltas.x, maxf(basis_column_deltas.y, basis_column_deltas.z)), 
		"paddle_face_center_delta_m": (paddle * PaddleDimensions.HEAD_OFFSET).distance_to(baseline_paddle * PaddleDimensions.HEAD_OFFSET), 
		"shoulder_delta_m": shoulder.distance_to(context.shoulder), 
		"elbow_from_production_baseline_m": elbow.distance_to(context.elbow), 
		"virtual_anchor_delta_m": arm.hand_pivot.global_position.distance_to(context.anchor), 
		"socket_solver_error_m": wrist.distance_to(arm.anatomical_wrist_world), 
		"upper_link_error_m": absf(shoulder.distance_to(elbow) - arm.upper_arm_length), 
		"forearm_link_error_m": absf(elbow.distance_to(wrist) - arm.forearm_length), 
		"visual_stretch": arm.visual_stretch, 
		"support_mount_unchanged": player.left_arm_node.hand_mesh.global_transform.is_equal_approx(context.support_mount)}
	var contact_metrics: Dictionary = context.contact.duplicate(true)
	if contact_metrics.has("world_center"):
		var ball_world: Vector3 = contact_metrics.world_center
		contact_metrics["paddle_ball_gap_m"] = PaddleClearance.distance_to_paddle_shape(paddle.affine_inverse() * ball_world) - 0.0375
		contact_metrics["world_center"] = _v(ball_world)
		contact_metrics["local_contact"] = _v(contact_metrics.local_contact)
	points["Neutral thumb axis"] = wrist + neutral_thumb * 0.12
	points["Actual thumb axis"] = wrist + actual_thumb * 0.12
	points["Actual mesh heel"] = _geometry_end(arm.hand_mesh, mount.basis * model.anatomical_basis.x, false, true)
	points["Forearm mesh end"] = _geometry_end(arm.fore_mesh, forearm_distal, true, false)
	var record: = {"pose": name, "hand_basis_determinant": mount.basis.determinant(), 
		"trial_mount_deg": context.trial_mount_deg, "definition_id": context.definition.posture_id, 
		"conditioning_source": "Authored pole + production shoulder rotation + conditioned_pole + visual lag", 
		"baseline_paddle": _tx(baseline_paddle), "actual_paddle": _tx(paddle), 
		"shoulder": _v(shoulder), "elbow": _v(elbow), "wrist": _v(wrist), 
		"torso_transform": _tx(player.body_pivot.get_node("TorsoMesh").global_transform), 
		"stance_forward": _v(player._get_forward_axis()), "stance_forehand": _v(player._get_forehand_axis()), 
		"anatomical_channels": anatomical_channels, "body_metrics": body_metrics, 
		"endpoint_metrics": endpoint_metrics, "contact_metrics": contact_metrics, 
		"anatomical_chirality": chirality, "actual_handle_length_m": handle_throat.distance_to(handle_butt), 
		"paddle_basis": [_v(player.paddle_node.global_basis.x), _v(player.paddle_node.global_basis.y), _v(player.paddle_node.global_basis.z)], "dorsal_world": _v(dorsal), 
		"anatomical_dorsal_world": _v(dorsal), "contact_reference_dorsal_world": _v(contact_dorsal), 
		"palm_contact_normal_world": _v(contact_normal), 
		"camera_normal_definition": "landmark anatomical Z; contact-reference normal recorded separately", 
		"palm_world": _v( - dorsal), "shaft_headward": _v(shaft), 
		"forearm_distal": _v(forearm_distal), "hand_distal": _v(distal), 
		"neutral_thumbward": _v(neutral_thumb), "actual_thumbward": _v(actual_thumb), 
		"projected_thumb_twist_deg": axial, "forearm_axial_deg": anatomical_channels.forearm_axial_deg, 
		"forearm_mesh_end_to_socket_m": points["Forearm mesh end"].distance_to(wrist), 
		"mesh_heel_to_socket_m": points["Actual mesh heel"].distance_to(wrist), "landmarks": {}}
	for key in points: record.landmarks[key] = _v(points[key])
	if export_swivels: record["swivel_audit"] = _export_swivel_geometry(player, mount, context, geometry)
	records.append(record)
	_assert_trial_anchors(player, mount, context)
	if metrics_only: return
	for view in ["palmar", "dorsal", "forearm_context", "body_context", "reference_wide"]:
		var focus: Vector3 = target
		var offset: Vector3 = - dorsal * 0.48 + shaft * 0.06
		var up: Vector3 = shaft
		if view == "dorsal": offset = dorsal * 0.48 + shaft * 0.06
		if view == "forearm_context":

			focus = context.shoulder.lerp(context.anchor, 0.5)
			offset = context.forearm_camera_offset
			up = Vector3.UP if absf(offset.normalized().dot(Vector3.UP)) < 0.92 else Vector3.FORWARD
		if view == "body_context":
			focus = context.shoulder.lerp(context.anchor, 0.4)
			offset = (player._get_forehand_axis() * 0.7 - player._get_forward_axis() * 0.65 + Vector3.UP * 0.2).normalized() * 1.2
			up = Vector3.UP
		if view == "reference_wide":
			focus = mount.origin + shaft * 0.115
			offset = dorsal * 0.7
			up = shaft
		camera.global_position = focus + offset
		camera.look_at(focus, up)
		camera.force_update_transform()
		if view == "reference_wide":
			_reference_overlay(name + " / DORSAL REFERENCE COMPARISON")
		else:
			_annotations(camera, points, name + " / " + view + " / axial %+.1f deg" % float(anatomical_channels.forearm_axial_deg), chirality)
		await process_frame
		await RenderingServer.frame_post_draw
		_assert_trial_anchors(player, mount, context)
		var path: = OUT.path_join(name + "_" + view + ".png")
		root.get_texture().get_image().save_png(path)

func _assert_trial_anchors(player, mount: Transform3D, context: Dictionary) -> void :
	var arm = player.right_arm_node
	assert (arm.hand_mesh.global_transform.is_equal_approx(mount), "Frozen rig remounted during capture")
	assert (player.paddle_node.global_transform.is_equal_approx(context.paddle), "Frozen trial changed paddle endpoint")
	assert (arm.upper_pivot.global_position.distance_to(context.shoulder) < 1e-05, "Frozen trial moved shoulder")
	assert (arm.hand_pivot.global_position.distance_to(context.anchor) < 1e-05, "Frozen trial moved virtual anchor")
	assert (player.left_arm_node.hand_mesh.global_transform.is_equal_approx(context.support_mount), "Trial changed support hand")




func _export_swivel_geometry(player, mount: Transform3D, context: Dictionary, geometry: Dictionary) -> Dictionary:
	var arm = player.right_arm_node
	if arm.upper_mesh.has_meta(&"arm_elbow_bridge"):
		return {"eligible": false, "geometry_certified": false, "format": "legacy_rigid_upper_repose", 
			"reason": "This historical format rotates one upper surface across elbow samples. The displayed elbow bridge is skinned to both segments and must be re-posed for each sample; this format cannot certify it.", 
			"required_replacement": "Export bind vertices, weights and each actual palette, or validate each pose with the shared posed-surface API in the engine."}
	var model = arm.articulated_hand
	var shoulder: Vector3 = context.shoulder
	var wrist: Vector3 = mount * model.wrist_socket
	var span: Vector3 = wrist - shoulder
	var distance: float = span.length()
	var l1: float = arm.upper_arm_length
	var l2: float = arm.forearm_length
	if distance >= l1 + l2 or distance <= absf(l1 - l2) + 1e-06:
		return {"eligible": false, "reason": "No nondegenerate exact two-link elbow circle"}
	var axis: Vector3 = span / distance
	var along: float = (l1 * l1 - l2 * l2 + distance * distance) / (2.0 * distance)
	var center: Vector3 = shoulder + axis * along
	var radius: float = sqrt(maxf(0.0, l1 * l1 - along * along))
	var u: Vector3 = axis.cross(Vector3.UP).normalized()
	if u.length_squared() < 0.5: u = axis.cross(Vector3.RIGHT).normalized()
	var v: Vector3 = axis.cross(u)
	var cells: Array = []
	for cell in geometry.cells:
		var planes: Array = []
		for plane in cell.planes: planes.append([plane.normal.x, plane.normal.y, plane.normal.z, plane.d])
		cells.append({"region": cell.region, "planes": planes, "conservative_fallback": cell.conservative_fallback})
	var saved: Array = []
	for node in arm.find_children("*", "Node3D", true, false): saved.append([node, node.transform])
	var old_wrist: Vector3 = arm.anatomical_wrist_world
	var old_stretch: float = arm.visual_stretch
	var samples: Array = []
	var best_ratio: float = INF
	var best_channels: Dictionary = {}
	const STEPS: = 1440
	for step in range(STEPS):
		var theta: float = TAU * step / STEPS
		var elbow: Vector3 = center + radius * (u * cos(theta) + v * sin(theta))
		var frame: Basis = Anatomy.forearm_reference(shoulder, elbow, wrist, Vector3.UP, false)
		var channels: Dictionary = Anatomy.decompose(frame, mount.basis * model.anatomical_basis, model.radial_sign)
		var ratio: float = maxf(float(channels.coupled_budget_ratio), absf(float(channels.forearm_axial_deg)) / Anatomy.AXIAL_BUDGET_DEG)
		if ratio < best_ratio: best_ratio = ratio;best_channels = channels
		if not channels.within_animation_budget: continue
		arm.solve_ik(context.anchor, elbow, context.paddle, wrist)
		model.set_mesh_world_transform(mount)
		arm.upper_mesh.force_update_transform()
		arm.fore_mesh.force_update_transform()
		assert (arm.forearm_pivot.global_position.distance_to(elbow) < 2e-05, "Exported swivel must match the production IK elbow")
		samples.append({"theta_deg": rad_to_deg(theta), "elbow": _v(arm.forearm_pivot.global_position), 
			"anatomical_channels": channels, "upper_transform": _tx(arm.upper_mesh.global_transform), 
			"forearm_transform": _tx(arm.fore_mesh.global_transform)})
	for item in saved: item[0].transform = item[1]
	arm.anatomical_wrist_world = old_wrist
	arm.visual_stretch = old_stretch
	return {"eligible": true, "step_degrees": 360.0 / STEPS, "tested_samples": STEPS, 
		"best_combined_ratio": best_ratio, "best_channels": best_channels, 
		"body_cells": cells, "upper_local_surface": _local_surface_samples(arm.upper_mesh), 
		"forearm_local_surface": _local_surface_samples(arm.fore_mesh), 
		"upper_shoulder_exclusion_m": 0.08, "wrist_feasible_samples": samples, 
		"note": "Exact live mesh transforms; same conservative skin-cell surface gate, no shoulder ROM assumption"}

func _local_surface_samples(instance: MeshInstance3D) -> Array:
	var output: Array = []
	for point in Clearance.mesh_surface_points(instance): output.append(_v(point))
	return output



func _geometry_end(instance: MeshInstance3D, axis: Vector3, maximum: bool, palm_only: bool) -> Vector3:
	var arrays: Array = instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if palm_only else Clearance.mesh_surface_triangles(instance)
	var bones: = PackedInt32Array()
	var weights: = PackedFloat32Array()
	var bridge_bone: int = -1
	if palm_only:
		bones = arrays[Mesh.ARRAY_BONES]
		weights = arrays[Mesh.ARRAY_WEIGHTS]
		var model = instance.get_meta("articulated_hand")
		vertices = model.sampled_vertices()
		bridge_bone = int(model.debug_metadata().wrist_bridge_bone)
	var candidates: Array[Vector3] = []
	var extremum: = - INF if maximum else INF
	for index in range(vertices.size()):
		if palm_only:
			var palm_vertex: = true
			for slot in range(4):
				if weights[index * 4 + slot] > 0.0 and bones[index * 4 + slot] not in [0, bridge_bone]: palm_vertex = false
			if not palm_vertex: continue
		var world: Vector3 = instance.global_transform * vertices[index]
		candidates.append(world)
		var distance: = world.dot(axis)
		extremum = maxf(extremum, distance) if maximum else minf(extremum, distance)
	var centre: = Vector3.ZERO
	var count: = 0
	for point in candidates:
		if absf(point.dot(axis) - extremum) < 1e-05:
			centre += point
			count += 1
	return centre / maxi(count, 1)



func _synchronize_render(player) -> void :
	for tween in get_processed_tweens(): tween.kill()
	game.reset_physics_interpolation()
	player.paddle_node.force_update_transform()
	for arm in [player.right_arm_node, player.left_arm_node]:
		arm.upper_mesh.force_update_transform()
		arm.fore_mesh.force_update_transform()
		arm.hand_mesh.force_update_transform()
		arm.articulated_hand.skeleton.force_update_transform()
	await physics_frame
	await process_frame
	await process_frame
	if not metrics_only: await RenderingServer.frame_post_draw



func _candidate_mounts(label: String, player, definition: PostureDefinition, contact: Dictionary = {}) -> void :
	assert (definition.paddle_hand == 0, "Opposite-edge fixture compares the actual right main hand")
	var arm = player.right_arm_node
	var model = arm.articulated_hand
	var paddle: Transform3D = player.paddle_node.global_transform
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var anchor: Vector3 = arm.hand_pivot.global_position
	var original_wrist: Vector3 = arm.anatomical_wrist_world
	var original_stretch: float = arm.visual_stretch
	var original_lag: float = arm.visual_wrist_lag_deg
	var baseline_mount: Transform3D = arm.hand_mesh.global_transform
	var context: = {"definition": definition, "paddle": paddle, "shoulder": shoulder, "anchor": anchor, 
		"elbow": arm.forearm_pivot.global_position, 
		"support_mount": player.left_arm_node.hand_mesh.global_transform, "contact": contact, 
		"forearm_camera_offset": ( - (baseline_mount.basis * model.anatomical_basis.z) + baseline_mount.basis.x * 0.55).normalized() * 0.95}
	var saved: Array = []
	for child in arm.find_children("*", "Node3D", true, false):
		var node: Node3D = child as Node3D
		saved.append([node, node.transform])
	var forehand: Vector3 = player._get_forehand_axis()
	var forward: Vector3 = player._get_forward_axis()
	var authored: Vector3 = player.global_position + forehand * 0.5 + Vector3.DOWN - forward * 0.5
	if definition.right_elbow_pole.length_squared() > 1e-10:
		authored = player.global_position + PoseApplier.stance_offset(definition.right_elbow_pole, forehand, forward)
	authored = player.arm_ik._rotate_shoulder_pole(arm, authored, definition.right_shoulder_rotation_deg)
	for degrees in [135.0, 315.0]:
		var mount: = Transform3D(paddle.basis * Basis(Vector3.UP, deg_to_rad(degrees)), anchor)
		var wrist: Vector3 = mount * model.wrist_socket
		var distal: Vector3 = mount.basis * model.anatomical_basis.x
		var pole: Vector3 = Anatomy.conditioned_pole(shoulder, wrist, authored, distal, arm.upper_arm_length, arm.forearm_length)
		var lag: float = clampf(float(definition.get_meta("visual_wrist_lag_deg", 0.0)), 0.0, 6.0)
		arm.visual_wrist_lag_deg = lag
		if lag > 1e-05:
			var axis: Vector3 = (wrist - shoulder).normalized()
			pole = shoulder + (pole - shoulder).rotated(axis, deg_to_rad(lag * (-1.0 if definition.family == 1 else 1.0)))
		arm.solve_ik(anchor, pole, paddle, wrist)
		model.set_mesh_world_transform(mount)
		if is_equal_approx(degrees, 135.0):
			assert (arm.forearm_pivot.global_position.distance_to(context.elbow) < 2e-05, "135-degree control must reproduce the actual production elbow")
		context["trial_mount_deg"] = degrees
		assert (player.paddle_node.global_transform.is_equal_approx(paddle), "Mount trial must not rotate or move the paddle")
		assert (arm.upper_pivot.global_position.distance_to(shoulder) < 1e-05, "Mount trial must not move the shoulder")
		await _capture(label + "_TEST_mount_%03d" % int(degrees), player, mount, context)
		assert (arm.hand_mesh.global_transform.is_equal_approx(mount), "Trial mount changed after rendering")
		assert (player.paddle_node.global_transform.is_equal_approx(paddle), "Paddle changed after rendering a trial")
	for item in saved:
		item[0].transform = item[1]
	arm.anatomical_wrist_world = original_wrist
	arm.visual_stretch = original_stretch
	arm.visual_wrist_lag_deg = original_lag
	await _synchronize_render(player)

func _apply_contact_pose(player, pose: PostureDefinition) -> void :
	player.current_velocity = Vector3.ZERO
	player.hitting.serving_visual_active = false
	player.hitting.charge_visual_active = false
	player.hitting.is_in_follow_through = false
	player.posture._committed_incoming_posture = -1
	player.posture.editor_preview_mode = false
	player.leg_ik.feet_initialized = false
	player.posture.transition_pose_blend = pose
	player.posture.force_posture_update(pose)

func _resume_game() -> void :
	for item in _saved_processing:
		var node: Node = item[0]
		if not is_instance_valid(node): continue
		node.process_mode = item[3]
		node.set_process(item[1])
		node.set_physics_process(item[2])
	_saved_processing.clear()
	game.process_mode = Node.PROCESS_MODE_INHERIT

func _freeze() -> void :


	assert (_saved_processing.is_empty(), "Resume saved process flags before freezing again")
	var nodes: Array = [game]
	nodes.append_array(game.find_children("*", "", true, false))
	for node in nodes:
		_saved_processing.append([node, node.is_processing(), node.is_physics_processing(), node.process_mode])
		node.set_process(false)
		node.set_physics_process(false)
	game.process_mode = Node.PROCESS_MODE_DISABLED
	for tween in get_processed_tweens(): tween.kill()
	game.hud.set_gameplay_elements_visible(false)
	game.mobile_controls.hide()
	for child in game.get_children():
		if child is CanvasLayer: child.hide()

func run() -> void :
	metrics_only = DisplayServer.get_name() == "headless" or "--metrics-only" in OS.get_cmdline_user_args()
	export_swivels = "--export-swivels" in OS.get_cmdline_user_args()
	create_timer(240).timeout.connect( func(): quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	if not metrics_only: DisplayServer.window_set_size(Vector2i(960, 800))
	root.size = Vector2i(960, 800)
	root.content_scale_size = Vector2i(960, 800)
	root.content_scale_factor = 1.0
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	root.get_node("Settings")._config.set_value("video", "shadow_quality", 0)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	for frame in range(5): await process_frame
	await physics_frame
	game.input_handler.set_process(false)
	game.main_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	game.main_camera.fov = 48.0
	game.main_camera.near = 0.012
	overlay = CanvasLayer.new()
	overlay.layer = 100
	root.add_child(overlay)
	_resume_game()
	game.serving_team = 0
	game._reset_ball()
	assert (game.game_serve.select_serve_style(Styles.Style.FLAT), "Loaded serve fixture selects the real Flat preparation")
	game.game_serve.start_charge()
	game.game_serve.tick_charge(0.6 * PickleballConstants.MAX_SERVE_CHARGE_TIME)
	await physics_frame
	await process_frame
	_freeze()
	var player = game.player_left


	var loaded: PostureDefinition = player.posture._presented_body_pose
	assert (loaded != null, "Actual loaded serve has a presented source pose")
	await _candidate_mounts("loaded_serve_q6", player, loaded)
	game.game_serve.cleanup()
	game.ball.freeze = true
	game.ball.hide()
	var ready: PostureDefinition = PostureLibrary.instance().get_def(20)
	_apply_contact_pose(player, ready)
	await _candidate_mounts("ready", player, ready)
	for posture_id in [0, 2]:
		var contact_pose: PostureDefinition = Motion.sample_drive(PostureLibrary.instance().get_def(posture_id), 0.5, 1.0)
		_apply_contact_pose(player, contact_pose)
		await _candidate_mounts("authored_forehand_contact" if posture_id == 0 else "authored_backhand_contact", player, contact_pose)
	for style in [Styles.Style.FLAT, Styles.Style.DROP_DRIVE]:
		var plan: Dictionary = Styles.release_plan(player.global_position, player.player_num == 1, style)
		var ball_world: Vector3 = plan.contact_position
		var relative: Vector3 = ball_world - player.global_position
		var local_contact: = Vector3(relative.dot(player._get_forehand_axis()), relative.y, relative.dot(player._get_forward_axis()))
		var contact_pose: PostureDefinition = Motion.serve_style_contact(style, local_contact)
		_apply_contact_pose(player, contact_pose)
		game.ball.global_position = ball_world
		game.ball.show()
		var contact: = {"world_center": ball_world, "local_contact": local_contact, "style": style, 
			"delivery": plan.delivery, "contact_time_s": plan.contact_time, "bounce_time_s": plan.bounce_time, 
			"source": "Shared release_plan + serve_style_contact; frozen contact sample, not a live flight result"}
		await _candidate_mounts("serve_style_flat_contact" if style == Styles.Style.FLAT else "serve_style_drop_drive_contact", player, contact_pose, contact)
	var file: = FileAccess.open(OUT.path_join("landmarks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	file.close()
	print("HAND OPPOSITE-EDGE AUDIT: 12 fixed-mount records; ", "metrics only" if metrics_only else "60 annotated views", "; anatomy/body/endpoint JSON -> ", OUT)
	quit()
