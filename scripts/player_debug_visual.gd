class_name PlayerDebugVisual extends Node
## PlayerDebugVisual — extracted from player.gd
## All debug visualization and indicator logic for AI and human players.

const HUMAN_INTERCEPT_POOL_SIZE := 4  # Mobile: reduced from 8
const AI_MARKER_HEIGHT := 0.09
const AI_MARKER_SMOOTHING := 0.08
const AI_POST_BOUNCE_MARKER_SMOOTHING := 0.12
const NON_VOLLEY_ZONE := PickleballConstants.NON_VOLLEY_ZONE
const MEDIUM_OVERHEAD_TRIGGER_HEIGHT := PickleballConstants.MEDIUM_OVERHEAD_TRIGGER_HEIGHT
const HIGH_OVERHEAD_TRIGGER_HEIGHT := PickleballConstants.HIGH_OVERHEAD_TRIGGER_HEIGHT
const DEBUG_STEP_PLANNER := true

var _debug_hidden: bool = true  # hidden by default — Z key toggles
var _intent_hidden: bool = false  # N key toggles — independent of Z. Shows
								   # the SMASH / SEMI-SMASH / VOLLEY / DINK /
								   # DROP / GROUNDSTROKE / LOB RETURN intent
								   # markers on where the human can intercept.

# AI indicator nodes
var ai_target_indicator: MeshInstance3D = null
var ai_bounce_indicator: MeshInstance3D = null
var ai_contact_indicator: MeshInstance3D = null
var ai_target_indicator_position: Vector3 = Vector3.ZERO
var ai_bounce_indicator_position: Vector3 = Vector3.ZERO
var ai_contact_indicator_position: Vector3 = Vector3.ZERO

# Human indicator nodes
var human_intercept_indicator: MeshInstance3D = null
var human_target_indicator: MeshInstance3D = null
var human_prebounce_indicators: Array[MeshInstance3D] = []
var human_postbounce_indicators: Array[MeshInstance3D] = []
var human_prebounce_dashlines: Array[MeshInstance3D] = []
var human_prebounce_labels: Array[Label3D] = []
var human_postbounce_labels: Array[Label3D] = []

# Incoming trajectory arc
var incoming_traj_mesh: ImmediateMesh = null
var incoming_traj_instance: MeshInstance3D = null
var incoming_traj_material: StandardMaterial3D = null
var _last_trajectory_points: Array[Vector3] = []
var _traj_log_pending: bool = false  # set true by practice launch to log once

# Human intercept state
var human_committed_pre_intercepts: Array[Vector3] = []
var human_committed_post_intercepts: Array[Vector3] = []
var human_committed_contact_position: Vector3 = Vector3.ZERO
var human_committed_target_position: Vector3 = Vector3.ZERO
var human_last_hit_by_seen: int = -1
var human_last_ball_vel_sign: float = 0.0

# Step debug markers
var _debug_right_target_marker: MeshInstance3D = null
var _debug_left_target_marker: MeshInstance3D = null
var _debug_right_origin_marker: MeshInstance3D = null
var _debug_left_origin_marker: MeshInstance3D = null


var _player: PlayerController


func _ready() -> void:
	_player = get_parent() as CharacterBody3D


func set_debug_visible(v: bool) -> void:
	_debug_hidden = not v
	for node in [ai_target_indicator, ai_bounce_indicator, ai_contact_indicator,
		human_intercept_indicator, human_target_indicator,
		_debug_right_target_marker, _debug_left_target_marker,
		_debug_right_origin_marker, _debug_left_origin_marker,
		incoming_traj_instance]:
		if node: node.visible = false
	for arr in [human_prebounce_indicators, human_postbounce_indicators, human_prebounce_dashlines]:
		for node in arr:
			if node: node.visible = false
	for arr in [human_prebounce_labels, human_postbounce_labels]:
		for lbl in arr:
			if lbl: lbl.visible = false

# N key toggles — independent of Z debug. Only affects shot-intent indicators
# (SMASH / SEMI-SMASH / VOLLEY / DINK / DROP / GROUNDSTROKE / LOB RETURN).
# Other Z-gated debug visuals continue to honor _debug_hidden.
func set_intent_indicators_visible(v: bool) -> void:
	_intent_hidden = not v
	if _intent_hidden:
		for arr in [human_prebounce_indicators, human_postbounce_indicators, human_prebounce_dashlines]:
			for node in arr:
				if node: node.visible = false
		for arr in [human_prebounce_labels, human_postbounce_labels]:
			for lbl in arr:
				if lbl: lbl.visible = false

