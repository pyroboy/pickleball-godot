extends RigidBody3D
class_name Ball


const BALL_MASS: = 0.024
const FLIGHT_CEILING_Y: float = 5.0
const BALL_RADIUS: = 0.0375
const GRAVITY_SCALE: = 1.0


const MAX_SPEED: = 20.0
const SERVE_SPEED: = 8.0
const BOUNCE_COR: = 0.64
const FLOOR_Y: = 0.075





static func get_effective_gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity")) * GRAVITY_SCALE





static func cor_for_impact_speed(v_impact: float) -> float:
	return lerpf(0.78, 0.56, clampf((v_impact - 3.0) / 15.0, 0.0, 1.0))








const AIR_DENSITY: = 1.225
const DRAG_COEFFICIENT: = 0.47





const MAGNUS_COEFFICIENT: = 0.0003



const SPIN_DAMPING_HALFLIFE: = 150.0




const SPIN_BOUNCE_TRANSFER: = 0.25
const SPIN_BOUNCE_DECAY: = 0.7



const AERO_EFFECT_SCALE: = 0.79

const SHOW_SPIN_DEBUG: = false
var spin_debug_visible: = SHOW_SPIN_DEBUG


var _contact_paddle: PhysicsBody3D = null
var _contact_paddle_grace: float = 0.0
var _authoritative_paddles: Array[PhysicsBody3D] = []
var wall_practice_active: = false
var wall_return_ready: = false
var is_in_play: bool = false:
	set(value):
		is_in_play = value
		_refresh_scene_net_ownership()
const ActorIdentity = preload("res://scripts/contact_actor_identity.gd")
var actor_registry = null
var last_hit_by: int = -1 # explicit legacy team alias
var last_hit_actor_id: int = -1
var last_hit_team_id: int = -1
var last_hit_court_side: int = -1
var serve_court_side: int = 0
var flight_id: int = 0
var serve_team: int = 0
var can_register_floor_bounce: bool = true
var was_above_bounce_height: bool = true
var bounce_count: int = 0


var serving_side_bounced: bool = false
var receiving_side_bounced: bool = false
var both_bounces_complete: bool = false
var ball_bounced_since_last_hit: bool = false
var bounces_since_last_hit: int = 0
var was_volley: bool = false

signal hit_by_paddle(player_num: int) # legacy TEAM notification
signal actor_hit_paddle(actor_id: int, team_id: int, court_side: int)
signal actor_hit_body(actor_id: int, team_id: int, court_side: int)
signal bounced(position: Vector3)


signal hit_player_body(player_num: int)


var audio_synth: Node = null


var _spin_axis_node: MeshInstance3D = null
var _equator_marker: MeshInstance3D = null
var _equator_marker_2: MeshInstance3D = null

func _ready() -> void :
	var synth: = preload("res://scripts/ball_audio_synth.gd").new()
	synth.name = "BallAudioSynth"
	add_child(synth)
	audio_synth = synth


	_setup_ball()


	hit_by_paddle.connect(_on_paddle_hit)
	bounced.connect(_on_floor_bounce)
	body_entered.connect(_on_body_entered)

func _setup_ball() -> void :
	name = "Ball"
	collision_layer = 1




	collision_mask = 7

	mass = BALL_MASS
	gravity_scale = GRAVITY_SCALE

	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 1.0
	physics_material_override.friction = 0.25

	contact_monitor = true
	max_contacts_reported = 4

	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = BALL_RADIUS
	col.shape = shape
	add_child(col)

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = BALL_RADIUS
	mesh.height = BALL_RADIUS * 2
	mesh_inst.mesh = mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0)
	mat.roughness = 0.3
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	if spin_debug_visible:
		_setup_spin_debug_visuals()

	reset()









