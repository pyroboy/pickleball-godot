class_name PostureEditorUI extends Control

## In-game posture editor UI — hotkey E toggles visibility.
##
## Features:
## - List of all 21 postures (click to load)
## - Editable fields for paddle position/rotation
## - "Play Transition" button: scrubs charge → contact → follow-through
## - Save button writes back to res://data/postures/*.tres
## - Interactive 3D gizmos for position and rotation editing
## - Bottom-docked editor sheet that keeps the 3D player visible above it

const DATA_DIR := "res://data/postures/"
const BASE_POSE_DATA_DIR := "res://data/base_poses/"
const READY_POSTURE_ID := 20
const CHARGE_FOREHAND_POSTURE_ID := 8
const CHARGE_BACKHAND_POSTURE_ID := 9

enum Workspace {
	STROKE_POSTURES,
	BASE_POSES,
}

enum LayoutPreset {
	HALF,
	WIDE,
}

signal editor_opened()
signal editor_closed()

var _library
var _base_pose_library
var _current_def = null
var _current_base_def = null
var _current_id: int = -1
var _is_dirty: bool = false
var _editor_restore_posture_id: int = -1
var _workspace_mode: int = Workspace.STROKE_POSTURES
var _layout_preset: int = LayoutPreset.HALF

# UI elements
var _posture_list: ItemList
var _mode_label: Label
var _status_label: Label
var _help_label: Label
var _workspace_button: Button
var _layout_button: Button
var _preview_context_option: OptionButton
var _tab_container: TabContainer
var _trigger_pose_button: Button
var _transition_button: Button
var _save_button: Button
var _solo_mode_button: Button
var _big_save_button: Button

# Tab containers
var _paddle_tab
var _legs_tab
var _arms_tab
var _head_tab
var _torso_tab
var _charge_tab
var _follow_through_tab

# Interactive 3D gizmos (Wave 1-2)
var _gizmo_controller
var _player: Node3D = null

# Pose trigger (Wave 3)
var _pose_trigger = null

# Transition player (Wave 4)
var _transition_player = null

# Transport bar (Wave 5)
var _transport_bar: Control
var _transport_play_btn: Button
var _transport_save_btn: Button
var _transport_phase_label: Label
var _transport_time_label: Label
var _transport_progress: ProgressBar

func _init() -> void:
	_library = load("res://scripts/posture_library.gd").new()
	_base_pose_library = load("res://scripts/base_pose_library.gd").new()

