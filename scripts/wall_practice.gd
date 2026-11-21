extends Node3D


const BallModel = preload("res://scripts/ball.gd")
const Profiles = preload("res://scripts/shot_profile.gd")
const Layout = preload("res://scripts/ui/mobile_layout.gd")
const FLOOR: = 0.075
const NET_REFERENCE_HEIGHT: = 0.8636
const HALF_WIDTH: = 3.4
const WALL_HEIGHT: = 3.5
const REBOUND: = 0.82
const FRONT: = 0.0
const TARGET_HALF_WIDTH: = 0.75
const TARGET_BOTTOM: = 1.06
const TARGET_TOP: = 1.78
const FEED_ORIGIN: = Vector3(0.42, 1.25, 0.16)
const FEED_TARGET: = Vector3(0.42, 0.95, 2.9)
const FEED_SECONDS: = 0.95   # a touch slower than the old 0.7 s flight (the 0.85 s parked wait is gone)
var game
var practice
var active: = false
var returns: = 0
var targets: = 0
var rebounds: = 0
var last_feedback: = "Find your rhythm"
var _wall: StaticBody3D
var _collision: CollisionShape3D
var _target_material: StandardMaterial3D
var _flash: = 0.0
var _saved: Dictionary = {}
var _hidden_nodes: Array[Node3D] = []
var _visibility: Array[bool] = []
var _previous: = Vector3.INF
var _incoming: = Vector3.ZERO
var _flight: = -1
var _cooldown: = 0.0
var _sphere: = SphereShape3D.new()
var _go_live: = false

func setup(owner_game, owner_practice) -> void :
	game = owner_game
	practice = owner_practice
	name = "WallPracticeCourt"
	hide()
	game.ball.body_entered.connect(_on_body_entered)
	game.ball.hit_player_body.connect(_on_body_hit)

