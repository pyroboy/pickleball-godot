"""
Fixed graph rebuild pipeline for pickleball-godot.

Fixes applied vs _graphify_pipeline.py:
1. Merges all chunk semantic JSONs (subagent outputs)
2. Removes archive nodes (scripts/archive/game.gd pollutes main component)
3. Removes phantom Godot base-type nodes (Resource, Node, RefCounted w/ no source)
4. Adds explicit cross-file edges to connect isolated components
5. Writes graph.json with full edge attributes (relation, confidence, weight)
"""

import json
import sys
sys.path.insert(0, '/Users/arjomagno/.local/share/uv/tools/graphifyy/lib/python3.11/site-packages')

from pathlib import Path
from graphify.build import build_from_json
from graphify.cluster import cluster, score_all
from graphify.analyze import god_nodes, surprising_connections
from graphify.report import generate
from graphify.export import to_json, to_html
import networkx as nx

ROOT = Path(__file__).parent.parent
OUT = Path(__file__).parent

# ── 1. Load base extract ──────────────────────────────────────────────────────
merged = json.loads((OUT / '.graphify_extract.json').read_text())
print(f"Base extract: {len(merged['nodes'])} nodes, {len(merged['edges'])} edges")

all_nodes = {n['id']: n for n in merged['nodes']}
all_edges = list(merged['edges'])
all_hyperedges = list(merged.get('hyperedges', []))

# ── 2. Merge chunk semantic JSONs (subagent outputs) ─────────────────────────
chunk_files = sorted(OUT.glob('.graphify_chunk_*.json'))
# Exclude the old file lists (those end with _files.txt handled separately)
chunk_jsons = [f for f in chunk_files if not f.name.endswith('_files.txt')]
print(f"Chunk JSONs to merge: {len(chunk_jsons)}")

for chunk_path in chunk_jsons:
    try:
        chunk = json.loads(chunk_path.read_text())
        new_nodes = 0
        for n in chunk.get('nodes', []):
            if n['id'] not in all_nodes:
                all_nodes[n['id']] = n
                new_nodes += 1
        all_edges.extend(chunk.get('edges', []))
        all_hyperedges.extend(chunk.get('hyperedges', []))
        print(f"  {chunk_path.name}: +{new_nodes} nodes, +{len(chunk.get('edges',[]))} edges")
    except Exception as e:
        print(f"  WARN: {chunk_path.name} failed: {e}")

# ── 3. Remove archive nodes ───────────────────────────────────────────────────
archive_ids = {nid for nid, n in all_nodes.items()
               if '/archive/' in (n.get('source_file') or '')}
print(f"\nRemoving {len(archive_ids)} archive nodes")
for aid in archive_ids:
    del all_nodes[aid]

# ── 4. Remove phantom Godot base-type nodes ───────────────────────────────────
PHANTOM_IDS = {'resource', 'node', 'refcounted', 'gizmohandle', 'meshinstance3d'}
phantom_ids = {nid for nid in all_nodes if nid in PHANTOM_IDS and not all_nodes[nid].get('source_file')}
print(f"Removing {len(phantom_ids)} phantom type nodes: {phantom_ids}")
for pid in phantom_ids:
    del all_nodes[pid]

# Filter edges referencing removed nodes
valid_ids = set(all_nodes.keys())
all_edges = [e for e in all_edges
             if e.get('source') in valid_ids and e.get('target') in valid_ids]
print(f"\nAfter cleanup: {len(all_nodes)} nodes, {len(all_edges)} edges")

# ── 5. Add explicit cross-file edges for isolated components ──────────────────
# These wire known architectural relationships the AST couldn't detect.
# Using exact node IDs from the AST extractor.