func _ready() -> void:
	# Right-side editor sheet so the player stays visible on the left.
	anchor_left = 0.65
	anchor_right = 0.98
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

	var panel := PanelContainer.new()
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.11, 0.15, 0.21, 0.96), Color(0.34, 0.47, 0.64, 0.95), 16))
	add_child(panel)

	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", _make_panel_style(Color(0.16, 0.2, 0.28, 0.95), Color(0.28, 0.4, 0.56, 0.95), 14))
	vbox.add_child(header)

	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 14)
	header_margin.add_theme_constant_override("margin_right", 14)
	header_margin.add_theme_constant_override("margin_top", 10)
	header_margin.add_theme_constant_override("margin_bottom", 10)
	header.add_child(header_margin)

	var header_vbox := VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 6)
	header_margin.add_child(header_vbox)

	# Title
	var title := Label.new()
	title.text = "Posture Editor"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = Color(0.97, 0.98, 1.0)
	header_vbox.add_child(title)

	var shortcut_label := Label.new()
	shortcut_label.text = "E or Esc close   •   G ghosts   •   P pose preview   •   Space swing preview"
	shortcut_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shortcut_label.modulate = Color(0.72, 0.8, 0.9)
	header_vbox.add_child(shortcut_label)

	_mode_label = Label.new()
	_mode_label.text = "Mode: Live"
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_label.add_theme_font_size_override("font_size", 14)
	_mode_label.modulate = Color(1.0, 0.92, 0.55)
	header_vbox.add_child(_mode_label)

	# Status label
	_status_label = Label.new()
	_status_label.text = "Select a posture to edit"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header_vbox.add_child(_status_label)

	_help_label = Label.new()
	_help_label.text = "Drag handles in the viewport to move body parts. Use Preview Pose for a static check, Preview Swing for motion."
	_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help_label.modulate = Color(0.76, 0.83, 0.92)
	header_vbox.add_child(_help_label)

	var workspace_row := HFlowContainer.new()
	workspace_row.add_theme_constant_override("separation", 10)
	header_vbox.add_child(workspace_row)

	_workspace_button = Button.new()
	_workspace_button.text = "Workspace: Stroke Postures"
	_workspace_button.pressed.connect(_on_toggle_workspace)
	workspace_row.add_child(_workspace_button)

	_layout_button = Button.new()
	_layout_button.pressed.connect(_on_toggle_layout_preset)
	workspace_row.add_child(_layout_button)

	var preview_label := Label.new()
	preview_label.text = "Preview State"
	preview_label.modulate = Color(0.83, 0.88, 0.96)
	workspace_row.add_child(preview_label)

	_preview_context_option = OptionButton.new()
	_preview_context_option.add_item("Live")
	_preview_context_option.add_item("Neutral")
	_preview_context_option.add_item("Incoming")
	_preview_context_option.add_item("Volley")
	_preview_context_option.add_item("Post-Bounce")
	_preview_context_option.add_item("Lunge")
	_preview_context_option.add_item("Jump")
	_preview_context_option.add_item("Landing")
	_preview_context_option.item_selected.connect(_on_preview_context_changed)
	workspace_row.add_child(_preview_context_option)

	var hsplit := HSplitContainer.new()
	hsplit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hsplit.split_offset = 300
	vbox.add_child(hsplit)

	var left_panel := PanelContainer.new()
	left_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.13, 0.18, 0.24, 0.97), Color(0.24, 0.34, 0.48, 0.95), 12))
	hsplit.add_child(left_panel)

	var left_margin := MarginContainer.new()
	left_margin.add_theme_constant_override("margin_left", 10)
	left_margin.add_theme_constant_override("margin_right", 10)
	left_margin.add_theme_constant_override("margin_top", 10)
	left_margin.add_theme_constant_override("margin_bottom", 10)
	left_panel.add_child(left_margin)

	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 8)
	left_margin.add_child(left_vbox)

	var left_title := Label.new()
	left_title.text = "Workspace Items"
	left_title.add_theme_font_size_override("font_size", 16)
	left_title.modulate = Color(0.97, 0.98, 1.0)
	left_vbox.add_child(left_title)

	var left_subtitle := Label.new()
	left_subtitle.text = "Select a stroke posture or base pose, then tweak it in the viewport or inspector."
	left_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_subtitle.modulate = Color(0.72, 0.8, 0.9)
	left_vbox.add_child(left_subtitle)

	_posture_list = ItemList.new()
	_posture_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_posture_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_posture_list.custom_minimum_size = Vector2(260, 200)
	_posture_list.item_selected.connect(_on_posture_selected)
	left_vbox.add_child(_posture_list)
	_populate_posture_list()

	var right_panel := PanelContainer.new()
	right_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.13, 0.18, 0.24, 0.97), Color(0.24, 0.34, 0.48, 0.95), 12))
	hsplit.add_child(right_panel)

	var right_margin := MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 10)
	right_margin.add_theme_constant_override("margin_right", 10)
	right_margin.add_theme_constant_override("margin_top", 10)
	right_margin.add_theme_constant_override("margin_bottom", 10)
	right_panel.add_child(right_margin)

	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 8)
	right_margin.add_child(right_vbox)

	var inspector_title := Label.new()
	inspector_title.text = "Inspector"
	inspector_title.add_theme_font_size_override("font_size", 16)
	inspector_title.modulate = Color(0.97, 0.98, 1.0)
	right_vbox.add_child(inspector_title)

	# Right: tabbed properties
	_tab_container = TabContainer.new()
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.tab_changed.connect(_on_tab_changed)
	right_vbox.add_child(_tab_container)
	
	# Create tabs
	_paddle_tab = load("res://scripts/posture_editor/tabs/paddle_tab.gd").new()
	_paddle_tab.name = "Paddle"
	_paddle_tab.field_changed.connect(_on_field_changed)
	_add_scroll_tab("Paddle", _paddle_tab)
	
	_legs_tab = load("res://scripts/posture_editor/tabs/legs_tab.gd").new()
	_legs_tab.name = "Legs"
	_legs_tab.field_changed.connect(_on_field_changed)
	_add_scroll_tab("Legs", _legs_tab)
	
	_arms_tab = load("res://scripts/posture_editor/tabs/arms_tab.gd").new()
	_arms_tab.name = "Arms"
	_arms_tab.field_changed.connect(_on_field_changed)
	_add_scroll_tab("Arms", _arms_tab)
	
	_head_tab = load("res://scripts/posture_editor/tabs/head_tab.gd").new()
	_head_tab.name = "Head"
	_head_tab.field_changed.connect(_on_field_changed)
	_add_scroll_tab("Head", _head_tab)
	
	_torso_tab = load("res://scripts/posture_editor/tabs/torso_tab.gd").new()
	_torso_tab.name = "Torso"
	_torso_tab.field_changed.connect(_on_field_changed)
	_add_scroll_tab("Torso", _torso_tab)

	_charge_tab = load("res://scripts/posture_editor/tabs/charge_tab.gd").new()
	_charge_tab.name = "Charge"
	_charge_tab.field_changed.connect(_on_field_changed)
	_add_scroll_tab("Charge", _charge_tab)

	_follow_through_tab = load("res://scripts/posture_editor/tabs/follow_through_tab.gd").new()
	_follow_through_tab.name = "Follow-Through"
	_follow_through_tab.field_changed.connect(_on_field_changed)
	_add_scroll_tab("Follow-Through", _follow_through_tab)

	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", _make_panel_style(Color(0.16, 0.2, 0.28, 0.97), Color(0.28, 0.4, 0.56, 0.95), 14))
	vbox.add_child(footer)

	var footer_margin := MarginContainer.new()
	footer_margin.add_theme_constant_override("margin_left", 10)
	footer_margin.add_theme_constant_override("margin_right", 10)
	footer_margin.add_theme_constant_override("margin_top", 10)
	footer_margin.add_theme_constant_override("margin_bottom", 10)
	footer.add_child(footer_margin)

	# Bottom buttons row (Preview Pose and Solo Mode only — Play/Save moved to transport bar)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	footer_margin.add_child(hbox)
	
	_trigger_pose_button = Button.new()
	_trigger_pose_button.text = "Preview Pose"
	_trigger_pose_button.pressed.connect(_on_trigger_pose)
	_trigger_pose_button.disabled = true
	_style_action_button(_trigger_pose_button, Color(0.33, 0.54, 0.76))
	hbox.add_child(_trigger_pose_button)

	_solo_mode_button = Button.new()
	_solo_mode_button.text = "Solo Mode: ON"
	_solo_mode_button.pressed.connect(_on_toggle_solo_mode)
	_style_action_button(_solo_mode_button, Color(0.52, 0.43, 0.74))
	hbox.add_child(_solo_mode_button)

	_big_save_button = null
	_update_save_button_state()
	_update_workspace_ui()
	# NOTE: right-side anchors (0.65-0.98) are set above in _ready().
	# _apply_layout_preset() is NOT called here — it's only for the old
	# bottom-docked HALF/WIDE presets triggered by the layout button.
	# Transport bar is built by _build_transport_bar() and added to the
	# canvas as a sibling of posture_editor_ui by game.gd.

## Builds the transport bar Control and returns it.
## Called by game.gd after posture_editor_ui is added to the canvas.
## The bar spans the LEFT 65% of the FULL viewport, bottom-aligned.
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
	# Build UI and set size once we have access to the parent viewport size.
	await get_tree().process_frame
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

	# Play / Stop button
	_transport_play_btn = Button.new()
	_transport_play_btn.custom_minimum_size = Vector2(80, 44)
	_transport_play_btn.text = "▶ Play"
	_transport_play_btn.pressed.connect(_on_transport_play)
	_transport_play_btn.add_theme_font_size_override("font_size", 16)
	_transport_play_btn.modulate = Color(0.31, 0.64, 0.62)
	transport_hbox.add_child(_transport_play_btn)

	# Save button
	_transport_save_btn = Button.new()
	_transport_save_btn.custom_minimum_size = Vector2(80, 44)
	_transport_save_btn.text = "💾 Save"
	_transport_save_btn.pressed.connect(_on_save)
	_transport_save_btn.add_theme_font_size_override("font_size", 14)
	_transport_save_btn.modulate = Color(0.86, 0.73, 0.25)
	transport_hbox.add_child(_transport_save_btn)

	# Phase separator
	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(2, 30)
	transport_hbox.add_child(sep)

	# Phase + time labels
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

	# Timeline progress bar
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

