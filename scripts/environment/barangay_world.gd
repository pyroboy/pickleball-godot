extends Node3D
## Barangay court world (visual only): the cement slab and its markings, a painted curb
## with chipped corners and a drainage gutter, bamboo net poles in hollow blocks, and
## behind the far end a two-storey house with a balcony, the barangay hall with its flag,
## a sari-sari store, two tricycles, power poles with banderitas, a crowd on Monobloc
## chairs and a bench, chickens and a dog; beside the far half a next-game queue and the
## scorer's table. Rows of houses and trees fill the view out to the horizon.
##
## Everything is real low-poly 3D (scripts/environment/env_mesh_kit.gd, env_figures.gd)
## shaded in three flat bands (shaders/env_toon.gdshader) and pixelated by the
## half-resolution PixelPost. Static props are one merged mesh, swaying cloth another,
## every figure part one MultiMesh. Static shadows are one baked mask drawn by one ground
## layer (see MASK_NEAR); the moving figures' ovals one more MultiMesh.
##
## Gameplay is untouched: nothing has collision, nothing goes under a player, nothing
## writes game state, and randomness uses this node's own seeded generator (the global
## one is shared with the seeded AI). The crowd only listens: ball paddle hits and bounces,
## rally end reasons, serve launch, post hits, the score and `view_flipped()`.
##
## Two ends with their own scenery: the barangay hall end at -z and the pandesal end at
## +z (scripts/environment/pandesal_end.gd, built in a child node turned half a turn so it
## is authored the same way, "far = -z"). After a doubles change of ends the camera looks
## at the other end; only the end in view is animated.

const Kit := preload("res://scripts/environment/env_mesh_kit.gd")
const Fig := preload("res://scripts/environment/env_figures.gd")
const People := preload("res://scripts/environment/env_people.gd")
const Pal := preload("res://scripts/environment/env_palette.gd")
const PandesalEnd := preload("res://scripts/environment/pandesal_end.gd")
const ToonShader := preload("res://shaders/env_toon.gdshader")
const FloorShader := preload("res://shaders/env_floor.gdshader")
const ShadowShader := preload("res://shaders/env_shadow.gdshader")
const NetProfile := preload("res://scripts/net_profile.gd")
const Sun := preload("res://scripts/graphics/sun_light.gd")
const ShadowMask := preload("res://scripts/graphics/shadow_mask.gd")
const MaskShader := preload("res://shaders/shadow_ground.gdshader")
const MaterialPrewarm := preload("res://scripts/graphics/material_prewarm.gd")
const PixelFont := preload("res://assets/fonts/arjo_pixel.fnt")

const SEED := 20261122
const GROUND_Y := 0.066          # just under the court surface (top 0.075)
const SLAB := Vector2(7.5, 14.0)
const VIEW_CULL_UP := 0.9         # crowd cull sphere centre above the feet (m)
const VIEW_CULL_R := 2.2          # and radius: a standing figure with props and its shadow
const TICK := 1.0 / 12.0         # figures move in 12 Hz steps (pixel-art timing, no crawl)
## Golden-hour distance fog (env_toon.gdshader `fog`): by distance outside the court lines
## everything leans toward the warm peach horizon (Sun.HORIZON_COLOR, the sky's horizon
## in game.gd): none for the first FOG.x metres, then 1 - exp(-FOG.y * metres) up to
## FOG.z. The crowd, the near stalls and the hall front keep full colour (< 6 % at 13 m
## out); the far rows of houses and trees recede (about 20 % at 25 m, 45 % at 60 m, 65 %
## at the horizon rows). Props, floor, shadows, crowd cards and signs all use it; players,
## ball, net and court do not.
const PUSH_COL := "#f5c79e"      # Sun.HORIZON_COLOR as hex (signs, `_label`)
const FOG := Vector3(8.0, 0.02, 0.7)
## Static shadows (shadow rework 2026-11-25): every prop registers its caster shape
## (`_shadow`, `_shadow_box`, `_shadow_points`: corner points, node space) and `_bake_mask`
## projects them along the shared sun (Sun.project) into one L8 opacity mask over the
## visible ground (scripts/graphics/shadow_mask.gd), unioned by max. Baked at build and
## again on a change of ends or a court-view swap, never per frame. Drawn by one multiply
## layer (shaders/shadow_ground.gdshader) just above the court lines, under the players'
## shadows. Near mask: 4 cm texels (about a card-art pixel) around both ends of the slab,
## published to ShadowMask; far mask: 15 cm texels for the house rows further out.
const MASK_NEAR := Rect2(-20.0, -34.0, 40.0, 68.0)    # world x, z, size (m)
const MASK_NEAR_TEXEL := 0.04
const MASK_FAR := Rect2(-52.5, -76.5, 105.0, 153.0)
const MASK_FAR_TEXEL := 0.15
const MASK_Y := 0.078            # over the court lines (0.077), under the players' shadows
## People, animals and the pandesal cart move, so theirs are small ovals that follow them
## (env_shadow.gdshader): from the feet along the sun, half the full cast length.
const FIG_REACH := 0.5
const COURT_HALF := Vector2(3.05, 6.705)
const PLAYING := 2               # game.gd GameState.PLAYING
const NET_REASONS := ["BALL_IN_NET", "NET_POST", "NET_TOUCH", "NET_PLANE"]

var _game: Node
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _tick_t := 0.0
var _flipped := false
const SWAY_HZ := 8.0             # the sway moves in steps so its pixels jump cleanly
var _sway_clock := 0.0
var _sway_shown := -1.0
var _toon: ShaderMaterial
var _grimy: ShaderMaterial
var _toon_n: ShaderMaterial      # the pandesal end's copies, lit for that end's facing
var _grimy_n: ShaderMaterial
var _near: Node3D                # the pandesal end (turned half a turn)
var _build_end := 0              # 0: hall end (-z), 1: pandesal end (+z) while building
var _live_end := 0               # the end the camera looks at
var _near_state: Dictionary = {} # pandesal end runtime (vendor, queue, jeepney, ...)
var _floor: ShaderMaterial
var _shadow_mat: ShaderMaterial   # env_shadow: the moving figures' ovals
var _mask_mat: ShaderMaterial     # shadow_ground: the baked static mask
var _cloud_mat: ShaderMaterial
var _mask_near: Image
var _mask_far: Image
var _tex_near: ImageTexture
var _tex_far: ImageTexture
var _casters: Array = []          # [PackedVector3Array points, opacity, banderita, world space, ground y]
var _figs: Array = []             # moving shadows: [pos (node space), radius, height]

var _mm_fig: MultiMesh
var _mm_shadow: MultiMesh
var _people: Array = []          # all people (crowd, watchers, tindera, neighbour, queue, scorer, walkers)
var _walkers: Array = []         # passers-by on the street lanes behind the far end
var _kids: Array = []            # ball kids: fetch balls the players should not walk to
var _fetch_kid: Dictionary = {}  # the kid on the current fetch, if any
var _cards                       # People.CardBatch: every person's pixel cards, one mesh
const PROP_SLOTS := 3            # cube props per person (paddle, bottle, fan, phone, umbrella, bag, taho)
const LANE_A := -14.6            # street lanes behind the crowd (local z)
const LANE_B := -15.9            # only west of the tricycles (x < 5)
const LANE_FAR := -27.6
var _last_cam := Vector3.INF
var _playing := false          # behind the hall, seen between the buildings
var _crowd: Array = []           # the ones who react as a crowd
var _chickens: Array = []
var _cats: Array = []
const CAT_PARTS := 6
var _chicks: Array = []          # follow the first chicken (the hen)
var _hen_trail: Array = []       # the hen's recent positions, newest first
var _dog: Dictionary = {}
var _scorer: Dictionary = {}
var _neighbour: Dictionary = {}

var _ball: Node
var _connected := {}
var _rally_hits := 0
var _check_speed := false
var _score := Vector2i(-1, -1)
var _score_labels: Array = []
var _score_pending := 0.0


func setup(game: Node, parent: Node3D) -> void:
	_game = game
	name = "BarangayWorld"
	parent.add_child(self)
	_rng.seed = SEED
	_toon = ShaderMaterial.new()
	_toon.shader = ToonShader
	_toon.set_shader_parameter("gain", Pal.GAIN)
	Sun.set_flipped(false)   # a new match starts unflipped (static state outlives the scene)
	_toon.set_shader_parameter("light_dir", Sun.to_sun())
	# the side away from the sun is shaded exactly like the ground in a cast shadow
	_toon.set_shader_parameter("dark_band", Vector3(1.07, 1.0, 0.88) * _shade_factor(Sun.SHADOW_OPACITY))
	_set_push(_toon)
	var apron := game.find_child("CourtApron", true, false)
	if apron is Node3D: apron.visible = false       # the floor shader draws slab and dirt
	_build_floor(game)
	# buildings get the weathered material (dirt, streaks, peeling paint, rust)
	_grimy = _toon.duplicate()
	_grimy.set_shader_parameter("grime", 1.0)
	_grimy.set_shader_parameter("grime_dirt", Pal.hex("#7d6a54"))
	_grimy.set_shader_parameter("grime_bare", Pal.hex("#a9a59c"))
	_grimy.set_shader_parameter("grime_rust", Pal.hex("#9a5a3c"))
	var bld := Kit.begin()
	var props := Kit.begin()
	var cloth := Kit.begin()
	_build_curb(props)
	_build_net_poles(game, props)
	_build_house(bld, cloth)
	_build_hall(bld, cloth)
	_build_store(bld)
	_build_poles(props, cloth)
	_build_tricycle(props, Vector3(6.9, 0, -16.2), Pal.hex("#3a6fc4"), 0.12)
	_build_tricycle(props, Vector3(8.9, 0, -15.9), Pal.hex("#d64a3a"), -0.1)
	_build_crowd_area(props)
	_build_queue(props)
	_build_scorer(props)
	_build_background(bld)
	_add_mesh("BarangayBuildings", bld, _grimy)
	_add_mesh("BarangayProps", props)
	_add_mesh("BarangayCloth", cloth)
	# the pandesal end: authored "far = -z" in a child turned half a turn, lit to match
	_near = Node3D.new()
	_near.name = "PandesalEnd"
	_near.transform.basis = Basis(Vector3.UP, PI)
	add_child(_near)
	_toon_n = _toon.duplicate()
	_grimy_n = _grimy.duplicate()
	_build_end = 1
	var nb := Kit.begin()
	var np := Kit.begin()
	var nc := Kit.begin()
	PandesalEnd.build_geometry(self, nb, np, nc)
	_add_mesh("PandesalBuildings", nb, _grimy_n, _near)
	_add_mesh("PandesalProps", np, _toon_n, _near)
	_add_mesh("PandesalCloth", nc, _toon_n, _near)
	_build_end = 0
	_build_clouds()
	_build_figures()
	_build_shadows()
	# pause menu "Court view": which end's scenery faces the camera (saved setting)
	Settings.settings_changed.connect(func(key: String, _v): if key == "video.court_view_swapped": _apply_view())
	_apply_view()
	# The match (not the title's quiet court): draw its materials once while it loads.
	if game.get_script() != null and str(game.get_script().resource_path) == "res://scripts/game.gd":
		MaterialPrewarm.run(game)


# ------------------------------------------------------------------ helpers

func _c(code: String) -> Color:
	return Pal.hex(code)


## The distance fog on a material (env_toon, env_floor, env_shadow, crowd cards).
func _set_push(m: ShaderMaterial) -> void:
	m.set_shader_parameter("fog_col", Pal.comp(Sun.HORIZON_COLOR))
	m.set_shader_parameter("fog", FOG)
	m.set_shader_parameter("court_half", COURT_HALF)


## The fog share at a point (this node's space; symmetric, so either end).
func _push_at(pos: Vector3) -> float:
	var out := Vector2(maxf(absf(pos.x) - COURT_HALF.x, 0.0), maxf(absf(pos.z) - COURT_HALF.y, 0.0)).length()
	return FOG.z * (1.0 - exp(-FOG.y * maxf(out - FOG.x, 0.0)))


func _add_mesh(label: String, st: SurfaceTool, material: Material = null, parent: Node3D = null) -> void:
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = st.commit()
	mi.material_override = material if material != null else _toon
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else self).add_child(mi)


## End-local (authored "far = -z") to this node's space for the end being built.
func _end_pos(v: Vector3, end := -1) -> Vector3:
	return Vector3(-v.x, v.y, -v.z) if (_build_end if end < 0 else end) == 1 else v


## A static caster for the baked shadow mask: a prism with an ellipse (or rectangle)
## footprint of `size` (x, z) at `pos`, from `lift` up to `lift + height` (end-local, like
## every prop). Its shadow is the projection of the prism's corners along the sun.
func _shadow(pos: Vector3, size: Vector2, rect := false, height := 0.0, lift := 0.0) -> void:
	var ring := PackedVector2Array()
	if rect:
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]: ring.append(c * size * 0.5)
	else:
		var n := 12 if maxf(size.x, size.y) > 0.8 else 8
		for k in n: ring.append(Vector2(cos(TAU * k / n), sin(TAU * k / n)) * size * 0.5)
	var pts: Array = []
	for y: float in [lift, lift + maxf(height, 0.02)]:
		for o in ring: pts.append(pos + Vector3(o.x, y, o.y))
	_shadow_points(pts)


