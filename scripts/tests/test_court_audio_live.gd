extends SceneTree

var checks: = 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void : call_deferred("run")
func run() -> void :
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.set_physics_process(false)
	game.input_handler.set_process(false)
	game.ball.freeze = true
	game.ball.is_in_play = false
	game.ball.set_physics_process(false)
	game.player_left.set_physics_process(false)
	game.player_right.set_physics_process(false)
	game.player_left.set_process(false)
	game.player_right.set_process(false)
	var sound = game.court_audio
	sound.set_process(false)
	check(sound != null and sound.ambience.playing, "real scene owns active court ambience")
	check(game.find_children("CourtAudio", "", false, false).size() == 1, "one court helper")
	var player = game.player_left
	var steps: int = sound.steps_played
	for frame in range(90):
		player.current_velocity = Vector3(2.8, 0, 0)
		player.position.x += 2.8 / 60.0
		player._process(1.0 / 60.0)
		sound._process(1.0 / 60.0)
	check(sound.steps_played > steps + 2, "actual travelling gait emits foot contacts")
	var squeaks: int = sound.squeaks_played
	for frame in range(25):
		player.current_velocity = Vector3(-2.8, 0, 0)
		player.position.x -= 2.8 / 60.0
		player._process(1.0 / 60.0)
		sound._process(1.0 / 60.0)
	check(sound.squeaks_played > squeaks, "actual reversal gets a contact-timed squeak")
	player.current_velocity = Vector3.ZERO
	for frame in range(45):
		player._process(1.0 / 60.0)
		sound._process(1.0 / 60.0)
	steps = sound.steps_played
	for frame in range(120):
		player._process(1.0 / 60.0)
		sound._process(1.0 / 60.0)
	check(sound.steps_played == steps, "settled real player stays silent")
	game.ball.global_position = Vector3(1.4, 0.08, -3.5)
	game.ball.audio_synth.on_floor_bounce(7.0)
	check(game.ball.audio_synth.bounce_player.global_position.is_equal_approx(game.ball.global_position), "bounce emitted at ball contact")
	game._reset_match()
	sound._last_cue_msec = -1000
	var cues: int = sound.cues_played
	game._on_point_scored(0)
	check(sound.cues_played == cues + 1 and sound.cue.stream == sound.POINT_WON, "real player point gives one cue")
	game._on_point_scored(0)
	check(sound.cues_played == cues + 1, "duplicate real point stays silent")
	game._reset_match()
	game.serving_team = 1
	sound._last_cue_msec = -1000
	game._on_point_scored(0)
	check(sound.cue.stream == sound.SIDE_OUT, "real side-out cue")
	game._reset_match()
	game.score_left = 10
	sound._last_cue_msec = -1000
	game._on_point_scored(0)
	check(game.match_over and sound.cue.stream == sound.MATCH_WON, "match-winning cue")
	game._reset_match()
	game._practice_mode = true
	sound._last_cue_msec = -1000
	cues = sound.cues_played
	game._on_point_scored(0)
	check(sound.cues_played == cues, "practice does not impersonate match point")
	game._practice_mode = false
	var playback_weak: WeakRef = weakref(sound.ambience.get_stream_playback())
	var controller: = root.get_node("PauseController")
	controller.open()
	await process_frame
	controller._menu._on_settings()
	var settings_panel = controller._menu._settings_overlay
	for key in ["audio_master", "audio_sfx", "audio_ambience", "audio_footsteps"]:
		var slider: HSlider = settings_panel._panel.find_child(key, true, false)
		check(slider != null and slider.editable, key + " present and editable")
		check(is_equal_approx(slider.value, float(root.get_node("Settings").get_value(key.replace("_", ".")))), key + " displays the exact saved/default level")
	check(settings_panel._panel.find_child("audio_music", true, false) == null, "no dead music slider")
	settings_panel._on_close()
	controller.close()
	check(sound._resume_ambience_pending and not sound.ambience.playing, "unpause defers ambience start until a surviving gameplay frame")
	var loop_weak: WeakRef = weakref(sound.ambience.stream)
	game.queue_free()
	await process_frame
	await create_timer(0.12).timeout
	check(playback_weak.get_ref() == null, "paused ambience playback released after scene exit")
	check(loop_weak.get_ref() == null, "same-frame resume/exit does not retain ambience resource")
	for failure in failures: push_error(failure)
	print("LIVE COURT AUDIO: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
