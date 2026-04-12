# Trajectory → Posture → Commit System Reference

A scan-first reference for the paddle pre-positioning pipeline. Every subsystem
claim is cited with `file:line` so reviewers can jump straight to source.

This doc is complementary to `docs/paddle-posture-audit.md` (the gap-search +
research audit) — it describes **what exists today**, not what's missing.

---

## 1. Overview

The paddle commitment pipeline turns a predicted ball trajectory into a
selected posture, a visible "ghost" preview, a color-coded confidence state,
and a post-contact grade. Five subsystems interlock:

```
   ┌──────────┐   aero step    ┌───────────────────┐
   │  Ball    │────────────────▶│ DebugVisual       │
   │  (live)  │  predict_aero   │ draw_incoming_    │
   └──────────┘  _step()        │ trajectory()      │
                                └──────┬────────────┘
                                       │ _last_trajectory_points
                                       ▼
   ┌──────────────────────────────────────────────────┐
   │ PlayerPaddlePosture                              │
   │   set_trajectory_points()                        │
   │    │                                             │
   │    ├─▶ _is_ghost_near_trajectory()  → GREEN pool │
   │    │                                             │
   │    ├─▶ _find_closest_ghost_to_point() → COMMIT   │
   │    │   FIRST / TRACE / LOCK                      │
   │    │                                             │
   │    ├─▶ stage machine → PINK / PURPLE / BLUE      │
   │    │                                             │
   │    └─▶ force_paddle_head_to_ghost() → spring IK  │
   └──────────┬───────────────────────────────────────┘
              │ grade_flashed.emit("PERFECT" …)
              ▼
       HUD / score logs
```

Subsystems Sections 2-4 walk through the catalog, trajectory, and green pool. Section 5
covers the commit machine including **pinpointing** (which trajectory sample
is "the contact point") and **clamping** (how ghosts are constrained to
per-posture zones). Section 6 covers the color stages with the corrected
BLUE latch semantics. Section 7 covers grading. Section 8 covers AI
asymmetry. Sections 9-11 cover gotchas, tuning, and assessment.

Primary source files:

| File | Lines | Purpose |
|---|---|---|
| `scripts/player_paddle_posture.gd` | 1450 | Posture catalog, green pool, commit state machine, scoring |
| `scripts/player_debug_visual.gd` | 868 | Trajectory integration + debug draw |
| `scripts/ball.gd` | 420 | Live physics + `predict_aero_step()` used by trajectory |
| `scripts/player_ai_brain.gd` | 743 | AI side — own trajectory, same physics, no ghosts |
| `scripts/player.gd` | — | Wires `set_trajectory_points()` fan-out each frame |

---

## 2. Paddle Posture Catalog

### 2.1 The 20 postures

Defined in `PaddlePosture` enum on `player.gd`. Grouped by tier:

| Tier | Postures |
|---|---|
| **Forehand** | `FOREHAND`, `WIDE_FOREHAND`, `LOW_FOREHAND`, `LOW_WIDE_FOREHAND` |
| **Backhand** | `BACKHAND`, `WIDE_BACKHAND`, `LOW_BACKHAND`, `LOW_WIDE_BACKHAND` |
| **Center / forward** | `FORWARD`, `LOW_FORWARD`, `READY`, `VOLLEY_READY` |
| **Overhead** | `MEDIUM_OVERHEAD`, `HIGH_OVERHEAD` |
| **Mid-low** | `MID_LOW_FOREHAND`, `MID_LOW_BACKHAND`, `MID_LOW_FORWARD`, `MID_LOW_WIDE_FOREHAND`, `MID_LOW_WIDE_BACKHAND` |
| **Charge (serve only)** | `CHARGE_FOREHAND`, `CHARGE_BACKHAND` |

### 2.2 Geometry sources

- Offset (paddle head relative to player origin): `get_posture_offset_for()`
  → `player_paddle_posture.gd:1313`
- Rotation (yaw/pitch/roll of the paddle): `_get_posture_rotation_offset_for()`
  → `player_paddle_posture.gd:1367`
- Family classifier (used by center-bias and scoring):
  `_get_posture_family()` → 0=forehand, 1=backhand, 2=center, 3=overhead.

### 2.3 Height tiers

Relative to `COURT_FLOOR_Y = 0.075`:

| Tier | Ball height | Behavior |
|---|---|---|
| LOW | < 0.22m (ankle) | Paddle inverted 180°, handle up, crouch triggered |
| MID_LOW | 0.22–0.55m (knee/shin) | 20–25° forward tilt, scooping stance |
| NORMAL | ≥ 0.55m | Upright grip, standard postures |

LOW postures invert the paddle 180° roll so the face points toward the net from
below. Clearance jumps from `0.06m` (normal) to `0.45m` (inverted) to avoid
ground intersection — see `player_paddle_posture.gd:345`.

