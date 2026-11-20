extends Node3D
class_name PixelCardRig
## 2.5D pixel-art cards pinned to the existing posture joints.
##
## Visual only: reads pivot transforms, never writes them, so IK, poses and
## gameplay are untouched (verified with tools/bench.sh + tools/pose_diff.py:
## identical pose traces with cards on and off). The rig lives beside the
## player, not under BodyPivot, because gameplay scans every BodyPivot mesh.
## The classic body meshes stay alive (gameplay reads their transforms and
## bounds) but move to a render layer the gameplay camera does not draw.
## Default on via Settings "video.character_style" = 1; set 0, or run with
## PICKLEBALL_CLASSIC_BODIES=1, for the classic 3D bodies. To retire the old
## 3D bodies later, delete this switch, not the meshes gameplay still reads.
## Card art: assets/pixel_cards (baked by the art generator in the main repo's
## docs/pixel_art_test/generator/make_cards.py).
##
## One mesh per player: every part is a quad in a single dynamic ArrayMesh with
## one shader material (one draw call per player). UVs address the atlas
## directly, so hand states are just a different atlas row.
##
## Card-layer polish (all placement only, joints and pivots are never written):
## - hand states open / grip / reach: two extra atlas rows are painted at load
##   (_extended_atlas) from the atlas skin colour, so no new art files are needed
## - joint overlap (LIMB_OVERLAP) and a per-part depth bias by camera side, so the
##   near arm/leg draws over the torso and the far one behind it (alpha scissor)
## - per-actor accent: palette swap of the team-coloured pixels (shader), see
##   apply_accent(); the human keeps the authored art, partner and the second
##   opponent get an accent
## - anticipation hold + contact pop (squash and stretch of the cards, about their
##   joint anchors, so hands stay on the paddle), driven by player.hitting
## - far tier: players beyond FAR_DIST sample the atlas at reduced texel density.
##   TODO(art): when a dedicated half-size far atlas is baked, add a "far" entry to
##   cards_meta.json and swap `atlas` in _set_far() instead of the shader snap.
## Debug: PICKLEBALL_CARD_DEBUG=nocards,bones,axes (comma list) or PixelCardRig.set_debug().

const ElbowSwivel = preload("res://scripts/elbow_swivel.gd")
const STYLE_KEY: = "video.character_style"   # 1 = pixel cards (default), 0 = classic 3D
const CLASSIC_LAYER: = 20                     # 1-based render layer hidden from the camera
const CELL_DEG: = 22.5
const HYSTERESIS_DEG: = 4.0
const META_PATH: = "res://assets/pixel_cards/cards_meta.json"
const TEXTURES: = ["res://assets/pixel_cards/cards_blue.png", "res://assets/pixel_cards/cards_red.png"]
const CARD_SHADER: = preload("res://shaders/pixel_card.gdshader")
const LUT_PATH: = "res://assets/pixel_cards/card_tonemap_lut.json"

const HAND_OPEN: = 0
const HAND_GRIP: = 1
const HAND_REACH: = 2
const EXTRA_ROWS: = 2                 # atlas rows appended at load: grip hand, reach hand
const REACH_ON: = 0.90                # arm extension (shoulder-hand / arm length) that shows the reach hand
const REACH_OFF: = 0.82
const FAR_DIST: = 16.0                # metres from the camera (camera ~ (0,10.5,11): far-court players are 17-21 m, near-court 10-14 m)
const FAR_HYST: = 1.5
const LIMB_OVERLAP: = 1.04            # limb cards run 4% long so joints never open a gap
const PART_BIAS: = {"head": 0.02, "torso": 0.0, "shorts": -0.01, "upper_arm": 0.03, "forearm": 0.035,
	"hand": 0.04, "thigh": 0.012, "shin": 0.016, "shoe": 0.02}   # metres toward the camera (near side; negated far side)
const BIAS_BLEND: = 0.04              # metres of side offset over which near/far bias eases
const POP_AMOUNT: = 0.08
const ANTICIPATION_AMOUNT: = 0.04
const ACCENT_DISPLAY: = [Color(0.13, 0.78, 0.72), Color(0.95, 0.58, 0.16)]   # on-screen accent per team (blue -> teal, red -> amber)

# Debug toggles (off by default except cards). Env var or set_debug().
static var show_cards: bool = true
static var show_bones: bool = false
static var show_axes: bool = false
static var accents_enabled: bool = true
static var _accents_force: bool = false   # PICKLEBALL_CARD_ACCENTS=force: every actor gets its accent (art check)
static var _env_read: bool = false
static var _far_force: int = -1        # -1 auto, 0 near tier, 1 far tier (PICKLEBALL_CARD_FAR)

