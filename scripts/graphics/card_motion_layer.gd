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
## Standing leg stances (card_stance.gd): ten of them, each player in their own order; the drawn
## feet step to the stance when the player stops and the hips shift over the weight foot.
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
# First-person look (pixel_card_rig.gd look_dir): the head turns this far on its own; past it
# the chest, both arms and the paddle turn with the look, and the hips by a share, so the head
# is never twisted far round from the body you see.
const LOOK_FREE_DEG: = 35.0
const LOOK_TORSO_MAX_DEG: = 75.0
const LOOK_HIP_SHARE: = 0.5
const TAP_LEAN_DEG: = 5.0     # lean toward a partner who is farther away (up to 1.7 m)
const TAP_PUSH: = 0.008       # m: the tap's push along the reach (a visible knock)
const HOLD_EASE: = 0.1        # s to switch an arm between free and on the paddle
const HOLD_DIST: = 0.14       # m: a hand this close to the paddle shaft / throat holds it
const STAND_EASE: = 0.35      # s to rise / sink
const STAND_BEND: = 0.997     # hip-to-ankle as a share of leg length when standing (about 9 deg of knee)
const STAND_MAX_RAISE: = 0.20 # m
const STAND_MAX_SHIFT: = 0.15 # m the hips may shift to centre over the feet
const STAND_UPRIGHT_DEG: = 18.0      # the torso comes back this far over the hips (the rally stance leans about 22 deg)
const STAND_RISE_HALF_LIFE: = 0.05   # s: the lift follows the stride this smoothly while walking
const REACT_ARM_STILL: = 0.35 # m/s: up to here a reaction moves the arm fully
const REACT_ARM_WALK: = 0.9   # m/s: from here the arm stays down
# Footwork flow (docs/FOOTWORK_PLAN.md), drawn only: the gameplay split step is under one card pixel.
const FLOW_HOP: = 0.04        # m the feet leave the ground in the split step (gameplay: 0.025 at most)
const FLOW_WIDE: = 0.045      # m each foot lands farther out
const FLOW_STEP: = 0.11       # m the inside foot steps toward the ball on the read (the gravity step)
const FLOW_STEP_LIFT: = 0.035
const GRAVITY_TIME: = 0.30    # s the drop-and-lean into a move lasts
const GRAVITY_DROP: = 0.04    # m the body drops as the inside foot unweights
const GRAVITY_LEAN_DEG: = 7.0 # the body falls toward where it is going
const DIAG_TURN_DEG: = 30.0   # chest turn toward a forward-diagonal run (the V-cut); the hips take DIAG_HIP_SHARE
const DIAG_HIP_SHARE: = 0.6
const SHUFFLE_DROP: = 0.055   # m the body sits lower in a fast side shuffle (the feet are wide apart)
const SHUFFLE_EASE: = 0.18    # s to sink / come back up
const STANCE_LEAN: = 0.8      # share of the way to a foot the hips shift at full weight on it (card_stance.gd)
const SWING_OMEGA: = 28.0     # rad/s: critically damped spring on the swing (no frame pops)

const CardReactionsScript = preload("res://scripts/graphics/card_reactions.gd")
const CardExpressionsScript = preload("res://scripts/graphics/card_expressions.gd")
const CardPartnerTapScript = preload("res://scripts/graphics/card_partner_tap.gd")
const CardStanceScript = preload("res://scripts/graphics/card_stance.gd")
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")

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
var _tap_noted: = false
var _tap = null               # CardPartnerTap: partner paddle tap between points
var _tapping: = false
var _expressions = null       # CardExpressions: idle / ready moods while standing
var _expr_amount: = 0.0
var _react_arm: = 1.0          # 0..1 how much of a reaction's arm motion shows (0 while walking)
var _flow_wide: = 0.0          # 0..1 feet landed wide after the split
var _flow_t: = 99.0            # s since the read (the gravity step plays from 0 to GRAVITY_TIME)
var _flow_dir: = Vector3.ZERO  # where the move goes (unit, flat)
var _flow_was_push: = false
var _flow_was_still: = true
var _diag: = 0.0               # deg the chest is turned toward a diagonal run (eased, signed)
var flow: = Vector3.ZERO       # bench: (hop m, gravity drop m, diagonal turn deg)
var _low: = 0.0                # 0..1 how far the body is lowered for a side shuffle
var shuffle_drop: = 0.0        # m lowered this frame (bench)
var _stance = null            # CardStance: this player's standing leg stances between points
var _stand_w: = 0.0           # 0 athletic crouch .. 1 standing straight (between points), eased
var _stand_p: = 0.0           # linear progress behind _stand_w
var stand_raise: = 0.0        # m the body is lifted this frame (bench)
var _stand_rise_prev: = 0.0
var _tap_w: = 0.0             # 0..1 how far into a paddle tap this card is (turn or reach)
var _free: Dictionary = {}    # arm -> 1 free .. 0 on the paddle (eased)
var last_channels: Dictionary = {}   # reaction / expression channels applied this frame (bench)
var _paddle_aim: = Transform3D.IDENTITY   # tap: paddle turned about the shown hand toward the partner
var _hang_on: = false          # the paddle hangs from a relaxed hand this frame
var _hang_turn: = Basis.IDENTITY
var _hang_origin: = Vector3.ZERO   # the paddle's grip as gameplay has it
var _hang_hand: Node3D = null
var grip_slip: = 0.0           # m the hanging paddle would have sat off the hand without _reseat_paddle (bench)
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
	_paddle_aim = Transform3D.IDENTITY
	_hang_on = false
	_update_hold(delta, paddle_arm)
	_gait(delta, swinging, paddle_arm)
	_relax_arms(delta, swinging, paddle_arm)
	_react(delta, paddle_arm, swinging)
	_partner_tap(delta, paddle_arm)
	_look_turn()
	_stand_straight(delta, swinging)
	_shuffle_low(delta, swinging)
	_footwork_flow(delta, swinging, paddle_arm)
	_reseat_paddle()