func _setup_spin_debug_visuals() -> void :


	_spin_axis_node = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.008
	cyl.bottom_radius = 0.008
	cyl.height = BALL_RADIUS * 3.0
	_spin_axis_node.mesh = cyl
	var axis_mat: StandardMaterial3D = StandardMaterial3D.new()
	axis_mat.albedo_color = Color(0.0, 1.0, 0.3)
	axis_mat.emission_enabled = true
	axis_mat.emission = Color(0.0, 1.0, 0.3)
	axis_mat.emission_energy_multiplier = 1.5
	axis_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spin_axis_node.material_override = axis_mat
	add_child(_spin_axis_node)
	_spin_axis_node.top_level = true




	_equator_marker = MeshInstance3D.new()
	var m1: SphereMesh = SphereMesh.new()
	m1.radius = 0.022
	m1.height = 0.044
	_equator_marker.mesh = m1
	var emat: StandardMaterial3D = StandardMaterial3D.new()
	emat.albedo_color = Color(1.0, 0.0, 0.0)
	emat.emission_enabled = true
	emat.emission = Color(1.0, 0.0, 0.0)
	emat.emission_energy_multiplier = 1.2
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_equator_marker.material_override = emat
	_equator_marker.position = Vector3(BALL_RADIUS * 0.95, 0, 0)
	add_child(_equator_marker)

	_equator_marker_2 = MeshInstance3D.new()
	_equator_marker_2.mesh = m1
	var emat2: StandardMaterial3D = StandardMaterial3D.new()
	emat2.albedo_color = Color(0.0, 0.4, 1.0)
	emat2.emission_enabled = true
	emat2.emission = Color(0.0, 0.4, 1.0)
	emat2.emission_energy_multiplier = 1.2
	emat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_equator_marker_2.material_override = emat2
	_equator_marker_2.position = Vector3(0, 0, BALL_RADIUS * 0.95)
	add_child(_equator_marker_2)




func _update_spin_visualizer() -> void :
	if _spin_axis_node == null:
		return
	var omega: Vector3 = angular_velocity
	var omega_mag: float = omega.length()
	if omega_mag < 0.1:
		_spin_axis_node.visible = false
		return
	_spin_axis_node.visible = true
	_spin_axis_node.global_position = global_position

	var omega_dir: Vector3 = omega / omega_mag
	var up: Vector3 = Vector3.UP
	if absf(omega_dir.dot(up)) > 0.99:
		up = Vector3.RIGHT
	_spin_axis_node.look_at(global_position + omega_dir, up)
	_spin_axis_node.rotate_object_local(Vector3.RIGHT, PI * 0.5)

	var scale_len: float = clampf(omega_mag / 25.0, 0.3, 2.0)
	_spin_axis_node.scale = Vector3(1.0, scale_len, 1.0)

	var h_vel: Vector3 = Vector3(linear_velocity.x, 0, linear_velocity.z)
	var tier: Color = Color(0.0, 1.0, 0.3)
	if h_vel.length() > 0.5:
		var roll_axis: Vector3 = Vector3.UP.cross(h_vel.normalized())
		var roll_c: float = omega.dot(roll_axis)
		var side_c: float = absf(omega.dot(Vector3.UP))
		var roll_abs: float = absf(roll_c)
		if side_c > roll_abs:
			tier = Color(0.0, 0.8, 1.0)
		elif roll_c > 0:
			tier = Color(0.0, 1.0, 0.3)
		else:
			tier = Color(1.0, 0.2, 0.2)
	var axis_mat: StandardMaterial3D = _spin_axis_node.material_override as StandardMaterial3D
	if axis_mat:
		axis_mat.albedo_color = tier
		axis_mat.emission = tier



func _on_paddle_hit(_player_num: int) -> void :
	if audio_synth:
		audio_synth.on_paddle_hit(linear_velocity.length())

func _on_floor_bounce(_position: Vector3) -> void :
	if audio_synth:
		audio_synth.on_floor_bounce(linear_velocity.length())

func _on_body_entered(body: Node) -> void :
	if body == _scene_net_body and owns_live_net_contact(): return
	if audio_synth:
		audio_synth.on_body_entered(body, global_position.y, linear_velocity)




	if body is CharacterBody3D and body.has_method("get_player_num"):
		actor_hit_body.emit(ActorIdentity.actor_id(body), ActorIdentity.team_id(body), ActorIdentity.court_side(body))
		hit_player_body.emit(body.get_player_num())

var _net_contact_guard: Node = null:
	set(value):
		_net_contact_guard = value
		_refresh_scene_net_ownership()
var _time_frozen: bool = false
var _frozen_position: Vector3 = Vector3.ZERO
var _frozen_velocity: Vector3 = Vector3.ZERO
var _frozen_omega: Vector3 = Vector3.ZERO
var _frozen_basis: Basis = Basis.IDENTITY

