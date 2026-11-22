extends Node3D
## Beach world around the court (visual only): sand, ocean and shoreline (one ground
## shader), a bamboo rope fence with bunting and the wordmark banner, coconut palms,
## spectators who cheer when a point ends, a lifeguard tower, umbrellas, towels, a tiki
## hut, an ice-cream cart, a pier, and animals (gulls, pelican, crab, turtle, dog,
## dolphins) with swimmers, buoys and a sailboat out on the water.
##
## Sprites come from one atlas baked by tools/bake_beach_sprites.py and are drawn from
## three MultiMeshes (upright sprites, flat decals, fixed quads), so the whole world is
## a handful of draw calls. Nothing here has collision, nothing goes under a player,
## nothing writes game state, and all randomness uses this node's own seeded generator
## (the global one is shared with the seeded AI). The only game state read is
## `game_state` (the crowd reacts to POINT_SCORED) and `view_flipped()`.
##
## Local -z is always out to sea. After a doubles change of ends the camera rig turns
## half a turn about the court centre, so this node turns with it and the ocean stays
## at the top of the screen.

const META_PATH := "res://assets/beach/beach_meta.json"
const Atlas := preload("res://assets/beach/beach_atlas.png")
const SpriteShader := preload("res://shaders/beach_sprite.gdshader")
const DecalShader := preload("res://shaders/beach_decal.gdshader")
const GroundShader := preload("res://shaders/beach_ground.gdshader")
const FlatShader := preload("res://shaders/beach_flat.gdshader")
const Logo := preload("res://assets/branding/arjostyle-pickleball.png")
const BrandShader := preload("res://shaders/court_brand.gdshader")

const SEED := 20261122
const GROUND_Y := 0.066           # just under the court surface (top 0.075)
const DECAL_Y := 0.071
const FENCE_X := 5.9
const FENCE_Z := 9.8
const FENCE_NEAR_Z := 7.5         # side fences stop short of the camera end
const SHORE_Z := -18.6
const POINT_SCORED := 3           # game.gd GameState.POINT_SCORED

var _game: Node
var _meta: Dictionary = {}
var _palette: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _last_state := -1
var _flipped := false

# Instance specs; written into the MultiMeshes once they are built.
var _sprites: Array = []   # {name, frame, pos, flip, sway, phase, scale, hidden}
var _decals: Array = []    # {name, frame, pos, size, yaw}
var _fixed: Array = []     # {name, frame, xform}
var _mm_sprite: MultiMesh
var _mm_decal: MultiMesh
var _mm_fixed: MultiMesh

var _fans: Array = []      # {idx, standing, mode, until, delay, next_look, look_until, base}
var _actors: Array = []    # animated things: {kind, idx, shadow, ...}


func setup(game: Node, parent: Node3D) -> void:
	_game = game
	name = "BeachWorld"
	parent.add_child(self)
	_rng.seed = SEED
	var f := FileAccess.open(META_PATH, FileAccess.READ)
	_meta = JSON.parse_string(f.get_as_text())
	for k in _meta.palette: _palette[k] = Color(str(_meta.palette[k]))
	var apron := game.find_child("CourtApron", true, false)
	if apron is Node3D: apron.visible = false        # the ground shader draws the pad instead
	_build_ground()
	_build_fence_and_banner()
	_build_pier()
	_place_world()
	_build_multimeshes()


# ------------------------------------------------------------------ building

func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "BeachGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(600.0, 600.0)
	ground.mesh = plane
	ground.position = Vector3(0.0, GROUND_Y, 0.0)
	var m := ShaderMaterial.new()
	m.shader = GroundShader
	for k in ["sand", "sand_dk", "sand_lt", "wet", "wet_dk", "foam", "shallow", "water", "deep", "deeper", "haze", "pad", "pad_dk", "curb"]:
		m.set_shader_parameter(k, _palette[k])
	m.set_shader_parameter("gain", float(_meta.gain))
	m.set_shader_parameter("shore_z", SHORE_Z)
	m.set_shader_parameter("pad_half", Vector2(FENCE_X, FENCE_Z))
	ground.material_override = m
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)


func _flat_mesh(label: String, st: SurfaceTool) -> void:
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = FlatShader
	m.set_shader_parameter("gain", float(_meta.gain))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


