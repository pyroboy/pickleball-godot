extends CanvasLayer
## Gameplay tips (docs/STAMINA_UX_PLAN.md, docs/SHOT_QUALITY_PLAN.md): a few words, each once
## per match, about what just happened (stamina, and the cause of your own miss).
##  - A small toast in the top right corner, under the TIPS button, for about 3 s. Never in
##    the middle of the court (user's call, 2026-11-24: it was distracting).
##  - A TIPS button with a count at the top right of the court area. It pulses when a new tip
##    arrives; tap it to open the list of tips (newest first, this session), tap again to hide.
## Off with Settings "Stamina tips". Never in the all-AI bench. Presentation only; each tip
## shown goes to the perf log ("stamina_tip").
const Layout = preload("res://scripts/ui/mobile_layout.gd")
const Tuning = preload("res://scripts/gameplay_tuning.gd")
const SHOW_SECONDS := 3.0
const FADE_SECONDS := 0.35
const TIP_COLOR := Color("ffd166")
## One tip per cause of your own miss (point_ending "why").
const MISS_TIPS := {
	"LATE": "Late: release as the ring closes.",
	"EARLY": "Early: wait for the ring.",
	"TOO LOW TO DRIVE": "Red ring: too low to drive. Tap to dink.",
	"MOVING": "Stop before you hit.",
	"LOW STAMINA": "Low stamina: dink until it is back.",
}

## Tips seen this session (kept across matches), newest last: {text, point}.
static var history: Array = []

var game: Node
var _toast: Label
var _button: Button
var _panel: PanelContainer
var _list: VBoxContainer
var _shown: Dictionary = {}
var _left := 0.0
var _queue: Array[String] = []
var _was_low: Dictionary = {}
var _last_state := -1
var _pulse := 0.0
var _unread := 0
var _rally_no := 0

func _ready() -> void:
	layer = 5
	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.modulate.a = 0.0
	_toast.add_theme_stylebox_override("normal", _box(Color(0.03, 0.05, 0.08, 0.85), TIP_COLOR))
	add_child(_toast)
	_button = Button.new()
	_button.text = "TIPS"
	_button.focus_mode = Control.FOCUS_NONE
	_button.visible = false
	_button.add_theme_stylebox_override("normal", _box(Color(0.03, 0.05, 0.08, 0.8), TIP_COLOR))
	_button.add_theme_stylebox_override("hover", _box(Color(0.08, 0.1, 0.14, 0.9), TIP_COLOR))
	_button.add_theme_stylebox_override("pressed", _box(Color(0.15, 0.13, 0.05, 0.95), TIP_COLOR))
	_button.add_theme_color_override("font_color", TIP_COLOR)
	_button.pressed.connect(_toggle_list)
	add_child(_button)
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", _box(Color(0.03, 0.05, 0.08, 0.94), TIP_COLOR))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_panel.add_child(_list)
	add_child(_panel)
	# The touch controls hand taps on these buttons over (mobile_controls._toolbar_at_point).
	if game != null and "extra_touch_buttons" in game: game.extra_touch_buttons.append(_button)

