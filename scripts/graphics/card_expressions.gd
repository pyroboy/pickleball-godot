extends RefCounted
class_name CardExpressions
## Standing expressions for the pixel cards (docs/POSE_STUDIO_SPEC.md stage 10): idle and ready
## variants coloured by each player's mood. Visual only: CardMotionLayer applies the channels.
##
## Context picks the family:
##   idle     the ball is dead between points (after the reactions): relaxed, paddle down
##   waiting  a serve is coming (set-serve, WAITING, SERVING): ready, on the toes
##   live     the ball is in play: ready. The paddle arm is never moved here (arm, elbow and
##            spin are zeroed) so the shown paddle stays where gameplay has it.
## Mood picks the flavour (each 0..1, updated at rally end; fatigue from stamina):
##   frustration  own errors (+0.5), team losses (+0.15); fades as the team wins
##   confidence   the team's winning streak
##   tension      late, close score (both near 11, or game point)
##   fatigue      stamina below full speed
## Expressions crossfade over BLEND s and fade with travel speed. Channels as card_reactions.gd,
## plus look (head turn, deg, + = toward the forehand side) and shrug (shoulders and head up, m).
##
## Not in lockstep (CardProfile): each player notices a change after their own delay, so the shown
## context lags the real one. Into idle: winners first, the one who erred a beat later. Into
## waiting: the server first, the receiving team next, the server's partner last. Into live: at
## once. Loops run at the player's own tempo and phase.

const CardProfileScript = preload("res://scripts/graphics/card_profile.gd")
const BLEND: = 0.45
const MOOD_ON: = 0.35
const CHANNELS: = ["arm", "elbow", "torso", "head", "bob", "spin", "look", "shrug"]
const ARM_CHANNELS: = ["arm", "elbow", "spin"]
const NAMES: = ["idle", "idle_tired", "idle_frustrated", "idle_confident", "ready", "ready_waiting",
	"ready_tense", "ready_frustrated", "ready_tired"]

var _player
var _game: Node = null
var _connected: = false
var frustration: = 0.0
var confidence: = 0.0
var _streak: = 0
var _w: Dictionary = {}       # expression -> blend weight
var _t: = 0.0
var _forced: = ""             # bench / studio: show this one regardless of context and mood
var _target: = ""
var profile   # CardProfile
var _shown_ctx: = "idle"      # the context this player has reacted to (lags the real one)
var _pending_ctx: = ""
var _pending_t: = 0.0
var _last_won: = true
var _last_erred: = false

func _init(player) -> void:
	_player = player
	profile = CardProfileScript.new(int(player.get_actor_id()) if player.has_method("get_actor_id") else 0)
	_t = profile.phase

func _connect() -> void:
	if _connected: return
	_game = _player.get_parent()
	if _game == null or not "rally_scorer" in _game or _game.rally_scorer == null: return
	_game.rally_scorer.rally_ended.connect(_on_rally_ended)
	_connected = true

func _on_rally_ended(winner: int, _r: String, _d: String) -> void:
	if winner not in [0, 1] or not is_instance_valid(_player): return
	if _game.has_method("_is_practice") and _game._is_practice(): return
	var won: bool = int(_player.get_team_id()) == winner
	var ball = _game.get("ball")
	var erred: bool = not won and ball != null and int(ball.get("last_hit_actor_id")) == int(_player.get_actor_id())
	_last_won = won
	_last_erred = erred
	if won:
		_streak += 1
		frustration *= 0.55
	else:
		_streak = 0
		frustration = minf(1.0, frustration * 0.85 + (0.5 if erred else 0.15))
	confidence = clampf(0.25 * float(_streak - 1), 0.0, 1.0)

func tension() -> float:
	if _game == null or _game.get("score_left") == null: return 0.0
	var a: int = int(_game.score_left)
	var b: int = int(_game.score_right)
	if maxi(a, b) >= 10: return 1.0
	if mini(a, b) >= 7 and absi(a - b) <= 2: return 0.6
	return 0.0

func fatigue() -> float:
	var st = _player.get("stamina")
	if st == null or not st.has_method("speed_factor"): return 0.0
	return clampf((1.0 - float(st.speed_factor())) / 0.15, 0.0, 1.0)

## True when the ball is in play and nothing is forced: the paddle arm must not move at all.
func live() -> bool:
	return _forced == "" and _context() == "live"

## Show one expression regardless of context and mood ("" = back to automatic).
func force(name: String) -> void:
	_forced = name

func current() -> String:
	return _target

func _context() -> String:
	var ball = _game.get("ball") if _game != null else null
	if ball != null and bool(ball.get("is_in_play")): return "live"
	# Set-serve: everyone takes the athletic stance for the coming rally.
	var bpc = _game.get("between_point_controller") if _game != null else null
	if bpc != null and is_instance_valid(bpc) and bpc.is_active() and str(bpc.get("phase")) == "SET_SERVE": return "waiting"
	var st = _game.get("game_state") if _game != null else null
	if st != null and "GameState" in _game and (int(st) == int(_game.GameState.WAITING) or int(st) == int(_game.GameState.SERVING)):
		return "waiting"
	return "idle"

## The context this player shows: the real one after this player's own delay (live at once).
func shown_context() -> String:
	return _shown_ctx