func draw_step_debug(r_target: Vector3, l_target: Vector3, r_origin: Vector3, l_origin: Vector3, r_swing: bool, l_swing: bool) -> void:
	if not DEBUG_STEP_PLANNER or _debug_hidden:
		return

	# Create markers on first call
	if _debug_right_target_marker == null:
		_debug_right_target_marker = create_debug_marker(Color(0.2, 0.5, 1.0, 0.7), 0.03)  # blue = right target
		_debug_left_target_marker = create_debug_marker(Color(1.0, 0.3, 0.2, 0.7), 0.03)    # red = left target
		_debug_right_origin_marker = create_debug_marker(Color(0.2, 0.5, 1.0, 0.3), 0.02)   # dim blue = right origin
		_debug_left_origin_marker = create_debug_marker(Color(1.0, 0.3, 0.2, 0.3), 0.02)    # dim red = left origin

	# Position target markers (where foot will land)
	_debug_right_target_marker.global_position = r_target + Vector3(0, 0.005, 0)
	_debug_left_target_marker.global_position = l_target + Vector3(0, 0.005, 0)

	# Position origin markers (where foot lifted from)
	_debug_right_origin_marker.global_position = r_origin + Vector3(0, 0.005, 0)
	_debug_left_origin_marker.global_position = l_origin + Vector3(0, 0.005, 0)

	# Scale up markers for swinging foot to show active step
	var active_scale: float = 1.5
	_debug_right_target_marker.scale = Vector3.ONE * (active_scale if r_swing else 1.0)
	_debug_left_target_marker.scale = Vector3.ONE * (active_scale if l_swing else 1.0)


func create_debug_marker(color: Color, radius: float) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	marker.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = mat
	get_tree().current_scene.add_child(marker)
	return marker


func create_ai_indicators() -> void:
	if not _player.is_ai:
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var parent_node: Node = tree.current_scene
	if parent_node == null:
		return

	ai_target_indicator = MeshInstance3D.new()
	var target_mesh: CylinderMesh = CylinderMesh.new()
	target_mesh.top_radius = 0.18
	target_mesh.bottom_radius = 0.18
	target_mesh.height = 0.014
	ai_target_indicator.mesh = target_mesh
	var target_material: StandardMaterial3D = StandardMaterial3D.new()
	target_material.albedo_color = Color(0.35, 0.95, 1.0, 0.88)
	target_material.emission_enabled = true
	target_material.emission = Color(0.35, 0.95, 1.0, 1.0)
	target_material.emission_energy_multiplier = 0.55
	target_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	target_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	target_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ai_target_indicator.material_override = target_material
	ai_target_indicator.visible = false
	ai_target_indicator.top_level = true
	parent_node.add_child(ai_target_indicator)

	ai_bounce_indicator = MeshInstance3D.new()
	var bounce_mesh: CylinderMesh = CylinderMesh.new()
	bounce_mesh.top_radius = 0.1
	bounce_mesh.bottom_radius = 0.1
	bounce_mesh.height = 0.012
	ai_bounce_indicator.mesh = bounce_mesh
	var bounce_material: StandardMaterial3D = StandardMaterial3D.new()
	bounce_material.albedo_color = Color(1.0, 0.94, 0.2, 0.92)
	bounce_material.emission_enabled = true
	bounce_material.emission = Color(1.0, 0.94, 0.2, 1.0)
	bounce_material.emission_energy_multiplier = 0.5
	bounce_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bounce_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bounce_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ai_bounce_indicator.material_override = bounce_material
	ai_bounce_indicator.visible = false
	ai_bounce_indicator.top_level = true
	parent_node.add_child(ai_bounce_indicator)

	ai_contact_indicator = MeshInstance3D.new()
	var contact_mesh: SphereMesh = SphereMesh.new()
	contact_mesh.radius = 0.11
	contact_mesh.height = 0.22
	ai_contact_indicator.mesh = contact_mesh
	var contact_material: StandardMaterial3D = StandardMaterial3D.new()
	contact_material.albedo_color = Color(1.0, 0.45, 0.2, 0.9)
	contact_material.emission_enabled = true
	contact_material.emission = Color(1.0, 0.45, 0.2, 1.0)
	contact_material.emission_energy_multiplier = 0.65
	contact_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	contact_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	contact_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ai_contact_indicator.material_override = contact_material
	ai_contact_indicator.visible = false
	ai_contact_indicator.top_level = true
	parent_node.add_child(ai_contact_indicator)
	ai_target_indicator_position = _player.global_position
	ai_bounce_indicator_position = _player.global_position
	ai_contact_indicator_position = _player.global_position
	_player.ai_brain.ai_committed_target_position = _player.global_position
	_player.ai_brain.ai_committed_bounce_position = _player.global_position
	_player.ai_brain.ai_committed_contact_position = _player.global_position


