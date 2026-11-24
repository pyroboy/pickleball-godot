extends Node
## Background music: the title theme in menus and a quieter groove during a match.
## Added once by the Settings autoload. Fades between the two as scenes change, drops under
## the pause menu and pauses while the app is in the background. The files come from
## tools/make_music.py; their level follows the Music slider (the "Music" bus).

const TITLE_PATH: = "res://assets/audio/music/title_theme.wav"
const MATCH_PATH: = "res://assets/audio/music/match_groove.wav"
const MATCH_SCENE: = "res://scenes/game.tscn"
const TITLE_DB: = -9.0
const MATCH_DB: = -19.0          # well under the paddle pops and bounces
const PAUSED_DROP_DB: = -7.0
const SILENT_DB: = -60.0
const START_DB: = -40.0
const FADE_DB_PER_SEC: = 45.0
const CHECK_SECONDS: = 0.25

var title: AudioStreamPlayer
var groove: AudioStreamPlayer
var _check_left: = 0.0
var _title_target: = SILENT_DB
var _groove_target: = SILENT_DB
var _backgrounded: = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		var bus: = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, "Music")
		AudioServer.set_bus_send(bus, "Master")
	title = _player("TitleTheme", TITLE_PATH)
	groove = _player("MatchGroove", MATCH_PATH)
	# Nothing to hear in a headless run (bench, tools), so nothing to drive either.
	if DisplayServer.get_name() == "headless": set_process(false)

func _player(player_name: String, path: String) -> AudioStreamPlayer:
	var player: = AudioStreamPlayer.new()
	player.name = player_name
	player.bus = "Music"
	player.volume_db = SILENT_DB
	if ResourceLoader.exists(path):
		var stream: = load(path) as AudioStreamWAV
		if stream != null and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = int(stream.get_length() * stream.mix_rate)
		player.stream = stream
	add_child(player)
	return player

func _process(delta: float) -> void:
	if _backgrounded: return
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = CHECK_SECONDS
		_pick_targets()
	_fade(title, _title_target, delta)
	_fade(groove, _groove_target, delta)

func _pick_targets() -> void:
	var scene: = get_tree().current_scene
	if scene == null: return   # between scenes: keep what is playing
	var in_match: = scene.scene_file_path == MATCH_SCENE
	var drop: = PAUSED_DROP_DB if get_tree().paused else 0.0
	_title_target = SILENT_DB if in_match else TITLE_DB + drop
	_groove_target = MATCH_DB + drop if in_match else SILENT_DB

func _fade(player: AudioStreamPlayer, target: float, delta: float) -> void:
	if player.stream == null: return
	if target > SILENT_DB and not player.playing:
		player.volume_db = START_DB
		player.play()
	player.volume_db = move_toward(player.volume_db, target, FADE_DB_PER_SEC * delta)
	if target <= SILENT_DB and player.playing and player.volume_db <= SILENT_DB + 0.5:
		player.stop()

func _notification(what: int) -> void:
	if title == null or groove == null: return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_backgrounded = true
		title.stream_paused = true
		groove.stream_paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_backgrounded = false
		title.stream_paused = false
		groove.stream_paused = false