static func _box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	var arrays := box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		var n: Vector3 = normals[index]
		if n.y < -0.5: continue
		var b := 1.0 if n.y > 0.5 else (0.86 if n.z > 0.5 or n.x < -0.5 else 0.74)
		st.set_color(Color(color.r * b, color.g * b, color.b * b))
		st.add_vertex(center + vertices[index])


func _rope(st: SurfaceTool, a: Vector3, b: Vector3, sag: float, color: Color) -> void:
	var steps := 4
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var p0 := a.lerp(b, t0) + Vector3.DOWN * sag * 4.0 * t0 * (1.0 - t0)
		var p1 := a.lerp(b, t1) + Vector3.DOWN * sag * 4.0 * t1 * (1.0 - t1)
		var mid := (p0 + p1) * 0.5
		var span := p1 - p0
		var along_x := absf(span.x) > absf(span.z)
		var size := Vector3(absf(span.x) + 0.035, 0.035, 0.035) if along_x else Vector3(0.035, 0.035, absf(span.z) + 0.035)
		size.y += absf(span.y)
		_box(st, mid, size, color)


func _build_fence_and_banner() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bamboo: Color = _palette.bamboo
	var knot: Color = _palette.bamboo_dk
	var rope: Color = _palette.rope
	var runs: Array = [
		[Vector3(-FENCE_X, 0, -FENCE_Z), Vector3(FENCE_X, 0, -FENCE_Z)],
		[Vector3(-FENCE_X, 0, -FENCE_Z), Vector3(-FENCE_X, 0, FENCE_NEAR_Z)],
		[Vector3(FENCE_X, 0, -FENCE_Z), Vector3(FENCE_X, 0, FENCE_NEAR_Z)]]
	for run in runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var count := int(ceil(a.distance_to(b) / 1.6))
		for i in count + 1:
			var p := a.lerp(b, float(i) / count)
			_box(st, p + Vector3(0, 0.55, 0), Vector3(0.09, 1.1, 0.09), bamboo)
			_box(st, p + Vector3(0, 0.38, 0), Vector3(0.1, 0.035, 0.1), knot)
			_box(st, p + Vector3(0, 0.8, 0), Vector3(0.1, 0.035, 0.1), knot)
			_box(st, p + Vector3(0, 1.11, 0), Vector3(0.11, 0.03, 0.11), knot)
			if i < count:
				var q := a.lerp(b, float(i + 1) / count)
				_rope(st, p + Vector3(0, 0.98, 0), q + Vector3(0, 0.98, 0), 0.07, rope)
				_rope(st, p + Vector3(0, 0.55, 0), q + Vector3(0, 0.55, 0), 0.05, rope)
	# Wordmark banner on two tall posts behind the far baseline.
	var banner_z := -FENCE_Z - 0.15
	for x in [-2.45, 2.45]:
		_box(st, Vector3(x, 0.95, banner_z), Vector3(0.12, 1.9, 0.12), bamboo)
		_box(st, Vector3(x, 1.92, banner_z), Vector3(0.16, 0.05, 0.16), knot)
	_box(st, Vector3(0, 1.22, banner_z), Vector3(4.75, 1.22, 0.05), _palette.navy)
	_box(st, Vector3(0, 1.85, banner_z), Vector3(4.9, 0.06, 0.07), knot)
	_flat_mesh("BeachFence", st)
	var mark := MeshInstance3D.new()
	mark.name = "BeachWordmark"
	var quad := QuadMesh.new()
	quad.size = Vector2(4.4, 1.15)
	mark.mesh = quad
	mark.position = Vector3(0, 1.22, banner_z + 0.03)
	var bm := ShaderMaterial.new()
	bm.shader = BrandShader
	bm.set_shader_parameter("logo_texture", Logo)
	bm.set_shader_parameter("ink", Color(0.98, 0.9, 0.66, 0.95))
	mark.material_override = bm
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mark)
	# Bunting along the back fence's top rope, both sides of the banner.
	var x := -FENCE_X + 0.25
	var i := 0
	while x < FENCE_X - 0.2:
		if absf(x) > 2.7:
			var span := 1.6
			var t := fposmod(x + FENCE_X, span) / span
			var y := 0.98 - 0.07 * 4.0 * t * (1.0 - t) - 0.42
			var xf := Transform3D(Basis(Vector3.UP, 0.0).scaled(Vector3(0.36, 0.42, 1.0)), Vector3(x, y, -FENCE_Z + 0.04))
			_fixed.append({"name": "bunting_%d" % (i % 5), "frame": 0, "xform": xf})
			i += 1
		x += 0.42