func _box(bg: Color, edge: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = Color(edge, 0.8)
	b.set_border_width_all(2)
	b.set_corner_radius_all(6)
	b.content_margin_left = 12; b.content_margin_right = 12; b.content_margin_top = 6; b.content_margin_bottom = 6
	return b

func _enabled() -> bool:
	return Tuning.STAMINA_ON and not preload("res://scripts/runtime_policy.gd").autoplay \
		and bool(Settings.get_value("gameplay.stamina_tips", true))

func _tip(key: String, text: String) -> void:
	if _shown.has(key): return
	_shown[key] = true
	_queue.append(text)
	history.append({"text": text, "point": _rally_no + 1})
	if history.size() > 30: history.pop_front()
	_unread += 1
	_pulse = 1.2
	if _panel.visible: _fill_list()
	PerfMonitor.note("stamina_tip", {"tip": key})

func _toggle_list() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_unread = 0
		_fill_list()

func _fill_list() -> void:
	for child in _list.get_children(): child.queue_free()
	var title := Label.new()
	title.text = "TIPS" if not history.is_empty() else "TIPS  ·  none yet"
	title.add_theme_color_override("font_color", TIP_COLOR)
	_list.add_child(title)
	for i in range(history.size() - 1, -1, -1):
		var item: Dictionary = history[i]
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.text = "Rally %d · %s" % [int(item.point), str(item.text)]
		line.add_theme_color_override("font_color", Color(1, 1, 1, 1.0 if i == history.size() - 1 else 0.8))
		_list.add_child(line)

func _process(delta: float) -> void:
	if not is_instance_valid(game) or not _enabled():
		_toast.modulate.a = 0.0
		_button.visible = false
		_panel.visible = false
		return
	var me = game.player_left
	if me == null: return
	var state: int = int(game.game_state)
	# Your third power shot in a row.
	if me.stamina.power_streak >= 3:
		_tip("streak", "3 drives in a row cost more. Dink to rest.")
	for p in game.get_players():
		var low: bool = p.stamina.value < Tuning.STAMINA_PENALTY_AT
		var was: bool = bool(_was_low.get(p.get_actor_id(), false))
		_was_low[p.get_actor_id()] = low
		if low and not was:
			if p == me: _tip("tired_me", "Low stamina: weaker drives, more misses.")
			elif p.team_id != me.team_id: _tip("tired_them", "Sweating opponent: drive at them.")
	# Long rally won by your team.
	if _last_state == game.GameState.PLAYING and state != game.GameState.PLAYING: _rally_no += 1
	if state != _last_state and state != game.GameState.PLAYING:
		var ending: Dictionary = game.last_point_ending if "last_point_ending" in game else {}
		if int(ending.get("winner", -1)) == me.team_id and int(ending.get("shots", 0)) >= Tuning.LONG_RALLY:
			_tip("long_rally", "Long rally won: +%d stamina." % int(Tuning.LONG_RALLY_REFILL))
		# Your own miss: what to do about its cause (the stamp's second line).
		var why: String = str(ending.get("why", ""))
		if int(ending.get("actor", -1)) == me.get_actor_id() and MISS_TIPS.has(why): _tip("miss_" + why, MISS_TIPS[why])
	if state == game.GameState.WAITING and me.stamina.value < 25.0:
		_tip("very_tired", "Very tired: dink this point.")
	_last_state = state
	# Layout: toast under the score, button top right, list under the button.
	var viewport := get_viewport()
	var size := viewport.get_visible_rect().size
	var scale := Layout.scale_for(size)
	var safe := Layout.safe_rect(viewport)
	var court := Layout.court_rect(size, safe) if Layout.is_portrait(size) else safe.grow(-16.0)
	_button.visible = true
	_button.text = "TIPS %d" % _unread if _unread > 0 else "TIPS"
	_button.add_theme_font_size_override("font_size", int(16 * scale))
	_button.size = Vector2(0, 0)
	_button.position = Vector2(court.end.x - _button.get_combined_minimum_size().x - 12.0 * scale, court.position.y + 10.0 * scale)
	_pulse = maxf(0.0, _pulse - delta)
	_button.scale = Vector2.ONE * (1.0 + 0.12 * sin(_pulse * 12.0) * minf(_pulse, 1.0))
	_button.pivot_offset = _button.size * 0.5
	if _panel.visible:
		_panel.size = Vector2(court.size.x * 0.78, 0)
		_panel.position = Vector2(court.end.x - _panel.size.x - 12.0 * scale, _button.position.y + _button.size.y + 8.0 * scale)
		for child in _list.get_children():
			if child is Label: child.add_theme_font_size_override("font_size", int(16 * scale))
	# Toast: one at a time.
	if _left <= 0.0 and not _queue.is_empty():
		_toast.text = _queue.pop_front()
		_left = SHOW_SECONDS
	if _left > 0.0 and not _panel.visible:
		_left -= delta
		# Small, in the corner under the TIPS button, right-aligned: out of the play area.
		_toast.add_theme_font_size_override("font_size", int(14 * scale))
		_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_toast.size = Vector2(minf(court.size.x * 0.5, 300.0 * scale), 0)
		_toast.position = Vector2(court.end.x - _toast.size.x - 12.0 * scale, _button.position.y + _button.size.y + 6.0 * scale)
		_toast.modulate.a = 0.9 * clampf(minf(_left, SHOW_SECONDS - _left) / FADE_SECONDS, 0.0, 1.0)
		_toast.add_theme_color_override("font_color", TIP_COLOR)
	else:
		_toast.modulate.a = 0.0
