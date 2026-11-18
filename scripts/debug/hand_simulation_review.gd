extends "res://scripts/debug/pose_simulation_review.gd"


func _build_review_ui() -> void :
	super._build_review_ui()
	var names: Array[String] = ["PALMAR", "DORSAL", "ARM / PADDLE CONTEXT"]
	for index in range(view_columns.size()):
		(view_columns[index].get_child(0) as Label).text = names[index]

func _position_cameras() -> void :
	var p = game.player_right if current.get("camera_player", 0) == 1 else game.player_left
	var pose = p.get_runtime_posture_def()
	var left_dominant: bool = pose != null and pose.paddle_hand == 1
	var support: bool = OS.has_environment("HAND_REVIEW_SUPPORT")
	var left: bool = not left_dominant if support else left_dominant
	var arm = p.left_arm_node if left else p.right_arm_node
	var mount: Transform3D = arm.hand_mesh.global_transform
	var model = arm.articulated_hand
	var anatomy: Basis = mount.basis * model.anatomical_basis
	var joints: Dictionary = model.joint_positions()
	var target: Vector3 = (mount * joints.wrist).lerp(mount * joints.middle_mcp, 0.5)
	var offsets: Array[Vector3] = [ - anatomy.z * 0.45, anatomy.z * 0.45]
	for index in range(cameras.size()):
		var camera: Camera3D = cameras[index]
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.near = 0.012
		if index < 2:
			camera.size = 0.29
			camera.global_position = target + offsets[index]
			camera.look_at(target, anatomy.x)
		else:


			var context: Vector3 = arm.upper_pivot.global_position.lerp(p.paddle_node.to_global(Vector3(0, 0.28, 0)), 0.56)
			camera.size = 1.05
			camera.global_position = context + (p._get_forward_axis() * 0.8 + p._get_forehand_axis() * 0.62 + Vector3.UP * 0.2)
			camera.look_at(context, Vector3.UP)

func _source_hashes() -> Dictionary:
	var hashes: Dictionary = super._source_hashes()
	hashes["debug/hand_simulation_review.gd"] = FileAccess.get_sha256("res://scripts/debug/hand_simulation_review.gd")
	for source in ["articulated_hand.gd", "player_hand_presentation.gd", "paddle_grip_frame.gd", "arm_anatomy.gd", "serve_pose_presentation.gd", "player_arm_visual.gd", "player_body_dimensions.gd", "articulated_torso_mesh.gd", "body_clearance.gd", "body_surface_profile.gd", "between_point_controller.gd"]:
		hashes[source] = FileAccess.get_sha256("res://scripts/" + source)
	hashes["data/postures/20_ready.tres"] = FileAccess.get_sha256("res://data/postures/20_ready.tres")
	return hashes

func _write_report() -> void :
	super._write_report()
	var path: String = output.path_join("review.json")
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	report.camera_order = ["palmar", "dorsal", "arm_paddle_context"]
	report.camera_frame = "Actual landmark-derived anatomical basis; context camera follows the body"
	report.support_hand_review = OS.has_environment("HAND_REVIEW_SUPPORT")
	var file: = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
