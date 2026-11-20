extends Node
class_name ScoreboardUI





var _hud: CanvasLayer


var _rally_visible_timer: float = 0.0
var _rally_generation: int = -1
var _shot_type_timer: float = 0.0
var _fault_visible_timer: float = 0.0
var _fault_edge: Color = Color("ff8f80")
var _fault_font: int = 34
var _zone_visible_timer: float = 0.0
var _speed_visible_timer: float = 0.0
var _preparation_guidance_text: = ""
var _game: Node
var _context_key: Array = []
var _context_portrait: = false

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
	# Name the team every time, in its colour: who won the rally and what changed.
	var owner: String = _hud.team_name(winner)
	var other: String = _hud.team_name(1 - winner) if winner in [0, 1] else ""
	var color: Color = Color("4eb8ff") if winner == 0 else Color("ff6278")
	var plural: bool = owner not in ["You", "Opponents"]   # "Your team scores", "Opponents score"
	var score_line := "%s %d  –  %d %s" % [_hud.team_name(0), _game.score_left, _game.score_right, _hud.team_name(1)]
	var headline := "SIDE OUT" if side_out else ("%s SCORE%s" % [owner.to_upper(), "S" if plural else ""])
	var detail := ("%s serve%s now" % [owner, "s" if plural else ""]) if side_out else score_line
	if _game.get("doubles_mode") == true and not complete:
		var outcome: Dictionary = _game.doubles_controller.last_outcome
		if not bool(outcome.get("point_scored", false)):
			if side_out:
				headline = "SIDE OUT"
				detail = "%s serve%s now" % [owner, "s" if plural else ""]
			else:
				# Serving team lost the rally but keeps serve: the winner did NOT score.
				color = Color("ffd25a")
				headline = "SECOND SERVER"
				detail = "%s win%s the rally · %s keep%s serving" % [owner, "s" if plural else "", other, "s" if other not in ["You", "Opponents"] else ""]
		else:
			detail = score_line
	if complete:
		headline = "%s WIN%s!" % [owner.to_upper(), "S" if plural else ""]
		detail = "Final · " + score_line
	_hud.show_rally_result(headline, detail, color)
	_rally_visible_timer = 2.8
	_rally_generation = _game._point_reset_generation
	_sync_match_context()

func clear_rally_result() -> void:
	_rally_visible_timer = 0.0
	if is_instance_valid(_hud): _hud.clear_rally_result()

## tone: 1 the human's side won the point, -1 it lost, 0 neutral (classic red).
func show_fault(headline: String, detail: String, tone: int = 0) -> void :
	if tone != 0 and is_instance_valid(_hud) and _hud.has_method("set_rally_reason"):
		# With a human playing, the reason joins the result banner (one banner,
		# not two): headline, this short line, then the score.
		_hud.set_rally_reason(detail, Color("bde879") if tone > 0 else Color("ff8f80"))
		if _hud.get("fault"): _hud.fault.visible = false
		_fault_visible_timer = 0.0
		return
	if _hud and _hud.get("fault"):
		# With a human playing, the result banner already says whose point it was:
		# show only the short friendly reason.
		_hud.fault.text = detail if tone != 0 else "%s\n%s" % [headline, detail]
		_hud.fault.add_theme_color_override("font_color", Color("bde879") if tone > 0 else Color("ff8f80"))
		_fault_edge = Color("bde879") if tone > 0 else Color("ff8f80")
		_fault_font = 34 if tone == 0 else 28
		_place_fault_banner(_fault_edge, _fault_font)
		_hud.fault.modulate.a = 1.0
		_hud.fault.visible = true
		_fault_visible_timer = 2.5

## The reason sits in a dark panel, centred, with its bottom edge just above the
## net on screen, so it is readable over the court and clear of the players' feet.
func _place_fault_banner(edge: Color, font_size: int) -> void:
	var label: Label = _hud.fault
	var layout = preload("res://scripts/ui/mobile_layout.gd")
	var view: Vector2 = label.get_viewport().get_visible_rect().size
	var portrait: bool = layout.is_portrait(view)
	var scale: float = layout.scale_for(view) if portrait else 1.0
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.04, 0.08, 0.12, 0.9)
	panel.border_color = edge
	panel.set_border_width_all(maxi(2, roundi(2.0 * scale)))
	panel.set_corner_radius_all(roundi(12.0 * scale))
	panel.content_margin_left = 16.0 * scale
	panel.content_margin_right = 16.0 * scale
	panel.content_margin_top = 9.0 * scale
	panel.content_margin_bottom = 10.0 * scale
	label.add_theme_stylebox_override("normal", panel)
	label.add_theme_font_size_override("font_size", roundi(font_size * scale))
	# Size the panel to its text: each line measured, never wider than the screen.
	var font: Font = label.get_theme_font("font")
	var size_px: int = roundi(font_size * scale)
	var lines: PackedStringArray = label.text.split("\n")
	var text_width := 0.0
	for line in lines: text_width = maxf(text_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x)
	var width: float = minf(view.x - 24.0 * scale, text_width + 36.0 * scale)
	var height: float = font.get_height(size_px) * lines.size() + 22.0 * scale
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if text_width + 36.0 * scale > view.x - 24.0 * scale else TextServer.AUTOWRAP_OFF
	label.custom_minimum_size = Vector2.ZERO
	label.size = Vector2(width, height)
	var net_y: float = view.y * 0.45
	var camera: Camera3D = label.get_viewport().get_camera_3d()
	var net_top := Vector3(0.0, PickleballConstants.FLOOR_Y + PickleballConstants.NET_HEIGHT, 0.0)
	if camera != null and not camera.is_position_behind(net_top):
		net_y = camera.unproject_position(net_top).y
	label.position = Vector2((view.x - width) * 0.5, maxf(8.0 * scale, net_y - height - 14.0 * scale))

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
		# The HUD re-lays out its labels when the result banner appears; keep the
		# reason panel sized to its text and above the net while it shows.
		if _hud and _hud.get("fault") and _hud.fault.visible: _place_fault_banner(_fault_edge, _fault_font)
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
		# Only rebuild the HUD's match-context text when its inputs change (not every frame).
		var practice_game: bool = _game.has_method("_is_practice") and _game._is_practice()
		var launcher = _game.get("practice_launcher")
		var key: Array = [_game.serving_team, _game.game_state in [1, 2], _game.get("match_over"), _game.score_left, _game.score_right, practice_game]
		var doubles = _game.get("doubles_state")
		if doubles != null: key.append(doubles.server_number)
		if practice_game and launcher != null:
			key.append(launcher.drill_mode)
			if launcher.is_wall(): key.append(launcher.wall_practice.returns * 1000 + launcher.wall_practice.targets)
		if key != _context_key or _hud._portrait != _context_portrait:
			_context_key = key
			_context_portrait = _hud._portrait
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
