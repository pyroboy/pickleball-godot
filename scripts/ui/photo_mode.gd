extends CanvasLayer
## Photo mode (pause menu > Photo mode): the match stays paused and the game camera roams free.
## Phone: one finger looks around, two fingers pinch to move forward / back and drag to slide
## and rise. Mac: drag to look, wheel to move, WASD / Q E to fly.
## Panel: camera presets (MATCH is the view you paused on), FOCUS (metres from the camera that
## stay sharp), APERTURE (f/1.4 very blurry .. f/22 all sharp), FOV (how wide the lens is) and
## ZOOM (magnifies that lens, 1x .. 6x), then HIDE (tap anywhere to bring the panel back), LOGO
## (the game logo as a watermark in the corner, on by default) and DONE (back to the pause menu).
## Play aids are hidden for the picture: name labels and rings on the court, the ball's height
## line.
## Nothing ticks: only the camera moves, and the player cards are redrawn for the new view.
## The pause menu's low-power loop stays on (settings.gd set_pause_idle), so the screen is
## redrawn only when the view or a slider changes; this node only shortens that loop's sleep
## while the view moves, to keep the motion smooth.
##
## Focus blur (shaders/photo_focus.gdshader) goes by each pixel's real distance. A second camera
## copies this one into a small off-screen view (the size of the half-resolution 3D picture)
## where shaders/photo_depth.gdshader writes the depth buffer out as a distance map; it is
## redrawn only when the view changes. A longer lens (narrow FOV, more zoom) blurs more, as a
## real one does. While the view moves the blur uses few samples, and many once it is still.
## At start the map is checked (bytes intact, real distances in it); if this device cannot
## supply it, the blur falls back to floor / arena distances with a capsule per player.

const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
const PixelDraw = preload("res://scripts/ui/pixel_draw.gd")
const PixelCardRigScript = preload("res://scripts/graphics/pixel_card_rig.gd")
const FocusShader = preload("res://shaders/photo_focus.gdshader")
const DepthShader = preload("res://shaders/photo_depth.gdshader")

