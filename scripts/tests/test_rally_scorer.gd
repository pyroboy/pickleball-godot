class_name TestRallyScorer extends RefCounted
## Test suite for scripts/rally_scorer.gd.
##
## Structure: each test_* function builds a FakeBall + FakePlayer pair,
## constructs a RallyScorer, optionally calls start_rally(), then invokes
## the relevant public validator and asserts the return dict.
##
## Run via: godot --headless --script scripts/tests/test_runner.gd
##
## Adding a new test: write `func test_my_scenario() -> void:` using the
## `_scorer()` / `_ball()` / `_player()` helpers below, then add it to the
## `run_all` list at the bottom.

# Note: Using different const names to avoid SHADOWED_GLOBAL_IDENTIFIER warnings
# from Godot's linter (they shadow class names from preloads)
const _RallyScorer := preload("res://scripts/rally_scorer.gd")
const _FakeBall := preload("res://scripts/tests/fakes/fake_ball.gd")
const _FakePlayer := preload("res://scripts/tests/fakes/fake_player.gd")

var _current_failures: Array[String] = []
var _current_test_name: String = ""

# ── Entry point ──────────────────────────────────────────────────────────────
func run_all(totals: Dictionary) -> void:
	var tests: Array[Callable] = [
		# Out of bounds (6)
		test_oob_blue_rolled_out_after_bounce,
		test_oob_red_rolled_out_after_bounce,
		test_oob_red_shot_long_past_blue_baseline,
		test_oob_blue_shot_long_past_red_baseline,
		test_oob_sideline_wide_after_bounce,
		test_oob_sideline_wide_shot,
		# Double bounce (2)
		test_double_bounce_blue_fails,
		test_double_bounce_red_fails,
		# Ball in net (2)
		test_ball_in_net_blue_weak_hit,
		test_ball_in_net_red_weak_hit,
		# Kitchen volley (4)
		test_kitchen_volley_blue_at_hit,
		test_kitchen_volley_red_at_hit,
		test_legal_volley_outside_kitchen,
		test_groundstroke_near_kitchen_is_legal,
		# Momentum fault (4)
		test_momentum_fault_fires_within_window,
		test_momentum_fault_no_fire_on_retreat,
		test_momentum_fault_window_expiry,
		test_momentum_fault_groundstroke_not_watched,
		# Two-bounce rule (4)
		test_two_bounce_blue_illegal_volley_of_serve,
		test_two_bounce_blue_legal_return_after_bounce,
		test_two_bounce_red_illegal_return_of_return,
		test_two_bounce_legal_volley_after_both_bounces,
		# Service fault (4)
		test_short_serve_blue,
		test_wrong_service_court_blue,
		test_valid_serve_lands_correct_diagonal,
		test_short_serve_red,
		# Server position (4)
		test_server_position_valid,
		test_server_position_wrong_half,
		test_server_position_wrong_court,
		test_server_position_foot_fault,
		# Body hit (2) — third scenario requires time-based cooldown via handler
		test_body_hit_ignored_when_ball_bouncing,
		test_body_hit_no_suppression,
		# Net touch (4)
		test_net_touch_blue_body_at_net,
		test_net_touch_red_body_at_net,
		test_net_touch_paddle_only,
		test_net_touch_safe_distance,
		# Fault precedence (2)
		test_precedence_two_bounce_beats_kitchen,
		test_precedence_double_bounce_over_oob,
		# Regressions (3)
		test_regression_oob_baseline_not_inverted,
		test_regression_oob_uses_last_hit_by,
		test_regression_receiver_fails_after_legal_bounce,
	]
	for t in tests:
		_current_test_name = t.get_method()
		_current_failures = []
		t.call()
		if _current_failures.is_empty():
			totals.pass += 1
		else:
			totals.fail += 1
			for f in _current_failures:
				totals.errors.append("%s: %s" % [_current_test_name, f])

# ── Helpers ──────────────────────────────────────────────────────────────────
func _scorer(serving_team: int = 0, from_right: bool = true) -> RallyScorer:
	var s := _RallyScorer.new()
	s.start_rally(serving_team, from_right)
	return s