## A static caster box (centre, size, turn), end-local.
func _shadow_box(center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	var pts: Array = []
	for k in 8:
		pts.append(center + basis * (Vector3(1 if k & 1 else -1, 1 if k & 2 else -1, 1 if k & 4 else -1) * size * 0.5))
	_shadow_points(pts)


## A static caster from its corner points (end-local); its shadow is their projection's
## convex hull. `world`: the points are already world space (the net, built by net.gd).
func _shadow_points(pts: Array, opacity := Sun.SHADOW_OPACITY, flag := false, world := false, ground := 0.0) -> void:
	var out := PackedVector3Array()
	for p: Vector3 in pts: out.append(p if world else _end_pos(p))
	_casters.append([out, opacity, flag, world, ground])


## A moving figure's shadow (person, animal, cart): a small oval from its feet along the
## sun (radius m, height m). Returns its index for `_move_shadow`.
func _figure_shadow(pos: Vector3, radius: float, height: float) -> int:
	_figs.append([_end_pos(pos), radius, height, false])
	return _figs.size() - 1


## The toon shade band's linear factor for a shadow at `opacity`: what makes a lit face
## show on screen as lit x mix(1, SHADOW_COLOR, opacity), like the ground in a cast shadow.
## Opaque environment colours go through the tonemap, so the factor is found through the
## same display -> stored LUT as every environment colour (env_palette.gd), on bare cement.
## (The shadow layers themselves multiply what is already on screen: their factor is
## mix(1, SHADOW_COLOR, opacity) as is; measured 2026-11-25, rendered ratio = factor^1.04.)
func _shade_factor(opacity: float) -> Vector3:
	var g := Color("#a3a19a")
	var c := Sun.SHADOW_COLOR
	var f := Vector3(lerpf(1.0, c.r, opacity), lerpf(1.0, c.g, opacity), lerpf(1.0, c.b, opacity))
	var lit := Pal.comp(g).srgb_to_linear()
	var dark := Pal.comp(Color(g.r * f.x, g.g * f.y, g.b * f.z)).srgb_to_linear()
	return Vector3(dark.r / lit.r, dark.g / lit.g, dark.b / lit.b)


## Banderitas from a to b (sag, count), flags and their shadows; shared by both ends.
## Each flag's shadow is its own triangle projected along the sun (the rope is too thin).
func _banderitas(cloth: SurfaceTool, a: Vector3, b: Vector3, sag: float, n: int, flags: Array) -> void:
	Kit.rope(cloth, a, b, sag, 0.015, _c("#efe8d8"), 12, 0.0)
	for i in n:
		var p := Kit.rope_point(a, b, sag, (i + 0.5) / n)
		var tri := [p + Vector3(-0.13, 0, 0), p + Vector3(0.0, -0.3, 0.01), p + Vector3(0.13, 0, 0)]
		Kit.tri(cloth, tri[0], tri[1], tri[2], flags[i % flags.size()], 0.55, true)
		_shadow_points(tri, Sun.SHADOW_OPACITY, true)


func _label(text: String, pos: Vector3, height: float, color: Color, yaw := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = PixelFont
	l.font_size = 9        # the bitmap font's own size (arjo_pixel.fnt), so it is not rescaled
	l.pixel_size = height / 9.0
	l.modulate = color      # never greyed: thin 1-texel strokes need their full contrast
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD   # hard glyph edges, opaque pass (no blending/sorting)
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	l.position = pos
	l.rotation.y = yaw
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(_near if _build_end == 1 else self).add_child(l)
	return l


# ------------------------------------------------------------------ floor, curb, net

func _build_floor(game: Node) -> void:
	_floor = ShaderMaterial.new()
	_floor.shader = FloorShader
	# cement tones kept close together (wear reads as texture, not as camouflage patches)
	var cols := {"cement": "#a3a19a", "cement_dk": "#9a9891", "cement_lt": "#aba9a2", "patch_col": "#8f8d86",
		"crack": "#6c6964", "stain": "#958f84", "bball": "#d6bb5e", "kitchen": "#7fa07c", "gutter": "#3b3936",
		"grate": "#6c6a66", "dirt": "#a88a68", "dirt_dk": "#957857", "dirt_lt": "#b89a78", "grass": "#7fa356",
		"grass_dk": "#668c47",
		# slate blue-green court paint: darker than the cement and the kitchen, a little
		# richer than the old worn #345f6c (same hue), still away from the ball
		# (yellow-green) and from both teams' kits (blue, red/orange)
		"court_paint": "#2b5e6e"}
	for k in cols: _floor.set_shader_parameter(k, _c(cols[k]))
	_floor.set_shader_parameter("gain", Pal.GAIN)
	_floor.set_shader_parameter("slab_half", SLAB)
	_floor.set_shader_parameter("court_half", COURT_HALF)
	_set_push(_floor)
	var ground := MeshInstance3D.new()
	ground.name = "BarangayGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(600.0, 600.0)
	ground.mesh = plane
	ground.position = Vector3(0, GROUND_Y, 0)
	ground.material_override = _floor
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	# court_branding.gd sets its own surface material right after this setup returns, so
	# put the shared floor on the court surface one frame later (one seamless slab).
	_cement_court.call_deferred(game)


func _cement_court(game: Node) -> void:
	var surface := game.find_child("CourtSurface", true, false)
	if surface is MeshInstance3D:
		surface.material_override = _floor


func _build_curb(st: SurfaceTool) -> void:
	var paint := [_c("#b5463a"), _c("#c25a4c"), _c("#a8473f"), _c("#c77a6c")]
	var bare := _c("#9c9890")
	var y := GROUND_Y + 0.05
	var w := 0.22
	var x0 := SLAB.x + w * 0.5
	var z0 := SLAB.y + w * 0.5
	# long sides (along z) and short sides (along x), in 0.6 m chunks; corners chipped
	var runs := [[Vector3(-x0, y, -z0), Vector3(-x0, y, z0)], [Vector3(x0, y, -z0), Vector3(x0, y, z0)],
		[Vector3(-x0, y, -z0), Vector3(x0, y, -z0)], [Vector3(-x0, y, z0), Vector3(x0, y, z0)]]
	for run in runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var length := a.distance_to(b)
		var n := int(ceil(length / 0.6))
		var along_z := absf(b.z - a.z) > absf(b.x - a.x)
		for i in n:
			var t0 := float(i) / n
			var t1 := float(i + 1) / n
			var corner := i == 0 or i == n - 1
			var c: Color = paint[_rng.randi() % paint.size()]
			if _rng.randf() < 0.12: c = bare
			var p := a.lerp(b, (t0 + t1) * 0.5)
			var seg := length / n - 0.02
			if corner:
				# chipped: a shorter, lower chunk with bare concrete showing, and rubble
				var keep := seg * 0.55
				var shift := (b - a).normalized() * (seg - keep) * (0.5 if i == 0 else -0.5)
				var size := Vector3(w * 0.8, 0.07, keep) if along_z else Vector3(keep, 0.07, w * 0.8)
				Kit.box(st, p + shift + Vector3(0, -0.015, 0), size, bare)
				for r in 2:
					var rp := p - shift * 1.6 + Vector3(_rng.randf_range(-0.08, 0.08), -0.04, _rng.randf_range(-0.08, 0.08))
					Kit.box(st, rp, Vector3(0.06, 0.04, 0.05), bare, Basis(Vector3.UP, _rng.randf() * TAU))
				continue
			var size := Vector3(w, 0.1, seg) if along_z else Vector3(seg, 0.1, w)
			Kit.box(st, p, size, c)
			if _rng.randf() < 0.25:   # a worn patch on top
				Kit.box(st, p + Vector3(0, 0.051, 0), Vector3(w * 0.5, 0.004, seg * 0.4) if along_z else Vector3(seg * 0.4, 0.004, w * 0.5), bare)
	# the gutter's outer lip on the +x side
	var lip_x := 8.22
	var lip := _c("#8f8b84")
	var k := 0
	var zz := -SLAB.y - 0.3
	while zz < SLAB.y + 0.3:
		Kit.box(st, Vector3(lip_x, GROUND_Y + 0.025, zz + 0.3), Vector3(0.16, 0.05, 0.58), lip.darkened(0.04 * (k % 2)))
		zz += 0.6
		k += 1


func _build_net_poles(game: Node, st: SurfaceTool) -> void:
	# The dark posts' meshes are only drawn (their collision shapes stay); bamboo replaces them.
	for path in ["Net/LeftPost", "Net/RightPost"]:
		var post := game.get_node_or_null(path)
		if post is Node3D: post.visible = false
	var bamboo := _c("#c4ae68")
	var bamboo_dk := _c("#a8964f")
	var node_c := _c("#8b7443")
	var straw := _c("#c9a85e")
	var block := _c("#94918a")
	var hole := _c("#4a4744")
	var h := NetProfile.post_height() + 0.18
	for side: float in [-1.0, 1.0]:
		var x := side * NetProfile.HALF_SPAN
		var base := Vector3(x, NetProfile.FLOOR_Y, 0)
		Kit.cylinder(st, base, 0.05, 0.045, h, bamboo, 6)
		Kit.box(st, base + Vector3(0.025, h * 0.5, 0), Vector3(0.02, h, 0.02), bamboo_dk)
		var y := 0.25
		while y < h - 0.05:
			Kit.cylinder(st, base + Vector3(0, y, 0), 0.056, 0.056, 0.025, node_c, 6)
			y += 0.32
		# straw rope where the net ties on (top and bottom), with a loose end
		var top := NetProfile.top_y_at(x)
		for ty: float in [top - 0.04, NetProfile.FLOOR_Y + 0.12]:
			Kit.cylinder(st, Vector3(x, ty - 0.03, 0), 0.064, 0.064, 0.06, straw, 6)
		Kit.beam(st, Vector3(x + side * 0.05, top - 0.05, 0.02), Vector3(x + side * 0.1, top - 0.28, 0.06), 0.018, straw)
		# two hollow blocks: one the pole stands in, one leaning on it
		for bi in 2:
			var c := base + Vector3(side * (0.0 if bi == 0 else 0.26), 0.1, 0.0 if bi == 0 else 0.05)
			Kit.box(st, c, Vector3(0.4, 0.2, 0.2), block, Basis(Vector3.UP, PI * 0.5 if bi == 0 else 0.25))
			var hb := Basis(Vector3.UP, PI * 0.5 if bi == 0 else 0.25)
			for hz: float in [-0.09, 0.09]:
				Kit.box(st, c + hb * Vector3(hz, 0.1, 0), Vector3(0.12, 0.004, 0.12), hole, hb)
			_shadow_box(c, Vector3(0.4, 0.2, 0.2), hb)
		_shadow(base - Vector3(0, base.y, 0), Vector2(0.1, 0.1), false, base.y + h)   # bamboo pole
	# The net's own shadow (world space, the net stands at z = 0 on the court): the open
	# weave light (Sun.NET_OPACITY), the top tape full; same columns as scripts/net.gd.
	var cols := 24
	for i in cols:
		var xa := lerpf(-NetProfile.HALF_SPAN, NetProfile.HALF_SPAN, float(i) / cols)
		var xb := lerpf(-NetProfile.HALF_SPAN, NetProfile.HALF_SPAN, float(i + 1) / cols)
		var fy: float = NetProfile.FLOOR_Y
		var ta: float = fy + NetProfile.height_at(xa)
		var tb: float = fy + NetProfile.height_at(xb)
		var tape: float = NetProfile.TAPE_WIDTH
		_shadow_points([Vector3(xa, fy, 0), Vector3(xb, fy, 0), Vector3(xb, tb - tape, 0), Vector3(xa, ta - tape, 0)], Sun.NET_OPACITY, false, true, fy)
		_shadow_points([Vector3(xa, ta - tape, 0), Vector3(xb, tb - tape, 0), Vector3(xb, tb, 0), Vector3(xa, ta, 0)], Sun.SHADOW_OPACITY, false, true, fy)


# ------------------------------------------------------------------ far buildings

func _gi_roof(st: SurfaceTool, x0: float, x1: float, z_front: float, z_back: float, y_front: float, y_back: float, rusty: bool) -> void:
	# corrugated galvanized iron: alternating light/dark strips, a few rust streaks
	var light := _c("#a6adb0")
	var dark := _c("#8a9194")
	var rust := _c("#a36a4c")
	var x := x0
	var i := 0
	while x < x1 - 0.01:
		var x2 := minf(x + 0.18, x1)
		var c := light if i % 2 == 0 else dark
		if rusty and _rng.randf() < 0.12: c = rust
		Kit.quad(st, Vector3(x, y_front, z_front), Vector3(x, y_back, z_back), Vector3(x2, y_back, z_back), Vector3(x2, y_front, z_front), c)
		x = x2
		i += 1


func _window(st: SurfaceTool, center: Vector3, size: Vector2, frame: Color, grille: bool) -> void:
	Kit.box(st, center, Vector3(size.x, size.y, 0.04), _c("#2e2a33"))
	Kit.box(st, center + Vector3(0, size.y * 0.5 + 0.03, 0.02), Vector3(size.x + 0.12, 0.06, 0.08), frame)
	Kit.box(st, center + Vector3(0, -size.y * 0.5 - 0.03, 0.03), Vector3(size.x + 0.14, 0.06, 0.1), frame)
	if grille:
		var x := -size.x * 0.5 + 0.1
		while x < size.x * 0.5:
			Kit.box(st, center + Vector3(x, 0, 0.03), Vector3(0.025, size.y, 0.025), _c("#d8d6cf"))
			x += 0.14


func _build_house(st: SurfaceTool, cloth: SurfaceTool) -> void:
	# Two-storey house, top-left corner: hollow-block ground floor, wooden upper floor,
	# balcony with railing and laundry, GI roof weighed down by old tyres.
	var x0 := -11.8
	var x1 := -5.8
	var zf := -18.0
	var zb := -23.0
	var cx := (x0 + x1) * 0.5
	var block := _c("#a9a59c")
	Kit.box(st, Vector3(cx, 1.4, (zf + zb) * 0.5), Vector3(x1 - x0, 2.8, zf - zb), block)
	var y := 0.2
	while y < 2.8:   # block courses on the front
		Kit.box(st, Vector3(cx, y, zf + 0.005), Vector3(x1 - x0, 0.02, 0.01), _c("#97938a"))
		y += 0.2
	_window(st, Vector3(-10.4, 1.5, zf + 0.02), Vector2(1.2, 0.9), _c("#5b8f6a"), true)
	Kit.box(st, Vector3(-7.6, 1.05, zf + 0.02), Vector3(0.9, 2.1, 0.05), _c("#7a5233"))      # door
	Kit.box(st, Vector3(cx, 2.85, (zf + zb) * 0.5 + 0.3), Vector3(x1 - x0 + 0.1, 0.12, zf - zb + 0.6), _c("#8f8b84"))
	var wood := [_c("#a3774f"), _c("#8f6643")]
	var x := x0
	var i := 0
	while x < x1 - 0.01:
		Kit.box(st, Vector3(minf(x + 0.15, x1 - 0.15), 4.2, (zf + zb) * 0.5), Vector3(0.3, 2.6, zf - zb - 0.2), wood[i % 2])
		x += 0.3
		i += 1
	for wx: float in [-10.8, -8.2]:
		_window(st, Vector3(wx, 4.3, zf - 0.08), Vector2(1.1, 1.0), _c("#6fa6c9"), false)
		for jy: float in [3.95, 4.15, 4.35, 4.55]:   # jalousie slats
			Kit.box(st, Vector3(wx, jy, zf - 0.04), Vector3(1.05, 0.04, 0.03), _c("#c8d6dc"))
	# balcony slab, railing, laundry
	var bz := zf + 1.0
	Kit.box(st, Vector3(-9.2, 2.92, (zf + bz) * 0.5), Vector3(3.6, 0.12, 1.0), _c("#9d9991"))
	var rail := _c("#5f8f62")
	Kit.box(st, Vector3(-9.2, 3.95, bz), Vector3(3.6, 0.06, 0.06), rail)
	var px := -11.0
	while px <= -7.35:
		Kit.box(st, Vector3(px, 3.45, bz), Vector3(0.04, 1.0, 0.04), rail)
		px += 0.3
	var la := Vector3(-10.9, 3.9, bz + 0.05)
	var lb := Vector3(-7.5, 3.9, bz + 0.05)
	Kit.rope(cloth, la, lb, 0.06, 0.015, _c("#e8e4da"), 6, 0.0)
	var clothes := [_c("#e85d5d"), _c("#f2f0ea"), _c("#4f8fd8"), _c("#f2c84b"), _c("#7cc490"), _c("#f29ac0")]
	for ci in 6:
		var t := 0.1 + ci * 0.15
		var top := Kit.rope_point(la, lb, 0.06, t)
		var wdt := _rng.randf_range(0.3, 0.42)
		var hgt := _rng.randf_range(0.35, 0.55)
		Kit.quad(cloth, top + Vector3(-wdt * 0.5, 0, 0), top + Vector3(-wdt * 0.5, -hgt, 0.02), top + Vector3(wdt * 0.5, -hgt, 0.02), top + Vector3(wdt * 0.5, 0, 0), clothes[ci], 0.0, false)
		Kit.box(cloth, top + Vector3(0, -hgt * 0.5, 0.012), Vector3(wdt * 0.9, hgt * 0.85, 0.01), clothes[ci], Basis.IDENTITY, false, 0.6)
	_shade_strip(st, x0, x1, zf - 0.08, 5.5, 0.45, wood[0])
	_shade_strip(st, x0, x1, zf + 0.015, 2.86, 0.4, block)
	_gi_roof(st, x0 - 0.3, x1 + 0.3, zf + 0.5, zb - 0.3, 5.75, 5.15, true)
	for tx: float in [-10.6, -7.8]:   # tyres on the roof
		Kit.cylinder(st, Vector3(tx, 5.5, -19.6), 0.32, 0.32, 0.12, _c("#2f2c2e"), 8)
	# cast shadow: the footprint (balcony included) swept along the sun by the roof height
	_shadow(Vector3(cx, 0, (zf + 1.0 + zb) * 0.5), Vector2(x1 - x0 + 0.6, zf + 1.0 - zb), true, 5.6)


const HALL := {"x0": -6.2, "x1": -0.6, "zf": -21.0, "zb": -27.0, "floor": 0.45, "porch": 1.6}


## Ground height for walkers: the hall's raised porch and its front steps.
func _ground_y(pos: Vector3) -> float:
	var x0: float = HALL.x0
	var x1: float = HALL.x1
	var zf: float = HALL.zf
	var pf: float = zf + float(HALL.porch)
	if pos.x < x0 or pos.x > x1 or pos.z < zf - 0.2: return 0.0
	if pos.z <= pf: return HALL.floor
	if absf(pos.x + 3.4) < 0.8 and pos.z < pf + 0.9: return float(HALL.floor) - floor((pos.z - pf) / 0.3) * 0.15
	return 0.0


func _build_hall(st: SurfaceTool, cloth: SurfaceTool) -> void:
	# Barangay hall: raised concrete floor and steps, a porch with columns and a
	# balustrade, a fascia with the sign under a gable pediment, a hipped GI roof,
	# louvred windows, a side window with an awning and an aircon, a meter box, a
	# downspout, a water drum, a porch bench and potted plants.
	var x0: float = HALL.x0
	var x1: float = HALL.x1
	var zf: float = HALL.zf
	var zb: float = HALL.zb
	var fh: float = HALL.floor
	var pf: float = zf + float(HALL.porch)
	var cx := (x0 + x1) * 0.5
	var dx := -3.4
	var wall := _c("#e6d7ad")
	var dado := _c("#7b98b6")
	var blue := _c("#3e6fb2")
	var white := _c("#efe9da")
	var concrete := _c("#a29d93")
	# raised base, porch floor and steps
	Kit.box(st, Vector3(cx, fh * 0.5, (zb + pf) * 0.5), Vector3(x1 - x0 + 0.2, fh, pf - zb), concrete)
	Kit.box(st, Vector3(cx, fh + 0.015, (zf + pf) * 0.5), Vector3(x1 - x0 + 0.2, 0.03, pf - zf), _c("#b5ae9f"))
	Kit.box(st, Vector3(cx, fh - 0.04, pf + 0.02), Vector3(x1 - x0 + 0.22, 0.08, 0.06), _c("#8f8a80"))
	for i in 3:
		var h := fh - (i + 1) * 0.15 + 0.15
		Kit.box(st, Vector3(dx, h * 0.5, pf + (i + 0.5) * 0.3), Vector3(1.6, h, 0.3), _c("#9c978d").darkened(0.04 * i))
	# walls with a two-tone dado and a cornice
	Kit.box(st, Vector3(cx, (fh + 3.75) * 0.5, (zf + zb) * 0.5), Vector3(x1 - x0, 3.75 - fh, zf - zb), wall)
	Kit.box(st, Vector3(cx, fh + 0.45, zf + 0.012), Vector3(x1 - x0, 0.9, 0.02), dado)
	Kit.box(st, Vector3(cx, fh + 0.92, zf + 0.02), Vector3(x1 - x0, 0.05, 0.04), white)
	Kit.box(st, Vector3(cx, 3.68, zf + 0.04), Vector3(x1 - x0 + 0.12, 0.16, 0.1), blue)
	# double door: wood frame, glass upper panels
	Kit.box(st, Vector3(dx, fh + 1.15, zf + 0.02), Vector3(1.55, 2.35, 0.04), _c("#5e4232"))
	for side: float in [-1.0, 1.0]:
		Kit.box(st, Vector3(dx + side * 0.36, fh + 1.45, zf + 0.04), Vector3(0.55, 1.1, 0.02), _c("#9ec3d8"))
		Kit.box(st, Vector3(dx + side * 0.36, fh + 0.5, zf + 0.04), Vector3(0.55, 0.65, 0.02), _c("#6f4f3a"))
	Kit.box(st, Vector3(dx, fh + 1.15, zf + 0.05), Vector3(0.04, 2.3, 0.02), _c("#3e2c22"))
	# louvred windows either side of the door
	for wx: float in [-5.3, -1.5]:
		_window(st, Vector3(wx, fh + 1.55, zf + 0.03), Vector2(1.05, 1.2), white, false)
		for k in 6:
			Kit.box(st, Vector3(wx, fh + 1.05 + k * 0.2, zf + 0.06), Vector3(1.0, 0.05, 0.03), _c("#c8d6dc"))
	# bulletin board with notices
	Kit.box(st, Vector3(-2.35, fh + 1.45, zf + 0.04), Vector3(0.75, 0.6, 0.04), _c("#a07a50"))
	for k in 5:
		Kit.box(st, Vector3(-2.58 + (k % 3) * 0.23, fh + 1.33 + (k / 3) * 0.26, zf + 0.065), Vector3(0.18, 0.2, 0.01), [_c("#f2f0ea"), _c("#f2c84b"), _c("#9ec9e8"), _c("#f29ac0"), _c("#f2f0ea")][k])
	# porch: columns with bases and capitals, balustrade either side of the steps
	var cols := [x0 + 0.2, -4.75, -2.05, x1 - 0.2]
	for col_x: float in cols:
		Kit.box(st, Vector3(col_x, fh + 0.1, pf - 0.18), Vector3(0.38, 0.2, 0.38), white)
		Kit.box(st, Vector3(col_x, (fh + 3.05) * 0.5, pf - 0.18), Vector3(0.26, 3.05 - fh, 0.26), _c("#f1ead6"))
		Kit.box(st, Vector3(col_x, 3.02, pf - 0.18), Vector3(0.36, 0.1, 0.36), white)
	var bays := [[x0 + 0.33, -4.88], [-4.62, dx - 0.85], [dx + 0.85, -2.18], [-1.92, x1 - 0.33]]
	for bay in bays:
		var b0: float = bay[0]
		var b1: float = bay[1]
		if b1 - b0 < 0.2: continue
		Kit.box(st, Vector3((b0 + b1) * 0.5, fh + 0.86, pf - 0.18), Vector3(b1 - b0, 0.07, 0.12), white)
		Kit.box(st, Vector3((b0 + b1) * 0.5, fh + 0.1, pf - 0.18), Vector3(b1 - b0, 0.06, 0.1), white)
		var bx := b0 + 0.08
		while bx < b1 - 0.04:
			Kit.box(st, Vector3(bx, fh + 0.48, pf - 0.18), Vector3(0.06, 0.72, 0.06), _c("#ddd6c4"))
			bx += 0.17
	# porch roof slab and a deep fascia that carries the sign
	Kit.box(st, Vector3(cx, 3.12, (zf + pf) * 0.5 + 0.05), Vector3(x1 - x0 + 0.3, 0.12, pf - zf + 0.3), _c("#d9cfb2"))
	Kit.box(st, Vector3(cx, 3.3, pf + 0.12), Vector3(x1 - x0 + 0.3, 0.6, 0.12), white)
	Kit.box(st, Vector3(cx, 3.02, pf + 0.19), Vector3(x1 - x0 + 0.3, 0.06, 0.02), blue)
	Kit.box(st, Vector3(cx, 3.33, pf + 0.2), Vector3(4.2, 0.46, 0.04), blue)
	_label("BARANGAY HALL", Vector3(cx, 3.33, pf + 0.23), 0.36, Color(1.0, 0.97, 0.88))
	# gable pediment over the entrance, with a round vent
	var pz := pf + 0.13
	var gl := Vector3(-5.35, 3.6, pz)
	var gr := Vector3(-1.45, 3.6, pz)
	var gt := Vector3(dx, 4.85, pz)
	Kit.tri(st, gl, gr, gt, wall, 0.0, true)
	Kit.beam(st, gl + Vector3(-0.1, -0.02, 0.03), gt + Vector3(0, 0.08, 0.03), 0.12, blue)
	Kit.beam(st, gr + Vector3(0.1, -0.02, 0.03), gt + Vector3(0, 0.08, 0.03), 0.12, blue)
	Kit.box(st, Vector3(dx, 3.62, pz + 0.02), Vector3(3.95, 0.08, 0.06), blue)
	Kit.cylinder(st, Vector3(dx, 4.0, pz + 0.01), 0.22, 0.22, 0.03, _c("#3a3640"), 8)
	for k in 3: Kit.box(st, Vector3(dx, 4.12 + k * 0.08 - 0.08, pz + 0.04), Vector3(0.36, 0.025, 0.02), white)
	# pediment roof wings back to the main roof
	_gi_roof(st, -5.5, dx, pz + 0.15, zf, 3.55, 4.95, false)
	_gi_roof(st, dx, -1.3, zf, pz + 0.15, 4.95, 3.55, false)
	# main hipped GI roof
	_gi_roof(st, x0 - 0.4, x1 + 0.4, zf + 0.25, (zf + zb) * 0.5, 3.8, 4.7, false)
	_gi_roof(st, x0 - 0.4, x1 + 0.4, (zf + zb) * 0.5, zb - 0.3, 4.7, 3.8, false)
	_shade_strip(st, x0, x1, zf + 0.022, 3.05, 0.5, wall)
	# right side wall: window with an awning, an aircon, a meter box, downspout, drum
	var sx := x1 + 0.01
	Kit.box(st, Vector3(sx + 0.02, fh + 1.55, -23.0), Vector3(0.04, 1.1, 1.0), _c("#34303a"))
	for k in 5: Kit.box(st, Vector3(sx + 0.05, fh + 1.1 + k * 0.22, -23.0), Vector3(0.03, 0.05, 0.95), _c("#c8d6dc"))
	_gi_roof(st, sx, sx + 0.6, -23.6, -22.4, fh + 2.35, fh + 2.2, true)
	Kit.box(st, Vector3(sx + 0.25, fh + 0.9, -24.4), Vector3(0.5, 0.45, 0.7), _c("#e8e6e0"))
	for k in 4: Kit.box(st, Vector3(sx + 0.51, fh + 0.82 + k * 0.06, -24.4), Vector3(0.01, 0.02, 0.62), _c("#8a8f94"))
	Kit.box(st, Vector3(sx + 0.06, 2.0, -21.6), Vector3(0.1, 0.4, 0.3), _c("#b9bcc0"))
	Kit.beam(st, Vector3(sx + 0.06, 2.2, -21.6), Vector3(sx + 0.06, 3.7, -21.6), 0.03, _c("#2e2c30"))
	Kit.beam(st, Vector3(x1 + 0.08, 3.75, zf + 0.1), Vector3(x1 + 0.08, 0.15, zf + 0.1), 0.08, _c("#8e9396"))
	Kit.box(st, Vector3(x1 + 0.18, 0.12, zf + 0.1), Vector3(0.28, 0.08, 0.12), _c("#8e9396"))
	Kit.cylinder(st, Vector3(x1 + 0.55, 0, -22.4), 0.3, 0.3, 0.85, _c("#3e7fd0"), 8)
	Kit.cylinder(st, Vector3(x1 + 0.55, 0.85, -22.4), 0.31, 0.31, 0.04, _c("#2f5fa8"), 8)
	# porch bench and potted plants by the steps
	Kit.box(st, Vector3(-5.2, fh + 0.42, zf + 0.45), Vector3(1.4, 0.06, 0.35), _c("#9a7048"))
	Kit.box(st, Vector3(-5.2, fh + 0.66, zf + 0.3), Vector3(1.4, 0.3, 0.05), _c("#9a7048"))
	for lx: float in [-5.8, -4.6]: Kit.box(st, Vector3(lx, fh + 0.2, zf + 0.45), Vector3(0.06, 0.4, 0.3), _c("#7d5638"))
	for px: float in [dx - 1.05, dx + 1.05]:
		Kit.cylinder(st, Vector3(px, 0, pf + 0.45), 0.2, 0.25, 0.4, _c("#b5603e"), 6)
		for k in 3:
			Kit.box(st, Vector3(px + (k - 1) * 0.1, 0.55 + (k % 2) * 0.12, pf + 0.45), Vector3(0.22, 0.32, 0.22), [_c("#5f9a55"), _c("#6fab5e"), _c("#4f8a49")][k], Basis(Vector3.UP, k * 0.7))
	_shadow(Vector3(cx, 0, (pf + zb) * 0.5), Vector2(x1 - x0 + 0.4, pf - zb), true, 4.6)
	# flagpole with a Philippine flag that waves (cloth mesh: sway grows along the flag)
	var fx := 0.4
	var fz := -19.0
	Kit.box(st, Vector3(fx, 0.15, fz), Vector3(0.6, 0.3, 0.6), _c("#b9b5ac"))
	Kit.cylinder(st, Vector3(fx, 0.3, fz), 0.05, 0.035, 6.8, _c("#e8e6e0"), 6)
	Kit.cylinder(st, Vector3(fx, 7.1, fz), 0.07, 0.07, 0.08, _c("#d8b84a"), 6)
	_flag(cloth, Vector3(fx + 0.05, 7.0, fz))
	_shadow(Vector3(fx, 0, fz), Vector2(0.6, 0.6), true, 0.3)            # plinth
	_shadow(Vector3(fx, 0, fz), Vector2(0.12, 0.12), false, 7.15)       # flagpole
	_shadow_box(Vector3(fx + 0.05 + 0.65, 6.675, fz), Vector3(1.3, 0.65, 0.02))   # the flag (hung flat)


func _flag(cloth: SurfaceTool, hoist_top: Vector3) -> void:
	var w := 1.3
	var h := 0.65
	var blue := _c("#2f5fb8")
	var red := _c("#cf3a33")
	var white := _c("#f2f0ea")
	var cols := 6
	for i in cols:
		var u0 := float(i) / cols
		var u1 := float(i + 1) / cols
		var s0 := u0 * 0.9
		for half in [0, 1]:
			var y0 := hoist_top.y - (0.0 if half == 0 else h * 0.5)
			var y1 := y0 - h * 0.5
			var c: Color = blue if half == 0 else red
			var a := Vector3(hoist_top.x + u0 * w, y0, hoist_top.z)
			var b := Vector3(hoist_top.x + u0 * w, y1, hoist_top.z)
			var cc := Vector3(hoist_top.x + u1 * w, y1, hoist_top.z)
			var d := Vector3(hoist_top.x + u1 * w, y0, hoist_top.z)
			Kit.quad(cloth, a, b, cc, d, c, s0, true)
	# white triangle at the hoist with the sun (a small yellow square)
	var tri_w := w * 0.42
	Kit.tri(cloth, hoist_top + Vector3(0, 0, 0.01), hoist_top + Vector3(0, -h, 0.01), hoist_top + Vector3(tri_w, -h * 0.5, 0.01), white, 0.15, true)
	Kit.box(cloth, hoist_top + Vector3(tri_w * 0.38, -h * 0.5, 0.015), Vector3(0.12, 0.12, 0.01), _c("#f2c84b"), Basis.IDENTITY, false, 0.15)


func _build_store(st: SurfaceTool) -> void:
	# Sari-sari store: light blue walls, a big window with a white grille, counter ledge,
	# hanging snack strips, an awning, a red sign, crates of bottles by the door.
	var x0 := 2.8
	var x1 := 8.3
	var zf := -18.5
	var zb := -22.5
	var cx := (x0 + x1) * 0.5
	var wall := _c("#86bccd")
	Kit.box(st, Vector3(cx, 1.55, (zf + zb) * 0.5), Vector3(x1 - x0, 3.1, zf - zb), wall)
	# concrete lower wall, painted plywood planks above it
	Kit.box(st, Vector3(cx, 0.45, zf + 0.012), Vector3(x1 - x0, 0.9, 0.03), _c("#a7a29a"))
	Kit.box(st, Vector3(cx, 0.92, zf + 0.03), Vector3(x1 - x0, 0.05, 0.05), _c("#8f8a82"))
	var plank := x0 + 0.3
	while plank < x1:
		Kit.box(st, Vector3(plank, 1.7, zf + 0.008), Vector3(0.025, 1.6, 0.012), wall.darkened(0.18))
		plank += 0.3
	var wx0 := 3.4
	var wx1 := 6.6
	Kit.box(st, Vector3((wx0 + wx1) * 0.5, 1.6, zf + 0.02), Vector3(wx1 - wx0, 1.3, 0.04), _c("#2c2830"))
	Kit.box(st, Vector3((wx0 + wx1) * 0.5, 0.92, zf + 0.25), Vector3(wx1 - wx0 + 0.2, 0.08, 0.5), _c("#9a6d45"))
	var gx := wx0 + 0.1
	while gx < wx1:
		Kit.box(st, Vector3(gx, 1.6, zf + 0.05), Vector3(0.025, 1.3, 0.025), _c("#e6e4dc"))
		gx += 0.16
	var snacks := [_c("#e0473b"), _c("#f2c84b"), _c("#3e7fd0"), _c("#ff9a4a"), _c("#7cc490")]
	var sx := wx0 + 0.25
	var si := 0
	while sx < wx1 - 0.2:
		var drop := _rng.randi_range(3, 6)
		for j in drop:
			Kit.box(st, Vector3(sx, 2.15 - j * 0.1, zf + 0.09), Vector3(0.08, 0.08, 0.02), snacks[(si + j) % snacks.size()])
		sx += 0.32
		si += 1
	Kit.box(st, Vector3(7.5, 1.05, zf + 0.02), Vector3(0.85, 2.1, 0.05), _c("#5e4a3a"))         # door
	# awning (GI sloping toward the court) and the sign above it
	_gi_roof(st, x0 - 0.2, x1 + 0.2, zf + 1.1, zf - 0.05, 2.45, 2.75, true)
	_shade_strip(st, x0, x1, zf + 0.012, 2.45, 0.3, wall)
	Kit.box(st, Vector3(cx, 3.0, zf + 0.04), Vector3(4.6, 0.56, 0.06), _c("#d23b34"))
	_label("SARI-SARI STORE", Vector3(cx, 3.0, zf + 0.09), 0.34, Color(1.0, 0.95, 0.85))
	Kit.box(st, Vector3(cx, 3.4, (zf + zb) * 0.5), Vector3(x1 - x0 + 0.2, 0.15, zf - zb + 0.2), _c("#9aa1a4"))
	for k in 2:   # bottle crates
		var cp := Vector3(8.05, 0.16 + k * 0.3, zf + 0.5)
		Kit.box(st, cp, Vector3(0.45, 0.3, 0.32), _c("#e6b93c"))
		Kit.box(st, cp + Vector3(0, 0.16, 0), Vector3(0.4, 0.04, 0.28), _c("#4a3a2a"))
	# posters and a chalk menu board on the front
	var posters := [[6.95, 1.75, "#f2c84b", "#e0473b"], [7.0, 1.2, "#f2f0ea", "#3e7fd0"], [3.1, 2.15, "#f29ac0", "#2f4f86"]]
	for pz in posters:
		Kit.box(st, Vector3(pz[0], pz[1], zf + 0.03), Vector3(0.36, 0.48, 0.01), _c(pz[2]))
		Kit.box(st, Vector3(pz[0], float(pz[1]) + 0.1, zf + 0.036), Vector3(0.28, 0.1, 0.01), _c(pz[3]))
		Kit.box(st, Vector3(pz[0], float(pz[1]) - 0.1, zf + 0.036), Vector3(0.24, 0.04, 0.01), _c(pz[3]))
	Kit.box(st, Vector3(3.1, 1.45, zf + 0.03), Vector3(0.42, 0.62, 0.03), _c("#2f4a3a"))
	for k in 4: Kit.box(st, Vector3(3.08 - (k % 2) * 0.03, 1.62 - k * 0.12, zf + 0.05), Vector3(0.28 - (k % 2) * 0.06, 0.025, 0.01), _c("#e6e2d6"))
	# chest freezer and a bench out front, an LPG tank, a meter box with its wire
	Kit.box(st, Vector3(3.25, 0.42, -18.05), Vector3(0.9, 0.84, 0.6), _c("#ecebe6"))
	Kit.box(st, Vector3(3.25, 0.86, -18.05), Vector3(0.92, 0.05, 0.62), _c("#3e7fd0"))
	Kit.box(st, Vector3(3.25, 0.6, -17.74), Vector3(0.5, 0.12, 0.01), _c("#d23b34"))
	_shadow(Vector3(3.25, 0, -18.05), Vector2(0.95, 0.65), true, 0.9)
	Kit.box(st, Vector3(6.95, 0.38, -17.75), Vector3(0.9, 0.06, 0.32), _c("#9a7048"))
	for lx: float in [6.6, 7.3]: Kit.box(st, Vector3(lx, 0.18, -17.75), Vector3(0.06, 0.36, 0.28), _c("#7d5638"))
	_shadow(Vector3(6.95, 0, -17.75), Vector2(0.95, 0.36), true, 0.4)
	Kit.cylinder(st, Vector3(8.55, 0, -18.8), 0.17, 0.17, 0.6, _c("#c9332c"), 8)
	Kit.cylinder(st, Vector3(8.55, 0.6, -18.8), 0.07, 0.07, 0.08, _c("#b9bcc0"), 6)
	Kit.box(st, Vector3(8.2, 2.1, zf + 0.06), Vector3(0.22, 0.3, 0.1), _c("#b9bcc0"))
	Kit.beam(st, Vector3(8.2, 2.25, zf + 0.06), Vector3(8.2, 3.3, zf + 0.06), 0.025, _c("#2e2c30"))
	# a blue tarp patched over a leaky part of the awning
	Kit.quad(st, Vector3(4.0, 2.53, zf + 0.75), Vector3(4.0, 2.66, zf + 0.15), Vector3(5.4, 2.66, zf + 0.15), Vector3(5.4, 2.53, zf + 0.75), _c("#3e7fd0"))
	_shadow(Vector3(cx, 0, (zf + 0.8 + zb) * 0.5), Vector2(x1 - x0 + 0.4, zf + 0.8 - zb), true, 3.4)


func _build_poles(st: SurfaceTool, cloth: SurfaceTool) -> void:
	var concrete := _c("#9e9b94")
	var wood := _c("#7d5c3e")
	var wire := _c("#2e2c30")
	var z := -15.2
	var tops: Array = []
	for x: float in [-9.3, 9.3]:
		Kit.cylinder(st, Vector3(x, 0, z), 0.13, 0.09, 7.6, concrete, 6)
		Kit.box(st, Vector3(x, 7.05, z), Vector3(1.6, 0.1, 0.1), wood)
		for ix: float in [-0.65, 0.0, 0.65]:
			Kit.cylinder(st, Vector3(x + ix, 7.1, z), 0.04, 0.03, 0.12, _c("#e8e6e0"), 5)
		tops.append(Vector3(x, 7.2, z))
		_shadow(Vector3(x, 0, z), Vector2(0.24, 0.24), false, 7.6)
		_shadow_box(Vector3(x, 7.05, z), Vector3(1.6, 0.1, 0.1))           # crossarm
	_shadow(Vector3(9.55, 0, z), Vector2(0.44, 0.44), false, 0.6, 5.6)     # transformer
	Kit.cylinder(st, Vector3(9.55, 5.6, z), 0.22, 0.22, 0.6, _c("#7f868a"), 8)                   # transformer
	# wires: across, off to both sides, and a few strays toward the houses behind
	for ix: float in [-0.65, 0.0, 0.65]:
		Kit.rope(st, Vector3(-9.3 + ix, 7.15, z), Vector3(9.3 + ix, 7.15, z), 0.45, 0.025, wire, 10)
		Kit.rope(st, Vector3(-9.3 + ix, 7.15, z), Vector3(-30.0, 7.0, z - 2.0), 0.6, 0.025, wire, 8)
		Kit.rope(st, Vector3(9.3 + ix, 7.15, z), Vector3(30.0, 7.0, z - 3.0), 0.6, 0.025, wire, 8)
	Kit.rope(st, Vector3(-9.3, 6.4, z), Vector3(-10.8, 4.9, -18.2), 0.25, 0.022, wire, 5)        # to the house
	Kit.rope(st, Vector3(9.3, 6.4, z), Vector3(7.8, 3.2, -18.6), 0.3, 0.022, wire, 5)           # to the store
	Kit.rope(st, Vector3(9.3, 6.0, z), Vector3(4.0, 3.6, -22.0), 0.5, 0.022, wire, 6)
	# banderitas between the poles, never over the court
	# high enough to hang above the rooflines on screen, not across the hall sign
	var flags := [_c("#e0473b"), _c("#f2c84b"), _c("#3e7fd0"), _c("#f2f0ea"), _c("#7cc490"), _c("#f29ac0")]
	_banderitas(cloth, Vector3(-9.3, 6.3, z + 0.05), Vector3(9.3, 6.3, z + 0.05), 0.65, 46, flags)


func _build_tricycle(st: SurfaceTool, at: Vector3, body: Color, yaw: float) -> void:
	# Motorbike with a sidecar and roof, seen side-on.
	var basis := Basis(Vector3.UP, yaw)
	var tire := _c("#2a272a")
	var rim := _c("#b9bcc0")
	var dark := _c("#3a3a40")
	var chrome := _c("#c9ccd0")
	var put := func(local: Vector3, size: Vector3, col: Color) -> void:
		Kit.box(st, at + basis * local, size, col, basis)
	for wz: float in [-0.75, 0.75]:   # bike wheels (two crossed boxes read as round)
		put.call(Vector3(-0.35, 0.3, wz), Vector3(0.1, 0.56, 0.56), tire)
		Kit.box(st, at + basis * Vector3(-0.35, 0.3, wz), Vector3(0.1, 0.56, 0.56), tire, basis * Basis(Vector3.RIGHT, PI * 0.25))
		put.call(Vector3(-0.3, 0.3, wz), Vector3(0.04, 0.2, 0.2), rim)
	put.call(Vector3(-0.35, 0.62, 0.0), Vector3(0.26, 0.28, 1.2), dark)
	put.call(Vector3(-0.35, 0.82, -0.2), Vector3(0.24, 0.1, 0.6), _c("#1f1d20"))   # seat
	put.call(Vector3(-0.35, 1.05, 0.72), Vector3(0.6, 0.05, 0.05), chrome)          # handlebar
	put.call(Vector3(-0.35, 0.8, 0.7), Vector3(0.05, 0.5, 0.05), chrome)
	# sidecar on the camera side, with roof on posts and a windshield
	put.call(Vector3(0.5, 0.55, 0.05), Vector3(1.0, 0.7, 1.5), body)
	put.call(Vector3(0.5, 0.92, 0.05), Vector3(1.04, 0.06, 1.54), body.lightened(0.15))
	put.call(Vector3(1.0, 0.55, 0.05), Vector3(0.02, 0.18, 1.5), _c("#f2f0ea"))      # stripe
	put.call(Vector3(0.5, 0.3, 0.0), Vector3(1.05, 0.12, 0.3), dark)
	put.call(Vector3(0.95, 0.25, 0.0), Vector3(0.12, 0.45, 0.45), tire)
	for pz: float in [-0.6, 0.65]:
		for px: float in [0.05, 0.95]:
			put.call(Vector3(px, 1.35, pz), Vector3(0.05, 0.85, 0.05), chrome)
	put.call(Vector3(0.45, 1.8, 0.05), Vector3(1.3, 0.08, 1.7), body.darkened(0.15))
	put.call(Vector3(0.5, 1.25, 0.72), Vector3(0.9, 0.5, 0.03), _c("#9ec9e8"))
	_shadow(at + Vector3(0.3, 0, -0.1), Vector2(1.6, 1.9), false, 1.8)


# ------------------------------------------------------------------ crowd, queue, scorer

func _monobloc(st: SurfaceTool, at: Vector3, yaw: float, col: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	Kit.box(st, at + b * Vector3(0, 0.43, 0.02), Vector3(0.46, 0.05, 0.44), col, b)
	Kit.box(st, at + b * Vector3(0, 0.72, -0.2), Vector3(0.44, 0.5, 0.05), col, b * Basis(Vector3.RIGHT, -0.15))
	Kit.box(st, at + b * Vector3(0, 0.62, -0.19), Vector3(0.3, 0.06, 0.06), col.darkened(0.12), b)
	for lx: float in [-0.2, 0.2]:
		for lz: float in [-0.18, 0.2]:
			Kit.beam(st, at + b * Vector3(lx * 0.9, 0.42, lz * 0.9), at + b * Vector3(lx * 1.15, 0.0, lz * 1.15), 0.045, col)
	_shadow(at, Vector2(0.5, 0.48), true, 0.9)


func _build_crowd_area(st: SurfaceTool) -> void:
	var white := _c("#e8e7e0")
	var green := _c("#86b48f")
	var red := _c("#d36a5c")
	_monobloc(st, Vector3(-6.8, 0, -12.0), 0.15, white)
	_monobloc(st, Vector3(-6.0, 0, -11.9), -0.05, green)
	_monobloc(st, Vector3(-1.3, 0, -12.0), -0.2, red)
	# long wooden bench
	var wood := _c("#9a7048")
	Kit.box(st, Vector3(-3.2, 0.43, -12.4), Vector3(2.7, 0.06, 0.4), wood)
	for lx: float in [-4.4, -2.0]:
		Kit.box(st, Vector3(lx, 0.2, -12.4), Vector3(0.08, 0.4, 0.34), wood.darkened(0.15))
	_shadow(Vector3(-3.2, 0, -12.4), Vector2(2.75, 0.42), true, 0.46)
	Kit.box(st, Vector3(-0.5, 0.18, -12.3), Vector3(0.5, 0.34, 0.34), _c("#d8453b"))   # cooler
	Kit.box(st, Vector3(-0.5, 0.37, -12.3), Vector3(0.52, 0.05, 0.36), _c("#f2f0ea"))
	_shadow(Vector3(-0.5, 0, -12.3), Vector2(0.54, 0.38), true, 0.4)


func _build_queue(st: SurfaceTool) -> void:
	var cols := [_c("#e8e7e0"), _c("#7fa4d8"), _c("#e8e7e0")]
	var zs := [-7.0, -6.2, -5.4]
	for i in 3:
		_monobloc(st, Vector3(-6.55, 0, zs[i]), PI * 0.5, cols[i])
	Kit.box(st, Vector3(-6.55, 0.6, -6.2), Vector3(0.36, 0.3, 0.22), _c("#3b4f7a"))      # sports bag on the middle chair
	Kit.box(st, Vector3(-6.5, 0.1, -4.7), Vector3(0.18, 0.2, 0.18), _c("#4fa0d8"))       # water bottle tub
	_shadow(Vector3(-6.5, 0, -4.7), Vector2(0.22, 0.22), true, 0.2)


func _build_scorer(st: SurfaceTool) -> void:
	var at := Vector3(6.1, 0, -3.2)
	var wood := _c("#9a7048")
	Kit.box(st, at + Vector3(0, 0.74, 0), Vector3(0.62, 0.05, 1.2), wood)
	for lz: float in [-0.52, 0.52]:
		for lx: float in [-0.25, 0.25]:
			Kit.box(st, at + Vector3(lx, 0.36, lz), Vector3(0.05, 0.72, 0.05), wood.darkened(0.15))
	_shadow(at, Vector2(0.66, 1.24), true, 0.77)
	_monobloc(st, Vector3(6.75, 0, -3.2), -PI * 0.5, _c("#e8e7e0"))
	# flip scoreboard: an easel facing the court and the camera
	var yaw := -0.45
	var b := Basis(Vector3.UP, yaw)
	var c := at + Vector3(0.0, 0.77, 0.15)
	Kit.box(st, c + b * Vector3(0, 0.25, 0), Vector3(0.62, 0.5, 0.04), _c("#3d3a38"), b)
	for side: float in [-1.0, 1.0]:
		var card := c + b * Vector3(side * 0.15, 0.25, 0.03)
		Kit.box(st, card, Vector3(0.26, 0.4, 0.02), _c("#f4f2ea"), b)
		var l := _label("0", card + b * Vector3(0, 0, 0.02), 0.32, Color(0.12, 0.12, 0.14), yaw)
		_score_labels.append(l)


# ------------------------------------------------------------------ background

## The background streets (trees, houses: ~16 ms each on the Mac, built twice per world and
## the world is built at the title and again for the match). Built once per process into
## their own mesh and appended (PerfToggles.env_bake_cache); the casters they add and the
## RNG state they leave are replayed, so what follows is built exactly as before. A cached
## entry is used only from the same RNG state, end and shift it was built from.
static var _bg_cache: Dictionary = {}
static var _cache_hooked := false

## The caches outlive every world; drop them when the app shuts down (no leaked resources).
static func _hook_cache_clear(tree: SceneTree) -> void:
	if _cache_hooked or tree == null: return
	_cache_hooked = true
	tree.root.tree_exiting.connect(func():
		_bg_cache.clear()
		_mask_cache.clear())

func _build_background(st: SurfaceTool, z_shift := 0.0) -> void:
	if not PerfToggles.env_bake_cache:
		_build_background_raw(st, z_shift)
		return
	_hook_cache_clear(get_tree())
	var key := [z_shift, _build_end, _rng.state]
	var hit: Dictionary = _bg_cache.get(key, {})
	if hit.is_empty():
		var own := Kit.begin()
		var first := _casters.size()
		_build_background_raw(own, z_shift)
		hit = {"mesh": own.commit(), "casters": _casters.slice(first).duplicate(true), "rng": _rng.state}
		_bg_cache[key] = hit
	else:
		_casters.append_array(Array(hit.casters).duplicate(true))
		_rng.state = int(hit.rng)
	var mesh: ArrayMesh = hit.mesh
	if mesh.get_surface_count() > 0: st.append_from(mesh, 0, Transform3D.IDENTITY)


func _build_background_raw(st: SurfaceTool, z_shift := 0.0) -> void:
	# Rows of houses and trees out to the horizon (the phone's top edge sees ~170 m out).
	var walls := ["#d9c7a3", "#b9cbb2", "#cfb3ae", "#a9bfd2", "#e0d19f", "#c8c0d8", "#e6e2d6"]
	var rows := [[-32.0, 20.0, 3.0], [-46.0, 28.0, 3.4], [-64.0, 38.0, 4.0], [-88.0, 52.0, 5.0], [-118.0, 70.0, 6.5], [-150.0, 90.0, 8.0]]
	for row in rows:
		var z: float = float(row[0]) + z_shift
		var half: float = row[1]
		var scale_f: float = row[2] / 3.0
		var x := -half
		while x < half:
			if _rng.randf() < 0.3:
				# tree: trunk and three stacked canopy boxes
				var hgt := _rng.randf_range(4.0, 6.5) * scale_f
				Kit.box(st, Vector3(x, hgt * 0.3, z), Vector3(0.3, hgt * 0.6, 0.3) * scale_f, _c("#7d5c3e"))
				var greens := [_c("#5f9a55"), _c("#6fab5e"), _c("#558c4d")]
				for k in 3:
					Kit.box(st, Vector3(x + _rng.randf_range(-0.5, 0.5) * scale_f, hgt * (0.55 + k * 0.17), z + _rng.randf_range(-0.4, 0.4)), Vector3(2.6 - k * 0.6, 1.3, 2.4 - k * 0.5) * scale_f, greens[k], Basis(Vector3.UP, _rng.randf() * PI))
				if z > -70.0:
					_shadow(Vector3(x, 0, z), Vector2(0.3, 0.3) * scale_f, false, hgt * 0.6)                  # trunk
					_shadow(Vector3(x, 0, z), Vector2(2.4, 2.0) * scale_f, false, hgt * 0.45, hgt * 0.5)     # canopy
				x += _rng.randf_range(2.5, 4.0) * scale_f
				continue
			var w := _rng.randf_range(4.0, 7.0) * scale_f
			var h := _rng.randf_range(2.6, 5.5) * scale_f
			var d := 5.0 * scale_f
			var wall := _c(walls[_rng.randi() % walls.size()])
			var zz := z + _rng.randf_range(-1.5, 1.5)
			var annex := _bg_house(st, x, x + w - 0.3, zz, h, d, wall, scale_f, z > -70.0)
			x += w + annex + _rng.randf_range(0.2, 1.5)


## A few flat golden-hour clouds far out in the sky (the serve camera sees a lot of sky):
## stacks of flattened boxes in the toon bands, warm cream on top and toward the sun,
## blue-violet underneath. Static, one mesh, no fog (the sky behind them is not fogged
## either). Own random generator so the rest of the world builds the same as before.
func _build_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 7
	var st := Kit.begin()
	var tops := [_c("#f8e6d0"), _c("#f4dcc4"), _c("#f9ecdc")]
	for k in 9:
		var ang := TAU * (k + rng.randf_range(0.15, 0.85)) / 9.0
		var r := rng.randf_range(230.0, 300.0)
		var c := Vector3(cos(ang) * r, rng.randf_range(38.0, 72.0), sin(ang) * r)
		var along := Basis(Vector3.UP, -ang + PI * 0.5)    # long side across the view
		var w := rng.randf_range(26.0, 46.0)
		var col: Color = tops[k % tops.size()]
		for j in rng.randi_range(3, 5):
			var off := along * Vector3(rng.randf_range(-0.4, 0.4) * w, rng.randf_range(0.0, 4.0), rng.randf_range(-4.0, 4.0))
			var size := Vector3(w * rng.randf_range(0.35, 0.6), rng.randf_range(4.0, 7.0), rng.randf_range(10.0, 16.0))
			Kit.box(st, c + off, size, col, along, false)
	var mat: ShaderMaterial = _toon.duplicate()
	mat.set_shader_parameter("fog", Vector3(0.0, 0.0, 0.0))
	_cloud_mat = mat
	_add_mesh("BarangayClouds", st, mat)


## Shade strip on a wall just under an overhang (eave, balcony, awning, canopy).
func _shade_strip(st: SurfaceTool, x0: float, x1: float, z_face: float, y_top: float, height: float, wall: Color) -> void:
	Kit.box(st, Vector3((x0 + x1) * 0.5, y_top - height * 0.5, z_face), Vector3(x1 - x0, height, 0.02), wall.darkened(0.3))


## One background house with real depth: plinth, overhanging GI eave with a fascia and
## its shadow on the wall, recessed windows with sills and lintels, a door with a step and
## canopy, and sometimes a balcony, a lower side annex or a water tank on the roof.
## Returns the extra width the annex takes. `shadows`: also a ground shadow on the right.
func _bg_house(st: SurfaceTool, x0: float, x1: float, zc: float, h: float, d: float, wall: Color, s: float, shadows: bool) -> float:
	var zf := zc + d * 0.5
	var w := x1 - x0
	var cx := (x0 + x1) * 0.5
	Kit.box(st, Vector3(cx, h * 0.5, zc), Vector3(w, h, d), wall)
	Kit.box(st, Vector3(cx, 0.15 * s, zf + 0.03), Vector3(w + 0.06, 0.3 * s, 0.08), wall.darkened(0.18))       # plinth
	var over := 0.6 * s
	_gi_roof(st, x0 - 0.3 * s, x1 + 0.3 * s, zf + over, zc - d * 0.5 - 0.1, h + 0.05, h + 0.5 * s, _rng.randf() < 0.5)
	var trims := [_c("#f2efe6"), _c("#7a5233"), _c("#3e6fb2"), _c("#5f8f62")]
	var trim: Color = trims[_rng.randi() % trims.size()]
	Kit.box(st, Vector3(cx, h - 0.02, zf + over), Vector3(w + 0.6 * s, 0.14 * s, 0.06), trim)                    # fascia
	_shade_strip(st, x0, x1, zf + 0.012, h, 0.5 * s, wall)
	var two_storey := h > 3.8 * s
	var floors := 2 if two_storey else 1
	var n := maxi(1, int(w / (2.1 * s)))
	var door_slot := _rng.randi() % (n + 1)
	for f in floors:
		var wy := (h * (0.3 if floors == 2 else 0.5)) + f * h * 0.45
		for i in n + (1 if f == 0 else 0):
			var wx := x0 + (i + 0.5) * w / float(n + (1 if f == 0 else 0))
			if f == 0 and i == door_slot:
				# door: recessed, framed, a step and a small canopy with its shadow
				Kit.box(st, Vector3(wx, 1.0 * s, zf + 0.01), Vector3(0.9 * s, 2.0 * s, 0.03), _c("#5e4232"))
				Kit.box(st, Vector3(wx, 2.05 * s, zf + 0.04), Vector3(1.1 * s, 0.1 * s, 0.08), trim)
				Kit.box(st, Vector3(wx, 0.06, zf + 0.25 * s), Vector3(1.2 * s, 0.12, 0.5 * s), _c("#a9a59c"))
				Kit.box(st, Vector3(wx, 2.3 * s, zf + 0.3 * s), Vector3(1.3 * s, 0.06 * s, 0.6 * s), _c("#a6adb0"))
				_shade_strip(st, wx - 0.6 * s, wx + 0.6 * s, zf + 0.02, 2.27 * s, 0.25 * s, wall)
				continue
			var ww := 0.95 * s
			var wh := 0.85 * s
			Kit.box(st, Vector3(wx, wy, zf - 0.04), Vector3(ww, wh, 0.12), _c("#34303a"))                         # recess
			Kit.box(st, Vector3(wx, wy + wh * 0.5 + 0.05 * s, zf + 0.03), Vector3(ww + 0.2 * s, 0.1 * s, 0.1), trim)  # lintel
			Kit.box(st, Vector3(wx, wy - wh * 0.5 - 0.05 * s, zf + 0.07), Vector3(ww + 0.25 * s, 0.08 * s, 0.18 * s), _c("#e6e2d6"))  # sill
			_shade_strip(st, wx - ww * 0.5, wx + ww * 0.5, zf - 0.02, wy + wh * 0.5, 0.18 * s, _c("#34303a"))
			if _rng.randf() < 0.35:   # a grille or a jalousie
				for k in 3: Kit.box(st, Vector3(wx - ww * 0.33 + k * ww * 0.33, wy, zf + 0.02), Vector3(0.03 * s, wh, 0.02), _c("#d8d6cf"))
	if two_storey and _rng.randf() < 0.5:
		# balcony slab and railing across part of the front, and its shadow below
		var by := h * 0.5
		var bw := w * 0.6
		Kit.box(st, Vector3(cx, by, zf + 0.45 * s), Vector3(bw, 0.12 * s, 0.9 * s), _c("#a9a59c"))
		Kit.box(st, Vector3(cx, by + 0.5 * s, zf + 0.88 * s), Vector3(bw, 0.06 * s, 0.05), trim)
		var px := cx - bw * 0.5
		while px <= cx + bw * 0.5:
			Kit.box(st, Vector3(px, by + 0.25 * s, zf + 0.88 * s), Vector3(0.04, 0.5 * s, 0.04), trim)
			px += 0.35 * s
		_shade_strip(st, cx - bw * 0.5, cx + bw * 0.5, zf + 0.015, by - 0.06 * s, 0.45 * s, wall)
	if _rng.randf() < 0.25:
		# water tank on a little stand on the roof
		var tx := x0 + w * _rng.randf_range(0.25, 0.75)
		var ty := h + 0.4 * s
		for lx: float in [-0.35, 0.35]:
			Kit.box(st, Vector3(tx + lx * s, ty + 0.3 * s, zc - d * 0.2), Vector3(0.06, 0.6 * s, 0.06), _c("#6a6e72"))
		Kit.cylinder(st, Vector3(tx, ty + 0.6 * s, zc - d * 0.2), 0.5 * s, 0.5 * s, 0.9 * s, _c("#3e7fd0"), 8)
	var annex := 0.0
	if _rng.randf() < 0.35:
		# lower lean-to annex on the right, set back a little
		annex = 1.9 * s
		var ah := h * 0.55
		var ad := d * 0.7
		var az := zc - d * 0.15
		var awall := wall.darkened(0.06)
		Kit.box(st, Vector3(x1 + annex * 0.5, ah * 0.5, az), Vector3(annex, ah, ad), awall)
		_gi_roof(st, x1, x1 + annex + 0.2 * s, az + ad * 0.5 + 0.4 * s, az - ad * 0.5, ah, ah + 0.4 * s, true)
		_shade_strip(st, x1, x1 + annex, az + ad * 0.5 + 0.012, ah, 0.35 * s, awall)
		Kit.box(st, Vector3(x1 + annex * 0.5, ah * 0.5, az + ad * 0.5 + 0.01), Vector3(0.7 * s, 0.6 * s, 0.03), _c("#34303a"))
	if shadows:
		# the low sun from the far left: each house's footprint swept along it by its height
		_shadow(Vector3((x0 + x1 + annex) * 0.5, 0, zc), Vector2(w + annex, d), true, h)
	return annex


# ------------------------------------------------------------------ figures

func _person(pos: Vector3, yaw: float, seated: bool, crowd := true, scale_f := -1.0) -> Dictionary:
	var i := _people.size()
	if _build_end == 1:
		pos = _end_pos(pos)
		yaw += PI
	var p := People.new_person(pos, yaw, seated, (i * 7 + 3) % 16, scale_f if scale_f > 0.0 else _rng.randf_range(0.95, 1.04))
	p.end = _build_end
	p.next_idle = _rng.randf_range(1.0, 6.0)
	p.rate = _rng.randf_range(5.0, 7.0)
	p.base_seated = seated
	p.role = "crowd"
	p.trait = TRAITS[(i * 3 + 1) % TRAITS.size()]
	_pick_posture(p)
	p.next_posture = _rng.randf_range(15.0, 40.0)
	_people.append(p)
	if crowd: _crowd.append(p)
	return p


func _pick_posture(p: Dictionary) -> void:
	var table: Dictionary = TRAIT_SEATED if p.seated else TRAIT_STANDING
	var options: Array = table.get(p.trait, ["normal"] if p.seated else ["stand"])
	p.posture = options[_rng.randi() % options.size()]


func _walker(kind := "") -> Dictionary:
	var p := _person(Vector3(0, 0, LANE_A), 0.0, false, false)
	p.role = "walker"
	p.kind = kind
	p.visible = false
	p.state = "gone"
	p.respawn = _rng.randf_range(0.0, 8.0)
	p.path = []
	p.dest = ""
	p.speed = 1.2
	p.walk_phase = _rng.randf() * TAU
	p.watch = false
	# passers-by mostly ignore the game; some look, a few wave or stop to watch
	var traits := ["nonchalant", "curious", "friendly", "busy", "nonchalant", "curious"]
	p.trait = traits[_walkers.size() % traits.size()]
	if kind == "umbrella": p.trait = "nonchalant"
	if kind == "mother": p.trait = "busy"
	if kind == "taho": p.trait = "calm"
	_walkers.append(p)
	return p


func _build_figures() -> void:
	# crowd behind the far end
	_person(Vector3(-6.8, 0, -12.0), 0.15, true)
	_person(Vector3(-6.0, 0, -11.9), -0.05, true)
	_person(Vector3(-1.3, 0, -12.0), -0.2, true)
	for bx: float in [-4.1, -3.2, -2.3]:
		_person(Vector3(bx, 0, -12.45), 0.0, true)
	for sx: float in [-5.4, -2.8, -1.0]:
		_person(Vector3(sx, 0, -13.4 + _rng.randf_range(-0.2, 0.2)), _rng.randf_range(-0.2, 0.2), false)
	# at the sari-sari store: two watchers and the tindera behind the counter
	_person(Vector3(3.9, 0, -17.6), 0.25, false)
	_person(Vector3(4.8, 0, -17.7), -0.1, false)
	_person(Vector3(5.2, 0, -19.1), 0.0, false)
	# neighbour on the balcony
	_neighbour = _person(Vector3(-9.6, 2.98, -17.55), 0.2, false, false)
	# next-game queue: two seated players with paddles (the middle chair holds their bag)
	for qz: float in [-7.0, -5.4]:
		var q := _person(Vector3(-6.55, 0, qz), PI * 0.5, true)
		q.trait = "fan" if qz < -6.0 else "nonchalant"
		_pick_posture(q)
		q.prop = "paddle"
		q.role = "queue"
	# scorer at the table
	_scorer = _person(Vector3(6.75, 0, -3.2), -PI * 0.5, true, false)
	_scorer.role = "scorer"
	_scorer.trait = "calm"
	_scorer.posture = "normal"
	# passers-by: errands on the street lanes, a taho vendor, a mother and her kid,
	# someone under a payong, and a few far off behind the hall
	for k in 4: _walker()
	_walker("taho")
	_walker("umbrella")
	var mother := _walker("mother")
	var kid := _walker("kid")
	kid.s = 0.72
	kid.leader = mother
	for k in 4: _walker("far")
	# ball kids: one on the ground behind the far baseline, one squatting by the right
	# net post, one behind the near baseline (off screen until needed)
	for spec in [[Vector3(5.0, 0, -10.5), 0.3, "knee_up", 0.12], [Vector3(6.45, 0, 1.0), -PI * 0.5, "tucked", 0.25],
			[Vector3(0.8, 0, 11.2), PI, "knee_up", 0.12]]:
		var k := _person(spec[0], spec[1], true, false, 0.7)
		k.role = "ballkid"
		k.end = -1
		k.home = spec[0]
		k.home_yaw = spec[1]
		k.home_posture = spec[2]
		k.home_seat = spec[3]
		k.posture = spec[2]
		k.seat_h = spec[3]
		k.state = "home"
		k.path = []
		k.walk_phase = 0.0
		k.has_ball = false
		k.until = 0.0
		k.recv = Vector3.ZERO
		k.watch = true
		_kids.append(k)
	_game.set_meta("ball_kids", self)
	# the pandesal end's people (vendor, audience, lolos, commuters, kids, passers-by)
	_build_end = 1
	PandesalEnd.build_people(self)
	_build_end = 0
	# chickens and a dog on the dirt behind the far end
	for k in 3:
		var pos := Vector3(_rng.randf_range(1.2, 4.2), 0, _rng.randf_range(-13.2, -11.4))
		var ch := Fig.new_chicken(pos, {"body": _c(["#f2efe6", "#b9733f", "#e8e2d2"][k]), "tail": _c(["#2f3a33", "#5a3a24", "#2f3a33"][k]),
			"comb": _c("#d8382f"), "beak": _c("#e8b33c"), "wing": _c(["#e0dccf", "#9e5e33", "#d4cfc0"][k])})
		ch.yaw = _rng.randf() * TAU
		ch.next = _rng.randf_range(0.5, 3.0)
		_chickens.append(ch)
	var rooster := Fig.new_chicken(_end_pos(Vector3(0.55, 0.1, -25.0), 1), {"body": _c("#b9733f"), "tail": _c("#1f3a2e"),
		"comb": _c("#d8382f"), "beak": _c("#e8b33c"), "wing": _c("#7a3f22")})
	rooster.caged = true
	rooster.next = 1e9
	rooster.yaw = PI
	_chickens.append(rooster)
	_cats = PandesalEnd.build_animals(self)
	# the hen (first chicken) leads four chicks
	_chickens[0].c.body = _c("#c98a4a")
	_chickens[0].c.wing = _c("#a86c38")
	for k in 4:
		var cp := Vector3(_chickens[0].pos) + Vector3(_rng.randf_range(-0.5, 0.5), 0, _rng.randf_range(-0.5, 0.5))
		var chick := Fig.new_chick(cp)
		chick.yaw = _rng.randf() * TAU
		chick.next = _rng.randf_range(0.5, 2.0)
		_chicks.append(chick)
	_dog = Fig.new_dog(Vector3(3.9, 0, -13.5), {"body": _c("#b98a52"), "snout": _c("#d9b07a"), "ear": _c("#8a6236"), "leg": _c("#a87a46")})
	_dog.yaw = -1.2
	# people: pixel cards (one mesh); props and animals: one MultiMesh of unit cubes
	_cards = People.CardBatch.new(self, _people.size())
	_set_push(_cards.instance.material_override)
	var count := _people.size() * PROP_SLOTS + _chickens.size() * Fig.CHICKEN_PARTS + Fig.DOG_PARTS + _chicks.size() * Fig.CHICK_PARTS + _cats.size() * CAT_PARTS
	var cube := Kit.begin()
	Kit.box(cube, Vector3.ZERO, Vector3.ONE, Color.WHITE, Basis.IDENTITY, false)
	_mm_fig = MultiMesh.new()
	_mm_fig.transform_format = MultiMesh.TRANSFORM_3D
	_mm_fig.use_colors = true
	_mm_fig.mesh = cube.commit()
	_mm_fig.instance_count = count
	var base := 0
	for p in _people:
		p.base_prop = base
		base += PROP_SLOTS
		var pos: Vector3 = p.pos
		var moving: bool = p.role in ["walker", "ballkid", "vendor"] or int(p.get("end", 0)) == 1
		var authored_z: float = -pos.z if int(p.get("end", 0)) == 1 else pos.z   # "far = -z" at either end
		if pos.y < 0.5 and (authored_z > -18.6 or moving):
			p.shadow = _figure_shadow(pos, 0.24 * float(p.get("s", 1.0)), (1.15 if bool(p.get("base_seated", false)) else 1.55) * float(p.get("s", 1.0)))
	for ch in _chickens:
		ch.base = base
		base += Fig.CHICKEN_PARTS
		Fig.color_chicken(_mm_fig, ch)
		Fig.pose_chicken(_mm_fig, ch)
		ch.shadow = _figure_shadow(ch.pos, 0.15, 0.35)
	for chick in _chicks:
		chick.base = base
		base += Fig.CHICK_PARTS
		Fig.color_chick(_mm_fig, chick, _c("#f7dc4a"), _c("#f0a030"))
		Fig.pose_chick(_mm_fig, chick)
		chick.shadow = _figure_shadow(chick.pos, 0.07, 0.12)
	for cat in _cats:
		cat.base = base
		base += CAT_PARTS
		for k in CAT_PARTS: _mm_fig.set_instance_color(int(cat.base) + k, cat.c if k != 3 else Color(cat.c).darkened(0.25))
		_pose_cat(cat)
	_dog.base = base
	Fig.color_dog(_mm_fig, _dog)
	Fig.pose_dog(_mm_fig, _dog)
	_dog.shadow = _figure_shadow(_dog.pos, 0.3, 0.5)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BarangayFigures"
	mmi.multimesh = _mm_fig
	mmi.material_override = _toon
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-60, -2, -60), Vector3(120, 30, 80))
	add_child(mmi)


func _build_shadows() -> void:
	# the baked static mask: two L8 images, one multiply layer over the whole ground
	_mask_near = Image.create(int(round(MASK_NEAR.size.x / MASK_NEAR_TEXEL)), int(round(MASK_NEAR.size.y / MASK_NEAR_TEXEL)), false, Image.FORMAT_L8)
	_mask_far = Image.create(int(round(MASK_FAR.size.x / MASK_FAR_TEXEL)), int(round(MASK_FAR.size.y / MASK_FAR_TEXEL)), false, Image.FORMAT_L8)
	_tex_near = ImageTexture.create_from_image(_mask_near)
	_tex_far = ImageTexture.create_from_image(_mask_far)
	_mask_mat = ShaderMaterial.new()
	_mask_mat.shader = MaskShader
	_mask_mat.render_priority = -2      # before the figures' ovals and the players' shadows
	_mask_uniforms(_mask_mat)
	_mask_mat.set_shader_parameter("far_mask", _tex_far)
	_mask_mat.set_shader_parameter("far_rect", Vector4(MASK_FAR.position.x, MASK_FAR.position.y, MASK_FAR.size.x, MASK_FAR.size.y))
	var layer := MeshInstance3D.new()
	layer.name = "BarangayShadowMask"
	var plane := PlaneMesh.new()
	plane.size = MASK_FAR.size       # centred on the court, so the half turn of a swap keeps it
	layer.mesh = plane
	layer.position = Vector3(MASK_FAR.get_center().x, MASK_Y, MASK_FAR.get_center().y)
	layer.material_override = _mask_mat
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(layer)
	# the moving figures: one MultiMesh of flat ovals
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	_mm_shadow = MultiMesh.new()
	_mm_shadow.transform_format = MultiMesh.TRANSFORM_3D
	_mm_shadow.mesh = quad
	_mm_shadow.instance_count = _figs.size()
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = ShadowShader
	_shadow_mat.render_priority = -1
	_mask_uniforms(_shadow_mat)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BarangayFigureShadows"
	mmi.multimesh = _mm_shadow
	mmi.material_override = _shadow_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-60, -1, -60), Vector3(120, 4, 120))
	add_child(mmi)


