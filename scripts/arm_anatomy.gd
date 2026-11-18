extends RefCounted




const FLEXION_BUDGET_DEG: = 70.0
const EXTENSION_BUDGET_DEG: = 70.0
const RADIAL_BUDGET_DEG: = 25.0
const ULNAR_BUDGET_DEG: = 35.0
const AXIAL_BUDGET_DEG: = 90.0

static func frame(distal: Vector3, radial_hint: Vector3) -> Basis:
	var x: Vector3 = distal.normalized()
	if x.length_squared() < 0.5: x = Vector3.RIGHT
	var y: Vector3 = radial_hint - x * radial_hint.dot(x)
	if y.length_squared() < 1e-05:
		y = Vector3.UP - x * Vector3.UP.dot(x)
	if y.length_squared() < 1e-05:
		y = Vector3.FORWARD - x * Vector3.FORWARD.dot(x)
	y = y.normalized()
	return Basis(x, y, x.cross(y).normalized()).orthonormalized()

static func decompose(forearm_frame: Basis, hand_frame: Basis, radial_sign: float = 1.0) -> Dictionary:
	var relative: Basis = forearm_frame.orthonormalized().inverse() * hand_frame.orthonormalized()

	var flexion: = asin(clampf(relative.z.x, -1.0, 1.0))
	var deviation: = atan2( - relative.y.x, relative.x.x)
	var axial: = atan2( - relative.z.y, relative.z.z)
	var bend: = acos(clampf(relative.x.x, -1.0, 1.0))
	var flex_deg: = rad_to_deg(flexion)
	var dev_deg: = rad_to_deg(deviation) * radial_sign
	var axial_deg: = rad_to_deg(axial) * radial_sign
	var flex_limit: = FLEXION_BUDGET_DEG if flex_deg >= 0 else EXTENSION_BUDGET_DEG
	var dev_limit: = RADIAL_BUDGET_DEG if dev_deg >= 0 else ULNAR_BUDGET_DEG
	var ellipse: = pow(flex_deg / flex_limit, 2.0) + pow(dev_deg / dev_limit, 2.0)
	return {"flexion_deg": flex_deg, "radial_deviation_deg": dev_deg, "forearm_axial_deg": axial_deg, 
		"net_hand_forearm_bend_deg": rad_to_deg(bend), "coupled_budget_ratio": ellipse, 
		"within_animation_budget": ellipse <= 1.001 and absf(axial_deg) <= AXIAL_BUDGET_DEG + 0.01, 
		"singular": absf(cos(flexion)) < 0.01, "basis_determinant": hand_frame.determinant()}

static func forearm_reference(shoulder: Vector3, elbow: Vector3, wrist: Vector3, thumb_up: Vector3, is_left: bool) -> Basis:
	var distal: Vector3 = (wrist - elbow).normalized()
	var upper: Vector3 = (elbow - shoulder).normalized()



	var thumbward: Vector3 = - upper + distal * upper.dot(distal)
	if thumbward.length_squared() < 1e-05: thumbward = thumb_up - distal * thumb_up.dot(distal)
	var radial_sign: float = -1.0 if is_left else 1.0
	return frame(distal, thumbward * radial_sign)





static func forearm_reference_for_arm(arm, wrist: Vector3, is_left: bool) -> Basis:
	return forearm_reference(arm.upper_pivot.global_position, arm.forearm_pivot.global_position, 
		wrist, - arm.forearm_pivot.global_basis.y, is_left)





## Keep an almost axial guide from turning millimetres of hand motion into a
## large elbow swivel. This is geometry-only: identical poses solve identically
## during playback, reverse playback and random scrubbing, without contact lag.
## The reference is stance-relative and points toward the torso. A perpendicular
## authored guide has full authority and is returned unchanged.
static func stabilized_pole(shoulder: Vector3, wrist: Vector3, authored: Vector3, reference: Vector3) -> Vector3:
	var span: Vector3 = wrist - shoulder
	if span.length_squared() < 1e-10: return authored
	var axis: Vector3 = span.normalized()
	var hint: Vector3 = (authored - shoulder).normalized()
	var radial: Vector3 = hint - axis * hint.dot(axis)
	var leverage: float = radial.length()
	if leverage >= 0.35: return authored
	var preferred: Vector3 = reference - axis * reference.dot(axis)
	if preferred.length_squared() < 1e-08:
		preferred = Vector3.UP - axis * axis.y
	if preferred.length_squared() < 1e-08:
		preferred = Vector3.FORWARD - axis * axis.dot(Vector3.FORWARD)
	preferred = preferred.normalized()
	if leverage < 1e-08: return shoulder + preferred
	# Use an angular warp rather than adding vectors: addition would create a
	# new zero-length pole when the authored and reference directions oppose.
	# theta - w*sin(theta) is monotonic, periodic, and preserves the +/-PI seam.
	var angle: float = preferred.signed_angle_to(radial, axis)
	var weight: float = 1.0 - smoothstep(0.0, 0.35, leverage)
	return shoulder + preferred.rotated(axis, angle - weight * sin(angle))


static func conditioned_pole(shoulder: Vector3, wrist: Vector3, authored: Vector3, hand_distal: Vector3, upper_length: float, fore_length: float) -> Vector3:
	var span: Vector3 = wrist - shoulder
	var distance: float = span.length()
	if distance < 0.005 or distance >= upper_length + fore_length: return authored
	var axis: Vector3 = span / distance
	var along: float = (upper_length * upper_length - fore_length * fore_length + distance * distance) / (2.0 * distance)
	var radius: float = sqrt(maxf(0.0, upper_length * upper_length - along * along))
	if radius < 0.001: return authored
	var center: Vector3 = shoulder + axis * along
	var original: Vector3 = authored - shoulder
	original = (original - axis * original.dot(axis)).normalized()
	var optimal: Vector3 = -hand_distal.normalized()
	optimal -= axis * optimal.dot(axis)
	var orientation_leverage: float = optimal.length()
	optimal = optimal.normalized()
	if original.length_squared() < 0.5 or optimal.length_squared() < 0.5: return authored
	var current_elbow: Vector3 = center + original * radius
	var bend: float = rad_to_deg(hand_distal.angle_to(wrist - current_elbow))
	var blend: float = smoothstep(42.0, 90.0, bend)
	# A straight arm or an axial hand has no reliable wrist-derived bend plane.
	blend *= smoothstep(0.0, 0.002, upper_length + fore_length - distance)
	blend *= smoothstep(0.0, 0.1, orientation_leverage)
	var angle: float = original.signed_angle_to(optimal, axis)


	var correction: float = clampf(angle, - deg_to_rad(135.0), deg_to_rad(135.0)) * blend
	return shoulder + original.rotated(axis, correction)
