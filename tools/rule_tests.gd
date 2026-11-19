extends SceneTree
## Headless rule tests for the doubles ledger.
## Run: godot --headless --path . -s tools/rule_tests.gd

const State := preload("res://scripts/doubles_match_state.gd")
var _fails := 0
var _checks := 0

func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("PASS  ", label)
	else:
		_fails += 1
		print("FAIL  ", label)

func _new() -> State:
	var s := State.new()
	assert(s.configure([[0, 2], [1, 3]], [0, 1], 0, 11, [1, -1]))
	return s

# Serve one rally: begin, then resolve for the winner.
func _rally(s: State, winner: int) -> Dictionary:
	var r: Dictionary = s.begin_rally(s.server_actor, {"correct_server_in_position": true, "correct_receiver_in_position": true})
	if r.is_empty(): return {"accepted": false, "reason": "begin_rally refused"}
	return s.complete_rally(winner, int(r.token))

func _init() -> void:
	# 0-0-2 start: opening team has one server.
	var s := _new()
	_check(s.score_call() == "0–0–2", "opening call is 0-0-2")
	_check(s.serving_team == 0 and s.server_number == 2, "opening team serves as server 2")

	# First fault by the opening team is an immediate side-out (no second server).
	var out := _rally(s, 1)
	_check(out.get("accepted", false) and out.side_out, "0-0-2 loss is a side-out")
	_check(s.serving_team == 1 and s.server_number == 1 and s.scores == [0, 0], "side-out hands serve to team 1 as server 1, score unchanged")

	# Server 1 -> server 2 rotation on a lost rally; teammate becomes server.
	var first_server := s.server_actor
	out = _rally(s, 0)
	_check(not out.side_out and s.serving_team == 1 and s.server_number == 2, "server 1 loses: partner serves as server 2")
	_check(s.server_actor == s.partner_of(first_server) and s.server_actor != first_server, "server 2 is the teammate")
	_check(s.scores == [0, 0], "no points scored on a lost serve")

	# Server 2 loses: side-out back to team 0 as server 1.
	out = _rally(s, 0)
	_check(out.side_out and s.serving_team == 0 and s.server_number == 1, "server 2 loses: side-out, new team server 1")

	# Only the serving team scores; side switching of the server's court follows score parity.
	var court_before := s.logical_court(s.server_actor)
	out = _rally(s, 0)
	_check(out.point_scored and s.scores == [1, 0], "serving team scores a point")
	_check(s.logical_court(s.server_actor) != court_before, "server switches courts after a point")
	out = _rally(s, 1)
	_check(not out.point_scored and s.scores == [1, 0], "receiving team win never scores")

	# End change: pending when a team reaches 6, only once, confirmed explicitly.
	s = _new()
	s.serving_team = 0; s.server_actor = 0; s.server_number = 1
	for i in 5:
		_rally(s, 0)
	_check(s.scores[0] == 5 and not s.end_change_pending, "no end change at 5")
	_rally(s, 0)
	_check(s.scores[0] == 6 and s.end_change_pending, "end change pending at 6")
	_check(s.begin_rally(s.server_actor, {"correct_server_in_position": true, "correct_receiver_in_position": true}).is_empty(), "no serve while end change is pending")
	var ends_before: Array = s.court_ends.duplicate()
	_check(s.confirm_end_change(), "end change confirmed")
	_check(s.court_ends == [-ends_before[0], -ends_before[1]] and s.ends_changed and not s.end_change_pending, "ends swapped once")
	for i in 3:
		_rally(s, 0)
	_check(not s.end_change_pending, "end change does not trigger again")

	# Win by 2: 11 alone is not enough at 10-10.
	s = _new()
	s.scores = [10, 10]; s.serving_team = 0; s.server_actor = 0; s.server_number = 1
	s.ends_changed = true
	_rally(s, 0)
	_check(s.scores == [11, 10] and not s.match_over, "11-10 does not end the game")
	_rally(s, 0)
	_check(s.scores == [12, 10] and s.match_over and s.winner_team == 0, "12-10 ends the game, team 0 wins")

	# Plain win at 11-0 style margin.
	s = _new()
	s.scores = [10, 3]; s.serving_team = 0; s.server_actor = 0; s.server_number = 1
	s.ends_changed = true
	_rally(s, 0)
	_check(s.match_over and s.winner_team == 0 and s.scores == [11, 3], "11-3 ends the game")
	_check(_rally(s, 0).get("accepted", false) == false, "no rallies after the match is over")

	# Lead of 2 held by the receiving side: the serving team cannot lose by scoring.
	s = _new()
	s.scores = [9, 10]; s.serving_team = 1; s.server_actor = 1; s.server_number = 1
	s.ends_changed = true
	_rally(s, 1)
	_check(s.scores == [9, 11] and s.match_over and s.winner_team == 1, "team 1 wins 11-9")

	print("\nrule tests: %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
