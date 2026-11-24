extends RefCounted
class_name CardStance
## Standing leg stances for the pixel cards between points. Visual only: CardMotionLayer moves the
## drawn feet and shifts the hips; the gameplay feet stay where they are.
##
## Ten stances. Each player goes through them in their own order, at their own width, holding
## each for a while, so the four never stand alike. A new stance is taken every time the player
## comes to a stop, and again after HOLD seconds of standing. Feet get to a new stance by
## stepping, one at a time, with the weight on the other foot.
##
## Per stance, for the right and the left foot: half = m from the centre line, fwd = m ahead of
## the middle of the feet, heel = m the heel is lifted (foot resting on its toes, knee bent).
## weight: -1 on the left foot .. +1 on the right foot (the hips shift over it).

const STANCES: = [
	{"name": "even",      "r": [0.15, 0.00, 0.0],   "l": [0.15, 0.00, 0.0],   "weight": 0.0},
	{"name": "lean_r",    "r": [0.11, 0.00, 0.0],   "l": [0.17, 0.03, 0.035], "weight": 0.8},
	{"name": "lean_l",    "r": [0.17, 0.03, 0.035], "l": [0.11, 0.00, 0.0],   "weight": -0.8},
	{"name": "wide",      "r": [0.27, 0.00, 0.0],   "l": [0.27, 0.00, 0.0],   "weight": 0.0},
	{"name": "wide_r",    "r": [0.23, -0.02, 0.0],  "l": [0.27, 0.02, 0.0],   "weight": 0.22},
	{"name": "wide_l",    "r": [0.27, 0.02, 0.0],   "l": [0.23, -0.02, 0.0],  "weight": -0.22},
	{"name": "stagger_r", "r": [0.15, 0.07, 0.0],   "l": [0.16, -0.04, 0.0],  "weight": -0.5},
	{"name": "stagger_l", "r": [0.16, -0.04, 0.0],  "l": [0.15, 0.07, 0.0],   "weight": 0.5},
	{"name": "narrow",    "r": [0.11, 0.00, 0.0],   "l": [0.11, 0.00, 0.0],   "weight": 0.0},
	{"name": "toe_back",  "r": [0.15, -0.07, 0.05], "l": [0.13, 0.02, 0.0],   "weight": -0.85},
]
const STEP_TIME: = 0.30     # s for one foot to step to its new spot
const STEP_LIFT: = 0.03     # m the stepping foot lifts
const STEP_LEAD: = 0.16     # s the weight shifts off a foot before it steps
const STEP_WEIGHT: = 0.7    # weight on the standing foot while the other steps
const HOLD: = Vector2(7.0, 13.0)   # s in one stance
const EXIT_TIME: = 0.25     # s for the feet to go back to the gameplay feet when the player moves off
const HEEL_RATE: = 0.18     # m/s the heel lifts / lowers

var weight: = 0.0           # eased, -1 left .. +1 right (0 when not standing)
var _order: Array = []
var _at: = 0
var _hold: = 0.0
var _on: = false
var _k: = 0.0               # 1 while in a stance, eases to 0 when leaving it
var _pos: Array = [Vector2.ZERO, Vector2.ZERO]    # right, left: drawn spot (side, fwd) from the middle of the feet
var _from: Array = [Vector2.ZERO, Vector2.ZERO]
var _to: Array = [Vector2.ZERO, Vector2.ZERO]
var _u: Array = [1.0, 1.0]      # step progress (1 = planted)
var _wait: Array = [0.0, 0.0]   # s before the foot steps
var _heel: Array = [0.0, 0.0]
var _heel_to: Array = [0.0, 0.0]
var _goal_weight: = 0.0
var _scale: = 1.0
var _mirror: = false
var _forced: = -1
var _rng: = RandomNumberGenerator.new()

func _init(actor_id: int) -> void:
	_rng.seed = 32452843 * (actor_id + 7)
	_order = range(STANCES.size())
	for i in range(_order.size() - 1, 0, -1):   # this player's own order
		var j: int = _rng.randi_range(0, i)
		var keep = _order[i]
		_order[i] = _order[j]
		_order[j] = keep
	_at = posmod(actor_id * 3, _order.size())
	_scale = _rng.randf_range(0.9, 1.15)
	_mirror = posmod(actor_id, 2) == 1

