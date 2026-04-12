# Pickleball Godot

3D pickleball game built in Godot 4.6.2 (GDScript).

## Entry Point

- **Main scene**: `scenes/game.tscn` (set in project.godot)
- **Main script**: `scripts/game.gd` — game loop, scoring, serve, UI, speedometer

## Architecture

All player logic is modular — child nodes attached in `player.gd:_ready()`:

| Module | File | Purpose |
|--------|------|---------|
| PlayerController | `player.gd` | Movement, bounds, paddle reference, enums |
| PlayerPaddlePosture | `player_paddle_posture.gd` | 20 postures, ball tracking, lerp position/rotation |
| PlayerArmIK | `player_arm_ik.gd` | Right arm → paddle IK, left arm two-handed grip |
| PlayerLegIK | `player_leg_ik.gd` | Gait system, step planning, foot lock |
| PlayerBodyAnimation | `player_body_animation.gd` | Lean, crouch, idle sway, walk bob |
| PlayerBodyBuilder | `player_body_builder.gd` | Procedural body mesh generation |
| PlayerHitting | `player_hitting.gd` | Serve charge, swing tweens, shot impulse |
| PlayerAIBrain | `player_ai_brain.gd` | AI state machine, trajectory prediction |
| PlayerDebugVisual | `player_debug_visual.gd` | 3D debug markers (intercept, step, trajectory) |

## Key Enums (in player.gd)

- `PaddlePosture` — 20 values: FOREHAND, FORWARD, BACKHAND, overheads, LOW_*, MID_LOW_*, WIDE_*, CHARGE_*
- `ShotContactState` — CLEAN, STRETCHED, POPUP
- `AIState` — INTERCEPT_POSITION, CHARGING, HIT_BALL

## Posture System

Ball height thresholds (relative to COURT_FLOOR_Y = 0.075):
- LOW: < 0.22 (ankle height)
- MID_LOW: 0.22 - 0.55 (knee/shin)
- NORMAL: >= 0.55

LOW postures invert the paddle (180 roll, handle up, face toward net) and trigger body crouch.
Backhand postures activate two-handed grip (left hand on paddle neck).
Crouch only activates when `ball.is_in_play` is true.

Position and rotation both lerp: wide=22, normal=16, low=12 (speed per second).

## Damping Pattern

Used everywhere for smooth transitions:
```gdscript
func _damp(current, target, halflife, dt):
    return lerpf(current, target, 1.0 - exp(-0.693 * dt / maxf(halflife, 0.001)))
```

## Court Layout

- Court length: 13.4, width: 6.1
- Net at Z=0, PlayerLeft on +Z side, PlayerRight on -Z side
- COURT_FLOOR_Y: 0.075
- Non-volley zone (kitchen): 1.8 units from net

## Ball Physics

- RigidBody3D, mass 0.024 kg, radius 0.06
- Gravity scale 1.5, bounce coefficient 0.685
- Max speed 20.0, serve speed 8.0

## Player Colors

- Blue = PlayerLeft (player_num=0, human)
- Red = PlayerRight (player_num=1, AI)

## Shot Types

4 shot types available to both human and AI players:

| Shot | Key | Speed | Arc | Target Zone | Character |
|------|-----|-------|-----|-------------|-----------|
| **Normal** | Auto | Medium | Medium | Mid-court | Balanced baseline rally shot |
| **Fast** | Auto | High | Low/flat | Deep baseline | Power shot, harder to react to |
| **Drop** | Auto | Low | Medium | Kitchen (NVZ) | Soft placement near net, forces opponent forward |
| **Lob** | Auto | Medium | High | Deep baseline | Over opponent's head, counters net play |

Enum: `ShotType` in `player.gd` — NORMAL, FAST, DROP, LOB

### Automatic Shot Selection (both human and AI)

Shot type is **context-determined**, not key-mapped. Same logic for both players:

| Factor | Favors | Why |
|--------|--------|-----|
| High charge + opponent deep | **Fast** | Power punish when opponent can't close distance |
| Low charge + near kitchen | **Drop** | Soft touch when already at net, short reach |
| Opponent crowding net | **Lob** | Go over their head to reset position |
| Opponent out of position laterally | **Fast** | Exploit the gap with speed |
| Neutral rally (no strong signal) | **Normal** | Safe default |
| Ball height LOW + near net | **Drop** | Natural dink/drop from low contact |
| Ball height HIGH + strong charge | **Fast** | Overhead power opportunity |