func _box(parent: Node3D, label: String, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh: = MeshInstance3D.new()
	mesh.name = label
	var box: = BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat: = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mesh.material_override = mat
	mesh.position = at
	parent.add_child(mesh)
	return mesh

func _label(text: String, at: Vector3, font_size: int = 48, pixel_size: float = 0.006) -> void :
	var label: = Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.position = at
	label.outline_size = 4
	label.modulate = Color("edf3da")
	label.no_depth_test = false
	add_child(label)

func _build() -> void :
	_box(self, "PracticeSurface", Vector3(0, 0.074, 3.65), Vector3(6.8, 0.002, 7.3), Color("254e51"))
	for x in [-3.15, 3.15]:
		_box(self, "Sideline", Vector3(x, 0.078, 3.65), Vector3(0.04, 0.004, 7.2), Color("d6e8d4"))
	_box(self, "Backline", Vector3(0, 0.078, 7.15), Vector3(6.34, 0.004, 0.04), Color("d6e8d4"))

	for z in [2.0, 4.0, 6.0]:
		for x in [-3.05, 3.05]:
			_box(self, "DistanceTick", Vector3(x, 0.078, z), Vector3(0.16, 0.004, 0.025), Color("8ba7a1"))
	_wall = StaticBody3D.new()
	_wall.name = "ReboundWall"
	_wall.collision_layer = 4
	_wall.collision_mask = 1
	_wall.physics_material_override = PhysicsMaterial.new()
	_wall.physics_material_override.absorbent = true
	_wall.physics_material_override.bounce = 1.0 - REBOUND
	_wall.physics_material_override.friction = 0.0
	add_child(_wall)
	_box(_wall, "WallFace", Vector3(0, FLOOR + WALL_HEIGHT * 0.5, -0.12), Vector3(HALF_WIDTH * 2, WALL_HEIGHT, 0.24), Color("18373f"))
	_collision = CollisionShape3D.new()
	var shape: = BoxShape3D.new()
	shape.size = Vector3(HALF_WIDTH * 2, WALL_HEIGHT, 0.24)
	_collision.shape = shape
	_collision.position = Vector3(0, FLOOR + WALL_HEIGHT * 0.5, -0.12)
	_collision.disabled = true
	_wall.add_child(_collision)
	_box(self, "CenterNetReference", Vector3(0, FLOOR + NET_REFERENCE_HEIGHT, 0.014), Vector3(HALF_WIDTH * 2, 0.038, 0.016), Color("e8efd6"))
	var target: = _box(self, "TargetArea", Vector3(0, (TARGET_BOTTOM + TARGET_TOP) * 0.5, 0.01), Vector3(TARGET_HALF_WIDTH * 2, TARGET_TOP - TARGET_BOTTOM, 0.01), Color("496f64"))
	_target_material = target.material_override
	for x in [ - TARGET_HALF_WIDTH, TARGET_HALF_WIDTH]:
		_box(self, "TargetBorder", Vector3(x, (TARGET_BOTTOM + TARGET_TOP) * 0.5, 0.025), Vector3(0.035, TARGET_TOP - TARGET_BOTTOM, 0.015), Color("c4e88a"))
	for y in [TARGET_BOTTOM, TARGET_TOP]:
		_box(self, "TargetBorder", Vector3(0, y, 0.025), Vector3(TARGET_HALF_WIDTH * 2, 0.035, 0.015), Color("c4e88a"))
	_label("WALL PRACTICE", Vector3(0, 2.84, 0.03), 62, 0.006)
	_label("HIT  ·  REBOUND  ·  REPEAT", Vector3(0, 2.44, 0.03), 34, 0.005)
	_label("34 in / 86.36 cm", Vector3(0, 0.63, 0.03), 44, 0.007)
	_label("CENTER-NET REFERENCE", Vector3(0, 0.32, 0.03), 28, 0.006)
	_sphere.radius = BallModel.BALL_RADIUS

func enter() -> void :
	if active: return
	if _wall == null: _build()
	active = true
	returns = 0
	targets = 0
	rebounds = 0
	var p = game.player_left
	_saved = {"min_x": p.min_x, "max_x": p.max_x, "min_z": p.min_z, "max_z": p.max_z, 
		"right_process": game.player_right.process_mode, "right_visible": game.player_right.visible, 
		"camera_position": game.main_camera.position, "camera_rotation": game.main_camera.rotation, 
		"camera_fov": game.main_camera.fov, "camera_keep": game.main_camera.keep_aspect, 
		"net_layer": game.get_node("Net").collision_layer}
	_hidden_nodes.clear()
	_visibility.clear()
	for path in ["Court/CourtSurface", "CourtLines", "Net", "CourtBranding", "CourtArenaVisual", "DebugZones"]:
		var node = game.get_node_or_null(path)
		if node is Node3D:
			_hidden_nodes.append(node)
			_visibility.append(node.visible)
			node.hide()
	game.get_node("Net").collision_layer = 0
	game.get_node("Net").bind_ball(null)
	game.ball._net_contact_guard = self
	game.ball.wall_practice_active = true
	game.player_right.set_ai_movement_enabled(false)
	game.player_right.hide()
	game.player_right.process_mode = Node.PROCESS_MODE_DISABLED
	_collision.set_deferred("disabled", false)
	show()

func leave() -> void :
	if not active: return
	active = false
	_go_live = false
	game.ball.wall_practice_active = false
	game.ball.wall_return_ready = false
	game.ball._net_contact_guard = null
	_collision.set_deferred("disabled", true)
	for index in _hidden_nodes.size():
		if is_instance_valid(_hidden_nodes[index]): _hidden_nodes[index].visible = _visibility[index]
	game.get_node("Net").collision_layer = _saved.net_layer
	game.get_node("Net").bind_ball(game.ball)
	var p = game.player_left
	p.min_x = _saved.min_x;p.max_x = _saved.max_x
	p.min_z = _saved.min_z;p.max_z = _saved.max_z
	game.player_right.process_mode = _saved.right_process
	game.player_right.visible = _saved.right_visible
	game.main_camera.position = _saved.camera_position
	game.main_camera.rotation = _saved.camera_rotation
	game.main_camera.fov = _saved.camera_fov
	game.main_camera.keep_aspect = _saved.camera_keep
	game.hud.difficulty.visible = game.hud._gameplay_visible and not game.hud._portrait
	_previous = Vector3.INF
	hide()

func feed() -> void :
	game.ball.begin_contact_context()
	var p = game.player_left
	game.serving_team = 0
	p.global_position = Vector3(0.0, p.ground_y, 3.4)
	p.min_x = -3.05;p.max_x = 3.05;p.min_z = 0.7;p.max_z = 7.0
	p.leg_ik.feet_initialized = false
	game.player_right.global_position = Vector3(30, 1, -30)
	game.player_right.hide()
	# Launch the feed right here, inside the drill reset, like every other drill. Parking the
	# ball with RigidBody.freeze and launching it later from _process left the contact
	# authority with a stale native sample: it held the point and the replay dropped the
	# drill into a match serve ("Hold to serve...").
	game.ball.global_position = FEED_ORIGIN
	var launch: Dictionary = practice.solve_airborne_feed(FEED_ORIGIN, FEED_TARGET, FEED_SECONDS)
	game.ball.freeze = false
	game.ball.linear_velocity = launch.velocity
	game.ball.angular_velocity = Vector3.ZERO
	game.ball.wall_return_ready = true
	# The drill-finish path parks the ball with RigidBody.freeze, which skips
	# _integrate_forces; going live before a fresh native sample exists makes the contact
	# authority hold the point. tick() puts the ball in play once physics has stepped it.
	game.ball.is_in_play = false
	_go_live = true
	game.ball.last_hit_by = -1
	game.ball.both_bounces_complete = true
	game.ball.serving_side_bounced = true
	game.ball.receiving_side_bounced = true
	game.ball.flight_id += 1
	# New flight after _reset_ball's contact reset: re-sync the authority to it, or its next
	# ordered interval sees a changed flight and holds the point.
	if game.contact_authority: game.contact_authority.reset()
	game._set_game_state(game.GameState.PLAYING)
	game.rally_scorer.cancel_rally()
	game.scoreboard_ui._hide_temporary_ui()
	game.aim_controller.reset()
	_cooldown = 0.0
	_previous = Vector3.INF
	practice._attempt_timer = 0.0
	practice._set_status("Ball coming · hold HIT")

func tick(delta: float) -> void :
	if not active or practice._attempt_finished: return
	_cooldown = maxf(0.0, _cooldown - delta)
	_flash = maxf(0.0, _flash - delta)
	_target_material.albedo_color = Color("b8dc76") if _flash > 0 else Color("496f64")
	if _go_live:
		var sample: Dictionary = game.ball.native_interval_sample()
		if int(sample.get("frame", -1)) != Engine.get_physics_frames() or sample.get("frozen", true) or int(sample.get("flight", -1)) != game.ball.flight_id: return
		_go_live = false
		game.ball.is_in_play = true
		if game.contact_authority: game.contact_authority.reset()
	var ball = game.ball
	if absf(ball.global_position.x) > HALF_WIDTH + 0.35 or ball.global_position.z < -0.4 or ball.global_position.z > 8.0:
		_finish("Ball away")
	elif ball.is_in_play and ball.linear_velocity.length() < 0.35 and ball.global_position.y < 0.2:
		_finish("Next ball")

func on_floor_bounce(_position: Vector3) -> void :
	if not active or practice._attempt_finished: return
	if game.ball.bounces_since_last_hit >= 2: _finish("Two bounces")

func on_paddle_hit(team: int) -> void :
	if not active or practice._attempt_finished or team != 0: return
	game.ball.wall_return_ready = false
	returns += 1
	practice._attempt_timer = 0.0
	practice._set_status("Return %d · find the target" % returns)

func _finish(reason: String) -> void :
	practice.finish_attempt(1, reason, "A fresh ball is coming · Pause to reset or leave")

func _on_body_hit(team: int) -> void :
	if active and team == 0 and game.ball.wall_return_ready: _finish("Body touch")

func _on_body_entered(body: Node) -> void :
	if _has_live_contact_owner(): return
	if not active or body != _wall or _cooldown > 0 or not game.ball.is_in_play: return
	_rebounded(game.ball.global_position)

func _rebounded(point: Vector3) -> void :
	if _cooldown > 0 or not active or practice._attempt_finished: return
	_cooldown = 0.09
	rebounds += 1
	var ball = game.ball
	ball.wall_return_ready = true
	ball.last_hit_by = -1
	ball.bounces_since_last_hit = 0
	ball.ball_bounced_since_last_hit = false
	ball.flight_id += 1
	practice._attempt_timer = 0.0
	var on_target: bool = absf(point.x) <= TARGET_HALF_WIDTH and point.y >= TARGET_BOTTOM and point.y <= TARGET_TOP
	if on_target:
		targets += 1
		_flash = 0.4
		last_feedback = "Target!"
	else:
		last_feedback = "Low on the wall" if point.y < FLOOR + NET_REFERENCE_HEIGHT else "Wall return"
	practice._set_status("%s · %d returns · %d targets" % [last_feedback, returns, targets])

func resolve_swept_contact(state: PhysicsDirectBodyState3D) -> void :
	if not active: return
	if _has_live_contact_owner():
		reset_sweep_observation(state.transform.origin, state.linear_velocity, game.ball.flight_id)
		return
	var ball = game.ball
	var current: Vector3 = state.transform.origin
	var previous: Vector3 = _previous
	var incoming: Vector3 = _incoming
	_previous = current
	_incoming = state.linear_velocity
	if _flight != ball.flight_id or not previous.is_finite():
		_flight = ball.flight_id
		return


	if incoming.z >= 0 or state.linear_velocity.z >= 0 or previous.z <= BallModel.BALL_RADIUS or current.z > BallModel.BALL_RADIUS: return
	var motion: Vector3 = current - previous
	if motion.length() > 1.0: return
	var query: = PhysicsShapeQueryParameters3D.new()
	query.shape = _sphere
	query.transform = Transform3D(Basis.IDENTITY, previous)
	query.motion = motion
	query.collision_mask = 4
	query.margin = 0.0001
	var cast: PackedFloat32Array = state.get_space_state().cast_motion(query)
	if cast.is_empty() or cast[0] >= 1.0: return
	var point: Vector3 = previous + motion * cast[0]
	if absf(point.x) > HALF_WIDTH or point.y > FLOOR + WALL_HEIGHT + BallModel.BALL_RADIUS: return
	var pose: Transform3D = state.transform
	pose.origin = point + Vector3(0, 0, 0.001)
	state.transform = pose
	state.linear_velocity = Vector3(incoming.x, incoming.y, - incoming.z * REBOUND)
	_previous = pose.origin
	_incoming = state.linear_velocity
	_rebounded(point)

func ordered_scene_body() -> PhysicsBody3D:
	return _wall if active and is_instance_valid(_wall) else null

func _has_live_contact_owner() -> bool:
	return active and is_instance_valid(game) and is_instance_valid(game.ball) and game.ball._net_contact_guard == self and game.ball.owns_live_net_contact()

func reset_sweep_observation(point: Vector3, velocity: Vector3, flight: int) -> void:
	_previous = point; _incoming = velocity; _flight = flight

func ordered_scene_geometry() -> Dictionary:
	if not active or not is_instance_valid(_wall) or not is_instance_valid(_collision) or _collision.disabled or not _collision.shape is BoxShape3D: return {}
	if (int(_wall.collision_layer) & int(game.ball.collision_mask)) == 0: return {}
	return {"transform": _collision.global_transform, "half_size": _collision.shape.size * 0.5, "restitution": REBOUND, "body_id": _wall.get_instance_id()}

func apply_authoritative_contact(event: Dictionary) -> bool:
	if not _has_live_contact_owner() or int(event.get("body_id", -1)) != _wall.get_instance_id() or event.type != "wall": return false
	_rebounded(event.point)
	reset_sweep_observation(game.ball.global_position, game.ball.linear_velocity, game.ball.flight_id)
	return true

static func clamp_target(point: Vector3) -> Vector3:
	return Vector3(clampf(point.x, -2.7, 2.7), clampf(point.y, FLOOR + NET_REFERENCE_HEIGHT + 0.12, 2.75), 0.015)

func solve_launch(origin: Vector3, target: Vector3, charge: float, mode: int, intent: String) -> Dictionary:
	target = clamp_target(target)
	var speed: float = lerpf(5.0, 10.5, clampf(charge, 0, 1))
	if intent == "DROP": speed = lerpf(4.5, 6.4, clampf(charge, 0, 1))
	var duration: float = clampf(Vector2(origin.x - target.x, origin.z).length() / speed, 0.22, 1.15)
	var profile: Dictionary = Profiles.create(mode, charge, "DROP" if intent == "DROP" else "DRIVE")
	var velocity: Vector3 = (target - origin) / duration + Vector3.UP * BallModel.get_effective_gravity() * duration * 0.5
	var omega: = Vector3.ZERO
	for iteration in 6:
		omega = Profiles.angular_velocity(profile, velocity)
		var endpoint: Vector3 = game.shot_physics._spin_position_after(origin, velocity, omega, duration)
		velocity += (target - endpoint) / duration * 0.86
		velocity = velocity.limit_length(BallModel.MAX_SPEED)
	omega = Profiles.angular_velocity(profile, velocity)
	return {"velocity": velocity, "omega": omega, "target": target, "profile": profile}

func preview(origin: Vector3, target: Vector3, charge: float, mode: int, intent: String) -> Dictionary:
	var launch: Dictionary = solve_launch(origin, target, charge, mode, intent)
	var points: = PackedVector3Array([origin])
	var pos: Vector3 = origin
	var velocity: Vector3 = launch.velocity
	var omega: Vector3 = launch.omega
	for step in 90:
		var moved: Array = BallModel.predict_aero_step(pos, velocity, omega, BallModel.get_effective_gravity(), 1.0 / 60.0)
		var next: Vector3 = moved[0]
		if next.z <= BallModel.BALL_RADIUS:
			var f: float = clampf((pos.z - BallModel.BALL_RADIUS) / (pos.z - next.z), 0, 1)
			points.append(pos.lerp(next, f))
			break
		pos = next;velocity = moved[1];omega = moved[2]
		if step % 2 == 0: points.append(pos)
	return {"points": points, "landing": points[points.size() - 1], "net_clear": true, "feasible": true}

func update_camera(camera: Camera3D) -> void :
	var portrait: bool = Layout.is_portrait(get_viewport().get_visible_rect().size)
	camera.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT
	camera.fov = 43.0 if portrait else 54.0
	camera.position = Vector3(0, 8.7, 11.7) if portrait else Vector3(0, 6.3, 10.6)
	camera.look_at(Vector3(0, 0.6, 2.1), Vector3.UP)
