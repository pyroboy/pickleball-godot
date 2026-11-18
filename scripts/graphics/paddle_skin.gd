extends Node3D
## Realistic paddle look (visual only). The gameplay paddle stays under BodyPivot with
## its meshes moved to a render layer the camera does not draw (gameplay still scans
## them); this node lives OUTSIDE the player and copies the paddle's interpolated
## transform every rendered frame. Designs: data/paddles.json. Shape = regulation
## outline from paddle_dimensions.gd, so the look always matches the hitbox.

const D = preload("res://scripts/paddle_dimensions.gd")
const DATA_PATH: = "res://data/paddles.json"
const SETTING_KEY: = "video.paddle"
const CLASSIC_LAYER: = 20   # same hidden layer as pixel_card_rig.gd
const FACE_W: = 40          # ~4.8 mm per texel: pixel look at gameplay zoom
const FACE_H: = 60
const GRIP_W: = 16
const GRIP_H: = 24
const EDGE_WRAP: = 0.005    # metres of edge guard visible on the face
const SUNSET: = [Color("#993c1d"), Color("#d85a30"), Color("#ef9f27"), Color("#f0997b")]

static var _data: Dictionary = {}
static var _materials: Dictionary = {}   # design id -> {face, edge, grip, cap}
static var _head_mesh: ArrayMesh

var design_id: = ""
var _player
var _paddle: Node3D
var _hide_timer: = 0.0
var _culled_cam: Camera3D

static func attach(player) -> Node3D:
	if player == null or player.get("paddle_node") == null: return null
	var host: Node = player.get_parent()
	if host == null: return null
	var skin_name: = "PaddleSkin_%d" % player.get_instance_id()
	var existing: Node = host.get_node_or_null(skin_name)
	if existing != null: existing.queue_free()
	var id: = _pick_design(player, host)
	if id == "": return null
	var skin: Node3D = (load("res://scripts/graphics/paddle_skin.gd") as GDScript).new()
	skin.name = skin_name
	skin.design_id = id
	skin._player = player
	skin._paddle = player.paddle_node
	skin.set_meta("paddle_design", id)
	host.add_child(skin)
	return skin

