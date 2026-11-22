extends SubViewportContainer
## Main-menu backdrop (visual only): the real match court, built by the game's own
## builders (court, lines, net, barangay world with its crowd and buildings), with a
## real-size pickleball resting on it. The camera sits low behind the ball, holding it in
## the lower-right corner, and the slow-mo lens (shaders/slowmo_lens) is a heavy
## tilt-shift focused on the ball.
##
## Easter egg: flick the ball and it rolls across the court that way. The camera swings
## round behind it (orbiting toward the roll direction) and follows it, keeping it in its
## corner. The ball stays on the pavement: it bounces softly off the curb and the net.
## It never turns on its own.

const Pal := preload("res://scripts/environment/env_palette.gd")
const BallShader := preload("res://shaders/menu_ball.gdshader")
const LensShader := preload("res://shaders/slowmo_lens.gdshader")
const NetProfile := preload("res://scripts/net_profile.gd")

const BALL_R := 0.0375               # a real pickleball (74 mm)
const BALL_SCREEN := Vector2(0.72, 0.8)
const BALL_GAIN := 2.1
const CAM_BACK := 0.46               # metres behind the ball
const CAM_UP := 0.15                 # metres above the ball centre
const START := Vector3(1.6, 0.0, 6.4)          # near baseline, right of centre
const SLAB := Vector2(7.5, 14.0)               # barangay_world SLAB: the pavement
const FLICK_GAIN := 0.0028           # screen px/s -> m/s
const MAX_SPEED := 8.0
const FRICTION := 0.9                # 1/s
const ORBIT_RATE := 2.2              # 1/s: how fast the camera swings behind the roll

var _view: SubViewport
var _cam: Camera3D
var _ball: MeshInstance3D
var _shadow: MeshInstance3D
var _world: Node3D
var _court: Node3D                   # stand-in "game" the court builders work on
var _lens: ShaderMaterial
var _pos := START                    # ball position on the floor
var _floor_y := 0.075
var _vel := Vector2.ZERO             # (x, z) m/s
var _yaw := 0.0                      # camera heading (0 = looking toward -z)
var _spin := Basis.from_euler(Vector3(0.35, 0.6, 0.12))
var _drag: Array = []
var _dragging := false
var _built := false


## The court builders and the barangay world read a few things off the game; this
## stand-in answers them for a quiet court between matches.
class MenuCourt extends Node3D:
	var game_state := 0
	var score_left := 0
	var score_right := 0
	var ball = null
	var rally_scorer = null
	var game_serve = null
	var doubles_mode := false
	func view_flipped() -> bool: return false


func _ready() -> void:
	name = "MenuBallScene"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	stretch_shrink = 2
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_DISABLED
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	_world = Node3D.new()
	_view.add_child(_world)
	_build_environment()
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.near = 0.02
	_cam.current = true
	_world.add_child(_cam)
	_build_ball()
	_build_lens()
	_place()
	# The court and the barangay are a big build: let the menu draw first.
	_build_court.call_deferred()


func _build_environment() -> void:
	# the match's own sky, light and Filmic tonemap, so the court looks as it does in play
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.52, 0.85)
	sky_mat.sky_horizon_color = Color(0.78, 0.86, 0.95)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.1, 0.13, 0.18)
	sky_mat.ground_horizon_color = Color(0.38, 0.42, 0.5)
	sky.sky_material = sky_mat
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.42
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = environment
	_world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 35, 0)
	sun.light_energy = 1.8
	sun.light_color = Color(1.0, 0.96, 0.88)
	_world.add_child(sun)


func _build_court() -> void:
	_court = MenuCourt.new()
	_court.name = "MenuCourt"
	_world.add_child(_court)
	var court_helper = load("res://scripts/court.gd").new()
	var net_helper = load("res://scripts/net.gd").new()
	court_helper.create_court(_court)
	court_helper.create_lines(_court)
	net_helper.create_net(_court)
	var branding = preload("res://scripts/court_branding.gd").new()
	_court.add_child(branding)
	branding.setup(_court)
	_built = true
	_place()


func _build_ball() -> void:
	_ball = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = BALL_R
	s.height = BALL_R * 2.0
	s.radial_segments = 48
	s.rings = 24
	_ball.mesh = s
	var m := ShaderMaterial.new()
	m.shader = BallShader
	# the standard neon yellow-green of a real pickleball (no glow), compensated for the
	# match's Filmic tonemap like the rest of the art
	var cols := {"dark": "#8fae16", "mid": "#c2e126", "light": "#d0ec30", "rim_col": "#dcf448",
		"hole_col": "#2f4204", "lip_col": "#8fae16"}
	# Raw colours pushed through the Filmic curve (the palette's 208/255 ceiling made the
	# ball olive); BALL_GAIN is tuned so its mid tone reads as #d2ee2c-ish on screen.
	for k in cols: m.set_shader_parameter(k, Color(cols[k]))
	m.set_shader_parameter("gain", BALL_GAIN)
	_ball.material_override = m
	_ball.basis = _spin
	_world.add_child(_ball)
	_shadow = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = BALL_R * 0.8
	disc.bottom_radius = BALL_R * 0.8
	disc.height = 0.001
	_shadow.mesh = disc
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0.03, 0.04, 0.05, 0.6)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow.material_override = sm
	_world.add_child(_shadow)


