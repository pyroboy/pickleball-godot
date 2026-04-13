# class_name Performant Fix Plan (Systemic — Whole Codebase)

## TL;DR

> **Quick Summary**: Fix ALL Godot 4 `class_name` type annotation parse errors across the entire codebase using the performant `preload` pattern for hot-path files and type erasure for cold-path editor-only files.
>
> **Deliverables**:
> - All parser errors resolved (no more "Could not find type X in current scope")
> - Hot-path files preserve typing (zero Variant dispatch overhead in physics loops)
> - Cold-path editor files use type erasure (acceptable — editor-only)
> - Headless boot succeeds with zero debugger breaks
> - `4` key probe prints all `MATCHES`
>
> **Estimated Effort**: Short–Medium (systematic pattern application across ~15 files)
> **Parallel Execution**: YES — 3 waves
> **Critical Path**: Wave 1 (hot-path PostureDefinition fixes) → Wave 2 (cold-path fixes) → Wave 3 (static var + remaining cold-path) → Boot → Probe

---

## Root Cause

Godot 4 resolves class-level `var x: SomeClassName` annotations at **parse time**, not runtime. Script load order is non-deterministic — if `SomeClassName`'s defining script hasn't been registered yet, the parser fails with `"Could not find type X in current scope."`.

A **stale `.godot/` cache** was masking this across many sessions. Fresh cache exposes all failures simultaneously.

---

## Two Fix Strategies

| Strategy | When to Use | Performance |
|---|---|---|
| **Type erasure** (`var x` without annotation) | Cold-path: editor/UI, event-driven, once-per-session code | Variant dispatch — acceptable for non-tight paths |
| **Preload + typed** (`const _X = preload(...); var x: X`) | Hot-path: anything called in `_physics_process` or per-frame | Zero overhead — same as original typed |

**`PlayerController` class-level vars**: These appear in 12 files but `PlayerController` extends `CharacterBody3D` (built-in), which is always available. None of these caused parse errors in testing. Skip fixing them.

---

## Complete Inventory (All Class-Level `class_name` Typed Variables)

### Hot-Path — Use Preload Pattern (13 variables)

| File | Variable | Type | Fix |
|------|----------|------|-----|
| `player_leg_ik.gd` | `pdef_feet` | `PostureDefinition` | Remove annotation |
| `player_leg_ik.gd` | `pdef_shift` | `PostureDefinition` | Remove annotation |
| `player_leg_ik.gd` | `pdef_pole` | `PostureDefinition` | Remove annotation |
| `player_arm_ik.gd` | `def` | `PostureDefinition` | Remove annotation |
| `player_body_animation.gd` | `runtime_def` (×2) | `PostureDefinition` | Remove annotation |
| `player_body_animation.gd` | `pdef_c` | `PostureDefinition` | Remove annotation |
| `player_body_animation.gd` | `pdef_t` | `PostureDefinition` | Remove annotation |
| `player_hitting.gd` | `current_def` | `PostureDefinition` | Remove annotation |
| `player_hitting.gd` | `def` | `PostureDefinition` | Remove annotation |
| `player_paddle_posture.gd` | `transition_pose_blend` | `PostureDefinition` | Remove annotation |

**Note on hot-path strategy**: These variables are assigned from `get_runtime_posture_def()` which returns a typed `PostureDefinition`. The returned value is already typed at the call site. Removing the annotation makes the variable `Variant` at class level, but the USE of the value (passing it to other functions, reading its properties) involves Variant dispatch. For these ~13 hot-path variables, the pragmatic approach is **type erasure** — the alternative (preload+typed) requires each function that consumes these vars to receive a typed `PostureDefinition` argument, which means changing function signatures across the codebase. The performance delta for a dozenVariant reads in a physics loop is measurable but acceptable given the simplicity. If profiling later shows it matters, preload+typed can be applied selectively.

### Cold-Path — Use Type Erasure (44+ variables)

These are editor-only or once-per-session. Removing type annotations is safe.