static func set_debug(cards: bool, bones: bool, axes: bool) -> void:
	_read_env()
	show_cards = cards
	show_bones = bones
	show_axes = axes

static func _read_env() -> void:
	if _env_read: return
	_env_read = true
	for tok in OS.get_environment("PICKLEBALL_CARD_DEBUG").to_lower().split(",", false):
		match tok.strip_edges():
			"nocards": show_cards = false
			"bones": show_bones = true
			"axes": show_axes = true
	var acc: = OS.get_environment("PICKLEBALL_CARD_ACCENTS")
	if acc == "0": accents_enabled = false
	_accents_force = acc == "force"
	var far: = OS.get_environment("PICKLEBALL_CARD_FAR")
	if far != "": _far_force = 1 if far == "1" else 0

static var _meta: Dictionary = {}
const PROFILE_KEY: = "video.player_profile"

var profile_id: = ""  # sprite profile in use ("" = the original team atlas)
var _grid: Dictionary = {}  # cell size, texel size and part anchors of the atlas in use

var _player  # player.gd instance (untyped: uses its script members)
var _cards: Array = []
var _cells: Dictionary = {}
var _hide_timer: float = 0.0
var _culled_cam: Camera3D = null

var _mat: ShaderMaterial
var _mesh_inst: MeshInstance3D
var _amesh: ArrayMesh
var _verts: PackedVector3Array = PackedVector3Array()
var _uvs: PackedVector2Array = PackedVector2Array()
var _atlas_px: Vector2 = Vector2(640, 440)
var _base_rows: int = 9
var _far: bool = false
var _team_ref_lum: float = 0.2
var _has_other: bool = false
var _paddle_arm = null
var _swing_active: bool = false
var _prev_ft: bool = false
var _ft_t: float = 0.0
var _popped: bool = false
var _pop: float = 0.0
var _pop_v: float = 0.0
var _ant: float = 0.0
var _dbg_inst: MeshInstance3D = null
var _dbg_mesh: ImmediateMesh = null
var _dbg_pts: PackedVector3Array = PackedVector3Array()
var _dbg_cols: PackedColorArray = PackedColorArray()

static func enabled() -> bool:
	# PICKLEBALL_CLASSIC_BODIES=1 forces classic bodies (benchmarks / A-B checks) without touching saved settings.
	if OS.get_environment("PICKLEBALL_CLASSIC_BODIES") == "1": return false
	return int(Settings.get_value(STYLE_KEY, 1)) == 1

static func attach(player) -> PixelCardRig:
	if player == null or player.body_pivot == null or not enabled(): return null
	# Cards live OUTSIDE the player: gameplay scans every mesh under BodyPivot
	# (surface contacts, geometry certificates), so cards there would change play.
	var host: Node = player.get_parent()
	if host == null: return null
	var rig_name: = "PixelCards_%d" % player.get_instance_id()
	var existing: Node = host.get_node_or_null(rig_name)
	if existing != null: existing.queue_free()
	var rig: = PixelCardRig.new()
	rig.name = rig_name
	rig._player = player
	host.add_child(rig)
	return rig

## Give one actor an on-screen accent colour (palette swap of its team-coloured pixels).
static func set_accent(player, display_color: Color) -> void:
	if player == null or player.get_parent() == null: return
	var rig: Node = player.get_parent().get_node_or_null("PixelCards_%d" % player.get_instance_id())
	if rig is PixelCardRig: rig.apply_accent(display_color)