func set_time_frozen(frozen: bool) -> void :
	_time_frozen = frozen

func set_frozen_state(pos: Vector3, vel: Vector3, omega: Vector3) -> void :
	_frozen_position = pos
	_frozen_velocity = vel
	_frozen_omega = omega
	_frozen_basis = transform.basis

func is_time_frozen() -> bool:
	return _time_frozen

var _native_interval_sample: Dictionary = {}
var _native_interval_serial := 0
func native_interval_sample() -> Dictionary:
	return _native_interval_sample.duplicate(true)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void :
	_native_interval_serial += 1
	_native_interval_sample = {"serial": _native_interval_serial, "frame": Engine.get_physics_frames(),
		"seconds": float(state.step), "flight": flight_id, "frozen": _time_frozen,
		"native_position": state.transform.origin, "native_velocity": state.linear_velocity}
	if _time_frozen:
		state.transform = Transform3D(_frozen_basis, _frozen_position)
		state.linear_velocity = _frozen_velocity
		state.angular_velocity = _frozen_omega
		return
	_refresh_scene_net_ownership()
	if is_instance_valid(_net_contact_guard):
		_net_contact_guard.resolve_swept_contact(state)



var time_since_last_bounce: float = -1.0
var _consumed_bounce_age: Dictionary = {}
func matches_consumed_motion(receipt: Dictionary) -> bool:
	if global_position != receipt.position or bounce_count != int(receipt.bounces): return false
	if not _prepared_aero.is_empty() and int(_prepared_aero.frame) == Engine.get_physics_frames() and int(_prepared_aero.flight) == flight_id:
		return _prepared_aero.position == receipt.position and _prepared_aero.before_velocity == receipt.velocity and _prepared_aero.before_omega == receipt.omega and linear_velocity == _prepared_aero.after_velocity and angular_velocity == _prepared_aero.after_omega and bounce_count == int(_prepared_aero.bounce_count)
	return linear_velocity == receipt.velocity and angular_velocity == receipt.omega

func mark_bounce_age_consumed() -> void:
	_consumed_bounce_age = {"frame": Engine.get_physics_frames(), "flight": flight_id}
func _clear_consumed_bounce_age() -> void:
	_consumed_bounce_age.clear()
func _bounce_age_is_consumed() -> bool:
	return int(_consumed_bounce_age.get("frame", -1)) == Engine.get_physics_frames() and int(_consumed_bounce_age.get("flight", -1)) == flight_id
var receiver_entire_ball_crossed: bool = false
var receiver_side_bounced: bool = false
var receiver_returned_across_net: bool = false

func _physics_process(_delta: float) -> void :
	if _time_frozen:
		return
	var bounce_age_before: float = time_since_last_bounce
	var receiver_before: Array = receiver_path_state()
	observe_receiver_position(global_position)
	if is_in_play and time_since_last_bounce >= 0.0 and not _bounce_age_is_consumed():
		time_since_last_bounce += maxf(0.0, _delta)
	_update_paddle_clearance(_delta)
	if audio_synth:
		audio_synth.update_cooldown(_delta)
	if spin_debug_visible:
		_update_spin_visualizer()




	_prepared_aero = {"frame": Engine.get_physics_frames(), "flight": flight_id, "delta": _delta,
		"before_velocity": linear_velocity, "before_omega": angular_velocity, "position": global_position, "bounce_count": bounce_count}
	_apply_aero_impulse(_delta)
	_prepared_aero["after_velocity"] = linear_velocity
	_prepared_aero["after_omega"] = angular_velocity

	# Every live interval is settled after all actor endpoints publish. The
	# next kick remains protected; completed native time is a separate clock.
	if is_instance_valid(_scene_interval_owner) and _scene_interval_owner.should_defer_scene_boundary():
		receiver_entire_ball_crossed = receiver_before[0]
		receiver_side_bounced = receiver_before[1]
		receiver_returned_across_net = receiver_before[2]
		time_since_last_bounce = bounce_age_before
		_deferred_scene = {"bounce_age_before": bounce_age_before, "frame": Engine.get_physics_frames(),
			"flight": flight_id, "delta": _delta, "kind": "ordered_live_interval", "receiver_before": receiver_before,
			"native_sample": native_interval_sample()}
		return

	if global_position.y > FLIGHT_CEILING_Y:
		global_position.y = FLIGHT_CEILING_Y
		linear_velocity.y = min(linear_velocity.y, 0)


	var floor_rest_y: float = FLOOR_Y + BALL_RADIUS
	if global_position.y < floor_rest_y and linear_velocity.y < 0:
		global_position.y = floor_rest_y




		if AERO_EFFECT_SCALE > 0.0:
			var tang_v: Vector3 = Vector3(linear_velocity.x, 0, linear_velocity.z)
			var spin_surface: Vector3 = Vector3(
				- angular_velocity.z * BALL_RADIUS, 
				0, 
				angular_velocity.x * BALL_RADIUS
			)
			var new_tang: Vector3 = tang_v - SPIN_BOUNCE_TRANSFER * (tang_v - spin_surface) * AERO_EFFECT_SCALE
			linear_velocity.x = new_tang.x
			linear_velocity.z = new_tang.z
			angular_velocity *= lerpf(1.0, SPIN_BOUNCE_DECAY, AERO_EFFECT_SCALE)
		linear_velocity.y = abs(linear_velocity.y) * cor_for_impact_speed(abs(linear_velocity.y))

		if can_register_floor_bounce:
			bounce_count += 1
			bounced.emit(Vector3(global_position.x, 0.082, global_position.z))
			can_register_floor_bounce = false






	if global_position.y > floor_rest_y + 0.015:
		can_register_floor_bounce = true



