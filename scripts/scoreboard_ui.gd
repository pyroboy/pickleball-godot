extends Node
class_name ScoreboardUI





var _hud: CanvasLayer


var _rally_visible_timer: float = 0.0
var _rally_generation: int = -1
var _shot_type_timer: float = 0.0
var _fault_visible_timer: float = 0.0
var _zone_visible_timer: float = 0.0
var _speed_visible_timer: float = 0.0
var _preparation_guidance_text: = ""
var _game: Node

const AI_DIFFICULTY_NAMES: Array[String] = ["EASY", "MEDIUM", "HARD"]
const AI_DIFFICULTY_COLORS: Array[Color] = [Color(0.4, 1.0, 0.4), Color(1.0, 0.85, 0.3), Color(1.0, 0.35, 0.35)]

func setup(hud: CanvasLayer) -> void :
	_hud = hud

	_game = get_parent() if get_parent() and get_parent().has_method("_format_serve_call") else null

	if _hud != null:
		_hide_temporary_ui()

func _process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_process(delta)
	PerfMonitor.record("proc.scoreboard_ui", Time.get_ticks_usec() - _pt)

func _perf_process(delta: float) -> void:
	_update_shot_type_fade(delta)
	_update_timers(delta)
	_sync_match_context()
	_sync_preparation_guidance()

func update_score(score_l: int, score_r: int) -> void :
	if _hud and _hud.get("score"):
		if _hud.has_method("set_score"):
			_hud.set_score(score_l, score_r)
		else:
			_hud.score.text = "%d - %d" % [score_l, score_r]
	_sync_match_context()

func set_spin_selection(mode: String, locked_mode: String = "", intent: String = "AUTO", locked_intent: String = "") -> void :
	if is_instance_valid(_hud) and _hud.has_method("set_spin_selection"):
		_hud.set_spin_selection(mode, locked_mode, intent, locked_intent)

func set_state_text(text: String) -> void :
	if _hud and _hud.get("state"):
		if _hud.has_method("set_status_text"): _hud.set_status_text(text)
		else: _hud.state.text = text
	_sync_match_context()

func update_difficulty(difficulty: int) -> void :
	if _hud and _hud.get("difficulty"):
		var label: Label = _hud.difficulty
		var index: = clampi(difficulty, 0, AI_DIFFICULTY_NAMES.size() - 1)
		label.text = "AI: " + AI_DIFFICULTY_NAMES[index] + "  [X]"
		label.add_theme_color_override("font_color", Hud.AI_DIFFICULTY_COLORS[index])

func show_rally_result(winner: int, side_out: bool, complete: bool = false) -> void:
	if not is_instance_valid(_hud) or not is_instance_valid(_game): return
	var owner: String = _hud.team_name(winner)
	var headline := "Sideout" if side_out else "Point!"
	var detail := "%s serve · score unchanged" % owner if side_out else "%s +1 · %d – %d" % [owner, _game.score_left, _game.score_right]
	if _game.get("doubles_mode") == true and not complete:
		var outcome: Dictionary = _game.doubles_controller.last_outcome
		if not bool(outcome.get("point_scored", false)):
			headline = "Sideout" if side_out else "Second server"
			detail = "%s serves · %s" % [_game.actor_label(_game.get_server_actor()), _game.doubles_state.score_call()]
	if complete:
		headline = "%s win%s!" % [owner, "" if owner in ["You", "Opponents"] else "s"]
		detail = "Final · %d – %d" % [_game.score_left, _game.score_right]
	_hud.show_rally_result(headline, detail)
	_rally_visible_timer = 2.8
	_rally_generation = _game._point_reset_generation
	_sync_match_context()

func clear_rally_result() -> void:
	_rally_visible_timer = 0.0
	if is_instance_valid(_hud): _hud.clear_rally_result()

func show_fault(headline: String, detail: String) -> void :
	if _hud and _hud.get("fault"):
		_hud.fault.text = "%s\n%s" % [headline, detail]
		_hud.fault.modulate.a = 1.0
		_hud.fault.visible = true
		_fault_visible_timer = 2.5

func clear_fault() -> void :
	_fault_visible_timer = 0.0
	if is_instance_valid(_hud) and _hud.get("fault"):
		_hud.fault.visible = false

func show_out(text: String = "OUT!") -> void :
	if _hud and _hud.get("out_text"):
		_hud.out_text.text = text
		_hud.out_text.modulate.a = 1.0
		_hud.out_text.visible = true
	if _hud and _hud.get("zone"):
		_hud.zone.visible = false

func hide_out() -> void :
	if _hud and _hud.get("out_text"):
		_hud.out_text.visible = false

func show_zone(zone_name: String) -> void :
	if _hud and _hud.get("zone"):
		_hud.zone.text = zone_name
		_hud.zone.modulate.a = 1.0
		_hud.zone.visible = true
		_zone_visible_timer = 2.0


func show_speed(speed_mph: float) -> void :
	if _hud and _hud.get("speed"):
		_hud.speed.text = "%.1f mph" % speed_mph
		_hud.speed.modulate.a = 1.0
		_speed_visible_timer = 3.5

func show_shot_type(shot_name: String) -> void :
	if _hud and _hud.get("shot_type"):
		var label: Label = _hud.shot_type
		label.text = shot_name
		_apply_shot_type_color(label, shot_name)
		label.modulate.a = 1.0
		_shot_type_timer = 2.5

