extends RefCounted
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")
## Pure standard side-out doubles ledger. It never moves a rig or awards contact.
## USA Pickleball 2026: 5.B, 5.C, 6.B.2, 21.B. First local mode is single-game 11.
## actor_id is unique; team_id and physical end are independent identities.

const RIGHT := 0
const LEFT := 1
const RULES_URL := "https://fliphtml5.com/cksih/USAP-Official-Rulebook/"
var teams: Array = [[0, 2], [1, 3]]
var starting_servers: Array = [0, 1]
var scores: Array = [0, 0]
var court_ends: Array = [1, -1]
var serving_team := 0
var server_actor := 0
var server_number := 2
var target_score := 11
var match_over := false
var winner_team := -1
var ends_changed := false
var end_change_pending := false
var rally_serial := 0
var active_rally: Dictionary = {}
var last_result: Dictionary = {}
var _last_result_open_to_correction := false

func configure(roster: Array, starters: Array, opening_team: int = 0, target: int = 11, ends: Array = [1, -1]) -> bool:
	if roster.size() != 2 or starters.size() != 2 or not opening_team in [0, 1] or not target in [11, 15, 21]: return false
	if ends.size() != 2 or not ends[0] is int or not ends[1] is int or not ends[0] in [-1, 1] or ends[1] != -ends[0]: return false
	var unique: Dictionary = {}
	for team in 2:
		if not roster[team] is Array or roster[team].size() != 2 or not starters[team] is int or not starters[team] in roster[team]: return false
		for actor in roster[team]:
			if not actor is int or actor < 0 or unique.has(actor): return false
			unique[actor] = true
	teams = roster.duplicate(true)
	starting_servers = starters.duplicate()
	court_ends = ends.duplicate()
	scores = [0, 0]
	serving_team = opening_team
	server_actor = int(starting_servers[opening_team])
	server_number = 2
	target_score = target
	match_over = false
	winner_team = -1
	ends_changed = false
	end_change_pending = false
	# Keep monotonic tokens across rematches on this ledger so an old callback
	# cannot settle the first rally of a new game.
	active_rally = {}
	last_result = {}
	_last_result_open_to_correction = false
	return true

func team_for_actor(actor_id: int) -> int:
	for team in 2:
		if actor_id in teams[team]: return team
	return -1

func partner_of(actor_id: int) -> int:
	var team := team_for_actor(actor_id)
	if team < 0: return -1
	return int(teams[team][1]) if int(teams[team][0]) == actor_id else int(teams[team][0])

func logical_court(actor_id: int) -> int:
	var team := team_for_actor(actor_id)
	if team < 0: return -1
	var starter_on_right: bool = int(scores[team]) % 2 == 0
	return RIGHT if (actor_id == int(starting_servers[team])) == starter_on_right else LEFT

func actor_in_court(team_id: int, court: int) -> int:
	if not team_id in [0, 1] or not court in [RIGHT, LEFT]: return -1
	for actor in teams[team_id]:
		if logical_court(int(actor)) == court: return int(actor)
	return -1

func correct_receiver() -> int:
	# Both players use their own net-facing right/left: equal labels are diagonal
	# world courts because the teams face opposite directions.
	return actor_in_court(1 - serving_team, logical_court(server_actor))

func score_call() -> String:
	return "%d–%d–%d" % [scores[serving_team], scores[1 - serving_team], server_number]

func service_context() -> Dictionary:
	return {"serving_team": serving_team, "server_actor": server_actor, "server_number": server_number,
		"receiver_actor": correct_receiver(), "serving_court": logical_court(server_actor), "score_call": score_call(),
		"scores": scores.duplicate(), "court_ends": court_ends.duplicate(), "match_over": match_over}

func begin_rally(actual_server: int = -1, call_facts: Dictionary = {}) -> Dictionary:
	# Called at the real serve, after the physical adapter has recorded score-call
	# positions. Beginning a new serve closes the prior rally's correction window.
	if match_over or not active_rally.is_empty() or end_change_pending: return {}
	if actual_server < 0: actual_server = server_actor
	if team_for_actor(actual_server) != serving_team: return {}
	rally_serial += 1
	_last_result_open_to_correction = false
	active_rally = service_context()
	active_rally["token"] = rally_serial
	active_rally["actual_server"] = actual_server
	active_rally["correct_server_in_position"] = bool(call_facts.get("correct_server_in_position", true))
	active_rally["correct_receiver_in_position"] = bool(call_facts.get("correct_receiver_in_position", true))
	active_rally["core_before"] = snapshot()
	active_rally["first_return_actor"] = -1
	return active_rally.duplicate(true)

