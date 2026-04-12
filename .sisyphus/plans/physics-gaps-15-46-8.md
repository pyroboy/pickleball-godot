# Physics Gaps: GAP-15, GAP-46, GAP-8 — Work Plan

## TL;DR

Implement three physics improvements for the pickleball game:
1. **GAP-15**: Sweet-spot off-center hit modifies ball *speed* (not just spin)
2. **GAP-46**: Calibrate `DRAG_COEFFICIENT` to real pickleball values (0.33 outdoor / 0.45 indoor)
3. **GAP-8**: Wire serve spin into the trajectory predictor (spin is created but never consumed)

> **Estimated Effort**: GAP-15 ~40 lines · GAP-46 ~15 lines · GAP-8 ~20 lines
> **Parallel Execution**: YES — all three are independent
> **Test Strategy**: `4` key probe (GAP-46), visual check (GAP-15), grep + probe (GAP-8)

---

## Context

### Research Findings (from librarian agent)

**GAP-46 — Real Pickleball Drag Coefficients** (Lindsey 2025, TWU):
- Outdoor ball (40-hole, small holes): Cd = **0.33**
- Indoor ball (26-hole, large holes): Cd = **0.45**
- Current game: Cd = **0.47** (slightly high for outdoor)
- Source: `twu.tennis-warehouse.com/learning_center/pickleball/pickleball_aerodynamics.php`

**GAP-46 — Cl Asymmetry** (Lindsey 2025 — new finding):
- Topspin: `CL ≈ −0.24 − 0.195·S`
- Backspin: `CL ≈ +0.17 + weak S dependence`
- Gravity counteracts backspin Magnus — symmetric Magnus is wrong for backspin

**GAP-15 — Sweet-Spot Physics** (Pickleball Science):
- Effective sweet spot oval: ~4–5" long × 2–3" wide, centered on center of percussion
- Off-center penalty: ~20% velocity loss at 1" off-center, ~40% at 2" off-center
- Game currently only computes `compute_sweet_spot_spin()` (spin torque) but does NOT modify ball speed based on contact point

---

## Work Objectives

### GAP-15 — Sweet-Spot Off-Center Speed Reduction

**Current state**: `compute_sweet_spot_spin()` at `shot_physics.gd:217` computes spin torque from ball-vs-paddle-center offset. It is wired at both hit sites (human `game.gd:600`, AI `player_ai_brain.gd:733`). However, it only modifies `angular_velocity` — ball *speed* is unchanged by contact point.

**Gap**: A complete sweet-spot model reduces ball speed when the ball hits far from the paddle's center of percussion (the "dead zone"). Currently all hits transfer energy at the same rate regardless of contact point.

**Must have**:
- Off-center hits reduce ball speed by a factor that scales with distance from sweet spot center
- Center hits retain full ball speed (no change to current behavior)
- Both human and AI hits use the same correction

**Must NOT do**:
- Change the `compute_sweet_spot_spin()` function (keep it as-is for spin)
- Add new physics constants without documenting them
- Modify the COR function in `ball.gd` (that's separate from GAP-15)

---

### GAP-46 — Real Pickleball Drag Coefficients

**Current state**: `DRAG_COEFFICIENT = 0.47` (speed-averaged). Probe reference says "real perforated ball: ~0.45–0.55". Research shows outdoor ball is 0.33.

**Gap**: The probe's reference deceleration is computed with Cd=0.47 (game's own value), not a real reference. The "real reference" label in the probe is currently misleading.

**Must have**:
- Update the probe's `_ref_drag_decel()` function to use Cd=0.33 (outdoor) or 0.45 (indoor) as the reference
- Update `DRAG_COEFFICIENT` in `ball.gd` to a reasonable default (0.40 as a middle ground, or keep 0.47)
- Document which Cd value the reference uses in the probe printout

**Nice to have**:
- Cl asymmetry (non-symmetric topspin/backspin lift) — this is a larger change; flag as separate future work

---

### GAP-8 — Serve Spin Wired to Trajectory

**Current state**: `ball.gd:149` sets `angular_velocity` to a random value on serve. The `predict_aero_step` function receives an `omega` parameter separately from `ball.angular_velocity`. The trajectory simulation (`simulate_shot_trajectory` in `shot_physics.gd`) computes its own `solve_omega` from `compute_shot_spin` and passes that to `predict_aero_step`. The ball's actual `angular_velocity` is never used by any predictor.

