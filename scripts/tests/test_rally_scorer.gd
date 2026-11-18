class_name TestRallyScorer extends RefCounted














const _RallyScorer: = preload("res://scripts/rally_scorer.gd")
const _FakeBall: = preload("res://scripts/tests/fakes/fake_ball.gd")
const _FakePlayer: = preload("res://scripts/tests/fakes/fake_player.gd")

var _current_failures: Array[String] = []
var _current_test_name: String = ""
var _fixture_nodes: Array[Node] = []


func run_all(totals: Dictionary) -> void :
	var tests: Array[Callable] = [

		test_oob_blue_rolled_out_after_bounce, 
		test_oob_red_rolled_out_after_bounce, 
		test_oob_red_shot_long_past_blue_baseline, 
		test_oob_blue_shot_long_past_red_baseline, 
		test_oob_sideline_wide_after_bounce, 
		test_oob_sideline_wide_shot, 

		test_double_bounce_blue_fails, 
		test_double_bounce_red_fails, 

		test_ball_in_net_blue_weak_hit, 
		test_ball_in_net_red_weak_hit, 

		test_kitchen_volley_blue_at_hit, 
		test_kitchen_volley_red_at_hit, 
		test_legal_volley_outside_kitchen, 
		test_groundstroke_near_kitchen_is_legal, 

		test_momentum_fault_fires_within_window, 
		test_momentum_fault_no_fire_on_retreat, 
		test_momentum_fault_window_expiry, 
		test_momentum_fault_groundstroke_not_watched, 

		test_two_bounce_blue_illegal_volley_of_serve, 
		test_two_bounce_blue_legal_return_after_bounce, 
		test_two_bounce_red_illegal_return_of_return, 
		test_two_bounce_legal_volley_after_both_bounces, 
		test_hit_signal_preserves_legal_bounce, 
		test_hit_signal_rejects_early_volley, 

		test_short_serve_blue, 
		test_wrong_service_court_blue, 
		test_valid_serve_lands_correct_diagonal, 
		test_short_serve_red, 
		test_red_serve_diagonal_both_parities, 

		test_server_position_valid, 
		test_server_position_uses_upcoming_serve_context, 
		test_server_position_wrong_half, 
		test_server_position_wrong_court, 
		test_server_position_foot_fault, 

		test_body_hit_ignored_when_ball_bouncing, 
		test_body_hit_no_suppression, 

		test_net_touch_blue_body_at_net, 
		test_net_touch_red_body_at_net, 
		test_net_touch_paddle_only, 
		test_net_touch_safe_distance, 
		test_net_touch_sag_profile, 

		test_precedence_two_bounce_beats_kitchen, 
		test_precedence_double_bounce_over_oob, 

		test_regression_oob_baseline_not_inverted, 
		test_regression_oob_uses_last_hit_by, 
		test_regression_receiver_fails_after_legal_bounce, 
	]
	for t in tests:
		_current_test_name = t.get_method()
		_current_failures = []
		t.call()
		for node in _fixture_nodes:
			if is_instance_valid(node): node.free()
		_fixture_nodes.clear()
		if _current_failures.is_empty():
			totals.pass += 1
		else:
			totals.fail += 1
			for f in _current_failures:
				totals.errors.append("%s: %s" % [_current_test_name, f])


func _scorer(serving_team: int = 0, from_right: bool = true) -> RallyScorer:
	var s: = _RallyScorer.new()
	_fixture_nodes.append(s)
	s.start_rally(serving_team, from_right)
	return s

func _ball() -> FakeBall:
	return _FakeBall.new()

func _player(num: int, pos: Vector3) -> FakePlayer:
	var player: = _FakePlayer.new(num, pos)
	_fixture_nodes.append(player)
	return player



func _assert_eq(actual, expected, msg: String = "") -> void :
	if actual != expected:
		_current_failures.append("expected %s, got %s %s" % [str(expected), str(actual), msg])

func _assert_true(cond: bool, msg: String = "") -> void :
	if not cond:
		_current_failures.append("expected true %s" % msg)