static func _load_meta() -> Dictionary:
	if _meta.is_empty():
		var f: = FileAccess.open(META_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary: _meta = parsed
	return _meta

func _ready() -> void:
	process_priority = 1000  # after posture / IK have moved the pivots
	_read_env()
	var meta: = _load_meta()
	if meta.is_empty(): return
	var team: int = clampi(int(_player.get("team_id")) if _player.get("team_id") != null else _player.player_num, 0, 1)
	var tex_path: String = TEXTURES[team]
	var other_path: String = TEXTURES[1 - team]
	# Player look (tools/bake_pixel_cards.py, data/sprite_profiles/): one atlas per team.
	profile_id = _pick_profile(meta)
	if profile_id != "":
		var path: String = str(meta.profiles[profile_id].textures.get(["blue", "red"][team], ""))
		if ResourceLoader.exists(path):
			tex_path = path
			var opath: String = str(meta.profiles[profile_id].textures.get(["blue", "red"][1 - team], ""))
			other_path = opath if ResourceLoader.exists(opath) else ""
		else: profile_id = ""
	set_meta("sprite_profile", profile_id)
	set_meta("paddle", str(meta.profiles[profile_id].get("paddle", "")) if profile_id != "" else "")
	# Profile atlases may use their own grid (finer texels, bigger cells, own anchors).
	_grid = meta
	if profile_id != "" and meta.profiles[profile_id].has("grid"):
		_grid = meta.duplicate()
		_grid.merge(meta.profiles[profile_id].grid, true)
	meta = _grid
	_base_rows = int(meta.rows)
	var torso: Node3D = _player.body_pivot.get_node_or_null("TorsoMesh")
	var head: Node3D = torso.get_node_or_null("HeadMesh") if torso else null
	var hips: Node3D = _player.body_pivot.get_node_or_null("HipsMesh")
	_add("head", head, null, false, meta, "head")
	_add("torso", torso, null, false, meta, "torso")
	_add("shorts", hips if hips else _player.body_pivot, null, false, meta, "body")
	for side in [["right", false], ["left", true]]:
		var arm: Node3D = _player.get(side[0] + "_arm_node")
		var leg: Node3D = _player.get(side[0] + "_leg_node")
		if arm and arm.get("upper_pivot"):
			_elbow_arm[arm.forearm_pivot] = arm
			_add("upper_arm", arm.upper_pivot, arm.forearm_pivot, side[1], meta, "body", null, arm.upper_pivot)
			_add("forearm", arm.forearm_pivot, arm.hand_pivot, side[1], meta, "body", null, arm.upper_pivot)
			_add("hand", arm.hand_pivot, null, side[1], meta, "body", arm.forearm_pivot, arm.upper_pivot, arm)
		if leg and leg.get("thigh_pivot"):
			_add("thigh", leg.thigh_pivot, leg.shin_pivot, side[1], meta, "body", null, leg.thigh_pivot)
			_add("shin", leg.shin_pivot, leg.foot_pivot, side[1], meta, "body", null, leg.thigh_pivot)
			_add("shoe", leg.foot_pivot, null, side[1], meta, "body", null, leg.thigh_pivot)
	_build_mesh(tex_path, other_path, meta)
	_hide_classic()
	get_tree().node_added.connect(_on_node_added)
	if accents_enabled and (_accents_force or _accent_rank() > 0): apply_accent(ACCENT_DISPLAY[team])

## Human: saved choice (video.player_profile). AI (or nothing saved): a profile nobody
## else on court has, picked with its own RNG so the bench-seeded global RNG is untouched.
func _pick_profile(meta: Dictionary) -> String:
	var all: Dictionary = meta.get("profiles", {})
	if all.is_empty(): return ""
	var saved: = str(Settings.get_value(PROFILE_KEY, ""))
	if not bool(_player.get("is_ai")) and all.has(saved): return saved
	var used: Array = [saved]
	if get_parent() != null:
		for child in get_parent().get_children():
			if child != self and child.has_meta("sprite_profile") and not child.is_queued_for_deletion():
				used.append(child.get_meta("sprite_profile"))
	var free: Array = all.keys().filter(func(k): return not used.has(k))
	if free.is_empty(): free = all.keys()
	var rng: = RandomNumberGenerator.new()
	rng.randomize()
	return str(free[rng.randi_range(0, free.size() - 1)])

func _add(part: String, a: Node3D, b: Node3D, mirror: bool, meta: Dictionary, facing: String, prev: Node3D = null, root: Node3D = null, arm = null) -> void:
	if a == null or not meta.parts.has(part): return
	var info: Dictionary = meta.parts[part]
	_cards.append({"part": part, "a": a, "b": b, "prev": prev, "mirror": mirror, "row": int(info.row),
		"root": root, "arm": arm, "side": 1 if root != null else 0, "hand_state": HAND_OPEN,
		"anchor": Vector2(info.anchor[0], info.anchor[1]), "end": Vector2(info.end[0], info.end[1]) if info.has("end") else Vector2.ZERO,
		"limb": info.has("end") and b != null, "facing": facing})

# ------------------------------------------------------------------ atlas + mesh

static var _atlas_cache: Dictionary = {}   # texture path -> {"tex": ImageTexture, "img": Image}
static var _lut: Dictionary = {}

## The team atlas plus two extra rows (grip hand, reach hand) painted from its own skin
## colour. Cached per texture path; the original atlas is copied unchanged above them.
static func _extended_atlas(path: String, grid: Dictionary) -> Dictionary:
	if _atlas_cache.has(path): return _atlas_cache[path]
	var base: Texture2D = load(path)
	var src: Image = base.get_image()
	if src.is_compressed(): src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var cell: = Vector2i(int(grid.cell[0]), int(grid.cell[1]))
	var cols: int = int(grid.cols)
	var rows: int = int(grid.rows)
	var out: = Image.create_empty(src.get_width(), (rows + EXTRA_ROWS) * cell.y, false, Image.FORMAT_RGBA8)
	out.blit_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i.ZERO)
	_paint_hands(out, grid, cols, rows, cell)
	var entry: = {"tex": ImageTexture.create_from_image(out), "img": out}
	_atlas_cache[path] = entry
	return entry

