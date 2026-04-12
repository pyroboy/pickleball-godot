class_name RallyScorer extends Node
## Owns ALL fault detection and rally-ending decisions for the pickleball game.
##
## Architecture:
##   - game.gd instantiates this as a child and calls bind() with the live ball
##     and both players.
##   - The scorer connects to ball signals (bounced, hit_by_paddle, hit_player_body)
##     and runs per-frame checks for out-of-bounds, net touch, and momentum fault.
##   - When any fault fires, the scorer emits rally_ended(winner, reason, detail).
##     game.gd connects to that single signal and calls _on_point_scored.
##
## Design:
##   - Fields are duck-typed (Object) so tests can pass FakeBall/FakePlayer
##     RefCounted stubs. The scorer reads fields by name, never checks types.
##   - Public check_* validators are pure-ish: take explicit inputs, return a
##     Dictionary {valid, winner, reason, detail}. Tests call them directly
##     without instantiating a scene tree.
##   - Fault precedence is encoded in the return-early order of the live
##     handlers (see "Fault precedence" comment near _process_fault_checks).

# ── Outgoing signal ───────────────────────────────────────────────────────────
## Emitted when a rally ends. winner: 0=Blue, 1=Red. reason: FAULT_* constant.
## detail: short human-readable description for HUD rendering.
signal rally_ended(winner: int, reason: String, detail: String)

# ── Fault reason constants (single source of truth) ──────────────────────────
const FAULT_OUT_OF_BOUNDS       := "OUT_OF_BOUNDS"
const FAULT_DOUBLE_BOUNCE       := "DOUBLE_BOUNCE"
const FAULT_BALL_IN_NET         := "BALL_IN_NET"
const FAULT_KITCHEN_VOLLEY      := "KITCHEN_VOLLEY"
const FAULT_MOMENTUM            := "MOMENTUM"
const FAULT_TWO_BOUNCE_RULE     := "TWO_BOUNCE_RULE"
const FAULT_BODY_HIT            := "BODY_HIT"
const FAULT_SHORT_SERVE         := "SHORT_SERVE"
const FAULT_WRONG_SERVICE_COURT := "WRONG_SERVICE_COURT"
const FAULT_FOOT_FAULT          := "FOOT_FAULT"
const FAULT_WRONG_HALF          := "WRONG_HALF"
const FAULT_NET_TOUCH           := "NET_TOUCH"

# ── Tunables (read from PickleballConstants where available) ─────────────────
const NET_TOUCH_Z_TOLERANCE: float = 0.15       # meters — player/paddle z distance from net plane
const BODY_HIT_COOLDOWN_MS: int = 300           # after any paddle hit, suppress body-hit faults
const OOB_Y_CHECK: float = 0.5                  # only check OOB when ball is near ground

# ── State ─────────────────────────────────────────────────────────────────────
var _ball                                       # Object — duck-typed (RigidBody3D live, FakeBall in tests)
var _player_left                                # Object — CharacterBody3D live, FakePlayer in tests
var _player_right                               # Object
var _active: bool = false                       # true during active play; gates per-frame checks
var _serving_team: int = 0                      # 0=Blue, 1=Red
var _serving_from_right: bool = true            # derived from score parity
var _serve_was_hit: bool = false                # serve has been validated (or first legal bounce occurred)
var _service_fault_triggered: bool = false      # one-shot guard for service fault path
# Momentum-into-kitchen watch window
var _last_volley_time_msec: int = 0
var _last_volley_player: int = -1
# Body-hit cooldown
var _last_paddle_hit_msec: int = 0
# For net-touch debounce (avoid firing multiple times in the same approach)
var _net_touch_fired: bool = false

# ── Setup ─────────────────────────────────────────────────────────────────────
## Called once by game.gd in _ready() after ball + players are instantiated.
## Connects to ball signals and stashes duck-typed refs for field access.
func bind(ball_ref, player_left_ref, player_right_ref) -> void:
	_ball = ball_ref
	_player_left = player_left_ref
	_player_right = player_right_ref
	# Only connect if the ref exposes Godot signals (live mode). Tests drive
	# the scorer directly via check_* methods and don't need signal routing.
	if ball_ref is Object and ball_ref.has_signal("bounced"):
		ball_ref.bounced.connect(_on_ball_bounced)
	if ball_ref is Object and ball_ref.has_signal("hit_by_paddle"):
		ball_ref.hit_by_paddle.connect(_on_any_paddle_hit)
	if ball_ref is Object and ball_ref.has_signal("hit_player_body"):
		ball_ref.hit_player_body.connect(_on_ball_hit_player_body)