const LOOK_PER_PIXEL := 0.0045      # radians per screen pixel (scaled to a 1080-tall screen)
const PINCH_METERS := 0.03          # forward per pixel of pinch
const PAN_METERS := 0.012           # sideways / up per pixel of two-finger drag
const FLY_SPEED := 4.0              # m/s with keys
const PITCH_LIMIT := 1.55
const BOUNDS_MIN := Vector3(-14.0, 0.25, -18.0)
const BOUNDS_MAX := Vector3(14.0, 16.0, 18.0)
const PRESETS := ["MATCH", "BROADCAST", "SIDE", "TOP", "NET", "HERO", "LOW", "SHOULDER"]
const F_STOPS := [1.4, 2.0, 2.8, 4.0, 5.6, 8.0, 11.0, 16.0, 22.0]
const BLUR_AT_F14 := 16.0           # blur radius in pixels at f/1.4 on a 1080-tall screen (match lens)
const BLUR_CAP := 30.0              # largest blur radius however long the lens
const FOCUS_DEPTH := 1.0            # m around the focus distance that stays fully sharp (at 0 m)
const FOCUS_DEPTH_GROWTH := 0.12    # ... plus this share of the focus distance either side
const FOCUS_MIN := 0.5
const FOCUS_MAX := 30.0
const FOV_MIN := 20.0               # degrees, on the camera's own axis (across the screen in portrait)
const FOV_MAX := 100.0
const ZOOM_MAX := 6.0
const DEPTH_LAYER := 18             # 1-based render layer only the distance camera sees (the card rig uses 20)
const MAP_MAX := 120.0              # m: the distance map's range (photo_depth.gdshader max_distance)
const TAPS_MOVING := 16             # blur samples while the view or a slider moves
const TAPS_STILL := 96              # ... once it has been still for STILL_AFTER_MS
const TAPS_STILL_BUSY := 32         # ... when something else keeps the screen redrawing
const STILL_AFTER_MS := 200
const LOOP_ACTIVE_USEC := 2000      # low-power loop sleep while the view moves (keeps 60 fps)
const LOOP_STILL_USEC := 16000      # ... and once it is still (settings.gd PAUSE_LOOP_USEC)
const LOGO_PATHS := ["res://assets/branding/title-logo.png", "res://assets/branding/arjostyle-pickleball.png"]
const LOGO_WIDTH := 0.26            # watermark width, share of the screen's short side
const LOGO_ALPHA := 0.92

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
var _logo: TextureRect
var _logo_on := true
var _focus_slider: HSlider
var _focus_label: Label
var _aperture_slider: HSlider
var _aperture_label: Label
var _fov_slider: HSlider
var _fov_label: Label
var _zoom_slider: HSlider
var _zoom_label: Label
var _blur_layer: CanvasLayer
var _blur_material: ShaderMaterial
var _depth_view: SubViewport
var _depth_cam: Camera3D
var _depth_material: ShaderMaterial
var _map_ok := false                # the distance map is usable on this device
var _dirty := true
var _still := false
var _active_until := 0              # msec: the view counts as moving until then
var _still_taps := TAPS_STILL
var _still_check_at := 0            # msec: when to check that the screen really went idle (0 = no check)
var _still_frames := 0

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
	# Play aids have no place in a photo: YOU / PARTNER labels and rings, the ball's height line
	# (match_feel.gd sets its `visible` every frame, so it is taken off every render layer).
	for node in _game.find_children("DoublesIdentityCues", "Node3D", true, false): _stash(node, "visible", false)
	var feel = _game.get_node_or_null("MatchFeel")
	var height_line = feel.get("_height_line") if feel != null else null
	if is_instance_valid(height_line): _stash(height_line, "layers", 0)
	for node in _game.find_children("*", "Node3D", true, false):
		if node.get_script() == PixelCardRigScript:
			_rigs.append(node)
			# First-person view: show your player whole (cards, not the eye-view arms) for the photo.
			if bool(node.get("first_person")): _stash(node, "first_person", false)
	_add_dof()
	_add_depth_view()
	_focus_slider.set_value_no_signal(_subject_distance())
	_aperture_slider.set_value_no_signal(F_STOPS.size() - 1)
	_fov_slider.set_value_no_signal(clampf(float(_saved_camera.fov), FOV_MIN, FOV_MAX))
	_zoom_slider.set_value_no_signal(1.0)
	_update_lens()
	_check_depth_map()
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
	_fov_label = _label()
	_fov_slider = _slider(FOV_MIN, FOV_MAX, 1.0)
	column.add_child(_row(_fov_label, _fov_slider))
	_zoom_label = _label()
	_zoom_slider = _slider(1.0, ZOOM_MAX, 0.1)
	column.add_child(_row(_zoom_label, _zoom_slider))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(bar)
	bar.add_child(_button("HIDE", _hide_panel, Vector2(170, 60), 24))
	bar.add_child(_button("LOGO", _toggle_logo, Vector2(170, 60), 24))
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
	# Watermark: the game logo in the bottom right corner, in every picture unless switched off.
	_logo = TextureRect.new()
	for path in LOGO_PATHS:
		if ResourceLoader.exists(path):
			_logo.texture = load(path)
			break
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.modulate.a = LOGO_ALPHA
	root.add_child(_logo)
	_focus_slider.value_changed.connect(func(_v: float) -> void: _update_lens())
	_aperture_slider.value_changed.connect(func(_v: float) -> void: _update_lens())
	_fov_slider.value_changed.connect(func(_v: float) -> void: _apply_fov())
	_zoom_slider.value_changed.connect(func(_v: float) -> void: _apply_fov())
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
	if _logo != null and _logo.texture != null:
		var logo_w: float = minf(size.x, size.y) * LOGO_WIDTH
		_logo.size = Vector2(logo_w, logo_w * _logo.texture.get_height() / maxf(_logo.texture.get_width(), 1.0))
		# Above the panel while it is up, in the corner once it is hidden.
		var floor_y: float = _panel.position.y - 12.0 if _panel.visible else size.y - 24.0 - bottom_inset
		_logo.position = Vector2(size.x - _logo.size.x - 24.0, floor_y - _logo.size.y)
		_logo.visible = _logo_on
	if is_instance_valid(_depth_view):
		_depth_view.size = _depth_size()
		_dirty = true

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

