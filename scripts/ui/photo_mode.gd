extends CanvasLayer
## Photo mode (pause menu > Photo mode): the match stays paused and the game camera roams free.
## Phone: one finger looks around, two fingers pinch to move forward / back and drag to slide
## and rise. Mac: drag to look, wheel to move, WASD / Q E to fly.
## Panel: camera presets (MATCH is the view you paused on), FOCUS (metres from the camera that
## stay sharp) and APERTURE (f/1.4 very blurry .. f/22 all sharp), then HIDE (tap anywhere to
## bring the panel back), DONE (back to the pause menu).
## Nothing ticks: only the camera moves, and the player cards are redrawn for the new view.
## Focus blur works like the solo aim slow-motion blur (shaders/photo_focus.gdshader): the
## background blurs and players / ball stay sharp when they are near the focus distance.

const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
const PixelDraw = preload("res://scripts/ui/pixel_draw.gd")
const PixelCardRigScript = preload("res://scripts/graphics/pixel_card_rig.gd")
const FocusShader = preload("res://shaders/photo_focus.gdshader")

const LOOK_PER_PIXEL := 0.0045      # radians per screen pixel (scaled to a 1080-tall screen)
const PINCH_METERS := 0.03          # forward per pixel of pinch
const PAN_METERS := 0.012           # sideways / up per pixel of two-finger drag
const FLY_SPEED := 4.0              # m/s with keys
const PITCH_LIMIT := 1.55
const BOUNDS_MIN := Vector3(-14.0, 0.25, -18.0)
const BOUNDS_MAX := Vector3(14.0, 16.0, 18.0)
const PRESETS := ["MATCH", "BROADCAST", "SIDE", "TOP", "NET", "HERO", "LOW", "SHOULDER"]
const F_STOPS := [1.4, 2.0, 2.8, 4.0, 5.6, 8.0, 11.0, 16.0, 22.0]
const BLUR_AT_F14 := 16.0           # blur radius in pixels at f/1.4 on a 1080-tall screen
const FOCUS_DEPTH := 1.0            # m around the focus distance that stays fully sharp (at 0 m)
const FOCUS_DEPTH_GROWTH := 0.12    # ... plus this share of the focus distance either side
const FOCUS_MIN := 0.5
const FOCUS_MAX := 30.0

var _camera: Camera3D
var _menu: CanvasLayer
var _game: Node
var _saved_camera: Dictionary = {}
var _hidden: Array = []             # [node, property, old value]
var _rigs: Array = []
var _yaw := 0.0
var _pitch := 0.0
var _touches: Dictionary = {}       # index -> position
var _tap_start := Vector2.INF
var _mouse_on_panel := false
var _panel: PanelContainer
var _hint: Label
var _focus_slider: HSlider
var _focus_label: Label
var _aperture_slider: HSlider
var _aperture_label: Label
var _blur_layer: CanvasLayer
var _blur_material: ShaderMaterial
var _dirty := true

## Enter from the pause menu. Returns false when there is no game camera to move.
func begin(menu: CanvasLayer) -> bool:
	_game = get_tree().current_scene
	var rig = _game.get("camera_rig") if _game != null else null
	_camera = rig.camera if rig != null else get_viewport().get_camera_3d()
	if _camera == null: return false
	_menu = menu
	_saved_camera = {"transform": _camera.global_transform, "fov": _camera.fov, "h": _camera.h_offset, "v": _camera.v_offset}
	_camera.h_offset = 0.0
	_camera.v_offset = 0.0
	_read_angles()
	# Hide every other overlay (HUD, touch controls, pause menu) and the helper rings; the
	# pixel-art post effect stays, it is part of the look.
	for node in _game.find_children("*", "CanvasLayer", true, false):
		if node != self and node.name != "PixelPost": _stash(node, "visible", false)
	_stash(menu, "visible", false)
	var mobile = _game.get("mobile_controls")
	if is_instance_valid(mobile): _stash(mobile, "process_mode", Node.PROCESS_MODE_DISABLED)
	for node in _game.find_children("ReachRings", "Node3D", true, false): _stash(node, "visible", false)
	for node in _game.find_children("*", "Node3D", true, false):
		if node.get_script() == PixelCardRigScript:
			_rigs.append(node)
			# First-person view: show your player whole (cards, not the eye-view arms) for the photo.
			if bool(node.get("first_person")): _stash(node, "first_person", false)
	_add_dof()
	_focus_slider.set_value_no_signal(_subject_distance())
	_aperture_slider.set_value_no_signal(F_STOPS.size() - 1)
	_update_lens()
	# Pose editors and tools hold the match paused the same way, and stay drawn live.
	var controller = get_node_or_null("/root/PauseController")
	if controller != null: controller.hold_overlay(self)
	return true