func receiver_path_state() -> Array:
	return [receiver_entire_ball_crossed, receiver_side_bounced, receiver_returned_across_net]

func observe_receiver_position(point: Vector3) -> void:
	if is_in_play and get_last_hit_court_side() in [0, 1]:
		var receiver_side: float = -1.0 if get_last_hit_court_side() == 0 else 1.0
		# Only a consumed physical point can establish either crossing.
		if point.z * receiver_side >= BALL_RADIUS: receiver_entire_ball_crossed = true
		if receiver_entire_ball_crossed and receiver_side_bounced and point.z * receiver_side <= -BALL_RADIUS:
			receiver_returned_across_net = true

var _scene_interval_owner: Node = null
var _scene_net_body: PhysicsBody3D = null
var _scene_added_net_exception := false
var _deferred_scene: Dictionary = {}
func set_scene_interval_owner(owner: Node) -> void:
	_scene_interval_owner = owner
	_deferred_scene.clear()
	_refresh_scene_net_ownership()

func owns_live_net_contact() -> bool:
	return is_instance_valid(_scene_net_body) and is_instance_valid(_scene_interval_owner) and _scene_interval_owner.owns_live_scene_motion()

func refresh_scene_contact_owner() -> void:
	_refresh_scene_net_ownership()
	if not owns_live_net_contact(): _clear_consumed_bounce_age()

func _refresh_scene_net_ownership() -> void:
	var target: PhysicsBody3D = null
	if is_instance_valid(_scene_interval_owner) and is_instance_valid(_net_contact_guard) and _scene_interval_owner.owns_live_scene_motion():
		if _net_contact_guard is PhysicsBody3D: target = _net_contact_guard
		elif _net_contact_guard.has_method("ordered_scene_body"): target = _net_contact_guard.ordered_scene_body()
	if target == _scene_net_body: return
	if is_instance_valid(_scene_net_body) and _scene_added_net_exception: remove_collision_exception_with(_scene_net_body)
	_scene_net_body = target; _scene_added_net_exception = false
	if is_instance_valid(target) and not get_collision_exceptions().has(target):
		add_collision_exception_with(target); _scene_added_net_exception = true
	if is_instance_valid(_net_contact_guard):
		_net_contact_guard.reset_sweep_observation(global_position, linear_velocity, flight_id)

func deferred_scene_interval() -> Dictionary:
	return _deferred_scene.duplicate()

func finish_clear_live_interval(ticket: Dictionary, seconds: float) -> bool:
	if _deferred_scene != ticket or not is_in_play: return false
	# No rewind or kick recomputation on a proven clear native path.
	observe_receiver_position(global_position)
	if time_since_last_bounce >= 0.0: time_since_last_bounce += seconds
	if global_position.y > FLOOR_Y + BALL_RADIUS + 0.015: can_register_floor_bounce = true
	_deferred_scene.clear()
	return true

