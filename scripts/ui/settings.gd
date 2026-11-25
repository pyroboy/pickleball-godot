extends Node
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")























signal settings_changed(key: String, value: Variant)

const CONFIG_PATH: String = "user://settings.cfg"

const DEFAULTS: Dictionary = {
	"video.fov": 60.0,
	"video.court_view_swapped": false,   # pause menu "Court view": which end's scenery faces the camera
	"video.camera_mode": 0, 
	"video.shake": 1.0, 
	"video.hitstop": true, 
	"video.particle_density": 2, 
	"video.shadow_quality": 1, 
	"video.fps_mode": 0,   # 0 = 60 fps, 1 = adaptive (60 while the device holds it; the phone default), 2 = 30 fps
	"video.focus_dim": 0.14,
	"video.focus_blur": 0.65,
	"video.focus_preview": true,
	"video.focus_arc_style": 0,
	"audio.master": 0.9, 
	"audio.sfx": 1.0, 
	"audio.music": 0.7, 
	"audio.ambience": 0.55, 
	"audio.footsteps": 0.75, 
	"gameplay.difficulty": 0,
	"gameplay.point_transition": 0, # Physical pickup remains the default.
	"gameplay.ai_style_partner": 0,
	"gameplay.ai_style_opponent_one": 1,
	"gameplay.ai_style_opponent_two": 2,
	"gameplay.execution_accuracy": 1, 
	"gameplay.reaction_delay": 0.0, 
	"gameplay.reaction_button": true, 
	"gameplay.timing_vibration": true, 
	"gameplay.aim_focus_seconds": 3.0,
	"gameplay.movement_guide": false,
	"gameplay.stamina_tips": true,
	"video.blur_ball": true,       # motion blur parts (strength: video.motion_smear)
	"video.blur_paddle": true,
	"video.blur_body": true,
	"video.ball_holes": true,      # pickleball holes on the ball, rolling (shaders/ball_body.gdshader)
	"video.player_shading": true,  # sun bands and rim on the players (shaders/pixel_card.gdshader `shading`)
	"video.vignette": true,        # graphics/pixel_post.gd
	"video.color_grade": true,
	"video.rally_record": false,   # REC on the match screen: save every rally (the 10 newest are kept)
	"video.rally_prompt": true,    # REC off: ask to save after each point
	"video.photo_button": true,    # the quick PHOTO button on the match screen (ui/hud.gd)
	"video.resolution": 0,   # 3D render resolution: 0 default, 1 = 1/3, 2 = 1/2, 3 = 2/3, 4 = full (graphics/pixel_post.gd)
	"video.motion_smear": 1.0,   # motion blur strength, 0 = off: the stretched ball (fx/ball_trail.gd) and the smear behind fast limbs (pixel_card.gdshader)
	"gameplay.stamina_bars": false,   # bars and numbers over the players; off = only the sweat shows
	"beta_debug.reach_rings": false, 
	"beta_debug.preparation_blocks": false, 
}

const MOBILE_DEFAULTS: = {"video.shadow_quality": 0, "video.particle_density": 1, "video.shake": 0.5, "video.fps_mode": 1}
const FOCUS_VISUAL_KEYS: Array[String] = ["video.focus_dim", "video.focus_blur", "video.focus_preview", "video.focus_arc_style"]

var _config: ConfigFile
var _save_queued: bool = false

func _ready() -> void :
	process_mode = Node.PROCESS_MODE_ALWAYS
	_config = ConfigFile.new()
	var err: int = _config.load(CONFIG_PATH)
	if err == OK:
		if RuntimePolicy.developer_tools: print("[Settings] loaded from ", CONFIG_PATH)
	else:
		if RuntimePolicy.developer_tools: print("[Settings] no saved config (err=", err, "), using defaults")

	var ui_sounds: Node = preload("res://scripts/audio/ui_sounds.gd").new()
	ui_sounds.name = "UiSounds"
	add_child(ui_sounds)
	var music: Node = preload("res://scripts/audio/game_music.gd").new()   # makes the Music bus
	music.name = "GameMusic"
	add_child(music)
	for key in ["audio.master", "audio.sfx", "audio.music", "audio.ambience", "audio.footsteps"]:
		_apply_audio_setting(key, get_value(key))
	_load_perf_toggles()

## Performance switches (docs/PERFORMANCE_PLAN.md "one build, several switches"): saved as
## "perf.<name>" keys, copied into PerfToggles here and on every change. A bench never reads
## the saved file: there they come from --set=perf.<name>=false or the PerfToggles defaults.
const PERF_UNLOCK_KEY := "perf_dev.unlocked"   # phone: the hidden Performance tab was unlocked
func _load_perf_toggles() -> void:
	for n in PerfToggles.NAMES:
		var v: Variant = null
		if RuntimePolicy.autoplay: v = RuntimePolicy.setting_override("perf." + n)
		elif _config.has_section_key("perf", n): v = _config.get_value("perf", n)
		if typeof(v) == TYPE_BOOL: PerfToggles.set_toggle(n, v)
	_apply_perf_engine()