## The hanging paddle turns about its grip. The grip was taken when the arm was relaxed, but the
## hand moves again after that (reactions, standing up straight, the hip shift of a stance), so
## the turn is put back on the grip where the hand is finally drawn. Without this the paddle sat
## beside the hand by up to the size of that later move.
func _reseat_paddle() -> void:
	grip_slip = 0.0
	if not _hang_on or _tapping or _hang_hand == null: return
	var hand_delta: Transform3D = _deltas.get(_hang_hand, Transform3D.IDENTITY)
	var grip: Vector3 = hand_delta * _hang_origin
	grip_slip = ((_paddle_aim * hand_delta) * _hang_origin).distance_to(grip)
	_paddle_aim = Transform3D(_hang_turn, grip - _hang_turn * grip)

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
	# A reaction's arm (fist pump, paddle up) is for a player standing: walking off with the hand
	# in the air and dropping it mid-stride reads wrong (user's call, 2026-11-24). Walking, the
	# arm stays down and only the head and body react.
	if not ch.is_empty():
		var still: float = 1.0 - smoothstep(REACT_ARM_STILL, REACT_ARM_WALK, _speed)
		_react_arm = move_toward(_react_arm, still, delta / 0.25) if delta > 0.0 else still
		for k in ["arm", "elbow", "spin"]:
			if ch.has(k): ch[k] = float(ch[k]) * _react_arm
	else:
		_react_arm = 1.0 - smoothstep(REACT_ARM_STILL, REACT_ARM_WALK, _speed)
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
	# Stance turn: the whole player (feet included) stands turned away from square to the net.
	if absf(float(ch.get("turn", 0.0))) > 1e-3: bob = bob * _turn_about(hip_p, Vector3.UP, deg_to_rad(float(ch.turn)))
	# Each turn's sign is found from the joints, so + always means the same thing on screen.
	var lean: = Transform3D.IDENTITY
	if absf(float(ch.torso)) > 1e-3:
		var sgn: float = signf(side.cross(_plain(torso) - hip_p).dot(fwd))
		if sgn != 0.0: lean = _turn_about(hip_p, side, deg_to_rad(float(ch.torso)) * sgn)
	# Sideways lean of the upper body over the hips (weight shifting from foot to foot).
	if absf(float(ch.get("sway", 0.0))) > 1e-3: lean = _turn_about(hip_p, fwd, deg_to_rad(float(ch.sway))) * lean
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

## A big first-person look turns the body: chest, head and arms about the hips, hips by a share.
func _look_turn() -> void:
	var look: Vector3 = _rig.look_dir
	# `look` is as long as the look is level (1 = level, 0 = straight down): a steep look
	# down turns the body less, and not at all near vertical.
	var level: float = smoothstep(0.35, 0.75, look.length())
	if not enabled() or _rig._raw or _tapping or level <= 0.0: return
	var player = _rig._player
	var body: Node3D = player.body_pivot
	var torso: Node3D = body.get_node_or_null("TorsoMesh")
	if torso == null: return
	var fwd: Vector3 = body.get_global_transform_interpolated().basis * player._get_forward_axis()
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6: return
	var need: float = fwd.normalized().signed_angle_to(look.normalized(), Vector3.UP)
	var over: float = absf(need) - deg_to_rad(LOOK_FREE_DEG)
	if over <= 0.0: return
	var yaw: float = signf(need) * minf(over, deg_to_rad(LOOK_TORSO_MAX_DEG)) * level
	var hips: Node3D = body.get_node_or_null("HipsMesh")
	var hip_p: Vector3 = _plain(hips if hips else body)
	var turn: = _turn_about(hip_p, Vector3.UP, yaw)
	var add: = func(n: Node3D, d: Transform3D) -> void:
		if n == null: return
		_deltas[n] = d * _deltas.get(n, Transform3D.IDENTITY)
	add.call(torso, turn)
	if hips != null: add.call(hips, _turn_about(hip_p, Vector3.UP, yaw * LOOK_HIP_SHARE))
	var head: Node3D = torso.get_node_or_null("HeadMesh")
	if head != null:
		# The head goes all the way to the look: the chest's turn, then the rest about the neck.
		var head_fwd: Vector3 = head.get_global_transform_interpolated().basis * player._get_forward_axis()
		head_fwd.y = 0.0
		var own: float = fwd.normalized().signed_angle_to(head_fwd.normalized(), Vector3.UP) if head_fwd.length_squared() > 1e-6 else 0.0
		add.call(head, _turn_about(turn * _plain(head), Vector3.UP, need - own - yaw) * turn)
	for arm_name in ["right_arm_node", "left_arm_node"]:
		var arm: Node3D = player.get(arm_name)
		if arm == null or arm.get("upper_pivot") == null: continue
		for n in [arm.upper_pivot, arm.forearm_pivot, arm.hand_pivot]: add.call(n, turn)

