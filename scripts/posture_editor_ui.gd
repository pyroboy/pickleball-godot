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

# ── Sub-modules ───────────────────────────────────────────────────────────────

var _state  # PostureEditorState (loaded via load())
var _preview  # PostureEditorPreview (loaded via load())
var _transport  # PostureEditorTransport (loaded via load())
var _gizmos  # PostureEditorGizmos (loaded via load())

# ── UI elements ────────────────────────────────────────────────────────────────

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

# Tab content (loaded from files)
var _paddle_tab
var _legs_tab
var _arms_tab
var _head_tab
var _torso_tab
var _charge_tab
var _follow_through_tab

# ── Inline state (not extracted) ─────────────────────────────────────────────

var _library
var _base_pose_library
var _player: Node3D = null

# ── Init ──────────────────────────────────────────────────────────────────────

func _init() -> void:
	_library = load("res://scripts/posture_library.gd").new()
	_base_pose_library = load("res://scripts/base_pose_library.gd").new()
	_state = load("res://scripts/posture_editor/posture_editor_state.gd").new()
	_preview = load("res://scripts/posture_editor/posture_editor_preview.gd").new()
	_transport = load("res://scripts/posture_editor/posture_editor_transport.gd").new()
	_gizmos = load("res://scripts/posture_editor/posture_editor_gizmos.gd").new()

# ── Ready ─────────────────────────────────────────────────────────────────────

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

	_init_preview()
	_init_transport()
	_init_gizmos()

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

	var header := _make_header()
	vbox.add_child(header)

	var hsplit := _make_main_split()
	vbox.add_child(hsplit)

	var footer := _make_footer()
	vbox.add_child(footer)

	# State needs all UI elements created first
	_state.init(_library, _base_pose_library, _posture_list, _save_button, _status_label, _transition_button, _trigger_pose_button)

	_update_workspace_ui()

# ── Module init helpers ────────────────────────────────────────────────────────

func _init_preview() -> void:
	_preview.init(_player, _library, _base_pose_library, _state)

func _init_transport() -> void:
	_transport.set_play_callback(Callable(self, "_on_play_transition"))
	_transport.set_save_callback(Callable(self, "_on_save"))
	_transport.transport_play_pressed.connect(_on_play_transition)

func _init_gizmos() -> void:
	_gizmos.init(_player, _state, _tab_container, get_tree())
	_gizmos.gizmo_selected.connect(_on_gizmo_selected)
	_gizmos.gizmo_moved.connect(_on_gizmo_moved)
	_gizmos.gizmo_rotated.connect(_on_gizmo_rotated)

# ── UI build helpers ──────────────────────────────────────────────────────────

func _make_header() -> Control:
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", _make_panel_style(Color(0.16, 0.2, 0.28, 0.95), Color(0.28, 0.4, 0.56, 0.95), 14))

	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 14)
	header_margin.add_theme_constant_override("margin_right", 14)
	header_margin.add_theme_constant_override("margin_top", 10)
	header_margin.add_theme_constant_override("margin_bottom", 10)
	header.add_child(header_margin)

	var header_vbox := VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 6)
	header_margin.add_child(header_vbox)

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

	return header

func _make_main_split() -> HSplitContainer:
	var hsplit := HSplitContainer.new()
	hsplit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hsplit.split_offset = 300

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
	_state.init(_library, _base_pose_library, _posture_list, _save_button, _status_label, _transition_button, _trigger_pose_button)
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

	_tab_container = TabContainer.new()
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.tab_changed.connect(_on_tab_changed)
	right_vbox.add_child(_tab_container)
	
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

	return hsplit

func _make_footer() -> Control:
	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", _make_panel_style(Color(0.16, 0.2, 0.28, 0.97), Color(0.28, 0.4, 0.56, 0.95), 14))

	var footer_margin := MarginContainer.new()
	footer_margin.add_theme_constant_override("margin_left", 10)
	footer_margin.add_theme_constant_override("margin_right", 10)
	footer_margin.add_theme_constant_override("margin_top", 10)
	footer_margin.add_theme_constant_override("margin_bottom", 10)
	footer.add_child(footer_margin)

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

	return footer