## Step 0b(a): one physics tick per frame at most. A late frame then loses a few ms of game
## time instead of running two ticks (a ~56 ms catch-up frame that makes the next one late
## too). Off: the project value (2). Benches run --fixed-fps 60, i.e. at most one 30 Hz tick
## per frame either way, so this cannot change a bench.
var _project_physics_steps: int = int(ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame", 2))
func _apply_perf_engine() -> void:
	var steps: int = 1 if PerfToggles.single_physics_step else _project_physics_steps
	if Engine.max_physics_steps_per_frame != steps: Engine.max_physics_steps_per_frame = steps

## Step 0b(b): the frame cap used when 30 fps is wanted.
## Godot 4.6 has only one frame limiter: Engine.max_fps, which sleeps until a target time that
## advances by 1/max_fps each frame (OS::add_frame_delay; clamped to within one period of now).
## On iOS the main loop runs from a CADisplayLink fixed at 60 Hz (preferredFrameRate is
## hard-coded to 60 in drivers/apple_embedded, whatever the 120 Hz screen says), so a frame
## can only start on a 16.7 ms vsync. With max_fps 30 the sleep ends exactly on the vsync it
## should catch: a little sleep jitter misses it and that frame takes 50 ms (the plan's 42 ms
## slow-5% average). There is no swap-interval-2 vsync mode (DisplayServer vsync modes are
## on/off/adaptive/mailbox) and physics_jitter_fix only snaps physics steps to frames, so
## neither paces frames. What works: max_fps 31 (32.3 ms) ends each sleep 1 ms before the
## vsync, so frames land on 33.3 ms. The 1 ms a frame that this drifts makes the limiter skip
## one sleep about every 20 frames: one 16.7 ms frame (an extra drawn frame, ~5% more draws,
## never a hitch; interpolation keeps motion correct). Falls back to 30 on a display that is
## not a multiple of 30 Hz.
func _cap_for_30() -> int:
	if not PerfToggles.display_paced_30: return 30
	var hz: float = 60.0 if OS.has_feature("ios") else DisplayServer.screen_get_refresh_rate()
	var per: float = hz / 30.0
	if hz < 59.0 or absf(per - roundf(per)) > 0.05: return 30
	return 31

## Frame rate (Settings "Frame rate"): 60 fps, Adaptive, or 30 fps.
## Adaptive (the phone default) is 60 fps for as long as the phone can hold it. Only when it
## cannot (a hot phone slows its processor and frames start to stutter) does it go to a steady
## 30 fps, which looks better than an uneven 45 and lets the phone cool; it then tries 60 again
## after a while, waiting longer each time 60 fails. The rate never changes in the middle of a
## rally: it changes at the next break in play. Physics is 30 Hz either way, so play is the
## same. Never in the bench.
const ADAPT_SLOW_MS := 21.0        # a frame this long missed its 60 fps slot (16.7 ms)
const ADAPT_WINDOW := 2.0          # s per verdict
const ADAPT_SLOW_SHARE := 0.2      # share of slow frames in a window (logged; no longer the verdict)
const ADAPT_MIN_FPS := 52.0        # a window that averages under this did not hold 60: a bad one
const ADAPT_BAD_WINDOWS := 3       # this many bad windows in a row: go to 30
const ADAPT_HOLD := 45.0           # s at 30 before 60 is tried again (doubles after each failed try)
const ADAPT_HOLD_MAX := 360.0
const ADAPT_PROVE := 20.0          # s at 60 without a bad window: the try worked, the hold resets
var adaptive_fps := 60             # what Adaptive wants right now (60 or 30)
var _adapt_frames := 0
var _adapt_slow := 0
var _adapt_clock := 0.0
var _adapt_bad := 0
var _adapt_hold := ADAPT_HOLD
var _adapt_left := 0.0             # s left at 30
var _adapt_good := 0.0             # s at 60 since the last try
var _adapt_last_usec := 0
var _adapt_tried := false         # 30 was used and 60 has not proven itself since

## One frame of the Adaptive verdict. Real time, so slow motion and pauses do not count.
func _adapt_tick() -> void:
	var now: int = Time.get_ticks_usec()
	var real: float = float(now - _adapt_last_usec) / 1000000.0 if _adapt_last_usec > 0 else 0.0
	_adapt_last_usec = now
	if real <= 0.0 or real > 0.5 or get_tree().paused: return   # a hitch from loading or a pause is not a verdict
	if adaptive_fps == 30:
		_adapt_left -= real
		if _adapt_left <= 0.0:
			adaptive_fps = 60
			_adapt_good = 0.0
			_adapt_bad = 0
			_adapt_frames = 0; _adapt_slow = 0; _adapt_clock = 0.0
			PerfMonitor.note("adaptive_fps", {"fps": 60, "why": "try 60 again", "next_hold": snappedf(_adapt_hold, 1.0)})
		return
	if Engine.max_fps != 0: return   # still capped (the switch waits for a break in play): 33 ms frames here are not a verdict
	_adapt_frames += 1
	if real * 1000.0 >= ADAPT_SLOW_MS: _adapt_slow += 1
	_adapt_clock += real
	_adapt_good += real
	if _adapt_good >= ADAPT_PROVE:
		_adapt_hold = ADAPT_HOLD
		_adapt_tried = false
	if _adapt_clock < ADAPT_WINDOW: return
	var share: float = float(_adapt_slow) / float(maxi(_adapt_frames, 1))
	# The verdict is the frame rate itself (2026-11-25). Physics ticks 30 times a second, so at 60
	# every other frame carries a tick and is longer than the one after it. On the 120 Hz phone
	# those frames passed 21 ms while the rally still averaged 60-80 fps; counting them as
	# misses sent every match to 30 within 10-25 s, which is the lag the user saw start after the
	# first rally. 60 has failed only when the window's average falls under ADAPT_MIN_FPS.
	var window_fps: float = float(_adapt_frames) / maxf(_adapt_clock, 0.001)
	_adapt_bad = _adapt_bad + 1 if window_fps < ADAPT_MIN_FPS else 0
	_adapt_frames = 0; _adapt_slow = 0; _adapt_clock = 0.0
	if _adapt_bad >= ADAPT_BAD_WINDOWS:
		# 60 failed again soon after a try: wait twice as long this time.
		if _adapt_tried and _adapt_good < ADAPT_PROVE: _adapt_hold = minf(_adapt_hold * 2.0, ADAPT_HOLD_MAX)
		adaptive_fps = 30
		_adapt_left = _adapt_hold
		_adapt_tried = true
		PerfMonitor.note("adaptive_fps", {"fps": 30, "why": "could not hold 60", "slow_share": snappedf(share, 0.01), "window_fps": snappedf(window_fps, 0.1), "hold": snappedf(_adapt_hold, 1.0)})
		_adapt_bad = 0

## Paused means stopped (user's call, 2026-11-24). While the pause menu is up (or the app lost
## focus) the game must not keep working: the court is not redrawn 60 times a second and the
## always-on helpers of the match do not tick. The engine goes to its low-power loop (it draws
## only when something on screen changes, such as a menu button) and those helpers are switched
## off until play resumes. The pause controller asks for it; this node undoes it the moment the
## tree is running again, whoever unpaused it.
const PAUSE_FROZEN_SCRIPTS := ["mobile_controls.gd", "match_feel.gd", "fx_pool.gd", "incoming_movement_guide.gd",
	"solo_aim_focus.gd", "movement_action_picker.gd", "game_serve.gd", "time_scale_manager.gd"]
const PAUSE_LOOP_USEC := 16000   # the idle loop still reads touches 60 times a second; it only draws on a change
var _pause_idle_wanted := false
var _pause_idle := false
var _pause_frozen: Array = []    # [node ref, was processing, was physics processing]

func set_pause_idle(wanted: bool) -> void:
	_pause_idle_wanted = wanted
	_apply_pause_idle()

func _apply_pause_idle() -> void:
	if not get_tree().paused: _pause_idle_wanted = false   # unpaused by someone else: the request is over
	var on: bool = _pause_idle_wanted and get_tree().paused and not RuntimePolicy.autoplay
	if on == _pause_idle: return
	_pause_idle = on
	OS.low_processor_usage_mode = on
	if on:
		OS.low_processor_usage_mode_sleep_usec = PAUSE_LOOP_USEC
		_pause_frozen.clear()
		var scene: Node = get_tree().current_scene
		if scene != null: _freeze_always_on(scene)
	else:
		for item in _pause_frozen:
			var node = item[0].get_ref()
			if node == null: continue
			node.set_process(item[1])
			node.set_physics_process(item[2])
		_pause_frozen.clear()

func _freeze_always_on(node: Node) -> void:
	var script = node.get_script()
	if script != null and str(script.resource_path).get_file() in PAUSE_FROZEN_SCRIPTS and (node.is_processing() or node.is_physics_processing()):
		_pause_frozen.append([weakref(node), node.is_processing(), node.is_physics_processing()])
		node.set_process(false)
		node.set_physics_process(false)
	for child in node.get_children(): _freeze_always_on(child)

var _cap_clock := 0.0
func _process(delta: float) -> void:
	if _pause_idle or _pause_idle_wanted: _apply_pause_idle()   # follows the tree if something else unpaused it
	if RuntimePolicy.autoplay: return
	var mode: int = int(get_value("video.fps_mode", 0))   # 0 = 60, 1 = adaptive, 2 = 30
	if mode == 1: _adapt_tick()
	_cap_clock -= delta
	if _cap_clock > 0.0: return
	_cap_clock = 0.25
	var want: int = 30 if mode == 2 else (adaptive_fps if mode == 1 else 60)
	var scene: Node = get_tree().current_scene
	# First-person view: always 60 (user's call, 2026-11-25), whatever the frame-rate setting.
	var first_person: bool = int(get_value("video.camera_mode", 0)) == 3 and scene != null and scene.get("camera_rig") != null
	if first_person: want = 60
	_apply_perf_engine()
	var cap: int = _cap_for_30() if want == 30 else 0
	if Engine.max_fps == cap: return
	# Never switch in the middle of a rally: wait for the next break in play.
	if mode == 1 and not first_person and scene != null and "game_state" in scene and "GameState" in scene and int(scene.game_state) == int(scene.GameState.PLAYING): return
	Engine.max_fps = cap

func _apply_audio_setting(key: String, value: Variant) -> void :
	var bus_name: = ""
	match key:
		"audio.master": bus_name = "Master"
		"audio.sfx": bus_name = "SFX"
		"audio.music": bus_name = "Music"
		"audio.ambience": bus_name = "Ambience"
		"audio.footsteps": bus_name = "Footsteps"
		_: return
	var bus: = AudioServer.get_bus_index(bus_name)
	if bus < 0: return
	var level: = clampf(float(value), 0.0, 1.0)
	if not is_finite(level): level = 0.0
	AudioServer.set_bus_mute(bus, level <= 0.0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(level, 0.0001)))