func _partner_tap(delta: float, paddle_arm) -> void:
	_tapping = false
	_tap_w = 0.0
	var player = _rig._player
	if not enabled() or _rig._raw or paddle_arm == null: return
	var tap: Dictionary = _tap.update(delta, _stop_reaction)
	if tap.is_empty():
		_tap_noted = false
		return
	_tapping = true
	var w: float = float(tap.w)
	var tw: float = float(tap.get("turn", w))
	_tap_w = clampf(maxf(w, tw), 0.0, 1.0)
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
	var need: float = fwd.normalized().signed_angle_to(to_p.normalized(), Vector3.UP)
	var limit: float = deg_to_rad(float(tap.turn_deg) if float(tap.get("turn_deg", -1.0)) > 0.0 else TAP_TURN_DEG)
	var yaw: float = clampf(need, -limit, limit) * tw
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
	var hip_share: float = float(tap.hip_share) if float(tap.get("hip_share", -1.0)) > 0.0 else TAP_HIP_SHARE
	if hips != null: add.call(hips, _turn_about(hip_p, Vector3.UP, yaw * hip_share))
	var head: Node3D = torso.get_node_or_null("HeadMesh")
	if head != null: add.call(head, turn)
	# Everything from here starts from the arm and paddle as they are drawn now (hanging at the
	# side between points), so the reach grows out of that and comes back to it.
	var paddle: Node3D = player.get("paddle_node")
	if paddle == null: return
	var pxf: Transform3D = paddle.get_global_transform_interpolated()
	var base: Transform3D = _deltas.get(paddle_arm.hand_pivot, Transform3D.IDENTITY)
	var hang: Transform3D = _paddle_aim
	var meet: Vector3 = Vector3(tap.target)
	var shoulder: Vector3 = turn * _plain(paddle_arm.upper_pivot)
	var grip0: Vector3 = turn * base * pxf.origin
	var from: Vector3 = grip0 - shoulder
	var to_meet: Vector3 = meet - shoulder
	var span: float = to_meet.length()
	var arm_len: float = from.length()
	var reach: float = PaddleSize.LENGTH   # grip to tip
	if arm_len < 1e-3 or span < 1e-3: return
	# A casual reach: the arm keeps its length and stays below the line to the meeting point, far
	# enough that the paddle, angled up from the grip, ends exactly there: shoulder, grip and tip
	# make a triangle, so the two tips really touch. Too close or too far for the triangle: the
	# grip goes on the line and the tips come as near as they can.
	var along: Vector3 = to_meet / span
	var grip_goal: Vector3 = shoulder + along * arm_len
	var down: Vector3 = along.cross(along.cross(Vector3.UP))
	if span > absf(arm_len - reach) + 0.01 and span < arm_len + reach - 0.01 and down.length_squared() > 1e-6:
		down = down.normalized() * (1.0 if down.y < 0.0 else -1.0)
		var cos_drop: float = clampf((arm_len * arm_len + span * span - reach * reach) / (2.0 * arm_len * span), -1.0, 1.0)
		grip_goal = shoulder + (along * cos_drop + down * sqrt(1.0 - cos_drop * cos_drop)) * arm_len
	var to: Vector3 = grip_goal - shoulder
	var qa: = Basis(Quaternion.IDENTITY.slerp(Quaternion(from.normalized(), to.normalized()), w))
	var aim: = Transform3D(qa, shoulder - qa * shoulder)
	for arm_name in ["right_arm_node", "left_arm_node"]:
		var arm: Node3D = player.get(arm_name)
		if arm == null or arm.get("upper_pivot") == null: continue
		var d: Transform3D = (aim * turn) if arm == paddle_arm else turn
		for n in [arm.upper_pivot, arm.forearm_pivot, arm.hand_pivot]: add.call(n, d)
	# The paddle turns about the grip until its tip is on the meeting point; at the touch it
	# pushes a few millimetres on, into the partner's paddle.
	var carry: Transform3D = aim * turn
	var grip: Vector3 = aim * grip0
	var shaft: Vector3 = (carry * hang * base).basis * pxf.basis.y
	var want: Vector3 = meet - grip
	if shaft.length_squared() < 1e-8 or want.length_squared() < 1e-8: return
	var qp: = Basis(Quaternion.IDENTITY.slerp(Quaternion(shaft.normalized(), want.normalized()), w))
	var push: = Transform3D(Basis.IDENTITY, want.normalized() * TAP_PUSH * float(tap.nudge))
	_paddle_aim = push * Transform3D(qp, grip - qp * grip) * carry * hang * carry.affine_inverse()
	# Once per tap, at the touch: where the drawn paddle tip is (the partner's note gives the other).
	if _tap._t >= CardPartnerTap.TAP_AT and not _tap_noted:
		_tap_noted = true
		var tip: Vector3 = paddle_delta(paddle_arm) * (pxf * Vector3(0, reach, 0))
		PerfMonitor.note("partner_tap", {"step": "reach", "tip": tip, "tip_gap": tip.distance_to(meet), "tip_height": tip.y - PickleballConstants.FLOOR_Y,
			"hand_height": (carry * base * _plain(paddle_arm.hand_pivot)).y - PickleballConstants.FLOOR_Y, "need_deg": rad_to_deg(need), "turn_deg": rad_to_deg(yaw), "busy": bool(tap.get("busy", false))})

# ------------------------------------------------------------------ arms down between points