## Positions the transport bar to span the LEFT 65% of the full viewport,
## bottom-aligned (y: 0.90 → 1.0). Called after _build_transport_bar_ui().
func _resize_transport_bar() -> void:
	if not _transport_bar:
		return
	# Horizontal: span from viewport x=0 to x=0.65*W
	_transport_bar.anchor_left = 0.0
	_transport_bar.anchor_right = 0.65
	_transport_bar.offset_left = 0
	_transport_bar.offset_right = 0
	# Vertical: bottom 10% of viewport
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

func _populate_posture_list() -> void:
	_posture_list.clear()
	if _is_base_pose_mode():
		for def in _base_pose_library.all_definitions():
			_posture_list.add_item(def.display_name)
	else:
		for def in _library.all_definitions():
			_posture_list.add_item(def.display_name)

func _add_scroll_tab(title: String, content: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(margin)

	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(content)
	_tab_container.add_child(scroll)

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

func _style_action_button(button: Button, accent: Color, emphasize: bool = false) -> void:
	button.custom_minimum_size = Vector2(0, 40)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 15 if emphasize else 14)
	button.add_theme_color_override("font_color", Color(0.97, 0.98, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	button.add_theme_color_override("font_pressed_color", Color(1, 1, 1))

	var normal := StyleBoxFlat.new()
	normal.bg_color = accent.darkened(0.28)
	normal.border_color = accent.lightened(0.18)
	normal.set_border_width_all(1)
	normal.corner_radius_top_left = 10
	normal.corner_radius_top_right = 10
	normal.corner_radius_bottom_left = 10
	normal.corner_radius_bottom_right = 10
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	button.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = accent.darkened(0.14)
	button.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate()
	pressed.bg_color = accent.darkened(0.04)
	button.add_theme_stylebox_override("pressed", pressed)

	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.2, 0.24, 0.3, 0.8)
	disabled.border_color = Color(0.28, 0.33, 0.42, 0.9)
	button.add_theme_stylebox_override("disabled", disabled)

func _set_dirty(dirty: bool) -> void:
	_is_dirty = dirty
	_update_save_button_state()

func _update_save_button_state() -> void:
	if _save_button == null:
		return
	if _is_dirty:
		_save_button.text = "Save Changes"
		_save_button.add_theme_color_override("font_color", Color(1.0, 0.97, 0.8))
	else:
		_save_button.text = "Save to .tres"
		_save_button.add_theme_color_override("font_color", Color(0.97, 0.98, 1.0))

func _on_toggle_layout_preset() -> void:
	_layout_preset = LayoutPreset.WIDE if _layout_preset == LayoutPreset.HALF else LayoutPreset.HALF
	_apply_layout_preset()

func _apply_layout_preset() -> void:
	match _layout_preset:
		LayoutPreset.WIDE:
			anchor_left = 0.02
			anchor_right = 0.98
			anchor_top = 0.48
			anchor_bottom = 0.97
			if _layout_button:
				_layout_button.text = "Panel: Tall"
		_:
			anchor_left = 0.02
			anchor_right = 0.98
			anchor_top = 0.58
			anchor_bottom = 0.97
			if _layout_button:
				_layout_button.text = "Panel: Compact"

func _is_base_pose_mode() -> bool:
	return _workspace_mode == Workspace.BASE_POSES

func _current_body_resource():
	return _current_base_def if _is_base_pose_mode() else _current_def

func _current_display_name() -> String:
	var res = _current_body_resource()
	return res.display_name if res != null else ""

func _preview_context_base_pose_id() -> int:
	if not _player:
		return -1
	var preview_idx: int = _preview_context_option.selected if _preview_context_option else 0
	match preview_idx:
		1: return _player.BasePoseState.ATHLETIC_READY
		2: return _player.BasePoseState.SPLIT_STEP
		3: return _player.BasePoseState.PUNCH_VOLLEY_READY
		4: return _player.BasePoseState.GROUNDSTROKE_BASE
		5:
			if _current_def and _current_def.height_tier == 0:
				return _player.BasePoseState.LOW_SCOOP_LUNGE
			if _current_def and _current_def.family == 1:
				return _player.BasePoseState.BACKHAND_LUNGE
			return _player.BasePoseState.FOREHAND_LUNGE
		6: return _player.BasePoseState.JUMP_TAKEOFF
		7: return _player.BasePoseState.LANDING_RECOVERY
		_: return -1

func _preview_context_stroke_posture_id() -> int:
	if not _player:
		return READY_POSTURE_ID
	var preview_idx: int = _preview_context_option.selected if _preview_context_option else 0
	match preview_idx:
		1: return READY_POSTURE_ID
		2: return READY_POSTURE_ID
		3: return _player.PaddlePosture.VOLLEY_READY
		4: return _player.PaddlePosture.FORWARD
		5:
			if _current_def and _current_def.family == 1:
				return _player.PaddlePosture.WIDE_BACKHAND
			if _current_def and _current_def.height_tier == 0:
				return _player.PaddlePosture.LOW_WIDE_FOREHAND
			return _player.PaddlePosture.WIDE_FOREHAND
		6: return _player.PaddlePosture.HIGH_OVERHEAD
		7: return READY_POSTURE_ID
		_: return _current_def.posture_id if _current_def else READY_POSTURE_ID

func _preview_context_base_pose_def():
	if not _player:
		return null
	var base_pose_id := _preview_context_base_pose_id()
	if base_pose_id < 0:
		return null
	return _base_pose_library.get_def(base_pose_id)

func _build_preview_posture_for_editor():
	if not _player:
		return null
	if _is_base_pose_mode():
		if _current_base_def == null or not _player.pose_controller:
			return null
		return _player.pose_controller.compose_preview_posture(_current_base_def, _preview_context_stroke_posture_id())
	if _current_def == null:
		return null
	return _contextualize_posture_for_preview(_current_def)

func _contextualize_posture_for_preview(def):
	if def == null:
		return null
	var base_def = _preview_context_base_pose_def()
	if base_def == null:
		return def
	return base_def.to_preview_posture(def)

func _update_workspace_ui() -> void:
	if _workspace_button:
		_workspace_button.text = "Workspace: Base Poses" if _is_base_pose_mode() else "Workspace: Stroke Postures"
		if _tab_container:
			var hide_stroke_tabs: bool = _is_base_pose_mode()
			for control in [_paddle_tab, _charge_tab, _follow_through_tab]:
				if control == null:
					continue
				var scroll: Control = control.get_parent().get_parent() as Control if control.get_parent() else null
				if scroll == null:
					continue
				var idx := _tab_container.get_tab_idx_from_control(scroll)
				if idx >= 0:
					_tab_container.set_tab_hidden(idx, hide_stroke_tabs)
			if hide_stroke_tabs:
				var first_body_scroll = _legs_tab.get_parent().get_parent() if _legs_tab and _legs_tab.get_parent() else null
				var first_body_tab = _tab_container.get_tab_idx_from_control(first_body_scroll)
				if first_body_tab >= 0:
					_tab_container.current_tab = first_body_tab
	_populate_posture_list()
	if _transition_button:
		_transition_button.disabled = _is_base_pose_mode() or _current_def == null
	_update_mode_ui()

func _on_posture_selected(index: int) -> void:
	if _is_base_pose_mode():
		if index < 0 or index >= _base_pose_library.definitions.size():
			return
		_current_base_def = _base_pose_library.definitions[index]
		_current_def = null
		_current_id = _current_base_def.base_pose_id
	else:
		if index < 0 or index >= _library.definitions.size():
			return
		_current_def = _library.definitions[index]
		_current_base_def = null
		_current_id = _current_def.posture_id
	_status_label.text = "Selected: %s (ID: %d)" % [_current_display_name(), _current_id]
	_populate_properties()
	_trigger_pose_button.disabled = false
	if _transition_button:
		_transition_button.disabled = _is_base_pose_mode()
	if _save_button:
		_save_button.disabled = false
	
	_update_active_gizmos()
	
	# Immediately apply the selected posture to the player body.
	# This makes the player take the pose on selection, not just on "Preview".
	var preview_def = _build_preview_posture_for_editor() if _is_base_pose_mode() else _current_def
	if _player and _player.posture and preview_def:
		_player.posture.force_posture_update(preview_def)
		# Clear restore ID so the pose persists after the editor closes
		_editor_restore_posture_id = -1
	
	# Setup transition player
	if _player and not _is_base_pose_mode():
		_setup_transition_player()
		if _transition_player and _transition_player.is_playing():
			_transition_player.stop()
	if _pose_trigger and _pose_trigger.is_frozen():
		var trigger_def = _build_preview_posture_for_editor()
		if trigger_def:
			_pose_trigger.trigger_pose(trigger_def)
		
	if _player and _player.posture and not _is_base_pose_mode():
		_player.posture.selected_posture_id = _current_id
	_update_mode_ui()

func _populate_properties() -> void:
	var body_def = _current_body_resource()
	if body_def == null:
		return
	
	# Update all tabs
	if not _is_base_pose_mode():
		_paddle_tab.set_definition(_current_def)
		_charge_tab.set_definition(_current_def)
		_follow_through_tab.set_definition(_current_def)
	_legs_tab.set_definition(body_def)
	_arms_tab.set_definition(body_def)
	_head_tab.set_definition(body_def)
	_torso_tab.set_definition(body_def)

func _on_field_changed(_field_name: String, _value: Variant) -> void:
	if _current_body_resource() == null:
		return
	_status_label.text = "Modified: %s" % _current_display_name()
	_set_dirty(true)
	_refresh_live_preview()
	_update_mode_ui()

func _on_trigger_pose() -> void:
	if not _player:
		return
	var preview_def = _build_preview_posture_for_editor()
	if preview_def == null:
		return
	
	if not _pose_trigger:
		_pose_trigger = load("res://scripts/posture_editor/pose_trigger.gd").new(_player)
	
	if _transition_player and _transition_player.is_playing():
		_transition_player.stop()
	
	if _pose_trigger.is_frozen():
		_pose_trigger.release_pose()
		_restore_live_posture_from_editor()
		_status_label.text = "Returned to live gameplay"
	else:
		_capture_live_restore_posture()
		_pose_trigger.trigger_pose(preview_def)
		_status_label.text = "Previewing static pose for %s" % _current_display_name()
	_update_mode_ui()

func _setup_transition_player() -> void:
	if not _player or not _current_def or _is_base_pose_mode():
		return
	
	if not _transition_player:
		_transition_player = load("res://scripts/posture_editor/transition_player.gd").new()
		add_child(_transition_player)
		_transition_player.playback_started.connect(_on_transition_preview_started)
		_transition_player.playback_stopped.connect(_on_transition_preview_ended)
		_transition_player.playback_finished.connect(_on_transition_preview_ended)
		_connect_transport_signals()
	
	var ready_def = _contextualize_posture_for_preview(_library.get_def(READY_POSTURE_ID))
	var charge_def = _contextualize_posture_for_preview(_build_charge_preview_def(_current_def))
	var contact_def = _contextualize_posture_for_preview(_current_def)
	var ft_defs = _build_follow_through_preview_defs(_current_def)
	var preview_ft_defs = []
	for ft_def in ft_defs:
		preview_ft_defs.append(_contextualize_posture_for_preview(ft_def))
	_transition_player.setup(_player, ready_def, charge_def, contact_def, preview_ft_defs)

func _on_play_transition() -> void:
	if _is_base_pose_mode():
		return
	if not _transition_player:
		_setup_transition_player()
	elif _current_def:
		_setup_transition_player()
	
	if not _transition_player:
		return
	
	if _transition_player.is_playing():
		_transition_player.pause()
		_status_label.text = "Swing preview paused"
	else:
		if not _current_def:
			return
		_capture_live_restore_posture()
		if _pose_trigger and _pose_trigger.is_frozen():
			_pose_trigger.release_pose()
		_transition_player.play()
		_status_label.text = "Previewing swing for %s" % _current_display_name()
	_update_mode_ui()

# ── Transport bar callbacks (Wave 5) ──────────────────────────────────────────

func _on_transport_play() -> void:
	# Delegate to the existing swing preview logic
	_on_play_transition()

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

func _on_save() -> void:
	var path: String = ""
	var filename: String = ""
	if _is_base_pose_mode():
		if _current_base_def == null:
			return
		filename = _filename_for_base_pose(_current_base_def)
		path = BASE_POSE_DATA_DIR + filename
	else:
		if _current_def == null:
			return
		filename = _filename_for(_current_def)
		path = DATA_DIR + filename
	var err := ResourceSaver.save(_current_body_resource(), path)
	if err == OK:
		_status_label.text = "Saved: %s" % filename
		_set_dirty(false)
		print("[POSTURE EDITOR] Saved ", path)
	else:
		_status_label.text = "Save failed: error %d" % err
		push_error("PostureEditor: failed to save " + path)
	_update_mode_ui()

func _filename_for_base_pose(def):
	var base: String = def.display_name.to_lower().replace(" ", "_").replace("-", "_")
	return "%02d_%s.tres" % [def.base_pose_id, base]

func _filename_for(def):
	var base: String = def.display_name.to_lower().replace(" ", "_").replace("-", "_")
	return "%02d_%s.tres" % [def.posture_id, base]

func _on_toggle_workspace() -> void:
	_workspace_mode = Workspace.BASE_POSES if not _is_base_pose_mode() else Workspace.STROKE_POSTURES
	_current_def = null
	_current_base_def = null
	_current_id = -1
	if _gizmo_controller:
		_gizmo_controller.clear_all_gizmos()
	if _pose_trigger and _pose_trigger.is_frozen():
		_pose_trigger.release_pose()
		_restore_live_posture_from_editor()
	_set_dirty(false)
	_trigger_pose_button.disabled = true
	if _transition_button:
		_transition_button.disabled = true
	if _save_button:
		_save_button.disabled = true
	_status_label.text = "Select a %s to edit" % ("base pose" if _is_base_pose_mode() else "stroke posture")
	_update_active_gizmos()
	_update_workspace_ui()

func _on_preview_context_changed(_index: int) -> void:
	if _pose_trigger and _pose_trigger.is_frozen():
		var preview_def = _build_preview_posture_for_editor()
		if preview_def:
			_pose_trigger.refresh_from_definition(preview_def)
	elif _transition_player and _transition_player.is_playing():
		_setup_transition_player()
	_update_mode_ui()

func _on_toggle_solo_mode() -> void:
	if not _player or not _player.posture:
		return
	
	_player.posture.solo_mode = not _player.posture.solo_mode
	_update_solo_mode_ui()

func _update_solo_mode_ui() -> void:
	if not _player or not _player.posture:
		return
	
	var enabled: bool = _player.posture.solo_mode
	_solo_mode_button.text = "Solo Mode: ON" if enabled else "Solo Mode: OFF"
	if enabled:
		_solo_mode_button.add_theme_color_override("font_color", Color(1, 1, 0))
	else:
		_solo_mode_button.remove_theme_color_override("font_color")

# ── Interactive 3D Gizmos (Wave 1-2) ────────────────────────────────────────

func set_player(player: Node3D) -> void:
	_player = player
	_update_solo_mode_ui()
	_create_gizmo_controller()

func _create_gizmo_controller() -> void:
	# Remove old gizmo system if exists
	if _gizmo_controller:
		_gizmo_controller.queue_free()
	
	_gizmo_controller = load("res://scripts/posture_editor/gizmo_controller.gd").new()
	_gizmo_controller.name = "GizmoController"
	
	# Add to player's parent (world space)
	if _player and _player.get_parent():
		_player.get_parent().add_child(_gizmo_controller)
	else:
		get_tree().root.add_child(_gizmo_controller)
	
	# Connect signals
	_gizmo_controller.gizmo_selected.connect(_on_gizmo_selected)
	_gizmo_controller.gizmo_moved.connect(_on_gizmo_moved)
	_gizmo_controller.gizmo_rotated.connect(_on_gizmo_rotated)
	
	# Set camera reference
	var camera := get_viewport().get_camera_3d()
	if camera:
		_gizmo_controller.set_camera(camera)
	
	# Only create gizmos if player is ready (in tree AND has valid global transform)
	var can_create_gizmos := false
	if _player and _player.is_inside_tree():
		# Also verify player has valid global position (not zero or very small means initialized)
		if _player.global_position.length() > 0.01:
			can_create_gizmos = true
	
	if can_create_gizmos:
		_update_active_gizmos()
	_update_gizmo_visibility()

# Deprecated - replaced by _update_active_gizmos logic
func _create_position_gizmos() -> void:
	pass

func get_current_paddle_position() -> Vector3:
	if _current_def != null and not _is_base_pose_mode():
		return _calculate_paddle_world_position(_current_def)
	return Vector3.INF

func _calculate_paddle_world_position(def):
	if not _player or not _player.is_inside_tree():
		return Vector3.ZERO
	
	var player_pos: Vector3 = _player.global_position
	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	
	# Guard against uninitialized axes (magnitude ~0 means not set up yet)
	if forward_axis.length() < 0.01 or forehand_axis.length() < 0.01:
		return Vector3.ZERO
	
	var offset: Vector3 = forehand_axis * def.paddle_forehand_mul + forward_axis * def.paddle_forward_mul + Vector3(0.0, def.paddle_y_offset, 0.0)
	return player_pos + offset

func _color_for_family(family: int) -> Color:
	match family:
		0: return Color(0.3, 0.9, 0.3)   # Forehand: green
		1: return Color(0.9, 0.3, 0.3)   # Backhand: red
		2: return Color(0.3, 0.3, 0.9)   # Center: blue
		3: return Color(0.9, 0.9, 0.3)   # Overhead: yellow
		_: return Color(0.7, 0.7, 0.7)   # Default: gray

func _on_gizmo_selected(gizmo) -> void:
	# Select corresponding posture in list
	if gizmo.posture_id >= 0:
		var defs = _base_pose_library.definitions if _is_base_pose_mode() else _library.definitions
		for i in range(defs.size()):
			var def = defs[i]
			var def_id: int = def.base_pose_id if _is_base_pose_mode() else def.posture_id
			if def_id == gizmo.posture_id:
				_posture_list.select(i)
				_on_posture_selected(i)
				break

func _on_gizmo_moved(gizmo, new_position: Vector3) -> void:
	var body_def = _current_body_resource()
	if body_def == null or gizmo.posture_id != _current_id:
		return
	
	# Convert world position back to posture definition values
	if _player:
		var forward_axis: Vector3 = _player._get_forward_axis()
		var forehand_axis: Vector3 = _player._get_forehand_axis()
		var player_pos := _player.global_position
		var offset: Vector3 = new_position - player_pos
		
		# Identify field type and apply
		match gizmo.field_name:
			"paddle_position":
				if _current_def:
					_current_def.paddle_forehand_mul = offset.dot(forehand_axis)
					_current_def.paddle_forward_mul = offset.dot(forward_axis)
					_current_def.paddle_y_offset = offset.y
			"right_hand_offset":
				var base_pos = _player.paddle_node.to_global(Vector3(0, 0.07, 0))
				var local_delta = new_position - base_pos
				body_def.right_hand_offset = Vector3(
					local_delta.dot(forehand_axis),
					local_delta.dot(Vector3.UP),
					local_delta.dot(forward_axis)
				)
			"left_hand_offset":
				var base_pos: Vector3
				match body_def.left_hand_mode:
					1: base_pos = _player.paddle_node.to_global(Vector3(0, 0.20, 0))
					2: base_pos = _player.global_position + forehand_axis * -0.2 + forward_axis * 0.2 + Vector3(0, 0.45, 0)
					3: base_pos = _player.global_position + Vector3(0, 1.05, 0) + forward_axis * 0.15
					_: base_pos = _player.global_position # Fallback
				var local_delta = new_position - base_pos
				body_def.left_hand_offset = Vector3(
					local_delta.dot(forehand_axis),
					local_delta.dot(Vector3.UP),
					local_delta.dot(forward_axis)
				)
			"right_foot_offset":
				var side := 1.0
				var base_pos: Vector3 = player_pos + forehand_axis * side * body_def.stance_width * 0.5
				var local_delta = new_position - base_pos
				body_def.right_foot_offset = Vector3(
					local_delta.dot(forehand_axis),
					local_delta.dot(Vector3.UP),
					local_delta.dot(forward_axis)
				)
			"left_foot_offset":
				var side := -1.0
				var base_pos: Vector3 = player_pos + forehand_axis * side * body_def.stance_width * 0.5
				var local_delta = new_position - base_pos
				body_def.left_foot_offset = Vector3(
					local_delta.dot(forehand_axis),
					local_delta.dot(Vector3.UP),
					local_delta.dot(forward_axis)
				)

		_set_dirty(true)
		_populate_properties()
		_status_label.text = "Updated: %s position" % _current_display_name()
		_refresh_live_preview()

func _on_gizmo_rotated(gizmo, euler_delta: Vector3) -> void:
	var body_def = _current_body_resource()
	if body_def == null or gizmo.posture_id != _current_id:
		return
	
	_set_dirty(true)
	
	match gizmo.field_name:
		"hip_rotation":
			body_def.hip_yaw_deg += euler_delta.y
		"torso_rotation":
			body_def.torso_pitch_deg += euler_delta.x
			body_def.torso_yaw_deg += euler_delta.y
			body_def.torso_roll_deg += euler_delta.z
		"head_rotation":
			body_def.head_pitch_deg += euler_delta.x
			body_def.head_yaw_deg += euler_delta.y
		"body_pivot_rotation":
			body_def.body_pitch_deg += euler_delta.x
			body_def.body_yaw_deg += euler_delta.y
			body_def.body_roll_deg += euler_delta.z
	
	_populate_properties()
	_refresh_live_preview()

func _on_tab_changed(_tab_index: int) -> void:
	_update_active_gizmos()

func _update_active_gizmos() -> void:
	var body_def = _current_body_resource()
	if not _gizmo_controller or body_def == null:
		return
	
	_gizmo_controller.clear_all_gizmos()

	if not _is_base_pose_mode():
		_create_paddle_gizmos()
	_create_torso_gizmos()
	_create_head_gizmos()
	_create_arm_gizmos()
	_create_leg_gizmos()
	
	_update_gizmo_visibility()

func _create_paddle_gizmos() -> void:
	if _is_base_pose_mode() or _current_def == null:
		return
	var def = _current_def
	var pos = _calculate_paddle_world_position(def)
	
	var gizmo = load("res://scripts/posture_editor/position_gizmo.gd").new()
	gizmo.name = "PositionGizmo_Paddle"
	gizmo.posture_id = def.posture_id
	gizmo.field_name = "paddle_position"
	gizmo.tab_name = "Paddle"
	gizmo.gizmo_color = _color_for_family(def.family)
	gizmo.gizmo_size = 0.08
	gizmo.global_position = pos
	_gizmo_controller.add_gizmo_handle(gizmo)

func _create_torso_gizmos() -> void:
	if not _player or not _player.skeleton: return
	
	# Hips Rotation
	var hip_idx: int = _player.skeleton.find_bone("hips")
	if hip_idx >= 0:
		var hip_pos: Vector3 = _player.skeleton.to_global(_player.skeleton.get_bone_global_pose(hip_idx).origin)
		var gizmo = load("res://scripts/posture_editor/rotation_gizmo.gd").new()
		gizmo.name = "RotationGizmo_Hips"
		gizmo.posture_id = _current_id
		gizmo.field_name = "hip_rotation"
		gizmo.tab_name = "Torso"
		gizmo.gizmo_color = Color(0, 1, 1)
		gizmo.ring_radius = 0.3
		gizmo.global_position = hip_pos
		_gizmo_controller.add_gizmo_handle(gizmo)
	
	# Torso/Chest Rotation
	var chest_idx: int = _player.skeleton.find_bone("chest")
	if chest_idx >= 0:
		var chest_pos: Vector3 = _player.skeleton.to_global(_player.skeleton.get_bone_global_pose(chest_idx).origin)
		var gizmo = load("res://scripts/posture_editor/rotation_gizmo.gd").new()
		gizmo.name = "RotationGizmo_Torso"
		gizmo.posture_id = _current_id
		gizmo.field_name = "torso_rotation"
		gizmo.tab_name = "Torso"
		gizmo.gizmo_color = Color(1, 0.5, 0)
		gizmo.ring_radius = 0.25
		gizmo.global_position = chest_pos
		_gizmo_controller.add_gizmo_handle(gizmo)

func _create_head_gizmos() -> void:
	if not _player or not _player.skeleton: return
	
	var head_idx: int = _player.skeleton.find_bone("head")
	if head_idx >= 0:
		var head_pos: Vector3 = _player.skeleton.to_global(_player.skeleton.get_bone_global_pose(head_idx).origin)
		var gizmo = load("res://scripts/posture_editor/rotation_gizmo.gd").new()
		gizmo.name = "RotationGizmo_Head"
		gizmo.posture_id = _current_id
		gizmo.field_name = "head_rotation"
		gizmo.tab_name = "Head"
		gizmo.gizmo_color = Color(1, 1, 1)
		gizmo.ring_radius = 0.15
		gizmo.global_position = head_pos
		_gizmo_controller.add_gizmo_handle(gizmo)

func _create_arm_gizmos() -> void:
	if not _player or not _player.paddle_node: return
	
	var def = _current_body_resource()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	var forward_axis: Vector3 = _player._get_forward_axis()
	
	# 1. Right hand target
	var r_base = _player.paddle_node.to_global(Vector3(0, 0.07, 0))
	var r_pos = r_base + load("res://scripts/posture_skeleton_applier.gd").stance_offset(def.right_hand_offset, forehand_axis, forward_axis)
	var r_gizmo = load("res://scripts/posture_editor/position_gizmo.gd").new()
	r_gizmo.name = "PositionGizmo_RightHand"
	r_gizmo.posture_id = _current_id
	r_gizmo.field_name = "right_hand_offset"
	r_gizmo.tab_name = "Arms"
	r_gizmo.gizmo_color = Color(1, 1, 0)
	r_gizmo.global_position = r_pos
	_gizmo_controller.add_gizmo_handle(r_gizmo)
	
	# 2. Left hand target
	var l_base: Vector3
	match def.left_hand_mode:
		1: l_base = _player.paddle_node.to_global(Vector3(0, 0.20, 0))
		2: l_base = _player.global_position + forehand_axis * -0.2 + forward_axis * 0.2 + Vector3(0, 0.45, 0)
		3: l_base = _player.global_position + Vector3(0, 1.05, 0) + forward_axis * 0.15
		_: l_base = _player.global_position
	var l_pos = l_base + load("res://scripts/posture_skeleton_applier.gd").stance_offset(def.left_hand_offset, forehand_axis, forward_axis)
	var l_gizmo = load("res://scripts/posture_editor/position_gizmo.gd").new()
	l_gizmo.name = "PositionGizmo_LeftHand"
	l_gizmo.posture_id = _current_id
	l_gizmo.field_name = "left_hand_offset"
	l_gizmo.tab_name = "Arms"
	l_gizmo.gizmo_color = Color(0, 1, 1)
	l_gizmo.global_position = l_pos
	_gizmo_controller.add_gizmo_handle(l_gizmo)

func _create_leg_gizmos() -> void:
	if not _player: return
	
	var def = _current_body_resource()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	var forward_axis: Vector3 = _player._get_forward_axis()
	var player_pos := _player.global_position
	
	# 1. Right Foot
	var r_stance: Vector3 = forehand_axis * 0.5 * def.stance_width
	var r_pos = player_pos + r_stance + load("res://scripts/posture_skeleton_applier.gd").stance_offset(def.right_foot_offset, forehand_axis, forward_axis)
	var r_gizmo = load("res://scripts/posture_editor/position_gizmo.gd").new()
	r_gizmo.name = "PositionGizmo_RightFoot"
	r_gizmo.posture_id = _current_id
	r_gizmo.field_name = "right_foot_offset"
	r_gizmo.tab_name = "Legs"
	r_gizmo.gizmo_color = Color(0.9, 0.3, 0.9)
	r_gizmo.global_position = r_pos
	_gizmo_controller.add_gizmo_handle(r_gizmo)
	
	# 2. Left Foot
	var l_stance: Vector3 = forehand_axis * -0.5 * def.stance_width
	var l_pos = player_pos + l_stance + load("res://scripts/posture_skeleton_applier.gd").stance_offset(def.left_foot_offset, forehand_axis, forward_axis)
	var l_gizmo = load("res://scripts/posture_editor/position_gizmo.gd").new()
	l_gizmo.name = "PositionGizmo_LeftFoot"
	l_gizmo.posture_id = _current_id
	l_gizmo.field_name = "left_foot_offset"
	l_gizmo.tab_name = "Legs"
	l_gizmo.gizmo_color = Color(0.3, 0.3, 0.9)
	l_gizmo.global_position = l_pos
	_gizmo_controller.add_gizmo_handle(l_gizmo)

func _refresh_live_preview() -> void:
	var preview_def = _build_preview_posture_for_editor()
	if preview_def == null or _player == null or not _player.posture:
		return
	if _pose_trigger and _pose_trigger.is_frozen():
		_pose_trigger.refresh_from_definition(preview_def)
	else:
		# Avoid hijacking live gameplay when the editor is open but pose is released.
		if Engine.time_scale < 0.001:
			_player.posture.force_posture_update(preview_def)

func _update_gizmo_positions() -> void:
	var body_def = _current_body_resource()
	if not _gizmo_controller or not _player or body_def == null:
		return
	if not _player.skeleton: return
	
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	var forward_axis: Vector3 = _player._get_forward_axis()
	
	for gizmo in _gizmo_controller.get_children():
		if not gizmo.has_method("get_posture_id"): continue
		if _gizmo_controller.get_selected_gizmo() == gizmo: continue
		
		match gizmo.field_name:
			"paddle_position":
				if _current_def:
					gizmo.global_position = _calculate_paddle_world_position(_current_def)
			"hip_rotation":
				var idx: int = _player.skeleton.find_bone("hips")
				if idx >= 0: gizmo.global_position = _player.skeleton.to_global(_player.skeleton.get_bone_global_pose(idx).origin)
			"torso_rotation":
				var idx: int = _player.skeleton.find_bone("chest")
				if idx >= 0: gizmo.global_position = _player.skeleton.to_global(_player.skeleton.get_bone_global_pose(idx).origin)
			"head_rotation":
				var idx: int = _player.skeleton.find_bone("head")
				if idx >= 0: gizmo.global_position = _player.skeleton.to_global(_player.skeleton.get_bone_global_pose(idx).origin)
			"right_hand_offset":
				var base = _player.paddle_node.to_global(Vector3(0, 0.07, 0))
				gizmo.global_position = base + load("res://scripts/posture_skeleton_applier.gd").stance_offset(body_def.right_hand_offset, forehand_axis, forward_axis)
			"left_hand_offset":
				var l_base: Vector3
				match body_def.left_hand_mode:
					1: l_base = _player.paddle_node.to_global(Vector3(0, 0.20, 0))
					2: l_base = _player.global_position + forehand_axis * -0.2 + forward_axis * 0.2 + Vector3(0, 0.45, 0)
					3: l_base = _player.global_position + Vector3(0, 1.05, 0) + forward_axis * 0.15
					_: l_base = _player.global_position
				gizmo.global_position = l_base + load("res://scripts/posture_skeleton_applier.gd").stance_offset(body_def.left_hand_offset, forehand_axis, forward_axis)
			"right_foot_offset":
				var base = _player.global_position + forehand_axis * 0.5 * body_def.stance_width
				gizmo.global_position = base + load("res://scripts/posture_skeleton_applier.gd").stance_offset(body_def.right_foot_offset, forehand_axis, forward_axis)
			"left_foot_offset":
				var base = _player.global_position + forehand_axis * -0.5 * body_def.stance_width
				gizmo.global_position = base + load("res://scripts/posture_skeleton_applier.gd").stance_offset(body_def.left_foot_offset, forehand_axis, forward_axis)

func _update_gizmo_visibility() -> void:
	if _gizmo_controller:
		_gizmo_controller.visible = visible
		if visible:
			# Get current tab name to filter gizmos
			var current_tab_name := ""
			if _tab_container:
				var current_tab_control = _tab_container.get_child(_tab_container.current_tab)
				if current_tab_control:
					current_tab_name = current_tab_control.name
			
			for gizmo in _gizmo_controller.get_children():
				if not gizmo.has_method("get_posture_id"): continue
				var gh: GizmoHandle = gizmo as GizmoHandle
				# Filter by posture_id AND tab_name (empty tab_name = show on all tabs)
				var posture_match: bool = (gh.posture_id == _current_id)
				var tab_match: bool = (gh.tab_name == "") or (gh.tab_name == current_tab_name)
				gizmo.visible = posture_match and tab_match

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		# Create gizmos if needed when editor becomes visible
		if visible and _player and _player.is_inside_tree():
			if _player.global_position.length() > 0.01:
				if _gizmo_controller and _gizmo_controller.get_child_count() == 0:
					_update_active_gizmos()
		
		_update_gizmo_visibility()
		if visible and _player:
			_update_gizmo_positions()
			_update_mode_ui()
		elif not visible:
			_teardown_preview_state()
		
		# Emit signals for game.gd to handle camera and UI
		if visible:
			editor_opened.emit()
		else:
			editor_closed.emit()

func _process(_delta: float) -> void:
	if _pose_trigger:
		_pose_trigger.update()
		
	# Update gizmo positions when editor is visible (except selected gizmo)
	if visible and _player:
		_update_gizmo_positions()

func _input(event: InputEvent) -> void:
	if not visible:
		return
		
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_G:
			_on_toggle_solo_mode()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_P:
			_on_trigger_pose()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE:
			_on_play_transition()
			get_viewport().set_input_as_handled()

func _build_charge_preview_def(def):
	if def == null:
		return null
	if def.family == 0:
		var fh_charge = _library.get_def(CHARGE_FOREHAND_POSTURE_ID)
		if fh_charge != null:
			return fh_charge
	elif def.family == 1:
		var bh_charge = _library.get_def(CHARGE_BACKHAND_POSTURE_ID)
		if bh_charge != null:
			return bh_charge

	var preview = _copy_definition(def)
	if preview == null:
		return null
	preview.display_name = "%s Charge Preview" % def.display_name
	preview.paddle_forehand_mul += def.charge_paddle_offset.x
	preview.paddle_y_offset += def.charge_paddle_offset.y
	preview.paddle_forward_mul += def.charge_paddle_offset.z
	preview.paddle_pitch_base_deg += def.charge_paddle_rotation_deg.x
	preview.paddle_yaw_base_deg += def.charge_paddle_rotation_deg.y
	preview.paddle_roll_base_deg += def.charge_paddle_rotation_deg.z
	preview.body_yaw_deg += def.charge_body_rotation_deg
	preview.hip_yaw_deg += def.charge_hip_coil_deg
	return preview

func _build_follow_through_preview_defs(def):
	var results = []
	if def == null:
		return results

	var follow = _copy_definition(def)
	if follow == null:
		return results

	follow.display_name = "%s Follow-Through" % def.display_name
	follow.paddle_forehand_mul += def.ft_paddle_offset.x
	follow.paddle_y_offset += def.ft_paddle_offset.y
	follow.paddle_forward_mul += def.ft_paddle_offset.z
	follow.paddle_pitch_base_deg += def.ft_paddle_rotation_deg.x
	follow.paddle_yaw_base_deg += def.ft_paddle_rotation_deg.y
	follow.paddle_roll_base_deg += def.ft_paddle_rotation_deg.z
	follow.hip_yaw_deg += def.ft_hip_uncoil_deg
	results.append(follow)
	return results

func _copy_definition(def):
	if def == null:
		return null
	return def.lerp_with(def, 0.0)

func _update_mode_ui() -> void:
	var mode := "Live"
	if _transition_player and _transition_player.is_playing():
		mode = "Preview Swing"
	elif _pose_trigger and _pose_trigger.is_frozen():
		mode = "Preview Pose"
	var item_word := "base pose" if _is_base_pose_mode() else "posture"

	if _mode_label:
		_mode_label.text = "Mode: %s" % mode
	if _trigger_pose_button:
		_trigger_pose_button.text = "Resume Live" if _pose_trigger and _pose_trigger.is_frozen() else "Preview %s" % ("Base Pose" if _is_base_pose_mode() else "Pose")
	if _transition_button:
		_transition_button.text = "Pause Swing" if _transition_player and _transition_player.is_playing() else "Preview Swing"
		_transition_button.disabled = _is_base_pose_mode() or _current_def == null
	if _help_label:
		match mode:
			"Preview Pose":
				_help_label.text = "Static preview is active. Drag handles to adjust the selected %s, or Resume Live to return to gameplay." % item_word
			"Preview Swing":
				_help_label.text = "Swing preview is active. Use Space to pause, P to switch back to a static pose, and G to toggle ghost clutter."
			_:
				if _is_base_pose_mode():
					_help_label.text = "Select a base pose, choose a preview state, then use Preview Base Pose. Drag handles in the viewport to shape stance, arms, torso, and head."
				else:
					_help_label.text = "Select a posture, then use Preview Pose or Preview Swing. Preview State lets you see the stroke against different base-pose contexts."

func _teardown_preview_state() -> void:
	if _transition_player:
		_transition_player.stop()
	if _pose_trigger and _pose_trigger.is_frozen():
		_pose_trigger.release_pose()
	_restore_live_posture_from_editor()
	_editor_restore_posture_id = -1
	_update_mode_ui()

func _capture_live_restore_posture() -> void:
	if _editor_restore_posture_id >= 0:
		return
	if _player and _player.posture:
		_editor_restore_posture_id = _player.posture.paddle_posture

func _restore_live_posture_from_editor() -> void:
	if _editor_restore_posture_id < 0 or not _player:
		return
	_player.paddle_posture = _editor_restore_posture_id

func _on_transition_preview_started() -> void:
	_update_mode_ui()

func _on_transition_preview_ended() -> void:
	if not (_pose_trigger and _pose_trigger.is_frozen()):
		_restore_live_posture_from_editor()
	_update_mode_ui()