## Distance of your player along the view axis (what the lens focuses by).
func _subject_distance() -> float:
	var to: Vector3 = _subject() - _camera.global_position
	var along: float = to.dot(-_camera.global_basis.z)
	return clampf(along if along > 0.0 else to.length(), FOCUS_MIN, FOCUS_MAX)

## Lens: FOV is the lens itself, ZOOM magnifies it (the two sliders make one field of view).
func _apply_fov() -> void:
	if _camera == null: return
	var half: float = tan(deg_to_rad(_fov_slider.value) * 0.5) / maxf(_zoom_slider.value, 1.0)
	_camera.fov = clampf(rad_to_deg(2.0 * atan(half)), 1.0, 179.0)
	_dirty = true

## How much longer the lens is than the match camera's (1 = the same).
func _lens_gain() -> float:
	return tan(deg_to_rad(float(_saved_camera.fov)) * 0.5) / maxf(tan(deg_to_rad(_camera.fov) * 0.5), 0.001)

## Looking around slows down with a long lens so the picture moves the same on screen.
func _look_scale() -> float:
	return clampf(1.0 / _lens_gain(), 0.08, 2.0)

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
	# A preset is a place to stand: back to 1x zoom, and MATCH also puts the match lens back.
	_zoom_slider.set_value_no_signal(1.0)
	if name == "MATCH": _fov_slider.set_value_no_signal(clampf(float(_saved_camera.fov), FOV_MIN, FOV_MAX))
	_apply_fov()
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

## The off-screen view that holds the distance map: a second camera on the same world, with a
## full-screen quad that only it sees (its own render layer) writing distances out.
func _add_depth_view() -> void:
	_depth_view = SubViewport.new()
	_depth_view.name = "PhotoDistanceView"
	_depth_view.size = _depth_size()
	_depth_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_depth_view.positional_shadow_atlas_size = 0
	_depth_view.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_depth_view)
	_depth_cam = Camera3D.new()
	_depth_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_depth_view.add_child(_depth_cam)
	var bit: int = 1 << (DEPTH_LAYER - 1)
	_stash(_camera, "cull_mask", _camera.cull_mask & ~bit)
	_depth_cam.cull_mask = _camera.cull_mask | bit
	var plain := Environment.new()   # no tonemap, fog or glow on the packed distances
	plain.background_mode = Environment.BG_COLOR
	plain.background_color = Color.BLACK
	_depth_cam.environment = plain
	_depth_cam.current = true
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2, 2)
	quad.mesh = mesh
	quad.layers = bit
	quad.extra_cull_margin = 16384.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_depth_material = ShaderMaterial.new()
	_depth_material.shader = DepthShader
	_depth_material.set_shader_parameter("max_distance", MAP_MAX)
	_depth_material.render_priority = 127   # after every see-through thing, however near the camera
	quad.material_override = _depth_material
	_depth_cam.add_child(quad)
	quad.position = Vector3(0, 0, -1)

## The 3D picture's own resolution (pixel_post.gd renders it at half size), so each block of
## the picture has exactly one distance.
func _depth_size() -> Vector2i:
	var root: Viewport = get_viewport()
	return (Vector2i(Vector2(root.size) * root.scaling_3d_scale)).max(Vector2i(8, 8))

## Copy the photo camera into the distance view and redraw the map once.
func _sync_depth() -> void:
	if not is_instance_valid(_depth_view) or _camera == null: return
	_depth_cam.global_transform = _camera.global_transform
	_depth_cam.fov = _camera.fov
	_depth_cam.near = _camera.near
	_depth_cam.far = _camera.far
	_depth_cam.keep_aspect = _camera.keep_aspect
	_depth_view.render_target_update_mode = SubViewport.UPDATE_ONCE

static func _unpack(c: Color) -> float:
	var d := Vector3(roundf((c.r8 - 64) / 3.0), roundf((c.g8 - 64) / 3.0), roundf((c.b8 - 64) / 3.0)).clamp(Vector3.ZERO, Vector3.ONE * 63.0)
	return MAP_MAX * (d.x / 64.0 + d.y / 4096.0 + d.z / 262144.0)

