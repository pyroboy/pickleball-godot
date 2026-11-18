extends SceneTree
const Store = preload("res://scripts/mobile_serve_pose_store.gd")
const Styles = preload("res://scripts/serve_style.gd")
const Surface = preload("res://scripts/paddle_clearance.gd")
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
var checks := 0
var failures: Array[String] = []
var game
var preview
var contacts := 0
var test_path := ""
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func tick() -> void:
	if game.game_state == game.GameState.WAITING and game.serving_team == 1:
		game.ai_serve_timer = game.game_serve.get_charge_ratio() / 0.8 * 1.5 if game.game_serve.is_charging() else 0.0
	await physics_frame; await process_frame
func local_foot(p, right: bool) -> Vector3:
	var leg = p.right_leg_node if right else p.left_leg_node
	var v: Vector3 = leg.foot_pivot.global_position - p.global_position
	return Vector3(v.dot(p._get_forehand_axis()), v.y, v.dot(p._get_forward_axis()))
func feet_match_preview(p, style: int, t: float) -> void:
	preview.show_pose(Store.sample(Store.get_def(style), t))
	for right in [true, false]:
		check(local_foot(p, right).distance_to(local_foot(preview.player, right)) < 0.0001, "saved planted feet match visible preview side%d style%d t%.1f" % [p.player_num, style, t])
	var actual_yaw: float = p.leg_ik._right_yaw - atan2(-p._get_forward_axis().x, -p._get_forward_axis().z)
	var preview_yaw: float = preview.player.leg_ik._right_yaw - atan2(-preview.player._get_forward_axis().x, -preview.player._get_forward_axis().z)
	check(absf(angle_difference(actual_yaw, preview_yaw)) < 0.00001, "saved planted toe angle matches visible preview")
func on_contact(side: int) -> void:
	contacts += 1
	var p = game.player_left if side == 0 else game.player_right
	var style: int = game.game_serve.selected_serve_style
	feet_match_preview(p, style, 0.5)
	var ball_local: Vector3 = p.paddle_node.global_transform.affine_inverse() * game.ball.global_position
	check(absf(Surface.distance_to_head_shape(ball_local) - Ball.BALL_RADIUS) < 0.0002, "edited real serve exact physical contact side%d style%d" % [side, style])
	for field in Store.PADDLE_FIELDS.slice(3):
		check(is_equal_approx(p.posture.transition_pose_blend.get(field), Store.get_def(style).get(field)), "live requested Contact rotation remains active: " + field)
	var Wrist = load("res://scripts/paddle_wrist_reach.gd")
	check(Wrist.displayed_wrist(p, p.posture.transition_pose_blend).distance_to(Wrist.wrist_world(p.paddle_node.global_transform, p.posture.transition_pose_blend)) < .00001, "live rotated Contact wrist stays seated")
	check(game.ball.get_meta("serve_delivery_bounces") == (1 if Styles.is_drop(style) else 0), "delivery bounce legality retained")
	check(is_equal_approx(p.posture.transition_pose_blend.body_yaw_deg, Store.get_default(style).body_yaw_deg + 2.0), "live contact body edit applied")
	check(is_equal_approx(p.posture.transition_pose_blend.main_grip_rotation_deg, Store.get_default(style).main_grip_rotation_deg + 2.0), "live contact grip edit applied")
	check(p.posture.transition_pose_blend.body_position_offset.is_equal_approx(Vector3(.012, -.015, -.015)), "live Contact body translation applied without moving its ball target")
