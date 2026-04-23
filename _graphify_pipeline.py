import json
from pathlib import Path
import sys
sys.path.insert(0, '/opt/homebrew/lib/python3.14/site-packages')
from graphify.build import build_from_json
from graphify.cluster import cluster, score_all
from graphify.analyze import god_nodes, surprising_connections
from graphify.report import generate

merged = json.loads(Path('graphify-out/.graphify_extract.json').read_text())
print(f"Extraction: {len(merged['nodes'])} nodes, {len(merged['edges'])} edges")

graph = build_from_json(merged)
print(f"Graph: {len(graph.nodes)} nodes, {len(graph.edges)} edges")

communities_by_id = cluster(graph)
print(f"Clustered: {len(communities_by_id)} communities")

node_to_comm = {}
for cid, nodes in communities_by_id.items():
    for n in nodes:
        node_to_comm[n] = cid

n_comms = len(communities_by_id)

gods = god_nodes(graph, top_n=15)
print(f"\nGod nodes:")
for g in gods:
    print(f"  {g['id']} - {g['degree']} edges")

scores = score_all(graph, communities_by_id)
comm_sizes = {cid: len(nodes) for cid, nodes in communities_by_id.items()}
sorted_scores = sorted(scores.items(), key=lambda x: x[1], reverse=True)
print(f"\nTop 10 communities by cohesion:")
for comm_id, coh in sorted_scores[:10]:
    n = comm_sizes.get(comm_id, 0)
    cov = n / len(graph.nodes) * 100
    print(f"  Comm {comm_id}: coh={coh:.3f}, nodes={n}, coverage={cov:.1f}%")

surprises = surprising_connections(graph, communities_by_id, top_n=10)
print(f"\nSurprising connections ({len(surprises)}):")
for s in surprises:
    print(f"  {s['source']} --[{s['relation']}]--> {s['target']} ({s['confidence']})")

print("\nGenerating report...")
detection = {
    'total_files': 321,
    'total_words': 399222,
}
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
    suggested_questions=None
)
Path('graphify-out/GRAPH_REPORT.md').write_text(report)
print(f"Report: {len(report)} chars")

node_list = [{'id': n, **dict(graph.nodes[n])} for n in graph.nodes]
edge_list = [{'source': u, 'target': v} for u, v in graph.edges]
Path('graphify-out/graph.json').write_text(json.dumps({'nodes': node_list, 'edges': edge_list}, indent=2))
print(f"graph.json saved: {len(node_list)} nodes, {len(edge_list)} edges")

isolates = [n for n in graph.nodes if graph.degree(n) == 0]
print(f"\nIsolates (degree=0): {len(isolates)}")
if isolates:
    print(f"  Examples: {isolates[:5]}")