extends RefCounted
## A fixed wrist and two fixed link lengths leave one elbow-circle degree of
## freedom. Select the nearest plane inside the existing wrist budget without
## rotating or translating a seated hand, the paddle, body, or contact target.
##
## One wrist budget for the whole game: the reach preflight (`accepts`, cached yes / no,
## live_transition_arm_reach) and the arm solve (`solve`, the elbow) use the same cost. The
## preflight's planes (every 10 deg) are a subset of the solve's (every 5 deg) and its limit
## (.98) is inside the solve's (1.0), so a body offset the preflight accepts is always one the
## solve can fit; the preflight is only ever the stricter of the two.
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const PaddleClearance = preload("res://scripts/paddle_clearance.gd")
const Screen = preload("res://scripts/qa_af_joint_region_screen.gd")
const STEP := PI / 36.0          # 5 deg (qa_af_joint_region_screen qualifies against it)
const SOLVE_LATTICE := 72        # elbow planes the solve samples (every 5 deg), then bisects
const LATTICE := 36              # planes the preflight samples (every 10 deg): every one is also a solve plane
const LATTICE_STEP := STEP * 2.0
const FLEX_LIMIT: float = Anatomy.FLEXION_BUDGET_DEG
const EXT_LIMIT: float = Anatomy.EXTENSION_BUDGET_DEG
const RADIAL_LIMIT: float = Anatomy.RADIAL_BUDGET_DEG
const ULNAR_LIMIT: float = Anatomy.ULNAR_BUDGET_DEG
const AXIAL_LIMIT: float = Anatomy.AXIAL_BUDGET_DEG
const ELBOW_LIMIT_IN_PLAY := false
const CACHE_LIMIT := 512
const CACHE_LIFETIME_TICKS := 60
static var _accept_cache := {}
static var _cache_epoch := -1

static func displayed_report(player) -> Dictionary:
	if player != null and "posture" in player and player.posture != null: player.posture.ensure_arm_pose()
	# Admission observes the displayed skin and physical joints. Solver metadata
	# is diagnostic only and can never certify a hand that was subsequently moved.
	var result := {"valid": true, "arms": []}
	for side in range(2):
		var arm = player.right_arm_node if side == 0 else player.left_arm_node
		if arm == null or arm.articulated_hand == null:
			result.valid = false
			result.arms.append({"valid": false, "reason": "missing_displayed_arm"})
			continue
		var model = arm.articulated_hand
		var mount: Transform3D = arm.hand_mesh.global_transform
		var wrist: Vector3 = mount * model.wrist_socket
		var shoulder: Vector3 = arm.upper_pivot.global_position
		var elbow: Vector3 = arm.forearm_pivot.global_position
		var upper_error: float = absf(shoulder.distance_to(elbow) - arm.upper_arm_length)
		var fore_error: float = absf(elbow.distance_to(wrist) - arm.forearm_length)
		# The solve's world-space wrist cache does not follow later root travel.
		# Measure the displayed forearm endpoint instead of certifying/rejecting
		# moving geometry from that stale diagnostic coordinate.
		var forearm_end: Vector3 = arm.forearm_pivot.global_transform * Vector3(0.0, 0.0, -arm.forearm_length)
		var socket_error: float = wrist.distance_to(forearm_end)
		var reference: Basis = Anatomy.forearm_reference_for_arm(arm, wrist, side == 1)
		var channels: Dictionary = Anatomy.decompose(reference, mount.basis * model.anatomical_basis, -1.0 if side == 1 else 1.0)
		var valid: bool = wrist.is_finite() and upper_error <= .00002 and fore_error <= .00002 and socket_error <= .00002 and bool(channels.within_animation_budget)
		result.arms.append({"valid": valid, "channels": channels, "upper_link_error": upper_error,
			"fore_link_error": fore_error, "wrist_socket_error": socket_error,
			"reach": shoulder.distance_to(wrist), "link_budget": arm.upper_arm_length + arm.forearm_length})
		result.valid = result.valid and valid
	return result