# ── Style helpers ─────────────────────────────────────────────────────────────

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

# ── List & tabs ───────────────────────────────────────────────────────────────

func _populate_posture_list() -> void:
	_state.populate_posture_list()

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

# ── Layout ────────────────────────────────────────────────────────────────────

func _on_toggle_layout_preset() -> void:
	var current = _state.get_layout_preset()
	_state.set_layout_preset(LayoutPreset.WIDE if current == LayoutPreset.HALF else LayoutPreset.HALF)
	_apply_layout_preset()

func _apply_layout_preset() -> void:
	match _state.get_layout_preset():
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

# ── Posture selection ─────────────────────────────────────────────────────────

func _on_posture_selected(index: int) -> void:
	if _state.is_base_pose_mode():
		if index < 0 or index >= _base_pose_library.definitions.size():
			return
		_state.set_current_base_def(_base_pose_library.definitions[index])
		_state.set_current_def(null)
		_state.set_current_id(_state.get_current_base_def().base_pose_id)
	else:
		if index < 0 or index >= _library.definitions.size():
			return
		_state.set_current_def(_library.definitions[index])
		_state.set_current_base_def(null)
		_state.set_current_id(_state.get_current_def().posture_id)
	_status_label.text = "Selected: %s (ID: %d)" % [_state.current_display_name(), _state.get_current_id()]
	_populate_properties()
	_trigger_pose_button.disabled = false
	if _transition_button:
		_transition_button.disabled = _state.is_base_pose_mode()
	if _save_button:
		_save_button.disabled = false
	
	_refresh_live_preview()
	_update_active_gizmos()
	
	var preview_def = _preview.build_preview_posture_for_editor() if _state.is_base_pose_mode() else _state.get_current_def()
	if _player and _player.posture and preview_def:
		_player.posture.force_posture_update(preview_def)
		if not _state.is_base_pose_mode():
			_player.posture._apply_full_body_posture(_state.get_current_def())
		_state.set_editor_restore_posture_id(-1)
	
	if _player and not _state.is_base_pose_mode():
		_preview.setup_transition_player()
		if _preview.get_transition_player() and _preview.get_transition_player().is_playing():
			_preview.get_transition_player().stop()
	
	var pose_trigger = _preview.get_pose_trigger()
	if pose_trigger and pose_trigger.is_frozen():
		var trigger_def = _preview.build_preview_posture_for_editor()
		if trigger_def:
			pose_trigger.trigger_pose(trigger_def)
		
	if _player and _player.posture and not _state.is_base_pose_mode():
		_player.posture.selected_posture_id = _state.get_current_id()
	_update_mode_ui()

func _populate_properties() -> void:
	var body_def = _state.current_body_resource()
	if body_def == null:
		return
	
	if not _state.is_base_pose_mode():
		_paddle_tab.set_definition(_state.get_current_def())
		_charge_tab.set_definition(_state.get_current_def())
		_follow_through_tab.set_definition(_state.get_current_def())
	_legs_tab.set_definition(body_def)
	_arms_tab.set_definition(body_def)
	_head_tab.set_definition(body_def)
	_torso_tab.set_definition(body_def)

# ── Field changes ─────────────────────────────────────────────────────────────

func _on_field_changed(_field_name: String, _value: Variant) -> void:
	if _state.current_body_resource() == null:
		return
	_status_label.text = "Modified: %s" % _state.current_display_name()
	_state.set_dirty(true)
	_refresh_live_preview()
	_update_gizmo_positions()
	if _state.get_current_def() and _player and _player.posture:
		_player.posture.force_posture_update(_state.get_current_def())
		_player.posture._apply_full_body_posture(_state.get_current_def())
	if _state.is_base_pose_mode() and _state.get_current_base_def() and _player and _player.posture:
		_player.posture._apply_full_body_posture(_state.get_current_base_def())
	_update_mode_ui()

# ── Trigger pose ─────────────────────────────────────────────────────────────

