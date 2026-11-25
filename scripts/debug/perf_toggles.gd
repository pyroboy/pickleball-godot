class_name PerfToggles
extends RefCounted
## Hidden switches for docs/PERFORMANCE_PLAN.md steps ("one build, several switches").
## Each optimisation reads its own static var on the hot path (no lookups per tick).
## true = the new, cheaper way; false = the old way, kept for A/B on the phone.
## Settings (developer section) writes them via set_toggle(); PerfMonitor logs active() into perf.jsonl.

static var single_physics_step: bool = true   # 0b(a): max_physics_steps_per_frame 2 -> 1
static var display_paced_30: bool = true      # 0b(b): 30 fps cap paced to the display refresh
static var human_plan_once: bool = true       # 1: human seat plans contact once per flight change
static var touch_on_change: bool = true       # 1: touch input works only when a touch changes
static var contact_idle_skip: bool = true     # 2: no contact / surface checks with no ball in play
static var contact_lean: bool = true          # 1b: contact authority / body snapshot reuse per-tick lookups
static var card_redraw_on_change: bool = true # 5: card parts redraw only when their pose changed
static var ai_plan_once: bool = true          # 5: AI plans once per ball
static var crowd_offscreen_skip: bool = true  # 5: crowd figures off screen skip their steps
static var material_prewarm: bool = true      # 5: match materials drawn once at load (no mid-rally shader compile)
static var env_bake_cache: bool = true        # 7: world background / shadow-mask bakes reused (title -> match)
static var pose_math_cache: bool = true       # 3: per-pose results reused (body-offset cap, drive swing keys); same values
static var swing_restore_light: bool = true   # 3: a follow-through restores body + paddle only; legs / arms solve once on the new pose
static var hand_turn_closed_form: bool = true # 3: 720 deg/s hand-turn limit from one blend, not a 6-step search
static var contact_sweep_share: bool = true   # 1b: per-tick contact snapshot keeps the pose object instead of copying it
static var nvz_once_per_tick: bool = true     # 1b: kitchen-feet state scanned once a tick (was 2-3 scans of the same rig)
static var grip_fit_once: bool = true         # 3: AI contact grip fitted once per plan, not every tick of the last 0.65 s
static var shot_solve_early_exit: bool = true # 3: drop-shot solver stops at 0.2 mm (the aimed solver's tolerance)
static var shot_presolve: bool = true         # 8 / worst tick: AI shot solved a few ticks before contact; the hit tick re-solves at that flight time only
static var native_math: bool = true           # 8: C++ versions of hot maths (ball flight steps, shot launch fitting) when the native library is in the build
static var card_tick_build: bool = true       # 5: player cards built once per physics tick; the shader blends between the last two ticks each frame
static var card_build_off_tick: bool = true   # 5: the per-tick card build waits for the frame after the tick's (the tick's own frame is the heaviest); that one frame continues the last tick's motion
static var ready_restore_skip: bool = true    # 3: a waiting AI's pose restore is skipped once the hand-turn limiter is done (0.35 s), not only when settled (0.85 s)
static var held_curve_prewarm: bool = true    # 1: your held-HIT curves built ahead while no ball is coming, not mid-rally on first use
static var simple_hand_shape: bool = true     # 3: the hand the ball can hit is one palm box (12 triangles), not the skinned 702-triangle hand with fingers; set when a match is built
static var simple_hands: bool = true          # 3: hands as posed (pixel cards draw them): no grip-roll fit, no wrist-limit / free-hand solve in rallies, wrist limits never block a hit

const NAMES: Array[String] = [
	"single_physics_step", "display_paced_30", "human_plan_once", "touch_on_change",
	"contact_idle_skip", "contact_lean", "card_redraw_on_change", "ai_plan_once", "crowd_offscreen_skip",
	"material_prewarm", "env_bake_cache", "pose_math_cache", "swing_restore_light", "hand_turn_closed_form",
	"contact_sweep_share", "nvz_once_per_tick", "grip_fit_once", "shot_solve_early_exit", "simple_hands", "shot_presolve", "simple_hand_shape", "held_curve_prewarm", "native_math", "card_tick_build", "card_build_off_tick", "ready_restore_skip",
]


static func set_toggle(toggle_name: String, value: bool) -> void:
	match toggle_name:
		"single_physics_step": single_physics_step = value
		"display_paced_30": display_paced_30 = value
		"human_plan_once": human_plan_once = value
		"touch_on_change": touch_on_change = value
		"contact_idle_skip": contact_idle_skip = value
		"contact_lean": contact_lean = value
		"card_redraw_on_change": card_redraw_on_change = value
		"ai_plan_once": ai_plan_once = value
		"crowd_offscreen_skip": crowd_offscreen_skip = value
		"material_prewarm": material_prewarm = value
		"env_bake_cache": env_bake_cache = value
		"pose_math_cache": pose_math_cache = value
		"swing_restore_light": swing_restore_light = value
		"hand_turn_closed_form": hand_turn_closed_form = value
		"contact_sweep_share": contact_sweep_share = value
		"nvz_once_per_tick": nvz_once_per_tick = value
		"grip_fit_once": grip_fit_once = value
		"shot_solve_early_exit": shot_solve_early_exit = value
		"simple_hands": simple_hands = value
		"shot_presolve": shot_presolve = value
		"simple_hand_shape": simple_hand_shape = value
		"held_curve_prewarm": held_curve_prewarm = value
		"card_tick_build": card_tick_build = value
		"card_build_off_tick": card_build_off_tick = value
		"ready_restore_skip": ready_restore_skip = value
		"native_math": native_math = value


static func get_toggle(toggle_name: String) -> bool:
	match toggle_name:
		"single_physics_step": return single_physics_step
		"display_paced_30": return display_paced_30
		"human_plan_once": return human_plan_once
		"touch_on_change": return touch_on_change
		"contact_idle_skip": return contact_idle_skip
		"contact_lean": return contact_lean
		"card_redraw_on_change": return card_redraw_on_change
		"ai_plan_once": return ai_plan_once
		"crowd_offscreen_skip": return crowd_offscreen_skip
		"material_prewarm": return material_prewarm
		"env_bake_cache": return env_bake_cache
		"pose_math_cache": return pose_math_cache
		"swing_restore_light": return swing_restore_light
		"hand_turn_closed_form": return hand_turn_closed_form
		"contact_sweep_share": return contact_sweep_share
		"nvz_once_per_tick": return nvz_once_per_tick
		"grip_fit_once": return grip_fit_once
		"shot_solve_early_exit": return shot_solve_early_exit
		"simple_hands": return simple_hands
		"shot_presolve": return shot_presolve
		"simple_hand_shape": return simple_hand_shape
		"held_curve_prewarm": return held_curve_prewarm
		"card_tick_build": return card_tick_build
		"card_build_off_tick": return card_build_off_tick
		"ready_restore_skip": return ready_restore_skip
		"native_math": return native_math
	return false


## One bit per NAMES entry: cheap change check (PerfMonitor compares it once a second).
static func mask() -> int:
	var m: int = 0
	for i in NAMES.size():
		if get_toggle(NAMES[i]): m |= 1 << i
	return m


## {name: bool} for perf.jsonl.
static func active() -> Dictionary:
	var out: Dictionary = {}
	for n in NAMES:
		out[n] = get_toggle(n)
	return out