static func solve(shoulder: Vector3, wrist: Vector3, elbow: Vector3, hand_basis: Basis, upper: float, fore: float, is_left: bool) -> Dictionary:
	var result := {"feasible": false, "changed": false, "elbow": elbow, "angle": 0.0, "cost": INF}
	var span: Vector3 = wrist - shoulder
	var distance := span.length()
	if distance < 0.00001 or distance >= upper + fore or distance <= absf(upper - fore): return result
	var axis := span / distance
	var along := (upper * upper - fore * fore + distance * distance) / (2.0 * distance)
	var radius := sqrt(maxf(0.0, upper * upper - along * along))
	var center := shoulder + axis * along
	var radial := elbow - center
	radial -= axis * radial.dot(axis)
	if radial.length_squared() < 0.00000001:
		radial = Vector3.UP - axis * axis.y
	if radial.length_squared() < 0.00000001:
		radial = Vector3.RIGHT - axis * axis.x
	radial = radial.normalized()
	result.cost = _cost(shoulder, wrist, center + radial * radius, hand_basis, is_left)
	result.nearest_elbow = center + radial * radius
	if _fits(shoulder, wrist, center + radial * radius, hand_basis, is_left):
		result.feasible = true
		return result
	# Use a fixed hand-relative chart so reach preflight and final IK inspect
	# the same sample lattice even when their input elbow was from last frame.
	var reference := hand_basis.y - axis * hand_basis.y.dot(axis)
	if reference.length_squared() < 0.00000001: reference = hand_basis.z - axis * hand_basis.z.dot(axis)
	reference = reference.normalized()
	var original_angle := reference.signed_angle_to(radial, axis)
	var best := INF
	for index in range(SOLVE_LATTICE):
		var angle := float(index) * STEP
		var delta := wrapf(angle - original_angle, -PI, PI)
		var candidate := center + reference.rotated(axis, angle) * radius
		var cost := _cost(shoulder, wrist, candidate, hand_basis, is_left)
		if cost < result.cost:
			result.cost = cost
			result.nearest_elbow = candidate
		if cost <= 1.0 and absf(delta) < absf(best): best = delta
	if is_finite(best):
		var low := 0.0; var high := absf(best); var direction := signf(best)
		for unused in range(14):
			var middle := (low + high) * .5
			if _fits(shoulder, wrist, center + radial.rotated(axis, middle * direction) * radius, hand_basis, is_left): high = middle
			else: low = middle
		best = high * direction
	if not is_finite(best): return result
	result.feasible = true
	result.changed = true
	result.angle = best
	result.elbow = center + radial.rotated(axis, best) * radius
	return result

static func _fits(shoulder: Vector3, wrist: Vector3, elbow: Vector3, hand: Basis, is_left: bool) -> bool:
	return _cost(shoulder, wrist, elbow, hand, is_left) <= 1.0

static func _cost(shoulder: Vector3, wrist: Vector3, elbow: Vector3, hand: Basis, is_left: bool) -> float:
	return cost(shoulder, wrist, elbow, hand.orthonormalized(), is_left)

## Wrist budget use of an elbow (<= 1 inside; a numerical reserve, never wider budgets): the
## Anatomy.forearm_reference / decompose channel maths inlined with static types.
static func cost(shoulder: Vector3, wrist: Vector3, elbow: Vector3, hand_orthonormal: Basis, left: bool) -> float:
	var distal: Vector3 = (wrist - elbow).normalized()
	var upper_dir: Vector3 = (elbow - shoulder).normalized()
	var thumbward: Vector3 = -upper_dir + distal * upper_dir.dot(distal)
	if thumbward.length_squared() < 1e-05: thumbward = Vector3.UP - distal * Vector3.UP.dot(distal)
	var hint: Vector3 = thumbward * (-1.0 if left else 1.0)
	var x: Vector3 = distal.normalized()
	if x.length_squared() < 0.5: x = Vector3.RIGHT
	var y: Vector3 = hint - x * hint.dot(x)
	if y.length_squared() < 1e-05: y = Vector3.UP - x * Vector3.UP.dot(x)
	if y.length_squared() < 1e-05: y = Vector3.FORWARD - x * Vector3.FORWARD.dot(x)
	y = y.normalized()
	var forearm := Basis(x, y, x.cross(y).normalized()).orthonormalized()
	var relative: Basis = forearm.orthonormalized().inverse() * hand_orthonormal
	var flexion: float = asin(clampf(relative.z.x, -1.0, 1.0))
	var deviation: float = atan2(-relative.y.x, relative.x.x)
	var axial: float = atan2(-relative.z.y, relative.z.z)
	var sign_side: float = -1.0 if left else 1.0
	var flex_deg: float = rad_to_deg(flexion)
	var dev_deg: float = rad_to_deg(deviation) * sign_side
	var axial_deg: float = rad_to_deg(axial) * sign_side
	var flex_limit: float = FLEX_LIMIT if flex_deg >= 0 else EXT_LIMIT
	var dev_limit: float = RADIAL_LIMIT if dev_deg >= 0 else ULNAR_LIMIT
	var ellipse: float = pow(flex_deg / flex_limit, 2.0) + pow(dev_deg / dev_limit, 2.0)
	return maxf(ellipse / .999, absf(axial_deg) / (AXIAL_LIMIT - .05))