func _on_trigger_pose() -> void:
	if not _player:
		return
	var preview_def = _preview.build_preview_posture_for_editor()
	if preview_def == null:
		return
	
	if not _preview.get_pose_trigger():
		_preview.set_pose_trigger(load("res://scripts/posture_editor/pose_trigger.gd").new(_player))
		add_child(_preview.get_pose_trigger())
	
	if _preview.get_transition_player() and _preview.get_transition_player().is_playing():
		_preview.get_transition_player().stop()
	
	if _preview.get_pose_trigger().is_frozen():
		_preview.get_pose_trigger().release_pose()
		_preview.restore_live_posture_from_editor()
		_status_label.text = "Returned to live gameplay"
	else:
		_preview.capture_live_restore_posture()
		_preview.get_pose_trigger().trigger_pose(preview_def)
		_status_label.text = "Previewing static pose for %s" % _state.current_display_name()
	_update_mode_ui()

# ── Play transition ───────────────────────────────────────────────────────────

func _on_play_transition() -> void:
	_preview.on_play_transition()
	if _preview.get_transition_player():
		_transport.set_transition_player(_preview.get_transition_player())
	_update_mode_ui()

# ── Save ──────────────────────────────────────────────────────────────────────

func _on_save() -> void:
	var path: String = ""
	var filename: String = ""
	if _state.is_base_pose_mode():
		if _state.get_current_base_def() == null:
			return
		filename = _state.filename_for_base_pose(_state.get_current_base_def())
		path = BASE_POSE_DATA_DIR + filename
	else:
		if _state.get_current_def() == null:
			return
		filename = _state.filename_for(_state.get_current_def())
		path = DATA_DIR + filename
	var err := ResourceSaver.save(_state.current_body_resource(), path)
	if err == OK:
		_status_label.text = "Saved: %s" % filename
		_state.set_dirty(false)
		print("[POSTURE EDITOR] Saved ", path)
	else:
		_status_label.text = "Save failed: error %d" % err
		push_error("PostureEditor: failed to save " + path)
	_update_mode_ui()

# ── Workspace ─────────────────────────────────────────────────────────────────

func _on_toggle_workspace() -> void:
	var new_mode = Workspace.BASE_POSES if not _state.is_base_pose_mode() else Workspace.STROKE_POSTURES
	_state.set_workspace_mode(new_mode)
	_state.set_current_def(null)
	_state.set_current_base_def(null)
	_state.set_current_id(-1)
	if _gizmos.get_gizmo_controller():
		_gizmos.get_gizmo_controller().clear_all_gizmos()
	var pose_trigger = _preview.get_pose_trigger()
	if pose_trigger and pose_trigger.is_frozen():
		pose_trigger.release_pose()
		_preview.restore_live_posture_from_editor()
	_state.set_dirty(false)
	_trigger_pose_button.disabled = true
	if _transition_button:
		_transition_button.disabled = true
	if _save_button:
		_save_button.disabled = true
	_status_label.text = "Select a %s to edit" % ("base pose" if _state.is_base_pose_mode() else "stroke posture")
	_update_active_gizmos()
	_update_workspace_ui()

func _update_workspace_ui() -> void:
	if _workspace_button:
		_workspace_button.text = "Workspace: Base Poses" if _state.is_base_pose_mode() else "Workspace: Stroke Postures"
		if _tab_container:
			var hide_stroke_tabs: bool = _state.is_base_pose_mode()
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
		_transition_button.disabled = _state.is_base_pose_mode() or _state.get_current_def() == null
	_update_mode_ui()

# ── Preview context ───────────────────────────────────────────────────────────

func _on_preview_context_changed(index: int) -> void:
	_preview.set_preview_context_option_idx(index)
	var pose_trigger = _preview.get_pose_trigger()
	if pose_trigger and pose_trigger.is_frozen():
		var preview_def = _preview.build_preview_posture_for_editor()
		if preview_def:
			pose_trigger.refresh_from_definition(preview_def)
	elif _preview.get_transition_player() and _preview.get_transition_player().is_playing():
		_preview.setup_transition_player()
	_update_mode_ui()