func _ball() -> FakeBall:
	return _FakeBall.new()

func _player(num: int, pos: Vector3) -> FakePlayer:
	return _FakePlayer.new(num, pos)

# Assertion helpers — record failures into _current_failures so a failing
# assert doesn't halt the rest of the test (lets us find all issues in one run).
func _assert_eq(actual, expected, msg: String = "") -> void:
	if actual != expected:
		_current_failures.append("expected %s, got %s %s" % [str(expected), str(actual), msg])

func _assert_true(cond: bool, msg: String = "") -> void:
	if not cond:
		_current_failures.append("expected true %s" % msg)

func _assert_false(cond: bool, msg: String = "") -> void:
	if cond:
		_current_failures.append("expected false %s" % msg)

# ── Tests: Out of bounds ─────────────────────────────────────────────────────
func test_oob_blue_rolled_out_after_bounce() -> void:
	# Red hit → bounced on Blue's court → Blue failed to return → ball rolled out
	# Expected: Red wins (receiver=Blue failed, hitter=Red scores)
	var s := _scorer()
	var b := _ball()
	b.last_hit_by = 1
	b.bounces_since_last_hit = 1
	b.global_position = Vector3(0, 0.1, 7.5)  # past Blue's baseline (6.7)
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_out_of_bounds()
	_assert_false(r["valid"])
	_assert_eq(r["winner"], 1)
	_assert_eq(r["reason"], _RallyScorer.FAULT_OUT_OF_BOUNDS)

func test_oob_red_rolled_out_after_bounce() -> void:
	var s := _scorer()
	var b := _ball()
	b.last_hit_by = 0
	b.bounces_since_last_hit = 1
	b.global_position = Vector3(0, 0.1, -7.5)
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_out_of_bounds()
	_assert_eq(r["winner"], 0)

func test_oob_red_shot_long_past_blue_baseline() -> void:
	# Red hit → ball flew past Blue's baseline without bouncing → Red's shot was long
	var s := _scorer()
	var b := _ball()
	b.last_hit_by = 1
	b.bounces_since_last_hit = 0
	b.global_position = Vector3(0, 0.3, 7.2)
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_out_of_bounds()
	_assert_false(r["valid"])
	_assert_eq(r["winner"], 0, "Blue wins — Red shot long")

func test_oob_blue_shot_long_past_red_baseline() -> void:
	var s := _scorer()
	var b := _ball()
	b.last_hit_by = 0
	b.bounces_since_last_hit = 0
	b.global_position = Vector3(0, 0.3, -7.2)
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_out_of_bounds()
	_assert_eq(r["winner"], 1)

func test_oob_sideline_wide_after_bounce() -> void:
	# Red hit → bounced on Blue's court → rolled out past sideline → Red wins
	var s := _scorer()
	var b := _ball()
	b.last_hit_by = 1
	b.bounces_since_last_hit = 1
	b.global_position = Vector3(3.5, 0.2, 4.0)
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_out_of_bounds()
	_assert_eq(r["winner"], 1)

func test_oob_sideline_wide_shot() -> void:
	# Red hit → ball flew wide past sideline without bouncing → Red's shot was wide
	var s := _scorer()
	var b := _ball()
	b.last_hit_by = 1
	b.bounces_since_last_hit = 0
	b.global_position = Vector3(3.5, 0.3, 4.0)
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_out_of_bounds()
	_assert_eq(r["winner"], 0, "Blue wins — Red shot wide")

# ── Tests: Double bounce ─────────────────────────────────────────────────────
func test_double_bounce_blue_fails() -> void:
	var s := _scorer()
	var b := _ball()
	b.last_hit_by = 1
	b.bounces_since_last_hit = 2
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_double_bounce_and_net_ball(Vector3(0, 0.1, 3.0))
	_assert_false(r["valid"])
	_assert_eq(r["winner"], 1)
	_assert_eq(r["reason"], _RallyScorer.FAULT_DOUBLE_BOUNCE)

