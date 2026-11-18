extends Node
class_name InputHandler

## InputHandler.gd - Centralizes all player input, hotkeys, and debug toggles.
## Manages serve/swing charging, aiming, and delegation to game modules.

# Dependencies
var _game: Node
var _ball: RigidBody3D
var _player_left: CharacterBody3D
var _player_right: CharacterBody3D
var _camera_rig: Node
var _practice: Node
var _posture_editor: Control
var _sound_panel: Control
var _reaction_button: Node

# Constants (mirroring PickleballConstants for local logic)
const MAX_SERVE_CHARGE_TIME := PickleballConstants.MAX_SERVE_CHARGE_TIME
const SERVE_AIM_STEP := PickleballConstants.SERVE_AIM_STEP
const SERVE_AIM_MAX := PickleballConstants.SERVE_AIM_MAX
const ARC_INTENT_STEP := PickleballConstants.ARC_INTENT_STEP
const ARC_INTENT_MIN := PickleballConstants.ARC_INTENT_MIN
const ARC_INTENT_MAX := PickleballConstants.ARC_INTENT_MAX

# State
var _swing_was_pressed: bool = false
var serve_is_charging: bool = false
var serve_charge_time: float = 0.0
var serve_aim_offset_x: float = 0.0
var trajectory_arc_offset: float = 0.0

# Key tracking states
var _key_states: Dictionary = {}
var _sound_test_states: Dictionary = {}

func setup(game: Node, ball: RigidBody3D, p_left: CharacterBody3D, p_right: CharacterBody3D, camera: Node, practice: Node, editor: Control, sound_panel: Control, reaction: Node) -> void:
	_game = game
	_ball = ball
	_player_left = p_left
	_player_right = p_right
	_camera_rig = camera
	_practice = practice
	_posture_editor = editor
	_sound_panel = sound_panel
	_reaction_button = reaction

func _process(delta: float) -> void:
	_handle_debug_toggles()
	if _sound_panel and _sound_panel.visible:
		serve_is_charging = false
		serve_charge_time = 0.0
		_swing_was_pressed = Input.is_action_pressed("ui_accept")
		_handle_sound_controls()
		_game.game_sound_tune._handle_sound_panel_input()
		return
	var editor_v2 = _game.get("posture_editor_v2") if _game else null
	if editor_v2 and editor_v2.visible:
		serve_is_charging = false
		serve_charge_time = 0.0
		_swing_was_pressed = Input.is_action_pressed("ui_accept")
		if _player_left and _player_left.hitting:
			_player_left.hitting.clear_charge_visual()
		return
	_handle_camera_and_movement_controls()
	_handle_practice_controls()
	_handle_sound_controls()
	_handle_swing_charge(delta)
	_update_aim_and_arc(delta)

func _handle_debug_toggles() -> void:
	# Tool hotkeys use events below so a quick press cannot disappear between frames.
	if _game._tool_state_active():
		return
	if _just_pressed(KEY_T):
		_game._start_drop_test()
	if _just_pressed(KEY_X):
		_game._cycle_difficulty()
	if _just_pressed(KEY_Z):
		_game._cycle_debug_visuals()
	if _just_pressed(KEY_N):
		_game._toggle_intent_indicators()
	if _just_pressed(KEY_5):
		_game._toggle_ball_freeze()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.ctrl_pressed or event.meta_pressed or event.alt_pressed:
		return
	if event.keycode in [KEY_E, KEY_Q]:
		_game._toggle_posture_editor_v2()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_M:
		_game._toggle_sound_panel()
		get_viewport().set_input_as_handled()

func _handle_camera_and_movement_controls() -> void:
	var editor_v2 = _game.get("posture_editor_v2") if _game else null
	if editor_v2 and editor_v2.visible:
		return
	# O key toggles auto-orbit even in editor mode (camera still orbits in editor)
	if _just_pressed(KEY_O) and _camera_rig:
		if _camera_rig.has_method("toggle_auto_orbit"): _camera_rig.toggle_auto_orbit()
	
	# P and C are gameplay-only; skip when posture editor is open
	if _posture_editor and _posture_editor.visible:
		return

	if _just_pressed(KEY_P) and _camera_rig:
		if _camera_rig.has_method("cycle_third_person"): _camera_rig.cycle_third_person()
		
	if _just_pressed(KEY_C) and _player_left:
		_player_left.manual_crouch = not _player_left.manual_crouch
		print("[CROUCH] ", "ON" if _player_left.manual_crouch else "OFF")

func _handle_practice_controls() -> void:
	if not _practice: return
	if _just_pressed(KEY_4): _practice.launch_ball()
	if _just_pressed(KEY_1): _practice.toggle_auto_hit()
	if _just_pressed(KEY_2): _practice.toggle_loop()

