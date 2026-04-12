extends Node
class_name ScoreboardUI

## ScoreboardUI.gd - Centralizes HUD management, label formatting, and UI animations.
## Handles the scoreboard, speedometer, shot-type indicators, and fault big-text.

# HUD Reference
var _hud: CanvasLayer

# State / Timers
var _shot_type_timer: float = 0.0
var _fault_visible_timer: float = 0.0
var _zone_visible_timer: float = 0.0

const AI_DIFFICULTY_NAMES: Array[String] = ["EASY", "MEDIUM", "HARD"]
const AI_DIFFICULTY_COLORS: Array[Color] = [Color(0.4, 1.0, 0.4), Color(1.0, 0.85, 0.3), Color(1.0, 0.35, 0.35)]

func setup(hud: CanvasLayer) -> void:
	_hud = hud
	# Ensure clear start (with null check)
	if _hud != null:
		_hide_temporary_ui()

func _process(delta: float) -> void:
	_update_shot_type_fade(delta)
	_update_timers(delta)

func update_score(score_l: int, score_r: int) -> void:
	if _hud and _hud.get("score"):
		_hud.score.text = "%d - %d" % [score_l, score_r]

func set_state_text(text: String) -> void:
	if _hud and _hud.get("state"):
		_hud.state.text = text

func update_difficulty(difficulty: int) -> void:
	if _hud and _hud.get("difficulty"):
		var label: Label = _hud.difficulty
		label.text = "AI: " + AI_DIFFICULTY_NAMES[difficulty] + "  [X]"
		label.add_theme_color_override("font_color", AI_DIFFICULTY_COLORS[difficulty])

func show_fault(headline: String, detail: String) -> void:
	if _hud and _hud.get("fault"):
		_hud.fault.text = "%s\n%s" % [headline, detail]
		_hud.fault.visible = true
		_fault_visible_timer = 2.5

func show_out(text: String = "OUT!") -> void:
	if _hud and _hud.get("out_text"):
		_hud.out_text.text = text
		_hud.out_text.visible = true
	if _hud and _hud.get("zone"):
		_hud.zone.visible = false

func hide_out() -> void:
	if _hud and _hud.get("out_text"):
		_hud.out_text.visible = false

func show_zone(zone_name: String) -> void:
	if _hud and _hud.get("zone"):
		_hud.zone.text = zone_name
		_hud.zone.visible = true
		_zone_visible_timer = 2.0

func show_speed(speed_mph: float) -> void:
	if _hud and _hud.get("speed"):
		_hud.speed.text = "%.1f mph" % speed_mph
		_hud.speed.modulate.a = 1.0

func show_shot_type(shot_name: String) -> void:
	if _hud and _hud.get("shot_type"):
		var label: Label = _hud.shot_type
		label.text = shot_name
		_apply_shot_type_color(label, shot_name)
		label.modulate.a = 1.0
		_shot_type_timer = 2.5

func update_debug_content(content: String) -> void:
	if _hud and _hud.get("debug"):
		_hud.debug.text = content

func update_posture_debug(content: String) -> void:
	if _hud and _hud.get("posture_debug"):
		_hud.posture_debug.text = content

func set_debug_visuals_active(active: bool) -> void:
	if _hud:
		if _hud.get("zone"): _hud.zone.visible = active
		if _hud.get("posture_debug"): _hud.posture_debug.visible = active
		if _hud.get("debug"): _hud.debug.visible = active

func hide_all_hud() -> void:
	if _hud:
		if _hud.has_method("set_gameplay_elements_visible"):
			_hud.set_gameplay_elements_visible(false)
		else:
			_hud.visible = false
		_hide_temporary_ui()

func show_all_hud() -> void:
	if _hud:
		if _hud.has_method("set_gameplay_elements_visible"):
			_hud.set_gameplay_elements_visible(true)
		else:
			_hud.visible = true

# Internal Helpers
func _apply_shot_type_color(label: Label, shot_name: String) -> void:
	match shot_name:
		"FAST", "SMASH":
			label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.15, 1.0))
		"VOLLEY":
			label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2, 1.0))
		"DROP", "DINK":
			label.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0, 1.0))
		"LOB":
			label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2, 1.0))
		"RETURN":
			label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7, 1.0))
		_:
			label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))

func _update_shot_type_fade(delta: float) -> void:
	if _shot_type_timer <= 0.0: return
	_shot_type_timer -= delta
	if _hud and _hud.get("shot_type"):
		var label = _hud.shot_type
		if _shot_type_timer <= 0.6:
			label.modulate.a = _shot_type_timer / 0.6
		else:
			label.modulate.a = 1.0

func _update_timers(delta: float) -> void:
	if _fault_visible_timer > 0:
		_fault_visible_timer -= delta
		if _fault_visible_timer <= 0:
			if _hud.get("fault"): _hud.fault.visible = false
			
	if _zone_visible_timer > 0:
		_zone_visible_timer -= delta
		if _zone_visible_timer <= 0:
			if _hud.get("zone"): _hud.zone.visible = false

func _hide_temporary_ui() -> void:
	if _hud.get("fault"): _hud.fault.visible = false
	if _hud.get("out_text"): _hud.out_text.visible = false
	if _hud.get("zone"): _hud.zone.visible = false
	if _hud.get("shot_type"): _hud.shot_type.modulate.a = 0.0