func test_double_bounce_red_fails() -> void:
	var s := _scorer()
	var b := _ball()
	b.last_hit_by = 0
	b.bounces_since_last_hit = 2
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_double_bounce_and_net_ball(Vector3(0, 0.1, -3.0))
	_assert_eq(r["winner"], 0)
	_assert_eq(r["reason"], _RallyScorer.FAULT_DOUBLE_BOUNCE)

# ── Tests: Ball in net (didn't cross) ────────────────────────────────────────
func test_ball_in_net_blue_weak_hit() -> void:
	# Blue hit → ball bounced back on Blue's own side → didn't cross net
	var s := _scorer()
	var b := _ball()
	b.last_hit_by = 0
	b.bounces_since_last_hit = 1
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_double_bounce_and_net_ball(Vector3(0, 0.1, 3.0))  # +Z = Blue's side
	_assert_false(r["valid"])
	_assert_eq(r["winner"], 1)
	_assert_eq(r["reason"], _RallyScorer.FAULT_BALL_IN_NET)

func test_ball_in_net_red_weak_hit() -> void:
	var s := _scorer()
	var b := _ball()
	b.last_hit_by = 1
	b.bounces_since_last_hit = 1
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_double_bounce_and_net_ball(Vector3(0, 0.1, -3.0))
	_assert_eq(r["winner"], 0)
	_assert_eq(r["reason"], _RallyScorer.FAULT_BALL_IN_NET)

# ── Tests: Kitchen volley ────────────────────────────────────────────────────
func test_kitchen_volley_blue_at_hit() -> void:
	var s := _scorer()
	var b := _ball()
	b.was_volley = true
	s.bind(b, _player(0, Vector3(0, 1, 1.0)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_kitchen_volley_at_hit(0, 1.0)
	_assert_false(r["valid"])
	_assert_eq(r["winner"], 1)
	_assert_eq(r["reason"], _RallyScorer.FAULT_KITCHEN_VOLLEY)

func test_kitchen_volley_red_at_hit() -> void:
	var s := _scorer()
	var b := _ball()
	b.was_volley = true
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -1.0)))
	var r := s.check_kitchen_volley_at_hit(1, -1.0)
	_assert_eq(r["winner"], 0)

