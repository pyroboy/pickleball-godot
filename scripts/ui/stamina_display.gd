extends CanvasLayer

# Two tiny projected bars; no physics queries or trajectory work.
const Layout = preload("res://scripts/ui/mobile_layout.gd")
const Feedback = preload("res://scripts/ui/stamina_feedback.gd")
const REAPPEAR_MARGIN := 4.0 # Additional logical pixels, scaled with the HUD.
const REAPPEAR_SECONDS := 0.10
const LOW_STAMINA_ENTER := 25.0
const LOW_STAMINA_EXIT := 27.0 # Conservative paint-only recovery margin.
var feedback: Array = []
var game: Node
var bars: Array[ProgressBar] = []
var fills: Array[StyleBoxFlat] = []
var heads: Array[Node3D] = []
var _clear_seconds: Array[float] = [0.0, 0.0]
var _low_stamina: Array[bool] = [false, false]
var _warning_player_ids: Array[int] = [0, 0]

func _ready() -> void:
	layer = 4
	for i in 2:
		var player = game.player_left if i == 0 else game.player_right
		heads.append(player.get_node_or_null("BodyPivot/TorsoMesh/HeadMesh"))
		var bar := ProgressBar.new()
		bar.max_value = 100.0
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.visible = false
		var background := StyleBoxFlat.new()
		background.bg_color = Color(0.035, 0.045, 0.06, 0.95)
		background.set_corner_radius_all(3)
		background.set_border_width_all(1)
		background.border_color = Color(0.8, 0.85, 0.9, 0.65)
		var fill := StyleBoxFlat.new()
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("background", background)
		bar.add_theme_stylebox_override("fill", fill)
		fills.append(fill)
		var state = Feedback.new()
		state.reset(player.stamina.value)
		feedback.append(state)
		bar.modulate.a = state.alpha
		bar.tooltip_text = "Stamina"
		add_child(bar)
		bars.append(bar)

func _process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_process(delta)
	PerfMonitor.record("proc.stamina_display", Time.get_ticks_usec() - _pt)

func _perf_process(delta: float) -> void:
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
	var safe := Layout.safe_rect(viewport)
	var court := Layout.court_rect(size, safe) if Layout.is_portrait(size) else safe.grow(-16.0)
	var ball_screen := Vector2.INF
	if game.ball != null and not camera.is_position_behind(game.ball.global_position):
		ball_screen = camera.unproject_position(game.ball.global_position)
	var tool_active: bool = game._tool_state_active()
	for i in 2:
		var player = game.player_left if i == 0 else game.player_right
		var bar := bars[i]
		var blocked := tool_active
		var clear_to_show := not tool_active
		bar.value = player.stamina.value
		# Same feedback follows the player across overhead and own-POV layouts.
		# Inherits scene pause; tool previews do not leave stale change highlights.
		if tool_active: feedback[i].reset(player.stamina.value)
		bar.modulate.a = feedback[i].advance(player.stamina.value, delta)
		bar.size = Vector2(88, 10) * scale
		var anchor: Vector3 = heads[i].global_position + Vector3.UP * 0.15 if is_instance_valid(heads[i]) else player.global_position + Vector3.UP
		var local_pov: bool = i == 0 and game.camera_rig.gameplay_camera.mode == 2
		if local_pov:
			# Side HUD leaves the exact ball-centered POV unobstructed.
			bar.position = court.position + Vector2(12, 14) * scale
		else:
			if camera.is_position_behind(anchor):
				blocked = true
				clear_to_show = false
			bar.position = camera.unproject_position(anchor) - Vector2(bar.size.x * 0.5, bar.size.y + 8.0 * scale)
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
		if player.stamina.value < LOW_STAMINA_ENTER:
			_low_stamina[i] = true
		elif player.stamina.value >= LOW_STAMINA_EXIT:
			_low_stamina[i] = false
		fills[i].bg_color = Color(1.0, 0.68, 0.2) if _low_stamina[i] else (Color(0.35, 0.7, 1.0) if i == 0 else Color(1.0, 0.45, 0.4))

func _hide_bars() -> void:
	for i in bars.size():
		bars[i].visible = false
		_clear_seconds[i] = 0.0
		_low_stamina[i] = false
		_warning_player_ids[i] = 0

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
