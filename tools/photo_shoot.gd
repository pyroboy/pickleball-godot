extends SceneTree
## Photo shoot: plays an all-AI doubles match in a window, pauses at action moments (smash,
## kitchen exchange, drive, wide stretch, and the ball arriving at the receiver), opens photo
## mode from the pause menu and takes a set of framed shots with its camera and FOCUS /
## APERTURE / FOV / ZOOM controls: action angles, players' point of view (pov_*), and the
## scenery around the court (sc_*, placed for the barangay world).
## Run: godot --path . --resolution 1080x1920 -s tools/photo_shoot.gd -- --mobile-runtime \
##        --autoplay --doubles --seed=1 --shoot-out=/abs/dir [--shoot-secs=150] [--shoot-per=3]
##        [--shoot-kinds=smash,trophy,drop,air,finish]   only these moments (default: all but the
##        smash phases). trophy / drop / air are the High Overhead's wind-up, paddle drop and top
##        of a jump; smash / after / finish are 1, 3 and 6 ticks after a smash hit (ball on its
##        way), each from a different smash: pausing resets the point, so one smash gives one moment.
##        [--shoot-force-jump=1]   staged: an AI about to hit a High Overhead is made to jump
##        (leap and scissor legs in turn) so the air legs can be shot; not what the match would do.
## -> <dir>/<nn>_<kind>_<recipe>.png and <dir>/shots.jsonl (what each picture is)

const F_STOPS := [1.4, 2.0, 2.8, 4.0, 5.6, 8.0, 11.0, 16.0, 22.0]

var _game: Node
var _out := ""
var _secs := 150.0
var _per := 3
var _busy := false
var _count := 0
var _taken: Dictionary = {}      # kind -> moments shot
var _pending: Dictionary = {}    # a hit waiting for its delay: {kind, actor, ticks}
var _incoming: Dictionary = {}   # a hit whose ball is on its way to a receiver: {actor}
var _scenery_left := 2           # moments that also get the scenery set
var _kinds: PackedStringArray = []   # --shoot-kinds: only these moments
var _force_jump := false         # --shoot-force-jump: staged jump before a High Overhead contact
var _forced := 0
var _phase: Dictionary = {}      # actor -> smash phase memory (ticks of the last trophy / drop / jump)
const PHASE_KINDS := ["trophy", "drop", "air", "after", "finish"]
const SMASH_MOMENTS := [["smash", 1], ["after", 3], ["finish", 6]]   # kind, physics ticks after the hit
var _smash_turn := 0
const HIGH_OVERHEAD := 4
var _log: FileAccess
var _started := 0

class Driver extends Node:
	var shoot
	func _physics_process(_delta: float) -> void: shoot._physics_tick()
	func _process(_delta: float) -> void: shoot._tick()

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shoot-out="): _out = arg.trim_prefix("--shoot-out=")
		if arg.begins_with("--shoot-secs="): _secs = float(arg.trim_prefix("--shoot-secs="))
		if arg.begins_with("--shoot-per="): _per = int(arg.trim_prefix("--shoot-per="))
		if arg.begins_with("--shoot-kinds="): _kinds = arg.trim_prefix("--shoot-kinds=").split(",", false)
		if arg == "--shoot-force-jump=1": _force_jump = true
	DirAccess.make_dir_recursive_absolute(_out)
	_log = FileAccess.open(_out.path_join("shots.jsonl"), FileAccess.WRITE)
	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(_game)
	var d := Driver.new()
	d.shoot = self
	d.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child.call_deferred(d)
	_started = Time.get_ticks_msec()

func _tick() -> void:
	if current_scene != _game and is_instance_valid(_game) and _game.is_inside_tree():
		current_scene = _game
		_game.ball.actor_hit_paddle.connect(_on_hit)
	if not _busy and (Time.get_ticks_msec() - _started) / 1000.0 > _secs: quit()

func _player(actor_id: int) -> Node3D:
	for p in _game.get_players():
		if p.get_actor_id() == actor_id: return p
	return null

