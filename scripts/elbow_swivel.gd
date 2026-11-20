extends RefCounted
## Elbow swivel: the one free choice an arm IK leaves (how far the elbow turns around the
## shoulder-wrist line), stored per key as an angle instead of a pole point. Blending the angle
## cannot swing the elbow through the arm the way a straight-line pole blend can.
##
## 0 deg = the elbow down for an arm pointing forward and a little out (REST_*); the reference
## follows the arm by the smallest rotation from that rest direction, and the chest by the pose's
## yaw, so it is continuous everywhere except an arm pointing straight back-and-in (never used).
## Positive = elbow turns out from the body (mirrored for the left arm).

const REST_OUT := 0.6       # rest arm direction: forward + 0.6 x out from the body
const POLE_REACH := 0.5     # pole distance from the arm line (metres): keeps stabilized_pole out of play

## [out_from_body, forward] of the chest for this pose and arm (world, unit, horizontal).
static func frame(def, forehand_axis: Vector3, forward_axis: Vector3, left: bool) -> Array:
	var yaw: float = deg_to_rad(float(def.body_yaw_deg) + float(def.hip_yaw_deg) + float(def.torso_yaw_deg))
	var turn := Basis(Vector3.UP, -yaw)
	var side: float = -1.0 if left else 1.0
	return [(turn * (forehand_axis * side)).normalized(), (turn * forward_axis).normalized()]

## Unit swivel-0 direction around the arm line (perpendicular to it); ZERO where undefined.
static func zero_direction(shoulder: Vector3, wrist: Vector3, out_dir: Vector3, fwd_dir: Vector3) -> Vector3:
	var span := wrist - shoulder
	if span.length_squared() < 1e-6: return Vector3.ZERO
	var axis := span.normalized()
	var rest := (fwd_dir + out_dir * REST_OUT).normalized()
	if rest.dot(axis) < -0.995: return Vector3.ZERO
	var rest_ref := Vector3.DOWN - rest * Vector3.DOWN.dot(rest)
	var r: Vector3 = Quaternion(rest, axis) * rest_ref.normalized()
	r -= axis * r.dot(axis)
	return r.normalized() if r.length_squared() > 1e-8 else Vector3.ZERO

## World pole that puts the elbow at `deg` (left arm mirrored); INF where undefined.
static func pole(shoulder: Vector3, wrist: Vector3, out_dir: Vector3, fwd_dir: Vector3, deg: float, left: bool) -> Vector3:
	var ref := zero_direction(shoulder, wrist, out_dir, fwd_dir)
	if ref == Vector3.ZERO: return Vector3.INF
	var span := wrist - shoulder
	var axis := span.normalized()
	var side: float = -1.0 if left else 1.0
	return shoulder + span * 0.5 + ref.rotated(axis, deg_to_rad(deg) * side) * POLE_REACH

## Swivel of a solved elbow, or of any point such as a pole (degrees, left arm mirrored); NAN when
## the point is on the arm line.
static func angle(shoulder: Vector3, wrist: Vector3, elbow: Vector3, out_dir: Vector3, fwd_dir: Vector3, left: bool) -> float:
	var ref := zero_direction(shoulder, wrist, out_dir, fwd_dir)
	if ref == Vector3.ZERO: return NAN
	var axis := (wrist - shoulder).normalized()
	var radial := elbow - shoulder
	radial -= axis * radial.dot(axis)
	if radial.length() < 0.005: return NAN
	var side: float = -1.0 if left else 1.0
	return rad_to_deg(ref.signed_angle_to(radial, axis)) * side