# ── Solo mode ─────────────────────────────────────────────────────────────────

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

# ── Tab changes ───────────────────────────────────────────────────────────────

func _on_tab_changed(_tab_index: int) -> void:
	_update_active_gizmos()

# ── Gizmo forwarding ───────────────────────────────────────────────────────────

func _on_gizmo_selected(gizmo) -> void:
	if gizmo.posture_id < 0:
		return
	var defs = _base_pose_library.definitions if _state.is_base_pose_mode() else _library.definitions
	var found_index := -1
	for i in range(defs.size()):
		var def = defs[i]
		var def_id: int = def.base_pose_id if _state.is_base_pose_mode() else def.posture_id
		if def_id == gizmo.posture_id:
			found_index = i
			break
	if found_index < 0:
		return
	
	if _state.is_base_pose_mode():
		_state.set_current_base_def(_base_pose_library.definitions[found_index])
		_state.set_current_def(null)
		_state.set_current_id(_state.get_current_base_def().base_pose_id)
	else:
		_state.set_current_def(_library.definitions[found_index])
		_state.set_current_base_def(null)
		_state.set_current_id(_state.get_current_def().posture_id)
	
	_posture_list.select(found_index)
	_populate_properties()
	_update_gizmo_visibility()
	_status_label.text = "Selected: %s (ID: %d)" % [_state.current_display_name(), _state.get_current_id()]

func _on_gizmo_moved(gizmo, new_position: Vector3) -> void:
	var body_def = _state.current_body_resource()
	if body_def == null or gizmo.posture_id != _state.get_current_id():
		return
	
	if _player:
		var forward_axis: Vector3 = _player._get_forward_axis()
		var forehand_axis: Vector3 = _player._get_forehand_axis()
		var player_pos := _player.global_position
		var offset: Vector3 = new_position - player_pos
		
		match gizmo.field_name:
			"paddle_position":
				if _state.get_current_def():
					_state.get_current_def().paddle_forehand_mul = offset.dot(forehand_axis)
					_state.get_current_def().paddle_forward_mul = offset.dot(forward_axis)
					_state.get_current_def().paddle_y_offset = offset.y
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
					_: base_pos = _player.global_position
				var local_delta = new_position - base_pos
				body_def.left_hand_offset = Vector3(
					local_delta.dot(forehand_axis),
					local_delta.dot(Vector3.UP),
					local_delta.dot(forward_axis)
				)
			"right_elbow_pole":
				var r_elbow_pivot: Node3D = _player.right_arm_node.get_node_or_null("UpperArmPivot/ForearmPivot")
				var r_animated_elbow: Vector3 = r_elbow_pivot.global_position if r_elbow_pivot else Vector3.ZERO
				var pole_delta = new_position - r_animated_elbow
				body_def.right_elbow_pole = Vector3(
					pole_delta.dot(forehand_axis),
					pole_delta.dot(Vector3.UP),
					pole_delta.dot(forward_axis)
				)
			"left_elbow_pole":
				var l_elbow_pivot: Node3D = _player.left_arm_node.get_node_or_null("UpperArmPivot/ForearmPivot")
				var l_animated_elbow: Vector3 = l_elbow_pivot.global_position if l_elbow_pivot else Vector3.ZERO
				var pole_delta = new_position - l_animated_elbow
				body_def.left_elbow_pole = Vector3(
					pole_delta.dot(forehand_axis),
					pole_delta.dot(Vector3.UP),
					pole_delta.dot(forward_axis)
				)
			"right_foot_offset":
				var gnd_y: float = 0.0
				var base: Vector3 = Vector3(_player.global_position.x, gnd_y, _player.global_position.z)
				var half_excess: float = (body_def.stance_width - 0.35) * 0.5
				var r_lateral: Vector3 = forehand_axis * (0.14 + half_excess)
				var r_fwd: float = -0.06
				if body_def.lead_foot == 0:
					r_fwd += body_def.front_foot_forward
				else:
					r_fwd += body_def.back_foot_back
				var r_base: Vector3 = base + r_lateral + forward_axis * r_fwd
				var local_delta = new_position - r_base
				body_def.right_foot_offset = Vector3(
					local_delta.dot(forehand_axis),
					local_delta.dot(Vector3.UP),
					local_delta.dot(forward_axis)
				)
			"left_foot_offset":
				var gnd_y: float = 0.0
				var base: Vector3 = Vector3(_player.global_position.x, gnd_y, _player.global_position.z)
				var half_excess: float = (body_def.stance_width - 0.35) * 0.5
				var l_lateral: Vector3 = forehand_axis * -(0.14 + half_excess)
				var l_fwd: float = 0.06
				if body_def.lead_foot == 0:
					l_fwd += body_def.back_foot_back
				else:
					l_fwd += body_def.front_foot_forward
				var l_base: Vector3 = base + l_lateral + forward_axis * l_fwd
				var local_delta = new_position - l_base
				body_def.left_foot_offset = Vector3(
					local_delta.dot(forehand_axis),
					local_delta.dot(Vector3.UP),
					local_delta.dot(forward_axis)
				)
			"right_knee_pole":
				var r_knee_pivot: Node3D = _player.right_leg_node.get_node_or_null("ThighPivot/ShinPivot")
				var r_animated_knee: Vector3 = r_knee_pivot.global_position if r_knee_pivot else Vector3.ZERO
				var pole_delta = new_position - r_animated_knee
				body_def.right_knee_pole = Vector3(
					pole_delta.dot(forehand_axis),
					pole_delta.dot(Vector3.UP),
					pole_delta.dot(forward_axis)
				)
			"left_knee_pole":
				var l_knee_pivot: Node3D = _player.left_leg_node.get_node_or_null("ThighPivot/ShinPivot")
				var l_animated_knee: Vector3 = l_knee_pivot.global_position if l_knee_pivot else Vector3.ZERO
				var pole_delta = new_position - l_animated_knee
				body_def.left_knee_pole = Vector3(
					pole_delta.dot(forehand_axis),
					pole_delta.dot(Vector3.UP),
					pole_delta.dot(forward_axis)
				)

	_state.set_dirty(true)
	_populate_properties()
	_status_label.text = "Updated: %s position" % _state.current_display_name()
	_refresh_live_preview()
	if _state.get_current_def() and _player and _player.posture:
		_player.posture.force_posture_update(_state.get_current_def())
		_player.posture._apply_full_body_posture(_state.get_current_def())
	if _state.is_base_pose_mode() and _state.get_current_base_def() and _player and _player.posture:
		_player.posture._apply_full_body_posture(_state.get_current_base_def())