**Gap**: Serve spin is visually visible (spin debug markers rotate) but has zero effect on the predicted trajectory. This makes spin feel decorative rather than physically meaningful.

**Must have**:
- `predict_aero_step` should use the *actual* `omega` from the ball's state for the live ball, not just for the trajectory simulation
- For the shot simulation in `shot_physics.gd`, the `omega` passed to `predict_aero_step` should still come from `compute_shot_spin` (that's correct for predicted shots)
- Verify that serve spin visible on the ball matches the trajectory the ball actually takes

**Must NOT do**:
- Change the Magnus coefficient value (that's GAP-46)
- Change how `angular_velocity` is initialized on serve
- Modify the Cl asymmetry finding (that's separate future work)

---

## Verification Strategy

### Test Decision
- **Test infrastructure**: EXISTS — `ball_physics_probe.gd` (key `4`), `drop_test.gd` (key `T`), `test_runner.gd`
- **Automated tests**: None for physics; game is validated via in-game probe + visual check
- **QA Scenarios**: Manual via Godot editor (key `4` + visual inspection of spin marker rotation + probe output parsing)

### QA Policy
Every task includes agent-executed QA scenarios. For physics work this means:
- Run Godot headless + `4` key via `godot_simulate_input`
- Parse `godot_get_debug_output()` for `→ MATCHES` lines
- Visual screenshot check for spin marker behavior

---

## Execution Strategy

```
Wave 1 (Parallel — all three are independent):
├── GAP-15: Add speed reduction to off-center hits (game.gd:599 + shot_physics.gd)
├── GAP-46: Update DRAG_COEFFICIENT + fix probe reference (ball.gd + ball_physics_probe.gd)
└── GAP-8: Wire serve spin into predictor (ball.gd predict_aero_step + shot_physics.gd)

Wave FINAL:
└── All three verified with probe + visual + grep
```

---

## TODOs

---

- [ ] 1. **GAP-15: Add off-center speed reduction to `compute_sweet_spot_speed()`**

  **What to do**:
  - Create new function `compute_sweet_spot_speed(ball_pos, paddle_pos, base_speed) -> float` in `shot_physics.gd`:
    ```gdscript
    func compute_sweet_spot_speed(ball_pos: Vector3, paddle_pos: Vector3, base_speed: float) -> float:
        var offset := ball_pos - paddle_pos
        var travel_dir := (ball_pos - _last_ball_pos).normalized() if _last_ball_pos else Vector3.FORWARD
        var offset_in_plane := offset - travel_dir * offset.dot(travel_dir)
        var offset_mag := offset_in_plane.length()
        # Sweet spot radius ~0.04m (4cm = 1.6" sweet spot on paddle)
        var sweet_spot_radius := 0.04
        if offset_mag < sweet_spot_radius:
            return base_speed  # center hit — full speed
        # Edge hit — reduce speed linearly
        var penalty := clamp((offset_mag - sweet_spot_radius) / 0.08, 0.0, 0.4)  # max 40% speed loss at edge
        return base_speed * (1.0 - penalty)
    ```
  - In `game.gd:_perform_player_swing()` at line ~600, after computing `_vel` but before assigning to ball:
    ```gdscript
    # GAP-15: sweet-spot speed reduction
    var sweet_speed := shot_physics.compute_sweet_spot_speed(ball_pos, _player.paddle.global_position, _vel.length())
    _vel = _vel.normalized() * sweet_speed
    ```
  - In `player_ai_brain.gd:_apply_ai_hit()` at line ~735, same pattern after computing `_ai_vel`
  - Add `_last_ball_pos` tracking to `ShotPhysics` (set at the start of `compute_shot_velocity`)

  **References**:
  - `shot_physics.gd:217-228` — existing `compute_sweet_spot_spin()` for pattern reference
  - `game.gd:588-609` — human swing hit site
  - `player_ai_brain.gd:721-749` — AI swing hit site

  **Acceptance Criteria**:
  - [ ] Center hits (ball lands within 4cm of paddle center) — ball speed unchanged
  - [ ] Edge hits (ball 8cm+ from center) — ball speed reduced by up to 40%
  - [ ] Both human and AI hits apply the same correction
  - [ ] `ball_physics_probe` output shows lower ball speed for intentionally off-center shots

  **QA Scenarios**:
  ```
  Scenario: Center hit — full speed
    Tool: godot_run_project + godot_simulate_input (KEY_4) + godot_get_debug_output
    Preconditions: Practice ball launches with baseline drive
    Steps:
      1. Launch practice ball (key 4)
      2. Read probe: "Initial vel: ... |v|=XX m/s"
    Expected Result: Speed matches compute_shot_velocity output (no penalty applied)
    Evidence: screenshot or debug output capture

  Scenario: Edge hit — speed reduced
    Tool: Same, but artificially offset paddle position in script before swing
    Preconditions: Ball arriving at extreme lateral edge of paddle
    Steps: Same probe measurement
    Expected Result: Speed 20-40% lower than center hit at same charge
    Evidence: debug output
  ```

---

- [ ] 2. **GAP-46: Calibrate DRAG_COEFFICIENT to real pickleball values**

  **What to do**:
  - Update `_ref_drag_decel()` in `ball_physics_probe.gd:289-293` to use Cd = **0.33** (outdoor ball, more demanding case):
    ```gdscript
    func _ref_drag_decel(v_h: float, v_total: float, mass: float, real_radius: float) -> float:
        var cd: float = 0.33  # outdoor pickleball — Lindsey 2025 TWU
        var cross: float = PI * real_radius * real_radius
        var drag_force: float = 0.5 * 1.225 * cd * cross * v_total * v_h
        return drag_force / mass
    ```
  - Update probe print at line ~88: `"DRAG_COEFFICIENT: %.3f        (Lindsey 2025: outdoor=0.33, indoor=0.45)"`
  - Consider adding a note in `ball.gd` constants block: `# Real Cd: outdoor=0.33, indoor=0.45 (Lindsey 2025)`
  - **Do NOT change** `DRAG_COEFFICIENT` in `ball.gd` yet — first establish whether the probe reference is the bottleneck

  **References**:
  - `ball_physics_probe.gd:289-293` — `_ref_drag_decel` function
  - `ball_physics_probe.gd:88` — print line for DRAG_COEFFICIENT
  - Lindsey 2025: `twu.tennis-warehouse.com/learning_center/pickleball/pickleball_aerodynamics.php`

  **Acceptance Criteria**:
  - [ ] Probe printout now says "Lindsey 2025: outdoor=0.33, indoor=0.45"
  - [ ] `_ref_drag_decel` uses Cd=0.33
  - [ ] After tuning, probe shows `→ MATCHES real reference ✓` for horizontal decel

  **QA Scenarios**:
  ```
  Scenario: Probe reference matches research
    Tool: godot_run_project + godot_simulate_input (KEY_4) + godot_get_debug_output
    Preconditions: Game running with current constants
    Steps:
      1. godot_simulate_input KEY_4
      2. sleep 2
      3. godot_get_debug_output
      4. Parse: "Real-ball ref decel: X.XXX" — should use Cd=0.33 internally
    Expected Result: Probe header says "Lindsey 2025: outdoor=0.33, indoor=0.45"
    Evidence: debug output screenshot
  ```

---

- [ ] 3. **GAP-8: Wire serve spin into trajectory prediction**

  **What to do**:
  - In `ball.gd:_physics_process()`, at the drag/Magnus section (~line 283), add a comment clarifying that `omega` is the ball's own angular_velocity (not a parameter):
    ```gdscript
    # NOTE: For serve spin, ball.angular_velocity is set at serve time (ball.gd:149).
    # For predicted trajectories (shot_physics.gd), omega comes from compute_shot_spin().
    # The magnus_force here uses the ball's own angular_velocity — correct for live ball.
    ```
  - In `ball.gd:predict_aero_step()` static method (line 401), verify it receives `omega` as a parameter and uses it directly — it should NOT read `ball.angular_velocity`. If it already does, confirm the design intent.
  - Grep verification: `grep -n "angular_velocity" ball.gd predict_aero_step` to confirm `omega` param is used, not `self.angular_velocity`
  - **Key check**: Does `simulate_shot_trajectory` in `shot_physics.gd:230` pass `solve_omega` (computed spin) correctly to `predict_aero_step`? Verify it does — if yes, the trajectory sim is correctly using computed spin. The issue is only that the *live ball's serve spin* isn't being consumed.

  **References**:
  - `ball.gd:283-288` — Magnus force in `_physics_process` — uses `angular_velocity` (self)
  - `ball.gd:401` — `predict_aero_step()` signature: receives `omega` as parameter
  - `ball.gd:149` — where serve spin is set: `angular_velocity = Vector3(...)`
  - `shot_physics.gd:247` — `simulate_shot_trajectory` calls `Ball.predict_aero_step(pos, cur_vel, cur_omega, ...)` with `cur_omega` from `solve_omega`

  **Acceptance Criteria**:
  - [ ] Serve spin (`ball.angular_velocity`) is visually visible on spin markers AND affects the ball's actual trajectory in `_physics_process`
  - [ ] `predict_aero_step` in trajectory simulation correctly uses passed `omega` param (verified by grep)
  - [ ] `simulate_shot_trajectory` passes `solve_omega` (computed spin) to `predict_aero_step` — this is correct for predicted shots

  **QA Scenarios**:
  ```
  Scenario: Serve spin visible AND affects trajectory
    Tool: godot_run_project + godot_simulate_input (KEY_F for serve) + godot_take_screenshot
    Preconditions: Serve with spin enabled (any serve)
    Steps:
      1. Fire a serve
      2. Watch spin axis arrow (green=topspin, red=backspin)
      3. Watch ball trajectory — does topspin cause visible dip vs flat serve?
    Expected Result: Spin markers rotate AND ball with topspin dips noticeably vs flat serve
    Failure Indicator: Spin markers rotate but trajectory is identical to no-spin ball
    Evidence: screenshot comparing spin vs flat serve arcs

  Scenario: Serve spin consumed by live physics (not just visual)
    Tool: godot_run_project + godot_simulate_input (KEY_F) + godot_get_debug_output
    Preconditions: Serve with heavy spin
    Steps:
      1. Fire two serves: one flat, one with max topspin
      2. Compare trajectory arcs — topspin should have measurably lower apex
      3. Run probe on both: compare h= values at same time t
    Expected Result: Topspin ball apex ~0.1-0.3m lower than flat at same initial speed
    Evidence: debug output comparison
  ```

---

## Final Verification Wave

- [ ] F1. **Plan Compliance Audit** — `oracle`
  Verify each task has a corresponding code change in the correct file.
  - GAP-15: `shot_physics.gd` has new `compute_sweet_spot_speed()` function + `game.gd` and `player_ai_brain.gd` call it
  - GAP-46: `ball_physics_probe.gd:_ref_drag_decel()` uses Cd=0.33
  - GAP-8: `ball.gd:_physics_process()` uses `angular_velocity` for Magnus, `predict_aero_step` verified correct by grep

- [ ] F2. **Code Quality Review** — `unspecified-high`
  - `godot_validate` on all edited files (no parse errors)
  - `godot_run_project --headless` — clean boot, no new errors

- [ ] F3. **Real Manual QA** — `unspecified-high` (+ `playwright` not needed — Godot MCP used)
  - GAP-15: Run `4` probe, visually compare center vs edge hit speeds
  - GAP-46: Run `4` probe, confirm "Lindsey 2025" reference in output
  - GAP-8: Compare flat vs spin serve trajectory visually

- [ ] F4. **Scope Fidelity Check** — `deep`
  - No changes outside the three target files: `shot_physics.gd`, `game.gd`, `player_ai_brain.gd`, `ball_physics_probe.gd`, `ball.gd`
  - No unintended changes to `compute_sweet_spot_spin()` (untouched)
  - No changes to COR function in `ball.gd`

---

## Commit Strategy

- **Single commit** for all three GAP fixes
- Message: `physics(pickleball): GAP-15 sweet-spot speed, GAP-46 drag Cd, GAP-8 serve spin wired`
- Pre-commit: `godot --headless --check-only .` (parse check only)

---

## Success Criteria

- [ ] GAP-15: Off-center hits reduce ball speed by up to 40% at paddle edge
- [ ] GAP-46: Probe reference uses Cd=0.33 (Lindsey 2025), output shows updated citation
- [ ] GAP-8: Serve spin is both **visually visible** (spin markers) AND **physically meaningful** (trajectory dips for topspin)
- [ ] All three probe MATCHES lines pass (horizontal decel, bounce COR, spin decay)
- [ ] No new parse errors in any edited file
- [ ] Headless boot: clean, no new warnings
