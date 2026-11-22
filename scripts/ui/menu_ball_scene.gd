extends SubViewportContainer
## Main-menu backdrop (visual only): a big neon pickleball resting on barangay cement in
## the lower-right corner, a faded court line and the red curb beside it, and a blurred
## hint of the barangay behind (houses, bunting, a pole). Rendered at half resolution in
## its own world so it reads as pixels, with the slow-mo lens (shaders/slowmo_lens) set
## to a heavy tilt-shift focused tightly on the ball.

const Kit := preload("res://scripts/environment/env_mesh_kit.gd")
const Pal := preload("res://scripts/environment/env_palette.gd")
const ToonShader := preload("res://shaders/env_toon.gdshader")
const FloorShader := preload("res://shaders/env_floor.gdshader")
const BallShader := preload("res://shaders/menu_ball.gdshader")
const LensShader := preload("res://shaders/slowmo_lens.gdshader")

const BALL_R := 0.4                  # a big ball: it is the menu's hero
const BALL_SCREEN := Vector2(0.72, 0.8)
const BALL_DEPTH := 3.8
const SCENE_GAIN := 1.0              # scenery under the linear tonemap

var _view: SubViewport
var _cam: Camera3D
var _ball: MeshInstance3D
var _world: Node3D
var _ground: Node3D             # floor, curb and backdrop: moved to meet the ball
var _lens: ShaderMaterial
var _t := 0.0
var _rest := Vector3.ZERO


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
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("17202a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.55)
	# Linear: the Filmic chain in the match caps colours near 218/255 and dulled the
	# ball; here it shows its true neon yellow-green.
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.position = Vector3(0.0, 1.05, 0.0)
	_cam.rotation = Vector3(deg_to_rad(-17.0), 0.0, 0.0)
	_cam.current = true
	_world.add_child(_cam)
	_ground = Node3D.new()
	_world.add_child(_ground)
	_build_floor()
	_build_backdrop()
	_build_ball()
	_build_lens()
	resized.connect(_place)
	_place.call_deferred()


func _toon() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ToonShader
	m.set_shader_parameter("gain", SCENE_GAIN)
	m.set_shader_parameter("light_dir", Vector3(-0.4, 0.7, 0.6))
	m.set_shader_parameter("haze", Pal.hex("#3a4656"))
	m.set_shader_parameter("haze_range", Vector2(10.0, 40.0))
	m.set_shader_parameter("haze_max", 0.55)
	return m


func _build_floor() -> void:
	var f := ShaderMaterial.new()
	f.shader = FloorShader
	# the same cement as the court, a touch darker: late afternoon
	var cols := {"cement": "#8f8d86", "cement_dk": "#83817a", "cement_lt": "#9c9a92", "patch_col": "#76746d",
		"crack": "#55524d", "stain": "#7b766b", "bball": "#cdb257", "kitchen": "#6f8f6c", "gutter": "#2f2d2a",
		"grate": "#5c5a56", "dirt": "#8f7558", "dirt_dk": "#7e6449", "dirt_lt": "#9d8364", "grass": "#6c8c48",
		"grass_dk": "#577539"}
	for k in cols: f.set_shader_parameter(k, Pal.hex(cols[k]))
	f.set_shader_parameter("gain", SCENE_GAIN)
	f.set_shader_parameter("slab_half", Vector2(6.0, 11.2))
	f.set_shader_parameter("gutter_x", Vector2(6.28, 6.64))
	var g := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	g.mesh = plane
	g.material_override = f
	g.name = "Floor"
	_ground.add_child(g)
	# the red curb running away from the ball toward the houses
	var st := Kit.begin()
	var paint := [Pal.hex("#b5463a"), Pal.hex("#c25a4c"), Pal.hex("#a8473f")]
	var z := 1.0
	var i := 0
	while z > -14.0:
		Kit.box(st, Vector3(6.11, 0.05, z - 0.3), Vector3(0.22, 0.1, 0.58), paint[i % 3])
		z -= 0.6
		i += 1
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _toon()
	_ground.add_child(mi)


func _build_backdrop() -> void:
	# a row of barangay houses, a pole and bunting far behind (lens-blurred to shapes)
	var st := Kit.begin()
	var walls := ["#d9c9a3", "#9fc3c9", "#e3b4a0", "#c9d6a3", "#f0e6cf", "#b9b0d6", "#e6cf8a"]
	var roofs := ["#8a5a44", "#5f6b73", "#7b4a3a", "#6f7f86"]
	var x := -14.0
	var k := 0
	while x < 16.0:
		var w := 3.2 + float((k * 7) % 5) * 0.5
		var h := 3.0 + float((k * 3) % 4) * 0.9
		var z := -16.0 - float((k * 5) % 3) * 1.4
		var c := Pal.hex(walls[k % walls.size()])
		Kit.box(st, Vector3(x + w * 0.5, h * 0.5, z), Vector3(w - 0.2, h, 3.0), c)
		Kit.box(st, Vector3(x + w * 0.5, h + 0.2, z + 0.1), Vector3(w + 0.2, 0.4, 3.4), Pal.hex(roofs[k % roofs.size()]))
		for wx: float in [0.28, 0.68]:
			Kit.box(st, Vector3(x + w * wx, h * 0.55, z + 1.52), Vector3(0.7, 0.8, 0.05), Pal.hex("#2a3440"))
		x += w
		k += 1
	Kit.cylinder(st, Vector3(-2.5, 0, -12.5), 0.14, 0.1, 7.5, Pal.hex("#9e9b94"), 6)
	var flags := ["#e0473b", "#f2c84b", "#3e7fd0", "#f2f0ea", "#7cc490", "#f29ac0"]
	var a := Vector3(-2.5, 6.2, -12.5)
	var b := Vector3(9.0, 5.4, -14.5)
	Kit.rope(st, a, b, 0.6, 0.02, Pal.hex("#efe8d8"), 10)
	for i in 26:
		var t := (i + 0.5) / 26.0
		var p := Kit.rope_point(a, b, 0.6, t)
		Kit.tri(st, p + Vector3(-0.14, 0, 0), p + Vector3(0, -0.32, 0.01), p + Vector3(0.14, 0, 0), Pal.hex(flags[i % flags.size()]), 0.0, true)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _toon()
	_ground.add_child(mi)


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
	# display colours, compensated for the Filmic tonemap like the rest of the art
	# the standard neon yellow-green of a real pickleball (no glow)
	var cols := {"dark": "#a0bf1d", "mid": "#d2ee2c", "light": "#e4f854", "rim_col": "#eefc8a",
		"hole_col": "#46600a", "lip_col": "#b3d324"}
	for k in cols: m.set_shader_parameter(k, Color(cols[k]))
	m.set_shader_parameter("gain", 1.0)
	_ball.material_override = m
	_world.add_child(_ball)
	# contact shadow: a dark flattened disc under the ball
	var sh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = BALL_R * 0.72
	disc.bottom_radius = BALL_R * 0.72
	disc.height = 0.002
	sh.mesh = disc
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0.03, 0.04, 0.05, 0.6)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sh.material_override = sm
	sh.name = "BallShadow"
	_world.add_child(sh)