func receiver_contact(actor_id: int, token: int) -> Dictionary:
	if not _active_token(token): return {"valid": false, "reason": "inactive or stale rally"}
	if int(active_rally.first_return_actor) >= 0: return {"valid": false, "reason": "serve return already recorded"}
	var receiving_team := 1 - int(active_rally.serving_team)
	if team_for_actor(actor_id) != receiving_team: return {"valid": false, "reason": "contact is not a receiving-team return"}
	active_rally.first_return_actor = actor_id
	if _score_call_positions_correct(active_rally) and actor_id != int(active_rally.receiver_actor):
		return {"valid": true, "fault_team": receiving_team, "rule": "5.C.1.c", "reason": "incorrect receiver returned serve"}
	return {"valid": true, "fault_team": -1, "position_correction_needed": _player_position_error(active_rally)}

func complete_rally(winning_team: int, token: int, reason: String = "") -> Dictionary:
	# Physical legality/momentum settlement is external and must finish first.
	if not _active_token(token) or not winning_team in [0, 1]: return {"accepted": false, "reason": "inactive, duplicate or invalid result"}
	var context: Dictionary = active_rally.duplicate(true)
	active_rally = {}
	var outcome := _apply_winner(winning_team)
	last_result = {"token": token, "winning_team": winning_team, "reason": reason, "rally": context,
		"core_before": context.core_before, "outcome": outcome.duplicate(true)}
	_last_result_open_to_correction = true
	return outcome

func confirm_end_change() -> bool:
	# The scene adapter must complete controlled dead-ball repositioning first.
	if not active_rally.is_empty() or not end_change_pending: return false
	court_ends = [-int(court_ends[0]), -int(court_ends[1])]
	end_change_pending = false
	ends_changed = true
	return true

func cancel_rally() -> void:
	# Explicit scene/practice/reset cancellation, distinct from a live replay.
	active_rally = {}
	_last_result_open_to_correction = false

func snapshot() -> Dictionary:
	return {"teams": teams.duplicate(true), "starting_servers": starting_servers.duplicate(), "scores": scores.duplicate(),
		"court_ends": court_ends.duplicate(), "serving_team": serving_team, "server_actor": server_actor,
		"server_number": server_number, "target_score": target_score, "match_over": match_over,
		"winner_team": winner_team, "ends_changed": ends_changed, "end_change_pending": end_change_pending}

func _apply_winner(winning_team: int) -> Dictionary:
	var previous_server := server_actor
	var point := winning_team == serving_team
	var side_out := false
	if point:
		scores[serving_team] += 1
		if int(scores[serving_team]) >= target_score and int(scores[serving_team]) - int(scores[1 - serving_team]) >= 2:
			match_over = true
			winner_team = serving_team
	elif server_number == 1:
		server_actor = partner_of(server_actor)
		server_number = 2
	else:
		serving_team = 1 - serving_team
		server_actor = actor_in_court(serving_team, RIGHT)
		server_number = 1
		side_out = true
	var threshold := 6 if target_score == 11 else (8 if target_score == 15 else 11)
	if RuntimePolicy.end_change_at > 0: threshold = RuntimePolicy.end_change_at
	if not ends_changed and not match_over and maxi(int(scores[0]), int(scores[1])) >= threshold: end_change_pending = true
	return {"accepted": true, "point_scored": point, "side_out": side_out, "previous_server": previous_server,
		"serving_team": serving_team, "server_actor": server_actor, "server_number": server_number,
		"scores": scores.duplicate(), "score_call": score_call(), "match_over": match_over,
		"winner_team": winner_team, "end_change_pending": end_change_pending}

func _active_token(token: int) -> bool:
	return not active_rally.is_empty() and int(active_rally.token) == token and not match_over

func _score_call_positions_correct(context: Dictionary) -> bool:
	return bool(context.correct_server_in_position) and bool(context.correct_receiver_in_position)

func _player_position_error(context: Dictionary) -> bool:
	return not _score_call_positions_correct(context) or int(context.actual_server) != int(context.server_actor)

func _restore_core(state: Dictionary) -> void:
	teams = state.teams.duplicate(true)
	starting_servers = state.starting_servers.duplicate()
	scores = state.scores.duplicate()
	court_ends = state.court_ends.duplicate()
	serving_team = int(state.serving_team)
	server_actor = int(state.server_actor)
	server_number = int(state.server_number)
	target_score = int(state.target_score)
	match_over = bool(state.match_over)
	winner_team = int(state.winner_team)
	ends_changed = bool(state.ends_changed)
	end_change_pending = bool(state.end_change_pending)