# ---------------------------------------------------------------- reach preflight

## Some elbow plane fits this wrist within `maximum` (the reach preflight). Same cost and
## LATTICE as `solve`; cached per exact input for CACHE_LIFETIME_TICKS.
static func accepts(shoulder: Vector3, wrist: Vector3, elbow: Vector3, hand: Basis, upper: float, fore: float, left: bool, maximum: float = .98) -> bool:
	var _pt := Time.get_ticks_usec()
	var tick := Engine.get_physics_frames()
	if _cache_epoch < 0 or tick < _cache_epoch or tick - _cache_epoch >= CACHE_LIFETIME_TICKS or _accept_cache.size() >= CACHE_LIMIT:
		_accept_cache.clear(); _cache_epoch = tick
	var key := var_to_bytes([shoulder, wrist, elbow, hand, upper, fore, left, maximum])
	var hit = _accept_cache.get(key)
	if hit == null:
		hit = _accepts(shoulder, wrist, elbow, hand, upper, fore, left, maximum)
		_accept_cache[key] = hit
	PerfMonitor.record("reach.accepts", Time.get_ticks_usec() - _pt)
	return hit

static func _accepts(shoulder: Vector3, wrist: Vector3, elbow: Vector3, hand: Basis, upper: float, fore: float, left: bool, maximum: float) -> bool:
	if not (shoulder.is_finite() and wrist.is_finite() and elbow.is_finite() and hand.is_finite() and is_finite(upper) and is_finite(fore) and is_finite(maximum)) or maximum > 1.0:
		var full := solve(shoulder, wrist, elbow, hand, upper, fore, left)
		return bool(full.feasible) and not float(full.cost) > maximum
	var span: Vector3 = wrist - shoulder
	var distance: float = span.length()
	if distance < .00001 or distance >= upper + fore or distance <= absf(upper - fore): return false
	var axis: Vector3 = span / distance
	var along: float = (upper * upper - fore * fore + distance * distance) / (2.0 * distance)
	var radius: float = sqrt(maxf(0.0, upper * upper - along * along))
	var center: Vector3 = shoulder + axis * along
	var radial: Vector3 = elbow - center
	radial -= axis * radial.dot(axis)
	if radial.length_squared() < .00000001: radial = Vector3.UP - axis * axis.y
	if radial.length_squared() < .00000001: radial = Vector3.RIGHT - axis * axis.x
	radial = radial.normalized()
	var hand_orthonormal: Basis = hand.orthonormalized()
	var initial: float = cost(shoulder, wrist, center + radial * radius, hand_orthonormal, left)
	if initial <= 1.0: return not initial > maximum   # the solve keeps this plane as it is
	var reference: Vector3 = hand.y - axis * hand.y.dot(axis)
	if reference.length_squared() < .00000001: reference = hand.z - axis * hand.z.dot(axis)
	reference = reference.normalized()
	if Screen.enabled and Screen.rejects(shoulder, wrist, hand, hand_orthonormal, axis, center, distance, along, radius, reference, upper, fore, left, maximum, initial): return false
	for index in LATTICE:
		if cost(shoulder, wrist, center + reference.rotated(axis, float(index) * LATTICE_STEP) * radius, hand_orthonormal, left) <= maximum: return true
	return false

