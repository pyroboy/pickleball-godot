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
## The only look (the classic 3D bodies were retired 2026-11-21): the meshes stay because
## gameplay still reads them (surface contacts, reach, the checker's torso test).
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
## - far tier: players across the net draw from their profile's far set (half the texel
##   density, match rows baked at the 20 degree angle the camera has on the far court; the
##   "far" entry in cards_meta.json, tools/bake_pixel_cards.py). One far texel is about one
##   pixel of the pixel viewport there, so far players stop dropping texels. The far grid is
##   the near grid at exactly half size, so only the material's textures change (_apply_set).
## - visual-only body motion (arm swing, shoulder counter-turn): CardMotionLayer deltas,
##   applied in _xf() after the interpolated read; the paddle skin reads paddle_delta()
## Debug: PICKLEBALL_CARD_DEBUG=nocards,bones,axes (comma list) or PixelCardRig.set_debug().

const ElbowSwivel = preload("res://scripts/elbow_swivel.gd")
const CardMotion = preload("res://scripts/graphics/card_motion_layer.gd")
const CLASSIC_LAYER: = 20                     # 1-based render layer hidden from the camera
const CELL_DEG: = 22.5
const HYSTERESIS_DEG: = 4.0
const META_PATH: = "res://assets/pixel_cards/cards_meta.json"
const TEXTURES: = ["res://assets/pixel_cards/cards_blue.png", "res://assets/pixel_cards/cards_red.png"]
const CARD_SHADER: = preload("res://shaders/pixel_card.gdshader")
const SOFT_SHADER: = preload("res://shaders/pixel_card_soft.gdshader")
const Sun = preload("res://scripts/graphics/sun_light.gd")
const GroundShadows = preload("res://scripts/fx/ground_shadows.gd")   # card_shadow next_pass + sun sync
const LUT_PATH: = "res://assets/pixel_cards/card_tonemap_lut.json"

const HAND_OPEN: = 0
const HAND_GRIP: = 1
const HAND_REACH: = 2
const HAND_CUP: = 3                   # holding the ball (baked row only; without it the grip hand is shown)
# Which hand drawing (tools/bake_pixel_cards.py hand_part):
#   grip  - a hand on the paddle: the paddle hand, and the support hand whenever it is on the
#           handle or throat (two-handed ready and backhands), and any hand in a swing;
#   cup   - a hand holding the ball (the ball within CUP_ON metres of it, not in play);
#   reach - a free arm at full stretch;
#   open  - otherwise: ready for the ball.
const CUP_ON: = 0.13
const CUP_OFF: = 0.18
const HOLD_GRIP_W: = 0.5              # card_motion_layer free weight below this = on the paddle
const REACH_HANG_Y: = -0.78           # arm direction (shoulder to hand) pointing down more than this = hanging
const CUP_AIM: = 0.75                 # how far the cupping hand turns from the forearm's line toward the ball
const EXTRA_ROWS: = 2                 # atlas rows appended at load: grip hand, reach hand
const REACH_ON: = 0.90                # arm extension (shoulder-hand / arm length) that shows the reach hand
const REACH_OFF: = 0.82
# Far tier by distance to the camera, measured against the net line at the player's own x
# (the camera sits lower and further back in portrait, so one fixed distance would split
# a team): far when this much beyond the net, near again when closer than FAR_EXIT.
const FAR_ENTER: = 1.2
const FAR_EXIT: = 0.2
const FAR_MIN_DIST: = 15.0            # never far closer than this (first-person and close cameras)
const LIMB_OVERLAP: = 1.04            # limb cards run 4% long so joints never open a gap
# A limb seen nearly end-on (your own thigh from above, an arm pointing at the camera) used to
# squash to a sliver. It is never drawn shorter than this share of its real length, centred on
# where it really is, so it reads as a foreshortened limb.
const LIMB_MIN_SHOWN: = 0.34
# ... and which way it points on screen is held while it is nearly end-on: that direction comes
# from a few millimetres of sideways offset there and spun round with every small move.
const LIMB_DIR_HOLD: = 0.10           # share of the limb's length seen sideways: below this the last direction is kept
const LIMB_DIR_FREE: = 0.28           # from here the real direction is used
# Limbs and hands seen along their length have their own drawings (tools/bake_pixel_cards.py
# LIMB_AXIAL / HAND_AXIAL: the part tilted toward the camera, from its root end or its far
# end). The one nearest to how end-on the limb really is gets drawn, so a foreshortened limb
# keeps square pixels and shows its end, not a side view squashed into a block.
const AXIAL_HYST_DEG: = 10.0          # a drawing is kept until another is this much nearer
const LIMB_AXIAL_MIN: = 0.7           # a tilted drawing is never drawn shorter than this share of its own length
# Other view heights of head / torso / shorts / shoe (tools/bake_pixel_cards.py VIEW_ELEV):
# "low" rows when the camera is about level with the part (first person looking at another
# player), "top" rows from nearly overhead (your own body when you look down, top cameras).
# The match camera (28-65 degrees up) stays on the normal rows.
const VIEW_LOW_ON: = 16.0             # degrees the camera is above the part
const VIEW_LOW_OFF: = 22.0
const VIEW_TOP_ON: = 73.0
const VIEW_TOP_OFF: = 67.0
const VIEW_TOP_ON_OWN: = 60.0          # first person, your own body: the from-above rows come in sooner and stay,
const VIEW_TOP_OFF_OWN: = 48.0         # so a step forward does not flip your shoe between two drawings
# First person: the eye is inside the body, so each of your own cards is turned for where the
# eye really is from that part (your chest is seen from the front, your shoes from behind and
# above), not one shared turn for the whole body as from a far camera. A part almost straight
# below the eye keeps its last turn (the direction there flips with every small head move).
const FIRST_PERSON_HOLD_M: = 0.08
# ... and your own torso is seen almost along its length, which a flat card cannot show: the
# card is drawn as tall as the torso really looks from the eye (the sine of the angle between
# the spine and the line of sight), relative to the height its art was drawn for. Without this
# the chest lay across the view like a cut-out and hid the legs and feet behind it.
const ART_ELEV_DEG: = {"head": 30.0, "torso": 40.0, "shorts": 44.0, "shoe": 44.0}   # tools/bake_pixel_cards.py PART_ELEV
const ART_LOW_DEG: = 8.0
const ART_TOP_DEG: = 78.0
const FIRST_PERSON_MIN_TALL: = 0.3
const PART_BIAS: = {"head": 0.02, "torso": 0.0, "shorts": -0.01, "upper_arm": 0.03, "forearm": 0.035,
	"hand": 0.04, "thigh": 0.012, "shin": 0.016, "shoe": 0.02}   # metres toward the camera (near side; negated far side)
const BIAS_BLEND: = 0.04              # metres of side offset over which near/far bias eases
const POP_AMOUNT: = 0.08
const ANTICIPATION_AMOUNT: = 0.04
const ACCENT_DISPLAY: = [Color(0.13, 0.78, 0.72), Color(0.97, 0.5, 0.06)]   # on-screen accent per team (blue -> teal, red -> orange)

# Debug toggles (off by default except cards). Env var or set_debug().
static var show_cards: bool = true
## First-person camera (gameplay_camera.gd FIRST_PERSON): this player's own cards stay drawn
## from inside the head (the user wants the pixel-card look there too), except the head and
## shorts. Visual only.
var first_person := false
const FIRST_PERSON_HIDDEN := ["head", "shorts"]
## A card this close to the eye would fill the screen as a flat sprite: it shrinks from
## FIRST_PERSON_NEAR_FADE m and is not drawn under FIRST_PERSON_NEAR_HIDE m.
const FIRST_PERSON_NEAR_HIDE := 0.28
const FIRST_PERSON_NEAR_FADE := 0.40
const FIRST_PERSON_LIMB_HIDE := 0.13       # a limb whose drawn part is centred closer than this is not drawn
const FIRST_PERSON_TOP_NEAR_HIDE := 0.14   # ... the from-above torso is meant to be seen close: it stays until here
const FIRST_PERSON_TOP_NEAR_FADE := 0.22
const FIRST_PERSON_UPPER_ARM_FROM := 0.55   # the upper arm is drawn from this far down toward the elbow: the shoulder end sits next to the eye and would fill the screen
## In first person the camera rides the DRAWN head (with the visual-only walk, lean and stance
## motion), not the gameplay head: set every frame before the cards are placed, then
## `on_drawn_head` lets the camera move there so the cards face this frame's eye.
var drawn_head_xf := Transform3D.IDENTITY
var drawn_body_basis := Basis.IDENTITY
var drawn_head_frame := -10
var on_drawn_head: Callable
## Where the first-person head points (world, level; ZERO for none). A big look turns the drawn
## chest, arms and hips with it (card_motion_layer.gd _look_turn). Visual only.
var look_dir := Vector3.ZERO
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
var _flash_left: float = 0.0   # real seconds of white hit flash left (flash_white)