Backhand family activates the two-handed grip (left hand on paddle neck) via
`player_arm_ik.gd`.

Crouch only engages when `ball.is_in_play` is true, so idle animations don't
collapse the player.

---

## 3. Trajectory Prediction

### 3.1 Who draws it

`PlayerDebugVisual.draw_incoming_trajectory()` at
`player_debug_visual.gd:459-530`. Runs every `_physics_process` (60 Hz) and
stores the result in `_last_trajectory_points: Array[Vector3]`.

Called whether or not debug visuals are toggled on — the *array* is always
populated; the *dashed 3D line* is only drawn when debug is enabled. Downstream
consumers always get data.

### 3.2 How it integrates

Uses `Ball.predict_aero_step()` at `ball.gd:378-413`. This function mirrors the
live physics step exactly:

- Quadratic drag: `F = -½·ρ·Cd·A·|v|·v`
- Magnus lift: `F = k·(ω × v)`
- Spin damping (exponential halflife 1.5s)
- One bounce allowed: detects `y ≤ 0.08`, applies COR `0.685`, spin-tangent
  coupling `SPIN_BOUNCE_TRANSFER = 0.25`, spin decay `SPIN_BOUNCE_DECAY = 0.70`.

Because prediction and live physics share the same integrator, a ghost drawn
on the trajectory is where the ball *will actually be* (within floating-point
error) — not a kinematic approximation. This is why PERFECT grades are
achievable at all.

### 3.3 Sample rate and window

Constants in `player_debug_visual.gd:475-476`:

- `TRAJECTORY_STEP_TIME = 0.04s` — one sample per 2.4 physics frames
- `MAX_STEPS ≈ 80` → ~3.2s lookahead window

~80 points is plenty to cover a full cross-court rally arc, including one post-
bounce tail.

### 3.4 Fan-out

`player.gd` pushes the array to its two consumers each frame:

```gdscript
debug_visual.update_human_intercept_pools(b)
posture.set_trajectory_points(debug_visual._last_trajectory_points)
awareness_grid.set_trajectory_points(debug_visual._last_trajectory_points)
```

(Approximate — see `player.gd:294-300`.)

The array is recomputed every frame, never cached. Stale trajectories are
impossible; jitter can be, which is why the green-fade and zone-exit-debounce
mechanisms exist downstream.

---

## 4. Green Pooling

### 4.1 Goal

Visually mark every posture whose ghost sits close to the predicted path, so
the player can see their viable options at a glance. It's a preview of the
commit space, not the commit itself.

### 4.2 Activation

`_is_ghost_near_trajectory(posture)` at `player_paddle_posture.gd:675-690`:

```gdscript
for pt in _trajectory_points:
    if ghost_world.distance_to(pt) < 0.45:
        return true
```

- 0.45m hard-coded threshold on line 688 (not a named constant — candidate for
  promotion to `GHOST_TRAJECTORY_RADIUS` or similar if tuning becomes frequent).
- CHARGE postures are skipped (line 678) — they're serve-only and should never
  participate in incoming-ball pooling.

### 4.3 State

- `_green_lit_postures: Dictionary` (line 112) — maps `posture_id → frame_index`
- `_first_green_posture: int` (line 113) — tracks the first primary green for
  `[GREEN P# ★FIRST]` log tagging
- `_trajectory_points: Array[Vector3]` (line 115) — the fan-out target
- `_green_trigger_count: int` (line 123) — per-ball counter for scoring log

Frame indices come from `Engine.get_physics_frames()` — 64-bit, so it will not
wrap in any realistic game session.

### 4.4 Fade-out (0.6s)

When a ghost *leaves* trajectory proximity, it doesn't flip back instantly.
Instead it fades from green to its base color over `INCOMING_FADE_DURATION =
0.6s` (`player_paddle_posture.gd:139`, used at :1224-1239):

```gdscript
frames_since_lit = Engine.get_physics_frames() - _green_lit_postures[posture]
secs_since = frames_since_lit * get_physics_process_delta_time()
fade_t = clampf(secs_since / INCOMING_FADE_DURATION, 0.0, 1.0)
blended = green_col.lerp(base_col, fade_t)
```

The fade exists because per-frame trajectory re-integration can briefly push a
ghost outside 0.45m due to numerical jitter. Without the fade, the pool would
flicker on every such frame.

### 4.5 Colors

- Bright green: `RGB(0.1, 1.0, 0.2)` + emission boost during active green
- Fading: lerp(green → paddle base color) over 0.6s
- Base color: yellow `_ghost_base_color` captured when
  `create_posture_ghosts(paddle_color)` was called

---

## 5. Commit State Machine — FIRST / TRACE / LOCK

The green pool is *suggestion*. The commit is *selection*. Exactly one
committed posture exists per ball (`_committed_incoming_posture: int`). It
passes through three phases.