static func apply(player, pose, hands) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_apply(player, pose, hands)
	PerfMonitor.record("arm.budget", Time.get_ticks_usec() - _pt)

static func _perf_apply(player, pose, hands) -> void:
	if not load("res://scripts/live_transition_arm_reach.gd").enabled(player, pose): return
	var reports: Array = []
	var rally: bool = load("res://scripts/live_transition_arm_reach.gd").in_rally(player)
	for side in range(2):
		var arm = player.right_arm_node if side == 0 else player.left_arm_node
		var model = arm.articulated_hand
		var mount: Transform3D = arm.hand_mesh.global_transform
		var wrist: Vector3 = mount * model.wrist_socket
		var main: bool = side == pose.paddle_hand
		if not main and hands.mode in ["RELAXED", "REGRIP"]:
			# A released support hand has no fixed paddle contact. Align its
			# orientation to the actual solved forearm rather than world-up,
			# which otherwise produces 150-degree axial twists during low shots.
			var neutral: Basis = Anatomy.forearm_reference_for_arm(arm, wrist, side == 1)
			var current: Basis = mount.basis * model.anatomical_basis
			var report := Anatomy.decompose(neutral, current, -1.0 if side == 1 else 1.0)
			if not report.within_animation_budget:
				var low := 0.0; var high := 1.0
				for unused in range(14):
					var weight := (low + high) * .5
					var candidate: Basis = current.slerp(neutral, weight).orthonormalized()
					var candidate_report := Anatomy.decompose(neutral, candidate, -1.0 if side == 1 else 1.0)
					if candidate_report.coupled_budget_ratio <= .999 and absf(candidate_report.forearm_axial_deg) <= Anatomy.AXIAL_BUDGET_DEG - .05: high = weight
					else: low = weight
				var basis: Basis = current.slerp(neutral, high).orthonormalized() * model.anatomical_basis.inverse()
				mount = Transform3D(basis, wrist - basis * model.wrist_socket)
				model.set_mesh_world_transform(mount)
				model.update_wrist_bridge(arm.fore_mesh.global_basis)
			var continuity: Dictionary = _continuous_support(player, arm, mount, side == 1)
			mount = arm.hand_mesh.global_transform
			hands.apply_live_regrip_shape(arm, pose)
			var separation: Dictionary = _separate_released_hand(player, arm, mount, side == 1)
			if not separation.get("feasible", true): separation = _recover_support_clearance(player, arm, mount, side == 1)
			var support_frame: Dictionary = arm.get_meta("live_support_frame", {})
			if not support_frame.is_empty():
				support_frame.wrist = arm.hand_mesh.global_transform * model.wrist_socket
				support_frame.shoulder = arm.upper_pivot.global_position

			reports.append({"feasible": true, "released_support": true, "clearance": separation, "continuity": continuity})
			continue
		# The elbow stays where the pose and the arm IK put it (user's call, 2026-11-23: solvers
		# belong in Pose Studio). Re-picking the elbow plane for wrist limits every tick cost 7% of
		# a physics tick and added elbow / hand shake. ELBOW_LIMIT_IN_PLAY = true restores it.
		var result: Dictionary = solve(arm.upper_pivot.global_position, wrist, arm.forearm_pivot.global_position,
			mount.basis * model.anatomical_basis, arm.upper_arm_length, arm.forearm_length, side == 1) if ELBOW_LIMIT_IN_PLAY or not rally \
			else {"feasible": true, "changed": false, "elbow": arm.forearm_pivot.global_position, "angle": 0.0, "cost": 0.0}
		reports.append(result)
		if not main:
			_remember_support(player, arm, mount)
			hands.apply_live_regrip_shape(arm, pose)
		if not result.feasible or not result.changed: continue
		arm.upper_pivot.basis = arm.upper_pivot.basis.orthonormalized()
		arm.forearm_pivot.basis = arm.forearm_pivot.basis.orthonormalized()
		arm.solve_ik(arm.hand_pivot.global_position, result.elbow, null, wrist)
		model.set_mesh_world_transform(mount)
		model.update_wrist_bridge(arm.fore_mesh.global_basis)
	player.set_meta("live_arm_budget", reports)