func _handle_sound_controls() -> void:
	# Sound test triggers (6-8, Y, U, I)
	_test_sound(KEY_6, "6", "paddle", 0)
	_test_sound(KEY_7, "7", "paddle", 1)
	_test_sound(KEY_8, "8", "paddle", 2)
	_test_sound(KEY_Y, "Y", "court", 0)
	_test_sound(KEY_U, "U", "court", 1)
	_test_sound(KEY_I, "I", "court", 2)

func _test_sound(keycode: int, key_name: String, sound_type: String, idx: int) -> void:
	var pressed = Input.is_key_pressed(keycode)
	var was = _sound_test_states.get(key_name, false)
	if pressed and not was and _ball and _ball.get("audio_synth"):
		if sound_type == "paddle": _ball.audio_synth.play_test_paddle_sound(idx)
		else: _ball.audio_synth.play_test_court_sound(idx)
	_sound_test_states[key_name] = pressed

func _handle_swing_charge(delta: float) -> void:
	if _posture_editor and _posture_editor.visible:
		serve_is_charging = false
		serve_charge_time = 0.0
		_swing_was_pressed = Input.is_action_pressed("ui_accept")
		if _player_left and _player_left.hitting:
			_player_left.hitting.clear_charge_visual()
		return

	var swing_pressed: bool = Input.is_action_pressed("ui_accept")
	if swing_pressed and not _swing_was_pressed:
		serve_is_charging = true
		serve_charge_time = 0.0
		if _game.has_method("_on_player_swing_press"):
			_game._on_player_swing_press()
			
	_swing_was_pressed = swing_pressed
	if serve_is_charging:
		if swing_pressed:
			serve_charge_time = min(serve_charge_time + delta, MAX_SERVE_CHARGE_TIME)
			var charge_ratio = serve_charge_time / MAX_SERVE_CHARGE_TIME
			if _player_left: _player_left.set_serve_charge_visual(charge_ratio)
			if _game.has_method("_update_charge_ui"):
				_game._update_charge_ui(charge_ratio)
			elif _game.get("game_serve") and _game.game_serve.has_method("_update_charge_ui"):
				_game.game_serve._update_charge_ui(charge_ratio)
		else:
			# Released
			serve_is_charging = false
			var ratio = serve_charge_time / MAX_SERVE_CHARGE_TIME
			serve_charge_time = 0.0
			
			# Check for perfect reaction bonus (Easy mode)
			if _game.ai_difficulty == 0 and _reaction_button and _reaction_button.has_method("is_perfect") and _reaction_button.is_perfect():
				ratio = 1.0
				if _reaction_button.has_method("trigger_perfect_flash"): _reaction_button.trigger_perfect_flash()
				print("[INPUT] PERFECT window bonus applied")
				
			if _game.has_method("_on_player_swing_release"):
				_game._on_player_swing_release(ratio)
			trajectory_arc_offset = 0.0

func _update_aim_and_arc(delta: float) -> void:
	# Ignore if posture editor is visible
	if _posture_editor and _posture_editor.visible:
		return
		
	# Serve aiming ([ / ])
	if _game.game_state == 0: # WAITING
		if Input.is_key_pressed(KEY_BRACKETLEFT):
			serve_aim_offset_x = clamp(serve_aim_offset_x - SERVE_AIM_STEP * delta * 10.0, -SERVE_AIM_MAX, SERVE_AIM_MAX)
		elif Input.is_key_pressed(KEY_BRACKETRIGHT):
			serve_aim_offset_x = clamp(serve_aim_offset_x + SERVE_AIM_STEP * delta * 10.0, -SERVE_AIM_MAX, SERVE_AIM_MAX)
		_game._update_waiting_ui()

	# Arc intent (R/F)
	var raise = Input.is_key_pressed(KEY_R)
	var lower = Input.is_key_pressed(KEY_F)
	
	if serve_is_charging:
		if raise and not _key_states.get(KEY_R, false):
			trajectory_arc_offset = clamp(trajectory_arc_offset + ARC_INTENT_STEP, ARC_INTENT_MIN, ARC_INTENT_MAX)
		if lower and not _key_states.get(KEY_F, false):
			trajectory_arc_offset = clamp(trajectory_arc_offset - ARC_INTENT_STEP, ARC_INTENT_MIN, ARC_INTENT_MAX)
	
	_key_states[KEY_R] = raise
	_key_states[KEY_F] = lower
	if _game and _game.serving_team == 0:
		_game.serve_aim_offset_x = serve_aim_offset_x
		_game.trajectory_arc_offset = trajectory_arc_offset
		if _game.game_serve:
			_game.game_serve.set_aim_offset(serve_aim_offset_x)
			_game.game_serve.set_arc_offset(trajectory_arc_offset)

func _just_pressed(keycode: int) -> bool:
	var pressed = Input.is_key_pressed(keycode)
	var was = _key_states.get(keycode, false)
	_key_states[keycode] = pressed
	return pressed and not was
