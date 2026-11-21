extends RefCounted
class_name CardPartnerTap
## Partner paddle tap between points (docs/POSE_STUDIO_SPEC.md stage 10). Visual only: nobody is
## moved; when both partners pass within reach after a point, both turn to each other and reach
## the paddle hand to a meeting point between them, tap, and come back. CardMotionLayer applies it.
##
## Rules: once per team per point; only while the ball is dead, within WINDOW s of the point end;
## not while either one has busy hands (bending for, lifting, passing or catching the ball);
## the tap replaces both partners' reactions (stop_reaction); both start on the same frame
## (shared event per game and team).

const RANGE: = 1.5            # m between partners (body centres) to start a tap
const WINDOW: = 5.0           # s after the point end
const TURN: = 0.45            # s: both turn to face each other first
const REACH: = 0.85           # s: paddle tips at the meeting point
const TAP_AT: = 0.98          # s: the tap nudge
const HOLD: = 1.15            # s: start back (paddle first, then the turn)
const DONE: = 1.75            # s
const MEET_HEIGHT: = 1.15     # m above the court
const LOOK_AHEAD: = 0.35      # s: partners must still be in range this far ahead
const BUSY_PHASES: = ["BEND", "LIFT", "PICKUP", "CARRY", "PASS_PREP", "PASS", "PASS_RELEASE", "CATCH", "CATCH_OPEN"]

static var _events: Dictionary = {}   # "<game id>:<team>" -> {"gen": int, "frame": int, "done": bool}

var _player
var _game: Node = null
var _connected: = false
var _point_t: = -1.0          # s since the last point end (-1: no point to tap for)
var _gen: = -1
var _t: = -1.0                # s into my tap (-1: none)

func _init(player) -> void:
	_player = player

func _connect() -> void:
	if _connected: return
	_game = _player.get_parent()
	if _game == null or not "rally_scorer" in _game or _game.rally_scorer == null: return
	_game.rally_scorer.rally_ended.connect(_on_rally_ended)
	_connected = true

func _on_rally_ended(winner: int, _r: String, _d: String) -> void:
	if winner not in [0, 1]: return
	if _game.has_method("_is_practice") and _game._is_practice(): return
	_point_t = 0.0
	_gen += 1

func active() -> bool:
	return _t >= 0.0

func _partner():
	if _game == null or not _game.has_method("get_players"): return null
	for p in _game.get_players():
		if p != _player and is_instance_valid(p) and p.get_team_id() == _player.get_team_id(): return p
	return null

static func _vel(p) -> Vector3:
	var v = p.get("current_velocity")
	return v if v is Vector3 else Vector3.ZERO

func _hands_busy(p) -> bool:
	if _game == null: _game = _player.get_parent()
	if _game == null: return false
	var bpc = _game.get("between_point_controller")
	if bpc == null or not is_instance_valid(bpc) or not bpc.is_active(): return false
	if not str(bpc.get("phase")) in BUSY_PHASES: return false
	var ps: Array = _game.get_players()
	var idx: int = ps.find(p)
	return idx >= 0 and (idx == int(bpc.get("retriever")) or idx == int(bpc.get("server")))

## Advance. `stop_reaction(p)` ends a player's card reaction when the tap starts.
## Returns {} or {"turn": 0..1 face-the-partner weight, "w": 0..1 reach weight, "nudge": 0..1, "target": Vector3, "partner": player}.
func update(delta: float, stop_reaction: Callable) -> Dictionary:
	_connect()
	if _game == null: return {}
	var ball = _game.get("ball")
	var dead: bool = ball != null and not bool(ball.get("is_in_play"))
	if _point_t >= 0.0: _point_t += delta
	var partner = _partner()
	if partner == null: _t = -1.0; return {}
	var key: = "%d:%d" % [_game.get_instance_id(), int(_player.get_team_id())]
	var ev: Dictionary = _events.get(key, {})
	if _t < 0.0:
		# Join a tap my partner started this frame, or start one.
		if not ev.is_empty() and int(ev.gen) == _gen and int(ev.frame) == Engine.get_process_frames():
			_t = 0.0
		elif dead and _point_t >= 0.0 and _point_t <= WINDOW and (ev.is_empty() or int(ev.gen) != _gen) \
				and not _hands_busy(_player) and not _hands_busy(partner):
			# Close now and still close at the reach (walking past or apart does not count).
			var d: Vector3 = partner.global_position - _player.global_position
			var ahead: Vector3 = d + (_vel(partner) - _vel(_player)) * LOOK_AHEAD
			d.y = 0.0
			ahead.y = 0.0
			if d.length() <= RANGE and ahead.length() <= RANGE:
				_events[key] = {"gen": _gen, "frame": Engine.get_process_frames()}
				_t = 0.0
				stop_reaction.call(_player)
				stop_reaction.call(partner)
		if _t < 0.0: return {}
	else:
		_t += delta
	if _t >= DONE or not dead:
		_t = -1.0
		_point_t = -1.0
		return {}
	# Turn first, then reach; going back the paddle comes down before the body turns away.
	var back_mid: float = lerpf(HOLD, DONE, 0.55)
	var turn: float = smoothstep(0.0, TURN, _t) * (1.0 - smoothstep(back_mid - 0.1, DONE, _t))
	var w: float = smoothstep(TURN * 0.6, REACH, _t) * (1.0 - smoothstep(HOLD, back_mid, _t))
	var nudge: float = maxf(0.0, 1.0 - absf(_t - TAP_AT) / 0.07)
	var mine: Vector3 = _player.global_position
	var theirs: Vector3 = partner.global_position
	var target: = (mine + theirs) * 0.5
	target.y = mine.y + MEET_HEIGHT
	return {"turn": turn, "w": w, "nudge": nudge, "target": target, "partner": partner}
