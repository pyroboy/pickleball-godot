extends RefCounted
class_name CardPartnerTap
## Partner paddle tap between points (docs/POSE_STUDIO_SPEC.md stage 10). The walk is the game's:
## between_point_controller.gd names a meeting point, walks the human and their partner to it and
## runs the clock. This draws the tap: both turn to each other and reach the paddle hand low, at
## about hand height like a handshake, the paddle tips touch at the meeting point, and they come
## back. CardMotionLayer applies it.

# The drawing's own clock, in seconds at an even pace. It is brief; between_point_controller.gd
# runs it (advance) and it slows through the touch, so the tap itself is the part the eye gets.
const TURN: = 0.26            # both turn to face each other first
const REACH: = 0.50           # paddle tips at the meeting point
const TAP_AT: = 0.50          # the touch
const HOLD: = 0.54            # start back (paddle first, then the turn)
const DONE: = 0.98
const SLOW_HALF: = 0.13       # the clock slows within this much of the touch, either side
const SLOW_RATE: = 0.35       # its slowest, at the touch
const EFFECT_LEAD: = 0.03     # the word and the flash start this much before the touch
const NUDGE_HALF: = 0.08      # the push into the partner's paddle lasts this long either side

## The drawing clock `t` after `delta` seconds at this tap's pace, slowed around the touch.
static func advance(t: float, delta: float, pace: float) -> float:
	var near: float = 1.0 - smoothstep(0.0, SLOW_HALF, absf(t - TAP_AT))
	return t + delta * lerpf(1.0, SLOW_RATE, near) / maxf(pace, 0.1)

const BUSY_PHASES: = ["BEND", "LIFT", "PICKUP", "CARRY", "PASS_PREP", "PASS", "PASS_RELEASE", "CATCH", "CATCH_OPEN"]

var _player
var _game: Node = null
var _t: = -1.0                # s into my tap (-1: none)

func _init(player) -> void:
	_player = player

func active() -> bool:
	return _t >= 0.0

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
## Returns {} or {"turn": 0..1 face-the-partner weight, "w": 0..1 reach weight, "nudge": 0..1, "target": Vector3, "partner": player,
## "turn_deg": the most this player turns (the busy partner turns less), "hip_share": how much of it the hips take (-1: the usual), "busy"}.
func update(_delta: float, stop_reaction: Callable) -> Dictionary:
	if _game == null: _game = _player.get_parent()
	if _game == null: return {}
	var bpc = _game.get("between_point_controller")
	var tap: Dictionary = bpc.tap_for(_player) if bpc != null and is_instance_valid(bpc) and bpc.has_method("tap_for") else {}
	if tap.is_empty() or float(tap.t) >= DONE:
		_t = -1.0
		return {}
	if _t < 0.0: stop_reaction.call(_player)
	_t = float(tap.t)
	# Turn first, then reach; going back the paddle comes down before the body turns away.
	var back_mid: float = lerpf(HOLD, DONE, 0.55)
	var turn: float = smoothstep(0.0, TURN, _t) * (1.0 - smoothstep(back_mid - 0.1, DONE, _t))
	var w: float = smoothstep(TURN * 0.6, REACH, _t) * (1.0 - smoothstep(HOLD, back_mid, _t))
	var nudge: float = maxf(0.0, 1.0 - absf(_t - TAP_AT) / NUDGE_HALF)
	return {"turn": turn, "w": w, "nudge": nudge, "target": tap.target, "partner": tap.partner, "turn_deg": tap.turn_deg, "hip_share": tap.hip_share, "busy": tap.busy}