const RELAX_EASE: = 0.3        # s for an arm to drop / come back up
const RELAX_SWING_DEG: = 16.0  # walking: the hanging arms swing against the legs
const RELAX_SWAY_DEG: = 2.5    # standing: a slow idle sway
var _relax: Dictionary = {}    # arm -> 0 as posed .. 1 hanging at the side (eased)
var _relax_t: = 0.0

## Bench: (paddle arm hang 0..1, free arm hang 0..1, code). Code: 0 hanging allowed, 1 no
## between-point, 2 IDLE / SET_SERVE, 3 ball action, 4 swinging / off.
func arm_state(paddle_arm) -> Vector3:
	var player = _rig._player
	var pr: = 0.0
	var fr: = 0.0
	for name in ["right_arm_node", "left_arm_node"]:
		var arm = player.get(name)
		if arm == null: continue
		if arm == paddle_arm: pr = float(_relax.get(arm, 0.0))
		else: fr = float(_relax.get(arm, 0.0))
	var code: = 0.0
	var bpc = player._between_point_owner() if player.has_method("_between_point_owner") else null
	if bpc == null: code = 1.0
	elif str(bpc.get("phase")) in ["IDLE", "SET_SERVE"]: code = 2.0
	elif _ball_action_playing(bpc): code = 3.0
	return Vector3(pr, fr, code)

## 1 when this arm has nothing to do: the point is over and it is not handling the ball,
## celebrating or getting set for the serve.
func _relax_goal(arm, paddle_arm, swinging: bool) -> float:
	var player = _rig._player
	if not enabled() or _rig._raw or swinging or not player.has_method("_between_point_owner"): return 0.0
	var bpc = player._between_point_owner()
	if bpc == null: return 0.0
	var ph: String = str(bpc.get("phase"))
	if ph in ["IDLE", "SET_SERVE"]: return 0.0
	# A ball action (pickup / throw / catch / carry) is an authored Pose Studio pose for both
	# arms: it plays as authored, never hung at the sides.
	if _ball_action_playing(bpc):
		# A helper walking to their spot before the ball comes has nothing in their hands yet:
		# arms down while they walk, the authored pose once they stand (user's call, 2026-11-24:
		# hands up while walking reads as robot arms). The carrier keeps the carry pose.
		# The same for the carrier's paddle arm: the other hand has the ball, the paddle swings low.
		var carrier: bool = bpc.index_for_actor(player) == int(bpc.get("_carry_team"))
		if ph in ["HELPER_WAIT", "CARRY"] and (not carrier or arm == paddle_arm):
			return smoothstep(REACT_ARM_STILL, REACT_ARM_WALK, _speed)
		# Stepping under a pass or into a throw: the free hand does the work, the paddle stays low.
		if arm == paddle_arm: return smoothstep(REACT_ARM_STILL, REACT_ARM_WALK, _speed)
		return 0.0
	# A reaction owns the paddle arm only while it shows on it (standing). Walking, the reaction's
	# arm is off (_react_arm), so the arm hangs and swings like the other one instead of staying
	# frozen in the ready guard with a bent elbow.
	if arm == paddle_arm: return (1.0 - _react_arm) if _reactions != null and _reactions.current() != "" else 1.0
	return 1.0

## True while this player plays a ball action between points (handles the ball, or holds it).
func _ball_action_playing(bpc = null) -> bool:
	var player = _rig._player
	if bpc == null:
		if not player.has_method("_between_point_owner"): return false
		bpc = player._between_point_owner()
	if bpc == null: return false
	var ph: String = str(bpc.get("phase"))
	if ph in ["IDLE", "SET_SERVE"]: return false
	var idx: int = bpc.index_for_actor(player)
	if idx < 0: return false
	if idx == int(bpc.get("_carry_team")): return true
	var handlers: Array = [int(bpc.get("retriever")), int(bpc.get("server")), int(bpc.get("catcher"))]
	return idx in handlers and (ph in CardPartnerTap.BUSY_PHASES or ph == "HELPER_WAIT")

