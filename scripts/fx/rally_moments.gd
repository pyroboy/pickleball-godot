extends Node3D
## Rally moments, presentation only (no physics; own RNG, never the global one the AI uses):
##  - a small confetti puff at rally-counter milestones (no confetti per point),
##  - PERFECT hit: a ring of sparks at the ball and the hitter's cards flash white,
##  - a stamp where the rally ended ("OUT", "NET", "KITCHEN", "WINNER" ...),
##  - a rally counter over the far baseline once a rally gets long: bold pixel text that
##    whose letters hop in a little wave on each ball hit (only then: still between hits),
##    a bit taller from 15 shots.
## Proposal PDF pages 17, 21 and 24. Lives under Game, never under a player's BodyPivot.

const PixelTheme = preload("res://scripts/ui/game_ui_theme.gd")
const PixelDraw = preload("res://scripts/ui/pixel_draw.gd")
const Layout = preload("res://scripts/ui/mobile_layout.gd")

const CONFETTI_MAX := 96
const CONFETTI_LIFE := 2.4
const CONFETTI_GRAVITY := 6.0
const CONFETTI_DRAG := 2.2         # 1/s on velocity: pieces float down instead of dropping
const CONFETTI_EXTRA := [Color("ffd46b"), Color("c4ef6b"), Color("f2f6ee")]

const SPARKS := 12
const SPARK_LIFE := 0.24
const SPARK_SPEED := 3.2
const SPARK_COLOR := Color("c4ef6b")
const PERFECT_FLASH := 0.07        # s of white cards: about two frames

const STAMP_SLAM := 0.12
const STAMP_HOLD := 1.0
const STAMP_FADE := 0.3
const STAMP_FAULT := Color("ff5d52")
const STAMP_WIN := Color("ffd46b")
const STAMPS := {
	RallyScorer.FAULT_OUT_OF_BOUNDS: "OUT",
	RallyScorer.FAULT_BALL_IN_NET: "NET",
	RallyScorer.FAULT_NET_POST: "POST",
	RallyScorer.FAULT_NET_TOUCH: "NET TOUCH",
	RallyScorer.FAULT_NET_PLANE: "OVER THE NET",
	RallyScorer.FAULT_KITCHEN_VOLLEY: "KITCHEN",
	RallyScorer.FAULT_MOMENTUM: "KITCHEN",
	RallyScorer.FAULT_SHORT_SERVE: "SHORT",
	RallyScorer.FAULT_FOOT_FAULT: "FOOT FAULT",
	RallyScorer.FAULT_WRONG_SERVICE_COURT: "WRONG BOX",
	RallyScorer.FAULT_DOUBLE_BOUNCE: "WINNER!",   # the ball beat the receiver
}

const COUNTER_FROM := 6            # rally length (serve = 1) where the counter appears
const COUNTER_HOT := 10
const COUNTER_FIRE := 15
const COUNTER_MILESTONE := 5       # every 5 shots from COUNTER_HOT: bigger pop and a puff
const COUNTER_HOLD := 1.6          # s it stays after the rally ends
const HOP_LETTER_DELAY := 0.035    # s between neighbouring letters in a hop wave
const HOP_SECONDS := 0.18          # one letter's jump, up and down
const HOP_HEADROOM := 3            # font pixels of room above the text for the jumps
const COUNTER_COLORS := [Color("f2efe6"), Color("f5d060"), Color("ff9a3c")]   # cream, gold (10+), orange (15+)
const COUNTER_EDGE_DARKEN := 0.55   # edge = the text colour, this much darker (no black stroke)

var _game
var _rng := RandomNumberGenerator.new()
var _clock := 0.0

var _confetti: MultiMeshInstance3D
var _c_pos := PackedVector3Array()
var _c_vel := PackedVector3Array()
var _c_axis := PackedVector3Array()
var _c_spin := PackedFloat32Array()
var _c_age := PackedFloat32Array()
var _c_phase := PackedFloat32Array()
var _c_color: Array[Color] = []
var _c_next := 0
var _c_alive := 0

