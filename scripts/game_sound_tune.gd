class_name GameSoundTune
extends Node

## Sound Tuning Panel
## Owns the sound signature tuning UI panel with 28 parameters.
## Injected as child of Game, initialized via setup().

signal slider_changed(idx: int, value: float)

var sound_tune_panel: PanelContainer
var sound_tune_rows: Array[Label] = []
var sound_tune_sliders: Array[HSlider] = []
var sound_tune_selected := 0

var _sound_panel_key_state: Dictionary = {}

# Injected dependencies
var _ball_audio_synth: Node
var _scoreboard_ui: Node
var _hud: CanvasLayer

var sound_tune_settings := [
	{"id": "paddle_pitch", "label": "Paddle Pitch"},
	{"id": "paddle_sub_pitch", "label": "Paddle Sub Pitch"},
	{"id": "paddle_pitch_blend", "label": "Paddle Pitch Blend"},
	{"id": "paddle_upper_pitch", "label": "Paddle Upper Pitch"},
	{"id": "paddle_body_pitch", "label": "Paddle Body Pitch"},
	{"id": "paddle_hollow_pitch", "label": "Paddle Hollow Pitch"},
	{"id": "paddle_body", "label": "Paddle Body"},
	{"id": "paddle_wood", "label": "Paddle Wood"},
	{"id": "paddle_hollow", "label": "Paddle Hollow"},
	{"id": "paddle_rumble", "label": "Paddle Rumble"},
	{"id": "paddle_core_softness", "label": "Paddle Core Softness"},
	{"id": "paddle_metallic", "label": "Paddle Metallic"},
	{"id": "paddle_ring", "label": "Paddle Ring"},
	{"id": "paddle_presence", "label": "Paddle Presence"},
	{"id": "paddle_attack", "label": "Paddle Attack"},
	{"id": "paddle_clack", "label": "Paddle Clack"},
	{"id": "paddle_noise", "label": "Paddle Noise"},
	{"id": "paddle_crackle", "label": "Paddle Crackle"},
	{"id": "paddle_compress", "label": "Paddle Compression"},
	{"id": "paddle_dead", "label": "Paddle Deadness"},
	{"id": "paddle_sweet_spot", "label": "Paddle Sweet Spot"},
	{"id": "paddle_variation", "label": "Paddle Variation"},
	{"id": "paddle_damp", "label": "Paddle Damp"},
	{"id": "paddle_tail", "label": "Paddle Tail"},
	{"id": "paddle_reflection", "label": "Paddle Reflection"},
	{"id": "paddle_echo", "label": "Paddle Echo"},
	{"id": "paddle_chirp", "label": "Ball Chirp"},
	{"id": "paddle_helmholtz", "label": "Ball Resonance"},
	{"id": "court_weight", "label": "Court Weight"},
	{"id": "court_snap", "label": "Court Snap"},
	{"id": "court_decay", "label": "Court Decay"},
	{"id": "court_hardness", "label": "Court Hardness"},
	{"id": "court_surface", "label": "Court Surface"}
]


func setup(ball_audio_synth: Node, scoreboard_ui: Node, hud: CanvasLayer) -> void:
	_ball_audio_synth = ball_audio_synth
	_scoreboard_ui = scoreboard_ui
	_hud = hud


func _create_sound_tune_panel(canvas: CanvasLayer) -> void:
	sound_tune_panel = PanelContainer.new()
	sound_tune_panel.anchor_left = 0.5
	sound_tune_panel.anchor_right = 0.5
	sound_tune_panel.anchor_top = 0.5
	sound_tune_panel.anchor_bottom = 0.5
	sound_tune_panel.offset_left = -260.0
	sound_tune_panel.offset_top = -430.0
	sound_tune_panel.offset_right = 260.0
	sound_tune_panel.offset_bottom = 430.0
	sound_tune_panel.focus_mode = Control.FOCUS_NONE
	sound_tune_panel.visible = false
	canvas.add_child(sound_tune_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	sound_tune_panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(vb)

	var title := Label.new()
	title.text = "Sound Signature  P: Toggle  Arrows: Select/Adjust"
	title.add_theme_font_size_override("font_size", 14)
	title.focus_mode = Control.FOCUS_NONE
	vb.add_child(title)

	for i in range(sound_tune_settings.size()):
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 12)
		row.focus_mode = Control.FOCUS_NONE
		vb.add_child(row)
		sound_tune_rows.append(row)

		var slider := HSlider.new()
		slider.min_value = -1.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.editable = false
		slider.focus_mode = Control.FOCUS_NONE
		slider.value_changed.connect(_on_slider_changed.bind(i))
		vb.add_child(slider)
		sound_tune_sliders.append(slider)

	_refresh_sound_tune_panel()


