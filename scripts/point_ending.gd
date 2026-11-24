extends RefCounted
## The one definition of how a point ended (GAME_MECHANICS_PLAN change 9). The bench
## report, the phone log ("point_ending" note) and the end-of-rally stamp read this.
## Reads only facts already decided (rally end reason, last contacts); never changes play.
const Tuning = preload("res://scripts/gameplay_tuning.gd")

const WINNER := "WINNER"
const FORCED_ERROR := "FORCED_ERROR"
const UNFORCED_ERROR := "UNFORCED_ERROR"
const UNCOVERED := "UNCOVERED"
const BODY_HIT := "BODY_HIT"
const RULE_FAULT := "RULE_FAULT"

const ERROR_REASONS := ["BALL_IN_NET", "OUT_OF_BOUNDS", "NET_POST"]
const ATTACK_TACTICS := ["SMASH", "SPEED_UP", "DRIVE", "LOB"]
const HARD_SPEED := 10.0

var _last: Dictionary = {}     # last contact of the rally
var shots: int = 0             # contacts this rally (serve included)
var _last_tick: int = -1
## Rally pressure: soft shots in a row this rally; an attack, drive or lob resets it.
var soft_run: int = 0
## Data: did the human's team (team 0) touch the ball this rally after the serve.
var human_team_touched := false
const SOFT_TACTICS := ["DINK", "DROP", "RESET"]
## Power shots in a row per team (any drive / smash / speed-up, or 11 m/s and up); a
## touch shot by that team resets it. The receiving AI reads it (habit).
var power_streak: Array[int] = [0, 0]
## Recent shots per team (true = power shot), newest last; kept across rallies (a habit).
var recent_power: Array = [[], []]

## Share of power shots among team t's last n shots (0 with fewer than 3 shots seen).
func power_share(t: int, n: int) -> float:
	if t not in [0, 1]: return 0.0
	var h: Array = recent_power[t]
	if h.size() < 3: return 0.0
	var tail: Array = h.slice(maxi(0, h.size() - n))
	return float(tail.count(true)) / float(tail.size())
const POWER_TACTICS := ["DRIVE", "SMASH", "SPEED_UP", "GROUNDSTROKE"]

## Seconds since the last contact of this rally (-1 before the serve).
func seconds_since_contact() -> float:
	if _last_tick < 0: return -1.0
	return float(Engine.get_physics_frames() - _last_tick) / float(Engine.physics_ticks_per_second)

func reset() -> void:
	_last = {}
	shots = 0
	_last_tick = -1
	soft_run = 0
	power_streak = [0, 0]
	human_team_touched = false

## Called once per contact, after the execution error is applied.
## `cause`: the hitter's own mishit cause, as a stamp word ("" for a clean hit).
func record_contact(actor_id: int, team: int, difficulty: float, tactic: String, speed: float, serve: bool, cause: String = "") -> void:
	if serve: shots = 0; soft_run = 0
	shots += 1
	soft_run = soft_run + 1 if tactic in SOFT_TACTICS else 0
	if team == 0 and not serve: human_team_touched = true
	if team in [0, 1]:
		var power: bool = (tactic in POWER_TACTICS or speed >= 11.0) and not serve
		power_streak[team] = power_streak[team] + 1 if power else 0
		if not serve:
			recent_power[team].append(power)
			if recent_power[team].size() > 12: recent_power[team].pop_front()
	_last_tick = Engine.get_physics_frames()
	_last = {"actor": actor_id, "team": team, "difficulty": difficulty, "tactic": tactic, "speed": speed, "why": cause}

## Name the ending. Returns {"ending", "cause", "actor", "difficulty", "shots", "where", "why"}.
## "where" and "why" are the two stamp lines (docs/SHOT_QUALITY_PLAN.md, proposal A): where the
## ball went, and the hitter's own cause. Only facts the player could see: never who "forced" it.
## `at`: the ball when the rally ended; `clearance`: the last shot's planned height over the tape.
func classify(winner: int, reason: String, at: Vector3 = Vector3.INF, clearance: float = -1.0) -> Dictionary:
	var out: Dictionary = {"ending": RULE_FAULT, "cause": "", "actor": int(_last.get("actor", -1)),
		"difficulty": snappedf(float(_last.get("difficulty", 0.0)), 0.01), "shots": shots, "reason": reason}
	if reason == "BODY_HIT":
		out.ending = BODY_HIT
	elif reason in ERROR_REASONS:
		var forced: bool = float(_last.get("difficulty", 0.0)) >= Tuning.FORCED_LINE
		out.ending = FORCED_ERROR if forced else UNFORCED_ERROR
		out.cause = "net" if reason == "BALL_IN_NET" else "out"
	elif reason == "DOUBLE_BOUNCE":
		var attack: bool = str(_last.get("tactic", "")) in ATTACK_TACTICS or float(_last.get("speed", 0.0)) >= HARD_SPEED
		out.ending = WINNER if attack and int(_last.get("team", -1)) == winner else UNCOVERED
	out["where"] = _where(str(out.ending), reason, at, clearance)
	out["why"] = str(_last.get("why", "")) if reason in ERROR_REASONS else ""
	return out

const JUST_OUT := 0.20     # m past the line that reads as "just" out

func _where(ending: String, reason: String, at: Vector3, clearance: float) -> String:
	match reason:
		"BALL_IN_NET": return "NET"   # one word for every net ball (user's call: "TAPE" / "NET TOP" were not clear)
		"OUT_OF_BOUNDS":
			if not at.is_finite(): return "OUT"
			var long_by: float = absf(at.z) - PickleballConstants.COURT_LENGTH * 0.5
			var wide_by: float = absf(at.x) - PickleballConstants.COURT_WIDTH * 0.5
			if long_by <= 0.0 and wide_by <= 0.0: return "OUT"
			var word: String = "WIDE" if wide_by > long_by else "LONG"
			return ("JUST " + word) if maxf(long_by, wide_by) < JUST_OUT else word
		"DOUBLE_BOUNCE":
			if shots <= 1: return "ACE!"
			if ending == UNCOVERED: return "DROPPED IN"
			return "SMASH!" if str(_last.get("tactic", "")) == "SMASH" else "WINNER!"
	return ""

## Short words for the stamp.
static func label(ending: String) -> String:
	return {WINNER: "WINNER", FORCED_ERROR: "FORCED", UNFORCED_ERROR: "UNFORCED", UNCOVERED: "", BODY_HIT: "", RULE_FAULT: ""}.get(ending, "")