var _sparks: MultiMeshInstance3D
var _s_dir := PackedVector3Array()
var _s_at := Vector3.ZERO
var _s_age := SPARK_LIFE

var _stamp: Label3D
var _stamp_why: Label3D     # second line, smaller: the hitter's own cause (LATE, MOVING ...)
var _stamp_hold := STAMP_HOLD
var _stamp_age := 99.0

var _counter: Control             # bold pixel text drawn on its own canvas layer (_draw_counter)
var _counter_text := ""
var _counter_color := Color.WHITE
var _counter_font := 36
var _hop_t := 99.0                # s since the last hit's hop wave started
var _counter_anchor := Vector3.ZERO   # world point it is pinned to (over the far baseline)
var _rally := 1
var _counter_left := 0.0
var _counter_big := false

func setup(game) -> void:
	_game = game
	name = "RallyMoments"
	# Placed every rendered frame from interpolated reads: no physics interpolation here.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rng.seed = 7151   # fixed: the look repeats, and the global RNG is never touched
	_build_confetti()
	_build_sparks()
	_stamp = _label(72, 0.011)
	_stamp_why = _label(40, 0.011)
	var layer := CanvasLayer.new()
	layer.layer = 5   # over the court, under the HUD banners and menus
	add_child(layer)
	_counter = Control.new()
	_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counter.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_counter.visible = false
	_counter.draw.connect(_draw_counter)
	layer.add_child(_counter)
	if _game.ball != null: _game.ball.hit_by_paddle.connect(_on_hit)
	if _game.rally_scorer != null: _game.rally_scorer.rally_ended.connect(_on_rally_ended)
	var human = _human()
	if human != null and human.get("posture") != null and human.posture.has_signal("grade_flashed"):
		human.posture.grade_flashed.connect(_on_grade)

func _human():
	return _game.get_human_actor() if _game != null and _game.has_method("get_human_actor") else null

func _practice() -> bool:
	return _game.has_method("_is_practice") and _game._is_practice()