func _mask_uniforms(m: ShaderMaterial) -> void:
	var c := Sun.SHADOW_COLOR
	m.set_shader_parameter("shadow_col", Vector3(c.r, c.g, c.b))
	m.set_shader_parameter("opacity", Sun.SHADOW_OPACITY)
	m.set_shader_parameter("near_mask", _tex_near)
	m.set_shader_parameter("near_rect", Vector4(MASK_NEAR.position.x, MASK_NEAR.position.y, MASK_NEAR.size.x, MASK_NEAR.size.y))
	m.set_shader_parameter("texel", MASK_NEAR_TEXEL)
	_set_push(m)


## Projects every static caster along the sun (in world space, after the world's own turn)
## and fills the convex hull of its points into the masks. Shapes are painted in order of
## opacity, so where they overlap the darker one wins: a max union, never darker twice.
## Baked masks by everything they are made from (casters, this node's turn, the sun), so a
## world built again (title, then the match) or turned back reuses its masks
## (PerfToggles.env_bake_cache).
static var _mask_cache: Dictionary = {}

func _bake_mask() -> void:
	if _mask_near == null: return
	var t0 := Time.get_ticks_usec()
	var xf := global_transform if is_inside_tree() else transform
	var o3 := Sun.project(Vector3.UP, 0.0)          # where 1 m of height lands (x, z)
	var off := Vector2(o3.x, o3.z)
	var key := 0
	if PerfToggles.env_bake_cache:
		key = hash([_casters, xf, o3, MASK_NEAR, MASK_FAR, MASK_NEAR_TEXEL, MASK_FAR_TEXEL])
		var hit: Array = _mask_cache.get(key, [])
		if not hit.is_empty():
			_mask_near.copy_from(hit[0])
			_mask_far.copy_from(hit[1])
			_publish_mask(t0)
			return
	var polys: Array = []
	for c in _casters:
		var pts: PackedVector3Array = c[0]
		var world: bool = c[3]
		var g: float = c[4]
		var p2 := PackedVector2Array()
		p2.resize(pts.size())
		for i in pts.size():
			var w: Vector3 = pts[i] if world else xf * pts[i]
			p2[i] = Vector2(w.x, w.z) + off * (w.y - g)
		var hull := Geometry2D.convex_hull(p2)
		if bool(c[2]):
			# banderitas: only the flags whose shadow falls outside the court lines
			var mid := Vector2.ZERO
			for q in p2: mid += q
			mid /= p2.size()
			if absf(mid.x) < COURT_HALF.x and absf(mid.y) < COURT_HALF.y: continue
		polys.append([hull, float(c[1])])
	polys.sort_custom(func(a, b): return a[1] < b[1])
	_mask_near.fill(Color.BLACK)
	_mask_far.fill(Color.BLACK)
	var inner := MASK_NEAR.grow(-0.5)
	for poly in polys:
		var hull: PackedVector2Array = poly[0]
		var box := Rect2(hull[0], Vector2.ZERO)
		for q in hull: box = box.expand(q)
		if box.intersects(MASK_NEAR): _fill_hull(_mask_near, MASK_NEAR, MASK_NEAR_TEXEL, hull, poly[1])
		if not inner.encloses(box): _fill_hull(_mask_far, MASK_FAR, MASK_FAR_TEXEL, hull, poly[1])
	if PerfToggles.env_bake_cache:
		if _mask_cache.size() >= 4: _mask_cache.clear()
		_mask_cache[key] = [_mask_near.duplicate(), _mask_far.duplicate()]
	_publish_mask(t0)


