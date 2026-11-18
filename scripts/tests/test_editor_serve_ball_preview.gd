extends SceneTree


const Preview = preload("res://scripts/posture_editor_v2/runtime_motion_preview.gd")
const BallPreview = preload("res://scripts/posture_editor_v2/serve_ball_preview.gd")
const Styles = preload("res://scripts/serve_style.gd")
const Hands = preload("res://scripts/player_hand_presentation.gd")
const Policy = preload("res://scripts/runtime_policy.gd")
var checks: = 0
var errors: Array[String] = []
class LateFrame extends Node:
	signal presented
	func _process(_delta: float) -> void : create_tween().tween_callback( func(): presented.emit())
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok and errors.size() < 30: errors.append(label)
func physics_state(ball) -> Array:
	return [ball.global_transform, ball.linear_velocity, ball.angular_velocity, ball.freeze, ball.collision_layer, ball.collision_mask]
func run():
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.game_serve.cleanup()
	game._toggle_posture_editor_v2()
	var editor = game.posture_editor_v2
	game.process_mode = Node.PROCESS_MODE_DISABLED
	for tween in get_processed_tweens(): tween.kill()
	var original: Array = physics_state(game.ball)
	var original_mesh: MeshInstance3D
	for child in game.ball.get_children():
		if child is MeshInstance3D and child.mesh is SphereMesh and is_equal_approx(child.mesh.radius, Ball.BALL_RADIUS): original_mesh = child;break
	var preview = BallPreview.new()
	for player in [game.player_left, game.player_right]:
		player.hitting.serving_visual_active = false;player.hitting.charge_visual_active = false;player.hitting.is_in_follow_through = false
		player.posture.editor_preview_mode = true
		for style in range(7):
			var plan: Dictionary = Styles.release_plan(Vector3(0, player.global_position.y, 0), false, style)
			var times: Array = [0.0, 0.045, float(plan.contact_time) * 0.5, float(plan.contact_time), float(plan.contact_time) + 0.05]
			if float(plan.bounce_time) > 0.0:
				times.append(float(plan.bounce_time) - 0.02);times.append(float(plan.bounce_time) + 0.02)
			var first_positions: Dictionary = {}
			for pass_index in range(2):
				for elapsed in times:
					var pose: PostureDefinition = Preview.sample_serve_elapsed(style, elapsed, 0.7, player.global_position.y)
					player.posture.transition_pose_blend = pose;player.posture.force_posture_update(pose)
					preview.update(player, pose, true)
					check( not game.ball.visible, "live ball hidden while editor proxy owns visibility")
					check(physics_state(game.ball) == original, "editor never changes live ball physics")
					check(preview.mesh.mesh == original_mesh.mesh, "proxy shares actual radius and ball mesh")
					if elapsed <= float(plan.contact_time):
						check(preview.mesh.visible, "held/drop/contact proxy is visible")
						if elapsed == 0.0:
							check(preview.mesh.global_position.distance_to(Hands.ball_center(player.left_arm_node)) < 1e-05, "held proxy seats in actual cup on either court")
						elif is_equal_approx(elapsed, float(plan.contact_time)):
							var c: Vector3 = plan.contact_position
							var expected: Vector3 = player.global_position + player._get_forehand_axis() * c.x + Vector3.UP * (c.y - player.global_position.y) - player._get_forward_axis() * c.z
							check(preview.mesh.global_position.distance_to(expected) < 1e-05, "contact proxy matches existing release plan")
					else: check( not preview.mesh.visible, "no invented outgoing flight after editor contact")
					if pass_index == 0: first_positions[elapsed] = preview.mesh.global_position
					elif preview.mesh.visible: check(preview.mesh.global_position.is_equal_approx(first_positions[elapsed]), "reverse scrub gives same visible delivery position")
				times.reverse()
			var builds: int = preview.plan_build_count
			for idle in range(60): preview.update(player, player.posture.transition_pose_blend, true)
			check(preview.plan_build_count == builds, "idle preview reuses cached release plan")
	preview.restore();check(game.ball.visible, "normal live visibility restored")
	game.ball.visible = false
	preview.update(game.player_left, Preview.sample_serve(0, 0, 0.5), true)
	preview.restore();check( not game.ball.visible, "original hidden visibility restored exactly")
	game.ball.visible = true
	preview.dispose(); await process_frame

	editor._on_posture_selected(0);editor._technique_picker.select(Preview.Technique.SERVE)
	editor._preview_charge.set_value_no_signal(0.3);editor._swing_speed.select(2)
	editor._on_runtime_preview_changed();editor._on_swing_scrubbed(0.0);editor._process(0.0)
	check(editor._serve_ball_preview != null and editor._serve_ball_preview.mesh.visible, "actual editor creates held delivery preview")
	check( not game.ball.visible, "actual editor hides stale live ball")
	editor._on_preview_swing()
	check(editor.process_priority > editor._transition_player.process_priority, "delivery preview observes the current playback pose")
	editor.process_mode = Node.PROCESS_MODE_ALWAYS
	var late = LateFrame.new();late.process_priority = 10000;root.add_child(late)
	var playback_samples: = 0
	var playback_plan: Dictionary = Styles.release_plan(Vector3(0, game.player_left.global_position.y, 0), false, 0)
	for frame in range(100):
		await late.presented
		var pose: PostureDefinition = game.player_left.posture.transition_pose_blend
		if pose == null or not pose.has_meta("preview_serve_release_elapsed"): continue
		var elapsed: float = pose.get_meta("preview_serve_release_elapsed")
		if elapsed > 0.0 and elapsed < float(playback_plan.contact_time):
			var point: Vector3 = editor._serve_ball_preview._position_at(playback_plan, elapsed)
			var p = game.player_left
			var expected: Vector3 = p.global_position + p._get_forehand_axis() * point.x + Vector3.UP * (point.y - p.global_position.y) - p._get_forward_axis() * point.z
			check(editor._serve_ball_preview.mesh.global_position.distance_to(expected) < 1e-05, "real playback proxy matches this frame's delivered hand pose")
			playback_samples += 1
	check(playback_samples > 4, "real playback exercised multiple falling-ball frames")
	late.queue_free();editor.process_mode = Node.PROCESS_MODE_INHERIT
	editor._transition_player.pause()
	editor.visible = false;editor._process(0.0)
	check(game.ball.visible and not editor._serve_ball_preview.mesh.visible, "abrupt hide restores live visibility")
	editor.visible = true;editor._process(0.0);editor._finish_close()
	check(game.ball.visible and not editor._serve_ball_preview.mesh.visible, "close restores live visibility")
	var old: bool = Policy.developer_tools;Policy.developer_tools = false
	var mobile = BallPreview.new();mobile.update(game.player_left, Preview.sample_serve(0, 0, 0.5), true)
	check(mobile.mesh == null and mobile.plan_build_count == 0, "mobile constructs no preview mesh or release plan")
	Policy.developer_tools = old;mobile.dispose()
	var proxy: WeakRef = weakref(editor._serve_ball_preview.mesh)
	editor.queue_free(); await process_frame; await process_frame
	check(proxy.get_ref() == null, "editor disposal frees its proxy")
	game.queue_free(); await process_frame; await process_frame
	print("EDITOR SERVE BALL PREVIEW: ", checks, " checks, ", errors.size(), " failures")
	for error in errors: push_error(error)
	quit(0 if errors.is_empty() else 1)