func _unshaded(additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.disable_fog = true
	if additive: m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

func _multimesh(mesh: Mesh, count: int, material: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.top_level = true
	add_child(node)
	return node

func _label(size: int, pixel: float) -> Label3D:
	var l := Label3D.new()
	l.font = PixelTheme.pixel_font()
	l.font_size = size
	l.pixel_size = pixel
	l.outline_size = 14
	l.outline_modulate = Color(0.06, 0.1, 0.14, 1.0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	l.no_depth_test = true
	l.shaded = false
	l.double_sided = true
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.visible = false
	add_child(l)
	return l

# --- confetti ------------------------------------------------------------------------

func _build_confetti() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.04)
	_confetti = _multimesh(quad, CONFETTI_MAX, _unshaded(false))
	for i in CONFETTI_MAX:
		_c_pos.append(Vector3.ZERO)
		_c_vel.append(Vector3.ZERO)
		_c_axis.append(Vector3.UP)
		_c_spin.append(0.0)
		_c_age.append(CONFETTI_LIFE)
		_c_phase.append(0.0)
		_c_color.append(Color.WHITE)

func _burst_confetti(at: Vector3, count: int, team_color: Color, up_speed: float = 4.2) -> void:
	for n in count:
		var i := _c_next
		_c_next = (_c_next + 1) % CONFETTI_MAX
		var a: float = _rng.randf() * TAU
		var out: float = _rng.randf_range(0.6, 2.2)
		_c_pos[i] = at + Vector3(_rng.randf_range(-0.15, 0.15), 0.0, _rng.randf_range(-0.15, 0.15))
		_c_vel[i] = Vector3(cos(a) * out, _rng.randf_range(up_speed * 0.6, up_speed), sin(a) * out)
		_c_axis[i] = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
		_c_spin[i] = _rng.randf_range(6.0, 14.0)
		_c_phase[i] = _rng.randf() * TAU
		_c_age[i] = 0.0
		_c_color[i] = team_color if _rng.randf() < 0.55 else CONFETTI_EXTRA[_rng.randi() % CONFETTI_EXTRA.size()]
	_c_alive = CONFETTI_MAX

func _update_confetti(real: float) -> void:
	if _c_alive == 0: return
	var mm := _confetti.multimesh
	var shown := 0
	var floor_y: float = PickleballConstants.FLOOR_Y + 0.01
	for i in CONFETTI_MAX:
		if _c_age[i] >= CONFETTI_LIFE: continue
		_c_age[i] += real
		var v: Vector3 = _c_vel[i]
		v.y -= CONFETTI_GRAVITY * real
		v *= exp(-CONFETTI_DRAG * real)
		_c_vel[i] = v
		var p: Vector3 = _c_pos[i] + v * real
		p.x += sin(_clock * 5.0 + _c_phase[i]) * 0.25 * real   # flutter side to side
		if p.y < floor_y:
			p.y = floor_y
			_c_vel[i] = Vector3.ZERO
		_c_pos[i] = p
		var fade: float = clampf((CONFETTI_LIFE - _c_age[i]) / 0.5, 0.0, 1.0)
		var basis := Basis(_c_axis[i], _c_spin[i] * _c_age[i] + _c_phase[i]).scaled(Vector3.ONE * maxf(fade, 0.01))
		mm.set_instance_transform(shown, Transform3D(basis, p))
		mm.set_instance_color(shown, _c_color[i])
		shown += 1
	mm.visible_instance_count = shown
	_c_alive = shown

# --- PERFECT sparks --------------------------------------------------------------------

func _build_sparks() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.014, 0.014, 0.16)
	_sparks = _multimesh(box, SPARKS, _unshaded(true))
	for i in SPARKS:
		var a: float = TAU * float(i) / SPARKS
		# Fixed ring, tipped a little toward the camera's view so it reads as a star.
		_s_dir.append(Vector3(cos(a), sin(a) * 0.85, sin(a) * 0.5).normalized())

func _on_grade(grade: String) -> void:
	if grade != "PERFECT" or _game.ball == null: return
	_s_at = _game.ball.get_global_transform_interpolated().origin
	_s_age = 0.0
	var human = _human()
	var host: Node = human.get_parent() if human != null else null
	var rig: Node = host.get_node_or_null("PixelCards_%d" % human.get_instance_id()) if host != null else null
	if rig != null and rig.has_method("flash_white"): rig.flash_white(PERFECT_FLASH)

func _update_sparks(real: float) -> void:
	var mm := _sparks.multimesh
	if _s_age >= SPARK_LIFE:
		mm.visible_instance_count = 0
		return
	_s_age += real
	var share: float = clampf(_s_age / SPARK_LIFE, 0.0, 1.0)
	var reach: float = SPARK_SPEED * SPARK_LIFE * (1.0 - pow(1.0 - share, 2.0))   # fast out, easing
	var color := Color(SPARK_COLOR, 1.0 - share)
	for i in SPARKS:
		var d: Vector3 = _s_dir[i]
		var basis := Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT)
		basis = basis.scaled(Vector3(1.0, 1.0, lerpf(1.4, 0.3, share)))
		mm.set_instance_transform(i, Transform3D(basis, _s_at + d * (0.12 + reach)))
		mm.set_instance_color(i, color)
	mm.visible_instance_count = SPARKS

# --- stamp and rally counter -----------------------------------------------------------