func clear_dead_scene_interval() -> void:
	if not is_in_play: _deferred_scene.clear()

var _prepared_aero: Dictionary = {}
var prepared_aero_rewinds := 0
var prepared_aero_reapplications := 0
var _aero_claim_serial := 0
var _open_aero_claim := -1

func _apply_aero_impulse(_delta: float) -> void:
	var speed: float = linear_velocity.length()
	if speed > 0.1 and AERO_EFFECT_SCALE > 0.0:
		var cross_section: float = PI * BALL_RADIUS * BALL_RADIUS
		var drag_force_mag: float = 0.5 * AIR_DENSITY * DRAG_COEFFICIENT * cross_section * speed * speed
		var drag_accel: Vector3 = - linear_velocity.normalized() * (drag_force_mag / mass)
		linear_velocity += drag_accel * _delta * AERO_EFFECT_SCALE









	if angular_velocity.length_squared() > 0.01 and speed > 0.5 and AERO_EFFECT_SCALE > 0.0:
		var magnus_force: Vector3 = MAGNUS_COEFFICIENT * angular_velocity.cross(linear_velocity)
		linear_velocity += (magnus_force / mass) * _delta * AERO_EFFECT_SCALE



	if angular_velocity.length_squared() > 0.001 and AERO_EFFECT_SCALE > 0.0:
		var spin_decay: float = exp( - _delta * 0.693 / (SPIN_DAMPING_HALFLIFE * AERO_EFFECT_SCALE))
		angular_velocity *= spin_decay

	if linear_velocity.length() > MAX_SPEED:
		linear_velocity = linear_velocity.normalized() * MAX_SPEED


func cancel_prepared_aero() -> void:
	_clear_consumed_bounce_age()
	# Explicit reset/teleport supplies a new state; its old force clock cannot carry across.
	_prepared_aero.clear(); _open_aero_claim = -1; _deferred_scene.clear()

func inspect_prepared_aero() -> Dictionary:
	if _prepared_aero.is_empty() or int(_prepared_aero.frame) != Engine.get_physics_frames() or int(_prepared_aero.flight) != flight_id:
		return {"valid": false, "reason": "prepared_aero_missing_or_stale"}
	if linear_velocity != _prepared_aero.after_velocity or angular_velocity != _prepared_aero.after_omega or bounce_count != int(_prepared_aero.bounce_count) or global_position != _prepared_aero.position:
		return {"valid": false, "reason": "prepared_aero_state_changed"}
	return {"valid": true, "before_velocity": _prepared_aero.before_velocity, "before_omega": _prepared_aero.before_omega, "delta": _prepared_aero.delta}

func take_prepared_aero() -> Dictionary:
	# Native integration has completed the observed interval. This script's
	# aero update prepares the NEXT interval, so a late authoritative contact
	# must replace that preparation using its corrected outgoing velocity.
	if _prepared_aero.is_empty() or int(_prepared_aero.frame) != Engine.get_physics_frames() or int(_prepared_aero.flight) != flight_id:
		return {"taken": false, "blocked": false}
	if linear_velocity != _prepared_aero.after_velocity or angular_velocity != _prepared_aero.after_omega or bounce_count != int(_prepared_aero.bounce_count) or global_position != _prepared_aero.position:
		return {"taken": false, "blocked": true, "reason": "prepared_aero_state_changed"}
	var token: Dictionary = _prepared_aero.duplicate(true)
	_prepared_aero.clear(); _deferred_scene.clear()
	linear_velocity = token.before_velocity; angular_velocity = token.before_omega
	prepared_aero_rewinds += 1
	_aero_claim_serial += 1; _open_aero_claim = _aero_claim_serial
	token["claim"] = _open_aero_claim
	token["taken"] = true; token["blocked"] = false
	return token

func reapply_prepared_aero(token: Dictionary) -> void:
	if not token.get("taken", false) or int(token.frame) != Engine.get_physics_frames() or int(token.get("claim", -2)) != _open_aero_claim: return
	_open_aero_claim = -1
	_apply_aero_impulse(float(token.delta))
	prepared_aero_reapplications += 1

func set_actor_registry(registry) -> void:
	actor_registry = registry