func _on_hit(actor_id: int, _team: int, _side: int) -> void:
	_incoming = {}
	if _busy or not _pending.is_empty() or int(_game.game_state) != 2: return
	var p := _player(actor_id)
	if p == null: return
	var b: Vector3 = _game.ball.global_position
	var players: Array = _game.get_players()
	var far := 0.0
	for q in players: far = maxf(far, absf(q.global_position.z))
	var kind := ""
	if b.y > 1.75: kind = "smash"
	elif far < 3.6: kind = "kitchen"
	elif absf(b.x - p.global_position.x) > 0.85 and b.y < 1.2: kind = "stretch"
	elif absf(p.global_position.z) > 4.5: kind = "drive"
	if kind == "smash" and not _kinds.is_empty():
		# Smash study: each smash gives one moment, taking turns (contact, just after, follow-through).
		for i in SMASH_MOMENTS.size():
			var m: Array = SMASH_MOMENTS[(_smash_turn + i) % SMASH_MOMENTS.size()]
			if _want(m[0]):
				_smash_turn = (_smash_turn + i + 1) % SMASH_MOMENTS.size()
				_pending = {"kind": m[0], "actor": actor_id, "ticks": m[1]}
				break
	elif kind != "" and _want(kind):
		# One physics tick later the ball has left the paddle and its speed is the shot's.
		_pending = {"kind": kind, "actor": actor_id, "ticks": 1}
	elif _kinds.is_empty() and int(_taken.get("incoming", 0)) < _per * 2:
		_incoming = {"actor": actor_id}

func _want(kind: String) -> bool:
	if _kinds.is_empty(): return kind not in PHASE_KINDS and int(_taken.get(kind, 0)) < _per
	return kind in _kinds and int(_taken.get(kind, 0)) < _per

func _begin(kind: String, p: Node3D) -> bool:
	_taken[kind] = int(_taken.get(kind, 0)) + 1
	_busy = true
	_shoot(kind, p, null)
	return true

