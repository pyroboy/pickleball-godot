extends SubViewportContainer
## Easter egg: flick the ball and it rolls that way. The ball stays put on screen while
## the cement, curb and street slide past under it (the camera tracks it), and it spins
## to match the roll, slowing to a stop. It never turns on its own.
##
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
const SCENE_GAIN := 1.7              # scenery under the linear tonemap

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
	env.background_color = Color("9fb4c4")
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
	m.set_shader_parameter("haze_range", Vector2(18.0, 60.0))
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
	f.set_shader_parameter("gain", SCENE_GAIN * 1.35)   # the cement around the ball reads light
	f.set_shader_parameter("slab_half", Vector2(6.0, 11.2))
	f.set_shader_parameter("gutter_x", Vector2(6.28, 6.64))
	var g := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	g.mesh = plane
	g.material_override = f
	_floor_mat = f
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


## Barangay backdrop in three rows at different depths. Each row is one strip mesh drawn
## three times side by side and wrapped around the view, so the street never runs out
## when the flicked ball rolls sideways; perspective gives the parallax.
const LAYERS := [
	# depth z, strip length, kind
	{"z": -14.0, "len": 30.0, "kind": "near"},
	{"z": -24.0, "len": 42.0, "kind": "mid"},
	{"z": -38.0, "len": 60.0, "kind": "far"},
]
var _layers: Array = []      # [{nodes: [Node3D x3], len}]
var _floor_mat: ShaderMaterial
var _base := Vector3.ZERO     # ground placement for the ball's corner
var _travel := Vector2.ZERO   # how far the ball has rolled (x, z), metres
var _vel := Vector2.ZERO      # roll speed (x, z), m/s
var _spin := Basis.from_euler(Vector3(0.35, 0.6, 0.12))   # the ball's orientation (rolling only)
var _drag: Array = []         # recent [usec, Vector2] pointer samples during a flick
var _dragging := false
const FLICK_GAIN := 0.0032    # screen px/s -> m/s
const MAX_SPEED := 9.0
const FRICTION := 1.1         # 1/s
const TRAVEL_Z := Vector2(-6.0, 9.0)   # keep the street rows in front of the camera
const TRAVEL_X := 70.0
var _rng := RandomNumberGenerator.new()

const WALLS := ["#d9c9a3", "#9fc3c9", "#e3b4a0", "#c9d6a3", "#f0e6cf", "#b9b0d6", "#e6cf8a", "#a9cfb4", "#e8b8c6"]
const ROOFS := ["#8a5a44", "#5f6b73", "#7b4a3a", "#6f7f86", "#9a6b3e", "#4f7a8a"]
const FLAGS := ["#e0473b", "#f2c84b", "#3e7fd0", "#f2f0ea", "#7cc490", "#f29ac0"]


func _build_backdrop() -> void:
	_rng.seed = 4321
	for spec in LAYERS:
		var st := Kit.begin()
		var length: float = spec.len
		match str(spec.kind):
			"far": _far_strip(st, float(spec.z), length)
			"mid": _mid_strip(st, float(spec.z), length)
			"near": _near_strip(st, float(spec.z), length)
		var mesh := st.commit()
		var mat := _toon()
		var nodes: Array = []
		for i in 3:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			mi.extra_cull_margin = length
			_ground.add_child(mi)
			nodes.append(mi)
		_layers.append({"nodes": nodes, "len": length})


func _c(code: String) -> Color:
	return Pal.hex(code)