func create_human_indicators() -> void:
	# Create intercept indicators for both human and AI players
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var parent_node: Node = tree.current_scene
	if parent_node == null:
		return

	# Incoming trajectory arc (dashed line)
	incoming_traj_instance = MeshInstance3D.new()
	incoming_traj_instance.name = "IncomingTrajectory"
	incoming_traj_mesh = ImmediateMesh.new()
	incoming_traj_instance.mesh = incoming_traj_mesh
	incoming_traj_material = StandardMaterial3D.new()
	incoming_traj_material.albedo_color = Color(0.85, 0.95, 1.0, 0.7)
	incoming_traj_material.emission_enabled = true
	incoming_traj_material.emission = Color(0.3, 0.8, 1.0, 1.0)
	incoming_traj_material.emission_energy_multiplier = 0.6
	incoming_traj_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	incoming_traj_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	incoming_traj_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	incoming_traj_instance.material_override = incoming_traj_material
	incoming_traj_instance.visible = false
	parent_node.add_child(incoming_traj_instance)

	human_intercept_indicator = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	human_intercept_indicator.mesh = mesh

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.7, 1.0, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.7, 1.0, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	human_intercept_indicator.material_override = mat
	human_intercept_indicator.top_level = true
	human_intercept_indicator.visible = false
	parent_node.add_child(human_intercept_indicator)

	human_target_indicator = MeshInstance3D.new()
	var target_mesh: CylinderMesh = CylinderMesh.new()
	target_mesh.top_radius = 0.28
	target_mesh.bottom_radius = 0.28
	target_mesh.height = 0.014
	human_target_indicator.mesh = target_mesh

	var target_mat: StandardMaterial3D = StandardMaterial3D.new()
	target_mat.albedo_color = Color(0.2, 1.0, 0.4, 0.3)
	target_mat.emission_enabled = true
	target_mat.emission = Color(0.2, 1.0, 0.4, 1.0)
	target_mat.emission_energy_multiplier = 0.4
	target_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	target_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	target_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	human_target_indicator.material_override = target_mat
	human_target_indicator.top_level = true
	human_target_indicator.visible = false
	parent_node.add_child(human_target_indicator)

	# --- Pre-bounce intercept pool (orange/gold) ---
	for i in range(HUMAN_INTERCEPT_POOL_SIZE):
		var node = MeshInstance3D.new()
		var m: SphereMesh = SphereMesh.new()
		m.radius = 0.07
		m.height = 0.14
		node.mesh = m
		var pm: StandardMaterial3D = StandardMaterial3D.new()
		pm.albedo_color = Color(1.0, 0.7, 0.1, 0.85)
		pm.emission_enabled = true
		pm.emission = Color(1.0, 0.5, 0.0, 1.0)
		pm.emission_energy_multiplier = 1.2
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.cull_mode = BaseMaterial3D.CULL_DISABLED
		node.material_override = pm
		node.top_level = true
		node.visible = false
		parent_node.add_child(node)
		human_prebounce_indicators.append(node)

	# --- Post-bounce intercept pool (cyan) ---
	for i in range(HUMAN_INTERCEPT_POOL_SIZE):
		var node = MeshInstance3D.new()
		var m: SphereMesh = SphereMesh.new()
		m.radius = 0.07
		m.height = 0.14
		node.mesh = m
		var pm: StandardMaterial3D = StandardMaterial3D.new()
		pm.albedo_color = Color(0.1, 0.9, 1.0, 0.8)
		pm.emission_enabled = true
		pm.emission = Color(0.0, 0.8, 1.0, 1.0)
		pm.emission_energy_multiplier = 1.0
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.cull_mode = BaseMaterial3D.CULL_DISABLED
		node.material_override = pm
		node.top_level = true
		node.visible = false
		parent_node.add_child(node)
		human_postbounce_indicators.append(node)

	# --- Dash-lines for pre-bounce (ImmediateMesh, one per pool slot) ---
	var dash_mat_base := StandardMaterial3D.new()
	dash_mat_base.albedo_color = Color(1.0, 0.6, 0.1, 0.7)
	dash_mat_base.emission_enabled = true
	dash_mat_base.emission = Color(1.0, 0.5, 0.0)
	dash_mat_base.emission_energy_multiplier = 0.9
	dash_mat_base.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dash_mat_base.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dash_mat_base.cull_mode = BaseMaterial3D.CULL_DISABLED
	for _i2 in range(HUMAN_INTERCEPT_POOL_SIZE):
		var dl := MeshInstance3D.new()
		dl.mesh = ImmediateMesh.new()
		dl.material_override = dash_mat_base.duplicate()
		dl.top_level = true
		dl.visible = false
		parent_node.add_child(dl)
		human_prebounce_dashlines.append(dl)

	# --- Labels for pre-bounce ---
	var pre_label_names := ["VOLLEY", "", "", "", "", "", "", ""]
	for li in range(HUMAN_INTERCEPT_POOL_SIZE):
		var lbl := Label3D.new()
		lbl.text = pre_label_names[li]
		lbl.font_size = 28
		lbl.modulate = Color(1.0, 0.75, 0.1, 1.0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.top_level = true
		lbl.visible = false
		parent_node.add_child(lbl)
		human_prebounce_labels.append(lbl)

	# --- Labels for post-bounce ---
	var post_label_names := ["RETURN", "DROP", "", "", "", "", "", ""]
	for li in range(HUMAN_INTERCEPT_POOL_SIZE):
		var lbl := Label3D.new()
		lbl.text = post_label_names[li]
		lbl.font_size = 28
		lbl.modulate = Color(0.2, 0.95, 1.0, 1.0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.top_level = true
		lbl.visible = false
		parent_node.add_child(lbl)
		human_postbounce_labels.append(lbl)


func update_ai_indicators() -> void:
	if _debug_hidden:
		return
	if not _player.is_ai or ai_target_indicator == null or ai_bounce_indicator == null or ai_contact_indicator == null:
		return

	var ball: RigidBody3D = _player._get_ball_ref()
	var indicators_visible: bool = _player.ai_movement_enabled and ball != null
	ai_target_indicator.visible = indicators_visible
	ai_bounce_indicator.visible = indicators_visible
	ai_contact_indicator.visible = indicators_visible
	if not indicators_visible:
		return

	var target_marker_goal: Vector3 = Vector3(_player.ai_brain.ai_target_position.x, AI_MARKER_HEIGHT, _player.ai_brain.ai_target_position.z)
	var bounce_marker_goal: Vector3 = Vector3(_player.ai_brain.ai_predicted_bounce_position.x, 0.082 + AI_MARKER_HEIGHT, _player.ai_brain.ai_predicted_bounce_position.z)
	var contact_marker_goal: Vector3 = _player.ai_brain.ai_predicted_contact_position
	if ai_target_indicator_position == Vector3.ZERO:
		ai_target_indicator_position = target_marker_goal
	if ai_bounce_indicator_position == Vector3.ZERO:
		ai_bounce_indicator_position = bounce_marker_goal
	if ai_contact_indicator_position == Vector3.ZERO:
		ai_contact_indicator_position = contact_marker_goal
	var target_smoothing: float = AI_POST_BOUNCE_MARKER_SMOOTHING
	ai_target_indicator_position = ai_target_indicator_position.lerp(target_marker_goal, target_smoothing)
	ai_bounce_indicator_position = ai_bounce_indicator_position.lerp(bounce_marker_goal, AI_MARKER_SMOOTHING)
	ai_contact_indicator_position = ai_contact_indicator_position.lerp(contact_marker_goal, AI_POST_BOUNCE_MARKER_SMOOTHING)

	# Clamp all AI indicators to stay within the AI's own court half
	ai_target_indicator.global_position = _player._clamp_to_court(ai_target_indicator_position)
	ai_bounce_indicator.global_position = _player._clamp_to_court(ai_bounce_indicator_position)
	ai_contact_indicator.global_position = _player._clamp_to_court(ai_contact_indicator_position)


func predict_human_intercept_points(ball: RigidBody3D) -> Dictionary:
	var gravity: float = Ball.get_effective_gravity()
	var pos: Vector3 = ball.global_position
	var vel: Vector3 = ball.linear_velocity
	var omega: Vector3 = ball.angular_velocity
	var floor_h: float = 0.08

	# Height windows for the three tier postures
	const MIN_HIT_HEIGHT := 0.18   # LOW posture minimum
	const MAX_HIT_HEIGHT := 1.5    # HIGH_OVERHEAD maximum
	const STEP := 0.045
	const MAX_STEPS := 80
	const MIN_GAP := 0.25          # Min metres between sampled dots so they don't pile up

	var pre_bounce: Array[Vector3] = []
	var post_bounce: Array[Vector3] = []
	var has_bounced := false
	var last_pre := Vector3.ZERO
	var last_post := Vector3.ZERO

	for _i in range(MAX_STEPS):
		var stepped: Array = Ball.predict_aero_step(pos, vel, omega, gravity, STEP)
		if stepped.is_empty():
			break
		pos = stepped[0]
		vel = stepped[1]
		omega = stepped[2]

		if pos.y <= floor_h:
			if not has_bounced:
				has_bounced = true
				pos.y = floor_h
				var bounced: Array = Ball.predict_bounce_spin(vel, omega)
				if bounced.is_empty():
					break
				vel = bounced[0]
				omega = bounced[1]
				continue
			else:
				break  # Landed again -- stop

		# Only consider points inside our court bounds
		if pos.z < _player.min_z or pos.z > _player.max_z:
			continue
		if pos.x < _player.min_x or pos.x > _player.max_x:
			continue

		if pos.y >= MIN_HIT_HEIGHT and pos.y <= MAX_HIT_HEIGHT:
			if not has_bounced:
				# Skip if inside the no-volley zone (kitchen) -- player 0 is +Z side
				var in_kitchen := (_player.player_num == 0 and pos.z < NON_VOLLEY_ZONE) or \
								  (_player.player_num == 1 and pos.z > -NON_VOLLEY_ZONE)
				if not in_kitchen:
					if last_pre == Vector3.ZERO or pos.distance_to(last_pre) >= MIN_GAP:
						if pre_bounce.size() < HUMAN_INTERCEPT_POOL_SIZE:
							pre_bounce.append(pos)
							last_pre = pos
			else:
				if last_post == Vector3.ZERO or pos.distance_to(last_post) >= MIN_GAP:
					if post_bounce.size() < HUMAN_INTERCEPT_POOL_SIZE:
						post_bounce.append(pos)
						last_post = pos

	return { "pre": pre_bounce, "post": post_bounce }


func draw_incoming_trajectory(ball: RigidBody3D) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if ball == null or incoming_traj_mesh == null:
		return points

	incoming_traj_mesh.clear_surfaces()

	if ball.linear_velocity.length() < 0.5:
		incoming_traj_instance.visible = false
		return points

	var gravity: float = Ball.get_effective_gravity()
	var pos: Vector3 = ball.global_position
	var vel: Vector3 = ball.linear_velocity
	var omega: Vector3 = ball.angular_velocity
	var has_bounced: bool = false
	var step_time: float = 0.04
	var max_steps: int = 80
	var dash_on: float = 0.15
	var dash_off: float = 0.10
	var accum: float = 0.0
	var drawing: bool = true
	var prev_pos: Vector3 = pos

	var should_draw: bool = not _debug_hidden

	if should_draw:
		incoming_traj_mesh.surface_begin(Mesh.PRIMITIVE_LINES, incoming_traj_material)

	for _step in range(max_steps):
		var stepped: Array = Ball.predict_aero_step(pos, vel, omega, gravity, step_time)
		if stepped.is_empty():
			break
		pos = stepped[0]
		vel = stepped[1]
		omega = stepped[2]

		if pos.y <= 0.08:
			pos.y = 0.08
			if not has_bounced:
				has_bounced = true
				var bounced: Array = Ball.predict_bounce_spin(vel, omega)
				if bounced.is_empty():
					break
				vel = bounced[0]
				omega = bounced[1]
			else:
				points.append(pos + Vector3(0, 0.03, 0))
				break

		points.append(pos + Vector3(0, 0.03, 0))

		if should_draw:
			var seg_len: float = prev_pos.distance_to(pos)
			accum += seg_len
			var threshold: float = dash_on if drawing else dash_off
			if accum >= threshold:
				accum = 0.0
				drawing = not drawing

			if drawing:
				incoming_traj_mesh.surface_add_vertex(prev_pos + Vector3(0, 0.03, 0))
				incoming_traj_mesh.surface_add_vertex(pos + Vector3(0, 0.03, 0))

		prev_pos = pos

	if should_draw:
		incoming_traj_mesh.surface_end()
		incoming_traj_instance.visible = true
	else:
		incoming_traj_instance.visible = false

	# One-shot trajectory trace log (triggered by practice ball launch)
	if _traj_log_pending and not points.is_empty():
		_traj_log_pending = false
		var player_pos: Vector3 = _player.global_position
		var paddle_pos: Vector3 = _player.global_position
		if _player.has_method("get_paddle_position"):
			paddle_pos = _player.get_paddle_position()
		var fwd: Vector3 = _player._get_forward_axis()
		var last_logged_dist: float = -1.0
		print("[TRAJ] %d pts | player=(%.1f,%.1f,%.1f) paddle=(%.1f,%.1f,%.1f) dir=(%.2f,%.2f)" % [points.size(), player_pos.x, player_pos.y, player_pos.z, paddle_pos.x, paddle_pos.y, paddle_pos.z, fwd.x, fwd.z])
		# Find nearest green ghost for each trajectory zone
		for i in range(points.size()):
			var pt: Vector3 = points[i]
			var d_player: float = Vector2(pt.x - player_pos.x, pt.z - player_pos.z).length()
			var bucket: float = snappedf(d_player, 0.5)
			if bucket != last_logged_dist and d_player <= 8.0:
				last_logged_dist = bucket
				var d_paddle: float = paddle_pos.distance_to(pt)
				# Find nearest ghost to this trajectory point
				var nearest_ghost: String = "-"
				var nearest_ghost_d: float = INF
				if _player.posture:
					for posture in _player.posture.posture_ghosts.keys():
						var gw: Vector3 = player_pos + _player.posture.get_posture_offset_for(posture)
						var gd: float = gw.distance_to(pt)
						if gd < nearest_ghost_d:
							nearest_ghost_d = gd
							nearest_ghost = _player.DEBUG_POSTURE_NAMES[posture] if posture < _player.DEBUG_POSTURE_NAMES.size() else "?"
				print("  d=%.1f pos=(%.2f,%.2f,%.2f) paddle=%.2f ghost=%s(%.2f)" % [d_player, pt.x, pt.y, pt.z, d_paddle, nearest_ghost, nearest_ghost_d])

	return points

func clear_incoming_trajectory() -> void:
	_last_trajectory_points.clear()
	if incoming_traj_mesh:
		incoming_traj_mesh.clear_surfaces()
	if incoming_traj_instance:
		incoming_traj_instance.visible = false

func update_human_intercept_pools(ball: RigidBody3D) -> void:
	# Always compute trajectory (posture system needs it even when visuals are off)
	_last_trajectory_points = draw_incoming_trajectory(ball)
	if _debug_hidden:
		# Hide the visual mesh but keep the points
		if incoming_traj_instance:
			incoming_traj_instance.visible = false
	# Commit when the OPPONENT hits the ball (not self)
	var opponent_num := 1 - _player.player_num
	var current_hit_by: int = -1
	if ball.has_method("get_last_hit_by"):
		current_hit_by = int(ball.get_last_hit_by())
	var opponent_just_hit := (current_hit_by == opponent_num and human_last_hit_by_seen != opponent_num)
	human_last_hit_by_seen = current_hit_by

	# Fallback: detect velocity direction toward our court
	var ball_vel_sign: float = sign(ball.linear_velocity.z)
	# For player 0 (+Z court), ball coming toward us = positive Z vel
	# For player 1 (-Z court), ball coming toward us = negative Z vel
	var toward_us := (_player.player_num == 0 and ball_vel_sign > 0) or (_player.player_num == 1 and ball_vel_sign < 0)
	var vel_flipped := (ball_vel_sign != human_last_ball_vel_sign and toward_us)
	human_last_ball_vel_sign = ball_vel_sign

	# Recompute on new opponent hit, velocity flip inbound, or first time
	var needs_commit = opponent_just_hit or vel_flipped or human_committed_pre_intercepts.is_empty()

	if needs_commit:
		var result = predict_human_intercept_points(ball)
		var pre: Array[Vector3] = result["pre"]
		var post: Array[Vector3] = result["post"]

		# Pick one best point per shot tier so all three can show simultaneously
		human_committed_pre_intercepts.clear()
		if pre.size() > 0:
			# Tier 1: VOLLEY  (0.18m - MEDIUM_OVERHEAD_TRIGGER_HEIGHT)
			var best_volley := Vector3.ZERO
			var best_volley_score := INF
			# Tier 2: SEMI-SMASH (MEDIUM -> HIGH threshold)
			var best_semi := Vector3.ZERO
			var best_semi_score := INF
			# Tier 3: FULL SMASH (>= HIGH threshold)
			var best_smash := Vector3.ZERO
			var best_smash_score := INF
			for pt in pre:
				var dist = _player.global_position.distance_to(pt)
				if pt.y < MEDIUM_OVERHEAD_TRIGGER_HEIGHT:
					var score = abs(pt.y - 0.5) + dist * 0.2
					if score < best_volley_score:
						best_volley_score = score
						best_volley = pt
				elif pt.y < HIGH_OVERHEAD_TRIGGER_HEIGHT:
					var score = abs(pt.y - 0.9) + dist * 0.2
					if score < best_semi_score:
						best_semi_score = score
						best_semi = pt
				else:
					var score = dist * 0.2
					if score < best_smash_score:
						best_smash_score = score
						best_smash = pt
			# Add in order: volley first (lowest), then semi, then smash (highest)
			if best_volley != Vector3.ZERO:
				human_committed_pre_intercepts.append(best_volley)
			if best_semi != Vector3.ZERO:
				human_committed_pre_intercepts.append(best_semi)
			if best_smash != Vector3.ZERO:
				human_committed_pre_intercepts.append(best_smash)

		# Pick optimal post-bounce: low (easy return) + medium (ideal)
		human_committed_post_intercepts.clear()
		if post.is_empty():
			return
		var best_mid = post[0]
		var best_mid_score = INF
		var best_low = Vector3.ZERO
		var best_low_score = INF
		for pt in post:
			var med_err = abs(pt.y - 0.85)
			var low_err = abs(pt.y - 0.35)
			var dist = _player.global_position.distance_to(pt)
			if med_err + dist * 0.2 < best_mid_score:
				best_mid_score = med_err + dist * 0.2
				best_mid = pt
			if low_err + dist * 0.2 < best_low_score:
				best_low_score = low_err + dist * 0.2
				best_low = pt
		human_committed_post_intercepts.append(best_mid)
		if best_low != Vector3.ZERO and best_low.distance_to(best_mid) > 0.4:
			human_committed_post_intercepts.append(best_low)

	# --- Intent-indicator visibility gate ---
	# Hide when any of these is true:
	#   1. N key has toggled them off (_intent_hidden)
	#   2. Ball isn't moving toward THIS player (serving it themselves, or they
	#      just struck it and it's leaving)
	#   3. Ball is nearly stationary (toss / sitting on paddle / reset / roll)
	# NOTE: deliberately NOT checking ball.is_in_play — it's only set for
	# practice launches, real serves never set it (game.gd uses linear_velocity
	# direct-set instead of ball.serve()), so relying on it would hide the
	# indicators for the entire rally. Velocity + direction are sufficient.
	# 1.5 m/s threshold catches toss jitter and residual post-point rolling.
	var ball_incoming: bool = toward_us and ball.linear_velocity.length() > 1.5
	if _intent_hidden or not ball_incoming:
		for node in human_prebounce_indicators:
			if node: node.visible = false
		for dl in human_prebounce_dashlines:
			if dl: dl.visible = false
		for lbl in human_prebounce_labels:
			if lbl: lbl.visible = false
		for node in human_postbounce_indicators:
			if node: node.visible = false
		for lbl in human_postbounce_labels:
			if lbl: lbl.visible = false
		return

	var player_z_abs: float = abs(_player.global_position.z)

	# --- Update pre-bounce indicator visuals ---
	for i in range(human_prebounce_indicators.size()):
		var node = human_prebounce_indicators[i]
		var dl = human_prebounce_dashlines[i] if i < human_prebounce_dashlines.size() else null
		var lbl = human_prebounce_labels[i] if i < human_prebounce_labels.size() else null
		if i < human_committed_pre_intercepts.size():
			var target_pt: Vector3 = human_committed_pre_intercepts[i]
			if node.global_position == Vector3.ZERO:
				node.global_position = target_pt
			else:
				node.global_position = node.global_position.lerp(target_pt, 0.06)
			node.visible = true

			var cls: Dictionary = _classify_pre_bounce_shot(target_pt.y, player_z_abs, abs(target_pt.z))
			var dot_color: Color = cls["dot_color"]
			var mat: StandardMaterial3D = node.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color = dot_color
				mat.emission = Color(dot_color.r, dot_color.g * 0.7, dot_color.b, 1.0)
				mat.emission_energy_multiplier = cls["energy"]
			node.scale = node.scale.lerp(Vector3.ONE * float(cls["scale"]), 0.15)

			if dl:
				var floor_pt: Vector3 = Vector3(node.global_position.x, 0.08, node.global_position.z)
				draw_dash_line(dl, floor_pt, node.global_position)
				dl.visible = true
				var dl_mat: StandardMaterial3D = dl.material_override as StandardMaterial3D
				if dl_mat:
					dl_mat.albedo_color = Color(dot_color.r, dot_color.g, dot_color.b, 0.7)
					dl_mat.emission = Color(dot_color.r, dot_color.g * 0.6, dot_color.b, 1.0)
			if lbl:
				lbl.text = cls["label"]
				lbl.modulate = cls["label_color"]
				lbl.global_position = node.global_position + Vector3(0.0, 0.18, 0.0)
				lbl.visible = true
		else:
			node.visible = false
			node.scale = Vector3.ONE
			if dl: dl.visible = false
			if lbl: lbl.visible = false

	# --- Update post-bounce indicator visuals ---
	for i in range(human_postbounce_indicators.size()):
		var node = human_postbounce_indicators[i]
		var lbl = human_postbounce_labels[i] if i < human_postbounce_labels.size() else null
		if i < human_committed_post_intercepts.size():
			var target_pt: Vector3 = human_committed_post_intercepts[i]
			if node.global_position == Vector3.ZERO:
				node.global_position = target_pt
			else:
				node.global_position = node.global_position.lerp(target_pt, 0.06)
			node.visible = true

			var cls: Dictionary = _classify_post_bounce_shot(target_pt.y, player_z_abs, abs(target_pt.z))
			var dot_color: Color = cls["dot_color"]
			var mat: StandardMaterial3D = node.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color = dot_color
				mat.emission = Color(dot_color.r, dot_color.g * 0.75, dot_color.b, 1.0)
				mat.emission_energy_multiplier = cls["energy"]
			node.scale = node.scale.lerp(Vector3.ONE * float(cls["scale"]), 0.15)

			if lbl:
				lbl.text = cls["label"]
				lbl.modulate = cls["label_color"]
				lbl.global_position = node.global_position + Vector3(0.0, 0.16, 0.0)
				lbl.visible = true
		else:
			node.visible = false
			node.scale = Vector3.ONE
			if lbl: lbl.visible = false

# ──────────────────────────────────────────────────────────────────────────
# Shot classifiers — decide what label + color to attach to a predicted
# intercept point based on ball height, player court position, and whether
# it's a pre-bounce (in the air) or post-bounce (after first bounce) hit.
# ──────────────────────────────────────────────────────────────────────────

func _classify_pre_bounce_shot(hit_h: float, player_z_abs: float, _pt_z_abs: float) -> Dictionary:
	if _player and _player.pose_controller:
		return _player.pose_controller.describe_contact_intent(hit_h, player_z_abs, true)
	# Tier 1 & 2: overhead tiers always dominate regardless of position.
	if hit_h >= HIGH_OVERHEAD_TRIGGER_HEIGHT:
		return {
			"label": "⚡ SMASH ⚡",
			"dot_color": Color(1.0, 0.15, 0.10, 1.0),
			"label_color": Color(1.0, 0.22, 0.02, 1.0),
			"scale": 1.65,
			"energy": 1.6,
		}
	if hit_h >= MEDIUM_OVERHEAD_TRIGGER_HEIGHT:
		return {
			"label": "SEMI-SMASH",
			"dot_color": Color(1.0, 0.55, 0.05, 1.0),
			"label_color": Color(1.0, 0.65, 0.10, 1.0),
			"scale": 1.25,
			"energy": 1.3,
		}
	# Sub-overhead: subdivide by ball height + kitchen proximity.
	var near_kitchen: bool = player_z_abs < NON_VOLLEY_ZONE + 0.6
	if hit_h < 0.45 and near_kitchen:
		return {
			"label": "DINK VOLLEY",
			"dot_color": Color(0.95, 0.90, 0.20, 1.0),
			"label_color": Color(1.0, 1.0, 0.35, 1.0),
			"scale": 0.95,
			"energy": 1.0,
		}
	if near_kitchen:
		return {
			"label": "PUNCH VOLLEY",
			"dot_color": Color(1.0, 0.78, 0.15, 1.0),
			"label_color": Color(1.0, 0.85, 0.22, 1.0),
			"scale": 1.05,
			"energy": 1.1,
		}
	# Deep volley — behind the kitchen, ball still in the air.
	return {
		"label": "DEEP VOLLEY",
		"dot_color": Color(1.0, 0.70, 0.15, 1.0),
		"label_color": Color(1.0, 0.78, 0.20, 1.0),
		"scale": 1.0,
		"energy": 1.0,
	}

func _classify_post_bounce_shot(hit_h: float, player_z_abs: float, _pt_z_abs: float) -> Dictionary:
	if _player and _player.pose_controller:
		return _player.pose_controller.describe_contact_intent(hit_h, player_z_abs, false)
	var near_kitchen: bool = player_z_abs < NON_VOLLEY_ZONE + 0.6
	var at_baseline: bool = player_z_abs > NON_VOLLEY_ZONE + 2.6
	# Very low contact near kitchen = dink.
	if hit_h < 0.40 and near_kitchen:
		return {
			"label": "DINK",
			"dot_color": Color(0.30, 1.00, 0.85, 1.0),
			"label_color": Color(0.45, 1.00, 0.90, 1.0),
			"scale": 0.90,
			"energy": 1.0,
		}
	# Low contact anywhere else — drop / half-volley.
	if hit_h < 0.45:
		return {
			"label": "DROP",
			"dot_color": Color(0.40, 0.95, 1.00, 1.0),
			"label_color": Color(0.55, 1.00, 1.00, 1.0),
			"scale": 0.95,
			"energy": 1.0,
		}
	# Very high contact = lob return.
	if hit_h > 1.10:
		return {
			"label": "LOB RETURN",
			"dot_color": Color(0.70, 0.55, 1.00, 1.0),
			"label_color": Color(0.80, 0.65, 1.00, 1.0),
			"scale": 1.10,
			"energy": 1.15,
		}
	# Deep player, medium ball = classic baseline groundstroke.
	if at_baseline:
		return {
			"label": "GROUNDSTROKE",
			"dot_color": Color(0.20, 0.90, 1.00, 1.0),
			"label_color": Color(0.35, 0.95, 1.00, 1.0),
			"scale": 1.10,
			"energy": 1.15,
		}
	# Otherwise — mid-court return.
	return {
		"label": "RETURN",
		"dot_color": Color(0.30, 0.85, 1.00, 1.0),
		"label_color": Color(0.45, 0.92, 1.00, 1.0),
		"scale": 1.00,
		"energy": 1.0,
	}


func draw_dash_line(mesh_inst: MeshInstance3D, from_pos: Vector3, to_pos: Vector3) -> void:
	var imesh := mesh_inst.mesh as ImmediateMesh
	if imesh == null:
		return
	imesh.clear_surfaces()
	var height := to_pos.y - from_pos.y
	if height < 0.05:
		return
	const NUM_DASHES := 7
	imesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for d in range(NUM_DASHES):
		var t_start := float(d) / float(NUM_DASHES)
		var t_end := (float(d) + 0.5) / float(NUM_DASHES)  # Half the segment = dash, other half = gap
		imesh.surface_add_vertex(Vector3(from_pos.x, from_pos.y + t_start * height, from_pos.z))
		imesh.surface_add_vertex(Vector3(from_pos.x, from_pos.y + t_end   * height, from_pos.z))
	imesh.surface_end()
