extends SceneTree
## Cinematic reel camera for one planned rally (seed 4, the point from tick 2427 to ~4006).
## Time base: G, the game clock in normal-speed ticks. Godot's time_scale keeps 30 physics
## ticks a second and shrinks each tick's step, so G advances by the time scale every tick.
## Every shot and the speed curve are functions of G. The ball's and players' future comes from
## a track written by an earlier run (--plan), so tracking leads the ball instead of chasing it;
## the rally's key hits (lob, smash, counter, point) are read from that plan. The speed curve is
## a fixed function of G (plus a 30-frame bullet time at the smash), so a run with the same
## curve replays the planning run exactly. Each run writes its own track (--track-out).
## The filming camera is a copy: the game's camera keeps running, because between points the
## game checks what that camera can see.
## Run: godot --path . --resolution 1080x1920 [--write-movie m.avi] --fixed-fps 30 \
##        -s tools/cine.gd -- --mobile-runtime --autoplay --doubles --seed=4 \
##        --plan=<track> --track-out=<track> --shots-out=<shots.jsonl>
## The shot list below is written for the seed-4 rally (game-clock ticks of its serve, dinks,
## lob, smash and counter); another rally needs new ranges. How-to: docs/REEL_TOOLS.md.

const BULLET_FRAMES := 30

var _game: Node
var _photo: Node
var _cam: Camera3D
var _ready_done := false
var _frame := 0
var _track: FileAccess
var _shots: FileAccess
var _g := 0.0                     # game clock (normal-speed ticks)
var _last_pf := -1
var _last_ts := 1.0
var _end_g := 4060.0
# plan
var _pt := PackedFloat32Array()   # G of each plan row
var _pb := PackedVector3Array()
var _pp: Dictionary = {}          # actor id -> PackedVector3Array (aligned with _pt)
var _hits: Array = []             # [g, actor]
var _st: Array = []               # [g, state] at changes
var LOB := 3928.0
var SMASH := 3954.0
var COUNTER := 3968.0
var POINT := 4006.0
# bullet time
var _bullet := -1
var _bullet_pending := false
var _bullet_done := false
var _bullet_c := Vector3.ZERO
var _bullet_ball := Vector3.ZERO
var _dir := Vector3.ZERO

class Driver extends Node:
	var d
	func _process(_delta: float) -> void: d._tick()

func _initialize() -> void:
	var plan := ""
	var track_out := ""
	var shots_out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--plan="): plan = arg.trim_prefix("--plan=")
		if arg.begins_with("--track-out="): track_out = arg.trim_prefix("--track-out=")
		if arg.begins_with("--shots-out="): shots_out = arg.trim_prefix("--shots-out=")
	_load_plan(plan)
	_find_events()
	_end_g = COUNTER + 100.0
	if OS.get_environment("CINE_END") != "": _end_g = float(OS.get_environment("CINE_END"))
	_track = FileAccess.open(track_out, FileAccess.WRITE)
	_shots = FileAccess.open(shots_out, FileAccess.WRITE)
	_shots.store_line(JSON.stringify({"events": {"lob": LOB, "smash": SMASH, "counter": COUNTER, "point": POINT}}))
	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(_game)
	var dr := Driver.new()
	dr.d = self
	dr.process_mode = Node.PROCESS_MODE_ALWAYS
	dr.process_priority = 10000
	root.add_child.call_deferred(dr)