func _on_hit(_team: int) -> void:
	if _game.game_state != _game.GameState.PLAYING or _practice(): return
	_rally += 1
	if _rally < COUNTER_FROM: return
	_counter_big = _rally >= COUNTER_HOT and (_rally - COUNTER_HOT) % COUNTER_MILESTONE == 0
	_counter_left = INF
	var tier: int = 2 if _rally >= COUNTER_FIRE else (1 if _rally >= COUNTER_HOT else 0)
	var s: float = Layout.scale_for(get_viewport().get_visible_rect().size)
	_counter_text = "RALLY %d" % _rally
	_counter_color = COUNTER_COLORS[tier]
	_counter_font = PixelDraw.font_size((45.0 if _counter_big else 36.0) * s)
	var fp: float = float(_counter_font) / PixelTheme.PIXEL_UNIT   # screen px per font pixel
	_counter.size = Vector2(PixelDraw.text_width(_counter_text, _counter_font) + fp * 3.0, PixelDraw.font().get_height(_counter_font) + fp * (3.0 + HOP_HEADROOM)).ceil()
	_hop_t = 0.0   # a hop wave runs across the letters on every hit
	_counter.queue_redraw()
	_place_counter()
	_counter.visible = true
	if _counter_big:
		PerfMonitor.note("rally_moment", {"milestone": _rally, "size": [_counter.size.x, _counter.size.y], "hop": _hop_height()})
		_burst_confetti(_counter_anchor + Vector3.DOWN * 0.2, 14, COUNTER_COLORS[tier], 2.4)

func _place_counter() -> void:
	var human = _human()
	var side: float = signf(human.global_position.z) if human != null else 1.0
	if side == 0.0: side = 1.0
	_counter_anchor = Vector3(0.0, 3.1, -side * (PickleballConstants.COURT_LENGTH * 0.5 + 0.8))

## Hop height in font pixels on each ball hit: small, a little taller from 15 shots.
func _hop_height() -> int:
	return 2 if _rally < COUNTER_FIRE else 3

## Height of letter `i` above its line, in font pixels (whole pixels: pixel-art hops).
## Only the wave started by the last ball hit; the counter never moves by itself.
func _letter_hop(i: int) -> int:
	if _counter_left != INF: return 0   # rally over: hold still
	var hit: float = (_hop_t - i * HOP_LETTER_DELAY) / HOP_SECONDS
	if hit <= 0.0 or hit >= 1.0: return 0
	return roundi(float(_hop_height()) * sin(PI * hit))

func _on_rally_ended(winner: int, reason: String, _detail: String) -> void:
	var shots := _rally
	_rally = 1
	if _practice() or winner not in [0, 1]: return
	if _counter.visible: _counter_left = COUNTER_HOLD
	# No confetti per point (user's call 2026-11-23): only the milestone puffs remain.
	# Stamp where the ball ended up. A body hit has its own "Ouch!" bubble (body_hit_fx.gd).
	if reason == RallyScorer.FAULT_BODY_HIT: return
	var text: String = STAMPS.get(reason, "FAULT")
	var why: String = ""
	# Two lines from the one definition of how a point ended (point_ending.gd, set by game.gd
	# first): where the ball went, then the hitter's own cause (LATE, MOVING ...). Never who
	# "forced" it: only what the player could see (docs/SHOT_QUALITY_PLAN.md).
	var ending: Dictionary = _game.last_point_ending if "last_point_ending" in _game else {}
	if int(ending.get("tick", -1)) == Engine.get_physics_frames():
		if str(ending.get("where", "")) != "": text = str(ending.where)
		if str(ending.get("why", "")) != "": why = str(ending.why)
	var ball = _game.ball
	if ball == null: return
	var at: Vector3 = ball.get_global_transform_interpolated().origin
	at.y = PickleballConstants.FLOOR_Y + 0.75
	_stamp.text = text
	_stamp.modulate = STAMP_WIN if winner == 0 else STAMP_FAULT   # gold: your team's point; red: theirs
	_stamp.global_position = at
	_stamp.rotation = Vector3.ZERO
	_stamp.visible = true
	_stamp_age = 0.0
	_stamp_why.text = why
	_stamp_why.modulate = _stamp.modulate
	_stamp_why.global_position = at - Vector3.UP * 0.5
	_stamp_why.visible = why != ""
	_stamp_hold = STAMP_HOLD + (0.6 if why != "" else 0.0)   # a moment longer to read the cause
	PerfMonitor.note("rally_moment", {"stamp": text, "why": why, "shots": shots, "winner": winner, "confetti": _c_alive, "counter": _counter.visible})

