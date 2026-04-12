# Godot Physics + Game Testing README

> **Purpose**: Guide for AI agents and humans on how to test the pickleball game's physics,
> calibrate constants, and validate gap fixes end-to-end.
>
> **Game**: Godot 4.6.2, GDScript. Project: `/Users/arjomagno/Documents/github-repos/pickleball-godot`
>
> **Last updated**: 2026-04-13 (rev 9 audit)

---

## Table of Contents

1. [Physics Constants Quick Reference](#1-physics-constants-quick-reference)
2. [In-Game Calibration Tools](#2-in-game-calibration-tools)
3. [Headless / CI Testing](#3-headless--ci-testing)
4. [Physics Gap Status](#4-physics-gap-status)
5. [Test Priority Order](#5-test-priority-order)
6. [E2E Test Scenarios by Gap](#6-e2e-test-scenarios-by-gap)
7. [Known Failure Modes](#7-known-failure-modes)

---

## 1. Physics Constants Quick Reference

**File**: `scripts/ball.gd` (lines 4–59)

All tunable constants live in the top block of `ball.gd`. Edit → test → repeat.

### Ball Properties

| Constant | Value | Notes |
|---|---|---|
| `BALL_MASS` | `0.024` kg | USAPA: 22.1–26.5 g |
| `BALL_RADIUS` | `0.0375` m | USAPA: 73–75.5 mm diameter |
| `GRAVITY_SCALE` | `1.0` | Was 1.5 (pre-aero hack). Real gravity now. |
| `MAX_SPEED` | `20.0` m/s | Hard cap on ball velocity |
| `SERVE_SPEED` | `8.0` m/s | — |
| `BOUNCE_COR` | `0.640` | USAPA 30–34" drop calibrated. Rev 8.1. |

### Aero + Spin

| Constant | Value | Research | Notes |
|---|---|---|---|
| `AIR_DENSITY` | `1.225` kg/m³ | 1.21 kg/m³ | Sea level; Lindsey 2025 uses 1.21 |
| `DRAG_COEFFICIENT` | `0.47` | **0.33 outdoor / 0.45 indoor** | Lindsey 2025: 0.33 outdoor, 0.45 indoor; Steyn 2025: 0.30 |
| `MAGNUS_COEFFICIENT` | `0.0003` | 0.00012 tennis baseline | Cross 1999; game uses 2.5× due to perforations |
| `SPIN_DAMPING_HALFLIFE` | `150.0` s | No data | Empirically tuned; no published pickleball spin-decay data |
| `SPIN_BOUNCE_TRANSFER` | `0.25` | No data | Fraction of tangential velocity absorbed per bounce |
| `SPIN_BOUNCE_DECAY` | `0.70` | No data | Fraction of `\|ω\|` surviving a bounce |
| `AERO_EFFECT_SCALE` | `0.79` | Tune to match | Scales all aero effects; 0.79 close to real for indoor |

**Key citations**:
- Lindsey 2025 (drag + Cl asymmetry): `twu.tennis-warehouse.com/learning_center/pickleball/pickleball_aerodynamics.php`
- Pickleball Science (sweet spot): `pickleballscience.org`
- USAPA spec: `equipment.usapickleball.org/docs/Equipment-Standards-Manual.pdf`
- Cross 1999 (COR): `physics.usyd.edu.au/~cross/PUBLICATIONS/`
- Steyn et al. 2025: arXiv:2501.00163

### Key Functions

| Function | File:Line | Purpose |
|---|---|---|
| `cor_for_impact_speed(v)` | `ball.gd:26` | Velocity-dependent COR: `lerp(0.78, 0.56, clamp((v-3)/15, 0, 1))` |
| `predict_aero_step()` | `ball.gd:401` | Mirror of live aero — used by all predictors |
| `predict_bounce_spin()` | `ball.gd:426` | Mirror of bounce + spin-tangential for predictors |
| `_physics_process()` | `ball.gd:267` | Quadratic drag + Magnus curl + spin damping + manual floor bounce |

### COR Formula (velocity-dependent, GAP-21)

```
COR(v) = lerp(0.78, 0.56, clamp((v - 3.0) / 15.0, 0.0, 1.0))
```
- At 3 m/s impact → COR = 0.78
- At 18 m/s impact → COR = 0.56
- Pickleball drops steeper than tennis due to hollow perforated construction
- Reference: Cross (1999) + USAPA equipment testing

**⚠️ Critical invariant**: `linear_damp = 0` and `angular_damp = 0` on `scenes/ball.tscn`.
The aero code in `ball.gd` is the **sole authority** on drag and spin decay.
If built-in damping is non-zero, the probe warns: `"⚠ non-zero stacks extra drag"`.

---

## 2. In-Game Calibration Tools

### `4` Key — Full Trajectory Physics Probe

**What it does**: Launches a practice ball with randomized USAPA-compliant spin bundles, captures the full trajectory, detects the first bounce, and prints measured physics vs real pickleball reference values.

**How to run**:
1. Start the game in Godot editor or headless
2. Press `4`
3. Read the console output

**Launcher**: `practice_launcher.gd` — spawns balls from realistic court zones (BASELINE, MIDCOURT, NEAR-KITCHEN, IN_KITCHEN) with spin bundles (DRIVE, TOPSPIN_ROLL, DROP, DINK, LOB, SLICE, KICK_SERVE).

**Probe**: `ball_physics_probe.gd` — subscribes to the ball's `bounced` signal (authoritative detection, not threshold-based — so fast serves register correctly).

**What it prints**:

```
══════════════════════════════════════════════════════
  BALL PHYSICS PROBE — press 4 again to re-measure
══════════════════════════════════════════════════════
  Initial pos  : (x, y, z)
  Initial vel  : (x, y, z)  |v|=X.XX m/s  |v_h|=X.XX m/s
  Initial spin : (x, y, z)  |ω|=X.X rad/s  TOPSPIN (XX.X)

  ─── Config snapshot ──────────────────────────────
  Mass            : X.XXXX kg    (USAPA: X.XXXX–X.XXXX)  ✓
  Radius          : X.XXXX m     (USAPA: X.XXXX–X.XXXX)  ✓
  BOUNCE_COR      : velocity-dependent  (GAP-21: 0.78 @ 3 m/s → 0.56 @ 18 m/s)
  DRAG_COEFFICIENT: X.XXX        (real perforated ball: ~0.45–0.55)
  MAGNUS_COEFF   : X.XXXX      (real tennis ball ~1.2e-4)
  AERO_EFFECT_SCL : X.XX        (0=off, 1=full real)

  ─── Live trajectory samples ──────────────────────
  [t=0.10] h=1.23 |v|=12.45 (1.23,4.56,11.11)  |ω|=22.1

  ▼ FIRST BOUNCE at t=0.XXX s
    pos=(x, y, z)
    v_in  (pre) : (x,y,z)  |v|=X.XX
    v_out (post): (x,y,z)  |v|=X.XX

  ═══ Measurements (pre-bounce flight only) ═══════
  Flight duration    : X.XXX s
  Horizontal decel   : X.XXX m/s²  ← MEASURED
  Game expected decel: X.XXX m/s²  (from ball.gd aero @ AERO_SCALE=X.XX)
  Real-ball ref decel: X.XXX m/s²  (USAPA-spec ball at same avg speed)
  Other sources      : %+.XXX m/s² (linear_damp + coupling + noise)
  Measured vs real   : %+.XXX m/s² (+ = too fast, - = too draggy)
                       → MATCHES real reference ✓

  Bounce COR (vert)  : X.XXX  (impact speed X.XX m/s)
  Bounce COR ref     : X.XXX  (Cross 1999 curve, pickleball-calibrated)
  Delta              : %+.XXX
                       → MATCHES velocity-dependent ref ✓

  Pre-bounce spin decay over X.XX s: measured X.XXX, ref X.XXX
                       → MATCHES ✓

  ─── To iterate ───────────────────────────────────
  Edit constants in scripts/ball.gd at the top block.
  Press 4 to launch again. Goal: all deltas ≈ 0.
```

**PASS criteria** (all must be true):
| Measurement | Threshold | Printed when passing |
|---|---|---|
| Horizontal decel vs real reference | `|delta| < 0.3` m/s² | `→ MATCHES real reference ✓` |
| Bounce COR vs Cross 1999 curve | `|delta| < 0.03` | `→ MATCHES velocity-dependent ref ✓` |
| Pre-bounce spin decay | `|delta| < 0.05` | `→ MATCHES ✓` |

**Calibration loop**:
```
Edit ball.gd constants
        ↓
Press 4 → probe captures trajectory
        ↓
Read deltas — if > threshold, probe prints suggested new value
        ↓
Repeat until all three measurements show ✓
```

---

### `T` Key — Kinematic Drop Test

**What it does**: Isolates `BOUNCE_COR` in complete isolation — no air drag, no spin, just gravity + bounce. Kinematic integration (not a RigidBody3D) so it exactly replicates the formula in `ball.gd`.

**How to run**:
1. Press `T`
2. Watch cyan sphere drop
3. Read console for bounce heights

**USAPA spec**: 78" drop on granite → 30–34" rebound → COR 0.620–0.660 at ~6 m/s impact.

**Output**:
```
=== DROP TEST RESULTS (kinematic, BOUNCE_COR = 0.640) ===
  Bounce 1         : 32.1 in   (theoretical: 32.2 in)
  Bounce 2         : 20.5 in
  Bounce 3         : 13.1 in
  Measured COR     : 0.641
  BOUNCE_COR const : 0.640
  ✓ Measured matches the BOUNCE_COR constant (integration accurate)

  USA PB spec      : 30-34 in  (COR 0.620-0.660 at ~6 m/s impact)
  ✓ PASS — matches USAPA spec
```

**⚠️ When to use `T` vs `4`**:
- `T`: when you only changed `BOUNCE_COR` and want to verify the constant in isolation
- `4`: when tuning `DRAG_COEFFICIENT`, `MAGNUS_COEFFICIENT`, `SPIN_DAMPING_HALFLIFE`, or `AERO_EFFECT_SCALE`
- Both can be used together

---

## 3. Headless / CI Testing

### Quick Headless Verify (parse + boot)

```bash
cd /Users/arjomagno/Documents/github-repos/pickleball-godot
godot --headless --path . --quit-after 30 2>&1 | grep -i error
```
Returns: zero lines = clean boot. Any `ERROR` or `Parse Error` lines = issue.

### Headless Test Runner (exit code)

```bash
godot --headless --script scripts/tests/test_runner.gd
echo $?   # 0 = all pass, 1 = any failure
```

**Test suites** (`test_runner.gd` loads these as GDScript classes):
- `test_base_pose_system.gd` — posture enum, zone containment
- `test_rally_scorer.gd` — rally scoring logic
- `test_physics_utils.gd` — physics helper functions
- `test_shot_physics_shallow.gd` — shot velocity/spin computation
- `test_player_hitting.gd` — hitting module unit tests

**CI presence**: No GitHub Actions workflow exists in this repo. The test runner is CI-ready structurally (returns exit codes) but no pipeline automates it.

### Godot MCP Tools (automated in-editor testing)

These tools work with a **running** Godot instance:

| Tool | What it does |
|---|---|
| `godot_run_project` | Launch game (with `background=true` for hidden window) |
| `godot_get_debug_output` | Read `print()` output from the running game |
| `godot_simulate_input` | Send keypresses (`{type:"key", key:"4", pressed:true}`) |
| `godot_take_screenshot` | Capture viewport PNG |
| `godot_run_script` | Execute arbitrary GDScript in the live SceneTree |

**Automated physics calibration**:
```javascript
// Launch game hidden
godot_run_project({projectPath: ".../pickleball-godot", background: true})
// Wait 3s for MCP bridge
sleep 3
// Press '4' to fire practice ball
godot_simulate_input({actions: [{type:"key", key:"4", pressed:true}]})
sleep 1
// Read probe output
godot_get_debug_output()
// → Parse "MATCHES" lines to determine pass/fail
```

---

## 4. Physics Gap Status

**Reference**: `docs/paddle-posture-audit.md` — §9.6 Domain-Based Segregation

### ⚙️ Physics & Ball (6 gaps)

| GAP | Description | Status | Effort |
|---|---|---|---|
| GAP-15 | Sweet-spot off-center hit modeling | 🔴 OPEN | ~50 lines |
| GAP-21 | Fixed COR ignores velocity dependence | ✅ RESOLVED (rev 8) | 1 line |
| GAP-22 | No ball-paddle dwell time | 🧪 DEFER | — |
| GAP-41 | Delete inert vestigial spin state | ✅ RESOLVED (rev 8) | 2 lines |
| GAP-46 | No pickleball-specific aerodynamic drag | 🔴 OPEN | Hard |
| GAP-8 | Full spin/Magnus implementation | 🔴 OPEN | Hard |

### What GAP-21 Resolution Actually Did

`ball.gd:322` — `cor_for_impact_speed()` is called on every floor bounce:
```gdscript
linear_velocity.y = abs(linear_velocity.y) * cor_for_impact_speed(abs(linear_velocity.y))
```
The constant `BOUNCE_COR = 0.640` is now **only a default** — `cor_for_impact_speed()` is the active path.
The `ball_physics_probe` at line 83 explicitly prints the velocity-dependent formula as a reminder.

### What GAP-15 (Sweet-Spot) Actually Needs

The `compute_sweet_spot_spin()` function at `shot_physics.gd:217` already exists:
```gdscript
# Computes rim-torque spin from ball-vs-paddle-center offset
var offset = ball_pos - paddle_pos
var offset_in_plane = offset - travel_dir * (offset.dot(travel_dir))
var lever = clamp((offset_mag - 0.03) / 0.08, 0.0, 1.0)
var mag = lever * vel_mag * 2.5
return torque_axis.normalized() * mag
```
It is **wired** at both hit sites:
- Human: `game.gd:600` → `ball.angular_velocity = _shot_spin + _sweet_spin`
- AI: `player_ai_brain.gd:733` → `body.angular_velocity = _ai_shot_spin + _ai_sweet_spin`

**GAP-15 gap**: This only models spin injection. A complete sweet-spot model also modifies **ball speed** based on contact point — center hit = full COR, edge hit = less energy transfer. The `compute_sweet_spot_spin` has no speed/COR modifier, only a torque modifier.

---

## 5. Test Priority Order

### Immediate (do these first)

**1. GAP-21 Verification** — Already resolved but needs e2e confirmation
- Run `T` (drop test) → verify bounce 1 is 30–34"
- Run `4` (trajectory probe) → verify `→ MATCHES velocity-dependent ref ✓`
- Run several `4` presses at different speeds (different court zones via practice launcher) and confirm COR matches Cross 1999 curve at each speed band

**2. GAP-15 Sweet-Spot E2E Test** — Confirm `compute_sweet_spot_spin` is producing meaningful torque
- Launch a TOPSPIN DRIVE from baseline (press `4` multiple times until a high-speed topspin ball appears)
- In the probe output, watch `Initial spin` — verify it shows TOPSPIN with `|ω|` in range 20–55 rad/s depending on charge
- Watch the Magnus curl on trajectory — topspin balls should dip noticeably compared to flat shots
- Compare trajectory arc of a flat ball vs a high-spin ball at same initial speed

### Medium Term

**3. GAP-46 Aerodynamic Drag Calibration** — Full real-world comparison

**Current state**: `DRAG_COEFFICIENT = 0.47`. Research shows this is slightly high.

**Real pickleball drag coefficients** (Lindsey 2025, TWU — "The Physics of Pickleball Aerodynamics and Trajectories", 86 free-flight trajectories):

| Ball Type | Cd | Source |
|---|---|---|
| Outdoor (40-hole, small holes) | **0.33** | Lindsey 2025 |
| Indoor (26-hole, large holes) | **0.45** | Lindsey 2025 |
| Game current | **0.47** | Slightly high for outdoor |

**New finding (Lindsey 2025)**: Lift coefficient (Cl) is **not symmetric** for topspin vs backspin:
- Topspin effective: `CL ≈ −0.24 − 0.195·S`
- Backspin: `CL ≈ +0.17 + weak S dependence`
- Gravity counteracts backspin Magnus — contradicts classical Magnus theory
- This is a new finding not yet in any open-source sim code

**Calibration steps**:
1. Press `4` repeatedly — read `Horizontal decel: X.XXX m/s² ← MEASURED` and `Real-ball ref decel: X.XXX m/s²`
2. If `Measured vs real: +X.XXX` → game too fast → raise `DRAG_COEFFICIENT` or `AERO_EFFECT_SCALE`
3. If `Measured vs real: -X.XXX` → game too draggy → lower them
4. The probe prints: `Try AERO_EFFECT_SCALE ≈ X.XX`
5. Consider branching `DRAG_COEFFICIENT` by ball type if indoor/outdoor modes exist

**4. GAP-8 Spin/Magnus Full Implementation** — Spin created but never consumed
- Current: `ball.gd:149` sets `angular_velocity` on serve, but `predict_aero_step` never reads `ball.angular_velocity` — it only uses the passed `omega` parameter
- **Verification**: grep `predict_aero_step` — `omega` comes from `simulate_shot_trajectory`'s `cur_omega`, not from `ball.angular_velocity`
- This means serve spin is **visually visible** (spin markers spin) but has **no effect on trajectory**
- To fix: `predict_aero_step` should use actual `omega` from the ball's state, not a separately-computed solve
- Also check `shot_physics.gd:230` — `simulate_shot_trajectory` uses `solve_omega` (from `compute_shot_spin`) as the initial `cur_omega` for the sim, but `predict_aero_step` inside the sim gets a separate `omega` param

### Hard / Deferred

**GAP-22**: Ball-paddle dwell time — instantaneous impulse is fine for pickleball feel. Defer.

**GAP-46**: Partially implemented. `AERO_EFFECT_SCALE` scales all aero effects. Real Cd is 0.33 (outdoor) / 0.45 (indoor). Current 0.47 is close but slightly high for outdoor. Also note the new Cl asymmetry finding — symmetric Magnus may be wrong for backspin.

---

## 6. E2E Test Scenarios by Gap

### GAP-21 — Velocity-Dependent COR

**Setup**: Press `4` to launch practice balls at varying speeds
**Method**: Read probe output at each launch. Plot `impact_speed` vs `measured_COR`.
**Expected**: Measured COR follows `lerp(0.78, 0.56, clamp((v-3)/15, 0, 1))` within ±0.03
**Scripted validation**:
```javascript
// Run 5 probe launches and parse COR deltas
for (i = 0; i < 5; i++) {
  godot_simulate_input({actions: [{type:"key", key:"4", pressed:true}]})
  sleep 2)
  output = godot_get_debug_output()
  // Parse: "Bounce COR (vert)  : X.XXX" and "Delta              : %+.XXX"
  // assert all |delta| < 0.03
}
```

### GAP-15 — Sweet-Spot Torque

**Setup**: Launch topspin balls at charge 0.5 and charge 1.0
**Method**: Compare `Initial spin` in probe output
**Expected**: Higher charge → higher `|ω|` (charge gain ~lerp 0.55–1.25 on topspin_mag)
**Visual check**: In-game, watch the spin axis arrow (green = topspin). Higher charge balls should visibly curl more.

### GAP-46 — Horizontal Deceleration

**Setup**: Launch flat baseline drives at charge 0.8–1.0 (maximum speed, minimum arc)
**Method**: Read `Horizontal decel: X.XXX m/s² ← MEASURED` from probe
**Expected**: Matches `Real-ball ref decel` within 0.3 m/s²
**Calibration**: If `Measured vs real: +X.XXX`:
- `+` means game too fast → increase `DRAG_COEFFICIENT` or `AERO_EFFECT_SCALE`
- `-` means game too draggy → decrease them

### GAP-41 — Vestigial Spin Cleanup

**Current state**: `ball.gd:149` sets `angular_velocity` to a random value on serve, but nothing in `_physics_process` or `predict_aero_step` uses `ball.angular_velocity` — only the `omega` parameter passed separately.
**Verification**: grep for `angular_velocity` usages in trajectory predictors — they should all read from the passed `omega` param, not from `ball.angular_velocity`.

---

## 7. Known Failure Modes

| Symptom | Likely Cause | Fix |
|---|---|---|
| Ball floats unrealistic | `AERO_EFFECT_SCALE` too low | Raise toward 1.0, use probe to tune |
| Ball dies too fast | `DRAG_COEFFICIENT` too high | Lower from 0.47 |
| Spin invisible | `MAGNUS_COEFFICIENT` too low | Raise from 0.0003 |
| Spin decays too fast | `SPIN_DAMPING_HALFLIFE` too low | Raise from 150.0 |
| Fast serves miss bounces | `bounced` signal threshold miss | Not threshold-based — verify signal fires in probe |
| Probe shows `⚠ non-zero` for linear_damp | Scene has damping enabled | Set `linear_damp=0` and `angular_damp=0` on ball.tscn |
| COR mismatch at low speed | `BOUNCE_COR` constant vs `cor_for_impact_speed` | `cor_for_impact_speed` is the active path; `BOUNCE_COR` only used as fallback |
| `T` drop test shows wrong bounce height | `BOUNCE_COR` drifted | Re-calibrate with probe: press `4`, read `BOUNCE_COR` suggestion |
| AI psychic on reaction | No visuomotor latency buffer | GAP-47 resolved this — verify `player_ai_brain.gd` has `_ball_history` ring buffer |

---

## Quick Command Cheat Sheet

```bash
# Parse check (no game launch)
godot --headless --check-only --path .

# Headless boot + error scan
godot --headless --path . --quit-after 30 2>&1 | grep -i error

# Headless test runner (exit code)
godot --headless --script scripts/tests/test_runner.gd
echo $?   # 0=pass, 1=fail

# MCP automated probe (requires running game)
# 1. Launch
godot_run_project({projectPath: "...", background: true})
sleep 3
# 2. Fire probe
godot_simulate_input({actions: [{type:"key",key:"4",pressed:true}]})
sleep 2
# 3. Read results
godot_get_debug_output()
# 4. Parse "MATCHES" lines for pass/fail

# Stop game
godot_stop_project()
```