func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = PanelContainer.new()
	var style: StyleBoxFlat = UiTheme.button_style(Color(UiTheme.PANEL, 0.78))
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_panel.add_child(column)
	var presets := HFlowContainer.new()
	presets.add_theme_constant_override("h_separation", 8)
	presets.add_theme_constant_override("v_separation", 8)
	column.add_child(presets)
	for name in PRESETS:
		presets.add_child(_button(name, _apply_preset.bind(name), Vector2(0, 54), 20))
	_focus_label = _label()
	_focus_slider = _slider(FOCUS_MIN, FOCUS_MAX, 0.1)
	column.add_child(_row(_focus_label, _focus_slider))
	_aperture_label = _label()
	_aperture_slider = _slider(0, F_STOPS.size() - 1, 1)
	column.add_child(_row(_aperture_label, _aperture_slider))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(bar)
	bar.add_child(_button("HIDE", _hide_panel, Vector2(170, 60), 24))
	var done := _button("DONE", finish, Vector2(170, 60), 24)
	done.add_theme_color_override("font_color", UiTheme.GOLD)
	bar.add_child(done)
	_hint = Label.new()
	_hint.text = "PHOTO MODE   1 finger: look   2 fingers: pinch to move, drag to slide"
	_hint.add_theme_font_override("font", PixelDraw.font())
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_hint)
	_focus_slider.value_changed.connect(func(_v: float) -> void: _update_lens())
	_aperture_slider.value_changed.connect(func(_v: float) -> void: _update_lens())
	get_viewport().size_changed.connect(_place)
	_place()

func _button(text: String, callback: Callable, size: Vector2, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", PixelDraw.font())
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color.WHITE)
	for state in ["normal", "hover", "focus"]: button.add_theme_stylebox_override(state, UiTheme.button_style(Color(UiTheme.PANEL, 0.9)))
	button.add_theme_stylebox_override("pressed", UiTheme.button_style(Color(UiTheme.PANEL, 0.95), true))
	button.pressed.connect(callback)
	return button

func _label() -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(230, 0)
	label.add_theme_font_override("font", PixelDraw.font())
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color.WHITE)
	return label

func _slider(low: float, high: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 48)
	var grab := GradientTexture2D.new()
	grab.width = 36
	grab.height = 36
	grab.fill = GradientTexture2D.FILL_RADIAL
	grab.fill_from = Vector2(0.5, 0.5)
	grab.fill_to = Vector2(0.5, 0.0)
	var colors := Gradient.new()
	colors.set_color(0, UiTheme.ACCENT)
	colors.set_color(1, UiTheme.ACCENT)
	colors.add_point(0.95, UiTheme.ACCENT)
	colors.add_point(0.99, Color(UiTheme.ACCENT, 0.0))
	grab.gradient = colors
	slider.add_theme_icon_override("grabber", grab)
	slider.add_theme_icon_override("grabber_highlight", grab)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.25)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	slider.add_theme_stylebox_override("slider", track)
	var filled := StyleBoxFlat.new()
	filled.bg_color = Color(UiTheme.ACCENT, 0.7)
	slider.add_theme_stylebox_override("grabber_area", filled)
	slider.add_theme_stylebox_override("grabber_area_highlight", filled)
	return slider

func _row(label: Label, slider: HSlider) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(label)
	row.add_child(slider)
	return row