func _assign_actual_actor(actor) -> bool:
	if not ActorIdentity.valid(actor): return false
	if is_instance_valid(actor_registry) and ActorIdentity.find_actor(actor_registry, ActorIdentity.actor_id(actor)) != actor: return false
	last_hit_actor_id = ActorIdentity.actor_id(actor)
	last_hit_team_id = ActorIdentity.team_id(actor)
	last_hit_court_side = ActorIdentity.court_side(actor)
	last_hit_by = last_hit_team_id
	return true

func _assign_legacy_team(team: int) -> bool:
	if team not in [0, 1]: return false
	if is_instance_valid(actor_registry):
		var actor = ActorIdentity.unique_team_actor(actor_registry, team)
		if actor == null: return false
		return _assign_actual_actor(actor)
	last_hit_by = team; last_hit_team_id = team
	last_hit_actor_id = team; last_hit_court_side = team
	return true

func get_last_hit_actor_id() -> int:
	if last_hit_team_id == last_hit_by and last_hit_actor_id >= 0: return last_hit_actor_id
	# Direct legacy fixture writes retain singles compatibility only.
	if not is_instance_valid(actor_registry): return last_hit_by
	return ActorIdentity.actor_id(ActorIdentity.unique_team_actor(actor_registry, last_hit_by))

func get_last_hit_team_id() -> int:
	return last_hit_by

func get_last_hit_court_side() -> int:
	if last_hit_team_id == last_hit_by and last_hit_court_side in [0, 1]: return last_hit_court_side
	if not is_instance_valid(actor_registry): return last_hit_by
	return ActorIdentity.team_side(actor_registry, last_hit_by)

func set_actor_serve_identity(actor) -> bool:
	## Call only after actual serve admission, before serve_launched.
	if not _assign_actual_actor(actor): return false
	serve_team = last_hit_team_id; serve_court_side = last_hit_court_side
	return true

func set_serve_actor(actor) -> bool:
	return set_actor_serve_identity(actor)

func serve_by_actor(actor, direction: Vector3) -> bool:
	if not set_actor_serve_identity(actor): return false
	_start_serve(last_hit_team_id, direction)
	return true

func serve(team: int, direction: Vector3) -> void:
	if not _assign_legacy_team(team): return
	serve_court_side = get_last_hit_court_side()
	_start_serve(team, direction)

func _start_serve(team: int, direction: Vector3) -> void:
	begin_contact_context()
	receiver_entire_ball_crossed = false
	receiver_side_bounced = false
	receiver_returned_across_net = false
	flight_id += 1
	serve_team = team
	is_in_play = true
	last_hit_by = team

	linear_velocity = direction.normalized() * SERVE_SPEED




func reset() -> void :
	begin_contact_context()
	cancel_prepared_aero()
	receiver_entire_ball_crossed = false
	receiver_side_bounced = false
	receiver_returned_across_net = false
	wall_return_ready = false
	_clear_paddle_collision_exception()
	flight_id += 1
	global_position = Vector3(-1.5, 1.5, -4)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	is_in_play = false
	last_hit_by = -1
	last_hit_actor_id = -1; last_hit_team_id = -1; last_hit_court_side = -1
	can_register_floor_bounce = true
	was_above_bounce_height = true
	bounce_count = 0

var _contact_callback_epoch := 0

func begin_contact_context() -> void:
	# Explicit context replacement, not an ordinary hit or scored fault.
	_contact_callback_epoch += 1

func contact_callback_epoch() -> int:
	return _contact_callback_epoch

func paddle_contact_context() -> Dictionary:
	return {"epoch": _contact_callback_epoch, "flight": flight_id, "actor": last_hit_actor_id,
		"team": last_hit_team_id, "side": last_hit_court_side, "legacy_team": last_hit_by}

func paddle_contact_is_current(context: Dictionary) -> bool:
	return not is_queued_for_deletion() and not context.is_empty() and context == paddle_contact_context()

func hit_by_actor(actor) -> bool:
	## Caller supplies an admitted physical actor, never a team guess.
	if not _assign_actual_actor(actor): return false
	return _record_paddle_contact(last_hit_team_id)

func hit_by_player(player_num: int) -> bool:
	if not _assign_legacy_team(player_num): return false
	return _record_paddle_contact(player_num)