## Between points the gameplay pose keeps the ready guard (paddle up, free hand out in front).
## The cards let both arms hang at the sides instead: the upper arm drops from the shoulder,
## the forearm follows with a slight bend, the paddle points down along the leg. Walking, the
## arms swing against the legs; standing, they sway a little.
func _relax_arms(delta: float, swinging: bool, paddle_arm) -> void:
	var player = _rig._player
	_relax_t += delta
	var body: Node3D = player.body_pivot
	var fwd: Vector3 = body.get_global_transform_interpolated().basis * player._get_forward_axis()
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6: return
	fwd = fwd.normalized()
	var side: = fwd.cross(Vector3.UP).normalized()
	var hips: Node3D = body.get_node_or_null("HipsMesh")
	var centre: Vector3 = _plain(hips if hips else body)
	var seed_phase: float = float(player.get_instance_id() % 97)
	for pair in [[player.get("right_arm_node"), 1.0], [player.get("left_arm_node"), -1.0]]:
		var arm: Node3D = pair[0]
		if arm == null or arm.get("upper_pivot") == null: continue
		var cur: float = float(_relax.get(arm, 0.0))
		cur = move_toward(cur, _relax_goal(arm, paddle_arm, swinging), delta / RELAX_EASE) if delta > 0.0 else cur
		_relax[arm] = cur
		if cur <= 0.001: continue
		var r: float = smoothstep(0.0, 1.0, cur)
		var shoulder: Vector3 = _plain(arm.upper_pivot)
		var elbow: Vector3 = _plain(arm.forearm_pivot)
		var hand: Vector3 = _plain(arm.hand_pivot)
		var out: Vector3 = side * signf((shoulder - centre).dot(side))
		# Swing with the stride (the gait's own measure), plus the idle sway.
		var swing: float = deg_to_rad(RELAX_SWING_DEG * clampf(_amt, -1.0, 1.0) * float(pair[1])
			+ RELAX_SWAY_DEG * sin(_relax_t * 1.5 + seed_phase + float(pair[1])))
		var rock: = Basis(side, swing)
		var upper_to: Vector3 = rock * (Vector3.DOWN + out * 0.10 + fwd * 0.04).normalized()
		var fore_to: Vector3 = rock * (Vector3.DOWN + out * 0.04 + fwd * 0.22).normalized()
		var t1: = Transform3D.IDENTITY
		if (elbow - shoulder).length_squared() > 1e-6:
			var b1: = Basis(Quaternion.IDENTITY.slerp(Quaternion((elbow - shoulder).normalized(), upper_to), r))
			t1 = Transform3D(b1, shoulder - b1 * shoulder)
		var elbow1: Vector3 = t1 * elbow
		var hand1: Vector3 = t1 * hand
		var t2: = t1
		if (hand1 - elbow1).length_squared() > 1e-6:
			var b2: = Basis(Quaternion.IDENTITY.slerp(Quaternion((hand1 - elbow1).normalized(), fore_to), r))
			t2 = Transform3D(b2, elbow1 - b2 * elbow1) * t1
		# Under whatever the gait already put on the arm (the shoulders' counter-turn).
		_deltas[arm.upper_pivot] = _deltas.get(arm.upper_pivot, Transform3D.IDENTITY) * t1
		_deltas[arm.forearm_pivot] = _deltas.get(arm.forearm_pivot, Transform3D.IDENTITY) * t2
		_deltas[arm.hand_pivot] = _deltas.get(arm.hand_pivot, Transform3D.IDENTITY) * t2
		if arm == paddle_arm:   # the paddle hangs from the hand, tip down and a little forward
			var paddle: Node3D = player.get("paddle_node")
			if paddle != null:
				var pxf: Transform3D = paddle.get_global_transform_interpolated()
				var hd: Transform3D = _deltas[arm.hand_pivot]
				var grip: Vector3 = hd * pxf.origin
				var shaft: Vector3 = hd.basis * pxf.basis.y
				if shaft.length_squared() > 1e-8:
					var bp: = Basis(Quaternion.IDENTITY.slerp(Quaternion(shaft.normalized(), rock * (Vector3.DOWN + fwd * 0.30 + out * 0.05).normalized()), r))
					_paddle_aim = Transform3D(bp, grip - bp * grip)
					_hang_on = true
					_hang_turn = bp
					_hang_origin = pxf.origin
					_hang_hand = arm.hand_pivot

# ------------------------------------------------------------------ stand straight between points

## True when this frame's legs are drawn straightened (0..1 weight above 0).
func standing() -> float:
	return _stand_w

func _drawn(n: Node3D) -> Vector3:
	var p: Vector3 = _plain(n)
	var d = _deltas.get(n)
	return p if d == null else d * p

## The torso and head come back over the hips (the rally stance leans forward, which reads as a
## slouch on a player standing or walking about). The arms ride the shoulders and keep hanging
## as they were. Not during a paddle tap: the reach is measured from the leaning shoulder.
func _stand_upright(weight: float) -> void:
	if weight <= 1e-3: return
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
	var hip_p: Vector3 = _drawn(hips if hips else body)
	var sgn: float = signf(side.cross(_drawn(torso) - hip_p).dot(fwd))
	if sgn == 0.0: return
	var back: = _turn_about(hip_p, side, -deg_to_rad(STAND_UPRIGHT_DEG) * weight * sgn)
	var arm_moves: Array = []
	for name in ["right_arm_node", "left_arm_node"]:
		var arm = player.get(name)
		if arm == null or arm.get("upper_pivot") == null: continue
		var shoulder: Vector3 = _drawn(arm.upper_pivot)
		arm_moves.append([arm, Transform3D(Basis.IDENTITY, back * shoulder - shoulder)])
	_deltas[torso] = back * _deltas.get(torso, Transform3D.IDENTITY)
	var head: Node3D = torso.get_node_or_null("HeadMesh")
	if head != null: _deltas[head] = back * _deltas.get(head, Transform3D.IDENTITY)
	for it in arm_moves:
		for n in [it[0].upper_pivot, it[0].forearm_pivot, it[0].hand_pivot]:
			if n != null: _deltas[n] = it[1] * _deltas.get(n, Transform3D.IDENTITY)

