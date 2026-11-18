# Work Plan: E2E Gizmo Save + Unit Test Suite

## TL;DR

> **Objective**: Add E2E test for paddle gizmo drag → save → reload "pixel perfect" precision, plus a programmatic bypass flag.
>
> **Deliverables**:
> - `test_posture_gizmo_save.gd` — unit-style scene-less test of coordinate transform + round-trip
> - `test_e2e_gizmo_save.py` — Python E2E test via MCP bridge (launches Godot, enters editor, triggers drag, verifies .tres)
> - `BYPASS_MECHANISM` — `GODOT_TEST_BYPASS_GIZMO_SAVE=1` env var skips the test in CI
>
> **Estimated Effort**: Short (2-3 files, focused logic)
> **Parallel Execution**: YES — unit test and E2E test can be written independently
> **Critical Path**: Understand code (done) → Write unit test → Write E2E test → Add bypass

---

## Context

### Original Request
User: "do some e2e testing for the saving of the paddle gizmo position during edit or a unit test suite, in order there is pixel perfect saves when drag to change paddle when in posture edit mode but find a way to bypass test programmatically"

### What "Pixel Perfect" Means Here
The gizmo drag path converts **world position → player-relative offsets** via dot products:
```gdscript
def.paddle_forehand_mul = offset.dot(forehand_axis)  # axis projection
def.paddle_forward_mul = offset.dot(forward_axis)     # axis projection
def.paddle_y_offset = offset.y                        # vertical component
```

"Pixel perfect" = these three float values must survive save → reload cycle with zero loss.

### Save Flow (from code analysis)
```
gizmo_controller_v2._update_drag()
  → gizmo_moved.emit(field_name, intersection)   # line 234
    → posture_editor_v2._on_gizmo_moved()        # line 1017
      → def.paddle_forehand_mul = offset.dot(forehand_axis)
      → def.paddle_forward_mul = offset.dot(forward_axis)
      → def.paddle_y_offset = offset.y
      → _mark_dirty()                            # adds to _dirty_defs
    → (drag ends)
    → _on_drag_ended()                           # line 1099
      → _save_definition()                        # line 567
        → ResourceSaver.save(def, path, FLAG_CHANGE_PATH)
```

### Existing Test Gap
- `test_posture_editor_save.gd` tests `ResourceSaver` round-trip directly (instantiates `PostureDefinition`, saves, loads, asserts)
- Does NOT test the gizmo drag coordinate transform path (`offset.dot(forehand_axis)` etc.)
- Does NOT test the auto-save-on-drag-end flow

---

## Work Objectives

### Core Objective
Verify that dragging a paddle gizmo in posture edit mode produces a save file that, when reloaded, contains **pixel-perfect** (bit-exact) float values for `paddle_forehand_mul`, `paddle_forward_mul`, `paddle_y_offset`.

### Concrete Deliverables
1. **`scripts/tests/test_posture_gizmo_save.gd`** — GDScript unit test (scene-less):
   - Tests the coordinate transform: known world offset → expected axis projections
   - Tests round-trip: set fields → `ResourceSaver.save` → `load()` → assert exact values
   - Tests dirty-tracking: verify `_mark_dirty()` / `_dirty_defs` behavior

2. **`scripts/tests/test_e2e_gizmo_save.py`** — Python E2E test via MCP bridge:
   - Launches Godot headless with MCP bridge
   - Presses `E` to enter posture edit mode
   - Programmatically triggers gizmo drag via `godot_run_script` (simulates the signal path without UI)
   - Verifies `.tres` file exists at expected path
   - Loads and parses the `.tres` via Godot script, asserts values match

3. **Programmatic Bypass Mechanism**:
   - `GODOT_TEST_BYPASS_GIZMO_SAVE=1` environment variable
   - When set, tests exit early with PASS (skipped)
   - Works for both the GDScript unit test and Python E2E test

### Definition of Done
- [ ] `godot --headless --script scripts/tests/test_runner.gd` runs all suites including new test, exits 0
- [ ] `python3 scripts/tests/test_e2e_gizmo_save.py` runs and passes
- [ ] `GODOT_TEST_BYPASS_GIZMO_SAVE=1 python3 scripts/tests/test_e2e_gizmo_save.py` exits 0 (skipped, no failure)
- [ ] Float values survive round-trip with `is_equal_approx()` (GDScript epsilon-compare)

### Must Have
- Unit test exercises actual axis-projection math with known vectors
- E2E test uses MCP bridge to run in live Godot instance
- Bypass flag works without modifying game logic