func _record_paddle_contact(player_num: int) -> bool:
	_clear_consumed_bounce_age()
	receiver_entire_ball_crossed = false
	receiver_side_bounced = false
	receiver_returned_across_net = false
	time_since_last_bounce = -1.0
	flight_id += 1
	was_volley = not ball_bounced_since_last_hit
	last_hit_by = player_num
	ball_bounced_since_last_hit = false
	bounces_since_last_hit = 0
	var event: Dictionary = paddle_contact_context()
	hit_by_paddle.emit(player_num)
	if not paddle_contact_is_current(event): return false
	actor_hit_paddle.emit(int(event.actor), int(event.team), int(event.side))
	return paddle_contact_is_current(event)

func get_last_hit_by() -> int:
	return last_hit_by

func get_bounce_count() -> int:
	return bounce_count

func record_bounce_side(bounce_z: float) -> void :
	time_since_last_bounce = 0.0
	if get_last_hit_court_side() in [0, 1] and bounce_z * (-1.0 if get_last_hit_court_side() == 0 else 1.0) >= BALL_RADIUS:
		receiver_entire_ball_crossed = true
		receiver_side_bounced = true
	ball_bounced_since_last_hit = true
	bounces_since_last_hit += 1
	var is_positive_z: bool = bounce_z > 0.0
	if (serve_court_side == 0 and is_positive_z) or (serve_court_side == 1 and not is_positive_z):
		serving_side_bounced = true
	else:
		receiving_side_bounced = true
	if serving_side_bounced and receiving_side_bounced:
		both_bounces_complete = true

func can_volley() -> bool:
	return both_bounces_complete

func reset_rally_state() -> void :
	begin_contact_context()
	_clear_consumed_bounce_age()
	receiver_entire_ball_crossed = false
	receiver_side_bounced = false
	receiver_returned_across_net = false
	time_since_last_bounce = -1.0
	serving_side_bounced = false
	receiving_side_bounced = false
	both_bounces_complete = false
	ball_bounced_since_last_hit = false
	bounces_since_last_hit = 0
	bounce_count = 0
	last_hit_by = -1
	last_hit_actor_id = -1; last_hit_team_id = -1; last_hit_court_side = -1
	was_volley = false






static func predict_aero_step(pos: Vector3, vel: Vector3, omega: Vector3, gravity: float, dt: float) -> Array:
	var speed: float = vel.length()
	if speed > 0.1 and AERO_EFFECT_SCALE > 0.0:
		var cross_section: float = PI * BALL_RADIUS * BALL_RADIUS
		var drag_force_mag: float = 0.5 * AIR_DENSITY * DRAG_COEFFICIENT * cross_section * speed * speed
		var drag_accel: Vector3 = - vel.normalized() * (drag_force_mag / BALL_MASS)
		vel += drag_accel * dt * AERO_EFFECT_SCALE

	if omega.length_squared() > 0.01 and speed > 0.5 and AERO_EFFECT_SCALE > 0.0:
		var magnus_force: Vector3 = MAGNUS_COEFFICIENT * omega.cross(vel)
		vel += (magnus_force / BALL_MASS) * dt * AERO_EFFECT_SCALE

	if omega.length_squared() > 0.001 and AERO_EFFECT_SCALE > 0.0:
		var spin_decay: float = exp( - dt * 0.693 / (SPIN_DAMPING_HALFLIFE * AERO_EFFECT_SCALE))
		omega *= spin_decay

	if vel.length() > MAX_SPEED:
		vel = vel.normalized() * MAX_SPEED



	var engine_damp: float = float(ProjectSettings.get_setting("physics/3d/default_linear_damp"))
	vel *= maxf(1.0 - engine_damp * dt, 0.0)



	var engine_angular_damp: float = float(ProjectSettings.get_setting("physics/3d/default_angular_damp"))
	omega *= maxf(1.0 - engine_angular_damp * dt, 0.0)


	vel.y -= gravity * dt

	pos += vel * dt
	return [pos, vel, omega]