func _build_pier() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood: Color = _palette.wood
	var wood_dk: Color = _palette.wood_dk
	var px := 11.5
	var z0 := SHORE_Z + 1.0
	var z1 := -31.0
	var z := z0
	var k := 0
	while z > z1:
		_box(st, Vector3(px, 0.62, z - 0.15), Vector3(1.8, 0.07, 0.26), wood if k % 2 == 0 else wood.lerp(wood_dk, 0.35))
		z -= 0.3
		k += 1
	z = z0
	while z > z1 - 0.1:
		for side in [-1.0, 1.0]:
			_box(st, Vector3(px + side * 0.95, 0.45, z), Vector3(0.14, 1.0, 0.14), wood_dk)
		z -= 2.2
	_box(st, Vector3(px + 0.95, 1.2, z1 + 0.1), Vector3(0.18, 1.2, 0.18), wood_dk)   # pelican post
	_flat_mesh("BeachPier", st)


# ------------------------------------------------------------------ placing

func _sprite(sprite: String, pos: Vector3, frame := 0, flip := false, sway := 0.0, scale_f := 1.0) -> int:
	_sprites.append({"name": sprite, "frame": frame, "pos": pos, "flip": flip, "sway": sway,
		"phase": _rng.randf(), "scale": scale_f, "hidden": false})
	return _sprites.size() - 1


func _decal(sprite: String, pos: Vector2, size: Vector2, yaw := 0.0) -> int:
	_decals.append({"name": sprite, "frame": 0, "pos": pos, "size": size, "yaw": yaw})
	return _decals.size() - 1


func _shadow(pos: Vector3, width: float, depth := -1.0) -> int:
	# the sun comes from the camera-left side: shadows fall a little right and back
	var d := width * 0.45 if depth < 0.0 else depth
	return _decal("shadow", Vector2(pos.x + width * 0.12, pos.z - d * 0.15), Vector2(width, d))


func _size(sprite: String) -> Vector2:
	var s: Array = _meta.sprites[sprite].size_m
	return Vector2(float(s[0]), float(s[1]))


