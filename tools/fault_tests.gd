extends SceneTree
## Headless tests for fault rules (rally_scorer.gd): lines, out, serve, two-bounce rule,
## kitchen volley, momentum, net ball, double bounce, post, body hit.
## Uses plain fixtures, not the real ball or player rig.
## Run: godot --headless --path . -s tools/fault_tests.gd

class FakeBall extends Node:
	signal bounced(position: Vector3)
	signal hit_by_paddle(team: int)
	signal hit_player_body(team: int)
	var last_hit_by := -1
	var bounces_since_last_hit := 0
	var was_volley := false
	var both_bounces_complete := false
	var flight_id := 1

class FakePlayer extends Node3D:
	var player_num := 0

var _fails := 0
var _checks := 0
var _gaps := 0
var _ended: Array = []
var _scorer
var _ball: FakeBall
var _blue: FakePlayer   # team 0, plays on the +z side
var _red: FakePlayer    # team 1, plays on the -z side

func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond: _fails += 1
	print("PASS  " if cond else "FAIL  ", label)

## A rule the game does not follow yet: reported, never fails the run.
func _gap(cond: bool, label: String) -> void:
	_gaps += 0 if cond else 1
	print("PASS  " if cond else "GAP   ", label)

func _is(result: Dictionary, reason: String, winner: int) -> bool:
	return not result.get("valid", true) and result.get("reason", "") == reason and int(result.get("winner", -1)) == winner

## New rally, ball last struck by `hitter` with the given state. By default the other team
## served, so the ball is a rally ball; pass `serving_team` = hitter to test a serve.
func _rally(hitter: int, bounces: int, volley: bool = false, both_bounced: bool = true, serving_team: int = -1) -> void:
	if serving_team < 0: serving_team = 1 - hitter
	_ended.clear()
	_blue.position = Vector3(1.5, 0.0, 6.9)
	_red.position = Vector3(-1.5, 0.0, -6.9)
	_scorer.cancel_rally()
	_scorer.start_rally(serving_team, true)
	_ball.last_hit_by = hitter
	_ball.bounces_since_last_hit = bounces
	_ball.was_volley = volley
	_ball.both_bounces_complete = both_bounced
	_ball.flight_id += 1

func _ended_with(reason: String, winner: int) -> bool:
	return _ended.size() == 1 and _ended[0][1] == reason and _ended[0][0] == winner