| File | Variables | Type | Fix |
|------|-----------|------|-----|
| `player_paddle_posture.gd` | `_skeleton_applier` | `PostureSkeletonApplier` | Type erasure |
| `player_paddle_posture.gd` | `_offset_resolver` | `PostureOffsetResolver` | Type erasure |
| `player_paddle_posture.gd` | `_commit_selector` | `PostureCommitSelector` | Type erasure |
| `pose_controller.gd` | `stroke_def` | `PostureDefinition` | Type erasure |
| `posture_editor/gizmo_controller.gd` | `_selected_gizmo`, `_hovered_gizmo` | `GizmoHandle` | Type erasure |
| `posture_editor/transition_player.gd` | `_ready_def`, `_charge_def`, `_contact_def`, `blended` | `PostureDefinition` | Type erasure |
| `posture_editor_ui.gd` | `_library`, `_base_pose_library`, `_gizmo_controller`, `_pose_trigger`, `_transition_player` | various | Type erasure (already done in prior session) |
| `posture_editor/tabs/charge_tab.gd` | `_def` | `PostureDefinition` | Type erasure |
| `posture_editor/tabs/paddle_tab.gd` | `_def` | `PostureDefinition` | Type erasure |
| `posture_editor/tabs/follow_through_tab.gd` | `_def` | `PostureDefinition` | Type erasure |
| `posture_editor/tabs/legs_tab.gd` | All UI child vars (`_stance_slider`, `_front_foot_slider`, etc.) | `SliderField` / `Vector3Editor` | Type erasure |
| `posture_editor/tabs/paddle_tab.gd` | All UI child vars | `SliderField` / `Vector3Editor` | Type erasure |
| `posture_editor/tabs/follow_through_tab.gd` | All UI child vars | `SliderField` / `Vector3Editor` | Type erasure |
| `posture_editor/tabs/torso_tab.gd` | All UI child vars | `SliderField` / `Vector3Editor` | Type erasure |
| `posture_editor/tabs/arms_tab.gd` | All UI child vars | `Vector3Editor` | Type erasure |
| `posture_editor/tabs/head_tab.gd` | All UI child vars | `SliderField` / `Vector3Editor` | Type erasure |

### Static Variables — Already Fine

| File | Variable | Type | Status |
|------|----------|------|--------|
| `posture_library.gd` | `static var _singleton: PostureLibrary` | `PostureLibrary` | Static init runs after all scripts loaded — no parse-time issue |
| `base_pose_library.gd` | `static var _singleton: BasePoseLibrary` | `BasePoseLibrary` | Same — no action needed |

### Skipped (Not `class_name` Typed — Built-in or Fine)

- `PlayerController` class-level vars (12 files) — `extends CharacterBody3D` (built-in), always resolves
- `Ball` class-level vars — `class_name Ball` is defined and loads fine
- All UI built-in types (`Label`, `Button`, `ItemList`, `TabContainer`, `HBoxContainer`, `VBoxContainer`, `Control`, `PanelContainer`, etc.) — built-in, always available
- All spatial types (`Node3D`, `RigidBody3D`, `CharacterBody3D`, `MeshInstance3D`, etc.) — built-in, always available
- All local typed variables (inside functions) — fine, resolved at runtime

---

## Work Objectives

### Must Have
- [ ] All class-level `class_name` type annotation parse errors resolved
- [ ] Headless boot: no `Debugger Break` / `Parser Error` in output (warnings OK)
- [ ] `4` key probe: all 4 sections print `MATCHES`

### Must NOT Have
- [ ] No Variant overhead added to the `physics_process` hot path beyond the ~13 pragmatic erasure choices above
- [ ] No parse errors on fresh `.godot/` cache
- [ ] No changes to game logic — only type annotation fixes
- [ ] No changes to `compute_sweet_spot_spin()` or `ball.gd` COR function

### Scope
**IN**: All `.gd` files with class-level `class_name` typed variable annotations
**OUT**: Built-in Godot types, function-local typed variables, function parameter/return types, `PlayerController` vars, static singleton vars

---

## Verification Strategy

**Boot cycle protocol** (after each wave):
1. `godot_stop_project`
2. `pkill -f "Godot.app"`
3. `rm -rf .godot/`
4. `godot_run_project` (background=true)
5. `sleep 10`
6. `godot_get_debug_output` → no `Debugger Break` / `Parser Error` = pass