## Bench / studio: hold this stance (-1 = back to the player's own order).
func force(index: int) -> void:
	_forced = index
	_hold = 0.0

func current() -> String:
	return str(STANCES[_index()].name) if _on else ""

func _index() -> int:
	return clampi(_forced, 0, STANCES.size() - 1) if _forced >= 0 else int(_order[_at])

## `base`: the two feet as gameplay has them, [right, left], each (side, fwd) from their middle.
## Returns {"d": [right, left] moves as Vector3(side, up, fwd), "weight": -1..1}.
func update(delta: float, active: bool, base: Array) -> Dictionary:
	if active and not _on:
		var k: float = smoothstep(0.0, 1.0, _k)
		for i in 2:
			_pos[i] = Vector2(base[i]).lerp(_pos[i], k)   # from where the feet are drawn now
			_heel[i] *= k
		_on = true
		_k = 1.0
		_advance(base)
	elif not active and _on:
		_on = false
	if _on:
		_hold -= delta
		if _hold <= 0.0 and _u[0] >= 1.0 and _u[1] >= 1.0: _advance(base)
	else:
		_k = move_toward(_k, 0.0, delta / EXIT_TIME)
		_goal_weight = 0.0
	var lift: Array = [0.0, 0.0]
	var stepping: = -1
	for i in 2:
		if _u[i] >= 1.0: continue
		var far: float = Vector2(_from[i]).distance_to(_to[i])
		if _wait[i] > 0.0:
			_wait[i] -= delta
			if _wait[i] <= STEP_LEAD and stepping < 0 and far > 0.03: stepping = i
			continue
		_u[i] = minf(1.0, _u[i] + delta / STEP_TIME)
		_pos[i] = Vector2(_from[i]).lerp(_to[i], smoothstep(0.0, 1.0, _u[i]))
		lift[i] = sin(PI * _u[i]) * STEP_LIFT * clampf(far / 0.06, 0.0, 1.0)
		if far > 0.03: stepping = i
	var goal: float = _goal_weight
	if stepping == 0: goal = -STEP_WEIGHT
	elif stepping == 1: goal = STEP_WEIGHT
	weight = lerpf(goal, weight, pow(0.5, delta / 0.09)) if delta > 0.0 else goal
	var k: float = smoothstep(0.0, 1.0, _k)
	var d: Array = []
	for i in 2:
		_heel[i] = move_toward(_heel[i], _heel_to[i] if (_on and _u[i] >= 1.0) else 0.0, delta * HEEL_RATE)
		var off: Vector2 = (Vector2(_pos[i]) - Vector2(base[i])) * k
		d.append(Vector3(off.x, (lift[i] + _heel[i]) * k, off.y))
	return {"d": d, "weight": weight * k}

## Take the next stance: set each foot's target and the order they step in.
func _advance(base: Array) -> void:
	if _forced < 0: _at = (_at + 1) % _order.size()
	var st: Dictionary = STANCES[_index()]
	_hold = _rng.randf_range(HOLD.x, HOLD.y)
	var right: Array = st.l if _mirror else st.r
	var left: Array = st.r if _mirror else st.l
	_goal_weight = -float(st.weight) if _mirror else float(st.weight)
	# The side axis runs from the left hip to the right hip, so the right foot is always at +x.
	# Fore-aft offsets stay small on purpose: seen from the camera a long stagger reads as crossed legs.
	_to[0] = Vector2(float(right[0]) * _scale, float(right[1]))
	_to[1] = Vector2(-float(left[0]) * _scale, float(left[1]))
	_heel_to = [float(right[2]), float(left[2])]
	# The foot that will carry the weight goes first; the resting foot follows.
	var first: int = 0 if _goal_weight >= 0.0 else 1
	if absf(_goal_weight) < 0.05: first = 0 if Vector2(_pos[0]).distance_to(_to[0]) >= Vector2(_pos[1]).distance_to(_to[1]) else 1
	for i in 2:
		_from[i] = _pos[i]
		_u[i] = 0.0
		_wait[i] = STEP_LEAD if i == first else STEP_LEAD * 2.0 + STEP_TIME + 0.08