func _place() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	var window_h: float = maxf(float(DisplayServer.window_get_size().y), 1.0)
	var safe := DisplayServer.get_display_safe_area()
	var bottom_inset: float = maxf(0.0, window_h - float(safe.end.y)) * size.y / window_h
	var top_inset: float = maxf(0.0, float(safe.position.y)) * size.y / window_h
	var width: float = minf(size.x - 32.0, 900.0)
	_panel.custom_minimum_size = Vector2(width, 0)
	_panel.reset_size()
	_panel.position = Vector2((size.x - width) * 0.5, size.y - _panel.size.y - 24.0 - bottom_inset)
	_hint.reset_size()
	_hint.position = Vector2((size.x - _hint.size.x) * 0.5, 24.0 + top_inset)

# ---- camera ----

func _read_angles() -> void:
	var forward: Vector3 = -_camera.global_transform.basis.z
	_yaw = atan2(-forward.x, -forward.z)
	_pitch = asin(clampf(forward.y, -1.0, 1.0))

func _apply_angles() -> void:
	_pitch = clampf(_pitch, -PITCH_LIMIT, PITCH_LIMIT)
	var at: Vector3 = _camera.global_position
	_camera.global_transform = Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, 0.0)), at)
	_dirty = true

func _move(local: Vector3) -> void:
	var b: Basis = _camera.global_transform.basis
	var at: Vector3 = _camera.global_position + b.x * local.x + Vector3.UP * local.y - b.z * local.z
	_camera.global_position = at.clamp(BOUNDS_MIN, BOUNDS_MAX)
	_dirty = true

## Your player (the human on the left team) and which end of the court they are on.
func _subject() -> Vector3:
	var me = _game.get("player_left") if _game != null else null
	return me.global_position if is_instance_valid(me) else Vector3(0, 0, 4)

func _subject_distance() -> float:
	return clampf(_camera.global_position.distance_to(_subject() + Vector3.UP * 1.1), FOCUS_MIN, FOCUS_MAX)

func _apply_preset(name: String) -> void:
	if name == "MATCH":
		_camera.global_transform = _saved_camera.transform
	else:
		var p: Vector3 = _subject()
		var s: float = 1.0 if p.z >= 0.0 else -1.0
		var post: float = PickleballConstants.COURT_WIDTH * 0.5 + 0.5
		var spot: Array = {
			"BROADCAST": [Vector3(0, 6.0, s * 13.5), Vector3(0, 0.4, 0)],
			"SIDE": [Vector3(11.0, 2.4, 0.0), Vector3(0, 0.6, 0)],
			"TOP": [Vector3(0, 15.5, s * 0.4), Vector3(0, 0, 0)],
			"NET": [Vector3(post, 1.0, 0.0), Vector3(p.x, 1.0, p.z)],
			"HERO": [Vector3(p.x + 0.9, 1.25, p.z + s * 2.2), Vector3(p.x, 1.2, p.z)],
			"LOW": [Vector3(p.x + 1.6, 0.35, p.z + s * 2.6), Vector3(p.x, 1.0, p.z)],
			"SHOULDER": [Vector3(p.x + 0.5, 1.75, p.z + s * 1.3), Vector3(p.x * 0.3, 0.7, -s * 4.5)],
		}[name]
		var at: Vector3 = Vector3(spot[0]).clamp(BOUNDS_MIN, BOUNDS_MAX)
		_camera.global_transform = Transform3D(Basis.IDENTITY, at).looking_at(spot[1], Vector3.UP)
	_read_angles()
	_focus_slider.value = _subject_distance()   # refocus on your player
	_dirty = true

# ---- lens ----

func _add_dof() -> void:
	# Drawn over the 3D view and the pixel post effect, under this panel.
	_blur_layer = CanvasLayer.new()
	_blur_layer.name = "PhotoFocusBlur"
	var post = _game.get_node_or_null("PixelPost")
	_blur_layer.layer = clampi(int(post.layer) + 1 if post != null else 0, -100, layer - 1)
	_blur_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur_material = ShaderMaterial.new()
	_blur_material.shader = FocusShader
	rect.material = _blur_material
	_blur_layer.add_child(rect)
	_blur_layer.visible = false
	_game.add_child(_blur_layer)