func _initialize() -> void:
	# Fixtures need to be inside the tree, which exists from the first frame.
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var Scorer = load("res://scripts/rally_scorer.gd")
	var Explainer = load("res://scripts/fault_explainer.gd")
	var C = root.get_node("PickleballConstants")
	_ball = FakeBall.new(); _blue = FakePlayer.new(); _red = FakePlayer.new()
	_red.player_num = 1
	_scorer = Scorer.new()
	for node in [_ball, _blue, _red, _scorer]: root.add_child(node)
	_scorer.set_physics_process(false)
	_scorer.bind(_ball, _blue, _red)
	_scorer.rally_ended.connect(func(winner, reason, detail): _ended.append([winner, reason, detail]))
	var half_w: float = C.COURT_WIDTH * 0.5
	var half_l: float = C.BASELINE_Z
	var nvz: float = C.NON_VOLLEY_ZONE

	# Lines are in: the whole painted line counts, nothing beyond it.
	_check(not Scorer.is_outside_painted_court(Vector3(half_w + 0.02, 0, 0)), "ball on the sideline is in")
	_check(Scorer.is_outside_painted_court(Vector3(half_w + 0.04, 0, 0)), "ball just past the sideline is out")
	_check(not Scorer.is_outside_painted_court(Vector3(0, 0, -half_l - 0.02)), "ball on the baseline is in")
	_check(Scorer.is_outside_painted_court(Vector3(0, 0, half_l + 0.04)), "ball just past the baseline is out")

	# Out: the hitter loses, judged at the first bounce only.
	_rally(0, 1)
	_ball.bounced.emit(Vector3(0, 0, -half_l - 0.5))
	_check(_ended_with("OUT_OF_BOUNDS", 1), "blue hits long: red wins, OUT_OF_BOUNDS")
	_ball.bounced.emit(Vector3(0, 0, -half_l - 0.5))
	_check(_ended.size() == 1, "a dead ball does not score twice")
	_rally(1, 2, false, true)
	_check(_scorer.check_out_of_bounds(Vector3(half_w + 1.0, 0, 3.0)).get("valid", true) == false, "out check itself flags a wide ball")
	_ball.bounced.emit(Vector3(half_w + 1.0, 0, 3.0))
	_check(_ended_with("DOUBLE_BOUNCE", 1), "second bounce outside the court is a double bounce, not out")

	# Serve landing. Blue (team 0) serves from the right, so the target box is x < 0, z < -kitchen.
	_rally(0, 1, false, false, 0)
	_check(_scorer.check_service_ball_landed(Vector3(-1.5, 0, -4.5)).get("valid", false), "serve in the diagonal box is good")
	_check(_is(_scorer.check_service_ball_landed(Vector3(-1.5, 0, -1.0)), "SHORT_SERVE", 1), "serve into the kitchen is short")
	_check(_is(_scorer.check_service_ball_landed(Vector3(-1.5, 0, -nvz + 0.01)), "SHORT_SERVE", 1), "serve just inside the kitchen is short")
	# The painted kitchen line (2.5 cm either side of 2.134 m) is part of the kitchen, so a serve
	# touching it should be short. Today only the nominal line position is compared.
	_gap(_is(_scorer.check_service_ball_landed(Vector3(-1.5, 0, -nvz - 0.02)), "SHORT_SERVE", 1), "serve on the far half of the painted kitchen line is short")
	_check(_is(_scorer.check_service_ball_landed(Vector3(1.5, 0, -4.5)), "WRONG_SERVICE_COURT", 1), "serve into the wrong box is a fault")
	_ball.bounced.emit(Vector3(-1.5, 0, -1.0))
	_check(_ended_with("SHORT_SERVE", 1), "short serve ends the rally for the receiver")
	_rally(1, 1, false, false, 1)
	_check(_scorer.check_service_ball_landed(Vector3(1.5, 0, 4.5)).get("valid", false), "red's serve from the right lands good in blue's box")
	_check(_is(_scorer.check_service_ball_landed(Vector3(-1.5, 0, 4.5)), "WRONG_SERVICE_COURT", 0), "red's serve into the wrong box is a fault")

	# Server position (team 0, +z side, serving from the right: x > 0, behind the baseline).
	_check(_scorer.check_server_position(Vector3(1.5, 0, half_l + 0.2), 0, 1).get("valid", false), "server behind the baseline on the right is legal")
	_check(_scorer.check_server_position(Vector3(1.5, 0, half_l - 0.5), 0, 1).get("reason", "") == "FOOT_FAULT", "server inside the baseline is a foot fault")
	_check(_scorer.check_server_position(Vector3(-1.5, 0, half_l + 0.2), 0, 1).get("reason", "") == "WRONG_SERVICE_COURT", "server on the wrong side of the centre line")
	_check(_scorer.check_server_position(Vector3(1.5, 0, -half_l - 0.2), 0, 1).get("reason", "") == "WRONG_HALF", "server on the opponent's half")

	# Two-bounce rule: the return and the third shot must bounce first.
	_rally(0, 0, true, false, 0)
	_check(_is(_scorer.check_actor_two_bounce_rule(1), "TWO_BOUNCE_RULE", 0), "volleying the serve is a fault")
	_ball.hit_by_paddle.emit(1)
	_check(_ended_with("TWO_BOUNCE_RULE", 0), "volleyed serve ends the rally for the server")
	_rally(0, 1, false, false, 0)
	_check(_scorer.check_actor_two_bounce_rule(1).get("valid", false), "returning the serve after its bounce is legal")
	_rally(0, 0, true, true)
	_check(_scorer.check_actor_two_bounce_rule(1).get("valid", false), "volley after both bounces is legal")

	# Kitchen: no volley while standing in it; a bounced ball may be played from there.
	_rally(0, 0, true, true)
	_red.position = Vector3(0, 0, -1.0)
	_ball.hit_by_paddle.emit(1)
	_check(_ended_with("KITCHEN_VOLLEY", 0), "volley from inside the kitchen is a fault")
	_rally(0, 1, false, true)
	_red.position = Vector3(0, 0, -1.0)
	_ball.hit_by_paddle.emit(1)
	_check(_ended.is_empty(), "bounced ball hit from inside the kitchen is legal")

	# Momentum: a legal volley, then carried into the kitchen.
	_rally(0, 0, true, true)
	_red.position = Vector3(0, 0, -nvz - 0.5)
	_ball.hit_by_paddle.emit(1)
	_check(_ended.is_empty(), "volley from behind the kitchen line is legal")
	_red.position = Vector3(0, 0, -1.0)
	_check(_is(_scorer.check_momentum_fault(), "MOMENTUM", 0), "stepping into the kitchen after a volley is a momentum fault")

	# Net ball and double bounce.
	_rally(0, 1)
	_ball.bounced.emit(Vector3(0, 0, 0.5))
	_check(_ended_with("BALL_IN_NET", 1), "shot that lands on the hitter's own side loses the point")
	_rally(0, 1)
	_ball.bounced.emit(Vector3(0, 0, -3.0))
	_check(_ended.is_empty(), "first bounce in the opponent's court keeps the rally alive")
	_ball.bounces_since_last_hit = 2
	_ball.bounced.emit(Vector3(0, 0, -4.0))
	_check(_ended_with("DOUBLE_BOUNCE", 0), "second bounce wins the point for the hitter")

	# Net post.
	_rally(1, 0)
	_scorer.on_ball_hit_post(Vector3(3.35, 0.5, 0))
	_check(_ended_with("NET_POST", 0), "hitting the post loses the point")

	# Body hits. body_struck (cosmetic: ball deflection, hit fx, Ouch bubble) fires
	# only when the scorer accepted the body-hit fault.
	var struck: Array = []
	_scorer.body_struck.connect(func(actor, evidence): struck.append([actor, evidence]))
	_rally(0, 0)
	_scorer.on_actor_body_contact(1, {"hit": true, "kind": "body", "actor_id": 1, "part": "torso", "point": Vector3(0, 1, -3)})
	_check(_ended_with("BODY_HIT", 0), "ball striking a player's body loses them the point")
	_check(struck.size() == 1 and struck[0][0] == 1 and struck[0][1].get("point") == Vector3(0, 1, -3), "accepted body hit emits body_struck once with its evidence")
	_scorer.on_actor_body_contact(1, {"hit": true, "kind": "body", "actor_id": 1, "part": "torso", "point": Vector3(0, 1, -3)})
	_check(struck.size() == 1, "a repeat contact after the point ended emits nothing")
	struck.clear()
	_rally(0, 0)
	_scorer.on_actor_body_contact(1, {"hit": true, "kind": "legal_paddle", "actor_id": 1})
	_check(_ended.is_empty(), "a paddle contact is not a body hit")
	_scorer.on_actor_body_contact(1, {"hit": true, "kind": "body", "actor_id": 1, "ambiguous": true})
	_check(_ended.is_empty(), "an ambiguous contact never awards a fault")
	_rally(0, 2)
	_scorer.on_actor_body_contact(1, {"hit": true, "kind": "body", "actor_id": 1})
	_check(_ended.is_empty(), "a ball that already bounced twice cannot body-hit")
	_check(struck.is_empty(), "rejected contacts emit no body_struck")

	# Double contact.
	_rally(1, 0)
	_scorer.on_actor_illegal_repeat_contact(1, {"new_contact": true, "fault": true, "actor_id": 1})
	_check(_ended_with("DOUBLE_CONTACT", 0), "a second separate contact is a double hit")

	# Every fault has a plain-language explanation for the player.
	var missing: Array = []
	var constants: Dictionary = Scorer.get_script_constant_map()
	for key in constants:
		if String(key).begins_with("FAULT_") and not Explainer.LINES.has(constants[key]): missing.append(constants[key])
	_check(missing.is_empty(), "every fault has an explanation (missing: %s)" % str(missing))
	_check(Explainer.explain("OUT_OF_BOUNDS", "", 0, 0).won and not Explainer.explain("OUT_OF_BOUNDS", "", 1, 0).won, "explanation knows who won")

	print("\nfault tests: %d checks, %d failed, %d known gaps" % [_checks, _fails, _gaps])
	quit(1 if _fails > 0 else 0)