**Final verification**: Run `4` key probe via `godot_simulate_input`, confirm all 4 sections print `MATCHES`.

---

## Execution Strategy

### Parallelization (3 Waves)

```
Wave 1 (Foundation — 4 hot-path player files):
├── Task 1: player_leg_ik.gd     (3 PostureDefinition vars)
├── Task 2: player_arm_ik.gd      (1 PostureDefinition var)
├── Task 3: player_body_animation.gd  (4 PostureDefinition vars)
└── Task 4: player_hitting.gd    (2 PostureDefinition vars)

Wave 2 (Cold-path infrastructure + pose_controller):
├── Task 5: player_paddle_posture.gd  (3 class_name infrastructure vars)
├── Task 6: pose_controller.gd         (stroke_def + Ball var)
├── Task 7: transition_player.gd        (4 PostureDefinition vars)
└── Task 8: gizmo_controller.gd         (2 GizmoHandle vars)

Wave 3 (Editor tab files — all cold-path):
├── Task 9:  charge_tab.gd        (_def + UI child vars)
├── Task 10: paddle_tab.gd        (_def + UI child vars)
├── Task 11: follow_through_tab.gd (_def + UI child vars)
├── Task 12: legs_tab.gd           (UI child vars)
├── Task 13: torso_tab.gd          (UI child vars)
├── Task 14: arms_tab.gd           (UI child vars)
└── Task 15: head_tab.gd           (UI child vars)

Wave FINAL (Verification):
├── F1: Full boot cycle (no debugger breaks)
├── F2: godot_validate on ALL modified files
└── F3: 4 key probe → all MATCHES
```

### Agent Dispatch

- **Wave 1**: 4 tasks → 4 parallel agents (1 per file, category=`quick`)
- **Wave 2**: 4 tasks → 4 parallel agents (1 per file, category=`quick`)
- **Wave 3**: 7 tasks → 7 parallel agents (1 per file, category=`quick`)

---

## TODOs

> Every task: remove type annotation, then godot_validate on that file.
> Hot-path pragmatic choice: type erasure on ~13 PostureDefinition vars in player modules. Simple, safe, acceptable Variant cost.

- [ ] 1. **player_leg_ik.gd** — 3 hot-path PostureDefinition vars

  **What to do**:
  - Read the file first to find the exact lines
  - Change class-level `var pdef_feet: PostureDefinition = ...` → `var pdef_feet` (3 vars: pdef_feet line ~184, pdef_shift line ~429, pdef_pole line ~465)
  - Keep all assignments as-is: `= _player.get_runtime_posture_def()` — the RHS is already typed at source
  - Do NOT touch `_player: PlayerController` — PlayerController extends built-in CharacterBody3D and resolves fine

  **Must NOT do**:
  - Don't change any local variables (there are many Vector3 locals with `: Vector3` — these are built-in and fine)
  - Don't touch function signatures

  **Pattern**:
  ```gdscript
  # Before:
  var pdef_feet: PostureDefinition = _player.get_runtime_posture_def()
  # After:
  var pdef_feet = _player.get_runtime_posture_def()
  ```

  **Recommended Agent Profile**:
  - **Category**: `quick`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 3, 4)
  - **Blocks**: Wave FINAL
  - **Blocked By**: None

  **References**:
  - `scripts/player.gd:457` — `get_runtime_posture_def()` returns `PostureDefinition`
  - `scripts/posture_definition.gd:1` — `class_name PostureDefinition extends Resource`

  **Acceptance Criteria**:
  - [ ] `godot_validate scripts/player_leg_ik.gd` → `valid: true`, 0 errors

  **QA Scenarios**:
  ```
  Scenario: Validate player_leg_ik.gd after fix
    Tool: Bash
    Preconditions: .godot/ cache cleared
    Steps:
      1. godot_validate(projectPath=".../pickleball-godot", scriptPath="scripts/player_leg_ik.gd")
    Expected Result: valid=true, errors=[]
    Evidence: .sisyphus/evidence/task-1-validate.json
  ```

  **Commit**: YES (Wave 1 commit)

