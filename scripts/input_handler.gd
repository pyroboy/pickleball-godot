extends Node
class_name InputHandler
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")





var _game: Node
var _ball: RigidBody3D
var _player_left: CharacterBody3D
var _player_right: CharacterBody3D
var _camera_rig: Node
var _practice: Node
var _sound_panel: Control
var _reaction_button: Node


const MAX_SERVE_CHARGE_TIME: = PickleballConstants.MAX_SERVE_CHARGE_TIME
const SERVE_AIM_STEP: = PickleballConstants.SERVE_AIM_STEP
const SERVE_AIM_MAX: = PickleballConstants.SERVE_AIM_MAX
const ARC_INTENT_STEP: = PickleballConstants.ARC_INTENT_STEP
const ARC_INTENT_MIN: = PickleballConstants.ARC_INTENT_MIN
const ARC_INTENT_MAX: = PickleballConstants.ARC_INTENT_MAX


var _swing_was_pressed: bool = false
var _transition_release_required: bool = false
var _last_control_usec: int = 0


var _deferred_rally_hold: bool = false
var serve_is_charging: bool = false
var serve_charge_time: float = 0.0
var serve_aim_offset_x: float = 0.0
var trajectory_arc_offset: float = 0.0


var _key_states: Dictionary = {}
var _sound_test_states: Dictionary = {}

func setup(game: Node, ball: RigidBody3D, p_left: CharacterBody3D, p_right: CharacterBody3D, camera: Node, practice: Node, sound_panel: Control, reaction: Node) -> void :
	_game = game
	_ball = ball
	_player_left = p_left
	_player_right = p_right
	_camera_rig = camera
	_practice = practice
	_sound_panel = sound_panel
	_reaction_button = reaction

func _process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_process(delta)
	PerfMonitor.record("proc.input_handler", Time.get_ticks_usec() - _pt)

func _perf_process(delta: float) -> void:
	var control_delta: float = _control_delta(delta, Time.get_ticks_usec())
	if _game != null and _game._point_transition_blocks_attempt():
		latch_transition_input()
		return
	if _transition_release_required:
		_swing_was_pressed = Input.is_action_pressed("ui_accept")
		_transition_release_required = _swing_was_pressed
		return
	_handle_debug_toggles()
	if _game and _game.aim_controller:
		var mobile = _game.mobile_controls
		var separate_aim: bool = mobile != null and mobile.uses_touch_aim()
		var direction: Vector2 = mobile.aim_direction() if separate_aim else Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if _game.view_flipped(): direction = -direction   # screen-relative aim at the far end
		var _ta := Time.get_ticks_usec()
		_game.aim_controller.update(control_delta, Input.is_action_pressed("ui_accept"), direction, separate_aim)
		PerfMonitor.record("input.aim", Time.get_ticks_usec() - _ta)
	if _sound_panel and _sound_panel.visible:
		_deferred_rally_hold = false
		serve_is_charging = false
		serve_charge_time = 0.0
		_swing_was_pressed = Input.is_action_pressed("ui_accept")
		_handle_sound_controls()
		_game.game_sound_tune._handle_sound_panel_input()
		return
	_handle_camera_and_movement_controls()
	_handle_practice_controls()
	_handle_sound_controls()
	var _tb := Time.get_ticks_usec()
	_update_aim_and_arc(delta)
	PerfMonitor.record("input.arc", Time.get_ticks_usec() - _tb)
	var _tc := Time.get_ticks_usec()
	_handle_swing_charge(control_delta)
	PerfMonitor.record("input.charge", Time.get_ticks_usec() - _tc)

func latch_transition_input() -> void:
	# No repeated cleanup/pose mutation: wait for release of a covered press.
	_swing_was_pressed = Input.is_action_pressed("ui_accept")
	_transition_release_required = _swing_was_pressed
	_deferred_rally_hold = false
	serve_is_charging = false
	serve_charge_time = 0.0
	_last_control_usec = Time.get_ticks_usec()

func _control_delta(world_delta: float, now_usec: int) -> float:
	var previous_usec: int = _last_control_usec
	_last_control_usec = now_usec
	if _game and _game.aim_focus and _game.aim_focus.holding and _game.aim_focus.is_solo():




		previous_usec = maxi(previous_usec, _game.aim_focus.started_usec)
		return maxf(0.0, float(now_usec - previous_usec) / 1000000.0)
	return world_delta

