extends SceneTree

const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const HP = preload("res://scripts/player_hand_presentation.gd")
const Hand = preload("res://scripts/articulated_hand.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
class LateFrame extends Node:
	signal presented
	func _process(_delta: float) -> void : create_tween().tween_callback( func(): presented.emit())
var late
var checks: = 0
var failures: Array[String] = []
var modes: Dictionary = {}
var maximum_wrist_gap: = 0.0
var maximum_arm_scale: = 1.0
var maximum_arm_scale_case: = ""
var live_main_anatomy_failures: Array = []
var live_main_anatomy_samples: = 0
var real_contacts_checked: = 0
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok and not label in failures: failures.append(label)
func sample(p, label: String) -> void :
	var pose = p.posture.transition_pose_blend if p.posture.transition_pose_blend != null else p.get_runtime_posture_def()
	var arm = p.left_arm_node if pose.paddle_hand == 1 else p.right_arm_node
	var offset: Vector3 = pose.left_hand_offset if pose.paddle_hand == 1 else pose.right_hand_offset
	check(arm.hand_pivot.global_position.distance_to(p.paddle_node.to_global(PaddleSize.MAIN_GRIP_OFFSET + offset)) < 0.001, label + " exact virtual grip")
	var main_model = arm.articulated_hand
	var main_joints: Dictionary = main_model.joint_positions()
	var mount: Transform3D = arm.hand_mesh.global_transform
	var shaft: Vector3 = p.paddle_node.global_basis.y.normalized()
	var index: Vector3 = mount * main_joints.index_mcp
	var pinky: Vector3 = mount * main_joints.little_mcp
	var middle: Vector3 = mount * main_joints.middle_mcp
	var wrist: Vector3 = mount * main_joints.wrist
	if not label.begins_with("editor"):



		var shoulder: Vector3 = arm.upper_pivot.global_position
		var elbow: Vector3 = arm.forearm_pivot.global_position
		var channels: Dictionary = Anatomy.decompose(Anatomy.forearm_reference_for_arm(arm, wrist, main_model.is_left), mount.basis * main_model.anatomical_basis, main_model.radial_sign)
		live_main_anatomy_samples += 1
		var style: int = int(p.get_parent().game_serve.selected_serve_style)
		check(channels.within_animation_budget, label + " dominant wrist budget side%d style%d" % [p.player_num, style])
		if not channels.within_animation_budget and live_main_anatomy_failures.size() < 40:
			live_main_anatomy_failures.append({"label": label, "side": p.player_num, "style": style, "channels": channels, 
				"serve_timing": p.get_parent().game_serve.get_serve_timing_state(), "follow_through": p.get_parent().game_serve._follow_through.duplicate(), 
				"pose_id": pose.posture_id, "paddle_rotation": pose.resolve_paddle_rotation_deg(-1, -1), "right_pole": pose.right_elbow_pole})
	var dorsal: Vector3 = mount.basis * Vector3.BACK
	check((index - pinky).dot(shaft) > 0.01, label + " index is nearer actual paddle throat than pinky")
	var chirality: float = (middle - wrist).normalized().cross((index - pinky).normalized()).dot(dorsal)
	check(chirality * (-1.0 if main_model.is_left else 1.0) > 0.8, label + " actual mounted anatomical chirality")
	for a in [p.right_arm_node, p.left_arm_node]:
		if a.visual_stretch > maximum_arm_scale:
			maximum_arm_scale = a.visual_stretch;maximum_arm_scale_case = label + " player" + str(p.player_num) + " " + str(a.name)
		var model = a.articulated_hand
		check(model != null, label + " articulated hand present")
		if model == null: continue
		var stats: Dictionary = model.debug_metadata()
		modes[stats.pose] = true
		check(stats.surface_count == 1 and stats.triangles <= 1200 and stats.bones == 17, label + " render budget: palm,15 finger joints and wrist bridge")
		check(a.hand_mesh.global_basis.determinant() > 0.99, label + " proper hand frame")
		check(a.visual_wrist_lag_deg >= 0.0 and a.visual_wrist_lag_deg <= 6.0001, label + " bounded visual lag")
		var socket: Vector3 = a.hand_mesh.global_transform * model.wrist_socket
		maximum_wrist_gap = maxf(maximum_wrist_gap, socket.distance_to(a.anatomical_wrist_world))
		check(socket.distance_to(a.anatomical_wrist_world) < 0.0001, label + " visible wrist matches solved endpoint")
func tick(p, label: String) -> void :
	var g = p.get_parent()
	if g.game_state == g.GameState.WAITING and g.serving_team == 1:
		g.ai_serve_timer = g.game_serve.get_charge_ratio() / 0.8 * 1.5 if g.game_serve.is_charging() else 0.0
	await physics_frame; await late.presented
	sample(p, label)
func run() -> void :
	create_timer(90).timeout.connect( func(): quit(2))
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	game.input_handler.set_process(false)
	game.game_serve.serve_launched.connect( func(side: int):
		var server = game.player_left if side == 0 else game.player_right
		real_contacts_checked += 1
		check(server.left_arm_node.articulated_hand._mode == "RELAXED", "actual CONTACT never reacquires the released ball side%d" % side))
	game.set_physics_process(true)
	late = LateFrame.new();late.process_priority = 10000;root.add_child(late)
	for side in [0, 1]:
		game.serving_team = side;game._reset_ball()
		var p = game.player_left if side == 0 else game.player_right
		game.player_right.set_ai_movement_enabled(false)
		for i in range(8): await tick(p, "idle settle")
		var before: Array = []
		for a in [p.right_arm_node, p.left_arm_node]:
			var model = a.articulated_hand
			before.append({"all": model.bone_pose_write_count, "bridge": model.wrist_bridge_update_count, "poses": model.pose_update_count, "mode": model._mode})
		for i in range(90): await tick(p, "idle")
		for index in range(2):
			var a = [p.right_arm_node, p.left_arm_node][index]
			var model = a.articulated_hand
			var all_delta: int = model.bone_pose_write_count - before[index].all
			var bridge_delta: int = model.wrist_bridge_update_count - before[index].bridge
			if all_delta > 0: print("IDLE CACHE side", side, " arm", index, " all=", all_delta, " bridge=", bridge_delta, " fingers=", all_delta - bridge_delta, " poses=", model.pose_update_count - before[index].poses, " modes=", before[index].mode, "->", model._mode)


			check(all_delta - bridge_delta == 0 and model.pose_update_count == before[index].poses, "idle adds no finger updates side%d" % side)
		for style in range(7):
			game.serving_team = side;game._reset_ball();game.game_serve.select_serve_style(style)
			for i in range(15): await tick(p, "held")
			game.game_serve.start_charge();game.game_serve.tick_charge(0.7 * PickleballConstants.MAX_SERVE_CHARGE_TIME)
			for i in range(3): await tick(p, "charged")
			var cup = p.left_arm_node.articulated_hand
			check(cup.debug_metadata().pose == "CUP", "actual serve state cups ball")
			var surface_gap: float = cup.ball_surface_gap(p.left_arm_node.hand_mesh.to_local(game.ball.global_position))
			check(absf(surface_gap) < 0.0002, "full skin contacts held ball side%d style%d gap%.6f" % [side, style, surface_gap])
			game.game_serve.release(0.7)
			var opened: = false
			for frame in range(130):
				await tick(p, "released")
				var stats: Dictionary = cup.debug_metadata()
				if stats.pose == "CUP" and stats.closure < 0.2: opened = true
				if game.ball.is_in_play: break
			check(opened, "release opens actual finger joints side%d style%d" % [side, style])
			check(game.ball.is_in_play, "real serve reached paddle contact")
			game.ball.freeze = true;game.set_physics_process(true)
			for i in range(50): await tick(p, "recovery")
			game.set_physics_process(true)


	for side in [0, 1]:
		for interruption in ["charge_reset", "release_reset", "release_cleanup"]:
			game.serving_team = side;game._reset_ball()
			var p = game.player_left if side == 0 else game.player_right
			for frame in range(12): await tick(p, "cancel settle")
			game.game_serve.start_charge();game.game_serve.tick_charge(0.65)
			if interruption != "charge_reset":
				game.game_serve.release(0.65)
				for frame in range(3): await tick(p, "cancel releasing")
			if interruption == "release_cleanup": game.game_serve.cleanup()
			else: game._reset_ball()
			check( not game.game_serve.is_release_pending(), "cancel clears pending release side%d %s" % [side, interruption])
			for frame in range(15): await tick(p, "cancel recovery")
			check( not game.ball.is_in_play, "cancel produces no stale contact")
			check(p.left_arm_node.articulated_hand.debug_metadata().pose == "CUP", "cancel restores actual held cup side%d %s pose=%s serving=%s" % [side, interruption, p.left_arm_node.articulated_hand.debug_metadata().pose, str(p.hitting.serving_visual_active)])
			game.game_serve.release(0.9)
			check( not game.game_serve.is_release_pending(), "cancel rejects stale release")

	game.process_mode = Node.PROCESS_MODE_DISABLED
	var p = game.player_left
	for dominant in [0, 1, 0, 1, 0]:
		var pose = PostureLibrary.instance().get_def(20).duplicate(true)
		pose.paddle_hand = dominant;pose.left_hand_mode = 4
		p.posture.editor_preview_mode = true;p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
		sample(p, "editor handedness")
	for dominant in [0, 1]:
		var pose = PostureLibrary.instance().get_def(20).duplicate(true)
		pose.paddle_hand = dominant;pose.left_hand_mode = 1
		p.posture.editor_preview_mode = true;p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
		for arm in [p.right_arm_node, p.left_arm_node]:
			var main: bool = arm.articulated_hand.is_left == (pose.paddle_hand == 1)
			var rotation: float = pose.main_grip_rotation_deg if main else pose.support_grip_rotation_deg
			var expected: Basis = HP.GripFrame.basis(p.paddle_node.global_basis, arm.articulated_hand.is_left, rotation)
			check(arm.hand_mesh.global_basis.is_equal_approx(expected), "grip orientation preserves anatomy plus explicit role profile")
	check(Hand.mesh_build_count == 2, "only one cached mesh per handedness through all resets")
	check(real_contacts_checked == 14, "all fourteen actual serve CONTACT callbacks checked")
	var anatomy_file: = FileAccess.open("/workspace/shared/pickleball-hands/live-main-serve-anatomy.json", FileAccess.WRITE)
	anatomy_file.store_string(JSON.stringify({"samples": live_main_anatomy_samples, "failures": live_main_anatomy_failures}, "  "));anatomy_file.close()
	print("HAND RUNTIME STATES: ", checks, " checks; failures=", failures, " modes=", modes, " wrist gap=", maximum_wrist_gap, " max_arm_scale=", maximum_arm_scale, " ", maximum_arm_scale_case)
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game, late)
	quit(0 if failures.is_empty() else 1)
