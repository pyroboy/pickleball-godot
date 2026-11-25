extends Node
## Rally replays: what a rally looked like from the serve to the point, so photo mode can play
## it back and scrub through it (scripts/ui/photo_mode.gd, RALLIES). Visual only.
##
## One record per physics tick, taken after everything else in the tick: for each player the
## world transform of the joints its pixel cards and paddle are drawn from, and the ball's
## place, motion blur and spin. Records are only taken while a rally is on, and only while
## a rally could be saved at all (REC on, or the save question on): outside that this node
## reads one number a tick. (Until 2026-11-26 it also kept the last 3 seconds at all times
## for a rewind in photo mode; the user removed that.)
##
## Showing a record never touches gameplay bodies: the players' roots and the ball's body stay
## where they are. Only the joints under each player are placed (parents before children), the
## drawn ball is moved through a meta the ball's drawing honours, and at the end every joint
## gets back exactly the local transform it had when photo mode opened.
var game: Node
var _players: Array = []
var _joints: Array = []     # per player: Array[Node3D], parents before children
var _records: Array = []    # the saved rally being viewed, oldest first: [per player Array[Transform3D], ball position, blur motion, hole turn]
var _present: Array = []    # per player: the joints' local transforms when photo mode opened
var _present_ball: Array = []
var _open := false

func setup(p_game: Node) -> void:
	game = p_game
	name = "PhotoHistory"
	process_physics_priority = 100000   # after every pose of the tick is final

## The C++ recorder (native/src/pickle_replay.cpp, class PickleReplay), when the library is in
## this build and the `native_math` switch is on. It keeps the rally as one flat block in the
## file's own layout, so a tick is one call, a save is one write on a worker thread, and
## playback places the joints straight from the block. The script paths below are its twin
## and its fallback; both write and read the same file.
var _native = null

func count() -> int:
	return _native.viewing_ticks() if _native != null else _records.size()

func _refresh_players() -> void:
	var found: Array = []
	for child in game.get_children():
		if child.get("body_pivot") != null and child.get("paddle_node") != null: found.append(child)
	if found == _players and _joints.size() == found.size(): return
	_players = found
	_joints.clear()
	_rally = []
	_rally_live = false
	for player in _players:
		var list: Array = []
		var rig: Node = _rig(player)
		for extra in [player.body_pivot, player.body_pivot.get_node_or_null("TorsoMesh"), player.body_pivot.get_node_or_null("TorsoMesh/HeadMesh"), player.paddle_node]:
			if extra is Node3D and not list.has(extra): list.append(extra)
		if rig != null:
			for card in rig.get("_cards"):
				for key in ["a", "b", "prev", "root"]:
					var joint = card.get(key)
					if joint is Node3D and not list.has(joint) and player.is_ancestor_of(joint): list.append(joint)
		list.sort_custom(func(x: Node3D, y: Node3D) -> bool: return x.get_path().get_name_count() < y.get_path().get_name_count())
		_joints.append(list)
	if NativeMath.lib() != null and ClassDB.class_exists(&"PickleReplay"):
		if _native == null: _native = ClassDB.instantiate(&"PickleReplay")
		var flat: Array = []
		var counts := PackedInt32Array()
		for list in _joints:
			counts.append((list as Array).size())
			flat.append_array(list)
		_native.setup(flat, counts, int(RALLY_MAX_SECONDS * Engine.physics_ticks_per_second))
	else:
		_native = null

func _rig(player: Node) -> Node:
	return game.get_node_or_null("PixelCards_%d" % player.get_instance_id())

func _skin(player: Node) -> Node:
	for child in game.get_children():
		if child.get("_blur_parts") != null and child.get("_player") == player: return child
	return null

func _physics_process(_delta: float) -> void:
	var began := Time.get_ticks_usec()
	_record()
	PerfMonitor.record("photo.history", Time.get_ticks_usec() - began)

var _wanted := true   # a rally could be saved: REC on, or the save question on

