class_name PlayerDebugVisual extends Node
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")




const HUMAN_INTERCEPT_POOL_SIZE = 4
const AI_MARKER_HEIGHT = 0.09
const NON_VOLLEY_ZONE = PickleballConstants.NON_VOLLEY_ZONE
const MEDIUM_OVERHEAD_TRIGGER_HEIGHT = PickleballConstants.MEDIUM_OVERHEAD_TRIGGER_HEIGHT
const HIGH_OVERHEAD_TRIGGER_HEIGHT = PickleballConstants.HIGH_OVERHEAD_TRIGGER_HEIGHT
const DEBUG_STEP_PLANNER = true

var _debug_hidden: bool = true
var _intent_hidden: bool = false





var _trajectory_visible: bool = false
var _intercept_visible: bool = false
var _ai_indicators_visible: bool = false
var _step_markers_visible: bool = false


var ai_target_indicator: MeshInstance3D = null
var ai_bounce_indicator: MeshInstance3D = null
var ai_contact_indicator: MeshInstance3D = null
var ai_target_indicator_position: Vector3 = Vector3.ZERO
var ai_bounce_indicator_position: Vector3 = Vector3.ZERO
var ai_contact_indicator_position: Vector3 = Vector3.ZERO


var human_intercept_indicator: MeshInstance3D = null
var human_target_indicator: MeshInstance3D = null
var human_prebounce_indicators: Array[MeshInstance3D] = []
var human_postbounce_indicators: Array[MeshInstance3D] = []
var human_prebounce_dashlines: Array[MeshInstance3D] = []
var human_prebounce_labels: Array[Label3D] = []
var human_postbounce_labels: Array[Label3D] = []


var incoming_traj_mesh: ImmediateMesh = null
var incoming_traj_instance: MeshInstance3D = null
var incoming_traj_material: StandardMaterial3D = null
var _last_flight: Dictionary = {}
var _last_trajectory_points: Array[Vector3] = []
var _traj_log_pending: bool = false


var human_committed_pre_intercepts: Array[Vector3] = []
var human_committed_post_intercepts: Array[Vector3] = []
var human_committed_contact_position: Vector3 = Vector3.ZERO
var human_committed_target_position: Vector3 = Vector3.ZERO
var human_last_hit_by_seen: int = -1
var human_last_ball_vel_sign: float = 0.0


var _debug_right_target_marker: MeshInstance3D = null
var _debug_left_target_marker: MeshInstance3D = null
var _debug_right_origin_marker: MeshInstance3D = null
var _debug_left_origin_marker: MeshInstance3D = null


var _player


func _ready() -> void :
	_player = get_parent() as CharacterBody3D


func set_debug_visible(v: bool) -> void :

	_debug_hidden = not v
	_trajectory_visible = v
	_intercept_visible = v
	_ai_indicators_visible = v
	_step_markers_visible = v
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


func set_trajectory_visible(v: bool) -> void :
	_trajectory_visible = v
	if incoming_traj_instance and not v:
		incoming_traj_instance.visible = false


func set_intercept_visible(v: bool) -> void :
	_intercept_visible = v
	if not v:
		for arr in [human_prebounce_indicators, human_postbounce_indicators, human_prebounce_dashlines]:
			for node in arr:
				if node: node.visible = false
		for arr in [human_prebounce_labels, human_postbounce_labels]:
			for lbl in arr:
				if lbl: lbl.visible = false


func set_ai_indicators_visible(v: bool) -> void :
	_ai_indicators_visible = v
	if not v:
		for node in [ai_target_indicator, ai_bounce_indicator, ai_contact_indicator]:
			if node: node.visible = false


func set_step_markers_visible(v: bool) -> void :
	_step_markers_visible = v
	if not v:
		for node in [_debug_right_target_marker, _debug_left_target_marker, 
					_debug_right_origin_marker, _debug_left_origin_marker]:
			if node: node.visible = false




func set_intent_indicators_visible(v: bool) -> void :
	_intent_hidden = not v
	if _intent_hidden:
		for arr in [human_prebounce_indicators, human_postbounce_indicators, human_prebounce_dashlines]:
			for node in arr:
				if node: node.visible = false
		for arr in [human_prebounce_labels, human_postbounce_labels]:
			for lbl in arr:
				if lbl: lbl.visible = false

func draw_step_debug(r_target: Vector3, l_target: Vector3, r_origin: Vector3, l_origin: Vector3, r_swing: bool, l_swing: bool) -> void :
	if not DEBUG_STEP_PLANNER or not _step_markers_visible:
		return


	if _debug_right_target_marker == null:
		_debug_right_target_marker = create_debug_marker(Color(0.2, 0.5, 1.0, 0.7), 0.03)
		_debug_left_target_marker = create_debug_marker(Color(1.0, 0.3, 0.2, 0.7), 0.03)
		_debug_right_origin_marker = create_debug_marker(Color(0.2, 0.5, 1.0, 0.3), 0.02)
		_debug_left_origin_marker = create_debug_marker(Color(1.0, 0.3, 0.2, 0.3), 0.02)


	_debug_right_target_marker.global_position = r_target + Vector3(0, 0.005, 0)
	_debug_left_target_marker.global_position = l_target + Vector3(0, 0.005, 0)


	_debug_right_origin_marker.global_position = r_origin + Vector3(0, 0.005, 0)
	_debug_left_origin_marker.global_position = l_origin + Vector3(0, 0.005, 0)


	var active_scale: float = 1.5
	_debug_right_target_marker.scale = Vector3.ONE * (active_scale if r_swing else 1.0)
	_debug_left_target_marker.scale = Vector3.ONE * (active_scale if l_swing else 1.0)


