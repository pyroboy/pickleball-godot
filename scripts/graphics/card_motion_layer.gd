extends RefCounted
class_name CardMotionLayer
## Visual-only body motion for the pixel cards (docs/POSE_STUDIO_SPEC.md stages 8 and 9).
##
## The card rig draws every joint through PixelCardRig._xf(). This layer holds a world-space
## delta per joint node, rebuilt each rendered frame, and the rig applies it after the
## interpolated read. Nothing here writes a pivot, so gameplay (IK, contact, reach, the meshes
## under BodyPivot) never sees this motion. The paddle skin applies the paddle hand's delta so
## the shown paddle stays in the shown hand.
##
## Motion so far (Stage 9): while running or walking, the free arm swings against the legs and
## the shoulders counter-turn against the hips, both driven by the real feet so they stay in
## step. Only when travelling along the facing (not in a side shuffle). Off during strokes,
## pose editors and between-point carries.
## Reactions (stage 10, card_reactions.gd): fist pump, bounce, paddle twirl, head drop, played
## at rally end on the paddle arm, torso, head and a small body bob.
## PICKLEBALL_CARD_MOTION=0 turns the layer off (A/B checks).

const SWING_DEG: = 20.0       # free-arm swing at a full stride and full speed
const TWIST_DEG: = 7.0        # shoulder counter-turn at a full stride and full speed
const SPEED_START: = 0.35     # m/s: below this, no gait motion
const SPEED_FULL: = 3.0       # m/s: full amplitude
const STRIDE_REF: = 0.32      # metres of front-back foot split read as a full stride
const WEIGHT_RATE: = 5.0      # 1/s fade in and out
const SPEED_HALF_LIFE: = 0.08
const SWING_OMEGA: = 28.0     # rad/s: critically damped spring on the swing (no frame pops)

const CardReactionsScript = preload("res://scripts/graphics/card_reactions.gd")

static var _env_off: int = -1

var _rig   # PixelCardRig
var _deltas: Dictionary = {}  # Node3D -> Transform3D, world space, applied on top of the read
var _weight: = 0.0
var _speed: = 0.0
var _stride: = 0.0
var _amt: = 0.0               # sprung swing amount, -1..1
var _amt_v: = 0.0
var _reactions = null         # CardReactions: between-point reactions (stage 10)
var _spin: = 0.0
var _prev_pos: = Vector3.INF
var _dir: = Vector3.ZERO      # smoothed horizontal travel direction (unit or zero)

func _init(rig) -> void:
	_rig = rig

static func enabled() -> bool:
	if _env_off < 0: _env_off = 1 if OS.get_environment("PICKLEBALL_CARD_MOTION") == "0" else 0
	return _env_off == 0

func clear() -> void:
	_deltas.clear()

func has_motion() -> bool:
	return not _deltas.is_empty()

func apply(n: Node3D, xf: Transform3D) -> Transform3D:
	var d = _deltas.get(n)
	return xf if d == null else d * xf

## The shown paddle hand's delta (identity when the hand has none).
func paddle_delta(paddle_arm) -> Transform3D:
	if paddle_arm == null: return Transform3D.IDENTITY
	return _deltas.get(paddle_arm.hand_pivot, Transform3D.IDENTITY)

static func _turn_about(pivot: Vector3, axis: Vector3, angle: float) -> Transform3D:
	var b: = Basis(axis, angle)
	return Transform3D(b, pivot - b * pivot)

## Rebuild the deltas. Call with the deltas cleared, so the rig's reads are the plain ones.
func update(delta: float, swinging: bool, paddle_arm) -> void:
	_deltas.clear()
	_gait(delta, swinging, paddle_arm)
	_react(delta, paddle_arm)