func _record() -> void:
	if game == null or _open or game.get("ball") == null: return
	var state: int = int(game.game_state)
	if Engine.get_physics_frames() % 30 == 0:
		var settings: Node = get_node_or_null("/root/Settings")
		_wanted = settings == null or not settings.has_method("get_value") or bool(settings.call("get_value", "video.rally_record", false)) or bool(settings.call("get_value", "video.rally_prompt", true))
	# Nothing is read from the players unless a rally is on (or its serve is starting now).
	var starting: bool = state == 1 and _last_state != 1 and _last_state != 2
	if not _wanted or not (_rally_live or starting):
		if not _wanted: _rally_live = false
		_last_state = state
		return
	# The joint lists are looked at again at each serve (a new match line-up), not every second.
	if starting or _players.is_empty(): _refresh_players()
	if _players.is_empty(): return
	if _native != null:
		var live_ball = game.ball
		var live_materials: Array = live_ball.get("blur_materials") if live_ball.get("blur_materials") != null else []
		var live_motion = (live_materials[0] as ShaderMaterial).get_shader_parameter("motion") if not live_materials.is_empty() else null
		var live_turn = (live_materials[0] as ShaderMaterial).get_shader_parameter("turn") if not live_materials.is_empty() else null
		_track_native(state, live_ball.global_position, live_motion if live_motion is Vector3 else Vector3.ZERO, live_turn if live_turn is Basis else Basis.IDENTITY)
		return
	var poses: Array = []
	for index in _players.size():
		if not is_instance_valid(_players[index]):
			_players.clear()
			return
		var row: Array[Transform3D] = []
		for joint: Node3D in _joints[index]: row.append(joint.global_transform)
		poses.append(row)
	var ball = game.ball
	var materials: Array = ball.get("blur_materials") if ball.get("blur_materials") != null else []
	var motion: Vector3 = (materials[0] as ShaderMaterial).get_shader_parameter("motion") if not materials.is_empty() and (materials[0] as ShaderMaterial).get_shader_parameter("motion") != null else Vector3.ZERO
	var turn = (materials[0] as ShaderMaterial).get_shader_parameter("turn") if not materials.is_empty() else null
	_track_rally([poses, ball.global_position, motion, turn])

# ---------------------------------------------------------------- rally replays
## A rally is kept from the start of the serve to a second after the point: the same records
## as above, for as long as the rally lasts (the newest RALLY_MAX_SECONDS of it). When it ends
## `rally_ready` fires; save_last_rally() writes it to a file (the HUD asks, or the REC button
## saves by itself). The RALLY_KEEP newest files are kept; photo mode lists and plays them.
signal rally_ready(seconds: float)
const RALLY_MAX_SECONDS := 60.0
const RALLY_TAIL_TICKS := 30
const RALLY_MIN_TICKS := 45        # shorter than 1.5 s (a serve fault) is not worth a save
const RALLY_KEEP := 10
const RALLY_DIR := "user://rallies"
const RALLY_VERSION := 1
var _rally: Array = []
var _rally_live := false
var _rally_tail := -1
var _last_rally: Array = []        # the rally that just ended, until it is saved or the next one ends
var _last_state := -1
var viewing_saved := false

func _track_rally(record: Array) -> void:
	var state: int = int(game.game_state)
	if state == 1 and _last_state != 1 and _last_state != 2:   # the serve begins
		_rally = []
		_rally_live = true
		_rally_tail = -1
	elif state == 0 and _rally_live and _rally_tail < 0: _rally_live = false   # reset before any point
	if _rally_live:
		_rally.append(record)
		if _rally.size() > int(RALLY_MAX_SECONDS * Engine.physics_ticks_per_second): _rally.pop_front()
		if state == 3 and _rally_tail < 0: _rally_tail = RALLY_TAIL_TICKS
		if _rally_tail >= 0:
			_rally_tail -= 1
			if _rally_tail < 0:
				_rally_live = false
				_last_rally = _rally
				_rally = []
				if _last_rally.size() >= RALLY_MIN_TICKS: rally_ready.emit(float(_last_rally.size()) / float(Engine.physics_ticks_per_second))
	_last_state = state

