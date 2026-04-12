# Posture Editor — Phase 4b Implementation Notes

**Status**: Phase 4b complete (3D gizmos). All phases 1/2/4/4b done. Phase 3 blocked on rig.

## What shipped

### scripts/posture_editor_ui.gd additions

**3D Gizmo System:**
- `_gizmo_root: Node3D` — parent container for all posture gizmos
- `_gizmos: Dictionary` — posture_id → MeshInstance3D mapping
- `_player: Node3D` — reference to Blue player for positioning

**Gizmo Features:**
- **Box meshes** at each posture's calculated offset position
- **Family colors**:
  - Forehand: green
  - Backhand: red
  - Center: blue
  - Overhead: yellow
- **Transparency**: 60% alpha, no depth test (always visible)
- **Selected highlight**: 1.75x scale on currently editing posture
- **Live positioning**: Updates every frame via `_process()` when visible

**Functions:**
- `set_player(player)` — initializes gizmos with player reference (called from game.gd)
- `_create_gizmos()` — builds 21 box meshes, adds to world space
- `_update_gizmo_positions()` — calculates world positions using player's forward/forehand axes
- `_highlight_gizmo(id)` — scales up selected posture, resets others
- `_notification(VISIBILITY_CHANGED)` — shows/hides gizmos with UI

### game.gd changes
- `posture_editor_ui.set_player(player_left)` after creating the UI

## Visual Result

When E is pressed:
1. UI panel appears center-screen
2. 21 colored boxes appear around the Blue player
3. Click a posture in the list → its box grows larger
4. Edit values → boxes move in real-time (gizmos track current paddle offset formula)

## Known Issues / TODO

1. **Gizmos show paddle position only** — full-body gizmos (feet, knees, elbows, head) need Phase 3 rig
2. **Follow-through gizmos** show at origin (they're static ghosts, calculated differently)
3. **No live paddle preview** — editing doesn't immediately move the actual paddle, just the gizmos

## Phase 3 Blocker

Phase 3 (wiring full-body fields to actual rig) requires:
- Skeleton3D added to player_body_builder.gd
- Bone hierarchy for: hips, spine, head, arms (upper/lower), legs (thigh/calf)
- IK target integration in PlayerLegIK, PlayerArmIK, PlayerBodyAnimation

This is 2-5 days of rigging work before the full-body fields in PostureDefinition become functional.

---

## Summary: All Phases Status

| Phase | Status | Notes |
|-------|--------|-------|
| 1 | ✅ Complete | PostureDefinition Resource, PostureLibrary, extractor tool, 21 .tres files |
| 2 | ✅ Complete | Wired into player_paddle_posture.gd, all consumers use library |
| 3 | ⏸️ Blocked | Needs Skeleton3D rig in body builder |
| 4 | ✅ Complete | In-game UI with list, property editor, save button |
| 4b | ✅ Complete | 3D gizmos around player, colored by family |

**Files created:**
- `scripts/posture_definition.gd` (157 lines)
- `scripts/posture_library.gd` (300+ lines)
- `tools/extract_postures.gd` (60 lines)
- `scripts/posture_editor_ui.gd` (335 lines)
- `data/postures/*.tres` (21 files, 00-20)
- `docs/posture-editor-phase*.md` (notes)

**Files modified:**
- `scripts/player_paddle_posture.gd` — library integration, fallback warnings
- `scripts/game.gd` — E key handler, UI instantiation, player reference
- `scripts/posture_library.gd` — singleton accessor

**Next step (optional):** Implement Phase 3 rigging when you want feet/knees/elbows/head to actually drive the body.