# File-level node IDs (from audit of current graph)
FILE_NODES = {
    'posture_constants':    'users_arjomagno_documents_github_repos_pickleball_godot_scripts_posture_constants_gd',
    'scoreboard_ui':        'users_arjomagno_documents_github_repos_pickleball_godot_scripts_scoreboard_ui_gd',
    'hud':                  'users_arjomagno_documents_github_repos_pickleball_godot_scripts_ui_hud_gd',
    'left_arm':             'users_arjomagno_documents_github_repos_pickleball_godot_scripts_left_arm_gd',
    'right_arm':            'users_arjomagno_documents_github_repos_pickleball_godot_scripts_right_arm_gd',
    'leg':                  'users_arjomagno_documents_github_repos_pickleball_godot_scripts_leg_gd',
    'gizmo_handle':         'users_arjomagno_documents_github_repos_pickleball_godot_scripts_posture_editor_gizmo_handle_gd',
    'posture_commit_selector': 'users_arjomagno_documents_github_repos_pickleball_godot_scripts_posture_commit_selector_gd',
    'posture_skeleton_applier': 'users_arjomagno_documents_github_repos_pickleball_godot_scripts_posture_skeleton_applier_gd',
}

# Anchor nodes (representative nodes from each isolated file's content)
ANCHOR_NODES = {
    # Component 3 (live game.gd + player.gd etc.) — connect to comp 2 (player_arm_ik etc.)
    'game_gameloop': 'game_gameloop',
    'player_hitting_apply_hit': 'player_hitting_apply_hit',
    # Comp 2 nodes
    'posture_editor_ui': next((nid for nid in all_nodes if 'posture_editor_ui' in nid and 'method' not in nid), None),
    'player_arm_ik': next((nid for nid in all_nodes if nid.startswith('player_arm_ik_') and len(nid) < 60), None),
    'player_leg_ik': next((nid for nid in all_nodes if nid.startswith('player_leg_ik_') and len(nid) < 60), None),
    # Comp 1 nodes — position/rotation gizmos ARE in comp 1
    'position_gizmo': 'users_arjomagno_documents_github_repos_pickleball_godot_scripts_posture_editor_position_gizmo_gd',
    'rotation_gizmo': 'users_arjomagno_documents_github_repos_pickleball_godot_scripts_posture_editor_rotation_gizmo_gd',
}

def add_edge(src, tgt, relation, confidence='INFERRED', score=0.85, sf=''):
    if src in valid_ids and tgt in valid_ids and src and tgt:
        all_edges.append({
            'source': src, 'target': tgt,
            'relation': relation,
            'confidence': confidence,
            'confidence_score': score,
            'source_file': sf,
            'source_location': None,
            'weight': score,
        })
        return True
    return False

cross_edges = 0

# posture_constants.gd → used by posture editor and player modules
pc = FILE_NODES['posture_constants']
for src_id in [
    ANCHOR_NODES.get('player_arm_ik'),
    ANCHOR_NODES.get('posture_editor_ui'),
    ANCHOR_NODES.get('player_leg_ik'),
]:
    if src_id:
        cross_edges += add_edge(src_id, pc, 'references', score=0.9, sf='scripts/player_arm_ik.gd')

# scoreboard_ui + hud → game.gd (reads score/state)
game_node = 'game_gameloop'
cross_edges += add_edge(FILE_NODES['scoreboard_ui'], game_node, 'references', score=0.9, sf='scripts/scoreboard_ui.gd')
cross_edges += add_edge(FILE_NODES['hud'], game_node, 'references', score=0.85, sf='scripts/ui/hud.gd')

# left/right arm + leg → player_arm_ik / player_leg_ik (composition)
pa = ANCHOR_NODES.get('player_arm_ik')
pl = ANCHOR_NODES.get('player_leg_ik')
if pa:
    cross_edges += add_edge(pa, FILE_NODES['left_arm'], 'uses', score=0.9, sf='scripts/player_arm_ik.gd')
    cross_edges += add_edge(pa, FILE_NODES['right_arm'], 'uses', score=0.9, sf='scripts/player_arm_ik.gd')
if pl:
    cross_edges += add_edge(pl, FILE_NODES['leg'], 'uses', score=0.9, sf='scripts/player_leg_ik.gd')

# gizmo_handle → position_gizmo + rotation_gizmo (comp 1)
gh = FILE_NODES['gizmo_handle']
cross_edges += add_edge(ANCHOR_NODES['position_gizmo'], gh, 'uses', score=0.9, sf='scripts/posture_editor/position_gizmo.gd')
cross_edges += add_edge(ANCHOR_NODES['rotation_gizmo'], gh, 'uses', score=0.9, sf='scripts/posture_editor/rotation_gizmo.gd')