Inputs to the decision: `charge_ratio`, `player_position`, `opponent_position`, `ball_height`, `contact_state`, `distance_to_kitchen`.

### Shot Parameters (per type)
Each shot type modifies the unified velocity function with:
- `target_speed_range` — min/max ball speed (m/s)
- `arc_boost` — additional vy lift (Lob high, Fast negative, Drop neutral)
- `target_z_range` — depth targeting (Drop → kitchen 1.8-2.5, Lob → deep 5.0-6.0)
- `force_multiplier` — scales paddle_force (Fast > 1.0, Drop < 1.0)

### AI Reaction Speed
Configurable `reaction_delay: float` (seconds) — after opponent hits, AI holds position for this duration before tracking the ball. Default 0.0 (instant). Higher values = easier difficulty.
- Recovery delay after AI's own shot: `reaction_delay * 1.5`
- Prediction noise fades as ball approaches (optional difficulty layer)

## Implementation Goals

### Phase 1: Unified Shot Velocity
- [ ] Create shared `compute_shot_velocity(shot_type, charge, origin, player_num)` function
- [ ] Both human (`game.gd:_perform_player_swing`) and AI (`player_ai_brain.gd:_compute_ai_shot_velocity`) call the same function
- [ ] Shot type modifies target_z, target_speed, and arc parameters

### Phase 2: Automatic Shot Type Selection
- [ ] Add `ShotType` enum to `player.gd`
- [ ] Create `determine_shot_type(charge, player_pos, opponent_pos, ball_height, contact_state)` function
- [ ] Both human and AI use the same selection logic — no manual key input
- [ ] Shot type feeds into the unified velocity function from Phase 1

### Phase 3: AI Reaction Speed
- [ ] Add configurable `reaction_delay` with timer-based delay before AI tracks ball
- [ ] AI holds position during reaction delay, then predicts and moves
- [ ] Recovery delay after AI's own shot: `reaction_delay * 1.5`

### Phase 4: Balance & Polish
- [ ] Tune per-shot-type speed/arc/target values for pickleball (not tennis)
- [ ] Out-of-bounds correction per shot type
- [ ] Net clearance adjustment for fast/low shots
- [ ] Visual/audio feedback per shot type (HUD shows which shot was selected)

## Paddle Posture Commit System (player_paddle_posture.gd)

The paddle posture tracking uses a **trajectory-centric green pool** system for incoming ball handling. This is the core of how the player's paddle automatically positions for returns.

### Architecture

```
Ball in play → debug_visual draws dashed trajectory arc → returns trajectory points
                    ↓
player_arm_ik.gd passes points to posture module via set_trajectory_points()
                    ↓
Ghosts within 0.45m of trajectory glow GREEN
                    ↓
_find_closest_ghost_to_point(contact_pt) picks the best ghost → COMMIT
                    ↓
Committed ghost shows PINK (far) → PURPLE (close) → BLUE (contact)
```

### Commit Flow

1. **FIRST** — When trajectory points become available, pick the ghost closest to the contact point (trajectory point nearest to player). Center postures get a 0.20m bias when lateral offset < 0.4m.
2. **TRACE** — When player moves > 0.4m AND a different ghost is now closest AND ball > 1.5m away AND contact is not behind player. Cooldown 0.15s between traces.
3. **LOCK** — When ball < 1.5m, no more switching. The commit is final.

### Key Functions

| Function | Purpose |
|----------|---------|
| `_find_closest_ghost_to_point(ref)` | Picks best ghost for a contact point. Center bias when lateral < 0.4m. Skips CHARGE postures. |
| `_find_closest_trajectory_point()` | Finds trajectory point nearest to player (XZ distance, hittable height 0.08-1.8m) |
| `_is_ghost_near_trajectory(posture)` | Checks if ghost world pos is within 0.45m of any trajectory point → GREEN glow |
| `_get_posture_family(p)` | 0=forehand, 1=backhand, 2=center, 3=overhead |

### Color Stages (committed ghost)

| Stage | Trigger | Color |
|-------|---------|-------|
| PINK | ball > 3m from player | Early prediction |
| PURPLE | ball < 3m from player | Committed, preparing |
| BLUE | ball < 0.35m from ghost (held 0.35s) | Contact imminent |

### Green Glow System