- [ ] 2. **player_arm_ik.gd** — 1 hot-path PostureDefinition var

  **What to do**:
  - Read file to find line ~10: `var def: PostureDefinition = _player.get_runtime_posture_def()`
  - Change to: `var def = _player.get_runtime_posture_def()`
  - Do NOT touch `_player: PlayerController` (line 3)

  **Pattern**: Same as Task 1

  **Recommended Agent Profile**:
  - **Category**: `quick`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 3, 4)
  - **Blocks**: Wave FINAL
  - **Blocked By**: None

  **Acceptance Criteria**:
  - [ ] `godot_validate scripts/player_arm_ik.gd` → `valid: true`, 0 errors

  **QA Scenarios**:
  ```
  Scenario: Validate player_arm_ik.gd after fix
    Tool: godot_validate
    Steps: [same as Task 1]
    Evidence: .sisyphus/evidence/task-2-validate.json
  ```

  **Commit**: YES (Wave 1 commit)

- [ ] 3. **player_body_animation.gd** — 4 hot-path PostureDefinition vars

  **What to do**:
  - Read file to find all PostureDefinition class-level vars:
    - `var runtime_def: PostureDefinition` at ~line 44
    - `var pdef_c: PostureDefinition` at ~line 98
    - `var runtime_def: PostureDefinition` at ~line 149 (second occurrence)
    - `var pdef_t: PostureDefinition` at ~line 174
  - Change all 4: remove `: PostureDefinition` type annotation
  - Do NOT touch `_player: PlayerController` (~line 33)
  - Do NOT touch local `Vector3` typed variables (built-in)

  **Pattern**: Same as Task 1

  **Recommended Agent Profile**:
  - **Category**: `quick`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2, 4)
  - **Blocks**: Wave FINAL
  - **Blocked By**: None

  **Acceptance Criteria**:
  - [ ] `godot_validate scripts/player_body_animation.gd` → `valid: true`, 0 errors

  **QA Scenarios**:
  ```
  Scenario: Validate player_body_animation.gd after fix
    Tool: godot_validate
    Steps: [same pattern as Task 1]
    Evidence: .sisyphus/evidence/task-3-validate.json
  ```

  **Commit**: YES (Wave 1 commit)

- [ ] 4. **player_hitting.gd** — 2 hot-path PostureDefinition vars

  **What to do**:
  - Read file to find:
    - `var current_def: PostureDefinition` at ~line 186 (assigned from `posture_lib.get_def()`)
    - `var def: PostureDefinition` at ~line 259 (assigned from `_get_posture_def()`)
  - Change both: remove `: PostureDefinition`
  - Do NOT touch `_player: PlayerController` (~line 39)
  - Do NOT touch `var posture_lib` — keeping as untyped is fine for a single dictionary access

  **Pattern**: Same as Task 1

  **Recommended Agent Profile**:
  - **Category**: `quick`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2, 3)
  - **Blocks**: Wave FINAL
  - **Blocked By**: None

  **Acceptance Criteria**:
  - [ ] `godot_validate scripts/player_hitting.gd` → `valid: true`, 0 errors

  **QA Scenarios**:
  ```
  Scenario: Validate player_hitting.gd after fix
    Tool: godot_validate
    Steps: [same pattern as Task 1]
    Evidence: .sisyphus/evidence/task-4-validate.json
  ```

  **Commit**: YES (Wave 1 commit)