# ── Rally lifecycle (called from game.gd._set_game_state) ────────────────────
func start_rally(serving_team: int, serving_from_right: bool) -> void:
	_serving_team = serving_team
	_serving_from_right = serving_from_right
	_serve_was_hit = false
	_service_fault_triggered = false
	_last_volley_time_msec = 0
	_last_volley_player = -1
	_last_paddle_hit_msec = 0
	_net_touch_fired = false
	_active = true

func end_rally() -> void:
	_active = false
	_last_volley_player = -1
	_net_touch_fired = false

func set_active(active: bool) -> void:
	_active = active
	if not active:
		_last_volley_player = -1

# ── Per-frame driver (live game only) ────────────────────────────────────────
func _physics_process(_delta: float) -> void:
	if not _active or _ball == null:
		return
	# Fault precedence (per-frame checks):
	#   1. Net touch — player body or paddle overlapping net plane
	#   2. Out of bounds — ball crossed court bounds
	#   3. Momentum fault — post-volley drift into kitchen within window
	var result: Dictionary = check_net_touch()
	if not result.get("valid", true):
		_emit(result); return
	result = check_out_of_bounds()
	if not result.get("valid", true):
		_emit(result); return
	result = check_momentum_fault()
	if not result.get("valid", true):
		_emit(result); return

# ── Signal handlers (live game only) ─────────────────────────────────────────
func _on_ball_bounced(bounce_pos: Vector3) -> void:
	if not _active:
		return
	# Service phase: if serve hasn't been validated yet, check service landing
	if not _serve_was_hit and _ball != null and _ball.get("last_hit_by") == _serving_team and _ball.get("bounces_since_last_hit") == 1:
		var svc := check_service_ball_landed(bounce_pos)
		if not svc.get("valid", true):
			_emit(svc); return
		_serve_was_hit = true
	# Double-bounce + ball-in-net checks run on every bounce
	var result := check_double_bounce_and_net_ball(bounce_pos)
	if not result.get("valid", true):
		_emit(result)

func _on_any_paddle_hit(player_num: int) -> void:
	if not _active:
		return
	_last_paddle_hit_msec = Time.get_ticks_msec()
	# Two-bounce rule is checked first (at hit time it's fatal if violated)
	var tbr := check_two_bounce_rule(player_num)
	if not tbr.get("valid", true):
		_emit(tbr); return
	# Kitchen volley check
	var player_z: float = (_player_left if player_num == 0 else _player_right).global_position.z
	var kv := check_kitchen_volley_at_hit(player_num, player_z)
	if not kv.get("valid", true):
		_emit(kv); return
	# Legal volley outside kitchen — arm momentum watch
	if _ball != null and _ball.get("was_volley") == true:
		_last_volley_time_msec = Time.get_ticks_msec()
		_last_volley_player = player_num

func _on_ball_hit_player_body(player_num: int) -> void:
	if not _active:
		return
	var since_paddle: int = Time.get_ticks_msec() - _last_paddle_hit_msec
	if since_paddle < BODY_HIT_COOLDOWN_MS:
		return  # swing follow-through, suppressed
	# Ignore if the ball is rolling around (already bounced >= 2 this rally)
	if _ball != null and int(_ball.get("bounces_since_last_hit")) >= 2:
		return
	var hitter_name: String = "Blue" if player_num == 0 else "Red"
	_emit({
		"valid": false,
		"winner": 1 - player_num,
		"reason": FAULT_BODY_HIT,
		"detail": "%s: Ball struck the player" % hitter_name.to_upper(),
	})

# ── Public validators (pure-ish — tests call these directly) ─────────────────

## Checks whether the ball's current position is outside the court, and if so
## decides the winner based on bounces_since_last_hit and last_hit_by.
func check_out_of_bounds() -> Dictionary:
	if _ball == null:
		return {"valid": true}
	if _ball.global_position.y > OOB_Y_CHECK:
		return {"valid": true}
	var bpos: Vector3 = _ball.global_position
	var left: float = -PickleballConstants.COURT_WIDTH / 2.0
	var right: float = PickleballConstants.COURT_WIDTH / 2.0
	var top: float = -PickleballConstants.BASELINE_Z
	var bottom: float = PickleballConstants.BASELINE_Z
	var is_out: bool = (bpos.x < left or bpos.x > right or bpos.z < top or bpos.z > bottom)
	if not is_out:
		return {"valid": true}
	# Decide winner by authoritative ball state.
	var last_hit: int = int(_ball.get("last_hit_by"))
	var bounces: int = int(_ball.get("bounces_since_last_hit"))
	var winner: int
	var detail: String
	if last_hit < 0:
		# Fallback: no hit on record. Use position to award.
		winner = 1 if bpos.z > 0 else 0
		detail = "ball out (no hit recorded)"
	elif bounces > 0:
		# Ball bounced legally then rolled/drifted out → receiver failed
		winner = last_hit
		detail = "%s failed to return" % ("Blue" if winner == 1 else "Red")
	else:
		# Ball flew out without bouncing → hitter's shot was long/wide
		winner = 1 - last_hit
		detail = "%s shot out" % ("Blue" if last_hit == 0 else "Red")
	return {
		"valid": false,
		"winner": winner,
		"reason": FAULT_OUT_OF_BOUNDS,
		"detail": detail,
	}