## Blend two poses' swivel fields: [right_deg, left_deg, weight]. In between, the weight is the
## smaller of the two ends': a blend with a pose that has no swivel (serves, built in code) plays
## exactly as before, and the hand-over at its ends is seamless because a baked swivel shows the
## same elbow as the older pole at its own key.
static func blend(a, b, t: float) -> Array:
	var wa: float = float(a.elbow_swivel_weight)
	var wb: float = float(b.elbow_swivel_weight)
	if t <= 0.0: return [a.right_elbow_swivel_deg, a.left_elbow_swivel_deg, wa]
	if t >= 1.0: return [b.right_elbow_swivel_deg, b.left_elbow_swivel_deg, wb]
	var w: float = minf(wa, wb)
	if wa > 0.0 and wb <= 0.0: return [a.right_elbow_swivel_deg, a.left_elbow_swivel_deg, w]
	if wb > 0.0 and wa <= 0.0: return [b.right_elbow_swivel_deg, b.left_elbow_swivel_deg, w]
	return [lerpf(a.right_elbow_swivel_deg, b.right_elbow_swivel_deg, t), lerpf(a.left_elbow_swivel_deg, b.left_elbow_swivel_deg, t), w]

## Blend the older pole (`legacy`, world point) toward the swivel angle `deg` by `w`, as angles
## in -180..180 blended through 0 (the elbow-down side), never the shortest way: the shortest way
## switches sides whenever the two are 180 deg apart, which a moving arm crosses anywhere; this
## switches only when an elbow points straight up.
static func mix(shoulder: Vector3, wrist: Vector3, legacy: Vector3, out_dir: Vector3, fwd_dir: Vector3, deg: float, left: bool, w: float) -> Vector3:
	if w <= 0.0: return legacy
	var swivel := pole(shoulder, wrist, out_dir, fwd_dir, deg, left)
	if not swivel.is_finite(): return legacy
	if w >= 1.0: return swivel
	var old := angle(shoulder, wrist, legacy, out_dir, fwd_dir, left)
	if is_nan(old): return swivel
	return pole(shoulder, wrist, out_dir, fwd_dir, lerpf(wrapf(old, -180.0, 180.0), wrapf(deg, -180.0, 180.0), w), left)

# ---------------------------------------------------------------- visual-only elbow

## The solved arm (what gameplay reads) keeps the guide-point elbow; the authored swivel is drawn
## by turning the elbow around the shoulder-wrist line by this angle (pixel cards, studio, checker).
const VISUAL_TURN_META := "elbow_visual_turn"

static func record_visual_turn(arm, wrist: Vector3, solved_pole: Vector3, swivel_pole: Vector3) -> void:
	var turn := 0.0
	if solved_pole != swivel_pole:
		var shoulder: Vector3 = arm.upper_pivot.global_position
		var span := wrist - shoulder
		if span.length_squared() > 1e-6:
			var axis := span.normalized()
			var a := solved_pole - shoulder; a -= axis * a.dot(axis)
			var b := swivel_pole - shoulder; b -= axis * b.dot(axis)
			if a.length_squared() > 1e-8 and b.length_squared() > 1e-8: turn = a.signed_angle_to(b, axis)
	var m: Dictionary = arm.get_meta(VISUAL_TURN_META, {})
	if turn == 0.0 and m.is_empty(): return
	var frame := Engine.get_physics_frames()
	var prev: float = float(m.get("prev", turn)) if int(m.get("frame", -1)) == frame else float(m.get("cur", turn))
	arm.set_meta(VISUAL_TURN_META, {"frame": frame, "prev": prev, "cur": turn})

## The drawn elbow from the solved shoulder, elbow and forearm end; `fraction` (0..1, physics
## interpolation) blends the previous tick's turn into this one's; < 0 = this tick's.
static func visual_elbow(arm, shoulder: Vector3, elbow: Vector3, wrist_end: Vector3, fraction := -1.0) -> Vector3:
	var m: Dictionary = arm.get_meta(VISUAL_TURN_META, {})
	if m.is_empty(): return elbow
	var turn: float = float(m.cur) if fraction < 0.0 else lerp_angle(float(m.prev), float(m.cur), fraction)
	if absf(turn) < 1e-6: return elbow
	var span := wrist_end - shoulder
	if span.length_squared() < 1e-6: return elbow
	return shoulder + (elbow - shoulder).rotated(span.normalized(), turn)

## This tick's drawn elbow from the arm's current (not interpolated) transforms.
static func visual_elbow_now(arm) -> Vector3:
	var e: Vector3 = arm.forearm_pivot.global_position
	if not arm.has_meta(VISUAL_TURN_META): return e
	return visual_elbow(arm, arm.upper_pivot.global_position, e, arm.anatomical_wrist_world)
