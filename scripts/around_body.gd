extends RefCounted
## Keeps a blended paddle outside the body. Pose blends move the paddle in a straight line
## (stroke_swing_path.blend_pose, the follow-through sweep) or swing the arm in joint space
## (serve_joint_motion.blend); between keys on opposite sides of the body (Ready in front, a
## backswing behind) that path can cut through the torso. `shift` sends the paddle around it:
##  1. Around: the paddle's shaft middle, in angle and distance around the torso axis, sweeps from
##     the blend's start to its end along the side the straight path passes nearest (chosen once
##     per blend, so the path is continuous; at the keys it is the keys exactly), never inside.
##  2. Clear: any shaft point (wrist to head) still inside is pushed out along that same side.
##
## Frame: the canonical pose frame those blends use (x forehand side, y up from the player root,
## +z away from the net). The torso is an elliptic cylinder from the pelvis to under the shoulders
## (player_body_dimensions.gd, body_surface_profile.gd: half-width ~0.17 m, half-depth ~0.10 m),
## plus a margin for the hand, placed like stroke_body_pose.gd places the body (crouch, weight
## shift, body pitch / yaw / roll, hip yaw, torso yaw and pitch). In ellipse units (rho = 1 on the shell):
## a blend whose straight path stays at rho >= 1 + SOFT + AROUND_FADE plays exactly as before.

const D = preload("res://scripts/player_body_dimensions.gd")
const Profile = preload("res://scripts/body_surface_profile.gd")
const MARGIN := 0.05                                       # hand / paddle thickness
const LIFT := 0.3                                          # stroke_body_pose.STANDING_BODY_LIFT
const WAIST_Y := D.PELVIS_CENTER_Y + D.PELVIS_HALF_HEIGHT # chest bends forward from here
const SOFT := 0.2                                          # easing band, in shell radii
const WRIST_BEYOND_GRIP := 0.10                            # the wrist sits about this far past the grip
const SHAFT_SAMPLES := 8                                    # points from the wrist to the paddle head
const ENDS := 0.15                                         # blend fraction over which step 2 fades in at each end
const FAR_M := 0.75                                        # paths further than this from the torso axis skip all checks
const AROUND_FADE := 0.3                                   # step 1 fades in as the straight path comes this close

static var enabled: bool = OS.get_environment("PICKLEBALL_AROUND_BODY") != "0"
static var _rings: Array = []   # body_surface_profile rings: [half-width, y, half-depth], pelvis -> neck

## Torso half-width and half-depth at body-pivot height y (the game's surface profile, pelvis to
## neck); ZERO outside it.
static func section(y: float) -> Vector2:
	if _rings.is_empty(): _rings = Profile.rings()
	if y <= _rings[0].y or y >= _rings[-1].y: return Vector2.ZERO
	for i in range(1, _rings.size()):
		if y <= _rings[i].y:
			var a: Vector3 = _rings[i - 1]; var b: Vector3 = _rings[i]
			var f: float = (y - a.y) / maxf(b.y - a.y, 1e-6)
			return Vector2(lerpf(a.x, b.x, f), lerpf(a.z, b.z, f))
	return Vector2.ZERO

## Translation for the paddle of a blend at fraction `t` (0..1): `hand` / `head` now, and at the
## blend's start (`*_a`) and end (`*_b`). Canonical pose frame; ZERO when the path is clear.
static func shift(pose, hand: Vector3, head: Vector3, hand_a: Vector3, head_a: Vector3, hand_b: Vector3, head_b: Vector3, t: float) -> Vector3:
	if not enabled or pose == null: return Vector3.ZERO
	# Cheap exit (most blends): the straight path and the paddle stay far from the torso axis.
	if _far(hand_a.lerp(head_a, 0.5), hand_b.lerp(head_b, 0.5)) and _far(hand, head): return Vector3.ZERO
	var _pt := Time.get_ticks_usec()
	var d := _shift(pose, hand, head, hand_a, head_a, hand_b, head_b, t)
	PerfMonitor.record("arm.around_body", Time.get_ticks_usec() - _pt)
	return d

## The segment a-b stays further than FAR_M from the vertical axis through the root (horizontal).
static func _far(a: Vector3, b: Vector3) -> bool:
	var p := Vector2(a.x, a.z); var q := Vector2(b.x, b.z)
	var d := q - p
	var f: float = clampf(-p.dot(d) / d.length_squared(), 0.0, 1.0) if d.length_squared() > 1e-8 else 0.0
	return (p + d * f).length() > FAR_M