func _publish_mask(t0: int) -> void:
	_tex_near.update(_mask_near)
	_tex_far.update(_mask_far)
	ShadowMask.publish(_tex_near, MASK_NEAR)
	PerfMonitor.record("env.shadow_bake", Time.get_ticks_usec() - t0)


## Scanline fill of a convex polygon (world x, z) into a mask: every texel whose centre is
## inside gets `value` (hard edges on the texel grid; nearest sampling keeps them).
func _fill_hull(img: Image, rect: Rect2, texel: float, hull: PackedVector2Array, value: float) -> void:
	var n := hull.size()
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	xs.resize(n)
	ys.resize(n)
	var y_lo := INF
	var y_hi := -INF
	for i in n:
		xs[i] = (hull[i].x - rect.position.x) / texel
		ys[i] = (hull[i].y - rect.position.y) / texel
		y_lo = minf(y_lo, ys[i])
		y_hi = maxf(y_hi, ys[i])
	var w := img.get_width()
	var h := img.get_height()
	var j0 := maxi(int(ceil(y_lo - 0.5)), 0)
	var j1 := mini(int(floor(y_hi - 0.5)), h - 1)
	var col := Color(value, value, value)
	for j in range(j0, j1 + 1):
		var yc := j + 0.5
		var xl := INF
		var xr := -INF
		for e in n:
			var ay := ys[e]
			var e1 := (e + 1) % n
			var by := ys[e1]
			if (ay <= yc) != (by <= yc):
				var x := xs[e] + (yc - ay) * (xs[e1] - xs[e]) / (by - ay)
				xl = minf(xl, x)
				xr = maxf(xr, x)
		var i0 := maxi(int(ceil(xl - 0.5)), 0)
		var i1 := mini(int(floor(xr - 0.5)), w - 1)
		if i1 >= i0: img.fill_rect(Rect2i(i0, j, i1 - i0 + 1, 1), col)