### 5.1 FIRST — initial pick

- Triggered when `_committed_incoming_posture < 0` AND ball is incoming AND
  `_trajectory_points` is non-empty (`player_paddle_posture.gd:276-280`)
- Picks the best ghost via `_find_closest_ghost_to_point(contact_pt)`
  (`:572-658`), where `contact_pt` is the trajectory sample nearest the player
- Center-bias: center postures (family 2) get a 0.20m distance bonus when the
  lateral offset from the player is < 0.4m — this encourages a "ready stance"
  over committing to a forehand/backhand when the ball is coming straight at
  the body
- CHARGE postures are skipped
- Log: `[COMMIT P#] FIRST d=X.XX -> POSTURE_NAME`
- Increments `_commit_count` (line 283) for the per-ball scoring log

### 5.2 TRACE — mid-flight recommit

Re-evaluates the pick when either the player moves or the trajectory shifts
enough that a different ghost is now closer.

- Zone-exit check (`:1193-1202`): each committed posture owns a reach zone
  `(x_min, x_max, y_min, y_max)`. If the contact point moves outside the zone
  plus `ZONE_EXIT_MARGIN = 0.3m` (`:44`), the commit is re-opened
- On exit, calls `_find_closest_ghost_to_point()` again. If the returned
  posture differs, swap: `_committed_incoming_posture = better_z`
- Log: `[ZONE_EXIT P#] OLD_POSTURE -> NEW_POSTURE`
- Debounced by `_zone_exit_cooldown` (≈ 0.5s) to prevent flip-flopping on the
  boundary

### 5.3 LOCK — spring chase

Once committed, the paddle head is actively driven toward the committed
ghost's world position via `force_paddle_head_to_ghost()`
(`player_paddle_posture.gd:693`). This is a framerate-independent spring
damper, not a snap.

Halflife is Fitts-law-derived and stage-compressed (GAP-4 / GAP-45 in the audit
doc):

```
halflife = max(fitts_MT * 0.35 * stage_compression, 0.02s)
```

where `fitts_MT` scales with reach distance (short reach → short halflife →
snappy; long reach → longer halflife → deliberate), and `stage_compression` is
a multiplier by commit stage:

| Stage | Compression |
|---|---|
| BLUE (<0.2s to contact) | 0.30× |
| PURPLE (0.2–0.8s) | 0.55× |
| PINK (>0.8s) | 0.80× |

So as the ball closes, the halflife shrinks and the paddle tracking gets
tighter. Stage *thresholds* do not change — only the *responsiveness* within
each stage.

The underlying integrator is `_damp_v3()` at line 345 — same pattern as the
`_damp()` documented in `CLAUDE.md`.

### 5.4 Pinpointing — where exactly is the contact point?

The commit logic needs a single 3D point: "this is where the ball will meet
the paddle". That point feeds `_find_closest_ghost_to_point()` and drives the
committed ghost's lerp target. There are **two** pinpointing functions, used
in different places, and they disagree on purpose.

#### 5.4.1 `_find_closest_trajectory_point()` — nearest-to-player (XZ)

`player_paddle_posture.gd:464-479`. The naive answer: walk the trajectory and
pick the sample whose XZ distance to the player is smallest. Also filters out
samples below `COURT_FLOOR_Y - 0.02` or above 1.8m (unreachable heights).

Used by the early-green detector and some diagnostic logs. It's fast but
*wrong* for descending arcs: on a dropping ball, the XZ-nearest sample can be
an intermediate height, not the low point where contact actually happens.

#### 5.4.2 `_compute_expected_contact_point()` — descending-aware

`player_paddle_posture.gd:481-516`. The smart answer. Branches on whether the
ball is descending (`linear_velocity.y < -1.0`):

- **Descending**: walks the trajectory in order and keeps overwriting
  `last_in_reach` every time a sample falls inside a reach window (XZ < 1.2m,
  height inside the filter band). The **final** write is the latest in-reach
  sample, which on a downward arc is also the lowest — i.e. the true contact
  point.
- **Ascending or flat**: falls back to XZ-nearest with the same filters.

`REACH_XZ = 1.2m` hard-coded on line 492 — this is the widest low-wide
posture reach. Anything beyond 1.2m is considered "can't get there".

This is the function FIRST commit uses (`:267 var contact_pt: Vector3 =
_compute_expected_contact_point()`). Using `_find_closest_trajectory_point()`
here caused misclassified commits on dink shots in an earlier rev.

#### 5.4.3 `_get_contact_point_local()` — player-local plane intersection

`player_paddle_posture.gd:539-570`. A third, more geometric pinpointer used
for ghost lerp targets (not commit selection). Finds where the trajectory
crosses the **ghost forward plane** at `GHOST_FORWARD_PLANE = 0.5m` in front
of the player (line 42), then clamps that offset into the stretch limits (see
next subsection). The result is stored in `_contact_point_local` and reused
frame-to-frame if no better sample is available.

