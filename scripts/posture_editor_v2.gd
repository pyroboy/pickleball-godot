class_name PostureEditorV2 extends Control

## Posture Editor v2 — clean-slate rewrite.
## Phase 1: just a UI panel that toggles with Q. No sub-modules, no camera rewiring,
## no gizmos. Everything else grows from this shell.

signal editor_opened()
signal editor_closed()

var _title_label: Label
var _close_button: Button

func _init() -> void:
	name = "PostureEditorV2"
	visible = false

func _ready() -> void:
	# Right-side sheet, same footprint as the legacy editor so the 3D court
	# stays visible on the left.
	anchor_left = 0.62
	anchor_right = 0.995
	anchor_top = 0.02
	anchor_bottom = 0.98
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_PASS

	var panel := PanelContainer.new()
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.12, 0.18, 0.96)
	sb.border_color = Color(0.42, 0.72, 0.95, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Posture Editor v2"
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color(0.86, 0.96, 1.0))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_close_button = Button.new()
	_close_button.text = "Close (Q)"
	_close_button.pressed.connect(close)
	header.add_child(_close_button)

	var hint := Label.new()
	hint.text = "Shell only — functionality coming next. Press Q or click Close to exit."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.7, 0.78, 0.85))
	vbox.add_child(hint)

func open() -> void:
	if visible:
		return
	visible = true
	editor_opened.emit()

func close() -> void:
	if not visible:
		return
	visible = false
	editor_closed.emit()

func toggle() -> void:
	if visible: close()
	else: open()