## A moving figure's oval: from just behind its feet along the sun (world direction, so
## undo this node's turn), FIG_REACH of its full cast length; hidden ones fold to nothing.
func _write_fig(i: int, hidden := false) -> void:
	var f: Array = _figs[i]
	if hidden:
		_mm_shadow.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -10, 0)))
		return
	var pos: Vector3 = f[0]
	var r: float = f[1]
	var along := 2.0 * r + FIG_REACH * float(f[2]) * Sun.shadow_length_per_metre()
	var dir := (transform.basis.inverse() * Sun.shadow_dir()).normalized()
	var side := dir.cross(Vector3.UP)
	var at := pos + dir * (along * 0.5 - r)
	_mm_shadow.set_instance_transform(i, Transform3D(Basis(dir * along, Vector3.UP, side * r * 1.8), Vector3(at.x, MASK_Y + 0.0005, at.z)))


func _move_shadow(i: int, pos: Vector3, hidden := false) -> void:
	if i < 0 or i >= _figs.size(): return
	var f: Array = _figs[i]
	if hidden == bool(f[3]) and (hidden or Vector3(f[0]).is_equal_approx(pos)): return
	f[0] = pos
	f[3] = hidden
	_write_fig(i, hidden)


# ------------------------------------------------------------------ runtime