### 5.5 Clamping — keeping ghosts in the feasible reach envelope

Pinpointing gives you "where the ball will be". Clamping turns that into
"where the ghost is *allowed* to be". Two layers:

#### 5.5.1 Global stretch limits

Applied in `_get_contact_point_local()` (`:562-568`):

| Constant | Value | Clamps |
|---|---|---|
| `GHOST_STRETCH_LATERAL_MAX` | 1.4m | `lx = clampf(off·fh, -1.4, 1.4)` — max sideways reach |
| `GHOST_STRETCH_HEIGHT_MIN` | -0.62m | Nominal vertical floor (legacy, see note) |
| `GHOST_STRETCH_HEIGHT_MAX` | 1.3m | Max vertical reach (overhead) |
| `GHOST_FORWARD_PLANE` | 0.5m | Forward distance of the paddle plane |
| `GHOST_CONTACT_MAX_DIST` | 3.0m | Reject candidate points farther than this from the plane |

The vertical min clamp has a dynamic override: `min_off_y = COURT_FLOOR_Y -
player_pos.y` (line 566). This lets the clamp track the actual court floor
instead of a fixed `-0.62m` — fixes low-ball clamping when the player is
standing on raised terrain. Before this fix, low wide shots were clipped
above the floor.

#### 5.5.2 Per-posture zone clamp (the tighter one)

Every posture owns a coverage rectangle in `POSTURE_ZONES` (`:48-76`),
structured as `{x_min, x_max, y_min, y_max}` in the player's local
forehand/height frame. Examples:

| Posture | x_min | x_max | y_min | y_max |
|---|---|---|---|---|
| `FOREHAND` | 0.2 | 0.55 | 0.5 | 1.0 |
| `WIDE_FOREHAND` | 0.5 | 1.1 | 0.48 | 1.0 |
| `MID_LOW_FOREHAND` | 0.2 | 0.55 | 0.15 | 0.52 |
| `LOW_WIDE_FOREHAND` | 0.5 | 1.1 | -0.2 | 0.15 |
| `HIGH_OVERHEAD` | -0.35 | 0.35 | 1.1 | 1.8 |

When a ghost is the committed one, its target position is clamped into its
own zone (`:1049-1050`):

```gdscript
var cl_x: float = clampf(contact_local.dot(fh_z), zone.x_min, zone.x_max)
var cl_y: float = clampf(contact_local.y, zone.y_min, zone.y_max)
target_pos = fh_z * cl_x + Vector3.UP * cl_y + fwd_z * GHOST_FORWARD_PLANE
```

This is what keeps a committed forehand ghost from flying to a backhand
position mid-swing. If the trajectory updates and the contact point now lives
outside the committed posture's zone, the ghost clamps to the nearest edge of
the zone — then the TRACE recommit logic decides whether to switch postures
entirely (via the zone-exit hysteresis).

The `y_min` values were deliberately raised on NORMAL postures so that
sub-0.48m balls *fall out* of normal zones and get a clean recommit to
`MID_LOW_*` variants (see comment on line 53-54). The zone bands are the
primary disambiguation between normal / mid-low / low tiers — they are tuned
so ~0.48m descending balls cleanly transfer.

#### 5.5.3 Spread-and-shift (non-committed ghosts)

Non-committed ghosts don't clamp; they get a behavior-based offset
(`:1056-1068`) that depends on where the ball is laterally vs where the
ghost's base position is:

- **Same side AND ball is wide (>0.3m lateral)**: spread outward by
  `clampf(|lateral|-0.3, 0, 0.6) * 0.8` — ghost reaches toward the ball
- **Opposite side**: shift 0.1m toward the ball side — subtle reach extension

This is why you see the *committed* ghost fly to a specific point while the
*other* ghosts drift slightly in the ball's direction. It's cheaper than full
clamping and it makes the pool feel alive.

#### 5.5.4 Floor clamp (paddle height)

Final safety net at `:335` and re-applied post-lerp at `:366`: the paddle
head itself can never go below the court surface. This is separate from the
ghost clamping — it guards against numerical dips during the spring chase
between frames.

### 5.6 Ghost dynamics during LOCK

- **Lerp, not snap**: ghosts fly toward the contact point at 6–8 m/s (line
  1080) instead of teleporting. You see the ready pose turn into the commit
  pose.
- **Anti-overlap**: `_apply_ghost_separation()` at `:1296` enforces
  `GHOST_MIN_DISTANCE = 0.18m` (`:140`). If two ghosts get closer, each is
  pushed away by half the deficit (`:913-916`).
- **Tighten**: non-committed ghosts pull 20% toward the committed ghost when
  the ball is incoming — visually concentrates the pool around the chosen
  answer.
