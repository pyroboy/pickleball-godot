extends RefCounted
const Store = preload("res://scripts/mobile_pose_store.gd")

# Immutable, flat value/metadata graphs. Stable encounter-order references
# preserve aliases and cycles without serializing process-specific Resource IDs.
# Every compound edge is an index, so Dictionary equality never recursively
# compares the input's depth. The work queue also avoids recursive traversal.
static func _seen_index(item, seen: Array) -> int:
	for index in range(seen.size()):
		if is_same(item, seen[index]): return index
	return -1

static func _fields(resource: Resource, seen: Array, nodes: Array) -> Dictionary:
	var result: Dictionary = {}
	for property in resource.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and (int(property.usage) & PROPERTY_USAGE_STORAGE) != 0:
			result[str(property.name)] = _reference(resource.get(property.name), seen, nodes)
	return result

static func _metadata(resource: Resource, seen: Array, nodes: Array, top_level: bool = false) -> Dictionary:
	var result: Dictionary = {}
	for key in resource.get_meta_list():
		var entry = resource.get_meta(key)
		# Ready tracking intentionally shares its original base. Only this
		# top-level contract compares identity; deep-copied metadata Resources
		# are otherwise compared by content, aliases and their own metadata.
		result[str(key)] = {"resource_id": entry.get_instance_id()} if top_level and str(key) == "ready_tracking_base" and entry is Resource else _reference(entry, seen, nodes)
	return result

static func _reference(item, seen: Array, nodes: Array):
	if item is Resource or item is Dictionary or item is Array:
		var prior: int = _seen_index(item, seen)
		if prior >= 0: return {"graph_reference": prior}
		var index: int = seen.size()
		seen.append(item)
		nodes.append({})
		return {"graph_reference": index}
	return item

static func _graph(item, top_level_metadata: bool = false) -> Dictionary:
	var seen: Array = []
	var nodes: Array = []
	var root = _reference(item, seen, nodes)
	var index: int = 0
	while index < seen.size():
		var current = seen[index]
		if current is Resource:
			nodes[index] = {"kind": "resource", "fields": _fields(current, seen, nodes), "metadata": _metadata(current, seen, nodes, top_level_metadata and index == 0)}
		elif current is Dictionary:
			var entries: Array = []
			for key in current: entries.append([_reference(key, seen, nodes), _reference(current[key], seen, nodes)])
			nodes[index] = {"kind": "dictionary", "entries": entries}
		else:
			var entries: Array = []
			for entry in current: entries.append(_reference(entry, seen, nodes))
			nodes[index] = {"kind": "array", "entries": entries}
		index += 1
	return {"root": root, "nodes": nodes}

static func value(item):
	return _graph(item)

static func pose(def: PostureDefinition) -> Dictionary:
	if def == null: return {"null": true}
	var graph: Dictionary = _graph(def, true)
	var root: Dictionary = graph.nodes[0]
	# Encode the store result as a separate flat graph too. It retains its exact
	# values without adding any recursively nested containers to the snapshot.
	return {"raw_authored": root.fields, "encoded_authored": value(Store._encode_fields(def)), "metadata": root.metadata, "graph_nodes": graph.nodes}
