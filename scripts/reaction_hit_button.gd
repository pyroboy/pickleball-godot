class_name ReactionHitButton extends Control

const MobileLayout = preload("res://scripts/ui/mobile_layout.gd")







signal auto_fire_requested

const BUTTON_RADIUS: float = 42.0
const RING_RADIUS_MAX: float = 105.0
const PERFECT_TOLERANCE: float = 14.0
const TTC_MAX: float = 1.2
const TTC_PERFECT: float = 0.15
const GRADE_FLASH_DURATION: float = 0.6

@export var auto_fire_on_perfect: bool = false


const COLOR_BUTTON_IDLE: = Color("294655")
const COLOR_BUTTON_PERFECT: = Color("bde879")
const COLOR_RING_FAR: = Color("f5d38b")
const COLOR_RING_PERFECT: = Color("bde879")
const COLOR_RING_LATE: = Color("ffab9c")
const COLOR_BUTTON_OUTLINE: = Color("102431")

const COLOR_BUTTON_IDLE_DIM: = Color("1c3646")
const COLOR_RING_IDLE_DIM: = Color(0.66, 0.75, 0.8, 0.22)

var _active: bool = false
var _ring_radius: float = RING_RADIUS_MAX
var _in_perfect_window: bool = false
var _posture_label: String = ""
var _flash_t: float = 0.0
var _pulse_phase: float = 0.0
var _grade_label: String = ""
var _grade_flash_t: float = 0.0
var _auto_fired_this_ball: bool = false

