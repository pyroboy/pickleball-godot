# How to Rebuild the Architecture Graph

This doc is for LLMs picking up this repo. It explains how to rebuild `graphify-out/graph.json` — the knowledge graph that maps the full codebase architecture.

---

## What the graph is

`graphify-out/graph.json` is a NetworkX node-link graph of the entire pickleball-godot codebase:

- **1,704 nodes** — files, classes, methods, constants, signals, doc concepts
- **2,679 edges** — `calls`, `contains`, `references`, `inherits`, `emits`, `rationale_for`, etc.
- **93% connected** — one main component, queryable via BFS/DFS/shortest-path

It covers `.gd` source files (AST-extracted), `.md` docs (semantically extracted), and architectural relationships between them.

---

## When to rebuild

- A significant batch of new `.gd` files were added
- Major refactor changed cross-file relationships
- New subsystem added (new directory, new module)
- The graph feels stale (query results don't match code)

For small changes (1-3 files), skip rebuilding — read the files directly.

---

## Prerequisites

```bash
uv tool install graphifyy   # one-time install
```

Verify:
```bash
which graphify
# → /Users/arjomagno/.local/bin/graphify
```

The interpreter path is stored at `graphify-out/.graphify_python` after first run. If missing:
```bash
GRAPHIFY_BIN=$(which graphify)
PYTHON=$(head -1 "$GRAPHIFY_BIN" | tr -d '#!')
mkdir -p graphify-out
echo "$PYTHON" > graphify-out/.graphify_python
```

---

## The rebuild script

The canonical rebuild is **`graphify-out/rebuild_graph.py`**. Run it with:

```bash
cd /Users/arjomagno/Documents/github-repos/pickleball-godot
$(cat graphify-out/.graphify_python) graphify-out/rebuild_graph.py
```

This script does everything:
1. Loads `graphify-out/.graphify_extract.json` (AST base)
2. Merges any `graphify-out/.graphify_chunk_NN.json` (semantic subagent outputs)
3. Removes archive nodes (`scripts/archive/`)
4. Removes phantom Godot base-type nodes (`Resource`, `Node`, `RefCounted`)
5. Adds explicit cross-file edges for known isolated components
6. Bridges AST nodes ↔ semantic nodes from same source file
7. Connects intra-file orphan nodes
8. Exports `graph.json`, `graph.html`, `GRAPH_REPORT.md`

Expected output:
```
Graph: 1704 nodes, 2679 edges
Connected components: 13  (main: 1586 = 93.1%)
Isolates: 0
```

---

## How to do a full rebuild from scratch

Use this when the AST extract is stale or missing.

### Step 1 — AST extraction (automated, no LLM)

```bash
$(cat graphify-out/.graphify_python) -c "
import json
from graphify.extract import collect_files, extract
from pathlib import Path

code_files = list(Path('scripts').rglob('*.gd')) + list(Path('tools').rglob('*.gd'))
result = extract(code_files, cache_root=Path('.'))
Path('graphify-out/.graphify_extract.json').write_text(json.dumps(result, indent=2))
print(f'AST: {len(result[\"nodes\"])} nodes, {len(result[\"edges\"])} edges')
"
```

### Step 2 — Semantic extraction (parallel subagents)

Split the codebase into chunks of 8–22 files. For this repo the chunk groups are:

| Chunk | Files | Focus |
|-------|-------|-------|
| 01 | `CLAUDE.md`, `README.md`, `docs/paddle-posture-audit.md`, other key docs | Architecture docs |
| 02 | `docs/ARCHITECTURE.md`, all other docs, `scripts/player_paddle_posture.gd` | Design docs + posture |
| 03 | `scripts/game.gd`, `scripts/player.gd`, `scripts/player_ai_brain.gd`, `scripts/player_hitting.gd`, `scripts/player_leg_ik.gd`, `scripts/player_debug_visual.gd`, `scripts/posture_editor_ui.gd`, `scripts/ball_audio_synth.gd` | Core game scripts |
| 04 | `scripts/ball.gd`, `scripts/posture_library.gd`, `scripts/player_awareness_grid.gd`, `scripts/posture_commit_selector.gd`, `scripts/game_trajectory.gd`, `scripts/game_serve.gd`, `scripts/rally_scorer.gd`, `scripts/posture_offset_resolver.gd`, `scripts/ball_physics_probe.gd`, `scripts/pose_controller.gd` | Ball + posture data pipeline |
| 05 | `scripts/shot_physics.gd`, `scripts/court.gd`, `scripts/rules.gd`, `scripts/input_handler.gd`, `scripts/player_body_builder.gd`, `scripts/player_body_animation.gd`, `scripts/posture_definition.gd`, `scripts/base_pose_library.gd`, `scripts/posture_colors.gd`, `scripts/practice_launcher.gd`, and remaining game subsystems | Game subsystems |
| 06 | `scripts/player_arm_ik.gd`, `scripts/left_arm.gd`, `scripts/right_arm.gd`, `scripts/leg.gd`, `scripts/constants.gd`, `scripts/posture_constants.gd`, `scripts/posture_skeleton_applier.gd`, `scripts/camera/`, `scripts/fx/`, `scripts/posture_editor/gizmo_controller.gd`, `scripts/posture_editor/posture_editor_gizmos.gd`, `scripts/posture_editor/posture_editor_transport.gd` | IK, FX, camera, gizmos |
| 07 | `scripts/posture_editor/` (tabs, property editors, state, gizmo handles), `scripts/tests/test_rally_scorer.gd`, `scripts/tests/test_posture_*.gd`, `scripts/tests/test_shot_physics*.gd` | Posture editor subsystem + tests |
| 08 | `scripts/tests/` (runners, fakes), `scripts/time/`, `scripts/ui/`, `tools/extract_postures.gd` | Test infrastructure + UI |

**Dispatch all 8 as parallel subagents in a single message.** Each subagent gets this prompt:

```
You are a graphify extraction subagent for a Godot 4 GDScript pickleball game.

Read these files (chunk N of 8):
[FILE LIST]

All paths relative to /Users/arjomagno/Documents/github-repos/pickleball-godot.

Extract a knowledge graph fragment. Focus on:
- Cross-file architectural edges (calls, uses, inherits, references, emits)
- Semantic patterns AST misses (state machines, data flows, design patterns)
- Rationale edges for WHY decisions in docs
- Do NOT re-extract simple imports — focus on meaningful relationships
- Hyperedges for coherent subsystems (3+ files)

Node ID format: lowercase [a-z0-9_] only. {stem}_{entity}.
confidence_score required: EXTRACTED=1.0, INFERRED=0.6-0.9, AMBIGUOUS=0.1-0.3

Write output JSON to graphify-out/.graphify_chunk_NN.json.
Schema: {"nodes":[{"id":"...","label":"...","file_type":"code|document","source_file":"relative/path","source_location":null,"source_url":null,"captured_at":null,"author":null,"contributor":null}],"edges":[{"source":"...","target":"...","relation":"...","confidence":"EXTRACTED|INFERRED|AMBIGUOUS","confidence_score":1.0,"source_file":"...","source_location":null,"weight":1.0}],"hyperedges":[],"input_tokens":0,"output_tokens":0}
```

Wait for all 8 to complete, then run `rebuild_graph.py`.

---

## Known pitfalls — read before touching the pipeline

### 1. Archive nodes pollute the main component
`scripts/archive/game.gd` is an old version of game.gd. The AST extractor processes it and creates 67 nodes that pull unrelated files into a false "main" component. `rebuild_graph.py` removes them. Do not add the archive directory to any chunk file list.

### 2. Subagents create incompatible node IDs
The AST extractor uses `{stem}_{entity}` (e.g. `posture_editor_ui_method__ready`). Semantic subagents sometimes abbreviate (e.g. `peui_module`). Both sets end up in the graph as separate islands. `rebuild_graph.py` bridges them with `describes` edges (AST file anchor → semantic node). This is expected — don't try to force subagents to use exact AST IDs.

### 3. `build_from_json` silently drops edges with unknown node IDs
If an edge's `source` or `target` doesn't match any node ID in the merged set, the edge is dropped without warning. This is why isolated components appear. The intra-file orphan bridge in `rebuild_graph.py` fixes this post-hoc. Always check isolate count after rebuilding.

### 4. The pipeline script `_graphify_pipeline.py` is broken
The old `_graphify_pipeline.py` strips edge attributes (`relation`, `confidence`, `weight`) when writing `graph.json`. Use `rebuild_graph.py` instead — it uses graphify's `to_json()` which preserves all attributes.

### 5. Phantom Godot base-type nodes
The AST extractor creates nodes for Godot built-in types (`Resource`, `Node`, `RefCounted`) with no `source_file`. These have 15+ duplicates and bloat the graph. `rebuild_graph.py` removes them. If they reappear after a fresh AST extraction, filter them in the merge step.

### 6. Do not transcribe audio files
Running `/graphify` on the full repo detects 163 `.wav` files in `audio_analysis/` as "video". Running Whisper transcription on audio samples would be expensive and useless. Always run extraction directly on `scripts/` and `docs/` — not the full repo root.

---

## Querying the graph

```python
import json
from pathlib import Path
from networkx.readwrite import json_graph
import networkx as nx

g = json.loads(Path('graphify-out/graph.json').read_text())
G = json_graph.node_link_graph(g, edges='links')

# BFS from a node
start = 'posture_editor_ui'
visited = {start}
frontier = {start}
for depth in range(3):
    next_f = {nb for n in frontier for nb in G.neighbors(n) if nb not in visited}
    visited |= next_f
    frontier = next_f

# Shortest path
path = nx.shortest_path(G, 'game_gd', 'posture_constants_postureconstants')

# Find nodes by file
nodes_for_file = [(nid, G.nodes[nid]) for nid in G.nodes
                  if 'player_arm_ik' in (G.nodes[nid].get('source_file','') or '')]

# God nodes (highest degree)
by_degree = sorted(G.degree(), key=lambda x: x[1], reverse=True)[:10]
```

### Key node IDs for architectural entry points

| Concept | Node ID |
|---------|---------|
| Game orchestrator | `game_gd` |
| Player controller | `player_gd` |
| AI brain | `player_ai_brain` |
| Posture editor UI | `posture_editor_ui` |
| Posture constants | `posture_constants_postureconstants` |
| Ball physics | `ball_gd` (or search `ball.gd` in source_file) |
| Posture commit pipeline | `posture_commit_selector_gd` |
| Test runner | search label `test_runner.gd` |

---

## Output files

| File | Purpose | Regenerate? |
|------|---------|-------------|
| `graphify-out/graph.json` | The graph — nodes + edges with all attributes | Yes, via rebuild_graph.py |
| `graphify-out/graph.html` | Interactive browser visualization | Yes, auto-generated |
| `graphify-out/GRAPH_REPORT.md` | Community report, god nodes, surprises | Yes, auto-generated |
| `graphify-out/rebuild_graph.py` | The pipeline — edit this, don't replace it | No |
| `graphify-out/manifest.json` | File hashes for incremental updates | Auto-managed |
| `graphify-out/cache/` | Semantic extraction cache | Keep — speeds up re-runs |
