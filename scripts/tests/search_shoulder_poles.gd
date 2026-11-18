extends SceneTree


const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Trial = preload("res://scripts/tests/diagnose_guard_serve_trials.gd")
const A = preload("res://scripts/arm_anatomy.gd")
const C = preload("res://scripts/body_clearance.gd")
const G = preload("res://scripts/paddle_clearance.gd")
var output: = "/workspace/shared/pickleball-hands/shoulder-pole-search.json"
var rows: Array = []
func _initialize(): call_deferred("run")
func run():
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	var p = game.player_left;p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false;p.current_velocity = Vector3.ZERO;p.posture._committed_incoming_posture = -1
	var source: PostureDefinition = PostureLibrary.instance().get_def(20)
	var surface: Array[Vector3] = G.sample_head_surface()

	for turn in range(75, 106, 15):
		for pitch in [0.0]:
			for protraction in [0.0, 0.025, 0.05]:
				for straighten in [0.0]:
					for spread in [0.0, 0.1, 0.2]:
						for forward in [0.0, 0.15, 0.3]:
							var pose: PostureDefinition = _turn(source, Basis(Vector3.UP, deg_to_rad(turn)) * Basis(Vector3.RIGHT, deg_to_rad(pitch)))
							pose.torso_pitch_deg -= straighten
							pose.right_elbow_pole += Vector3(spread, 0, forward)
							pose.left_elbow_pole += Vector3( - spread, 0, forward)
							p.posture.editor_preview_mode = false;p.leg_ik.feet_initialized = false;p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
							var front: Vector3 = - p.body_pivot.get_node("TorsoMesh").global_basis.z
							for arm in [p.right_arm_node, p.left_arm_node]: arm.global_position += front * protraction
							p.arm_ik.update_arm_ik(0.0, pose)
							var geometry: Dictionary = C.volumes(p, pose, p.body_pivot.global_transform)
							var tx: Transform3D = p.paddle_node.global_transform
							var body: Dictionary = C.sample_paddle(tx, surface, geometry)
							var face: float = G.distance_to_paddle_shape(tx.affine_inverse() * p.body_pivot.get_node("TorsoMesh/HeadMesh").global_position) - 0.12
							var score: = 0.0; var arm_margin: = INF; var arms: Array = []
							for side in [0, 1]:
								var arm = p.right_arm_node if side == 0 else p.left_arm_node; var model = arm.articulated_hand
								var s: Vector3 = arm.upper_pivot.global_position; var e: Vector3 = arm.forearm_pivot.global_position; var w: Vector3 = model.hand_mesh.global_transform * model.wrist_socket
								var channels: Dictionary = A.decompose(A.forearm_reference(s, e, w, Vector3.UP, side == 1), model.hand_mesh.global_basis * model.anatomical_basis, model.radial_sign)
								var upper: Dictionary = C.sample_segment(s, e, 0.058, geometry, 0.128); var fore: Dictionary = C.sample_segment(e, w, 0.037, geometry)
								var upper_detail: Dictionary = {}
								var upper_surface: Dictionary = C.mesh_surface_margins(arm.upper_mesh, geometry, s, e, 0.08, upper_detail)
								var fore_surface: Dictionary = C.mesh_surface_margins(arm.fore_mesh, geometry)
								for region in C.REGIONS: arm_margin = minf(arm_margin, minf(upper_surface[region], fore_surface[region]))
								score = maxf(score, maxf(channels.coupled_budget_ratio, pow(channels.forearm_axial_deg / 90.0, 2)))
								arms.append({"channels": channels, "upper": upper, "forearm": fore, "upper_surface": upper_surface, "upper_minimum_samples": upper_detail, "forearm_surface": fore_surface, "S": [s.x, s.y, s.z], "E": [e.x, e.y, e.z], "W": [w.x, w.y, w.z]})
							rows.append({"turn": turn, "pitch": pitch, "protraction": protraction, "straighten": straighten, "pole_spread": spread, "pole_forward": forward, "score": score, "arm_margin": arm_margin, "face": face, "paddle_body": body, "arms": arms})
	var file: = FileAccess.open(output, FileAccess.WRITE);file.store_string(JSON.stringify(rows, "\t"));file.close()
	print("SHOULDER POLE SEARCH ", rows.size(), " -> ", output);game.queue_free(); await process_frame;quit()
func _turn(pose: PostureDefinition, turn: Basis) -> PostureDefinition:
	var helper = preload("res://scripts/stroke_preparation_orientation.gd")
	var result: PostureDefinition = pose.lerp_with(pose, 0)
	var old: Basis = helper.canonical_basis(pose); var basis: Basis = old * turn
	var from_head: = (PaddleSize.MAIN_GRIP_OFFSET - PaddleSize.HEAD_OFFSET) + pose.right_hand_offset
	var grip: = Vector3(pose.paddle_forehand_mul, pose.paddle_y_offset, - pose.paddle_forward_mul) + old * from_head
	var head: Vector3 = grip - basis * from_head;helper.set_canonical_basis(result, basis)
	result.paddle_forehand_mul = head.x;result.paddle_y_offset = head.y;result.paddle_forward_mul = - head.z
	return result