func _update_stamp(real: float) -> void:
	if not _stamp.visible: return
	_stamp_age += real
	var t := _stamp_age
	if t >= STAMP_SLAM + _stamp_hold + STAMP_FADE:
		_stamp.visible = false
		_stamp_why.visible = false
		return
	var s: float
	if t < STAMP_SLAM:
		s = lerpf(2.4, 0.9, ease(t / STAMP_SLAM, 0.4))        # slams down
	else:
		s = 1.0 - 0.1 * exp(-(t - STAMP_SLAM) * 14.0) * cos((t - STAMP_SLAM) * 40.0)   # settles
	_stamp.scale = Vector3.ONE * s
	var alpha: float = clampf((STAMP_SLAM + _stamp_hold + STAMP_FADE - t) / STAMP_FADE, 0.0, 1.0)
	_stamp.modulate.a = alpha
	_stamp.outline_modulate.a = alpha
	_stamp_why.modulate.a = alpha
	_stamp_why.outline_modulate.a = alpha

func _update_counter(real: float) -> void:
	if not _counter.visible: return
	if _counter_left != INF:
		_counter_left -= real
		if _counter_left <= 0.0:
			_counter.visible = false
			return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(_counter_anchor):
		_counter.modulate.a = 0.0
		return
	var view: Vector2 = get_viewport().get_visible_rect().size
	var at: Vector2 = cam.unproject_position(_counter_anchor)
	# Keep it fully on screen (it is pinned above the far baseline).
	at.x = clampf(at.x, _counter.size.x * 0.5 + 8.0, view.x - _counter.size.x * 0.5 - 8.0)
	at.y = clampf(at.y, _counter.size.y * 0.5 + 8.0, view.y - _counter.size.y * 0.5 - 8.0)
	_counter.position = (at - _counter.size * 0.5).round()
	# Redraw only while a hop wave is running (then the letters hold still).
	var wave_end: float = HOP_SECONDS + HOP_LETTER_DELAY * _counter_text.length()
	if _hop_t <= wave_end: _counter.queue_redraw()
	_hop_t += real
	var alpha: float = clampf(_counter_left / 0.3, 0.0, 1.0) if _counter_left != INF else 1.0
	_counter.modulate.a = alpha

## Bold pixel text, no plate: an edge in a darker shade of the text colour, one font pixel all round, the glyphs drawn
## twice one font pixel apart (bold), and a hard drop shadow.
func _draw_counter() -> void:
	if _counter_text == "": return
	var f: Font = PixelDraw.font()
	var fp: float = float(_counter_font) / PixelTheme.PIXEL_UNIT
	var base := Vector2(fp, fp * (1.0 + HOP_HEADROOM) + f.get_ascent(_counter_font)).round()
	var edge: Color = _counter_color.darkened(COUNTER_EDGE_DARKEN)
	# Letter by letter, so each can hop on its own. Edges first for every letter, then
	# the fills, so a neighbour's edge never cuts into a letter.
	var spots: Array = []
	for i in _counter_text.length():
		if _counter_text[i] == " ": continue
		var x: float = f.get_string_size(_counter_text.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, _counter_font).x
		spots.append([_counter_text[i], base + Vector2(x, -_letter_hop(i) * fp)])
	for spot in spots:
		for off in [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(2, -1), Vector2(-1, 0), Vector2(2, 0),
				Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1), Vector2(2, 1), Vector2(0, 2), Vector2(1, 2)]:
			_counter.draw_string(f, spot[1] + off * fp, spot[0], HORIZONTAL_ALIGNMENT_LEFT, -1, _counter_font, edge)
	for spot in spots:
		for bold in [0.0, fp]:
			_counter.draw_string(f, spot[1] + Vector2(bold, 0), spot[0], HORIZONTAL_ALIGNMENT_LEFT, -1, _counter_font, _counter_color)

func _process(delta: float) -> void:
	var real: float = delta / maxf(Engine.time_scale, 0.05)
	_clock += real
	_update_confetti(real)
	_update_sparks(real)
	_update_stamp(real)
	_update_counter(real)