## A barangay house: walls, a pitched or flat roof, windows with frames, a door, sometimes
## an upper storey, a balcony rail or a laundry line.
func _house(st: SurfaceTool, x: float, z: float, w: float, storeys: int) -> void:
	var wall := _c(WALLS[_rng.randi() % WALLS.size()])
	var roof := _c(ROOFS[_rng.randi() % ROOFS.size()])
	var h := 2.8 * storeys
	var d := 4.0
	Kit.box(st, Vector3(x, h * 0.5, z), Vector3(w, h, d), wall)
	if _rng.randf() < 0.6:
		# pitched roof: two slopes and gable triangles
		var ridge := h + 1.2
		var hw := w * 0.5 + 0.25
		var hd := d * 0.5 + 0.3
		Kit.quad(st, Vector3(x - hw, h, z + hd), Vector3(x + hw, h, z + hd), Vector3(x + hw, ridge, z), Vector3(x - hw, ridge, z), roof, 0.0, true)
		Kit.quad(st, Vector3(x + hw, h, z - hd), Vector3(x - hw, h, z - hd), Vector3(x - hw, ridge, z), Vector3(x + hw, ridge, z), roof.darkened(0.15), 0.0, true)
		Kit.tri(st, Vector3(x - w * 0.5, h, z + d * 0.5), Vector3(x - w * 0.5, ridge - 0.1, z), Vector3(x - w * 0.5, h, z - d * 0.5), wall.darkened(0.1), 0.0, true)
		Kit.tri(st, Vector3(x + w * 0.5, h, z - d * 0.5), Vector3(x + w * 0.5, ridge - 0.1, z), Vector3(x + w * 0.5, h, z + d * 0.5), wall.darkened(0.1), 0.0, true)
	else:
		Kit.box(st, Vector3(x, h + 0.12, z), Vector3(w + 0.3, 0.24, d + 0.3), roof)
		if _rng.randf() < 0.5:   # water tank on the flat roof
			Kit.cylinder(st, Vector3(x + w * 0.25, h + 0.24, z - 0.5), 0.45, 0.45, 0.9, _c("#3e7fd0"), 8)
	var front := z + d * 0.5 + 0.03
	for f in storeys:
		var y := 2.8 * f + 1.6
		var n := maxi(1, int(w / 1.6))
		for i in n:
			var wx := x - w * 0.5 + (i + 0.5) * w / n
			if f == 0 and i == n / 2:
				Kit.box(st, Vector3(wx, 1.0, front), Vector3(0.8, 2.0, 0.06), _c("#6b4a33"))
				continue
			Kit.box(st, Vector3(wx, y, front), Vector3(0.8, 0.75, 0.06), _c("#d8d2c0"))
			Kit.box(st, Vector3(wx, y, front + 0.02), Vector3(0.62, 0.58, 0.06), _c("#2a3440"))
		if f > 0 and _rng.randf() < 0.6:   # balcony rail
			Kit.box(st, Vector3(x, 2.8 * f + 0.5, front + 0.45), Vector3(w * 0.8, 0.08, 0.08), _c("#5b5f66"))
			for i in 7:
				Kit.box(st, Vector3(x - w * 0.4 + i * w * 0.8 / 6.0, 2.8 * f + 0.25, front + 0.45), Vector3(0.05, 0.5, 0.05), _c("#5b5f66"))
	if _rng.randf() < 0.4:   # laundry line across the front
		var a := Vector3(x - w * 0.45, 2.2, front + 0.6)
		var b := Vector3(x + w * 0.45, 2.2, front + 0.6)
		Kit.rope(st, a, b, 0.15, 0.02, _c("#d8d2c0"), 6)
		for i in 5:
			var p := Kit.rope_point(a, b, 0.15, (i + 0.5) / 5.0)
			Kit.box(st, p + Vector3(0, -0.3, 0), Vector3(0.4, 0.55, 0.03), _c(FLAGS[_rng.randi() % FLAGS.size()]))


func _store(st: SurfaceTool, x: float, z: float) -> void:
	var w := 4.2
	Kit.box(st, Vector3(x, 1.4, z), Vector3(w, 2.8, 3.6), _c("#9fc3c9"))
	Kit.box(st, Vector3(x, 2.5, z + 1.83), Vector3(w * 0.95, 0.5, 0.06), _c("#e0473b"))       # sign board
	Kit.box(st, Vector3(x, 1.3, z + 1.84), Vector3(w * 0.8, 1.2, 0.04), _c("#2a3440"))         # grille window
	for i in 9:
		Kit.box(st, Vector3(x - w * 0.38 + i * w * 0.095, 1.3, z + 1.88), Vector3(0.04, 1.2, 0.04), _c("#c9c4b8"))
	Kit.quad(st, Vector3(x - w * 0.55, 2.3, z + 1.8), Vector3(x + w * 0.55, 2.3, z + 1.8), Vector3(x + w * 0.55, 2.0, z + 2.8), Vector3(x - w * 0.55, 2.0, z + 2.8), _c("#5f6b73"), 0.0, true)
	Kit.box(st, Vector3(x, 3.0, z), Vector3(w + 0.3, 0.3, 3.9), _c("#7b4a3a"))


func _pole(st: SurfaceTool, x: float, z: float) -> Vector3:
	Kit.cylinder(st, Vector3(x, 0, z), 0.14, 0.1, 7.5, _c("#9e9b94"), 6)
	Kit.box(st, Vector3(x, 7.0, z), Vector3(1.4, 0.1, 0.1), _c("#7d5c3e"))
	return Vector3(x, 7.0, z)