## Court view: with the swap on, the whole world turns half a turn so the other end's
## scenery faces the camera (the court is symmetric, so play is unchanged). The floor
## pattern, which end animates and the sun all follow: the sun stays behind-left of the
## camera at either end (Sun.set_flipped), the toon bands relight and the static shadow
## mask is baked again in world space after the turn.
func _apply_view() -> void:
	var swapped := bool(Settings.get_value("video.court_view_swapped", false))
	transform.basis = Basis(Vector3.UP, PI) if swapped else Basis.IDENTITY
	_floor.set_shader_parameter("flip", -1.0 if swapped else 1.0)
	Sun.set_flipped(_flipped)
	for m in [_toon, _grimy, _toon_n, _grimy_n, _cloud_mat]:
		if m != null: m.set_shader_parameter("light_dir", Sun.to_sun())
	_bake_mask()
	if _mm_shadow != null:
		for i in _figs.size(): _write_fig(i, bool(_figs[i][3]))
	_live_end = (1 if _flipped else 0) ^ (1 if swapped else 0)
	for p in _people: p.erase("sig")  # redraw everyone once

func _process(delta: float) -> void:
	# Sway clock for the flags and laundry (env_toon.gdshader sway_time), stepped at SWAY_HZ.
	# Fed from here so it stops with the pause and the paused screen is not redrawn.
	if _toon != null:
		_sway_clock += delta
		var sway: float = floorf(_sway_clock * SWAY_HZ) / SWAY_HZ
		if sway != _sway_shown:
			_sway_shown = sway
			for m in [_toon, _grimy, _toon_n, _grimy_n]:
				if m != null: m.set_shader_parameter("sway_time", sway)
	if _mm_fig == null: return
	var t0 := Time.get_ticks_usec()
	_t += delta
	_connect_signals()
	var flipped: bool = _game != null and _game.has_method("view_flipped") and bool(_game.view_flipped())
	if flipped != _flipped:
		_flipped = flipped
		_apply_view()                     # the camera now faces the other end
		_react_all("clap", 1.8)      # applause for the change of ends
	_tick_t += delta
	# Perf: the crowd's step waits one frame when this frame also carries a physics tick (at 60
	# fps every other frame does, and those are the frames that run long). Never two in a row,
	# so at 30 fps, where every frame carries one, it steps as before.
	var physics_frame: int = Engine.get_physics_frames()
	var carries_tick: bool = physics_frame != _seen_physics_frame
	_seen_physics_frame = physics_frame
	if _tick_t >= TICK:
		if carries_tick and not _step_waited: _step_waited = true
		else:
			_step_waited = false
			_tick_t = fmod(_tick_t, TICK)
			_step()
	PerfMonitor.record("env.barangay", Time.get_ticks_usec() - t0)

var _seen_physics_frame: int = -1
var _step_waited := false


func _connect_signals() -> void:
	if _game == null: return
	var ball = _game.get("ball")
	if ball != null and ball != _ball and is_instance_valid(ball):
		_ball = ball
		if ball.has_signal("actor_hit_paddle"): ball.actor_hit_paddle.connect(_on_paddle_hit)
		if ball.has_signal("bounced"): ball.bounced.connect(_on_bounce)
	if not _connected.has("scorer"):
		var scorer = _game.get("rally_scorer")
		if scorer != null and scorer.has_signal("rally_ended"):
			scorer.rally_ended.connect(_on_rally_ended)
			_connected["scorer"] = true
	if not _connected.has("serve"):
		var serve = _game.get("game_serve")
		if serve != null and serve.has_signal("serve_launched"):
			serve.serve_launched.connect(_on_serve)
			_connected["serve"] = true
	if not _connected.has("net"):
		var net := _game.get_node_or_null("Net")
		if net != null and net.has_signal("ball_hit_post"):
			net.ball_hit_post.connect(_on_post)
			_connected["net"] = true


func _on_paddle_hit(_actor_id: int, _team_id: int, _court_side: int) -> void:
	_rally_hits += 1
	_check_speed = true


func _on_serve(_team: int) -> void:
	_rally_hits = 0
	for p in _crowd:
		if p.mode != "idle": p.mode = "idle"


func _on_post(_point: Vector3) -> void:
	_react_all("hands_head", 1.2, 0.8)


func _on_bounce(pos: Vector3) -> void:
	var local := to_local(pos)
	for ch in _chickens:
		if Vector3(ch.pos).distance_to(local) < 4.0: _scatter(ch, local)
	for chick in _chicks:
		if Vector3(chick.pos).distance_to(local) < 3.0:
			chick.mode = "run"
			chick.next = _t + 1.2
	for p in _crowd:
		if Vector3(p.pos).distance_to(local) < 2.6: _react(p, "flinch", 0.6)
	if Vector3(_dog.pos).distance_to(local) < 4.0: _dog_bark(1.2)


func _on_rally_ended(_winner: int, reason: String, _detail: String) -> void:
	var big := _rally_hits >= 8
	for p in _crowd:
		var r := _rng.randf()
		var seated: bool = p.base_seated
		var tr: String = p.trait
		var dozing: bool = p.idle_kind == "doze" and _t < float(p.idle_until)
		match tr:
			"nonchalant":
				# barely looks up: a glance or a couple of claps, then back to the phone
				if r < 0.25: _react(p, "clap_light", 0.7)
				elif r < 0.45: _react(p, "glance", 0.6)
				continue
			"sleepy":
				if big or dozing and r < 0.5: _react(p, "startle", 0.5, "clap_light", 0.8)
				elif r < 0.4: _react(p, "clap_light", 0.8)
				continue
			"grumpy":
				if reason in NET_REASONS or reason == "OUT_OF_BOUNDS": _react(p, "facepalm" if r < 0.5 else "hands_head", 1.1)
				elif big: _react(p, "clap_light", 1.2)
				continue
			"calm":
				if big: _react(p, "clap", _rng.randf_range(1.4, 2.0))
				elif reason in NET_REASONS and r < 0.3: _react(p, "ooh", 0.8, "clap_light", 0.8)
				else: _react(p, "clap_light", _rng.randf_range(1.0, 1.6))
				continue
			"chatty":
				if big: _react(p, "cheer", 1.4, "chat", 2.0)
				elif reason in NET_REASONS and r < 0.5: _react(p, "ooh", 0.8, "chat", 1.8)
				else: _react(p, "clap", 1.0, "chat", 1.8)
				continue
		# fans (and anyone else): the full range
		if big:
			if seated and r < 0.5: _react(p, "stand_cheer", _rng.randf_range(1.8, 2.6), "clap", 1.0)
			elif not seated and r < 0.5: _react(p, "jump", _rng.randf_range(1.4, 2.0), "clap", 1.0)
			elif r < 0.75: _react(p, "fist_pump", _rng.randf_range(1.4, 2.0), "clap", 0.8)
			else: _react(p, "cheer", _rng.randf_range(1.8, 2.6), "clap", 1.0)
		elif reason in NET_REASONS:
			if r < 0.3: _react(p, "hands_head", 1.0, "clap", 0.9)
			elif r < 0.5: _react(p, "facepalm", 1.2)
			elif r < 0.65: _react(p, "ooh", 0.9, "clap", 0.8)
			else: _react(p, "clap", _rng.randf_range(1.0, 1.6))
		elif reason == "OUT_OF_BOUNDS":
			if r < 0.4: _react(p, "point", 1.1, "clap", 0.8)
			elif r < 0.55: _react(p, "facepalm", 1.0)
			else: _react(p, "clap", _rng.randf_range(1.0, 1.6))
		elif reason == "BODY_HIT":
			if r < 0.5: _react(p, "wince", 0.8, "ooh", 0.6)
			else: _react(p, "clap", 1.2)
		elif r < 0.3:
			_react(p, "cheer", _rng.randf_range(1.2, 1.8), "clap", 0.8)
		elif r < 0.45:
			_react(p, "fist_pump", 1.2, "clap", 0.6)
		else:
			_react(p, "clap", _rng.randf_range(1.2, 2.0))
	_react(_neighbour, "wave" if big else "lean", 2.0)
	# passers-by on the near lane stop, turn and clap on a big point
	for w in _walkers:
		var lane_z: float = Vector3(w.pos).z * (-1.0 if int(w.get("end", 0)) == 1 else 1.0)
		if big and w.state == "walk" and lane_z > LANE_B - 0.2 and w.kind != "far" and w.trait in ["curious", "friendly"]:
			w.state = "stop"
			w.wait_until = _t + _rng.randf_range(1.4, 2.4)
	_score_pending = _t + 0.5
	if big:
		_dog_bark(1.6)
		for ch in _chickens: _scatter(ch, Vector3(ch.pos) + Vector3(_rng.randf_range(-1, 1), 0, 1.0))
	_rally_hits = 0


func _react(p: Dictionary, mode: String, duration: float, then := "", then_dur := 0.0) -> void:
	if p.is_empty(): return
	p.mode = mode
	p.delay = _t + _rng.randf_range(0.0, 0.3)
	p.until = p.delay + duration
	p.then = then
	p.then_dur = then_dur


func _react_all(mode: String, duration: float, share := 1.0) -> void:
	for p in _crowd:
		if _rng.randf() <= share: _react(p, mode, duration)


func _scatter(ch: Dictionary, from: Vector3) -> void:
	if ch.get("caged", false): return
	var away := Vector3(ch.pos) - from
	away.y = 0
	if away.length() < 0.1: away = Vector3(_rng.randf_range(-1, 1), 0, -1)
	ch.mode = "run"
	ch.target = Vector3(ch.home) + away.normalized() * _rng.randf_range(1.5, 2.5)
	ch.target.x = clampf(ch.target.x, 0.5, 5.5)
	ch.target.z = clampf(ch.target.z, -13.8, -10.8)
	ch.next = _t + 1.6


func _dog_bark(duration: float) -> void:
	_dog.mode = "bark"
	_dog.until = _t + duration


func _step() -> void:
	var playing := _game != null and int(_game.get("game_state")) == PLAYING
	_playing = playing
	var ball_local := Vector3.ZERO
	var have_ball := _ball != null and is_instance_valid(_ball)
	if have_ball: ball_local = to_local((_ball as Node3D).get_global_transform_interpolated().origin)
	if _check_speed and have_ball:
		_check_speed = false
		if (_ball as RigidBody3D).linear_velocity.length() > 14.0:
			for k in 3: _react(_crowd[_rng.randi() % _crowd.size()], "flinch", 0.5)
	_update_score()
	for w in _walkers: _step_walker(w)
	for k in _kids: _step_kid(k, playing, have_ball, ball_local)
	if _live_end == 1: PandesalEnd.step(self, TICK)
	var cam := get_viewport().get_camera_3d()
	var cam_local := to_local(cam.get_global_transform_interpolated().origin) if cam != null else Vector3(0, 10, 15)
	# Cards face the camera, so a camera move redraws everyone; otherwise only people whose
	# pose changed since the last tick are solved and rewritten (most sit still).
	var cam_moved := cam_local.distance_to(_last_cam) > 0.01
	_last_cam = cam_local
	# PerfToggles.crowd_offscreen_skip: a figure outside the camera's view keeps its state
	# stepping but is not solved or rewritten; its sig is dropped so it redraws on entering.
	var planes: Array[Plane] = []
	if PerfToggles.crowd_offscreen_skip and cam != null: planes = cam.get_frustum()
	var changed := false
	for i in _people.size():
		var p: Dictionary = _people[i]
		if int(p.get("end", -1)) >= 0 and int(p.end) != _live_end and p.has("sig"): continue   # the end behind the camera
		var pandesal: bool = p.role in ["vendor", "dama", "pump", "mechanic", "cook", "diner", "buyer"]
		var steps_here: bool = not pandesal and p.role != "walker" and p.role != "ballkid"
		# Off-screen seated / standing people (they never move) skip their step too: their
		# reaction timers resume from _t when they are seen again.
		var seen: bool = planes.is_empty() or _in_view(planes, p)
		if pandesal: PandesalEnd.step_person(self, p)
		elif steps_here and seen: _step_person(p, playing, have_ball, ball_local)
		if not seen and (steps_here or not planes.is_empty() and not _in_view(planes, p)):
			p.erase("sig")
			if p.has("shadow"): _move_shadow(int(p.shadow), p.pos, not bool(p.visible))
			continue
		var sig := [p.arm_l, p.arm_r, p.lean, p.head_yaw, p.head_pitch, p.bounce, p.sway, p.seated, p.walk, p.pos, p.yaw, p.visible, p.prop]
		if not cam_moved and sig == p.get("sig", []): continue
		p.sig = sig
		changed = true
		var j := People.solve(p, _cards.extents(int(p.profile)))
		_cards.write(i, p, j, cam_local)
		_pose_props(p, j)
		if p.has("shadow"): _move_shadow(int(p.shadow), p.pos, not bool(p.visible))
	if changed: _cards.commit()
	for ch in _chickens: _step_chicken(ch)
	_step_chicks()
	if _live_end == 1:
		for cat in _cats:
			cat.step = int(cat.step) + 1
			_pose_cat(cat)
	_step_dog()


## Whether a figure's bounding sphere (feet to above the head, arms out, and its shadow's
## reach) touches the camera frustum. Frustum planes face outward.
func _in_view(planes: Array[Plane], p: Dictionary) -> bool:
	var c: Vector3 = to_global(Vector3(p.pos) + Vector3(0.0, VIEW_CULL_UP, 0.0))
	for pl in planes:
		if pl.distance_to(c) > VIEW_CULL_R: return false
	return true


func _update_score() -> void:
	if _game == null: return
	var s := Vector2i(int(_game.get("score_left")), int(_game.get("score_right")))
	if _score.x < 0:
		_score = s
		_set_score_labels()
		return
	if s != _score and _t >= _score_pending:
		_score = s
		_react(_scorer, "flip", 0.7)
		_set_score_labels()


func _set_score_labels() -> void:
	if _score_labels.size() < 2: return
	var left := _score.x if not _flipped else _score.y
	var right := _score.y if not _flipped else _score.x
	_score_labels[0].text = str(left)
	_score_labels[1].text = str(right)