## Footwork flow while the ball is in play (docs/FOOTWORK_PLAN.md). Drawn only.
##   split step    the hop shows (feet and body up), and the feet land a little wider
##   gravity step  when the direction is read (split push_off), or on any start from standing,
##                 the inside foot lifts and lands toward the ball while the body drops and
##                 leans that way: falling into the move instead of pushing straight sideways
##   diagonal run  hips and chest turn toward a forward-diagonal run (the V-cut at the net)
## The hands and the paddle stay where gameplay has them.
func _footwork_flow(delta: float, swinging: bool, paddle_arm) -> void:
	flow = Vector3.ZERO
	var player = _rig._player
	var on: bool = enabled() and not _rig._raw and _stand_w <= 0.01 and not _tapping \
		and not (player.has_method("_between_point_owner") and player._between_point_owner() != null)
	var split: Dictionary = {}
	var pc = player.get("pose_controller")
	if on and pc != null and pc.get("split_step") != null: split = pc.split_step.sample()
	var phase: String = str(split.get("phase", "ready"))
	var body: Node3D = player.body_pivot
	var fwd: Vector3 = body.get_global_transform_interpolated().basis * player._get_forward_axis()
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6: return
	fwd = fwd.normalized()
	# --- triggers
	var push: bool = phase == "push_off"
	var read_dir: Vector3 = split.get("direction", Vector3.ZERO)
	if on and push and not _flow_was_push and read_dir.length_squared() > 1e-4:
		_flow_t = 0.0
		_flow_dir = Vector3(read_dir.x, 0.0, read_dir.z).normalized()
	elif on and not swinging and _flow_was_still and _speed > 0.5 and _dir.length_squared() > 0.5 and _flow_t > GRAVITY_TIME:
		_flow_t = 0.0   # a start from standing, without a split
		_flow_dir = _dir.normalized()
	_flow_was_push = push
	if _speed < 0.15: _flow_was_still = true
	elif _speed > 0.5: _flow_was_still = false
	if delta > 0.0: _flow_t += delta
	_flow_wide = move_toward(_flow_wide, 1.0 if on and phase in ["split_land", "push_off"] else 0.0, delta / 0.07) if delta > 0.0 else 0.0
	var hop: float = FLOW_HOP * clampf(float(split.get("foot_lift", 0.0)) / 0.025, 0.0, 1.0) if on else 0.0
	var g: float = sin(PI * clampf(_flow_t / GRAVITY_TIME, 0.0, 1.0)) if on and not swinging and _flow_t < GRAVITY_TIME else 0.0
	# --- diagonal turn
	var want_turn: = 0.0
	if on and not swinging and _dir.length_squared() > 0.5:
		var ang: float = fwd.signed_angle_to(_dir.normalized(), Vector3.UP)
		if cos(ang) > 0.2:   # forward diagonals only: retreats keep facing the play
			want_turn = clampf(rad_to_deg(ang), -DIAG_TURN_DEG, DIAG_TURN_DEG) * absf(sin(2.0 * ang)) * smoothstep(1.2, 2.6, _speed)
	_diag = lerpf(want_turn, _diag, pow(0.5, delta / 0.09)) if delta > 0.0 else want_turn
	flow = Vector3(hop, GRAVITY_DROP * g, _diag)
	if hop <= 1e-4 and g <= 1e-3 and _flow_wide <= 1e-3 and absf(_diag) < 0.3: return
	var legs: Array = []
	for name in ["right_leg_node", "left_leg_node"]:
		var leg = player.get(name)
		if leg == null or leg.get("thigh_pivot") == null or leg.get("shin_pivot") == null or leg.get("foot_pivot") == null: return
		legs.append([leg, _drawn(leg.thigh_pivot), _drawn(leg.shin_pivot), _drawn(leg.foot_pivot)])
	var add: = func(n: Node3D, d: Transform3D) -> void:
		if n == null: return
		_deltas[n] = d * _deltas.get(n, Transform3D.IDENTITY)
	var hips: Node3D = body.get_node_or_null("HipsMesh")
	var torso: Node3D = body.get_node_or_null("TorsoMesh")
	var hip_p: Vector3 = _drawn(hips if hips else body)
	# --- body: up with the hop, down and leaning with the gravity step, turned for a diagonal
	var lift: = Transform3D(Basis.IDENTITY, Vector3.UP * (hop * 0.6 - GRAVITY_DROP * g))
	var lean: = Transform3D.IDENTITY
	if g > 1e-3 and _flow_dir.length_squared() > 0.5:
		lean = _turn_about(hip_p, Vector3.UP.cross(_flow_dir).normalized(), deg_to_rad(GRAVITY_LEAN_DEG) * g)
	var turn: = _turn_about(hip_p, Vector3.UP, deg_to_rad(_diag))
	var hip_turn: = _turn_about(hip_p, Vector3.UP, deg_to_rad(_diag * DIAG_HIP_SHARE))
	var upper: = lift * lean * turn
	add.call(body, lift)
	add.call(hips, lift * hip_turn)
	if torso != null:
		var head: Node3D = torso.get_node_or_null("HeadMesh")
		# The head stays on the ball: it rides the shoulders' position, not their turn.
		if head != null:
			var hp: Vector3 = _drawn(head)
			add.call(head, Transform3D(Basis.IDENTITY, upper * hp - hp))
		add.call(torso, upper)
	for name in ["right_arm_node", "left_arm_node"]:
		var arm = player.get(name)
		if arm == null or arm.get("upper_pivot") == null: continue
		var free: float = _free_w(arm) if arm != paddle_arm else 0.0
		add.call(arm.upper_pivot, upper)                                              # the shoulder goes with the chest
		add.call(arm.forearm_pivot, Transform3D.IDENTITY.interpolate_with(upper, lerpf(0.5, 1.0, free)))
		if free > 0.0: add.call(arm.hand_pivot, Transform3D.IDENTITY.interpolate_with(upper, free))
	# --- feet: up with the hop, landed wider, the inside foot stepping toward the ball
	var mid: Vector3 = (legs[0][3] + legs[1][3]) * 0.5
	var side_axis: Vector3 = legs[0][1] - legs[1][1]
	side_axis.y = 0.0
	side_axis = side_axis.normalized() if side_axis.length_squared() > 1e-6 else fwd.cross(Vector3.UP)
	var inside: int = -1
	if g > 1e-3: inside = 0 if (legs[0][3] - mid).dot(_flow_dir) >= (legs[1][3] - mid).dot(_flow_dir) else 1
	var u: float = clampf(_flow_t / (GRAVITY_TIME * 0.5), 0.0, 1.0)
	var back: float = 1.0 - smoothstep(0.55, 1.0, _flow_t / GRAVITY_TIME)   # the gameplay feet take over
	for i in 2:
		var move: Vector3 = Vector3.UP * hop + side_axis * (FLOW_WIDE * _flow_wide * (1.0 if i == 0 else -1.0))
		if i == inside: move += (_flow_dir * FLOW_STEP * smoothstep(0.0, 1.0, u) + Vector3.UP * FLOW_STEP_LIFT * sin(PI * u)) * back
		var leg = legs[i][0]
		if move.length_squared() > 1e-10: add.call(leg.foot_pivot, Transform3D(Basis.IDENTITY, move))
		# Knee: two-bone placement from the moved hip to the moved ankle, bending the way it did.
		var hip_d: Transform3D = lift * hip_turn
		add.call(leg.thigh_pivot, hip_d)
		var hip: Vector3 = hip_d * legs[i][1]
		var ankle: Vector3 = legs[i][3] + move
		var l1: float = _plain(leg.thigh_pivot).distance_to(_plain(leg.shin_pivot))
		var l2: float = _plain(leg.shin_pivot).distance_to(_plain(leg.foot_pivot))
		var axis: Vector3 = ankle - hip
		var d: float = clampf(axis.length(), 1e-4, l1 + l2 - 1e-4)
		var dir: Vector3 = axis.normalized()
		var pole: Vector3 = legs[i][2] - legs[i][1]
		pole -= dir * pole.dot(dir)
		if pole.length_squared() < 1e-8: continue
		pole = pole.normalized()
		var a: float = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
		var knee: Vector3 = hip + dir * a + pole * sqrt(maxf(l1 * l1 - a * a, 0.0))
		_deltas[leg.shin_pivot] = Transform3D(Basis.IDENTITY, knee - legs[i][2]) * _deltas.get(leg.shin_pivot, Transform3D.IDENTITY)

