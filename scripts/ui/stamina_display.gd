extends CanvasLayer

# Stamina you can read (docs/STAMINA_UX_PLAN.md). Presentation only: no physics queries,
# nothing gameplay reads, and its own random stream (never the global one the seeded AI uses).
#  - A small bar over every player: a notch at the penalty line, a white "ghost" chunk for
#    what was just spent, amber below the line, red and pulsing below 25. Shown the whole
#    rally; between points only while changing or low.
#  - Your own bar, larger, with the number, at the top of the court area.
#  - Floating "-N" over your team on a costly shot, a "TIRED" tag when anyone crosses the
#    line, "+N LONG RALLY" on a refill.
#  - Pixel sweat drops over a tired player (no glow).
const Layout = preload("res://scripts/ui/mobile_layout.gd")
const Feedback = preload("res://scripts/ui/stamina_feedback.gd")
const _Tuning = preload("res://scripts/gameplay_tuning.gd")
const REAPPEAR_MARGIN := 4.0 # Additional logical pixels, scaled with the HUD.
const REAPPEAR_SECONDS := 0.10
# The bar turns amber where the low-stamina penalty starts (50 with the Gameplay v2
# stamina rule, gameplay_tuning STAMINA_ON; 25 before), so you can plan around it.
const LOW_STAMINA_ENTER: float = _Tuning.STAMINA_PENALTY_AT if _Tuning.STAMINA_ON else 25.0
const LOW_STAMINA_EXIT: float = LOW_STAMINA_ENTER + 2.0 # Conservative paint-only recovery margin.
const VERY_LOW := 25.0
const RALLY_ALPHA := 0.9
const GHOST_HOLD := 0.45
const GHOST_DRAIN := 60.0          # stamina points per second the ghost chunk drains
const POP_COST_MIN := 4.0          # a single drop this big shows a floating "-N"
const POP_SECONDS := 1.1
const REFILL_MIN := 8.0            # a jump this big outside a rally is the long-rally refill
const COLOR_MINE := Color(0.35, 0.7, 1.0)
const COLOR_THEIRS := Color(1.0, 0.45, 0.4)
const COLOR_TIRED := Color(1.0, 0.68, 0.2)
const COLOR_VERY_TIRED := Color(1.0, 0.3, 0.25)

## One drawn bar: background, fill, ghost, notch at the penalty line (and the number when big).
class StaminaBar extends Control:
	var value := 100.0
	var ghost := 100.0
	var fill := Color.WHITE
	var pulse := 0.0
	var big := false
	var font: Font
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.035, 0.045, 0.06, 0.95))
		var w: float = size.x - 2.0
		var f := Rect2(Vector2(1, 1), Vector2(w * clampf(value / 100.0, 0.0, 1.0), size.y - 2.0))
		if ghost > value:
			draw_rect(Rect2(Vector2(1 + f.size.x, 1), Vector2(w * clampf((ghost - value) / 100.0, 0.0, 1.0), size.y - 2.0)), Color(1, 1, 1, 0.85))
		draw_rect(f, fill.lerp(Color.WHITE, pulse * 0.35))
		var notch_x: float = 1.0 + w * LOW_STAMINA_ENTER / 100.0
		draw_line(Vector2(notch_x, -2.0), Vector2(notch_x, size.y + 2.0), Color(1, 1, 1, 0.9), 2.0 if big else 1.0)
		draw_rect(r, Color(0.8, 0.85, 0.9, 0.65), false, 1.0)
		if big and font != null and size.y >= 4.0:
			var fs: int = int(size.y * 1.6)
			draw_string(font, Vector2(size.x + 6.0, size.y * 0.5 + fs * 0.35), str(int(round(value))), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fill)