## The High Overhead's phases, read off the player each tick: trophy (paddle up behind the head
## while the ball comes down), drop (paddle below the shoulders right after a trophy), air (top
## of a jump). Every jump is logged, shot or not.
func _poll_phases() -> bool:
	if int(_game.game_state) != 2: return false
	var tick: int = Engine.get_physics_frames()
	var ball: Vector3 = _game.ball.global_position
	for p in _game.get_players():
		var id: int = p.get_actor_id()
		if not _phase.has(id): _phase[id] = {}
		var st: Dictionary = _phase[id]
		var up: float = p.global_position.y - p.ground_y
		if p.is_jumping and up > 0.16 and p.vertical_velocity <= 0.35 and not st.get("air", false):
			st["air"] = true
			_log.store_line(JSON.stringify({"event": "jump", "actor": id, "tick": tick, "up": snappedf(up, 0.01), "style": int(p.jump_style), "posture": int(p.paddle_posture)}))
			_log.flush()
			if _want("air"): return _begin("air", p)
		if not p.is_jumping: st["air"] = false
		if _force_jump and not p.is_jumping and p.is_ai and p.ai_brain != null and int(p.ai_brain.ai_desired_posture) == HIGH_OVERHEAD \
				and p.ai_brain.ai_selected_contact_reachable and float(p.ai_brain.ai_selected_contact_time) > 0.12 and float(p.ai_brain.ai_selected_contact_time) <= 0.235 \
				and tick - int(st.get("forced_tick", -999)) > 60:
			# Staged: the game's own jump (0.24 m, top at contact), with the legs alternating leap / scissor.
			st["forced_tick"] = tick
			p.jump_style = _forced % 2
			_forced += 1
			p.vertical_velocity = sqrt(2.0 * p.JUMP_GRAVITY * p.CONTEXTUAL_JUMP_HEIGHT)
			p.is_jumping = true
			p.jump_takeoff_position = p.global_position
			_log.store_line(JSON.stringify({"event": "forced_jump", "actor": id, "tick": tick, "style": int(p.jump_style), "lead": snappedf(float(p.ai_brain.ai_selected_contact_time), 0.01)}))
			_log.flush()
		if int(p.paddle_posture) != HIGH_OVERHEAD or p.paddle_node == null:
			if st.has("oh"):
				# What the paddle did during this overhead (head height above the feet, how far behind the body).
				_log.store_line(JSON.stringify({"event": "overhead", "actor": id, "tick": tick, "ticks": st.oh[0], "head_max": snappedf(st.oh[1], 0.01), "head_min": snappedf(st.oh[2], 0.01), "back_max": snappedf(st.oh[3], 0.01),
					"drop_ticks": int(st.get("drop_ticks", 0)), "drop_low": snappedf(float(st.get("drop_low", 9.0)), 0.01)}))
				st["drop_ticks"] = 0; st["drop_low"] = 9.0
				_log.flush()
				st.erase("oh")
			continue
		var head: Vector3 = p.paddle_node.global_transform * Vector3(0, 0.28, 0) - p.global_position   # paddle head centre
		var back: float = - head.dot(p._get_forward_axis())
		var ball_d: float = ball.distance_to(p.global_position + Vector3.UP * 2.2)
		var oh: Array = st.get("oh", [0, -9.0, 9.0, -9.0])
		st["oh"] = [oh[0] + 1, maxf(oh[1], head.y - up), minf(oh[2], head.y - up), maxf(oh[3], back)]
		# Heights are from the player's root (about hip height): trophy head ~1.0, drop ~0.2, contact ~1.5.
		if head.y - up > 0.95 and back > 0.1:
			st["trophy_seen"] = tick
			if ball_d < 3.2 and ball_d > 0.9 and _game.ball.linear_velocity.y < 0.0 and tick - int(st.get("trophy_tick", -999)) > 120:
				st["trophy_tick"] = tick
				if _want("trophy"): return _begin("trophy", p)
		elif head.y - up < 0.55 and back > 0.05 and tick - int(st.get("trophy_seen", -999)) < 15:
			# Paddle well below the shoulders behind the body, right after a trophy: the Drop.
			st["drop_ticks"] = int(st.get("drop_ticks", 0)) + 1
			st["drop_low"] = minf(float(st.get("drop_low", 9.0)), head.y - up)
			if tick - int(st.get("drop_tick", -999)) > 120:
				st["drop_tick"] = tick
				if _want("drop"): return _begin("drop", p)
	return false

func _physics_tick() -> void:
	if _busy: return
	if _pending.is_empty() and _poll_phases(): return
	if not _incoming.is_empty() and _pending.is_empty():
		var hitter := _player(_incoming.actor)
		var ball: Vector3 = _game.ball.global_position
		var vel: Vector3 = _game.ball.linear_velocity
		if hitter == null or int(_game.game_state) != 2: _incoming = {}; return
		for q in _game.get_players():
			if q.team_id == hitter.team_id: continue
			var to: Vector3 = q.global_position - ball
			var flat := Vector2(to.x, to.z)
			if flat.length() < 2.4 and flat.dot(Vector2(vel.x, vel.z)) > 0.0 and ball.y > 0.35 and ball.y < 2.0 and vel.length() > 6.0:
				_incoming = {}
				_taken["incoming"] = int(_taken.get("incoming", 0)) + 1
				_busy = true
				_shoot("incoming", hitter, q)
				return
		return
	if _pending.is_empty(): return
	_pending.ticks -= 1
	if _pending.ticks > 0: return
	var m: Dictionary = _pending
	_pending = {}
	var speed: float = _game.ball.linear_velocity.length()
	if m.kind == "drive" and speed < 11.0: return
	if m.kind == "smash" and speed < 10.0 and _kinds.is_empty(): return
	if m.kind in ["after", "finish"] and (speed < 6.0 or int(_game.game_state) != 2): return   # the ball must still be flying
	_taken[m.kind] = int(_taken.get(m.kind, 0)) + 1
	_busy = true
	_shoot(m.kind, _player(m.actor), null)

