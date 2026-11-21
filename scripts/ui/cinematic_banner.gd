extends CanvasLayer
class_name CinematicBanner
## Full-screen cinematic overlay: a timed banner (change of ends, match point) and a
## black "cut" flash that hides a hard camera cut. Never blocks input; any press skips.

signal skipped

var _dim: ColorRect
var _box: VBoxContainer
var _title: Label
var _sub: Label
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
	_box = VBoxContainer.new()
	_box.set_anchors_preset(Control.PRESET_CENTER)
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.modulate.a = 0.0
	add_child(_box)
	_title = _label(46, Color(1, 0.93, 0.62))
	_sub = _label(22, Color(0.86, 0.9, 0.96))
	_box.add_child(_title)
	_box.add_child(_sub)

func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# Fade in (0.35 s), hold, fade out (0.45 s) over `seconds` in total.
func show_banner(title: String, sub: String = "", seconds: float = 3.0, dim_alpha: float = 0.45, title_size: int = 46, sub_size: int = 22) -> void:
	_kill()
	_title.add_theme_font_size_override("font_size", title_size)
	_sub.add_theme_font_size_override("font_size", sub_size)
	_title.add_theme_constant_override("outline_size", maxi(8, title_size / 6))
	_title.text = title
	_sub.text = sub
	PerfMonitor.note("banner", {"title": title, "sub": sub, "seconds": seconds})
	_sub.visible = sub != ""
	_banner_active = true
	var fade_in := minf(0.35, seconds * 0.2)
	var fade_out := minf(0.45, seconds * 0.25)
	var hold := maxf(0.0, seconds - fade_in - fade_out)
	_tween = create_tween().set_parallel(false)
	_tween.tween_property(_dim, "color:a", dim_alpha, fade_in)
	_tween.parallel().tween_property(_box, "modulate:a", 1.0, fade_in)
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