func _on_gizmo_rotated(gizmo, euler_delta: Vector3) -> void:
	var body_def = _state.current_body_resource()
	if body_def == null or gizmo.posture_id != _state.get_current_id():
		return
	
	_state.set_dirty(true)
	
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
	if _state.get_current_def() and _player and _player.posture:
		_player.posture.force_posture_update(_state.get_current_def())
		_player.posture._apply_full_body_posture(_state.get_current_def())
	if _state.is_base_pose_mode() and _state.get_current_base_def() and _player and _player.posture:
		_player.posture._apply_full_body_posture(_state.get_current_base_def())
	_update_gizmo_positions()

# ── Gizmo management ──────────────────────────────────────────────────────────

func set_player(player: Node3D) -> void:
	_player = player
	_update_solo_mode_ui()
	_preview.init(_player, _library, _base_pose_library, _state)
	_gizmos.set_player(_player)
	_gizmos.create_gizmo_controller()

func _update_active_gizmos() -> void:
	_gizmos.update_active_gizmos()

func _update_gizmo_positions() -> void:
	_gizmos.update_gizmo_positions()

func _update_gizmo_visibility() -> void:
	_gizmos.update_gizmo_visibility()

func _refresh_live_preview() -> void:
	_gizmos.refresh_live_preview()

# ── Transport bar ─────────────────────────────────────────────────────────────

func build_transport_bar() -> Control:
	return _transport.build_transport_bar()

# ── Mode UI ───────────────────────────────────────────────────────────────────

