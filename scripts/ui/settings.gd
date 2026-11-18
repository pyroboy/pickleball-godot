extends Node
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")























signal settings_changed(key: String, value: Variant)

const CONFIG_PATH: String = "user://settings.cfg"

const DEFAULTS: Dictionary = {
	"video.fov": 60.0,
	"video.camera_mode": 0, 
	"video.shake": 1.0, 
	"video.hitstop": true, 
	"video.particle_density": 2, 
	"video.shadow_quality": 1, 
	"video.focus_dim": 0.14,
	"video.focus_blur": 0.65,
	"video.focus_preview": true,
	"video.focus_arc_style": 0,
	"video.character_style": 1, # 1 = 2.5D pixel cards (default), 0 = classic 3D bodies
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
	"beta_debug.reach_rings": false, 
	"beta_debug.preparation_blocks": false, 
}

const MOBILE_DEFAULTS: = {"video.shadow_quality": 0, "video.particle_density": 1, "video.shake": 0.5}
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

	for key in ["audio.master", "audio.sfx", "audio.ambience", "audio.footsteps"]:
		_apply_audio_setting(key, get_value(key))

func _apply_audio_setting(key: String, value: Variant) -> void :
	var bus_name: = ""
	match key:
		"audio.master": bus_name = "Master"
		"audio.sfx": bus_name = "SFX"
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
	if default_v == null and DEFAULTS.has(key):
		default_v = DEFAULTS[key]
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
	settings_changed.emit(key, value)
	_queue_save()

func reset_to_defaults() -> void :
	for key in DEFAULTS.keys():
		set_value(key, MOBILE_DEFAULTS[key] if OS.has_feature("mobile") and MOBILE_DEFAULTS.has(key) else DEFAULTS[key])

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