- Ghosts within 0.45m of any trajectory point glow green
- Per-ghost fade: when ghost leaves trajectory proximity, fades green→yellow over 0.6s using frame timestamp
- `_green_lit_postures` dict tracks active greens (key=posture, value=frame timestamp)
- Green triggers counted per ball for scoring

### Scoring Rubric

At BLUE stage or closest approach (whichever fires), the system grades:

| Grade | ball2ghost | Meaning |
|-------|-----------|---------|
| PERFECT | < 0.25m | Ball went through the ghost |
| GREAT | < 0.40m | Within paddle reach |
| GOOD | < 0.60m | Close, slight adjustment |
| OK | < 0.80m | Reachable with stretch |
| MISS | >= 0.80m | Wrong posture |

Score log: `[SCORE P0] GREAT FH ball2ghost=0.34 commits=2 poses=3 greens=6`

### Console Logs

| Tag | What it shows | When |
|-----|---------------|------|
| `[COMMIT]` | FIRST/TRACE posture decisions | On commit |
| `[COLOR]` | PINK/PURPLE/BLUE stage transitions | On stage change |
| `[GREEN]` | Individual ghost entering green set | Per ghost |
| `[MOVE]` | Player position, ball/paddle distance | Every 0.5m movement |
| `[SCORE]` | Grade + all counters | At contact or ball passing |
| `[TRAJ]` | Full trajectory trace with ghost distances | Per practice ball |
| `[TRACK]` | Incoming detection trigger | Once per ball |

### Ghost Dynamics

- **Lerped positions**: ghosts fly into position at speed 8.0/s (not snapping)
- **Anti-overlap**: pairwise separation pushes ghosts apart if < 0.18m
- **Tighten**: when ball incoming, non-committed ghosts pull 20% toward committed ghost
- **Base color**: yellow `_ghost_base_color` stored from `create_posture_ghosts(paddle_color)`

### Hotkeys

| Key | Function |
|-----|----------|
| 4 | Practice ball launcher (random arcs toward Blue player) |
| X | Cycle AI difficulty (EASY/MEDIUM/HARD) |
| Z | Toggle debug visuals (posture ghosts, zones, trajectories) |
| P | 3rd person camera (cycle Blue/Red/default) |

### AI Difficulty (game.gd)

| Level | Shot power range | Court awareness |
|-------|-----------------|-----------------|
| EASY (default) | 80% dinks, 20% medium | Random lateral |
| MEDIUM | 55% soft, 45% firm | Aims away from player |
| HARD | 35% medium, 65% drives | Aims away from player |

### AI Hit System (player_ai_brain.gd)