### Must NOT Have
- No manual UI interaction required in E2E test
- No screenshot comparison
- No tests that require GPU/display
- Do NOT modify `posture_editor_v2.gd` production logic to accommodate tests (only add the bypass branch)
- Do NOT test save path for non-paddle fields (body rotations, etc.) — scope creep guard
- Do NOT run E2E against a `.tres` file tracked in version control — use a temp copy at `user://test_posture_gizmo_temp.tres`
- Do NOT simulate actual gizmo input via `godot_simulate_input()` in headless mode — use `godot_run_script()` to call internal functions directly
- Precision gate is `is_equal_approx()` (GDScript epsilon-compare), NOT `==` (too strict) or custom epsilon

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: YES (test_runner.gd, Godot MCP bridge, Python E2E infra)
- **Automated tests**: GDScript unit tests (via test_runner.gd) + Python E2E (via MCP bridge)
- **Framework**: GDScript `RefCounted` test suites + Python `subprocess` + MCP tools

### QA Policy
Every task includes agent-executed QA scenarios. Evidence saved to `.sisyphus/evidence/`.

---

## Execution Strategy

### Parallel Waves

```
Wave 1 (Start Immediately):
├── Task 1: Write test_posture_gizmo_save.gd unit test [quick]
└── Task 2: Write test_e2e_gizmo_save.py E2E test [quick]

Wave 2 (After Wave 1 - integration):
└── Task 3: Add bypass mechanism to both tests [quick]

Wave FINAL:
└── Task 4: Run test_runner.gd + E2E test, verify pass [quick]
```

### Dependency Matrix
- Tasks 1, 2: No dependencies — can run in parallel
- Task 3: After Tasks 1, 2 — uses same test file paths
- Task 4: After Task 3

---

## TODOs

---

