# Posture Editor — Phase 1 Implementation Notes

**Status**: Phase 1 complete (schema + library + extractor). No runtime wiring yet.

## What shipped

| File | Purpose |
|---|---|
| `scripts/posture_definition.gd` | `PostureDefinition` Resource class. 21 postures × full-body field set (paddle, arms, legs, torso, head, charge, follow-through, metadata). |
| `scripts/posture_library.gd` | `PostureLibrary` loader/indexer. Loads from `res://data/postures/*.tres` if present, otherwise builds defaults in code from the exact current hardcoded values. |
| `tools/extract_postures.gd` | `@tool EditorScript` that snapshots `_build_defaults()` to disk as `data/postures/NN_name.tres` files. Run once from Godot editor (File → Run). |
| `docs/posture-editor-phase1-notes.md` | This file. |

Zero edits to existing gameplay code. The library exists but no runtime subsystem consumes it yet. Phase 2 is the wiring pass.

## Posture count correction

The proposal said "20 postures". The enum in `scripts/player.gd:42-64` actually has **21** — I missed `READY` during the earlier scope pass. All 21 are in `_build_defaults()`.

## Byte-identical verification path

Phase 1 cannot be tested against runtime because nothing is wired. The verification is **structural**: every numeric literal in `_build_defaults()` is a literal copy of:

- `player_paddle_posture.gd:14-36` (paddle position constants)
- `player_paddle_posture.gd:50-76` (`POSTURE_ZONES`)
- `player_paddle_posture.gd:1313-1365` (`get_posture_offset_for`)
- `player_paddle_posture.gd:1367-1406` (`_get_posture_rotation_offset_for`)
- `player_hitting.gd:4-14, 101-156` (charge rotations, body rotation)

Each posture's `_make()` call is cross-referenceable to the source lines. Phase 2 swaps the switch blocks for library lookups, and that's where we'll get behavioral byte-identical verification via practice-ball `[SCORE]` logs before/after.

## How to generate the .tres files

Open the project in Godot 4.6, open `tools/extract_postures.gd` in the script editor, then **File → Run** (Ctrl+Shift+X). Watch the Output panel for 21 "wrote..." lines. Files land in `data/postures/`.

You don't have to do this for Phase 2 to work — the library will fall back to `_build_defaults()` in code if the directory is missing. Running the extractor is only needed once you want to edit postures outside the code (via the future editor UI, the Godot inspector, or a text editor).

## Critical discovery: Q1 is answered

Proposal §8 Q1 asked whether the current player rig has a Skeleton3D with enough bones for per-posture hips/torso/head control.

**Answer: no.** `scripts/player_body_builder.gd` has zero references to `Skeleton3D`, `bone`, or `Bone`. The body is procedural mesh generation. This means Phase 3 (feet/knees/elbows/head/torso fields actually driving the rig) has a **prerequisite step** the proposal did not account for:

### Phase 2.5 (new): Rig extension

Before Phase 3 can wire full-body fields, the player needs either:

**Option A — Skeleton3D + SkeletonIK3D**
Rebuild `player_body_builder.gd` to emit a MeshInstance3D + Skeleton3D with a proper bone hierarchy (pelvis → spine → neck → head, pelvis → hips → knees → ankles, pelvis → shoulders → elbows → wrists). Use Godot 4.6's SkeletonModifier3D nodes for IK. Heaviest option; ~3-5 days on its own.

**Option B — Procedural joint Node3Ds**
Keep the procedural mesh but add invisible Node3Ds for each joint (hip_L, hip_R, knee_L, knee_R, etc.). Mesh verts bind to these via a simple skinning pass in the body builder. Lighter than a full Skeleton3D but still ~2-3 days. Good fit because the existing `player_leg_ik.gd` already works with transform-based IK, not skeletal IK.

**Option C — Defer Phase 3 and ship Phase 2+4 first**
Wire the loader (Phase 2) + editor UI (Phase 4) for paddle-only fields. Body fields are editable in the Resource but `PostureApplier` ignores them. This gives the editor for paddle tuning on day 1 and defers the rig work. **Recommended** — it unblocks 90% of Arjo's tuning needs while the rig refactor is scoped separately.

My recommendation: **Option C first**, then circle back to choose between A and B once Arjo has felt how far paddle-only tuning gets him.

## Verification the Phase 1 files are well-formed

Not runnable from Claude without Godot. Arjo's manual checks:

1. Open project in Godot 4.6 — no parse errors in the script editor for the three new files.
2. `File → Run` on `tools/extract_postures.gd` — expect 21 "wrote..." lines, zero errors. `data/postures/` directory appears with 21 .tres files.
3. Open any .tres file in the inspector — every field is visible, grouped by the `@export_group` headers, `posture_id` and `display_name` correct.
4. `load("res://data/postures/00_forehand.tres")` in the remote inspector — returns a `PostureDefinition`, `resolve_paddle_offset(Vector3.RIGHT, Vector3.FORWARD)` returns `Vector3(0.5, 0.0, 0.4)` (matching the current hardcoded FOREHAND offset).

## Next

Phase 2 proceeds after Phase 1 is verified. Phase 2 replaces the hardcoded switches in `player_paddle_posture.gd` with `library.get_def(posture_id)` lookups. The rotation and offset resolver functions on `PostureDefinition` already handle the sign-source pattern — Phase 2 is a mechanical swap.
