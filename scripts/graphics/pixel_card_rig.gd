extends Node3D
class_name PixelCardRig
## 2.5D pixel-art cards pinned to the existing posture joints.
##
## Visual only: reads pivot transforms, never writes them, so IK, poses and
## gameplay are untouched (verified with tools/bench.sh + tools/pose_diff.py:
## identical pose traces with cards on and off). The rig lives beside the
## player, not under BodyPivot, because gameplay scans every BodyPivot mesh.
## The classic body meshes stay alive (gameplay reads their transforms and
## bounds) but move to a render layer the gameplay camera does not draw.
## Default on via Settings "video.character_style" = 1; set 0, or run with
## PICKLEBALL_CLASSIC_BODIES=1, for the classic 3D bodies. To retire the old
## 3D bodies later, delete this switch, not the meshes gameplay still reads.
## Card art: assets/pixel_cards (baked by the art generator in the main repo's
## docs/pixel_art_test/generator/make_cards.py).

const STYLE_KEY: = "video.character_style"   # 1 = pixel cards (default), 0 = classic 3D
const CLASSIC_LAYER: = 20                     # 1-based render layer hidden from the camera
const CELL_DEG: = 22.5
const HYSTERESIS_DEG: = 4.0
const META_PATH: = "res://assets/pixel_cards/cards_meta.json"
const TEXTURES: = ["res://assets/pixel_cards/cards_blue.png", "res://assets/pixel_cards/cards_red.png"]
const CARD_SHADER: = preload("res://shaders/pixel_card.gdshader")

static var _meta: Dictionary = {}

var _player  # player.gd instance (untyped: uses its script members)
var _cards: Array = []
var _cells: Dictionary = {}
var _hide_timer: float = 0.0

static func enabled() -> bool:
	# PICKLEBALL_CLASSIC_BODIES=1 forces classic bodies (benchmarks / A-B checks) without touching saved settings.
	if OS.get_environment("PICKLEBALL_CLASSIC_BODIES") == "1": return false
	return int(Settings.get_value(STYLE_KEY, 1)) == 1

static func attach(player) -> PixelCardRig:
	if player == null or player.body_pivot == null or not enabled(): return null
	# Cards live OUTSIDE the player: gameplay scans every mesh under BodyPivot
	# (surface contacts, geometry certificates), so cards there would change play.
	var host: Node = player.get_parent()
	if host == null: return null
	var rig_name: = "PixelCards_%d" % player.get_instance_id()
	var existing: Node = host.get_node_or_null(rig_name)
	if existing != null: existing.queue_free()
	var rig: = PixelCardRig.new()
	rig.name = rig_name
	rig._player = player
	host.add_child(rig)
	return rig

