## Transport bar UI and playback callbacks.
## Built and managed separately; returned to shell for parenting.

extends Control

signal transport_play_pressed()

var _transport_bar: Control
var _transport_play_btn: Button
var _transport_save_btn: Button
var _transport_phase_label: Label
var _transport_time_label: Label
var _transport_progress: ProgressBar

var _transition_player  # TransitionPlayer reference
var _play_callback: Callable
var _save_callback: Callable
var _playback_finished_callback: Callable

func set_transition_player(player) -> void:
	_transition_player = player
	_connect_transport_signals()

func set_play_callback(cb: Callable) -> void:
	_play_callback = cb

func set_save_callback(cb: Callable) -> void:
	_save_callback = cb

func set_playback_finished_callback(cb: Callable) -> void:
	_playback_finished_callback = cb

func build_transport_bar() -> Control:
	_transport_bar = Control.new()
	_transport_bar.name = "TransportBar"
	_transport_bar.anchor_left = 0.0
	_transport_bar.anchor_right = 1.0
	_transport_bar.anchor_top = 0.0
	_transport_bar.anchor_bottom = 1.0
	_transport_bar.offset_left = 0
	_transport_bar.offset_top = 0
	_transport_bar.offset_right = 0
	_transport_bar.offset_bottom = 0
	_transport_bar.z_index = 10
	_transport_bar.tree_entered.connect(_on_transport_bar_tree_entered)
	return _transport_bar

func _on_transport_bar_tree_entered() -> void:
	await self.ready
	_build_transport_bar_ui()
	_resize_transport_bar()

func _build_transport_bar_ui() -> void:
	if not _transport_bar:
		return

	var transport_panel := PanelContainer.new()
	transport_panel.anchor_right = 1.0
	transport_panel.anchor_bottom = 1.0
	transport_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.10, 0.14, 0.20, 0.97), Color(0.28, 0.40, 0.56, 0.95), 12))
	_transport_bar.add_child(transport_panel)

	var transport_m := MarginContainer.new()
	transport_m.anchor_right = 1.0
	transport_m.anchor_bottom = 1.0
	transport_m.add_theme_constant_override("margin_left", 16)
	transport_m.add_theme_constant_override("margin_right", 16)
	transport_m.add_theme_constant_override("margin_top", 10)
	transport_m.add_theme_constant_override("margin_bottom", 10)
	transport_panel.add_child(transport_m)

	var transport_hbox := HBoxContainer.new()
	transport_hbox.add_theme_constant_override("separation", 16)
	transport_m.add_child(transport_hbox)

	_transport_play_btn = Button.new()
	_transport_play_btn.custom_minimum_size = Vector2(80, 44)
	_transport_play_btn.text = "▶ Play"
	_transport_play_btn.pressed.connect(_on_transport_play)
	_transport_play_btn.add_theme_font_size_override("font_size", 16)
	_transport_play_btn.modulate = Color(0.31, 0.64, 0.62)
	transport_hbox.add_child(_transport_play_btn)

	_transport_save_btn = Button.new()
	_transport_save_btn.custom_minimum_size = Vector2(80, 44)
	_transport_save_btn.text = "💾 Save"
	_transport_save_btn.pressed.connect(_on_transport_save)
	_transport_save_btn.add_theme_font_size_override("font_size", 14)
	_transport_save_btn.modulate = Color(0.86, 0.73, 0.25)
	transport_hbox.add_child(_transport_save_btn)

	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(2, 30)
	transport_hbox.add_child(sep)

	var phase_vbox := VBoxContainer.new()
	phase_vbox.add_theme_constant_override("separation", 4)
	transport_hbox.add_child(phase_vbox)

	var phase_row := HBoxContainer.new()
	phase_row.add_theme_constant_override("separation", 8)
	phase_vbox.add_child(phase_row)

	var phase_title := Label.new()
	phase_title.text = "Phase:"
	phase_title.modulate = Color(0.72, 0.80, 0.90)
	phase_title.add_theme_font_size_override("font_size", 12)
	phase_row.add_child(phase_title)

	_transport_phase_label = Label.new()
	_transport_phase_label.text = "READY"
	_transport_phase_label.modulate = Color(0.97, 0.98, 1.0)
	_transport_phase_label.add_theme_font_size_override("font_size", 13)
	phase_row.add_child(_transport_phase_label)

	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 8)
	phase_vbox.add_child(time_row)

	var time_title := Label.new()
	time_title.text = "Time:"
	time_title.modulate = Color(0.72, 0.80, 0.90)
	time_title.add_theme_font_size_override("font_size", 12)
	time_row.add_child(time_title)

	_transport_time_label = Label.new()
	_transport_time_label.text = "0.00s / 1.10s"
	_transport_time_label.modulate = Color(0.85, 0.92, 1.0)
	_transport_time_label.add_theme_font_size_override("font_size", 13)
	time_row.add_child(_transport_time_label)

	var timeline_sep := VSeparator.new()
	timeline_sep.custom_minimum_size = Vector2(2, 30)
	transport_hbox.add_child(timeline_sep)

	_transport_progress = ProgressBar.new()
	_transport_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_transport_progress.custom_minimum_size = Vector2(200, 20)
	_transport_progress.step = 0.01
	_transport_progress.show_percentage = false
	_transport_progress.max_value = 1.0
	_transport_progress.value = 0.0
	var prog_style := StyleBoxFlat.new()
	prog_style.bg_color = Color(0.18, 0.24, 0.32, 0.9)
	prog_style.corner_radius_top_left = 4
	prog_style.corner_radius_top_right = 4
	prog_style.corner_radius_bottom_left = 4
	prog_style.corner_radius_bottom_right = 4
	_transport_progress.add_theme_stylebox_override("background", prog_style)
	var fg_style := StyleBoxFlat.new()
	fg_style.bg_color = Color(0.31, 0.64, 0.62, 0.9)
	fg_style.corner_radius_top_left = 4
	fg_style.corner_radius_top_right = 4
	fg_style.corner_radius_bottom_left = 4
	fg_style.corner_radius_bottom_right = 4
	_transport_progress.add_theme_stylebox_override("fill", fg_style)
	transport_hbox.add_child(_transport_progress)

	_connect_transport_signals()

