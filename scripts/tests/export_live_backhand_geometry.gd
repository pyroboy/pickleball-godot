extends "res://scripts/debug/hand_simulation_review.gd"


var contact_geometry: Array = []
var _presented_cases: Dictionary = {}

func _record_contact(side: int = 0) -> void :
	super._record_contact(side)
	if current.get("id", "") == "charge_backhand" and side == 0:
		contact_geometry.append(_actual_geometry(game.player_left, "physical_hit_signal"))

func _measure_body(player_override = null) -> Dictionary:
	var measured: Dictionary = super._measure_body(player_override)
	var case_id: String = current.get("id", "")
	var selected_case: bool = case_id == "charge_backhand" or case_id.begins_with("pose_")
	if player_override == null and selected_case and not _presented_cases.has(case_id) and hit_frame >= 0 and frame_number == hit_frame:
		var geometry: Dictionary = _actual_geometry(game.player_left, "presented_hit_frame")
		geometry["review_anatomical_channels"] = measured.arms[0].anatomical_channels
		geometry["review_pose_fields"] = measured.pose_fields
		contact_geometry.append(geometry)
		_presented_cases[case_id] = true
	return measured

func _basis(b: Basis) -> Array:
	return [_v(b.x), _v(b.y), _v(b.z)]

func _transform(t: Transform3D) -> Array:
	return [_v(t.basis.x), _v(t.basis.y), _v(t.basis.z), _v(t.origin)]

func _actual_geometry(player, capture_phase: String) -> Dictionary:
	var pose: PostureDefinition = player.posture.transition_pose_blend
	if pose == null and player.posture.human_contact != null: pose = player.posture.human_contact.visual_pose
	if pose == null: pose = player.get_runtime_posture_def()
	var arm = player.left_arm_node if pose.paddle_hand == 1 else player.right_arm_node
	var model = arm.articulated_hand
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var elbow: Vector3 = arm.forearm_pivot.global_position
	var wrist: Vector3 = arm.hand_mesh.global_transform * model.wrist_socket
	var geometry: Dictionary = BodySurface.volumes(player, pose, player.body_pivot.global_transform)
	var cells: Array = []
	for cell in geometry.cells:
		var planes: Array = []
		for plane in cell.planes: planes.append([plane.normal.x, plane.normal.y, plane.normal.z, plane.d])
		cells.append({"region": cell.region, "planes": planes, "conservative_fallback": cell.conservative_fallback})
	var fields: Dictionary = {}
	for key in ["posture_id", "paddle_hand", "left_hand_mode", "right_elbow_pole", "left_elbow_pole", "right_shoulder_rotation_deg", "left_shoulder_rotation_deg", "right_hand_offset", "left_hand_offset"]:
		var value = pose.get(key)
		fields[key] = _v(value) if value is Vector3 else value
	var frame: Basis = ArmAnatomy.forearm_reference(shoulder, elbow, wrist, Vector3.UP, arm == player.left_arm_node)
	return {"capture_phase": capture_phase, "case": current.id, "frame": frame_number, "hit_frame": hit_frame, 
		"sim_time": sim_time, "flight_id": game.ball.flight_id, "incoming_bounces": observed_bounces.duplicate(), 
		"hits_recorded": current.hits.duplicate(true), "arm_side": "left" if arm == player.left_arm_node else "right", 
		"pose_fields": fields, "player_origin": _v(player.global_position), "stance_forward": _v(player._get_forward_axis()), "stance_forehand": _v(player._get_forehand_axis()), 
		"shoulder": _v(shoulder), "elbow": _v(elbow), "wrist": _v(wrist), "virtual_anchor": _v(arm.hand_pivot.global_position), 
		"upper_length": arm.upper_arm_length, "fore_length": arm.forearm_length, "visual_stretch": arm.visual_stretch, 
		"visual_wrist_lag_deg": arm.visual_wrist_lag_deg, "radial_sign": model.radial_sign, 
		"paddle_transform": _transform(player.paddle_node.global_transform), "hand_transform": _transform(arm.hand_mesh.global_transform), 
		"hand_frame": _basis(arm.hand_mesh.global_basis * model.anatomical_basis), "local_anatomical_basis": _basis(model.anatomical_basis), 
		"anatomical_channels": ArmAnatomy.decompose(frame, arm.hand_mesh.global_basis * model.anatomical_basis, model.radial_sign), 
		"body_cells": cells, "body_transform": _transform(player.body_pivot.global_transform), 
		"upper_transform": _transform(arm.upper_mesh.global_transform), "forearm_transform": _transform(arm.fore_mesh.global_transform), 
		"upper_local_surface": _local_surface(arm.upper_mesh), "forearm_local_surface": _local_surface(arm.fore_mesh), 
		"upper_local_triangles": _local_triangles(arm.upper_mesh), "forearm_local_triangles": _local_triangles(arm.fore_mesh), 
		"surface_contract": "Displayed local triangles at this measured pose. A new elbow requires re-posing the skinned bridge, not rigidly rotating this upper surface.", 
		"upper_shoulder_exclusion_m": 0.08, 
		"actual_upper_margins": BodySurface.mesh_surface_margins(arm.upper_mesh, geometry, shoulder, elbow, 0.08), 
		"actual_forearm_margins": BodySurface.mesh_surface_margins(arm.fore_mesh, geometry), 
		"ball_position": _v(game.ball.global_position), "note": "Observed live feed, user-input charge/release and physical contact; no pose resampling or modified transforms"}

func _local_surface(mesh: MeshInstance3D) -> Array:
	var result: Array = []
	for point in BodySurface.mesh_surface_points(mesh): result.append(_v(point))
	return result

func _local_triangles(mesh: MeshInstance3D) -> Array:
	var result: Array = []
	for point in BodySurface.mesh_surface_triangles(mesh): result.append(_v(point))
	return result

func _source_hashes() -> Dictionary:
	var hashes: Dictionary = super._source_hashes()
	hashes["tests/export_live_backhand_geometry.gd"] = FileAccess.get_sha256("res://scripts/tests/export_live_backhand_geometry.gd")
	return hashes

func _write_report() -> void :
	super._write_report()
	var file: = FileAccess.open(output.path_join("contact-geometry.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"source_hashes": _source_hashes(), "snapshots": contact_geometry}, "\t"));file.close()
	print("LIVE CONTACT GEOMETRY: ", contact_geometry.size(), " snapshots; presented real contacts=", _presented_cases.size(), " -> ", output)