func _ready() -> void :
	custom_minimum_size = Vector2(RING_RADIUS_MAX * 2.2, RING_RADIUS_MAX * 2.2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	visible = _presentation_allowed()
	_ring_radius = RING_RADIUS_MAX




func update_from_stage(stage: int, posture_name: String, _commit_dist: float, _ball2ghost: float, ttc: float) -> void :
	if stage < 0:
		enter_idle()
		return
	_active = true
	visible = _presentation_allowed()
	_posture_label = posture_name


	var t: float = clampf(1.0 - ttc / TTC_MAX, 0.0, 1.0)
	_ring_radius = lerp(RING_RADIUS_MAX, BUTTON_RADIUS, t)
	var was_perfect: bool = _in_perfect_window
	_in_perfect_window = (stage == 2) or (ttc < TTC_PERFECT) or (absf(_ring_radius - BUTTON_RADIUS) < PERFECT_TOLERANCE)
	if _in_perfect_window and not was_perfect and auto_fire_on_perfect and not _auto_fired_this_ball:
		_auto_fired_this_ball = true
		auto_fire_requested.emit()
	queue_redraw()



func show_grade(grade: String) -> void :
	_grade_label = grade
	_grade_flash_t = GRADE_FLASH_DURATION
	queue_redraw()



func enter_idle() -> void :
	_active = false
	visible = _presentation_allowed()
	_in_perfect_window = false
	_ring_radius = RING_RADIUS_MAX
	_posture_label = ""
	_flash_t = 0.0
	_auto_fired_this_ball = false
	queue_redraw()


func hide_button() -> void :
	_active = false
	visible = false
	_in_perfect_window = false
	_flash_t = 0.0
	queue_redraw()

func is_perfect() -> bool:
	return _active and _in_perfect_window

func trigger_perfect_flash() -> void :
	_flash_t = 0.3
	var tw: = create_tween()
	tw.tween_property(self, "_flash_t", 0.0, 0.3)

func _process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_process(delta)
	PerfMonitor.record("proc.reaction_hit_button", Time.get_ticks_usec() - _pt)

func _perf_process(delta: float) -> void:

	_pulse_phase = fmod(_pulse_phase + delta * (4.0 if _active else 2.0), TAU)
	if _grade_flash_t > 0.0:
		_grade_flash_t = maxf(_grade_flash_t - delta, 0.0)
	queue_redraw()

func _presentation_allowed() -> bool:
	# The portrait touch deck owns all timing presentation. Physics may call
	# enter_idle after its process callback, so suppression must live here.
	return not MobileLayout.is_portrait(get_viewport().get_visible_rect().size)

func _draw() -> void :
	if not _presentation_allowed(): return
	var center: Vector2 = size * 0.5
	var font: Font = ThemeDB.fallback_font

	draw_circle(center, RING_RADIUS_MAX + 7.0, Color(0.06, 0.14, 0.19, 0.84))



	if _grade_flash_t > 0.0 and _grade_label != "":
		var grade_alpha: float = clampf(_grade_flash_t / GRADE_FLASH_DURATION, 0.0, 1.0)
		var grade_color: Color
		match _grade_label:
			"PERFECT": grade_color = Color(0.3, 1.0, 0.4, grade_alpha)
			"GREAT": grade_color = Color(0.5, 1.0, 0.6, grade_alpha)
			"GOOD": grade_color = Color(1.0, 0.9, 0.3, grade_alpha)
			"OK": grade_color = Color(1.0, 0.6, 0.2, grade_alpha)
			_: grade_color = Color(1.0, 0.3, 0.3, grade_alpha)
		var grade_size: int = 34
		var grade_w: float = font.get_string_size(_grade_label, HORIZONTAL_ALIGNMENT_CENTER, -1, grade_size).x
		draw_string(font, center + Vector2( - grade_w * 0.5, - BUTTON_RADIUS - 52.0), _grade_label, HORIZONTAL_ALIGNMENT_CENTER, -1, grade_size, grade_color)

	if not _active:


		draw_arc(center, RING_RADIUS_MAX, 0.0, TAU, 64, COLOR_RING_IDLE_DIM, 3.0, true)

		var idle_pulse: float = 1.0 + 0.03 * sin(_pulse_phase)
		var idle_r: float = BUTTON_RADIUS * idle_pulse
		draw_arc(center, idle_r + 2.0, 0.0, TAU, 48, COLOR_BUTTON_OUTLINE, 4.0, true)
		draw_circle(center, idle_r, COLOR_BUTTON_IDLE_DIM)

		var itxt: String = "SPACE"
		var itxt_size: int = 18
		var itext_w: float = font.get_string_size(itxt, HORIZONTAL_ALIGNMENT_CENTER, -1, itxt_size).x
		draw_string(font, center + Vector2( - itext_w * 0.5, 6.0), itxt, HORIZONTAL_ALIGNMENT_CENTER, -1, itxt_size, Color("a9becb"))
		_draw_caption(font, center, "TIMING GUIDE", -66, Color("a9becb"), 13)
		_draw_caption(font, center, "Await incoming ball", 76, Color("a9becb"), 13)
		return



	var ring_col: Color = COLOR_RING_FAR
	if _in_perfect_window:
		ring_col = COLOR_RING_PERFECT
	elif _ring_radius < BUTTON_RADIUS - PERFECT_TOLERANCE:
		ring_col = COLOR_RING_LATE
	draw_arc(center, _ring_radius, 0.0, TAU, 72, ring_col, 7.0, true)

	if _in_perfect_window:
		draw_arc(center, BUTTON_RADIUS + PERFECT_TOLERANCE, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 2.0, true)


	var pulse_scale: float = 1.0 + 0.04 * sin(_pulse_phase)
	var btn_r: float = BUTTON_RADIUS * pulse_scale
	var btn_col: Color = COLOR_BUTTON_PERFECT if _in_perfect_window else COLOR_BUTTON_IDLE
	if _flash_t > 0.0:
		btn_col = btn_col.lerp(Color.WHITE, clampf(_flash_t / 0.3, 0.0, 1.0))
		btn_r *= (1.0 + 0.15 * (_flash_t / 0.3))
	draw_arc(center, btn_r + 2.5, 0.0, TAU, 48, COLOR_BUTTON_OUTLINE, 5.0, true)
	draw_circle(center, btn_r, btn_col)


	var txt: String = "SPACE"
	var txt_size: int = 18
	var text_w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, txt_size).x
	draw_string(font, center + Vector2( - text_w * 0.5, 6.0), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, txt_size, Color("102431") if _in_perfect_window else Color("eef5fa"))


	if _posture_label != "":
		var pn_size: int = 13
		var caption: String = _posture_label.left(24)
		var pn_w: float = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_CENTER, -1, pn_size).x
		draw_string(font, center + Vector2( - pn_w * 0.5, BUTTON_RADIUS + 32.0), caption, HORIZONTAL_ALIGNMENT_CENTER, -1, pn_size, Color(1, 1, 1, 0.85))


	if _in_perfect_window:
		var title_size: int = 16
		var title: String = "RELEASE"
		var title_w: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, title_size).x
		draw_string(font, center + Vector2( - title_w * 0.5, - BUTTON_RADIUS - 18.0), title, HORIZONTAL_ALIGNMENT_CENTER, -1, title_size, COLOR_RING_PERFECT)

func _draw_caption(font: Font, center: Vector2, text: String, y: float, color: Color, font_size: int) -> void :
	var width: = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	draw_string(font, center + Vector2( - width * 0.5, y), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)
