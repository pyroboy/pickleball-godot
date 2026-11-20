extends RefCounted
class_name CardReactions
## Between-point reactions for the pixel cards (docs/POSE_STUDIO_SPEC.md stage 10). Visual only:
## CardMotionLayer turns the curves sampled here into card deltas, so gameplay never sees them.
##
## A reaction is a short keyed curve over a few channels:
##   arm    paddle arm lift about the shoulder, deg (+ = hand up / forward)
##   elbow  forearm bend about the elbow, deg (+ = hand up)
##   torso  lean about the hips, deg (+ = forward, - = back)
##   head   head nod, deg (+ = chin down)
##   bob    whole body up, m
##   spin   paddle spin about its shaft, deg
## Only the paddle arm moves: the other hand carries the ball between points.
## Picked at rally end from a per-player mood (won / lost, who erred, streak, margin), never the
## same one twice in a row, with this player's own RNG (the bench-seeded global RNG is untouched).
## Plays only while the ball is dead; fades out at once when the next rally starts.

const CHANNELS: = ["arm", "elbow", "torso", "head", "bob", "spin"]
const FADE_OUT: = 0.15
# name -> [[t, {channel: value}], ...]; missing channels are 0 at that key.
const REACTIONS: = {
	"fist_pump": [[0.0, {}], [0.16, {"arm": 35.0, "elbow": 55.0, "torso": -3.0}],
		[0.30, {"arm": 48.0, "elbow": 80.0, "torso": -5.0, "bob": 0.02}], [0.44, {"arm": 30.0, "elbow": 55.0, "torso": -2.0}],
		[0.58, {"arm": 48.0, "elbow": 80.0, "torso": -5.0, "bob": 0.02}], [0.80, {"arm": 35.0, "elbow": 55.0, "torso": -2.0}],
		[1.15, {}]],
	"bounce": [[0.0, {}], [0.12, {"bob": 0.035, "arm": 18.0}], [0.24, {"arm": 14.0}], [0.36, {"bob": 0.035, "arm": 18.0}],
		[0.48, {"arm": 14.0}], [0.60, {"bob": 0.03, "arm": 16.0}], [0.72, {"arm": 10.0}], [0.95, {}]],
	"paddle_twirl": [[0.0, {}], [0.15, {"arm": 28.0, "elbow": 20.0}], [0.85, {"arm": 28.0, "elbow": 20.0, "spin": 720.0}],
		[1.15, {"spin": 720.0}]],
	"head_drop": [[0.0, {}], [0.35, {"head": 32.0, "torso": 12.0, "arm": -12.0}], [1.05, {"head": 36.0, "torso": 14.0, "arm": -14.0}],
		[1.45, {}]],
	"head_drop_small": [[0.0, {}], [0.30, {"head": 18.0, "torso": 6.0, "arm": -8.0}], [0.80, {"head": 20.0, "torso": 6.0, "arm": -8.0}],
		[1.10, {}]],
}

static var _streaks: Dictionary = {}   # game instance id -> [last winning team, count]

var _player
var _rng: = RandomNumberGenerator.new()
var _game: Node = null
var _connected: = false
var _name: = ""
var _last: = ""
var _t: = 0.0
var _delay: = 0.0
var _fade: = 1.0
var _fading: = false
var _generation: = -1

func _init(player) -> void:
	_player = player
	# Own, fixed seed per actor: repeatable runs, no draws from the global RNG.
	_rng.seed = 7919 * (int(player.get_actor_id()) + 1) if player.has_method("get_actor_id") else 7919

func active() -> bool:
	return _name != ""

func current() -> String:
	return _name

## Start a reaction by name now (bench and studio use this too).
func play(name: String, delay: float = 0.0) -> void:
	if not REACTIONS.has(name): return
	_name = name
	_last = name
	_t = 0.0
	_delay = delay
	_fade = 1.0
	_fading = false

## Let the current reaction go (quick fade), e.g. when a partner tap takes over.
func stop() -> void:
	if _name != "": _fading = true

