extends CanvasLayer
## Gameplay tips (docs/STAMINA_UX_PLAN.md, docs/SHOT_QUALITY_PLAN.md): a few words, each once
## per match, about what just happened (stamina, and the cause of your own miss).
##  - A small toast in the top right corner, under the TIPS button, for about 3 s. Never in
##    the middle of the court (user's call, 2026-11-24: it was distracting).
##  - A TIPS button with a count at the top right of the court area. It pulses when a new tip
##    arrives; tap it to open the list of tips (newest first, this session), tap again to hide.
## Off with Settings "Stamina tips". Never in the all-AI bench. Presentation only; each tip
## shown goes to the perf log ("stamina_tip").
## Drawn in the UI kit's pixel style (gold-rimmed navy pixel plates, the pixel font); the
## TIPS button keeps the exact touch rect it had with the old sans label.
const Layout = preload("res://scripts/ui/mobile_layout.gd")
const Tuning = preload("res://scripts/gameplay_tuning.gd")
const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
const PixelStyle = preload("res://scripts/ui/pixel_style_box.gd")
const PixelDraw = preload("res://scripts/ui/pixel_draw.gd")
const SHOW_SECONDS := 3.0
const FADE_SECONDS := 0.35
const TIP_COLOR := UiTheme.KIT_GOLD
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
var _button_styles: Array = []   # normal, hover, pressed, hover_pressed (pixel_style_box.gd)
var _layout_key := Vector3(-1, -1, -1)
var _court := Rect2()
var _scale := 1.0

func _ready() -> void:
	layer = 5
	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_theme_font_override("font", UiTheme.pixel_font())
	_toast.add_theme_color_override("font_shadow_color", PixelDraw.SHADOW)
	_toast.add_theme_constant_override("shadow_offset_x", 0)
	_toast.add_theme_constant_override("shadow_offset_y", 2)
	UiTheme.crisp(_toast)
	_toast.modulate.a = 0.0
	add_child(_toast)
	_button = Button.new()
	_button.text = "TIPS"
	_button.focus_mode = Control.FOCUS_NONE
	_button.visible = false
	_button.add_theme_font_override("font", UiTheme.pixel_font())
	UiTheme.crisp(_button)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		_button.add_theme_color_override(state, TIP_COLOR)
	_button.pressed.connect(_toggle_list)
	add_child(_button)
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.crisp(_panel)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_panel.add_child(_list)
	add_child(_panel)
	# The touch controls hand taps on these buttons over (mobile_controls._toolbar_at_point).
	if game != null and "extra_touch_buttons" in game: game.extra_touch_buttons.append(_button)

## Gold-rimmed navy pixel plate (the kit), padded by these margins at scale s.
func _plate(fill: Color, s: float, h_margin: float, v_margin: float) -> StyleBox:
	var style = PixelStyle.plate(fill, s, 1, Color(TIP_COLOR, 0.85))
	PixelStyle.set_margins(style, h_margin * s, v_margin * s, h_margin * s, (v_margin + 1.0) * s)
	return style

## Relayout only when the screen or the button text changes (never per frame). The button
## keeps the touch rect the old sans label gave it (fallback font, 12/6 px margins): the
## margins are solved so the pixel text sits in that same rect, and the plate is drawn a
## little wider when the pixel text needs it (drawing only, the touch rect is unchanged).
func _relayout(size: Vector2) -> void:
	var viewport := get_viewport()
	_scale = Layout.scale_for(size)
	var safe := Layout.safe_rect(viewport)
	_court = Layout.court_rect(size, safe) if Layout.is_portrait(size) else safe.grow(-16.0)
	var text := "TIPS %d" % _unread if _unread > 0 else "TIPS"
	var old_size := int(16 * _scale)
	var sans: Font = ThemeDB.fallback_font
	var touch := Vector2(sans.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, old_size).x + 24.0, sans.get_height(old_size) + 12.0)
	var pixel_size := UiTheme.pixel_size(16 * _scale)
	var font := UiTheme.pixel_font()
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixel_size).x
	var side := maxf(0.0, floorf((touch.x - text_w) * 0.5))
	var top := maxf(0.0, floorf((touch.y - font.get_height(pixel_size)) * 0.5))
	var plate_overhang := maxf(0.0, ceilf((text_w + 20.0 * _scale - touch.x) * 0.5))
	if _button_styles.is_empty():
		for fill in [Color(UiTheme.PANEL, 0.88), Color(UiTheme.SURFACE_HOVER, 0.92), Color(UiTheme.SURFACE_PRESSED, 0.95), Color(UiTheme.SURFACE_PRESSED, 0.95)]:
			_button_styles.append(PixelStyle.plate(fill, _scale, 1, Color(TIP_COLOR, 0.85)))
		for i in _button_styles.size(): _button.add_theme_stylebox_override(["normal", "hover", "pressed", "hover_pressed"][i], _button_styles[i])
	for style in _button_styles:
		style.unit = PixelDraw.unit(_scale)
		style.inset = Vector2(-plate_overhang, 0)
		PixelStyle.set_margins(style, side, top, touch.x - text_w - side, touch.y - font.get_height(pixel_size) - top)
	_button.text = text
	_button.add_theme_font_size_override("font_size", pixel_size)
	_button.size = Vector2.ZERO
	_button.position = Vector2(_court.end.x - _button.get_combined_minimum_size().x - 12.0 * _scale, _court.position.y + 10.0 * _scale)
	_button.pivot_offset = _button.size * 0.5
	_toast.add_theme_stylebox_override("normal", _plate(Color(UiTheme.PANEL, 0.9), _scale, 10.0, 6.0))
	_toast.add_theme_font_size_override("font_size", pixel_size)
	_panel.add_theme_stylebox_override("panel", _plate(Color(UiTheme.PANEL, 0.94), _scale, 14.0, 10.0))
	if _panel.visible: _place_panel()

