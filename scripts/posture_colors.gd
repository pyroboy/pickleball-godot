class_name PostureColors
extends RefCounted

## Extracted color math and blend logic for posture ghosts.
## Phase 4: consolidated from player_paddle_posture.gd update_posture_ghosts()
## and create_posture_ghosts().
##
## Responsible for all ghost paddle color / emission / alpha calculations:
##   - Base ghost color derived from paddle_color
##   - Charge-posture darkening
##   - Stage-driven colors (PINK / PURPLE / BLUE) via TTC thresholds
##   - Proximity near/far alpha + emission ramp
##   - Green-lit trajectory feedback + fade-out lerp
##   - Hit-flash orange burst
##   - Optional TTC-tiered awareness-grid override

## ── Stage colors (committed via TTC thresholds) ────────────────────────────
## Stage 0 — PINK: ball far, no commit yet.
const STAGE_PINK_ALBEDO:       Color = Color(1.0, 0.3, 0.7)
const STAGE_PINK_EMISSION:     Color = Color(0.95, 0.2, 0.6)
const STAGE_PINK_EM_MULT:      float = 0.5
const STAGE_PINK_ALPHA:        float = PostureConstants.POSTURE_GHOST_ACTIVE_ALPHA

## Stage 1 — PURPLE: ball approaching, TTC < TTC_PURPLE.
const STAGE_PURPLE_ALBEDO:     Color = Color(0.6, 0.1, 1.0)
const STAGE_PURPLE_EMISSION:   Color = Color(0.5, 0.05, 0.95)
const STAGE_PURPLE_EM_MULT:    float = PostureConstants.POSTURE_GHOST_NEAR_EMISSION
const STAGE_PURPLE_ALPHA:      float = PostureConstants.POSTURE_GHOST_NEAR_ALPHA

## Stage 2 — BLUE: committed, TTC < TTC_BLUE or within BLUE_DIST_FALLBACK.
const STAGE_BLUE_ALBEDO:       Color = Color(0.15, 0.5, 1.0)
const STAGE_BLUE_EMISSION:     Color = Color(0.1, 0.4, 1.0)
const STAGE_BLUE_EM_MULT:      float = PostureConstants.POSTURE_GHOST_NEAR_EMISSION * 1.4
const STAGE_BLUE_ALPHA:        float = 0.75

## ── Green-lit (ghost near trajectory) ───────────────────────────────────────
const GREEN_ALBEDO:            Color = Color(0.1, 1.0, 0.2)
const GREEN_EMISSION:          Color = Color(0.0, 1.0, 0.1)
const GREEN_EM_MULT:           float = PostureConstants.POSTURE_GHOST_NEAR_EMISSION

## ── Hit flash ────────────────────────────────────────────────────────────────
const HIT_ALBEDO:              Color = Color(1.0, 0.45, 0.0)
const HIT_EMISSION:            Color = Color(1.0, 0.3, 0.0)
const HIT_EM_MULT_MIN:         float = 0.1
const HIT_EM_MULT_MAX:         float = 3.0
const HIT_ALPHA_MIN:           float = PostureConstants.POSTURE_GHOST_ALPHA
const HIT_ALPHA_MAX:           float = 0.85

## ── Proximity ramp defaults (non-green, non-stage, non-hit) ─────────────────
const NEAR_EM_MULT_MIN:        float = 0.24
const NEAR_EM_MULT_MAX:        float = PostureConstants.POSTURE_GHOST_NEAR_EMISSION  # 1.8
const BASE_EM_MULT:            float = 0.12
const BASE_ALPHA:              float = PostureConstants.POSTURE_GHOST_ALPHA            # 0.12
const ACTIVE_ALPHA:            float = PostureConstants.POSTURE_GHOST_ACTIVE_ALPHA    # 0.3

## ── Awareness-grid TTC-tiered override ───────────────────────────────────────
## When an awareness grid is present and ball is incoming, ghost colors can be
## overridden by a time-to-contact color tier. This lets the volumetric grid
## drive border coloring in addition to the stage logic above.
## Threshold TTC below which the override activates.
const GRID_TTC_THRESHOLD:      float = 1.5
## Alpha range for grid override (0.55 → 0.95 as TTC shrinks).
const GRID_ALPHA_MIN:          float = PostureConstants.POSTURE_GHOST_NEAR_ALPHA
const GRID_ALPHA_MAX:          float = 0.95
## Emission multiplier range for grid override.
const GRID_EM_MULT_MIN:        float = 0.35
const GRID_EM_MULT_MAX:        float = 1.2


## Compute the base ghost material albedo color for a given posture.
## Charge postures render darker / more opaque; all others use paddle_color
## at standard ghost alpha.
static func ghost_base_albedo(paddle_color: Color, is_charge: bool) -> Color:
	if is_charge:
		return Color(
			paddle_color.r * 0.5,
			paddle_color.g * 0.5,
			paddle_color.b * 0.5,
			PostureConstants.POSTURE_GHOST_ALPHA * 1.5,
		)
	return Color(
		paddle_color.r,
		paddle_color.g,
		paddle_color.b,
		PostureConstants.POSTURE_GHOST_ALPHA,
	)


