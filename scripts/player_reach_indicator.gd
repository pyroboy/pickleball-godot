extends Node3D



const Planner = preload("res://scripts/incoming_contact_planner.gd")
const RingShader = preload("res://shaders/player_reach_rings.gdshader")
const SETTING: = "beta_debug.reach_rings"
const PREPARATION_SETTING: = "beta_debug.preparation_blocks"
const PreparationVisual = preload("res://scripts/preparation_superblock_visual.gd")
var preparation_visual: Node3D
const NORMAL_POSTURES: = [0, 1, 2]


const SAMPLE_FORWARD_MAX: = 1.2
var inner_radius: = 0.0
var outer_radius: = 0.0
var active_band: = 0
var envelope_witness: = Vector3.ZERO
var envelope_pose: PostureDefinition
var _player
var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _enabled: = false
var _display_outer: = -1.0
var planned_movement: = false
var planned_target: = Vector3.ZERO
var _flight_path: MeshInstance3D
var _flight_mesh: ImmediateMesh
var _contact_tip: MeshInstance3D
var _path_revision: = -1

func _ready() -> void :
	_player = get_parent()
	Settings.settings_changed.connect(_on_setting_changed)
	_set_enabled(bool(Settings.get_value(SETTING, false)))
	_set_preparation_enabled(bool(Settings.get_value(PREPARATION_SETTING, false)))

func _on_setting_changed(key: String, value: Variant) -> void :
	if key == SETTING: _set_enabled(bool(value))
	elif key == PREPARATION_SETTING: _set_preparation_enabled(bool(value))

func _set_preparation_enabled(enabled: bool) -> void :


	if enabled and preparation_visual == null:
		preparation_visual = PreparationVisual.new()
		preparation_visual.name = "PreparationBlocks"
		_player.add_child(preparation_visual)
		preparation_visual.top_level = true
		preparation_visual.global_transform = Transform3D.IDENTITY
		preparation_visual.configure(_player)
	if preparation_visual:
		preparation_visual.visible = enabled
		preparation_visual.set_process(enabled)
		if enabled: preparation_visual.sync()

func _set_enabled(enabled: bool) -> void :
	_enabled = enabled
	visible = enabled
	set_process(enabled)
	if not enabled:
		active_band = 0
		return
	if _mesh == null: _build_visual()
	refresh()

func _build_visual() -> void :



	_measure_nominal_envelope()
	var plane: = PlaneMesh.new()
	plane.size = Vector2.ONE * 2.0
	_mesh = MeshInstance3D.new()
	_mesh.name = "GroundReachGuides"
	_mesh.mesh = plane
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = RingShader
	_material.set_shader_parameter("half_extent", outer_radius + 0.15)
	_material.set_shader_parameter("inner_radius", inner_radius)
	_material.set_shader_parameter("outer_radius", outer_radius)
	_mesh.material_override = _material
	add_child(_mesh)

	_flight_mesh = ImmediateMesh.new()
	_flight_path = MeshInstance3D.new()
	_flight_path.name = "IncomingPredictionToContact"
	_flight_path.mesh = _flight_mesh
	_flight_path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flight_path)
	_flight_path.top_level = true
	_flight_path.global_transform = Transform3D.IDENTITY
	var path_material: = StandardMaterial3D.new()
	path_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	path_material.albedo_color = Color(0.85, 0.39, 1.0, 0.9)
	path_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flight_path.material_override = path_material
	_contact_tip = MeshInstance3D.new()
	_contact_tip.name = "PredictedContactPoint"
	var sphere: = SphereMesh.new()
	sphere.radius = 0.045;sphere.height = 0.09
	sphere.radial_segments = 8;sphere.rings = 4
	_contact_tip.mesh = sphere
	_contact_tip.material_override = path_material
	_contact_tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_contact_tip)
	_contact_tip.top_level = true
	_set_display_outer(outer_radius)