## Checks whether a serve's first bounce landed in the correct diagonal
## service court. Called from _on_ball_bounced only during service phase.
func check_service_ball_landed(bounce_pos: Vector3) -> Dictionary:
	var nvz: float = PickleballConstants.NON_VOLLEY_ZONE
	if _serving_team == 0:
		# Blue serves toward Red's side (-Z)
		var correct_side: bool = bounce_pos.z < -nvz
		var correct_diag: bool
		if _serving_from_right:
			correct_diag = bounce_pos.x < 0.0
		else:
			correct_diag = bounce_pos.x > 0.0
		if not correct_side:
			return {"valid": false, "winner": 1, "reason": FAULT_SHORT_SERVE, "detail": "Blue: serve landed in kitchen"}
		if not correct_diag:
			return {"valid": false, "winner": 1, "reason": FAULT_WRONG_SERVICE_COURT, "detail": "Blue: wrong service court"}
	else:
		# Red serves toward Blue's side (+Z)
		var correct_side2: bool = bounce_pos.z > nvz
		var correct_diag2: bool
		if _serving_from_right:
			correct_diag2 = bounce_pos.x < 0.0
		else:
			correct_diag2 = bounce_pos.x > 0.0
		if not correct_side2:
			return {"valid": false, "winner": 0, "reason": FAULT_SHORT_SERVE, "detail": "Red: serve landed in kitchen"}
		if not correct_diag2:
			return {"valid": false, "winner": 0, "reason": FAULT_WRONG_SERVICE_COURT, "detail": "Red: wrong service court"}
	return {"valid": true}

## Server position pre-serve check. Returns a {valid, reason} dict (no winner —
## the caller in game.gd triggers the fault and awards the point).
func check_server_position(server_pos: Vector3) -> Dictionary:
	var total_score_parity_bool: bool = _serving_from_right
	var baseline_edge: float = PickleballConstants.BASELINE_Z - PickleballConstants.FOOT_FAULT_TOLERANCE
	var on_correct_half: bool
	var on_correct_side: bool
	var behind_baseline: bool
	if _serving_team == 0:
		on_correct_half = server_pos.z > 0.2
		on_correct_side = (server_pos.x > 0.2) if total_score_parity_bool else (server_pos.x < -0.2)
		behind_baseline = server_pos.z >= baseline_edge
	else:
		on_correct_half = server_pos.z < -0.2
		on_correct_side = (server_pos.x < -0.2) if total_score_parity_bool else (server_pos.x > 0.2)
		behind_baseline = server_pos.z <= -baseline_edge
	var reason: String = ""
	if not on_correct_half:
		reason = FAULT_WRONG_HALF
	elif not on_correct_side:
		reason = FAULT_WRONG_SERVICE_COURT
	elif not behind_baseline:
		reason = FAULT_FOOT_FAULT
	return {"valid": reason == "", "reason": reason}

## Checks whether a paddle hit occurred while the hitting player was inside
## the non-volley zone AND the ball was airborne (was_volley == true).
func check_kitchen_volley_at_hit(player_num: int, player_z: float) -> Dictionary:
	if _ball == null or _ball.get("was_volley") != true:
		return {"valid": true}
	if absf(player_z) >= PickleballConstants.NON_VOLLEY_ZONE:
		return {"valid": true}
	var hitter: String = "Blue" if player_num == 0 else "Red"
	return {
		"valid": false,
		"winner": 1 - player_num,
		"reason": FAULT_KITCHEN_VOLLEY,
		"detail": "%s volleyed in the kitchen" % hitter.to_upper(),
	}

## Two-bounce rule: during the first two rally exchanges, each side must let
## the ball bounce once on their court before striking it. Fires if the player
## tries to volley before both_bounces_complete AND the ball hasn't bounced
## since the prior hit (i.e., it's been airborne the whole time).
func check_two_bounce_rule(player_num: int) -> Dictionary:
	if _ball == null:
		return {"valid": true}
	if _ball.get("both_bounces_complete") == true:
		return {"valid": true}
	if _ball.get("ball_bounced_since_last_hit") == true:
		return {"valid": true}
	var hitter: String = "Blue" if player_num == 0 else "Red"
	return {
		"valid": false,
		"winner": 1 - player_num,
		"reason": FAULT_TWO_BOUNCE_RULE,
		"detail": "%s: let it bounce first" % hitter.to_upper(),
	}

