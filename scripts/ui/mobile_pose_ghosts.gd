extends Node3D
## Render-only snapshots of the solved preview rig. No extra Players, IK,
## collisions, or animation loops. Rigid pieces batch across all visible frames;
## skinned torso/limb/hand pieces retain their actual sampled bone poses.
const MAX_PER_GAP := 6
const OPACITY := 0.11
var sources: Array[MeshInstance3D] = []
var samples: Array = []
var batches: Array = []
var _player: Node3D
var _materials: Array[StandardMaterial3D] = []

func initialize(player: Node3D) -> void:
	_player = player
	_collect(player.body_pivot)
	for color in [Color("cfb7f3"), Color("89dfdf")]:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(color, OPACITY)
		# Normal depth testing keeps the opaque current pose legible. Back-face
		# culling avoids doubling the apparent opacity of every closed surface.
		material.cull_mode = BaseMaterial3D.CULL_BACK
		_materials.append(material)

func _collect(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null and node.layers != 0:
		sources.append(node)
	for child in node.get_children(): _collect(child)

func begin_samples() -> void:
	samples.clear()

func capture_sample() -> void:
	var frame: Array = []
	for source in sources:
		var sample := {"transform": source.global_transform, "visible": source.is_visible_in_tree(), "bones": []}
		if source.skin != null:
			var skeleton := source.get_node_or_null(source.skeleton) as Skeleton3D
			if skeleton != null:
				sample.skeleton_transform = skeleton.global_transform
				for bone in range(skeleton.get_bone_count()): sample.bones.append(skeleton.get_bone_pose(bone))
		frame.append(sample)
	samples.append(frame)

func _ensure_pool() -> void:
	if not batches.is_empty(): return
	for source in sources:
		var skeleton := source.get_node_or_null(source.skeleton) as Skeleton3D if source.skin != null else null
		var entry := {"source": source, "copies": []}
		if skeleton == null:
			# One batch per gap permits subtle before/after Contact tinting.
			entry.rigid = []
			for gap in range(2):
				var batch := MultiMeshInstance3D.new()
				batch.name = str(source.name) + "GhostBatch" + str(gap)
				batch.set_meta("source_path", _player.get_path_to(source))
				batch.multimesh = MultiMesh.new()
				batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
				batch.multimesh.mesh = source.mesh
				batch.multimesh.instance_count = MAX_PER_GAP
				batch.multimesh.visible_instance_count = 0
				batch.material_override = _materials[gap]
				batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(batch)
				entry.rigid.append(batch)
		else:
			for slot in range(MAX_PER_GAP * 2):
				var copy := MeshInstance3D.new()
				copy.name = str(source.name) + "Ghost" + str(slot)
				copy.set_meta("source_path", _player.get_path_to(source))
				copy.mesh = source.mesh; copy.skin = source.skin
				copy.custom_aabb = source.custom_aabb
				copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(copy)
				var skin := Skeleton3D.new()
				skin.name = "SnapshotSkeleton"
				skin.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
				copy.add_child(skin)
				for bone in range(skeleton.get_bone_count()):
					skin.add_bone(skeleton.get_bone_name(bone))
					skin.set_bone_parent(bone, skeleton.get_bone_parent(bone))
					skin.set_bone_rest(bone, skeleton.get_bone_rest(bone))
				copy.skeleton = copy.get_path_to(skin)
				copy.visible = false
				entry.copies.append({"mesh": copy, "skeleton": skin})
		batches.append(entry)

func display_indices(indices: PackedInt32Array) -> void:
	visible = not indices.is_empty() and not samples.is_empty()
	if not visible: return
	_ensure_pool()
	var per_gap := indices.size() / 2
	for source_index in range(batches.size()):
		var entry: Dictionary = batches[source_index]
		if entry.has("rigid"):
			for gap in range(2):
				var batch: MultiMeshInstance3D = entry.rigid[gap]
				var drawn := 0
				for slot in range(per_gap):
					var sample: Dictionary = samples[indices[gap * per_gap + slot]][source_index]
					if not sample.visible: continue
					batch.multimesh.set_instance_transform(drawn, batch.global_transform.affine_inverse() * sample.transform)
					drawn += 1
				batch.multimesh.visible_instance_count = drawn
		else:
			for slot in range(entry.copies.size()):
				var copy: Dictionary = entry.copies[slot]
				copy.mesh.visible = slot < indices.size()
				if slot >= indices.size(): continue
				var sample: Dictionary = samples[indices[slot]][source_index]
				copy.mesh.visible = sample.visible
				copy.mesh.material_override = _materials[0 if slot < per_gap else 1]
				copy.mesh.global_transform = sample.transform
				copy.skeleton.global_transform = sample.skeleton_transform
				for bone in range(sample.bones.size()): copy.skeleton.set_bone_pose(bone, sample.bones[bone])
				copy.skeleton.force_update_all_bone_transforms()