func _tree(st: SurfaceTool, x: float, z: float, s: float) -> void:
	Kit.cylinder(st, Vector3(x, 0, z), 0.22 * s, 0.16 * s, 2.6 * s, _c("#6b4a33"), 6)
	var leaf := [_c("#5f8f3e"), _c("#6fa04a"), _c("#4f7f34")]
	for i in 5:
		var o := Vector3(_rng.randf_range(-0.9, 0.9), _rng.randf_range(0.0, 1.0), _rng.randf_range(-0.6, 0.6)) * s
		Kit.box(st, Vector3(x, 3.1 * s, z) + o, Vector3(1.5, 1.2, 1.4) * s, leaf[i % 3], Basis(Vector3.UP, _rng.randf() * TAU))


func _tricycle(st: SurfaceTool, x: float, z: float) -> void:
	var body := _c(["#3a6fc4", "#d64a3a", "#f2c84b", "#3e9e6a"][_rng.randi() % 4])
	Kit.box(st, Vector3(x, 0.9, z), Vector3(1.6, 1.1, 1.1), body)                    # sidecar
	Kit.box(st, Vector3(x, 1.55, z), Vector3(1.7, 0.12, 1.2), _c("#2a2a2a"))         # roof
	Kit.box(st, Vector3(x + 1.2, 0.8, z - 0.2), Vector3(1.2, 0.5, 0.3), body.darkened(0.2))   # motorbike
	for wx: float in [-0.5, 0.5, 1.6]:
		Kit.cylinder(st, Vector3(x + wx, 0, z + (0.55 if wx < 1.0 else -0.2)), 0.3, 0.3, 0.12, _c("#1e1e1e"), 8)