static func _load_meta() -> Dictionary:
	if _meta.is_empty():
		var f: = FileAccess.open(META_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary: _meta = parsed
	return _meta

func _ready() -> void:
	process_priority = 1000  # after posture / IK have moved the pivots
	var meta: = _load_meta()
	if meta.is_empty(): return
	var team: int = clampi(int(_player.get("team_id")) if _player.get("team_id") != null else _player.player_num, 0, 1)
	var tex: Texture2D = load(TEXTURES[team])
	var torso: Node3D = _player.body_pivot.get_node_or_null("TorsoMesh")
	var head: Node3D = torso.get_node_or_null("HeadMesh") if torso else null
	var hips: Node3D = _player.body_pivot.get_node_or_null("HipsMesh")
	_add("head", head, null, false, tex, meta, "head")
	_add("torso", torso, null, false, tex, meta, "torso")
	_add("shorts", hips if hips else _player.body_pivot, null, false, tex, meta, "body")
	for side in [["right", false], ["left", true]]:
		var arm: Node3D = _player.get(side[0] + "_arm_node")
		var leg: Node3D = _player.get(side[0] + "_leg_node")
		if arm and arm.get("upper_pivot"):
			_add("upper_arm", arm.upper_pivot, arm.forearm_pivot, side[1], tex, meta, "body")
			_add("forearm", arm.forearm_pivot, arm.hand_pivot, side[1], tex, meta, "body")
			_add("hand", arm.hand_pivot, null, side[1], tex, meta, "body", arm.forearm_pivot)
		if leg and leg.get("thigh_pivot"):
			_add("thigh", leg.thigh_pivot, leg.shin_pivot, side[1], tex, meta, "body")
			_add("shin", leg.shin_pivot, leg.foot_pivot, side[1], tex, meta, "body")
			_add("shoe", leg.foot_pivot, null, side[1], tex, meta, "body")
	_hide_classic()

func _add(part: String, a: Node3D, b: Node3D, mirror: bool, tex: Texture2D, meta: Dictionary, facing: String, prev: Node3D = null) -> void:
	if a == null or not meta.parts.has(part): return
	var info: Dictionary = meta.parts[part]
	# Unshaded, fog-free card shader; atlas colours are pre-compensated for the
	# game's Filmic tonemap, and `gain` lets highlights reach full white.
	var mat: = ShaderMaterial.new()
	mat.shader = CARD_SHADER
	mat.set_shader_parameter("atlas", tex)
	mat.set_shader_parameter("cell_scale", Vector2(1.0 / float(meta.cols), 1.0 / float(meta.rows)))
	mat.set_shader_parameter("gain", float(meta.get("gain", 1.0)))
	var mesh: = MeshInstance3D.new()
	mesh.name = "Card_%s%s" % [part, "_L" if mirror else ""]
	var quad: = QuadMesh.new()
	quad.size = Vector2.ONE
	mesh.mesh = quad
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.top_level = true
	mesh.set_meta("pixel_card", true)
	add_child(mesh)
	_cards.append({"mesh": mesh, "mat": mat, "a": a, "b": b, "prev": prev, "mirror": mirror, "row": int(info.row),
		"anchor": Vector2(info.anchor[0], info.anchor[1]), "end": Vector2(info.end[0], info.end[1]) if info.has("end") else Vector2.ZERO,
		"limb": info.has("end") and b != null, "facing": facing})

func _process(delta: float) -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_player.body_pivot):
		queue_free()
		return
	var cam: = get_viewport().get_camera_3d()
	if cam == null or _cards.is_empty(): return
	# Follow the player's visibility, and hide our own body in first-person view.
	var head_pos: Vector3 = _player.body_pivot.global_position + Vector3.UP * 1.5
	visible = _player.is_visible_in_tree() and cam.global_position.distance_to(head_pos) > 0.6
	if not visible: return
	cam.set_cull_mask_value(CLASSIC_LAYER, false)
	_hide_timer -= delta
	if _hide_timer <= 0.0:
		_hide_timer = 0.25
		_hide_classic()
	var meta: = _meta
	var s: float = float(meta.meters_per_texel)
	var cell: Vector2 = Vector2(meta.cell[0], meta.cell[1])
	var cols: int = int(meta.cols)
	var rows: int = int(meta.rows)
	var cam_pos: = cam.global_position
	var body_cell: int = _cell_for("body", _player.body_pivot, cam_pos)
	var torso_node: Node3D = _player.body_pivot.get_node_or_null("TorsoMesh")
	var torso_cell: int = _cell_for("torso", torso_node, cam_pos) if torso_node else body_cell
	var head_node: Node3D = torso_node.get_node_or_null("HeadMesh") if torso_node else null
	var head_cell: int = _cell_for("head", head_node, cam_pos) if head_node else torso_cell
	for c in _cards:
		var a: Vector3 = c.a.global_position
		var b: Vector3
		if c.limb: b = c.b.global_position
		elif c.prev != null: b = a + (a - c.prev.global_position).normalized() * 0.06
		else: b = a
		var mid: Vector3 = (a + b) * 0.5
		var z: Vector3 = (cam_pos - mid).normalized()
		var up_dir: Vector3
		var sy: float = s
		if c.limb or c.prev != null:
			var d: Vector3 = b - a
			var dp: Vector3 = d - z * d.dot(z)
			var texel_len: float = maxf(c.end.y - c.anchor.y, 1.0) if c.limb else 1.2
			if dp.length() < 0.0001: dp = -(Vector3.UP - z * z.y)
			up_dir = -dp.normalized()
			if c.limb: sy = dp.length() / texel_len
		else:
			var up_hint: Vector3 = c.a.global_basis.y if c.facing != "body" else Vector3.UP
			up_dir = (up_hint - z * up_hint.dot(z)).normalized()
		var x: Vector3 = up_dir.cross(z).normalized()
		var k: int = head_cell if c.facing == "head" else (torso_cell if c.facing == "torso" else body_cell)
		if c.mirror:
			x = -x
			k = (cols - k) % cols
		var anchor: Vector2 = c.anchor
		var origin_a: Vector3 = a + z * (mid - a).dot(z)
		var center: Vector3 = origin_a + x * ((cell.x * 0.5 - anchor.x) * s) - up_dir * ((cell.y * 0.5 - anchor.y) * sy)
		c.mesh.global_transform = Transform3D(Basis(x * (cell.x * s), up_dir * (cell.y * sy), z), center)
		c.mat.set_shader_parameter("cell_offset", Vector2(float(k) / cols, float(c.row) / rows))

func _cell_for(key: String, node: Node3D, cam_pos: Vector3) -> int:
	var fwd: Vector3 = node.global_basis * _player._get_forward_axis()
	fwd.y = 0.0
	var to_cam: Vector3 = cam_pos - node.global_position
	to_cam.y = 0.0
	if fwd.length() < 0.001 or to_cam.length() < 0.001: return int(_cells.get(key, 0))
	var rel: float = rad_to_deg(to_cam.normalized().signed_angle_to(fwd.normalized(), Vector3.UP))
	var cur: int = int(_cells.get(key, -1))
	if cur >= 0:
		var diff: float = wrapf(rel - cur * CELL_DEG, -180.0, 180.0)
		if absf(diff) <= CELL_DEG * 0.5 + HYSTERESIS_DEG: return cur
	cur = posmod(roundi(rel / CELL_DEG), 16)
	_cells[key] = cur
	return cur

func _hide_classic() -> void:
	var paddle: Node = _player.get("paddle_node")
	for node in _player.body_pivot.find_children("*", "GeometryInstance3D", true, false):
		if node.has_meta("pixel_card"): continue
		if paddle != null and (node == paddle or paddle.is_ancestor_of(node)): continue
		if node.layers != 0:
			node.layers = 1 << (CLASSIC_LAYER - 1)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