- [ ] 5. **player_paddle_posture.gd** — 3 cold-path class_name infrastructure vars

  **What to do**:
  - Read file to find lines:
    - `var _skeleton_applier: PostureSkeletonApplier = null` (~line 7)
    - `var _offset_resolver: PostureOffsetResolver` (~line 10)
    - `var _commit_selector: PostureCommitSelector` (~line 13)
  - Change all 3: remove `: TypeName` annotation (type erasure — cold path)
  - Do NOT touch `_posture_lib` (already untyped from prior session)
  - Do NOT touch `var transition_pose_blend: PostureDefinition` (line 153) — handled separately in Wave 1 style if needed, but cold-path so erasure is fine
  - Do NOT touch any other class-level vars with built-in types (MeshInstance3D, Node3D, etc.)

  **Pattern**:
  ```gdscript
  # Before:
  var _skeleton_applier: PostureSkeletonApplier = null
  # After:
  var _skeleton_applier = null
  ```

  **Recommended Agent Profile**:
  - **Category**: `quick`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 6, 7, 8)
  - **Blocks**: Wave FINAL
  - **Blocked By**: None

  **Acceptance Criteria**:
  - [ ] `godot_validate scripts/player_paddle_posture.gd` → `valid: true`, 0 errors

  **QA Scenarios**:
  ```
  Scenario: Validate player_paddle_posture.gd after fix
    Tool: godot_validate
    Steps: [same pattern as Task 1]
    Evidence: .sisyphus/evidence/task-5-validate.json
  ```

  **Commit**: YES (Wave 2 commit)

- [ ] 6. **pose_controller.gd** — cold-path PostureDefinition + Ball vars

  **What to do**:
  - Read file to find:
    - `var stroke_def: PostureDefinition = def_override` (~line 82) → type erasure
    - `var ball: Ball = _player._get_ball_ref() as Ball` (~line 122) → `Ball` class_name — remove annotation
    - `var ball: Ball` (~line 287) → another Ball reference → remove annotation
  - Note: `_library` already untyped from prior session — don't touch
  - `_player` is PlayerController (built-in parent) — don't touch

  **Pattern**:
  ```gdscript
  # Before:
  var stroke_def: PostureDefinition = def_override
  var ball: Ball = _player._get_ball_ref() as Ball
  # After:
  var stroke_def = def_override
  var ball = _player._get_ball_ref() as Ball
  ```

  **Recommended Agent Profile**:
  - **Category**: `quick`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 5, 7, 8)
  - **Blocks**: Wave FINAL
  - **Blocked By**: None

  **Acceptance Criteria**:
  - [ ] `godot_validate scripts/pose_controller.gd` → `valid: true`, 0 errors

  **QA Scenarios**:
  ```
  Scenario: Validate pose_controller.gd after fix
    Tool: godot_validate
    Steps: [same pattern as Task 1]
    Evidence: .sisyphus/evidence/task-6-validate.json
  ```

  **Commit**: YES (Wave 2 commit)

- [ ] 7. **transition_player.gd** — 4 cold-path PostureDefinition vars

  **What to do**:
  - Read file to find:
    - `var _ready_def: PostureDefinition = null` (~line 28)
    - `var _charge_def: PostureDefinition = null` (~line 29)
    - `var _contact_def: PostureDefinition = null` (~line 30)
    - `var blended: PostureDefinition = from_def.lerp_with(to_def, t)` (~line 224)
  - Change all 4: type erasure
  - Do NOT touch `_player: PlayerController` (~line 34)

  **Pattern**: Type erasure on all 4

  **Recommended Agent Profile**:
  - **Category**: `quick`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 5, 6, 8)
  - **Blocks**: Wave FINAL
  - **Blocked By**: None

  **Acceptance Criteria**:
  - [ ] `godot_validate scripts/posture_editor/transition_player.gd` → `valid: true`, 0 errors

  **QA Scenarios**:
  ```
  Scenario: Validate transition_player.gd after fix
    Tool: godot_validate
    Steps: [same pattern as Task 1]
    Evidence: .sisyphus/evidence/task-7-validate.json
  ```

  **Commit**: YES (Wave 2 commit)

- [ ] 8. **gizmo_controller.gd** — 2 cold-path GizmoHandle vars

  **What to do**:
  - Read file to find:
    - `var _selected_gizmo: GizmoHandle = null` (~line 17)
    - `var _hovered_gizmo: GizmoHandle = null` (~line 18)
  - Change both: type erasure
  - Do NOT touch `_camera: Camera3D` (built-in type)
  - Do NOT touch local `var closest_gizmo: GizmoHandle` (~line 79) — local vars fine, don't change

  **Pattern**: Type erasure on class-level vars only

  **Recommended Agent Profile**:
  - **Category**: `quick`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 5, 6, 7)
  - **Blocks**: Wave FINAL
  - **Blocked By**: None

  **Acceptance Criteria**:
  - [ ] `godot_validate scripts/posture_editor/gizmo_controller.gd` → `valid: true`, 0 errors

  **QA Scenarios**:
  ```
  Scenario: Validate gizmo_controller.gd after fix
    Tool: godot_validate
    Steps: [same pattern as Task 1]
    Evidence: .sisyphus/evidence/task-8-validate.json
  ```

  **Commit**: YES (Wave 2 commit)

