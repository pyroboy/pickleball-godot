extends Node
## Special shots (GAME_MECHANICS_PLAN change 8), human side:
##  - Erne marker: while the incoming flight allows an Erne for you and there is time
##    to spare (jump prep + 0.3 s), a ring shows where you land outside the sideline.
##    HIT then takes the Erne (human_contact_controller, game.erne_chance_live). The
##    marker says the shot is possible, never that it is safe.
##  - Slow-motion beat for your team (you and partner): ~0.4 s at 0.35x once the jump is
##    committed, ending at contact with a short visual freeze. At most one per rally.
##    Own TimeScale source. Never in --autoplay (the all-AI bench), so a benched rally
##    cannot change. Opponent Ernes get no slow motion (their shot name still shows).
const Tuning = preload("res://scripts/gameplay_tuning.gd")
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")
const SLOW_ID := "special_shot"
const SLOW_SCALE := 0.35
const SLOW_SECONDS := 0.4          # real time
const CONTACT_FREEZE := 0.08
const SPARE_SECONDS := 0.3
const MARKER_COLOR := Color("ff7ad9")

var _game
var _marker: MeshInstance3D
var _label: Label3D
var _tick := 0
var _slow_until_usec := 0
var _slow_used := false
var _was_active: Dictionary = {}

func setup(game) -> void:
	_game = game
	if not Tuning.ERNE_ON or RuntimePolicy.autoplay:
		set_process(false); set_physics_process(false)
		return
	_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.26; ring.outer_radius = 0.34; ring.rings = 24; ring.ring_segments = 6
	_marker.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = MARKER_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker.material_override = mat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)
	_label = Label3D.new()
	_label.text = "ERNE"
	_label.font_size = 48; _label.pixel_size = 0.006
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = MARKER_COLOR; _label.outline_size = 8
	_label.no_depth_test = true
	_label.visible = false
	add_child(_label)

func _exit_tree() -> void:
	if _slow_until_usec > 0: TimeScale.release(SLOW_ID)

func _human():
	return _game.get_human_actor() if _game != null and _game.has_method("get_human_actor") else null

func _physics_process(_delta: float) -> void:
	_tick += 1
	var live := false
	var me = _human()
	var ball = _game.ball if _game != null else null
	var playing: bool = _game != null and _game.game_state == _game.GameState.PLAYING
	if not playing: _slow_used = false
	if playing and me != null and ball != null and me.erne_action != null and not me.erne_action.active:
		if _tick % 3 == 0 or _marker.visible:
			if me.erne_action.eligible(ball):
				var t0 := Time.get_ticks_usec()
				var plan: Dictionary = me.erne_action.choose_plan(ball)
				PerfMonitor.record("special.erne_marker", Time.get_ticks_usec() - t0)
				if not plan.is_empty() and float(plan.time) >= me.erne_action.PREPARE_TIME + SPARE_SECONDS:
					live = true
					var at: Vector3 = plan.landing
					_marker.global_position = Vector3(at.x, PickleballConstants.FLOOR_Y + 0.01, at.z)
					_label.global_position = Vector3(at.x, PickleballConstants.FLOOR_Y + 0.55, at.z)
		else:
			live = _marker.visible
	_game.erne_chance_live = live
	_marker.visible = live
	_label.visible = live

func _process(_delta: float) -> void:
	if _game == null: return
	var me = _human()
	var now := Time.get_ticks_usec()
	for p in _game.get_players():
		if p.erne_action == null: continue
		var active: bool = p.erne_action.active
		var was: bool = bool(_was_active.get(p.get_actor_id(), false))
		_was_active[p.get_actor_id()] = active
		var mine: bool = me != null and p.team_id == me.team_id
		if mine and active and not was and not _slow_used:
			_slow_used = true
			_slow_until_usec = now + int(SLOW_SECONDS * 1000000.0)
			TimeScale.request_slowmo(SLOW_ID, SLOW_SCALE)
			PerfMonitor.note("special_moment", {"kind": "ERNE", "actor": p.get_actor_id(), "slowmo": true})
		elif mine and was and not active and _slow_until_usec > 0:
			_end_slow(true)
	if _slow_until_usec > 0 and now >= _slow_until_usec: _end_slow(false)

func _end_slow(contact: bool) -> void:
	_slow_until_usec = 0
	TimeScale.release(SLOW_ID)
	if contact: TimeScale.request_hitstop(CONTACT_FREEZE)