- **Freeze on BLUE latch**: see next section — once `_blue_latched`, the
  committed ghost stops moving at `_ghost_frozen_at` and the paddle swings
  through a stationary target.

---

## 6. Color Stages — PINK / PURPLE / BLUE

The stage machine is driven by Time-To-Contact (TTC), not raw distance. TTC is
computed against the committed ghost, not the player body.

### 6.1 Thresholds

Constants at `player_paddle_posture.gd:133-136`:

```
const BLUE_HOLD_DURATION := 0.35   # min sustained BLUE before latch
const TTC_BLUE           := 0.2    # TTC cutoff for BLUE
const TTC_PURPLE         := 0.8    # TTC cutoff for PURPLE
const BLUE_DIST_FALLBACK := 0.35   # ball-to-ghost fallback
```

Stage assignment (`:1116-1121`):

```
elif ttc < TTC_BLUE or ball_to_ghost < BLUE_DIST_FALLBACK:
    stage = 2  # BLUE
elif ttc < TTC_PURPLE:
    stage = 1  # PURPLE
else:
    stage = 0  # PINK
```

`BLUE_DIST_FALLBACK = 0.35m` is the rescue when TTC is degenerate (ball is
slow, post-bounce, or TTC solver returned `INF`). Without it, fast near-body
balls wouldn't escalate to BLUE.

### 6.2 Appearance per stage

| Stage | When | Ghost color | Emission | Meaning |
|---|---|---|---|---|
| PINK (0) | TTC ≥ 0.8s | dim base | 0.08 | Early prediction, may still change |
| PURPLE (1) | 0.2 ≤ TTC < 0.8 | brighter commitment | ~0.5 | Committed, preparing the swing |
| BLUE (2) | TTC < 0.2 OR ball2ghost < 0.35m | max saturation | 0.1 → 3.0 (flash) | Contact imminent, ghost frozen |

### 6.3 BLUE latch (one-shot) and the hold window

**Correction from an earlier draft of this doc**: BLUE does not require a
0.35s sustain *before* latching. BLUE latches **immediately** the first frame
the condition fires (`player_paddle_posture.gd:1116-1120`):

```gdscript
elif ttc < TTC_BLUE or ball_to_ghost < BLUE_DIST_FALLBACK:
    stage = 2
    _blue_latched = true
    _blue_hold_timer = BLUE_HOLD_DURATION  # 0.35s
    _ghost_frozen_at = ghost_world
```

`BLUE_HOLD_DURATION = 0.35s` is the **post-latch hold window**, decremented
each frame at `:1111-1112`. During this window:

- `_blue_latched` remains true → stage stays at 2 even if the ball briefly
  escapes the trigger (post-bounce, wall interactions, etc.)
- `_ghost_frozen_at` is fixed → the committed ghost stops moving; the paddle
  swings through a stationary target
- The hold window gives the grade emission and visual flash enough time to
  register without the stage machine flipping underneath them

Rationale: bouncy / oscillating trajectories can briefly push `ball_to_ghost`
back above 0.35m just after contact, or TTC can go negative / undefined. The
one-shot latch + 0.35s hold prevents the stage from flipping back to PURPLE
mid-flash. The ghost freeze is what makes the swing consistent — if the
committed target kept lerping during contact, the grade would depend on
whichever frame the contact landed on.

Single-line summary: **latch is instant, hold is 0.35s, freeze is permanent
for the ball**.

### 6.4 Signal

```
signal incoming_stage_changed(stage, posture, commit_dist, ball2ghost, ttc)
```

Fires when `stage != _last_commit_stage` (`:1153` area, emit on :1160). The
HUD listens and re-colors debug text; the same signal feeds the scoring
trigger.

### 6.5 XZ distance vs 3D distance

Two distances are tracked and they mean different things:

- `commit_dist` — **XZ plane only** (`:1107-1108`). Used as a fallback
  ordering for stage logic and for `[MOVE]` log lines. Height is ignored on
  purpose because a lob overhead doesn't mean "you're far away" — it means "I
  should go to an overhead posture".
- `ball2ghost` — **full 3D distance** to the committed ghost. This is what
  scoring grades on.

Don't conflate them.

---

## 7. Scoring Rubric

### 7.1 Tracking

`_closest_ball2ghost: float = INF` at `:124`. Updated each frame while a
commit is active (`:1106`):

```
if ball_to_ghost < _closest_ball2ghost:
    _closest_ball2ghost = ball_to_ghost
```

This is the **minimum distance achieved during the entire commit window** —
the "best shot" against the chosen posture. Reset per ball in
`reset_incoming_highlight()` (`:762`).

### 7.2 Grades

From `player_paddle_posture.gd:1162-1172`:

