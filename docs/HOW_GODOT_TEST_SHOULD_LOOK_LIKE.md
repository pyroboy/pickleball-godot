# How Godot Tests Should Look Like

## The Golden Rule

**Every test in this project must be discoverable from a single entry point.**

If a test is not in `test_runner.gd` or `test_all_suites.gd`, it does not exist for CI/MCP purposes.

---

## Test Taxonomy

We have three kinds of tests. Know which one you are writing:

### 1. Unit Tests — `scripts/tests/test_*.gd`

- **Headless**: `godot --headless --script scripts/tests/test_runner.gd`
- **Deterministic**: fixed RNG seeds, no scene, no randomness
- **Pure**: fakes stub out Node/scene dependencies
- **Fast**: the full suite runs in ~1 second
- **Counted**: each `test_*` method in `Array[Callable]` = 1 pass/fail

**Template:**
```gdscript
class_name TestMyFeature extends TestBase
## What this tests and which fakes it uses.

const _MySystem := preload("res://scripts/my_system.gd")

func run_all(totals: Dictionary) -> void:
	var tests: Array[Callable] = [
		test_foo_computes_bar,
		test_foo_bounds,
	]
	_run_test_list(totals, tests)

func test_foo_computes_bar() -> void:
	var sys := _MySystem.new()
	var result := sys.compute(5.0)
	_assert_eq_f(result, 10.0, 0.001, "compute doubles input")

func test_foo_bounds() -> void:
	var sys := _MySystem.new()
	var result := sys.compute(100.0)
	_assert_le(result, 50.0, "compute clamps at max")
	_assert_ge(result, 0.0, "compute never goes negative")
```

**Rules:**
- Always `extends TestBase` — inherits `_assert_*` helpers and `_run_test_list()`
- Always use `class_name` — required for preloading in runners
- Always add to **both** `test_runner.gd` and `test_all_suites.gd`
- Always add to `test_editor_runner.gd` if you want editor convenience
- Never `push_error()` — use `_assert_true(cond, "msg")` instead

**Assertion helpers** (from `TestBase`):

| Helper | Usage |
|--------|-------|
| `_assert_true(cond, msg)` | Boolean must be true |
| `_assert_false(cond, msg)` | Boolean must be false |
| `_assert_eq(a, b, msg)` | Exact equality (Variant) |
| `_assert_eq_f(a, b, tol, msg)` | Float equality within tolerance |
| `_assert_eq_v3(a, b, tol, msg)` | Vector3 equality within distance |
| `_assert_gt(a, b, msg)` | a > b |
| `_assert_ge(a, b, msg)` | a >= b |
| `_assert_lt(a, b, msg)` | a < b |
| `_assert_le(a, b, msg)` | a <= b |
| `_assert_in_range(val, lo, hi, msg)` | lo <= val <= hi |

---

### 2. E2E Tests — `scripts/tests/e2e_*.gd` or standalone runners

- **Needs scene**: requires a running Game scene with ball, players, physics
- **Slower**: runs actual game loop for N frames
- **Integration**: tests cross-system behavior (swing → ball speed → landing)
- **Counted as 1**: the whole E2E script = 1 pass/fail

**Existing E2E tests:**

| File | What it tests | How to run |
|------|---------------|------------|
| `e2e_test_runner.gd` | Full rally: serve → AI return → player hit | Attach to scene, runs 120 frames |
| `_e2e_fast_mode.gd` | Fast-forward ball launch (10x) | Attach to scene |
| `test_e2e_gizmo_save_runner.gd` | Resource save/load round-trip | `godot --headless --script scripts/tests/test_e2e_gizmo_save_runner.gd` |
| `test_e2e_gizmo_save.py` | Python wrapper for gizmo save E2E | `python3 scripts/tests/test_e2e_gizmo_save.py` |

**Rules:**
- E2E tests are **NOT** in `test_runner.gd` — they need a scene
- They are launched individually or via MCP `run_script`
- They extend `SceneTree` or `Node`, not `TestBase`

---

### 3. Runtime Debug Tools — `scripts/tests/runtime/*.gd`