static func _shift(pose, hand: Vector3, head: Vector3, hand_a: Vector3, head_a: Vector3, hand_b: Vector3, head_b: Vector3, t: float) -> Vector3:
	var mid: Vector3 = _mid(hand, head)
	var mid_a: Vector3 = _mid(hand_a, head_a)
	var mid_b: Vector3 = _mid(hand_b, head_b)
	var delta := Vector3.ZERO
	# 1. Around the body.
	var closest := INF
	var near := Vector3.ZERO
	for k in 9:
		var p: Vector3 = mid_a.lerp(mid_b, k / 8.0)
		var r: float = rho(pose, p)
		if r < closest: closest = r; near = p
	var around: float = smoothstep(1.0 + SOFT + AROUND_FADE, 1.0 + SOFT, closest) if closest < INF else 0.0
	var pa: Vector3 = _polar(pose, mid_a); var pb: Vector3 = _polar(pose, mid_b); var pn: Vector3 = _polar(pose, near)
	var pm: Vector3 = _polar(pose, mid)
	if around > 0.0 and pa.x < INF and pb.x < INF and pm.x < INF:
		var turn: float = wrapf(pb.y - pa.y, -PI, PI)
		var other: float = turn - signf(turn) * TAU if absf(turn) > 1e-4 else 0.0
		# The side the straight path passes nearest: the arc whose middle is closer to it.
		if pn.x < INF and absf(wrapf(pa.y + other * 0.5 - pn.y, -PI, PI)) < absf(wrapf(pa.y + turn * 0.5 - pn.y, -PI, PI)): turn = other
		var r: float = lerpf(pa.x, pb.x, t)
		r = lerpf(r, maxf(r, _eased(r)), smoothstep(0.0, ENDS, t) * smoothstep(0.0, ENDS, 1.0 - t))
		var target: Vector3 = _from_polar(pose, r, pa.y + turn * t, pm.z, mid)
		delta = (target - mid) * around
	# 2. Clear the shaft, pushing along the middle's own side (never flips front / back).
	var ends: float = smoothstep(0.0, ENDS, t) * smoothstep(0.0, ENDS, 1.0 - t)
	if ends > 0.0:
		var out: Vector3 = _outward(pose, mid + delta)
		var wrist: Vector3 = hand + (hand - head).normalized() * WRIST_BEYOND_GRIP if hand.distance_squared_to(head) > 1e-6 else hand
		for step in 11:
			var d: Vector3 = delta + out * (0.02 * step * ends)
			var clear := true
			for k in SHAFT_SAMPLES + 1:
				if rho(pose, wrist.lerp(head, float(k) / SHAFT_SAMPLES) + d) < 1.0: clear = false; break
			if clear: delta = d; break
	return delta

static func _mid(hand: Vector3, head: Vector3) -> Vector3:
	var wrist: Vector3 = hand + (hand - head).normalized() * WRIST_BEYOND_GRIP if hand.distance_squared_to(head) > 1e-6 else hand
	return wrist.lerp(head, 0.5)

## rho' >= 1 for rho < 1 + SOFT, C1, equal to rho beyond.
static func _eased(r: float) -> float:
	if r >= 1.0 + SOFT: return r
	var u: float = (r - 1.0) / SOFT
	return 1.0 + SOFT * (0.25 * (u + 1.0) * (u + 1.0) if u > -1.0 else 0.0)

## Body frame at `p`: [origin, pivot basis, part basis, hinge] (stroke_body_pose.gd placement).
static func _frame(pose, p: Vector3) -> Array:
	var origin := Vector3(0.0, LIFT - float(pose.crouch_amount), -float(pose.weight_shift) * 0.1)
	var pivot := Basis.from_euler(Vector3(-float(pose.body_pitch_deg), -float(pose.body_yaw_deg), float(pose.body_roll_deg)) * (PI / 180.0))
	var q: Vector3 = pivot.inverse() * (p - origin)
	var part := Basis(Vector3.UP, -deg_to_rad(float(pose.hip_yaw_deg)))
	if q.y > WAIST_Y: part = part * Basis(Vector3.UP, -deg_to_rad(float(pose.torso_yaw_deg))) * Basis(Vector3.RIGHT, -deg_to_rad(float(pose.torso_pitch_deg)))
	return [origin, pivot, part, Vector3(0.0, WAIST_Y, 0.0)]

static func _local(pose, p: Vector3) -> Vector3:
	var f: Array = _frame(pose, p)
	return f[2].inverse() * (f[1].inverse() * (p - f[0]) - f[3]) + f[3]

## [rho, angle around the torso axis, local height]; x = INF off the torso.
static func _polar(pose, p: Vector3) -> Vector3:
	var local: Vector3 = _local(pose, p)
	var size: Vector2 = section(local.y)
	if size == Vector2.ZERO: return Vector3(INF, 0.0, local.y)
	var e := Vector2(local.x / (size.x + MARGIN), local.z / (size.y + MARGIN))
	return Vector3(e.length(), atan2(e.y, e.x), local.y)

static func _from_polar(pose, r: float, angle: float, y: float, near: Vector3) -> Vector3:
	var size: Vector2 = section(y)
	var local := Vector3(cos(angle) * r * (size.x + MARGIN), y, sin(angle) * r * (size.y + MARGIN))
	var f: Array = _frame(pose, near)
	return f[0] + f[1] * (f[2] * (local - f[3]) + f[3])

## Horizontal direction from the torso axis to `p` (canonical frame).
static func _outward(pose, p: Vector3) -> Vector3:
	var local: Vector3 = _local(pose, p)
	var f: Array = _frame(pose, p)
	var axis: Vector3 = f[0] + f[1] * (f[2] * (Vector3(0.0, local.y, 0.0) - f[3]) + f[3])
	var d: Vector3 = p - axis
	d.y = 0.0
	return d.normalized() if d.length_squared() > 1e-8 else Vector3(0.0, 0.0, -1.0)

## Shell value of `p` for `pose`: < 1 inside the torso + margin, >= 1 + SOFT clear; INF off the torso.
static func rho(pose, p: Vector3) -> float:
	return _polar(pose, p).x