var _mat: ShaderMaterial
var _soft_mat: ShaderMaterial   # the card again, alpha blended: the soft edges of motion blur (pixel_card_soft.gdshader)

const TICK_FAST_SQ := 0.03 * 0.03   # a card corner moved this far in a tick (0.9 m/s): motion blur can show. Under the shader's own threshold at any strength: the solid pass leaves blurred edges to the soft pass
var _soft_on: bool = false

## The soft pass is one more draw of the whole card mesh, so it is only chained on (after the
## ground shadow pass) for a player with a card moving fast enough to blur this tick.
func _set_soft_pass(on: bool) -> void:
	on = on and _smear_shown > 0.0
	if on == _soft_on or _shadow_mat == null: return
	_soft_on = on
	_chain_passes()

## The passes after the card: its ground shadow, the shadow's soft rim while the lens blur is
## on, the soft motion-blur edges while the player is moving fast.
func _chain_passes() -> void:
	if _shadow_mat == null: return
	var last: ShaderMaterial = _shadow_mat
	if _rim_on and _rim_mat != null:
		last.next_pass = _rim_mat
		last = _rim_mat
	last.next_pass = _soft_mat if _soft_on else null

const SHADOW_RIM_TEXELS := 2.5   # soft rim width at full lens blur, atlas texels
var _rim_mat: ShaderMaterial     # the shadow's soft rim (shaders/card_shadow_soft.gdshader)
var _rim_on: bool = false

## Player shadows are drawn after the lens blur (serve aim, slow motion), so they soften
## themselves: a rim pass is chained on while the lens is on, with the solid shadow's values.
func _update_shadow_rim() -> void:
	if _rim_mat == null or _shadow_mat == null: return
	var soften: float = GroundShadows.lens_soften
	# ... and a moving player's shadow gets the motion blur's trail from the same pass.
	var trail: float = maxf(_smear_shown, 0.0) if _soft_on else 0.0
	var on: bool = soften > 0.01 or trail > 0.0
	if on != _rim_on:
		_rim_on = on
		_chain_passes()
	if not on: return
	for param in ["light_dir", "has_mask", "shadow_mask", "mask_rect", "cast"]:
		_rim_mat.set_shader_parameter(param, _shadow_mat.get_shader_parameter(param))
	_rim_mat.set_shader_parameter("soften", soften * SHADOW_RIM_TEXELS if soften > 0.01 else 0.0)
	_rim_mat.set_shader_parameter("smear", trail)

## One value for both card passes (they run the same shader code).
func _card_param(param: StringName, value: Variant) -> void:
	_mat.set_shader_parameter(param, value)
	if _soft_mat != null: _soft_mat.set_shader_parameter(param, value)
var _shadow_mat: ShaderMaterial   # _mat.next_pass: this mesh again, flattened onto the court along the sun
var _sun_seen: = Vector2i(-1, -1)   # (Sun.version, ShadowMask.version) applied to the materials
var _shadow_cast: bool = true
var _mesh_inst: MeshInstance3D
var _amesh: ArrayMesh
var _verts: PackedVector3Array = PackedVector3Array()
var _uvs: PackedVector2Array = PackedVector2Array()
var _atlas_px: Vector2 = Vector2(640, 440)
var _base_rows: int = 9
var _far: bool = false
var _near_set: Dictionary = {}   # what _apply_set swaps: textures, atlas size, team luminance
var _far_set: Dictionary = {}    # empty when the profile has no usable far atlas (the near set is kept)
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
# PerfToggles.card_redraw_on_change: every input the quads are built from this frame (camera,
# drawn joints, squash, cells, ball), compared per card with what that card was last built
# from; a card that did not move keeps its quad, and with no card moved the upload is skipped.
const SIG_HEAD: = 4
const SIG_PER_CARD: = 5
const SIG_TOL_SQ: = 0.0014 * 0.0014   # metres: 1/20 of a card texel (0.028 m)
const CAM_TOL_SQ: = 0.01 * 0.01       # camera metres: at 5+ m that turns a card under 0.12 degrees
var _sig: PackedVector3Array = PackedVector3Array()
var _drawn_sig: PackedVector3Array = PackedVector3Array()
static var cards_skipped: int = 0   # probes: card quads kept (all rigs)
static var cards_drawn: int = 0     # probes: card quads rebuilt (all rigs)

static func attach(player) -> PixelCardRig:
	if player == null or player.body_pivot == null: return null
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
	if profile_id != "" and other_path != "" and meta.profiles[profile_id].has("far"):
		_build_far(meta.profiles[profile_id].far, team, meta)
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
	var extra: = func(suffix: String) -> int:
		return int(meta.parts[part + suffix].row) if meta.parts.has(part + suffix) else -1
	# Drawings of this part seen along its length: limbs [tilt deg, row, texels from joint to
	# joint]; hands, per hand row (open, grip, reach, cup), [tilt deg, row].
	var variants: Array = []
	var hand_variants: Dictionary = {}
	if info.has("end") and b != null:
		variants.append([0.0, int(info.row), maxf(float(info.end[1]) - float(info.anchor[1]), 1.0)])
		for key in meta.parts:
			var q: Dictionary = meta.parts[key]
			if q.has("axial") and str(q.get("of", "")) == part:
				variants.append([float(q.axial), int(q.row), maxf(float(q.end[1]) - float(q.anchor[1]), 1.0)])
	elif part == "hand":
		for key in meta.parts:
			var q: Dictionary = meta.parts[key]
			if not q.has("axial") or not meta.parts.has(str(q.get("of", ""))) or not str(q.of).begins_with("hand"): continue
			var base_row: int = int(meta.parts[str(q.of)].row)
			if not hand_variants.has(base_row): hand_variants[base_row] = [[0.0, base_row]]
			hand_variants[base_row].append([float(q.axial), int(q.row)])
	_cards.append({"part": part, "a": a, "b": b, "prev": prev, "mirror": mirror, "row": int(info.row),
		"low_row": extra.call("_low"), "top_row": extra.call("_top"), "view": 0,
		"variants": variants, "hand_variants": hand_variants, "axial": 0.0,
		"grip_row": extra.call("_grip"), "reach_row": extra.call("_reach"), "cup_row": extra.call("_cup"), "detail": float(info.get("detail", 1.0)),
		"root": root, "arm": arm, "side": 1 if root != null else 0, "hand_state": HAND_OPEN,
		"anchor": Vector2(info.anchor[0], info.anchor[1]), "end": Vector2(info.end[0], info.end[1]) if info.has("end") else Vector2.ZERO,
		"limb": info.has("end") and b != null, "facing": facing})

# ------------------------------------------------------------------ atlas + mesh

static var _atlas_cache: Dictionary = {}   # texture path -> {"tex": ImageTexture, "img": Image}
static var _lut: Dictionary = {}

## The team atlas plus two extra rows (grip hand, reach hand) painted from its own skin
## colour. Cached per texture path; the original atlas is copied unchanged above them.
static func _extended_atlas(path: String, grid: Dictionary, paint: bool = true) -> Dictionary:
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
	if paint: _paint_hands(out, grid, cols, rows, cell)
	elif grid.parts.has("hand"):
		# Far set: its texels are too coarse for the painted fallback hands; the extra rows
		# repeat the open hand so those rows still exist.
		var hand_row: = Rect2i(0, int(grid.parts.hand.row) * cell.y, cols * cell.x, cell.y)
		for extra in range(EXTRA_ROWS): out.blit_rect(src, hand_row, Vector2i(0, (rows + extra) * cell.y))
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
	_soft_mat = ShaderMaterial.new()
	_soft_mat.shader = SOFT_SHADER
	_card_param("atlas", own.tex)
	_atlas_px = Vector2(own.img.get_width(), own.img.get_height())
	_card_param("atlas_px", _atlas_px)
	_card_param("cell_uv", Vector2(float(meta.cell[0]) / _atlas_px.x, float(meta.cell[1]) / _atlas_px.y))
	_card_param("gain", float(meta.get("gain", 1.0)))
	_card_param("shading", 1.0)   # stepped golden-hour sun bands + sun-side rim
	_shadow_mat = GroundShadows.card_shadow_material(own.tex)
	_rim_mat = GroundShadows.card_shadow_material(own.tex, true)
	for shadow: ShaderMaterial in [_shadow_mat, _rim_mat]:
		shadow.set_shader_parameter("atlas_px", _atlas_px)
		shadow.set_shader_parameter("cell_uv", Vector2(float(meta.cell[0]) / _atlas_px.x, float(meta.cell[1]) / _atlas_px.y))
	_mat.next_pass = _shadow_mat
	_sun_seen = GroundShadows.sync_card_sun(_mat, _shadow_mat, _sun_seen)
	_has_other = other_path != ""
	if _has_other:
		var other: Dictionary = _extended_atlas(other_path, meta)
		_card_param("atlas_other", other.tex)
		_team_ref_lum = _team_reference_luminance(own.img, other.img, meta)
		_card_param("team_ref_lum", _team_ref_lum)
	else:
		_card_param("atlas_other", own.tex)
	_near_set = {"tex": own.tex, "other": _mat.get_shader_parameter("atlas_other"), "px": _atlas_px, "lum": _team_ref_lum}
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
	# CUSTOM0 (3 floats): each corner one physics tick ago, for the shader's blend (tick build).
	var previous: = PackedFloat32Array()
	previous.resize(n * 4 * 3)
	arrays[Mesh.ARRAY_CUSTOM0] = previous
	# CUSTOM1 (3 floats): each corner's eased motion per tick, for the motion blur.
	arrays[Mesh.ARRAY_CUSTOM1] = previous.duplicate()
	# CUSTOM2 (3 floats): the shadow's own corner, as an offset from the card's (true joint-to-joint shapes).
	arrays[Mesh.ARRAY_CUSTOM2] = previous.duplicate()
	_attr.resize(n * 4 * ATTR_STRIDE)
	_amesh = ArrayMesh.new()
	_amesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE | (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) | (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT))
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