func _gait(delta: float, swinging: bool, paddle_arm) -> void:
	var player = _rig._player
	var body: Node3D = player.body_pivot
	var bxf: Transform3D = _rig._xf(body)
	if delta > 0.0 and not _rig._raw:
		var pos: = bxf.origin
		if _prev_pos != Vector3.INF:
			var step: = pos - _prev_pos
			step.y = 0.0
			var inst: float = minf(step.length() / delta, 8.0)
			_speed = lerpf(inst, _speed, pow(0.5, delta / SPEED_HALF_LIFE))
			if step.length() > 1e-5:
				_dir = _dir.lerp(step.normalized(), 1.0 - pow(0.5, delta / SPEED_HALF_LIFE))
		_prev_pos = pos
	var between: bool = player.has_method("_between_point_owner") and player._between_point_owner() != null
	var fwd: Vector3 = bxf.basis * player._get_forward_axis()
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6: return
	fwd = fwd.normalized()
	# Arms swing when travelling along the body's facing (run, backpedal), not in a side shuffle.
	var along: float = smoothstep(0.35, 0.8, absf(_dir.dot(fwd)))
	var want: = 0.0
	if enabled() and not _rig._raw and not swinging:
		want = smoothstep(SPEED_START, SPEED_FULL, _speed) * along
	_weight = move_toward(_weight, want, delta * WEIGHT_RATE)
	if _weight < 0.001:
		_amt = 0.0
		_amt_v = 0.0
		return
	var side: = fwd.cross(Vector3.UP).normalized()
	var rleg: Node3D = player.get("right_leg_node")
	var lleg: Node3D = player.get("left_leg_node")
	if rleg == null or lleg == null or rleg.get("foot_pivot") == null or lleg.get("foot_pivot") == null: return
	# +1: left foot forward (right arm forward, right shoulder forward), -1: right foot forward.
	var split: float = (_rig._xf(lleg.foot_pivot).origin - _rig._xf(rleg.foot_pivot).origin).dot(fwd)
	_stride = lerpf(clampf(split / STRIDE_REF, -1.0, 1.0), _stride, pow(0.5, delta / 0.03))
	# Implicit critically damped spring: the foot split can jump when a foot re-plants.
	var w: = SWING_OMEGA
	_amt_v = (_amt_v + w * w * (_stride * _weight - _amt) * delta) / (1.0 + 2.0 * w * delta + w * w * delta * delta)
	_amt += _amt_v * delta
	var amt: float = clampf(_amt, -1.0, 1.0)
	var hips: Node3D = body.get_node_or_null("HipsMesh")
	var torso: Node3D = body.get_node_or_null("TorsoMesh")
	if torso == null: return
	var pivot: Vector3 = _rig._xf(hips if hips else body).origin
	var rarm: Node3D = player.get("right_arm_node")
	var larm: Node3D = player.get("left_arm_node")
	# Twist sign: a positive turn about UP must carry the right shoulder forward.
	var twist: = Transform3D.IDENTITY
	if rarm != null and rarm.get("upper_pivot") != null:
		var r: Vector3 = _rig._xf(rarm.upper_pivot).origin - pivot
		var sgn: float = signf(Vector3.UP.cross(r).dot(fwd))
		if sgn != 0.0: twist = _turn_about(pivot, Vector3.UP, deg_to_rad(TWIST_DEG) * amt * sgn)
	_deltas[torso] = twist
	var head: Node3D = torso.get_node_or_null("HeadMesh")
	# The head stays on the ball: it rides the shoulders' position, not their turn.
	if head != null:
		var hp: Vector3 = _rig._xf(head).origin
		_deltas[head] = Transform3D(Basis.IDENTITY, twist * hp - hp)
	for pair in [[rarm, 1.0], [larm, -1.0]]:
		var arm: Node3D = pair[0]
		if arm == null or arm.get("upper_pivot") == null: continue
		var swing: = Transform3D.IDENTITY
		if arm != paddle_arm and not between:
			var shoulder: Vector3 = _rig._xf(arm.upper_pivot).origin
			var hand: Vector3 = _rig._xf(arm.hand_pivot).origin
			var sgn: float = signf(side.cross(hand - shoulder).dot(fwd))
			if sgn != 0.0:
				swing = _turn_about(shoulder, side, deg_to_rad(SWING_DEG) * amt * float(pair[1]) * sgn)
		var d: = twist * swing
		for n in [arm.upper_pivot, arm.forearm_pivot, arm.hand_pivot]:
			if n != null: _deltas[n] = d

