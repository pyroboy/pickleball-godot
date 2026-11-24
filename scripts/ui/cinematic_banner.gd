extends CanvasLayer
class_name CinematicBanner
## Full-screen cinematic overlay: a timed banner (change of ends, match point) and a
## black "cut" flash that hides a hard camera cut. Never blocks input; any press skips.

signal skipped

const PixelBanner = preload("res://scripts/ui/pixel_banner.gd")
const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
const Layout = preload("res://scripts/ui/mobile_layout.gd")

var _dim: ColorRect
var _box: Control           # holder faded by the tween
var _banner: Control        # pixel_banner.gd
var _tween: Tween
var _banner_active := false

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_box = Control.new()
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.modulate.a = 0.0
	add_child(_box)
	_banner = PixelBanner.new()
	_box.add_child(_banner)

# Kit banner (proposal PDF p.23): navy plate (gold for MATCH / GAME POINT, which sweeps in
# from the side), the sub line as a ribbon. Fade in (0.35 s), hold, fade out (0.45 s).
func show_banner(title: String, sub: String = "", seconds: float = 3.0, dim_alpha: float = 0.45, title_size: int = 46, sub_size: int = 22) -> void:
	_kill()
	PerfMonitor.note("banner", {"title": title, "sub": sub, "seconds": seconds})
	var view: Vector2 = _box.get_viewport_rect().size
	var portrait: bool = Layout.is_portrait(view)
	var big: bool = "POINT" in title.to_upper()
	var ui_sounds: Node = get_node_or_null("/root/Settings/UiSounds")
	if ui_sounds != null: ui_sounds.stinger(big)
	_banner.s = Layout.scale_for(view) if portrait else view.y / 720.0
	_banner.title_px = float(title_size) * (1.0 if portrait else 0.75)
	_banner.ribbon_px = float(sub_size) * (1.0 if portrait else 0.75)
	_banner.max_width = view.x - 32.0 * _banner.s
	_banner.present(title.to_upper(), sub.to_upper(), UiTheme.KIT_GOLD if big else UiTheme.SURFACE_HOVER, UiTheme.PANEL, not big)
	_banner.center_on(view * Vector2(0.5, 0.42))
	_banner_active = true
	var fade_in := minf(0.35, seconds * 0.2)
	var fade_out := minf(0.45, seconds * 0.25)
	var hold := maxf(0.0, seconds - fade_in - fade_out)
	_tween = create_tween().set_parallel(false)
	_tween.tween_property(_dim, "color:a", dim_alpha, fade_in)
	_tween.parallel().tween_property(_box, "modulate:a", 1.0, fade_in)
	if big:
		var rest: Vector2 = _banner.position
		_banner.position.x = -_banner.size.x
		_tween.parallel().tween_property(_banner, "position", rest, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(hold)
	_tween.tween_property(_dim, "color:a", 0.0, fade_out)
	_tween.parallel().tween_property(_box, "modulate:a", 0.0, fade_out)
	_tween.tween_callback(func(): _banner_active = false)

# Opaque black this frame, then fade out: hides a camera cut made on the same frame.
func cut_flash(fade_seconds: float = 0.6) -> void:
	if _banner_active: return # the banner's dim already covers it; keep the banner
	_kill()
	_dim.color.a = 1.0
	_tween = create_tween()
	_tween.tween_interval(0.12)
	_tween.tween_property(_dim, "color:a", 0.0, fade_seconds)

func skip() -> void:
	if not _banner_active and _dim.color.a <= 0.0: return
	_kill()
	_banner_active = false
	_tween = create_tween()
	_tween.tween_property(_dim, "color:a", 0.0, 0.15)
	_tween.parallel().tween_property(_box, "modulate:a", 0.0, 0.15)
	skipped.emit()

func _kill() -> void:
	if _tween != null and _tween.is_valid(): _tween.kill()
	_tween = null

func _input(event: InputEvent) -> void:
	if not _banner_active: return
	if (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed):
		skip()