## Draw every card white for a moment (visual only; rally_moments.gd on a PERFECT hit).
func flash_white(seconds: float) -> void:
	if _mat == null: return
	_flash_left = maxf(_flash_left, seconds)
	_card_param("flash", 0.85)

func _update_flash(delta: float) -> void:
	if _flash_left <= 0.0: return
	_flash_left -= delta / maxf(Engine.time_scale, 0.05)
	if _flash_left <= 0.0: _card_param("flash", 0.0)

func apply_accent(display_color: Color) -> void:
	if _mat == null or not _has_other: return
	_card_param("accent_color", _display_to_atlas(display_color))
	_card_param("accent_mix", 1.0)

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
## Bench only (PerfMonitor frame log): the joints as drawn this frame, keyed part + side
## (interpolated read + card motion), so tools measure what the eye sees, not the 30 Hz rig.
static var record_drawn: bool = false
var drawn: Dictionary = {}
var _motion = null   # CardMotionLayer: visual-only joint deltas for this frame
var _elbow_arm: Dictionary = {}   # forearm pivot (elbow) -> arm: the elbow is drawn at the authored swivel

## A joint's drawn position: the node's, except an elbow turned to the pose's authored swivel
## (scripts/elbow_swivel.gd; the solved arm itself stays as gameplay uses it).
func _pos(n: Node3D) -> Vector3:
	var p: Vector3 = _xf(n).origin
	var arm = _elbow_arm.get(n)
	if arm == null or not arm.has_meta(ElbowSwivel.VISUAL_TURN_META): return p
	var fore: Transform3D = _xf(n)
	var wrist_end: Vector3 = fore * Vector3(0.0, 0.0, -float(arm.forearm_length) * float(arm.visual_stretch))
	return ElbowSwivel.visual_elbow(arm, _xf(arm.upper_pivot).origin, p, wrist_end, -1.0 if (_raw or _tick_read) else Engine.get_physics_interpolation_fraction())

func _xf(n: Node3D) -> Transform3D:
	var xf: Transform3D = n.global_transform if (_raw or _tick_read) else n.get_global_transform_interpolated()
	if _motion != null and _motion.has_motion(): return _motion.apply(n, xf)
	return xf

## Visual-only paddle spin about its shaft this frame, radians (reactions; the paddle skin applies it).
func paddle_spin() -> float:
	if _motion == null or not visible: return 0.0
	if _tick_mode: return lerpf(_spin_before, _spin_now, minf(_blend_shown, 1.0))
	return _motion.paddle_spin()

## The shown paddle hand's visual-only delta this frame (the paddle skin applies it).
func paddle_delta() -> Transform3D:
	if _motion == null or not visible: return Transform3D.IDENTITY
	if _tick_mode:
		# Blended like the cards, so the shown paddle stays in the shown hand between ticks.
		if _paddle_before.is_equal_approx(_paddle_now): return _paddle_now
		return _paddle_before.interpolate_with(_paddle_now, minf(_blend_shown, 1.0))
	return _motion.paddle_delta(_paddle_arm)

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
	# Implicit spring step: stable at any frame time. The explicit step blew up past
	# ~0.04 s frames (hit spikes) and stretched the cards across the screen.
	_pop_v = (_pop_v - 900.0 * _pop * d) / (1.0 + 36.0 * d + 900.0 * d * d)
	_pop += _pop_v * d
	_pop = clampf(_pop, -POP_AMOUNT, POP_AMOUNT)
	return clampf(_pop - ANTICIPATION_AMOUNT * _ant, -0.15, 0.15)

## The far set is used only when its grid is the near grid at exactly half size (same rows,
## half the cell, anchors and ends, twice the metres per texel): the card quads and UVs then
## stay as they are and only the textures change.
func _build_far(far: Dictionary, team: int, near: Dictionary) -> void:
	var paths: Array = [str(far.textures.get(["blue", "red"][team], "")), str(far.textures.get(["blue", "red"][1 - team], ""))]
	if not (ResourceLoader.exists(paths[0]) and ResourceLoader.exists(paths[1])): return
	var grid: Dictionary = near.duplicate()
	grid.merge(far.grid, true)
	if int(grid.rows) != int(near.rows) or int(grid.cols) != int(near.cols) or int(grid.cell[0]) * 2 != int(near.cell[0]) \
			or int(grid.cell[1]) * 2 != int(near.cell[1]) or not is_equal_approx(float(grid.meters_per_texel), 2.0 * float(near.meters_per_texel)): return
	for part in near.parts:
		if not grid.parts.has(part): return
		var a: Dictionary = near.parts[part]
		var b: Dictionary = grid.parts[part]
		if int(a.row) != int(b.row) or not Vector2(a.anchor[0], a.anchor[1]).is_equal_approx(2.0 * Vector2(b.anchor[0], b.anchor[1])): return
		if a.has("end") and not Vector2(a.end[0], a.end[1]).is_equal_approx(2.0 * Vector2(b.end[0], b.end[1])): return
	var own: Dictionary = _extended_atlas(paths[0], grid, false)
	var other: Dictionary = _extended_atlas(paths[1], grid, false)
	_far_set = {"tex": own.tex, "other": other.tex, "px": Vector2(own.img.get_width(), own.img.get_height()),
		"lum": _team_reference_luminance(own.img, other.img, grid)}

func _apply_set(card_set: Dictionary) -> void:
	_card_param("atlas", card_set.tex)
	_card_param("atlas_other", card_set.other)
	_card_param("atlas_px", card_set.px)
	_card_param("team_ref_lum", float(card_set.lum))

func _update_far(dist: float, net_dist: float) -> void:
	if _far_set.is_empty(): return
	var want: bool = _far
	if _far_force >= 0: want = _far_force == 1
	elif _far and dist < maxf(net_dist + FAR_EXIT, FAR_MIN_DIST - 1.0): want = false
	elif not _far and dist > maxf(net_dist + FAR_ENTER, FAR_MIN_DIST): want = true
	if want != _far:
		_far = want
		_apply_set(_far_set if _far else _near_set)

## The hand nearest the paddle holds it (grip). The other hand is open, a fist while swinging,
## and reaches when the arm is nearly fully extended.
func _hand_row(c: Dictionary, a: Vector3) -> int:
	var arm = c.arm
	var state: int = HAND_OPEN
	var was: int = int(c.hand_state)
	var on_paddle: bool = (arm == _paddle_arm and _paddle_arm != null) or (_motion != null and _motion._free_w(arm) < HOLD_GRIP_W)
	if on_paddle:
		state = HAND_GRIP
	else:
		var ball = _player._get_ball_ref() if _player.has_method("_get_ball_ref") else null
		var holding: bool = false
		if ball != null and is_instance_valid(ball) and not bool(ball.get("is_in_play")):
			holding = a.distance_to(_xf(ball).origin) < (CUP_OFF if was == HAND_CUP else CUP_ON)
		if holding:
			state = HAND_CUP
		else:
			var reach_len: float = float(arm.get("upper_arm_length")) + float(arm.get("forearm_length"))
			var along: Vector3 = a - _xf(c.root).origin
			var ext: float = along.length() / maxf(reach_len, 0.01)
			# A straight arm hanging at the side is relaxed, not reaching: the spread hand is
			# only for an arm stretched out (not pointing down).
			var hanging: bool = along.normalized().y < REACH_HANG_Y
			if ext > (REACH_OFF if was == HAND_REACH else REACH_ON) and not hanging: state = HAND_REACH
			elif _swing_active: state = HAND_GRIP
	c.hand_state = state
	if state == HAND_OPEN: return int(c.row)
	# Baked hand rows (fingers, tools/bake_pixel_cards.py) when the atlas has them; else the
	# two rows painted at load (grip, reach), with the grip standing in for the cup.
	var baked: int = int(c.grip_row) if state == HAND_GRIP else (int(c.reach_row) if state == HAND_REACH else int(c.cup_row))
	if baked >= 0: return baked
	return _base_rows + (HAND_GRIP if state == HAND_CUP else state) - 1

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