func _assert_false(cond: bool, msg: String = "") -> void :
	if cond:
		_current_failures.append("expected false %s" % msg)


func test_oob_blue_rolled_out_after_bounce() -> void :


	var s: = _scorer()
	var b: = _ball()
	b.last_hit_by = 1
	b.bounces_since_last_hit = 2
	b.global_position = Vector3(0, 0.1, 7.5)
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_double_bounce_and_net_ball(b.global_position)
	_assert_false(r["valid"])
	_assert_eq(r["winner"], 1)
	_assert_eq(r["reason"], _RallyScorer.FAULT_DOUBLE_BOUNCE)

func test_oob_red_rolled_out_after_bounce() -> void :
	var s: = _scorer()
	var b: = _ball()
	b.last_hit_by = 0
	b.bounces_since_last_hit = 2
	b.global_position = Vector3(0, 0.1, -7.5)
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_double_bounce_and_net_ball(b.global_position)
	_assert_eq(r["winner"], 0)

func test_oob_red_shot_long_past_blue_baseline() -> void :

	var s: = _scorer()
	var b: = _ball()
	b.last_hit_by = 1
	b.bounces_since_last_hit = 0
	b.global_position = Vector3(0, 0.3, 7.2)
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_out_of_bounds(b.global_position)
	_assert_false(r["valid"])
	_assert_eq(r["winner"], 0, "Blue wins — Red shot long")

func test_oob_blue_shot_long_past_red_baseline() -> void :
	var s: = _scorer()
	var b: = _ball()
	b.last_hit_by = 0
	b.bounces_since_last_hit = 0
	b.global_position = Vector3(0, 0.3, -7.2)
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_out_of_bounds(b.global_position)
	_assert_eq(r["winner"], 1)

func test_oob_sideline_wide_after_bounce() -> void :

	var s: = _scorer()
	var b: = _ball()
	b.last_hit_by = 1
	b.bounces_since_last_hit = 2
	b.global_position = Vector3(3.5, 0.2, 4.0)
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_double_bounce_and_net_ball(b.global_position)
	_assert_eq(r["winner"], 1)

func test_oob_sideline_wide_shot() -> void :

	var s: = _scorer()
	var b: = _ball()
	b.last_hit_by = 1
	b.bounces_since_last_hit = 0
	b.global_position = Vector3(3.5, 0.3, 4.0)
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_out_of_bounds(b.global_position)
	_assert_eq(r["winner"], 0, "Blue wins — Red shot wide")


func test_double_bounce_blue_fails() -> void :
	var s: = _scorer()
	var b: = _ball()
	b.last_hit_by = 1
	b.bounces_since_last_hit = 2
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_double_bounce_and_net_ball(Vector3(0, 0.1, 3.0))
	_assert_false(r["valid"])
	_assert_eq(r["winner"], 1)
	_assert_eq(r["reason"], _RallyScorer.FAULT_DOUBLE_BOUNCE)

func test_double_bounce_red_fails() -> void :
	var s: = _scorer()
	var b: = _ball()
	b.last_hit_by = 0
	b.bounces_since_last_hit = 2
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_double_bounce_and_net_ball(Vector3(0, 0.1, -3.0))
	_assert_eq(r["winner"], 0)
	_assert_eq(r["reason"], _RallyScorer.FAULT_DOUBLE_BOUNCE)


func test_ball_in_net_blue_weak_hit() -> void :

	var s: = _scorer()
	var b: = _ball()
	b.last_hit_by = 0
	b.bounces_since_last_hit = 1
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_double_bounce_and_net_ball(Vector3(0, 0.1, 3.0))
	_assert_false(r["valid"])
	_assert_eq(r["winner"], 1)
	_assert_eq(r["reason"], _RallyScorer.FAULT_BALL_IN_NET)

func test_ball_in_net_red_weak_hit() -> void :
	var s: = _scorer()
	var b: = _ball()
	b.last_hit_by = 1
	b.bounces_since_last_hit = 1
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_double_bounce_and_net_ball(Vector3(0, 0.1, -3.0))
	_assert_eq(r["winner"], 0)
	_assert_eq(r["reason"], _RallyScorer.FAULT_BALL_IN_NET)


