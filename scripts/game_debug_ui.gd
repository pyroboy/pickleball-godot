class_name GameDebugUI
extends Node
## Owns debug cycling, posture debug labels, and zone debug display.
## Fully extracted from game.gd.

# ── State ──────────────────────────────────────────────────────────────────────
var _debug_z_cycle: int = 0  # 0=all off, 1=all on, 2=on but zones hidden
var _intent_indicators_visible: bool = true

# ── Injected references ───────────────────────────────────────────────────────
var _player_left: CharacterBody3D
var _player_right: CharacterBody3D
var _scoreboard_ui: Node  # ScoreboardUI
var _rally_scorer: Node
var _ball: RigidBody3D
var _serve_charge_time: float = 0.0
var _ai_difficulty: int = 0  # Reference to game.gd ai_difficulty (0=EASY, 1=MEDIUM, 2=HARD)
var _serve_aim_offset_x: float = 0.0
var _trajectory_arc_offset: float = 0.0

# ─────────────────────────────────────────────────────────────────────────────
func setup(
	player_left: CharacterBody3D,
	player_right: CharacterBody3D,
	scoreboard_ui: Node,
	rally_scorer: Node,
	ball: RigidBody3D,
	_serve_charge_time_ref: float,
	_ai_difficulty_ref: int,
	_serve_aim_offset_x_ref: float,
	_trajectory_arc_offset_ref: float
) -> void:
	_player_left = player_left
	_player_right = player_right
	_scoreboard_ui = scoreboard_ui
	_rally_scorer = rally_scorer
	_ball = ball
	# The RefCounted params are just for signature compatibility;
	# actual values are updated via update() each frame.

# ── Input handlers (called from game.gd's _input) ─────────────────────────────

func cycle_difficulty() -> void:
	_ai_difficulty = (_ai_difficulty + 1) % 3
	_scoreboard_ui.update_difficulty(_ai_difficulty)
	print("[AI DIFFICULTY] ", ["EASY", "MEDIUM", "HARD"][_ai_difficulty])
	if _player_right and _player_right.has_method("get_ai_brain"):
		var brain = _player_right.get_ai_brain()
		if brain:
			brain.ai_difficulty = _ai_difficulty


func cycle_debug_visuals() -> void:
	_debug_z_cycle = (_debug_z_cycle + 1) % 3
	if _debug_z_cycle == 0:
		_set_debug_visuals_visible(false)
		_set_debug_zones_visible(false)
		if _scoreboard_ui:
			_scoreboard_ui.set_debug_visuals_active(false)
	elif _debug_z_cycle == 1:
		_set_debug_visuals_visible(true)
		_set_debug_zones_visible(true)
		if _scoreboard_ui:
			_scoreboard_ui.set_debug_visuals_active(true)
	elif _debug_z_cycle == 2:
		_set_debug_visuals_visible(true)
		_set_debug_zones_visible(false)
		if _scoreboard_ui:
			_scoreboard_ui.set_debug_visuals_active(true)


func toggle_intent_indicators() -> void:
	_intent_indicators_visible = not _intent_indicators_visible
	if _player_left and _player_left.has_method("get_debug_visual"):
		var dv = _player_left.get_debug_visual()
		if dv and dv.has_method("set_intent_indicators_visible"):
			dv.set_intent_indicators_visible(_intent_indicators_visible)
	if _player_right and _player_right.has_method("get_debug_visual"):
		var dv = _player_right.get_debug_visual()
		if dv and dv.has_method("set_intent_indicators_visible"):
			dv.set_intent_indicators_visible(_intent_indicators_visible)


# ── Main update (called from game.gd's _physics_process) ──────────────────────

func update(
	game_state: int,
	ball: RigidBody3D,
	player_left: CharacterBody3D,
	player_right: CharacterBody3D
) -> void:
	_update_service_zone_debug(game_state, ball)
	_update_debug_label(game_state, ball, player_left, player_right)


# ── Posture debug ──────────────────────────────────────────────────────────────

func update_posture_debug() -> void:
	if _scoreboard_ui == null:
		return
	var blue := _posture_line("BLUE", _player_left)
	var red := _posture_line("RED", _player_right)
	_scoreboard_ui.update_posture_debug(blue + "\n" + red)


