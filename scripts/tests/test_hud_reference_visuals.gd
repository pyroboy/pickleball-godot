extends SceneTree

const Layout = preload("res://scripts/ui/mobile_layout.gd")
var failures: Array[String] = []
var checks: = 0

func _initialize() -> void :
	call_deferred("run")

func check(condition: bool, message: String) -> void :
	checks += 1
	if not condition: failures.append(message)

func run() -> void :
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	var hud = game.hud
	game.input_handler.set_process(false)
	for resolution in [Vector2i(720, 1280), Vector2i(600, 960), Vector2i(1080, 2340)]:
		root.content_scale_size = resolution
		root.size = resolution
		await process_frame
		await process_frame
		hud._layout_desktop()
		hud.set_gameplay_elements_visible(true)
		hud.set_score(11, 10)
		hud.set_aim_state("SERVE")
		hud.set_charge(0.0, false)
		var safe: = Layout.safe_rect(root)
		var court: = Layout.court_rect(safe.size, safe)
		check(hud.score.text == "11   :   10", "reference scoreboard changes public score text")
		check(hud._score_chrome.is_visible_in_tree(), "angular scoreboard missing in portrait")
		check(hud._guidance_chrome.is_visible_in_tree(), "icon guidance missing in portrait")
		check( not hud._status_panel.visible, "legacy opaque mobile status panel restored")
		check(hud._blue_label.text == "YOU\nBLUE" and hud._red_label.text == "AI\nRED", "reference team names missing")
		for control in [hud._score_panel, hud._guidance_chrome, hud._toolbar, hud.state, hud._charge_label, hud._charge_bar, hud._controls_hint]:
			check(safe.encloses(control.get_global_rect()), "%s offscreen at %s" % [control.name, resolution])
			check(control.get_global_rect().end.y < court.position.y, "%s enters portrait court band" % control.name)
		check( not hud._guidance_chrome.get_global_rect().intersects(hud._toolbar.get_global_rect()), "guidance overlaps toolbar")
		for caption in hud._toolbar_captions:
			check(caption.is_visible_in_tree() and not caption.text.is_empty(), "icon-only toolbar lost readable label")
		hud.set_gameplay_elements_visible(false)
		check( not hud._score_chrome.is_visible_in_tree() and not hud._guidance_chrome.is_visible_in_tree(), "decorations leak into menu/editor")
		hud.set_gameplay_elements_visible(true)
		hud.set_between_point_active(true)
		await process_frame
		check(hud._skip_button.is_visible_in_tree(), "retrieval skip hidden by icon toolbar")
		check( not hud._guidance_chrome.guidance_details, "empty guidance rows retain icons during retrieval")
		check( not hud._charge_label.visible and not hud._controls_hint.visible, "retrieval resurrects gameplay captions")
		hud.set_between_point_active(false)
		check(hud._guidance_chrome.guidance_details and hud._charge_label.visible, "guidance does not recover after retrieval")
	root.content_scale_size = Vector2i(1280, 800)
	root.size = Vector2i(1280, 800)
	await process_frame
	await process_frame
	hud._layout_desktop()
	check( not hud._score_chrome.visible and not hud._guidance_chrome.visible, "portrait chrome persists on desktop")
	check(hud._guide_button.text == "Guide" and hud._pause_button.text == "Pause", "desktop toolbar labels not restored")
	check(hud._blue_label.text == "YOU · BLUE" and hud._red_label.text == "AI · RED", "desktop team labels not restored")
	check(hud._status_panel.visible, "desktop status card not restored")
	game.queue_free()
	await process_frame
	await process_frame
	for failure in failures: push_error(failure)
	print("HUD REFERENCE VISUALS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
