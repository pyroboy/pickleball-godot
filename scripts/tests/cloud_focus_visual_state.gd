extends SceneTree
## Headless state-contract checks. Shader pixel output remains separate native QA.
const Layout = preload("res://scripts/ui/mobile_layout.gd")
const FocusShader = preload("res://shaders/solo_aim_focus.gdshader")
const DimShader = preload("res://shaders/solo_aim_focus_dim.gdshader")
var checks := 0
var failures: Array[String] = []
var game
var focus
var settings
var now := 100000000

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.0001, label + " expected %.5f, got %.5f" % [expected, actual])

func frames(count := 2) -> void:
	for i in count:
		await process_frame

func show_focus() -> void:
	focus.cancel()
	game._reset_ball()
	Input.action_press("ui_accept")
	game._on_player_swing_press()
	game.aim_controller.update(0.1, true, Vector2.ZERO)
	now += 1000000
	focus._update_presentation(now)

func end_focus() -> void:
	Input.action_release("ui_accept")
	game.input_handler.cancel_charge_input()
	focus.cancel()

func run() -> void:
	create_timer(60.0, true).timeout.connect(func(): quit(2))
	root.size = Vector2i(540, 960)
	root.content_scale_size = Vector2i(720, 1280)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(4)
	game.process_mode = Node.PROCESS_MODE_DISABLED
	focus = game.aim_focus
	focus.set_process(false)
	settings = root.get_node("Settings")
	near(float(settings.get_value("video.focus_dim")), 0.14, "default dim")
	near(float(settings.get_value("video.focus_blur")), 0.65, "default blur")
	check(bool(settings.get_value("video.focus_preview")), "default preview on")
	check(focus.layer < game.hud.layer, "HUD stays above focus CanvasLayer")
	check(focus._dim.mouse_filter == Control.MOUSE_FILTER_IGNORE and focus._drawing.mouse_filter == Control.MOUSE_FILTER_IGNORE, "focus visuals do not capture inputs")
	show_focus()
	check(focus.active and focus._presentation and focus._dim.visible and focus._drawing.visible, "default focus presents all intended layers")
	near(float(focus._material.get_shader_parameter("strength")), 0.0, "entry starts with zero dim")
	near(float(focus._material.get_shader_parameter("effect_mix")), 0.0, "entry starts with zero blur blend")
	focus._update_presentation(now + focus.VISUAL_ENTER_USEC / 2)
	near(float(focus._material.get_shader_parameter("strength")), 0.07, "halfway eased dim")
	near(float(focus._material.get_shader_parameter("effect_mix")), 0.5, "halfway eased blur blend")
	focus._update_presentation(now + focus.VISUAL_ENTER_USEC)
	near(float(focus._material.get_shader_parameter("strength")), 0.14, "fully entered dim")
	near(float(focus._material.get_shader_parameter("effect_mix")), 1.0, "fully entered blur blend")
	check(focus._material.shader == FocusShader, "default uses blur shader")
	for size in [Vector2i(360, 800), Vector2i(432, 936), Vector2i(720, 1280), Vector2i(1180, 780)]:
		root.size = size
		root.content_scale_size = size
		await frames(3)
		focus._update_presentation(now + focus.VISUAL_ENTER_USEC + 1)
		var viewport := root.get_visible_rect()
		check(focus._dim.get_global_rect().is_equal_approx(viewport), "full viewport dim rect after resize %s (actual %s expected %s)" % [size, focus._dim.get_global_rect(), viewport])
		check(focus._drawing.get_global_rect().is_equal_approx(viewport), "full viewport preview rect after resize %s" % size)
		check(focus._material.get_shader_parameter("viewport_size").is_equal_approx(viewport.size), "uniform viewport dimensions follow resize %s" % size)
		near(float(focus._material.get_shader_parameter("blur_radius")), 0.65 * 2.0 * Layout.scale_for(viewport.size), "scaled blur radius %s" % size)
	settings.set_value("video.focus_preview", false)
	focus._update_presentation(now + focus.VISUAL_ENTER_USEC + 2)
	check(not focus._drawing.visible and focus._dim.visible and focus.active, "preview off preserves dim and focus gameplay")
	settings.set_value("video.focus_blur", 0.0)
	focus._update_presentation(now + focus.VISUAL_ENTER_USEC + 3)
	check(focus._material.shader == DimShader and focus._dim.visible, "zero blur uses dim-only shader")
	near(float(focus._material.get_shader_parameter("strength")), 0.14, "dim-only strength preserved")
	settings.set_value("video.focus_dim", 0.0)
	focus._update_presentation(now + focus.VISUAL_ENTER_USEC + 4)
	check(not focus._dim.visible and not focus._drawing.visible and focus.active, "all visuals off leaves focus timing active")
	settings.set_value("video.focus_preview", true)
	focus._update_presentation(now + focus.VISUAL_ENTER_USEC + 5)
	check(not focus._dim.visible and focus._drawing.visible, "preview-only mode")
	settings.reset_focus_visuals()
	focus._update_presentation(now + focus.VISUAL_ENTER_USEC + 6)
	check(focus._dim.visible and focus._drawing.visible and focus._material.shader == FocusShader, "visual defaults reenable independently")
	var camera: Camera3D = root.get_camera_3d()
	var camera_before: Transform3D = camera.global_transform
	var ball_before: Vector3 = game.ball.global_position
	var viewport_size: Vector2 = root.get_visible_rect().size
	var behind: Vector3 = camera.global_position + camera.global_basis.z * 5.0
	check(focus._protected_uv(camera, behind, viewport_size) == Vector2(-2, -2), "behind-camera point mask uses sentinel")
	game.ball.global_position = behind
	focus._update_presentation(now + focus.VISUAL_ENTER_USEC + 7)
	check(focus._material.get_shader_parameter("ball_uv") == Vector2(-2, -2), "moving ball behind camera clears its visible mask")
	game.ball.global_position = ball_before
	focus._update_presentation(now + focus.VISUAL_ENTER_USEC + 8)
	check(focus._material.get_shader_parameter("ball_uv").is_equal_approx(focus._protected_uv(camera, ball_before, viewport_size)), "returning ball recomputes current projection")
	camera.global_position += camera.global_basis.x * 0.5
	focus._update_presentation(now + focus.VISUAL_ENTER_USEC + 9)
	check(focus._material.get_shader_parameter("blue_uv").is_equal_approx(focus._protected_uv(camera, game.player_left.global_position + Vector3.UP * 0.10, viewport_size)), "camera move recomputes player mask")
	camera.rotate_y(PI)
	focus._update_presentation(now + focus.VISUAL_ENTER_USEC + 10)
	check(not focus._presentation and not focus._dim.visible and not focus._drawing.visible and focus._visual_enter_usec == -1, "target behind camera hides effects and clears entry timer")
	camera.global_transform = camera_before
	focus._update_presentation(now + focus.VISUAL_ENTER_USEC + 11)
	check(focus._presentation and focus._visual_enter_usec > 0, "camera return reenters presentation")
	near(float(focus._material.get_shader_parameter("strength")), 0.0, "camera return restarts eased entry")
	for reason in ["cancel", "pause", "background", "release"]:
		show_focus()
		focus._update_presentation(now + focus.VISUAL_ENTER_USEC)
		check(focus._presentation, "cancellation fixture present for " + reason)
		match reason:
			"cancel": focus.cancel()
			"pause":
				root.get_node("PauseController").open()
				root.get_node("PauseController").close()
			"background": focus._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
			"release": focus.end_hold()
		check(not focus.active and not focus._presentation and not focus._dim.visible and not focus._drawing.visible and focus._visual_enter_usec == -1, "immediate visual cleanup on " + reason)
		near(Engine.time_scale, 1.0, "normal clock after " + reason)
		end_focus()
	game.queue_free()
	await frames(3)
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	print("CLOUD FOCUS VISUAL STATE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