static func _separate_released_hand(player, arm, mount: Transform3D, left: bool) -> Dictionary:
	# Only a released hand may leave its nominal wrist target. Translate along
	# the paddle normal by the smallest skin-derived clearance, then solve the
	# real fixed links and wrist channels again. Seated grips never enter here.
	var paddle: Transform3D = player.paddle_node.global_transform
	var local: Transform3D = paddle.affine_inverse() * mount
	if PaddleClearance.distance_to_paddle_shape(local.origin) > .18: return {"moved": false}
	var points: PackedVector3Array = arm.articulated_hand.sampled_vertices()
	var intervals: Array[Vector2] = []
	var overlaps := false
	for point in points:
		var p: Vector3 = local * point
		var half_width := -1.0
		var cap: float = Vector2(p.x, maxf(absf(p.y - PaddleSize.HEAD_CENTER_Y) - PaddleSize.HEAD_SPINE_HALF, 0.0)).length()
		if cap <= PaddleSize.HEAD_RADIUS: half_width = PaddleSize.HEAD_HALF_THICKNESS
		if absf(p.y - PaddleSize.HANDLE_CENTER_Y) <= PaddleSize.HANDLE_LENGTH * .5 and absf(p.x) <= PaddleSize.HANDLE_RADIUS:
			half_width = maxf(half_width, sqrt(maxf(0.0, PaddleSize.HANDLE_RADIUS * PaddleSize.HANDLE_RADIUS - p.x * p.x)))
		if half_width < 0.0: continue
		var interval := Vector2(-half_width - p.z - .001, half_width - p.z + .001)
		intervals.append(interval)
		if interval.x < 0.0 and interval.y > 0.0: overlaps = true
	if not overlaps: return {"moved": false}
	var positive := 0.0; var negative := 0.0
	for unused in range(intervals.size() + 1):
		var old_positive := positive; var old_negative := negative
		for interval in intervals:
			if interval.x < positive + .000001 and interval.y > positive: positive = interval.y
			if interval.x < negative and interval.y > negative - .000001: negative = interval.x
		if positive == old_positive and negative == old_negative: break
	var candidates: Array = [positive, negative] if positive <= -negative else [negative, positive]
	var wrist: Vector3 = mount * arm.articulated_hand.wrist_socket
	for amount in candidates:
		if absf(amount) > .075:
			var tilted: Dictionary = _tilted_release_escape(player, arm, mount, left, signf(amount), points)
			if tilted.get("feasible", false): return tilted
			continue
		var shift: Vector3 = paddle.basis.z.normalized() * amount
		var fit := solve(arm.upper_pivot.global_position, wrist + shift, arm.forearm_pivot.global_position,
			mount.basis * arm.articulated_hand.anatomical_basis, arm.upper_arm_length, arm.forearm_length, left)
		if not fit.feasible: continue
		arm.upper_pivot.basis = arm.upper_pivot.basis.orthonormalized()
		arm.forearm_pivot.basis = arm.forearm_pivot.basis.orthonormalized()
		mount.origin += shift
		arm.solve_ik(mount.origin, fit.elbow, null, wrist + shift)
		arm.articulated_hand.set_mesh_world_transform(mount)
		arm.articulated_hand.update_wrist_bridge(arm.fore_mesh.global_basis)
		return {"moved": true, "distance": amount, "feasible": true}
	return {"moved": false, "feasible": false}

static func _support_clock(player, arm) -> Dictionary:
	var now: float = player._support_sim_time
	var state: Dictionary = arm.get_meta("live_support_frame", {})
	if state.is_empty():
		state = {"start_shoulder": arm.upper_pivot.global_position, "shoulder": arm.upper_pivot.global_position, "time": now, "dt": 0.0, "remaining": 0.0, "start": arm.hand_mesh.global_basis.orthonormalized(), "last": arm.hand_mesh.global_basis.orthonormalized(), "wrist": arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket, "start_wrist": arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket}
	elif now > float(state.time) + .0000001:
		state.start = state.last
		state.start_wrist = state.wrist
		state.start_shoulder = state.shoulder
		state.dt = now - float(state.time)
		state.time = now
		state.remaining = deg_to_rad(719.0) * float(state.dt)
	return state