## Start-up check (the blur is still off at f/22): first that the packed bytes arrive intact,
## trying the plain output and then one pre-compensated for an sRGB conversion; then that the
## map holds real, varied distances. Passing both switches the blur to the map.
func _check_depth_map() -> void:
	var bytes_ok := false
	for linearise in [false, true]:
		_depth_material.set_shader_parameter("calibrate", true)
		_depth_material.set_shader_parameter("pre_linearise", linearise)
		_sync_depth()
		await RenderingServer.frame_post_draw
		if not is_instance_valid(_depth_view): return
		var probe: Image = _depth_view.get_texture().get_image()
		if probe == null or probe.is_empty(): break
		var c: Color = probe.get_pixel(probe.get_width() / 2, probe.get_height() / 2)
		if absi(c.r8 - 79) <= 1 and absi(c.g8 - 163) <= 1 and absi(c.b8 - 244) <= 1:
			bytes_ok = true
			break
	_depth_material.set_shader_parameter("calibrate", false)
	var low := INF
	var high := 0.0
	if bytes_ok:
		_sync_depth()
		await RenderingServer.frame_post_draw
		if not is_instance_valid(_depth_view): return
		var map: Image = _depth_view.get_texture().get_image()
		for y in range(4, map.get_height(), maxi(map.get_height() / 24, 1)):
			for x in range(4, map.get_width(), maxi(map.get_width() / 12, 1)):
				var d: float = _unpack(map.get_pixel(x, y))
				low = minf(low, d)
				high = maxf(high, d)
	_map_ok = bytes_ok and high - low > 1.0
	if _blur_material != null:
		_blur_material.set_shader_parameter("use_map", _map_ok)
		_blur_material.set_shader_parameter("depth_map", _depth_view.get_texture())
		_blur_material.set_shader_parameter("map_max", MAP_MAX)
		_blur_material.set_shader_parameter("block", 1.0 / maxf(get_viewport().scaling_3d_scale, 0.01))
	if not _map_ok: _hint.text += "\n(simple blur: no distance map on this device)"
	var monitor = get_node_or_null("/root/PerfMonitor")
	if monitor != null and monitor.has_method("note"): monitor.note("photo_depth", {"ok": _map_ok, "bytes": bytes_ok, "near": snappedf(low, 0.01) if low < INF else -1.0, "far": snappedf(high, 0.01)})
	_place()
	_dirty = true

func _update_lens() -> void:
	var focus: float = _focus_slider.value
	var stop: float = F_STOPS[clampi(int(_aperture_slider.value), 0, F_STOPS.size() - 1)]
	_focus_label.text = "FOCUS %.1f m" % focus
	_aperture_label.text = "APERTURE f/%s" % (str(int(stop)) if stop >= 4.0 else "%.1f" % stop)
	_fov_label.text = "FOV %d deg" % int(_fov_slider.value)
	_zoom_label.text = "ZOOM %.1fx" % _zoom_slider.value
	if not is_instance_valid(_blur_layer) or _camera == null: return
	_mark_active()
	var size: Vector2 = get_viewport().get_visible_rect().size
	var scale: float = size.y / 1080.0
	# A longer lens at the same f-stop blurs more.
	var blur: float = minf(BLUR_AT_F14 * (1.4 / stop) * _lens_gain(), BLUR_CAP) * scale
	_blur_layer.visible = stop < 22.0 and blur >= 0.5
	if not _blur_layer.visible: return
	_blur_material.set_shader_parameter("viewport_size", size)
	_blur_material.set_shader_parameter("blur_radius", blur)
	_blur_material.set_shader_parameter("focus_distance", focus)
	# The sharp zone deepens with distance, as with a real lens.
	_blur_material.set_shader_parameter("focus_range", FOCUS_DEPTH * 0.5 + FOCUS_DEPTH_GROWTH * focus)
	if _map_ok: return
	# Fallback only (no distance map): every player (feet to head; a player's origin is at the
	# waist) and the ball carry their own distance; drawn far to near so a nearer one wins.
	var subjects: Array = []
	if _game.has_method("get_players"):
		for p in _game.get_players(): subjects.append([p.global_position - Vector3.UP * 0.95, p.global_position + Vector3.UP * 0.8, 0.22, 14.0])
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
	_blur_material.set_shader_parameter("cam_pos", _camera.global_position)
	_blur_material.set_shader_parameter("cam_right", basis.x)
	_blur_material.set_shader_parameter("cam_up", basis.y)
	_blur_material.set_shader_parameter("cam_forward", forward)
	_blur_material.set_shader_parameter("tan_half", tans)
	_blur_material.set_shader_parameter("floor_y", PickleballConstants.FLOOR_Y)
	_blur_material.set_shader_parameter("seg", segs)
	_blur_material.set_shader_parameter("seg_radius", PackedFloat32Array(radii))
	_blur_material.set_shader_parameter("seg_dist", PackedFloat32Array(dists))