func _posture_line(tag: String, player: CharacterBody3D) -> String:
	if player == null:
		return tag + ": ---"
	var idx: int = player.paddle_posture
	var pname: String
	if idx < player.DEBUG_POSTURE_NAMES.size():
		pname = player.DEBUG_POSTURE_NAMES[idx]
	else:
		pname = "???"
	var crouch: float = 0.0
	if player.has_node("body_anim"):
		var body_anim = player.get_node("body_anim")
		if body_anim and body_anim.has_method("get_crouch_amount"):
			crouch = body_anim.get_crouch_amount()
	var stance: String = "CROUCHING" if crouch > 0.02 else "STANDING"
	var gap: float = 0.0
	if player.has_node("leg_ik"):
		var leg_ik = player.get_node("leg_ik")
		if leg_ik and leg_ik.has_method("get_feet_gap"):
			gap = leg_ik.get_feet_gap()
	var feet: String = "WIDE" if gap > 0.45 else ("APART" if gap > 0.25 else "NARROW")
	return tag + ": " + pname + " | " + stance + " | " + feet + " " + str(snapped(gap, 0.01))


# ── Zone debug ─────────────────────────────────────────────────────────────────

func update_service_zone_debug() -> void:
	_update_service_zone_debug(0, _ball)


func _update_service_zone_debug(_game_state: int, ball: RigidBody3D) -> void:
	if _game_state != 2 or ball == null:  # GameState.PLAYING == 2
		return
	var bpos: Vector3 = ball.global_position
	if bpos.y > 0.4:
		return
	_update_zone_debug(bpos)


# Debug: Show which zone ball landed in
func _update_zone_debug(bpos: Vector3) -> void:
	const NON_VOLLEY_ZONE: float = 1.8
	if _scoreboard_ui == null or _ball == null:
		return
	# Determine what zone ball is in
	var zone: String = ""
	if bpos.z > NON_VOLLEY_ZONE:
		# BLUE'S SIDE (red serving, ball on blue side)
		if bpos.x > 0.0:
			zone = "BLUE RIGHT (CYAN)"
		elif bpos.x < 0.0:
			zone = "BLUE LEFT (LIME)"
		else:
			zone = "BLUE CENTER"
	elif bpos.z < -NON_VOLLEY_ZONE:
		# RED'S SIDE (blue serving, ball on red side)
		if bpos.x > 0.0:
			zone = "RED RIGHT (MAGENTA)"
		elif bpos.x < 0.0:
			zone = "RED LEFT (PURPLE)"
		else:
			zone = "RED CENTER"
	else:
		# KITCHEN / NVZ
		zone = ("BLUE" if bpos.z > 0 else "RED") + " KITCHEN"
	_scoreboard_ui.show_zone(zone)


# ── Debug label ────────────────────────────────────────────────────────────────