static func _paint_hands(img: Image, grid: Dictionary, cols: int, rows: int, cell: Vector2i) -> void:
	if not grid.parts.has("hand"): return
	var hand: Dictionary = grid.parts.hand
	var ax: int = int(hand.anchor[0])
	var ay: int = int(hand.anchor[1])
	var hr: int = int(hand.row)
	var skin: = Color(188.0 / 255.0, 83.0 / 255.0, 61.0 / 255.0)
	var probe: Color = img.get_pixel(ax, hr * cell.y + ay + 1)
	if probe.a > 0.5: skin = probe
	var dark: = Color(skin.r * 0.62, skin.g * 0.62, skin.b * 0.62, 1.0)
	# Offsets are texels from the wrist anchor; +y runs away from the forearm.
	var grip: Array = []
	for dy in range(0, 4):
		for dx in range(-2, 3):
			grip.append([dx, dy, dark if (dy == 3 or (dy == 2 and dx >= -1 and dx <= 1)) else skin])
	grip.append([-3, 1, skin])
	var reach: Array = []
	for dy in range(0, 3):
		for dx in range(-2, 2): reach.append([dx, dy, skin])
	for dy in range(3, 6):
		for dx in [-2, 0, 1]: reach.append([dx, dy, dark if dy == 5 else skin])
	for dy in range(3, 5): reach.append([-1, dy, dark])
	reach.append([-3, 1, skin])
	reach.append([-3, 2, dark])
	var shapes: Array = [grip, reach]
	for s in range(shapes.size()):
		var y0: int = (rows + s) * cell.y + ay
		for k in range(cols):
			var x0: int = k * cell.x + ax
			for px in shapes[s]:
				img.set_pixel(x0 + px[0], y0 + px[1], px[2])

func _build_mesh(tex_path: String, other_path: String, meta: Dictionary) -> void:
	var own: Dictionary = _extended_atlas(tex_path, meta)
	_mat = ShaderMaterial.new()
	_mat.shader = CARD_SHADER
	_mat.set_shader_parameter("atlas", own.tex)
	_atlas_px = Vector2(own.img.get_width(), own.img.get_height())
	_mat.set_shader_parameter("atlas_px", _atlas_px)
	_mat.set_shader_parameter("gain", float(meta.get("gain", 1.0)))
	_has_other = other_path != ""
	if _has_other:
		var other: Dictionary = _extended_atlas(other_path, meta)
		_mat.set_shader_parameter("atlas_other", other.tex)
		_team_ref_lum = _team_reference_luminance(own.img, other.img, meta)
		_mat.set_shader_parameter("team_ref_lum", _team_ref_lum)
	else:
		_mat.set_shader_parameter("atlas_other", own.tex)
	var n: int = _cards.size()
	_verts.resize(n * 4)
	_uvs.resize(n * 4)
	var idx: = PackedInt32Array()
	idx.resize(n * 6)
	for i in range(n):
		var o: int = i * 4
		var t: int = i * 6
		idx[t] = o; idx[t + 1] = o + 1; idx[t + 2] = o + 2
		idx[t + 3] = o; idx[t + 4] = o + 2; idx[t + 5] = o + 3
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	_amesh = ArrayMesh.new()
	_amesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	_amesh.custom_aabb = AABB(Vector3(-60, -5, -60), Vector3(120, 20, 120))   # vertices are world space and move every frame
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.name = "Cards"
	_mesh_inst.mesh = _amesh
	_mesh_inst.material_override = _mat
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_inst.top_level = true
	# Placed every rendered frame from interpolated joints (see _process).
	_mesh_inst.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mesh_inst.set_meta("pixel_card", true)
	add_child(_mesh_inst)

