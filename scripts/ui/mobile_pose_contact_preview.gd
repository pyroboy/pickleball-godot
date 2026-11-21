extends Node3D
## Isolated editor illustration. No collision body, hit registration, or match state.
## The ball touches the solved Contact paddle at t=.5; this is not a hit test.
const D = preload("res://scripts/paddle_dimensions.gd")
const Styles = preload("res://scripts/serve_style.gd")
const Regions = preload("res://scripts/preparation_superblocks.gd")
const PATH_STEPS := 64
var player
var ball: MeshInstance3D
var path: MeshInstance3D
var contact_marker: MeshInstance3D
var block: MeshInstance3D
var contact_point := Vector3.ZERO
var contact_transform := Transform3D.IDENTITY
var serve_style := -1
var _forward := Vector3.FORWARD
var _normal := Vector3.FORWARD
var _serve_plan: Dictionary = {}
var _definition: PostureDefinition
var _show_block := true
var _progress := 0.0

func initialize(owner) -> void:
	player = owner
	if ball != null: return
	name = "EditorContactPreview"
	ball = MeshInstance3D.new(); ball.name = "IllustrativeBall"
	var sphere := SphereMesh.new()
	sphere.radius = Ball.BALL_RADIUS; sphere.height = Ball.BALL_RADIUS * 2.0
	sphere.radial_segments = 24; sphere.rings = 12
	ball.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1, 1, 0); material.roughness = .3
	ball.material_override = material
	add_child(ball)
	contact_marker = MeshInstance3D.new(); contact_marker.name = "SampledPaddleContact"
	var tip := SphereMesh.new(); tip.radius = .012; tip.height = .024
	contact_marker.mesh = tip; contact_marker.material_override = _line_material(Color("71f5da"))
	contact_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(contact_marker)
	path = MeshInstance3D.new(); path.name = "IllustrativeBallPath"
	path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(path)
	block = MeshInstance3D.new(); block.name = "AuthoredContactZone"
	block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(block); block.visible = false
	set_process(false); set_physics_process(false)

func configure(definition: PostureDefinition, solved_contact: Transform3D, style: int = -1) -> void:
	_definition = definition
	contact_transform = solved_contact
	serve_style = style
	_forward = player._get_forward_axis().normalized()
	_normal = solved_contact.basis.z.normalized()
	if _normal.dot(_forward) < 0.0: _normal = -_normal
	contact_point = solved_contact * D.HEAD_OFFSET + _normal * (D.HEAD_HALF_THICKNESS + Ball.BALL_RADIUS)
	contact_marker.global_position = contact_point - _normal * Ball.BALL_RADIUS
	_serve_plan.clear()
	if serve_style >= 0:
		_serve_plan = Styles.release_plan(Vector3(0, player.global_position.y, 0), false, Styles.valid_style(serve_style))
	_build_path()
	_build_block()
	update_progress(_progress)

func update_progress(t: float) -> void:
	_progress = clampf(t, 0.0, 1.0)
	if ball: ball.global_position = ball_position_at(_progress)

func ball_position_at(t: float) -> Vector3:
	t = clampf(t, 0.0, 1.0)
	if t <= .5:
		var u := t * 2.0
		if not _serve_plan.is_empty(): return _serve_position(u)
		# Representative feed into the paddle face, with a modest loft.
		return contact_point + _normal * (1.65 * (1.0 - u)) + Vector3.UP * (.3 * sin(PI * u))
	var u := (t - .5) * 2.0
	return contact_point + _forward * (1.8 * u) + Vector3.UP * (.45 * sin(PI * u))

func _serve_position(u: float) -> Vector3:
	if u >= 1.0: return contact_point
	var elapsed: float = float(_serve_plan.contact_time) * u
	var samples: Array = _serve_plan.samples
	var point: Vector3 = _serve_plan.release_position
	var previous_time := 0.0
	for sample in samples:
		var next_time: float = float(sample.time)
		if next_time >= elapsed:
			point = point.lerp(sample.pos, clampf((elapsed - previous_time) / maxf(next_time - previous_time, .000001), 0.0, 1.0))
			break
		point = sample.pos; previous_time = next_time
	# Preserve the actual release/drop/bounce shape and ground height while
	# adapting its endpoint to the edited Contact pose. Never move the rig.
	var floor_y: float = Ball.FLOOR_Y + Ball.BALL_RADIUS
	var end: Vector3 = _serve_plan.contact_position
	var height_scale: float = maxf(contact_point.y - floor_y, .001) / maxf(end.y - floor_y, .001)
	return Vector3(contact_point.x, floor_y + (point.y - floor_y) * height_scale, contact_point.z)

func _build_path() -> void:
	var material := _line_material(Color("e7db72"))
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for i in range(PATH_STEPS):
		# Dashed guide keeps the motion arc and the ball visually distinct.
		if i % 2 != 0: continue
		mesh.surface_add_vertex(to_local(ball_position_at(float(i) / PATH_STEPS)))
		mesh.surface_add_vertex(to_local(ball_position_at(float(i + 1) / PATH_STEPS)))
	mesh.surface_end(); path.mesh = mesh

func _build_block() -> void:
	for child in block.get_children(): child.free()
	block.visible = _show_block and _definition != null and _definition.has_zone
	if _definition == null or not _definition.has_zone: return
	# Identical bounds and floor extension to authored Preparation blocks.
	var bottom: float = 0.0 if _definition.height_tier == 0 else _definition.zone_y_min
	var dimensions := Vector3(_definition.zone_x_max - _definition.zone_x_min, _definition.zone_y_max - bottom, .15)
	var box := BoxMesh.new(); box.size = dimensions; block.mesh = box
	var color: Color = Regions.COLORS[clampi(_definition.height_tier, 0, 3)]
	var material := _line_material(Color(color, .10))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	block.material_override = material
	var center := Regions.world_point(player, (_definition.zone_x_min + _definition.zone_x_max) * .5, (bottom + _definition.zone_y_max) * .5, _definition.zone_forward_offset)
	block.global_transform = Transform3D(Basis(player._get_forehand_axis(), Vector3.UP, -player._get_forward_axis()), center)
	var mesh := ImmediateMesh.new(); mesh.surface_begin(Mesh.PRIMITIVE_LINES, _line_material(color))
	var half := dimensions * .5
	for axis in range(3):
		for a in [-1.0, 1.0]:
			for b in [-1.0, 1.0]:
				var start := half; var end := half
				start[axis] = -half[axis]
				start[(axis + 1) % 3] *= a; start[(axis + 2) % 3] *= b
				end[(axis + 1) % 3] *= a; end[(axis + 2) % 3] *= b
				mesh.surface_add_vertex(start); mesh.surface_add_vertex(end)
	mesh.surface_end()
	var edges := MeshInstance3D.new(); edges.mesh = mesh
	edges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	block.add_child(edges)

func _line_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material

func dispose() -> void:
	player = null; _definition = null; _serve_plan.clear()
	queue_free()