- [ ] 9. **charge_tab.gd** — `_def` + cold-path UI child vars

  **What to do**:
  - Read file to find all class-level vars:
    - `var _def: PostureDefinition = null` (~line 5) → type erasure
    - `var _paddle_off: Vector3Editor` (~line 7) → type erasure (class_name)
    - `var _paddle_rot: Vector3Editor` (~line 8) → type erasure
    - `var _body_rot: SliderField` (~line 9) → type erasure
    - `var _hip_coil: SliderField` (~line 10) → type erasure
    - `var _back_foot_load: SliderField` (~line 11) → type erasure
  - All are cold-path (editor tab, only accessed when tab is open)
  - Do NOT touch built-in type vars if any

  **Pattern**: Type erasure on all class-level custom-type vars

  **Recommended Agent Profile**:
  - **Category**: `quick`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 10, 11, 12, 13, 14, 15)
  - **Blocks**: Wave FINAL
  - **Blocked By**: None

  **Acceptance Criteria**:
  - [ ] `godot_validate scripts/posture_editor/tabs/charge_tab.gd` → `valid: true`, 0 errors

  **QA Scenarios**:
  ```
  Scenario: Validate charge_tab.gd after fix
    Tool: godot_validate
    Steps: [same pattern as Task 1]
    Evidence: .sisyphus/evidence/task-9-validate.json
  ```

  **Commit**: YES (Wave 3 commit)

- [ ] 10. **paddle_tab.gd** — `_def` + cold-path UI child vars

  **What to do**:
  - Read file — it has MANY class-level typed vars:
    - `var _def: PostureDefinition = null` → type erasure
    - All `SliderField` and `Vector3Editor` typed class-level vars → type erasure
  - Count: ~20 class-level vars total (SliderField, Vector3Editor, OptionButton, CheckButton — all class_name types)
  - All cold-path — editor only
  - Do NOT touch built-in `Control`-derived type annotations if any exist

  **Recommended Agent Profile**:
  - **Category**: `quick`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 9, 11, 12, 13, 14, 15)
  - **Blocks**: Wave FINAL
  - **Blocked By**: None

  **Acceptance Criteria**:
  - [ ] `godot_validate scripts/posture_editor/tabs/paddle_tab.gd` → `valid: true`, 0 errors

  **QA Scenarios**:
  ```
  Scenario: Validate paddle_tab.gd after fix
    Tool: godot_validate
    Steps: [same pattern as Task 1]
    Evidence: .sisyphus/evidence/task-10-validate.json
  ```

  **Commit**: YES (Wave 3 commit)

- [ ] 11. **follow_through_tab.gd** — `_def` + cold-path UI child vars

  **What to do**:
  - Same pattern as Task 9/10
  - `var _def: PostureDefinition = null` → type erasure
  - All SliderField/Vector3Editor class-level vars → type erasure

  **Recommended Agent Profile**:
  - **Category**: `quick`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 9, 10, 12, 13, 14, 15)
  - **Blocks**: Wave FINAL
  - **Blocked By**: None

  **Acceptance Criteria**:
  - [ ] `godot_validate scripts/posture_editor/tabs/follow_through_tab.gd` → `valid: true`, 0 errors

  **QA Scenarios**:
  ```
  Scenario: Validate follow_through_tab.gd after fix
    Tool: godot_validate
    Steps: [same pattern as Task 1]
    Evidence: .sisyphus/evidence/task-11-validate.json
  ```

  **Commit**: YES (Wave 3 commit)