## Floating words and numbers, and sweat drops (screen space, one overlay).
class Overlay extends Control:
	var pops: Array = []      # {text, color, pos, age}
	var drops: Array = []     # {pos, vel, age}
	var font: Font
	var scale_ui := 1.0
	func _draw() -> void:
		if font == null: return
		for p in pops:
			var a: float = clampf(1.0 - float(p.age) / POP_SECONDS, 0.0, 1.0)
			var fs: int = int(22 * scale_ui)
			var pos: Vector2 = p.pos - Vector2(0, 40.0 * scale_ui * float(p.age))
			var c: Color = p.color; c.a = a
			draw_string_outline(font, pos, p.text, HORIZONTAL_ALIGNMENT_CENTER, 160 * scale_ui, fs, int(6 * scale_ui), Color(0, 0, 0, a * 0.8))
			draw_string(font, pos, p.text, HORIZONTAL_ALIGNMENT_CENTER, 160 * scale_ui, fs, c)
		for d in drops:
			var a2: float = clampf(1.0 - float(d.age) / 0.6, 0.0, 1.0)
			var px: float = 3.0 * scale_ui
			draw_rect(Rect2(d.pos, Vector2(px, px * 1.4)), Color(0.75, 0.9, 1.0, a2))

var feedback: Array = []
var game: Node
var bars: Array = []
var heads: Array[Node3D] = []
var _clear_seconds: Array[float] = []
var _players: Array = []
var _low_stamina: Array[bool] = []
var _warning_player_ids: Array[int] = []
var _last_value: Array[float] = []
var _ghost_hold: Array[float] = []
var _drop_clock: Array[float] = []
var _big: StaminaBar
var _overlay: Overlay
var _font: Font
var _clock := 0.0
var _fx_rng := RandomNumberGenerator.new()

func _ready() -> void:
	layer = 4
	_fx_rng.seed = 0x5eed
	_font = ThemeDB.fallback_font
	var theme_script = load("res://scripts/ui/game_ui_theme.gd")
	if theme_script != null and theme_script.has_method("pixel_font"): _font = theme_script.pixel_font()
	_overlay = Overlay.new(); _overlay.font = _font
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	_players = game.get_players() if game.has_method("get_players") else [game.player_left, game.player_right]
	_players.sort_custom(func(a, b): return a.get_actor_id() < b.get_actor_id())
	for i in _players.size():
		var player = _players[i]
		_clear_seconds.append(0.0); _low_stamina.append(false); _warning_player_ids.append(0)
		_last_value.append(player.stamina.value); _ghost_hold.append(0.0); _drop_clock.append(0.0)
		heads.append(player.get_node_or_null("BodyPivot/TorsoMesh/HeadMesh"))
		var bar := StaminaBar.new()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.visible = false
		bar.value = player.stamina.value; bar.ghost = bar.value
		var state = Feedback.new()
		state.reset(player.stamina.value)
		feedback.append(state)
		bar.modulate.a = state.alpha
		bar.tooltip_text = "Stamina"
		add_child(bar)
		bars.append(bar)
	_big = StaminaBar.new(); _big.big = true; _big.font = _font
	_big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_big)

func _process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_process(delta)
	PerfMonitor.record("proc.stamina_display", Time.get_ticks_usec() - _pt)

func _color_for(player, value: float, i: int) -> Color:
	if value < VERY_LOW: return COLOR_VERY_TIRED
	if i >= 0 and _low_stamina[i]: return COLOR_TIRED
	return COLOR_MINE if player.team_id == game.player_left.team_id else COLOR_THEIRS

func _pop(text: String, color: Color, at: Vector2) -> void:
	_overlay.pops.append({"text": text, "color": color, "pos": at - Vector2(80.0 * _overlay.scale_ui, 0), "age": 0.0})