static func duration(name: String) -> float:
	var keys: Array = REACTIONS.get(name, [])
	return float(keys[-1][0]) if not keys.is_empty() else 0.0

func _connect() -> void:
	if _connected: return
	_game = _player.get_parent()
	if _game == null or not "rally_scorer" in _game or _game.rally_scorer == null: return
	_game.rally_scorer.rally_ended.connect(_on_rally_ended)
	_connected = true

func _on_rally_ended(winner: int, _reason: String, _detail: String) -> void:
	if winner not in [0, 1] or not is_instance_valid(_player): return
	if _game.has_method("_is_practice") and _game._is_practice(): return
	var gid: int = _game.get_instance_id()
	# Each rig hears the signal; count the streak once per rally.
	var gen: int = int(_game.get("_point_reset_generation")) if _game.get("_point_reset_generation") != null else 0
	var s: Array = _streaks.get(gid, [-1, 0, -999])
	if s[2] != gen:
		s = [winner, (int(s[1]) + 1) if int(s[0]) == winner else 1, gen]
		_streaks[gid] = s
	var team: int = int(_player.get_team_id())
	var won: bool = team == winner
	var ball = _game.get("ball")
	var erred: bool = not won and ball != null and int(ball.get("last_hit_actor_id")) == int(_player.get_actor_id())
	var streak: int = int(s[1]) if won else 0
	var margin: int = 0
	if _game.get("score_left") != null:
		margin = (int(_game.score_left) - int(_game.score_right)) * (1 if team == 0 else -1)
	var pick: = _choose(won, erred, streak, margin)
	if pick != "": play(pick, _rng.randf_range(0.12, 0.32))

## Mood -> weighted candidates; never the last one again.
func _choose(won: bool, erred: bool, streak: int, margin: int) -> String:
	var cands: Dictionary = {}
	if won:
		cands = {"fist_pump": 1.0 + (1.5 if streak >= 2 else 0.0) + (1.0 if margin >= 3 else 0.0),
			"bounce": 1.2, "paddle_twirl": 0.8, "": 0.6}
	elif erred:
		cands = {"head_drop": 2.0 + (1.0 if margin <= -3 else 0.0), "head_drop_small": 1.0}
	else:
		cands = {"head_drop_small": 1.0, "": 1.5}
	cands.erase(_last)
	var total: = 0.0
	for k in cands: total += float(cands[k])
	var r: = _rng.randf() * total
	for k in cands:
		r -= float(cands[k])
		if r <= 0.0: return k
	return ""

## Advance and sample. Returns {} when nothing plays, else channel -> value (already faded).
func update(delta: float) -> Dictionary:
	_connect()
	if _name == "": return {}
	var ball = _game.get("ball") if _game != null else null
	if not _fading and ball != null and bool(ball.get("is_in_play")): _fading = true   # next rally: let go
	if _fading:
		_fade = move_toward(_fade, 0.0, delta / FADE_OUT)
		if _fade <= 0.0:
			_name = ""
			return {}
	if _delay > 0.0:
		_delay -= delta
		if _fading: _name = ""
		return {}
	_t += delta
	if _t >= duration(_name) or _fade <= 0.0:
		_name = ""
		return {}
	var out: = sample(_name, _t)
	for k in out: out[k] = float(out[k]) * _fade
	return out

## Channel values of a reaction at time t (smoothstep between keys).
static func sample(name: String, t: float) -> Dictionary:
	var keys: Array = REACTIONS.get(name, [])
	var out: = {}
	if keys.is_empty(): return out
	var i: = 0
	while i < keys.size() - 2 and t > float(keys[i + 1][0]): i += 1
	var a: Array = keys[i]
	var b: Array = keys[mini(i + 1, keys.size() - 1)]
	var span: float = maxf(float(b[0]) - float(a[0]), 1e-4)
	var u: float = smoothstep(0.0, 1.0, clampf((t - float(a[0])) / span, 0.0, 1.0))
	for ch in CHANNELS:
		out[ch] = lerpf(float(a[1].get(ch, 0.0)), float(b[1].get(ch, 0.0)), u)
	return out