func _handle_debug_toggles() -> void :
	if not RuntimePolicy.developer_tools: return

	if _game._tool_state_active():
		return
	if _just_pressed(KEY_X):
		_game._cycle_difficulty()
	if _just_pressed(KEY_N):
		_game._toggle_intent_indicators()
	if not _game.hud.debug_mode: return
	if _just_pressed(KEY_T):
		_game._start_drop_test()
	if _just_pressed(KEY_Z):
		_game._cycle_debug_visuals()
	if _just_pressed(KEY_5):
		_game._toggle_ball_freeze()

func _unhandled_key_input(event: InputEvent) -> void :
	if _game != null and _game._point_transition_blocks_attempt(): return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.ctrl_pressed or event.meta_pressed or event.alt_pressed:
		return
	if event.keycode == KEY_F3:
		_game.hud.toggle_debug_mode()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F2 and _game.hud.debug_available and not _game.hud._portrait and not OS.has_feature("mobile"):
		_game.hud.set_debug_mode(true)
		_game.open_mobile_pose_editor()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_E:
		if _game and not _game._tool_state_active():
			_game.select_drop_shot()
			get_viewport().set_input_as_handled()
	elif event.keycode == KEY_Q:

		if _game and not _game._tool_state_active():
			_game.cycle_spin_mode()
			get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT]:
		if _game and not _game._tool_state_active() and _game.game_state == 0 and _game.human_may_serve():
			_game.aim_controller.nudge(Vector2(-1 if event.keycode == KEY_BRACKETLEFT else 1, 0), 0.035)
			get_viewport().set_input_as_handled()
	elif event.keycode == KEY_M and _game.hud.debug_mode:
		_game._toggle_sound_panel()
		get_viewport().set_input_as_handled()

func _handle_camera_and_movement_controls() -> void :
	if _just_pressed(KEY_O) and _camera_rig:
		if _camera_rig.has_method("toggle_auto_orbit"): _camera_rig.toggle_auto_orbit()


	if _just_pressed(KEY_P) and _camera_rig:
		if _camera_rig.has_method("cycle_third_person"): _camera_rig.cycle_third_person()

	if _just_pressed(KEY_C) and _player_left:
		_player_left.manual_crouch = not _player_left.manual_crouch
		if RuntimePolicy.developer_tools: print("[CROUCH] ", "ON" if _player_left.manual_crouch else "OFF")

func _handle_practice_controls() -> void :
	if not _practice or not _game.hud.debug_mode: return
	if _just_pressed(KEY_4): _practice.launch_ball()
	if _just_pressed(KEY_1): _practice.toggle_auto_hit()
	if _just_pressed(KEY_2): _practice.toggle_loop()

func _handle_sound_controls() -> void :
	if not _game.hud.debug_mode: return

	_test_sound(KEY_6, "6", "paddle", 0)
	_test_sound(KEY_7, "7", "paddle", 1)
	_test_sound(KEY_8, "8", "paddle", 2)
	_test_sound(KEY_Y, "Y", "court", 0)
	_test_sound(KEY_U, "U", "court", 1)
	_test_sound(KEY_I, "I", "court", 2)

func _test_sound(keycode: int, key_name: String, sound_type: String, idx: int) -> void :
	var pressed = Input.is_key_pressed(keycode)
	var was = _sound_test_states.get(key_name, false)
	if pressed and not was and _ball and _ball.get("audio_synth"):
		if sound_type == "paddle": _ball.audio_synth.play_test_paddle_sound(idx)
		else: _ball.audio_synth.play_test_court_sound(idx)
	_sound_test_states[key_name] = pressed

## Seconds of hold for full power: rally shots build up over RALLY_FULL_HOLD (1 s), the
## serve keeps its short MAX_SERVE_CHARGE_TIME.
func _full_hold() -> float:
	return PickleballConstants.RALLY_FULL_HOLD if _game and _game.game_state == 2 else MAX_SERVE_CHARGE_TIME

