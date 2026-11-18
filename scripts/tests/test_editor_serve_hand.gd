extends SceneTree


const Preview = preload("res://scripts/posture_editor_v2/runtime_motion_preview.gd")
const Styles = preload("res://scripts/serve_style.gd")
const Hands = preload("res://scripts/player_hand_presentation.gd")
var checks: = 0
var errors: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok and errors.size() < 40: errors.append(label)
func run():
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	for p in [game.player_left, game.player_right]:
		p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
		p.current_velocity = Vector3.ZERO;p.posture.editor_preview_mode = true
		var model = p.left_arm_node.articulated_hand
		for style in range(7):
			for charge in [0.0, 0.3, 0.6, 1.0]:
				var held: PostureDefinition = Preview.sample_serve(style, 0.0, charge, p.global_position.y)
				p.posture.transition_pose_blend = held;p.posture.force_posture_update(held)
				var local: Vector3 = Styles.hold_offset(style)
				var center: Vector3 = p.global_position + p._get_forehand_axis() * local.x + Vector3.UP * local.y + p._get_forward_axis() * local.z
				check(model._mode == "CUP" and is_equal_approx(model._closure, 1.0), "all editor held styles use closed cup")
				check(Hands.ball_center(p.left_arm_node).distance_to(center) < 1e-05, "editor cup uses exact shared held centre on both courts")
				var gap: float = Hands.ball_surface_gap(p.left_arm_node, center, Hands.BALL_RADIUS)
				check(gap >= - 0.001 and gap < 0.003, "editor held ball seats on finite palm surface")
				var frames: Dictionary = {}
				for elapsed in [0.0, 0.045, 0.081, 0.135, 0.179, 0.18, 0.181, 0.25]:
					var pose: PostureDefinition = Preview.sample_serve_elapsed(style, elapsed, charge, p.global_position.y)
					p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
					frames[elapsed] = model.hand_mesh.global_transform
					check(model.hand_mesh.global_basis.determinant() > 0.99, "preview release retains a proper hand frame")


				for elapsed in [0.135, 0.0, 0.25, 0.045, 0.181, 0.081, 0.18, 0.179]:
					var pose: PostureDefinition = Preview.sample_serve_elapsed(style, elapsed, charge, p.global_position.y)
					p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
					var actual: Transform3D = model.hand_mesh.global_transform
					var expected: Transform3D = frames[elapsed]
					check(actual.origin.distance_to(expected.origin) < 1e-05 and actual.basis.is_equal_approx(expected.basis), "editor arbitrary seek is deterministic")
				var ready: PostureDefinition = PostureLibrary.instance().get_def(20)
				p.posture.transition_pose_blend = ready;p.posture.force_posture_update(ready)
				check(model._mode == "RELAXED", "leaving serve preview returns to the authored one-hand Ready guard")
	print("EDITOR SERVE HAND: ", checks, " checks, ", errors.size(), " failures")
	for error in errors: push_error(error)
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game)
	quit(0 if errors.is_empty() else 1)
