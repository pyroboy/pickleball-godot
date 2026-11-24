extends Node
## Interface sounds for every button, switch, tab and slider in the game, plus the master
## limiter. Added once by the Settings autoload; hooks controls as they enter the tree, so
## menus need no sound code of their own.

const SfxBank = preload("res://scripts/audio/sfx_bank.gd")
const MIN_GAP_MSEC: = 45
const CONFIRM_WORDS: Array[String] = ["PLAY", "START", "REMATCH", "RESUME", "CONTINUE"]   # buttons that begin play

var taps_played: = 0
var _player: AudioStreamPlayer
var _taps: Array[AudioStreamWAV] = []
var _last_msec: = -1000
var _chimes: AudioStreamPlayer
var _confirm: AudioStreamWAV
var _ready_tick: AudioStreamWAV
var _stingers: Array[AudioStreamWAV] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_add_master_limiter()
	for variant in 3: _taps.append(SfxBank.ui_tap(variant))
	_player = AudioStreamPlayer.new()
	_player.name = "UiTap"
	_player.bus = "SFX"
	_player.volume_db = -13.0
	_player.max_polyphony = 2
	add_child(_player)
	_confirm = SfxBank.chime([523.25, 783.99], 0.07, 0.3, 16.0)
	_ready_tick = SfxBank.chime([1760.0], 0.0, 0.07, 60.0)
	_stingers = [SfxBank.stinger(false), SfxBank.stinger(true)]
	_chimes = AudioStreamPlayer.new()
	_chimes.name = "UiChime"
	_chimes.bus = "SFX"
	add_child(_chimes)
	get_tree().node_added.connect(_on_node_added)

## Lifts the overall level a little for phone speakers and stops loud moments from clipping.
func _add_master_limiter() -> void:
	var bus: = AudioServer.get_bus_index("Master")
	for index in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, index) is AudioEffectHardLimiter: return
	var limiter: = AudioEffectHardLimiter.new()
	limiter.pre_gain_db = 3.0
	limiter.ceiling_db = -1.0
	AudioServer.add_bus_effect(bus, limiter)

func _on_node_added(node: Node) -> void:
	# A control can leave the tree and come back, so each hook is made only once.
	if node is BaseButton:
		_hook(node.pressed, _on_button_pressed.bind(node))
		if node is OptionButton: _hook(node.item_selected, _on_item_picked)
	elif node is Slider:
		_hook(node.drag_ended, _on_slider_released)
	elif node is TabBar:
		_hook(node.tab_clicked, _on_item_picked)

func _hook(source: Signal, target: Callable) -> void:
	if not source.is_connected(target): source.connect(target)

func _on_button_pressed(button: BaseButton) -> void:
	if button.toggle_mode and not button is OptionButton:
		tap(1 if button.button_pressed else 2)
		return
	var label: = str(button.get("text")).to_upper()
	for word in CONFIRM_WORDS:
		if word in label:
			_chime(_confirm, -14.0)
			return
	tap(0)

func _on_item_picked(_index: int) -> void:
	tap(0)

func _on_slider_released(value_changed: bool) -> void:
	if value_changed: tap(0)

func tap(variant: int = 0) -> void:
	var now: = Time.get_ticks_msec()
	if now - _last_msec < MIN_GAP_MSEC: return
	_last_msec = now
	_player.stream = _taps[clampi(variant, 0, _taps.size() - 1)]
	_player.play()
	taps_played += 1

func _chime(stream: AudioStreamWAV, volume_db: float) -> void:
	_chimes.stream = stream
	_chimes.volume_db = volume_db
	_chimes.play()

## A banner slid in (match point, change of court).
func stinger(big: bool) -> void:
	_chime(_stingers[1 if big else 0], -15.0 if big else -18.0)

## The held shot is ready to release: a small tick with the buzz.
func ready_tick() -> void:
	_chime(_ready_tick, -21.0)
