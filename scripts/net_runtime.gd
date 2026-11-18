extends StaticBody3D

signal ball_hit_post(point: Vector3)
var _post_fault_flight := -1


const Profile = preload("res://scripts/net_profile.gd")
const MAX_IMPACTS: = 4
const IMPACT_LIFETIME: = 2.0
var _materials: Array[ShaderMaterial] = []
var _impacts: Array[Vector4] = []
var _ball: RigidBody3D
var _last_velocity: = Vector3.ZERO
var _last_flight: int = -1
var _cooldown: = 0.0
var impact_count: = 0
var _sweep_previous: = Vector3.INF
var _sweep_velocity: = Vector3.ZERO
var _sweep_flight: = -1
var _sweep_shape: = SphereShape3D.new()

func bind_ball(ball: RigidBody3D) -> void :
	if is_instance_valid(_ball):
		if _ball.body_shape_entered.is_connected(_on_ball_shape_entered):
			_ball.body_shape_entered.disconnect(_on_ball_shape_entered)
		if _ball.body_entered.is_connected(_on_ball_body_entered):
			_ball.body_entered.disconnect(_on_ball_body_entered)
		if "_net_contact_guard" in _ball and _ball._net_contact_guard == self:
			_ball._net_contact_guard = null
	_ball = ball
	_post_fault_flight = -1
	clear_impacts()
	if not is_instance_valid(ball): return



	if "_net_contact_guard" in ball: ball._net_contact_guard = self
	_sweep_shape.radius = 0.0375
	_sweep_previous = Vector3.INF
	_last_velocity = ball.linear_velocity
	_last_flight = int(ball.get("flight_id")) if "flight_id" in ball else -1
	_sweep_flight = _last_flight
	_sweep_previous = ball.global_position
	_sweep_velocity = ball.linear_velocity
	ball.body_entered.connect(_on_ball_body_entered)
	ball.body_shape_entered.connect(_on_ball_shape_entered)

func register_material(material: ShaderMaterial) -> void :
	_materials.append(material)
	_upload_impacts()

func _physics_process(delta: float) -> void :
	if is_instance_valid(_ball):
		if _ball.has_method("is_time_frozen") and _ball.is_time_frozen(): return
		var flight: int = int(_ball.get("flight_id")) if "flight_id" in _ball else _last_flight

		if flight != _last_flight:
			clear_impacts()
			_last_flight = flight
			_sweep_flight = flight
			_sweep_previous = _ball.global_position
			_sweep_velocity = _ball.linear_velocity
		_last_velocity = _ball.linear_velocity
	advance_impacts(delta)

func _on_ball_body_entered(body: Node) -> void :
	if _has_live_contact_owner(): return
	if body != self or not is_instance_valid(_ball) or _cooldown > 0.0: return
	var incoming: Vector3 = _last_velocity
	if incoming.length_squared() < 0.1: incoming = _ball.linear_velocity
	add_impact(to_local(_ball.global_position), incoming)
	_cooldown = 0.075

func _on_ball_shape_entered(_body_rid: RID, body: Node, body_shape_index: int, _local_shape_index: int) -> void:
	if _has_live_contact_owner(): return
	if body != self or not is_instance_valid(_ball): return
	var owner = shape_owner_get_owner(shape_find_owner(body_shape_index))
	if owner != null and String(owner.name).ends_with("PostCollision"):
		_notify_post(_ball.global_position)

func _notify_post(point: Vector3, authoritative: bool = false) -> void:
	if _has_live_contact_owner() and not authoritative: return
	var flight: int = int(_ball.get("flight_id")) if "flight_id" in _ball else _last_flight
	if flight == _post_fault_flight: return
	_post_fault_flight = flight
	ball_hit_post.emit(point)

func add_impact(point: Vector3, incoming: Vector3) -> void :
	if not point.is_finite() or not incoming.is_finite(): return
	if not Profile.spans_x(point.x, 0.05): return
	var strength: float = clampf(absf(incoming.z) * 0.004, 0.008, 0.075)
	var direction: float = signf(incoming.z)
	if is_zero_approx(direction): direction = 1.0
	if _impacts.size() == MAX_IMPACTS: _impacts.pop_front()
	_impacts.append(Vector4(point.x, clampf(point.y, Profile.FLOOR_Y, Profile.top_y_at(point.x)), 0.0, strength * direction))
	impact_count += 1
	_upload_impacts()

func advance_impacts(delta: float) -> void :
	_cooldown = maxf(0.0, _cooldown - delta)
	if _impacts.is_empty(): return
	for i in range(_impacts.size() - 1, -1, -1):
		_impacts[i].z += maxf(0.0, delta)
		if _impacts[i].z >= IMPACT_LIFETIME: _impacts.remove_at(i)
	_upload_impacts()

func clear_impacts() -> void :
	_impacts.clear()
	_cooldown = 0.0
	_upload_impacts()

func _upload_impacts() -> void :
	var packed: = PackedVector4Array()
	for i in range(MAX_IMPACTS):
		packed.append(_impacts[i] if i < _impacts.size() else Vector4.ZERO)
	for material in _materials: material.set_shader_parameter("impacts", packed)