## _track_rally for the C++ recorder: the same rally rules, the records kept on its side.
func _track_native(state: int, at: Vector3, motion: Vector3, turn: Basis) -> void:
	if state == 1 and _last_state != 1 and _last_state != 2:   # the serve begins
		_native.begin()
		_rally_live = true
		_rally_tail = -1
	elif state == 0 and _rally_live and _rally_tail < 0: _rally_live = false   # reset before any point
	if _rally_live:
		if not _native.record(at, motion, turn):
			_players.clear()   # a joint is gone: the lists are set up again at the next serve
			_rally_live = false
		else:
			if state == 3 and _rally_tail < 0: _rally_tail = RALLY_TAIL_TICKS
			if _rally_tail >= 0:
				_rally_tail -= 1
				if _rally_tail < 0:
					_rally_live = false
					var ticks: int = _native.recorded()
					_native.finish()
					if ticks >= RALLY_MIN_TICKS: rally_ready.emit(float(ticks) / float(Engine.physics_ticks_per_second))
					else: _native.drop_finished()
	_last_state = state

func has_unsaved_rally() -> bool:
	if _native != null: return _native.finished_ticks() >= RALLY_MIN_TICKS
	return _last_rally.size() >= RALLY_MIN_TICKS

## Writes the rally that just ended (compressed; 12 numbers per joint per tick, plus the ball).
func save_last_rally() -> bool:
	if not has_unsaved_rally(): return false
	DirAccess.make_dir_recursive_absolute(RALLY_DIR)
	if _native != null:
		# Room for the new file first; then the write (and its compression) runs on a worker
		# thread, so the match never waits for it.
		var kept: Array = _rally_files()
		for extra in range(RALLY_KEEP - 1, kept.size()): DirAccess.remove_absolute("%s/%s" % [RALLY_DIR, kept[extra]])
		var path: String = "%s/%d.rally" % [RALLY_DIR, int(Time.get_unix_time_from_system())]
		WorkerThreadPool.add_task(Callable(_native, "save_finished").bind(path, Engine.physics_ticks_per_second))
		return true
	var file := FileAccess.open_compressed("%s/%d.rally" % [RALLY_DIR, int(Time.get_unix_time_from_system())], FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null: return false
	var rows: Array = _last_rally[0][0]
	file.store_32(RALLY_VERSION)
	file.store_32(Engine.physics_ticks_per_second)
	file.store_32(_last_rally.size())
	file.store_32(rows.size())
	for row in rows: file.store_32((row as Array).size())
	for record in _last_rally:
		var numbers := PackedFloat32Array()
		for row in record[0]:
			for xf: Transform3D in row:
				numbers.append_array(PackedFloat32Array([xf.basis.x.x, xf.basis.x.y, xf.basis.x.z, xf.basis.y.x, xf.basis.y.y, xf.basis.y.z, xf.basis.z.x, xf.basis.z.y, xf.basis.z.z, xf.origin.x, xf.origin.y, xf.origin.z]))
		var at: Vector3 = record[1]
		var motion: Vector3 = record[2] if record[2] is Vector3 else Vector3.ZERO
		var turn: Basis = record[3] if record[3] is Basis else Basis.IDENTITY
		numbers.append_array(PackedFloat32Array([at.x, at.y, at.z, motion.x, motion.y, motion.z, turn.x.x, turn.x.y, turn.x.z, turn.y.x, turn.y.y, turn.y.z, turn.z.x, turn.z.y, turn.z.z]))
		file.store_buffer(numbers.to_byte_array())
	file.close()
	_last_rally = []
	var saved: Array = _rally_files()
	for extra in range(RALLY_KEEP, saved.size()): DirAccess.remove_absolute("%s/%s" % [RALLY_DIR, saved[extra]])
	return true

func _rally_files() -> Array:
	var names: Array = []
	var dir := DirAccess.open(RALLY_DIR)
	if dir == null: return names
	for name in dir.get_files():
		if name.ends_with(".rally"): names.append(name)
	names.sort()
	names.reverse()   # newest first (the name is the save time)
	return names

## Saved rallies, newest first: {path, when (unix seconds), seconds, fits (same players and joints as this match)}.
func saved_rallies() -> Array:
	var out: Array = []
	for name in _rally_files():
		var path: String = "%s/%s" % [RALLY_DIR, name]
		var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		if file == null: continue
		var version: int = file.get_32()
		var rate: int = maxi(file.get_32(), 1)
		var ticks: int = file.get_32()
		var players: int = file.get_32()
		var fits: bool = version == RALLY_VERSION and players == _joints.size()
		for index in players:
			var joints: int = file.get_32()
			if index >= _joints.size() or joints != (_joints[index] as Array).size(): fits = false
		file.close()
		out.append({"path": path, "when": int(name.get_basename()), "seconds": float(ticks) / float(rate), "fits": fits})
	return out

func _load_rally(path: String) -> Array:
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null: return []
	if file.get_32() != RALLY_VERSION: return []
	file.get_32()
	var ticks: int = file.get_32()
	var players: int = file.get_32()
	var counts: Array = []
	var joints_total := 0
	for index in players:
		counts.append(file.get_32())
		joints_total += int(counts[index])
	if players != _joints.size(): return []
	for index in players:
		if int(counts[index]) != (_joints[index] as Array).size(): return []
	var out: Array = []
	var per_record: int = joints_total * 12 + 15
	for tick in ticks:
		var numbers: PackedFloat32Array = file.get_buffer(per_record * 4).to_float32_array()
		if numbers.size() != per_record: break
		var poses: Array = []
		var n := 0
		for index in players:
			var row: Array[Transform3D] = []
			for joint in int(counts[index]):
				row.append(Transform3D(Basis(Vector3(numbers[n], numbers[n + 1], numbers[n + 2]), Vector3(numbers[n + 3], numbers[n + 4], numbers[n + 5]), Vector3(numbers[n + 6], numbers[n + 7], numbers[n + 8])), Vector3(numbers[n + 9], numbers[n + 10], numbers[n + 11])))
				n += 12
			poses.append(row)
		out.append([poses, Vector3(numbers[n], numbers[n + 1], numbers[n + 2]), Vector3(numbers[n + 3], numbers[n + 4], numbers[n + 5]),
			Basis(Vector3(numbers[n + 6], numbers[n + 7], numbers[n + 8]), Vector3(numbers[n + 9], numbers[n + 10], numbers[n + 11]), Vector3(numbers[n + 12], numbers[n + 13], numbers[n + 14]))])
	file.close()
	return out

## Photo mode: load a saved rally to scrub and play ("" = none: back to the paused moment).
func view(path: String) -> bool:
	if not _open: return false
	if path == "":
		show_present()
		return true
	if _native != null:
		if _native.load(path) <= 0: return false
		viewing_saved = true
		return true
	var loaded: Array = _load_rally(path)
	if loaded.is_empty(): return false
	_records = loaded
	viewing_saved = true
	return true

## Photo mode opened: remember exactly how things are, to put them back.
func begin() -> void:
	_open = true
	_records = []
	viewing_saved = false
	if _players.is_empty(): _refresh_players()
	_present.clear()
	for index in _players.size():
		var row: Array[Transform3D] = []
		for joint: Node3D in _joints[index]: row.append(joint.transform)
		_present.append(row)
	var ball = game.ball
	var materials: Array = ball.get("blur_materials") if ball.get("blur_materials") != null else []
	_present_ball = [(materials[0] as ShaderMaterial).get_shader_parameter("motion") if not materials.is_empty() else null, (materials[0] as ShaderMaterial).get_shader_parameter("turn") if not materials.is_empty() else null]

## Show the loaded rally `back` ticks before its end (0 = its last tick).
func show_back(back: int) -> void:
	var total: int = count()
	if not _open or total == 0: return
	var at: int = clampi(total - 1 - back, 0, total - 1)
	var rigs: Array = []
	var skins: Array = []
	for player in _players:
		rigs.append(_rig(player))
		skins.append(_skin(player))
	# The two ticks before it are drawn first, as ticks, so the cards carry that moment's motion
	# (their motion blur and its shadow trail) and the paddle has the place it came from.
	var paddle_before: Array = []
	for step in [at - 2, at - 1, at]:
		if step == at:
			paddle_before.clear()
			for player in _players: paddle_before.append((player.paddle_node as Node3D).global_transform)
		if _native != null:
			_native.apply(clampi(step, 0, total - 1))
		else:
			var record: Array = _records[clampi(step, 0, total - 1)]
			for index in _players.size():
				var joints: Array = _joints[index]
				var row: Array = record[0][index]
				for j in mini(joints.size(), row.size()): (joints[j] as Node3D).global_transform = row[j]
		for rig in rigs:
			if rig == null: continue
			rig.photo_tick = true
			rig._draw_cards(1.0 / float(Engine.physics_ticks_per_second))
			rig.photo_tick = false
	for index in _players.size():
		if skins[index] != null and index < paddle_before.size(): skins[index].photo_sweep(paddle_before[index], (_players[index].paddle_node as Node3D).global_transform)
	if _native != null:
		var b: PackedFloat32Array = _native.ball(at)
		if b.size() == 15: _show_ball(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), Basis(Vector3(b[6], b[7], b[8]), Vector3(b[9], b[10], b[11]), Vector3(b[12], b[13], b[14])), true)
	else:
		var shown: Array = _records[at]
		_show_ball(shown[1], shown[2], shown[3], true)