func get_value(key: String, fallback: Variant = null) -> Variant:
	var parts: PackedStringArray = key.split(".", true, 1)
	if parts.size() != 2:
		return fallback
	var section: String = parts[0]
	var _name: String = parts[1]
	var default_v: Variant = fallback
	if RuntimePolicy.autoplay and section == "gameplay":
		var pinned: Variant = RuntimePolicy.setting_override(key)
		if pinned != null: return pinned
		return DEFAULTS.get(key, fallback)
	if default_v == null and DEFAULTS.has(key):
		default_v = DEFAULTS[key]
	if default_v == null and section == "perf":
		default_v = PerfToggles.get_toggle(_name)
	if OS.has_feature("mobile") and MOBILE_DEFAULTS.has(key):
		default_v = MOBILE_DEFAULTS[key]
	return _sanitize_focus_value(key, _config.get_value(section, _name, default_v))

func set_value(key: String, value: Variant) -> void :
	var parts: PackedStringArray = key.split(".", true, 1)
	if parts.size() != 2:
		return
	value = _sanitize_focus_value(key, value)
	_config.set_value(parts[0], parts[1], value)
	_apply_audio_setting(key, value)
	if parts[0] == "perf" and typeof(value) == TYPE_BOOL:
		PerfToggles.set_toggle(parts[1], value)
		_apply_perf_engine()
	settings_changed.emit(key, value)
	_queue_save()