# Batch an uninterrupted endpoint integration. This keeps the single-step equations,
# operation order and physics timestep; no trajectory samples are needed by solvers.
# Settings are read per invocation so runtime tuning is never hidden by a stale cache.
static func predict_aero_steps(pos: Vector3, vel: Vector3, omega: Vector3, gravity: float, dt: float, count: int) -> Array:
	var engine_damp: float = float(ProjectSettings.get_setting("physics/3d/default_linear_damp"))
	var engine_angular_damp: float = float(ProjectSettings.get_setting("physics/3d/default_angular_damp"))
	var spin_decay: float = exp( - dt * 0.693 / (SPIN_DAMPING_HALFLIFE * AERO_EFFECT_SCALE)) if AERO_EFFECT_SCALE > 0.0 else 1.0
	for step in count:
		var speed: float = vel.length()
		if speed > 0.1 and AERO_EFFECT_SCALE > 0.0:
			var cross_section: float = PI * BALL_RADIUS * BALL_RADIUS
			var drag_force_mag: float = 0.5 * AIR_DENSITY * DRAG_COEFFICIENT * cross_section * speed * speed
			var drag_accel: Vector3 = - vel.normalized() * (drag_force_mag / BALL_MASS)
			vel += drag_accel * dt * AERO_EFFECT_SCALE
		if omega.length_squared() > 0.01 and speed > 0.5 and AERO_EFFECT_SCALE > 0.0:
			var magnus_force: Vector3 = MAGNUS_COEFFICIENT * omega.cross(vel)
			vel += (magnus_force / BALL_MASS) * dt * AERO_EFFECT_SCALE
		if omega.length_squared() > 0.001 and AERO_EFFECT_SCALE > 0.0:
			omega *= spin_decay
		if vel.length() > MAX_SPEED:
			vel = vel.normalized() * MAX_SPEED
		vel *= maxf(1.0 - engine_damp * dt, 0.0)
		omega *= maxf(1.0 - engine_angular_damp * dt, 0.0)
		vel.y -= gravity * dt
		pos += vel * dt
	return [pos, vel, omega]


static func predict_bounce_spin(vel: Vector3, omega: Vector3) -> Array:
	if AERO_EFFECT_SCALE > 0.0:
		var tang_v: Vector3 = Vector3(vel.x, 0, vel.z)
		var spin_surface: Vector3 = Vector3(
			- omega.z * BALL_RADIUS, 
			0, 
			omega.x * BALL_RADIUS
		)
		var new_tang: Vector3 = tang_v - SPIN_BOUNCE_TRANSFER * (tang_v - spin_surface) * AERO_EFFECT_SCALE
		vel.x = new_tang.x
		vel.z = new_tang.z
		omega *= lerpf(1.0, SPIN_BOUNCE_DECAY, AERO_EFFECT_SCALE)
	vel.y = abs(vel.y) * cor_for_impact_speed(abs(vel.y))
	return [vel, omega]




func set_authoritative_paddles(paddles: Array) -> void:
	# One match contact owner observes the exact rendered paddle/handle. Native
	# StaticBody response must not reverse a ball before that owner sees it.
	for old in _authoritative_paddles:
		if is_instance_valid(old) and not paddles.has(old) and old != _contact_paddle: remove_collision_exception_with(old)
	_authoritative_paddles.clear()
	for paddle in paddles:
		if is_instance_valid(paddle) and paddle is PhysicsBody3D:
			_authoritative_paddles.append(paddle)
			add_collision_exception_with(paddle)

func suppress_paddle_collision(paddle: PhysicsBody3D) -> void :
	_clear_paddle_collision_exception()
	if not is_instance_valid(paddle): return
	_contact_paddle = paddle
	_contact_paddle_grace = 0.1
	add_collision_exception_with(paddle)

func _update_paddle_clearance(delta: float) -> void :
	if _contact_paddle_grace <= 0.0: return
	_contact_paddle_grace -= delta
	if _contact_paddle_grace <= 0.0:
		_clear_paddle_collision_exception()

func _clear_paddle_collision_exception() -> void :
	if is_instance_valid(_contact_paddle) and not _authoritative_paddles.has(_contact_paddle):
		remove_collision_exception_with(_contact_paddle)
	_contact_paddle = null
	_contact_paddle_grace = 0.0

func set_spin_debug_visible(enabled: bool) -> void :
	spin_debug_visible = enabled
	if enabled and _spin_axis_node == null: _setup_spin_debug_visuals()
	if _spin_axis_node: _spin_axis_node.visible = enabled
	if _equator_marker: _equator_marker.visible = enabled
	if _equator_marker_2: _equator_marker_2.visible = enabled