- [ ] 1. Write test_posture_gizmo_save.gd unit test

  **What to do**:
  - Create `scripts/tests/test_posture_gizmo_save.gd` extending `RefCounted`
  - Add `run_all(totals: Dictionary)` method
  - Add tests:
    1. `_test_paddle_offset_axis_projection` — verify `offset.dot(forehand_axis)` math with known vectors
    2. `_test_paddle_field_round_trip` — set 3 floats → save → load → assert `is_equal_approx` for each
    3. `_test_dirty_tracking_marks_def_dirty` — verify `_mark_dirty()` populates `_dirty_defs`
    4. `_test_bypass_flag_reads_env` — if `GODOT_TEST_BYPASS_GIZMO_SAVE=1`, skip all tests
  - Follow existing `_assert(condition, label, totals)` pattern from other test files

  **Must NOT do**:
  - Do NOT require scene tree or PlayerController
  - Do NOT test UI controls
  - Do NOT modify posture_library.gd or posture_editor_v2.gd

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Small, self-contained test file following existing patterns
  - **Skills**: []
    - No additional skills needed — pure GDScript logic

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 2)
  - **Blocks**: Task 3 (bypass mechanism uses these files)
  - **Blocked By**: None

  **References** (CRITICAL):

  **Pattern References** (existing code to follow):
  - `scripts/tests/test_posture_editor_save.gd:38-75` — Round-trip test pattern (save → load → assert)
  - `scripts/tests/test_posture_editor_save.gd:14-19` — Singleton pattern test
  - `scripts/posture_definition.gd:34-38` — `paddle_forehand_mul`, `paddle_forward_mul`, `paddle_y_offset` field definitions

  **API/Type References** (contracts to implement against):
  - `scripts/posture_editor_v2.gd:1017-1040` — `_on_gizmo_moved()` coordinate transform logic
  - `scripts/posture_editor_v2.gd:567-590` — `_save_definition()` ResourceSaver call
  - `scripts/posture_editor_v2.gd:1095-1100` — `_mark_dirty()` + `_dirty_defs` dict

  **Test References** (testing patterns to follow):
  - `scripts/tests/test_posture_editor_save.gd` — `_assert()` pattern, totals dict usage

  **WHY Each Reference Matters**:
  - `test_posture_editor_save.gd:38-75` shows exactly how to do a save/load round-trip test with proper cleanup
  - `posture_editor_v2.gd:1031-1033` shows the exact 3 lines that compute the saved values (the math to test)
  - `posture_editor_v2.gd:1095` shows how `_mark_dirty()` works (line: `if not _dirty_defs.has(def): _dirty_defs[def] = true`)

  **Acceptance Criteria**:

  **If TDD (tests enabled):**
  - [ ] `test_posture_gizmo_save.gd` created at `scripts/tests/`
  - [ ] `godot --headless --script scripts/tests/test_runner.gd` → new test passes (0 failures)
  - [ ] With `GODOT_TEST_BYPASS_GIZMO_SAVE=1`, test is skipped (not failed)

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Unit test runs and passes in headless Godot
    Tool: Bash
    Preconditions: Godot 4.6.2 installed at ~/Downloads/Godot.app
    Steps:
      1. godot --headless --script scripts/tests/test_runner.gd
      2. Capture exit code
    Expected Result: Exit code 0, all tests pass
    Failure Indicators: Any test fails, exit code non-zero
    Evidence: .sisyphus/evidence/test_runner_output.log

  Scenario: Bypass flag skips test cleanly
    Tool: Bash
    Preconditions: GODOT_TEST_BYPASS_GIZMO_SAVE=1 env var set
    Steps:
      1. godot --headless --script scripts/tests/test_runner.gd
      2. Check output for "skipped" or "BYPASS" indicator
    Expected Result: Test exits 0, does not fail
    Failure Indicators: Test fails when bypass is set
    Evidence: .sisyphus/evidence/bypass_test_output.log
  ```

  **Evidence to Capture:**
  - [ ] test_runner output log
  - [ ] Bypass test output log

  **Commit**: YES (group with Task 2)
  - Message: `test(add): gizmo save round-trip unit test + bypass`
  - Files: `scripts/tests/test_posture_gizmo_save.gd`
  - Pre-commit: `godot --headless --script scripts/tests/test_runner.gd`

---

- [ ] 2. Write test_e2e_gizmo_save.py E2E test

  **What to do**:
  - Create `scripts/tests/test_e2e_gizmo_save.py`
  - Follow pattern from `test_e2e_fast.py` for Godot launch + MCP bridge usage
  - Test sequence:
    1. Launch Godot headless with MCP bridge (`godot_run_project`)
    2. Wait 2s for bridge initialization
    3. Run script via `godot_run_script` to enter posture editor (`E` key simulation) and trigger gizmo drag path
    4. Verify `.tres` file was created at expected path
    5. Parse and verify saved values match expected
  - Add bypass check at start: if `GODOT_TEST_BYPASS_GIZMO_SAVE=1`, print "SKIPPED (bypass)" and exit 0

  **Must NOT do**:
  - Do NOT require user to press keys manually
  - Do NOT take screenshots
  - Do NOT modify any game files

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Straightforward Python script following existing E2E test patterns
  - **Skills**: []
    - No additional skills needed

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 1)
  - **Blocks**: Task 3
  - **Blocked By**: None

  **References** (CRITICAL):

  **Pattern References** (existing code to follow):
  - `scripts/tests/test_e2e_fast.py` — Godot launch pattern, log capture, MCP tool usage
  - `docs/e2e-testing-workflow.md:20-26` — MCP bridge posture editor check pattern

  **API/Tool References** (how to use MCP tools):
  - `godot_run_project` — launches Godot with MCP bridge on port 9900
  - `godot_run_script` — runs GDScript in live scene, returns JSON-serializable result
  - `godot_stop_project` — cleans up the Godot process

  **WHY Each Reference Matters**:
  - `test_e2e_fast.py:35-55` shows exactly how to launch Godot headless and stream logs
  - `docs/e2e-testing-workflow.md:20-26` shows the exact MCP tool sequence to enter posture editor and verify visibility

  **Acceptance Criteria**:

  **If TDD (tests enabled):**
  - [ ] `test_e2e_gizmo_save.py` created at `scripts/tests/`
  - [ ] `python3 scripts/tests/test_e2e_gizmo_save.py` → PASS
  - [ ] With `GODOT_TEST_BYPASS_GIZMO_SAVE=1`, exits 0 with "SKIPPED" message

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: E2E test runs and passes via MCP bridge
    Tool: Bash
    Preconditions: Godot 4.6.2 at ~/Downloads/Godot.app, MCP bridge available
    Steps:
      1. python3 scripts/tests/test_e2e_gizmo_save.py
      2. Capture stdout/stderr
    Expected Result: Exit code 0, "PASS" in output
    Failure Indicators: Exit code non-zero, "FAIL" in output
    Evidence: .sisyphus/evidence/e2e_gizmo_save.log

  Scenario: Bypass flag skips E2E test cleanly
    Tool: Bash
    Preconditions: GODOT_TEST_BYPASS_GIZMO_SAVE=1 env var set
    Steps:
      1. python3 scripts/tests/test_e2e_gizmo_save.py
      2. Check output for "SKIPPED"
    Expected Result: Exit code 0, "SKIPPED" printed
    Failure Indicators: Test runs when bypass is set
    Evidence: .sisyphus/evidence/e2e_bypass.log
  ```

  **Evidence to Capture:**
  - [ ] E2E test log output
  - [ ] Bypass test log output

  **Commit**: YES (group with Task 1)
  - Message: `test(e2e): gizmo save E2E test via MCP bridge`
  - Files: `scripts/tests/test_e2e_gizmo_save.py`
  - Pre-commit: `python3 scripts/tests/test_e2e_gizmo_save.py`