func _handle_swing_charge(delta: float) -> void :
	var held_now: bool = Input.is_action_pressed("ui_accept")
	if not held_now: _deferred_rally_hold = false

	if _game and _game.game_state == 1:
		_deferred_rally_hold = false
		serve_is_charging = false
		serve_charge_time = 0.0
		_swing_was_pressed = Input.is_action_pressed("ui_accept")
		return
	if _game and _game.game_state == 2 and _player_left and _player_left.posture:
		var human = _player_left.posture.human_contact
		if human != null and human.phase >= 0:
			if held_now and not _swing_was_pressed and human.phase >= 2 and human.hit:
				_deferred_rally_hold = true


				if _game.aim_focus: _game.aim_focus.begin_hold()
			serve_is_charging = false
			serve_charge_time = 0.0
			_swing_was_pressed = Input.is_action_pressed("ui_accept")
			return

	var swing_pressed: bool = Input.is_action_pressed("ui_accept")
	if swing_pressed and ( not _swing_was_pressed or _deferred_rally_hold):
		_deferred_rally_hold = false
		serve_is_charging = true
		serve_charge_time = 0.0
		if _game.has_method("_on_player_swing_press"):
			_game._on_player_swing_press()

	_swing_was_pressed = swing_pressed
	if serve_is_charging:
		if swing_pressed:
			serve_charge_time = min(serve_charge_time + delta, _full_hold())
			var charge_ratio = minf(serve_charge_time / _full_hold(), 1.0)
			if _player_left: _player_left.set_serve_charge_visual(charge_ratio, delta)
			if _game.has_method("_update_charge_ui"):
				_game._update_charge_ui(charge_ratio, _player_left != null)
			elif _game.get("game_serve") and _game.game_serve.has_method("_update_charge_ui"):
				_game.game_serve._update_charge_ui(charge_ratio)
		else:

			serve_is_charging = false
			var ratio = minf(serve_charge_time / _full_hold(), 1.0)
			serve_charge_time = 0.0


			if _game.ai_difficulty == 0 and _reaction_button and _reaction_button.has_method("is_perfect") and _reaction_button.is_perfect():
				if _reaction_button.has_method("trigger_perfect_flash"): _reaction_button.trigger_perfect_flash()
				if RuntimePolicy.developer_tools: print("[INPUT] PERFECT timing; chosen power preserved")

			if _game.has_method("_on_player_swing_release"):
				_game._on_player_swing_release(ratio)
			trajectory_arc_offset = 0.0

func _update_aim_and_arc(delta: float) -> void :


	if _game.game_state == 0 and _game.human_may_serve():
		var lateral: float = float(Input.is_key_pressed(KEY_BRACKETRIGHT)) - float(Input.is_key_pressed(KEY_BRACKETLEFT))
		_game.aim_controller.nudge(Vector2(lateral, 0), delta)
		serve_aim_offset_x = _game.aim_controller.get_target().x
		_game._update_waiting_ui()


	var raise = Input.is_key_pressed(KEY_R)
	var lower = Input.is_key_pressed(KEY_F)

	if serve_is_charging:
		if raise and not _key_states.get(KEY_R, false):
			trajectory_arc_offset = clamp(trajectory_arc_offset + ARC_INTENT_STEP, ARC_INTENT_MIN, ARC_INTENT_MAX)
		if lower and not _key_states.get(KEY_F, false):
			trajectory_arc_offset = clamp(trajectory_arc_offset - ARC_INTENT_STEP, ARC_INTENT_MIN, ARC_INTENT_MAX)

	_key_states[KEY_R] = raise
	_key_states[KEY_F] = lower
	if _game and _game.human_may_serve():
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


func cancel_charge_input() -> void :
	_deferred_rally_hold = false

	serve_is_charging = false
	serve_charge_time = 0.0
	_swing_was_pressed = Input.is_action_pressed("ui_accept")
	trajectory_arc_offset = 0.0
	if not is_instance_valid(_game): return
	if _game.aim_focus: _game.aim_focus.cancel()
	if _game.game_state == 0 and _game.game_serve: _game.game_serve.cleanup(true)
	_game.serve_is_charging = false
	_game.serve_charge_time = 0.0
	if _game.aim_controller: _game.aim_controller.reset()
	if _player_left and _player_left.hitting: _player_left.hitting.clear_charge_visual()
	if _game.hud: _game.hud.set_charge(0.0, false)
