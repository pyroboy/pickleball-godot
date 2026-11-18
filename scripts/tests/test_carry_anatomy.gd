extends SceneTree

const A = preload("res://scripts/arm_anatomy.gd")
const B = preload("res://scripts/body_clearance.gd")
const P = preload("res://scripts/paddle_clearance.gd")
var checks: = 0
var failures: Array[String] = []
var minimum_body: = INF
var minimum_limb: = INF
var maximum_ratio: = 0.0
var maximum_rotation_step: = 0.0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok and failures.size() < 30: failures.append(label)
func run():
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	var head: Array[Vector3] = P.sample_head_surface()
	for player in [game.player_left, game.player_right]:
		player.hitting.serving_visual_active = false;player.hitting.charge_visual_active = false;player.hitting.is_in_follow_through = false
		player.posture.editor_preview_mode = false;player.current_velocity = Vector3.ZERO
		var previous: = Quaternion.IDENTITY
		for step in range(41):
			var bend: float = step / 40.0
			var pose: PostureDefinition = game.between_point_controller._make_pose(player.player_num, bend)
			player.leg_ik.feet_initialized = false;player.posture.transition_pose_blend = pose;player.posture.force_posture_update(pose)
			var arm = player.right_arm_node; var model = arm.articulated_hand
			var s: Vector3 = arm.upper_pivot.global_position; var e: Vector3 = arm.forearm_pivot.global_position
			var w: Vector3 = arm.hand_mesh.global_transform * model.wrist_socket
			var channels: Dictionary = A.decompose(A.forearm_reference_for_arm(arm, w, false), arm.hand_mesh.global_basis * model.anatomical_basis)
			maximum_ratio = maxf(maximum_ratio, channels.coupled_budget_ratio)
			check(channels.within_animation_budget, "carry keeps anatomical wrist budget side%d bend%.3f" % [player.player_num, bend])
			check(arm.visual_stretch <= 1.001 and absf(s.distance_to(e) - 0.35) < 0.0001 and absf(e.distance_to(w) - 0.35) < 0.0001, "carry preserves true main arm links")
			var geometry: Dictionary = B.volumes(player, pose, player.body_pivot.global_transform)
			var upper: Dictionary = B.mesh_surface_margins(arm.upper_mesh, geometry, s, e, 0.08)
			var fore: Dictionary = B.mesh_surface_margins(arm.fore_mesh, geometry)
			for region in B.REGIONS:
				var gap: float = minf(upper[region], fore[region]);minimum_body = minf(minimum_body, gap)
				check(gap >= - 3e-05, "carry clears actual " + region)
			var tx: Transform3D = player.paddle_node.global_transform
			for mesh in [arm.upper_mesh, arm.fore_mesh, player.left_arm_node.upper_mesh, player.left_arm_node.fore_mesh, player.right_leg_node.thigh_mesh, player.right_leg_node.shin_mesh, player.left_leg_node.thigh_mesh, player.left_leg_node.shin_mesh]:
				var relative: Transform3D = tx.affine_inverse() * mesh.global_transform
				var margin: = INF
				for point in B.mesh_surface_points(mesh): margin = minf(margin, P.distance_to_paddle_shape(relative * point))
				minimum_limb = minf(minimum_limb, margin)
				check(margin >= - 3e-05, "carry paddle clears actual " + mesh.name)
			var body: Dictionary = B.sample_paddle(tx, head, geometry)
			for region in B.REGIONS: check(body[region] >= - 3e-05, "carry blade clears " + region)
			var rotation: Quaternion = arm.hand_mesh.global_basis.get_rotation_quaternion()
			if step > 0:
				var angle: float = rad_to_deg(rotation.angle_to(previous));maximum_rotation_step = maxf(maximum_rotation_step, angle)
				check(angle < 5.0, "carry bend has no hand orientation pop")
			previous = rotation
	print("CARRY ANATOMY: ", checks, " checks; failures=", failures, " body=", minimum_body, " limb=", minimum_limb, " wrist ratio=", maximum_ratio, " rotation step=", maximum_rotation_step)
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game)
	quit(0 if failures.is_empty() else 1)