func _update_debug_label(
	game_state: int,
	ball: RigidBody3D,
	player_left: CharacterBody3D,
	player_right: CharacterBody3D
) -> void:
	if ball == null or _scoreboard_ui == null:
		return

	if game_state != 2:  # GameState.PLAYING
		_scoreboard_ui.update_debug_content("")
		return

	var ball_y: float = ball.global_position.y
	var ball_pos: Vector3 = ball.global_position

	# Blue player (human)
	var blue_paddle: Vector3 = player_left.get_paddle_position()
	var blue_dist: float = blue_paddle.distance_to(ball_pos)
	var blue_charge: float = clamp(_serve_charge_time / 0.8, 0.0, 1.0)
	var blue_contact: int = player_left._get_contact_state(blue_dist, ball_y, blue_charge)
	var blue_contact_name: String = ["CLEAN", "STRETCH", "POPUP"][blue_contact]

	# Red player (AI)
	var red_paddle: Vector3 = player_right.get_paddle_position()
	var red_dist: float = red_paddle.distance_to(ball_pos)
	var red_charge: float = 0.0
	if player_right.get("ai_is_charging"):
		red_charge = clamp(player_right.get("ai_charge_time") / 0.25, 0.0, 1.0)
	var red_contact: int = player_right._get_contact_state(red_dist, ball_y, red_charge)
	var red_contact_name: String = ["CLEAN", "STRETCH", "POPUP"][red_contact]

	# Ball info
	var ball_speed: float = ball.linear_velocity.length()
	var dist_to_net: float = absf(ball_pos.z)

	# Posture names
	var blue_posture_idx: int = player_left.paddle_posture
	var blue_pname: String
	if blue_posture_idx < player_left.DEBUG_POSTURE_NAMES.size():
		blue_pname = player_left.DEBUG_POSTURE_NAMES[blue_posture_idx]
	else:
		blue_pname = "???"

	var red_posture_idx: int = player_right.paddle_posture
	var red_pname: String
	if red_posture_idx < player_right.DEBUG_POSTURE_NAMES.size():
		red_pname = player_right.DEBUG_POSTURE_NAMES[red_posture_idx]
	else:
		red_pname = "???"

	# Serve info - serving_team is on game, not player; default to 0 (BLUE)
	var serving_team_val: int = 0
	var serving_tag: String = "BLUE" if serving_team_val == 0 else "RED"

	var debug_lines: Array[String] = []
	debug_lines.append("=== %s SERVING | aim_x=%.2f arc=%.2f ===" % [serving_tag, _serve_aim_offset_x, _trajectory_arc_offset])
	debug_lines.append("ball height=%.3f dist_net=%.2f speed=%.1f" % [ball_y, dist_to_net, ball_speed])
	debug_lines.append("--- BLUE ---")
	debug_lines.append("  posture=%s contact=%s dist=%.2f" % [blue_pname, blue_contact_name, blue_dist])
	debug_lines.append("--- RED ---")
	debug_lines.append("  posture=%s contact=%s dist=%.2f" % [red_pname, red_contact_name, red_dist])

	var debug_content := "\n".join(debug_lines)
	_scoreboard_ui.update_debug_content(debug_content)


# ── Visibility setters (forwarded to game.gd internals) ───────────────────────

func set_debug_visible(v: bool) -> void:
	# Posture ghosts — Blue only (Red/AI ghosts always hidden)
	if _player_left and _player_left.posture != null:
		var posture = _player_left.posture
		if posture.has_method("set_ghosts_visible"):
			posture.set_ghosts_visible(v)
	if _player_right and _player_right.posture != null:
		var posture = _player_right.posture
		if posture and posture.has_method("set_ghosts_visible"):
			posture.set_ghosts_visible(false)
	# Awareness grid — Blue only
	if _player_left and _player_left.has_node("awareness_grid"):
		var grid = _player_left.get_node_or_null("awareness_grid")
		if grid and grid.has_method("set_visible"):
			grid.set_visible(v)
	if _player_right and _player_right.has_node("awareness_grid"):
		var grid = _player_right.get_node_or_null("awareness_grid")
		if grid and grid.has_method("set_visible"):
			grid.set_visible(false)
	# Both players' debug visuals (indicators, step markers)
	if _player_left and _player_left.has_node("debug_visual"):
		var dv = _player_left.get_node_or_null("debug_visual")
		if dv and dv.has_method("set_debug_visible"):
			dv.set_debug_visible(v)
	if _player_right and _player_right.has_node("debug_visual"):
		var dv = _player_right.get_node_or_null("debug_visual")
		if dv and dv.has_method("set_debug_visible"):
			dv.set_debug_visible(v)


func set_debug_zones_visible(_v: bool) -> void:
	# DebugZones is a child of game.gd node; we can't find it directly from here
	# so this is a no-op — game.gd calls this on itself
	pass


func _set_debug_visuals_visible(v: bool) -> void:
	set_debug_visible(v)


func _set_debug_zones_visible(v: bool) -> void:
	set_debug_zones_visible(v)


# ── Update refs from game.gd (called each frame via update()) ─────────────────

func update_refs(
	serve_charge_time: float,
	ai_difficulty: int,
	serve_aim_offset_x: float,
	trajectory_arc_offset: float
) -> void:
	_serve_charge_time = serve_charge_time
	_ai_difficulty = ai_difficulty
	_serve_aim_offset_x = serve_aim_offset_x
	_trajectory_arc_offset = trajectory_arc_offset