func _place_world() -> void:
	# Towels first: decals draw in order and shadows go over them.
	_decal("towel_3", Vector2(-4.3, -14.2), Vector2(1.0, 1.8), 1.45)
	_decal("towel_0", Vector2(3.0, -14.7), Vector2(1.0, 1.8), 0.2)
	_decal("towel_1", Vector2(4.4, -14.9), Vector2(1.0, 1.8), -0.15)
	_decal("towel_2", Vector2(7.4, -15.4), Vector2(1.0, 1.8), 0.5)
	_decal("towel_0", Vector2(-1.1, -14.9), Vector2(1.0, 1.8), -0.4)
	# Coconut palms framing the court and lining the beach.
	var palms: Array = [
		[-7.6, -6.5, 2, false], [7.8, -4.0, 0, true], [-9.6, -13.4, 0, false], [9.9, -14.3, 1, false],
		[-14.5, -10.5, 1, false], [14.8, -9.5, 2, true], [-5.7, -17.1, 3, false], [16.2, -16.8, 3, true],
		[-19.0, -15.6, 2, false], [12.6, -1.5, 3, false], [-11.8, -1.2, 0, true], [-24.0, -12.0, 1, true],
		[22.0, -13.0, 0, false]]
	for p in palms:
		var pos := Vector3(p[0], 0.0, p[1])
		_sprite("palm_%d" % p[2], pos, 0, p[3], _rng.randf_range(0.12, 0.22))
		_shadow(pos, 2.6, 1.1)
	# Bleacher benches behind the far fence: eight seated fans and four standing.
	for bx in [-4.2, 0.0, 4.2]:
		_sprite("bench", Vector3(bx, 0.0, -11.45))
		_shadow(Vector3(bx, 0, -11.45), 3.8, 0.7)
	var seat := 0
	for bx in [-4.2, 0.0, 4.2]:
		for off in [-1.15, 0.0, 1.15]:
			var pos := Vector3(bx + off, 0.0, -11.28)
			if bx == 0.0 and off == 0.0:
				_sprite("cooler", pos + Vector3(0, 0.45, 0))
				continue
			_add_fan("fan_sit_%d" % seat, pos, false)
			seat += 1
	var stand_x: Array = [-6.0, -2.0, 1.6, 4.8]
	for i in 4:
		var pos := Vector3(stand_x[i], 0.0, -12.65 + _rng.randf_range(-0.2, 0.2))
		_add_fan("fan_stand_%d" % i, pos, true)
		_shadow(pos, 0.8)
	# Beach life.
	_sprite("tiki_hut", Vector3(-9.2, 0.0, -11.0)); _shadow(Vector3(-9.2, 0, -11.0), 4.2, 1.6)
	_actors.append({"kind": "loop2", "idx": _sprites.size() - 1, "rate": 2.2})
	_sprite("icecream_cart", Vector3(8.2, 0.0, -12.0)); _shadow(Vector3(8.2, 0, -12.0), 2.4, 0.9)
	_actors.append({"kind": "bell", "idx": _sprites.size() - 1, "next": 3.0})
	_sprite("lifeguard_tower", Vector3(-10.8, 0.0, -15.8)); _shadow(Vector3(-10.8, 0, -15.8), 3.0, 1.4)
	_actors.append({"kind": "tower", "idx": _sprites.size() - 1, "next": 2.0, "frame": 0})
	for u in [[1, -4.0, -14.7], [0, 3.6, -15.2], [2, 7.0, -15.8], [3, -1.4, -15.3]]:
		var pos := Vector3(u[1], 0.0, u[2])
		_sprite("umbrella_%d" % u[0], pos)
		_shadow(pos + Vector3(0.6, 0, 0.3), 2.8, 1.4)
	_sprite("sunbather", Vector3(-4.3, 0.0, -14.25))
	_actors.append({"kind": "sunbather", "idx": _sprites.size() - 1, "next": 6.0})
	_sprite("kid_sandcastle", Vector3(0.9, 0.0, -16.5)); _shadow(Vector3(0.9, 0, -16.5), 1.8, 0.6)
	_actors.append({"kind": "loop2", "idx": _sprites.size() - 1, "rate": 2.6})
	for s in [[0, -7.5, -15.6], [1, -7.0, -15.75], [2, 9.2, -16.4]]:
		_sprite("surfboard_%d" % s[0], Vector3(s[1], 0.0, s[2]))
		_shadow(Vector3(s[1], 0, s[2]), 0.7, 0.3)
	_sprite("beach_ball", Vector3(-1.8, 0.0, -13.8)); _shadow(Vector3(-1.8, 0, -13.8), 0.6, 0.25)
	_sprite("cooler", Vector3(4.1, 0.0, -14.1)); _shadow(Vector3(4.1, 0, -14.1), 0.9, 0.35)
	for r in [["rock_0", -9.6, -19.0, false], ["rock_1", -8.4, -19.2, true], ["rock_0", 9.8, -19.4, true]]:
		_sprite(r[0], Vector3(r[1], 0.0, r[2]), 0, r[3])
	_sprite("driftwood", Vector3(7.6, 0.0, -17.4))
	for i in 9:
		var shell_pos := Vector3(_rng.randf_range(-13.0, 13.0), 0.0, _rng.randf_range(-17.6, -16.6))
		_sprite("starfish" if i % 3 == 0 else "shell", shell_pos, 0, i % 2 == 0)
	# Far out: islands, a sailboat, buoys and swimmers.
	# (The phone's top edge sits just under the horizon, ~170 m out, so anything far and
	# tall is cut off: the sailboat stays at 50 m and small.)
	_actors.append({"kind": "sailboat", "idx": _sprite("sailboat", Vector3(-20.0, 0.0, -50.0))})
	for b in [[-8.0, -32.0], [6.5, -37.0], [-19.0, -29.0]]:
		_actors.append({"kind": "bob", "idx": _sprite("buoy", Vector3(b[0], 0.0, b[1])), "base": Vector3(b[0], 0.0, b[1]), "phase": _rng.randf() * TAU})
	for s in [[-3.2, -24.5], [8.6, -27.5]]:
		_actors.append({"kind": "swimmer", "idx": _sprite("swimmer", Vector3(s[0], 0.0, s[1])), "base": Vector3(s[0], 0.0, s[1]), "phase": _rng.randf() * TAU})
	# Animals.
	_actors.append({"kind": "pelican", "idx": _sprite("pelican", Vector3(12.45, 1.8, -30.9)), "next": 4.0})
	for g in [[-3.5, -17.3], [-2.6, -17.8], [4.8, -17.2], [5.7, -17.7]]:
		var pos := Vector3(g[0], 0.0, g[1])
		_actors.append({"kind": "gull_ground", "idx": _sprite("gull_ground", pos, 0, _rng.randf() < 0.5),
			"shadow": _shadow(pos, 0.5), "home": pos, "pos": pos, "next": _rng.randf_range(1.0, 4.0),
			"mode": "idle", "fly_t": 0.0, "dir": 1.0})
	for i in 3:
		_actors.append({"kind": "gull_fly", "idx": _sprite("gull_fly", Vector3.ZERO), "phase": _rng.randf() * TAU,
			"radius": _rng.randf_range(8.0, 14.0), "height": _rng.randf_range(6.0, 10.0), "speed": _rng.randf_range(0.18, 0.3) * (1.0 if i % 2 == 0 else -1.0),
			"center": Vector3(_rng.randf_range(-6.0, 6.0), 0.0, _rng.randf_range(-24.0, -20.0))})
	var crab_pos := Vector3(-7.5, 0.0, -18.3)
	_actors.append({"kind": "crab", "idx": _sprite("crab", crab_pos), "shadow": _shadow(crab_pos, 0.5),
		"pos": crab_pos, "target": -5.5, "pause": 0.0})
	var turtle_pos := Vector3(-1.6, 0.0, -15.6)
	_actors.append({"kind": "turtle", "idx": _sprite("turtle", turtle_pos), "shadow": _shadow(turtle_pos, 0.8),
		"start": turtle_pos, "pos": turtle_pos})
	var dog_pos := Vector3(-9.0, 0.0, -17.4)
	_actors.append({"kind": "dog", "idx": _sprite("dog", dog_pos), "shadow": _shadow(dog_pos, 0.9),
		"pos": dog_pos, "dir": 1.0, "pause": 0.0})
	for i in 2:
		_actors.append({"kind": "dolphin", "idx": _sprite("dolphin", Vector3.ZERO), "splash": _sprite("splash", Vector3.ZERO),
			"next": 4.0 + i * 7.0, "t": -1.0, "pos": Vector3.ZERO, "dir": 1.0})