## Double-bounce detection + ball-in-net detection. Called from _on_ball_bounced.
func check_double_bounce_and_net_ball(bounce_pos: Vector3) -> Dictionary:
	if _ball == null:
		return {"valid": true}
	var bounces: int = int(_ball.get("bounces_since_last_hit"))
	var last_hit: int = int(_ball.get("last_hit_by"))
	# Double bounce: ball bounced twice on one side before being returned
	if bounces >= 2 and last_hit >= 0:
		var _loser_name: String = "Blue" if last_hit == 1 else "Red"
		# Wait — if last_hit is the hitter, the LOSER of the double bounce is
		# whoever failed to return, i.e., the OTHER player. Winner = last_hit.
		var winner: int = last_hit
		return {
			"valid": false,
			"winner": winner,
			"reason": FAULT_DOUBLE_BOUNCE,
			"detail": "%s: failed to return in time" % ("Blue" if winner == 1 else "Red").to_upper(),
		}
	# Ball in net: ball bounced on the same side as the last hitter (after
	# being hit) → their shot didn't clear the net.
	if last_hit >= 0:
		var hitter_side_positive: bool = (last_hit == 0)  # Blue on +Z
		var bounce_side_positive: bool = bounce_pos.z > 0
		if hitter_side_positive == bounce_side_positive and bounces == 1:
			# Ball bounced back on the hitter's own court on the first bounce
			# after their hit → it never crossed the net (or bounced back off).
			var hitter: String = "Blue" if last_hit == 0 else "Red"
			return {
				"valid": false,
				"winner": 1 - last_hit,
				"reason": FAULT_BALL_IN_NET,
				"detail": "%s: ball did not cross the net" % hitter.to_upper(),
			}
	return {"valid": true}

## Momentum fault: post-volley player drifted into the kitchen within the
## MOMENTUM_FAULT_WINDOW_MS watch window. Called per-frame from _physics_process.
func check_momentum_fault() -> Dictionary:
	if _last_volley_player < 0:
		return {"valid": true}
	var elapsed_ms: int = Time.get_ticks_msec() - _last_volley_time_msec
	if elapsed_ms > PickleballConstants.MOMENTUM_FAULT_WINDOW_MS:
		_last_volley_player = -1
		return {"valid": true}
	var watched = _player_left if _last_volley_player == 0 else _player_right
	if watched == null:
		return {"valid": true}
	var wz: float = watched.global_position.z
	if absf(wz) >= PickleballConstants.NON_VOLLEY_ZONE:
		return {"valid": true}
	var hitter: String = "Blue" if _last_volley_player == 0 else "Red"
	var faulted: int = _last_volley_player
	_last_volley_player = -1
	return {
		"valid": false,
		"winner": 1 - faulted,
		"reason": FAULT_MOMENTUM,
		"detail": "%s: crossed kitchen line after volley" % hitter.to_upper(),
	}

## Net touch: player body OR paddle too close to the net plane at net height.
func check_net_touch() -> Dictionary:
	if _player_left == null or _player_right == null:
		return {"valid": true}
	var net_h: float = PickleballConstants.NET_HEIGHT
	# Check body Z proximity to net plane at a height that physically intersects the net
	for pnum in [0, 1]:
		var p = _player_left if pnum == 0 else _player_right
		var body_z: float = p.global_position.z
		var body_y: float = p.global_position.y
		if absf(body_z) < NET_TOUCH_Z_TOLERANCE and body_y < net_h:
			var hitter: String = "Blue" if pnum == 0 else "Red"
			return {
				"valid": false,
				"winner": 1 - pnum,
				"reason": FAULT_NET_TOUCH,
				"detail": "%s: touched the net" % hitter.to_upper(),
			}
		# Paddle check (if player exposes get_paddle_position)
		if p.has_method("get_paddle_position"):
			var pad: Vector3 = p.get_paddle_position()
			if absf(pad.z) < NET_TOUCH_Z_TOLERANCE and pad.y < net_h:
				var hitter2: String = "Blue" if pnum == 0 else "Red"
				return {
					"valid": false,
					"winner": 1 - pnum,
					"reason": FAULT_NET_TOUCH,
					"detail": "%s: paddle touched the net" % hitter2.to_upper(),
				}
	return {"valid": true}

# ── Internal ──────────────────────────────────────────────────────────────────
func _emit(result: Dictionary) -> void:
	# Closes the rally immediately so per-frame checks won't re-fire during the
	# grace period before game.gd transitions to point_scored.
	_active = false
	var winner: int = int(result.get("winner", -1))
	var reason: String = String(result.get("reason", ""))
	var detail: String = String(result.get("detail", ""))
	print("[RALLY END] winner=%d reason=%s detail=%s" % [winner, reason, detail])
	rally_ended.emit(winner, reason, detail)
