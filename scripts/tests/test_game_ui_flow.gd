extends SceneTree
## Actual scene integration: all poses, preview stages, numeric controls and tool lifecycle.
var failures: Array[String] = []
var checks: int = 0
const SwingPath = preload("res://scripts/stroke_swing_path.gd")

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func run() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await physics_frame
	await process_frame
	var editor = game.posture_editor_v2
	var pause_controller = root.get_node("PauseController")
	var old_size: Vector2i = root.size
	var camera_transform: Transform3D
	game._perform_serve(0.5)
	await physics_frame
	camera_transform = game.camera_rig.camera.transform
	game._toggle_posture_editor_v2()
	var held_position: Vector3 = game.ball.global_position
	for i in range(5):
		await physics_frame
	check(game.ball.global_position.distance_to(held_position) < 0.001, "ball moves while editing")
	check(not game.player_left.is_physics_processing(), "human movement remains active in editor")
	check(not game.player_right.is_physics_processing(), "AI movement remains active in editor")
	check(not game.hud._toolbar.visible and not game.reaction_button.visible, "game HUD overlaps editor")
	check(root.size == old_size, "opening editor changes window size")
	check(editor._pose_picker.item_count == 21, "stroke selector must contain all 21 poses")
	var projected_player: Vector2 = game.camera_rig.camera.unproject_position(game.player_left.global_position)
	check(projected_player.x < editor.get_global_rect().position.x * 0.65, "editor camera leaves player behind panel")
	for pose in range(21):
		editor._on_posture_selected(pose)
		check(editor._current_def == editor._library.all_definitions()[pose], "selector uses wrong pose")
		check(editor._swing_visual.sample_heads.size() == 65, "swing trail missing samples")
		var authored = editor._current_def
		var contact = SwingPath.sample(authored, 0.5)
		check(is_equal_approx(contact.paddle_forehand_mul, authored.paddle_forehand_mul) and is_equal_approx(contact.paddle_y_offset, authored.paddle_y_offset), "curve misses authored contact")
		for progress in [0.0, 0.25, 0.5, 0.75, 1.0]:
			editor._swing_scrub.value = progress
			await process_frame
			var expected: Transform3D = SwingPath.world_transform(game.player_left, SwingPath.sample(authored, progress))
			check(game.player_left.paddle_node.global_position.distance_to(expected.origin) < 0.06, "scrubbed paddle does not follow curve")
		for section in range(5):
			editor._select_section(section)
			check(game.player_left.posture.transition_pose_blend != null, "missing preview pose%d section%d" % [pose, section])
			editor._apply_section_preview()
		# Exercise the actual shared slider/spin signal path, then restore this resource.
		editor._select_section(1)
		var field = editor._paddle_tab._widgets["paddle_pitch_base_deg"]
		var before: float = editor._current_def.paddle_pitch_base_deg
		var notifications: Array[float] = []
		var callback := func(value: float): notifications.append(value)
		field.value_changed.connect(callback)
		field._spin.value = before + 1.0 if before < 179.0 else before - 1.0
		check(notifications.size() == 1, "numeric edit emitted more than once")
		check(editor._dirty_defs.has(editor._dirty_key(editor._current_def)), "pose edit missing dirty state")
		check(not editor._save_button.disabled, "Save is disabled after an edit")
		check(editor._pose_picker.get_item_text(pose).begins_with("●"), "selector missing dirty marker")
		field.value_changed.disconnect(callback)
		editor._on_revert_pose()
		check(not editor._dirty_defs.has(editor._dirty_key(editor._current_def)), "Revert retains dirty state")
		check(is_equal_approx(editor._current_def.paddle_pitch_base_deg, before), "Revert failed to restore angle")
		# Loading boolean controls must never create an edit.
		editor._contact_tab.set_definition(editor._current_def)
		check(editor._dirty_defs.is_empty(), "loading contact controls dirties pose")
	# Wind-up edits update the wind-up preview rather than the contact position.
	editor._on_posture_selected(0)
	# Grip options exercise the real inspector signals and runtime support-arm targets.
	for hand in [0, 1]:
		var choice = editor._paddle_tab._widgets["paddle_hand"]
		choice.select(hand)
		choice.item_selected.emit(hand)
		check(game.player_left.posture.transition_pose_blend.paddle_hand == hand, "paddle-hand choice missing in preview")
		var support = editor._paddle_tab._widgets["left_hand_mode"]
		support.select(1)
		support.item_selected.emit(1)
		var grip: Vector3 = game.player_left.arm_ik.get_support_hand_target(editor._current_def)
		check(grip.distance_to(game.player_left.paddle_node.to_global(Vector3(0, 0.20, 0))) < 0.001, "both-hands choice fails to grip")
		support.select(4)
		support.item_selected.emit(4)
		var released: Vector3 = game.player_left.arm_ik.get_support_hand_target(editor._current_def)
		check(released.distance_to(grip) > 0.1, "Free mode still grips paddle")
	var path: String = "user://test_swing_grip_roundtrip.tres"
	check(ResourceSaver.save(editor._current_def, path) == OK, "grip save failed")
	var loaded = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(loaded.paddle_hand == 1 and loaded.left_hand_mode == 4 and is_equal_approx(loaded.swing_path_blend, editor._current_def.swing_path_blend), "grip and curve values fail to reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	editor._on_revert_pose()
	editor._on_posture_selected(1) # Verify switching between neck support and release on the authored left-hand backhand.
	var backhand = editor._current_def
	var free_choice = editor._paddle_tab._widgets["left_hand_mode"]
	free_choice.select(1)
	free_choice.item_selected.emit(1)
	var auto_target: Vector3 = game.player_left.arm_ik.get_support_hand_target(backhand)
	free_choice.select(4)
	free_choice.item_selected.emit(4)
	check(game.player_left.arm_ik.get_support_hand_target(backhand).distance_to(auto_target) > 0.1, "backhand ignores explicit released-hand choice")
	editor._on_revert_pose()
	editor._on_posture_selected(0)
	editor._on_preview_swing()
	check(editor._transition_player.is_playing(), "swing preview failed to play")
	editor._transition_player._current_phase = TransitionPlayer.Phase.CONTACT
	editor._transition_player._phase_time = editor._transition_player.phase_durations[TransitionPlayer.Phase.CONTACT] * 0.5
	editor._transition_player._apply_phase_pose()
	var moving = game.player_left.posture.transition_pose_blend
	check(is_equal_approx(moving.paddle_forward_mul, SwingPath.sample(editor._current_def, SwingPath.release_progress(editor._current_def, 0, 0.5)).paddle_forward_mul), "strike preview snaps instead of blending")
	editor._on_preview_pose()
	editor._select_section(2)
	var windup = editor._charge_tab._widgets["charge_paddle_offset"]
	windup._x_spin.value += 0.05
	var preview = game.player_left.posture.transition_pose_blend
	check(is_equal_approx(preview.paddle_forehand_mul, editor._current_def.paddle_forehand_mul + editor._current_def.charge_paddle_offset.x), "wind-up edit does not update preview")
	editor._on_revert_pose()
	# Base poses have only body settings; selection and editing must be safe for every pose.
	editor._on_toggle_workspace()
	check(editor._pose_picker.item_count == 22, "body selector must contain all 22 poses")
	for pose in range(editor._pose_picker.item_count):
		editor._on_posture_selected(pose)
		check(game.player_left.posture.transition_pose_blend != null, "missing body preview")
		check(editor._section_picker.is_item_disabled(1), "body pose exposes paddle section")
		var field = editor._body_tab._widgets["stance_width"]
		var before: float = editor._current_def.stance_width
		field._spin.value = before + 0.01
		check(editor._dirty_defs.has(editor._dirty_key(editor._current_def)), "body edit is not dirty")
		editor._on_revert_pose()
		check(is_equal_approx(editor._current_def.stance_width, before), "body revert failed")
	await process_frame
	check(editor.get_global_rect().encloses(editor._save_button.get_global_rect()), "Save button outside panel")
	check(editor._tab_container.size.y > 100, "inspector has no room for controls")
	editor.close()
	check(not editor.visible and not game.camera_rig.editor_active, "editor did not close")
	check(game.ball.freeze == false and game.ball.is_physics_processing(), "ball failed to resume")
	check(game.player_left.is_physics_processing(), "human failed to resume")
	check(game.camera_rig.camera.transform.is_equal_approx(camera_transform), "game camera was not restored")
	game._toggle_sound_panel()
	check(game.game_sound_tune.sound_tune_panel.visible, "sound panel did not open")
	game._toggle_posture_editor_v2()
	check(not game.game_sound_tune.sound_tune_panel.visible and editor.visible, "sound and editor overlap")
	editor._on_toggle_workspace()
	editor._on_posture_selected(0)
	editor._paddle_tab._widgets["paddle_pitch_base_deg"]._spin.value += 1
	check(game.close_active_tool(), "Escape cannot close active tool")
	check(editor._save_dialog.visible and editor.visible, "unsaved close did not show prompt")
	check(pause_controller._menu == null, "pause menu overlaps unsaved prompt")
	editor._save_dialog.hide()
	editor._on_revert_pose()
	editor.close()
	pause_controller.open()
	pause_controller._menu._on_settings()
	check(not pause_controller._menu._panel.visible, "pause controls overlap settings")
	var settings = pause_controller._menu._settings_overlay
	check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(settings._panel.get_global_rect()), "settings extends off screen")
	check(pause_controller._menu.close_settings(), "settings back does not close settings")
	check(pause_controller._menu._panel.visible, "settings back did not restore pause menu")
	pause_controller.close()
	game.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("GAME UI FLOW: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