## Side shuffle: the gameplay feet are wide apart, so the drawn body sits a little lower over
## them (hips, torso, head and shoulders down; knees re-bent to the planted feet). The hands
## and the paddle stay exactly where gameplay has them: the ball is in play.
func _shuffle_low(delta: float, swinging: bool) -> void:
	shuffle_drop = 0.0
	var player = _rig._player
	var feet = player.get("leg_ik")
	var want: = 0.0
	if enabled() and not _rig._raw and not swinging and feet != null and str(feet.get("locomotion_state")) == "lateral_shuffle" and _stand_w <= 0.01:
		want = smoothstep(1.0, 1.8, _speed)
	_low = move_toward(_low, want, delta / SHUFFLE_EASE) if delta > 0.0 else want
	if _low <= 0.001: return
	var drop: float = SHUFFLE_DROP * smoothstep(0.0, 1.0, _low)
	shuffle_drop = drop
	var down: = Transform3D(Basis.IDENTITY, Vector3.DOWN * drop)
	var add: = func(n: Node3D, d: Transform3D) -> void:
		if n == null: return
		_deltas[n] = d * _deltas.get(n, Transform3D.IDENTITY)
	var legs: Array = []
	for name in ["right_leg_node", "left_leg_node"]:
		var leg = player.get(name)
		if leg == null or leg.get("thigh_pivot") == null or leg.get("shin_pivot") == null or leg.get("foot_pivot") == null: return
		legs.append([leg, _drawn(leg.thigh_pivot), _drawn(leg.shin_pivot), _drawn(leg.foot_pivot)])
	var body: Node3D = player.body_pivot
	add.call(body, down)
	add.call(body.get_node_or_null("HipsMesh"), down)
	var torso: Node3D = body.get_node_or_null("TorsoMesh")
	if torso != null:
		add.call(torso, down)
		add.call(torso.get_node_or_null("HeadMesh"), down)
	for name in ["right_arm_node", "left_arm_node"]:
		var arm = player.get(name)
		if arm == null or arm.get("upper_pivot") == null: continue
		add.call(arm.upper_pivot, down)                                                    # shoulder: all the way
		add.call(arm.forearm_pivot, Transform3D(Basis.IDENTITY, Vector3.DOWN * drop * 0.5))   # elbow: half; the hand stays
	for it in legs:
		var leg = it[0]
		add.call(leg.thigh_pivot, down)
		var hip: Vector3 = it[1] + Vector3.DOWN * drop
		var ankle: Vector3 = it[3]
		var l1: float = _plain(leg.thigh_pivot).distance_to(_plain(leg.shin_pivot))
		var l2: float = _plain(leg.shin_pivot).distance_to(_plain(leg.foot_pivot))
		var axis: Vector3 = ankle - hip
		var d: float = clampf(axis.length(), 1e-4, l1 + l2 - 1e-4)
		var dir: Vector3 = axis.normalized()
		var pole: Vector3 = it[2] - it[1]
		pole -= dir * pole.dot(dir)
		if pole.length_squared() < 1e-8: continue
		pole = pole.normalized()
		var a: float = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
		var knee: Vector3 = hip + dir * a + pole * sqrt(maxf(l1 * l1 - a * a, 0.0))
		_deltas[leg.shin_pivot] = Transform3D(Basis.IDENTITY, knee - it[2]) * _deltas.get(leg.shin_pivot, Transform3D.IDENTITY)