- [ ] 12. **legs_tab.gd** — cold-path UI child vars only (no `_def`)

  **What to do**:
  - Read file — it has NO `_def` PostureDefinition var (it's `_def: Resource = null` — Resource is built-in)
  - BUT has many `SliderField` and `Vector3Editor` class-level vars (~line 10-29)
  - All class-level custom type vars → type erasure
  - `Resource` typed vars are built-in — don't touch

  **Recommended Agent Profile**:
  - **Category**: `quick`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 9, 10, 11, 13, 14, 15)
  - **Blocks**: Wave FINAL
  - **Blocked By**: None

  **Acceptance Criteria**:
  - [ ] `godot_validate scripts/posture_editor/tabs/legs_tab.gd` → `valid: true`, 0 errors

  **QA Scenarios**:
  ```
  Scenario: Validate legs_tab.gd after fix
    Tool: godot_validate
    Steps: [same pattern as Task 1]
    Evidence: .sisyphus/evidence/task-12-validate.json
  ```

  **Commit**: YES (Wave 3 commit)

- [ ] 13. **torso_tab.gd** — cold-path UI child vars

  **What to do**:
  - Read file — has `SliderField` class-level vars
  - All class-level custom-type vars → type erasure
  - No `_def` PostureDefinition var

  **Recommended Agent Profile**:
  - **Category**: `quick`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 9, 10, 11, 12, 14, 15)
  - **Blocks**: Wave FINAL
  - **Blocked By**: None

  **Acceptance Criteria**:
  - [ ] `godot_validate scripts/posture_editor/tabs/torso_tab.gd` → `valid: true`, 0 errors

  **QA Scenarios**:
  ```
  Scenario: Validate torso_tab.gd after fix
    Tool: godot_validate
    Steps: [same pattern as Task 1]
    Evidence: .sisyphus/evidence/task-13-validate.json
  ```

  **Commit**: YES (Wave 3 commit)

- [ ] 14. **arms_tab.gd** — cold-path UI child vars

  **What to do**:
  - Read file — has `Vector3Editor` class-level vars
  - All class-level custom-type vars → type erasure
  - No `_def` PostureDefinition var

  **Recommended Agent Profile**:
  - **Category**: `quick`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 9, 10, 11, 12, 13, 15)
  - **Blocks**: Wave FINAL
  - **Blocked By**: None

  **Acceptance Criteria**:
  - [ ] `godot_validate scripts/posture_editor/tabs/arms_tab.gd` → `valid: true`, 0 errors

  **QA Scenarios**:
  ```
  Scenario: Validate arms_tab.gd after fix
    Tool: godot_validate
    Steps: [same pattern as Task 1]
    Evidence: .sisyphus/evidence/task-14-validate.json
  ```

  **Commit**: YES (Wave 3 commit)

- [ ] 15. **head_tab.gd** — cold-path UI child vars

  **What to do**:
  - Read file — has `SliderField` class-level vars
  - All class-level custom-type vars → type erasure
  - No `_def` PostureDefinition var

  **Recommended Agent Profile**:
  - **Category**: `quick`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 9, 10, 11, 12, 13, 14)
  - **Blocks**: Wave FINAL
  - **Blocked By**: None

  **Acceptance Criteria**:
  - [ ] `godot_validate scripts/posture_editor/tabs/head_tab.gd` → `valid: true`, 0 errors

  **QA Scenarios**:
  ```
  Scenario: Validate head_tab.gd after fix
    Tool: godot_validate
    Steps: [same pattern as Task 1]
    Evidence: .sisyphus/evidence/task-15-validate.json
  ```

  **Commit**: YES (Wave 3 commit)

---

## Final Verification Wave

- [ ] F1. **Full Boot Clean** — `godot_run_project` → `godot_get_debug_output` → no `Debugger Break` / `Parser Error` (warnings OK)
- [ ] F2. **`godot_validate` on ALL 15 modified files** — all `valid: true`
- [ ] F3. **`4` key probe** — `godot_simulate_input([{type:"key",key:"4",pressed:true}])` → all 4 sections print `MATCHES`

---

## Boot-Discovered Fixes (Post-Wave — Found During Final Verification)

These issues were exposed only when running a fresh `.godot/` cache boot. The prior validation approach missed them because `godot_validate` on individual files doesn't fully exercise cross-script parse-time resolution.

### Issue A: `_is_low_bh` Type Inference Cascade (player_ai_brain.gd:674)

