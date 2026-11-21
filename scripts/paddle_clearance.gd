extends RefCounted
const WristReach = preload("res://scripts/paddle_wrist_reach.gd")



const PaddleDimensions = preload("res://scripts/paddle_dimensions.gd")
const MAX_CONTACT_SURFACE_GAP: = 0.005
const Path = preload("res://scripts/stroke_swing_path.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")

static func distance_to_head_shape(local_point: Vector3) -> float:
	var p: Vector3 = local_point - PaddleDimensions.HEAD_OFFSET
	var cap: float = Vector2(p.x, maxf(absf(p.y) - PaddleDimensions.HEAD_SPINE_HALF, 0.0)).length() - PaddleDimensions.HEAD_RADIUS
	var thickness: float = absf(p.z) - PaddleDimensions.HEAD_HALF_THICKNESS
	return Vector2(maxf(cap, 0.0), maxf(thickness, 0.0)).length() + minf(maxf(cap, thickness), 0.0)

static func distance_to_paddle_shape(local_point: Vector3) -> float:
	var cylinder: = Vector2(Vector2(local_point.x, local_point.z).length() - PaddleDimensions.HANDLE_RADIUS, absf(local_point.y - PaddleDimensions.HANDLE_CENTER_Y) - PaddleDimensions.HANDLE_LENGTH * 0.5)
	var handle: float = cylinder.max(Vector2.ZERO).length() + minf(maxf(cylinder.x, cylinder.y), 0.0)
	return minf(handle, distance_to_head_shape(local_point))

static func head_outline_error_bound() -> float:
	return PaddleDimensions.HEAD_RADIUS * (1.0 - cos(PI / (2.0 * PaddleDimensions.OUTLINE_ARC_STEPS)))



static func contact_surface_tolerance() -> float:
	return MAX_CONTACT_SURFACE_GAP - head_outline_error_bound()

static func sample_head_surface() -> Array[Vector3]:
	var points: Array[Vector3] = []
	var center: = Vector2(0.0, PaddleDimensions.HEAD_CENTER_Y)


	for outline_point in PaddleDimensions.head_outline():
		for fraction in [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]:
			var point: Vector2 = center.lerp(outline_point, fraction)
			for z in [ - PaddleDimensions.HEAD_HALF_THICKNESS, PaddleDimensions.HEAD_HALF_THICKNESS]:
				points.append(Vector3(point.x, point.y, z))
	for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
		for step in range(24):
			var angle: float = TAU * step / 24.0
			points.append(Vector3(cos(angle) * PaddleDimensions.HANDLE_RADIUS, fraction * PaddleDimensions.HANDLE_LENGTH, sin(angle) * PaddleDimensions.HANDLE_RADIUS))
	return points

static func signed_box_distance(point: Vector3, half_extents: Vector3) -> float:
	var q: Vector3 = point.abs() - half_extents
	return q.max(Vector3.ZERO).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)

static func closest_head_surface(point: Vector3, incoming: Vector3) -> Vector3:
	var xy: = Vector2(point.x, point.y - PaddleDimensions.HEAD_CENTER_Y)
	var spine: = Vector2(0.0, clampf(xy.y, - PaddleDimensions.HEAD_SPINE_HALF, PaddleDimensions.HEAD_SPINE_HALF))
	var radial: Vector2 = xy - spine
	var inside_xy: bool = radial.length() <= PaddleDimensions.HEAD_RADIUS
	var nearest_xy: Vector2 = xy if inside_xy else spine + radial.normalized() * PaddleDimensions.HEAD_RADIUS
	var z: float = clampf(point.z, - PaddleDimensions.HEAD_HALF_THICKNESS, PaddleDimensions.HEAD_HALF_THICKNESS)
	if inside_xy and absf(point.z) <= PaddleDimensions.HEAD_HALF_THICKNESS:

		z = - PaddleDimensions.HEAD_HALF_THICKNESS if incoming.z > 0.0 else PaddleDimensions.HEAD_HALF_THICKNESS
	return Vector3(nearest_xy.x, nearest_xy.y + PaddleDimensions.HEAD_CENTER_Y, z)



static func contact_surface_pose(player, pose: PostureDefinition, ball_position: Vector3, incoming_velocity: Vector3, fitted_shoulder: Vector3 = Vector3.INF) -> PostureDefinition:
	if pose == null: return null
	var paddle: Transform3D = Path.world_transform(player, pose)
	var local_ball: Vector3 = paddle.affine_inverse() * ball_position
	var local_velocity: Vector3 = paddle.basis.inverse() * incoming_velocity
	var surface: Vector3 = closest_head_surface(local_ball, local_velocity)
	var normal: Vector3 = local_ball - surface
	if distance_to_head_shape(local_ball) < 0.0 or normal.length_squared() < 1e-07:
		normal = Vector3(0, 0, -1 if local_velocity.z > 0.0 else 1)
		# A near-zero normal can occur just outside the opposite face. If the
		# normal switches to the incoming face, the surface point must switch
		# with it or seating is short by the full paddle thickness.
		surface.z = normal.z * PaddleDimensions.HEAD_HALF_THICKNESS
	else: normal = normal.normalized()
	var correction: Vector3 = ball_position - paddle * (surface + normal * 0.0375)
	# Surface seating is a world-space correction. Preserve the exact travel,
	# grip and pose metadata, then invert those overlays once when encoding it.
	paddle.origin += correction
	var candidate: PostureDefinition = preload("res://scripts/paddle_pose_encoding.gd").encode(player, pose, paddle)
	var tx: Transform3D = Path.world_transform(player, candidate)
	var shoulder: Vector3 = fitted_shoulder if fitted_shoulder.is_finite() else Body.shoulder_world(player, candidate)
	if not WristReach.fits(tx, candidate, shoulder, WristReach.link_budget(player, candidate)): return null
	return candidate