func create_debug_marker(color: Color, radius: float) -> MeshInstance3D:
	var marker = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	marker.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = mat
	get_tree().current_scene.add_child(marker)
	return marker


func create_ai_indicators() -> void :
	if not RuntimePolicy.developer_tools: return
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


func create_human_indicators() -> void :
	if not RuntimePolicy.developer_tools: return

	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var parent_node: Node = tree.current_scene
	if parent_node == null:
		return


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


	var dash_mat_base = StandardMaterial3D.new()
	dash_mat_base.albedo_color = Color(1.0, 0.6, 0.1, 0.7)
	dash_mat_base.emission_enabled = true
	dash_mat_base.emission = Color(1.0, 0.5, 0.0)
	dash_mat_base.emission_energy_multiplier = 0.9
	dash_mat_base.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dash_mat_base.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dash_mat_base.cull_mode = BaseMaterial3D.CULL_DISABLED
	for _i2 in range(HUMAN_INTERCEPT_POOL_SIZE):
		var dl = MeshInstance3D.new()
		dl.mesh = ImmediateMesh.new()
		dl.material_override = dash_mat_base.duplicate()
		dl.top_level = true
		dl.visible = false
		parent_node.add_child(dl)
		human_prebounce_dashlines.append(dl)


	var pre_label_names = ["VOLLEY", "", "", "", "", "", "", ""]
	for li in range(HUMAN_INTERCEPT_POOL_SIZE):
		var lbl = Label3D.new()
		lbl.text = pre_label_names[li]
		lbl.font_size = 28
		lbl.modulate = Color(1.0, 0.75, 0.1, 1.0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.top_level = true
		lbl.visible = false
		parent_node.add_child(lbl)
		human_prebounce_labels.append(lbl)


	var post_label_names = ["RETURN", "DROP", "", "", "", "", "", ""]
	for li in range(HUMAN_INTERCEPT_POOL_SIZE):
		var lbl = Label3D.new()
		lbl.text = post_label_names[li]
		lbl.font_size = 28
		lbl.modulate = Color(0.2, 0.95, 1.0, 1.0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.top_level = true
		lbl.visible = false
		parent_node.add_child(lbl)
		human_postbounce_labels.append(lbl)


func update_ai_indicators() -> void :
	if not _ai_indicators_visible:
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


	ai_target_indicator_position = target_marker_goal
	ai_bounce_indicator_position = bounce_marker_goal
	ai_contact_indicator_position = contact_marker_goal


	ai_target_indicator.global_position = _player._clamp_to_court(ai_target_indicator_position)
	ai_bounce_indicator.global_position = _player._clamp_to_court(ai_bounce_indicator_position)
	ai_contact_indicator.global_position = _player._clamp_to_court(ai_contact_indicator_position)


func draw_incoming_trajectory(ball: RigidBody3D) -> Array[Vector3]:
	var points: Array[Vector3] = []
	_last_flight = {}
	if incoming_traj_mesh: incoming_traj_mesh.clear_surfaces()
	if ball == null or not ball.is_in_play or ball.linear_velocity.length() < 0.5:
		if incoming_traj_instance: incoming_traj_instance.hide()
		return points


	if not RuntimePolicy.developer_tools and (ball.last_hit_by == _player.player_num or ball.linear_velocity.dot( - _player._get_forward_axis()) < 0.1):
		return points
	_last_flight = BallFlightPredictor.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity)
	if not RuntimePolicy.developer_tools: return points
	var samples: Array = _last_flight.samples
	for sample in samples: points.append(sample.pos)

	if incoming_traj_mesh and _trajectory_visible and points.size() > 1:
		incoming_traj_mesh.surface_begin(Mesh.PRIMITIVE_LINES, incoming_traj_material)
		for i in range(points.size() - 1):
			if i % 6 < 4:
				incoming_traj_mesh.surface_add_vertex(points[i] + Vector3.UP * 0.03)
				incoming_traj_mesh.surface_add_vertex(points[i + 1] + Vector3.UP * 0.03)
		incoming_traj_mesh.surface_end()
	if incoming_traj_instance: incoming_traj_instance.visible = _trajectory_visible
	return points

func update_human_intercept_pools(ball: RigidBody3D) -> void :
	_last_trajectory_points = draw_incoming_trajectory(ball)

	for nodes in [human_prebounce_indicators, human_postbounce_indicators, human_prebounce_dashlines, human_prebounce_labels, human_postbounce_labels]:
		for node in nodes:
			if node: node.visible = false