## Personalities. Each spectator has one: it picks how they sit or stand, the habits they
## fall into, whether they follow the ball, and how they take a point.
const TRAITS := ["fan", "calm", "nonchalant", "grumpy", "sleepy", "chatty", "fan", "calm", "nonchalant", "chatty"]
const TRAIT_IDLE := {
	"fan": ["", "knees", "lean_in", "nod", "clap_light", "chat", "knees"],
	"calm": ["", "", "hand_on_thigh", "drink", "nod", "shade", "scratch", "arms_crossed"],
	"nonchalant": ["phone", "phone", "phone", "chin_rest", "", "drink", "fan"],
	"grumpy": ["arms_crossed", "arms_crossed", "", "scratch", "chin_rest", "hands_hips"],
	"sleepy": ["doze", "doze", "nod", "", "stretch", "lean_back"],
	"chatty": ["chat", "chat", "chat", "", "drink", "gesture"],
}
const TRAIT_SEATED := {"fan": ["tucked", "normal"], "calm": ["crossed", "normal"], "nonchalant": ["figure_four", "sprawl"],
	"grumpy": ["wide"], "sleepy": ["sprawl", "knee_up"], "chatty": ["crossed", "knee_up", "normal"]}
const TRAIT_STANDING := {"fan": ["stand_wide"], "calm": ["stand", "contrapposto"], "nonchalant": ["cross_ankles", "contrapposto"],
	"grumpy": ["stand_wide"], "sleepy": ["contrapposto"], "chatty": ["contrapposto", "stand"]}
## While the ball is in play the crowd keeps its arms down (raised arms behind the far
## players read as noise); bigger habits wait for the point to end.
const PLAY_HABITS := ["", "knees", "lean_in", "arms_crossed", "hands_hips", "hand_on_thigh", "phone", "doze", "nod", "shift"]
const SEATED_ONLY := ["knees", "lean_back", "lean_in", "doze", "chin_rest", "hand_on_thigh"]
const STANDING_ONLY := ["hands_hips", "shift"]


const IDLE_SEATED := ["", "knees", "lean_back", "fan", "drink", "phone", "chat", "scratch", "nod", "shade", "arms_crossed", "stretch", "knees", "chat"]
const IDLE_STANDING := ["", "arms_crossed", "hands_hips", "shift", "phone", "drink", "chat", "scratch", "shade", "stretch", "fan", "hands_hips", "shift"]


func _step_person(p: Dictionary, playing: bool, have_ball: bool, ball_local: Vector3) -> void:
	var mode: String = p.mode
	if mode != "idle" and _t > float(p.until):
		if str(p.get("then", "")) != "":
			p.mode = p.then
			p.delay = _t
			p.until = _t + float(p.then_dur)
			p.then = ""
		else:
			p.mode = "idle"
		mode = p.mode
	var active := mode != "idle" and _t >= float(p.delay)
	var beat := int(_t * float(p.rate)) % 2
	p.seated = p.base_seated and not (active and mode == "stand_cheer")
	var seated: bool = p.seated
	var rest := "idle_sit" if seated else "idle_stand"
	var arm_l: Variant = rest
	var arm_r: Variant = rest
	var lean := 0.0
	var bounce := 0.0
	var sway := 0.0
	var head_yaw := 0.0
	var head_pitch := 0.0
	var prop: String = "paddle" if p.role == "queue" else ""
	if p.role == "queue": arm_r = "hold_paddle"
	if active:
		match mode:
			"cheer", "stand_cheer":
				arm_l = "cheer_a" if beat == 0 else "cheer_b"
				arm_r = "cheer_b" if beat == 0 else "cheer_a"
				bounce = (0.02 if seated else 0.07) * beat
				lean = -0.05
			"jump":
				arm_l = "cheer_a"
				arm_r = "cheer_a"
				bounce = 0.14 * beat
			"fist_pump":
				arm_r = "fist_up" if beat == 0 else "fist_mid"
				bounce = (0.0 if seated else 0.05) * beat
			"clap":
				arm_l = "clap_open" if beat == 0 else "clap_shut"
				arm_r = arm_l
			"hands_head":
				arm_l = "hands_head"
				arm_r = "hands_head"
				lean = -0.12
			"facepalm":
				arm_r = "facepalm"
				head_pitch = 0.35
				lean = 0.1
			"ooh":
				arm_l = "mouth"
				arm_r = "mouth"
				bounce = 0.03 * beat
				lean = -0.08
			"wince":
				arm_l = "wince"
				arm_r = "wince"
				lean = -0.18
			"point":
				arm_r = "point"
			"clap_light":
				arm_l = "clap_open" if int(_t * 3.5) % 2 == 0 else "clap_shut"
				arm_r = arm_l
			"startle":
				arm_l = "wince"
				arm_r = "wince"
				bounce = 0.05
				lean = -0.2
			"chat":
				head_yaw = 0.8 if Vector3(p.pos).x < -3.0 else -0.8
				arm_r = "gesture_a" if beat == 0 else "gesture_b"
			"glance":
				head_pitch = -0.1
			"flinch":
				lean = -0.15
				bounce = 0.03
			"flip":
				arm_r = "reach_up"
			"wave":
				arm_r = "wave_a" if beat == 0 else "wave_b"
				lean = 0.2
			"lean":
				lean = 0.3
				arm_l = "counter"
				arm_r = "counter"
	else:
		# mannerisms: a few seconds of one idle habit, then a few seconds of nothing
		if _t > float(p.next_idle):
			var kinds: Array = TRAIT_IDLE.get(p.trait, IDLE_SEATED if seated else IDLE_STANDING)
			var pick: String = kinds[_rng.randi() % kinds.size()]
			if (seated and pick in STANDING_ONLY) or (not seated and pick in SEATED_ONLY): pick = ""
			p.idle_kind = pick
			p.idle_until = _t + _rng.randf_range(2.0, 5.0)
			p.next_idle = float(p.idle_until) + _rng.randf_range(1.5, 6.0)
		var kind: String = p.idle_kind if _t < float(p.idle_until) else ""
		var tr: String = p.trait
		if playing and not (kind in PLAY_HABITS): kind = ""
		if playing and kind == "phone" and tr != "nonchalant": kind = ""   # eyes on the rally
		# resting arms by personality when no habit is playing
		if kind == "":
			match tr:
				"grumpy": kind = "arms_crossed"
				"nonchalant": kind = "phone" if p.role != "queue" else ("hand_on_thigh" if playing else "chin_rest")
				"fan": kind = "knees" if seated else ""
				"sleepy": kind = "doze" if seated and not playing else ""
		if p.role == "queue" and kind == "phone": kind = "hand_on_thigh" if playing else "chin_rest"
		# now and then re-cross the legs or shift stance
		if _t > float(p.next_posture):
			_pick_posture(p)
			p.next_posture = _t + _rng.randf_range(15.0, 40.0)
		var slow := int(_t * 2.5 + float(p.rate)) % 2
		match kind:
			"knees":
				arm_l = "knees"
				arm_r = "knees"
				lean = 0.25
			"lean_in":
				arm_l = "arm_on_knee"
				arm_r = "arm_on_knee"
				lean = 0.3
			"clap_light":
				arm_l = "clap_open" if int(_t * 3.0) % 2 == 0 else "clap_shut"
				arm_r = arm_l
			"doze":
				arm_l = "hand_on_thigh"
				arm_r = "hand_on_thigh"
				head_pitch = 0.55
				lean = 0.12
			"chin_rest":
				arm_r = "chin_rest"
				arm_l = "arm_on_knee" if seated else "pocket"
				lean = 0.22
				head_pitch = 0.1
			"hand_on_thigh":
				arm_l = "hand_on_thigh"
				arm_r = "hand_on_thigh"
			"gesture":
				arm_r = "gesture_a" if int(_t * 3.0) % 2 == 0 else "gesture_b"
				arm_l = "gesture_b" if int(_t * 3.0) % 2 == 0 else "gesture_a"
				head_yaw = 0.7 if Vector3(p.pos).x < -3.0 else -0.7
			"lean_back":
				arm_l = "behind_head"
				arm_r = "behind_head"
				lean = -0.18
			"fan":
				arm_r = "fan_a" if int(_t * 8.0) % 2 == 0 else "fan_b"
				prop = "fan"
			"drink":
				arm_r = "drink"
				prop = "bottle"
				head_pitch = -0.25 * slow
			"phone":
				arm_l = "phone"
				arm_r = "phone"
				prop = "phone"
				head_pitch = 0.4
			"chat":
				head_yaw = 0.8 if Vector3(p.pos).x < -3.0 else -0.8
				arm_r = "gesture_a" if slow == 0 else "gesture_b"
			"scratch":
				arm_r = "scratch"
				head_pitch = 0.15
			"nod":
				head_pitch = 0.18 * (int(_t * 4.0) % 2)
			"shade":
				arm_r = "shade"
				head_pitch = -0.1
			"arms_crossed":
				arm_l = "arms_crossed"
				arm_r = "arms_crossed"
			"hands_hips":
				arm_l = "hands_hips"
				arm_r = "hands_hips"
			"shift":
				sway = 0.04 if slow == 0 else -0.04
			"stretch":
				arm_l = "stretch"
				arm_r = "stretch"
				lean = -0.1
		if p.role == "queue" and kind in ["fan", "drink", "phone"]: arm_r = "hold_paddle"
		if playing:
			if _rally_hits >= 6 and seated and kind == "":
				lean = 0.28
				arm_l = "lean_in"
				if p.role != "queue": arm_r = "lean_in"
			if _rally_hits >= 10 and not seated:
				# tension without raised arms
				arm_l = "arms_crossed"
				arm_r = "arms_crossed"
				lean = 0.12
		# eyes on the ball while it is in play
		var attentive: bool = tr != "nonchalant" and kind != "doze"
		if playing and have_ball and p.watch and attentive:
			var to_ball := ball_local - Vector3(p.pos)
			var facing := Vector3(sin(float(p.yaw)), 0, cos(float(p.yaw)))
			var right := Vector3(facing.z, 0, -facing.x)
			head_yaw = clampf(atan2(to_ball.dot(right), to_ball.dot(facing)), -0.8, 0.8)
			head_yaw = round(head_yaw / 0.2) * 0.2
	if p.role == "queue": prop = "paddle"
	p.arm_l = arm_l
	p.arm_r = arm_r
	p.lean = lean
	p.bounce = bounce
	p.sway = sway
	p.head_yaw = head_yaw
	p.head_pitch = head_pitch
	p.prop = prop


## Passers-by: walk a lane, run an errand (pass through, buy at the store, go into the
## hall or the house, stop behind the crowd to watch), then leave; some come out of a door.
func _step_walker(w: Dictionary) -> void:
	var lead = w.get("leader")
	if lead is Dictionary:
		# the kid trots beside the mother, a step behind
		w.visible = lead.visible
		w.state = "follow"
		if not lead.visible: return
		var lf := Vector3(sin(float(lead.yaw)), 0, cos(float(lead.yaw)))
		var target: Vector3 = Vector3(lead.pos) - lf * 0.5 + Vector3(lf.z, 0, -lf.x) * 0.45
		var d := target - Vector3(w.pos)
		var moving := d.length() > 0.08
		if moving:
			w.pos = Vector3(w.pos) + d.normalized() * minf(d.length(), 2.2 * TICK)
			w.yaw = atan2(d.x, d.z)
			w.walk_phase = float(w.walk_phase) + 2.2 * TICK / 0.45 * PI
		else:
			w.yaw = lead.yaw
		_walk_pose(w, moving, 0.45)
		return
	match str(w.state):
		"gone":
			w.visible = false
			if _t > float(w.respawn): _start_trip(w)
		"walk":
			var path: Array = w.path
			if path.is_empty():
				_arrive(w)
			else:
				var to: Vector3 = path[0]
				var d := to - Vector3(w.pos)
				d.y = 0.0
				var step := float(w.speed) * TICK
				if d.length() <= step:
					w.pos = to
					path.pop_front()
				else:
					w.pos = Vector3(w.pos) + d.normalized() * step
					w.yaw = atan2(d.x, d.z)
				var wp: Vector3 = w.pos
				wp.y = _ground_y(wp)
				w.pos = wp
				w.walk_phase = float(w.walk_phase) + step / 0.7 * PI
				_walk_pose(w, true, 0.7)
		"queue", "served":
			_walk_pose(w, false, 0.7)
			PandesalEnd.queue_idle(self, w)
		"wait", "watch", "stop":
			if str(w.state) == "stop": w.yaw = PI if int(w.get("end", 0)) == 1 else 0.0
			_walk_pose(w, false, 0.7)
			if w.state == "watch":
				w.arm_l = "arms_crossed" if int(_t / 4.0) % 2 == 0 else "idle_stand"
				w.arm_r = w.arm_l
			elif w.state == "wait" and w.dest == "store":
				w.arm_l = "counter"
				w.arm_r = "counter"
			elif w.state == "stop":
				var beat := int(_t * 6.0) % 2
				w.arm_l = "clap_open" if beat == 0 else "clap_shut"
				w.arm_r = w.arm_l
			if _t > float(w.wait_until):
				if w.state == "stop":
					w.state = "walk"
				else:
					_leave(w)
	if w.has("shadow"): _move_shadow(w.shadow, w.pos, not w.visible)


func _walk_pose(w: Dictionary, moving: bool, stride: float) -> void:
	_walk_pose_base(w, moving, stride)
	if w.get("bread", false):
		# walks off with the paper bag, a bite now and then
		w.prop = "paper_bag"
		w.arm_r = "drink" if int(_t * 1.2 + float(w.walk_phase)) % 3 == 0 else "hold_ball"


func _walk_pose_base(w: Dictionary, moving: bool, stride: float) -> void:
	var ph: float = w.walk_phase
	w.walk = ph if moving else -1.0
	w.bounce = 0.025 * absf(sin(ph)) if moving else 0.0
	var swing := 0.4 * sin(ph) if moving else 0.0
	w.arm_l = [Vector3(-0.1, -1.0, swing), Vector3(-0.05, -1.0, swing + 0.25)]
	w.arm_r = [Vector3(0.1, -1.0, -swing), Vector3(0.05, -1.0, -swing + 0.25)]
	w.lean = 0.06 if moving else 0.0
	w.head_yaw = 0.0
	w.head_pitch = 0.0
	match str(w.kind):
		"taho":
			w.arm_l = "carry_pole"
			w.arm_r = "carry_pole"
			w.prop = "taho"
		"umbrella":
			w.arm_r = "umbrella"
			w.prop = "umbrella"
		"mother":
			w.prop = "bag"
			w.arm_l = "carry_bag"
		_:
			w.prop = ""
			if w.get("leader") is Dictionary: return
			match str(w.trait):
				"nonchalant":
					# eyes on the phone, walking right past the game
					w.arm_l = "phone"
					w.arm_r = "phone"
					w.prop = "phone"
					w.head_pitch = 0.35
				"busy":
					w.prop = "bag"
					w.arm_l = "carry_bag"
					w.lean = 0.12 if moving else 0.0
				"curious":
					# keeps glancing at the court while walking
					if moving and int(_t / 2.5 + float(w.walk_phase)) % 3 != 0:
						var to_court := -Vector3(w.pos)
						var f := Vector3(sin(float(w.yaw)), 0, cos(float(w.yaw)))
						var r := Vector3(f.z, 0, -f.x)
						w.head_yaw = round(clampf(atan2(to_court.dot(r), to_court.dot(f)), -0.9, 0.9) / 0.3) * 0.3
				"friendly":
					# waves at the crowd while passing behind them
					var x := Vector3(w.pos).x
					if moving and not _playing and x > -7.0 and x < 0.0 and absf(Vector3(w.pos).z - LANE_A) < 0.3:
						w.arm_r = "wave_a" if int(_t * 5.0) % 2 == 0 else "wave_b"
						w.head_yaw = 0.6 if float(w.yaw) > 0.0 else -0.6


func _start_trip(w: Dictionary) -> void:
	if int(w.get("end", 0)) == 1:
		PandesalEnd.start_trip(self, w)
		return
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	w.visible = true
	w.state = "walk"
	w.cells = {}
	if w.kind == "far":
		w.speed = _rng.randf_range(0.9, 1.4)
		w.pos = Vector3(side * 42.0, 0, LANE_FAR + _rng.randf_range(-0.4, 0.4))
		w.path = [Vector3(-side * 42.0, 0, Vector3(w.pos).z)]
		w.dest = "exit"
		return
	w.speed = 0.65 if w.kind == "taho" else _rng.randf_range(1.0, 1.4)
	var lane := LANE_A if _rng.randf() < 0.6 or side > 0.0 else LANE_B
	var start_x := side * 17.0
	var r := _rng.randf()
	if w.kind == "taho" or w.kind == "umbrella" or w.kind == "mother": r = minf(r, 0.39)   # they pass along
	if w.trait in ["nonchalant", "busy"] and r >= 0.76 and r < 0.88: r = 0.1                 # no time for the game
	if w.trait == "curious" and r < 0.4 and _rng.randf() < 0.5: r = 0.8                     # stops to watch
	w.speed = (_rng.randf_range(1.6, 1.8) if w.trait == "busy" else w.speed)
	if r < 0.4:
		w.dest = "exit"
		w.pos = Vector3(start_x, 0, lane)
		w.path = [Vector3(-start_x, 0, lane)]
	elif r < 0.58:
		w.dest = "store"
		w.pos = Vector3(start_x, 0, LANE_A)
		w.path = [Vector3(5.7, 0, LANE_A), Vector3(5.7, 0, -17.75)]
	elif r < 0.68:
		w.dest = "enter"
		w.pos = Vector3(start_x, 0, lane)
		w.path = [Vector3(-3.4, 0, lane), Vector3(-3.4, 0, -19.6), Vector3(-3.4, 0, -20.8)]
	elif r < 0.76:
		w.dest = "enter"
		w.pos = Vector3(start_x, 0, lane)
		w.path = [Vector3(-7.6, 0, lane), Vector3(-7.6, 0, -17.8)]
	elif r < 0.88:
		w.dest = "watch"
		var wx := _rng.randf_range(-6.6, -0.4)
		w.pos = Vector3(start_x, 0, LANE_A)
		w.path = [Vector3(wx, 0, LANE_A), Vector3(wx, 0, -14.0)]
	else:
		# comes out of the hall or the house and heads off
		var door := Vector3(-3.4, 0, -20.6) if _rng.randf() < 0.5 else Vector3(-7.6, 0, -17.9)
		w.dest = "exit"
		w.pos = door
		w.path = [Vector3(door.x, 0, lane), Vector3(side * 17.0, 0, lane)]