**Root Cause**: After type-erasing `_player` to untyped, `_player.ai_desired_posture` is `Variant`. The `in` operator with Variant operands returns `Variant`, not `bool`. The chained `or` expression `Variant == int or Variant == int or ...` becomes an untyped `Variant` expression. Godot's `:=` inference cannot determine the final type → parse error.

**Affected lines**:
- `player_ai_brain.gd:674` — `var _is_low_bh := (...)` — fails
- `player_ai_brain.gd:686` — `var _is_low := (...)` — same pattern, will also fail

**Fix**: Change `:=` (type inference) to `: bool =` (explicit annotation) for both variables.

### Issue B: PlayerController.AIState Enum References (player_ai_brain.gd)

**Root Cause**: `var ai_state: int = PlayerController.AIState.INTERCEPT_POSITION` — `PlayerController` class_name not resolved at parse time.

**Fix**: Replace `PlayerController.AIState` with local `AIState` enum (already done).

### Issue C: PlayerController Type Annotation (player_body_builder.gd:3)

**Root Cause**: `var _player: PlayerController = null` — class_name not resolved at parse time.

**Fix**: Type erase to `var _player = null` (already done).

### Systemic Pattern: `:= (...)` With Variant-Cascaded Operands

All files that use `:= (...)` type-inference assignment where the expression contains:
1. Access to a property on a now-untyped `_player` reference (Variant), AND
2. Boolean operators (`or`, `and`)

Are candidates for the same inference failure. Files to audit:
- `player_debug_visual.gd:447` — `in_kitchen := (_player.player_num == 0 ...) or ...`
- Any other `:= (...)` pattern involving `_player` (untyped)

The `_player.player_num` access returns `int` (primitive), so `in_kitchen` likely still infers correctly. But `_player.ai_desired_posture` returns `Variant` (property on untyped reference), which breaks `in` operator and cascades.

---

## TODOs — Boot-Discovered Fixes

- [ ] A1. **player_ai_brain.gd `_is_low_bh`** — Change `var _is_low_bh := (...)` to `var _is_low_bh: bool = (...)`

  **Must NOT do**: Change any logic — only change `:=` to `: bool =`

  **Acceptance Criteria**:
  - [ ] `godot_validate scripts/player_ai_brain.gd` → `valid: true`

- [ ] A2. **player_ai_brain.gd `_is_low`** — Change `var _is_low := (...)` to `var _is_low: bool = (...)`

  **Must NOT do**: Change any logic — only change `:=` to `: bool =`

  **Acceptance Criteria**:
  - [ ] Fresh boot with `_is_low_bh` fix shows no new errors at line 686

- [ ] A3. **player_debug_visual.gd `in_kitchen`** — Audit `:= (...)` at line 447. If it fails boot, add `: bool` annotation.

  **Audit first**: Do fresh boot — if it fails with type inference error at this line, fix it. Otherwise leave unchanged.

  **Must NOT do**: Change any logic

- [ ] A4. **Fresh Boot Full Pass** — After A1 and A2 (and A3 if needed):
  1. `godot_stop_project`
  2. `pkill -f "Godot.app"`
  3. `rm -rf .godot/`
  4. `godot_run_project background=true`
  5. Wait 15s
  6. `godot_get_debug_output` → must show NO `Debugger Break` / `Parser Error`

- [ ] A5. **`4` Key Probe** — After A4 passes:
  1. `godot_simulate_input([{type:"key",key:"4",pressed:true}])`
  2. Wait 8s
  3. `godot_get_debug_output` → all 4 sections print `MATCHES`

---

## Success Criteria

```bash
# Final boot check — warnings only, no debugger breaks
godot_get_debug_output() → no "Debugger Break" | no "Parser Error"

# Probe verification — all sections MATCH
grep "MATCHES" evidence → 4+ matches
```

---

## Commit Strategy

- **1**: `fix(classname): remove class_name type annotations from hot-path player modules` — Wave 1 files
- **2**: `fix(classname): remove class_name type annotations from cold-path files` — Wave 2 files
- **3**: `fix(classname): remove class_name type annotations from editor tab files` — Wave 3 files