static func _remember_support(player, arm, mount: Transform3D) -> void:
	var state: Dictionary = _support_clock(player, arm)
	state.last = mount.basis.orthonormalized()
	state.wrist = mount * arm.articulated_hand.wrist_socket
	state.shoulder = arm.upper_pivot.global_position
	arm.set_meta("live_support_frame", state)

static func _continuous_support(player, arm, desired: Transform3D, left: bool) -> Dictionary:
	var state: Dictionary = _support_clock(player, arm)
	var previous: Basis = state.last
	var wanted: Basis = desired.basis.orthonormalized()
	var angle: float = _basis_angle(previous, wanted)
	var allowance: float = state.remaining
	var weight: float = minf(1.0, allowance / maxf(angle, .000001))
	var wrist: Vector3 = desired * arm.articulated_hand.wrist_socket
	var chosen: Basis = previous.slerp(wanted, weight).orthonormalized()
	var fit := solve(arm.upper_pivot.global_position, wrist, arm.forearm_pivot.global_position,
		chosen * arm.articulated_hand.anatomical_basis, arm.upper_arm_length, arm.forearm_length, left)
	if not fit.feasible:
		# The free wrist can follow a continuous safe approach while its hand
		# orientation catches up; it has no seated paddle constraint yet.
		var previous_wrist: Vector3 = state.wrist + arm.upper_pivot.global_position - Vector3(state.shoulder)
		for index in range(1, 13):
			var trial_wrist: Vector3 = wrist.lerp(previous_wrist, float(index) / 12.0)
			var trial := solve(arm.upper_pivot.global_position, trial_wrist, arm.forearm_pivot.global_position,
				chosen * arm.articulated_hand.anatomical_basis, arm.upper_arm_length, arm.forearm_length, left)
			if trial.feasible:
				wrist = trial_wrist; fit = trial
				break
	if not fit.feasible:
		# A changing wrist target may invalidate this limited world orientation.
		# Preserve the strict physical frame and report the unresolved path,
		# rather than detaching a socket or expanding its anatomical cone.
		state.last = wanted
		state.wrist = wrist
		state.shoulder = arm.upper_pivot.global_position
		arm.set_meta("live_support_frame", state)
		return {"feasible": false, "angle": angle, "allowance": allowance}
	var mount := Transform3D(chosen, wrist - chosen * arm.articulated_hand.wrist_socket)
	arm.upper_pivot.basis = arm.upper_pivot.basis.orthonormalized()
	arm.forearm_pivot.basis = arm.forearm_pivot.basis.orthonormalized()
	arm.solve_ik(mount.origin, fit.elbow, null, wrist)
	arm.articulated_hand.set_mesh_world_transform(mount)
	arm.articulated_hand.update_wrist_bridge(arm.fore_mesh.global_basis)
	state.last = chosen
	state.remaining = maxf(0.0, float(state.remaining) - _basis_angle(previous, chosen))
	state.wrist = wrist
	state.shoulder = arm.upper_pivot.global_position
	arm.set_meta("live_support_frame", state)
	return {"feasible": true, "angle": angle * weight, "allowance": allowance}

static func _basis_angle(first: Basis, second: Basis) -> float:
	var relative: Quaternion = first.get_rotation_quaternion().inverse() * second.get_rotation_quaternion()
	return 2.0 * atan2(Vector3(relative.x, relative.y, relative.z).length(), absf(relative.w))

