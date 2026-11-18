# Pickleball Game Testing Guide

## Philosophy

All game tests are **deterministic, headless, and pure**:
- **No scene required** — tests run with `godot --headless`
- **No randomness** — or controlled via fixed RNG seeds
- **No real game loop** — fakes stub out Node/scene dependencies
- **One assertion failure per test** — each test method counts as 1 pass/fail

This makes tests fast (~1s for the full suite), reproducible, and CI-friendly.

## Running Tests

### CLI (all suites)
```bash
godot --headless --script scripts/tests/test_runner.gd
```

### CLI (single suite)
```bash
godot --headless --script scripts/tests/test_shot_physics.gd
```

### MCP / E2E runner
```gdscript
TestAllSuites.new().execute(get_tree())
```

Exit code is `0` on pass, `1` on any failure.

## File Template

Create `scripts/tests/test_my_feature.gd`:

```gdscript
class_name TestMyFeature extends TestBase
## What this suite tests and which fakes it uses.
##
## Run via: godot --headless --script scripts/tests/test_runner.gd

const _MySystem := preload("res://scripts/my_system.gd")
const _FakePlayer := preload("res://scripts/tests/fakes/fake_player.gd")


func run_all(totals: Dictionary) -> void:
	var tests: Array[Callable] = [
		# Group tests by category with counts
		test_foo_does_bar,
		test_foo_bounds,
	]
	_run_test_list(totals, tests)


## ── Category Name ────────────────────────────────────────────────────────────

func test_foo_does_bar() -> void:
	var sys := _MySystem.new()
	var result := sys.compute(5.0)
	_assert_eq_f(result, 10.0, 0.001, "compute doubles input")


func test_foo_bounds() -> void:
	var sys := _MySystem.new()
	var result := sys.compute(100.0)
	_assert_le(result, 50.0, "compute clamps at max")
	_assert_ge(result, 0.0, "compute never goes negative")
```

## Checklist for Adding a New Suite

1. **Create file** at `scripts/tests/test_*.gd`
2. **Extend `TestBase`** — inherits all `_assert_*` helpers and `_run_test_list`
3. **Use `class_name`** — required for preloading in runners
4. **Build `Array[Callable]`** — list every `test_*` method
5. **Call `_run_test_list(totals, tests)`** — handles pass/fail counting
6. **Use `_assert_*` helpers** — never `push_error()` or manual `if` + `print`
7. **Add to runners**:
   - `scripts/tests/test_runner.gd` (CLI)
   - `scripts/tests/test_all_suites.gd` (MCP/E2E)
8. **Run the suite** — verify it passes before committing

## Assertion Helpers (from TestBase)

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

## Fakes

All fakes live in `scripts/tests/fakes/`:

| Fake | Extends | Use when testing... |
|------|---------|---------------------|
| `FakePlayer` | `Node` | Anything reading `global_position`, `get_player_num()`, `get_paddle_position()` |
| `FakeBallNode` | `Node` | `ShotPhysics.setup()` which expects a Node with ball properties |
| `FakeBall` | `RefCounted` | `RallyScorer` which expects a lightweight ball object |
| `FakeGame` | `RefCounted` | `PlayerAIBrain` which calls `compute_shot_spin()`, sweet-spot helpers |
| `FakePlayerAI` | `FakePlayer` | AI trajectory tests — adds `ai_desired_posture`, `min_z`, `max_z` |

Add new fakes only when the existing ones don't expose the surface your system needs.

## Test Granularity Rules

- **One scenario per test method** — if you have 7 scenarios, you have 7 methods in `Array[Callable]`
- **One pass/fail per method** — `_run_test_list` counts each callable as 1 test
- **Use rate thresholds for probabilistic tests** — e.g. `_assert_ge(rate, 95.0, "...")`
- **Print rates for visibility** — `print("S1 Baseline: %d/%d (%.1f%%)" % [p, t, rate])`
- **Never aggregate multiple scenarios into 1 counted test** — this loses failure granularity

## Anti-Patterns

❌ **Direct `totals` manipulation** (Pattern C) — breaks the uniform `_run_test_list` model  
❌ **Single `_failures` array for entire suite** — counts N scenarios as 1 test  
❌ **Copy-pasting assert helpers** — use `TestBase` instead  
❌ **Scene-dependent setup** — keep tests headless; use fakes  
❌ **Unseeded RNG** — always set `_rng.seed` or call `seed(value)` for determinism

## Forehand keyframe integration

The full-body swing test runs the actual game scene and editor, in addition to the unit suites above:

```bash
godot --headless --path . --script res://scripts/tests/test_forehand_keyframes.gd
godot --headless --path . --script res://scripts/tests/test_game_ui_flow.gd
```

It checks the three authored stages on both players, arm reach throughout the swing, body/paddle inspector signals, planted feet, gizmo editing, nested keyframe save/reload/revert, and partial charge continuity.

## Human incoming contact and held Space

```bash
godot --headless --path . --script res://scripts/tests/test_human_incoming_contact.gd
```

This runs normal game scenes and the actual input polling, pose selection, charge, timed strike and hit path. It covers 22 controlled returns across lateral lanes, low/normal/high balls, spin, fast/soft shots and a required bounce. It checks actual paddle-to-ball distance at the hit signal, prediction against live impact, pose switching while held, unreachable balls, queued-flight invalidation, recovery, rally charge instructions, and cancelling charge when opening the editor or sound panel. It is separate from the pure unit runner.

## Every authored stroke

```bash
godot --headless --path . --script res://scripts/tests/test_all_stroke_poses.gd
godot --headless --path . --script res://scripts/tests/test_all_stroke_contacts.gd
```

The first checks all 21 poses on both sides of the court, body/paddle preview alignment, both arms' reach, floor clearance, planted feet and keyframe save/reload. The second runs 54 actual gameplay returns: all 18 receiving poses at three charge levels, requiring the correct selected posture, paddle hand, single hit and contact error within 0.10 m.