- AI uses `_try_ai_hit_ball()` exclusively (hitbox callback disabled)
- Charge start requires `ball.global_position.z < 0` (ball on AI's side)
- Low/mid-low postures kept during charge (not converted to CHARGE_FOREHAND)
- Shot velocity via `game_node.compute_shot_velocity(ball_pos, charge, 1)`
- Prediction functions use `_has_entered_ai_side` flag to handle balls starting on opponent's side

### Ball Bounce Detection (ball.gd)

Bounce signal emits from inside the manual floor bounce code (not threshold-based detection). This ensures fast serves register bounces correctly — the physics engine resolves collisions before `_physics_process`, so threshold-based detection misses fast balls.

## Debug HUD

Posture debug label in `game.gd` — shows posture name + STANDING/CROUCHING for both players, positioned under the speed label (top-right).

## Audit Document

**Primary reference**: `docs/paddle-posture-audit.md` (~1650 lines).

Comprehensive gap-search audit of paddle posture detection, trajectory/TTC logic, green pool, reach, jump, and ball physics — cross-referenced to academic research and the current state of the art in procedural animation. Read this first before touching any posture, AI, IK, or ball physics code.

**Structure** (revs 1-8):
- Part 1-2: current logic catalog + initial gap list (GAP-1 through GAP-14)
- Part 3: procedural animation SOTA table
- Part 4/4b: prioritized queue + implementation sketches
- Part 5: file/line map for every subsystem
- Part 6: academic research cross-reference (Brody/Cross/Goodwill racket physics, Kibler/Elliott biomechanics, Lee/Bootsma/McLeod interception, Holden/Starke/Clavet procedural animation) — yields GAP-15 through GAP-24
- Part 7: reach/jump/footwork gaps (GAP-25 through GAP-32)
- Part 8: **awareness grid** wiring gaps (GAP-33 through GAP-39). The grid at `scripts/player_awareness_grid.gd` is a full volumetric proximity detector with per-vertex TTC coloring — was missed in early audits
- Part 9: deep re-audit with verified corrections + subsystems discovered (GAP-40 through GAP-51). Includes difficulty-tier segregation (🟢 easy / 🟡 medium / 🔴 hard / 🧪 research-grade)
- Part 10: rev-8 implementation log — eight easy gaps landed with file:line refs

**Status legend in the doc**: ✅ RESOLVED / 🟡 PARTIAL / 🔴 OPEN / 🚨 critical / 🧪 deferred.

**Resolved**: GAP-1, 3, 4, 6, 9, 20, 28, 33, 34, 40, 41, 44, 45, 47.
**Top open**: GAP-7b posture-aware pole IK, GAP-25 AI jump capability, GAP-43 AI body-kinematic anticipation, GAP-15 sweet-spot hit modeling.

## Ball Physics Calibration Tool

**Key**: press `4` → launches a practice ball and runs `BallPhysicsProbe` which logs the trajectory and compares measurements against real USAPA pickleball spec + Cross (1999) COR curve.

- Launcher at `game.gd:_launch_practice_ball` imparts topspin/backspin aligned to travel direction (spin variety is a work-in-progress — see "Spin" below)
- Probe at `scripts/ball_physics_probe.gd` follows the same pattern as `drop_test.gd` (key `T` runs the drop test for bounce COR calibration)
- Iteration loop: press 4 → read log → edit constants at top of `ball.gd` → restart game → press 4 again. Goal: all reported deltas print "MATCHES real reference ✓"

### Tunable ball.gd constants

```gdscript
const AIR_DENSITY := 1.225
const DRAG_COEFFICIENT := 0.47            # perforated pickleball, Cd
const MAGNUS_COEFFICIENT := 0.00012       # spin curl
const SPIN_DAMPING_HALFLIFE := 1.5        # seconds for |ω| to halve
const SPIN_BOUNCE_TRANSFER := 0.25        # topspin → forward boost
const SPIN_BOUNCE_DECAY := 0.70           # |ω| surviving a bounce
const AERO_EFFECT_SCALE := 0.5            # 0=disabled, 1=fully realistic
```

### Ball physics additions (rev 5 of audit)

All gated by `AERO_EFFECT_SCALE`:
1. **Quadratic air drag** in `ball.gd:_physics_process` — `F = -½·ρ·Cd·A·|v|·v`
2. **Magnus force** — `F = k·(ω × v)` — topspin dips, backspin lifts
3. **Spin damping** — exponential decay of `angular_velocity`
4. **Spin-tangential coupling on bounce** — topspin adds forward velocity, backspin subtracts
5. **Spin decay on bounce** — ~30% energy loss per floor hit

### Important: Godot built-in damping is ZERO'd

`scenes/ball.tscn` has `linear_damp = 0` and `angular_damp = 0`. The aero code in `ball.gd` is the sole source of drag and spin decay. If these are ever re-enabled, the probe will warn and all calibration numbers become meaningless because they will stack on top of the aero code.

### Probe formula detail

Horizontal drag component scales with `v_h × v_total` (NOT `v_h²`) because drag force acts antiparallel to total velocity and then projects onto horizontal. Early probe revs used `v_h²` and reported false "too draggy" warnings on high-arc lobs. Fixed at rev 3 of the probe.

## Auto-Debug System

OpenCode can autonomously find and fix Godot errors via `/fix-godot`.

### Prerequisites
```bash
brew install godot  # Godot 4.6.2 required
```

### Usage
```
/fix-godot
```
This will:
1. Check Godot is installed
2. Run warm-up import (registers all script classes)
3. Launch game headless for 15 seconds
4. Parse errors from stderr/stdout
5. Auto-fix common errors (parse errors, null calls, invalid calls)
6. Re-verify the fix

### What it fixes
- Parse/syntax errors in .gd files
- Null instance errors (uninitialized nodes)
- Invalid function calls (wrong arg count/type)
- Missing dictionary keys
- Signal connection errors

### What it CANNOT fix
- Physics tuning, visual glitches, AI behavior, performance

### Manual debug
```bash
cd /Users/arjomagno/Documents/github-repos/pickleball-godot
godot --headless --path . --quit-after 30 2>&1 | grep -i error
```
