extends Node3D

const ActivationZones = preload("res://scripts/contact_activation_zones.gd")
const Regions = preload("res://scripts/preparation_superblocks.gd")
const DEPTH: = 0.08
var player
var geometry: Dictionary = {}
var blocks: Dictionary = {}
var authored: Array[Dictionary] = []

func configure(owner) -> void :
	player = owner
	geometry = Regions.layout()
	for block in geometry.blocks:
		var color: Color = Regions.COLORS[int(block.band)]
		var node: = _box(Vector3(block.x_max - block.x_min, block.y_max - block.y_min, DEPTH), color, 0.08)
		node.name = "PreparationBlock_%d" % int(block.id)
		var label: = Label3D.new()
		label.text = block.name
		label.font_size = 48
		label.pixel_size = 0.0035
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = color
		node.add_child(label)
		blocks[int(block.id)] = {"node": node, "bounds": block}


	# The inner coverage is the same derived map used by the incoming planner.
	# Thin blue-gray boxes are preparation/contact zones, not physical hitboxes.
	for region in ActivationZones.display_regions():
		var rect: Rect2 = region.rect
		var depth: float = region.forward_max - region.forward_min
		var color := Color("e1eaf4") if region.bridge else Color("b8c9df")
		var node := _box(Vector3(rect.size.x, rect.size.y, depth), color, 0.055 if region.bridge else 0.035)
		node.name = "ContactCoverage_%d" % authored.size()
		authored.append({"node": node, "x": rect.get_center().x,
			"y": rect.get_center().y, "forward": (region.forward_min + region.forward_max) * 0.5, "owners": region.owners, "id": int(region.owners[0])})
	sync()

func _process(_delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_process(_delta)
	PerfMonitor.record("proc.preparation_superblock_visual", Time.get_ticks_usec() - _pt)

func _perf_process(_delta: float) -> void:
	if player == null: return
	var game = player.get_parent()
	visible = player.visible and not player.posture.editor_preview_mode and game.game_state != game.GameState.POINT_SCORED and not game.match_over
	if visible: sync()

func sync() -> void :
	if not visible or player == null: return
	var frame: = Basis(player._get_forehand_axis(), Vector3.UP, - player._get_forward_axis())
	var hint: Dictionary = player.posture.human_contact.superblock_hint if player.posture.human_contact else {}
	var active: int = int(hint.get("block_id", -1)) if Input.is_action_pressed("ui_accept") else -1
	for id in blocks:
		var item: Dictionary = blocks[id]
		var b: Dictionary = item.bounds
		item.node.global_transform = Transform3D(frame, Regions.world_point(player, (b.x_min + b.x_max) * 0.5, (b.y_min + b.y_max) * 0.5, b.forward))
		var mat: StandardMaterial3D = item.node.material_override
		var color: Color = Regions.COLORS[int(b.band)]
		mat.albedo_color = Color(color, 0.45 if int(id) == active else 0.08)
	for item in authored:
		item.node.global_transform = Transform3D(frame, Regions.world_point(player, item.x, item.y, item.forward))

func _box(size: Vector3, color: Color, alpha: float) -> MeshInstance3D:
	var mesh: = BoxMesh.new()
	mesh.size = size
	var material: = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(color, alpha)
	var node: = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	var half: Vector3 = size * 0.5
	var points: Array[Vector3] = []
	for y in [ - half.y, half.y]:
		for z in [ - half.z, half.z]: points.append(Vector3( - half.x, y, z));points.append(Vector3(half.x, y, z))
	for x in [ - half.x, half.x]:
		for z in [ - half.z, half.z]: points.append(Vector3(x, - half.y, z));points.append(Vector3(x, half.y, z))
	for x in [ - half.x, half.x]:
		for y in [ - half.y, half.y]: points.append(Vector3(x, y, - half.z));points.append(Vector3(x, y, half.z))
	_lines(node, points, color)
	return node

func _lines(parent: Node3D, points: Array, color: Color) -> void :
	var material: = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	var mesh: = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for point in points: mesh.surface_add_vertex(point)
	mesh.surface_end()
	var node: = MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