func _update_lens() -> void:
	var focus: float = _focus_slider.value
	var stop: float = F_STOPS[clampi(int(_aperture_slider.value), 0, F_STOPS.size() - 1)]
	_focus_label.text = "FOCUS %.1f m" % focus
	_aperture_label.text = "APERTURE f/%s" % (str(int(stop)) if stop >= 4.0 else "%.1f" % stop)
	if not is_instance_valid(_blur_layer) or _camera == null: return
	var size: Vector2 = get_viewport().get_visible_rect().size
	var scale: float = size.y / 1080.0
	var blur: float = BLUR_AT_F14 * (1.4 / stop) * scale
	_blur_layer.visible = stop < 22.0 and blur >= 0.5
	if not _blur_layer.visible: return
	# Subjects: every player (feet to head) and the ball, each blurred by its own distance;
	# drawn far to near so a nearer one wins where they overlap.
	var subjects: Array = []
	if _game.has_method("get_players"):
		for p in _game.get_players(): subjects.append([p.global_position + Vector3.UP * 0.1, p.global_position + Vector3.UP * 1.75, 0.32, 18.0])
	var ball = _game.get("ball")
	if is_instance_valid(ball): subjects.append([ball.global_position, ball.global_position, 0.0, 16.0])
	var forward: Vector3 = -_camera.global_basis.z
	var found: Array = []
	for item in subjects:
		var a: Vector3 = item[0]; var b: Vector3 = item[1]
		if _camera.is_position_behind(a) or _camera.is_position_behind(b): continue
		var sa: Vector2 = _camera.unproject_position(a); var sb: Vector2 = _camera.unproject_position(b)
		found.append({"seg": Vector4(sa.x / size.x, sa.y / size.y, sb.x / size.x, sb.y / size.y),
			"radius": maxf(float(item[3]) * scale, sa.distance_to(sb) * float(item[2])),
			"dist": maxf(((a + b) * 0.5 - _camera.global_position).dot(forward), 0.05)})
	found.sort_custom(func(x, y): return x.dist > y.dist)
	var segs: Array = []
	var radii: Array = []
	var dists: Array = []
	for item in found.slice(0, 5):
		segs.append(item.seg); radii.append(item.radius); dists.append(item.dist)
	while segs.size() < 5:
		segs.append(Vector4(-2, -2, -2, -2)); radii.append(0.0); dists.append(0.0)
	var aspect: float = size.x / maxf(size.y, 1.0)
	var t: float = tan(deg_to_rad(_camera.fov) * 0.5)
	var tans: Vector2 = Vector2(t * aspect, t) if _camera.keep_aspect == Camera3D.KEEP_HEIGHT else Vector2(t, t / aspect)
	var basis: Basis = _camera.global_basis
	_blur_material.set_shader_parameter("viewport_size", size)
	_blur_material.set_shader_parameter("blur_radius", blur)
	_blur_material.set_shader_parameter("focus_distance", focus)
	# The sharp zone deepens with distance, as with a real lens.
	_blur_material.set_shader_parameter("focus_range", FOCUS_DEPTH * 0.5 + FOCUS_DEPTH_GROWTH * focus)
	_blur_material.set_shader_parameter("cam_pos", _camera.global_position)
	_blur_material.set_shader_parameter("cam_right", basis.x)
	_blur_material.set_shader_parameter("cam_up", basis.y)
	_blur_material.set_shader_parameter("cam_forward", forward)
	_blur_material.set_shader_parameter("tan_half", tans)
	_blur_material.set_shader_parameter("floor_y", PickleballConstants.FLOOR_Y)
	_blur_material.set_shader_parameter("seg", segs)
	_blur_material.set_shader_parameter("seg_radius", PackedFloat32Array(radii))
	_blur_material.set_shader_parameter("seg_dist", PackedFloat32Array(dists))

# ---- input ----

func _on_panel(at: Vector2) -> bool:
	return _panel.visible and _panel.get_global_rect().grow(8.0).has_point(at)