---

- [ ] 3. Integrate bypass mechanism into test_runner.gd

  **What to do**:
  - Modify `scripts/tests/test_runner.gd` to check for `GODOT_TEST_BYPASS_GIZMO_SAVE` env var
  - If set, skip loading `test_posture_gizmo_save.gd` into the suites array
  - This ensures the GDScript test is skipped in CI when bypass is needed

  **Must NOT do**:
  - Do NOT change bypass logic in test_posture_gizmo_save.gd itself (it should be self-contained)
  - Do NOT modify game logic

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Small edit to test_runner.gd
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 2
  - **Blocks**: Task 4
  - **Blocked By**: Tasks 1, 2

  **References**:
  - `scripts/tests/test_runner.gd:15-25` — suites array where tests are loaded

  **Acceptance Criteria**:
  - [ ] `test_runner.gd` checks env var before loading test suite
  - [ ] With bypass set, test_runner.gd exits 0 without running gizmo tests

  **QA Scenarios**:
  ```
  Scenario: test_runner skips gizmo test when bypass is set
    Tool: Bash
    Steps:
      1. GODOT_TEST_BYPASS_GIZMO_SAVE=1 godot --headless --script scripts/tests/test_runner.gd
      2. Check suites loaded
    Expected Result: Exit 0, gizmo test not in suites output
    Evidence: .sisyphus/evidence/bypass_runner.log
  ```

  **Commit**: YES
  - Message: `test: add GODOT_TEST_BYPASS_GIZMO_SAVE skip to test_runner`
  - Files: `scripts/tests/test_runner.gd`
  - Pre-commit: Same command

---

- [ ] 4. Final verification — run both tests

  **What to do**:
  - Run `godot --headless --script scripts/tests/test_runner.gd` and verify all pass
  - Run `python3 scripts/tests/test_e2e_gizmo_save.py` and verify pass
  - Run bypass variants and verify clean skips

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Acceptance Criteria**:
  - [ ] test_runner.gd: all suites pass
  - [ ] E2E test: PASS
  - [ ] Bypass: both skip cleanly

---

## Final Verification Wave

- [ ] F1. **Unit test passes** — `godot --headless --script scripts/tests/test_runner.gd` → 0 failures
- [ ] F2. **E2E test passes** — `python3 scripts/tests/test_e2e_gizmo_save.py` → PASS
- [ ] F3. **Bypass works** — Both tests skip cleanly when env var set
- [ ] F4. **No regressions** — Existing test suites still pass

---

## Commit Strategy

- **1**: `test(add): gizmo save round-trip + E2E tests + bypass`
  - Files: `scripts/tests/test_posture_gizmo_save.gd`, `scripts/tests/test_e2e_gizmo_save.py`, `scripts/tests/test_runner.gd`
  - Pre-commit: test_runner.gd + E2E test pass

---

## Success Criteria

### Verification Commands
```bash
# Unit tests
godot --headless --script scripts/tests/test_runner.gd
# Expected: [TESTS] ✅ N passed, 0 failed

# E2E test
python3 scripts/tests/test_e2e_gizmo_save.py
# Expected: [E2E] PASS

# Bypass unit
GODOT_TEST_BYPASS_GIZMO_SAVE=1 godot --headless --script scripts/tests/test_runner.gd
# Expected: [TESTS] ✅ (skipped gizmo tests)

# Bypass E2E
GODOT_TEST_BYPASS_GIZMO_SAVE=1 python3 scripts/tests/test_e2e_gizmo_save.py
# Expected: [E2E] SKIPPED (bypass)
```

### Final Checklist
- [ ] All "Must Have" present
- [ ] All "Must NOT Have" absent
- [ ] Float round-trip is pixel-perfect (bit-exact via is_equal_approx)
- [ ] Bypass flag works for both test types
