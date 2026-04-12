class_name ReactionHitButton extends Control
## Easy-mode reaction HIT button: a circular button in the lower-right with a
## collapsing outer ring. The ring radius is driven by time-to-contact (TTC)
## from player_paddle_posture.gd, so the ring paces correctly across slow lobs
## and fast drives alike. The "perfect window" is when TTC is near zero, which
## aligns with the BLUE contact-imminent stage and the ring reaching the
## button perimeter.

signal auto_fire_requested

const BUTTON_RADIUS: float = 60.0
const RING_RADIUS_MAX: float = 160.0            # ~2.67x button radius
const PERFECT_TOLERANCE: float = 14.0           # pixels — ring within ±14px of button edge = perfect
const TTC_MAX: float = 1.2                      # seconds — ring starts closing when ball is ≤ this far out
const TTC_PERFECT: float = 0.15                 # seconds — TTC threshold for the perfect window
const GRADE_FLASH_DURATION: float = 0.6         # seconds — grade label stays on button after contact

@export var auto_fire_on_perfect: bool = false  # when true, fires auto_fire_requested once per ball at perfect window

# Ring + button colors
const COLOR_BUTTON_IDLE := Color(0.95, 0.35, 0.25, 0.92)   # red-orange
const COLOR_BUTTON_PERFECT := Color(0.3, 1.0, 0.4, 1.0)    # bright green
const COLOR_RING_FAR := Color(1.0, 0.85, 0.2, 0.8)         # yellow
const COLOR_RING_PERFECT := Color(0.3, 1.0, 0.4, 1.0)
const COLOR_RING_LATE := Color(1.0, 0.25, 0.25, 0.7)
const COLOR_BUTTON_OUTLINE := Color(0.1, 0.1, 0.15, 0.85)
# Idle-state (no incoming ball) colors — dimmer than active
const COLOR_BUTTON_IDLE_DIM := Color(0.35, 0.35, 0.4, 0.7)
const COLOR_RING_IDLE_DIM := Color(0.6, 0.6, 0.65, 0.35)

var _active: bool = false                # true when a ball is incoming (ring animating)
var _ring_radius: float = RING_RADIUS_MAX
var _in_perfect_window: bool = false
var _posture_label: String = ""
var _flash_t: float = 0.0                # perfect-hit flash (decays 0.3 -> 0)
var _pulse_phase: float = 0.0            # idle-state breathing on the button
var _grade_label: String = ""            # last grade from posture module
var _grade_flash_t: float = 0.0          # seconds remaining on grade HUD flash
var _auto_fired_this_ball: bool = false  # one-shot auto-fire guard