func _wait(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout

func _eye(p: Node3D) -> Vector3:
	var head: Node3D = p.get_node_or_null("BodyPivot/TorsoMesh/HeadMesh")
	return head.global_position if head != null else p.global_position + Vector3.UP * 0.7

func _rig(p: Node3D) -> Node:
	return p.get_parent().get_node_or_null("PixelCards_%d" % p.get_instance_id()) if p != null else null

## The opponent the ball is heading for (nearest to its line of flight).
func _receiver(hitter: Node3D, ball: Vector3, fly: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for q in _game.get_players():
		if q.team_id == hitter.team_id: continue
		var to: Vector3 = q.global_position - ball
		var d: float = (Vector2(to.x, to.z) - Vector2(fly.x, fly.z).normalized() * Vector2(to.x, to.z).dot(Vector2(fly.x, fly.z).normalized())).length()
		if d < best_d: best_d = d; best = q
	return best

func _partner(p: Node3D) -> Node3D:
	for q in _game.get_players():
		if q != p and q.team_id == p.team_id: return q
	return null

# Each recipe: [camera position, look at, fov, zoom, f-stop index, focus on (point), eye-view player or null]

## Action angles around the hitter at contact.
func _action_recipes(hitter: Node3D, ball: Vector3, fly: Vector3) -> Dictionary:
	var p: Vector3 = hitter.global_position          # waist
	var s: float = 1.0 if p.z >= 0.0 else -1.0       # which end the hitter is on
	var side: float = 1.0 if ball.x >= p.x else -1.0 # paddle side
	var chest: Vector3 = p + Vector3.UP * 0.35
	var mid: Vector3 = chest.lerp(ball, 0.5)
	return {
		# Low and close in front of the hitter, looking up: the swing fills the frame.
		"hero_low": [Vector3(p.x + side * 1.1, 0.32, p.z - s * 2.3), mid + Vector3.UP * 0.15, 55.0, 1.0, 0, chest, null],
		# From the open side, a little higher and wider: hitter plus the place.
		"hero_wide": [Vector3(p.x - side * 1.8, 0.6, p.z - s * 1.6), mid, 70.0, 1.0, 1, chest, null],
		# Over the hitter's shoulder down the court: the shot and who has to deal with it.
		"shoulder": [Vector3(p.x - side * 0.7, 1.95, p.z + s * 2.4), Vector3(ball.x + fly.x * 4.0, 0.8, ball.z + fly.z * 4.0), 50.0, 1.0, 1, chest, null],
		# Long lens from the net post: the hitter picked out, everything else melts.
		"post_tele": [Vector3(-side * 3.6, 0.9, -s * 0.5), mid, 40.0, 3.0, 0, chest, null],
		# The same long lens raised over the net tape: paddle, ball and face, nothing in the way.
		"post_high": [Vector3(-side * 3.6, 1.45, -s * 0.5), mid + Vector3.UP * 0.2, 40.0, 3.0, 0, chest, null],
		# Long lens from the sideline: flat, compressed side view of the swing.
		"side_tele": [Vector3(side * 11.0, 1.1, p.z - s * 1.0), mid, 30.0, 2.6, 0, chest, null],
		# In the ball's path, looking back at the hitter: the ball big and sharp, coming at the lens.
		"ball_eye": [ball + fly * 1.3 + Vector3(-side * 0.25, 0.12, 0), ball.lerp(chest, 0.6), 60.0, 1.0, 0, ball, null],
		# From behind the other baseline, long: the whole point stacked up, focus on the hitter.
		"baseline_tele": [Vector3(p.x * 0.4 + side * 1.5, 1.6, -s * 12.0), mid, 30.0, 2.2, 1, chest, null],
	}

## What the players see: camera at a player's eyes, that player drawn as eye-view arms.
func _pov_recipes(hitter: Node3D, receiver: Node3D, ball: Vector3, fly: Vector3) -> Dictionary:
	var out: Dictionary = {}
	var he: Vector3 = _eye(hitter)
	var h_chest: Vector3 = hitter.global_position + Vector3.UP * 0.35
	# The hitter's own view down the line of the shot.
	out["pov_hitter"] = [he + fly * 0.1, ball + fly * 3.0, 85.0, 1.0, 3, ball + fly * 3.0, hitter]
	if receiver != null:
		var re: Vector3 = _eye(receiver)
		var to_ball: Vector3 = (ball - re).normalized()
		var r_chest: Vector3 = receiver.global_position + Vector3.UP * 0.35
		# The receiver's eyes on the ball, wide like the eye: arms and paddle in the frame.
		out["pov_receiver"] = [re + to_ball * 0.1, ball.lerp(h_chest, 0.25), 85.0, 1.0, 2, ball, receiver]
		# Same eyes, longer lens, wide open: the ball sharp, the hitter soft behind it.
		out["pov_receiver_tele"] = [re + to_ball * 0.1, ball.lerp(h_chest, 0.5), 60.0, 1.6, 0, ball, receiver]
		# ... and focused past the ball on who hit it.
		out["pov_receiver_far"] = [re + to_ball * 0.1, h_chest, 60.0, 2.2, 0, h_chest, receiver]
		# The hitter watching the ball go to the receiver.
		out["pov_hitter_watch"] = [he + fly * 0.1, r_chest, 60.0, 1.8, 1, r_chest, hitter]
		var mate := _partner(receiver)
		if mate != null:
			var me: Vector3 = _eye(mate)
			# The receiver's partner glancing across at them as the ball arrives.
			out["pov_partner"] = [me + (r_chest - me).normalized() * 0.1, r_chest.lerp(ball, 0.4), 70.0, 1.0, 1, r_chest, mate]
	return out

## The barangay around the court (hall end at -z, pandesal end at +z).
func _scenery_recipes() -> Dictionary:
	var court := Vector3(0, 0.9, 0)
	return {
		"sc_balcony": [Vector3(-8.6, 4.4, -16.6), Vector3(0, 0.3, -1.5), 55.0, 1.0, 5, court, null],
		"sc_crowd_seats": [Vector3(-0.6, 1.45, -15.4), Vector3(0, 1.0, -2.0), 45.0, 1.0, 1, Vector3(-0.6, 1.0, -13.2), null],
		"sc_crowd_match": [Vector3(-0.6, 1.45, -15.4), Vector3(0, 1.0, -2.0), 45.0, 1.4, 2, Vector3(0, 1.0, -3.0), null],
		"sc_tricycle": [Vector3(9.8, 0.9, -13.4), Vector3(7.4, 0.8, -16.2), 50.0, 1.0, 2, Vector3(7.4, 0.8, -16.2), null],
		"sc_tricycle_match": [Vector3(9.6, 1.0, -17.6), Vector3(1.0, 1.0, -4.0), 50.0, 1.0, 0, Vector3(7.6, 0.8, -16.0), null],
		"sc_hall_flag": [Vector3(2.6, 0.35, -9.0), Vector3(0.2, 5.0, -19.0), 70.0, 1.0, 6, Vector3(0.4, 4.0, -19.0), null],
		"sc_scorer": [Vector3(9.2, 1.3, -1.4), Vector3(6.75, 0.95, -3.2), 45.0, 1.0, 1, Vector3(6.75, 0.95, -3.2), null],
		"sc_scorer_match": [Vector3(8.9, 1.5, -4.9), Vector3(0, 0.9, 1.0), 45.0, 1.0, 0, Vector3(6.75, 0.95, -3.2), null],
		"sc_dog": [Vector3(5.1, 0.3, -12.1), Vector3(3.9, 0.35, -13.5), 40.0, 1.5, 0, Vector3(3.9, 0.35, -13.5), null],
		"sc_wide_hall": [Vector3(11.5, 6.5, 15.0), Vector3(-1.0, 1.0, -8.0), 55.0, 1.0, 7, court, null],
		"sc_wide_pandesal": [Vector3(-11.5, 6.5, -15.0), Vector3(1.0, 1.0, 8.0), 55.0, 1.0, 7, court, null],
		"sc_pandesal": [Vector3(0.0, 1.6, 9.0), Vector3(0, 2.0, 20.0), 60.0, 1.0, 5, Vector3(0, 2.0, 18.0), null],
		"sc_net_low": [Vector3(-4.8, 0.45, 0.9), Vector3(3.0, 1.1, -5.0), 55.0, 1.0, 1, Vector3(-3.3, 0.9, 0.0), null],
		"sc_banderitas": [Vector3(0.0, 0.3, 3.0), Vector3(0.0, 6.0, -12.0), 80.0, 1.0, 6, Vector3(0, 4.0, -8.0), null],
		"sc_queue": [Vector3(-9.2, 1.3, -3.6), Vector3(-6.55, 0.9, -7.0), 50.0, 1.0, 1, Vector3(-6.55, 0.9, -7.0), null],
		"sc_top": [Vector3(0, 15.5, 0.4), Vector3(0, 0, 0), 60.0, 1.0, 8, court, null],
	}

func _shoot(kind: String, hitter: Node3D, receiver: Node3D) -> void:
	_count += 1
	var pc: Node = root.get_node("PauseController")
	pc.open()
	await _wait(0.2)
	var menu = pc._menu
	menu._on_photo_mode()
	var photo = menu._photo_mode
	if not is_instance_valid(photo):
		pc.close(); _busy = false; return
	await _wait(0.5)   # the distance map check takes a few frames
	photo._hide_panel()
	var ball: Vector3 = _game.ball.global_position
	var vel: Vector3 = _game.ball.linear_velocity
	var s: float = 1.0 if hitter.global_position.z >= 0.0 else -1.0
	var fly: Vector3 = vel.normalized() if vel.length() > 0.5 else Vector3(0, 0, -s)
	if receiver == null: receiver = _receiver(hitter, ball, fly)
	var recipes: Dictionary = _pov_recipes(hitter, receiver, ball, fly) if _kinds.is_empty() else {}
	if not _kinds.is_empty():
		# Smash study: the body from the side and from the net, whole figure in frame.
		var hp: Vector3 = hitter.global_position
		var body: Vector3 = hp + Vector3.UP * 1.25
		var fwd: Vector3 = hitter._get_forward_axis()
		var fh: Vector3 = hitter._get_forehand_axis()
		recipes["side_full"] = [hp + fh * 5.5 + Vector3.UP * 1.1, body, 40.0, 1.6, 3, hp, null]
		recipes["three_quarter"] = [hp + fh * 2.4 + fwd * 2.8 + Vector3.UP * 1.4, body + Vector3.UP * 0.1, 50.0, 1.4, 2, hp, null]
		recipes["front_low"] = [hp + fwd * 3.0 - fh * 0.9 + Vector3.UP * 0.45, body + Vector3.UP * 0.3, 50.0, 1.3, 2, hp, null]
		recipes["back_full"] = [hp - fwd * 4.8 - fh * 1.0 + Vector3.UP * 1.6, body + Vector3.UP * 0.2, 40.0, 1.6, 3, hp, null]
		if kind in ["smash", "after", "finish", "air"]:
			var act: Dictionary = _action_recipes(hitter, ball, fly)
			for name in ["hero_low", "shoulder", "ball_eye", "baseline_tele"]: recipes[name] = act[name]
		if kind in ["after", "finish"]:
			# Hitter and the ball in flight in one frame: from the side of the flight line, and from behind the hitter.
			var mid: Vector3 = (body + ball) * 0.5
			var flat: Vector3 = Vector3(fly.x, 0, fly.z).normalized()
			var perp: Vector3 = flat.cross(Vector3.UP)
			var span: float = maxf(body.distance_to(ball), 2.0)
			recipes["flight_side"] = [mid + perp * (span * 1.5 + 2.5) + Vector3.UP * 0.2, mid, 62.0, 1.0, 4, hp, null]
			recipes["flight_behind"] = [hp - flat * 3.4 + perp * 1.4 + Vector3.UP * 2.0, mid + Vector3.DOWN * 0.2, 60.0, 1.0, 4, hp, null]
	elif kind != "incoming": recipes.merge(_action_recipes(hitter, ball, fly))
	elif receiver != null:
		# The receiver about to hit, seen from the ball's side.
		var rp: Vector3 = receiver.global_position
		var rs: float = 1.0 if rp.z >= 0.0 else -1.0
		recipes["recv_front"] = [Vector3(ball.x * 0.5 + rp.x * 0.5 + 0.9, 0.4, rp.z - rs * 2.6), (rp + Vector3.UP * 0.35).lerp(ball, 0.4), 55.0, 1.0, 0, rp, null]
		recipes["recv_side"] = [Vector3(rp.x + (4.5 if rp.x < 0.0 else -4.5), 0.8, rp.z - rs * 0.6), (rp + Vector3.UP * 0.35).lerp(ball, 0.4), 40.0, 1.6, 0, rp, null]
	if _scenery_left > 0 and _count >= 2 and _kinds.is_empty():
		_scenery_left -= 1
		recipes.merge(_scenery_recipes())
	for name in recipes:
		var r: Array = recipes[name]
		var at: Vector3 = Vector3(r[0]).clamp(photo.BOUNDS_MIN, photo.BOUNDS_MAX)
		var cam: Camera3D = photo._camera
		for q in _game.get_players():
			var rig := _rig(q)
			if rig != null: rig.first_person = (q == r[6])
		cam.global_transform = Transform3D(Basis.IDENTITY, at).looking_at(r[1], Vector3.UP)
		photo._read_angles()
		photo._fov_slider.value = r[2]
		photo._zoom_slider.value = r[3]
		photo._apply_fov()
		photo._aperture_slider.value = r[4]
		var focus: float = (Vector3(r[5]) - at).dot(-cam.global_basis.z)
		photo._focus_slider.value = clampf(focus, photo.FOCUS_MIN, photo.FOCUS_MAX)
		photo._update_lens()
		photo._dirty = true
		await _wait(0.65)   # settle: full-quality blur
		var file := "%02d_%s_%s.png" % [_count, kind, name]
		root.get_texture().get_image().save_png(_out.path_join(file))
		_log.store_line(JSON.stringify({"file": file, "kind": kind, "recipe": name, "actor": hitter.get_actor_id(),
			"tick": Engine.get_physics_frames(), "ball": [snappedf(ball.x, 0.01), snappedf(ball.y, 0.01), snappedf(ball.z, 0.01)],
			"speed_mph": snappedf(vel.length() * 2.23694, 0.1), "cam": [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)],
			"fov": r[2], "zoom": r[3], "f": F_STOPS[r[4]], "focus_m": snappedf(photo._focus_slider.value, 0.1), "map": photo._map_ok,
			"ball_from_hitter_m": snappedf(ball.distance_to(hitter.global_position + Vector3.UP * 1.25), 0.01), "state": int(_game.game_state),
			"posture": int(hitter.paddle_posture), "jumping": bool(hitter.is_jumping), "up": snappedf(hitter.global_position.y - hitter.ground_y, 0.01),
			"jump_style": int(hitter.jump_style), "staged_jump": _force_jump, "feet_y": [snappedf(hitter.leg_ik.right_foot_smooth.y, 0.01), snappedf(hitter.leg_ik.left_foot_smooth.y, 0.01)] if hitter.leg_ik else []}))
		_log.flush()
	for q in _game.get_players():
		var rig := _rig(q)
		if rig != null: rig.first_person = false
	photo.finish()
	await _wait(0.2)
	pc.close()
	await _wait(0.3)
	_busy = false