func _measure_nominal_envelope() -> void :
	var fwd: Vector3 = _player._get_forward_axis()
	var side: Vector3 = _player._get_forehand_axis()
	for def in PostureLibrary.instance().all_definitions():
		if not def.has_zone: continue
		if def.posture_id in NORMAL_POSTURES:
			inner_radius = maxf(inner_radius, Vector2(def.paddle_forehand_mul, def.zone_forward_offset).length())
		for lateral_fraction in [0.0, 0.5, 1.0]:
			var lateral: float = lerpf(def.zone_x_min, def.zone_x_max, lateral_fraction)
			for height_fraction in [0.0, 0.5, 1.0]:
				for step in range(1, 13):
					var front: float = SAMPLE_FORWARD_MAX * float(step) / 12.0
					var point: Vector3 = _player.global_position + side * lateral + fwd * front
					point.y = _player.COURT_FLOOR_Y + lerpf(def.zone_y_min, def.zone_y_max, height_fraction)
					var radius: = Vector2(lateral, front).length()
					if radius <= outer_radius: continue
					var pose: PostureDefinition = Planner.balanced_reach_pose(_player, def, point)
					if pose == null: continue
					outer_radius = radius
					envelope_witness = point
					envelope_pose = pose
	outer_radius = maxf(outer_radius, inner_radius)

func _process(_delta: float) -> void :
	refresh()

func refresh() -> void :
	if not _enabled or _mesh == null: return


	global_position = Vector3(_player.global_position.x, _player.COURT_FLOOR_Y + 0.008, _player.global_position.z)
	global_basis = Basis.IDENTITY
	var game = _player.get_parent()
	visible = _player.visible and not _player.posture.editor_preview_mode and game.game_state != game.GameState.POINT_SCORED and not game.match_over
	active_band = 0
	planned_movement = false
	_material.set_shader_parameter("plan_active", false)
	var human = _player.posture.human_contact
	var ball = _player._get_ball_ref()
	_refresh_prediction_path(human, ball)
	if not visible or human == null or ball == null:
		_material.set_shader_parameter("active_band", 0)
		return



	var valid: bool = not human.contact.is_empty() and human._flight_id == ball.flight_id and ball.is_in_play and ball.last_hit_by != _player.player_num and ball.bounces_since_last_hit < 2 and human.phase <= 1
	if valid:
		var offset: Vector3 = human.contact.point - _player.global_position
		var radius: = Vector2(offset.x, offset.z).length()
		active_band = 2 if bool(human.contact.get("extended", false)) or radius > inner_radius + 0.03 else 1
		_material.set_shader_parameter("contact_direction", Vector2(offset.x, offset.z).normalized())


		var display_outer: float = maxf(outer_radius, radius)
		_set_display_outer(display_outer)
	else:
		_set_display_outer(outer_radius)
	_material.set_shader_parameter("active_band", active_band)


	planned_movement = human.footwork.active and not human.footwork.plan.is_empty() and ball.is_in_play and ball.last_hit_by != _player.player_num and human.footwork._flight_id == ball.flight_id
	if planned_movement:
		planned_target = human.footwork.plan.target_root
		var delta: Vector3 = planned_target - _player.global_position
		var target_offset: = Vector2(delta.x, delta.z)
		_material.set_shader_parameter("plan_active", true)
		_material.set_shader_parameter("plan_target", target_offset)
		var extent: float = maxf(_display_outer + 0.15, target_offset.length() + 0.2)
		_material.set_shader_parameter("half_extent", extent)
		_mesh.scale = Vector3(extent, 1.0, extent)
	else:
		_material.set_shader_parameter("half_extent", _display_outer + 0.15)
		_mesh.scale = Vector3(_display_outer + 0.15, 1.0, _display_outer + 0.15)

func _set_display_outer(radius: float) -> void :
	if is_equal_approx(_display_outer, radius): return
	_display_outer = radius
	_material.set_shader_parameter("outer_radius", radius)
	_material.set_shader_parameter("half_extent", radius + 0.15)
	_mesh.scale = Vector3(radius + 0.15, 1.0, radius + 0.15)

func _refresh_prediction_path(human, ball) -> void :
	if _flight_path == null: return
	var valid: bool = visible and human != null and ball != null and human._flight_id == ball.flight_id and ball.is_in_play and ball.last_hit_by != _player.player_num and human.phase <= 1
	var preparation: Dictionary = human.preparation_contact() if valid else {}
	valid = valid and not preparation.is_empty()
	_flight_path.visible = valid
	_contact_tip.visible = valid
	if not valid: return
	_contact_tip.global_position = preparation.point
	if _path_revision == human.prediction_revision: return
	_path_revision = human.prediction_revision
	_flight_mesh.clear_surfaces()
	var points: PackedVector3Array = human.anticipation_path
	if points.size() < 2: return
	_flight_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for index in range(points.size() - 1):
		_flight_mesh.surface_add_vertex(points[index])
		_flight_mesh.surface_add_vertex(points[index].lerp(points[index + 1], 0.65))
	_flight_mesh.surface_end()