## Most common team-coloured (own vs other atlas differ) pixel of the torso: the shirt's main shade.
func _team_reference_luminance(own: Image, other: Image, grid: Dictionary) -> float:
	if not grid.parts.has("torso"): return _team_ref_lum
	var cell: = Vector2i(int(grid.cell[0]), int(grid.cell[1]))
	var row: int = int(grid.parts.torso.row)
	var counts: Dictionary = {}
	var best: = Color.BLACK
	var best_n: int = 0
	for y in range(cell.y):
		for x in range(cell.x):
			var c: Color = own.get_pixel(x, row * cell.y + y)
			if c.a < 0.5: continue
			var o: Color = other.get_pixel(x, row * cell.y + y)
			if absf(c.r - o.r) + absf(c.g - o.g) + absf(c.b - o.b) < 0.1: continue
			var key: int = c.to_rgba32()
			counts[key] = int(counts.get(key, 0)) + 1
			if counts[key] > best_n:
				best_n = counts[key]
				best = c
	if best_n == 0: return _team_ref_lum
	var lin: Color = best.srgb_to_linear()
	return maxf(lin.r * 0.2126 + lin.g * 0.7152 + lin.b * 0.0722, 0.02)

## On-screen colour -> atlas colour, through the tonemap calibration (atlas values are pre-compensated).
static func _display_to_atlas(display: Color) -> Color:
	if _lut.is_empty():
		var f: = FileAccess.open(LUT_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary: _lut = parsed
	if _lut.is_empty(): return display
	var screen: Array = _lut.screen
	var out: Array = []
	for v in [display.r, display.g, display.b]:
		var target: float = v * 255.0
		var i: int = 0
		while i < 255 and float(screen[i]) < target: i += 1
		out.append(float(_lut.atlas[i]) / 255.0)
	return Color(out[0], out[1], out[2])

func apply_accent(display_color: Color) -> void:
	if _mat == null or not _has_other: return
	_mat.set_shader_parameter("accent_color", _display_to_atlas(display_color))
	_mat.set_shader_parameter("accent_mix", 1.0)

func clear_accent() -> void:
	if _mat != null: _mat.set_shader_parameter("accent_mix", 0.0)

## Human keeps the authored art (rank 0). Among same-team actors the human, then the lower
## actor id, ranks first; each later one gets the team accent so partner and opponents read apart.
func _accent_rank() -> int:
	var host: Node = get_parent()
	if host == null or not _player.has_method("get_actor_id"): return 0
	var mine: int = (1000 if bool(_player.get("is_ai")) else 0) + int(_player.get_actor_id())
	var team: int = int(_player.get_team_id())
	var rank: int = 0
	for ch in host.get_children():
		if ch == _player or not is_instance_valid(ch) or not ch.has_method("get_actor_id") or not ch.has_method("get_team_id"): continue
		if int(ch.get_team_id()) != team: continue
		if (1000 if bool(ch.get("is_ai")) else 0) + int(ch.get_actor_id()) < mine: rank += 1
	return rank

# ------------------------------------------------------------------ per frame

var _raw: bool = false
var _elbow_arm: Dictionary = {}   # forearm pivot (elbow) -> arm: the elbow is drawn at the authored swivel

## A joint's drawn position: the node's, except an elbow turned to the pose's authored swivel
## (scripts/elbow_swivel.gd; the solved arm itself stays as gameplay uses it).
func _pos(n: Node3D) -> Vector3:
	var p: Vector3 = _xf(n).origin
	var arm = _elbow_arm.get(n)
	if arm == null or not arm.has_meta(ElbowSwivel.VISUAL_TURN_META): return p
	var fore: Transform3D = _xf(n)
	var wrist_end: Vector3 = fore * Vector3(0.0, 0.0, -float(arm.forearm_length) * float(arm.visual_stretch))
	return ElbowSwivel.visual_elbow(arm, _xf(arm.upper_pivot).origin, p, wrist_end, -1.0 if _raw else Engine.get_physics_interpolation_fraction())

func _xf(n: Node3D) -> Transform3D:
	return n.global_transform if _raw else n.get_global_transform_interpolated()

## Anticipation hold (coil while charging / before contact) and contact pop, as a
## signed length factor: +k stretches the cards along their length, -k squashes.
func _squash(delta: float) -> float:
	var h = _player.get("hitting")
	if h == null: return 0.0
	var d: float = minf(delta, 0.05)
	var ft: bool = bool(h.is_in_follow_through)
	var charge: bool = bool(h.charge_visual_active)
	_swing_active = ft or charge
	var strike: float = 0.09
	if ft:
		var times: Array = h._ft_phase_times   # read only: [strike end, sweep end, ...] seconds
		if not times.is_empty(): strike = maxf(float(times[0]), 0.03)
	if ft and not _prev_ft:
		_ft_t = 0.0
		_popped = false
	if ft: _ft_t += d
	else: _popped = false
	_prev_ft = ft
	var hold: bool = (charge and not ft) or (ft and _ft_t < strike * 0.6)
	_ant = move_toward(_ant, 1.0 if hold else 0.0, d * (10.0 if hold else 40.0))
	if ft and not _popped and _ft_t >= strike:
		_popped = true
		_pop = POP_AMOUNT
		_pop_v = 0.0
	_pop_v += (-900.0 * _pop - 36.0 * _pop_v) * d
	_pop += _pop_v * d
	return _pop - ANTICIPATION_AMOUNT * _ant

func _update_far(dist: float) -> void:
	var want: bool = _far
	if _far_force >= 0: want = _far_force == 1
	elif _far and dist < FAR_DIST - FAR_HYST: want = false
	elif not _far and dist > FAR_DIST + FAR_HYST: want = true
	if want != _far:
		_far = want
		_mat.set_shader_parameter("snap", 2.0 if _far else 1.0)

## The hand nearest the paddle holds it (grip). The other hand is open, a fist while swinging,
## and reaches when the arm is nearly fully extended.
func _hand_row(c: Dictionary, a: Vector3) -> int:
	var arm = c.arm
	var state: int = HAND_OPEN
	if arm == _paddle_arm and _paddle_arm != null:
		state = HAND_GRIP
	else:
		var reach_len: float = float(arm.get("upper_arm_length")) + float(arm.get("forearm_length"))
		var ext: float = (a - _xf(c.root).origin).length() / maxf(reach_len, 0.01)
		var was: bool = int(c.hand_state) == HAND_REACH
		if ext > (REACH_OFF if was else REACH_ON): state = HAND_REACH
		elif _swing_active: state = HAND_GRIP
	c.hand_state = state
	if state == HAND_OPEN: return int(c.row)
	return _base_rows + state - 1

func _update_paddle_arm() -> void:
	_paddle_arm = null
	var paddle: Node3D = _player.get("paddle_node")
	if paddle == null or not is_instance_valid(paddle): return
	var p: Vector3 = _xf(paddle).origin
	var best: float = INF
	for c in _cards:
		if c.part != "hand": continue
		var d: float = _xf(c.a).origin.distance_squared_to(p)
		if d < best:
			best = d
			_paddle_arm = c.arm

func _process(delta: float) -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_player.body_pivot):
		queue_free()
		return
	var cam: = get_viewport().get_camera_3d()
	if cam == null or _cards.is_empty() or _amesh == null: return
	# Follow the player's visibility, and hide our own body in first-person view.
	var head_pos: Vector3 = _player.body_pivot.global_position + Vector3.UP * 1.5
	visible = _player.is_visible_in_tree() and cam.global_position.distance_to(head_pos) > 0.6
	if not visible: return
	if cam != _culled_cam:
		cam.set_cull_mask_value(CLASSIC_LAYER, false)
		_culled_cam = cam
	# New body meshes are hidden as they enter the tree (_on_node_added); this slow
	# sweep only catches layer changes made by other code.
	_hide_timer -= delta
	if _hide_timer <= 0.0:
		_hide_timer = 2.0
		_hide_classic()
	_mesh_inst.visible = show_cards
	var meta: = _grid
	var s: float = float(meta.meters_per_texel)
	var cell: Vector2 = Vector2(meta.cell[0], meta.cell[1])
	var cols: int = int(meta.cols)
	# Physics runs at 30 Hz with interpolation: read the rendered (interpolated)
	# transforms, not the last physics tick, or the cards step at 30 Hz.
	var cam_pos: = cam.get_global_transform_interpolated().origin
	# Pose editors (desktop and mobile) pause physics and pose the skeleton directly,
	# so interpolated transforms hold the last physics tick; read the live ones there.
	_raw = get_tree().paused or (_player.posture != null and _player.posture.editor_preview_mode)
	var body_cell: int = _cell_for("body", _player.body_pivot, cam_pos)
	var torso_node: Node3D = _player.body_pivot.get_node_or_null("TorsoMesh")
	var torso_cell: int = _cell_for("torso", torso_node, cam_pos) if torso_node else body_cell
	var head_node: Node3D = torso_node.get_node_or_null("HeadMesh") if torso_node else null
	var head_cell: int = _cell_for("head", head_node, cam_pos) if head_node else torso_cell
	var torso_pos: Vector3 = _xf(torso_node if torso_node else _player.body_pivot).origin
	_update_far(cam_pos.distance_to(torso_pos))
	var squash: float = _squash(delta)
	_update_paddle_arm()
	var want_dbg: bool = show_bones or show_axes
	if want_dbg:
		_dbg_pts.clear()
		_dbg_cols.clear()
	var tex_w: float = _atlas_px.x
	var tex_h: float = _atlas_px.y
	var i: int = 0
	for c in _cards:
		var a: Vector3 = _pos(c.a)
		var b: Vector3
		if c.limb: b = _pos(c.b)
		elif c.prev != null: b = a + (a - _pos(c.prev)).normalized() * 0.06
		else: b = a
		var mid: Vector3 = (a + b) * 0.5
		var z: Vector3 = (cam_pos - mid).normalized()
		var up_dir: Vector3
		var sy: float = s
		if c.limb or c.prev != null:
			var d: Vector3 = b - a
			var dp: Vector3 = d - z * d.dot(z)
			var texel_len: float = maxf(c.end.y - c.anchor.y, 1.0) if c.limb else 1.2
			if dp.length() < 0.0001: dp = -(Vector3.UP - z * z.y)
			up_dir = -dp.normalized()
			if c.limb: sy = dp.length() / texel_len
		else:
			var up_hint: Vector3 = _xf(c.a).basis.y if c.facing != "body" else Vector3.UP
			up_dir = (up_hint - z * up_hint.dot(z)).normalized()
		var x: Vector3 = up_dir.cross(z).normalized()
		var k: int = head_cell if c.facing == "head" else (torso_cell if c.facing == "torso" else body_cell)
		if c.mirror:
			x = -x
			k = (cols - k) % cols
		var anchor: Vector2 = c.anchor
		var origin_a: Vector3 = a + z * (mid - a).dot(z)
		# Draw order by camera side: the limb chain nearer the camera than the torso draws in
		# front of it, the far one behind (small metre bias along the view ray, eased).
		var bias: float = float(PART_BIAS.get(c.part, 0.0))
		if c.side != 0:
			bias *= clampf((_xf(c.root).origin - torso_pos).dot(z) / BIAS_BLEND, -1.0, 1.0)
		origin_a += z * bias
		var lsc: float = 1.0
		var wsc: float = 1.0
		if c.limb: lsc = LIMB_OVERLAP   # joint seams: run past the joint into the next card
		if c.part != "hand":
			lsc *= 1.0 + squash
			wsc = 1.0 - 0.7 * squash
		var xs: float = s * wsc
		var ys: float = sy * lsc
		var x0: float = -anchor.x * xs
		var x1: float = (cell.x - anchor.x) * xs
		var y0: float = -anchor.y * ys
		var y1: float = (cell.y - anchor.y) * ys
		var row: int = _hand_row(c, a) if c.part == "hand" else int(c.row)
		var v: int = i * 4
		_verts[v] = origin_a + x * x0 - up_dir * y0
		_verts[v + 1] = origin_a + x * x1 - up_dir * y0
		_verts[v + 2] = origin_a + x * x1 - up_dir * y1
		_verts[v + 3] = origin_a + x * x0 - up_dir * y1
		var u0: float = float(k) * cell.x / tex_w
		var u1: float = (float(k) + 1.0) * cell.x / tex_w
		var v0: float = float(row) * cell.y / tex_h
		var v1: float = (float(row) + 1.0) * cell.y / tex_h
		_uvs[v] = Vector2(u0, v0)
		_uvs[v + 1] = Vector2(u1, v0)
		_uvs[v + 2] = Vector2(u1, v1)
		_uvs[v + 3] = Vector2(u0, v1)
		i += 1
		if want_dbg: _debug_lines(c, a, b, origin_a, x, up_dir, z)
	_amesh.surface_update_vertex_region(0, 0, _verts.to_byte_array())
	_amesh.surface_update_attribute_region(0, 0, _uvs.to_byte_array())
	_draw_debug(want_dbg)