func _add_fan(sprite: String, pos: Vector3, standing: bool) -> void:
	var idx := _sprite(sprite, pos, 0, _rng.randf() < 0.3)
	_fans.append({"idx": idx, "standing": standing, "mode": "idle", "until": 0.0, "delay": 0.0,
		"next_look": _rng.randf_range(2.0, 9.0), "look_until": 0.0, "rate": _rng.randf_range(5.0, 7.5)})


# ------------------------------------------------------------------ multimeshes

func _build_multimeshes() -> void:
	var tex_size := Vector2(float(_meta.atlas_px[0]), float(_meta.atlas_px[1]))
	var upright := QuadMesh.new()
	upright.size = Vector2.ONE
	upright.center_offset = Vector3(0.0, 0.5, 0.0)
	_mm_sprite = _new_mm(upright, _sprites.size())
	_add_mm("BeachSprites", _mm_sprite, _material(SpriteShader, 1.0))
	var flat := QuadMesh.new()
	flat.size = Vector2.ONE
	_mm_decal = _new_mm(flat, _decals.size())
	_add_mm("BeachDecals", _mm_decal, _material(DecalShader, 0.0))
	_mm_fixed = _new_mm(upright, _fixed.size())
	_add_mm("BeachFixed", _mm_fixed, _material(SpriteShader, 0.0))
	for i in _sprites.size(): _write_sprite(i)
	for i in _decals.size(): _write_decal(i)
	for i in _fixed.size():
		var spec: Dictionary = _fixed[i]
		_mm_fixed.set_instance_transform(i, spec.xform)
		_mm_fixed.set_instance_custom_data(i, _rect(spec.name, 0, false))
		_mm_fixed.set_instance_color(i, Color(0, 0, 0, 1))