## The standing stance showing now ("" when none).
func stance() -> String:
	return _stance.current() if _stance != null else ""

## Moves the drawn feet to this player's standing stance (stood still between points; walking,
## the feet are the gameplay feet). Returns how far the hips shift toward the weight foot.
func _apply_stance(delta: float, legs: Array) -> Vector3:
	var player = _rig._player
	if _stance == null: _stance = CardStanceScript.new(int(player.get_actor_id()) if player.has_method("get_actor_id") else 0)
	var fwd: Vector3 = player.body_pivot.get_global_transform_interpolated().basis * player._get_forward_axis()
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6: return Vector3.ZERO
	# The frame is the hip line as drawn (left hip to right hip), so the right foot always goes
	# under the right hip: the legs can never be placed crossed, whichever way the body or the
	# feet are turned (the body's forward axis and the hips disagree after a walk).
	var side: Vector3 = _drawn(legs[0].thigh_pivot) - _drawn(legs[1].thigh_pivot)
	side.y = 0.0
	if side.length_squared() < 1e-6: return Vector3.ZERO
	side = side.normalized()
	fwd = side.cross(Vector3.UP) * (1.0 if side.cross(Vector3.UP).dot(fwd) >= 0.0 else -1.0)
	var feet: Array = [_drawn(legs[0].foot_pivot), _drawn(legs[1].foot_pivot)]
	var centre: Vector3 = (feet[0] + feet[1]) * 0.5
	var base: Array = []
	for f in feet: base.append(Vector2((f - centre).dot(side), (f - centre).dot(fwd)))
	var active: bool = _stand_p > 0.6 and _speed < 0.25 and not _tapping and (_reactions == null or _reactions.current() == "")
	var st: Dictionary = _stance.update(delta, active, base)
	for i in 2:
		var d: Vector3 = st.d[i]
		if d.length_squared() < 1e-10: continue
		var foot: Node3D = legs[i].foot_pivot
		_deltas[foot] = Transform3D(Basis.IDENTITY, side * d.x + Vector3.UP * d.y + fwd * d.z) * _deltas.get(foot, Transform3D.IDENTITY)
	var lean: Vector3 = (_drawn(legs[0].foot_pivot) - _drawn(legs[1].foot_pivot)) * 0.5 * float(st.weight) * STANCE_LEAN
	lean.y = 0.0
	return lean

func _stand_straight(delta: float, swinging: bool) -> void:
	stand_raise = 0.0
	var player = _rig._player
	var want: = 0.0
	if enabled() and not _rig._raw and not swinging and _expressions != null and _expressions.shown_context() == "idle" \
			and not (_tap != null and _tap._hands_busy(player)) and not _ball_action_playing():
		# Between points the walk stays upright too (the athletic crouch is for the rally); any
		# other time the stance comes back as soon as the player moves.
		var strolling: bool = player.has_method("_between_point_owner") and player._between_point_owner() != null
		want = 1.0 if strolling else 1.0 - smoothstep(0.3, 1.0, _speed)
	# This player's own speed (CardProfile), eased in and out rather than linear.
	var ease: float = STAND_EASE
	if _expressions != null:
		ease = _expressions.profile.rise_ease if want > _stand_p else _expressions.profile.sink_ease
		if _expressions._context() == "live": ease = minf(ease, 0.15)   # the rally started: no lag
	_stand_p = move_toward(_stand_p, want, delta / ease) if delta > 0.0 else want
	_stand_w = smoothstep(0.0, 1.0, _stand_p)
	# Idle body actions bend the knees by lowering the stand (card_expressions.gd "squat").
	_stand_w *= 1.0 - clampf(float(last_channels.get("squat", 0.0)), 0.0, 1.0)
	if _stand_w <= 1e-3:
		_stand_rise_prev = 0.0
		if _stance != null: _stance.update(1.0, false, [Vector2.ZERO, Vector2.ZERO])   # back on the gameplay feet
		return
	_stand_upright(_stand_w * (1.0 - _tap_w))
	var legs: Array = []
	for name in ["right_leg_node", "left_leg_node"]:
		var leg = player.get(name)
		if leg == null or leg.get("thigh_pivot") == null or leg.get("shin_pivot") == null or leg.get("foot_pivot") == null: return
		legs.append(leg)
	# Stand centred: the hips shift over the middle of the feet (weight shift), so both legs can
	# straighten; then they rise until the more stretched leg is straight (soft knee).
	# This player's own stance (card_stance.gd) moves the drawn feet and puts the weight on one.
	var lean: Vector3 = _apply_stance(delta, legs)
	var mid: Vector3 = (_drawn(legs[0].foot_pivot) + _drawn(legs[1].foot_pivot)) * 0.5 + lean
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
	if rise == INF: return
	rise = minf(rise, STAND_MAX_RAISE) * _stand_w
	# Walking, the room to rise changes with every stride: follow it smoothly (no step pops).
	if delta > 0.0 and _speed > 0.3: rise = lerpf(rise, _stand_rise_prev, pow(0.5, delta / STAND_RISE_HALF_LIFE))
	_stand_rise_prev = rise
	if rise <= 1e-4: return
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