## The view or a slider just changed: few blur samples and a quick loop until it settles.
func _mark_active() -> void:
	_active_until = Time.get_ticks_msec() + STILL_AFTER_MS
	_still_check_at = 0
	if _still or _blur_material.get_shader_parameter("taps") == null:
		_still = false
		_blur_material.set_shader_parameter("taps", TAPS_MOVING)
	OS.low_processor_usage_mode_sleep_usec = LOOP_ACTIVE_USEC

## Settled: one more map and the full sample count, then the screen can go idle.
func _settle(now: int) -> void:
	_still = true
	_sync_depth()
	if _blur_material != null: _blur_material.set_shader_parameter("taps", _still_taps)
	OS.low_processor_usage_mode_sleep_usec = LOOP_STILL_USEC
	_still_frames = Engine.get_frames_drawn()
	_still_check_at = now + 1000

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
			_yaw -= event.relative.x * LOOK_PER_PIXEL * scale * _look_scale()
			_pitch -= event.relative.y * LOOK_PER_PIXEL * scale * _look_scale()
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
		_yaw -= event.relative.x * LOOK_PER_PIXEL * scale * _look_scale()
		_pitch -= event.relative.y * LOOK_PER_PIXEL * scale * _look_scale()
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
	var now: int = Time.get_ticks_msec()
	if _dirty:
		_dirty = false
		# Cards face the camera; the match is paused, so redraw them once for the new view.
		for rig in _rigs:
			if is_instance_valid(rig): rig._draw_cards(0.0)
		_sync_depth()
		_update_lens()   # the lens or the view changed
	elif not _still and now >= _active_until:
		_settle(now)
	elif _still_check_at > 0 and now >= _still_check_at:
		# Still, yet the screen kept redrawing (something else animates): a full-quality blur
		# every frame would cost too much, so settle for fewer samples.
		_still_check_at = 0
		if Engine.get_frames_drawn() - _still_frames > 20 and _still_taps != TAPS_STILL_BUSY:
			_still_taps = TAPS_STILL_BUSY
			if _blur_material != null: _blur_material.set_shader_parameter("taps", _still_taps)

func _hide_panel() -> void:
	_panel.visible = false
	_hint.visible = false
	_place()

func _show_panel() -> void:
	_panel.visible = true
	_hint.visible = true
	_place()

func _toggle_logo() -> void:
	_logo_on = not _logo_on
	_place()

## Back to the pause menu with the match view restored.
func finish() -> void:
	OS.low_processor_usage_mode_sleep_usec = LOOP_STILL_USEC
	if is_instance_valid(_blur_layer): _blur_layer.queue_free()
	if is_instance_valid(_depth_view): _depth_view.queue_free()
	_depth_view = null
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
	if is_instance_valid(_menu) and _menu.has_method("photo_mode_closed"): _menu.photo_mode_closed()
	queue_free()

func _exit_tree() -> void:
	OS.low_processor_usage_mode_sleep_usec = LOOP_STILL_USEC

func _stash(node: Node, property: String, value) -> void:
	_hidden.append([node, property, node.get(property)])
	node.set(property, value)