# posture_commit_selector → player_paddle_posture (physics.gd / player_paddle_posture.gd in comp 9)
# Find player_paddle_posture node
pp_node = next((nid for nid in all_nodes if nid.startswith('player_paddle_posture_') and len(nid) < 70), None)
if pp_node:
    cross_edges += add_edge(pp_node, FILE_NODES['posture_commit_selector'], 'uses', score=0.85, sf='scripts/player_paddle_posture.gd')

# Connect comp 3 (live game.gd) to comp 2 (player_arm_ik, posture_editor_ui)
# game.gd calls player modules — wire via game_gameloop → player_arm_ik
if pa:
    cross_edges += add_edge('game_gameloop', pa, 'calls', score=0.8, sf='scripts/game.gd')

# posture_skeleton_applier (comp 1) → posture_constants (isolated)
cross_edges += add_edge(FILE_NODES['posture_skeleton_applier'], pc, 'references', score=0.85,
                        sf='scripts/posture_skeleton_applier.gd')

print(f"Added {cross_edges} explicit cross-file edges")

# ── 5b. Bridge chunk semantic nodes to AST nodes (same source_file) ───────────
# Chunk subagents used different ID schemes than AST (e.g. peui_* vs posture_editor_ui_*).
# Bridge: for each chunk semantic node that doesn't exist in AST, connect it to a
# representative AST node from the same source_file via a 'describes' edge.
# This merges the two ID worlds without collapsing all nodes into one.

# Map: source_file → list of AST node IDs (for picking representative anchors)
ast_data = json.loads((OUT / '.graphify_ast.json').read_text())
ast_ids = {n['id'] for n in ast_data['nodes']}
ast_by_file: dict[str, list[str]] = {}
for n in ast_data['nodes']:
    sf = n.get('source_file') or ''
    if sf:
        ast_by_file.setdefault(sf, []).append(n['id'])

# Also build absolute→relative sf mapping (AST uses abs paths, chunks use relative)
abs_to_rel: dict[str, str] = {}
for sf in ast_by_file:
    rel = str(Path(sf).relative_to(ROOT)) if Path(sf).is_absolute() else sf
    abs_to_rel[sf] = rel
    abs_to_rel[rel] = sf  # bidirectional

# Prefer file-level nodes (degree 1 in AST) as anchors to avoid over-connecting
def ast_anchor_for(source_file: str) -> str | None:
    # Try both absolute and relative
    candidates = ast_by_file.get(source_file, []) or ast_by_file.get(abs_to_rel.get(source_file, ''), [])
    # Filter to nodes that are in valid_ids (not removed)
    candidates = [c for c in candidates if c in valid_ids]
    if not candidates:
        return None
    # Prefer nodes whose label ends with .gd (file-level node)
    for c in candidates:
        if all_nodes.get(c, {}).get('label', '').endswith('.gd'):
            return c
    return candidates[0]

# Identify chunk-only nodes (not in AST)
chunk_node_ids = set()
for chunk_path in chunk_jsons:
    try:
        chunk = json.loads(chunk_path.read_text())
        for n in chunk.get('nodes', []):
            if n['id'] not in ast_ids:
                chunk_node_ids.add(n['id'])
    except Exception:
        pass

bridge_edges = 0
for nid in chunk_node_ids:
    if nid not in all_nodes:
        continue
    sf = all_nodes[nid].get('source_file') or ''
    if not sf:
        continue
    anchor = ast_anchor_for(sf)
    if anchor and anchor != nid:
        bridge_edges += add_edge(anchor, nid, 'describes', 'INFERRED', 0.7, sf)

print(f"Added {bridge_edges} AST↔semantic bridge edges")