func _ready() -> void:
	custom_minimum_size = Vector2(RING_RADIUS_MAX * 2.2, RING_RADIUS_MAX * 2.2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	visible = true
	_ring_radius = RING_RADIUS_MAX

# Called by game.gd whenever the posture module's incoming_stage_changed signal fires.
# stage: -1=clear (return to idle), 0=PINK, 1=PURPLE, 2=BLUE
# ttc: seconds until ball reaches committed ghost (primary ring driver)
func update_from_stage(stage: int, posture_name: String, _commit_dist: float, _ball2ghost: float, ttc: float) -> void:
	if stage < 0:
		enter_idle()
		return
	_active = true
	visible = true
	_posture_label = posture_name
	# Ring radius is a pure function of TTC: TTC_MAX seconds out = max radius,
	# 0 seconds = button edge. Correct pacing for both slow lobs and fast drives.
	var t: float = clampf(1.0 - ttc / TTC_MAX, 0.0, 1.0)
	_ring_radius = lerp(RING_RADIUS_MAX, BUTTON_RADIUS, t)
	var was_perfect: bool = _in_perfect_window
	_in_perfect_window = (stage == 2) or (ttc < TTC_PERFECT) or (absf(_ring_radius - BUTTON_RADIUS) < PERFECT_TOLERANCE)
	if _in_perfect_window and not was_perfect and auto_fire_on_perfect and not _auto_fired_this_ball:
		_auto_fired_this_ball = true
		auto_fire_requested.emit()
	queue_redraw()

# Called by game.gd when posture module emits grade_flashed. Displays the grade
# as a HUD flash on the button for GRADE_FLASH_DURATION seconds.
func show_grade(grade: String) -> void:
	_grade_label = grade
	_grade_flash_t = GRADE_FLASH_DURATION
	queue_redraw()

# Return to the persistent idle state: button stays visible but greyed-out,
# ring expanded to max radius, no posture label, no perfect window.
func enter_idle() -> void:
	_active = false
	visible = true
	_in_perfect_window = false
	_ring_radius = RING_RADIUS_MAX
	_posture_label = ""
	_flash_t = 0.0
	_auto_fired_this_ball = false
	queue_redraw()

# Fully hide the button (unused now that the button persists, kept for completeness).
func hide_button() -> void:
	_active = false
	visible = false
	_in_perfect_window = false
	_flash_t = 0.0
	queue_redraw()

func is_perfect() -> bool:
	return _active and _in_perfect_window

func trigger_perfect_flash() -> void:
	_flash_t = 0.3
	var tw := create_tween()
	tw.tween_property(self, "_flash_t", 0.0, 0.3)

func _process(delta: float) -> void:
	# Pulse runs in both idle and active states so the button always feels alive
	_pulse_phase = fmod(_pulse_phase + delta * (4.0 if _active else 2.0), TAU)
	if _grade_flash_t > 0.0:
		_grade_flash_t = maxf(_grade_flash_t - delta, 0.0)
	queue_redraw()

func _draw() -> void:
	var center: Vector2 = size * 0.5
	var font: Font = ThemeDB.fallback_font

	# Grade HUD flash renders in both idle and active states so the flash survives
	# reset_incoming_highlight() flipping the button back to idle.
	if _grade_flash_t > 0.0 and _grade_label != "":
		var grade_alpha: float = clampf(_grade_flash_t / GRADE_FLASH_DURATION, 0.0, 1.0)
		var grade_color: Color
		match _grade_label:
			"PERFECT": grade_color = Color(0.3, 1.0, 0.4, grade_alpha)
			"GREAT":   grade_color = Color(0.5, 1.0, 0.6, grade_alpha)
			"GOOD":    grade_color = Color(1.0, 0.9, 0.3, grade_alpha)
			"OK":      grade_color = Color(1.0, 0.6, 0.2, grade_alpha)
			_:         grade_color = Color(1.0, 0.3, 0.3, grade_alpha)
		var grade_size: int = 34
		var grade_w: float = font.get_string_size(_grade_label, HORIZONTAL_ALIGNMENT_CENTER, -1, grade_size).x
		draw_string(font, center + Vector2(-grade_w * 0.5, -BUTTON_RADIUS - 52.0), _grade_label, HORIZONTAL_ALIGNMENT_CENTER, -1, grade_size, grade_color)

	if not _active:
		# ── IDLE STATE — persistent, dimmed, no collapsing ring ──
		# Faint outer ring at max radius
		draw_arc(center, RING_RADIUS_MAX, 0.0, TAU, 64, COLOR_RING_IDLE_DIM, 3.0, true)
		# Dimmed button with slow breathing pulse
		var idle_pulse: float = 1.0 + 0.03 * sin(_pulse_phase)
		var idle_r: float = BUTTON_RADIUS * idle_pulse
		draw_arc(center, idle_r + 2.0, 0.0, TAU, 48, COLOR_BUTTON_OUTLINE, 4.0, true)
		draw_circle(center, idle_r, COLOR_BUTTON_IDLE_DIM)
		# "HIT" label dimmed
		var itxt: String = "HIT"
		var itxt_size: int = 44
		var itext_w: float = font.get_string_size(itxt, HORIZONTAL_ALIGNMENT_CENTER, -1, itxt_size).x
		draw_string(font, center + Vector2(-itext_w * 0.5, 15.0), itxt, HORIZONTAL_ALIGNMENT_CENTER, -1, itxt_size, Color(1, 1, 1, 0.55))
		return

	# ── ACTIVE STATE — collapsing ring around committed ball ──
	# Outer ring color based on phase
	var ring_col: Color = COLOR_RING_FAR
	if _in_perfect_window:
		ring_col = COLOR_RING_PERFECT
	elif _ring_radius < BUTTON_RADIUS - PERFECT_TOLERANCE:
		ring_col = COLOR_RING_LATE
	draw_arc(center, _ring_radius, 0.0, TAU, 72, ring_col, 7.0, true)
	# Faint tolerance guide ring visible during perfect window
	if _in_perfect_window:
		draw_arc(center, BUTTON_RADIUS + PERFECT_TOLERANCE, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 2.0, true)

	# Button circle with pulse + flash
	var pulse_scale: float = 1.0 + 0.04 * sin(_pulse_phase)
	var btn_r: float = BUTTON_RADIUS * pulse_scale
	var btn_col: Color = COLOR_BUTTON_PERFECT if _in_perfect_window else COLOR_BUTTON_IDLE
	if _flash_t > 0.0:
		btn_col = btn_col.lerp(Color.WHITE, clampf(_flash_t / 0.3, 0.0, 1.0))
		btn_r *= (1.0 + 0.15 * (_flash_t / 0.3))
	draw_arc(center, btn_r + 2.5, 0.0, TAU, 48, COLOR_BUTTON_OUTLINE, 5.0, true)
	draw_circle(center, btn_r, btn_col)

	# "HIT" label
	var txt: String = "HIT"
	var txt_size: int = 44
	var text_w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, txt_size).x
	draw_string(font, center + Vector2(-text_w * 0.5, 15.0), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, txt_size, Color.WHITE)

	# Posture name caption below the button
	if _posture_label != "":
		var pn_size: int = 16
		var pn_w: float = font.get_string_size(_posture_label, HORIZONTAL_ALIGNMENT_CENTER, -1, pn_size).x
		draw_string(font, center + Vector2(-pn_w * 0.5, BUTTON_RADIUS + 32.0), _posture_label, HORIZONTAL_ALIGNMENT_CENTER, -1, pn_size, Color(1, 1, 1, 0.85))

	# "REACT!" title above the button when in perfect window
	if _in_perfect_window:
		var title_size: int = 20
		var title: String = "REACT!"
		var title_w: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, title_size).x
		draw_string(font, center + Vector2(-title_w * 0.5, -BUTTON_RADIUS - 18.0), title, HORIZONTAL_ALIGNMENT_CENTER, -1, title_size, COLOR_RING_PERFECT)