func _input(event: InputEvent) -> void:
	if _camera == null: return
	var scale: float = 1080.0 / maxf(get_viewport().get_visible_rect().size.y, 1.0)
	if event is InputEventScreenTouch:
		if event.pressed:
			if _on_panel(event.position): return   # the slider or button gets it
			_touches[event.index] = event.position
			if _touches.size() == 1: _tap_start = event.position
			if _touches.size() > 1: _tap_start = Vector2.INF
		else:
			if not _touches.has(event.index): return
			_touches.erase(event.index)
			# A tap with the panel hidden brings it back.
			if not _panel.visible and _tap_start.is_finite() and event.position.distance_to(_tap_start) < 20.0: _show_panel()
			if _touches.is_empty(): _tap_start = Vector2.INF
		return
	if event is InputEventScreenDrag:
		if not _touches.has(event.index): return
		var before: Vector2 = _touches[event.index]
		if _touches.size() == 1:
			_yaw -= event.relative.x * LOOK_PER_PIXEL * scale
			_pitch -= event.relative.y * LOOK_PER_PIXEL * scale
			_apply_angles()
		elif _touches.size() >= 2:
			var other: Vector2 = Vector2.INF
			for key in _touches:
				if key != event.index: other = _touches[key]; break
			if other.is_finite():
				var spread: float = event.position.distance_to(other) - before.distance_to(other)
				_move(Vector3(-event.relative.x * 0.5 * PAN_METERS * scale, event.relative.y * 0.5 * PAN_METERS * scale, spread * PINCH_METERS * scale))
		_touches[event.index] = event.position
		if _tap_start.is_finite() and event.position.distance_to(_tap_start) >= 20.0: _tap_start = Vector2.INF
		return
	# Mac: drag to look, wheel to move (touches arrive as touch events on the phone).
	if OS.has_feature("mobile") or event.device == InputEvent.DEVICE_ID_EMULATION: return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		if event.pressed:
			_mouse_on_panel = _on_panel(event.position)
			if not _panel.visible: _show_panel()
	elif event is InputEventMouseMotion and not _mouse_on_panel and (event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)) != 0:
		_yaw -= event.relative.x * LOOK_PER_PIXEL * scale
		_pitch -= event.relative.y * LOOK_PER_PIXEL * scale
		_apply_angles()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and not _on_panel(event.position):
		_move(Vector3(0, 0, 0.4 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.4))

func _process(delta: float) -> void:
	if _camera == null: return
	if not OS.has_feature("mobile"):
		var fly := Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)),
			float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)))
		if fly != Vector3.ZERO: _move(fly * FLY_SPEED * minf(delta, 0.05))
	if _dirty:
		_dirty = false
		# Cards face the camera; the match is paused, so redraw them once for the new view.
		for rig in _rigs:
			if is_instance_valid(rig): rig._draw_cards(0.0)
		_update_lens()   # subjects moved on screen

func _hide_panel() -> void:
	_panel.visible = false
	_hint.visible = false

func _show_panel() -> void:
	_panel.visible = true
	_hint.visible = true

## Back to the pause menu with the match view restored.
func finish() -> void:
	if is_instance_valid(_blur_layer): _blur_layer.queue_free()
	if _camera != null and is_instance_valid(_camera):
		_camera.global_transform = _saved_camera.transform
		_camera.fov = _saved_camera.fov
		_camera.h_offset = _saved_camera.h
		_camera.v_offset = _saved_camera.v
		for rig in _rigs:
			if is_instance_valid(rig): rig._draw_cards(0.0)
	_hidden.reverse()   # a node stashed twice gets its first (real) value back last
	for item in _hidden:
		if is_instance_valid(item[0]): item[0].set(item[1], item[2])
	_hidden.clear()
	_camera = null
	var controller = get_node_or_null("/root/PauseController")
	if controller != null: controller.release_overlay(self)
	if is_instance_valid(_menu) and _menu.has_method("photo_mode_closed"): _menu.photo_mode_closed()
	queue_free()

func _stash(node: Node, property: String, value) -> void:
	_hidden.append([node, property, node.get(property)])
	node.set(property, value)