static func designs() -> Dictionary:
	if _data.is_empty():
		var f: = FileAccess.open(DATA_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary: _data = parsed
	return _data.get("designs", {})

## Human: saved choice (video.paddle) or the default. AI: a design nobody on court uses,
## picked with its own RNG so the global (bench-seeded) RNG is never touched.
static func _pick_design(player, host: Node) -> String:
	var all: = designs()
	if all.is_empty(): return ""
	# The player's sprite profile names a default paddle (pixel_card_rig.gd sets it).
	var rig: Node = host.get_node_or_null("PixelCards_%d" % player.get_instance_id())
	var own: = str(rig.get_meta("paddle", "")) if rig != null else ""
	var saved: = str(Settings.get_value(SETTING_KEY, ""))
	if not bool(player.get("is_ai")):
		for id in [saved, own, str(_data.get("default", ""))]:
			if all.has(id): return id
		return str(all.keys()[0])
	var used: Array = [saved]
	for child in host.get_children():
		if child.has_meta("paddle_design") and not child.is_queued_for_deletion():
			used.append(child.get_meta("paddle_design"))
	if all.has(own) and not used.has(own): return own
	var free: Array = all.keys().filter(func(k): return not used.has(k))
	if free.is_empty(): free = all.keys()
	var rng: = RandomNumberGenerator.new()
	rng.randomize()
	return str(free[rng.randi_range(0, free.size() - 1)])

func _ready() -> void:
	process_priority = 1001   # after posture / IK and the card rig
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var mats: Dictionary = _materials_for(design_id)
	if _head_mesh == null: _head_mesh = _build_head()
	var head: = _mesh_node(_head_mesh, Vector3.ZERO)
	head.set_surface_override_material(0, mats.face)
	head.set_surface_override_material(1, mats.face)
	head.set_surface_override_material(2, mats.edge)
	var grip_len: float = D.HANDLE_LENGTH - 0.008
	var grip: = CylinderMesh.new()
	grip.top_radius = D.HANDLE_RADIUS * 1.04   # tape sits proud of the handle
	grip.bottom_radius = grip.top_radius
	grip.height = grip_len
	grip.radial_segments = 12
	grip.rings = 1
	_mesh_node(grip, Vector3(0, 0.008 + grip_len * 0.5, 0)).material_override = mats.grip
	var cap: = CylinderMesh.new()
	cap.top_radius = D.HANDLE_RADIUS * 1.22
	cap.bottom_radius = cap.top_radius
	cap.height = 0.008
	cap.radial_segments = 12
	cap.rings = 1
	_mesh_node(cap, Vector3(0, 0.004, 0)).material_override = mats.cap
	var throat: = BoxMesh.new()
	throat.size = Vector3(0.028, 0.02, D.THICKNESS * 0.9)
	_mesh_node(throat, Vector3(0, D.HEAD_BOTTOM_Y + 0.004, 0)).material_override = mats.edge
	_hide_original()
	_follow()

func _mesh_node(mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var node: = MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(node)
	return node

func _process(delta: float) -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_paddle):
		queue_free()
		return
	# Mirror the original's visibility: hidden player, or first-person view (the
	# gameplay camera turns the avatar's meshes to shadows-only / layer 0 there).
	var head: = _paddle.get_node_or_null("Head") as GeometryInstance3D
	visible = _paddle.is_visible_in_tree() and head != null and head.layers != 0 \
		and head.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	if not visible: return
	var cam: = get_viewport().get_camera_3d()
	if cam != null and cam != _culled_cam:
		cam.set_cull_mask_value(CLASSIC_LAYER, false)
		_culled_cam = cam
	_hide_timer -= delta
	if _hide_timer <= 0.0:
		_hide_timer = 2.0
		_hide_original()
	_follow()

func _follow() -> void:
	# Pose editors pause physics and pose directly: read live transforms there.
	var posture = _player.get("posture")
	var raw: bool = get_tree().paused or (posture != null and posture.editor_preview_mode)
	global_transform = _paddle.global_transform if raw else _paddle.get_global_transform_interpolated()

func _hide_original() -> void:
	# Layer 20, never 0: gameplay (player_surface_contacts.gd) only skips layer-0 meshes.
	for node in _paddle.find_children("*", "GeometryInstance3D", true, false):
		if node.layers != 0:
			node.layers = 1 << (CLASSIC_LAYER - 1)

# --- meshes and materials (shared per design) ---------------------------------

## Front face (+z), back face (-z, u mirrored so graphics read correctly), rim.
static func _build_head() -> ArrayMesh:
	var outline: PackedVector2Array = D.head_outline()
	var r: float = D.HEAD_RADIUS
	var t: float = D.HEAD_HALF_THICKNESS
	var centre: = Vector2(0, D.HEAD_CENTER_Y)
	var mesh: = ArrayMesh.new()
	for side in [1.0, -1.0]:
		var st: = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(outline.size()):
			var a: Vector2 = outline[i]
			var b: Vector2 = outline[(i + 1) % outline.size()]
			for p in ([centre, b, a] if side > 0.0 else [centre, a, b]):
				var u: float = (p.x + r) / (2.0 * r)
				st.set_normal(Vector3(0, 0, side))
				st.set_uv(Vector2(u if side > 0.0 else 1.0 - u, 1.0 - (p.y - D.HEAD_BOTTOM_Y) / D.HEAD_LENGTH))
				st.add_vertex(Vector3(p.x, p.y, side * t))
		mesh = st.commit(mesh)
	var rim: = SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(outline.size()):
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		var e: Vector2 = b - a
		var n: = Vector3(e.y, -e.x, 0).normalized()
		for p in [Vector3(a.x, a.y, t), Vector3(b.x, b.y, t), Vector3(b.x, b.y, -t),
				Vector3(a.x, a.y, t), Vector3(b.x, b.y, -t), Vector3(a.x, a.y, -t)]:
			rim.set_normal(n)
			rim.add_vertex(p)
	return rim.commit(mesh)

static func _materials_for(id: String) -> Dictionary:
	if _materials.has(id): return _materials[id]
	var d: Dictionary = designs().get(id, {})
	var face: = _material(Color(d.get("base", "#262626")), 0.75)
	face.albedo_color = Color.WHITE
	face.albedo_texture = _face_texture(d)
	face.cull_mode = BaseMaterial3D.CULL_DISABLED
	var grip: = _material(Color.WHITE, 0.9)
	grip.albedo_texture = _grip_texture(Color(d.get("grip", "#1a1a1a")), Color(d.get("seam", "#3a3a3a")))
	var mats: = {"face": face, "grip": grip,
		"edge": _material(Color(d.get("edge", "#121212")), 0.6),
		"cap": _material(Color(d.get("cap", "#222222")), 0.5)}
	_materials[id] = mats
	return mats

static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var m: = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return m

static func _face_texture(d: Dictionary) -> ImageTexture:
	var base: = Color(d.get("base", "#262626"))
	var alt: = Color(d.get("alt", "#3a3a3a"))
	var ink: = Color(d.get("ink", "#9a9a9a"))
	var edge: = Color(d.get("edge", "#121212"))
	var kind: = str(d.get("face", "flat"))
	var graphic: = str(d.get("graphic", "none"))
	var rng: = RandomNumberGenerator.new()
	rng.seed = hash(str(d.get("name", "")))   # own RNG: same texture every run
	var img: = Image.create(FACE_W, FACE_H, false, Image.FORMAT_RGBA8)
	var r: float = D.HEAD_RADIUS
	var spine: float = D.HEAD_SPINE_HALF
	for y in range(FACE_H):
		for x in range(FACE_W):
			var u: = (x + 0.5) / FACE_W
			var v: = (y + 0.5) / FACE_H
			var col: = _surface(kind, x, y, base, alt, rng)
			col = _graphic(graphic, x, y, u, v, col, ink, alt)
			# Edge guard wraps a few millimetres onto the face.
			var px: = (u * 2.0 - 1.0) * r
			var py: = (0.5 - v) * D.HEAD_LENGTH
			if Vector2(px, py - clampf(py, -spine, spine)).length() - r > -EDGE_WRAP: col = edge
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

static func _surface(kind: String, x: int, y: int, base: Color, alt: Color, rng: RandomNumberGenerator) -> Color:
	match kind:
		"carbon_twill": return alt if (x + y) % 4 < 2 else base
		"carbon_cross": return alt if (x / 2 + y / 2) % 2 == 0 else base
		"graphite": return base.lerp(alt, rng.randf() * 0.7)
		"fiberglass": return base.lerp(base.lightened(0.08), rng.randf())
		"wood":
			var grain: = sin(x * 1.05 + sin(y * 0.16) * 2.2)
			return alt if grain > 0.6 else base.lerp(alt, rng.randf() * 0.15)
	return base

static func _graphic(kind: String, x: int, y: int, u: float, v: float, col: Color, ink: Color, alt: Color) -> Color:
	match kind:
		"wordmark":
			if u > 0.28 and u < 0.72 and v > 0.80 and v < 0.84: return ink
		"slash":
			var s: = v + u * 0.3
			if s > 0.70 and s < 0.82: return ink
		"dots_band":
			if v > 0.36 and v < 0.43: return ink
			if x % 5 == 2 and y % 5 == 2: return alt
		"block":
			var outer: = u > 0.22 and u < 0.78 and v > 0.25 and v < 0.63
			var inner: = u > 0.27 and u < 0.73 and v > 0.285 and v < 0.595
			if outer and not inner: return ink
		"stamp":
			var d: = Vector2((u - 0.5) * D.WIDTH, (v - 0.78) * D.HEAD_LENGTH).length()
			if d > 0.018 and d < 0.023: return ink
		"sunset":
			if v > 0.66:
				var band: = clampi(int((v - 0.66) / 0.075), 0, 3)
				# One dithered row at each band boundary.
				if band > 0 and v - (0.66 + band * 0.075) < 1.0 / FACE_H and (x + y) % 2 == 0: band -= 1
				return SUNSET[band]
	return col

static func _grip_texture(grip: Color, seam: Color) -> ImageTexture:
	var img: = Image.create(GRIP_W, GRIP_H, false, Image.FORMAT_RGBA8)
	for y in range(GRIP_H):
		for x in range(GRIP_W):
			# Spiral wrap: one diagonal seam every 6 texels.
			img.set_pixel(x, y, seam if (x + y) % 6 == 0 else grip)
	return ImageTexture.create_from_image(img)