func _update_mode_ui() -> void:
	var mode := "Live"
	if _preview != null and _preview.get_transition_player() and _preview.get_transition_player().is_playing():
		mode = "Preview Swing"
	elif _preview != null and _preview.get_pose_trigger() and _preview.get_pose_trigger().is_frozen():
		mode = "Preview Pose"
	var item_word := "base pose" if _state != null and _state.is_base_pose_mode() else "posture"

	if _mode_label:
		_mode_label.text = "Mode: %s" % mode
	if _trigger_pose_button:
		var trigger_frozen = _preview != null and _preview.get_pose_trigger() and _preview.get_pose_trigger().is_frozen()
		_trigger_pose_button.text = "Resume Live" if trigger_frozen else "Preview %s" % ("Base Pose" if _state != null and _state.is_base_pose_mode() else "Pose")
	if _transition_button:
		var playing = _preview != null and _preview.get_transition_player() and _preview.get_transition_player().is_playing()
		_transition_button.text = "Pause Swing" if playing else "Preview Swing"
		_transition_button.disabled = _state != null and (_state.is_base_pose_mode() or _state.get_current_def() == null)
	if _help_label:
		match mode:
			"Preview Pose":
				_help_label.text = "Static preview is active. Drag handles to adjust the selected %s, or Resume Live to return to gameplay." % item_word
			"Preview Swing":
				_help_label.text = "Swing preview is active. Use Space to pause, P to switch back to a static pose, and G to toggle ghost clutter."
			_:
				if _state != null and _state.is_base_pose_mode():
					_help_label.text = "Select a base pose, choose a preview state, then use Preview Base Pose. Drag handles in the viewport to shape stance, arms, torso, and head."
				else:
					_help_label.text = "Select a posture, then use Preview Pose or Preview Swing. Preview State lets you see the stroke against different base-pose contexts."

# ── Teardown ─────────────────────────────────────────────────────────────────

func _teardown_preview_state() -> void:
	if _preview:
		if _preview.get_transition_player():
			_preview.get_transition_player().stop()
		if _preview.get_pose_trigger() and _preview.get_pose_trigger().is_frozen():
			_preview.get_pose_trigger().release_pose()
		_preview.restore_live_posture_from_editor()
	if _state:
		_state.set_editor_restore_posture_id(-1)
	if _gizmos:
		_gizmos.teardown_mesh_nodes()
	_update_mode_ui()

# ── Notification ───────────────────────────────────────────────────────────────

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if visible and _state != null and _state.get_current_def() == null and _posture_list.get_item_count() > 0:
			_on_posture_selected(0)
		
		if visible and _player and _player.is_inside_tree():
			if _player.global_position.length() > 0.01:
				_refresh_live_preview()
				if _gizmos != null and _gizmos.get_gizmo_controller() and _gizmos.get_gizmo_controller().get_child_count() == 0:
					_update_active_gizmos()
		
		if _gizmos != null:
			_update_gizmo_visibility()
		if visible and _player:
			_update_gizmo_positions()
			_update_mode_ui()
		elif not visible:
			_teardown_preview_state()
		
		if visible:
			editor_opened.emit()
		else:
			editor_closed.emit()

# ── Input ─────────────────────────────────────────────────────────────────────

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

# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _preview != null:
		var pose_trigger = _preview.get_pose_trigger()
		if pose_trigger:
			pose_trigger.update()
	
	if visible and _player:
		_update_gizmo_positions()
	
	if _gizmos != null and _gizmos.get_gizmo_controller() and _player and _player.is_inside_tree() and _player.skeleton:
		_gizmos.process_frame(delta)

func get_current_paddle_position() -> Vector3:
	if _gizmos:
		return _gizmos.get_current_paddle_position()
	return Vector3.INF

# ── Transition callbacks ───────────────────────────────────────────────────────

func _on_transition_preview_started() -> void:
	_update_mode_ui()

func _on_transition_preview_ended() -> void:
	if _preview != null and not (_preview.get_pose_trigger() and _preview.get_pose_trigger().is_frozen()):
		_preview.restore_live_posture_from_editor()
	_update_mode_ui()