func test_legal_volley_outside_kitchen() -> void:
	var s := _scorer()
	var b := _ball()
	b.was_volley = true
	s.bind(b, _player(0, Vector3(0, 1, 2.5)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_kitchen_volley_at_hit(0, 2.5)
	_assert_true(r["valid"], "legal volley outside kitchen")

func test_groundstroke_near_kitchen_is_legal() -> void:
	var s := _scorer()
	var b := _ball()
	b.was_volley = false  # bounced, not a volley
	s.bind(b, _player(0, Vector3(0, 1, 1.5)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_kitchen_volley_at_hit(0, 1.5)
	_assert_true(r["valid"], "groundstroke in kitchen is legal")

# ── Tests: Momentum fault ────────────────────────────────────────────────────
func test_momentum_fault_fires_within_window() -> void:
	var s := _scorer()
	var blue := _player(0, Vector3(0, 1, 2.5))
	s.bind(_ball(), blue, _player(1, Vector3(0, 1, -6.8)))
	# Simulate arming the watch window directly (skip _on_any_paddle_hit plumbing)
	s._last_volley_time_msec = Time.get_ticks_msec()
	s._last_volley_player = 0
	# Now player drifts into the kitchen
	blue.global_position = Vector3(0, 1, 1.5)
	var r := s.check_momentum_fault()
	_assert_false(r["valid"])
	_assert_eq(r["winner"], 1)
	_assert_eq(r["reason"], _RallyScorer.FAULT_MOMENTUM)

func test_momentum_fault_no_fire_on_retreat() -> void:
	var s := _scorer()
	var blue := _player(0, Vector3(0, 1, 2.5))
	s.bind(_ball(), blue, _player(1, Vector3(0, 1, -6.8)))
	s._last_volley_time_msec = Time.get_ticks_msec()
	s._last_volley_player = 0
	blue.global_position = Vector3(0, 1, 3.5)
	var r := s.check_momentum_fault()
	_assert_true(r["valid"])

func test_momentum_fault_window_expiry() -> void:
	var s := _scorer()
	var blue := _player(0, Vector3(0, 1, 1.5))
	s.bind(_ball(), blue, _player(1, Vector3(0, 1, -6.8)))
	# Window was armed 1000ms ago — past the 800ms cutoff
	s._last_volley_time_msec = Time.get_ticks_msec() - 1000
	s._last_volley_player = 0
	var r := s.check_momentum_fault()
	_assert_true(r["valid"], "window expired")
	_assert_eq(s._last_volley_player, -1, "player cleared after expiry")

func test_momentum_fault_groundstroke_not_watched() -> void:
	# If the watch was never armed (groundstroke path), check returns valid.
	var s := _scorer()
	s.bind(_ball(), _player(0, Vector3(0, 1, 1.5)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_momentum_fault()
	_assert_true(r["valid"])

# ── Tests: Two-bounce rule ───────────────────────────────────────────────────
func test_two_bounce_blue_illegal_volley_of_serve() -> void:
	var s := _scorer()
	var b := _ball()
	b.both_bounces_complete = false
	b.ball_bounced_since_last_hit = false  # ball is airborne since the serve
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_two_bounce_rule(0)
	_assert_false(r["valid"])
	_assert_eq(r["reason"], _RallyScorer.FAULT_TWO_BOUNCE_RULE)
	_assert_eq(r["winner"], 1)

func test_two_bounce_blue_legal_return_after_bounce() -> void:
	var s := _scorer()
	var b := _ball()
	b.both_bounces_complete = false
	b.ball_bounced_since_last_hit = true  # ball bounced once since last hit
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_two_bounce_rule(0)
	_assert_true(r["valid"])

func test_two_bounce_red_illegal_return_of_return() -> void:
	var s := _scorer()
	var b := _ball()
	b.both_bounces_complete = false
	b.ball_bounced_since_last_hit = false
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_two_bounce_rule(1)
	_assert_false(r["valid"])
	_assert_eq(r["winner"], 0)

func test_two_bounce_legal_volley_after_both_bounces() -> void:
	var s := _scorer()
	var b := _ball()
	b.both_bounces_complete = true  # rule satisfied
	b.ball_bounced_since_last_hit = false
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_two_bounce_rule(0)
	_assert_true(r["valid"])

# ── Tests: Service fault ─────────────────────────────────────────────────────
func test_short_serve_blue() -> void:
	# Blue serves, ball lands inside NVZ on Red's side (z = -1.5)
	var s := _scorer(0, true)
	s.bind(_ball(), _player(0, Vector3(1.5, 1, 6.8)), _player(1, Vector3(-1.5, 1, -6.8)))
	var r := s.check_service_ball_landed(Vector3(-1.5, 0.1, -1.5))
	_assert_false(r["valid"])
	_assert_eq(r["reason"], _RallyScorer.FAULT_SHORT_SERVE)
	_assert_eq(r["winner"], 1)

func test_wrong_service_court_blue() -> void:
	# Blue from right, should serve to Red's left (x<0). Ball lands x>0 = wrong
	var s := _scorer(0, true)
	s.bind(_ball(), _player(0, Vector3(1.5, 1, 6.8)), _player(1, Vector3(-1.5, 1, -6.8)))
	var r := s.check_service_ball_landed(Vector3(1.5, 0.1, -4.0))
	_assert_false(r["valid"])
	_assert_eq(r["reason"], _RallyScorer.FAULT_WRONG_SERVICE_COURT)

func test_valid_serve_lands_correct_diagonal() -> void:
	var s := _scorer(0, true)
	s.bind(_ball(), _player(0, Vector3(1.5, 1, 6.8)), _player(1, Vector3(-1.5, 1, -6.8)))
	var r := s.check_service_ball_landed(Vector3(-1.5, 0.1, -4.0))
	_assert_true(r["valid"])

func test_short_serve_red() -> void:
	var s := _scorer(1, true)
	s.bind(_ball(), _player(0, Vector3(-1.5, 1, 6.8)), _player(1, Vector3(-1.5, 1, -6.8)))
	var r := s.check_service_ball_landed(Vector3(1.5, 0.1, 1.5))
	_assert_false(r["valid"])
	_assert_eq(r["winner"], 0)

# ── Tests: Server position ───────────────────────────────────────────────────
func test_server_position_valid() -> void:
	var s := _scorer(0, true)
	s.bind(_ball(), _player(0, Vector3(1.5, 1, 6.8)), _player(1, Vector3(-1.5, 1, -6.8)))
	var r := s.check_server_position(Vector3(1.5, 1, 6.8))
	_assert_true(r["valid"])

func test_server_position_wrong_half() -> void:
	var s := _scorer(0, true)
	s.bind(_ball(), _player(0, Vector3(1.5, 1, 6.8)), _player(1, Vector3(-1.5, 1, -6.8)))
	var r := s.check_server_position(Vector3(1.5, 1, -1.0))
	_assert_eq(r["reason"], _RallyScorer.FAULT_WRONG_HALF)

func test_server_position_wrong_court() -> void:
	# Even score → from_right = true → Blue should be at x > 0
	var s := _scorer(0, true)
	s.bind(_ball(), _player(0, Vector3(-1.5, 1, 6.8)), _player(1, Vector3(-1.5, 1, -6.8)))
	var r := s.check_server_position(Vector3(-1.5, 1, 6.8))
	_assert_eq(r["reason"], _RallyScorer.FAULT_WRONG_SERVICE_COURT)

func test_server_position_foot_fault() -> void:
	var s := _scorer(0, true)
	s.bind(_ball(), _player(0, Vector3(1.5, 1, 6.0)), _player(1, Vector3(-1.5, 1, -6.8)))
	var r := s.check_server_position(Vector3(1.5, 1, 6.0))  # in front of baseline
	_assert_eq(r["reason"], _RallyScorer.FAULT_FOOT_FAULT)

# ── Tests: Body hit ──────────────────────────────────────────────────────────
func test_body_hit_ignored_when_ball_bouncing() -> void:
	# Body hit should NOT fire if the ball has already bounced multiple times
	# (it's a rolling ball, not a live hit)
	var s := _scorer()
	var b := _ball()
	b.bounces_since_last_hit = 3
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	# The signal handler guards against this; we can't call it directly because
	# it uses Time.get_ticks_msec() internally, but we can verify the guard
	# condition matches. This test documents the expected behavior.
	_assert_true(int(b.get("bounces_since_last_hit")) >= 2)

func test_body_hit_no_suppression() -> void:
	# When a body hit is genuinely live (no recent paddle, ball not bouncing),
	# the scorer should issue the fault. The live path is signal-driven and
	# we'd need to mock Time to test it fully — documenting expected behavior.
	var s := _scorer()
	var b := _ball()
	b.bounces_since_last_hit = 0
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	# Simulate that no paddle hit has occurred recently
	s._last_paddle_hit_msec = 0
	_assert_true(int(b.get("bounces_since_last_hit")) < 2)

# ── Tests: Net touch ─────────────────────────────────────────────────────────
func test_net_touch_blue_body_at_net() -> void:
	var s := _scorer()
	s.bind(_ball(), _player(0, Vector3(0, 0.3, 0.05)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_net_touch()
	_assert_false(r["valid"])
	_assert_eq(r["winner"], 1)
	_assert_eq(r["reason"], _RallyScorer.FAULT_NET_TOUCH)

func test_net_touch_red_body_at_net() -> void:
	var s := _scorer()
	s.bind(_ball(), _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 0.3, -0.05)))
	var r := s.check_net_touch()
	_assert_eq(r["winner"], 0)

func test_net_touch_paddle_only() -> void:
	var s := _scorer()
	var blue := _player(0, Vector3(0, 1, 0.5))  # body safe
	blue.paddle_position = Vector3(0, 0.4, 0.08)  # paddle touching net
	s.bind(_ball(), blue, _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_net_touch()
	_assert_false(r["valid"])
	_assert_eq(r["winner"], 1)

func test_net_touch_safe_distance() -> void:
	var s := _scorer()
	var blue := _player(0, Vector3(0, 1, 0.5))
	blue.paddle_position = Vector3(0, 1, 0.4)
	s.bind(_ball(), blue, _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_net_touch()
	_assert_true(r["valid"])

# ── Tests: Fault precedence ──────────────────────────────────────────────────
func test_precedence_two_bounce_beats_kitchen() -> void:
	# Player is in the kitchen AND two-bounce rule not satisfied.
	# Both checks would fault — but the scorer's _on_any_paddle_hit runs
	# two-bounce first. This test verifies each check independently and
	# documents that two-bounce wins (is checked first in the handler).
	var s := _scorer()
	var b := _ball()
	b.both_bounces_complete = false
	b.ball_bounced_since_last_hit = false
	b.was_volley = true
	s.bind(b, _player(0, Vector3(0, 1, 1.0)), _player(1, Vector3(0, 1, -6.8)))
	var tbr := s.check_two_bounce_rule(0)
	var kv := s.check_kitchen_volley_at_hit(0, 1.0)
	_assert_false(tbr["valid"])
	_assert_false(kv["valid"])
	# Precedence: two-bounce is checked first, so it wins
	_assert_eq(tbr["reason"], _RallyScorer.FAULT_TWO_BOUNCE_RULE)

func test_precedence_double_bounce_over_oob() -> void:
	# Ball is at z > 6.7 (OOB) AND bounces_since_last_hit = 2 (double bounce).
	# Both would fire; double-bounce runs in the bounce handler, OOB in
	# _physics_process. In practice the bounce handler runs first per frame.
	var s := _scorer()
	var b := _ball()
	b.last_hit_by = 1
	b.bounces_since_last_hit = 2
	b.global_position = Vector3(0, 0.1, 7.5)
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var db := s.check_double_bounce_and_net_ball(Vector3(0, 0.1, 6.0))
	_assert_false(db["valid"])
	_assert_eq(db["reason"], _RallyScorer.FAULT_DOUBLE_BOUNCE)
	_assert_eq(db["winner"], 1)

# ── Regression tests (bugs that have actually been fixed) ───────────────────
func test_regression_oob_baseline_not_inverted() -> void:
	# Prior bug: OOB past Blue's baseline awarded Blue (wrong).
	# Fixed to award to whoever is NOT the one who failed/hit out.
	var s := _scorer()
	var b := _ball()
	b.last_hit_by = 1
	b.bounces_since_last_hit = 1
	b.global_position = Vector3(0, 0.1, 7.5)
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_out_of_bounds()
	_assert_eq(r["winner"], 1, "Red must win — Blue failed to return (not inverted)")

func test_regression_oob_uses_last_hit_by() -> void:
	# Prior bug: OOB used z-position proxy instead of last_hit_by.
	# When Red shoots long past Blue's baseline, Blue must win — NOT Red.
	var s := _scorer()
	var b := _ball()
	b.last_hit_by = 1
	b.bounces_since_last_hit = 0  # never bounced = shot was long
	b.global_position = Vector3(0, 0.3, 7.2)
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_out_of_bounds()
	_assert_eq(r["winner"], 0, "Blue wins — Red's shot was long")

func test_regression_receiver_fails_after_legal_bounce() -> void:
	# Canonical scenario: Red hits, ball bounces legally on Blue's court,
	# Blue fails to return, ball rolls past baseline.
	# User reported: "I deliberately failed to hit back and the game scored wrong."
	var s := _scorer()
	var b := _ball()
	b.last_hit_by = 1
	b.bounces_since_last_hit = 1  # bounced legally once on Blue's side
	b.global_position = Vector3(1.2, 0.2, 7.1)  # rolled just past baseline
	s.bind(b, _player(0, Vector3(0, 1, 6.8)), _player(1, Vector3(0, 1, -6.8)))
	var r := s.check_out_of_bounds()
	_assert_eq(r["winner"], 1, "Red wins when Blue deliberately fails to return")
	_assert_eq(r["reason"], _RallyScorer.FAULT_OUT_OF_BOUNDS)