func _new_mm(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	return mm


func _material(shader: Shader, billboard: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("atlas", Atlas)
	m.set_shader_parameter("gain", float(_meta.gain))
	if shader == SpriteShader: m.set_shader_parameter("billboard", billboard)
	return m


func _add_mm(label: String, mm: MultiMesh, material: Material) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# billboards move their vertices in the shader: never cull by the quad's own bounds
	mmi.custom_aabb = AABB(Vector3(-320, -5, -320), Vector3(640, 80, 640))
	add_child(mmi)


func _rect(sprite: String, frame: int, flip: bool) -> Color:
	var frames: Array = _meta.sprites[sprite].frames
	var r: Array = frames[clampi(frame, 0, frames.size() - 1)]
	return Color(float(r[0]), float(r[1]), -float(r[2]) if flip else float(r[2]), float(r[3]))


func _write_sprite(i: int) -> void:
	var spec: Dictionary = _sprites[i]
	var s := _size(spec.name) * float(spec.scale)
	var basis := Basis.from_scale(Vector3(s.x, s.y, 1.0)) if not spec.hidden else Basis.from_scale(Vector3.ZERO)
	_mm_sprite.set_instance_transform(i, Transform3D(basis, spec.pos))
	_mm_sprite.set_instance_custom_data(i, _rect(spec.name, spec.frame, spec.flip))
	_mm_sprite.set_instance_color(i, Color(spec.sway, spec.phase, 0.0, 1.0))


func _write_decal(i: int) -> void:
	var spec: Dictionary = _decals[i]
	var size: Vector2 = spec.size
	var flat := Basis(Vector3(size.x, 0, 0), Vector3(0, 0, -size.y), Vector3(0, 1, 0))
	var pos: Vector2 = spec.pos
	_mm_decal.set_instance_transform(i, Transform3D(Basis(Vector3.UP, spec.yaw) * flat, Vector3(pos.x, DECAL_Y, pos.y)))
	_mm_decal.set_instance_custom_data(i, _rect(spec.name, 0, false))
	_mm_decal.set_instance_color(i, Color(0, 0, 0, 1))


func _put(i: int, frame: int, pos: Vector3, flip: bool, hidden := false) -> void:
	var spec: Dictionary = _sprites[i]
	spec.frame = frame
	spec.pos = pos
	spec.flip = flip
	spec.hidden = hidden
	_write_sprite(i)


func _move_shadow(i: int, pos: Vector3, hidden := false) -> void:
	var spec: Dictionary = _decals[i]
	var size: Vector2 = spec.size
	spec.pos = Vector2(pos.x + size.x * 0.12, pos.z - size.y * 0.15)
	if hidden: spec.size = Vector2.ZERO
	_write_decal(i)
	spec.size = size


# ------------------------------------------------------------------ animation

func _process(delta: float) -> void:
	if _mm_sprite == null: return
	var t0 := Time.get_ticks_usec()
	_t += delta
	var flipped: bool = _game != null and _game.has_method("view_flipped") and bool(_game.view_flipped())
	if flipped != _flipped:
		_flipped = flipped
		transform.basis = Basis(Vector3.UP, PI) if flipped else Basis.IDENTITY
	var state := int(_game.get("game_state")) if _game != null else -1
	if state == POINT_SCORED and _last_state != POINT_SCORED: _start_cheer()
	_last_state = state
	_update_fans()
	for a in _actors: _update_actor(a, delta)
	PerfMonitor.record("env.beach", Time.get_ticks_usec() - t0)


func _start_cheer() -> void:
	for f in _fans:
		f.mode = "cheer" if _rng.randf() < 0.65 else "clap"
		f.delay = _t + _rng.randf_range(0.0, 0.35)
		f.until = f.delay + _rng.randf_range(1.6, 2.6)


func _update_fans() -> void:
	for f in _fans:
		var spec: Dictionary = _sprites[f.idx]
		var frame := 0
		if f.mode != "idle" and _t >= f.delay:
			var beat := int((_t - f.delay) * float(f.rate)) % 2
			frame = (4 + beat) if f.mode == "cheer" else (2 + beat)
			if _t > f.until:
				# cheering fans finish with a few claps, then settle
				if f.mode == "cheer":
					f.mode = "clap"
					f.until = _t + _rng.randf_range(0.6, 1.2)
				else:
					f.mode = "idle"
		elif f.mode == "idle":
			if _t > f.next_look:
				f.look_until = _t + _rng.randf_range(0.8, 2.0)
				f.next_look = f.look_until + _rng.randf_range(3.0, 10.0)
			frame = 1 if _t < f.look_until else 0
		if frame != int(spec.frame):
			spec.frame = frame
			_write_sprite(f.idx)


func _update_actor(a: Dictionary, delta: float) -> void:
	var spec: Dictionary = _sprites[a.idx]
	match a.kind:
		"loop2":
			var fr := int(_t * float(a.rate)) % 2
			if fr != int(spec.frame): _put(a.idx, fr, spec.pos, spec.flip)
		"bell":
			var ringing := _t < float(a.next) + 1.2 and _t > float(a.next)
			if _t > float(a.next) + 1.2: a.next = _t + _rng.randf_range(6.0, 14.0)
			var fr := (int(_t * 8.0) % 2) if ringing else 0
			if fr != int(spec.frame): _put(a.idx, fr, spec.pos, spec.flip)
		"tower":
			if _t > float(a.next):
				a.frame = [0, 0, 1, 2][_rng.randi() % 4]
				a.next = _t + _rng.randf_range(2.0, 5.0)
			if int(a.frame) != int(spec.frame): _put(a.idx, int(a.frame), spec.pos, spec.flip)
		"sunbather":
			if _t > float(a.next):
				_put(a.idx, 1 - int(spec.frame), spec.pos, spec.flip)
				a.next = _t + _rng.randf_range(5.0, 12.0)
		"sailboat":
			var x := -24.0 + fposmod(_t * 0.3 + 12.0, 48.0)
			var bob := 0.12 * sin(_t * 0.9)
			_put(a.idx, int(_t * 1.5) % 2, Vector3(x, bob - 0.25, -50.0), false)
		"bob":
			var base: Vector3 = a.base
			_put(a.idx, 0, base + Vector3(0, -0.15 + 0.12 * sin(_t * 1.6 + float(a.phase)), 0), false)
		"swimmer":
			var base: Vector3 = a.base
			var drift := Vector3(1.5 * sin(_t * 0.07 + float(a.phase)), -0.2 + 0.08 * sin(_t * 2.0 + float(a.phase)), 0)
			_put(a.idx, int(_t * 1.6) % 2, base + drift, cos(_t * 0.07 + float(a.phase)) < 0.0)
		"pelican":
			if _t > float(a.next):
				_put(a.idx, 1 - int(spec.frame), spec.pos, spec.flip)
				a.next = _t + _rng.randf_range(2.5, 7.0)
		"gull_fly":
			var ang := float(a.phase) + _t * float(a.speed)
			var c: Vector3 = a.center
			var pos := c + Vector3(cos(ang) * float(a.radius), float(a.height) + 0.6 * sin(_t * 0.7 + float(a.phase)), sin(ang) * float(a.radius) * 0.45)
			var heading := -sin(ang) * float(a.speed)
			var glide := sin(_t * 0.5 + float(a.phase)) > 0.4
			var fr := 1 if glide else int(_t * 7.0 + float(a.phase)) % 4
			_put(a.idx, fr, pos, heading < 0.0)
		"gull_ground":
			_update_ground_gull(a, delta)
		"crab":
			var pos: Vector3 = a.pos
			if float(a.pause) > 0.0:
				a.pause = float(a.pause) - delta
				_put(a.idx, 0, pos, false)
			else:
				var dx := float(a.target) - pos.x
				pos.x += signf(dx) * minf(absf(dx), 0.9 * delta)
				a.pos = pos
				_put(a.idx, int(_t * 10.0) % 2, pos, false)
				if absf(dx) < 0.02:
					a.target = _rng.randf_range(-9.0, -4.0)
					a.pause = _rng.randf_range(1.0, 4.0)
			_move_shadow(a.shadow, pos)
		"turtle":
			var start: Vector3 = a.start
			var cycle := fposmod(_t, 70.0)
			var pos := start + Vector3(-0.2 * cycle / 70.0, 0.0, -cycle * 0.065)
			var swim := pos.z < SHORE_Z + 0.3
			var gone := pos.z < SHORE_Z - 0.6
			if swim: pos.y = -0.15
			_put(a.idx, int(_t * 2.0) % 2, pos, true, gone)
			_move_shadow(a.shadow, pos, swim)
		"dog":
			_update_dog(a, delta)
		"dolphin":
			_update_dolphin(a, delta)


func _update_ground_gull(a: Dictionary, delta: float) -> void:
	var pos: Vector3 = a.pos
	var home: Vector3 = a.home
	match str(a.mode):
		"idle":
			var fr := 1 if fposmod(_t + float(a.next), 3.0) < 0.5 else 0
			_put(a.idx, fr, pos, _sprites[a.idx].flip)
			if _t > float(a.next):
				var r := _rng.randf()
				if r < 0.2:
					a.mode = "fly"
					a.fly_t = 0.0
					a.dir = -1.0 if _rng.randf() < 0.5 else 1.0
				elif r < 0.7:
					a.mode = "walk"
					a.walk_to = home + Vector3(_rng.randf_range(-1.2, 1.2), 0, _rng.randf_range(-0.4, 0.4))
				a.next = _t + _rng.randf_range(2.0, 6.0)
		"walk":
			var to: Vector3 = a.walk_to
			var step := to - pos
			if step.length() < 0.03:
				a.mode = "idle"
			else:
				pos += step.normalized() * minf(step.length(), 0.45 * delta)
				a.pos = pos
				_put(a.idx, 2 if int(_t * 6.0) % 2 == 0 else 0, pos, step.x < 0.0)
		"fly":
			# a lap out over the water and back to the same spot
			a.fly_t = float(a.fly_t) + delta
			var k := float(a.fly_t) / 9.0
			if k >= 1.0:
				a.mode = "idle"
				a.pos = home
				_put(a.idx, 0, home, _sprites[a.idx].flip)
				_move_shadow(a.shadow, home)
				return
			var ang := k * TAU
			var p := home + Vector3(float(a.dir) * sin(ang) * 6.0, sin(k * PI) * 4.5, -(1.0 - cos(ang)) * 3.0)
			var spec: Dictionary = _sprites[a.idx]
			spec.name = "gull_fly"
			_put(a.idx, int(_t * 8.0) % 4, p, cos(ang) * float(a.dir) < 0.0)
			_move_shadow(a.shadow, Vector3(p.x, 0, p.z), p.y > 1.5)
			return
	_move_shadow(a.shadow, pos)


func _update_dog(a: Dictionary, delta: float) -> void:
	var pos: Vector3 = a.pos
	if float(a.pause) > 0.0:
		a.pause = float(a.pause) - delta
		_put(a.idx, 4 + int(_t * 4.0) % 2, pos, float(a.dir) < 0.0)
	else:
		pos.x += float(a.dir) * 3.2 * delta
		# chase the wash: run a little closer to the water and back
		pos.z = -17.4 - 0.5 * (0.5 + 0.5 * sin(_t * 0.45 + 3.6))
		a.pos = pos
		_put(a.idx, int(_t * 10.0) % 4, pos, float(a.dir) < 0.0)
		if absf(pos.x) > 10.5 and signf(pos.x) == float(a.dir):
			a.dir = -float(a.dir)
			a.pause = _rng.randf_range(1.5, 3.5)
	_move_shadow(a.shadow, pos)


func _update_dolphin(a: Dictionary, delta: float) -> void:
	if float(a.t) < 0.0:
		_put(a.idx, 0, Vector3.ZERO, false, true)
		_put(a.splash, 0, Vector3.ZERO, false, true)
		if _t > float(a.next):
			a.t = 0.0
			a.dir = -1.0 if _rng.randf() < 0.5 else 1.0
			a.pos = Vector3(_rng.randf_range(-14.0, 14.0), 0.0, _rng.randf_range(-48.0, -32.0))
		return
	a.t = float(a.t) + delta
	var k := float(a.t) / 1.4
	var start: Vector3 = a.pos
	if k >= 1.0:
		# splash where it went back in, then wait for the next jump
		var splash_k := (float(a.t) - 1.4) / 0.45
		var end := start + Vector3(float(a.dir) * 3.2, -0.2, 0)
		_put(a.idx, 0, Vector3.ZERO, false, true)
		if splash_k >= 1.0:
			_put(a.splash, 0, Vector3.ZERO, false, true)
			a.t = -1.0
			a.next = _t + _rng.randf_range(6.0, 14.0)
		else:
			_put(a.splash, mini(2, int(splash_k * 3.0)), end, false)
		return
	var pos := start + Vector3(float(a.dir) * 3.2 * k, 2.2 * sin(k * PI) - 0.9, 0)
	var fr := 0 if k < 0.33 else (1 if k < 0.66 else 2)
	_put(a.idx, fr, pos, float(a.dir) < 0.0)
	if k < 0.25: _put(a.splash, mini(2, int(k * 12.0)), start + Vector3(0, -0.2, 0), false)
	else: _put(a.splash, 0, Vector3.ZERO, false, true)