func _load_plan(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	var last := -1.0
	var last_st := -1
	while not f.eof_reached():
		var line := f.get_line()
		if line.is_empty(): continue
		var r = JSON.parse_string(line)
		if r.has("hit"):
			_hits.append([float(r.g) if r.has("g") else float(r.tick), int(r.hit)])
			continue
		if not r.has("t"): continue
		var g: float = float(r.g) if r.has("g") else float(r.t) + float(r.fr)
		if g <= last: continue
		last = g
		if int(r.st) != last_st:
			last_st = int(r.st)
			_st.append([g, last_st])
		_pt.append(g)
		_pb.append(Vector3(r.b[0], r.b[1], r.b[2]))
		for p in r.p:
			var id := int(p[0])
			if not _pp.has(id): _pp[id] = PackedVector3Array()
			_pp[id].append(Vector3(p[2][0], p[2][1], p[2][2]))

## The rally's key hits from the plan: the lob (actor 0 near G 3928), the next hit by actor 1
## (smash), the next hit after that (counter), and the point's end.
func _find_events() -> void:
	var lob := -1.0
	for h in _hits:
		if h[1] == 0 and absf(h[0] - 3928.0) < 6.0: lob = h[0]
	if lob < 0.0: return
	LOB = lob
	for h in _hits:
		if h[0] > LOB and h[1] == 1: SMASH = h[0]; break
	for h in _hits:
		if h[0] > SMASH: COUNTER = h[0]; break
	for s in _st:
		if s[0] > COUNTER and s[1] == 3: POINT = s[0]; break

# ---- plan sampling ----

func _idx(t: float) -> int:
	var lo := 0
	var hi := _pt.size() - 1
	if t <= _pt[0]: return 0
	if t >= _pt[hi]: return hi - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if _pt[mid] <= t: lo = mid
		else: hi = mid
	return lo

func _sample(arr: PackedVector3Array, t: float) -> Vector3:
	var i := _idx(t)
	var span: float = maxf(_pt[i + 1] - _pt[i], 0.00001)
	return arr[i].lerp(arr[i + 1], clampf((t - _pt[i]) / span, 0.0, 1.0))

func ball(t: float) -> Vector3: return _sample(_pb, t)
func player(id: int, t: float) -> Vector3: return _sample(_pp[id], t)

## Ball smoothed over [t - back, t + ahead] (gaussian, in G), so the frame leads it.
func ball_s(t: float, back: float, ahead: float) -> Vector3:
	var sum := Vector3.ZERO
	var w := 0.0
	var mid := (ahead - back) * 0.5
	var sigma: float = maxf((ahead + back) * 0.35, 0.15)
	var step: float = maxf((ahead + back) / 24.0, 0.02)
	var k := -back
	while k <= ahead + 0.0001:
		var wk: float = exp(-pow(k - mid, 2.0) / (2.0 * sigma * sigma))
		sum += ball(t + k) * wk
		w += wk
		k += step
	return sum / w

# ---- easing ----

static func ss(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)

static func io(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return 4.0 * u * u * u if u < 0.5 else 1.0 - pow(-2.0 * u + 2.0, 3.0) / 2.0

static func band(a: float, b: float, t: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)

## Speed curve: a fixed function of G. Up to BULLET_G it is the curve the plan was recorded
## with (so the plan still holds there); bullet time starts at BULLET_G, just before contact.
const BULLET_G := 3950.9
func speed(t: float) -> float:
	if t < 3928.0: return 1.0
	if t < 3946.0: return lerpf(1.0, 0.3, ss(band(3928, 3946, t)))
	if t < BULLET_G: return lerpf(0.3, 0.12, ss(band(3946, 3954, t)))
	if t < 3956.0: return lerpf(0.17, 0.45, ss(band(BULLET_G, 3956, t)))
	if t < 3960.4: return lerpf(0.45, 0.15, ss(band(3956, 3960.4, t)))
	if t < 3961.6: return 0.15
	if t < 3976.0: return lerpf(0.15, 1.0, ss(band(3961.6, 3976, t)))
	return 1.0

## Screen-time progress of t through [a, b]: plan rows are one per rendered frame, so this
## eases camera moves evenly on screen even while the game clock slows down.
func uf(a: float, b: float, t: float) -> float:
	var fa := _fi(a)
	var fb := _fi(b)
	return clampf((_fi(t) - fa) / maxf(fb - fa, 0.001), 0.0, 1.0)

func _fi(t: float) -> float:
	var i := _idx(t)
	return float(i) + clampf((t - _pt[i]) / maxf(_pt[i + 1] - _pt[i], 0.00001), 0.0, 1.0)

static func ease_out(u: float) -> float:   # moves from the first frame, settles gently
	u = clampf(u, 0.0, 1.0)
	return (1.0 - pow(1.0 - u, 3.0)) * ss(u / 0.12) if u < 0.12 else 1.0 - pow(1.0 - u, 3.0)

# ---- shots ----
# Each returns {pos, look | subject+sx+sy, fov, f, focus[, up][, smooth_dir]}.
# subject + sx/sy: aim so `subject` lands at that screen position (0..1, top-left origin).

var _release_pose: Dictionary = {}

func _shot(t: float) -> Array:
	if _bullet >= 0: return ["F_bullet", _shot_f(float(_bullet) / float(BULLET_FRAMES - 1))]
	if t >= 2410.0 and t < 2480.0: return ["A_establish", _shot_a(t, uf(2410, 2480, t))]
	if t >= 3757.0 and t < 3812.0: return ["C1_dink_dolly", _shot_c1(t, uf(3757, 3812, t))]
	if t >= 3848.0 and t < 3903.0: return ["C2_dink_ots", _shot_c2(t, uf(3848, 3903, t))]
	if t >= LOB - 6.0 and not _bullet_done and t < BULLET_G + 1.0: return ["DE_lob_orbit", _shot_de(t, uf(LOB - 6.0, BULLET_G, t))]
	if _bullet_done and t < SMASH + 2.0: return ["F_release", _release_pose]
	if _bullet_done and t < COUNTER + 0.25: return ["G_chase", _shot_g(t, uf(SMASH + 2.0, COUNTER + 0.25, t))]
	if _bullet_done and t < COUNTER + 27.0: return ["H_counter", _shot_h(t, uf(COUNTER + 0.25, COUNTER + 27.0, t))]
	if _bullet_done and t >= COUNTER + 27.0: return ["I_crowd", _shot_i(uf(COUNTER + 27.0, COUNTER + 93.0, t))]
	return ["idle", {"pos": Vector3(0, 6.0, 13.0), "look": Vector3(0, 0.5, -1.0), "fov": 50.0, "f": 6, "focus": Vector3(0, 1, 0)}]

func _shot_a(t: float, u: float) -> Dictionary:
	var e := ease_out(u)
	var p0 := Vector3(0, 16.0, 0.6)
	var p1 := Vector3(0.4, 9.0, 9.0)
	var p2 := Vector3(1.6, 2.3, 9.8)
	var pos := p0.lerp(p1, e).lerp(p1.lerp(p2, e), e)
	var server := player(0, t) + Vector3(0, 0.4, 0)
	var look := Vector3(0, 0, 0).lerp(Vector3(0, 0.9, -4.0).lerp(server, 0.3), e)
	var k := ss(u * 1.6)
	var up := Vector3(0, k, -(1.0 - k)).normalized()
	return {"pos": pos, "look": look, "fov": lerpf(58.0, 42.0, e), "f": 6 if u < 0.6 else 3, "focus": server.lerp(Vector3(0, 1, 0), 1.0 - e), "up": up}

func _shot_c1(t: float, u: float) -> Dictionary:
	# Off the net line toward the near baseline, so the post stays out; cards seen 3/4.
	var bs := ball_s(t, 4.0, 8.0)
	var slow := ball_s(t, 12.0, 12.0)
	var pos := Vector3(lerpf(4.9, 4.5, io(u)), 1.6, 2.4 + 0.3 * slow.z)
	var aim := Vector3(bs.x * 0.7, bs.y * 0.5 + 0.35, bs.z)
	return {"pos": pos, "subject": aim, "sx": 0.5, "sy": 0.55, "fov": 50.0, "f": 1, "focus": bs}

func _shot_c2(t: float, u: float) -> Dictionary:
	# Shoulder on the left third only; ball and opponents in the clear two-thirds.
	var a2 := player(2, t)
	var pos := (a2 + Vector3(-1.5, 0.45, 1.9)).lerp(a2 + Vector3(-1.3, 0.4, 1.4), io(u))
	var bs := ball_s(t, 4.0, 8.0)
	var opp := (player(1, t) + player(3, t)) * 0.5 + Vector3(0, 0.3, 0)
	return {"pos": pos, "subject": bs.lerp(opp, 0.55), "sx": 0.58, "sy": 0.5, "fov": 40.0, "f": 1, "focus": bs.lerp(opp, 0.5)}

func _orbit(c: Vector3, a_deg: float, r: float, h: float) -> Vector3:
	var a := deg_to_rad(a_deg)
	return Vector3(c.x + sin(a) * r, h, c.z - cos(a) * r)

func _shot_de(t: float, u: float) -> Dictionary:
	var c := player(1, t) + Vector3(0, 0.35, 0)
	var e := io(u)
	var pos := _orbit(c, lerpf(20.0, 100.0, e), 3.4, lerpf(0.8, 1.3, e))
	var subject := (player(1, t) + Vector3(0, 0.25, 0)).lerp(ball_s(t, 2.0, 4.0), 0.3)
	return {"pos": pos, "subject": subject, "sx": 0.6, "sy": 0.5, "fov": 48.0, "f": 0, "focus": c}

func _shot_f(u: float) -> Dictionary:
	var e := io(u)
	var pos := _orbit(_bullet_c, lerpf(100.0, 180.0, e), lerpf(3.4, 2.6, e), lerpf(1.3, 1.7, e))
	var subject := _bullet_c.lerp(_bullet_ball, 0.6)
	var d := {"pos": pos, "subject": subject, "sx": 0.5, "sy": 0.45, "fov": lerpf(48.0, 42.0, e), "f": 0, "focus": _bullet_ball}
	_release_pose = d.duplicate()
	return d

func _shot_g(t: float, u: float) -> Dictionary:
	# Rides 1 m behind and 0.3 m above the ball, then settles 3 m short of the counter-smasher
	# at chest height, aimed at the contact point (known from the plan).
	var b := ball_s(t, 0.6, 0.6)
	var bf := ball_s(t + 1.5, 0.6, 0.6)
	var dir := (bf - b).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var free := b - dir * 1.0 + side * 0.2 + Vector3.UP * 0.3
	var hitter := player(2, COUNTER)
	var contact := ball(COUNTER)
	var away := Vector3(free.x - hitter.x, 0.0, free.z - hitter.z)
	var stop := hitter + away.normalized() * 3.0
	stop.y = 1.45
	var k := ss(clampf((4.2 - away.length()) / 1.2, 0.0, 1.0))
	var pos := free.lerp(stop, k)
	var subject := b.lerp(b.lerp(contact, 0.5), k)
	return {"pos": pos, "subject": subject, "sx": 0.5, "sy": 0.5, "fov": 58.0, "f": 1, "focus": b}

func _shot_h(t: float, u: float) -> Dictionary:
	# Low between the two near players: the counter-smash comes straight at the lens, skips
	# off the concrete and rips past on the left; the camera whips round after it.
	var pos := Vector3(1.05, 0.8, -6.8)
	return {"pos": pos, "subject": ball_s(t + 1.0, 1.5, 2.0), "sx": 0.5, "sy": 0.4, "fov": 42.0, "f": 1, "focus": ball_s(t, 0.5, 0.5), "smooth_dir": 0.3}

func _shot_i(u: float) -> Dictionary:
	# Crane up and push in on the hall crowd so it fills the lower half.
	var e := io(u)
	var pos := Vector3(0.0, 2.1, -6.4).lerp(Vector3(0.2, 4.1, -7.3), e)
	var look := Vector3(0, 0.9, -12.5).lerp(Vector3(0, 0.8, -12.7), e)
	return {"pos": pos, "look": look, "fov": lerpf(52.0, 46.0, e), "f": 2, "focus": Vector3(0, 1.1, -12.3)}

# ---- runtime ----

func _setup() -> void:
	current_scene = _game
	_game.ball.actor_hit_paddle.connect(_on_hit)
	var rig = _game.get("camera_rig")
	var game_cam: Camera3D = rig.camera
	_photo = load("res://scripts/ui/photo_mode.gd").new()
	root.add_child(_photo)
	var dummy := CanvasLayer.new()
	root.add_child(dummy)
	_photo.begin(dummy)
	game_cam.h_offset = _photo._saved_camera.h
	game_cam.v_offset = _photo._saved_camera.v
	_cam = game_cam.duplicate(0) as Camera3D
	_cam.script = null
	_cam.name = "FilmCamera"
	root.add_child(_cam)
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_cam.make_current()
	_photo._camera = _cam
	_photo._hide_panel()
	_photo._logo_on = false
	_photo._place()
	_ready_done = true

func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]

func _on_hit(actor_id: int, team: int, _side: int) -> void:
	var g: float = _g + _last_ts
	_track.store_line(JSON.stringify({"hit": actor_id, "team": team, "tick": Engine.get_physics_frames(), "g": snappedf(g, 0.0001),
		"pos": _v(_game.ball.global_position), "vel": _v(_game.ball.linear_velocity)}))

func _tick() -> void:
	if not _ready_done:
		if is_instance_valid(_game) and _game.is_inside_tree() and _game.get("camera_rig") != null and _game.camera_rig.camera != null:
			_setup()
		return
	_frame += 1
	var pf: int = Engine.get_physics_frames()
	if _last_pf < 0: _g = float(pf)
	else: _g += float(pf - _last_pf) * _last_ts
	_last_pf = pf
	var t: float = _g
	var row := {"t": pf, "fr": 0.0, "g": snappedf(t, 0.0001), "st": int(_game.game_state), "b": _v(_game.ball.get_global_transform_interpolated().origin)}
	var ps: Array = []
	for p in _game.get_players():
		ps.append([p.get_actor_id(), p.team_id, _v(p.get_global_transform_interpolated().origin), int(p.paddle_posture)])
	row["p"] = ps
	_track.store_line(JSON.stringify(row))
	if not _bullet_done and _bullet < 0 and t >= BULLET_G: _bullet_pending = true
	if _bullet_pending:
		_bullet_pending = false
		_bullet = 0
		_bullet_c = _ipos_player(1) + Vector3(0, 0.35, 0)
		_bullet_ball = _game.ball.get_global_transform_interpolated().origin
		for n in _game.find_children("*", "VisualInstance3D", true, false):
			if n.is_visible_in_tree() and n.global_position.distance_to(_bullet_ball) < 0.9:
				_shots.store_line(JSON.stringify({"near_ball": str(n.get_path()), "class": n.get_class(), "script": str(n.get_script().resource_path) if n.get_script() else "", "d": snappedf(n.global_position.distance_to(_bullet_ball), 0.01)}))
	var shot: Array = _shot(t)
	# The ball trail piles up into a blob in slow motion: off for the slow shots.
	var trail_on: bool = not (str(shot[0]) in ["DE_lob_orbit", "F_bullet", "F_release"])
	for n in _game.get_children():
		var sc: Script = n.get_script()
		if sc != null and sc.resource_path.ends_with("ball_trail.gd"):
			if not n.has_meta("reel_layers"): n.set_meta("reel_layers", n.layers)
			n.layers = int(n.get_meta("reel_layers")) if trail_on else 0
	# A smash flash or contact burst frozen by bullet time reads as a smudge: off for those shots.
	var frozen: bool = str(shot[0]) in ["F_bullet", "F_release"]
	var feel: Node = _game.get_node_or_null("MatchFeel")
	if feel != null:
		for m in feel.get("_flashes"):
			if is_instance_valid(m):
				if not m.has_meta("reel_layers"): m.set_meta("reel_layers", m.layers)
				m.layers = 0
	var pool: Node = root.get_node_or_null("FXPool")
	if pool != null and pool.has_method("set") and "visible" in pool: pool.visible = not frozen
	_apply(shot[1])
	var ts: float = 0.002 if _bullet >= 0 else speed(t)
	_shots.store_line(JSON.stringify({"f": _frame, "shot": shot[0], "g": snappedf(t, 0.0001), "ts": snappedf(ts, 0.0001),
		"err": snappedf(ball(t).distance_to(_game.ball.get_global_transform_interpolated().origin), 0.001),
		"scr": _scr(shot[1])}))
	if _bullet >= 0:
		_bullet += 1
		if _bullet >= BULLET_FRAMES:
			_bullet = -1
			_bullet_done = true
			ts = speed(t)
	_set_speed(ts)
	_last_ts = ts
	if t >= _end_g:
		_set_speed(1.0)
		_track.flush(); _shots.flush()
		quit()

## Through the game's TimeScale autoload, which owns Engine.time_scale. Its request_slowmo()
## clamps other sources at 0.05, too high for bullet time (0.002), so the source is written
## directly and applied with its own _apply().
func _set_speed(ts: float) -> void:
	var tsm: Node = root.get_node_or_null("TimeScale")
	if tsm == null:
		Engine.time_scale = ts
	elif ts >= 0.999:
		tsm.release("reel")
	else:
		tsm._slowmo_sources["reel"] = clampf(ts, 0.001, 1.0)
		tsm._apply()

func _scr(d: Dictionary) -> Array:
	if not d.has("subject"): return []
	var size: Vector2 = _cam.get_viewport().get_visible_rect().size
	var p: Vector2 = _cam.unproject_position(Vector3(d.subject)) / size
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]

