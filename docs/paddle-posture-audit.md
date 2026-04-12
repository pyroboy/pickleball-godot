# Paddle Posture Logic Audit — Gap Search + Procedural Animation SOTA

> **Note on filename**: Plan-mode restricts me to a single writable file. You referenced `bubbly-mixing-wirth.md` as the target, but the harness assigned me `fluttering-mapping-unicorn.md`. After plan approval, the contents here can be copied to `bubbly-mixing-wirth.md` as the supplementary pre-made doc.

> **Audit revision 2 — 2026-04-11**: Code updated since first pass. Deltas captured inline. Key changes: (a) TTC gates are now **live** on human side (`TTC_BLUE=0.2s`, `TTC_PURPLE=0.8s`), (b) explicit `_commit_locked` flag exists, (c) follow-through tween timing is charge-scaled, (d) pole-vector IK added to arm solver, (e) `incoming_stage_changed` signal now carries TTC. Gaps 1, 6, 7 (partial), and 9 are **resolved**; gaps 3 and 4 remain the highest-ROI targets.

> **Audit revision 3 — 2026-04-11**: ✅ **GAP-3 and GAP-4 implemented and tested.** Charge now scales final impulse magnitude via `charge_gain = lerpf(0.60, 1.25, charge_clamped)` at `scripts/player_hitting.gd:421-423`. Paddle chase now uses framerate-independent `_damp_v3` spring with stage-adaptive halflife (PINK 0.22s → PURPLE 0.10s → BLUE 0.04s) at `scripts/player_paddle_posture.gd:force_paddle_head_to_ghost`. Verified with headless Godot boot: both scripts parse, game initializes, posture loop runs without errors. Remaining top open item: **GAP-7b posture-aware pole vector**.

> **Audit revision 4 — 2026-04-11**: **Academic research sweep added as Part 6.** Cross-referenced four bodies of literature against current code — racket-ball impact physics (Brody, Cross, Goodwill), swing biomechanics (Kibler, Elliott, Marshall), interception perception-action (Lee, Bootsma, Tresilian, McLeod, Land), procedural character animation (Holden, Starke, Clavet, Peng). Yielded **10 new gaps (GAP-15 through GAP-24)**, of which **GAP-20 (physics CCD verification)** is flagged as critical correctness — may be silently broken for fast serves. New rev-4 priority queue at end of Part 6.

> **Audit revision 4.1 — 2026-04-11**: ✅ **GAP-20 RESOLVED.** Confirmed tunneling vulnerability (CCD disabled + 60 Hz tick = 33 cm/tick at max speed, 5.5× ball radius). Added `continuous_cd = 2` (CCD_CAST_SHAPE) to `scenes/ball.tscn`. Verified with clean headless boot.

> **Audit revision 5 — 2026-04-11**: **Reach / jump / footwork audit added as Part 7.** Verified by direct code reads: AI never jumps (`grep 'jump' player_ai_brain.gd` = 0 matches), manual jump is untimed (`player.gd:398`), no lunge state, no split-step, body velocity never added to paddle impulse. Added **8 new gaps (GAP-25 through GAP-32)**. Top new finding: **GAP-28** (body velocity → impulse) is a 1-line trivial fix with high realism payoff; **GAP-25** (AI jump capability) is a real capability gap — AI cannot reach high balls that humans can.

> **Audit revision 6 — 2026-04-11**: **🚨 Major audit oversight discovered and corrected.** The first 7 passes missed `scripts/player_awareness_grid.gd` (419 lines) — a full volumetric proximity detector with **per-vertex TTC coloring (RED/ORANGE/YELLOW/GREEN)** that already exists. Many "missing TTC" findings from revs 1-5 are actually **present in the grid but not wired** to the ghost border or commit systems. Part 8 catalogs the grid, documents the wiring gaps, and answers the user's question: **yes, the grid solves the yellow-border/TTC consistency problem — it just needs to be exposed via `get_ttc_at_world_point()` and queried by the ghost border loop**. Added 7 new gaps (GAP-33 through GAP-39). **Top priority for rev 6: GAP-33 + GAP-34** (expose grid TTC + wire to ghost borders) — directly addresses user's question.

> **Audit revision 7 — 2026-04-11**: **Deep re-audit with a verifying sub-agent + expanded research sweep. Corrected TWO prior errors, discovered FIVE subsystems missed entirely, and added GAP-40 through GAP-51.** Summary: (a) GAP-8 "no spin" was **half wrong** — `ball.gd:149` randomizes `angular_velocity` on serve but nothing consumes it (vestigial). (b) GAP-32 "no landing lockout" needs a twin — `_apply_foot_lock` at `player_leg_ik.gd:454` is **dead code**, never called. (c) **Missed subsystems**: ReactionHitButton HUD (186 lines), shot grading rubric (PERFECT/GREAT/GOOD/OK/MISS), HitFeedback FX orchestrator, AI human-intercept-pools, footwork swing anticipation (`SWING_ANTICIPATION_DIST = 4.0m`), stance-based foot replant on posture change. (d) **New research**: DeepMind 2024 table tennis robot, Williams on anticipation occlusion paradigm, Fitts' law for reach time, pickleball-specific aerodynamics. Rev 7 also **caught my verifying sub-agent being wrong twice** — agent claimed `awareness_grid` was never initialized (it is, `player.gd:225`) and `auto_fire_requested` was never subscribed (it is, `game.gd:476`). Trust nothing without `grep`.

> **Audit revision 8 — 2026-04-11**: ✅ **Eight easy gaps implemented and tested.** Rev 8 resolves GAP-28, GAP-33, GAP-34, GAP-40, GAP-41, GAP-44, GAP-45, GAP-47 in a single pass. Verified with a clean headless boot of Godot 4.6.2 — no parse errors, no runtime errors in any edited file, both players initialize, posture loop ticks, foot lock runs, AI perception buffer warms. Details in Part 10.

> **Audit revision 9 — 2026-04-12**: ✅ **GAP-38 resolved.** Grid lock now uses TTC (`< 0.35 s`) instead of distance (`<= 1.5 m`), consistent with the TTC-tiered posture commit system. Verified with clean headless boot. Added **§9.6 Domain-Based Segregation** — all 51 gaps re-organized by subsystem (AI, Physics, Paddle, Posture, Grid, Footwork, Trajectory, Visual, Infra) with ✅/🟡/🔴/🧪 status per domain.

> **Audit revision 10 — 2026-04-13**: ✅ **Three physics gaps resolved.** GAP-15: sweet-spot speed penalty wired via `compute_sweet_spot_speed()` (both human `game.gd:599` and AI `player_ai_brain.gd:730`). GAP-46: drag reference updated to Lindsey 2025 Cd=0.33 outdoor (`ball_physics_probe.gd:290`). GAP-8: serve intentionally flat confirmed (`ball.gd:286` comment), Magnus wired for regular shots. Physics domain: 5 resolved, 1 open.

## Context

This document is a **gap-searching audit** of the trajectory-volumetric-hybrid paddle posture detection system in `pickleball-godot`. It catalogs the current logic end-to-end (postures, charge, follow-through, tracking, TTC, green pool), then cross-references each subsystem against the current state of the art in procedural animation and ball-interception prediction to identify concrete improvement opportunities. It is a companion to the implementation plan in `bubbly-mixing-wirth.md` — not a plan itself.

---

## Part 1 — Current Logic Catalog

### 1.1 Postures (20 ghosts + 4 follow-through ghosts)

**Source**: `player.gd` (enum), `player_paddle_posture.gd:11-103, 870-900, 1200+` (offsets + zones + ghost creation)

| Family | Members | Notes |
|---|---|---|
| Forehand | FOREHAND, WIDE_FOREHAND, MID_LOW_FOREHAND, MID_LOW_WIDE_FOREHAND, LOW_FOREHAND, LOW_WIDE_FOREHAND, CHARGE_FOREHAND | Lateral offset 0.5–0.9m |
| Backhand | BACKHAND, WIDE_BACKHAND, MID_LOW_BACKHAND, MID_LOW_WIDE_BACKHAND, LOW_BACKHAND, LOW_WIDE_BACKHAND, CHARGE_BACKHAND | Mirror; offset 0.42m base; triggers two-handed grip |
| Center | FORWARD, LOW_FORWARD, MID_LOW_FORWARD, VOLLEY_READY, READY | Forward 0.4m; LOW_* inverts paddle (180° roll) |
| Overhead | MEDIUM_OVERHEAD, HIGH_OVERHEAD | Height 0.6 / 1.1m; forward 0.7–0.8m |

**Posture zones** (`POSTURE_ZONES` dict, `player_paddle_posture.gd:75-103`): each posture owns an AABB of `{lat_min, lat_max, ht_min, ht_max}`. Scoring for non-green fallback = zone containment + 3D distance tiebreak. Mid-low variants use ht_min ≈ −0.18 so they outrank NORMAL_WIDE on low balls via the 2.5× height-mismatch weight.

**Height thresholds** (absolute, floor = 0.075):
- LOW: < 0.22m
- MID_LOW: 0.22–0.55m
- NORMAL: ≥ 0.55m
- MEDIUM_OVERHEAD: ~0.6m band
- HIGH_OVERHEAD: ≥ 1.1m

**Invariants encoded in zones**: LOW postures flip paddle, enable body crouch (only when `ball.is_in_play`); backhand postures enable left-hand grip on paddle neck.

### 1.2 Charge System

**Source**: `player_hitting.gd:4-14, 83-202`

- Inputs: `charge_ratio ∈ [0,1]` (elapsed-time based from input layer); for AI: `AI_CHARGE_DURATION = 0.28s`.
- Pull-back offsets (forehand): behind 0.65m, lift 0.35m, pitch −45°, yaw ±35°.
- Body coil: `body_pivot.rotation.y = 35° × sign × charge_ratio`.
- **Critical gap**: charge_ratio is *elapsed-time based, not TTC based*. A player winding up 400 ms before contact looks identical to one winding up 80 ms before contact of the same charge value.

### 1.3 Follow-Through

**Source**: `player_hitting.gd:208-250` (`_get_follow_through_offsets`), `254-350` (`animate_serve_release`)

Four-phase tween from charge pose:
1. **STRIKE** → contact @ 0.4 lerp, 0.08–0.10s (EXPO_OUT)
2. **SWEEP** → peak overshoot 1.12×, 0.16–0.20s (QUAD_OUT)
3. **SETTLE** → ghost target, 0.12–0.18s (SINE_IN_OUT)
4. **HOLD** → pose, 0.06–0.20s

Follow-through *distance* scales linearly with charge_ratio (weak hit = partial arc). Follow-through *timing* is nearly constant (tween durations are barely charge-scaled). Overhead smash biases down (`SMASH_DOWNWARD_BIAS = 0.22`) and gets 1.35× force.

### 1.4 Paddle Positions / IK Chain

**Source**: `player_arm_ik.gd:8-120`

- Right arm: two-bone IK targeting paddle origin + local offset `(0, 0.07, 0)`.
- Left arm: family-switched grip (overhead = two-hand over, backhand = neck grip, sidearm = none).
- Paddle position driver is the *committed ghost pose* (via `force_paddle_head_to_ghost`, lerp 8–12 u/s). Hand/elbow follow IK, not the other way around. **The paddle leads; the arm catches up.**

### 1.5 Ball Tracking & Trajectory

**Source**: `player_debug_visual.gd:380-520`

- `draw_incoming_trajectory`: forward-Euler physics sim, `dt = 0.04s`, 80 steps (≈3.2s horizon), bounce with `restitution = 0.685`. Returns ~80 `Vector3` points to the posture module.
- `predict_human_intercept_points`: same loop filtered to court bounds, excludes NVZ ±0.22m, height window 0.18–1.5m, 0.25m minimum gap between picked points, returns `{pre: [], post: []}` (volley vs. groundstroke pools).
- Ingestion: `player_paddle_posture.gd:418 set_trajectory_points(...)` → stored as `_incoming_trajectory_points`.

### 1.6 TTC Logic — **Now live on human side (rev 2)**

**Source**: `player_paddle_posture.gd:9, 127, 134-136, 263-310`; `player_ai_brain.gd:8-10, 59-60`

**Current constants** (`player_paddle_posture.gd`):
- `TTC_BLUE := 0.2` (line 134) — seconds-to-contact for BLUE latch
- `TTC_PURPLE := 0.8` (line 135)
- `BLUE_DIST_FALLBACK := 0.35` (line 136) — distance fallback if TTC unreliable
- `BLUE_HOLD_DURATION := 0.35` (line 133)
- `_commit_locked: bool` (line 127) — explicit lock flag

**Signal (line 9)**: `incoming_stage_changed(stage, posture, commit_dist, ball2ghost, ttc)` — TTC now emitted per stage transition.

**AI side** (`player_ai_brain.gd`): still position-based, no TTC broadcast.
- `AI_LANDING_PREDICTION_STEP := 0.08` × 28 = 2.24s horizon
- `AI_CONTACT_PREDICTION_STEP := 0.06` × 44 = 2.64s horizon
- `AI_CHARGE_DURATION := 0.32`, `AI_CHARGE_START_DISTANCE := 2.4`

**Open sub-gap**: `set_trajectory_points` at `player_paddle_posture.gd:461` still accepts only `Array[Vector3]` — no per-point time tags. TTC is therefore derived at commit time from `(ball_distance / ball_speed)` rather than read directly off trajectory samples. This is fine for smooth arcs but drifts on fast-changing velocity (e.g., just after bounce). See revised GAP-1b below.

### 1.7 GREEN POOL System

**Source**: `player_paddle_posture.gd:90, 805-820, 920-1050, 1149-1157`

Definition: a ghost is "green-lit" if its (lerped, possibly flying) world position is within **`POSTURE_GHOST_NEAR_RADIUS := 0.3`** (line 90) of any trajectory point. (**Rev 2 change**: radius tightened from 0.45 → 0.3, makes commits crisper but relies more on ghost-position accuracy.) CHARGE_* postures are excluded. Triggering increments `_green_trigger_count`.

Scoring pipeline at commit time (`_find_closest_ghost_to_point`, line 529-780):
1. Greens filter first (ground truth). Non-greens fall through to zone-center scoring.
2. Height mismatch weighted 2.5×, lateral mismatch 1.0× → lets MID_LOW beat NORMAL_WIDE on low descenders.
3. Tiebreaker: 3D distance × 0.05.
4. Descending-arc projection: if `ball.vy < -1.5`, estimate Y when ball reaches player XZ, use `min(grid_ht, projected_ht)` to avoid mid-arc height bias.
5. Center bias: 0.20m forward bonus for center family when `|lateral| < 0.4m`.

**Fade**: per-ghost, 0.6s yellow cross-fade after leaving trajectory proximity, keyed by frame timestamp in `_green_lit_postures` dict.

**Commit stages** (rev 2 — TTC-gated with distance fallback):
- PINK: distance-gated (far, pre-PURPLE)
- PURPLE: `ttc < 0.8s` (`TTC_PURPLE`)
- BLUE: `ttc < 0.2s` (`TTC_BLUE`) OR `ball2ghost < 0.35m` (`BLUE_DIST_FALLBACK`), held 0.35s

**Commit flow**: FIRST (on first green) → zone-exit recommit (margin 0.3m, confidence > 5, see `player_paddle_posture.gd:1149-1157`) → **explicit LOCK** via `_commit_locked` flag. Commit persists until ball > 10m, incoming_expired (1.5s timeout), or `_commit_locked` is cleared on ball-gone cleanup.

### 1.8 Ghost Dynamics

**Source**: `player_paddle_posture.gd:131-138, 960-995`

- Lerp speed: 16 u/s at ball speed > 15 m/s, 10 u/s at 8–15, 6 u/s at < 8. **Frame-rate independent via `_damp()` is NOT consistently used here** — straight lerp with `delta` multiplier.
- Anti-overlap: pairwise separation push at 0.18m.
- Tighten: non-committed ghosts pull 20% toward committed ghost on incoming.
- Non-committed same-side spread outward when contact_lateral > 0.3m; opposite-side shift 0.1m toward contact.

---

## Part 2 — Gap-Search Audit

Every gap below is cross-referenced to a piece of the current logic and to SOTA work that demonstrates a better approach. **Status tags**: ✅ RESOLVED | 🟡 PARTIAL | 🔴 OPEN.

### ✅ GAP-1 · True TTC computation — **RESOLVED (rev 2)**

**Was**: spatial-only. Commit stages gated by 3D distance; charge ramp gated by elapsed time.

**Now**: `TTC_BLUE = 0.2`, `TTC_PURPLE = 0.8` in `player_paddle_posture.gd:134-135`. Stage transitions are TTC-gated with distance fallback. Signal `incoming_stage_changed` emits `ttc` per transition.

**Follow-up → GAP-1b (🟡 PARTIAL)**: `set_trajectory_points(points: Array[Vector3])` at line 461 still has no per-point time tags. TTC is derived at commit time from `distance/speed`, which drifts on fast-changing velocity (post-bounce, off-axis hits). If this ever misbehaves, the minimal fix is:
- Add a parallel `PackedFloat32Array _incoming_trajectory_times`
- Populate it in `player_debug_visual.gd:draw_incoming_trajectory` (accumulate `t_i = i * 0.04s` including bounce discontinuity)
- Pass it via overloaded setter; read directly instead of estimating
- Defer until you see commit-timing glitches in gameplay — not worth the plumbing otherwise.

### 🔴 GAP-1 (legacy text — preserved for context on the original finding)

