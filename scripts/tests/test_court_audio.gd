extends SceneTree
const Court = preload("res://scripts/court_audio.gd")
class AudioTestLegs extends RefCounted:
	var feet_initialized: = true
	var right_foot_locked: = true
	var left_foot_locked: = true
	var right_foot_lock_pos: = Vector3(0.25, 0.075, 0)
	var left_foot_lock_pos: = Vector3(-0.25, 0.075, 0)
class AudioTestPlayer extends Node3D:
	var leg_ik: = AudioTestLegs.new()
	var current_velocity: = Vector3.ZERO
	var is_jumping: = false
class AudioTestGame extends Node3D:
	var player_left: = AudioTestPlayer.new()
	var player_right: = AudioTestPlayer.new()
	var tools_open: = false
	func _ready() -> void :
		add_child(player_left)
		add_child(player_right)
	func _tool_state_active() -> bool: return tools_open
var checks: = 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void : call_deferred("run")
func run() -> void :
	var settings: = root.get_node("Settings")
	var previous: = {}
	for key in ["audio.master", "audio.sfx", "audio.ambience", "audio.footsteps"]:
		previous[key] = settings.get_value(key)
		settings.set_value(key, 0.8)
	var game: = AudioTestGame.new()
	root.add_child(game)
	var sound: = Court.new()
	game.add_child(sound)
	sound.setup(game)
	sound.set_process(false)
	await process_frame
	check(sound.get_child_count() == 4, "exactly four audio players")
	check(sound.ambience.playing, "ambience starts once in a game")
	check(sound.ambience.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "ambience loops")
	check(sound.ambience.stream.mix_rate == 22050, "lightweight ambience sample rate")
	check(sound.ambience.stream.loop_end == sound.ambience.stream.data.size() / 2, "loop covers exactly PCM frames")
	check(sound.ambience.stream.data.decode_s16(0) == sound.ambience.stream.data.decode_s16(sound.ambience.stream.data.size() - 2), "seamless PCM loop boundary")
	for voice in sound.shoe_voices:
		check(voice.max_polyphony == 1 and voice.bus == "Footsteps", "shoe voices bounded and separately routed")
	for asset in Court.STEPS + Court.SQUEAKS + [Court.POINT_WON, Court.POINT_LOST, Court.SIDE_OUT, Court.MATCH_WON, Court.MATCH_LOST]:
		check(asset.data.decode_s16(0) == 0 and asset.data.decode_s16(asset.data.size() - 2) == 0, "short asset starts/ends at zero")
		check(asset.get_length() < 0.6, "feedback remains brief")
	sound.setup(game)
	check(sound.get_child_count() == 4, "repeat setup does not duplicate voices")
	sound._update_player(0, 0.2)
	for index in range(300): sound._update_player(0, 1.0 / 60.0)
	check(sound.steps_played == 0, "idle character remains silent")
	var player: = game.player_left
	player.current_velocity = Vector3(3, 0, 0)
	player.leg_ik.right_foot_locked = false
	sound._update_player(0, 0.2)
	player.position.x += 0.2
	player.leg_ik.right_foot_locked = true
	sound._update_player(0, 0.1)
	check(sound.steps_played == 1, "real landing emits one step")
	sound._update_player(0, 0.1)
	check(sound.steps_played == 1, "planted foot does not repeat")
	player.leg_ik.right_foot_locked = false
	sound._update_player(0, 0.2)
	player.position.x += 5
	player.leg_ik.right_foot_locked = true
	sound._update_player(0, 0.1)
	check(sound.steps_played == 1, "teleport contact is silent")
	player.is_jumping = true
	player.leg_ik.right_foot_locked = false
	sound._update_player(0, 0.2)
	player.leg_ik.right_foot_locked = true
	sound._update_player(0, 0.2)
	check(sound.steps_played == 1, "airborne player is silent")
	player.is_jumping = false
	player.leg_ik.right_foot_locked = false
	sound._update_player(0, 0.2)
	sound.reset_contacts()
	player.leg_ik.right_foot_locked = true
	sound._update_player(0, 0.2)
	check(sound.steps_played == 1, "same-position reset cannot create a footfall")
	check(sound.ambience.playing, "contact reset retains one ambience bed")
	for index in range(500): sound._play_shoe(index % 2, Vector3.ZERO, 3.0, index % 3 == 0)
	check(sound.get_child_count() == 4, "event stress never allocates players")
	check(sound.shoe_voices[0].max_polyphony == 1, "stress retains bounded overlap")
	sound.play_point_cue(0, false, false)
	check(sound.cue.stream == Court.POINT_WON and sound.cues_played == 1, "player point cue")
	sound.play_point_cue(0, false, false)
	check(sound.cues_played == 1, "duplicate point cue suppressed")
	for item in [[1, false, false, Court.POINT_LOST], [0, true, false, Court.SIDE_OUT], [0, false, true, Court.MATCH_WON], [1, false, true, Court.MATCH_LOST]]:
		sound._last_cue_msec = -1000
		sound.play_point_cue(item[0], item[1], item[2])
		check(sound.cue.stream == item[3], "correct outcome cue")
	for item in [["audio.master", "Master"], ["audio.sfx", "SFX"], ["audio.ambience", "Ambience"], ["audio.footsteps", "Footsteps"]]:
		var bus: = AudioServer.get_bus_index(item[1])
		check(bus >= 0, item[1] + " bus present")
		settings.set_value(item[0], 0.0)
		check(AudioServer.is_bus_mute(bus), item[1] + " truly muted at zero")
		settings.set_value(item[0], 0.42)
		check( not AudioServer.is_bus_mute(bus), item[1] + " unmuted above zero")
		check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(bus)), 0.42), item[1] + " setting applies without UI")
	settings.set_value("audio.ambience", 0.0)
	check( not sound.ambience.playing, "muted ambience stops its loop")
	settings.set_value("audio.ambience", 0.5)
	check(sound.ambience.playing, "unmuted ambience restarts one loop")
	settings.set_value("audio.footsteps", 0.0)
	check( not sound.shoe_voices[0].playing and not sound.shoe_voices[1].playing, "shoe mute stops voices")
	var count: = sound.steps_played
	sound._play_shoe(0, Vector3.ZERO, 3.0, false)
	check(sound.steps_played == count, "muted shoes skip new playback")
	settings.set_value("audio.footsteps", 0.8)
	await process_frame
	var persisted: = ConfigFile.new()
	check(persisted.load("user://settings.cfg") == OK, "audio settings persisted")
	check(is_equal_approx(float(persisted.get_value("audio", "ambience")), 0.5), "saved ambience level")
	check(is_equal_approx(float(persisted.get_value("audio", "footsteps")), 0.8), "saved footsteps level")
	paused = true
	await process_frame
	check( not sound.ambience.playing, "scene pause stops ambience")
	settings.set_value("audio.ambience", 0.0)
	settings.set_value("audio.ambience", 0.5)
	check( not sound.ambience.playing, "changing ambience volume cannot start audio while paused")
	count = sound.cues_played
	sound._last_cue_msec = -1000
	sound.play_point_cue(0)
	check(sound.cues_played == count, "paused cue cannot start")
	paused = false
	sound._process(0.0)
	await process_frame
	check( not sound.ambience.stream_paused, "unpause resumes ambience")
	check(sound.ambience.playing, "unpause starts reenabled ambience")
	for index in range(3):
		sound._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		check( not sound.ambience.playing and not sound.cue.playing, "background stops audio")
		sound._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		sound._process(0.0)
		check(sound.ambience.playing and sound.get_child_count() == 4, "resume reuses existing ambience")
	await process_frame
	var weak: WeakRef = weakref(sound.ambience)
	game.queue_free()
	await process_frame
	check(weak.get_ref() == null, "scene exit frees ambience player")
	for key in previous: settings.set_value(key, previous[key])
	await process_frame

	await create_timer(0.05).timeout
	for failure in failures: push_error(failure)
	print("COURT AUDIO: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