## Tick build (PerfToggles.card_tick_build). The cards were rebuilt on every drawn frame from
## interpolated joints: 4 players x 60-120 frames a second, the largest script cost in the game
## (about 1 ms a frame on the phone). The joints only change on a physics tick, so the cards
## are now built once per tick from the tick's own joints, and each corner is stored with where
## it was one tick before (attribute CUSTOM0). The card and shadow shaders blend the two by the
## engine's interpolation fraction, the same fraction every other interpolated node is drawn
## with, so cards, paddle and ball stay in step. Frames between ticks only set that fraction.
## Not used in first person (the camera follows the drawn head every frame), while paused or in
## a pose editor (no ticks), with debug lines, or when a tool records drawn positions.
##
## Build off the tick's frame (PerfToggles.card_build_off_tick). The frame a physics tick runs
## in is the game's heaviest (the phone: about 25 ms against 8 ms for the frames between), so
## the build waits for the next frame. The tick's own frame is drawn by carrying the last
## tick's motion on (blend 1 + fraction). That is exact when the frame starts on the tick
## (fraction 0, the steady case on a 60 or 120 Hz screen) and drifts with the fraction: a
## running leg is off by about half a card texel at fraction 0.2, so the build only waits up
## to TICK_WAIT_MAX_F and is done at once past it. When no frame comes between two ticks (30 fps or less) there is
## nothing to wait for, and the build goes back to the tick's frame for TICK_WAIT_OFF builds
## (after two such ticks within two seconds: one alone is a hitch).
const TICK_WAIT_OFF := 300
const TICK_WAIT_MAX_F := 0.12           # the build only waits when the tick's frame starts this early in the tick
const TICK_WAIT_OFF_MAX := 3600
var _wait_span: int = TICK_WAIT_OFF
var _frame_tick: int = -1
var _wait_missed: int = -1000
var _waiting_tick: int = -1            # the tick whose build was left for the next frame
var _wait_off: int = 0                 # builds left before waiting is tried again
const ATTR_STRIDE := 11                # ... and the shadow's corner as an offset from the card's (x, y, z)
const SHADOW_WIDEN := 1.15              # the shadow's width over the art's (native/src/pickle_cards.cpp)
const VEL_FOLLOW := 0.55               # share of the way the blur's motion moves to this tick's each tick
var _vel_last_a := PackedVector3Array()   # motion blur: each card's joints one tick ago, and their eased motion per tick
var _vel_last_b := PackedVector3Array()
var _vel_a := PackedVector3Array()
var _vel_b := PackedVector3Array()
var _vel_have: bool = false
const TICK_JUMP_SQ := 1.5 * 1.5        # a corner that moved further than this in one tick teleported: no blend
var _attr := PackedFloat32Array()
var _built_tick: int = -1
var _tick_read: bool = false           # joints read as the tick left them (not interpolated)
var _tick_mode: bool = false
var _blend_shown: float = -1.0
var _tick_moving: bool = false         # the last tick build moved something: one more upload settles it
const TICK_TURN_MIN := 0.3             # a card whose side or length axis turned past this cosine in one tick flipped: no blend
var _paddle_before := Transform3D.IDENTITY   # the paddle hand's visual delta one tick ago and now
var _paddle_now := Transform3D.IDENTITY
var _spin_before: float = 0.0
var _spin_now: float = 0.0
var _redrawn := PackedByteArray()       # per card: this build changed its drawing (other atlas cell)

var _native = null                     # PickleCards (native/src/pickle_cards.cpp), one per rig
var _native_tried: bool = false
var _native_stale: bool = true         # the script loop built last: the native builder rebuilds every card
var _script_stale: bool = false        # ... and the other way round
var _native_params := PackedFloat64Array()
var _native_hands := PackedInt32Array()
var _hand_cards := PackedInt32Array()  # indices of the hand cards (their drawing is picked in script)
var _native_joints: bool = false       # the native builder also reads the joints
var _native_extras := PackedVector3Array()
var _elbow_slots: Array = []           # forearm pivots whose drawn elbow may differ from the joint (arm slot = index)
var _no_cards: Array = []

## The native card builder for this rig, or null (no library in this build, or the
## `native_math` switch is off): the script loop in _draw_cards is then used.
func _native_cards():
	if NativeMath.lib() == null: return null
	if _native_tried: return _native
	_native_tried = true
	if not ClassDB.class_exists(&"PickleCards") or _cards.size() > 62: return null
	var statics := PackedFloat64Array()
	var variants := PackedFloat64Array()
	_hand_cards.clear()
	for index in _cards.size():
		var c: Dictionary = _cards[index]
		var first: int = variants.size() / 3
		if c.limb:
			for v in c.variants: variants.append_array([float(v[0]), float(v[1]), float(v[2])])
		elif c.part == "hand":
			_hand_cards.append(index)
			for base_row in c.hand_variants:
				for v in c.hand_variants[base_row]: variants.append_array([float(base_row), float(v[0]), float(v[1])])
		statics.append_array([1.0 if c.limb else 0.0, 1.0 if c.prev != null else 0.0, 1.0 if c.part == "hand" else 0.0,
			1.0 if c.mirror else 0.0, 2.0 if c.facing == "head" else (1.0 if c.facing == "torso" else 0.0), float(c.side),
			c.anchor.x, c.anchor.y, c.end.y, float(c.detail), float(c.row), float(c.low_row), float(c.top_row),
			float(PART_BIAS.get(c.part, 0.0)), float(first), float(variants.size() / 3 - first)])
	_native_params.resize(23)
	_native_hands.resize(_cards.size())
	_native_hands.fill(-1)
	_native = ClassDB.instantiate(&"PickleCards")
	_native.setup(statics, variants)
	# Joint reads: the distinct joints, and per card which ones it reads.
	var joints: Array = []
	var reads := PackedInt32Array()
	var joint_index: = func(n) -> int:
		if n == null: return -1
		var at: int = joints.find(n)
		if at < 0:
			joints.append(n)
			at = joints.size() - 1
		return at
	_elbow_slots = _elbow_arm.keys()
	for index in _cards.size():
		var c: Dictionary = _cards[index]
		var other = c.b if c.limb else c.prev
		var up_mode: int = 3 if c.part == "hand" else ((1 if c.facing != "body" else 2) if (not c.limb and c.prev == null) else 0)
		reads.append_array([joint_index.call(c.a), joint_index.call(other), joint_index.call(c.root), up_mode,
			_elbow_slots.find(c.a), _elbow_slots.find(other) if other != null else -1, _hand_cards.find(index)])
	_native_joints = _elbow_slots.size() <= 2 and _hand_cards.size() <= 3
	if _native_joints:
		_native_extras.resize(9)
		_native.setup_joints(joints, reads)
	return _native

func _fill_native_params(cam_pos: Vector3, torso_pos: Vector3, ball_pos: Vector3, s: float, cell: Vector2, cols: int, tex_w: float, tex_h: float, squash: float, body_cell: int, torso_cell: int, head_cell: int, ball_ok: bool) -> void:
	_native_params[0] = cam_pos.x; _native_params[1] = cam_pos.y; _native_params[2] = cam_pos.z
	_native_params[3] = torso_pos.x; _native_params[4] = torso_pos.y; _native_params[5] = torso_pos.z
	_native_params[6] = ball_pos.x; _native_params[7] = ball_pos.y; _native_params[8] = ball_pos.z
	_native_params[9] = s; _native_params[10] = cell.x; _native_params[11] = cell.y; _native_params[12] = cols
	_native_params[13] = tex_w; _native_params[14] = tex_h; _native_params[15] = squash
	_native_params[16] = body_cell; _native_params[17] = torso_cell; _native_params[18] = head_cell
	_native_params[19] = 1.0 if ball_ok else 0.0
	var light: Vector3 = -Sun.to_sun()
	_native_params[20] = light.x; _native_params[21] = light.y; _native_params[22] = light.z

const SMEAR_KEY := "video.motion_smear"   # 0 off .. 1: trail length as a share of one tick's motion (pixel_card.gdshader)
var _smear_setting: float = 1.0
var _smear_shown: float = -1.0
var photo_tick: bool = false     # photo history is drawing a past tick: build it as a tick
var _blur_frozen: bool = false   # paused with blur on: the blur state is kept as it was
var _shading_on: bool = true   # Settings video.player_shading: the sun bands and rim on this player's cards

