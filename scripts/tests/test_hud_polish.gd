extends SceneTree

var failures: Array[String] = []
var checks: = 0

func _initialize() -> void :
	call_deferred("run")

func check(condition: bool, message: String) -> void :
	checks += 1
	if not condition: failures.append(message)

func run() -> void :
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	var hud = game.hud
	var ui = game.scoreboard_ui
	ui.update_score(7, 11)
	check(hud.score.text == "7   :   11", "team score lost its values")
	check(hud._blue_label.text.contains("YOU") and hud._red_label.text.contains("AI"), "teams are not identified")
	game.serving_team = 1
	ui._sync_match_context()
	check(hud._serve_label.text.contains("AI SERVE"), "server label misses side-out change")
	game.serving_team = 0
	game.game_serve.start_charge()
	game.game_serve.tick_charge(0.3)
	ui._sync_match_context()
	check(hud._charging and hud._charge_bar.value > 0, "meter does not read real serve charge")
	hud.set_charge(3.0, true)
	check(is_equal_approx(hud._charge_bar.value, 1.0), "meter permits >100 percent")
	check(hud._charge_label.text.contains("100%"), "full charge lacks numeric feedback")
	game.game_serve.cleanup()
	ui._sync_match_context()
	check( not hud._charging and is_zero_approx(hud._charge_bar.value), "charge remains after cancellation")
	ui.update_difficulty(99)
	check(hud.difficulty.text.contains("HARD"), "difficulty overflow is not clamped")
	ui.show_fault("FAULT", "Serve must clear the kitchen")
	check(hud.fault.visible and hud.fault.modulate.a == 1.0, "fault feedback invisible")
	ui.show_out()
	check(hud.out_text.visible and hud.out_text.modulate.a == 1.0, "out feedback invisible")
	ui.show_zone("KITCHEN")
	check(hud.zone.visible and hud.zone.modulate.a == 1.0, "zone feedback invisible")
	ui.show_shot_type("DROP")
	ui._update_shot_type_fade(8.0)
	check(is_zero_approx(hud.shot_type.modulate.a), "shot fade leaves invalid alpha")
	ui.show_speed(21.3)
	check(hud.speed.text == "21.3 mph", "speed API changes supplied mph value")
	ui._update_timers(8.0)
	check(is_zero_approx(hud.speed.modulate.a), "stale speed remains after timeout")
	ui.hide_all_hud()
	check( not hud._charge_bar.visible and not hud._serve_label.visible and not hud._toolbar.visible, "new HUD elements leak into editor")
	ui.show_all_hud()
	check(hud._charge_bar.visible and hud._serve_label.visible, "new HUD elements fail to restore")
	check( not hud.fault.visible and not hud.out_text.visible, "dismissed fault resurrected after editor")
	for mode in ["Flat", "Topspin", "Slice"]:
		ui.set_spin_selection(mode)
		check(hud._spin_label.text.contains(mode.to_upper()), "selected spin text incorrect")
	check(hud._spin_label.visible and hud._spin_label.text.contains("[Q]"), "spin selector lacks shortcut")
	check(hud._guide_instructions.text.contains("Q  Cycle spin") and not hud._guide_instructions.text.contains("E / Q"), "guide retains conflicting Q shortcut")
	ui.hide_all_hud()
	check( not hud._spin_label.visible, "spin indicator leaks into editor")
	ui.show_all_hud()
	check(hud._spin_label.visible, "spin indicator missing after editor")
	ui.set_spin_selection("flat", "slice")
	check(hud._spin_label.text.contains("NEXT") and hud._locked_spin_label.visible, "pending selection not distinguished from locked shot")
	check(hud._locked_spin_label.text.contains("SLICE"), "locked shot text incorrect")
	ui.set_spin_selection("flat")
	check( not hud._locked_spin_label.visible and hud._spin_label.text.contains("SPIN"), "locked shot survives reset")
	ui.set_spin_selection("flat", "", "DROP")
	hud.set_match_context(0, false)
	check(hud._spin_label.text.contains("DROP") and hud._spin_label.text.contains("RALLY"), "Drop selection misrepresents legal serve")
	hud.set_match_context(0, true)
	hud.set_charge(0.5, true)
	check(hud._spin_label.text.contains("SHOT") and hud._charge_label.text.contains("DROP TOUCH"), "Drop touch feedback missing in rally")
	ui.set_spin_selection("flat", "slice", "DROP", "AUTO")
	check(hud._spin_label.text.contains("NEXT") and hud._locked_spin_label.text.contains("SLICE"), "locked spin vs next Drop unclear")
	ui.set_spin_selection("topspin", "flat", "AUTO", "DROP")
	check(hud._locked_spin_label.text.contains("DROP"), "locked Drop lost after choosing spin")
	check(hud._guide_instructions.text.contains("F2  Edit poses") and hud._pose_button.tooltip_text.ends_with("F2"), "editor shortcut not updated to F2")
	ui.set_spin_selection("flat")
	for resolution in [Vector2i(1440, 900), Vector2i(1280, 720), Vector2i(960, 600), Vector2i(800, 600)]:
		root.content_scale_size = resolution
		root.size = resolution
		await process_frame
		await process_frame
		hud._layout_desktop()
		var screen: = Rect2(Vector2.ZERO, root.get_visible_rect().size)
		for element in [hud._score_panel, hud._status_panel, hud._toolbar, hud._charge_bar, hud._controls_hint]:
			check(screen.encloses(element.get_global_rect()), "%s offscreen at %s" % [element.name, resolution])
		check( not hud._score_panel.get_global_rect().intersects(hud._toolbar.get_global_rect()), "toolbar overlaps score at %s" % resolution)
		check( not hud._score_panel.get_global_rect().intersects(hud.shot_type.get_global_rect()), "shot feedback overlaps score at %s" % resolution)
		check(hud._status_panel.get_global_rect().encloses(hud._charge_label.get_global_rect()), "charge label exceeds status card at %s" % resolution)
		hud._toggle_guide()
		await process_frame
		check(screen.encloses(hud._guide.get_global_rect()), "guide offscreen at %s" % resolution)
		hud._guide_button.grab_focus()
		hud._toggle_guide()
		check( not hud._guide_button.has_focus(), "guide close traps Space on toolbar")
		var controller = root.get_node("PauseController")
		controller.open()
		await process_frame
		check(screen.encloses(controller._menu._panel.get_global_rect()), "pause panel offscreen at %s" % resolution)
		check(controller._menu._resume_button.has_focus(), "pause lacks initial keyboard focus")
		controller._menu._on_settings()
		var settings = controller._menu._settings_overlay
		var settings_store = root.get_node("Settings")
		for key in ["video.fov", "video.shake", "gameplay.reaction_delay", "audio.master", "audio.sfx", "audio.ambience", "audio.footsteps"]:
			var slider: HSlider = settings._panel.find_child(key.replace(".", "_"), true, false)
			check(is_equal_approx(slider.value, float(settings_store.get_value(key))), "slider does not show real setting: " + key)
		for key in ["video.particle_density", "video.shadow_quality", "gameplay.difficulty"]:
			var option: OptionButton = settings._panel.find_child(key.replace(".", "_"), true, false)
			check(option.selected == int(settings_store.get_value(key)), "dropdown does not show real setting: " + key)
		controller._menu._on_settings()
		check(controller._menu._settings_overlay == settings, "repeat Settings stacks overlays")
		await process_frame
		check(screen.encloses(settings._panel.get_global_rect()), "settings offscreen at %s" % resolution)
		settings._on_close()
		settings._on_close()
		check(controller._menu._settings_button.has_focus(), "settings return loses keyboard focus")
		controller.close()
		await process_frame
	game.queue_free()
	await process_frame
	await process_frame
	for failure in failures: push_error(failure)
	print("HUD POLISH: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