func _bunting(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	Kit.rope(st, a, b, 0.6, 0.02, _c("#efe8d8"), 10)
	var n := int(a.distance_to(b) / 0.45)
	for i in n:
		var p := Kit.rope_point(a, b, 0.6, (i + 0.5) / n)
		Kit.tri(st, p + Vector3(-0.14, 0, 0), p + Vector3(0, -0.32, 0.01), p + Vector3(0.14, 0, 0), _c(FLAGS[i % FLAGS.size()]), 0.0, true)


func _far_strip(st: SurfaceTool, z: float, length: float) -> void:
	var x := -length * 0.5
	while x < length * 0.5 - 4.0:
		var w := _rng.randf_range(4.0, 6.5)
		if _rng.randf() < 0.25:
			_tree(st, x + w * 0.5, z + 2.5, 1.6)
		_house(st, x + w * 0.5, z - _rng.randf_range(0.0, 3.0), w - 0.3, 2 + int(_rng.randf() < 0.4))
		x += w


func _mid_strip(st: SurfaceTool, z: float, length: float) -> void:
	var x := -length * 0.5
	var poles: Array = []
	var i := 0
	while x < length * 0.5 - 4.0:
		if i % 4 == 2:
			_store(st, x + 2.2, z)
			x += 4.6
		else:
			var w := _rng.randf_range(3.6, 5.2)
			_house(st, x + w * 0.5, z - _rng.randf_range(0.0, 1.0), w - 0.25, 1 + int(_rng.randf() < 0.5))
			x += w
		if i % 3 == 0:
			poles.append(_pole(st, x - 0.3, z + 3.2))
		i += 1
	for j in range(poles.size() - 1):
		var a: Vector3 = poles[j]
		var b: Vector3 = poles[j + 1]
		Kit.rope(st, a + Vector3(0, 0.1, 0), b + Vector3(0, 0.1, 0), 0.5, 0.025, _c("#2e2c30"), 8)
		_bunting(st, a + Vector3(0, -0.8, 0.1), b + Vector3(0, -0.8, 0.1))


func _near_strip(st: SurfaceTool, z: float, length: float) -> void:
	var x := -length * 0.5 + 2.0
	while x < length * 0.5 - 2.0:
		var r := _rng.randf()
		if r < 0.3:
			_tricycle(st, x, z)
			x += _rng.randf_range(5.0, 7.0)
		elif r < 0.6:
			# potted plants by a wall
			for k in 3:
				Kit.cylinder(st, Vector3(x + k * 0.6, 0, z), 0.22, 0.28, 0.45, _c("#b5643f"), 6)
				Kit.box(st, Vector3(x + k * 0.6, 0.75, z), Vector3(0.5, 0.6, 0.5), _c("#6fa04a"), Basis(Vector3.UP, _rng.randf()))
			x += _rng.randf_range(4.0, 6.0)
		elif r < 0.8:
			# a bench and crates
			Kit.box(st, Vector3(x + 0.8, 0.45, z), Vector3(1.8, 0.08, 0.45), _c("#8a5a44"))
			for lx: float in [0.05, 1.55]:
				Kit.box(st, Vector3(x + lx, 0.22, z), Vector3(0.08, 0.44, 0.4), _c("#6b4a33"))
			Kit.box(st, Vector3(x + 2.4, 0.25, z + 0.2), Vector3(0.5, 0.5, 0.4), _c("#d64a3a"))
			Kit.box(st, Vector3(x + 2.4, 0.75, z + 0.2), Vector3(0.5, 0.5, 0.4), _c("#f2c84b"))
			x += _rng.randf_range(5.0, 7.0)
		else:
			_tree(st, x, z - 1.0, 1.0)
			x += _rng.randf_range(4.0, 6.0)


func _build_ball() -> void:
	_ball = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = BALL_R
	s.height = BALL_R * 2.0
	s.radial_segments = 48
	s.rings = 24
	_ball.mesh = s
	_ball.basis = _spin
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
	_lens.set_shader_parameter("strength", 0.06)
	_lens.set_shader_parameter("desaturate", 0.15)
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
	_base = Vector3(centre.x + 0.95 - 6.11, floor_y, 0.0)
	_apply_travel()
	for child in _world.get_children():
		if child is MeshInstance3D and child.name == "BallShadow":
			child.position = Vector3(centre.x, floor_y + 0.003, centre.z)
	_lens.set_shader_parameter("focus_depth", _cam.global_position.distance_to(centre))
	_ball.position = centre


func _apply_travel() -> void:
	_ground.position = _base + Vector3(_travel.x, 0.0, _travel.y)
	if _floor_mat: _floor_mat.set_shader_parameter("pattern_offset", Vector2(_ground.position.x, _ground.position.z))
	# keep each street row's three copies around the view
	for layer in _layers:
		var length: float = layer.len
		var off := fposmod(_ground.position.x, length)
		var nodes: Array = layer.nodes
		for i in 3:
			(nodes[i] as Node3D).position.x = float(i - 1) * length + off - _ground.position.x


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
	var vs := Vector2(_view.size) * float(stretch_shrink)
	var c := vs * BALL_SCREEN
	var edge := _cam.unproject_position(_ball.position + Vector3(BALL_R, 0, 0)) * float(stretch_shrink)
	var r := absf(edge.x - _cam.unproject_position(_ball.position).x * float(stretch_shrink))
	return at.distance_to(c) < r * 1.25 + 20.0


func _flick() -> void:
	if _drag.size() < 2: return
	var a: Array = _drag[0]
	var b: Array = _drag[-1]
	var dt := maxf(float(int(b[0]) - int(a[0])) / 1000000.0, 0.016)
	var sv: Vector2 = (Vector2(b[1]) - Vector2(a[1])) / dt
	if sv.length() < 60.0: return
	# screen right -> +x, screen down -> toward the camera (+z)
	_vel = (sv * FLICK_GAIN).limit_length(MAX_SPEED)


func _process(delta: float) -> void:
	if _ball == null: return
	_t += delta
	if _vel.length_squared() > 0.0001:
		var step := _vel * delta
		# the world slides the other way under the ball; stop at the street ends
		var nt := _travel - step
		if nt.x < -TRAVEL_X or nt.x > TRAVEL_X: _vel.x *= -0.35     # bump off the end, softly
		if nt.y < TRAVEL_Z.x or nt.y > TRAVEL_Z.y: _vel.y *= -0.35
		nt.x = clampf(nt.x, -TRAVEL_X, TRAVEL_X)
		nt.y = clampf(nt.y, TRAVEL_Z.x, TRAVEL_Z.y)
		_travel = nt
		_apply_travel()
		# roll: turn about the axis across the motion by distance / radius
		var move := Vector3(_vel.x, 0.0, _vel.y)
		var axis := Vector3.UP.cross(move.normalized())
		if axis.length_squared() > 0.0001:
			_spin = Basis(axis.normalized(), step.length() / BALL_R) * _spin
			_ball.basis = _spin.orthonormalized()
		_vel *= exp(-FRICTION * delta)
		_vel = _vel.move_toward(Vector2.ZERO, 0.4 * delta)