## Bones: joint segments; axes: each card's x (red), up (green) and view (blue) vectors.
func _debug_lines(c: Dictionary, a: Vector3, b: Vector3, origin: Vector3, x: Vector3, up_dir: Vector3, z: Vector3) -> void:
	if show_bones:
		if c.limb:
			_dbg_pts.append(a); _dbg_pts.append(b)
		else:
			_dbg_pts.append(a); _dbg_pts.append(a + Vector3.UP * 0.04)
		_dbg_cols.append(Color.YELLOW); _dbg_cols.append(Color.YELLOW)
	if show_axes:
		for pair in [[x, Color.RED], [up_dir, Color.GREEN], [z, Color.BLUE]]:
			_dbg_pts.append(origin); _dbg_pts.append(origin + pair[0] * 0.08)
			_dbg_cols.append(pair[1]); _dbg_cols.append(pair[1])

func _draw_debug(on: bool) -> void:
	if not on:
		if _dbg_inst != null: _dbg_inst.visible = false
		return
	if _dbg_inst == null:
		_dbg_mesh = ImmediateMesh.new()
		_dbg_inst = MeshInstance3D.new()
		_dbg_inst.name = "CardDebug"
		_dbg_inst.mesh = _dbg_mesh
		_dbg_inst.top_level = true
		_dbg_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_dbg_inst.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_dbg_inst.custom_aabb = AABB(Vector3(-60, -5, -60), Vector3(120, 20, 120))
		var m: = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.no_depth_test = true
		_dbg_inst.material_override = m
		add_child(_dbg_inst)
	_dbg_inst.visible = true
	_dbg_mesh.clear_surfaces()
	if _dbg_pts.is_empty(): return
	_dbg_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for j in range(_dbg_pts.size()):
		_dbg_mesh.surface_set_color(_dbg_cols[j])
		_dbg_mesh.surface_add_vertex(_dbg_pts[j])
	_dbg_mesh.surface_end()