func update_debug_content(content: String) -> void :
	if _hud and _hud.get("debug"):
		_hud.debug.text = content

func update_posture_debug(content: String) -> void :
	if _hud and _hud.get("posture_debug"):
		_hud.posture_debug.text = content

func set_debug_visuals_active(active: bool) -> void :
	if _hud:
		if _hud.get("zone"): _hud.zone.visible = active
		if _hud.get("posture_debug"): _hud.posture_debug.visible = active
		if _hud.get("debug"): _hud.debug.visible = active

func hide_all_hud() -> void :
	_hide_temporary_ui()
	if _hud:
		if _hud.has_method("set_gameplay_elements_visible"):
			_hud.set_gameplay_elements_visible(false)
		else:
			_hud.visible = false

func show_all_hud() -> void :
	if _hud:
		if _hud.has_method("set_gameplay_elements_visible"):
			_hud.set_gameplay_elements_visible(true)
		else:
			_hud.visible = true
	_sync_match_context()


func _apply_shot_type_color(label: Label, shot_name: String) -> void :
	match shot_name:
		"FAST", "SMASH":
			label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.15, 1.0))
		"VOLLEY":
			label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2, 1.0))
		"DROP", "DINK":
			label.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0, 1.0))
		"LOB":
			label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2, 1.0))
		"RETURN":
			label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7, 1.0))
		_:
			label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))

func _update_shot_type_fade(delta: float) -> void :
	if _shot_type_timer <= 0.0: return
	_shot_type_timer -= delta
	if _hud and _hud.get("shot_type"):
		var label = _hud.shot_type
		if _shot_type_timer <= 0.6:
			label.modulate.a = clampf(_shot_type_timer / 0.6, 0.0, 1.0)
		else:
			label.modulate.a = 1.0

func _update_timers(delta: float) -> void :
	if not is_instance_valid(_hud): return
	if _rally_visible_timer > 0.0:
		if not is_instance_valid(_game) or _rally_generation != _game._point_reset_generation or _game._is_practice() or not _hud._gameplay_visible:
			clear_rally_result()
		else:
			_rally_visible_timer = maxf(0.0, _rally_visible_timer - delta)
			_hud._rally_banner.modulate.a = clampf(_rally_visible_timer / 0.3, 0.0, 1.0)
			if _rally_visible_timer == 0.0: clear_rally_result()
	if _speed_visible_timer > 0.0:
		_speed_visible_timer = maxf(0.0, _speed_visible_timer - delta)
		if _hud.get("speed"):
			_hud.speed.modulate.a = clampf(_speed_visible_timer / 0.6, 0.0, 1.0)
	if _fault_visible_timer > 0:
		_fault_visible_timer -= delta
		if _fault_visible_timer <= 0:
			if _hud.get("fault"): _hud.fault.visible = false

	if _zone_visible_timer > 0:
		_zone_visible_timer -= delta
		if _zone_visible_timer <= 0:
			if _hud.get("zone"): _hud.zone.visible = false

func _hide_temporary_ui() -> void :
	# Dismiss the events as well as their pixels. Otherwise the next timer tick
	# restores old feedback when a tool closes or a practice feed is reset.
	_shot_type_timer = 0.0
	_speed_visible_timer = 0.0
	_fault_visible_timer = 0.0
	_zone_visible_timer = 0.0
	clear_rally_result()
	if not is_instance_valid(_hud): return
	if _hud.get("fault"): _hud.fault.visible = false
	if _hud.get("out_text"): _hud.out_text.visible = false
	if _hud.get("zone"): _hud.zone.visible = false
	if _hud.get("shot_type"): _hud.shot_type.modulate.a = 0.0
	if _hud.get("speed"): _hud.speed.modulate.a = 0.0

func _sync_match_context() -> void :
	if not is_instance_valid(_hud) or not is_instance_valid(_game): return
	if _hud.has_method("set_match_context"):
		_hud.set_match_context(_game.serving_team, _game.game_state in [1, 2])
	if _hud.has_method("set_charge"):
		var input = _game.get("input_handler")
		var serve = _game.get("game_serve")
		var charging: = false
		var ratio: = 0.0
		if input and input.serve_is_charging:
			charging = true
			ratio = input.serve_charge_time / PickleballConstants.MAX_SERVE_CHARGE_TIME
		elif serve and serve.is_charging():
			charging = true
			ratio = serve.get_charge_ratio()
		_hud.set_charge(ratio, charging)

func _sync_preparation_guidance() -> void :
	if not is_instance_valid(_hud) or not is_instance_valid(_game): return
	var value: = ""
	if _game.game_state == _game.GameState.PLAYING and not _game._tool_state_active() and not _game.match_over:
		var human = _game.player_left.posture.human_contact
		if human != null: value = human.preparation_status_text()
		if not value.is_empty() and not _hud._portrait and _game.player_left.hitting.charge_visual_active and human.phase < 0:
			value += "\nRelease SPACE to queue"
	if not value.is_empty():
		_preparation_guidance_text = value
		_hud.set_status_text(value)
	elif not _preparation_guidance_text.is_empty():


		if _hud.state.text == _preparation_guidance_text:
			_hud.set_status_text("Rally!" if _game.game_state == _game.GameState.PLAYING else "")
		_preparation_guidance_text = ""
