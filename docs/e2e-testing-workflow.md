# E2E Testing Workflow — godot-pickleball

## Quick Reference

### 1. Fast Blocking System Test (~1.6s)
Headless, no screenshots, pure log parsing.

```bash
cd /Users/arjomagno/Documents/github-repos/pickleball-godot
python3 scripts/tests/test_e2e_fast.py
```
- **What it checks**: `[PURPLE]` fires in logs
- **Speed**: ~1.6s (10x engine time scale)
- **Env vars**: `GODOT_TEST_FAST=10.0`, `GODOT_TEST_AUTO_LAUNCH=1`
- **Output**: `e2e-fast.log`

---

### 2. Super-Fast Posture Editor Check (~150ms) — E key

```
/godot_run_project  → wait 2s
/godot_simulate_input → actions=[{key:"E", pressed:true}, {wait:50ms}, {key:"E", pressed:false}]
/godot_run_script → script="extends RefCounted|func execute(scene_tree) -> Variant:\n    var game = scene_tree.get_root().get_node(\"Game\")\n    var peui = null\n    for c in game.get_children():\n      if c is CanvasLayer:\n        peui = c.get_node_or_null(\"PostureEditorUI\")\n        break\n    return {visible: peui.visible if peui else false}"
```
**Result**: `{"visible": true}` — ~150ms end-to-end

---

### 3. Super-Fast Debug Visuals Check (~150ms) — Z key

Z cycles: OFF(0) → zones+visuals(1) → visuals-only(2) → OFF(0)...

```
/godot_run_project  → wait 2s
/godot_simulate_input → actions=[{key:"Z", pressed:true}, {wait:50ms}, {key:"Z", pressed:false}]
/godot_run_script → script="extends RefCounted|func execute(scene_tree) -> Variant:\n    var game = scene_tree.get_root().get_node(\"Game\")\n    var gd = game.get(\"game_debug_ui\")\n    if gd == null: return {error:\"null\"}\n    return {z_cycle: gd.get(\"_debug_z_cycle\")}"
```
**Result**: `{"z_cycle": 1}` — press again for 2, again for 0

---

### 4. Screenshot (foreground only)
```
/godot_run_project  (no background flag)
/godot_take_screenshot()
```
- Background mode = black screenshot
- Foreground mode = actual game view

---

## Key Godot Keycodes

| Key | Action | Queryable State |
|-----|--------|----------------|
| `E` | Toggle posture editor | `PostureEditorUI.visible` |
| `Z` | Cycle debug visuals (0→1→2→0) | `game_debug_ui._debug_z_cycle` (0=OFF, 1=zones+vis, 2=vis only) |
| `P` | Camera cycle | — |
| `4` | Launch practice ball | — |
| `SPACE` | Charge serve | — |

---

## Environment Variables for Tests

| Var | Effect |
|-----|--------|
| `GODOT_TEST_FAST=10.0` | 10x engine time scale via `time_scale_manager.gd` |
| `GODOT_TEST_AUTO_LAUNCH=1` | Auto-launch ball on `practice_launcher.gd` setup |

---

## Infrastructure

| Item | Detail |
|------|--------|
| **MCP Bridge** | Port 9900 UDP, internal only |
| **Bridge start** | `godot_run_project` → ready in ~2s |
| **Bridge stop** | `godot_stop_project` |
| **Screenshot path** | `.mcp/screenshots/` |
| **Evidence log** | `.sisyphus/evidence/e2e-fast.log` |

---

## Files

| File | Purpose |
|------|---------|
| `scripts/tests/test_e2e_fast.py` | Fast blocking system test (headless, ~1.6s) |
| `scripts/tests/test_posture_editor.py` | MCP-bridge posture editor check (template) |
| `scripts/time/time_scale_manager.gd` | 10x fast-forward via `GODOT_TEST_FAST` env var |
| `scripts/practice_launcher.gd` | Auto-launch via `GODOT_TEST_AUTO_LAUNCH` env var |
| `docs/e2e-testing-workflow.md` | This file |

---

## Auto-Pause + Screenshot on Key Moments (NOT YET WIRED)

When `GODOT_TEST_FAST` active + `[PURPLE✓]` fires:
1. `Engine.time_scale → 0` (instant freeze)
2. Take screenshot via MCP
3. Resume at 10x

Wiring: hook `time_scale_manager.gd` → detect `[PURPLE✓]` print → trigger screenshot.