# ------------------------------------------------------------------ reactions (stage 10)

func _plain(n: Node3D) -> Vector3:
	return (n.global_transform if _rig._raw else n.get_global_transform_interpolated()).origin

## The reaction playing now ("" when none).
func reaction() -> String:
	return _reactions.current() if _reactions != null and enabled() else ""

## Paddle spin about its shaft this frame, radians (the paddle skin applies it).
func paddle_spin() -> float:
	return _spin

func _react(delta: float, paddle_arm) -> void:
	_spin = 0.0
	var player = _rig._player
	if _reactions == null: _reactions = CardReactionsScript.new(player)
	if not enabled() or _rig._raw: return
	var ch: Dictionary = _reactions.update(delta)
	if ch.is_empty(): return
	var body: Node3D = player.body_pivot
	var torso: Node3D = body.get_node_or_null("TorsoMesh")
	if torso == null: return
	var fwd: Vector3 = body.get_global_transform_interpolated().basis * player._get_forward_axis()
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6: return
	fwd = fwd.normalized()
	var side: = fwd.cross(Vector3.UP).normalized()
	var hips: Node3D = body.get_node_or_null("HipsMesh")
	var hip_p: Vector3 = _plain(hips if hips else body)
	var bob: = Transform3D(Basis.IDENTITY, Vector3.UP * float(ch.bob))
	# Each turn's sign is found from the joints, so + always means the same thing on screen.
	var lean: = Transform3D.IDENTITY
	if absf(float(ch.torso)) > 1e-3:
		var sgn: float = signf(side.cross(_plain(torso) - hip_p).dot(fwd))
		if sgn != 0.0: lean = _turn_about(hip_p, side, deg_to_rad(float(ch.torso)) * sgn)
	var upper: = bob * lean
	var add: = func(n: Node3D, d: Transform3D) -> void:
		if n == null: return
		_deltas[n] = d * _deltas.get(n, Transform3D.IDENTITY)
	add.call(body, bob)
	if hips != null: add.call(hips, bob)
	for leg_name in ["right_leg_node", "left_leg_node"]:
		var leg: Node3D = player.get(leg_name)
		if leg != null and leg.get("thigh_pivot") != null:
			for n in [leg.thigh_pivot, leg.shin_pivot, leg.foot_pivot]: add.call(n, bob)
	add.call(torso, upper)
	var head: Node3D = torso.get_node_or_null("HeadMesh")
	if head != null:
		var nod: = Transform3D.IDENTITY
		if absf(float(ch.head)) > 1e-3:
			var sgn: float = signf(side.cross(Vector3.UP).dot(fwd))
			nod = _turn_about(_plain(head), side, deg_to_rad(float(ch.head)) * sgn)
		add.call(head, upper * nod)
	for arm_name in ["right_arm_node", "left_arm_node"]:
		var arm: Node3D = player.get(arm_name)
		if arm == null or arm.get("upper_pivot") == null: continue
		var lift: = Transform3D.IDENTITY
		var bend: = Transform3D.IDENTITY
		if arm == paddle_arm:   # the other hand carries the ball between points
			var shoulder: Vector3 = _plain(arm.upper_pivot)
			var elbow: Vector3 = _plain(arm.forearm_pivot)
			var hand: Vector3 = _plain(arm.hand_pivot)
			if absf(float(ch.arm)) > 1e-3:
				var sgn: float = signf(side.cross(hand - shoulder).dot(Vector3.UP))
				if sgn != 0.0: lift = _turn_about(shoulder, side, deg_to_rad(float(ch.arm)) * sgn)
			if absf(float(ch.elbow)) > 1e-3:
				var sgn: float = signf(side.cross(hand - elbow).dot(Vector3.UP))
				if sgn != 0.0: bend = _turn_about(elbow, side, deg_to_rad(float(ch.elbow)) * sgn)
			_spin = deg_to_rad(float(ch.spin))
		add.call(arm.upper_pivot, upper * lift)
		add.call(arm.forearm_pivot, upper * lift * bend)
		add.call(arm.hand_pivot, upper * lift * bend)