func test_kitchen_volley_blue_at_hit() -> void :
	var s: = _scorer()
	var b: = _ball()
	b.was_volley = true
	s.bind(b, _player(0, Vector3(0, 1, 1.0)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_kitchen_volley_at_hit(0, 1.0)
	_assert_false(r["valid"])
	_assert_eq(r["winner"], 1)
	_assert_eq(r["reason"], _RallyScorer.FAULT_KITCHEN_VOLLEY)

func test_kitchen_volley_red_at_hit() -> void :
	var s: = _scorer()
	var b: = _ball()
	b.was_volley = true
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -1.0)))
	var r: = s.check_kitchen_volley_at_hit(1, -1.0)
	_assert_eq(r["winner"], 0)

func test_legal_volley_outside_kitchen() -> void :
	var s: = _scorer()
	var b: = _ball()
	b.was_volley = true
	s.bind(b, _player(0, Vector3(0, 1, 2.5)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_kitchen_volley_at_hit(0, 2.5)
	_assert_true(r["valid"], "legal volley outside kitchen")

func test_groundstroke_near_kitchen_is_legal() -> void :
	var s: = _scorer()
	var b: = _ball()
	b.was_volley = false
	s.bind(b, _player(0, Vector3(0, 1, 1.5)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_kitchen_volley_at_hit(0, 1.5)
	_assert_true(r["valid"], "groundstroke in kitchen is legal")


func test_momentum_fault_fires_within_window() -> void :
	var s: = _scorer()
	var blue: = _player(0, Vector3(0, 1, 2.5))
	s.bind(_ball(), blue, _player(1, Vector3(0, 1, -6.8)))

	s._last_volley_time_msec = Time.get_ticks_msec()
	s._last_volley_player = 0

	blue.global_position = Vector3(0, 1, 1.5)
	var r: = s.check_momentum_fault()
	_assert_false(r["valid"])
	_assert_eq(r["winner"], 1)
	_assert_eq(r["reason"], _RallyScorer.FAULT_MOMENTUM)

func test_momentum_fault_no_fire_on_retreat() -> void :
	var s: = _scorer()
	var blue: = _player(0, Vector3(0, 1, 2.5))
	s.bind(_ball(), blue, _player(1, Vector3(0, 1, -6.8)))
	s._last_volley_time_msec = Time.get_ticks_msec()
	s._last_volley_player = 0
	blue.global_position = Vector3(0, 1, 3.5)
	var r: = s.check_momentum_fault()
	_assert_true(r["valid"])

func test_momentum_fault_window_expiry() -> void :
	var s: = _scorer()
	var blue: = _player(0, Vector3(0, 1, 1.5))
	s.bind(_ball(), blue, _player(1, Vector3(0, 1, -6.8)))

	s._last_volley_time_msec = Time.get_ticks_msec() - 1000
	s._last_volley_player = 0
	var r: = s.check_momentum_fault()
	_assert_true(r["valid"], "window expired")
	_assert_eq(s._last_volley_player, -1, "player cleared after expiry")

func test_momentum_fault_groundstroke_not_watched() -> void :

	var s: = _scorer()
	s.bind(_ball(), _player(0, Vector3(0, 1, 1.5)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_momentum_fault()
	_assert_true(r["valid"])


func test_two_bounce_blue_illegal_volley_of_serve() -> void :
	var s: = _scorer()
	var b: = _ball()
	b.both_bounces_complete = false
	b.ball_bounced_since_last_hit = false
	b.was_volley = true
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_two_bounce_rule(0)
	_assert_false(r["valid"])
	_assert_eq(r["reason"], _RallyScorer.FAULT_TWO_BOUNCE_RULE)
	_assert_eq(r["winner"], 1)

func test_two_bounce_blue_legal_return_after_bounce() -> void :
	var s: = _scorer()
	var b: = _ball()
	b.both_bounces_complete = false
	b.ball_bounced_since_last_hit = true
	b.was_volley = false
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_two_bounce_rule(0)
	_assert_true(r["valid"])

func test_two_bounce_red_illegal_return_of_return() -> void :
	var s: = _scorer()
	var b: = _ball()
	b.both_bounces_complete = false
	b.ball_bounced_since_last_hit = false
	b.was_volley = true
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_two_bounce_rule(1)
	_assert_false(r["valid"])
	_assert_eq(r["winner"], 0)

func test_two_bounce_legal_volley_after_both_bounces() -> void :
	var s: = _scorer()
	var b: = _ball()
	b.both_bounces_complete = true
	b.ball_bounced_since_last_hit = false
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_two_bounce_rule(0)
	_assert_true(r["valid"])

func test_hit_signal_preserves_legal_bounce() -> void :
	var s: = _scorer()
	var b: = Ball.new()
	b.ball_bounced_since_last_hit = true
	b.both_bounces_complete = false
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var faults: Array[String] = []
	s.rally_ended.connect( func(_winner: int, reason: String, _detail: String) -> void : faults.append(reason))
	s.start_rally(0, true)
	b.hit_by_player(1)
	_assert_true(faults.is_empty(), "return after a bounce stays legal through the hit signal")
	b.free()
	s.free()

func test_hit_signal_rejects_early_volley() -> void :
	var s: = _scorer()
	var b: = Ball.new()
	b.ball_bounced_since_last_hit = false
	b.both_bounces_complete = false
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var faults: Array[String] = []
	s.rally_ended.connect( func(_winner: int, reason: String, _detail: String) -> void : faults.append(reason))
	s.start_rally(0, true)
	b.hit_by_player(1)
	_assert_eq(faults.size(), 1, "early volley emits a fault")
	if not faults.is_empty():
		_assert_eq(faults[0], _RallyScorer.FAULT_TWO_BOUNCE_RULE)
	b.free()
	s.free()


func test_short_serve_blue() -> void :

	var s: = _scorer(0, true)
	s.bind(_ball(), _player(0, Vector3(1.5, 1, 6.8)), _player(1, Vector3(-1.5, 1, -6.8)))
	var r: = s.check_service_ball_landed(Vector3(-1.5, 0.1, -1.5))
	_assert_false(r["valid"])
	_assert_eq(r["reason"], _RallyScorer.FAULT_SHORT_SERVE)
	_assert_eq(r["winner"], 1)

func test_wrong_service_court_blue() -> void :

	var s: = _scorer(0, true)
	s.bind(_ball(), _player(0, Vector3(1.5, 1, 6.8)), _player(1, Vector3(-1.5, 1, -6.8)))
	var r: = s.check_service_ball_landed(Vector3(1.5, 0.1, -4.0))
	_assert_false(r["valid"])
	_assert_eq(r["reason"], _RallyScorer.FAULT_WRONG_SERVICE_COURT)

func test_valid_serve_lands_correct_diagonal() -> void :
	var s: = _scorer(0, true)
	s.bind(_ball(), _player(0, Vector3(1.5, 1, 6.8)), _player(1, Vector3(-1.5, 1, -6.8)))
	var r: = s.check_service_ball_landed(Vector3(-1.5, 0.1, -4.0))
	_assert_true(r["valid"])

func test_short_serve_red() -> void :
	var s: = _scorer(1, true)
	s.bind(_ball(), _player(0, Vector3(-1.5, 1, 6.8)), _player(1, Vector3(-1.5, 1, -6.8)))
	var r: = s.check_service_ball_landed(Vector3(1.5, 0.1, 1.5))
	_assert_false(r["valid"])
	_assert_eq(r["winner"], 0)

func test_red_serve_diagonal_both_parities() -> void :
	var s: = _scorer(1, true)
	_assert_true(s.check_service_ball_landed(Vector3(1.5, 0.1, 4.5))["valid"])
	_assert_eq(s.check_service_ball_landed(Vector3(-1.5, 0.1, 4.5))["reason"], _RallyScorer.FAULT_WRONG_SERVICE_COURT)
	s.start_rally(1, false)
	_assert_true(s.check_service_ball_landed(Vector3(-1.5, 0.1, 4.5))["valid"])
	_assert_eq(s.check_service_ball_landed(Vector3(1.5, 0.1, 4.5))["reason"], _RallyScorer.FAULT_WRONG_SERVICE_COURT)

func test_server_position_uses_upcoming_serve_context() -> void :
	var s: = _scorer(0, true)
	_assert_true(s.check_server_position(Vector3(-1.5, 1, -6.8), 1, 1)["valid"])
	_assert_true(s.check_server_position(Vector3(1.5, 1, -6.8), 1, 0)["valid"])


func test_server_position_valid() -> void :
	var s: = _scorer(0, true)
	s.bind(_ball(), _player(0, Vector3(1.5, 1, 6.8)), _player(1, Vector3(-1.5, 1, -6.8)))
	var r: = s.check_server_position(Vector3(1.5, 1, 6.8))
	_assert_true(r["valid"])

func test_server_position_wrong_half() -> void :
	var s: = _scorer(0, true)
	s.bind(_ball(), _player(0, Vector3(1.5, 1, 6.8)), _player(1, Vector3(-1.5, 1, -6.8)))
	var r: = s.check_server_position(Vector3(1.5, 1, -1.0))
	_assert_eq(r["reason"], _RallyScorer.FAULT_WRONG_HALF)

func test_server_position_wrong_court() -> void :

	var s: = _scorer(0, true)
	s.bind(_ball(), _player(0, Vector3(-1.5, 1, 6.8)), _player(1, Vector3(-1.5, 1, -6.8)))
	var r: = s.check_server_position(Vector3(-1.5, 1, 6.8))
	_assert_eq(r["reason"], _RallyScorer.FAULT_WRONG_SERVICE_COURT)

func test_server_position_foot_fault() -> void :
	var s: = _scorer(0, true)
	s.bind(_ball(), _player(0, Vector3(1.5, 1, 6.0)), _player(1, Vector3(-1.5, 1, -6.8)))
	var r: = s.check_server_position(Vector3(1.5, 1, 6.0))
	_assert_eq(r["reason"], _RallyScorer.FAULT_FOOT_FAULT)


func test_body_hit_ignored_when_ball_bouncing() -> void :


	var s: = _scorer()
	var b: = _ball()
	b.bounces_since_last_hit = 3
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))



	_assert_true(int(b.get("bounces_since_last_hit")) >= 2)

func test_body_hit_no_suppression() -> void :



	var s: = _scorer()
	var b: = _ball()
	b.bounces_since_last_hit = 0
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))

	s._last_paddle_hit_msec = 0
	_assert_true(int(b.get("bounces_since_last_hit")) < 2)


func test_net_touch_blue_body_at_net() -> void :
	var s: = _scorer()
	s.bind(_ball(), _player(0, Vector3(0, 0.3, 0.05)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_net_touch()
	_assert_false(r["valid"])
	_assert_eq(r["winner"], 1)
	_assert_eq(r["reason"], _RallyScorer.FAULT_NET_TOUCH)

func test_net_touch_red_body_at_net() -> void :
	var s: = _scorer()
	s.bind(_ball(), _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 0.3, -0.05)))
	var r: = s.check_net_touch()
	_assert_eq(r["winner"], 0)

func test_net_touch_paddle_only() -> void :
	var s: = _scorer()
	var blue: = _player(0, Vector3(0, 1, 0.5))
	blue.paddle_position = Vector3(0, 0.4, 0.08)
	s.bind(_ball(), blue, _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_net_touch()
	_assert_false(r["valid"])
	_assert_eq(r["winner"], 1)

func test_net_touch_safe_distance() -> void :
	var s: = _scorer()
	var blue: = _player(0, Vector3(0, 1, 0.5))
	blue.paddle_position = Vector3(0, 1, 0.4)
	s.bind(_ball(), blue, _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_net_touch()
	_assert_true(r["valid"])


func test_precedence_two_bounce_beats_kitchen() -> void :




	var s: = _scorer()
	var b: = _ball()
	b.both_bounces_complete = false
	b.ball_bounced_since_last_hit = false
	b.was_volley = true
	s.bind(b, _player(0, Vector3(0, 1, 1.0)), _player(1, Vector3(0, 1, -6.8)))
	var tbr: = s.check_two_bounce_rule(0)
	var kv: = s.check_kitchen_volley_at_hit(0, 1.0)
	_assert_false(tbr["valid"])
	_assert_false(kv["valid"])

	_assert_eq(tbr["reason"], _RallyScorer.FAULT_TWO_BOUNCE_RULE)

func test_precedence_double_bounce_over_oob() -> void :



	var s: = _scorer()
	var b: = _ball()
	b.last_hit_by = 1
	b.bounces_since_last_hit = 2
	b.global_position = Vector3(0, 0.1, 7.5)
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var db: = s.check_double_bounce_and_net_ball(Vector3(0, 0.1, 6.0))
	_assert_false(db["valid"])
	_assert_eq(db["reason"], _RallyScorer.FAULT_DOUBLE_BOUNCE)
	_assert_eq(db["winner"], 1)


func test_regression_oob_baseline_not_inverted() -> void :


	var s: = _scorer()
	var b: = _ball()
	b.last_hit_by = 1
	b.bounces_since_last_hit = 2
	b.global_position = Vector3(0, 0.1, 7.5)
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_double_bounce_and_net_ball(b.global_position)
	_assert_eq(r["winner"], 1, "Red must win — Blue failed to return (not inverted)")

func test_regression_oob_uses_last_hit_by() -> void :


	var s: = _scorer()
	var b: = _ball()
	b.last_hit_by = 1
	b.bounces_since_last_hit = 0
	b.global_position = Vector3(0, 0.3, 7.2)
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_out_of_bounds(b.global_position)
	_assert_eq(r["winner"], 0, "Blue wins — Red's shot was long")

func test_regression_receiver_fails_after_legal_bounce() -> void :



	var s: = _scorer()
	var b: = _ball()
	b.last_hit_by = 1
	b.bounces_since_last_hit = 2
	b.global_position = Vector3(1.2, 0.2, 7.1)
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r: = s.check_double_bounce_and_net_ball(b.global_position)
	_assert_eq(r["winner"], 1, "Red wins when Blue deliberately fails to return")
	_assert_eq(r["reason"], _RallyScorer.FAULT_DOUBLE_BOUNCE)


func test_net_touch_sag_profile() -> void :
	var profile = preload("res://scripts/net_profile.gd")
	for offender in [0, 1]:
		for x in [-3.05, 0.0, 3.05]:
			for paddle_only in [false, true]:
				var s: = _scorer()
				var blue: = _player(0, Vector3(0, 1.2, 4.0))
				var red: = _player(1, Vector3(0, 1.2, -4.0))
				var b: = _ball()
				var player = blue if offender == 0 else red
				var direction: float = 1.0 if offender == 0 else -1.0
				var top: float = profile.top_y_at(x)
				if paddle_only:

					player.global_position = Vector3(0.0, 1.2, direction * 0.5)
					player.paddle_position = Vector3(x, top - 0.002, direction * 0.05)
				else:
					player.global_position = Vector3(x, top - 0.002, direction * 0.05)
					player.paddle_position = Vector3(x, top + 0.05, direction * 0.4)
				s.bind(b, blue, red)
				var result: Dictionary = s.check_net_touch()
				_assert_false(result.valid, "below visible sagging tape must touch")
				_assert_eq(result.winner, 1 - offender, "same scoring semantics")
				_assert_eq(result.reason, _RallyScorer.FAULT_NET_TOUCH)
				if paddle_only: player.paddle_position.y = top + 0.002
				else: player.global_position.y = top + 0.002
				_assert_true(s.check_net_touch().valid, "above visible tape must not touch")
				s.free();blue.free();red.free()