func reset_focus_visuals() -> void:
	# Reset only these visual preferences; keep gameplay and custom pose data intact.
	for key in FOCUS_VISUAL_KEYS:
		set_value(key, DEFAULTS[key])

func _sanitize_focus_value(key: String, value: Variant) -> Variant:
	if key in preload("res://scripts/ai_playing_styles.gd").SETTINGS.values():
		return value if typeof(value) == TYPE_INT and value >= 0 and value < 5 else DEFAULTS[key]
	if key == "video.focus_arc_style" or key == "gameplay.execution_accuracy" or key == "gameplay.point_transition":
		return value if typeof(value) == TYPE_INT and value in [0, 1] else DEFAULTS[key]
	# Treat malformed saved values like missing preferences, without rewriting
	# unrelated keys or migrating any authored data.
	if key == "video.focus_preview" or key == "gameplay.movement_guide":
		return value if typeof(value) == TYPE_BOOL else DEFAULTS[key]
	if key == "video.focus_dim" or key == "video.focus_blur":
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return DEFAULTS[key]
		var amount: float = float(value)
		if not is_finite(amount):
			return DEFAULTS[key]
		return clampf(amount, 0.0, 0.35 if key == "video.focus_dim" else 1.5)
	return value

func _queue_save() -> void :
	if _save_queued:
		return
	_save_queued = true
	call_deferred("_do_save")

func _do_save() -> void :
	_save_queued = false
	var err: int = _config.save(CONFIG_PATH)
	if err != OK:
		push_warning("[Settings] save failed err=" + str(err))