func _resize_transport_bar() -> void:
	if not _transport_bar:
		return
	_transport_bar.anchor_left = 0.0
	_transport_bar.anchor_right = 0.65
	_transport_bar.offset_left = 0
	_transport_bar.offset_right = 0
	_transport_bar.anchor_top = 0.90
	_transport_bar.anchor_bottom = 1.0
	_transport_bar.offset_top = 0
	_transport_bar.offset_bottom = 0
	_transport_bar.z_index = 10

func _connect_transport_signals() -> void:
	if _transition_player:
		_transition_player.playback_started.connect(_on_transport_playback_started)
		_transition_player.playback_stopped.connect(_on_transport_playback_stopped)
		_transition_player.playback_finished.connect(_on_transport_playback_finished)
		_transition_player.phase_changed.connect(_on_transport_phase_changed)

func _on_transport_play() -> void:
	transport_play_pressed.emit()

func _on_transport_save() -> void:
	if _save_callback.is_valid():
		_save_callback.call()

func _on_transport_playback_started() -> void:
	if _transport_play_btn:
		_transport_play_btn.text = "⏸ Pause"
	_update_transport_ui()

func _on_transport_playback_stopped() -> void:
	if _transport_play_btn:
		_transport_play_btn.text = "▶ Play"
	_update_transport_ui()

func _on_transport_playback_finished() -> void:
	if _transport_play_btn:
		_transport_play_btn.text = "▶ Play"
	if _transport_phase_label:
		_transport_phase_label.text = "READY"
	if _transport_time_label:
		_transport_time_label.text = "0.00s / %.2fs" % 1.1
	if _transport_progress:
		_transport_progress.value = 0.0
	if _playback_finished_callback.is_valid():
		_playback_finished_callback.call()

func _on_transport_phase_changed(_new_phase: int) -> void:
	_update_transport_ui()

func _update_transport_ui() -> void:
	if not _transition_player:
		return
	var tp: TransitionPlayer = _transition_player as TransitionPlayer
	var phase: TransitionPlayer.Phase = tp.get_current_phase()
	var phase_idx: int = phase as int
	var phase_name := ""
	match phase_idx:
		0: phase_name = "CHARGE"
		1: phase_name = "CONTACT"
		2: phase_name = "FOLLOW_THROUGH"
		3: phase_name = "SETTLE"
		4: phase_name = "READY"
		_: phase_name = "?"
	if _transport_phase_label:
		_transport_phase_label.text = phase_name
	var total_dur: float = tp.get_total_duration()
	var current_time: float = tp.get_total_progress() * total_dur
	if _transport_time_label:
		_transport_time_label.text = "%.2fs / %.2fs" % [current_time, total_dur]
	if _transport_progress:
		_transport_progress.value = tp.get_total_progress()

func _make_panel_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.shadow_color = Color(0, 0, 0, 0.18)
	style.shadow_size = 6
	return style

func get_transport_bar() -> Control:
	return _transport_bar

func get_save_button() -> Button:
	return _transport_save_btn