func _place_panel() -> void:
	_panel.size = Vector2(_court.size.x * 0.78, 0)
	_panel.position = Vector2(_court.end.x - _panel.size.x - 12.0 * _scale, _button.position.y + _button.size.y + 8.0 * _scale)

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
		_place_panel()

## Kit rule: the title in the pixel font, the tips (body copy) in the clean sans.
func _fill_list() -> void:
	for child in _list.get_children(): child.queue_free()
	var title := Label.new()
	title.text = "TIPS" if not history.is_empty() else "TIPS  ·  none yet"
	title.add_theme_color_override("font_color", TIP_COLOR)
	UiTheme.use_pixel(title, 18 * _scale)
	_list.add_child(title)
	for i in range(history.size() - 1, -1, -1):
		var item: Dictionary = history[i]
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.text = "Rally %d · %s" % [int(item.point), str(item.text)]
		line.add_theme_font_override("font", UiTheme.sans_font())
		line.add_theme_font_size_override("font_size", int(16 * _scale))
		line.add_theme_color_override("font_color", Color(UiTheme.INK, 1.0 if i == history.size() - 1 else 0.8))
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
	# Layout: button top right, toast and list under it. Rebuilt only on a new screen size
	# or button text (count), not every frame.
	var size := get_viewport().get_visible_rect().size
	var key := Vector3(size.x, size.y, _unread)
	if key != _layout_key:
		_layout_key = key
		_relayout(size)
		if _left > 0.0: _place_toast()
	_button.visible = true
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - delta)
		_button.scale = Vector2.ONE * (1.0 + 0.12 * sin(_pulse * 12.0) * minf(_pulse, 1.0))
	# Toast: one at a time.
	if _left <= 0.0 and not _queue.is_empty():
		_toast.text = _queue.pop_front()
		_left = SHOW_SECONDS
		_place_toast()
	if _left > 0.0 and not _panel.visible:
		_left -= delta
		_toast.modulate.a = 0.9 * clampf(minf(_left, SHOW_SECONDS - _left) / FADE_SECONDS, 0.0, 1.0)
	else:
		_toast.modulate.a = 0.0

## Small, in the corner under the TIPS button, right-aligned: out of the play area.
func _place_toast() -> void:
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toast.add_theme_color_override("font_color", TIP_COLOR)
	# The plate hugs a one-line tip; longer tips wrap at the old width.
	var one_line: float = _toast.get_theme_font("font").get_string_size(_toast.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _toast.get_theme_font_size("font_size")).x + _toast.get_theme_stylebox("normal").get_minimum_size().x
	var width: float = minf(ceilf(one_line), minf(_court.size.x * 0.5, 300.0 * _scale))
	_toast.size = Vector2(width, 0)
	# A wrapping label keeps the height it needed at its old width (a new tip wrapped at the
	# last, narrower width: a plate 1600 px tall down the court). Ask again at the new width.
	_toast.size = Vector2(width, _toast.get_minimum_size().y)
	_toast.position = Vector2(_court.end.x - _toast.size.x - 12.0 * _scale, _button.position.y + _button.size.y + 6.0 * _scale)