| Grade | `_closest_ball2ghost` | Meaning |
|---|---|---|
| PERFECT | < 0.25m | Ball passed through the ghost |
| GREAT | < 0.40m | Within paddle head reach |
| GOOD | < 0.60m | Close, minor adjustment |
| OK | < 0.80m | Marginal stretch |
| MISS | ≥ 0.80m | Wrong posture entirely |

### 7.3 Emission

Signal `grade_flashed.emit(grade)` fires at stage 2 + contact. A per-ball
guard `_scored_this_ball` prevents double-grading if the ball lingers in the
contact zone.

Console format (example):

```
[SCORE P0] GREAT FH ball2ghost=0.34 commits=2 poses=3 greens=6
```

- `P0` — player 0 (human blue)
- `FH` — family shorthand (forehand)
- `ball2ghost=0.34` — the minimum 3D distance
- `commits=2` — FIRST + 1 TRACE recommit this ball
- `poses=3` — distinct postures the commit visited
- `greens=6` — total green activations this ball

---

## 8. AI vs Human Asymmetry

The AI (`player_ai_brain.gd`, 743 lines) uses the same *physics* as the human
but a different *consumption pattern*. The commitment/ghost/green pipeline is
**human-only**.

### 8.1 What the AI shares

- **Posture catalog** — AI picks from all 20 postures. Height-to-posture
  mapping at `_get_posture_for_height()` (`:246-275`); preference scoring at
  `_get_ai_posture_preference()` (`:316-340`).
- **Physics integrator** — AI predicts via `Ball.predict_aero_step()`, same
  function the human trajectory uses.

### 8.2 What the AI does *not* share

- **Ghosts** — AI never touches `posture_ghosts`, never activates green, never
  sees PINK/PURPLE/BLUE. These are purely visualization/feedback for the
  human.
- **Trajectory fan-out** — AI does not read `_last_trajectory_points`. It
  computes its own trajectory candidates via `_predict_ai_contact_candidates()`
  (`:408-464`), seeded from a delayed ball history buffer.

### 8.3 Reaction latency symmetry (GAP-47)

The AI reads a delayed snapshot of ball state to match human reaction time.
Ring buffer `_ball_history` stores `{pos, vel, omega}` each frame; the AI
samples `_ball_history[0]` (oldest) instead of the live ball.

Constants at `player_ai_brain.gd:81-83`:

| Difficulty | Frames | Latency |
|---|---|---|
| EASY | 18 | 300 ms |
| MEDIUM | 12 | 200 ms |
| HARD | 8 | 133 ms |

Dispatch at `:347-349`. This ensures the AI can't "cheat" by reading live
ball state that the human hasn't yet had time to react to.

---

## 9. Gotchas & Non-Obvious Coupling

1. **Trajectory-first architecture.** No trajectory → no green → no commit. If
   `_trajectory_points` is ever empty when it shouldn't be (e.g. the ball
   reference was dropped), the entire pipeline goes silent. Check for
   `_ball_incoming` + non-empty trajectory before debugging posture logic.

2. **Green fade vs commit stage are independent.** A ghost can be green *and*
   uncommitted — green means "viable option", not "selected". The committed
   ghost uses stage colors (pink/purple/blue), not green.

3. **BLUE latch is one-shot; the 0.35s is the *post-latch* hold window.**
   Latch fires on the first frame `ttc < TTC_BLUE OR ball_to_ghost < 0.35m`.
   `_blue_hold_timer` then counts down 0.35s while the stage stays pinned at
   2 and the ghost stays frozen — preventing the stage machine from flipping
   back mid-flash. Don't model it as "requires 0.35s sustain before
   latching".

4. **Committed ghost freezes at latch.** Once `_blue_latched`, the ghost
   stops at `_ghost_frozen_at` and the paddle swings toward that fixed point.
   Don't expect the ghost to keep tracking after latch.

5. **Stage compression tunes halflife, not thresholds.** The 0.30 / 0.55 /
   0.80 multipliers shorten the spring halflife but do not move the PINK /
   PURPLE / BLUE boundaries. Conflating them leads to confused tuning.

6. **AI and human share physics, not visualization.** When debugging AI
   misses, don't look in `_green_lit_postures` or `_committed_incoming_posture`
   — those are human-only. Look at `_ball_history` and
   `_predict_ai_contact_candidates()`.

7. **Ghost separation is 0.18m, green radius is 0.45m.** Two different
   numbers, two different purposes. `GHOST_MIN_DISTANCE` (line 140) is
   anti-overlap; the 0.45m on line 688 is trajectory proximity. Easy to
   confuse.

8. **LOW posture clearance is 7.5× normal.** 0.45m inverted vs 0.06m upright
   (`:345`). If you adjust ground offsets for postures, check both paths.

9. **`_scored_this_ball` guards double-grades.** A ball can linger in the
   contact zone after passing through the paddle; without the guard, the same
   ball would emit GREAT twice.

