extends RefCounted
## Pose Studio timeline for a ball action (pickup / throw), the same shape as
## scripts/ui/mobile_pose_sequence.gd so the editor's transport plays it. Poses are built the way
## the game builds them (scripts/ball_actions.gd: code-built stand + the working copy's key
## deltas, ball hand from the code wrist targets), so playback shows what a point break will show.
##   pickup: stand -> Reach -> Grab -> Rise -> stand      throw: carry -> Wind-back -> Release -> Follow -> carry
## Marks: prefix_seconds = key 1, + release_seconds = key 2, + stroke_seconds = key 3.

const Actions = preload("res://scripts/ball_actions.gd")
const ArmPath = preload("res://scripts/between_point_arm_path.gd")

var source: Resource
var style := -2            # not a serve (the timeline's joint guide asks)
var prefix_seconds := 0.0
var release_seconds := 0.0
var stroke_seconds := 0.0
var full_seconds := 0.0
var preparation_seconds := 0.0
var duration := 0.0
var times: Array = []
var _deltas: Array = [{}, {}, {}]
var _ready: PostureDefinition

func configure(def: Resource, _mode = 0, _stance = 0, _variant = 0, _runtime = true, _player = null) -> void:
	source = def
	_ready = PostureLibrary.instance().get_def(Actions.READY_ID)
	_deltas = Actions.deltas_of(def)
	times = Actions.key_times(def)
	prefix_seconds = times[0]
	release_seconds = times[1] - times[0]
	stroke_seconds = times[2] - times[0]
	duration = times[3]
	full_seconds = duration - prefix_seconds

func permits_core_overlay() -> bool: return false
func _stance_copy(pose: PostureDefinition) -> PostureDefinition: return pose

## Key progress (0 key 1, 0.5 key 2, 1 key 3) -> pose (joint guide, ghosts).
func _stroke_pose(progress: float) -> PostureDefinition:
	var p := clampf(progress, 0.0, 1.0)
	var t: float = lerpf(times[0], times[1], p * 2.0) if p <= 0.5 else lerpf(times[1], times[2], (p - 0.5) * 2.0)
	return pose_at(t).pose

func sample(seconds: float) -> Dictionary:
	var t := clampf(seconds, 0.0, duration)
	var r := pose_at(t)
	var p := 0.0
	if t >= times[2]: p = 1.0
	elif t >= times[1]: p = 0.5 + 0.5 * (t - times[1]) / maxf(times[2] - times[1], 0.001)
	elif t >= times[0]: p = 0.5 * (t - times[0]) / maxf(times[1] - times[0], 0.001)
	return {"pose": r.pose, "phase": r.phase, "progress": p, "elapsed": t, "duration": duration, "split": {},
		"authored_key": -1, "context": true, "ball": r.ball}

## {pose, phase, ball (player axes: where the ball is; INF = flying away)} at t seconds.
func pose_at(t: float) -> Dictionary:
	var names: Array = Actions.KEY_NAMES[int(source.action_id)]
	var pose: PostureDefinition
	var hand: Vector3
	var phase := ""
	var ball := Vector3.INF
	var grab: Vector3 = Actions.grab_hand()
	if int(source.action_id) == Actions.PICKUP:
		var bt: float = source.bend_time
		var lt: float = source.lift_time
		if t <= bt:
			var b := smoothstep(0.0, bt - 0.05, t)
			var d := Actions.pickup_delta(_deltas, b, false)
			pose = Actions.stand_pose(_ready, b); Actions.add_to(pose, d)
			hand = Actions.CARRY_HAND.lerp(grab, b) + Actions.hand(d)
			phase = ("Stand → " + names[0]) if t < times[0] else (names[0] + " → " + names[1])
			ball = Actions.PICKUP_BALL
		else:
			var blend := smoothstep(0.0, lt - 0.08, t - bt)
			var d := Actions.pickup_delta(_deltas, 1.0 - blend, true)
			pose = Actions.stand_pose(_ready, 1.0 - blend); Actions.add_to(pose, d)
			hand = grab.lerp(Actions.CARRY_HAND, blend) + Actions.hand(d)
			phase = (names[1] + " → " + names[2]) if t < times[2] else (names[2] + " → Stand")
			ball = hand - Vector3(0, 0.075, 0)
	else:
		var wt: float = source.windup_time
		var rt: float = source.release_time
		var ft: float = source.follow_time
		var w0: Vector3 = Actions.CARRY_HAND + Actions.THROW_WINDUP + Actions.hand(_deltas[0])
		var w1: Vector3 = Actions.CARRY_HAND + Actions.THROW_FINISH + Actions.hand(_deltas[1])
		var w2: Vector3 = Actions.CARRY_HAND + Actions.hand(_deltas[2])
		var d: Dictionary
		# Edited throws swing the hand on an arc around the shoulder, as the game does.
		var edited := false
		for k in _deltas: edited = edited or not (k as Dictionary).is_empty()
		var sh: Vector3 = Actions.SHOULDER if edited else Vector3.INF
		if t < wt:
			var w := ArmPath.clock_weight(t / wt)
			d = Actions.mix({}, _deltas[0], w); hand = _swing(sh, Actions.CARRY_HAND, w0, w); phase = "Carry → " + names[0]
		elif t < rt:
			var w := ArmPath.clock_weight((t - wt) / maxf(rt - wt, 0.05))
			d = Actions.mix(_deltas[0], _deltas[1], w); hand = _swing(sh, w0, w1, w); phase = names[0] + " → " + names[1]
		elif t < rt + ft:
			var w := ArmPath.clock_weight((t - rt) / ft)
			d = Actions.mix(_deltas[1], _deltas[2], w); hand = _swing(sh, w1, w2, w); phase = names[1] + " → " + names[2]
		else:
			var w := clampf((t - rt - ft) / Actions.RETURN_TIME, 0.0, 1.0)
			d = Actions.mix(_deltas[2], {}, w); hand = _swing(sh, w2, Actions.CARRY_HAND, w); phase = names[2] + " → Carry"
		pose = Actions.stand_pose(_ready, 0.0); Actions.add_to(pose, d)
		if t < rt: ball = hand + Vector3(0, 0.075, 0)
	pose.left_hand_offset = hand - Actions.FREE_HAND
	return {"pose": pose, "phase": phase, "ball": ball}

func _swing(pivot: Vector3, a: Vector3, b: Vector3, w: float) -> Vector3:
	return a.lerp(b, w) if not pivot.is_finite() else Actions.arc(pivot, a, b, w)