func displacement_at(point: Vector3) -> float:

	var v: float = clampf((point.y - Profile.FLOOR_Y) / Profile.height_at(point.x), 0.0, 1.0)
	var anchor: float = sin(v * PI) * maxf(0.0, 1.0 - pow(absf(point.x) / Profile.HALF_SPAN, 8.0))
	var displacement: = 0.0
	for hit in _impacts:
		var distance: float = Vector2((point.x - hit.x) * 0.82, (point.y - hit.y) * 1.4).length()
		displacement += hit.w * exp( - hit.z * 3.4) * exp( - distance * 3.8) * sin(hit.z * 22.0 - distance * 9.0)
	return clampf(displacement * anchor, -0.045, 0.045)


func resolve_swept_contact(state: PhysicsDirectBodyState3D) -> void :
	if _has_live_contact_owner():
		reset_sweep_observation(state.transform.origin, state.linear_velocity, int(_ball.flight_id))
		return




	var current: Vector3 = state.transform.origin
	var flight: int = int(_ball.get("flight_id")) if "flight_id" in _ball else -1
	var previous: Vector3 = _sweep_previous
	var velocity_before: Vector3 = _sweep_velocity
	_sweep_previous = current
	_sweep_velocity = state.linear_velocity
	if not previous.is_finite() or flight != _sweep_flight:
		_sweep_flight = flight
		return
	var motion: Vector3 = current - previous
	if motion.length() > 1.0: return
	# Native convex posts and this swept guard share exact rendered geometry.
	# Unlike fabric, a post hit need not cross z=0 in this step.
	var post: Dictionary = Profile.post_sweep(previous, current, _sweep_shape.radius)
	if post.get("hit", false):
		_notify_post(post.point)
		var incoming: Vector3 = velocity_before if velocity_before.length_squared() >= 0.01 else state.linear_velocity
		var normal: Vector3 = post.normal
		var toward: float = incoming.dot(normal)
		if toward < 0.0 and state.linear_velocity.dot(normal) < 0.0:
			var adjusted: Transform3D = state.transform
			adjusted.origin = post.point + normal * 0.001
			state.transform = adjusted
			state.linear_velocity = (incoming - normal * toward) * 0.86 - normal * toward * 0.32
			_sweep_previous = adjusted.origin
			_sweep_velocity = state.linear_velocity
			return
	if previous.z * current.z >= 0.0:



		if absf(current.z) < Profile.THICKNESS * 0.5 + _sweep_shape.radius + 0.002:
			_sweep_previous = previous
			_sweep_velocity = velocity_before
		return
	if velocity_before.length_squared() < 0.01: velocity_before = state.linear_velocity
	if velocity_before.z * state.linear_velocity.z <= 0.0: return
	var fraction: float = clampf( - previous.z / motion.z, 0.0, 1.0)
	var crossing: Vector3 = previous.lerp(current, fraction)
	if not Profile.spans_x(crossing.x, _sweep_shape.radius): return
	if crossing.y >= Profile.clear_y_at(crossing.x, _sweep_shape.radius): return

	if current.y >= Profile.clear_y_at(current.x, _sweep_shape.radius) and state.linear_velocity.y > 0.0: return
	var query: = PhysicsShapeQueryParameters3D.new()
	query.shape = _sweep_shape
	query.transform = Transform3D(Basis.IDENTITY, previous)
	query.motion = motion
	query.collision_mask = collision_layer
	query.margin = 0.0001
	var cast: PackedFloat32Array = state.get_space_state().cast_motion(query)
	if cast.is_empty() or cast[0] >= 1.0: return
	var contact: Vector3 = previous + motion * cast[0]
	var direction: float = signf(motion.z)
	var nearest: Vector3 = Vector3(clampf(contact.x, - Profile.HALF_SPAN, Profile.HALF_SPAN), 
		clampf(contact.y, Profile.FLOOR_Y, Profile.top_y_at(contact.x)), - direction * Profile.THICKNESS * 0.5)
	var normal: Vector3 = (contact - nearest).normalized()
	if normal.length_squared() < 0.5: normal = Vector3(0, 0, - direction)
	var toward: float = velocity_before.dot(normal)
	if toward >= 0.0: return
	var transform_now: Transform3D = state.transform
	transform_now.origin = contact + normal * 0.001
	state.transform = transform_now
	state.linear_velocity = (velocity_before - normal * toward) * 0.86 - normal * toward * 0.32
	_sweep_previous = transform_now.origin
	_sweep_velocity = state.linear_velocity
	if _cooldown <= 0.0:
		add_impact(to_local(nearest), velocity_before)
		_cooldown = 0.075

func _has_live_contact_owner() -> bool:
	return is_instance_valid(_ball) and _ball.has_method("owns_live_net_contact") and _ball.owns_live_net_contact()

func reset_sweep_observation(point: Vector3, velocity: Vector3, flight: int) -> void:
	_sweep_previous = point; _sweep_velocity = velocity; _sweep_flight = flight

func apply_authoritative_contact(event: Dictionary) -> bool:
	if not _has_live_contact_owner() or event.get("type", "") not in ["net", "post"]: return false
	add_impact(to_local(event.point), event.incoming)
	_cooldown = 0.075
	if _ball.audio_synth != null: _ball.audio_synth.on_body_entered(self, event.point.y, event.incoming)
	if event.type == "post": _notify_post(event.point, true)
	return true