10. **Zone-exit cooldown is per-commit.** If you're seeing recommits flap,
    check `_zone_exit_cooldown`, not `ZONE_EXIT_MARGIN`. The margin is the
    trigger; the cooldown is the debounce.

---

## 10. Tuning Knobs

Every threshold / duration / distance in the pipeline, with its live value and
citation. Use this as the assessment sheet when balancing.

### 10.1 Green pool

| Constant | Value | Purpose | File:line |
|---|---|---|---|
| Green radius (magic number) | 0.45m | Ghost→trajectory max distance for green | `player_paddle_posture.gd:688` |
| `INCOMING_FADE_DURATION` | 0.6s | Green → base color fade window on exit | `player_paddle_posture.gd:139` |

### 10.2 Commit stages

| Constant | Value | Purpose | File:line |
|---|---|---|---|
| `TTC_PURPLE` | 0.8s | PINK → PURPLE TTC threshold | `player_paddle_posture.gd:135` |
| `TTC_BLUE` | 0.2s | PURPLE → BLUE TTC threshold | `player_paddle_posture.gd:134` |
| `BLUE_HOLD_DURATION` | 0.35s | Post-latch hold window (stage pinned, ghost frozen) | `player_paddle_posture.gd:133` |
| `BLUE_DIST_FALLBACK` | 0.35m | Distance fallback when TTC degenerate | `player_paddle_posture.gd:136` |
| Stage compression BLUE | 0.30× | Halflife multiplier during BLUE | `player_paddle_posture.gd:717` (approx) |
| Stage compression PURPLE | 0.55× | Halflife multiplier during PURPLE | `player_paddle_posture.gd:717` (approx) |
| Stage compression PINK | 0.80× | Halflife multiplier during PINK | `player_paddle_posture.gd:717` (approx) |

### 10.3 Commit state machine

| Constant | Value | Purpose | File:line |
|---|---|---|---|
| `ZONE_EXIT_MARGIN` | 0.3m | Hysteresis on zone-exit recommit | `player_paddle_posture.gd:44` |
| `_zone_exit_cooldown` | ~0.5s | Debounce between recommits | `player_paddle_posture.gd:~1200` |
| Center-bias distance bonus | 0.20m | Favor center postures near body | `player_paddle_posture.gd:572-658` (in scorer) |
| Center-bias lateral cutoff | 0.4m | Apply center-bias only when body-central | `player_paddle_posture.gd:572-658` |

### 10.3b Pinpointing & clamping

| Constant | Value | Purpose | File:line |
|---|---|---|---|
| `GHOST_STRETCH_LATERAL_MAX` | 1.4m | Max lateral clamp in `_get_contact_point_local()` | `player_paddle_posture.gd:39` |
| `GHOST_STRETCH_HEIGHT_MIN` | -0.62m | Nominal vertical floor (overridden by dynamic floor) | `player_paddle_posture.gd:40` |
| `GHOST_STRETCH_HEIGHT_MAX` | 1.3m | Max vertical reach (overhead cap) | `player_paddle_posture.gd:41` |
| `GHOST_FORWARD_PLANE` | 0.5m | Forward plane where ghosts live | `player_paddle_posture.gd:42` |
| `GHOST_CONTACT_MAX_DIST` | 3.0m | Max accepted distance to forward plane | `player_paddle_posture.gd:43` |
| `REACH_XZ` (pinpoint) | 1.2m | Widest reach for descending-aware pinpoint | `player_paddle_posture.gd:492` |
| Trajectory height filter | 0.08–1.8m | Reject unreachable samples during pinpoint | `player_paddle_posture.gd:473,499,510` |
| Descending velocity cutoff | -1.0 m/s | Threshold to switch to last-in-reach picking | `player_paddle_posture.gd:491` |
| `POSTURE_ZONES` | per-posture | Clamp rectangle in player-local space | `player_paddle_posture.gd:48-76` |

### 10.4 Ghost dynamics

| Constant | Value | Purpose | File:line |
|---|---|---|---|
| `GHOST_MIN_DISTANCE` | 0.18m | Anti-overlap pairwise pushback | `player_paddle_posture.gd:140` |
| Ghost lerp speed | 6–8 m/s | Ghost travel toward contact | `player_paddle_posture.gd:1080` |
| Tighten pull | 20% | Non-committed ghost pull toward committed | `player_paddle_posture.gd:~1290` |
| LOW posture clearance | 0.45m | Inverted paddle floor gap | `player_paddle_posture.gd:345` |
| Normal posture clearance | 0.06m | Upright paddle floor gap | `player_paddle_posture.gd:345` |

### 10.5 Trajectory