func _show_ball(position: Vector3, motion, turn, moved: bool) -> void:
	var ball = game.ball
	if moved: ball.set_meta("photo_origin", position)
	elif ball.has_meta("photo_origin"): ball.remove_meta("photo_origin")
	for child in ball.get_children():
		if child.get("_parts") != null and child.has_method("_process"): child._process(0.0)   # the drawn ball (ball_bounce_snap.gd)
	var materials: Array = ball.get("blur_materials") if ball.get("blur_materials") != null else []
	for material: ShaderMaterial in materials:
		if motion != null: material.set_shader_parameter("motion", motion)
	if not materials.is_empty() and turn != null: (materials[0] as ShaderMaterial).set_shader_parameter("turn", turn)

## Back to the moment photo mode opened at: every joint exactly as it was, the ball where it
## is. A rally that was shown left its own motion in the cards, so their blur is switched off
## until play resumes and the next tick writes the real one.
func show_present() -> void:
	var shown: bool = viewing_saved
	_records = []
	if _native != null: _native.close_view()
	viewing_saved = false
	for index in mini(_players.size(), _present.size()):
		var joints: Array = _joints[index]
		for j in mini(joints.size(), _present[index].size()): (joints[j] as Node3D).transform = _present[index][j]
	if _present_ball.size() == 2: _show_ball(game.ball.global_position, _present_ball[0], _present_ball[1], false)
	if not shown: return
	for player in _players:
		var rig: Node = _rig(player)
		if rig != null:
			rig._card_param("smear", 0.0)
			rig._smear_shown = 0.0
			rig._set_soft_pass(false)
			rig._draw_cards(0.0)
		var skin: Node = _skin(player)
		if skin != null and skin.get("_blur_root") != null: (skin.get("_blur_root") as Node3D).visible = false

## Photo mode closed.
func end() -> void:
	if not _open: return
	show_present()
	_open = false