func _refresh_sound_tune_panel() -> void:
	if _ball_audio_synth == null:
		return
	var tunings: Dictionary = _ball_audio_synth.get_sound_tunings()
	for i in range(sound_tune_settings.size()):
		var setting: Dictionary = sound_tune_settings[i]
		var id: String = setting["id"]
		var value: float = tunings.get(id, 0.0)
		if i < sound_tune_rows.size():
			var prefix := "> " if i == sound_tune_selected else "  "
			var label_text: String = prefix + String(setting["label"]) + ": " + str(snapped(value, 0.05))
			if id == "paddle_pitch" and _ball_audio_synth.has_method("get_paddle_pitch_note") and _ball_audio_synth.has_method("get_paddle_pitch_frequency"):
				label_text += "  [" + _ball_audio_synth.get_paddle_pitch_note() + " / " + str(int(round(_ball_audio_synth.get_paddle_pitch_frequency()))) + " Hz]"
			sound_tune_rows[i].text = label_text
			sound_tune_rows[i].modulate = Color(1.0, 0.95, 0.55, 1.0) if i == sound_tune_selected else Color(0.88, 0.88, 0.88, 1.0)
		if i < sound_tune_sliders.size():
			sound_tune_sliders[i].value = value
			sound_tune_sliders[i].modulate = Color(1.0, 0.85, 0.35, 1.0) if i == sound_tune_selected else Color(0.7, 0.7, 0.7, 1.0)


func _handle_sound_panel_input() -> void:
	if _ball_audio_synth == null:
		return
	if sound_tune_panel == null or not sound_tune_panel.visible:
		return

	if _consume_panel_key("up", KEY_UP):
		sound_tune_selected = wrapi(sound_tune_selected - 1, 0, sound_tune_settings.size())
		_refresh_sound_tune_panel()
	if _consume_panel_key("down", KEY_DOWN):
		sound_tune_selected = wrapi(sound_tune_selected + 1, 0, sound_tune_settings.size())
		_refresh_sound_tune_panel()
	if _consume_panel_key("left", KEY_LEFT):
		_adjust_sound_tuning(-0.05)
	if _consume_panel_key("right", KEY_RIGHT):
		_adjust_sound_tuning(0.05)


func _consume_panel_key(key_name: String, keycode: Key) -> bool:
	var pressed: bool = Input.is_key_pressed(keycode)
	var was_pressed: bool = _sound_panel_key_state.get(key_name, false)
	_sound_panel_key_state[key_name] = pressed
	return pressed and not was_pressed


func _adjust_sound_tuning(delta: float) -> void:
	if _ball_audio_synth == null:
		return
	var _setting: Dictionary = sound_tune_settings[sound_tune_selected]
	var id: String = _setting["id"]
	var tunings: Dictionary = _ball_audio_synth.get_sound_tunings()
	var next_value: float = clamp(tunings.get(id, 0.0) + delta, -1.0, 1.0)
	_ball_audio_synth.set_sound_tuning(id, next_value)
	_refresh_sound_tune_panel()


func _print_sound_tunings() -> void:
	if _ball_audio_synth == null:
		return
	var tunings: Dictionary = _ball_audio_synth.get_sound_tunings()
	print("")
	print("=== SOUND TUNINGS ===")
	for setting in sound_tune_settings:
		var id: String = setting["id"]
		print(setting["label"], ": ", snapped(float(tunings.get(id, 0.0)), 0.01))


func _on_slider_changed(idx: int, value: float) -> void:
	slider_changed.emit(idx, value)
	if _ball_audio_synth != null and idx < sound_tune_settings.size():
		var id: String = sound_tune_settings[idx]["id"]
		_ball_audio_synth.set_sound_tuning(id, value)
		_refresh_sound_tune_panel()