func run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	test_path = "user://pose_store_tests/serve_live_%d/serves.json" % OS.get_process_id()
	Store.set_test_path(test_path)
	for style in range(7):
		var edit: PostureDefinition = Store.get_default(style)
		edit.body_yaw_deg += 2.0
		edit.paddle_pitch_base_deg += 5.0
		edit.paddle_yaw_base_deg -= 4.0
		edit.paddle_roll_base_deg += 6.0
		edit.charge_paddle_rotation_deg -= Vector3(5, -4, 6)
		edit.ft_paddle_rotation_deg -= Vector3(5, -4, 6)
		edit.body_position_offset = Vector3(.012, -.015, -.015)
		edit.windup_body.values.body_position_offset = Vector3(-.008, -.01, 0)
		edit.follow_through_body.values.body_position_offset = Vector3(.01, -.015, .005)
		edit.main_grip_rotation_deg += 2.0
		edit.paddle_in_hand_rotation_deg = 3.0
		edit.right_knee_pole.x += 0.01
		edit.windup_body.values.torso_yaw_deg += 2.0
		edit.windup_body.values.right_foot_offset.x += 0.01
		edit.windup_body.values.right_foot_yaw_deg += 3.0
		edit.windup_body.values.stance_width += 0.02
		edit.charge_paddle_offset.x += 0.01
		edit.follow_through_body.values.right_elbow_pole.y += 0.01
		edit.ft_paddle_offset.y += 0.02
		check(Store.save(edit) == OK, "persist modest serve edits")
		check(Store.copy_values(edit, Store.get_def(style)) == OK, "publish modest serve edits")
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	preview = load("res://scripts/ui/mobile_pose_preview.gd").new(); root.add_child(preview)
	await process_frame; await physics_frame
	game.input_handler.set_process(false)
	game.game_serve.serve_launched.connect(on_contact)
	for side in [0, 1]:
		for style in range(7):
			game.serving_team = side; game._reset_ball(); game.game_serve.select_serve_style(style)
			game.player_right.set_ai_movement_enabled(false)
			var p = game.player_left if side == 0 else game.player_right
			for i in range(15): await tick()
			feet_match_preview(p, style, 0.0)
			if side == 0 and style == 0:
				var saved_again: PostureDefinition = Store.get_def(style).duplicate(true)
				saved_again.windup_body.values.left_foot_offset.x -= 0.012
				check(Store.save(saved_again) == OK and Store.copy_values(saved_again, Store.get_def(style)) == OK, "save new stance while already prepared")
				game.game_serve._prepare_server(0.0)
				feet_match_preview(p, style, 0.0)
			check(game.game_serve._legal_service_feet(p, side), "automatic setup clears full edited shoe footprint")
			game.game_serve.start_charge(); game.game_serve.tick_charge(0.7 * PickleballConstants.MAX_SERVE_CHARGE_TIME)
			for i in range(3): await tick()
			feet_match_preview(p, style, 0.0)
			check(absf(p.left_arm_node.articulated_hand.ball_surface_gap(p.left_arm_node.hand_mesh.to_local(game.ball.global_position))) < 0.0002, "edited held ball remains in support palm")
			var before: int = contacts
			game.game_serve.release(0.7)
			check(game.ball.linear_velocity.length() < 0.00001, "release remains unforced")
			for frame in range(135):
				await tick()
				if contacts > before: break
			check(contacts == before + 1, "edited serve reaches real contact side%d style%d" % [side, style])
			game.ball.freeze = true
			# Check the actual follow-through owner synchronously, before ordinary
			# rally movement translates the server away from its planted feet.
			game.game_serve._advance_follow_through(Styles.sweep_duration(style))
			feet_match_preview(p, style, 1.0)
			for i in range(35): await tick()
	check(contacts == 14, "all fourteen edited live serves delivered")
	game.serving_team = 0; game._reset_ball(); game.game_serve.select_serve_style(0)
	for index in range(5): await tick()
	game.game_serve.start_charge(); game.game_serve.tick_charge(.2); game.game_serve.release(.7)
	check(game.game_serve.is_release_pending(), "rotated serve starts a pending delivery")
	var before_cancel := contacts
	game.game_serve.cleanup()
	for index in range(50): await tick()
	check(not game.game_serve.is_release_pending() and contacts == before_cancel, "cancelled rotated serve never launches late")
	DirAccess.remove_absolute(test_path)
	print("MOBILE SERVE POSE LIVE: %d checks, %d failures" % [checks, failures.size()])
	preview.queue_free()
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game)
	quit(0 if failures.is_empty() else 1)
