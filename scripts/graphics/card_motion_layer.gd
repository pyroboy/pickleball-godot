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
## pose editors and between-point carries. While the ball is in play the paddle arm never moves
## (the shown paddle is where gameplay has it); only the free arm swings and the chest turns.
## Stand straight between points (_stand_straight): the gameplay legs keep the athletic crouch;
## the cards lift the body and straighten the knees, feet where they are, and sink back into the
## athletic stance when the next rally is coming.
## Standing expressions (card_expressions.gd): idle / ready waiting / ready, coloured by mood.
## Partner paddle tap (card_partner_tap.gd) when partners pass within reach after a point.
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
const TAP_TURN_DEG: = 70.0    # chest turn toward the partner for a paddle tap (face each other)
const TAP_HIP_SHARE: = 0.35   # part of that turn the hips take, so the waist doesn't over-twist
const TAP_LEAN_DEG: = 5.0     # lean toward a partner who is farther away (up to 1.7 m)
const TAP_PADDLE_REACH: = 0.43  # m from the hand to the paddle tip (tips meet)
const TAP_PUSH: = 0.004       # m: the tap's push along the reach
const HOLD_EASE: = 0.1        # s to switch an arm between free and on the paddle
const HOLD_DIST: = 0.14       # m: a hand this close to the paddle shaft / throat holds it
const STAND_EASE: = 0.35      # s to rise / sink
const STAND_BEND: = 0.997     # hip-to-ankle as a share of leg length when standing (about 9 deg of knee)
const STAND_MAX_RAISE: = 0.20 # m
const STAND_MAX_SHIFT: = 0.15 # m the hips may shift to centre over the feet
const SWING_OMEGA: = 28.0     # rad/s: critically damped spring on the swing (no frame pops)

const CardReactionsScript = preload("res://scripts/graphics/card_reactions.gd")
const CardExpressionsScript = preload("res://scripts/graphics/card_expressions.gd")
const CardPartnerTapScript = preload("res://scripts/graphics/card_partner_tap.gd")

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
var _tap = null               # CardPartnerTap: partner paddle tap between points
var _tapping: = false
var _expressions = null       # CardExpressions: idle / ready moods while standing
var _expr_amount: = 0.0
var _stand_w: = 0.0           # 0 athletic crouch .. 1 standing straight (between points)
var stand_raise: = 0.0        # m the body is lifted this frame (bench)
var _free: Dictionary = {}    # arm -> 1 free .. 0 on the paddle (eased)
var last_channels: Dictionary = {}   # reaction / expression channels applied this frame (bench)
var _paddle_aim: = Transform3D.IDENTITY   # tap: paddle turned about the shown hand toward the partner
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

## The shown paddle's delta: the paddle hand's, plus the tap's turn of the paddle toward the partner.
func paddle_delta(paddle_arm) -> Transform3D:
	if paddle_arm == null: return Transform3D.IDENTITY
	return _paddle_aim * _deltas.get(paddle_arm.hand_pivot, Transform3D.IDENTITY)

## How free each arm is this frame (1 = free, 0 = on the paddle), eased so a hand near the
## paddle does not flicker between the two.
func _update_hold(delta: float, paddle_arm) -> void:
	for name in ["right_arm_node", "left_arm_node"]:
		var arm = _rig._player.get(name)
		if arm == null: continue
		var goal: float = 0.0 if (arm == paddle_arm or _holds_paddle(arm)) else 1.0
		var cur: float = float(_free.get(arm, goal))
		_free[arm] = move_toward(cur, goal, delta / HOLD_EASE) if delta > 0.0 else goal

func _free_w(arm) -> float:
	return float(_free.get(arm, 1.0))

