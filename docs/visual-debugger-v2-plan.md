# Visual Debugger V2 — Porting Plan

## Goal
Replace the current coarse Z-key debug cycle (OFF → ALL-ON → ALL-ON-no-zones) with a **phase-by-phase progressive reveal**. Each phase adds ~2 related debug layers so the developer can reason about them as a group before the full picture gets noisy.

Pressing **Z** advances to the next phase. Earlier phases stay visible so the context builds up.

---

## What the Current System Does (V1)

| State | Z presses | What's visible |
|-------|-----------|----------------|
| 0 | 0 | Everything hidden |
| 1 | 1 | All debug ON + zone overlay ON |
| 2 | 2 | All debug ON + zone overlay OFF |
| 0 | 3 | Back to hidden |

The V1 toggle is a blunt instrument — everything flips at once.

---

## What V2 Should Do (Phase by Phase)

| Phase | Z presses | New Layers This Phase | Cumulative Visible |
|-------|-----------|----------------------|-------------------|
| 0 | 0 | — | Nothing |
| 1 | 1 | **Posture Ghosts** + **Charge Positions** | 2 layers |
| 2 | 2 | **Follow-Through Ghosts** + **Volumetric Grid** | 4 layers |
| 3 | 3 | **Trajectory Arc** + **Intercept Indicators** | 6 layers |
| 4 | 4 | **AI Indicators** + **Step Markers** | 8 layers |
| 5 | 5 | **Zone Overlay** + scoreboard debug panel | Everything |
| 0 | 6 | — | Back to clean court |

> Phases are grouped by **logical domain**: paddle geometry → swing & space → ball prediction → agent reasoning → full HUD.

---

## The Six Visual Debug Elements (Grouped into Phases)

### Phase 1 — Paddle Geometry

#### 1a. Posture Ghosts
- **What:** 21 paddle-shaped ghosts showing every possible paddle posture position around the player.
- **Current code:** `PlayerPaddlePosture.create_posture_ghosts()` + `set_ghosts_visible()`
- **V2 change:** Phase 1 shows these plus charge positions together.

#### 1b. Charge Positions
- **What:** The two charge-posture ghosts (CHARGE_FOREHAND, CHARGE_BACKHAND) that show where the paddle pulls back before a swing.
- **Current code:** Already exists inside `posture_ghosts` dictionary with darker material.
- **V2 change:** Give them a **distinct visual treatment** (pulsing glow + label) so they stand out as a separate readable layer within Phase 1.

---

### Phase 2 — Swing & Spatial Awareness

#### 2a. Follow-Through Ghosts
- **What:** 4 static paddle ghosts showing the follow-through end pose for each swing family (forehand, backhand, center, overhead).
- **Current code:** `_create_follow_through_ghosts()` stores them in `ft_ghosts` dictionary.
- **V2 change:** Dedicated visibility control so they can be revealed as a group in Phase 2.

#### 2b. Volumetric Grid (Awareness Grid)
- **What:** 3D field of sphere vertices around the player that light up red/orange/yellow/green along the predicted ball trajectory.
- **Current code:** `PlayerAwarenessGrid._build_grid()` + `set_visible()`
- **V2 change:** Reveal in Phase 2 so the user sees the spatial field together with the swing end-state.

---

### Phase 3 — Ball Prediction

#### 3a. Incoming Trajectory Arc
- **What:** Dashed white/cyan line showing the predicted ball path using aerodynamic step simulation.
- **Current code:** `PlayerDebugVisual.draw_incoming_trajectory()`
- **V2 change:** Granular visibility toggle so it appears only in Phase 3.

#### 3b. Intercept Indicators
- **What:** Pre-bounce (orange/gold) and post-bounce (cyan) spheres + labels showing where the player can intercept the ball and what shot type each point enables (VOLLEY, SMASH, RETURN, DROP, etc.).
- **Current code:** `PlayerDebugVisual.update_human_intercept_pools()`
- **V2 change:** Separate toggle from the trajectory arc. Together in Phase 3 they tell the full ball-prediction story.

---

### Phase 4 — Agent Reasoning

#### 4a. AI Indicators
- **What:** Cylinder/sphere markers showing the AI's target position, predicted bounce, and predicted contact point.
- **Current code:** `PlayerDebugVisual.create_ai_indicators()` + `update_ai_indicators()`
- **V2 change:** Toggle independently. Visible for both players in Phase 4.