func _ipos_player(id: int) -> Vector3:
	for p in _game.get_players():
		if p.get_actor_id() == id: return p.get_global_transform_interpolated().origin
	return Vector3.ZERO

func _apply(s: Dictionary) -> void:
	for node in _game.find_children("DoublesIdentityCues", "Node3D", true, false): node.visible = false
	for node in _game.find_children("ReachRings", "Node3D", true, false): node.visible = false
	var readability: Node = _game.ball.get_node_or_null("BallReadability")
	if readability != null: readability.visible = false
	for node in _game.find_children("*", "CanvasLayer", true, false):
		if node.name != "PixelPost": node.visible = false
	for node in _game.find_children("*", "Label3D", true, false):
		if node.billboard != BaseMaterial3D.BILLBOARD_DISABLED: node.visible = false
	var at: Vector3 = Vector3(s.pos).clamp(_photo.BOUNDS_MIN, _photo.BOUNDS_MAX)
	var dir: Vector3 = ((Vector3(s.subject) if s.has("subject") else Vector3(s.look)) - at).normalized()
	if s.has("smooth_dir"):
		_dir = dir if _dir == Vector3.ZERO else _dir.slerp(dir, float(s.smooth_dir)).normalized()
		dir = _dir
	else:
		_dir = Vector3.ZERO
	var up: Vector3 = s.get("up", Vector3.UP)
	if absf(dir.dot(up.normalized())) > 0.995: up = Vector3(0, 0, -1)
	_cam.global_transform = Transform3D(Basis.IDENTITY, at).looking_at(at + dir, up)
	_cam.fov = float(s.fov)
	if s.has("subject"):
		# Turn so the subject sits at (sx, sy) on screen instead of the centre.
		var size: Vector2 = _cam.get_viewport().get_visible_rect().size
		var th: float = tan(deg_to_rad(_cam.fov) * 0.5)
		var tx: float = th if _cam.keep_aspect == Camera3D.KEEP_WIDTH else th * size.x / size.y
		var ty: float = th if _cam.keep_aspect == Camera3D.KEEP_HEIGHT else th * size.y / size.x
		var b: Basis = _cam.global_basis
		b = Basis(Vector3.UP, atan((float(s.sx) - 0.5) * 2.0 * tx)) * b
		b = Basis(b.x.normalized(), atan((float(s.sy) - 0.5) * 2.0 * ty)) * b
		_cam.global_basis = b.orthonormalized()
	_cam.h_offset = 0.0
	_cam.v_offset = 0.0
	_photo._read_angles()
	_photo._fov_slider.set_value_no_signal(s.fov)
	_photo._zoom_slider.set_value_no_signal(1.0)
	_photo._apply_fov()
	_photo._aperture_slider.set_value_no_signal(s.f)
	var focus: float = (Vector3(s.focus) - at).dot(-_cam.global_basis.z)
	_photo._focus_slider.set_value_no_signal(clampf(focus, _photo.FOCUS_MIN, _photo.FOCUS_MAX))
	_photo._sync_depth()
	_photo._update_lens()
	if _photo._blur_material != null: _photo._blur_material.set_shader_parameter("taps", 64)