| Constant | Value | Purpose | File:line |
|---|---|---|---|
| `TRAJECTORY_STEP_TIME` | 0.04s | Sample interval for trajectory integration | `player_debug_visual.gd:475` |
| Max trajectory steps | 80 | ~3.2s lookahead window | `player_debug_visual.gd:476` |
| Bounce floor detect | y ≤ 0.08 | Switch to post-bounce integration | `ball.gd:378-413` |

### 10.6 Aero physics (from `ball.gd`, gated by `AERO_EFFECT_SCALE`)

| Constant | Value | Purpose |
|---|---|---|
| `AIR_DENSITY` | 1.225 | Atmospheric density (sea level) |
| `DRAG_COEFFICIENT` | 0.47 | Pickleball Cd (perforated) |
| `MAGNUS_COEFFICIENT` | 0.00012 | Spin curl magnitude |
| `SPIN_DAMPING_HALFLIFE` | 1.5s | Angular velocity decay halflife |
| `SPIN_BOUNCE_TRANSFER` | 0.25 | Topspin → forward velocity on bounce |
| `SPIN_BOUNCE_DECAY` | 0.70 | Fraction of `|ω|` surviving a bounce |
| `AERO_EFFECT_SCALE` | 0.5 | Global aero multiplier (0=off, 1=full) |

### 10.7 Scoring

| Constant | Value | Grade |
|---|---|---|
| PERFECT | < 0.25m | `player_paddle_posture.gd:1164` |
| GREAT | < 0.40m | `player_paddle_posture.gd:1166` |
| GOOD | < 0.60m | `player_paddle_posture.gd:1168` |
| OK | < 0.80m | `player_paddle_posture.gd:1170` |

### 10.8 AI reaction latency

| Difficulty | Frames | Latency | File:line |
|---|---|---|---|
| EASY | 18 | 300 ms | `player_ai_brain.gd:81` |
| MEDIUM | 12 | 200 ms | `player_ai_brain.gd:82` |
| HARD | 8 | 133 ms | `player_ai_brain.gd:83` |

---

## 11. Assessment Hooks

### 11.1 Hotkeys

| Key | Action |
|---|---|
| `4` | Launch a practice ball (random arcs toward the blue player) |
| `Z` | Toggle debug visuals (ghosts, zones, trajectory line) |
| `X` | Cycle AI difficulty (EASY / MEDIUM / HARD) |
| `T` | Run bounce-COR drop test |
| `P` | Cycle 3rd-person camera targets |

### 11.2 Console log tags

| Tag | Meaning |
|---|---|
| `[TRACK]` | Ball entered incoming-detection window |
| `[TRAJ]` | Full trajectory trace with per-ghost distances |
| `[GREEN]` | Ghost entered green pool (★FIRST marks the first) |
| `[COMMIT]` | FIRST commit or TRACE recommit |
| `[ZONE_EXIT]` | Recommit triggered by zone-exit hysteresis |
| `[COLOR]` | PINK / PURPLE / BLUE transition |
| `[MOVE]` | Player moved > 0.5m — logs position, ball dist, paddle dist |
| `[SCORE]` | Final grade + all per-ball counters |

### 11.3 Assessment workflow

1. Launch game, press `Z` to show debug visuals.
2. Press `4` to launch a practice ball.
3. Watch the ghost ring:
   - Greens should light up in a coherent band along the trajectory.
   - One ghost escalates PINK → PURPLE → BLUE as the ball approaches.
   - On BLUE latch, the ghost freezes.
4. Read the `[SCORE]` line. A healthy system shows GREAT or PERFECT on clean
   arcs; GOOD/OK on stretches; MISS only on intentionally evil launches.
5. If grades trend low, check in order:
   - `[GREEN]` count — is the pool too small? (raise 0.45m threshold)
   - `[COMMIT]` logs — is FIRST picking a sensible posture?
   - `[ZONE_EXIT]` — is TRACE flipping too often? (raise `_zone_exit_cooldown`
     or `ZONE_EXIT_MARGIN`)
   - `[COLOR]` — is BLUE latching early/late? (tune `TTC_BLUE` +
     `BLUE_HOLD_DURATION` together, not independently)

### 11.4 Cross-reference

Open gaps that affect this pipeline but are not yet closed — see
`docs/paddle-posture-audit.md`:

- **GAP-7b** — posture-aware pole IK (arm routing during exotic postures)
- **GAP-15** — sweet-spot hit modeling (ball2ghost grades don't account for
  which part of the paddle face made contact)
- **GAP-25** — AI jump capability (missing vertical reach)
- **GAP-43** — AI body-kinematic anticipation (AI doesn't pre-commit the
  body the way the human posture system does)

Resolved gaps relevant here: GAP-4 (framerate-independent spring chase),
GAP-20, GAP-28, GAP-40, GAP-41, GAP-44, GAP-45 (Fitts-law halflife),
GAP-47 (AI latency symmetry).