- **Interactive**: press a key in-game to trigger
- **Visual**: shows meshes, trajectories, debug overlays
- **NOT tests**: these are calibration probes and debug visualizers
- **Never headless**: requires rendered scene

**Existing runtime tools:**

| File | What it does | Trigger |
|------|--------------|---------|
| `game_drop_test.gd` | Kinematic drop test for BOUNCE_COR | Press T in-game |
| `drop_test.gd` | Older drop test (superseded) | — |
| `swing_e2e_probe.gd` | GAP-X paddle→ball speed probe | `game.run_swing_e2e_test()` from MCP |
| `ball_physics_probe.gd` | Trajectory sampler for physics tuning | Press 4 in-game |

**Rules:**
- Live in `scripts/tests/runtime/` — never in `scripts/` root
- Never added to `test_runner.gd`
- Documented in this file, not in CI

---

## Directory Layout

```
scripts/tests/
├── test_base.gd                  # Shared base class (TestBase)
├── test_runner.gd                # CLI entry point — ALL unit tests
├── test_all_suites.gd            # MCP entry point — ALL unit tests
├── test_editor_runner.gd         # Editor entry point — ALL unit tests
│
├── test_*.gd                     # Unit test suites (12+)
│   ├── test_shot_physics.gd
│   ├── test_ai_trajectory.gd
│   ├── test_rally_scorer.gd
│   └── ...
│
├── fakes/
│   ├── fake_player.gd
│   ├── fake_ball_node.gd
│   ├── fake_game.gd
│   └── ...
│
├── e2e_test_runner.gd            # E2E: full rally
├── _e2e_fast_mode.gd             # E2E: fast-forward
├── test_e2e_gizmo_save_runner.gd # E2E: resource round-trip
├── test_e2e_gizmo_save.py        # E2E: Python wrapper
│
└── runtime/
    ├── game_drop_test.gd         # Runtime: drop test
    ├── drop_test.gd              # Runtime: old drop test
    ├── swing_e2e_probe.gd        # Runtime: swing coupling probe
    └── ball_physics_probe.gd     # Runtime: trajectory sampler
```

---

## Checklist for Adding a New Unit Test

1. **Create** `scripts/tests/test_my_feature.gd`
2. **Extend `TestBase`** and use `class_name TestMyFeature`
3. **Build `Array[Callable]`** with `test_*` methods
4. **Call `_run_test_list(totals, tests)`**
5. **Use `_assert_*` helpers** — never `push_error()` or bare `if` + `print`
6. **Add to runners:**
   - `scripts/tests/test_runner.gd`
   - `scripts/tests/test_all_suites.gd`
   - `scripts/tests/test_editor_runner.gd`
7. **Run** `godot --headless --script scripts/tests/test_runner.gd`
8. **Commit** only when it passes

---

## Running Tests

### All unit tests (CLI)
```bash
godot --headless --script scripts/tests/test_runner.gd
```

### Single suite (CLI)
```bash
# Unit tests run through test_runner only. To test a single suite,
# temporarily edit test_runner.gd to comment out other suites.
```

### Editor (in Godot IDE)
```
Open scripts/tests/test_editor_runner.gd → Cmd+Shift+X (macOS) / Ctrl+Shift+X
```

### MCP
```gdscript
# Unit tests
TestAllSuites.new().execute(get_tree())

# E2E swing probe
game.run_swing_e2e_test()
```

### E2E gizmo save
```bash
python3 scripts/tests/test_e2e_gizmo_save.py
```

---

## Anti-Patterns (DO NOT)

❌ **Copy-paste assert helpers** — use `TestBase`  
❌ **Aggregate multiple scenarios into 1 counted test** — each scenario = 1 method  
❌ **Direct `totals` manipulation** — use `_run_test_list()`  
❌ **Scene-dependent unit tests** — use fakes, keep headless  
❌ **Unseeded RNG** — always set `_rng.seed` or `seed(value)`  
❌ **Put runtime debug tools in `scripts/` root** — use `scripts/tests/runtime/`  
❌ **Forget to add to all three runners** — `test_runner`, `test_all_suites`, `test_editor_runner`
