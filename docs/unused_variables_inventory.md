# Unused Variables Inventory

This document tracks variables that were identified as unused/dead code in the codebase.

## Summary

| Status | Count |
|--------|-------|
| **Resolved** | 10 |
| **Total Analyzed** | 65 files (~600 vars) |

## Resolved (Removed)

| File | Variable | Line | Reason |
|------|----------|------|--------|
| `player_paddle_posture.gd` | `_first_green_posture` | 152 | Kept for debug logging but never used in logging |
| `player_paddle_posture.gd` | `_last_lit_postures` | 153 | Declared for change-detection but never used |
| `player_paddle_posture.gd` | `_posture_hold_timer` | 123 | Write-only - only set to 0, never read |
| `game.gd` | `_last_volley_player` | 83 | Write-only - only set to -1, never read |
| `game.gd` | `_serve_was_hit` | 84 | Write-only - only set to false, never read |
| `player_hitting.gd` | `charge_animation_tween` | 27 | Declared but never used |
| `player_hitting.gd` | `ai_trajectory_mesh_instance` | 31 | Duplicate - exists in player_ai_brain.gd |
| `player_hitting.gd` | `ai_trajectory_mesh` | 32 | Duplicate - exists in player_ai_brain.gd |
| `player_hitting.gd` | `ai_trajectory_material` | 33 | Duplicate - exists in player_ai_brain.gd |
| `player_hitting.gd` | `ai_trajectory_timer` | 34 | Duplicate - exists in player_ai_brain.gd |
| `player_hitting.gd` | `ai_hit_cooldown` | 37 | Duplicate - exists in player_ai_brain.gd |

**Date Resolved**: 2026-04-11

---

## Analysis Notes

### game.gd
- `_last_volley_player` and `_serve_was_hit` were leftover from refactoring
- The actual implementations exist in `rally_scorer.gd` where they are properly used

### player_paddle_posture.gd
- `_posture_hold_timer` was a vestigial timer that was reset but never read/used
- `_hit_posture` IS used (line 1117: `posture == _hit_posture`) - **not removed**

### player_hitting.gd
- AI trajectory and cooldown variables were moved to `player_ai_brain.gd`
- The declarations in player_hitting.gd are dead duplicates from incomplete refactor

---

## Maintenance

When adding new variables:
1. Ensure every `var` is used in at least one function
2. Avoid "write-only" variables (assigned but never read)
3. If a variable is temporarily unused, mark with `# TODO: use this` comment

Run analysis periodically to catch new unused variables.