func _perf_process(delta: float) -> void:
	_clock += delta
	if not is_instance_valid(game) or not is_instance_valid(game.camera_rig):
		_hide_bars()
		return
	var camera: Camera3D = game.camera_rig.camera
	if not is_instance_valid(camera):
		_hide_bars()
		return
	var viewport := get_viewport()
	var size := viewport.get_visible_rect().size
	var scale := Layout.scale_for(size)
	_overlay.scale_ui = scale
	var safe := Layout.safe_rect(viewport)
	var court := Layout.court_rect(size, safe) if Layout.is_portrait(size) else safe.grow(-16.0)
	var ball_screen := Vector2.INF
	if game.ball != null and not camera.is_position_behind(game.ball.global_position):
		ball_screen = camera.unproject_position(game.ball.get_global_transform_interpolated().origin)
	var tool_active: bool = game._tool_state_active()
	# Settings "Stamina bars" (off by default): no bars, numbers or words, only the sweat.
	var show_bars: bool = bool(Settings.get_value("gameplay.stamina_bars", false))
	var rally: bool = game.game_state == game.GameState.PLAYING
	var pulse: float = 0.5 + 0.5 * sin(_clock * 6.0)
	for i in bars.size():
		var player = _players[i]
		if not is_instance_valid(player): continue
		var bar: StaminaBar = bars[i]
		var blocked := tool_active or not show_bars
		var clear_to_show := not tool_active and show_bars
		var value: float = player.stamina.value
		var mine: bool = player.team_id == game.player_left.team_id
		# Ghost chunk: a drop holds as white, then drains.
		var drop: float = _last_value[i] - value
		if drop > 0.05:
			bar.ghost = maxf(bar.ghost, _last_value[i])
			_ghost_hold[i] = GHOST_HOLD
		_ghost_hold[i] = maxf(0.0, _ghost_hold[i] - delta)
		if _ghost_hold[i] <= 0.0: bar.ghost = move_toward(bar.ghost, value, GHOST_DRAIN * delta)
		bar.ghost = maxf(bar.ghost, value)
		bar.value = value
		var anchor: Vector3 = heads[i].get_global_transform_interpolated().origin + Vector3.UP * 0.15 if is_instance_valid(heads[i]) else player.get_global_transform_interpolated().origin + Vector3.UP
		var head_screen := Vector2.INF
		if not camera.is_position_behind(anchor): head_screen = camera.unproject_position(anchor)
		if drop >= POP_COST_MIN and mine and head_screen.is_finite() and not tool_active and show_bars:
			_pop("-%d" % int(round(drop)), COLOR_TIRED if value < LOW_STAMINA_ENTER else Color(1, 1, 1), head_screen - Vector2(0, 28.0 * scale))
		if -drop >= REFILL_MIN and not rally and head_screen.is_finite() and not tool_active and show_bars:
			_pop("+%d LONG RALLY" % int(round(-drop)), Color("7dff9a"), head_screen - Vector2(0, 28.0 * scale))
		_last_value[i] = value
		if tool_active: feedback[i].reset(value)
		var fade: float = feedback[i].advance(value, delta)
		var tired: bool = value < LOW_STAMINA_ENTER
		bar.modulate.a = maxf(fade, RALLY_ALPHA) if rally or tired else fade
		bar.size = (Vector2(88, 10) if player == game.player_left else Vector2(68, 8)) * scale
		var local_pov: bool = player == game.player_left and game.camera_rig.gameplay_camera.mode in [2, 3]
		if local_pov:
			# Own-POV camera: your big bar shows it, the ball stays clear.
			blocked = true
			clear_to_show = false
		elif not head_screen.is_finite():
			blocked = true
			clear_to_show = false
		else:
			bar.position = head_screen - Vector2(bar.size.x * 0.5, bar.size.y + 8.0 * scale)
			bar.position.x = clampf(bar.position.x, court.position.x, maxf(court.position.x, court.end.x - bar.size.x))
			bar.position.y = clampf(bar.position.y, court.position.y, maxf(court.position.y, court.end.y - bar.size.y))
		# Suppress rather than cover the ball or jump the bar across the court.
		var bar_rect := Rect2(bar.position, bar.size)
		blocked = blocked or bar_rect.grow(20.0 * scale).has_point(ball_screen)
		clear_to_show = clear_to_show and not bar_rect.grow((20.0 + REAPPEAR_MARGIN) * scale).has_point(ball_screen)
		var controls = game.mobile_controls
		if controls != null and controls.enabled:
			var rect := bar_rect.grow(6.0 * scale)
			var clear_rect := bar_rect.grow((6.0 + REAPPEAR_MARGIN) * scale)
			var hit_radius: float = controls._charge_radius * 1.25
			var hit_rect := Rect2(controls._charge_center - Vector2.ONE * hit_radius, Vector2.ONE * hit_radius * 2.0)
			blocked = blocked or rect.intersects(hit_rect) or rect.intersects(controls._timing_caption_rect)
			clear_to_show = clear_to_show and not clear_rect.intersects(hit_rect) and not clear_rect.intersects(controls._timing_caption_rect)
		_update_visibility(i, blocked, clear_to_show, delta)

		var player_id: int = player.get_instance_id()
		if tool_active or _warning_player_ids[i] != player_id:
			_low_stamina[i] = false
			_warning_player_ids[i] = player_id
		var was_low: bool = _low_stamina[i]
		if value < LOW_STAMINA_ENTER:
			_low_stamina[i] = true
		elif value >= LOW_STAMINA_EXIT:
			_low_stamina[i] = false
		if _low_stamina[i] and not was_low and head_screen.is_finite() and not tool_active and show_bars:
			_pop("TIRED", COLOR_TIRED, head_screen - Vector2(0, 46.0 * scale))
		bar.fill = _color_for(player, value, i)
		bar.pulse = pulse if value < VERY_LOW else 0.0
		bar.queue_redraw()
		# Sweat drops over a tired player (pixel squares, no glow).
		if tired and head_screen.is_finite() and not tool_active:
			_drop_clock[i] -= delta
			if _drop_clock[i] <= 0.0:
				var fatigue: float = clampf(1.0 - value / LOW_STAMINA_ENTER, 0.0, 1.0)
				_drop_clock[i] = lerpf(0.7, 0.25, fatigue)
				var side: float = -1.0 if _fx_rng.randf() < 0.5 else 1.0
				_overlay.drops.append({"pos": head_screen + Vector2(side * 10.0 * scale, -6.0 * scale), "vel": Vector2(side * 18.0, -30.0) * scale, "age": 0.0})
	# Your big bar with the number, top of the court area.
	var me = game.player_left
	var mi: int = _players.find(me)
	if is_instance_valid(me) and not tool_active and mi >= 0 and show_bars:
		_big.visible = true
		_big.size = Vector2(150, 12) * scale
		_big.position = court.position + Vector2(12, 14) * scale
		_big.value = me.stamina.value
		_big.ghost = bars[mi].ghost
		_big.fill = _color_for(me, me.stamina.value, mi)
		_big.pulse = pulse if me.stamina.value < VERY_LOW else 0.0
		_big.queue_redraw()
	elif _big != null:
		_big.visible = false
	# Age the floating words and drops.
	for p in _overlay.pops: p.age += delta
	_overlay.pops = _overlay.pops.filter(func(p): return p.age < POP_SECONDS)
	for d in _overlay.drops:
		d.age += delta; d.vel.y += 160.0 * scale * delta; d.pos += d.vel * delta
	_overlay.drops = _overlay.drops.filter(func(d): return d.age < 0.6)
	_overlay.queue_redraw()

func _hide_bars() -> void:
	for i in bars.size():
		bars[i].visible = false
		_clear_seconds[i] = 0.0
		_low_stamina[i] = false
		_warning_player_ids[i] = 0
	if _big != null: _big.visible = false

func _update_visibility(index: int, blocked: bool, clear_to_show: bool, delta: float) -> void:
	# Occlusion always wins immediately. Only re-entry waits for comfortable,
	# continuous clearance, so boundary noise cannot flash an obstructive bar.
	if blocked:
		bars[index].visible = false
		_clear_seconds[index] = 0.0
	elif bars[index].visible or not clear_to_show:
		_clear_seconds[index] = 0.0
	else:
		_clear_seconds[index] = minf(REAPPEAR_SECONDS, _clear_seconds[index] + maxf(0.0, delta))
		if _clear_seconds[index] + 0.000001 >= REAPPEAR_SECONDS:
			bars[index].visible = true