func _set_tick_blend(blend: float) -> void:
	if is_equal_approx(blend, _blend_shown): return
	_blend_shown = blend
	_card_param("tick_blend", blend)
	_shadow_mat.set_shader_parameter("tick_blend", blend)
	if _rim_mat != null: _rim_mat.set_shader_parameter("tick_blend", blend)

func _process(delta: float) -> void:
	var _rt: = Time.get_ticks_usec()
	_draw_cards(delta)
	var spent: int = Time.get_ticks_usec() - _rt
	PerfMonitor.record("card.rig", spent)   # the whole rig for this player, card.motion included
	var tick_now: int = Engine.get_physics_frames()
	if tick_now != _frame_tick:
		_frame_tick = tick_now
		PerfMonitor.record("card.on_tick", spent)   # the share that lands on a frame with a physics tick (the heavy frames)

func _draw_cards(delta: float) -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_player.body_pivot):
		queue_free()
		return
	var cam: = get_viewport().get_camera_3d()
	if cam == null or _cards.is_empty() or _amesh == null: return
	# Follow the player's visibility, and hide our own body in first-person view.
	var head_pos: Vector3 = _player.body_pivot.global_position + Vector3.UP * 1.5
	visible = _player.is_visible_in_tree() and (first_person or cam.global_position.distance_to(head_pos) > 0.6)
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
		_smear_setting = float(Settings.get_value(SMEAR_KEY, 1.0)) if bool(Settings.get_value("video.blur_body", true)) else 0.0
		var shaded: bool = bool(Settings.get_value("video.player_shading", true))
		if shaded != _shading_on:
			_shading_on = shaded
			_card_param("shading", 1.0 if shaded else 0.0)
	_mesh_inst.visible = show_cards
	var sun_before: Vector2i = _sun_seen
	_sun_seen = GroundShadows.sync_card_sun(_mat, _shadow_mat, _sun_seen)
	if _sun_seen.x != sun_before.x:   # the shadow shapes face the sun: rebuild every card
		_native_stale = true
		_script_stale = true
	# First person hides your own head and hips near the eye: a headless shadow would read
	# wrong, so your own shadow is off there (everyone else's stays).
	if _shadow_cast == first_person:
		_shadow_cast = not first_person
		_shadow_mat.set_shader_parameter("cast", 1.0 if _shadow_cast else 0.0)
	_update_shadow_rim()
	_update_flash(delta)
	_tick_mode = PerfToggles.card_tick_build and not first_person and not record_drawn and not (show_bones or show_axes) \
		and not get_tree().paused and not (_player.posture != null and _player.posture.editor_preview_mode)
	# Photo history (scripts/fx/photo_history.gd) draws a past tick as a tick, so the cards get
	# that moment's motion for their blur.
	if photo_tick: _tick_mode = true
	_tick_read = _tick_mode
	# Motion smear needs the two tick corners, which only the tick build keeps current.
	# Paused (photo mode, the pause menu): the moment is frozen with its blur. The corners'
	# motion is still in the mesh from the last tick, so the blur strength, the soft pass and
	# the shadow trail are simply left as they were (the blur follows the photo camera, since
	# the shaders read the motion in view space every frame).
	_blur_frozen = get_tree().paused and not (_player.posture != null and _player.posture.editor_preview_mode) and _smear_shown > 0.0
	# Slow motion: the exposure is real time, so the blur shrinks with the slow-down.
	var smear: float = snappedf(_smear_setting * clampf(Engine.time_scale, 0.0, 1.0), 0.02) if _tick_mode else 0.0
	if _blur_frozen: smear = _smear_shown
	if smear != _smear_shown:
		_smear_shown = smear
		_card_param("smear", smear)
	if _tick_mode:
		var tick: int = Engine.get_physics_frames()
		if tick == _built_tick and not photo_tick:
			_set_tick_blend(Engine.get_physics_interpolation_fraction())
			return
		var into_tick: float = Engine.get_physics_interpolation_fraction()
		if PerfToggles.card_build_off_tick and _built_tick == tick - 1 and _waiting_tick != tick and _wait_off <= 0 and into_tick <= TICK_WAIT_MAX_F and not photo_tick:
			_waiting_tick = tick
			_set_tick_blend(1.0 + into_tick)
			return
		if _waiting_tick == tick - 1:
			# The next tick came with no frame between. Once is a hitch; twice within two seconds
			# is a frame rate with no frames between ticks.
			if tick - _wait_missed < 60:
				_wait_off = _wait_span
				_wait_span = mini(_wait_span * 2, TICK_WAIT_OFF_MAX)   # each failed retry waits twice as long
			_wait_missed = tick
		elif _wait_off > 0: _wait_off -= 1
		_waiting_tick = -1
		# The visual-only motion steps by game time per tick, not by the uneven time between the
		# frames that happened to build (which made its speed waver).
		delta = float(clampi(tick - _built_tick, 1, 4) if _built_tick >= 0 else 1) / float(Engine.physics_ticks_per_second)
		_built_tick = tick
	else:
		_built_tick = -1
	var old_verts: PackedVector3Array = _verts.duplicate() if _tick_mode else PackedVector3Array()
	if _tick_mode:
		if _redrawn.size() != _cards.size(): _redrawn.resize(_cards.size())
		_redrawn.fill(0)
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
	if _motion == null: _motion = CardMotion.new(self)
	_motion.clear()
	# Visual-only motion first, so facing cells and every joint read below include it.
	var squash: float = _squash(delta)
	_update_paddle_arm()
	var _mt: = Time.get_ticks_usec()
	_motion.update(delta, _swing_active, _paddle_arm)
	if first_person:
		var head_mesh: Node3D = _player.body_pivot.get_node_or_null("TorsoMesh/HeadMesh")
		if head_mesh != null:
			drawn_head_xf = _xf(head_mesh)
			drawn_body_basis = _xf(_player.body_pivot).basis
			drawn_head_frame = Engine.get_process_frames()
			if on_drawn_head.is_valid():
				on_drawn_head.call()
				cam_pos = cam.global_position
	if record_drawn: drawn["grip_slip"] = Vector3(_motion.grip_slip, _motion._stand_w, 0.0)   # bench: paddle off the hand before the reseat
	if record_drawn: drawn["flow"] = _motion.flow   # bench: split hop m, gravity drop m, diagonal turn deg
	if record_drawn: drawn["arm_state"] = _motion.arm_state(_paddle_arm)   # bench: paddle arm relax, free arm relax, why not relaxed
	PerfMonitor.record("card.motion", Time.get_ticks_usec() - _mt)
	var face_cam: Vector3 = cam_pos
	var body_cell: int = _cell_for("body", _player.body_pivot, face_cam)
	var torso_node: Node3D = _player.body_pivot.get_node_or_null("TorsoMesh")
	var torso_cell: int = _cell_for("torso", torso_node, face_cam) if torso_node else body_cell
	var head_node: Node3D = torso_node.get_node_or_null("HeadMesh") if torso_node else null
	var head_cell: int = _cell_for("head", head_node, face_cam) if head_node else torso_cell
	var torso_pos: Vector3 = _xf(torso_node if torso_node else _player.body_pivot).origin
	_update_far(cam_pos.distance_to(torso_pos), cam_pos.distance_to(Vector3(torso_pos.x, torso_pos.y, 0.0)))
	var want_dbg: bool = show_bones or show_axes
	if want_dbg:
		_dbg_pts.clear()
		_dbg_cols.clear()
	var tex_w: float = _atlas_px.x
	var tex_h: float = _atlas_px.y
	# Read every joint once (the quad loop below uses these), then skip the rebuild when
	# nothing it reads moved.
	var n_sig: int = SIG_HEAD + SIG_PER_CARD * _cards.size()
	if _sig.size() != n_sig: _sig.resize(n_sig)
	var ball = _player._get_ball_ref() if _player.has_method("_get_ball_ref") else null
	var ball_ok: bool = ball != null and is_instance_valid(ball)
	var ball_pos: Vector3 = _xf(ball).origin if ball_ok else Vector3.ZERO
	var pa_id: float = 0.0
	if _paddle_arm != null: pa_id = 1.0 if _paddle_arm == _player.get("right_arm_node") else 2.0
	var ball_held: bool = ball_ok and not bool(ball.get("is_in_play"))
	var native = _native_cards() if not (first_person or want_dbg or record_drawn) else null
	# The joint reads in C++ too (read_joints): each distinct joint once, with the motion
	# layer's deltas; the drawn elbows and the hands' free weights are handed over from here.
	var native_read: bool = false
	if native != null and _native_joints:
		_native_extras[0] = cam_pos
		_native_extras[1] = Vector3(squash, 1.0 if _swing_active else 0.0, pa_id)
		_native_extras[2] = Vector3(body_cell, torso_cell, head_cell)
		_native_extras[3] = Vector3(1.0 if ball_held else 0.0, 1.0 if first_person else 0.0, 1.0 if _far else 0.0)
		_native_extras[4] = torso_pos
		_native_extras[5] = ball_pos
		var read_flags: int = 4 if ball_held else 0
		for slot in _elbow_slots.size():
			var elbow_arm = _elbow_arm.get(_elbow_slots[slot])
			if elbow_arm != null and elbow_arm.has_meta(ElbowSwivel.VISUAL_TURN_META):
				_native_extras[6 + slot] = _pos(_elbow_slots[slot])
				read_flags |= 1 << slot
		var free: Vector3 = Vector3.ONE
		for slot in _hand_cards.size():
			var hand_arm = _cards[_hand_cards[slot]].arm
			if hand_arm != null: free[slot] = _motion._free_w(hand_arm)
		_native_extras[8] = free
		native_read = native.read_joints(_motion._deltas, _native_extras, read_flags, not (_raw or _tick_read))
	_sig[0] = cam_pos
	_sig[1] = Vector3(squash, 1.0 if _swing_active else 0.0, pa_id)
	_sig[2] = Vector3(body_cell, torso_cell, head_cell)
	_sig[3] = Vector3(1.0 if ball_held else 0.0, 1.0 if first_person else 0.0, 1.0 if _far else 0.0)
	var si: int = SIG_HEAD
	for c in (_no_cards if native_read else _cards):
		_sig[si] = _pos(c.a)
		if c.limb: _sig[si + 1] = _pos(c.b)
		elif c.prev != null: _sig[si + 1] = _pos(c.prev)
		else: _sig[si + 1] = Vector3.ZERO
		# The draw-order bias reads the root against the torso, so that difference is the input.
		_sig[si + 2] = (_xf(c.root).origin - torso_pos) if c.root != null else Vector3.ZERO
		if c.part == "hand": _sig[si + 3] = Vector3(_motion._free_w(c.arm) if c.arm != null else 1.0, 0.0, 0.0)
		elif not c.limb and c.prev == null: _sig[si + 3] = _xf(c.a).basis.y if c.facing != "body" else Vector3.UP
		else: _sig[si + 3] = Vector3.ZERO
		_sig[si + 4] = ball_pos if (ball_held and c.part == "hand") else Vector3.ZERO   # a hand holding the ball reads it
		si += SIG_PER_CARD
	# Every input is a point (metres, unit vectors, small integers). A card whose inputs all
	# moved less than SIG_TOL since it was last built keeps its quad; the camera (shared by
	# every card) may drift CAM_TOL before all are rebuilt. Both are far under a screen pixel.
	if native != null:
		# The quad build in C++ (native/src/pickle_cards.cpp): the same steps as the loop below.
		var force_all: bool = not PerfToggles.card_redraw_on_change or _raw or _native_stale
		var mask: int = native.prepare_read(force_all) if native_read else native.prepare(_sig, force_all)
		_native_stale = false
		_script_stale = true
		var cup_mask: int = 0
		for hi in _hand_cards:
			if mask & (1 << hi):
				var hand_card: Dictionary = _cards[hi]
				if int(hand_card.hand_state) == HAND_CUP: cup_mask |= 1 << hi
				_native_hands[hi] = _hand_row(hand_card, _pos(hand_card.a))
		_fill_native_params(cam_pos, torso_pos, ball_pos, s, cell, cols, tex_w, tex_h, squash, body_cell, torso_cell, head_cell, ball_ok)
		var result: int = native.build(_native_params, _native_hands, cup_mask, _tick_mode)
		cards_drawn += result & 255
		cards_skipped += _cards.size() - (result & 255)
		if not _blur_frozen or photo_tick: _set_soft_pass(_tick_mode and (result & 512) != 0)
		if _tick_mode:
			_paddle_before = _paddle_now
			_spin_before = _spin_now
			_paddle_now = _motion.paddle_delta(_paddle_arm)
			_spin_now = _motion.paddle_spin()
		if result & 256:
			_amesh.surface_update_vertex_region(0, 0, native.vertex_bytes())
			_amesh.surface_update_attribute_region(0, 0, native.attr_bytes())
		_set_tick_blend(Engine.get_physics_interpolation_fraction() if _tick_mode and not photo_tick else 1.0)
		_draw_debug(false)
		return
	_native_stale = true
	var sun_light: Vector3 = -Sun.to_sun()
	var all_cards: bool = not PerfToggles.card_redraw_on_change or first_person or want_dbg or _raw or _drawn_sig.size() != n_sig or _script_stale
	_script_stale = false
	if not all_cards:
		if _sig[0].distance_squared_to(_drawn_sig[0]) > CAM_TOL_SQ: all_cards = true
		else:
			for k in range(1, SIG_HEAD):
				if _sig[k].distance_squared_to(_drawn_sig[k]) > SIG_TOL_SQ:
					all_cards = true
					break
	if all_cards:
		_drawn_sig = _sig.duplicate() if _drawn_sig.size() != n_sig else _drawn_sig
		for k in SIG_HEAD: _drawn_sig[k] = _sig[k]
	var built: int = 0
	si = SIG_HEAD
	var i: int = 0
	for c in _cards:
		var a: Vector3 = _sig[si]
		var b_src: Vector3 = _sig[si + 1]
		var root_pos: Vector3 = _sig[si + 2] + torso_pos
		var up_read: Vector3 = _sig[si + 3]
		if not all_cards:
			var moved: bool = false
			for k in SIG_PER_CARD:
				if _sig[si + k].distance_squared_to(_drawn_sig[si + k]) > SIG_TOL_SQ:
					moved = true
					break
			if not moved:
				si += SIG_PER_CARD
				i += 1
				cards_skipped += 1
				continue
		for k in SIG_PER_CARD: _drawn_sig[si + k] = _sig[si + k]
		si += SIG_PER_CARD
		built += 1
		cards_drawn += 1
		if record_drawn: drawn["%s%d" % [c.part, 1 if c.mirror else 0]] = a
		if first_person and c.part in FIRST_PERSON_HIDDEN:
			# Collapsed to a point: nothing drawn, the vertex layout stays the same.
			var hidden_v: int = i * 4
			for corner in 4: _verts[hidden_v + corner] = a
			i += 1
			continue
		var b: Vector3
		if c.limb: b = b_src
		elif c.prev != null:
			var along: Vector3 = (a - b_src).normalized()
			# A hand cupping the ball points at the ball, so the ball sits in the palm and fingers
			# (on the forearm's line it sat on the wrist).
			if int(c.hand_state) == HAND_CUP:
				if ball_ok:
					var to_ball: Vector3 = ball_pos - a
					if to_ball.length() > 0.02 and to_ball.length() < CUP_OFF * 1.5: along = along.lerp(to_ball.normalized(), CUP_AIM).normalized()
			b = a + along * 0.06
		else: b = a
		# First person: only the elbow end of your upper arm is drawn (its shoulder end is beside
		# the eye). The drawing is cropped there, not squeezed into the part that is left.
		var crop: float = FIRST_PERSON_UPPER_ARM_FROM if (first_person and c.part == "upper_arm" and c.limb) else 0.0
		var mid: Vector3 = (a.lerp(b, crop) + b) * 0.5
		var z: Vector3 = (cam_pos - mid).normalized()
		var up_dir: Vector3
		var sy: float = s
		var limb_shift: Vector3 = Vector3.ZERO
		var true_scale: float = 1.0   # a limb's real length over the length its card shows
		var limb_row: int = -1
		var limb_texels: float = 0.0
		var tilt: float = 0.0
		if c.limb or c.prev != null:
			var d: Vector3 = b - a
			var dp: Vector3 = d - z * d.dot(z)
			var texel_len: float = maxf(c.end.y - c.anchor.y, 1.0) if c.limb else 1.2
			if dp.length() < 0.0001: dp = -(Vector3.UP - z * z.y)
			up_dir = -dp.normalized()
			# How end-on it is seen: + from its root end, - from its far end.
			tilt = rad_to_deg(asin(clampf(z.dot(-d.normalized()), -1.0, 1.0)))
			var side_share: float = dp.length() / maxf(d.length(), 0.001)
			var held = c.get("dir")
			if held is Vector3 and side_share < LIMB_DIR_FREE:
				var kept: Vector3 = Vector3(held) - z * Vector3(held).dot(z)   # last direction, laid in today's plane
				if kept.length_squared() > 1e-6:
					up_dir = kept.normalized().slerp(up_dir, smoothstep(LIMB_DIR_HOLD, LIMB_DIR_FREE, side_share)).normalized() if kept.normalized().dot(up_dir) > -0.999 else kept.normalized()
			c["dir"] = up_dir
			if c.limb:
				var pick: Array = _pick_axial(c, tilt)
				limb_row = int(pick[1])
				texel_len = float(pick[2])
				limb_texels = texel_len
				# Never shorter than a share of the drawing's own length, centred on where it is.
				var least: float = LIMB_MIN_SHOWN if is_zero_approx(float(pick[0])) else cos(deg_to_rad(absf(float(pick[0])))) * LIMB_AXIAL_MIN
				var shown: float = maxf(dp.length(), d.length() * least)
				sy = shown / texel_len
				true_scale = d.length() / maxf(shown, 0.0001)
				limb_shift = up_dir * (shown - dp.length()) * 0.5
		else:
			# Screen-up of the sprite: the part's own up (so a lean shows) while that is well
			# seen; from steep above or below it is the level direction away from the camera,
			# which is the same line on screen and does not vanish when you look straight down.
			var away: Vector3 = mid - face_cam
			away.y = 0.0
			var steep: float = smoothstep(0.55, 0.85, absf(z.y))
			var up_hint: Vector3 = up_read
			var plain: Vector3 = up_hint - z * up_hint.dot(z)
			var level: Vector3 = Vector3.ZERO
			if away.length_squared() > 1e-6:
				level = away.normalized() * signf(z.y)
				level = level - z * level.dot(z)
			var mixed: Vector3 = plain.normalized() * (1.0 - steep) + (level.normalized() if level.length_squared() > 1e-8 else plain.normalized()) * steep
			up_dir = (mixed if mixed.length_squared() > 1e-8 else plain).normalized()
		var x: Vector3 = up_dir.cross(z).normalized()
		var k: int = head_cell if c.facing == "head" else (torso_cell if c.facing == "torso" else body_cell)
		if first_person: k = _own_cell(c, head_node if c.facing == "head" else (torso_node if c.facing == "torso" else _player.body_pivot), mid, cam_pos)
		if c.mirror:
			x = -x
			k = (cols - k) % cols
		var anchor: Vector2 = c.anchor
		var origin_a: Vector3 = a + z * (mid - a).dot(z) + limb_shift
		# Draw order by camera side: the limb chain nearer the camera than the torso draws in
		# front of it, the far one behind (small metre bias along the view ray, eased).
		var bias: float = float(PART_BIAS.get(c.part, 0.0))
		if c.side != 0:
			bias *= clampf((root_pos - torso_pos).dot(z) / BIAS_BLEND, -1.0, 1.0)
		origin_a += z * bias
		var lsc: float = 1.0
		var wsc: float = 1.0
		if c.limb: lsc = LIMB_OVERLAP   # joint seams: run past the joint into the next card
		if c.part != "hand":
			lsc *= 1.0 + squash
			wsc = 1.0 - 0.7 * squash
		var xs: float = s * wsc / float(c.detail)
		var ys: float = sy * lsc / float(c.detail)
		# Which view height: low / normal / top, by how far above the part the camera is.
		var row: int = int(c.row)
		if limb_row >= 0: row = limb_row
		if c.part == "hand":
			row = _hand_row(c, a)
			var tilted = c.hand_variants.get(row)
			if tilted != null: row = _pick_hand_axial(c, tilted, tilt)
		elif int(c.low_row) >= 0 or int(c.top_row) >= 0:
			var elev: float = rad_to_deg(asin(clampf(z.y, -1.0, 1.0)))
			var view: int = int(c.view)
			if view > 0: view = 1 if elev > (VIEW_TOP_OFF_OWN if first_person else VIEW_TOP_OFF) else 0
			elif view < 0: view = -1 if elev < VIEW_LOW_OFF else 0
			if view == 0:
				if elev > (VIEW_TOP_ON_OWN if first_person else VIEW_TOP_ON) and int(c.top_row) >= 0: view = 1
				elif elev < VIEW_LOW_ON and int(c.low_row) >= 0: view = -1
			c.view = view
			if view > 0 and int(c.top_row) >= 0: row = int(c.top_row)
			elif view < 0 and int(c.low_row) >= 0: row = int(c.low_row)
		if first_person and not c.limb and c.prev == null:
			var art_deg: float = ART_TOP_DEG if int(c.view) > 0 else (ART_LOW_DEG if int(c.view) < 0 else float(ART_ELEV_DEG.get(c.part, 40.0)))
			var axis: Vector3 = (_xf(c.a).basis.y if c.facing != "body" else Vector3.UP).normalized()
			var seen: float = sqrt(maxf(0.0, 1.0 - pow(axis.dot(z), 2.0)))
			ys *= clampf(seen / cos(deg_to_rad(art_deg)), FIRST_PERSON_MIN_TALL, 1.0)
		if first_person:
			var from_above: bool = int(c.view) > 0
			var hide_at: float = FIRST_PERSON_TOP_NEAR_HIDE if from_above else FIRST_PERSON_NEAR_HIDE
			var fade_at: float = FIRST_PERSON_TOP_NEAR_FADE if from_above else FIRST_PERSON_NEAR_FADE
			var near: float = clampf((cam_pos.distance_to(mid) - hide_at) / (fade_at - hide_at), 0.0, 1.0)
			# Limbs are not shrunk: a card shrinks toward its own joint, which pulled the upper
			# arm and forearm apart at the elbow (two floating blocks). They are only dropped
			# when right at the eye.
			if c.limb: near = 1.0 if cam_pos.distance_to(mid) > FIRST_PERSON_LIMB_HIDE else 0.0
			xs *= near
			ys *= near
		var x0: float = -anchor.x * xs
		var x1: float = (cell.x - anchor.x) * xs
		var top_texel: float = anchor.y + crop * limb_texels if crop > 0.0 else 0.0
		var y0: float = (top_texel - anchor.y) * ys
		var y1: float = (cell.y - anchor.y) * ys
		var v: int = i * 4
		_verts[v] = origin_a + x * x0 - up_dir * y0
		_verts[v + 1] = origin_a + x * x1 - up_dir * y0
		_verts[v + 2] = origin_a + x * x1 - up_dir * y1
		_verts[v + 3] = origin_a + x * x0 - up_dir * y1
		var u0: float = float(k) * cell.x / tex_w
		var u1: float = (float(k) + 1.0) * cell.x / tex_w
		var v0: float = (float(row) * cell.y + top_texel) / tex_h
		var v1: float = (float(row) + 1.0) * cell.y / tex_h
		_uvs[v] = Vector2(u0, v0)
		_uvs[v + 1] = Vector2(u1, v0)
		_uvs[v + 2] = Vector2(u1, v1)
		_uvs[v + 3] = Vector2(u0, v1)
		var at: int = v * ATTR_STRIDE
		# Another drawing (facing cell, view row, limb tilt row) has its own size and anchor: its
		# corners are not the old drawing's corners moved, so this tick shows it as it is.
		if _tick_mode and (not is_equal_approx(_attr[at], u0) or not is_equal_approx(_attr[at + 1], v0) or not is_equal_approx(_attr[at + 2 * ATTR_STRIDE + 1], v1)): _redrawn[i] = 1
		_attr[at] = u0; _attr[at + 1] = v0
		_attr[at + ATTR_STRIDE] = u1; _attr[at + ATTR_STRIDE + 1] = v0
		_attr[at + 2 * ATTR_STRIDE] = u1; _attr[at + 2 * ATTR_STRIDE + 1] = v1
		_attr[at + 3 * ATTR_STRIDE] = u0; _attr[at + 3 * ATTR_STRIDE + 1] = v1
		# The shadow's own shape (the same steps as native/src/pickle_cards.cpp): independent of
		# the camera. From the part's real joint, along its real line, turned to face the sun,
		# SHADOW_WIDEN times the art's width; stored per corner as the offset from the card's corner.
		var cast_axis: Vector3
		if c.limb or c.prev != null:
			var run: Vector3 = b - a
			cast_axis = run.normalized() if run.length() > 1e-4 else -up_dir
		else:
			cast_axis = -up_read.normalized() if up_read.length_squared() > 1e-6 else Vector3.DOWN
		var cast_side: Vector3 = cast_axis.cross(sun_light)
		cast_side = cast_side.normalized() * SHADOW_WIDEN if cast_side.length_squared() > 1e-8 else x
		if cast_side.dot(x) < 0.0: cast_side = -cast_side
		var cast_y0: float = y0 * true_scale
		var cast_y1: float = y1 * true_scale
		var cast_corners: Array[Vector3] = [a + cast_side * x0 + cast_axis * cast_y0, a + cast_side * x1 + cast_axis * cast_y0, a + cast_side * x1 + cast_axis * cast_y1, a + cast_side * x0 + cast_axis * cast_y1]
		for corner in 4:
			var cast_offset: Vector3 = cast_corners[corner] - _verts[v + corner]
			var slot: int = at + corner * ATTR_STRIDE + 8
			_attr[slot] = cast_offset.x; _attr[slot + 1] = cast_offset.y; _attr[slot + 2] = cast_offset.z
		i += 1
		if want_dbg: _debug_lines(c, a, b, origin_a, x, up_dir, z)
	if _tick_mode:
		# Each corner's place one tick ago: what it was before this build (a card that was not
		# rebuilt did not move, so both are the same). A teleport does not slide across the court.
		var moved: bool = built > 0
		# Motion blur (the same steps as native/src/pickle_cards.cpp): each corner's motion this
		# tick from the card's own joints, eased over a few ticks.
		var fast: bool = false
		var vel_changed: bool = false
		var n_cards: int = _cards.size()
		if _vel_a.size() != n_cards:
			_vel_last_a.resize(n_cards); _vel_last_b.resize(n_cards); _vel_a.resize(n_cards); _vel_b.resize(n_cards)
			_vel_a.fill(Vector3.ZERO); _vel_b.fill(Vector3.ZERO)
			_vel_have = false
		for index in n_cards:
			var card: Dictionary = _cards[index]
			var joint: Vector3 = _sig[SIG_HEAD + index * SIG_PER_CARD]
			var far_joint: Vector3 = _sig[SIG_HEAD + index * SIG_PER_CARD + 1] if card.limb else joint
			var raw_a: Vector3 = Vector3.ZERO
			var raw_b: Vector3 = Vector3.ZERO
			if _vel_have:
				raw_a = joint - _vel_last_a[index]
				raw_b = far_joint - _vel_last_b[index]
				if raw_a.length_squared() > TICK_JUMP_SQ or raw_b.length_squared() > TICK_JUMP_SQ:
					raw_a = Vector3.ZERO
					raw_b = Vector3.ZERO
			_vel_last_a[index] = joint
			_vel_last_b[index] = far_joint
			var va: Vector3 = _vel_a[index].lerp(raw_a, VEL_FOLLOW)
			var vb: Vector3 = _vel_b[index].lerp(raw_b, VEL_FOLLOW)
			if va.length_squared() < 0.0005 * 0.0005: va = Vector3.ZERO
			if vb.length_squared() < 0.0005 * 0.0005: vb = Vector3.ZERO
			_vel_a[index] = va
			_vel_b[index] = vb
			if va.length_squared() > TICK_FAST_SQ or vb.length_squared() > TICK_FAST_SQ: fast = true
			var t0: float = 0.0
			var t1: float = 0.0
			if card.limb:
				var limb_len: float = maxf(card.end.y - card.anchor.y, 1.0)
				t0 = clampf(-card.anchor.y / limb_len, -0.5, 1.5)
				t1 = clampf((cell.y - card.anchor.y) / limb_len, -0.5, 1.5)
			var top: Vector3 = va + (vb - va) * t0
			var bottom: Vector3 = va + (vb - va) * t1
			for corner in 4:
				var motion: Vector3 = top if corner < 2 else bottom
				var slot: int = (index * 4 + corner) * ATTR_STRIDE
				if _attr[slot + 5] != motion.x or _attr[slot + 6] != motion.y or _attr[slot + 7] != motion.z:
					vel_changed = true
					_attr[slot + 5] = motion.x; _attr[slot + 6] = motion.y; _attr[slot + 7] = motion.z
		_vel_have = true
		_paddle_before = _paddle_now
		_spin_before = _spin_now
		_paddle_now = _motion.paddle_delta(_paddle_arm)
		_spin_now = _motion.paddle_spin()
		if moved or _tick_moving or vel_changed:
			for first in range(0, _verts.size(), 4):
				# Blending corners is only right for a card that moved or turned a little. One that
				# jumped (teleport), flipped (mirrored, turned end over end), changed drawing or was
				# hidden a tick ago is shown where it is now, as the per-frame build showed it.
				var now0: Vector3 = _verts[first]
				var was0: Vector3 = old_verts[first]
				var side_now: Vector3 = _verts[first + 1] - now0
				var side_was: Vector3 = old_verts[first + 1] - was0
				var tall_now: Vector3 = _verts[first + 3] - now0
				var tall_was: Vector3 = old_verts[first + 3] - was0
				var blend_ok: bool = _redrawn[first >> 2] == 0 and was0.distance_squared_to(now0) <= TICK_JUMP_SQ \
					and side_now.dot(side_was) > TICK_TURN_MIN * side_now.length() * side_was.length() \
					and tall_now.dot(tall_was) > TICK_TURN_MIN * tall_now.length() * tall_was.length()
				if blend_ok and (was0.distance_squared_to(now0) > TICK_FAST_SQ or old_verts[first + 1].distance_squared_to(_verts[first + 1]) > TICK_FAST_SQ or old_verts[first + 2].distance_squared_to(_verts[first + 2]) > TICK_FAST_SQ or old_verts[first + 3].distance_squared_to(_verts[first + 3]) > TICK_FAST_SQ): fast = true
				for corner in range(first, first + 4):
					var before: Vector3 = old_verts[corner] if blend_ok else _verts[corner]
					var at: int = corner * ATTR_STRIDE
					_attr[at + 2] = before.x; _attr[at + 3] = before.y; _attr[at + 4] = before.z
			_amesh.surface_update_vertex_region(0, 0, _verts.to_byte_array())
			_amesh.surface_update_attribute_region(0, 0, _attr.to_byte_array())
		_tick_moving = moved
		_set_soft_pass(fast)
		_set_tick_blend(1.0 if photo_tick else Engine.get_physics_interpolation_fraction())
	else:
		_vel_have = false
		if not _blur_frozen: _set_soft_pass(false)
		_set_tick_blend(1.0)
		if built > 0:
			_amesh.surface_update_vertex_region(0, 0, _verts.to_byte_array())
			_amesh.surface_update_attribute_region(0, 0, _attr.to_byte_array())
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
	var basis: Basis = node.global_basis
	if _motion != null and _motion.has_motion(): basis = _motion.apply(node, Transform3D(basis, Vector3.ZERO)).basis
	var fwd: Vector3 = basis * _player._get_forward_axis()
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