static func _recover_support_clearance(player, arm, mount: Transform3D, left: bool) -> Dictionary:
	var state: Dictionary = arm.get_meta("live_support_frame", {})
	if state.is_empty(): return {"moved": false, "feasible": false}
	var wrist: Vector3 = mount * arm.articulated_hand.wrist_socket
	var previous: Vector3 = state.start_wrist + arm.upper_pivot.global_position - Vector3(state.start_shoulder)
	var points: PackedVector3Array = arm.articulated_hand.sampled_vertices()
	var inverse: Transform3D = player.paddle_node.global_transform.affine_inverse()
	for step in range(1, 13):
		var trial: Vector3 = wrist.lerp(previous, float(step) / 12.0)
		if trial.distance_to(wrist) > .075: continue
		var fit: Dictionary = solve(arm.upper_pivot.global_position, trial, arm.forearm_pivot.global_position,
			mount.basis * arm.articulated_hand.anatomical_basis, arm.upper_arm_length, arm.forearm_length, left)
		if not fit.feasible: continue
		var target := Transform3D(mount.basis, trial - mount.basis * arm.articulated_hand.wrist_socket)
		var local: Transform3D = inverse * target
		var clear := true
		for point in points:
			if PaddleClearance.distance_to_paddle_shape(local * point) < .001:
				clear = false; break
		if not clear: continue
		arm.upper_pivot.basis = arm.upper_pivot.basis.orthonormalized()
		arm.forearm_pivot.basis = arm.forearm_pivot.basis.orthonormalized()
		arm.solve_ik(target.origin, fit.elbow, null, trial)
		arm.articulated_hand.set_mesh_world_transform(target)
		arm.articulated_hand.update_wrist_bridge(arm.fore_mesh.global_basis)
		return {"moved": true, "feasible": true, "rollback_m": trial.distance_to(wrist)}
	return {"moved": false, "feasible": false}

static func _tilted_release_escape(player, arm, mount: Transform3D, left: bool, direction: float, points: PackedVector3Array) -> Dictionary:
	var state: Dictionary = arm.get_meta("live_support_frame", {})
	var allowance: float = float(state.get("remaining", 0.0))
	if allowance < .00001: return {"feasible": false}
	var paddle: Transform3D = player.paddle_node.global_transform
	var normal: Vector3 = paddle.basis.z.normalized() * direction
	var wrist: Vector3 = mount * arm.articulated_hand.wrist_socket + normal * .075
	var chosen: Basis = mount.basis.orthonormalized()
	for unused in range(5):
		var target := Transform3D(chosen, wrist - chosen * arm.articulated_hand.wrist_socket)
		var local: Transform3D = paddle.affine_inverse() * target
		var deepest := 0.0; var lever := Vector3.ZERO
		for point in points:
			var p: Vector3 = local * point
			if PaddleClearance.distance_to_paddle_shape(p) >= .001: continue
			var half_width: float = PaddleSize.HEAD_HALF_THICKNESS
			if absf(p.y - PaddleSize.HANDLE_CENTER_Y) <= PaddleSize.HANDLE_LENGTH * .5 and absf(p.x) <= PaddleSize.HANDLE_RADIUS:
				half_width = maxf(half_width, sqrt(maxf(0.0, PaddleSize.HANDLE_RADIUS * PaddleSize.HANDLE_RADIUS - p.x * p.x)))
			var deficit: float = .001 - (direction * p.z - half_width)
			if deficit > deepest: deepest = deficit; lever = target * point - wrist
		if deepest <= 0.0:
			var fit := solve(arm.upper_pivot.global_position, wrist, arm.forearm_pivot.global_position,
				chosen * arm.articulated_hand.anatomical_basis, arm.upper_arm_length, arm.forearm_length, left)
			if not fit.feasible: return {"feasible": false}
			var spent: float = _basis_angle(mount.basis.orthonormalized(), chosen)
			if spent > allowance: return {"feasible": false}
			arm.upper_pivot.basis = arm.upper_pivot.basis.orthonormalized()
			arm.forearm_pivot.basis = arm.forearm_pivot.basis.orthonormalized()
			arm.solve_ik(target.origin, fit.elbow, null, wrist)
			arm.articulated_hand.set_mesh_world_transform(target)
			arm.articulated_hand.update_wrist_bridge(arm.fore_mesh.global_basis)
			state.last = chosen; state.remaining = maxf(0.0, allowance - spent)
			return {"moved": true, "feasible": true, "normal_escape_m": .075, "turn_deg": rad_to_deg(spent)}
		var gradient: Vector3 = lever.cross(normal)
		if gradient.length() < .00001: return {"feasible": false}
		var turn: float = deepest / gradient.length() * 1.02
		chosen = (Basis(gradient.normalized(), turn) * chosen).orthonormalized()
		if _basis_angle(mount.basis.orthonormalized(), chosen) > allowance: return {"feasible": false}
	return {"feasible": false}