func _arrive(w: Dictionary) -> void:
	if int(w.get("end", 0)) == 1:
		PandesalEnd.arrive(self, w)
		return
	match str(w.dest):
		"store":
			w.state = "wait"
			w.yaw = PI
			w.wait_until = _t + _rng.randf_range(3.0, 7.0)
		"watch":
			w.state = "watch"
			w.yaw = 0.0
			w.watch = true
			w.wait_until = _t + _rng.randf_range(8.0, 18.0)
		"enter", "exit":
			w.state = "gone"
			w.visible = false
			w.respawn = _t + _rng.randf_range(2.0, 9.0)


func _leave(w: Dictionary) -> void:
	if int(w.get("end", 0)) == 1:
		PandesalEnd.leave(self, w)
		return
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	var here: Vector3 = w.pos
	w.watch = false
	w.state = "walk"
	w.dest = "exit"
	w.path = [Vector3(here.x, 0, LANE_A), Vector3(side * 17.0, 0, LANE_A)]


## Hand-held and carried props as cube instances, from the solved joints.
func _pose_props(p: Dictionary, j: Dictionary) -> void:
	var b: int = p.base_prop
	var hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -50, 0))
	var xf: Array = [hidden, hidden, hidden]
	var col: Array = [_c("#e0473b"), _c("#e0473b"), _c("#e0473b")]
	var prop: String = p.prop if p.visible else ""
	var wr: Vector3 = j.get("wr_r", Vector3.ZERO)
	var el: Vector3 = j.get("el_r", Vector3.ZERO)
	var fore := (wr - el).normalized() if wr != el else Vector3.UP
	match prop:
		"paddle":
			xf[0] = Transform3D(Fig._along(fore, Vector3(0.05, 0.14, 0.03)), wr + fore * 0.05)
			xf[1] = Transform3D(Fig._along(fore, Vector3(0.2, 0.24, 0.03)), wr + fore * 0.22)
			col[0] = _c("#2a2a2e")
			col[1] = _c(["#e0473b", "#3e7fd0", "#f2c84b"][int(p.profile) % 3])
		"paper_bag":
			xf[0] = Transform3D(Basis(Vector3.UP, float(p.yaw)) * Basis.from_scale(Vector3(0.13, 0.18, 0.08)), wr + Vector3.DOWN * 0.04)
			col[0] = _c("#b9895a")
		"steam":
			# puffs rising out of the opened pandesal box
			var top := PandesalEnd.steam_origin(self)
			for k in 3:
				var f := fmod(_t * 0.8 + k / 3.0, 1.0)
				var sz := 0.16 * (1.0 - f) + 0.04
				xf[k] = Transform3D(Basis.from_scale(Vector3(sz, sz, sz)), top + Vector3(0.12 * (k - 1) + 0.06 * sin(_t * 3.0 + k), 0.6 * f, 0.04 * k))
				col[k] = _c("#f2f0ea")
		"ball":
			xf[0] = Transform3D(Basis.from_scale(Vector3(0.09, 0.09, 0.09)), wr + fore * 0.05)
			col[0] = _c("#e8e04a")
		"bottle":
			xf[0] = Transform3D(Fig._along(fore, Vector3(0.06, 0.18, 0.06)), wr + fore * 0.06)
			col[0] = _c("#7fc4e0")
		"fan":
			xf[0] = Transform3D(Fig._along(fore, Vector3(0.22, 0.22, 0.02)), wr + fore * 0.12)
			col[0] = _c("#e6c27a")
		"phone":
			var lw: Vector3 = j.get("wr_l", wr)
			xf[0] = Transform3D(Fig._along(Vector3(j.up), Vector3(0.08, 0.14, 0.02)), (wr + lw) * 0.5 + Vector3.UP * 0.04)
			col[0] = _c("#2a2a2e")
		"umbrella":
			var top := wr + Vector3.UP * 0.95
			xf[0] = Transform3D(Fig._along(Vector3.UP, Vector3(0.03, 1.0, 0.03)), wr + Vector3.UP * 0.45)
			xf[1] = Transform3D(Basis.from_scale(Vector3(1.0, 0.1, 1.0)), top)
			xf[2] = Transform3D(Basis.from_scale(Vector3(0.55, 0.12, 0.55)), top + Vector3.UP * 0.1)
			col[0] = _c("#3a3a3a")
			col[1] = _c("#e0473b")
			col[2] = _c("#f2f0ea")
		"bag":
			var hip: Vector3 = j.get("hip_l", wr)
			var fwd: Vector3 = j.fwd
			var side := Vector3(fwd.z, 0, -fwd.x)
			xf[0] = Transform3D(Basis(Vector3.UP, float(p.yaw)) * Basis.from_scale(Vector3(0.12, 0.28, 0.3)), hip - side * 0.16 + Vector3.UP * 0.02)
			col[0] = _c("#c9a46a")
		"taho":
			var sl: Vector3 = j.get("sh_l", wr)
			var sr: Vector3 = j.get("sh_r", wr)
			var mid := (sl + sr) * 0.5 + Vector3.UP * 0.06
			var across := (sr - sl).normalized()
			xf[0] = Transform3D(Fig._along(across, Vector3(0.04, 1.7, 0.04)), mid)
			xf[1] = Transform3D(Basis.from_scale(Vector3(0.3, 0.34, 0.3)), mid - across * 0.8 - Vector3.UP * 0.55)
			xf[2] = Transform3D(Basis.from_scale(Vector3(0.3, 0.34, 0.3)), mid + across * 0.8 - Vector3.UP * 0.55)
			col[0] = _c("#a88a56")
			col[1] = _c("#b9bcc0")
			col[2] = _c("#b9bcc0")
	for k in PROP_SLOTS:
		_mm_fig.set_instance_transform(b + k, xf[k])
		_mm_fig.set_instance_color(b + k, col[k])


func _step_chicken(ch: Dictionary) -> void:
	ch.step = int(ch.step) + 1
	var pos: Vector3 = ch.pos
	match str(ch.mode):
		"peck":
			ch.head_down = int(ch.step) % 6 < 2
			ch.flap = false
			if _t > float(ch.next):
				ch.mode = "walk"
				ch.target = Vector3(ch.home) + Vector3(_rng.randf_range(-1.6, 1.6), 0, _rng.randf_range(-1.0, 1.0))
				ch.next = _t + _rng.randf_range(3.0, 6.0)
		"walk", "run":
			var speed := 0.06 if ch.mode == "walk" else 0.28
			var to: Vector3 = ch.target
			var d := to - pos
			ch.head_down = false
			ch.flap = ch.mode == "run"
			if d.length() < 0.05 or _t > float(ch.next):
				ch.mode = "peck"
				ch.next = _t + _rng.randf_range(2.0, 5.0)
				if ch.flap: ch.home = pos
			else:
				pos += d.normalized() * minf(d.length(), speed)
				ch.yaw = atan2(d.x, d.z)
				ch.pos = pos
	Fig.pose_chicken(_mm_fig, ch)
	_move_shadow(ch.shadow, pos)


## Chicks: when the hen walks or runs they trail behind her in a line, each a few steps
## further back along her path; when she pecks they potter about near her and peck too.
func _step_chicks() -> void:
	if _chickens.is_empty(): return
	var hen: Dictionary = _chickens[0]
	var hen_pos: Vector3 = hen.pos
	if _hen_trail.is_empty() or Vector3(_hen_trail[0]).distance_to(hen_pos) > 0.08:
		_hen_trail.push_front(hen_pos)
		if _hen_trail.size() > 40: _hen_trail.pop_back()
	var hen_moving: bool = hen.mode != "peck"
	for i in _chicks.size():
		var k: Dictionary = _chicks[i]
		k.step = int(k.step) + 1
		var pos: Vector3 = k.pos
		var speed := 0.05
		if str(k.mode) == "run" and _t < float(k.next):
			speed = 0.2
		elif hen_moving:
			k.mode = "follow"
			var idx := mini((i + 1) * 4, _hen_trail.size() - 1)
			k.target = _hen_trail[idx] if idx >= 0 else hen_pos
			speed = 0.1 if str(hen.mode) == "walk" else 0.24
		else:
			# potter near the hen: pick a spot, walk to it, peck a while
			if str(k.mode) != "peck" and str(k.mode) != "wander":
				k.mode = "wander"
				k.target = hen_pos + Vector3(_rng.randf_range(-0.7, 0.7), 0, _rng.randf_range(-0.6, 0.6))
			if str(k.mode) == "peck" and _t > float(k.next):
				k.mode = "wander"
				k.target = hen_pos + Vector3(_rng.randf_range(-0.7, 0.7), 0, _rng.randf_range(-0.6, 0.6))
		var to: Vector3 = k.target
		var d := to - pos
		d.y = 0.0
		if d.length() > 0.04 and str(k.mode) != "peck":
			pos += d.normalized() * minf(d.length(), speed)
			k.yaw = atan2(d.x, d.z)
			k.pos = pos
			k.head_down = false
		elif str(k.mode) == "wander":
			k.mode = "peck"
			k.next = _t + _rng.randf_range(1.0, 3.0)
		if str(k.mode) == "peck": k.head_down = (int(k.step) + i * 2) % 5 < 2
		elif str(k.mode) == "run" and _t >= float(k.next): k.mode = "follow"
		Fig.pose_chick(_mm_fig, k)
		_move_shadow(k.shadow, pos)


func _pose_cat(cat: Dictionary) -> void:
	var root := Transform3D(Basis(Vector3.UP, float(cat.yaw)), Vector3(cat.pos))
	var b: int = cat.base
	var flick := 0.5 * sin(float(cat.step) * 0.9)
	_mm_fig.set_instance_transform(b + 0, root * Transform3D(Basis.from_scale(Vector3(0.18, 0.2, 0.3)), Vector3(0, 0.12, 0)))
	_mm_fig.set_instance_transform(b + 1, root * Transform3D(Basis.from_scale(Vector3(0.14, 0.13, 0.12)), Vector3(0, 0.27, 0.12)))
	for side: float in [-1.0, 1.0]:
		_mm_fig.set_instance_transform(b + (2 if side < 0.0 else 3), root * Transform3D(Basis.from_scale(Vector3(0.04, 0.06, 0.03)), Vector3(side * 0.045, 0.36, 0.12)))
	_mm_fig.set_instance_transform(b + 4, root * Transform3D(Basis(Vector3.UP, flick) * Basis(Vector3.RIGHT, 0.4) * Basis.from_scale(Vector3(0.04, 0.04, 0.3)), Vector3(0.05, 0.06, -0.25)))
	_mm_fig.set_instance_transform(b + 5, root * Transform3D(Basis.from_scale(Vector3(0.14, 0.12, 0.05)), Vector3(0, 0.05, 0.14)))


func _step_dog() -> void:
	_dog.step = int(_dog.step) + 1
	match str(_dog.mode):
		"sleep":
			if _t > float(_dog.next):
				_dog.mode = "sit"
				_dog.until = _t + _rng.randf_range(3.0, 6.0)
		"sit":
			if _t > float(_dog.until):
				_dog.mode = "sleep"
				_dog.next = _t + _rng.randf_range(8.0, 18.0)
		"bark":
			if _t > float(_dog.until):
				_dog.mode = "sit"
				_dog.until = _t + 3.0
	Fig.pose_dog(_mm_fig, _dog)


# ------------------------------------------------------------------ ball kids
# The between-point controller (scripts/between_point_controller.gd) asks for a kid when
# the ball is out of the players' reach or far from them, waits for `throw_origin` to give
# the kid's hand position, and launches its usual pass to the server from there. Only that
# handover touches the real ball; the kid carries a look-alike while it is hidden.

const KID_RUN := 5.2
const KID_JOG := 2.6
const KID_MAX_FETCH := 26.0     # m: farther than this the off-screen toss is used
const KID_THROW_RANGE := 14.0   # m: walk closer to the server than this before throwing


func available() -> bool:
	return is_inside_tree() and is_visible_in_tree() and not _kids.is_empty()


func request_fetch(ball_world: Vector3, receiver_world: Vector3) -> bool:
	var ball := to_local(ball_world)
	ball.y = 0.0
	var best: Dictionary = {}
	var best_d := INF
	for k in _kids:
		if k.state != "home": continue
		var d := absf(Vector3(k.pos).x - ball.x) + absf(Vector3(k.pos).z - ball.z)
		if d < best_d:
			best_d = d
			best = k
	if best.is_empty() or best_d > KID_MAX_FETCH: return false
	_fetch_kid = best
	best.recv = to_local(receiver_world)
	best.path = _kid_route(best.pos, ball)
	best.state = "run"
	best.seated = false
	best.has_ball = false
	PerfMonitor.note("ball_kid", {"step": "fetch", "distance": best_d, "ball_x": ball.x, "ball_z": ball.z})
	return true


func throw_origin(receiver_world: Vector3) -> Vector3:
	if _fetch_kid.is_empty(): return Vector3.INF
	var k := _fetch_kid
	k.recv = to_local(receiver_world)
	match str(k.state):
		"ready":
			k.state = "windup"
			k.until = _t + 0.28
		"windup":
			if _t >= float(k.until):
				k.state = "release"
				k.until = _t + 0.45
				k.has_ball = false
				k.arm_r = "release"
				var j := People.solve(k, _cards.extents(int(k.profile)))
				PerfMonitor.note("ball_kid", {"step": "throw"})
				return to_global(Vector3(j.wr_r) + Vector3.UP * 0.05)
	return Vector3.INF


func cancel_fetch() -> void:
	if _fetch_kid.is_empty(): return
	var k := _fetch_kid
	_fetch_kid = {}
	if k.state in ["run", "pickup", "carry", "ready", "windup"]:
		k.has_ball = false
		_kid_go_home(k)


## Around the court, not through it: kids along the ends move sideways first, the kid
## beside the court moves along the sideline first.
func _kid_route(from: Vector3, to: Vector3) -> Array:
	if absf(from.x) > 5.8: return [Vector3(from.x, 0, to.z), to]
	return [Vector3(to.x, 0, from.z), to]


func _kid_go_home(k: Dictionary) -> void:
	k.state = "return"
	k.path = _kid_route(k.pos, k.home)


func _step_kid(k: Dictionary, playing: bool, have_ball: bool, ball_local: Vector3) -> void:
	var state: String = k.state
	k.walk = -1.0
	k.bounce = 0.0
	k.lean = 0.0
	k.sway = 0.0
	k.head_pitch = 0.0
	k.head_yaw = 0.0
	k.prop = "ball" if k.has_ball else ""
	match state:
		"home":
			k.seated = true
			k.pos = k.home
			k.yaw = k.home_yaw
			k.posture = k.home_posture
			k.seat_h = k.home_seat
			k.arm_l = "knees"
			k.arm_r = "knees"
			k.lean = 0.2
			if playing and have_ball:
				var to_ball := ball_local - Vector3(k.pos)
				var f := Vector3(sin(float(k.yaw)), 0, cos(float(k.yaw)))
				var r := Vector3(f.z, 0, -f.x)
				k.head_yaw = round(clampf(atan2(to_ball.dot(r), to_ball.dot(f)), -0.9, 0.9) / 0.3) * 0.3
		"run", "carry", "return":
			k.seated = false
			k.posture = "stand"
			var speed := KID_JOG if state == "return" else KID_RUN
			var path: Array = k.path
			if path.is_empty():
				match state:
					"run":
						k.state = "pickup"
						k.until = _t + 0.4
					"carry":
						k.state = "ready"
					"return":
						k.state = "home"
				return
			var to: Vector3 = path[0]
			var d := to - Vector3(k.pos)
			d.y = 0.0
			var step := speed * TICK
			if d.length() <= step:
				k.pos = to
				path.pop_front()
			else:
				k.pos = Vector3(k.pos) + d.normalized() * step
				k.yaw = atan2(d.x, d.z)
			k.walk_phase = float(k.walk_phase) + step / 0.9 * PI
			k.walk = k.walk_phase
			var swing := 0.6 * sin(float(k.walk_phase))
			k.arm_l = [Vector3(-0.15, -0.7, swing), Vector3(-0.05, 0.1, swing + 0.6)]
			k.arm_r = "hold_ball" if k.has_ball else [Vector3(0.15, -0.7, -swing), Vector3(0.05, 0.1, -swing + 0.6)]
			k.bounce = 0.04 * absf(sin(float(k.walk_phase)))
			k.lean = 0.18 if state != "return" else 0.08
		"pickup":
			k.seated = true
			k.seat_h = 0.28
			k.posture = "tucked"
			k.lean = 0.55
			k.arm_l = "reach_down"
			k.arm_r = "reach_down"
			if _t > float(k.until):
				k.has_ball = true
				# walk in closer if the server is far, then get ready to throw
				var recv: Vector3 = k.recv
				var here: Vector3 = k.pos
				var gap := Vector3(recv.x - here.x, 0, recv.z - here.z)
				if gap.length() > KID_THROW_RANGE:
					var spot := here + gap.normalized() * (gap.length() - KID_THROW_RANGE)
					k.path = [spot]
					k.state = "carry"
				else:
					k.state = "ready"
		"ready", "windup", "release":
			k.seated = false
			k.posture = "stand_wide" if state != "ready" else "stand"
			var recv: Vector3 = k.recv
			var to_r := recv - Vector3(k.pos)
			k.yaw = atan2(to_r.x, to_r.z)
			k.arm_l = "idle_stand"
			k.arm_r = "hold_ball" if state == "ready" else ("windup" if state == "windup" else "release")
			k.lean = -0.05 if state == "windup" else (0.15 if state == "release" else 0.0)
			if state == "release" and _t > float(k.until):
				_fetch_kid = {}
				_kid_go_home(k)
	if k.has("shadow"): _move_shadow(k.shadow, k.pos)