## The limb drawing for how end-on it is seen (tilt, degrees): [tilt, row, texels joint to joint].
func _pick_axial(c: Dictionary, tilt: float) -> Array:
	var variants: Array = c.variants
	if variants.is_empty(): return [0.0, int(c.row), maxf(c.end.y - c.anchor.y, 1.0)]
	var current: float = float(c.axial)
	var best: Array = variants[0]
	var best_off: float = INF
	var kept: Array = []
	for v in variants:
		var off: float = absf(tilt - float(v[0]))
		if off < best_off:
			best_off = off
			best = v
		if is_equal_approx(float(v[0]), current): kept = v
	if not kept.is_empty() and absf(tilt - current) <= best_off + AXIAL_HYST_DEG: best = kept
	c["axial"] = float(best[0])
	return best

## The same for a hand row: `tilted` is [[tilt, row], ...] with the side view first.
func _pick_hand_axial(c: Dictionary, tilted: Array, tilt: float) -> int:
	var current: float = float(c.axial)
	var best: Array = tilted[0]
	var best_off: float = INF
	var kept: Array = []
	for v in tilted:
		var off: float = absf(tilt - float(v[0]))
		if off < best_off:
			best_off = off
			best = v
		if is_equal_approx(float(v[0]), current): kept = v
	if not kept.is_empty() and absf(tilt - current) <= best_off + AXIAL_HYST_DEG: best = kept
	c["axial"] = float(best[0])
	return int(best[1])

## First person: the sprite turn for one of your own cards, from where the eye is from that card.
func _own_cell(c: Dictionary, node: Node3D, at: Vector3, cam_pos: Vector3) -> int:
	var cur: int = int(c.get("cell", -1))
	if node == null: return maxi(cur, 0)
	var basis: Basis = node.global_basis
	if _motion != null and _motion.has_motion(): basis = _motion.apply(node, Transform3D(basis, Vector3.ZERO)).basis
	var fwd: Vector3 = basis * _player._get_forward_axis()
	fwd.y = 0.0
	var to_cam: Vector3 = cam_pos - at
	to_cam.y = 0.0
	if fwd.length() < 0.001 or to_cam.length() < FIRST_PERSON_HOLD_M: return maxi(cur, 0)
	var rel: float = rad_to_deg(to_cam.normalized().signed_angle_to(fwd.normalized(), Vector3.UP))
	if cur >= 0 and absf(wrapf(rel - cur * CELL_DEG, -180.0, 180.0)) <= CELL_DEG * 0.5 + HYSTERESIS_DEG * 2.0: return cur
	cur = posmod(roundi(rel / CELL_DEG), 16)
	c["cell"] = cur
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
