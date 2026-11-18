class_name PostureColors
extends RefCounted

const _PostureConstants = preload("res://scripts/posture_constants.gd")















const STAGE_PINK_ALBEDO: Color = Color(1.0, 0.3, 0.7)
const STAGE_PINK_EMISSION: Color = Color(0.95, 0.2, 0.6)
const STAGE_PINK_EM_MULT: float = 0.5
const STAGE_PINK_ALPHA: float = _PostureConstants.POSTURE_GHOST_ACTIVE_ALPHA


const STAGE_PURPLE_ALBEDO: Color = Color(0.6, 0.1, 1.0)
const STAGE_PURPLE_EMISSION: Color = Color(0.5, 0.05, 0.95)
const STAGE_PURPLE_EM_MULT: float = _PostureConstants.POSTURE_GHOST_NEAR_EMISSION
const STAGE_PURPLE_ALPHA: float = _PostureConstants.POSTURE_GHOST_NEAR_ALPHA


const STAGE_BLUE_ALBEDO: Color = Color(0.15, 0.5, 1.0)
const STAGE_BLUE_EMISSION: Color = Color(0.1, 0.4, 1.0)
const STAGE_BLUE_EM_MULT: float = _PostureConstants.POSTURE_GHOST_NEAR_EMISSION * 1.4
const STAGE_BLUE_ALPHA: float = 0.75


const GREEN_ALBEDO: Color = Color(0.1, 1.0, 0.2)
const GREEN_EMISSION: Color = Color(0.0, 1.0, 0.1)
const GREEN_EM_MULT: float = _PostureConstants.POSTURE_GHOST_NEAR_EMISSION


const HIT_ALBEDO: Color = Color(1.0, 0.45, 0.0)
const HIT_EMISSION: Color = Color(1.0, 0.3, 0.0)
const HIT_EM_MULT_MIN: float = 0.1
const HIT_EM_MULT_MAX: float = 3.0
const HIT_ALPHA_MIN: float = _PostureConstants.POSTURE_GHOST_ALPHA
const HIT_ALPHA_MAX: float = 0.85


const NEAR_EM_MULT_MIN: float = 0.24
const NEAR_EM_MULT_MAX: float = _PostureConstants.POSTURE_GHOST_NEAR_EMISSION
const BASE_EM_MULT: float = 0.12
const BASE_ALPHA: float = _PostureConstants.POSTURE_GHOST_ALPHA
const ACTIVE_ALPHA: float = _PostureConstants.POSTURE_GHOST_ACTIVE_ALPHA






const GRID_TTC_THRESHOLD: float = 1.5

const GRID_ALPHA_MIN: float = _PostureConstants.POSTURE_GHOST_NEAR_ALPHA
const GRID_ALPHA_MAX: float = 0.95

const GRID_EM_MULT_MIN: float = 0.35
const GRID_EM_MULT_MAX: float = 1.2





static func ghost_base_albedo(paddle_color: Color, is_charge: bool) -> Color:
	if is_charge:
		return Color(
			paddle_color.r * 0.5, 
			paddle_color.g * 0.5, 
			paddle_color.b * 0.5, 
			_PostureConstants.POSTURE_GHOST_ALPHA * 1.5, 
		)
	return Color(
		paddle_color.r, 
		paddle_color.g, 
		paddle_color.b, 
		_PostureConstants.POSTURE_GHOST_ALPHA, 
	)





static func ghost_base_emission(paddle_color: Color, is_charge: bool) -> Color:
	if is_charge:
		return Color(
			paddle_color.r * 0.4 + 0.1, 
			paddle_color.g * 0.4 + 0.1, 
			paddle_color.b * 0.4 + 0.1, 
			1.0, 
		)
	return Color(
		paddle_color.r * 0.7 + 0.2, 
		paddle_color.g * 0.7 + 0.2, 
		paddle_color.b * 0.7 + 0.2, 
		1.0, 
	)



static func ghost_base_em_mult(is_charge: bool) -> float:
	return 0.08 if is_charge else 0.12




static func stage_colors(stage: int) -> Dictionary:
	match stage:
		2:
			return {
				"albedo": STAGE_BLUE_ALBEDO, 
				"emission": STAGE_BLUE_EMISSION, 
				"em_mult": STAGE_BLUE_EM_MULT, 
				"alpha": STAGE_BLUE_ALPHA, 
			}
		1:
			return {
				"albedo": STAGE_PURPLE_ALBEDO, 
				"emission": STAGE_PURPLE_EMISSION, 
				"em_mult": STAGE_PURPLE_EM_MULT, 
				"alpha": STAGE_PURPLE_ALPHA, 
			}
		_:
			return {
				"albedo": STAGE_PINK_ALBEDO, 
				"emission": STAGE_PINK_EMISSION, 
				"em_mult": STAGE_PINK_EM_MULT, 
				"alpha": STAGE_PINK_ALPHA, 
			}






