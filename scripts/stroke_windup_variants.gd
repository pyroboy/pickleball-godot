extends RefCounted
## Shared, disposable windup geometry. Never changes an authored keyframe.
## Used by editor previews and the human held-Hit preparation animation.
const Path = preload("res://scripts/stroke_swing_path.gd")
const Orientation = preload("res://scripts/stroke_preparation_orientation.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const WristReach = preload("res://scripts/paddle_wrist_reach.gd")
const D = preload("res://scripts/paddle_dimensions.gd")
enum Mode { NORMAL, STRONG, WEAK }
const NORMAL := Mode.NORMAL
const STRONG := Mode.STRONG
const WEAK := Mode.WEAK
const SIX_INCHES_M := 0.1524
const ARC_STEPS := 128
const EXTENSION_STEPS := 96
const EPSILON := 0.000001
const LIMIT_TOLERANCE_M := 0.00015
const MIN_REMAINING_ARC_M := 0.002

var mode := NORMAL
var report: Dictionary = {}
var _definition: PostureDefinition
var _sampler: Callable
var _player
var _length := 0.0
var _amount := 0.0
var _distances := PackedFloat64Array()
var _transforms: Array[Transform3D] = []
var _poses: Array[PostureDefinition] = []
var _extension_distances := PackedFloat64Array()
var _extension_heads := PackedVector3Array()
var _extension_axis := Vector3.UP
var _extension_radians_per_m := 0.0

func configure(definition: PostureDefinition, selected_mode: int = NORMAL, base_sampler: Callable = Callable(), player = null) -> void:
	_definition = definition
	mode = clampi(selected_mode, NORMAL, WEAK)
	_sampler = base_sampler
	_player = player
	_length = 0.0
	_amount = 0.0
	_distances.clear(); _transforms.clear(); _poses.clear()
	_extension_distances.clear(); _extension_heads.clear()
	_extension_axis = Vector3.UP; _extension_radians_per_m = 0.0
	report = {"mode": mode, "requested_distance_m": SIX_INCHES_M if mode != NORMAL else 0.0,
		"applied_distance_m": 0.0, "limited": false, "reason": "", "reach_checked": player != null}
	if definition == null or mode == NORMAL: return
	if definition.posture_id == 20:
		_limit("Ready is a static pose")
		return
	# Every sample below reads this same source without yielding or mutation.
	# Build its authored endpoints once; all 129 exact curve samples remain.
	var windup: PostureDefinition = Path.endpoint(definition, 0) if not _sampler.is_valid() else null
	var finish: PostureDefinition = Path.endpoint(definition, 2) if not _sampler.is_valid() else null
	for index in range(ARC_STEPS + 1):
		var progress: float = float(index) / (ARC_STEPS * 2.0)
		var pose: PostureDefinition = _base_sample(definition, progress) if _sampler.is_valid() else Path.sample_with_endpoints(definition, progress, windup, finish)
		var transform: Transform3D = _transform(pose)
		if index > 0: _length += (transform * D.HEAD_OFFSET).distance_to(_transforms[-1] * D.HEAD_OFFSET)
		_poses.append(pose); _transforms.append(transform); _distances.append(_length)
	if _length < MIN_REMAINING_ARC_M:
		_limit("No usable backswing curve")
		return
	_prepare_extension()
	_amount = SIX_INCHES_M
	if mode == WEAK and _amount > _length - MIN_REMAINING_ARC_M:
		_amount = maxf(0.0, _length - MIN_REMAINING_ARC_M)
		_limit("Short backswing curve")
	# Preserve existing authored constraint errors, but never increase them or
	# silently stretch the arm to make the six-inch request look successful.
	if player != null and not _amount_fits(_amount):
		var low := 0.0
		var high := _amount
		for iteration in range(11):
			var middle: float = (low + high) * 0.5
			if _amount_fits(middle): low = middle
			else: high = middle
		_amount = low if low >= 0.0005 else 0.0
		_limit("Arm reach or floor limit")
	report.applied_distance_m = _amount
	report.normal_backswing_length_m = _length

func _limit(reason: String) -> void:
	report.limited = true
	report.reason = reason

func status_text() -> String:
	if mode == NORMAL: return "Normal preview · authored Wind-up"
	var name: String = "Strong" if mode == STRONG else "Weak"
	var direction: String = "farther back" if mode == STRONG else "less backswing"
	if report.get("limited", false):
		return "%s preview · %.1f of 6 in · %s" % [name, _amount / 0.0254, report.get("reason", "Reach limit")]
	return "%s preview · 6 in %s" % [name, direction]

func sample(definition: PostureDefinition, progress: float) -> PostureDefinition:
	if definition == null: return null
	var t: float = clampf(progress, 0.0, 1.0)
	# A stance must remain truly static, even if old data contains phase deltas.
	if definition.posture_id == 20: return _base_sample(definition, 0.5)
	var base: PostureDefinition = _base_sample(definition, t)
	if definition != _definition or mode == NORMAL or _amount <= EPSILON or t >= 0.5: return base
	return _variant_pose(base, t, _amount)

## Continuous extension amount for held-Hit preparation, using the same curve.
func sample_amount(definition: PostureDefinition, progress: float, amount_ratio: float) -> PostureDefinition:
	var base: PostureDefinition = _base_sample(definition, clampf(progress, 0.0, 1.0))
	if definition != _definition or mode == NORMAL or _amount <= EPSILON or progress >= 0.5: return base
	return _variant_pose(base, clampf(progress, 0.0, 1.0), _amount * clampf(amount_ratio, 0.0, 1.0))

func _base_sample(definition: PostureDefinition, progress: float) -> PostureDefinition:
	return _sampler.call(definition, progress) if _sampler.is_valid() else Path.sample(definition, progress)

func _transform(pose: PostureDefinition) -> Transform3D:
	return Path.world_transform(_player, pose) if _player != null else Path.canonical_transform(pose)

func _distance_at_progress(progress: float) -> float:
	var position: float = clampf(progress * 2.0, 0.0, 1.0) * ARC_STEPS
	var index: int = mini(int(position), ARC_STEPS - 1)
	return lerpf(_distances[index], _distances[index + 1], position - index)

func _progress_at_distance(distance: float) -> float:
	if distance <= 0.0: return 0.0
	if distance >= _length: return 0.5
	var high: int = _upper_index(_distances, distance)
	var low: int = high - 1
	var span: float = _distances[high] - _distances[low]
	var fraction: float = (distance - _distances[low]) / span if span > EPSILON else 0.0
	return (low + fraction) / (ARC_STEPS * 2.0)

func _upper_index(values: PackedFloat64Array, distance: float) -> int:
	var low := 1
	var high: int = values.size() - 1
	while low < high:
		var middle: int = (low + high) / 2
		if values[middle] < distance: low = middle + 1
		else: high = middle
	return low

func _source_transform(distance: float) -> Transform3D:
	if distance < 0.0: return _extended_transform(-distance)
	if distance <= EPSILON: return _transforms[0]
	if distance >= _length: return _transforms[-1]
	# Arc length selects a time on the original sampler; it does not replace
	# curved strokes or a serve's multi-part release/strike by three straight lines.
	return _transform(_base_sample(_definition, _progress_at_distance(distance)))

func _prepare_extension() -> void:
	var span: float = minf(0.012, _length * 0.05)
	var h0: Vector3 = _transforms[0] * D.HEAD_OFFSET
	var first: Transform3D = _source_transform(span)
	var h1: Vector3 = first * D.HEAD_OFFSET
	var h2: Vector3 = _source_transform(span * 2.0) * D.HEAD_OFFSET
	var tangent: Vector3 = ((h1 - h0) * 4.0 - (h2 - h0)).normalized()
	if tangent.length_squared() < EPSILON: tangent = (h1 - h0).normalized()
	var curvature: Vector3 = (h2 - h1 * 2.0 + h0) / (span * span)
	curvature -= tangent * curvature.dot(tangent)
	# A short, stable local continuation. No looping beyond the authored start.
	curvature = curvature.limit_length(8.0)
	var q0: Quaternion = _transforms[0].basis.get_rotation_quaternion()
	var q1: Quaternion = first.basis.get_rotation_quaternion()
	if q0.dot(q1) < 0.0: q1 = -q1
	var turn: Quaternion = (q0.inverse() * q1).normalized()
	var imaginary := Vector3(turn.x, turn.y, turn.z)
	var angle: float = 2.0 * atan2(imaginary.length(), turn.w)
	if angle > EPSILON:
		_extension_axis = imaginary.normalized()
		_extension_radians_per_m = minf(angle / span, 12.0)
	var cumulative := 0.0
	for index in range(EXTENSION_STEPS + 1):
		var offset: float = -SIX_INCHES_M * float(index) / EXTENSION_STEPS
		var head: Vector3 = h0 + tangent * offset + curvature * (offset * offset * 0.5)
		if index > 0: cumulative += head.distance_to(_extension_heads[-1])
		_extension_heads.append(head); _extension_distances.append(cumulative)

func _extended_transform(distance: float) -> Transform3D:
	var high: int = _upper_index(_extension_distances, distance)
	var low: int = high - 1
	var span: float = _extension_distances[high] - _extension_distances[low]
	var fraction: float = clampf((distance - _extension_distances[low]) / maxf(span, EPSILON), 0.0, 1.0)
	var head: Vector3 = _extension_heads[low].lerp(_extension_heads[high], fraction)
	var basis: Basis = _transforms[0].basis * Basis(_extension_axis, -distance * _extension_radians_per_m)
	return Transform3D(basis, head - basis * D.HEAD_OFFSET)

func _target_distance(progress: float, amount: float) -> float:
	var distance: float = _distance_at_progress(progress)
	var fraction: float = clampf(distance / _length, 0.0, 1.0)
	if mode == STRONG:
		return distance - amount * pow(1.0 - fraction, 2.0)
	# Monotonic shortening, even when the requested distance is most of a small
	# backswing. The derivative returns to 1 at Contact, so there is no new kink.
	var remaining: float = maxf(_length - amount, EPSILON)
	return amount + remaining * pow(fraction, _length / remaining)

func _variant_pose(base: PostureDefinition, progress: float, amount: float) -> PostureDefinition:
	var pose: PostureDefinition = base.duplicate(true)
	var displayed: Transform3D = _source_transform(_target_distance(progress, amount))
	# The curve measures the visible head after grip spin. Convert it back to
	# authored coordinates before setting fields; never double-apply grip spin.
	var raw: Transform3D = Path.remove_in_hand_transform(displayed, pose)
	var stance: Basis = Basis(_player._get_forehand_axis(), Vector3.UP, -_player._get_forward_axis()) if _player != null else Basis.IDENTITY
	Orientation.set_canonical_basis(pose, stance.inverse() * raw.basis)
	var head: Vector3 = raw * D.HEAD_OFFSET - (_player.global_position if _player != null else Vector3.ZERO)
	var local: Vector3 = stance.inverse() * head
	pose.paddle_forehand_mul = local.x
	pose.paddle_y_offset = local.y
	pose.paddle_forward_mul = -local.z
	return pose

func _amount_fits(amount: float) -> bool:
	if amount <= EPSILON: return true
	# These checks use the same original body clocks as playback. Retiming an
	# entire serve would accidentally move its planted feet or held-ball hand.
	for index in range(0, ARC_STEPS, 4):
		var t: float = float(index) / (ARC_STEPS * 2.0)
		var base: PostureDefinition = _poses[index]
		var pose: PostureDefinition = _variant_pose(base, t, amount)
		var desired: Transform3D = _source_transform(_target_distance(t, amount))
		var actual: Transform3D = _transform(pose)
		if (desired * D.HEAD_OFFSET).distance_to(actual * D.HEAD_OFFSET) > LIMIT_TOLERANCE_M: return false
		var shoulder: Vector3 = Body.shoulder_world(_player, pose)
		var budget: float = WristReach.link_budget(_player, pose)
		var original_distance: float = WristReach.wrist_world(_transforms[index], base).distance_to(shoulder)
		var allowed_distance: float = maxf(budget, original_distance) + LIMIT_TOLERANCE_M
		if WristReach.wrist_world(actual, pose).distance_to(shoulder) > allowed_distance: return false
	return true
