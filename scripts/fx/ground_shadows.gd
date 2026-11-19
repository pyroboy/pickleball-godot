extends Node3D


const FLOOR_Y: = Ball.FLOOR_Y + 0.0045
const ShaderSource = preload("res://shaders/ground_shadow.gdshader")
const BallShaderSource = preload("res://shaders/ball_ground_shadow.gdshader")
# Matches the visible 16 x 40 m apron. The ball cue is also useful after an out.
const BALL_APRON_HALF_SIZE: = Vector2(8.0, 20.0)
const BALL_MIN_DIAMETER: = 0.30
const BALL_MAX_DIAMETER: = 0.48
const BALL_MIN_OPACITY: = 0.48
const BALL_MAX_OPACITY: = 0.72
# Player blob ellipse (metres, x by z) and its opacity at ground level.
const PLAYER_BLOB: = Vector2(0.95, 0.62)
const PLAYER_OPACITY: = 0.42
var _targets: Array[Node3D] = []
var _shadows: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []

func setup(ball: Node3D, left: Node3D, right: Node3D, roster: Array = []) -> void :
	name = "GroundShadows"
	_disconnect_ball_visibility()
	for shadow in _shadows: shadow.free()
	_shadows.clear()
	_materials.clear()
	_targets = [ball]
	for actor in (roster if not roster.is_empty() else [left, right]):
		if is_instance_valid(actor) and actor not in _targets: _targets.append(actor)
	for i in range(_targets.size()):
		var shadow: = MeshInstance3D.new()
		shadow.name = "BallShadow" if i == 0 else "PlayerShadow%d" % i
		var plane: = PlaneMesh.new()
		plane.size = Vector2.ONE
		shadow.mesh = plane
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material: = ShaderMaterial.new()
		material.shader = BallShaderSource if i == 0 else ShaderSource
		if i == 0:
			material.set_shader_parameter("apron_half_size", BALL_APRON_HALF_SIZE)
		shadow.material_override = material
		shadow.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved every frame
		add_child(shadow)
		_shadows.append(shadow)
		_materials.append(material)
	# Visibility can change during a paused editor or offscreen retrieval. These
	# signals prevent a stale sibling blob without making paused shadows process.
	if is_instance_valid(ball):
		ball.visibility_changed.connect(update_shadows)
		ball.tree_exiting.connect(_hide_ball_shadow)
	update_shadows()

func _disconnect_ball_visibility() -> void :
	if _targets.is_empty() or not is_instance_valid(_targets[0]): return
	var ball: Node3D = _targets[0]
	if ball.visibility_changed.is_connected(update_shadows):
		ball.visibility_changed.disconnect(update_shadows)
	if ball.tree_exiting.is_connected(_hide_ball_shadow):
		ball.tree_exiting.disconnect(_hide_ball_shadow)

func _hide_ball_shadow() -> void :
	if not _shadows.is_empty() and is_instance_valid(_shadows[0]): _shadows[0].hide()

func _exit_tree() -> void :
	_disconnect_ball_visibility()

func _process(_delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_process(_delta)
	PerfMonitor.record("proc.ground_shadows", Time.get_ticks_usec() - _pt)

func _perf_process(_delta: float) -> void:
	update_shadows()

static func cue_for_height(height: float, ball: bool) -> Vector3:
	var h: float = maxf(height, 0.0)
	if ball:
		var lift: float = clampf(h / (Ball.FLIGHT_CEILING_Y - Ball.FLOOR_Y - Ball.BALL_RADIUS), 0.0, 1.0)
		var diameter: float = lerpf(BALL_MIN_DIAMETER, BALL_MAX_DIAMETER, lift)
		return Vector3(diameter, diameter, lerpf(BALL_MAX_OPACITY, BALL_MIN_OPACITY, lift))
	var lift: float = clampf(h / 1.0, 0.0, 1.0)
	# Player blob (cards cast no shadow): a soft dark ellipse under the feet, a touch
	# darker when planted and shrinking / fading as the player leaves the ground.
	return Vector3(lerpf(PLAYER_BLOB.x, PLAYER_BLOB.x * 0.72, lift), lerpf(PLAYER_BLOB.y, PLAYER_BLOB.y * 0.72, lift), lerpf(PLAYER_OPACITY, PLAYER_OPACITY * 0.4, lift))

func update_shadows() -> void :
	for i in range(_targets.size()):
		var target: Node3D = _targets[i]
		var shadow: MeshInstance3D = _shadows[i]
		if not is_instance_valid(target):
			shadow.visible = false
			continue
		var pos: Vector3 = target.get_meta("render_origin", target.get_global_transform_interpolated().origin)   # drawn, not the 30 Hz tick

		var half_size: Vector2 = BALL_APRON_HALF_SIZE if i == 0 else Vector2(7.7, 11.7)
		shadow.visible = target.is_visible_in_tree() and pos.is_finite() and absf(pos.x) < half_size.x and absf(pos.z) < half_size.y
		if not shadow.visible: continue
		var ground: float = Ball.FLOOR_Y + Ball.BALL_RADIUS if i == 0 else (float(target.get("ground_y")) if "ground_y" in target else 1.0)
		var cue: Vector3 = cue_for_height(pos.y - ground, i == 0)
		shadow.global_position = Vector3(pos.x, FLOOR_Y, pos.z)
		shadow.scale = Vector3(cue.x, 1.0, cue.y)
		_materials[i].set_shader_parameter("opacity", cue.z)
