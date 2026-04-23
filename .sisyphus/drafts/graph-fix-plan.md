# Graph Quality Fix Plan

## Root Cause Analysis

### What the graph is
- **Source**: `graphify-out/.graphify_extract.json` (1398 nodes, 1957 edges with `relation` types)
- **Built by**: `_graphify_pipeline.py` → `graphify.build.build_from_json()` → `graph.json`
- **Final graph**: 1377 nodes, 2149 links with `relation`, `confidence`, `weight`

### What I got wrong in the first pass
- Reported "all edge labels empty" — **WRONG**. Edges DO have `relation` field with 20 distinct types:
  - `contains`, `calls`, `defines_method`, `defines_constant`, `references`, `rationale_for`, `defines_enum`, `defines_property`, `signal`, `inherits`, `implements`, `conceptually_related_to`, `emits`, `uses`, `owns`, `semantically_similar_to`, `reads`, `shares_data_with`, `mutates`
- Reported 7 orphan degree-0 nodes — **PARTIALLY WRONG**. The 7 orphans (`GizmoController`, `PostureEditorGizmos`, etc.) are degree-0 in the **post-merge** graph, but they DO have edges in the extract. They lost edges during the `build_from_json` process.

### What is actually broken

**Issue 1: Node ID collision — same file, different extraction layers**

`scripts/game.gd` appears in TWO separate subgraphs:
- Layer A (AST extractor): nodes with IDs like `game_gameloop`, `game_setup_game`, `game_physics_process`...
- Layer B (chunk_03): nodes with IDs like `game_module`, `game_class`, `game_signal_ball_landed`...

These two groups have **zero edges between them** because they use incompatible ID schemes. Same logical file, same 54 nodes, but they're only internally connected — the two groups never cross-link.

**Issue 2: 23 disconnected components — graph is severely fragmented**

| Component | Size | Key files |
|---|---|---|
| 1 (main) | 799 | `game.gd`, `player.gd`, `ball.gd`, `archive/`, tests |
| 2 | 155 | `player_ai_brain.gd`, `posture_editor_ui.gd`, `player_debug_visual.gd`, `player_leg_ik.gd`, `docs/` |
| 3 | 148 | `scripts/game.gd` (different subgraph), `ball_audio_synth.gd`, `shot_physics.gd` |
| 4 | 52 | `posture_constants.gd` alone |
| 5 | 40 | `scoreboard_ui.gd`, `ui/hud.gd` |
| 6-23 | 8-25 each | Various posture_editor/, body parts, tools, tests |

**Root cause**: The AST extractor creates cross-file edges via `calls` and `references` relationships by parsing actual GDScript `preload`, `load`, `extends`, `onready`, `new()`, and call expressions. However:

1. **Chunk_03 nodes don't connect to AST nodes** — `game_module` (chunk) and `game_gameloop` (AST) are the same concept but have no edges
2. **`game.gd` is split** — One subgraph of 56 nodes (with `ball_audio_synth.gd`, `shot_physics.gd`) is in component 3, while another 54-node subgraph (from the archive) is in component 1
3. **`build_graph_03.py` never ran** — The output file `.graphify_chunk_03.json` doesn't exist, so the 150 rich hand-crafted chunk_03 nodes were added to the extract manually (190 nodes total in extract with chunk-style IDs) but 40 of them were dropped in the final graph

**Issue 3: 7 nodes became orphan after graph building**

`GizmoController`, `PostureEditorGizmos`, `PostureEditorState`, `CameraRig`, `PlayerAwarenessGrid`, `GameTrajectory Module`, `test_runner.gd` — these have edges in the extract but degree-0 in the final graph. Something in `build_from_json` is filtering them out.

**Issue 4: Phantom type nodes**
6 nodes (`resource`, `node`, `refcounted`, `gizmohandle`, `meshinstance3d`) have no `source_file` — Godot base types that leaked into the AST extraction.

## Fixes

### Fix 1: Merge chunk_03 IDs into AST IDs (or eliminate chunk_03 layer)
**Problem**: Two representations of `game.gd` don't connect.
**Fix options**:
- Option A: Merge by creating `CONTAINS` edges between chunk_03 module nodes and their corresponding AST child nodes
- Option B: Delete the chunk_03 nodes entirely (they add 150 nodes but the AST already covers the same files)
- Option C: Run `build_graph_03.py` to generate `.graphify_chunk_03.json` and merge it properly before the pipeline

**Recommended**: Option B — the chunk_03 nodes are manually maintained and go stale. The AST extractor already captures the same information. Delete chunk_03 nodes from the extract and let the AST nodes be the single representation.

### Fix 2: Run `.graphify_chunk_03.json` → merge before pipeline
**Problem**: 40 of 190 chunk_03 nodes get dropped by `build_from_json`.
**Fix**: The chunk_03 output file doesn't exist at the path `build_graph_03.py` writes to. Run it and ensure the merge step includes it.

### Fix 3: Add cross-file edges for isolated components
**Problem**: `posture_constants.gd` (52 nodes, isolated), UI files (40 nodes), etc.
**Fix**: Manually add edges based on code references:
- `posture_editor_ui.gd` → `posture_constants.gd` (`references`)
- `scoreboard_ui.gd` → `game.gd` (score display)
- `gizmo_handle.gd` → `posture_editor_gizmos.gd` → `gizmo_controller.gd`

### Fix 4: Investigate why 7 nodes become orphans in `build_from_json`
**Problem**: `GizmoController`, `PostureEditorGizmos`, etc. have edges in the extract but degree-0 in the final graph.
**Fix**: This likely happens in `graphify.build.build_from_json`. Check if there's a deduplication step that merges nodes by some key and accidentally merges these with others, or a filter that removes nodes with certain characteristics.

### Fix 5: Remove phantom type nodes
**Problem**: `resource`, `node`, `refcounted`, `gizmohandle`, `meshinstance3d` — no source_file.
**Fix**: Filter these out in the extract step or in the pipeline.

## Implementation Order

1. **Run `build_graph_03.py`** → generates `.graphify_chunk_03.json` (currently missing)
2. **Audit `build_from_json`** → understand why 7 nodes become orphans and 21 nodes are dropped
3. **Fix the merge** → ensure chunk_03 nodes are properly merged (not duplicated, not dropped)
4. **Add cross-file edges** → connect isolated components via hand-coded edges
5. **Remove phantom nodes** → filter out generic type nodes
6. **Re-run pipeline** → regenerate `graph.json` and verify connectivity

## Files to Modify
- `_graphify_pipeline.py` — merge fix, phantom filter, orphan investigation
- `graphify-out/build_graph_03.py` — run it to generate `.graphify_chunk_03.json`
- `.graphify_extract.json` — add cross-file edges for isolated components
- OR create a new `graphify-out/_graphify_fix.py` that post-processes the existing `graph.json`

## Verification
- All 1377+ nodes should be in ONE connected component
- All nodes should have degree ≥ 1
- No phantom type nodes
- Cross-file edge ratio should increase from 17.3% to >50%