#### 4b. Step Debug Markers
- **What:** Blue/red spheres showing right/left foot target positions and origins. The swinging foot marker scales up.
- **Current code:** `PlayerDebugVisual.draw_step_debug()`
- **V2 change:** Toggle independently. Shows alongside AI indicators in Phase 4 to reveal how both players plan movement.

---

### Phase 5 — Full HUD

#### 5a. Zone Overlay
- **What:** 2D court overlay showing service zones, kitchen, etc.
- **Current code:** `GameDebugUI.set_debug_zones_visible()`
- **V2 change:** Add only in the final phase so the screen doesn't get cluttered early.

#### 5b. Scoreboard Debug Panel
- **What:** Text readout showing posture names, contact state, ball speed, distances, etc.
- **Current code:** `ScoreboardUI.set_debug_visuals_active()`
- **V2 change:** Enable in Phase 5 so the textual debug joins the visual debug.

---

## Architecture Changes Needed

### 1. Phase Enum & Cycle Logic

Replace the 3-state `_debug_z_cycle` with a 6-state phase enum in `GameDebugUI`:

```gdscript
enum DebugPhase {
    OFF = 0,
    PADDLE_GEOMETRY = 1,   # posture ghosts + charge
    SWING_AND_SPACE = 2,   # follow-through + volumetric grid
    BALL_PREDICTION = 3,   # trajectory arc + intercept indicators
    AGENT_REASONING = 4,   # AI indicators + step markers
    FULL_HUD = 5,          # zone overlay + debug text panel
}
var _current_phase: int = DebugPhase.OFF
```

In `cycle_debug_visuals()`:
```gdscript
func cycle_debug_visuals() -> void:
    _current_phase = (_current_phase + 1) % 6
    _apply_phase(_current_phase)
```

### 2. Per-Layer Visibility API

Each subsystem gets fine-grained toggles. `_apply_phase()` calls only what that phase needs.

#### `PlayerPaddlePosture`
```gdscript
func set_posture_ghosts_visible(v: bool) -> void        # 21 posture ghosts
func set_charge_ghosts_visible(v: bool) -> void          # CHARGE_FH + CHARGE_BH only
func set_follow_through_visible(v: bool) -> void         # 4 ft_ghosts
func set_charge_highlight_active(v: bool) -> void        # pulse + label boost
```

#### `PlayerDebugVisual`
```gdscript
func set_trajectory_visible(v: bool) -> void             # incoming arc
func set_intercept_visible(v: bool) -> void              # pre/post bounce pools
func set_ai_indicators_visible(v: bool) -> void          # AI target/bounce/contact
func set_step_markers_visible(v: bool) -> void           # foot step spheres
```

#### `PlayerAwarenessGrid`
```gdscript
func set_visible(v: bool) -> void                        # already exists
```

### 3. Phase Application Table

```gdscript
func _apply_phase(phase: int) -> void:
    var p1 := phase >= DebugPhase.PADDLE_GEOMETRY
    var p2 := phase >= DebugPhase.SWING_AND_SPACE
    var p3 := phase >= DebugPhase.BALL_PREDICTION
    var p4 := phase >= DebugPhase.AGENT_REASONING
    var p5 := phase >= DebugPhase.FULL_HUD

    # Phase 1: Paddle Geometry
    _set_posture_ghosts_visible(p1)
    _set_charge_ghosts_visible(p1)
    _set_charge_highlight(p1)          # pulse only in phase 1, or keep it?

    # Phase 2: Swing & Space
    _set_follow_through_visible(p2)
    _set_grid_visible(p2)

    # Phase 3: Ball Prediction
    _set_trajectory_visible(p3)
    _set_intercept_visible(p3)

    # Phase 4: Agent Reasoning
    _set_ai_indicators_visible(p4)
    _set_step_markers_visible(p4)

    # Phase 5: Full HUD
    _set_zones_visible(p5)
    _set_debug_text_panel(p5)
```

> **Question:** Should charge highlight pulse stay active in later phases, or only in Phase 1?  
> **Answer:** Keep the pulse only in Phase 1. After that, charge ghosts settle back to their normal material so they don't distract from the new layers.

---

## Implementation Steps

### Step 0 — Prep
- [ ] Back up `game_debug_ui.gd`, `player_debug_visual.gd`, `player_paddle_posture.gd`
- [ ] Search codebase for any hard dependency on the old 3-state cycle

### Step 1 — `GameDebugUI` Phase Skeleton
- [ ] Replace `_debug_z_cycle` with `_current_phase` (0..5)
- [ ] Add `DebugPhase` enum
- [ ] Rewrite `cycle_debug_visuals()` to increment modulo 6
- [ ] Write `_apply_phase()` with the table above
- [ ] Add `_set_*()` helper wrappers for each layer