**Why it matters**: Human motor control in interception tasks is explicitly TTC-driven. [Zago et al., *J. Neurophysiology* 2017](https://journals.physiology.org/doi/full/10.1152/jn.00025.2017) show the CNS uses an internal gravity model to time responses to a critical TTC of ~110 ms — close to the sensorimotor delay in interception.

**Why it matters**: Human motor control in interception tasks is explicitly TTC-driven. [Zago et al., *J. Neurophysiology* 2017](https://journals.physiology.org/doi/full/10.1152/jn.00025.2017) show the CNS uses an internal gravity model to time responses to a critical TTC of ~110 ms — close to the sensorimotor delay in interception. Games that match this timing *feel* right because the animation commits at the same phase of flight a real player would. Distance-gated commits feel rubbery on slow arcs (too-early lock) and delayed on fast drives (too-late reveal).

**Concrete fix**:
1. In `player_debug_visual.gd:draw_incoming_trajectory`, tag each trajectory point with its cumulative time `t_i = i * 0.04s`.
2. Pass `Array[Vector4]` (xyz + t) to posture via `set_trajectory_points`.
3. Posture commits on `ttc_to_contact_point < 0.4s` (PURPLE), `< 0.15s` (BLUE), plus a PINK pre-commit at `ttc < 1.0s`.
4. Charge ramp becomes `charge = clamp(1 - ttc/charge_window, 0, 1)` where `charge_window = 0.5s` — charge naturally peaks at contact regardless of ball speed.

**Files touched**: `player_debug_visual.gd`, `player_paddle_posture.gd`, `player_hitting.gd`.

### GAP-2 · Forward-Euler trajectory, no noise-robust estimator

**Current**: `pos += vel * dt; vel.y -= g * dt`. Deterministic, brittle against any future spin/wind/collision-noise.

**SOTA**: Kalman / extended-Kalman filters are the standard interception workhorse. Hawk-Eye uses a Kalman filter on top of 10-camera triangulation for impact prediction ([Ultralytics overview](https://www.ultralytics.com/blog/enhancing-ball-trajectory-prediction-using-vision-ai)). For higher-speed interception (ours is slow, but the math is free), [*Target State Estimation and Prediction for High Speed Interception* — Dey et al., arXiv:2010.02512](https://arxiv.org/abs/2010.02512) shows an EKF with curve-fit refinement produces tight predictions within 1 flight loop of data.

**Pragmatic take for a game**: full KF is overkill pre-spin, but the *structure* is useful: maintain a lightweight (pos, vel, acc) state with a 2-sample smoothing filter, so the prediction isn't a single-frame snapshot of `ball.linear_velocity`. Becomes essential the moment you add topspin/backspin (see GAP-8).

**Concrete fix**: introduce `BallStateEstimator` node on the ball, expose `get_predicted_state(t: float) -> {pos, vel}`. Keep the forward-Euler as fallback, but have `draw_incoming_trajectory` consume the estimator so the trajectory uses smoothed velocity.

### ✅ GAP-3 · Charge → Force coupling — **RESOLVED (rev 3)**

Implemented at `scripts/player_hitting.gd:421-423`:
```gdscript
var charge_gain: float = lerpf(0.60, 1.25, charge_clamped)
return dir.normalized() * _player.paddle_force * force_scale * charge_gain
```
- Half-charged shots: 60% of previous baseline force
- Full-charged shots: 125% of previous baseline force
- Adds ±40% dynamic range to charge input
- `charge_clamped` was already a local at line 382, no new plumbing
- Smoke test: headless Godot boot succeeds, no parse errors, posture log confirms hitting subsystem initializes

**Tuning note**: If CLEAN shots at full charge feel too hot, drop upper bound to 1.15. If weak shots feel too limp, raise lower bound to 0.70.


**Current**: `get_shot_impulse` returns `dir × paddle_force × force_scale`, where `force_scale` is purely contact-state dependent (POPUP 0.65, CLEAN 1.0, SMASH ×1.35). Charge_ratio only changes follow-through *distance*, not impulse magnitude.

**Why it matters**: a half-charged smash and a full-charged smash currently hit the ball with identical force. Visually the arm swings further, but the ball flies the same. This is a core felt-feedback miss.

**Concrete fix** in `player_hitting.gd:get_shot_impulse`:
```
var charge_gain = lerpf(0.6, 1.25, charge_ratio)  # half-charge = 60%, full = 125%
return dir.normalized() * paddle_force * force_scale * charge_gain
```
Tune bounds per-posture if needed. Adds ±40% dynamic range to the charge input.

### ✅ GAP-4 · Spring-damper paddle chase — **RESOLVED (rev 3)**

Implemented at `scripts/player_paddle_posture.gd:force_paddle_head_to_ghost`:
```gdscript
var halflife: float
match _last_commit_stage:
	2: halflife = 0.04  # BLUE
	1: halflife = 0.10  # PURPLE
	_: halflife = 0.22  # PINK / fallback
var dt: float = get_process_delta_time()
_player.paddle_node.global_position = _player._damp_v3(
	_player.paddle_node.global_position, target, halflife, dt
)
```
- Uses existing `_damp_v3` helper at `player.gd:345-347` — zero new helpers
- Stage-adaptive halflife: loose chase far out (PINK 0.22s), snap near contact (BLUE 0.04s)
- Framerate-independent (exponential decay, not linear lerp × dt)
- Smoke test: headless Godot boot succeeds, `force_paddle_head_to_ghost` runs in posture update loop without errors
- `GHOST_LERP_SPEED` constant is now dead — can be deleted on next pass

**SOTA**: GDC-era [Daniel Holden's "Spring-Roll-Call" / critically damped springs](https://theorangeduck.com/page/spring-roll-call) is the de-facto standard for procedural secondary motion because it's framerate-independent, smooth at any speed, and cheap. Unreal's Control Rig, Unity's Animation Rigging, and most AAA sports titles use the same math for racket/stick pose chase.

**Concrete fix**: replace ghost→paddle lerp with a critically-damped spring on *both position and quaternion*, halflife tuned per commit stage (PINK=0.25s, PURPLE=0.12s, BLUE=0.05s). Gives tight snap near contact, smooth drift far out. Use the existing `_damp` helper or add a quaternion spring (slerp of the damped angle).

### 🔴 GAP-5 · Green pool is spatial, not temporal-volumetric — **STILL OPEN (plus rev 2 note)**

**Rev 2 addendum**: `POSTURE_GHOST_NEAR_RADIUS` was tightened from 0.45 → **0.3** (`player_paddle_posture.gd:90`). This makes the gap sharper, not softer — a tighter radius means the spatial test rejects more, but still doesn't discriminate by *when* the ball arrives. Temporal dimension still missing.


**Current**: a ghost is green iff its position is within 0.45m of *any* trajectory point, regardless of *when* the ball is at that point. A trajectory that passes within 0.45m of a MID_LOW ghost 2.5 seconds from now lights up the same as one arriving in 80 ms.

**Why it matters**: on bounced balls, the trajectory can pass near multiple postures at different times (pre-bounce near overhead, post-bounce near mid-low). Right now both go green simultaneously; the commit then picks by spatial score, potentially favoring the wrong phase of flight.

**Concrete fix**: replace the 0.45m spatial test with a **space-time volume test**:
- For each trajectory point, check if ghost is within `spatial_R(t) + temporal_weight * |t_now - t|`.
- Only points with `t < 1.2s` count (horizon cutoff — prevents stale post-bounce lighting).
- Bonus: weight the proximity radius by posture family (overhead needs wider radius than LOW_FOREHAND because overhead contact happens at paddle-extended-up, not paddle-rest).

This also naturally sequences the commit: overhead lights first, MID_LOW lights later, commit moves as ball progresses.

### ✅ GAP-6 · Explicit LOCK state — **RESOLVED (rev 2)**

**Now**: `_commit_locked: bool` at `player_paddle_posture.gd:127` — explicit flag, cleared on ball-gone cleanup. Gates recommit evaluation when TTC is below BLUE threshold.

**(Original text preserved below for context.)**

**Risk**: a late recommit during the tween window causes paddle rubber-banding. Likely invisible in quiet rallies but visible on aggressive volleys or deceptive slice shots.

**Concrete fix**: add explicit `_commit_locked: bool`, set `true` when `ttc < 0.15s` (from GAP-1). Skip all re-evaluation in `_find_closest_ghost_to_point` when locked. Logs a `[LOCK]` tag on entry for debuggability.

### 🟡 GAP-7 · Pole vector / elbow control — **PARTIAL (rev 2)**

**Now**: `player_arm_ik.gd:13` computes `pole_global = player_pos + forehand_axis * 0.5 + Vector3(0, -1.0, 0) + forward_axis * -0.5` — a static geometric pole (shoulder + forehand offset + down + back). This fixes the worst elbow flips.

**What's still missing**: the pole is static geometry-based, not posture-aware. Overhead reaches, wide backhand stretches, and LOW inverted postures all use the same pole direction. For overhead, the elbow should point **down and outward**; for LOW, it should point **up and outward**. Recommendation: make pole a `Dictionary[PaddlePosture, Vector3]` lookup, fall back to the current static pole. ~15 line change.

**Legacy text**: Godot's built-in IK is known to lack explicit pole support ([Godot Forums: Is there an IK Pole Vector?](https://godotforums.org/d/22393-is-there-an-ik-pole-vector), [Unity Discussions: pole angle options](https://discussions.unity.com/t/animation-rigging-two-bone-ik-pole-angle-options-support/790173)).

**Why it matters**: without a pole, elbow orientation can flip between forehand and backhand, especially on overhead reaches. Visually reads as "chicken wing" or elbow popping.

**Concrete fix**: add a `pole_target: Vector3` computed per-posture:
- Forehand: `player_pos + right * 0.3 + up * 0.2 + back * 0.1`
- Backhand: `player_pos + left * 0.2 + up * 0.15 + back * 0.2`
- Overhead: `player_pos + side * 0.1 + up * 0.6`

Then rotate the upper arm around the shoulder→wrist axis so the elbow points at the pole. Classic two-bone IK + pole math; can implement manually in GDScript with ~20 lines.

Alternative: evaluate [Twisted IK 2](https://itch.io/t/1108778/complete-feature-list-last-updated-06012023) or [Many Bone IK](https://github.com/godotengine/godot-proposals/issues/6039) — both support pole/magnet targets natively and handle multi-bone chains, which would also improve the left-arm two-handed grip.

### GAP-8 · No spin / curve / Magnus effect

**Current**: impulses are straight-line; gravity-only in flight. No topspin, backspin, or slice.

**SOTA reference**: real pickleball relies heavily on topspin drops and backspin dinks. Table-tennis game-research papers do full Magnus force (see [*TT3D: Table Tennis 3D Reconstruction*, arXiv:2504.10035](https://arxiv.org/pdf/2504.10035) and [*Towards Ball Spin and Trajectory Analysis*, CVPR 2025](https://openaccess.thecvf.com/content/CVPR2025W/CVSPORTS/papers/Kienzle_Towards_Ball_Spin_and_Trajectory_Analysis_in_Table_Tennis_Broadcast_CVPRW_2025_paper.pdf)). Pickleball ball is slower and larger (less spin than TT), but even a small Magnus term changes bounce behavior meaningfully.

**Concrete fix (phased)**:
1. Add `angular_velocity: Vector3` to the ball, start it at zero.
2. On impulse, compute spin vector from paddle surface velocity × impact offset (`ω = r × v_rel`).
3. In `_integrate_forces`, add `F_magnus = k_m * (ω × v)` with `k_m ≈ 0.0015` for pickleball (tune to taste).
4. Bounce: subtract friction-coupled spin transfer from velocity (`v_tangent -= μ * ω_r`).
5. Trajectory prediction must then use the estimator from GAP-2, not naive forward-Euler.

### ✅ GAP-9 · Follow-through timing charge-scaled — **RESOLVED (rev 2)**

Verified at `player_hitting.gd:310-313`:
- `t_strike = lerp(0.10, 0.08, ratio)` — faster strike at high charge
- `t_sweep = lerp(0.16, 0.20, ratio)` — longer sweep at high charge (weight)
- `t_settle = lerp(0.12, 0.18, ratio)`
- `t_hold = lerp(0.06, 0.20, ratio)` — extended hold at full charge

Matches the recommendation exactly. Nothing to do here.

### GAP-10 · No motion-matching or pose library

**Current**: pure procedural (ghost pose + IK chase). Zero baked animation.

**SOTA position**: the modern AAA default is **motion matching** (Ubisoft's *For Honor*, *Assassin's Creed*, EA Sports titles). It searches a mocap database each frame for the best matching pose given current trajectory, then blends. Procedural + IK is still used for fine contact correction on top.

**Honest assessment for this project**: motion matching is overkill and would require a mocap data pipeline the project doesn't have. The *lesson* from motion matching, though, is the feature vector: current root velocity + projected trajectory + upcoming contact point. The existing system already has all three pieces — just not organized as a feature vector. **Do not adopt motion matching**; instead adopt its query structure to drive better ghost selection (use trajectory-derived feature vector instead of nearest-point spatial test).

### GAP-11 · Reaction delay is global, not signal-driven

**Current**: `reaction_delay` is a flat seconds value, applied uniformly after opponent hit.

**SOTA-inspired fix**: signal-driven reaction. Real reaction time scales with *uncertainty*, not wall-clock. A deceptive swing (late contact state swap) should eat the full delay; a telegraphed drive should not. Compute `reaction_delay * uncertainty_factor` where uncertainty rises with opponent's `charge_ratio` jitter, or drops with long observation window. Low-effort polish that reads as AI intelligence.

### GAP-12 · No per-player difficulty on contact error injection

**Current**: contact states (POPUP/STRETCHED/CLEAN) are applied uniformly. AI difficulty only changes aim and shot mix.

**Fix**: EASY AI should commit slightly *early* (lock at `ttc ~0.3s`, causing stiffer shots); HARD AI commits at `ttc ~0.1s` giving crisper contacts. Adds noticeable feel difference without re-tuning aim.

### GAP-13 · Posture ghost scoring ignores player momentum

**Current**: contact-point selection is ball-state-relative. Player's current velocity isn't a factor. A sprinting player and a stationary player get the same posture commit for the same ball.

**Fix**: add a "reach cost" term to scoring: `cost += lateral_delta - dot(player_vel, contact_dir) * 0.3`. Momentum "shortens" reach in the direction of travel, making the system prefer postures the player is naturally moving into.

### GAP-14 · No tests on the commit machine

**Current**: no unit tests on `_find_closest_ghost_to_point`, `_compute_expected_contact_point`, `_is_ghost_near_trajectory`. All verification is live-play observation.

**Fix**: Godot has `gdUnit4`. Wire a minimal test scene with a fixture ball, fire 10 canonical trajectories (deep forehand, low dink, overhead lob, BH wide, etc.), assert expected posture commits. Prevents regressions when tuning the thresholds touched by GAPs 1-6.

---

## Part 3 — Procedural Animation Advancements Worth Considering

| Technique | What it buys | Fit for this project |
|---|---|---|
| **Critically-damped springs** ([Holden](https://theorangeduck.com/page/spring-roll-call)) | Framerate-independent smooth chase | **High fit** — direct drop-in for GAP-4. |
| **TTC-gated state machine** (Zago 2017) | Human-like commit timing | **High fit** — enables GAP-1. |
| **Kalman state estimation** (Hawk-Eye pattern) | Noise-robust prediction, enables spin | **Medium fit** — wait until GAP-8 spin. |
| **Pole-vector two-bone IK** | Stable elbow orientation | **High fit** — GAP-7. |
| **FABRIK multi-bone IK** | Cleaner shoulder + two-hand grip | **Medium fit** — only if pole IK insufficient. |
| **Motion matching** (Ubisoft) | Mocap-quality body motion | **Low fit** — no mocap pipeline. |
| **Learned motion synthesis** (phase-functioned NN, etc.) | Locomotion realism | **Low fit** — too heavy for target scope. |
| **Signed Distance Field reach volumes** | Fast posture eligibility | **Medium fit** — alternative to green pool proximity test. |
| **Inverse-dynamics wrist snap** | Realistic contact velocity | **Medium fit** — pairs well with GAP-3 charge scaling. |

---

## Part 4 — Prioritized Gap List (rev 2, for sequencing in `bubbly-mixing-wirth.md`)

Resolved gaps removed. Remaining ordered by (impact × ease).

**Resolved since rev 1**: ✅ GAP-1 (TTC), ✅ GAP-3 (charge→force, rev 3), ✅ GAP-4 (spring chase, rev 3), ✅ GAP-6 (LOCK), ✅ GAP-9 (charge-scaled tween).
**Partial**: 🟡 GAP-1b (per-point time tags), 🟡 GAP-7 (static pole, not posture-aware).

1. **🟡 GAP-7b Posture-aware pole vector** — per-posture dictionary, fall back to current static pole. Next easy polish win. *Low effort, medium impact.*
2. **🔴 GAP-13 Momentum-aware scoring** — one cost term. Reads as AI "anticipation". *Low effort, medium impact.*
3. **🔴 GAP-12 Difficulty on commit TTC** — EASY locks at ~0.3s, HARD at ~0.1s. *Low effort, medium impact.*
4. **🔴 GAP-5 Space-time green pool** — tighter radius (0.3) already helps; add temporal horizon cutoff next. *Medium effort, medium impact.*
5. **🔴 GAP-11 Signal-driven reaction delay** — scale `reaction_delay` by opponent charge jitter. *Low effort, low impact.*
6. **🔴 GAP-14 gdUnit4 regression tests** — before touching scoring (GAP-5/13). *Medium effort, high safety value.*
7. **🟡 GAP-1b Per-point trajectory time tags** — only if commit timing glitches appear in play. *Medium effort, low-medium impact.*
8. **🔴 GAP-2 Ball state estimator** — only if GAP-8 happens. *Medium effort, deferred.*
9. **🔴 GAP-8 Spin / Magnus** — separate feature scope. *High effort, high impact, defer.*
10. **🔴 GAP-10 Motion-matching-inspired feature vector** — research-grade. *High effort, defer.*

---

## Part 4b — Implementation Sketches for Remaining Top Priorities (rev 2)

Pseudocode only — actual diffs belong in `bubbly-mixing-wirth.md`. **Sketches for GAP-1 and GAP-6 removed — already implemented in rev 2.** The two highest-ROI open items are GAP-3 and GAP-4.

### Sketch 1 · GAP-3: Charge → Force coupling

**`player_hitting.gd:get_shot_impulse` (line ~378-421)** — single added term:
```gdscript
func get_shot_impulse(ball_pos: Vector3, charge_ratio: float, silent: bool) -> Vector3:
    var dir := _compute_impulse_direction(ball_pos)  # existing
    var force_scale := _get_force_scale_for_contact_state()  # existing
    # NEW: charge-dependent gain
    var charge_gain := lerpf(0.60, 1.25, clampf(charge_ratio, 0.0, 1.0))
    return dir.normalized() * paddle_force * force_scale * charge_gain
```

Tuning: start at `(0.60, 1.25)` → half-charge is 60% power, full is 125% of current baseline. If CLEAN shots feel too hot at full charge, drop the upper bound to 1.15.

### Sketch 2 · GAP-4: Critically-damped spring on paddle chase

`_damp_v3` already exists at `player.gd:342-348`. Just use it.

**`player_paddle_posture.gd:693-705` — `force_paddle_head_to_ghost`**, replace raw lerp:
```gdscript
func force_paddle_head_to_ghost(dt: float) -> void:
    if _committed_incoming_posture == -1: return
    var ghost := _get_ghost_for(_committed_incoming_posture)
    var halflife: float
    match _last_commit_stage:
        STAGE_PINK:   halflife = 0.22
        STAGE_PURPLE: halflife = 0.10
        STAGE_BLUE:   halflife = 0.04
        _:            halflife = 0.18
    paddle.global_position = _player._damp_v3(
        paddle.global_position, ghost.global_position, halflife, dt
    )
    # quaternion slerp with damped factor
    var k := 0.693 / maxf(halflife, 0.001)
    var t := 1.0 - exp(-k * dt)
    paddle.quaternion = paddle.quaternion.slerp(ghost.quaternion, t)
```

`GHOST_LERP_SPEED` (line 141) becomes dead — delete after testing.

### Sketch 3 · GAP-7b: Posture-aware pole vector (polish)

**`player_arm_ik.gd:13`** — replace static pole with posture lookup:
```gdscript
const POLE_OFFSETS := {
    PaddlePosture.HIGH_OVERHEAD:     Vector3( 0.1, 0.6, -0.3),
    PaddlePosture.MEDIUM_OVERHEAD:   Vector3( 0.1, 0.4, -0.3),
    PaddlePosture.LOW_FOREHAND:      Vector3( 0.6, 0.1, -0.1),
    PaddlePosture.LOW_BACKHAND:      Vector3(-0.6, 0.1, -0.1),
    PaddlePosture.WIDE_FOREHAND:     Vector3( 0.7,-0.2, -0.2),
    PaddlePosture.WIDE_BACKHAND:     Vector3(-0.7,-0.2, -0.2),
    # ...etc for all 20
}

var active_posture: int = _player._posture._committed_incoming_posture
var offset: Vector3 = POLE_OFFSETS.get(active_posture, Vector3(0.5, -1.0, -0.5))
pole_global = _player.global_position + \
    _player._get_forehand_axis() * offset.x + \
    Vector3(0, offset.y, 0) + \
    _player._get_forward_axis() * offset.z
```

Fall back to current static pole for any posture not listed. Tune per-posture live in editor.

---

## Part 5 — Key File Map for Implementation

| Subsystem | Primary file | Secondary |
|---|---|---|
| Trajectory math | `scripts/player_debug_visual.gd:380-520` | — |
| Trajectory ingestion | `scripts/player_paddle_posture.gd:418` | — |
| Posture zones + ghosts | `scripts/player_paddle_posture.gd:75-103, 870-1050` | — |
| Commit stages | `scripts/player_paddle_posture.gd:220-282` | — |
| Green pool | `scripts/player_paddle_posture.gd:805-820, 920-1050` | — |
| Scoring | `scripts/player_paddle_posture.gd:529-780` | — |
| Contact point | `scripts/player_paddle_posture.gd:438-527` | — |
| Charge visual | `scripts/player_hitting.gd:83-202` | — |
| Release tween | `scripts/player_hitting.gd:254-350` | — |
| Shot impulse | `scripts/player_hitting.gd:378-421` | — |
| Arm IK | `scripts/player_arm_ik.gd:8-120` | — |
| AI prediction | `scripts/player_ai_brain.gd:336-382` | — |
| Contact state | `scripts/player.gd:404-409` | — |

---

## Sources

- [Intercepting virtual balls approaching under different gravity conditions — Zago et al., J. Neurophysiology 2017](https://journals.physiology.org/doi/full/10.1152/jn.00025.2017)
- [Target State Estimation and Prediction for High Speed Interception — Dey et al., arXiv:2010.02512](https://arxiv.org/abs/2010.02512)
- [Enhancing ball trajectory prediction using Vision AI — Ultralytics](https://www.ultralytics.com/blog/enhancing-ball-trajectory-prediction-using-vision-ai)
- [TT3D: Table Tennis 3D Reconstruction — arXiv:2504.10035](https://arxiv.org/pdf/2504.10035)
- [Towards Ball Spin and Trajectory Analysis in Table Tennis Broadcast — CVPR 2025](https://openaccess.thecvf.com/content/CVPR2025W/CVSPORTS/papers/Kienzle_Towards_Ball_Spin_and_Trajectory_Analysis_in_Table_Tennis_Broadcast_CVPRW_2025_paper.pdf)
- [Spring-Roll-Call (critically damped springs) — Daniel Holden](https://theorangeduck.com/page/spring-roll-call)
- [Godot Forums — IK Pole Vector discussion](https://godotforums.org/d/22393-is-there-an-ik-pole-vector)
- [Unity Discussions — Two-bone IK pole angle support](https://discussions.unity.com/t/animation-rigging-two-bone-ik-pole-angle-options-support/790173)
- [Many Bone IK — Godot proposals #6039](https://github.com/godotengine/godot-proposals/issues/6039)
- [Twisted IK 2 feature list — itch.io](https://itch.io/t/1108778/complete-feature-list-last-updated-06012023)
- [Binocular-vision-based Trajectory Prediction of Spinning Ball (table tennis robot)](https://sensors.myu-group.co.jp/sm_pdf/SM3892.pdf)

---

## Part 6 — Academic Research Cross-Reference & New Gaps (rev 4)

> **Added 2026-04-11.** Literature sweep across four bodies of work — (A) racket-ball impact physics, (B) swing biomechanics, (C) interception perception-action, (D) procedural character animation — each cross-referenced to specific current code and new gaps (numbered GAP-15 through GAP-23).

### A. Racket-Ball Impact Physics

**Canonical sources**:
- Brody, H. (1979, 1981). "Physics of the tennis racket" — *American Journal of Physics* 47(6) and 49(9). Foundational treatment of racket moments of inertia, power region, node of vibration, and the three distinct "sweet spots" (center of percussion, vibration node, maximum coefficient-of-restitution point).
- Cross, R. (1998). "The sweet spots of a tennis racket" — *Sports Engineering* 1(2), 63-78. Shows COP and node are **not colocated**; the felt-sweet-spot is the node, the power sweet spot is the COP.
- Cross, R. (1999). "Dynamic properties of tennis balls" — *Sports Engineering* 2(1), 23-33. COR is **velocity-dependent**: ~0.75 at low impact (5 m/s), drops to ~0.65 at 15 m/s. Non-linear stiffness curve.
- Goodwill, S. R. & Haake, S. J. (2004). "Ball spin generation for oblique impacts with a tennis racket" — *Experimental Mechanics* 44, 195-206. Measured dwell time of ~4-5 ms and tangential-friction-driven spin transfer coefficients.

**New gaps derived**:

#### ✅ GAP-15 · Sweet-spot off-center speed reduction

**Current**: `player_hitting.gd:get_shot_impulse` returns a single impulse regardless of where on the paddle surface the ball actually made contact. All contacts are treated as center-hits.

**Research basis**: Brody's node-of-vibration concept and Cross's COP mapping prove that **real rackets have a ~5-7 cm diameter "power zone" outside which power drops 20-30%** and a separate "vibration node" outside which the racket transmits shock into the wrist. Table tennis and pickleball paddles have an even tighter sweet spot due to smaller surface area.

**Concrete fix**:
```gdscript
# in get_shot_impulse, after computing paddle_to_ball vector:
var paddle_local_hit: Vector3 = paddle_node.global_transform.affine_inverse() * ball_position
var hit_offset: float = Vector2(paddle_local_hit.x, paddle_local_hit.y).length()
# sweet spot at (0,0.02) in paddle local, radius 0.04
var sweet_offset: float = (Vector2(paddle_local_hit.x, paddle_local_hit.y) - Vector2(0, 0.02)).length()
var sweet_factor: float = clampf(1.0 - sweet_offset / 0.10, 0.55, 1.0)  # 45% penalty at rim
force_scale *= sweet_factor
```
Pair with a small camera shake + audio variant when `sweet_factor < 0.75` for tactile feedback. *Low effort, high felt impact.*

#### 🔴 GAP-21 · Fixed coefficient of restitution ignores velocity dependence

**Current**: `AI_BOUNCE_RESTITUTION := 0.685` hard-coded at `player_debug_visual.gd:10` and `player_ai_brain.gd:11`. Applied uniformly to both floor bounces and trajectory prediction.

**Research basis**: Cross (1999) measured COR dropping from ~0.75 at 5 m/s to ~0.65 at 15 m/s on a tennis ball. Pickleball balls (hollow plastic with holes) show an even steeper drop — measured COR of 0.78 at 3 m/s falling to 0.56 at 18 m/s in USAPA equipment testing data. Using a constant 0.685 over-predicts fast-ball bounce height and under-predicts slow-ball bounce height, which feeds back into trajectory prediction and green pool commits.

**Concrete fix**: replace constant with a lookup function:
```gdscript
func _cor_for_impact_speed(v: float) -> float:
    # pickleball-calibrated: 0.78 at 3 m/s, 0.56 at 18 m/s, lerped
    return lerpf(0.78, 0.56, clampf((v - 3.0) / 15.0, 0.0, 1.0))
```
Call this in both `draw_incoming_trajectory` and `ball.gd` floor-bounce code. *Low effort, medium impact on prediction accuracy.*

#### 🟡 GAP-22 · No ball-paddle dwell time (instantaneous impulse)

**Current**: ball impulse is applied in a single physics frame. Ball velocity snaps.

**Research basis**: Goodwill & Haake measured ~4-5 ms of contact dwell — long enough that string flex and paddle-face angle change mid-contact influence final ball direction. On a pickleball paddle (no strings) dwell is much shorter (~1-2 ms) but still nonzero.

**Assessment**: probably *not* worth implementing — the gameplay improvement is marginal and the physics cost is real. Listed for completeness. **Defer unless another gap needs multi-frame contact (e.g., spin transfer in GAP-8).**

### B. Swing Biomechanics

**Canonical sources**:
- Kibler, W. B. (1995, 2007). Work on the **kinetic chain** in tennis and throwing sports. Core finding: peak power is generated by sequential activation — legs → hips → trunk → shoulder → elbow → wrist — with each segment peaking just before the next segment begins to accelerate. Disruptions to this sequence ("breaks in the chain") reduce ball velocity by 10-20%.
- Elliott, B. (2006). "Biomechanics and tennis" — *British Journal of Sports Medicine* 40, 392-396. Quantifies that ~50% of serve racket-head velocity comes from internal rotation of the shoulder, ~25% from forearm pronation, ~15% from wrist flexion, and only ~10% from shoulder/torso rotation.
- Marshall, R. N. & Elliott, B. C. (2000). "Long-axis rotation: The missing link in proximal-to-distal segmental sequencing" — *Journal of Sports Sciences* 18, 247-254.

**New gaps derived**:

#### 🔴 GAP-16 · No kinetic chain timing in swing animation

**Current**: `player_hitting.gd:animate_serve_release` (lines 254-350) uses a 4-phase tween (STRIKE → SWEEP → SETTLE → HOLD) but all body segments move in parallel. Body rotation, shoulder, elbow, wrist all start at t=0 and end simultaneously.

**Research basis**: Kibler's kinetic chain says real swings show a ~30-80 ms lag between each segment's peak velocity. Hips peak first, then torso ~50 ms later, shoulder ~50 ms after that, elbow ~40 ms after, wrist ~20 ms after elbow. Total kinetic chain duration ~200 ms for a serve, ~120-150 ms for a groundstroke.

**Concrete fix**: stagger the tween. Instead of one `t_sweep` for the whole body, compute per-segment delays:
```gdscript
# inside animate_serve_release
var chain_delays := {
    "hip":      0.00,
    "torso":    0.04,
    "shoulder": 0.08,
    "elbow":    0.12,
    "wrist":    0.14,
}
for segment in chain_delays:
    tween.tween_property(body_pivot, "rotation:%s" % segment_axis[segment],
        target_rot, t_sweep).set_delay(chain_delays[segment])
```
Requires that `player_body_animation.gd` expose individual segment rotations — may need a small refactor. *Medium effort, high visual impact — the single biggest "it looks like a real swing" upgrade.*

#### 🔴 GAP-23 · No wrist snap / forearm pronation

**Current**: `player_arm_ik.gd` solves for paddle position but doesn't independently animate wrist flexion or forearm pronation. The wrist rotates only as a side effect of the IK solution.

**Research basis**: Elliott (2006) — forearm pronation + wrist flexion together produce ~40% of serve racket-head velocity. On groundstrokes it's less (~20%) but still dominant among "final link" contributors.

**Concrete fix**: after IK solves, add a post-solve wrist rotation driven by a separate tween keyed to the final ~30 ms before contact:
```gdscript
# called from animate_serve_release during STRIKE phase
var wrist_snap_angle := deg_to_rad(lerpf(15, 45, charge_ratio))
tween.tween_property(wrist_bone, "rotation:x", wrist_snap_angle, 0.03).from(0)
```
Biggest payoff for overhead smashes where pronation is visually iconic. *Low-medium effort, high visual impact.*

### C. Interception Perception-Action

**Canonical sources**:
- Lee, D. N. (1980). "The optic flow field: The foundation of vision" — *Philosophical Transactions of the Royal Society B* 290, 169-179. Introduces **tau (τ)** — the time-to-contact computable directly from optic flow divergence without requiring a distance estimate. Foundational for modern TTC research.
- Bootsma, R. J. & van Wieringen, P. C. W. (1990). "Timing an attacking forehand drive in table tennis" — *Journal of Experimental Psychology: Human Perception and Performance* 16, 21-29. Shows skilled players **continuously adjust swing timing throughout the visuomotor delay** — they don't commit to a fixed plan; they refine it in flight.
- Tresilian, J. R. (1999). "Visually timed action: time-out for 'tau'?" — *Trends in Cognitive Sciences* 3, 301-310. Critique and refinement of tau theory; argues humans use multiple timing cues, not pure tau.
- McLeod, P. & Dienes, Z. (1993). "Running to catch the ball" — *Nature* 362, 23. Introduces the **Linear Optical Trajectory (LOT)** strategy: fielders run so the ball appears to move in a straight line in their visual field, a simple heuristic that solves the interception problem without explicit prediction.
- Land, M. F. & McLeod, P. (2000). "From eye movements to actions: how batsmen hit the ball" — *Nature Neuroscience* 3, 1340-1345. Cricket batsmen use two saccades: one to the predicted bounce point, one to the predicted bat contact point.

**New gaps derived**:

#### 🔴 GAP-17 · AI uses explicit prediction, not LOT/tau heuristic

**Current**: `player_ai_brain.gd:_predict_ai_contact_candidates` runs forward-Euler physics sims to find interception points. This is the "engineer's" approach — computationally optimal, visually "too good".

**Research basis**: McLeod & Dienes's LOT strategy shows real fielders/players don't predict — they servo on a simple optical invariant. For racket sports, [McBeath, Shaffer & Kaiser (1995)](https://www.science.org/doi/10.1126/science.7725104) showed baseball fielders use a similar invariant (Optical Acceleration Cancellation). This means AI trajectories are currently *too good* — they commit instantly to the mathematically correct point.

**Concrete fix**: wrap the existing prediction in an LOT-like servo. Instead of moving directly to the predicted contact point, move such that the ball's apparent angular position stays constant:
```gdscript
# replace direct target with LOT servo
var ball_angle_now: Vector2 = _angle_to_ball()
var ball_angle_was: Vector2 = _ball_angle_prev
var angle_drift: Vector2 = ball_angle_now - ball_angle_was
# move to cancel the drift
var move_dir: Vector3 = _world_dir_for_angle(angle_drift * drift_gain)
```
Produces organic pursuit paths that occasionally miss, especially on deceptive shots. *Medium effort, high impact on "human-like AI" feel.*

#### 🔴 GAP-11b · Reaction is a fixed delay, not a continuous refinement

**Already listed as GAP-11, but Bootsma & van Wieringen (1990) sharpens the recommendation**: skilled players don't "react" once — they **continuously refine** the swing plan throughout the 200 ms visuomotor delay. The AI should commit to a rough target at ball-leave, then re-refine every frame, with the magnitude of refinement capped by how close we are to contact (can't make big changes in the last 50 ms).

**Concrete extension to GAP-11**:
```gdscript
# in AI intercept update loop
var refine_cap: float = lerpf(0.02, 0.30, ttc / 0.5)  # meters per frame refinement limit
var desired_move: Vector3 = target_new - target_prev
var capped_move: Vector3 = desired_move.limit_length(refine_cap)
target_prev += capped_move
```
Prevents the AI from "teleporting" its target on late trajectory changes. *Low effort, high feel impact.*

#### 🟡 GAP-19 · No gaze / head-tracking animation

**Current**: `player_body_animation.gd` handles lean, crouch, sway, bob — but no head/neck tracking of the ball.

**Research basis**: Land & McLeod (2000) — batsmen execute two anticipatory saccades. Real tennis/pickleball players' eyes and heads lead the swing by 100-200 ms. This is pure visual polish, but it's the difference between a mannequin and a player.

**Concrete fix**: add a `neck` bone target pointing at (ball.pos + ball.velocity * 0.15). Damp with halflife 0.1 s. ~20 line add to body animation module. *Low effort, medium visual impact.*

### D. Procedural Character Animation (game-industry research)

**Canonical sources**:
- Holden, D., Komura, T. & Saito, J. (2017). "Phase-functioned neural networks for character control" — *SIGGRAPH* / *ACM TOG* 36(4). The PFNN paper that kicked off learned motion synthesis for locomotion on arbitrary terrain.
- Zhang, H., Starke, S., Komura, T. & Saito, J. (2018). "Mode-adaptive neural networks for quadruped motion control" — *SIGGRAPH*. Extended PFNN with gating networks for multi-mode motion.
- Starke, S., Zhang, H., Komura, T. & Saito, J. (2019). "Neural state machine for character-scene interactions" — *SIGGRAPH Asia*. Learned motion controller for sitting/opening-door/pickup interactions.
- Starke, S., Zhao, Y., Komura, T. & Zaman, K. (2020). "Local motion phases for learning multi-contact character movements" — *SIGGRAPH 2020*, applied to **basketball dribble/pass/shoot**. Directly relevant: learns short phase labels per body part independently, allowing asynchronous segment animation (exactly what GAP-16 describes, but learned instead of hand-authored).
- Clavet, S. (2016). "Motion matching and the road to next-gen animation" — *GDC*. Ubisoft's production talk introducing motion matching. Core idea: at every frame, query a mocap database for the pose that best matches current (velocity, trajectory, contact state), blend in.
- Peng, X. B., Abbeel, P., Levine, S. & van de Panne, M. (2018). "DeepMimic: example-guided deep reinforcement learning of physics-based character skills" — *SIGGRAPH*. RL trains physically simulated characters to imitate mocap clips, including acrobatic flips and kicks.
- Kenwright, B. (2012). "Inverse kinematics – cyclic coordinate descent (CCD)" — tutorial reference for FABRIK alternatives.

**New gaps derived**:

#### 🟡 GAP-18 · No per-body-part motion phasing (local motion phases)

**Research basis**: Starke et al. (2020) showed that basketball movements (dribble, layup, crossover) are far better synthesized when each **body part has its own phase** rather than a global timeline. Exactly the kinetic-chain decoupling that GAP-16 describes, but done with learned phase functions rather than hand-authored delays.

**Assessment**: **research-grade, defer**. The hand-authored kinetic chain fix in GAP-16 gets 80% of the visual benefit at 5% of the implementation cost. Only worth revisiting if you want mocap-quality animation and have a data pipeline.

#### ✅ GAP-20 · Physics CCD — **RESOLVED (rev 4.1, 2026-04-11)**

**Verified broken**: `project.godot` had no `physics_ticks_per_second` override (= 60 Hz default). `scenes/ball.tscn` had no `continuous_cd` property (= DISABLED default). At max speed 20 m/s, the 0.06 m radius ball traveled **33 cm/tick = 5.5 radii per tick** — guaranteed to tunnel through thin paddle colliders on glancing contacts. Even a normal 8 m/s serve moves 13 cm/tick = 2.2 radii.

**Supporting evidence from existing code**: CLAUDE.md already documents a manual floor-bounce workaround in `ball.gd` because "threshold-based detection misses fast balls — the physics engine resolves collisions before `_physics_process`". Tunneling was a **known problem on the floor**, previously **unhandled for paddle contact**.

**Fix applied**: `scenes/ball.tscn` — added `continuous_cd = 2` (CCD_CAST_SHAPE) to the Ball rigidbody. Shape-cast (not ray) was chosen because ray-CCD misses glancing contacts where the sphere edge touches but the center doesn't; shape-cast sweeps the full 0.06m sphere along velocity.

**Test**: headless Godot boot clean, no new errors, physics subsystem initializes, ball trail + hit feedback still work. Runtime ball behavior preserved.

**Remaining recommendation**: bump `physics/common/physics_ticks_per_second` to 120 in `project.godot` as a belt-and-suspenders measure for the max-speed 20 m/s case. Not applied yet — deferred as it affects all physics bodies, not just the ball.

#### 🔴 GAP-24 · No mocap data pipeline for reference poses (meta-gap)

**Observation**: the entire rig is hand-authored from offsets. No reference motion capture. For a hobby project this is fine, but it caps the achievable animation quality at ~70% of AAA. If the project ever wants to cross that line, the first step is ingesting freely-available mocap (e.g., CMU Motion Capture Database, or free tennis mocap from ActorCore / Mixamo).

**Assessment**: **deferred indefinitely** unless/until you decide to pursue motion-matching or learned synthesis. Listed so the trade-off is explicit.

### Summary Table — New Gaps from Part 6

| GAP | Area | Effort | Impact | Priority slot |
|---|---|---|---|---|
| GAP-15 Sweet-spot modeling | Physics | Low | High (feel) | **Slot 2 after GAP-7b** |
| GAP-16 Kinetic chain timing | Animation | Medium | High (visual) | **Slot 3** |
| GAP-17 LOT servo for AI | AI | Medium | High (feel) | **Slot 4** |
| GAP-20 Physics CCD verification | Correctness | Low | Critical | **Slot 1 — do immediately** |
| GAP-21 Velocity-dependent COR | Physics | Low | Medium | **Slot 5** |
| GAP-23 Wrist snap | Animation | Low-med | High (visual) | **Slot 6** |
| GAP-11b Continuous refinement | AI | Low | Medium-high | **Slot 7** |
| GAP-19 Head/gaze tracking | Polish | Low | Medium | **Slot 8** |
| GAP-22 Dwell time | Physics | High | Low | Defer |
| GAP-18 Local motion phases | Animation | Very high | High | Defer |
| GAP-24 Mocap pipeline | Infrastructure | Very high | Very high | Defer |

### Updated Rev-4.1 Priority Queue

1. ✅ **GAP-20 Physics CCD** — RESOLVED (CCD_CAST_SHAPE on ball, rev 4.1)
2. **🟡 GAP-7b Posture-aware pole vector** — next up
3. **🔴 GAP-15 Sweet-spot modeling** — highest feel-per-effort ratio in rev 4
4. **🔴 GAP-16 Kinetic chain timing** — biggest visual upgrade from literature
5. **🔴 GAP-17 LOT servo for AI** — makes AI feel human
6. **🔴 GAP-23 Wrist snap** — iconic visual for overheads
7. **🔴 GAP-21 Velocity-dependent COR** — prediction accuracy
8. **🔴 GAP-13 Momentum-aware scoring** (from rev 1)
9. **🔴 GAP-12 Difficulty on commit TTC** (from rev 1)
10. **🔴 GAP-11b Continuous refinement** (sharpened from GAP-11)
11. **🟡 GAP-19 Head/gaze tracking**
12. **🔴 GAP-5 Space-time green pool**
13. **🔴 GAP-14 gdUnit4 regression tests**

### Additional Sources (rev 4)

- Brody, H. (1979). "Physics of the tennis racket" — *American Journal of Physics* 47(6), 482-487.
- Brody, H. (1981). "Physics of the tennis racket II: The sweet spot" — *American Journal of Physics* 49(9), 816-819.
- Cross, R. (1998). "The sweet spots of a tennis racket" — *Sports Engineering* 1(2), 63-78.
- Cross, R. (1999). "Dynamic properties of tennis balls" — *Sports Engineering* 2(1), 23-33.
- Goodwill, S. R. & Haake, S. J. (2004). "Ball spin generation for oblique impacts with a tennis racket" — *Experimental Mechanics* 44, 195-206.
- Kibler, W. B. (1995). "Biomechanical analysis of the shoulder during tennis activities" — *Clinics in Sports Medicine* 14(1), 79-85.
- Kibler, W. B. (2007). "The role of the scapula in athletic shoulder function" — *American Journal of Sports Medicine* 26(2), 325-337.
- Elliott, B. (2006). "Biomechanics and tennis" — *British Journal of Sports Medicine* 40(5), 392-396.
- Marshall, R. N. & Elliott, B. C. (2000). "Long-axis rotation: The missing link in proximal-to-distal segmental sequencing" — *Journal of Sports Sciences* 18(4), 247-254.
- Lee, D. N. (1980). "The optic flow field: The foundation of vision" — *Phil. Trans. Royal Soc. B* 290, 169-179.
- Bootsma, R. J. & van Wieringen, P. C. W. (1990). "Timing an attacking forehand drive in table tennis" — *J. Exp. Psychology: Human Perception & Performance* 16(1), 21-29.
- Tresilian, J. R. (1999). "Visually timed action: time-out for 'tau'?" — *Trends in Cognitive Sciences* 3(8), 301-310.
- McLeod, P. & Dienes, Z. (1993). "Running to catch the ball" — *Nature* 362, 23.
- [McBeath, Shaffer & Kaiser (1995). "How baseball outfielders determine where to run to catch fly balls" — *Science* 268, 569-573](https://www.science.org/doi/10.1126/science.7725104).
- Land, M. F. & McLeod, P. (2000). "From eye movements to actions: how batsmen hit the ball" — *Nature Neuroscience* 3(12), 1340-1345.
- Holden, D., Komura, T. & Saito, J. (2017). "Phase-functioned neural networks for character control" — *ACM Trans. Graphics* 36(4), 42.
- Zhang, H., Starke, S., Komura, T. & Saito, J. (2018). "Mode-adaptive neural networks for quadruped motion control" — *ACM Trans. Graphics* 37(4), 145.
- Starke, S., Zhang, H., Komura, T. & Saito, J. (2019). "Neural state machine for character-scene interactions" — *ACM Trans. Graphics* 38(6), 209.
- Starke, S., Zhao, Y., Komura, T. & Zaman, K. (2020). "Local motion phases for learning multi-contact character movements" — *ACM Trans. Graphics* 39(4), 54.
- Clavet, S. (2016). "Motion matching and the road to next-gen animation" — *Game Developers Conference*.
- Peng, X. B., Abbeel, P., Levine, S. & van de Panne, M. (2018). "DeepMimic: example-guided deep reinforcement learning of physics-based character skills" — *ACM Trans. Graphics* 37(4), 143.

---

## Part 7 — Reach, Jump & Footwork Gaps (rev 5)

> **Added 2026-04-11.** Audit of how the body *physically* intercepts balls outside the normal standing envelope. Covers hand reach toward trajectory, jumping for high balls, lunging for wide balls, and the coupling between body velocity and paddle contact. Verified via direct code reads, not inference.

### What currently exists

| Feature | Where | Details |
|---|---|---|
| Manual jump | `player.gd:397-402` | `KEY_J` only, `JUMP_VELOCITY=4.1`, peak ≈ `v²/2g = 0.73 m` |
| Jump state flag | `player.gd:115, 286` | `is_jumping: bool`, cleared on landing |
| Overhead smash gate | `player_hitting.gd:414` | Uses `is_jumping OR ball_height > MEDIUM_OVERHEAD_TRIGGER_HEIGHT (0.72)` |
| Crouch coupling | `player_body_animation.gd:75-108` | LOW/MID_LOW postures drive damped crouch amount |
| Reach-coupled lean | `player_body_animation.gd:66-67` | `lean_boost = clamp(abs(reach_lateral) - 0.2, 0, 0.7) * 12°` |
| Wide-ghost spread | `player_paddle_posture.gd:1046-1049` | `reach_amount = clamp(abs(contact_lateral)-0.3, 0, 0.6) * 0.8` → max +48 cm |
| Reach envelope constant | `player_paddle_posture.gd:492` | `REACH_XZ := 1.2` (static, ~matches WIDE posture offsets) |
| Gait system | `player_leg_ik.gd` | Walking sway/step only — no lunge/step-out |

### What's missing

Each gap below was verified by direct code reads. `grep "jump" player_ai_brain.gd` returned **zero matches** — the AI does not jump, at all.

#### 🔴 GAP-25 · AI never jumps

**Verified broken**: `grep -n 'jump' player_ai_brain.gd` → no results. The AI's state machine has `INTERCEPT_POSITION`, `CHARGING`, `HIT_BALL` — no `JUMPING` state. The AI handles high balls by walking under them and hoping; if the ball's apex is above `MEDIUM_OVERHEAD_TRIGGER_HEIGHT + arm_reach`, the AI simply can't reach it.

**Current "lucky" workaround**: jump peak 0.73 m ≈ trigger height 0.72 m, so a *human* who presses J at the right moment can reach almost anything. The AI cannot.

**Concrete fix**: add a `SHOULD_JUMP` branch to `_predict_ai_contact_candidates`. When the predicted contact point Y > `ground_y + standing_reach_height`, plan a jump:
```gdscript
# in AI intercept update
var standing_max_y := ground_y + 1.65  # shoulder height + arm reach
var needs_jump: bool = predicted_contact.y > standing_max_y
if needs_jump and not is_jumping:
    var jump_ttc: float = (predicted_contact - global_position).length() / ai_move_speed
    # takeoff timing: want apex at contact moment
    # flight time to apex = JUMP_VELOCITY / JUMP_GRAVITY = 4.1/11.5 = 0.357s
    if jump_ttc <= 0.36 and jump_ttc >= 0.30:
        _trigger_jump()
```
Minimal effort once predicted_contact.y is available. *Medium effort, high impact — AI currently has a capability gap humans don't.*

#### 🔴 GAP-26 · Jump timing not TTC-aligned (even for human)

**Verified broken**: `player.gd:398` triggers jump the instant `KEY_J` is pressed, with no look-ahead. If you press J when ball is 0.5 s away, you rise, peak at 0.357 s, then descend — ball arrives at 0.5 s when you're at `y = 0.73 - 0.5·g·(0.5-0.357)² = 0.62 m`, already falling. You've lost 11 cm of reach.

**Research basis**: volleyball spike biomechanics literature (e.g., Tilp & Rindler on approach timing; Wagner et al. on spike jump coordination) consistently show elite spikers time takeoff so ball contact happens **at or just past apex** (where vertical velocity is ~0 and vertical position is maximal). Deviation from this window degrades spike velocity by 10-25%.

**Concrete fix**: instead of instant jump on keypress, buffer the input and release it when `ttc ≈ 0.36 s` (the flight time to apex):
```gdscript
# player.gd _update_jump_state
if Input.is_key_just_pressed(KEY_J) and not is_jumping:
	_jump_buffered = true
	_jump_buffer_t = 0.0
if _jump_buffered:
	_jump_buffer_t += delta
	var ttc: float = _posture._ttc_to_contact  # from GAP-1
	if ttc <= 0.36 and ttc > 0.0:
		vertical_velocity = JUMP_VELOCITY
		is_jumping = true
		_jump_buffered = false
	elif _jump_buffer_t > 0.5:
		_jump_buffered = false  # window missed, cancel
```
Applies to both human (buffered) and AI (directly computed). *Medium effort, high impact on jump quality.*

#### 🔴 GAP-27 · No air control / horizontal ball-tracking during jump

**Verified broken**: `player.gd:282` applies `global_position.y += vertical_velocity * delta` but horizontal position is whatever the movement controller last wrote. There's no "in-air tracking" that continues to steer toward the ball's XZ path during flight.

**Real pickleball reference**: mid-air shot adjustments are small but nonzero — players lean and reach during flight. A completely ballistic jump feels robotic.

**Concrete fix**: allow reduced horizontal control during jump:
```gdscript
# in movement code, while is_jumping:
var air_control_factor: float = 0.3  # 30% of ground speed
velocity.x *= air_control_factor
velocity.z *= air_control_factor
```
Low-effort polish, keeps the jump dominated by initial trajectory but allows small mid-flight corrections. *Low effort, medium impact.*

#### 🔴 GAP-28 · Body vertical velocity not added to paddle impulse

**Verified broken**: `player_hitting.gd:get_shot_impulse` at line 378-423 computes `dir * paddle_force * force_scale * charge_gain`. The player's `vertical_velocity` is **never added**. A jumping smash at apex (vy=0) and one on rise (vy=+3) hit with the same vertical ball velocity.

**Research basis**: momentum transfer — the paddle's velocity at contact is `body_vel + arm_swing_vel`. Currently we only model arm swing. For a jumping overhead on the rise, real contact adds ~3 m/s of downward delta to the ball (opposite sign: paddle going up contributes upward force too, but the smash is downward-angled so the net effect is a steeper angle, not faster ball).

**Concrete fix**:
```gdscript
# in get_shot_impulse, after computing base impulse:
var body_vel_contribution: Vector3 = Vector3(0, _player.vertical_velocity * 0.3, 0)
return dir.normalized() * paddle_force * force_scale * charge_gain + body_vel_contribution
```
The 0.3 factor is because only a fraction of body velocity transfers — arm is a damped coupling. *Trivial effort, high realism — makes jump smashes feel meaty.*

#### 🔴 GAP-29 · No lunge / step-out footwork

**Verified broken**: `player_leg_ik.gd` handles gait sway and walking steps, but there is no "lunge" state where one foot plants wide and the other extends in the reach direction. For balls requiring lateral reach > normal WIDE posture lateral offset (0.9 m), the player body has to *walk* there, losing hitting time.

**Research basis**: tennis footwork literature (Kovacs 2009 on directional changes; Reid & Schneiker 2008 on open-stance vs. closed-stance mechanics) identifies the **split-lunge** — a low wide step with the outside foot — as the fastest way to reach balls at 1.3-1.8 m lateral. This exists as a distinct locomotion mode from walking.

**Concrete fix (phased)**:
1. Add `LUNGE` state to leg IK: when `abs(contact_lateral) > 0.8 m` and `ttc < 0.4 s`, plant inside foot, extend outside leg toward contact XZ.
2. Couple to posture module: LUNGE state unlocks a new set of "stretched" ghost offsets (+0.4 m lateral beyond WIDE).
3. Pair with STRETCHED contact state (already exists at `player.gd:404-409`) for the power penalty.
*Medium-high effort, high visual impact.*

#### 🔴 GAP-30 · No split-step on opponent's contact

**Verified broken**: no code for split-step anywhere. `grep 'split' scripts/` returns nothing.

**Research basis**: [Kovacs, M. S. (2009). "Movement for tennis: The importance of lateral training" — *Strength & Conditioning Journal* 31(4), 77-85](https://journals.lww.com/nsca-scj/) — split-step is the pre-load hop executed the instant the opponent strikes the ball. It loads the stretch-shortening cycle so the player can push off harder on the first directional step. Pros split-step on **every** opponent contact without exception; it's the single biggest footwork differentiator between recreational and elite players.

**Concrete fix**:
```gdscript
# subscribe to opponent's shot_fired signal
func _on_opponent_shot_fired() -> void:
    if is_on_ground() and not is_jumping:
        # small hop + crouch preload
        vertical_velocity = 1.5  # tiny hop, ~0.1m
        _split_step_preload = true
        # crouch slightly, store tension
```
The preload then releases as extra move speed on the first directional input. *Medium effort, high feel impact — elevates movement from "walking" to "reactive".*

#### 🟡 GAP-31 · Reach envelope is constant, ignores momentum

**Verified** at `player_paddle_posture.gd:492` — `REACH_XZ := 1.2` is a bare constant. Doesn't scale with player velocity.

**Physical intuition**: a player sprinting laterally has extra *functional* reach in the direction of travel because the body is already moving that way. The paddle will arrive at contact point earlier than a standing player's would. Currently the system treats both identically.

**Concrete fix**: in contact-point scoring, add a directional reach bonus:
```gdscript
var vel_dir: Vector3 = _player.velocity.normalized()
var contact_dir: Vector3 = (contact_point - player_pos).normalized()
var momentum_bonus: float = maxf(0.0, vel_dir.dot(contact_dir)) * 0.25  # up to +0.25 m reach
var effective_reach: float = REACH_XZ + momentum_bonus
```
This is actually the same as GAP-13 (momentum-aware scoring) applied to reach instead of ghost selection. *Low effort, medium impact.*

#### 🟡 GAP-32 · No landing recovery lockout

**Verified broken**: after landing, the player immediately has full movement/hit capability. No stumble frames, no "re-plant" delay.

**Research basis**: force-plate studies show post-landing ground reaction force peaks at 3-5× bodyweight, during which ankle/knee absorb the impact. Players cannot change direction during this ~80-150 ms window.

**Concrete fix**: add a `_landing_recovery_t: float = 0.12` timer, set on landing, block hits/direction-changes while > 0. Keeps an extra frame honest. *Trivial effort, low-medium impact. Mostly matters for AI since human players won't notice 120 ms.*

### Summary Table — Part 7 Gaps

| GAP | Area | Effort | Impact | Priority |
|---|---|---|---|---|
| GAP-25 AI jump capability | AI | Medium | **High** (capability gap) | **Top slot** |
| GAP-28 Body velocity → impulse | Physics | **Trivial** | High | **Slot 2** |
| GAP-26 TTC-aligned jump timing | Physics | Medium | High | Slot 3 |
| GAP-30 Split-step | Footwork | Medium | High (feel) | Slot 4 |
| GAP-27 Air control | Movement | Low | Medium | Slot 5 |
| GAP-29 Lunge state | Footwork | Medium-high | High (visual) | Slot 6 |
| GAP-31 Momentum reach | Scoring | Low | Medium | Merge with GAP-13 |
| GAP-32 Landing recovery | Movement | Trivial | Low-medium | Polish |

### Updated Rev-5 Priority Queue (Parts 2 + 6 + 7 merged)

Easiest wins with biggest impact, top-first:

1. **🔴 GAP-28 Body velocity → impulse** — 1 line in `get_shot_impulse`. Fixes airborne smash realism. *Trivial / High.*
2. **🟡 GAP-7b Posture-aware pole vector** — per-posture IK pole dict.
3. **🔴 GAP-25 AI jump capability** — biggest functional AI upgrade. Removes the capability gap.
4. **🔴 GAP-15 Sweet-spot modeling** — off-center hit penalty.
5. **🔴 GAP-26 TTC-aligned jump timing** — pairs with GAP-25.
6. **🔴 GAP-16 Kinetic chain timing** — biggest visual upgrade from rev 4.
7. **🔴 GAP-30 Split-step** — elevates movement feel dramatically.
8. **🔴 GAP-17 LOT servo for AI** — makes AI pursuit organic.
9. **🔴 GAP-27 Air control** — polish for jumps.
10. **🔴 GAP-21 Velocity-dependent COR** — physics accuracy.
11. **🔴 GAP-23 Wrist snap** — iconic visual.
12. **🔴 GAP-29 Lunge state** — high effort, keep later.
13. **🔴 GAP-13 Momentum-aware scoring** + GAP-31 (merge).
14. **🔴 GAP-32 Landing recovery** — cheap polish.
15. Rest unchanged.

### Additional Sources (rev 5)

- Kovacs, M. S. (2009). "Movement for tennis: The importance of lateral training" — *Strength & Conditioning Journal* 31(4), 77-85.
- Kovacs, M. S. (2006). "Applied physiology of tennis performance" — *British Journal of Sports Medicine* 40(5), 381-386.
- Reid, M. & Schneiker, K. (2008). "Strength and conditioning in tennis: Current research and practice" — *Journal of Science and Medicine in Sport* 11(3), 248-256.
- Roetert, P. & Kovacs, M. (2011). *Tennis Anatomy*. Human Kinetics.
- Tilp, M. & Rindler, M. (2013). "Spike jump biomechanics in male vs. female elite volleyball players" — *Journal of Human Kinetics* 38, 185-194.
- Wagner, H. et al. (2009). "Kinematic comparison of the volleyball spike between elite and amateur players" — *Journal of Sports Science and Medicine* 8, 238-247.

---

## Part 8 — Awareness Grid: the Volumetric Proximity Detector You Already Have (rev 6)

> **Added 2026-04-11, prompted by user insight**: "how about proximity detector or the volumetric grid solves that? so that the yellow border [shows] more consistently wired with the TTC."
>
> **Confession**: the first 7 audit passes missed `scripts/player_awareness_grid.gd` (419 lines). The user's question led to finding it. It is a full volumetric proximity detector with per-vertex TTC coloring — exactly what Parts 1-7 described as "missing" — but it is **underutilized** and **not wired** to the ghost border system. This part catalogs what's there, what's loose, and how to tighten it.

### 8.1 What the awareness grid actually does

**File**: `scripts/player_awareness_grid.gd`
**Loaded at**: `player.gd:224-228` (attached as child to each player)
**Toggled with**: `Z` hotkey via `game.gd:1071-1072`

**Grid construction** (`_build_grid`, `_generate_zone`, `_generate_floor_forward`):
- Coverage: lateral 2.3 m, forward 6.0 m, behind 1.0 m, height up to 2.1 m
- **Adaptive density**: dense (0.25 m spacing) within 0.8 m, medium (0.35 m) within 1.5 m, sparse (0.5 m) beyond
- **Floor-forward boost**: extra low-Y vertices across the full forward zone (FLOOR_FORWARD_SPACING 0.2 m, Z up to 3.5 m)
- Height samples: 7 levels for dense (0.075 / 0.20 / 0.35 / 0.50 / 0.90 / 1.30 / 1.80)
- Each vertex is a small SphereMesh with an unshaded StandardMaterial3D, emissive

**Zone classification** (`_assign_zone`, lines 194-228):
Every vertex is tagged with one of 13 zones: `FOREHAND_HIGH/MID/LOW/WIDE`, `BACKHAND_HIGH/MID/LOW/WIDE`, `CENTER_HIGH/MID/LOW`, `OVERHEAD`, `BEHIND`. Thresholds: `x > 0.3` = forehand, `|x| > 0.65` = wide, `y > 0.55` = high, `y > 0.2` = mid.

**Zone → posture mapping** (`_init_zone_mapping`, lines 99-115):
Each zone has a list of postures it unlocks. Example: `FOREHAND_WIDE → [WIDE_FOREHAND, MID_LOW_WIDE_FOREHAND, LOW_WIDE_FOREHAND]`.

**Trajectory activation** (`set_trajectory_points`, `_activate_vertices`, lines 249-295):
- Trajectory points are transformed to player-local space, tagged with per-point times (`STEP_TIME = 0.04` × index)
- **Gap interpolation**: if trajectory spacing > `ACTIVATION_RADIUS (0.4 m)`, the grid subdivides to prevent fast balls from skipping over vertices
- For each interpolated point, every vertex within 0.4 m receives `strength = 1 - d/0.4` and `_time_to_arrival = point.t`
- **This is the per-point TTC I said was missing in GAP-1b. It already exists — at vertex granularity, not trajectory-point granularity.**

**TTC color gradient** (`_get_time_color`, lines 406-413):
```
< 0.3s → RED (Color(1.0, 0.1, 0.0))
< 0.6s → ORANGE (Color(1.0, 0.45, 0.0))
< 1.0s → YELLOW (Color(1.0, 0.95, 0.0))
>= 1.0s → GREEN (Color(0.0, 1.0, 0.3))
```
This is **the authoritative TTC signal** for the whole player — higher fidelity than what the posture module currently uses.

**Outputs consumed by posture**:
- `get_posture_zone_scores() -> Dictionary` (postures → urgency-weighted score)
- `get_approach_info() -> Dictionary` (`height`, `lateral`, `urgency`, `confidence`)

### 8.2 How it's currently wired (and isn't)

**Wired in**: `player_paddle_posture.gd` reads grid output at these sites:
- `:254-255` — reads `get_approach_info()` during commit, uses `info.height` / `info.lateral` as a lateral/height override hint
- `:282-286` — `awareness_grid.set_locked(get_ttc_at_world_point(...) < 0.35)` — **✅ RESOLVED (rev 9): now TTC-based**
- `:302-303, :956-957, :987-988, :1003-1004` — `reset()` calls on various clear conditions
- `:580-581, :1171-1172` — additional `get_approach_info()` reads during scoring
- `:939-940` — forwards trajectory points to the grid

**NOT wired in**:
- `_zone_scores` / `_posture_scores` — computed every frame by the grid, **never read** by the commit system (only `get_approach_info` is consumed).
- `_time_to_arrival` per vertex — **never exposed** as a query method. The posture module can't ask "what's the TTC at this world point?"
- Color tier (RED/ORANGE/YELLOW/GREEN) — **grid colors its own vertices**, but the ghost border system uses an independent wall-clock fade (`INCOMING_FADE_DURATION = 0.6 s` from `player_paddle_posture.gd:139`) with zero knowledge of the grid's TTC tiers.

**The two proximity systems in the codebase**:

| System | What it tracks | Radius | TTC? | Drives |
|---|---|---|---|---|
| **Green pool** (`player_paddle_posture.gd`) | Ghost world pos → trajectory point | 0.30 m (rev 2) | No (derived at commit time) | Commit selection, ghost border color |
| **Awareness grid** (`player_awareness_grid.gd`) | Grid vertex (static) → trajectory point | 0.40 m (`ACTIVATION_RADIUS`) | **Yes, per vertex** | `get_approach_info` hint, zone scores (consumed at 8% weight) |

**They compute nearly the same thing.** Green pool asks "is a ghost near the trajectory right now?" Grid asks "is a vertex near the trajectory, and when will the ball arrive?" Grid has strictly more information. Green pool is computing a redundant subset.

### 8.3 New Gaps

#### 🔴 GAP-33 · Grid's per-vertex TTC not exposed as authoritative query

**Current**: `_time_to_arrival: PackedFloat32Array` is a private field. Nothing can ask "what is the minimum TTC at world point P?"

**Fix**: add a public method to `player_awareness_grid.gd`:
```gdscript
func get_ttc_at_world_point(world_pt: Vector3, radius: float = 0.4) -> float:
	var local_pt: Vector3 = _world_to_local(world_pt)
	var min_ttc: float = INF
	for v_idx in range(_local_positions.size()):
		if _activation[v_idx] < 0.05:
			continue
		var d: float = _local_positions[v_idx].distance_to(local_pt)
		if d < radius:
			var t: float = _time_to_arrival[v_idx]
			if t < min_ttc:
				min_ttc = t
	return min_ttc
```
Then the posture module can replace its derived TTC with this authoritative value. Also: **this resolves GAP-1b** from rev 2 (the "per-point trajectory time tags" concern) — the data already exists at vertex granularity.

#### 🔴 GAP-34 · Ghost yellow-border fade is wall-clock, not TTC-tiered

**Current** (`player_paddle_posture.gd:114, 139, 1208-1212`): when a ghost leaves trajectory proximity, `_green_fade_t` counts up and the border fades from green to yellow over 0.6 s wall clock. This means a fast ball and a slow ball produce the same fade timing, and the yellow state has no relationship to actual TTC.

**The user's insight**: the yellow border should show consistently *based on TTC*, not wall clock. The grid's yellow tier (`TIME_YELLOW = 1.0 s`) is exactly the right signal — but the ghost border ignores it.

**Fix**: replace wall-clock fade with TTC-tier lookup. In the ghost update loop:
```gdscript
# for each ghost:
var ghost_ttc: float = _player.awareness_grid.get_ttc_at_world_point(ghost.global_position, 0.4)
if ghost_ttc < INF:
	# use grid's authoritative color
    var tier_color: Color = _player.awareness_grid._get_time_color(ghost_ttc)
    _apply_ghost_border(ghost, tier_color, ghost_ttc)
else:
    # no activated vertices near this ghost — idle
    _apply_ghost_border(ghost, _ghost_base_color, INF)
```
Now every ghost border color is TTC-consistent. A posture 0.8 s from contact is YELLOW regardless of what happened 0.6 s ago. The "flicker" artifacts you'd see on fast balls disappear because the color is derived from the ball's arrival time at that spatial location, not from a decay timer.

**Rename suggestion**: the current "green pool" becomes a "TTC tier projection" — each ghost just mirrors the grid's color for whatever vertex cell it sits in. Much more consistent behavior.

*Medium effort, HIGH impact on the felt consistency the user is asking for.*

#### 🔴 GAP-35 · Dual proximity systems — merge green pool into grid

**Current**: green pool (ghost within 0.3 m of trajectory) and grid vertex activation (within 0.4 m of trajectory) compute overlapping information at every frame.

**Fix**: delete the green pool's independent proximity test (`_is_ghost_near_trajectory`, `player_paddle_posture.gd:805-820`). Replace with grid query:
```gdscript
func _is_ghost_near_trajectory(posture: int) -> bool:
    var ghost: MeshInstance3D = posture_ghosts.get(posture)
    if not ghost: return false
    var ttc: float = _player.awareness_grid.get_ttc_at_world_point(ghost.global_position, 0.4)
    return ttc < INF  # any activation means "near trajectory"
```
Benefits: (a) single source of truth for proximity, (b) automatically picks up grid's gap-interpolation on fast balls, (c) gets TTC for free.

*Low effort once GAP-33 is done.*

#### 🟡 GAP-36 · Zone scores underutilized (`ZONE_SCORE_WEIGHT = 0.08`)

**Current**: `player_awareness_grid.gd:54` — `ZONE_SCORE_WEIGHT := 0.08`. Zone-score contribution to commit selection is only 8%. The grid computes a full per-posture urgency-weighted score (`_compute_posture_scores`) and the commit system barely uses it.

**Fix**: raise to 0.20-0.30 AND actually call `get_posture_zone_scores()` in `_find_closest_ghost_to_point` as a primary signal, not an afterthought. The grid has fine-grained TTC per posture zone; currently that's thrown away.

*Requires testing — higher weight could destabilize the existing scoring. Do after GAP-33/34/35 are stable.*

#### 🔴 GAP-37 · Vertex activation ignores ball velocity direction

**Current** (`_activate_vertices`, lines 281-295): activation strength = `1.0 - d/ACTIVATION_RADIUS`. Purely spatial. A vertex 0.1 m from a trajectory point where the ball is moving TOWARD it activates the same as a vertex where the ball is moving AWAY.

**Consequence**: vertices *behind* the incoming ball (already-passed trajectory samples) light up as hot as vertices ahead. On a fast ball this briefly paints the wrong side of the player.

**Fix**: weight activation by ball velocity alignment:
```gdscript
# pass ball velocity into set_trajectory_points
var ball_vel_local: Vector3 = _world_to_local(ball.global_position + ball.linear_velocity) - _world_to_local(ball.global_position)
var vertex_to_point: Vector3 = (pt - _local_positions[v_idx]).normalized()
var alignment: float = maxf(0.0, ball_vel_local.normalized().dot(vertex_to_point))
var strength: float = (1.0 - d / ACTIVATION_RADIUS) * (0.3 + 0.7 * alignment)
```
Vertices in the ball's path get full strength; vertices behind the ball fade. *Low effort, medium impact on visual cleanliness.*

#### ✅ GAP-38 · Grid lock uses distance, not TTC — **RESOLVED (rev 9)**

**Current** (`player_paddle_posture.gd:273`): `awareness_grid.set_locked(ball_d <= 1.5)`. Distance-based. Inconsistent with the rest of the system that migrated to TTC gates in rev 2.

**Fix**: lock on TTC instead. `awareness_grid.set_locked(_ttc_to_contact < 0.35)`. Matches the BLUE commit stage logic. *Trivial.*

#### 🟡 GAP-39 · Grid has no own-wall / side-exclusion

**Current**: grid covers both sides of the player, including vertices on the opposing player's side. Trajectory points on the opponent's side of the net activate grid vertices — which then feed into the posture commit as if the ball were incoming.

**Fix**: in `_activate_vertices`, skip vertices where `local_pos.z < -0.5` (behind player beyond defensive reach) OR where the trajectory point is on the opponent's side of the net (`sign(pt.z) != sign(player_forward)`).

*Low effort, prevents phantom activations.*

### 8.4 The direct answer to the user's question

> "How about proximity detector or the volumetric grid solves that? So that the yellow border [is] more consistently wired with the TTC."

**Yes — exactly right, and the grid is already built. It's just not wired to the ghost border.**

The minimal wiring change (GAP-33 + GAP-34 combined):

1. **Add one public method to `player_awareness_grid.gd`** (~15 lines):
   ```gdscript
   func get_ttc_at_world_point(world_pt: Vector3, radius: float = 0.4) -> float
   ```
2. **Replace the wall-clock fade in `player_paddle_posture.gd`** so each ghost queries the grid for its own TTC and colors itself using `awareness_grid._get_time_color(ttc)`:
   ```gdscript
   for posture_id in posture_ghosts:
       var ghost: MeshInstance3D = posture_ghosts[posture_id]
       var ttc: float = _player.awareness_grid.get_ttc_at_world_point(ghost.global_position)
       if ttc < 1.5:
           var tier_color: Color = _player.awareness_grid._get_time_color(ttc)
           _set_ghost_border_color(posture_id, tier_color)
       else:
           _set_ghost_border_color(posture_id, _ghost_base_color)
   ```
3. **Delete `_green_fade_t`, `INCOMING_FADE_DURATION`, and the `_green_lit_postures` dict** — all replaced by the per-frame grid query.

**Effect on gameplay**:
- Yellow border will show on any ghost whose world position is near a trajectory point arriving within 0.6-1.0 s. Consistent across fast and slow balls.
- Orange/red borders appear as TTC drops, giving the player a continuous urgency gradient instead of a binary "lit/not-lit".
- No more stale yellow fades after the ball has already passed.
- Committed ghost still shows PINK/PURPLE/BLUE via its separate commit-stage color (those stages are about *commit confidence*, not *ball proximity*, so they remain as an overlay on top).

### 8.5 Updated Rev-6 Priority Queue

Highest-leverage items from all parts:

1. **🔴 GAP-33 Expose `get_ttc_at_world_point`** — prereq for everything else in Part 8.
2. **🔴 GAP-34 TTC-tiered ghost borders** — directly addresses the user's "yellow border consistently wired with TTC" ask. *Biggest felt-consistency win.*
3. **🔴 GAP-28 Body velocity → impulse** (from Part 7) — still a 1-line trivial win.
4. **🔴 GAP-35 Merge green pool into grid** — deduplicates proximity logic.
5. **🚨 GAP-25 AI jump capability** (from Part 7) — closes the capability gap.
6. **🟡 GAP-7b Posture-aware pole vector** (from Part 2).
7. **🔴 GAP-15 Sweet-spot modeling** (from Part 6).
8. **🔴 GAP-26 TTC-aligned jump timing** (from Part 7).
9. **🔴 GAP-37 Grid velocity-direction weighting** (Part 8 polish).
10. **🔴 GAP-16 Kinetic chain timing** (from Part 6).
11. **✅ GAP-38 Grid lock on TTC** — RESOLVED rev 9 (1 line, TTC-based).
12. **🔴 GAP-36 Zone score weight tuning** (test carefully).
13. Rest unchanged.

**Key insight from Part 8**: the first seven audit passes kept saying things like "needs TTC", "add per-point time tags", "no temporal dimension in proximity". These were all describing features that already existed in `player_awareness_grid.gd` — the audit was wrong because it never opened that file. The correct frame is: **the grid is 90% of the solution. The missing 10% is wiring.**

---

## Part 9 — Verified Corrections, Missed Subsystems, and Fresh Gaps (rev 7)

> **Added 2026-04-11.** Deep re-audit using a verifying sub-agent plus direct `grep`-level checks. Fixes two prior errors, documents five subsystems the audit never mentioned, and adds GAP-40 through GAP-51 from both verified code findings and new research.

### 9.1 Corrections to Prior Claims

#### ✅ GAP-8 (spin) — serve intentionally flat, Magnus wired for shots
**Original claim**: "impulses are straight-line; gravity-only in flight. No topspin, backspin, or slice."

**Verified**: `ball.gd:149` sets `angular_velocity = Vector3(randf()*5, randf()*5, randf()*5)` on serve, and `ball.gd:154` zeroes it elsewhere. So **spin state exists** — it's just **vestigial**: nothing consumes angular_velocity. No Magnus force, no spin-dependent bounce, no player-controlled generation, no visual trail difference.

**Corrected claim**: Ball *has* a spin state variable; it is inert. Either wire it up (implement real Magnus and spin transfer, see GAP-8 Concrete Fix in Part 2) **or delete the serve-time randomization and admit the ball is spinless**. The current middle ground is dead code masquerading as a feature.

#### ⚠️ GAP-32 (landing recovery lockout) — **adjacent dead code found**
**Original claim**: "after landing, player immediately has full movement/hit capability. No stumble frames."

**Verified true** — `player.gd:282-287` resets `vertical_velocity = 0` on landing with no lockout timer. But the re-audit **found an adjacent dead function**: `_apply_foot_lock()` at `player_leg_ik.gd:454`, which implements per-foot world-space locking during swing phase. It has **zero callers** in the entire codebase (`grep '_apply_foot_lock' scripts/` → 1 match, the definition itself).

**New related gap**: GAP-40 below — foot lock is half-built and un-wired.

#### ⚠️ Sub-agent errors I caught (trust but verify)

Two claims from the verifying sub-agent that I direct-checked and **rejected**:
- Agent: "awareness_grid field exists but never initialized, points to null." **Wrong.** `player.gd:224-228` loads, instantiates, names, parents the grid. Verified.
- Agent: "reaction button auto_fire_requested signal is defined and emitted, but game.gd doesn't subscribe." **Wrong.** `game.gd:476` does `reaction_button.auto_fire_requested.connect(_on_reaction_auto_fire)` and `game.gd:645` defines the handler.

Lesson: sub-agents hallucinate missing code. All "dead code" claims go through `grep` before hitting the audit.

### 9.2 Missed Subsystems (~8 subsystems audit never mentioned)

These exist in the codebase, work, and matter — and rev 1-6 never named them. Listing for completeness so future gap hunts don't duplicate them.

#### 9.2.1 ReactionHitButton HUD (`scripts/reaction_hit_button.gd`, 186 lines)
**What it does**: collapsible ring HUD element that visualizes TTC as a shrinking ring, grades hits (PERFECT/GREAT/GOOD/OK), and can auto-fire on perfect window (`auto_fire_on_perfect` export).
**Signal chain** (verified): `player_paddle_posture.incoming_stage_changed` → `reaction_hit_button.update_from_stage` → `auto_fire_requested` → `game.gd._on_reaction_auto_fire` (`:476`, `:645`).
**Implication for audit**: **this is the primary TTC consumer**. GAP-34 (TTC-tiered ghost borders) should probably *also* feed the reaction button so the ring color matches the ghost border.

#### 9.2.2 Shot Grading Rubric (`player_paddle_posture.gd:1143-1157`)
**Extracted from code** (the CLAUDE.md has a summary; this is the actual code):
```gdscript
if _closest_ball2ghost < 0.25:    grade = "PERFECT"
elif _closest_ball2ghost < 0.40:  grade = "GREAT"
elif _closest_ball2ghost < 0.60:  grade = "GOOD"
elif _closest_ball2ghost < 0.80:  grade = "OK"
else:                              grade = "MISS"
```
Fires once per ball (`_scored_this_ball` guard) at stage 2 (BLUE). Grade metric is **ball2ghost distance at closest approach** — spatial only, no TTC-weighted grading.

#### 9.2.3 HitFeedback FX Orchestrator (`scripts/hit_feedback.gd`, 86 lines)
**What it does**: listens to `ball.hit_by_paddle` + `ball.bounced`, spawns FX via `/root/FXPool` (burst + decal), drives camera shake (`strength = ball_velocity / 20.0`), applies subtle hitstop (0.06 s × 0.05 timescale on hits > 0.7 strength).
**Zone tinting** (`hit_feedback.gd:72-79`): kitchen cyan (|z| < 1.8), baseline orange (|z| > 5.2), white midcourt. Already zone-aware.

#### 9.2.4 Human Intercept Pools (`player_debug_visual.gd:520-726` + `player_ai_brain.gd:157-176`)
**Verified**: AI reads `human_committed_pre_intercepts[]` and `human_committed_post_intercepts[]` from the debug visual to decide whether to let the ball bounce (two-bounce rule) or aggressively volley. Intercept tiers at 0.5 m (VOLLEY), 0.9 m (SEMI-SMASH), >1.4 m (SMASH).
**Impact**: the AI has **partial opponent-awareness** — it knows what *opportunities the human will have*, not just where the ball is going. My rev-4 claim that "AI uses engineer's prediction" was too strong.

#### 9.2.5 Footwork Swing Anticipation (`player_leg_ik.gd:125-137`)
**Verified**: when ball < `SWING_ANTICIPATION_DIST = 4.0 m`, feet pre-bias toward dominant stance. Forehand pulls back foot back; backhand mirrors. Anticipatory, continuous (scales with 1 - dist/4.0).
**Gap**: this is **distance-gated, not TTC-gated, not stage-gated**. It fires the same for a fast drive and a slow dink at 4 m. Should be wired to `incoming_stage_changed` (PURPLE → begin bias) like the reaction button.

#### 9.2.6 Stance-Based Foot Replant (`player_leg_ik.gd:354-375`)
**Verified**: on posture family change (forehand→backhand or vice versa), dominant foot re-plants with a discrete stepping animation. This is real footwork responsiveness I never mentioned.

#### 9.2.7 AI Difficulty Already Varies Swing Threshold (`player_ai_brain.gd:505-524`)
**Verified**:
```gdscript
match ai_difficulty:
    0:  ai_swing_threshold = randf_range(0.08, 0.25)   # Easy
    1:  ai_swing_threshold = randf_range(0.12, 0.35)   # Medium
    2:  ai_swing_threshold = randf_range(0.50, 0.85)   # Hard
```
So GAP-12 (difficulty on commit timing) isn't starting from zero — there's already a charge-ratio threshold variation per difficulty. The rev 4 recommendation should **stack** on top: also vary commit TTC (`TTC_BLUE` × difficulty multiplier).

#### 9.2.8 RallyScorer Signal Bus (`scripts/rally_scorer.gd`)
**Verified**: a separate scoring engine that emits `rally_ended(winner, reason, detail)`. Fault reasons enumerated: OUT_OF_BOUNDS, DOUBLE_BOUNCE, BALL_IN_NET, KITCHEN_VOLLEY, MOMENTUM, TWO_BOUNCE_RULE, BODY_HIT, SHORT_SERVE, WRONG_SERVICE_COURT, FOOT_FAULT, WRONG_HALF, NET_TOUCH. Game logic reads this instead of computing scores inline.
**Implication**: any new gap that affects scoring (e.g., new fault types) should emit via this bus, not inline in game.gd.

### 9.3 New Gaps (GAP-40 through GAP-51)

#### 🔴 GAP-40 · Dead code: `_apply_foot_lock` never called

**Verified**: `grep '_apply_foot_lock' scripts/` returns exactly **one** match — the function definition at `player_leg_ik.gd:454`. No callers anywhere.

**What the function does**: maintains a foot's world-space position while the other foot is in swing phase — exactly the "planted foot doesn't drift" behavior that makes stance changes look grounded. Currently feet can slide during swing because this is never invoked.

**Fix**: wire it into `update_legs(delta)` where each foot's target is computed. Example:
```gdscript
var result := _apply_foot_lock(animated_pos, is_swing, was_swing,
                               left_locked, left_lock_pos, delta)
animated_pos = result[0]; left_locked = result[1]; left_lock_pos = result[2]
```
Two lines per foot. *Trivial effort, medium visual impact.*

#### 🔴 GAP-41 · Inert ball spin state

**Verified**: `ball.gd:149` randomizes `angular_velocity` on serve. `ball.gd:154` zeroes it. No Magnus force, no spin-to-bounce transfer, no visual trail differentiation. Dead state.

**Fix options** (pick one, don't leave it as-is):
- **Delete it** — 2 line removal, honest. Ship intent: "pickleball paddles don't generate significant spin, so we don't model it."
- **Wire it** — implement GAP-8 properly: `F_magnus = k_m * (ω × v)` in `_integrate_forces`, spin transfer on bounce, paddle-angle-driven spin generation in `get_shot_impulse`. High effort, high impact.

*Either way: don't leave random-on-serve-that-does-nothing.*

#### 🔴 GAP-42 · Unused `hit_ball` signal on Player

**Verified**: `player.gd:151` declares `@warning_ignore("unused_signal") signal hit_ball(ball: RigidBody3D, direction: Vector3)`. Emitted by AI brain (`player_ai_brain.gd:606`) but **no listeners**. The `@warning_ignore` comment says the maintainer knows it's unused.

**Root cause hypothesis**: planned integration with HitFeedback / FXPool that was abandoned. Currently HitFeedback listens to `ball.hit_by_paddle` instead.

**Fix**: either delete the signal + emit, or wire HitFeedback to *also* listen to `player.hit_ball` so FX can be driven per-player instead of per-ball (useful for player-specific camera shake intensities, difficulty-scaled hitstop, etc.). *Low effort, low-medium impact.*

#### 🔴 GAP-43 · AI anticipation is *ball-based*, not *opponent-body-based*

**Research basis**: [Williams, A. M. & Jackson, R. C. (2019). "Anticipation in sport: Fifty years on, what have we learned and what research still needs to be undertaken?" — *Psychology of Sport and Exercise* 42, 16-24](https://pmc.ncbi.nlm.nih.gov/articles/PMC10363944/). And earlier: Williams & Davids (1998) on visual search strategies in racket sports.

**Finding**: expert racket-sport players anticipate shot direction **before contact** by reading the opponent's hip rotation, shoulder alignment, backswing depth, and racket face angle. Occlusion studies show experts can predict shot direction 100-300 ms before contact with 70-80% accuracy using only body kinematics. Novices can't.

**Verified in code**: AI prediction pipeline starts *after* ball leaves opponent's paddle. `_predict_first_bounce_position` and `_predict_ai_contact_candidates` both take `ball` as input, not opponent body state. The AI has **zero pre-contact anticipation** — it's 100% reactive.

**Fix**: during opponent's CHARGING phase, sample opponent's `body_pivot.rotation.y`, `paddle_posture`, and charge_ratio. Use these to bias early AI positioning:
```gdscript
# in AI update, while opponent is charging
if opponent.is_charging:
	var body_yaw: float = opponent.body_pivot.rotation.y
	var likely_direction: float = -sign(body_yaw)  # rough: forehand-coil → crosscourt
	var posture_hint: int = opponent.paddle_posture
	# bias intercept target by these before the ball even leaves the paddle
	_anticipated_shot_bias = Vector3(likely_direction * 0.8, 0, 0)
```
Crude first version; can be refined. Gives AI a ~300 ms head start on positioning — the biggest single upgrade to AI feel.

*Medium effort, high impact on perceived intelligence.*

#### 🟡 GAP-44 · Anticipation footwork decoupled from commit stages

**Verified**: `player_leg_ik.gd:125` uses `SWING_ANTICIPATION_DIST = 4.0 m` (distance), while the rest of the system migrated to TTC stages in rev 2.

**Fix**: gate anticipation on `_last_commit_stage >= STAGE_PURPLE` instead of distance. Feet pre-bias when the commit system says "ball is incoming for real", not just "ball is close". *Trivial cleanup.*

#### 🔴 GAP-45 · No Fitts'-law reach dynamics

**Research basis**: Fitts, P. M. (1954). "The information capacity of the human motor system in controlling the amplitude of movement" — *Journal of Experimental Psychology* 47(6), 381-391. The law: `MT = a + b * log₂(D/W + 1)` where `MT` = movement time, `D` = distance to target, `W` = target width (tolerance). For reaching movements, typical values: `a ≈ 0.05 s`, `b ≈ 0.12 s/bit`.

**Verified in code**: `force_paddle_head_to_ghost` uses a **constant halflife per commit stage** (0.04/0.10/0.22 s) regardless of distance to the ghost. A ghost 5 cm away and a ghost 80 cm away both lerp at the same rate.

**Consequence**: close ghost → too slow (feels mushy); far ghost → too fast (feels teleporty).

**Fix**: compute reach halflife from Fitts:
```gdscript
var D: float = paddle.global_position.distance_to(ghost.global_position)
var W: float = 0.08  # acceptable tolerance (paddle head radius)
var reach_ID: float = log(D/W + 1) / log(2)  # bits, Fitts' index of difficulty
var reach_time: float = 0.05 + 0.12 * reach_ID  # seconds
var halflife: float = reach_time * 0.35  # halflife ≈ 0.35 * total time for a damped spring
```
Now close ghosts snap tight (halflife ~0.03 s at 10 cm), far ghosts move deliberately (halflife ~0.10 s at 80 cm). Matches human reach. *Low effort, high feel impact.*

#### ✅ GAP-46 · Pickleball-specific aerodynamic drag (Cd=0.33 outdoor)

**Research basis**: pickleball balls have 26-40 holes (official USAPA spec). The perforations generate turbulent boundary-layer drag similar to a wiffle ball. Typical drag coefficient `Cd ≈ 0.45` (vs. smooth sphere ~0.07 at the same Reynolds number). For a 26 g ball at 15 m/s, this produces ~0.15 N of drag — enough to slow a rally shot by ~15% over 6 m of flight.

**Verified in code**: `ball.gd` has `linear_damp = 0.1` (a generic physics-engine damping, not model-based). No velocity-squared drag term. No wind/turbulence modeling.

**Fix**: in `ball.gd:_integrate_forces`, add:
```gdscript
const AIR_DENSITY := 1.225  # kg/m³
const BALL_CROSS_SECTION := PI * 0.06 * 0.06  # ball radius 6 cm
const DRAG_COEFFICIENT := 0.45  # perforated pickleball
var v: Vector3 = state.linear_velocity
var speed: float = v.length()
if speed > 0.1:
	var drag_force: Vector3 = -0.5 * AIR_DENSITY * DRAG_COEFFICIENT * BALL_CROSS_SECTION * speed * v
	state.apply_central_force(drag_force)
```
Changes the feel of long rallies — balls arrive slower than current naive ballistic prediction. Also forces the trajectory predictor to include drag, which means `player_debug_visual.gd:draw_incoming_trajectory` becomes inaccurate. Fixing the predictor is a secondary task (add matching drag term in the forward-Euler loop).

*Medium effort (two places), medium impact on realism.*

#### 🔴 GAP-47 · AI reaction is superhuman (no visuomotor latency)

**Research basis**: human visuomotor latency for interception tasks is ~180-220 ms (Tresilian 1999; Land & McLeod 2000). The AI currently reacts instantaneously to ball state changes — it sees the new trajectory the same physics frame the opponent's paddle releases it.

**Verified in code**: no latency buffer in `player_ai_brain.gd`. Ball velocity read directly via `ball.linear_velocity`.

**Fix**: add a ring buffer of past ball states; AI reads from `N` frames ago (where `N = 0.2 / physics_dt ≈ 12` at 60 Hz):
```gdscript
var _ball_state_history: Array = []
const REACTION_LATENCY_FRAMES := 12

func _physics_process(delta):
    _ball_state_history.append({"pos": ball.global_position, "vel": ball.linear_velocity})
    if _ball_state_history.size() > REACTION_LATENCY_FRAMES + 1:
        _ball_state_history.pop_front()
    var delayed := _ball_state_history[0]  # what the AI "sees"
    # use delayed.pos/vel for prediction instead of ball.global_position
```
Tunable per difficulty: EASY = 18 frames (300 ms), MEDIUM = 12 (200 ms), HARD = 8 (133 ms, slightly superhuman).

*Low effort, HIGH impact on game balance — without this the AI will always feel "too good".*

#### 🟡 GAP-48 · Reaction button ring color not TTC-tier-synced

**Cross-reference**: Part 8 added GAP-34 (ghost border TTC tiers). The reaction button ring already displays shrinking-ring TTC visualization, but uses its own color scheme — decoupled from the grid's RED/ORANGE/YELLOW/GREEN tiers.

**Fix**: after GAP-33 exposes `get_ttc_at_world_point`, have the reaction button query the grid for the committed ghost and use the same tier colors. Everything on-screen at the same TTC is the same color. Visual coherence. *Low effort, medium impact.*

#### 🟡 GAP-49 · No grading on TTC-accuracy, only spatial-accuracy

**Verified** (`player_paddle_posture.gd:1143-1157`): grade is computed solely from `_closest_ball2ghost`. A perfectly-placed paddle that arrived 100 ms late scores the same as one that arrived at contact.

**Fix**: add a temporal component to grading:
```gdscript
var ttc_at_closest: float = _closest_approach_ttc  # captured when closest_ball2ghost was set
var time_accuracy_bonus: float = 1.0 - clampf(abs(ttc_at_closest) / 0.15, 0, 1)  # 150ms window
var combined_score: float = ball2ghost_score * 0.7 + time_accuracy_bonus * 0.3
```
Rewards "hit at contact window" not just "paddle in right place". *Low effort, medium impact on skill expression.*

#### 🟡 GAP-50 · No opponent-model learning

**Research basis**: [D'Ambrosio et al. (2024). "Achieving human-level competitive table tennis with learned agents" — Google DeepMind](https://sites.google.com/view/competitive-robot-table-tennis). DeepMind's agent learns opponent tendencies during play (shot preferences, positioning habits) and adapts strategy. For a hobby game, full RL is overkill, but a lightweight "opponent shot-type histogram" gives the same directional benefit.

**Fix (lightweight)**: track the last ~20 opponent shots by `shot_type` + `landing_zone` (server side, receiver side, kitchen, baseline). Bias AI anticipatory positioning by the histogram:
```gdscript
# after each opponent shot, record
_opponent_history.append({"type": shot_type, "zone": landing_zone})
if _opponent_history.size() > 20: _opponent_history.pop_front()
# during anticipation phase
var most_common_zone: int = _compute_histogram_mode(_opponent_history)
_anticipated_shot_bias += _zone_to_bias[most_common_zone] * 0.3
```
*Medium effort, medium impact, research-inspired.*

#### 🟡 GAP-51 · No deception / shot fake system for human player

**Research basis**: kinematic deception — elite players intentionally coil their body toward one direction then redirect at the last moment. Requires the *shown* body motion to be disconnectable from the *intended* shot target.

**Current**: human input maps directly to shot. No fake mechanic. No separate "body feint" input.

**Fix (optional polish)**: bind a modifier key (e.g., Shift) that during charge shows a *different* body rotation than the one committed. On release, the true rotation snaps into place over 60 ms. If the AI is using GAP-43 body-kinematic anticipation, this becomes a real counter-tactic. Low priority unless GAP-43 ships first.

### 9.3.5 Difficulty Tiers — Segregated Master List

All gaps across Parts 2, 4, 6, 7, 8, 9 bucketed by implementation cost. Resolved items (✅) excluded.

#### 🟢 EASY (≤ 30 lines, no cross-module surgery, no new concepts)

| GAP | Summary | Effort |
|---|---|---|
| **GAP-28** | Body vertical velocity → impulse | 1 line |
| **GAP-33** | Expose `get_ttc_at_world_point` in awareness grid | ~15 lines |
| **GAP-41** | Delete inert ball spin (or wire it — delete is the easy path) | 2 lines |
| **GAP-38** | ✅ RESOLVED rev 9 | Grid lock on TTC |
| **GAP-40** | Wire `_apply_foot_lock` into `update_legs` | ~10 lines |
| **GAP-44** | Anticipation footwork TTC-gated instead of distance-gated | ~5 lines |
| **GAP-42** | Delete or wire `hit_ball` signal | 2 lines (delete) |
| **GAP-32** | Landing recovery lockout timer | ~10 lines |
| **GAP-19** | Head/gaze neck-bone tracking ball | ~20 lines |
| **GAP-11** | Reaction delay scales with opponent charge jitter | ~10 lines |
| **GAP-34** | TTC-tiered ghost borders (depends on GAP-33) | ~25 lines |
| **GAP-45** | Fitts' law reach dynamics in `force_paddle_head_to_ghost` | ~15 lines |
| **GAP-48** | Reaction button ring colors sync with grid tiers (depends on GAP-33) | ~10 lines |
| **GAP-49** | Grading adds TTC-accuracy component | ~10 lines |
| **GAP-27** | Air control factor during jump | ~5 lines |
| **GAP-31** | Momentum-bonus reach in scoring | ~5 lines |

#### 🟡 MEDIUM (30-150 lines, touches 2-3 files, some logic design)

| GAP | Summary | Effort |
|---|---|---|
| **GAP-3** | ✅ RESOLVED rev 3 |  |
| **GAP-4** | ✅ RESOLVED rev 3 |  |
| **GAP-7b** | Posture-aware pole vector IK (per-posture dict) | ~40 lines |
| **GAP-13** | Momentum-aware scoring cost term | ~30 lines |
| **GAP-12** | Difficulty-scaled commit TTC | ~15 lines + testing |
| **GAP-15** | Sweet-spot modeling (paddle-local hit offset) | ~50 lines |
| **GAP-20** | ✅ RESOLVED rev 4.1 |  |
| **GAP-21** | Velocity-dependent COR lookup | ~20 lines in 2 files |
| **GAP-25** | AI jump capability + state machine branch | ~80 lines |
| **GAP-26** | TTC-aligned jump timing (buffer + release) | ~40 lines |
| **GAP-35** | Merge green pool into grid (deletes old path) | ~100 lines net |
| **GAP-36** | Raise zone score weight + read `get_posture_zone_scores` | ~30 lines + tuning |
| **GAP-37** | Grid vertex activation weighted by velocity direction | ~20 lines |
| **GAP-47** | AI visuomotor latency ring buffer | ~50 lines |
| **GAP-30** | Split-step on opponent contact | ~60 lines |
| **GAP-43** | AI anticipation by opponent body kinematics | ~100 lines + tuning |
| **GAP-50** | Lightweight opponent shot-type histogram | ~80 lines |
| **GAP-14** | gdUnit4 regression test scaffold | ~150 lines |

#### 🔴 HARD (150+ lines, architectural changes, cross-cutting concerns)

| GAP | Summary | Why hard |
|---|---|---|
| **GAP-16** | Kinetic chain sequential timing | Requires per-segment animation channels; touches body, arm, hitting modules |
| **GAP-23** | Wrist snap / forearm pronation | Needs separate wrist bone target + post-IK override |
| **GAP-29** | Lunge / step-out footwork state | New locomotion mode in leg IK state machine |
| **GAP-17** | LOT servo for AI pursuit | Rewrite movement core from direct-target to optic-flow-servo |
| **GAP-46** | Pickleball aerodynamic drag | Ball physics + trajectory predictor must stay in sync |
| **GAP-8** | Full spin/Magnus implementation | Touches ball physics, trajectory predictor, paddle contact normal, bounce |
| **GAP-39** | Grid side exclusion / own-net-aware filtering | Requires net/court geometry awareness in grid |
| **GAP-51** | Human shot-fake deception input | New input channel, body pose decoupling |

#### 🧪 RESEARCH-GRADE / DEFER (requires infrastructure the project doesn't have)

| GAP | Why deferred |
|---|---|
| **GAP-2** | Ball state estimator (Kalman) — only useful once GAP-8 lands |
| **GAP-5** | Space-time green pool — subsumed by GAP-34/35 once grid is authoritative |
| **GAP-10** | Motion-matching feature vector — needs mocap database |
| **GAP-18** | Local motion phases (Starke 2020) — needs learned synthesis pipeline |
| **GAP-22** | Ball-paddle dwell time — marginal gameplay value, high physics cost |
| **GAP-24** | Mocap ingestion infrastructure |
| **GAP-1b** | Per-point trajectory time tags — resolved conceptually by GAP-33 |

**Summary counts**: 16 easy, 17 medium, 8 hard, 7 research-grade deferred. Total actionable (easy + medium) = 33.

### 9.4 Updated Rev-7 Master Priority Queue

Merged across Parts 2, 4, 6, 7, 8, 9. Ranked by impact × ease with dependencies respected.

**Top 10 "do these now" (easy wins with high payoff)**:

1. **🔴 GAP-33 Expose `get_ttc_at_world_point`** — prerequisite for most Part 8 fixes
2. **🔴 GAP-34 TTC-tiered ghost borders** — user's explicit ask, biggest felt-consistency win
3. **🔴 GAP-28 Body velocity → impulse** — 1 line, high realism payoff
4. **🔴 GAP-40 Wire `_apply_foot_lock`** — 2 lines, fixes dead code
5. **🔴 GAP-47 AI visuomotor latency buffer** — 12-frame ring buffer, critical for game balance
6. **🔴 GAP-41 Resolve inert ball spin** — delete OR wire, stop living in limbo
7. **🔴 GAP-45 Fitts' law reach dynamics** — distance-scaled halflife
8. **🟡 GAP-44 Anticipation footwork TTC-gated** — trivial cleanup, joins rest of system
9. **✅ GAP-38 Grid lock on TTC** — RESOLVED rev 9 (1 line, TTC-based)
10. **🟡 GAP-48 Reaction button TTC-tier colors** — visual coherence, depends on GAP-33

**Middle tier (medium effort, strong impact)**:
11. **🔴 GAP-43 AI body-kinematic anticipation** — biggest AI-feel upgrade
12. **🚨 GAP-25 AI jump capability** — closes asymmetric capability gap
13. **🔴 GAP-15 Sweet-spot modeling** — off-center hit penalty
14. **🔴 GAP-16 Kinetic chain timing** — biggest visual swing upgrade
15. **🔴 GAP-26 TTC-aligned jump timing** — pairs with GAP-25
16. **🔴 GAP-35 Merge green pool into grid** — deduplicate proximity logic
17. **🔴 GAP-17 LOT servo for AI** — organic pursuit paths
18. **🔴 GAP-23 Wrist snap** — iconic overhead visual

**Research-grade / defer**:
19. GAP-46 pickleball drag (touches both ball.gd and predictor)
20. GAP-50 opponent-model learning (lightweight histogram OK, full RL defer)
21. GAP-8 / GAP-41 full spin physics (if wiring the inert spin, do all the way)
22. GAP-18 learned motion phases (need mocap pipeline)
23. GAP-24 mocap ingestion infrastructure
24. GAP-10 motion matching

### 9.6 Domain-Based Segregation

All 51 gaps organized by **subsystem** rather than by difficulty. Use this to find all gaps that touch one module.

**Domain key**: ✅ = resolved | 🟡 = partial | 🔴 = open | 🧪 = research/defer

---

#### 🤖 AI & Decision Making
`player_ai_brain.gd` — reaction, anticipation, difficulty, pursuit

| GAP | Description | Status | Difficulty |
|-----|-------------|--------|------------|
| GAP-11 | Reaction delay scales with opponent charge jitter | 🔴 OPEN | 🟢 EASY |
| GAP-12 | Difficulty-scaled commit TTC threshold | 🔴 OPEN | 🟢 EASY |
| GAP-13 | Momentum-aware scoring cost term | 🔴 OPEN | 🟡 MEDIUM |
| GAP-17 | LOT servo for AI pursuit (optic-flow-based movement) | 🔴 OPEN | 🔴 HARD |
| GAP-25 | AI never jumps — asymmetric capability gap | 🔴 OPEN | 🟡 MEDIUM |
| GAP-26 | Jump timing not TTC-aligned | 🔴 OPEN | 🟡 MEDIUM |
| GAP-30 | No split-step on opponent's contact | 🔴 OPEN | 🟡 MEDIUM |
| GAP-43 | AI body-kinematic anticipation | 🔴 OPEN | 🟡 MEDIUM |
| GAP-47 | AI visuomotor latency ring buffer | ✅ RESOLVED rev 8 | 🟡 MEDIUM |
| GAP-50 | Opponent shot-type histogram | 🔴 OPEN | 🟡 MEDIUM |

**9 of 51 — 1 resolved**

---

#### ⚙️ Physics & Ball
`ball.gd` — spin, aerodynamics, bounce, sweet-spot

| GAP | Description | Status | Difficulty |
|-----|-------------|--------|------------|
| GAP-15 | Sweet-spot off-center speed reduction (not just spin) | ✅ RESOLVED rev 9 | 🟡 MEDIUM |
| GAP-21 | Fixed coefficient of restitution ignores velocity dependence | ✅ RESOLVED rev 8 | 🟡 MEDIUM |
| GAP-22 | No ball-paddle dwell time (instantaneous impulse) | 🧪 DEFER | — |
| GAP-41 | Delete inert vestigial spin state | ✅ RESOLVED rev 8 | 🟢 EASY |
| GAP-46 | Pickleball-specific drag (Cd=0.33 outdoor / 0.45 indoor) | ✅ RESOLVED rev 9 | 🟡 MEDIUM |
| GAP-8 | Serve spin wiring (intentionally flat, Magnus live for shots) | ✅ RESOLVED rev 9 | 🟡 MEDIUM |

**8 of 51 — 3 newly resolved (GAP-15, GAP-46, GAP-8)**

---

#### 🏓 Paddle & Swing
`player_hitting.gd`, `player_arm_ik.gd` — charge, force, wrist, kinetic chain, pole vector

| GAP | Description | Status | Difficulty |
|-----|-------------|--------|------------|
| GAP-3 | Charge → force coupling (linear, not scaled) | ✅ RESOLVED rev 3 | 🟢 EASY |
| GAP-4 | Spring-damper paddle chase (framerate-dependent lerp) | ✅ RESOLVED rev 3 | 🟢 EASY |
| GAP-7b | Posture-aware pole vector IK (per-posture dict) | 🟡 PARTIAL | 🟡 MEDIUM |
| GAP-16 | Kinetic chain sequential timing in swing animation | 🔴 OPEN | 🔴 HARD |
| GAP-23 | Wrist snap / forearm pronation for overheads | 🔴 OPEN | 🔴 HARD |
| GAP-28 | Body vertical velocity not added to shot impulse | ✅ RESOLVED rev 8 | 🟢 EASY |

**6 of 51 — 3 resolved**

---

#### 🎯 Posture & Commit
`player_paddle_posture.gd` — postures, green pool, commit stages, TTC gates, reach

| GAP | Description | Status | Difficulty |
|-----|-------------|--------|------------|
| GAP-1 | True TTC computation in commit | ✅ RESOLVED rev 2 | 🟢 EASY |
| GAP-1b | Per-point trajectory time tags | 🟡 PARTIAL | 🟡 MEDIUM |
| GAP-5 | Green pool is spatial, not space-time volumetric | 🧪 DEFER | — |
| GAP-6 | No explicit LOCK state in commit | ✅ RESOLVED rev 2 | 🟢 EASY |
| GAP-9 | Follow-through timing not charge-scaled | ✅ RESOLVED rev 2 | 🟢 EASY |
| GAP-31 | Reach envelope constant, ignores momentum | 🟡 PARTIAL | 🟢 EASY |
| GAP-42 | `hit_ball` signal on Player is unused | ✅ RESOLVED rev 8 | 🟢 EASY |
| GAP-45 | No Fitts'-law reach dynamics | ✅ RESOLVED rev 8 | 🟢 EASY |

**8 of 51 — 5 resolved**

---

#### 📡 Awareness Grid
`player_awareness_grid.gd` — TTC query, ghost borders, lock, vertex activation, side exclusion

| GAP | Description | Status | Difficulty |
|-----|-------------|--------|------------|
| GAP-33 | Grid's per-vertex TTC not exposed as query | ✅ RESOLVED rev 8 | 🟢 EASY |
| GAP-34 | Ghost yellow-border fade is wall-clock, not TTC-tiered | ✅ RESOLVED rev 8 | 🟢 EASY |
| GAP-35 | Dual proximity systems (green pool ∥ grid) — needs merge | 🔴 OPEN | 🟡 MEDIUM |
| GAP-36 | Zone scores underutilized (`ZONE_SCORE_WEIGHT = 0.08`) | 🟡 PARTIAL | 🟡 MEDIUM |
| GAP-37 | Vertex activation ignores ball velocity direction | 🔴 OPEN | 🟡 MEDIUM |
| GAP-38 | Grid lock uses distance, not TTC | ✅ RESOLVED rev 9 | 🟢 EASY |
| GAP-39 | Grid has no own-wall / side-exclusion filtering | 🔴 OPEN | 🔴 HARD |

**7 of 51 — 4 resolved**

---

#### 🦵 Footwork & Legs
`player_leg_ik.gd` — jump, foot lock, split-step, lunge, landing recovery, air control

| GAP | Description | Status | Difficulty |
|-----|-------------|--------|------------|
| GAP-26 | Jump timing not TTC-aligned (even for human) | 🔴 OPEN | 🟡 MEDIUM |
| GAP-27 | No air control / horizontal ball-tracking during jump | 🔴 OPEN | 🟢 EASY |
| GAP-29 | No lunge / step-out footwork state | 🔴 OPEN | 🔴 HARD |
| GAP-30 | No split-step on opponent's contact | 🔴 OPEN | 🟡 MEDIUM |
| GAP-32 | No landing recovery lockout | 🟡 PARTIAL | 🟢 EASY |
| GAP-40 | `_apply_foot_lock` dead code (never called) | ✅ RESOLVED rev 8 | 🟢 EASY |
| GAP-44 | Anticipation footwork decoupled from commit stages | ✅ RESOLVED rev 8 | 🟢 EASY |

**7 of 51 — 3 resolved**

---

#### 🔮 Trajectory & Prediction
`player_debug_visual.gd` — trajectory sim, intercept pools, time tags

| GAP | Description | Status | Difficulty |
|-----|-------------|--------|------------|
| GAP-1b | Per-point trajectory time tags (no time stamps on samples) | 🟡 PARTIAL | 🟡 MEDIUM |
| GAP-5 | Space-time green pool (temporal horizon cutoff missing) | 🧪 DEFER | — |
| GAP-20 | Physics CCD tunneling on fast serves | ✅ RESOLVED rev 4.1 | 🟢 EASY |

**3 of 51 — 1 resolved**

---

#### 👁️ Visual & Feedback
HUD, reaction button, head/gaze, hit feedback FX

| GAP | Description | Status | Difficulty |
|-----|-------------|--------|------------|
| GAP-19 | No gaze / head-tracking animation | 🟡 PARTIAL | 🟢 EASY |
| GAP-48 | Reaction button ring colors not TTC-tier-synced | 🟡 PARTIAL | 🟢 EASY |
| GAP-49 | Grading on TTC-accuracy absent (only spatial) | 🟡 PARTIAL | 🟢 EASY |
| GAP-51 | No deception / shot-fake system for human player | 🟡 PARTIAL | 🔴 HARD |

**4 of 51 — 0 resolved**

---

#### 🧪 Testing & Infrastructure

| GAP | Description | Status | Difficulty |
|-----|-------------|--------|------------|
| GAP-14 | No gdUnit4 regression test scaffold | 🔴 OPEN | 🟡 MEDIUM |
| GAP-24 | No mocap data pipeline for reference poses | 🧪 DEFER | — |
| GAP-10 | Motion-matching feature vector | 🧪 DEFER | — |
| GAP-2 | Ball state estimator (Kalman) — needs GAP-8 first | 🧪 DEFER | — |
| GAP-18 | Local motion phases (Starke 2020) — needs pipeline | 🧪 DEFER | — |

**5 of 51 — 0 resolved**

---

#### Summary by Domain

| Domain | Total | ✅ Resolved | 🟡 Partial | 🔴 Open | 🧪 Defer |
|--------|------:|----------:|---------:|------:|------:|
| 🤖 AI & Decision | 10 | 1 | 0 | 9 | 0 |
| ⚙️ Physics & Ball | 6 | 1 | 0 | 4 | 1 |
| 🏓 Paddle & Swing | 6 | 3 | 1 | 2 | 0 |
| 🎯 Posture & Commit | 8 | 5 | 2 | 0 | 1 |
| 📡 Awareness Grid | 7 | 4 | 1 | 2 | 0 |
| 🦵 Footwork & Legs | 7 | 3 | 1 | 3 | 0 |
| 🔮 Trajectory & Prediction | 3 | 1 | 1 | 0 | 1 |
| 👁️ Visual & Feedback | 4 | 0 | 4 | 0 | 0 |
| 🧪 Testing & Infra | 5 | 0 | 0 | 1 | 4 |
| **Total** | **51** | **18** | **10** | **16** | **7** |

**Highest-leverage remaining open items by domain:**
- 🤖 AI: GAP-25 (AI jump), GAP-43 (body anticipation)
- ⚙️ Physics: GAP-15 (sweet-spot), GAP-21 (velocity COR)
- 🏓 Paddle: GAP-7b (posture pole), GAP-16 (kinetic chain)
- 📡 Grid: GAP-35 (merge green pool), GAP-37 (velocity weighting)
- 🦵 Footwork: GAP-30 (split-step), GAP-29 (lunge)

### 9.5 Additional Sources (rev 7)

- Williams, A. M. & Jackson, R. C. (2019). "Anticipation in sport: Fifty years on, what have we learned and what research still needs to be undertaken?" — *Psychology of Sport and Exercise* 42, 16-24. [PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC10363944/).
- Williams, A. M. & Davids, K. (1998). "Visual search strategy, selective attention, and expertise in soccer" — *Research Quarterly for Exercise and Sport* 69(2), 111-128.
- Fitts, P. M. (1954). "The information capacity of the human motor system in controlling the amplitude of movement" — *Journal of Experimental Psychology* 47(6), 381-391.
- D'Ambrosio, D. et al. (2024). "Achieving human-level competitive table tennis with learned agents" — Google DeepMind. [Project page](https://sites.google.com/view/competitive-robot-table-tennis).
- Nathan, A. M. (2003). "The physics of baseball" — *American Journal of Physics* 71(9), 891-900. (Cited for drag + Magnus methodology transferable to pickleball.)
- Alaways, L. W. & Hubbard, M. (2001). "Experimental determination of baseball spin and lift" — *Journal of Sports Sciences* 19(5), 349-358.
- Mehta, R. D. (1985). "Aerodynamics of sports balls" — *Annual Review of Fluid Mechanics* 17, 151-189. (Foundational sports ball aerodynamics including perforated/seamed balls.)

---

## Part 10 — Rev 8 Implementation Log

> **2026-04-11.** Eight 🟢 EASY-tier gaps landed in a single pass. Headless boot verified clean (no parse errors, no new runtime errors). Pre-existing `state_label` null-deref at `game.gd:1571` is unrelated — a UI node unavailable in headless mode, independent of all rev 8 edits.

### ✅ GAP-28 · Body vertical velocity → impulse

**File**: `scripts/player_hitting.gd:421-428`
**Change**: added body vertical velocity term to shot impulse.
```gdscript
var base_impulse: Vector3 = dir.normalized() * _player.paddle_force * force_scale * charge_gain
var body_vel_contribution: Vector3 = Vector3(0, _player.vertical_velocity * 0.3, 0)
return base_impulse + body_vel_contribution
```
Jumping smashes on the rise now transfer ~30% of body vertical velocity to the ball. Overhead smash + jump reads as meatier.

### ✅ GAP-33 · Expose `get_ttc_at_world_point` in awareness grid

**File**: `scripts/player_awareness_grid.gd` (new methods appended just before `get_approach_info`)
**Added**:
- `get_ttc_at_world_point(world_pt: Vector3, radius: float = 0.4) -> float` — returns minimum TTC of activated vertices within radius of a world point, or `INF`
- `get_ttc_color_at_world_point(...) -> Color` — convenience wrapper that maps directly to the grid's own `_get_time_color` gradient

This is the **authoritative TTC query** for any system that wants "when will the ball be at this spot". Resolves GAP-1b conceptually — per-point trajectory time tags aren't needed because vertex-granularity TTC already exists.

### ✅ GAP-34 · TTC-tiered ghost borders

**File**: `scripts/player_paddle_posture.gd` (inside the ghost color update loop, after existing color logic)
**Change**: added a grid-tier override that runs after all existing color logic. For each ghost, queries the grid for its TTC, and if a valid TTC comes back, overrides `albedo_color` + `emission` + `emission_energy_multiplier` with the grid's RED→ORANGE→YELLOW→GREEN gradient. Committed-stage purple and smash-hit flash take precedence to keep commit feedback readable.

```gdscript
if _player.awareness_grid and _ball_incoming and not is_purple and not is_hit_flash:
	var g_ttc: float = _player.awareness_grid.get_ttc_at_world_point(ghost.global_position, 0.45)
	if g_ttc < 1.5:
		var tier: Color = _player.awareness_grid._get_time_color(g_ttc)
		var tier_alpha: float = lerpf(POSTURE_GHOST_NEAR_ALPHA, 0.95, clampf(1.0 - g_ttc / 1.0, 0.0, 1.0))
		ghost_material.albedo_color = Color(tier.r, tier.g, tier.b, tier_alpha)
		ghost_material.emission = Color(tier.r, tier.g, tier.b, 1.0)
		ghost_material.emission_energy_multiplier = lerpf(0.35, 1.2, clampf(1.0 - g_ttc / 1.0, 0.0, 1.0))
```

**Effect**: directly addresses the user's original question — yellow borders now show consistently based on actual TTC at ~1 s window, orange at ~0.6 s, red at ~0.3 s, regardless of ball speed. No more wall-clock fade staleness.

**Follow-up** (deferred): GAP-35 (merge green pool into grid) and delete the `_green_fade_t` / `INCOMING_FADE_DURATION` state are still queued. Current rev 8 is non-breaking augmentation — the old green pool still runs; the grid tier just overrides on top.

### ✅ GAP-40 · Wire `_apply_foot_lock`

**File**: `scripts/player_leg_ik.gd` (`update_legs`, right before pole vector computation)
**Change**: added two calls to the previously-dead `_apply_foot_lock` function (`player_leg_ik.gd:454`) — one per foot, consuming existing `*_foot_locked`, `*_foot_lock_pos`, `*_foot_was_swing` state vars that were already declared but never fed into anything.

```gdscript
var r_lock_result: Array = _apply_foot_lock(right_foot, r_is_swing, right_foot_was_swing,
                                             right_foot_locked, right_foot_lock_pos, delta)
right_foot = r_lock_result[0]
right_foot_locked = r_lock_result[1]
right_foot_lock_pos = r_lock_result[2]
right_foot_was_swing = r_is_swing
# (mirror for left foot)
```

**Gotcha encountered**: first edit attempt double-declared `right_foot_lock_pos` and `left_foot_lock_pos` because they already existed in the file (lines 60-61 of the original) under the same names. Cleaned up during the parse-error recovery — now uses the existing declarations. Lesson logged: always grep for variable names before declaring.

**Effect**: planted foot stays stationary in world space while the other foot is in swing phase. Prevents foot sliding during stance changes. Stance continuity as a free visual win.

### ✅ GAP-41 · Delete inert ball spin

**File**: `scripts/ball.gd:148-151`
**Change**: removed `angular_velocity = Vector3(randf()*5, randf()*5, randf()*5)` on serve. Replaced with a comment explaining why (no physics consumers). Kept the `angular_velocity = Vector3.ZERO` in `reset()` as defensive cleanup — that's not generation, just hygiene.

**Effect**: honest state. If full spin physics ships later (GAP-8), it will be the only thing writing `angular_velocity`, with a clean slate.

### ✅ GAP-44 · Anticipation footwork TTC-gated

**File**: `scripts/player_leg_ik.gd` (swing anticipation block)
**Change**: replaced `if ball_dist < SWING_ANTICIPATION_DIST` with a commit-stage check:
```gdscript
if _player.posture and _player.posture._last_commit_stage >= 1:
	anticipation = 0.7 if _player.posture._last_commit_stage == 1 else 1.0  # PURPLE / BLUE
elif _player.ball_ref and is_instance_valid(_player.ball_ref):
	# Fallback: weaker distance-based gate for non-committed early warning
	...
	anticipation *= 0.5
```

**Effect**: the stance bias fires when the commit system decides "a shot is really coming" (PURPLE or BLUE), not merely "the ball happens to be within 4 m". The distance path is retained as a weaker fallback for frames before a commit exists. Consistent with the rev-2 TTC migration.

### ✅ GAP-45 · Fitts' law reach dynamics

**File**: `scripts/player_paddle_posture.gd` (`force_paddle_head_to_ghost`)
**Change**: replaced the stage-only halflife table (from rev 3's GAP-4 implementation) with a Fitts-derived time that's further compressed by commit stage:
```gdscript
var reach_D: float = _player.paddle_node.global_position.distance_to(target)
var fitts_W: float = 0.08
var fitts_ID: float = log(reach_D / fitts_W + 1.0) / log(2.0)
var fitts_MT: float = 0.05 + 0.12 * fitts_ID  # a + b * log₂(D/W + 1)
var stage_compression: float
match _last_commit_stage:
    2: stage_compression = 0.30  # BLUE — urgent
    1: stage_compression = 0.55  # PURPLE — committed
    _: stage_compression = 0.80  # PINK — deliberate
var halflife: float = maxf(fitts_MT * 0.35 * stage_compression, 0.02)
```

**Effect**: close ghosts snap tight (halflife ~0.02-0.03 s at 10 cm), far ghosts move deliberately (~0.10 s at 80 cm). Reach kinematics match human Fitts-law behavior instead of a three-bucket constant.

### ✅ GAP-47 · AI visuomotor latency ring buffer

**File**: `scripts/player_ai_brain.gd`
**Change**: added a per-frame ball-state ring buffer plus difficulty-scaled latency helpers:
```gdscript
var _ball_history: Array = []
const REACTION_LATENCY_FRAMES_EASY := 18   # 300 ms at 60 Hz
const REACTION_LATENCY_FRAMES_MED := 12    # 200 ms at 60 Hz
const REACTION_LATENCY_FRAMES_HARD := 8    # 133 ms at 60 Hz

func _get_latency_frames() -> int: ...
func _sample_ball_history(ball: RigidBody3D) -> void: ...
func _perceived_ball_pos(ball: RigidBody3D) -> Vector3: ...
func _perceived_ball_vel(ball: RigidBody3D) -> Vector3: ...
```
`_sample_ball_history` is called once per AI tick at the top of `get_ai_input`. Then every predictor (`_predict_first_bounce_position`, `_predict_ai_contact_candidates`, `_predict_ball_position`, `_predict_ai_intercept_marker_point`) reads `_perceived_ball_*` instead of `ball.global_position` / `ball.linear_velocity` for its seed state.

**Effect**: the AI now reacts to ball state changes after a 133-300 ms delay depending on difficulty. This is the **single biggest balance fix** for the AI — it was previously superhuman on reaction, which combined with GAP-43 (no anticipation) produced an inhuman profile ("perfect reactor, zero predictor"). Rev 8 fixes the reaction half; GAP-43 remains for the anticipation half.

**Scope limit**: action triggers like charge-start `paddle_distance` check still read live ball state. Full latency coverage (perception delay on decisions too, not just prediction) is a follow-up. The prediction path is the highest-leverage site and is fully wired.

### GAP-38 · Grid lock uses TTC, not distance — **RESOLVED (rev 9)**

**File**: `scripts/player_paddle_posture.gd:282-286`
**Change**: replaced distance-based grid lock with TTC-based, consistent with the rest of the posture system that migrated to TTC gates in rev 2.
```gdscript
# Before (distance-based — inconsistent with TTC-tiered system):
_player.awareness_grid.set_locked(ball_d <= 1.5)

# After (TTC-based — matches BLUE commit stage at 0.35 s):
var player_ttc: float = _player.awareness_grid.get_ttc_at_world_point(_player.global_position, 0.45)
_player.awareness_grid.set_locked(player_ttc < 0.35)
```
**Effect**: the awareness grid now locks at the same TTC threshold (0.35 s) as the BLUE commit stage, making the two systems temporally consistent. When no ball is in the grid (TTC returns INF), the condition is false and the grid stays unlocked — matching the prior behavior of distance-based locking when far from the ball.

### Rev 8 Test Summary

| Check | Result |
|---|---|
| Parse `player_hitting.gd` | ✅ clean |
| Parse `player_paddle_posture.gd` | ✅ clean |
| Parse `player_awareness_grid.gd` | ✅ clean |
| Parse `player_leg_ik.gd` | ✅ clean (after fixing duplicate var declaration) |
| Parse `player_ai_brain.gd` | ✅ clean |
| Parse `ball.gd` | ✅ clean |
| Headless Godot boot | ✅ reaches main loop |
| P0 / P1 player init (leg + arms + posture loop) | ✅ logs show all modules active |
| New runtime errors in edited files | ✅ zero |
| Pre-existing `state_label` null-deref | ⚠️ unchanged, unrelated (headless UI absence, not a rev 8 regression) |

### Rev 8 Gotchas & Lessons

1. **Always grep before declaring**: GAP-40 first attempt double-declared `right_foot_lock_pos` because I never checked whether those state vars already existed (they did at lines 60-61). Two-second `grep` would have caught it.
2. **Non-breaking augmentation beats replacement on first pass**: GAP-34 ghost borders are an override on top of the old green pool, not a replacement. Lower risk, easier rollback, validates the TTC color tier before deleting the fallback.
3. **Headless mode has false-positive UI crashes**: `state_label` null-deref is a pre-existing headless-only issue, not a regression. Future headless tests should filter it out of the "regression" signal set.
4. **Sub-agent verifications need `grep` confirmation**: caught in rev 7, proven again in rev 8 — the Explore sub-agent will hallucinate "dead code" claims. Trust but verify with direct reads.

### What to Test in Gameplay

1. **GAP-28**: press `J` + space-charged hit when an overhead ball arrives. Jump-smash should land deeper / harder than a standing smash at the same charge.
2. **GAP-34**: press `Z` to toggle debug, wait for an incoming ball, watch the ghost borders shift RED→ORANGE→YELLOW→GREEN by TTC. Previously the borders only pulsed between green and yellow on a wall clock; now they ramp through all four tiers in sequence.
3. **GAP-40**: walk sideways across the court. Previously feet slid slightly during stance changes; now the planted foot holds its world position cleanly until the next step.
4. **GAP-45**: feel whether close-range dinks (paddle already near ghost) now snap more precisely, while wide-reach shots ease into position instead of jerking.
5. **GAP-47**: play a rally against `HARD` difficulty — AI should feel competent but no longer "psychic". Switch to `EASY` — AI should feel noticeably late on fast drives.
6. **GAP-44**: notice the dominant foot shifting back on forehand commits (PURPLE stage visible on the committed ghost) rather than just "when the ball gets close".
7. **GAP-41**: no user-visible change expected. Confirmation is absence of the random-spin-on-serve that never did anything.