# ── 5c. Connect ALL isolated nodes to any sibling in same source_file ─────────
# This catches AST-generated nodes with zero edges (e.g. peui_*, posturecolors_*)
# Group all nodes by source_file
nodes_by_file: dict[str, list[str]] = {}
for nid, n in all_nodes.items():
    sf = n.get('source_file') or ''
    if sf:
        nodes_by_file.setdefault(sf, []).append(nid)

# Build edge index: which nodes appear in at least one edge?
edge_srcs = {e['source'] for e in all_edges}
edge_tgts = {e['target'] for e in all_edges}
has_edge = edge_srcs | edge_tgts

# For each source file, pick a "root" node (prefers file-level nodes or first in list)
def file_root(nids: list[str]) -> str:
    for nid in nids:
        if all_nodes[nid].get('label', '').endswith('.gd'):
            return nid
    # Prefer shortest ID (usually the class-level node)
    return min(nids, key=len)

orphan_bridges = 0
for sf, nids in nodes_by_file.items():
    if len(nids) < 2:
        continue
    orphans = [nid for nid in nids if nid not in has_edge]
    if not orphans:
        continue
    # Find the best connected node in this file group to anchor to
    connected = [nid for nid in nids if nid in has_edge]
    if connected:
        anchor = min(connected, key=len)  # shortest ID = most likely class node
    else:
        anchor = file_root(nids)
    for orphan in orphans:
        if orphan == anchor:
            continue
        if add_edge(anchor, orphan, 'contains', 'INFERRED', 0.6, sf):
            orphan_bridges += 1
            has_edge.add(orphan)

print(f"Added {orphan_bridges} intra-file orphan bridge edges")
valid_ids = set(all_nodes.keys())  # refresh after adds

# ── 6. Build graph ────────────────────────────────────────────────────────────
extract_clean = {
    'nodes': list(all_nodes.values()),
    'edges': all_edges,
    'hyperedges': all_hyperedges,
    'input_tokens': merged.get('input_tokens', 0),
    'output_tokens': merged.get('output_tokens', 0),
}

graph = build_from_json(extract_clean)
print(f"\nGraph: {len(graph.nodes)} nodes, {len(graph.edges)} edges")

# Report connectivity
comps = sorted(nx.connected_components(graph), key=len, reverse=True)
print(f"Connected components: {len(comps)}")
print(f"  Largest: {len(comps[0])} nodes")
print(f"  2nd: {len(comps[1])} nodes" if len(comps) > 1 else "")
print(f"  3rd: {len(comps[2])} nodes" if len(comps) > 2 else "")
print(f"  Coverage in largest: {len(comps[0])/len(graph.nodes)*100:.1f}%")

isolates = [n for n in graph.nodes if graph.degree(n) == 0]
print(f"Degree-0 isolates: {len(isolates)}")
if isolates:
    print(f"  Examples: {isolates[:5]}")

# ── 7. Cluster + analyze ──────────────────────────────────────────────────────
communities_by_id = cluster(graph)
scores = score_all(graph, communities_by_id)
gods = god_nodes(graph, top_n=15)
surprises = surprising_connections(graph, communities_by_id, top_n=10)

print(f"\nCommunities: {len(communities_by_id)}")
print(f"God nodes:")
for g in gods[:5]:
    print(f"  {g['id']} - {g['degree']} edges")

# ── 8. Report ─────────────────────────────────────────────────────────────────
detection = {'total_files': 131, 'total_words': 292296}
token_cost = {'input': 0, 'output': 0}
report = generate(
    G=graph,
    communities=communities_by_id,
    cohesion_scores=scores,
    community_labels={},
    god_node_list=gods,
    surprise_list=surprises,
    detection_result=detection,
    token_cost=token_cost,
    root='.',
    suggested_questions=None,
)
(OUT / 'GRAPH_REPORT.md').write_text(report)
print(f"\nReport written: {len(report)} chars")

# ── 9. Export ─────────────────────────────────────────────────────────────────
to_json(graph, communities_by_id, str(OUT / 'graph.json'))
print(f"graph.json saved: {len(graph.nodes)} nodes, {len(graph.edges)} edges")

if len(graph.nodes) <= 5000:
    to_html(graph, communities_by_id, str(OUT / 'graph.html'))
    print("graph.html saved")
