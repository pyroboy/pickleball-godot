extends Node
## Autoload "Settings".
## Owns user:// settings.cfg — loads on _ready, auto-saves on set_value
## (debounced by one frame to batch writes).
##
## Categories:
##   video.fov                 float  50–90   default 60
##   video.shake               float  0–1.5   default 1.0
##   video.hitstop             bool            default true
##   video.particle_density    int    0–3     default 2  (Off/Low/Med/High)
##   video.shadow_quality      int    0–2     default 1  (Off/Low/High)
##   audio.master              float  0–1     default 0.9
##   audio.sfx                 float  0–1     default 1.0
##   audio.music               float  0–1     default 0.7
##   gameplay.difficulty       int    0–2     default 0
##   gameplay.reaction_delay   float  0–0.5   default 0.0
##   gameplay.reaction_button  bool            default true
##
## Consumers read via get_value(key, default). Changes fire settings_changed.

signal settings_changed(key: String, value: Variant)

const CONFIG_PATH: String = "user://settings.cfg"

const DEFAULTS: Dictionary = {
	"video.fov": 60.0,
	"video.shake": 1.0,
	"video.hitstop": true,
	"video.particle_density": 2,
	"video.shadow_quality": 1,
	"audio.master": 0.9,
	"audio.sfx": 1.0,
	"audio.music": 0.7,
	"gameplay.difficulty": 0,
	"gameplay.reaction_delay": 0.0,
	"gameplay.reaction_button": true,
}

var _config: ConfigFile
var _save_queued: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_config = ConfigFile.new()
	var err: int = _config.load(CONFIG_PATH)
	if err == OK:
		print("[Settings] loaded from ", CONFIG_PATH)
	else:
		print("[Settings] no saved config (err=", err, "), using defaults")

func get_value(key: String, fallback: Variant = null) -> Variant:
	var parts: PackedStringArray = key.split(".", true, 1)
	if parts.size() != 2:
		return fallback
	var section: String = parts[0]
	var _name: String = parts[1]
	var default_v: Variant = fallback
	if default_v == null and DEFAULTS.has(key):
		default_v = DEFAULTS[key]
	return _config.get_value(section, _name, default_v)

func set_value(key: String, value: Variant) -> void:
	var parts: PackedStringArray = key.split(".", true, 1)
	if parts.size() != 2:
		return
	_config.set_value(parts[0], parts[1], value)
	settings_changed.emit(key, value)
	_queue_save()

func reset_to_defaults() -> void:
	for key in DEFAULTS.keys():
		set_value(key, DEFAULTS[key])

func _queue_save() -> void:
	if _save_queued:
		return
	_save_queued = true
	call_deferred("_do_save")

func _do_save() -> void:
	_save_queued = false
	var err: int = _config.save(CONFIG_PATH)
	if err != OK:
		push_warning("[Settings] save failed err=" + str(err))