static func compute_stage(
	ttc: float, 
	ball_to_ghost_dist: float, 
	_blue_hold_timer: float, 
	blue_latched: bool, 
) -> int:
	if blue_latched:
		return 2
	if ttc < _PostureConstants.TTC_BLUE or ball_to_ghost_dist < _PostureConstants.BLUE_DIST_FALLBACK:
		return 2
	if ttc < _PostureConstants.TTC_PURPLE:
		return 1
	return 0





static func green_fading(
	fade_t: float, 
	paddle_color: Color, 
) -> Dictionary:
	var t: float = clampf(fade_t, 0.0, 1.0)
	var green_col: = GREEN_ALBEDO
	var base_col: = Color(paddle_color.r, paddle_color.g, paddle_color.b)
	var blended: = green_col.lerp(base_col, t)
	var alpha: float = lerpf(_PostureConstants.POSTURE_GHOST_NEAR_ALPHA, _PostureConstants.POSTURE_GHOST_ALPHA, t)
	var em_green: = GREEN_EMISSION
	var em_base: = Color(paddle_color.r * 0.7 + 0.2, paddle_color.g * 0.7 + 0.2, paddle_color.b * 0.7 + 0.2)
	var em_blended: = em_green.lerp(em_base, t)
	var em_mult: float = lerpf(GREEN_EM_MULT * 0.6, BASE_EM_MULT, t)
	return {
		"albedo": Color(blended.r, blended.g, blended.b, alpha), 
		"emission": em_blended, 
		"em_mult": em_mult, 
	}





static func proximity_color(
	near_t: float, 
	is_active: bool, 
	paddle_color: Color, 
) -> Dictionary:
	var alpha: float
	var em_mult: float
	if near_t > 0.0:
		alpha = lerpf(ACTIVE_ALPHA, _PostureConstants.POSTURE_GHOST_NEAR_ALPHA, near_t)
		em_mult = lerpf(NEAR_EM_MULT_MIN, _PostureConstants.POSTURE_GHOST_NEAR_EMISSION, near_t)
	elif is_active:
		alpha = ACTIVE_ALPHA
		em_mult = NEAR_EM_MULT_MIN
	else:
		alpha = BASE_ALPHA
		em_mult = BASE_EM_MULT
	return {
		"albedo": Color(paddle_color.r, paddle_color.g, paddle_color.b, alpha), 
		"emission": Color(paddle_color.r * 0.7 + 0.2, paddle_color.g * 0.7 + 0.2, paddle_color.b * 0.7 + 0.2), 
		"em_mult": em_mult, 
	}




static func hit_flash(hit_t: float) -> Dictionary:
	var t: float = clampf(hit_t, 0.0, 1.0)
	return {
		"albedo": Color(HIT_ALBEDO.r, HIT_ALBEDO.g, HIT_ALBEDO.b, lerpf(HIT_ALPHA_MIN, HIT_ALPHA_MAX, t)), 
		"emission": HIT_EMISSION, 
		"em_mult": lerpf(HIT_EM_MULT_MIN, HIT_EM_MULT_MAX, t), 
	}






static func grid_override(
	g_ttc: float, 
	tier_color: Color, 
):
	if g_ttc >= GRID_TTC_THRESHOLD:
		return null
	var urgency: float = clampf(1.0 - g_ttc / 1.0, 0.0, 1.0)
	var alpha: float = lerpf(GRID_ALPHA_MIN, GRID_ALPHA_MAX, urgency)
	var em_mult: float = lerpf(GRID_EM_MULT_MIN, GRID_EM_MULT_MAX, urgency)
	return {
		"albedo": Color(tier_color.r, tier_color.g, tier_color.b, alpha), 
		"emission": Color(tier_color.r, tier_color.g, tier_color.b, 1.0), 
		"em_mult": em_mult, 
	}



static func apply(
	material: StandardMaterial3D, 
	color_dict: Dictionary, 
	emit_enabled: bool = true, 
	unshaded: bool = true, 
) -> void :
	material.albedo_color = color_dict.get("albedo", Color.WHITE)
	material.emission = color_dict.get("emission", Color.BLACK)
	material.emission_enabled = emit_enabled
	if color_dict.has("em_mult"):
		material.emission_energy_multiplier = color_dict["em_mult"]
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