func _build_lens() -> void:
	_lens = ShaderMaterial.new()
	_lens.shader = LensShader
	_lens.render_priority = Material.RENDER_PRIORITY_MIN
	_lens.set_shader_parameter("effect_mix", 1.0)
	_lens.set_shader_parameter("strength", 0.06)
	_lens.set_shader_parameter("desaturate", 0.15)
	_lens.set_shader_parameter("max_blur", 0.026)
	_lens.set_shader_parameter("focus_band", 0.16)    # the ball, front to back
	_lens.set_shader_parameter("defocus_gain", 3.0)
	_lens.set_shader_parameter("near_strength", 1.0)
	_lens.set_shader_parameter("ball_uv", Vector2(-2, -2))
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _lens
	mi.extra_cull_margin = 16384.0
	mi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	_world.add_child(mi)


## Ball, shadow and camera for the current position and heading. The camera sits behind
## the ball along the heading and is turned so the ball lands at BALL_SCREEN.
func _place() -> void:
	if _cam == null or _view == null: return
	var centre := Vector3(_pos.x, _floor_y + BALL_R, _pos.z)
	_ball.position = centre
	_shadow.position = Vector3(_pos.x, _floor_y + 0.002, _pos.z)
	var fwd := Vector3(sin(_yaw), 0.0, -cos(_yaw))
	_cam.position = centre - fwd * CAM_BACK + Vector3.UP * CAM_UP
	_cam.look_at(centre, Vector3.UP)
	var vs := Vector2(_view.size)
	if vs.x > 1.0 and vs.y > 1.0:
		# turn so the ball sits at BALL_SCREEN instead of the centre (keep_height fov)
		var ndc := (BALL_SCREEN - Vector2(0.5, 0.5)) * 2.0
		var tv := tan(deg_to_rad(_cam.fov) * 0.5)
		var th := tv * vs.x / vs.y
		_cam.rotate_object_local(Vector3.UP, atan(ndc.x * th))
		_cam.rotate_object_local(Vector3.RIGHT, atan(ndc.y * tv))
	_lens.set_shader_parameter("focus_depth", _cam.position.distance_to(centre))


## Flick input: a press on (or near) the ball starts a flick; the release speed rolls it.
func _input(event: InputEvent) -> void:
	if _ball == null or _cam == null: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _near_ball(event.position):
				_dragging = true
				_drag = [[Time.get_ticks_usec(), event.position]]
				_vel *= 0.3          # catching it slows it
				get_viewport().set_input_as_handled()
		elif _dragging:
			_dragging = false
			_drag.append([Time.get_ticks_usec(), event.position])
			_flick()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		_drag.append([Time.get_ticks_usec(), event.position])
		while _drag.size() > 2 and int(_drag[-1][0]) - int(_drag[0][0]) > 120000: _drag.pop_front()
		get_viewport().set_input_as_handled()   # a flick across the menu does not hover buttons


func _near_ball(at: Vector2) -> bool:
	var k := float(stretch_shrink)
	var c := _cam.unproject_position(_ball.position) * k
	var edge := _cam.unproject_position(_ball.position + _cam.global_basis.x * BALL_R) * k
	return at.distance_to(c) < c.distance_to(edge) * 1.25 + 24.0


## The flick in screen space becomes a roll on the court relative to where the camera
## looks: up the screen rolls away from the camera, sideways rolls across.
func _flick() -> void:
	if _drag.size() < 2: return
	var a: Array = _drag[0]
	var b: Array = _drag[-1]
	var dt := maxf(float(int(b[0]) - int(a[0])) / 1000000.0, 0.016)
	var sv: Vector2 = (Vector2(b[1]) - Vector2(a[1])) / dt
	if sv.length() < 60.0: return
	var fwd := Vector2(sin(_yaw), -cos(_yaw))      # (x, z) the camera looks along
	var right := Vector2(cos(_yaw), sin(_yaw))
	_vel = (right * sv.x - fwd * sv.y) * FLICK_GAIN
	_vel = _vel.limit_length(MAX_SPEED)


func _process(delta: float) -> void:
	if _ball == null: return
	if _vel.length_squared() > 0.0001:
		var step := _vel * delta
		var nx := _pos.x + step.x
		var nz := _pos.z + step.y
		# the pavement edge (curb): bump back softly
		var lim := SLAB - Vector2(0.25, 0.25)
		if absf(nx) > lim.x:
			_vel.x *= -0.4
			nx = clampf(nx, -lim.x, lim.x)
		if absf(nz) > lim.y:
			_vel.y *= -0.4
			nz = clampf(nz, -lim.y, lim.y)
		# the net: a wall across the court between the posts
		if absf(nx) < NetProfile.HALF_SPAN + 0.1 and _pos.z != 0.0 and signf(nz) != signf(_pos.z):
			_vel.y *= -0.35
			nz = signf(_pos.z) * 0.06
		var move := Vector3(nx - _pos.x, 0.0, nz - _pos.z)
		_pos.x = nx
		_pos.z = nz
		# roll: turn about the axis across the motion by distance / radius
		if move.length_squared() > 1e-10:
			var axis := Vector3.UP.cross(move.normalized())
			_spin = Basis(axis, move.length() / BALL_R) * _spin
			_ball.basis = _spin.orthonormalized()
		# the camera swings round behind the roll
		var heading := atan2(_vel.x, -_vel.y)
		var turn := wrapf(heading - _yaw, -PI, PI)
		_yaw += turn * (1.0 - exp(-ORBIT_RATE * delta)) * clampf(_vel.length() / 1.5, 0.0, 1.0)
		_vel *= exp(-FRICTION * delta)
		_vel = _vel.move_toward(Vector2.ZERO, 0.3 * delta)
	_place()