### Step 2 — `PlayerPaddlePosture` Layer Toggles
- [ ] `set_posture_ghosts_visible(bool)` — alias/wrap existing `set_ghosts_visible()`
- [ ] `set_charge_ghosts_visible(bool)` — show/hide only CHARGE_FOREHAND and CHARGE_BACKHAND ghosts
- [ ] `set_follow_through_visible(bool)` — show/hide `ft_ghosts` independently
- [ ] Add `_charge_face_active` bool + pulse logic in `update_posture_ghosts()`
  - When active: animate emission energy multiplier with `sin(Time.get_time_dict_from_system())`
  - When inactive: restore normal charge material

### Step 3 — `PlayerDebugVisual` Layer Toggles
- [ ] `set_trajectory_visible(bool)` — controls `incoming_traj_instance.visible`
- [ ] `set_intercept_visible(bool)` — controls pools, dashlines, labels
- [ ] `set_ai_indicators_visible(bool)` — controls AI markers
- [ ] `set_step_markers_visible(bool)` — controls foot step spheres
- [ ] Keep old `set_debug_visible(bool)` as a backwards-compatible "all-on" override

### Step 4 — Wire in `GameDebugUI`
- [ ] Connect all `_set_*()` helpers to the real subsystem methods
- [ ] Add on-screen phase label (e.g. "DEBUG Phase 1: Paddle Geometry")

### Step 5 — Test Each Phase
- [ ] **Phase 0:** Court is clean
- [ ] **Phase 1:** 21 posture ghosts + 2 charge ghosts (pulsing) visible
- [ ] **Phase 2:** + 4 follow-through ghosts + awareness grid
- [ ] **Phase 3:** + trajectory arc + intercept markers populate when ball is incoming
- [ ] **Phase 4:** + AI indicators (Red side) + step markers
- [ ] **Phase 5:** + zone overlay + debug text panel
- [ ] **Wrap:** Z from Phase 5 goes back to Phase 0

### Step 6 — Polish
- [ ] Ensure N-key intent indicators remain independent of phase cycle
- [ ] Ensure scoreboard posture debug (`update_posture_debug()`) still works
- [ ] Verify solo mode / posture editor don't conflict with debug phases

---

## Files to Touch

| File | Changes |
|------|---------|
| `scripts/game_debug_ui.gd` | Replace 3-state cycle with 6-phase enum + `_apply_phase()` |
| `scripts/player_paddle_posture.gd` | Add charge/follow-through granular visibility + pulse effect |
| `scripts/player_debug_visual.gd` | Split `set_debug_visible` into 4 per-layer toggles |
| `scripts/player_awareness_grid.gd` | No changes — `set_visible(bool)` already exists |
| `scripts/game.gd` | Verify `_cycle_debug_visuals()` forwarding still works |

---

## Design Notes

### Why 2 layers per phase?
- One layer alone is often too little context to be meaningful.
- Two related layers tell a story: e.g. posture ghosts + charge positions show "where the paddle can be" and "where it winds up."
- Three+ layers per phase gets noisy too fast.

### Why accumulation?
- The user sees how each new layer adds information to the existing picture.
- By Phase 5 the full debug picture is complete — no surprises.

### Why this grouping?
| Phase | Rationale |
|-------|-----------|
| 1 Paddle Geometry | Static paddle positions are the easiest to read. Charge is a variant of rest geometry. |
| 2 Swing & Space | Follow-through shows where the swing ends; the grid shows the 3D space the player monitors. Both are spatial envelopes. |
| 3 Ball Prediction | Trajectory + intercepts are two views of the same ball path. Together they explain "where the ball goes" and "where I can hit it." |
| 4 Agent Reasoning | AI indicators + step markers reveal how the agents (AI and human) plan movement. Symmetric pair. |
| 5 Full HUD | Text + zones are informational overlays, not spatial 3D debug. Save them for last. |

---

## Success Criteria

- [ ] Z cycles cleanly through 6 phases and wraps to OFF.
- [ ] Each phase adds exactly ~2 new visual layers; earlier layers remain visible.
- [ ] Charge ghosts pulse only in Phase 1, then settle to normal.
- [ ] No phase is too cluttered to read.
- [ ] N-key intent toggle remains independent.
- [ ] Existing posture editor, solo mode, and scoreboard are unaffected.