func _update_shown(delta: float) -> void:
	var raw: = _context()
	if raw == "live" or _game == null:
		_shown_ctx = raw
		_pending_ctx = ""
		return
	if raw == _shown_ctx:
		_pending_ctx = ""
		return
	if raw != _pending_ctx:
		_pending_ctx = raw
		_pending_t = maxf(0.0, _delay_for(raw) + profile.jitter())
	_pending_t -= delta
	if _pending_t <= 0.0:
		_shown_ctx = raw
		_pending_ctx = ""

func _delay_for(ctx: String) -> float:
	if ctx == "idle":
		return profile.notice + (0.0 if _last_won else (0.6 if _last_erred else 0.25))
	# waiting: who has the serve
	var srv = _game.get_server_actor() if _game.has_method("get_server_actor") else null
	if srv == null or not is_instance_valid(srv): return profile.notice
	if srv == _player: return profile.notice * 0.5
	if int(srv.get_team_id()) == int(_player.get_team_id()): return profile.notice + 0.35
	return profile.notice + 0.15

func _pick() -> String:
	if _forced != "": return _forced
	var ctx: = _shown_ctx
	var ten: = tension()
	var tired: = fatigue()
	match ctx:
		"idle":
			if frustration >= MOOD_ON: return "idle_frustrated"
			if tired >= MOOD_ON: return "idle_tired"
			if confidence >= MOOD_ON: return "idle_confident"
			return "idle"
		"waiting":
			if ten >= MOOD_ON: return "ready_tense"
			if frustration >= MOOD_ON: return "ready_frustrated"
			if tired >= MOOD_ON: return "ready_tired"
			return "ready_waiting"
		_:
			if ten >= MOOD_ON: return "ready_tense"
			if frustration >= MOOD_ON: return "ready_frustrated"
			if tired >= MOOD_ON: return "ready_tired"
			return "ready"

## Advance; `amount` (0..1) scales the result (fades with speed, reactions and taps).
## Returns channel -> value ({} when nothing shows).
func update(delta: float, amount: float) -> Dictionary:
	_connect()
	_t += delta * profile.tempo
	_update_shown(delta)
	_target = _pick()
	for n in NAMES:
		var goal: float = 1.0 if n == _target else 0.0
		_w[n] = move_toward(float(_w.get(n, 0.0)), goal, delta / BLEND)
	if amount <= 1e-3: return {}
	var out: = {}
	for ch in CHANNELS: out[ch] = 0.0
	var any: = false
	for n in NAMES:
		var w: float = float(_w.get(n, 0.0))
		if w <= 1e-4: continue
		any = true
		var c: Dictionary = sample(n, _t)
		for ch in c: out[ch] += float(c[ch]) * w
	if not any: return {}
	var live: bool = _forced == "" and _context() == "live"
	for ch in out:
		out[ch] = 0.0 if (live and ch in ARM_CHANNELS) else float(out[ch]) * amount
	return out

## Channel values of an expression at time t (looping, a few seconds per cycle).
static func sample(name: String, t: float) -> Dictionary:
	var breath: float = sin(t * 1.7)
	match name:
		"idle":   # relaxed stand: paddle down, upright, breathing, an easy look around
			return {"arm": -28.0, "elbow": -10.0, "torso": -2.0, "bob": 0.006 * breath,
				"look": 14.0 * sin(t * 0.45) * _gate(t, 7.0, 0.0, 3.5)}
		"idle_tired":   # hunched, heavy breathing, paddle hanging
			return {"arm": -38.0, "elbow": -15.0, "torso": 10.0, "head": 12.0, "bob": 0.012 * sin(t * 2.6), "shrug": -0.012}
		"idle_frustrated":   # head down, shoulders low, a shake of the head now and then
			return {"arm": -32.0, "elbow": -12.0, "torso": 6.0, "head": 16.0, "shrug": -0.015, "bob": 0.005 * breath,
				"look": 13.0 * sin(t * 10.0) * _gate(t, 4.5, 1.0, 0.7)}
		"idle_confident":   # chest up, paddle carried higher, a twirl now and then
			return {"arm": -12.0, "elbow": 10.0, "torso": -5.0, "head": -4.0, "bob": 0.005 * breath,
				"spin": _twirl(fposmod(t, 5.0) - 2.0, 0.55)}
		"ready":   # the gameplay ready pose with breathing
			return {"bob": 0.004 * breath}
		"ready_waiting":   # on the toes for the serve
			return {"bob": 0.012 * absf(sin(t * 3.2)), "torso": 2.0}
		"ready_tense":   # shoulders up, leaning in, quick small bounce, eyes fixed
			return {"shrug": 0.02, "torso": 5.0, "head": -3.0, "bob": 0.006 * absf(sin(t * 5.5))}
		"ready_frustrated":   # head low, shoulders dropped
			return {"head": 9.0, "torso": 3.0, "shrug": -0.012, "bob": 0.004 * breath}
		"ready_tired":   # hunched, heavier breathing
			return {"torso": 7.0, "head": 6.0, "shrug": -0.008, "bob": 0.009 * sin(t * 2.4)}
	return {}

## 0..1 window that opens for `width` s every `period` s, starting at `offset`.
static func _gate(t: float, period: float, offset: float, width: float) -> float:
	var u: float = fposmod(t - offset, period)
	if u > width: return 0.0
	return sin(PI * u / width)

## One full paddle turn over `width` s from u = 0; 0 outside (a full turn looks the same as none).
static func _twirl(u: float, width: float) -> float:
	if u <= 0.0 or u >= width: return 0.0
	return 360.0 * smoothstep(0.0, width, u)
