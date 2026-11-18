extends CanvasLayer


const Layout = preload("res://scripts/ui/mobile_layout.gd")
const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
const SCORE_SECONDS: = 2.8
const OUT_SECONDS: = 1.1
const GESTURE_SECONDS: = 0.78
var game
var bubble: PanelContainer
var label: Label
var speaker: = -1
var speaker_actor_id: = -1
var _gesture_actor_id: = -1
var kind: = ""
var remaining: = 0.0
var gesture_elapsed: = GESTURE_SECONDS
var _serve_key: = ""
var _generation: = -1
var _gesture_team: = -1
var _gesture_generation: = -1

func setup(owner_game) -> void :
	game = owner_game
	name = "CourtCallouts"
	layer = 2
	bubble = PanelContainer.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.theme = UiTheme.create()
	var style: = StyleBoxFlat.new()
	style.bg_color = Color("eff6df")
	style.border_color = Color("28545e")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	bubble.add_theme_stylebox_override("panel", style)
	add_child(bubble)
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color("16323a"))
	bubble.add_child(label)
	bubble.hide()
	game.rally_scorer.rally_ended.connect(_on_rally_ended)

static func score_text(left: int, right: int, server: int) -> String:

	return "%d – %d" % ([left, right] if server == 0 else [right, left])

func _show(text: String, team: int, call_kind: String, seconds: float) -> void :
	speaker = team
	speaker_actor_id = -1
	if game.get("doubles_mode") == true:
		var actor = game.get_server_actor() if call_kind == "SCORE" else _nearest_team_actor(team)
		if actor != null: speaker_actor_id = actor.get_actor_id()
	kind = call_kind
	label.text = text
	remaining = seconds
	_generation = game._point_reset_generation
	bubble.show()
	_place()

func clear() -> void :
	remaining = 0.0
	gesture_elapsed = GESTURE_SECONDS
	_gesture_team = -1
	kind = ""
	speaker = -1
	speaker_actor_id = -1
	_gesture_actor_id = -1
	bubble.hide()

func _process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_process(delta)
	PerfMonitor.record("proc.court_callouts", Time.get_ticks_usec() - _pt)

func _perf_process(delta: float) -> void:
	if game._is_practice() or game._tool_state_active() or not game.hud._gameplay_visible:
		clear()
		_serve_key = ""
		return
	if _generation != game._point_reset_generation and remaining > 0: clear()
	if game.game_state == game.GameState.WAITING and not game.match_over:
		var key: = "%d:%d:%d:%d" % [game._point_reset_generation, game.serving_team, game.score_left, game.score_right]
		if game.get("doubles_mode") == true: key += ":" + game.doubles_state.score_call() + ":" + str(game.doubles_state.server_actor)
		if key != _serve_key:
			_serve_key = key
			_show(game.doubles_state.score_call() if game.get("doubles_mode") == true else score_text(game.score_left, game.score_right, game.serving_team), game.serving_team, "SCORE", SCORE_SECONDS)
	elif kind == "SCORE":
		clear()
	if game.game_state != game.GameState.POINT_SCORED and kind == "OUT": clear()
	if remaining > 0:
		remaining = maxf(0.0, remaining - delta)
		gesture_elapsed += delta
		bubble.modulate.a = minf(1.0, remaining / 0.16)
		_place()
		if remaining == 0: clear()

func _on_rally_ended(winner: int, reason: String, _detail: String) -> void :
	if game._is_practice() or reason != RallyScorer.FAULT_OUT_OF_BOUNDS: return
	var hitter: int = game.ball.last_hit_by


	if hitter not in [0, 1] or game.ball.bounces_since_last_hit > 1 or winner != 1 - hitter: return
	game.game_shots._hide_out_indicator()
	game.hud.fault.hide()
	game.scoreboard_ui._fault_visible_timer = 0.0
	_show("Out!", 1 - hitter, "OUT", OUT_SECONDS)
	_gesture_team = 1 - hitter
	_gesture_actor_id = speaker_actor_id
	_gesture_generation = game._point_reset_generation
	gesture_elapsed = 0.0

func gesture_weight(player) -> float:
	if game.get("doubles_mode") == true and player.get_actor_id() != _gesture_actor_id: return 0.0
	if player.player_num != _gesture_team or gesture_elapsed >= GESTURE_SECONDS or _gesture_generation != game._point_reset_generation: return 0.0
	if game._is_practice() or game.game_state != game.GameState.POINT_SCORED or game.ball.is_in_play: return 0.0
	var between = game.between_point_controller

	if between and between.is_active() and not between.hand_presentation_for(player.get_actor_id()).is_empty(): return 0.0
	return smoothstep(0.0, 0.18, gesture_elapsed) * (1.0 - smoothstep(0.49, GESTURE_SECONDS, gesture_elapsed))

func gesture_target(player, arm, normal_target: Vector3, weight: float) -> Vector3:
	var side: float = -1.0 if arm == player.left_arm_node else 1.0
	var shoulder: Vector3 = arm.upper_pivot.global_position


	var raised: Vector3 = shoulder + Vector3.UP * 0.43 + player._get_forehand_axis() * side * 0.19 + player._get_forward_axis() * 0.08
	return normal_target.lerp(raised, weight)

func _place() -> void :
	if speaker not in [0, 1] or not bubble.visible: return
	var player = game.get_player_by_actor_id(speaker_actor_id) if speaker_actor_id >= 0 else game.player_left if speaker == 0 else game.player_right
	if player == null: clear(); return
	var camera: Camera3D = game.main_camera
	var head: Vector3 = player.get_global_transform_interpolated().origin + Vector3.UP * 0.92
	if camera == null or camera.is_position_behind(head):
		bubble.hide()
		return
	var size: Vector2 = get_viewport().get_visible_rect().size
	var scale: float = Layout.scale_for(size) if Layout.is_portrait(size) else 1.0
	label.add_theme_font_size_override("font_size", roundi(25 * scale))
	bubble.reset_size()
	var safe: Rect2 = Layout.safe_rect(get_viewport())
	var court: Rect2 = Layout.court_rect(size, safe) if Layout.is_portrait(size) else safe.grow(-12)
	var point: Vector2 = camera.unproject_position(head)
	var side: float = -1.0 if point.x > court.get_center().x else 1.0
	var pos: = point + Vector2(side * 48 * scale - (bubble.size.x if side < 0 else 0.0), - bubble.size.y - 10 * scale)
	pos.x = clampf(pos.x, court.position.x + 5 * scale, maxf(court.position.x + 5 * scale, court.end.x - bubble.size.x - 5 * scale))
	pos.y = clampf(pos.y, court.position.y + 4 * scale, maxf(court.position.y + 4 * scale, court.end.y - bubble.size.y))

	if game.ball.visible and not camera.is_position_behind(game.ball.global_position):
		var ball_point: Vector2 = camera.unproject_position(game.ball.get_global_transform_interpolated().origin)
		if Rect2(pos, bubble.size).grow(16 * scale).has_point(ball_point):
			pos.x = clampf(point.x - side * 48 * scale - (bubble.size.x if side > 0 else 0.0), court.position.x + 5 * scale, maxf(court.position.x + 5 * scale, court.end.x - bubble.size.x - 5 * scale))
	bubble.position = pos

func _nearest_team_actor(team:int):
	var selected=null;var distance:float=INF
	for actor in game.get_team_players(team):
		var next:float=actor.global_position.distance_squared_to(game.ball.global_position)
		if next<distance: selected=actor;distance=next
	return selected