func _build_lens() -> void:
	_lens = ShaderMaterial.new()
	_lens.shader = LensShader
	_lens.render_priority = Material.RENDER_PRIORITY_MIN
	_lens.set_shader_parameter("effect_mix", 1.0)
	_lens.set_shader_parameter("strength", 0.3)
	_lens.set_shader_parameter("desaturate", 0.35)
	_lens.set_shader_parameter("max_blur", 0.028)
	_lens.set_shader_parameter("focus_band", 1.3)   # the whole ball, front to back
	_lens.set_shader_parameter("defocus_gain", 3.2)
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


## Put the ball in the lower-right corner of whatever screen shape we have, resting on
## the floor (the floor plane moves to meet it), and focus the lens on it.
func _place() -> void:
	if _view == null or _cam == null: return
	var vs := Vector2(_view.size)
	if vs.x < 2.0 or vs.y < 2.0: return
	var centre := _cam.project_position(vs * BALL_SCREEN, BALL_DEPTH)
	_rest = centre
	var floor_y := centre.y - BALL_R
	# the slab edge and red curb run just right of the ball
	_ground.position = Vector3(centre.x + 0.95 - 6.11, floor_y, 0.0)
	for child in _world.get_children():
		if child is MeshInstance3D and child.name == "BallShadow":
			child.position = Vector3(centre.x, floor_y + 0.003, centre.z)
	_lens.set_shader_parameter("focus_depth", _cam.global_position.distance_to(centre))
	_ball.position = centre


func _process(delta: float) -> void:
	if _ball == null: return
	_t += delta
	# a slow turn and a gentle settle, stepped at 12 Hz like the rest of the art
	var tick := floorf(_t * 12.0) / 12.0
	_ball.rotation = Vector3(0.35, tick * 0.35, 0.12 * sin(tick * 0.5))