func _cell_for(key: String, node: Node3D, cam_pos: Vector3) -> int:
	var fwd: Vector3 = node.global_basis * _player._get_forward_axis()
	fwd.y = 0.0
	var to_cam: Vector3 = cam_pos - node.global_position
	to_cam.y = 0.0
	if fwd.length() < 0.001 or to_cam.length() < 0.001: return int(_cells.get(key, 0))
	var rel: float = rad_to_deg(to_cam.normalized().signed_angle_to(fwd.normalized(), Vector3.UP))
	var cur: int = int(_cells.get(key, -1))
	if cur >= 0:
		var diff: float = wrapf(rel - cur * CELL_DEG, -180.0, 180.0)
		if absf(diff) <= CELL_DEG * 0.5 + HYSTERESIS_DEG: return cur
	cur = posmod(roundi(rel / CELL_DEG), 16)
	_cells[key] = cur
	return cur

func _on_node_added(node: Node) -> void:
	if node is GeometryInstance3D and is_instance_valid(_player) and is_instance_valid(_player.body_pivot) \
			and _player.body_pivot.is_ancestor_of(node):
		_hide_timer = minf(_hide_timer, 0.0)  # sweep on the next frame

func _hide_classic() -> void:
	var paddle: Node = _player.get("paddle_node")
	for node in _player.body_pivot.find_children("*", "GeometryInstance3D", true, false):
		if node.has_meta("pixel_card"): continue
		if paddle != null and (node == paddle or paddle.is_ancestor_of(node)): continue
		if node.layers != 0:
			node.layers = 1 << (CLASSIC_LAYER - 1)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_drop_from_renderer(node)

## Take a hidden body mesh out of the renderer (no culling, no instance updates).
## Only the RenderingServer instance is switched off: `visible` and `layers` stay
## as they are, so gameplay filters (is_visible_in_tree, layers != 0) see no change.
## Godot re-enables the instance whenever the node's visibility changes, so the
## node's visibility_changed signal switches it off again.
## PICKLEBALL_CLASSIC_IN_RENDERER=1 keeps the old layer-only hide (perf A/B).
static var _keep_in_renderer: int = -1

func _drop_from_renderer(node: GeometryInstance3D) -> void:
	if _keep_in_renderer < 0:
		_keep_in_renderer = 1 if OS.get_environment("PICKLEBALL_CLASSIC_IN_RENDERER") == "1" else 0
	if _keep_in_renderer == 1: return
	RenderingServer.instance_set_visible(node.get_instance(), false)
	var cb: = _redrop.bind(node)
	if not node.visibility_changed.is_connected(cb):
		node.visibility_changed.connect(cb)

func _redrop(node: GeometryInstance3D) -> void:
	if is_instance_valid(node): RenderingServer.instance_set_visible(node.get_instance(), false)