## Compute the base ghost material emission color for a given posture.
## Charge postures have a dimmer, warmer emission; standard postures are
## brighter with a +0.2 RGB lift.
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


## Compute base emission energy multiplier for a charge vs. standard ghost.
static func ghost_base_em_mult(is_charge: bool) -> float:
	return 0.08 if is_charge else 0.12


## Return stage color triplet (albedo, emission, em_mult, alpha) for the given
## committed incoming stage (0 = PINK, 1 = PURPLE, 2 = BLUE).
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


## Compute stage index from time-to-contact and distance metrics.
## Returns 2 (BLUE) if TTC < TTC_BLUE or ball within BLUE_DIST_FALLBACK,
##         1 (PURPLE) if TTC < TTC_PURPLE,
##         0 (PINK) otherwise.
static func compute_stage(
	ttc: float,
	ball_to_ghost_dist: float,
	blue_hold_timer: float,
	blue_latched: bool,
) -> int:
	if blue_latched:
		return 2
	if ttc < PostureConstants.TTC_BLUE or ball_to_ghost_dist < PostureConstants.BLUE_DIST_FALLBACK:
		return 2
	if ttc < PostureConstants.TTC_PURPLE:
		return 1
	return 0


## Compute the ghost color when it is near the ball trajectory (green-lit).
## Returns a lerped pair (albedo, emission) that fades from green toward the
## base ghost color over fade_t (0 = just expired, 1.0 = fully base).
static func green_fading(
	fade_t: float,
	paddle_color: Color,
) -> Dictionary:
	var t: float = clampf(fade_t, 0.0, 1.0)
	var green_col := GREEN_ALBEDO  # use as base for lerp
	var base_col := Color(paddle_color.r, paddle_color.g, paddle_color.b)
	var blended := green_col.lerp(base_col, t)
	var alpha: float = lerpf(PostureConstants.POSTURE_GHOST_NEAR_ALPHA, PostureConstants.POSTURE_GHOST_ALPHA, t)
	var em_green := GREEN_EMISSION
	var em_base := Color(paddle_color.r * 0.7 + 0.2, paddle_color.g * 0.7 + 0.2, paddle_color.b * 0.7 + 0.2)
	var em_blended := em_green.lerp(em_base, t)
	var em_mult: float = lerpf(GREEN_EM_MULT * 0.6, BASE_EM_MULT, t)
	return {
		"albedo": Color(blended.r, blended.g, blended.b, alpha),
		"emission": em_blended,
		"em_mult": em_mult,
	}


## Compute proximity-based alpha and emission multiplier for a ghost that is
## near the ball but not green-lit or in a commit stage.
## near_t: 0 = at NEAR_RADIUS edge, 1 = at ball position.
static func proximity_color(
	near_t: float,
	is_active: bool,
	paddle_color: Color,
) -> Dictionary:
	var alpha: float
	var em_mult: float
	if near_t > 0.0:
		alpha = lerpf(ACTIVE_ALPHA, PostureConstants.POSTURE_GHOST_NEAR_ALPHA, near_t)
		em_mult = lerpf(NEAR_EM_MULT_MIN, PostureConstants.POSTURE_GHOST_NEAR_EMISSION, near_t)
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


## Compute hit-flash color for a ghost matching the current hit posture.
## hit_t: 0 = just started, 1.0 = end of flash duration.
static func hit_flash(hit_t: float) -> Dictionary:
	var t: float = clampf(hit_t, 0.0, 1.0)
	return {
		"albedo": Color(HIT_ALBEDO.r, HIT_ALBEDO.g, HIT_ALBEDO.b, lerpf(HIT_ALPHA_MIN, HIT_ALPHA_MAX, t)),
		"emission": HIT_EMISSION,
		"em_mult": lerpf(HIT_EM_MULT_MIN, HIT_EM_MULT_MAX, t),
	}


## Compute awareness-grid TTC-tiered color override.
## Returns null if TTC >= GRID_TTC_THRESHOLD or grid not available,
## otherwise returns a color dict with alpha and em_mult based on urgency.
## tier_color: Color from awareness_grid._get_time_color(g_ttc).
static func grid_override(
	g_ttc: float,
	tier_color: Color,
) -> Dictionary:
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


## Apply a completed color dict to a StandardMaterial3D.
static func apply(
	material: StandardMaterial3D,
	color_dict: Dictionary,
	emit_enabled: bool = true,
	unshaded: bool = true,
) -> void:
	material.albedo_color = color_dict.get("albedo", Color.WHITE)
	material.emission = color_dict.get("emission", Color.BLACK)
	material.emission_enabled = emit_enabled
	if color_dict.has("em_mult"):
		material.emission_energy_multiplier = color_dict["em_mult"]
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