## A hand on the paddle (the grip, or the support hand on the throat in two-handed holds).
func _holds_paddle(arm) -> bool:
	var paddle: Node3D = _rig._player.get("paddle_node")
	if paddle == null or arm == null or arm.get("hand_pivot") == null: return false
	var pxf: Transform3D = paddle.global_transform if _rig._raw else paddle.get_global_transform_interpolated()
	var a: Vector3 = pxf.origin
	var b: Vector3 = pxf * Vector3(0.0, 0.42, 0.0)
	var h: Vector3 = _plain(arm.hand_pivot)
	var ab: Vector3 = b - a
	var u: float = clampf((h - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return h.distance_to(a + ab * u) < HOLD_DIST

static func _turn_about(pivot: Vector3, axis: Vector3, angle: float) -> Transform3D:
	var b: = Basis(axis, angle)
	return Transform3D(b, pivot - b * pivot)

## Rebuild the deltas. Call with the deltas cleared, so the rig's reads are the plain ones.
func update(delta: float, swinging: bool, paddle_arm) -> void:
	_deltas.clear()
	_update_hold(delta, paddle_arm)
	_gait(delta, swinging, paddle_arm)
	_react(delta, paddle_arm, swinging)
	_partner_tap(delta, paddle_arm)
	_stand_straight(delta, swinging)

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
		var free: float = _free_w(arm)
		if free > 0.0 and not between:
			var shoulder: Vector3 = _rig._xf(arm.upper_pivot).origin
			var hand: Vector3 = _rig._xf(arm.hand_pivot).origin
			var sgn: float = signf(side.cross(hand - shoulder).dot(fwd))
			if sgn != 0.0:
				swing = _turn_about(shoulder, side, deg_to_rad(SWING_DEG) * amt * float(pair[1]) * sgn * free)
		var d: = twist * swing
		# Ball in play: the shown paddle and the hands on it stay where gameplay has them.
		if _expressions != null and _expressions.live(): d = Transform3D.IDENTITY.interpolate_with(d, free)
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

func _react(delta: float, paddle_arm, swinging: bool) -> void:
	_spin = 0.0
	var player = _rig._player
	if _reactions == null: _reactions = CardReactionsScript.new(player)
	if _expressions == null: _expressions = CardExpressionsScript.new(player)
	if _tap == null: _tap = CardPartnerTapScript.new(player)
	if not enabled() or _rig._raw: return
	var ch: Dictionary = _reactions.update(delta)
	# Standing expressions: fade with travel speed, and give way to reactions, taps, strokes
	# and hands busy with the ball.
	var want: float = 1.0 - smoothstep(0.3, 1.2, _speed)
	if not ch.is_empty() or _tapping or swinging or _tap._hands_busy(player): want = 0.0
	_expr_amount = move_toward(_expr_amount, want, delta / 0.2)
	var ex: Dictionary = _expressions.update(delta, _expr_amount)
	if ch.is_empty(): ch = ex
	elif not ex.is_empty():   # the expression fades out under the reaction (no snap)
		for k in ex: ch[k] = float(ch.get(k, 0.0)) + float(ex[k])
	last_channels = ch
	if ch.is_empty(): return
	# Ball in play: the shown paddle stays exactly where gameplay has it.
	_apply_channels(ch, paddle_arm, _expressions.live() and _reactions.current() == "")

## The standing expression showing now ("" when none).
func expression() -> String:
	return _expressions.current() if _expressions != null and enabled() and _expr_amount > 0.05 else ""

## Channels (card_reactions.gd / card_expressions.gd) -> card deltas, on top of the gait ones.
func _apply_channels(ch: Dictionary, paddle_arm, keep_paddle_arm: bool = false) -> void:
	var player = _rig._player
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
	var lifted: = upper * Transform3D(Basis.IDENTITY, Vector3.UP * float(ch.get("shrug", 0.0)))
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
		if absf(float(ch.get("look", 0.0))) > 1e-3:
			var sgn: float = signf(Vector3.UP.cross(fwd).dot(player._get_forehand_axis()))
			if sgn != 0.0: nod = _turn_about(_plain(head), Vector3.UP, deg_to_rad(float(ch.look)) * sgn) * nod
		add.call(head, lifted * nod)
	for arm_name in ["right_arm_node", "left_arm_node"]:
		var arm: Node3D = player.get(arm_name)
		if arm == null or arm.get("upper_pivot") == null: continue
		var keep: float = (1.0 - _free_w(arm)) if keep_paddle_arm else 0.0
		if keep >= 0.999: continue
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
		var du: Transform3D = (lifted * lift).interpolate_with(Transform3D.IDENTITY, keep)
		var dl: Transform3D = (lifted * lift * bend).interpolate_with(Transform3D.IDENTITY, keep)
		add.call(arm.upper_pivot, du)
		add.call(arm.forearm_pivot, dl)
		add.call(arm.hand_pivot, dl)

# ------------------------------------------------------------------ partner paddle tap

## True while this card taps paddles with its partner.
func tapping() -> bool:
	return _tapping

func _stop_reaction(p) -> void:
	var m = self
	if p != _rig._player:
		var host: Node = p.get_parent()
		var rig: Node = host.get_node_or_null("PixelCards_%d" % p.get_instance_id()) if host != null else null
		m = rig.get("_motion") if rig != null else null
	if m != null and m._reactions != null: m._reactions.stop()

func _partner_tap(delta: float, paddle_arm) -> void:
	_tapping = false
	_paddle_aim = Transform3D.IDENTITY
	var player = _rig._player
	if not enabled() or _rig._raw or paddle_arm == null: return
	var tap: Dictionary = _tap.update(delta, _stop_reaction)
	if tap.is_empty(): return
	_tapping = true
	var w: float = float(tap.w)
	var tw: float = float(tap.get("turn", w))
	if tw <= 1e-4 and w <= 1e-4: return
	var body: Node3D = player.body_pivot
	var torso: Node3D = body.get_node_or_null("TorsoMesh")
	if torso == null: return
	var fwd: Vector3 = body.get_global_transform_interpolated().basis * player._get_forward_axis()
	fwd.y = 0.0
	var to_p: Vector3 = tap.partner.global_position - player.global_position
	to_p.y = 0.0
	if fwd.length_squared() < 1e-6 or to_p.length_squared() < 1e-6: return
	# First the chest (and partly the hips) turn to face the partner, then the paddle hand reaches.
	var yaw: float = clampf(fwd.normalized().signed_angle_to(to_p.normalized(), Vector3.UP), -deg_to_rad(TAP_TURN_DEG), deg_to_rad(TAP_TURN_DEG)) * tw
	var hips: Node3D = body.get_node_or_null("HipsMesh")
	var hip_p: Vector3 = _plain(hips if hips else body)
	var turn: = _turn_about(hip_p, Vector3.UP, yaw)
	# Farther apart: lean toward the partner so the paddles still meet.
	var to_dir: Vector3 = to_p.normalized()
	var lean_deg: float = TAP_LEAN_DEG * clampf((to_p.length() - 0.9) / 0.8, 0.0, 1.0) * tw
	if lean_deg > 0.01:
		var axis: Vector3 = to_dir.cross(Vector3.UP).normalized()
		var sgn: float = signf(axis.cross(_plain(torso) - hip_p).dot(to_dir))
		if sgn != 0.0: turn = _turn_about(hip_p, axis, deg_to_rad(lean_deg) * sgn) * turn
	var add: = func(n: Node3D, d: Transform3D) -> void:
		if n == null: return
		_deltas[n] = d * _deltas.get(n, Transform3D.IDENTITY)
	add.call(torso, turn)
	if hips != null: add.call(hips, _turn_about(hip_p, Vector3.UP, yaw * TAP_HIP_SHARE))
	var head: Node3D = torso.get_node_or_null("HeadMesh")
	if head != null: add.call(head, turn)
	var aim: = Transform3D.IDENTITY
	var shoulder: Vector3 = turn * _plain(paddle_arm.upper_pivot)
	var hand: Vector3 = turn * _plain(paddle_arm.hand_pivot)
	# The hand stops a paddle short of the meeting point, so only the paddle tips meet there.
	var meet: Vector3 = Vector3(tap.target)
	var to_meet: Vector3 = meet - shoulder
	var hand_goal: Vector3 = meet - to_meet.normalized() * TAP_PADDLE_REACH if to_meet.length() > TAP_PADDLE_REACH + 0.05 else shoulder + to_meet * 0.5
	var from: Vector3 = hand - shoulder
	var to: Vector3 = hand_goal - shoulder
	if from.length_squared() > 1e-6 and to.length_squared() > 1e-6:
		var q: = Quaternion(from.normalized(), to.normalized())
		var b: = Basis(Quaternion.IDENTITY.slerp(q, w))
		aim = Transform3D(b, shoulder - b * shoulder)
		# The tap: a short push along the reach.
		aim = Transform3D(Basis.IDENTITY, to.normalized() * TAP_PUSH * float(tap.nudge)) * aim
	for arm_name in ["right_arm_node", "left_arm_node"]:
		var arm: Node3D = player.get(arm_name)
		if arm == null or arm.get("upper_pivot") == null: continue
		var d: Transform3D = (aim * turn) if arm == paddle_arm else turn
		for n in [arm.upper_pivot, arm.forearm_pivot, arm.hand_pivot]: add.call(n, d)
	# The paddle head, not just the hand, points at the meeting point.
	var paddle: Node3D = player.get("paddle_node")
	if paddle != null:
		var pxf: Transform3D = paddle.get_global_transform_interpolated()
		var hd: Transform3D = aim * turn
		var grip: Vector3 = hd * pxf.origin
		var shaft: Vector3 = hd.basis * pxf.basis.y
		var want: Vector3 = Vector3(tap.target) - grip
		if shaft.length_squared() > 1e-6 and want.length_squared() > 1e-6:
			var b: = Basis(Quaternion.IDENTITY.slerp(Quaternion(shaft.normalized(), want.normalized()), w))
			_paddle_aim = Transform3D(b, grip - b * grip)

# ------------------------------------------------------------------ stand straight between points

## True when this frame's legs are drawn straightened (0..1 weight above 0).
func standing() -> float:
	return _stand_w

func _drawn(n: Node3D) -> Vector3:
	var p: Vector3 = _plain(n)
	var d = _deltas.get(n)
	return p if d == null else d * p

func _stand_straight(delta: float, swinging: bool) -> void:
	stand_raise = 0.0
	var player = _rig._player
	var want: = 0.0
	if enabled() and not _rig._raw and not swinging and _expressions != null and _expressions._context() == "idle" \
			and not (_tap != null and _tap._hands_busy(player)):
		want = 1.0 - smoothstep(0.3, 1.0, _speed)
	_stand_w = move_toward(_stand_w, want, delta / STAND_EASE) if delta > 0.0 else want
	if _stand_w <= 1e-3: return
	var legs: Array = []
	for name in ["right_leg_node", "left_leg_node"]:
		var leg = player.get(name)
		if leg == null or leg.get("thigh_pivot") == null or leg.get("shin_pivot") == null or leg.get("foot_pivot") == null: return
		legs.append(leg)
	# Stand centred: the hips shift over the middle of the feet (weight shift), so both legs can
	# straighten; then they rise until the more stretched leg is straight (soft knee).
	var mid: Vector3 = (_drawn(legs[0].foot_pivot) + _drawn(legs[1].foot_pivot)) * 0.5
	var pelvis: Vector3 = (_drawn(legs[0].thigh_pivot) + _drawn(legs[1].thigh_pivot)) * 0.5
	var shift: Vector3 = mid - pelvis
	shift.y = 0.0
	shift = shift.limit_length(STAND_MAX_SHIFT) * _stand_w
	var rise: = INF
	var info: Array = []
	for leg in legs:
		var hip: Vector3 = _drawn(leg.thigh_pivot) + shift
		var knee: Vector3 = _drawn(leg.shin_pivot)
		var ankle: Vector3 = _drawn(leg.foot_pivot)
		var l1: float = _plain(leg.thigh_pivot).distance_to(_plain(leg.shin_pivot))
		var l2: float = _plain(leg.shin_pivot).distance_to(_plain(leg.foot_pivot))
		var reach: float = (l1 + l2) * STAND_BEND
		var off: Vector3 = hip - ankle
		var flat: float = Vector2(off.x, off.z).length()
		if flat >= reach: rise = 0.0
		else: rise = minf(rise, maxf(0.0, sqrt(reach * reach - flat * flat) - off.y))
		info.append([leg, hip, knee, ankle, l1, l2])
	if rise == INF or rise <= 1e-4: return
	rise = minf(rise, STAND_MAX_RAISE) * _stand_w
	stand_raise = rise
	var up: = Transform3D(Basis.IDENTITY, Vector3.UP * rise + shift)
	var add: = func(n: Node3D, d: Transform3D) -> void:
		if n == null: return
		_deltas[n] = d * _deltas.get(n, Transform3D.IDENTITY)
	var body: Node3D = player.body_pivot
	add.call(body, up)
	var hips: Node3D = body.get_node_or_null("HipsMesh")
	if hips != null: add.call(hips, up)
	var torso: Node3D = body.get_node_or_null("TorsoMesh")
	if torso != null:
		add.call(torso, up)
		var head: Node3D = torso.get_node_or_null("HeadMesh")
		if head != null: add.call(head, up)
	for name in ["right_arm_node", "left_arm_node"]:
		var arm = player.get(name)
		if arm == null or arm.get("upper_pivot") == null: continue
		for n in [arm.upper_pivot, arm.forearm_pivot, arm.hand_pivot]: add.call(n, up)
	# Knees: two-bone placement from the raised hip to the planted ankle, bending the way they did.
	for it in info:
		var leg = it[0]
		var hip: Vector3 = it[1] + Vector3.UP * rise
		var knee0: Vector3 = it[2]
		var ankle: Vector3 = it[3]
		var l1: float = it[4]
		var l2: float = it[5]
		add.call(leg.thigh_pivot, up)
		var axis: Vector3 = ankle - hip
		var d: float = clampf(axis.length(), 1e-4, l1 + l2 - 1e-4)
		var dir: Vector3 = axis.normalized()
		var pole: Vector3 = knee0 - (it[1] - shift)
		pole -= dir * pole.dot(dir)
		if pole.length_squared() < 1e-8: pole = Vector3.UP.cross(dir).cross(dir)
		pole = pole.normalized()
		var a: float = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
		var h: float = sqrt(maxf(l1 * l1 - a * a, 0.0))
		var knee: Vector3 = hip + dir * a + pole * h
		_deltas[leg.shin_pivot] = Transform3D(Basis.IDENTITY, knee - knee0) * _deltas.get(leg.shin_pivot, Transform3D.IDENTITY)

