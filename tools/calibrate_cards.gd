extends SceneTree
## Measures how pixel-card atlas values appear on screen (card shader + the game's
## Filmic environment + PixelPost), so tools/bake_pixel_cards.py can pre-compensate.
## Windowed run (needs the real renderer):
##   godot --path . --resolution 768x768 --script tools/calibrate_cards.gd
## -> assets/pixel_cards/card_tonemap_lut.json: {"atlas": [0..255], "screen": [...]}
## Keep the environment below in step with scripts/game.gd.

const OUT: = "res://assets/pixel_cards/card_tonemap_lut.json"
const META: = "res://assets/pixel_cards/cards_meta.json"
var _frames: = 0

func _initialize() -> void:
	var root3d: = Node3D.new()
	root.add_child(root3d)
	var env: = WorldEnvironment.new()
	var e: = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.36, 0.65)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.tonemap_white = 6.0
	e.fog_enabled = false
	env.environment = e
	root3d.add_child(env)
	var cam: = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.0
	cam.position = Vector3(0, 0, 2)
	root3d.add_child(cam)
	# 16 x 16 grey ramp: texel (x, y) = level y * 16 + x.
	var img: = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for i in range(256):
		img.set_pixel(i % 16, i / 16, Color8(i, i, i, 255))
	var mat: = ShaderMaterial.new()
	mat.shader = load("res://shaders/pixel_card.gdshader")
	mat.set_shader_parameter("atlas", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("cell_offset", Vector2.ZERO)
	mat.set_shader_parameter("cell_scale", Vector2.ONE)
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(META))
	mat.set_shader_parameter("gain", float(meta.get("gain", 1.0)) if meta is Dictionary else 2.2)
	var quad: = MeshInstance3D.new()
	var mesh: = QuadMesh.new()
	mesh.size = Vector2.ONE
	quad.mesh = mesh
	quad.material_override = mat
	root3d.add_child(quad)
	var post: CanvasLayer = load("res://scripts/graphics/pixel_post.gd").new()
	root.add_child(post)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		# No vignette: players sit mostly mid-screen; measure the pure transfer.
		var rect: = root.find_child("PixelPost", true, false) as ColorRect
		if rect != null: (rect.material as ShaderMaterial).set_shader_parameter("vignette", 0.0)
	if _frames < 30: return false
	var shot: = root.get_texture().get_image()
	var w: = shot.get_width(); var h: = shot.get_height()
	var side: = mini(w, h)
	var x0: = (w - side) / 2; var y0: = (h - side) / 2
	var screen: = []
	for i in range(256):
		# Centre of texel block (i % 16, i / 16); image y goes down, texture v goes down too.
		var px: = x0 + int((i % 16 + 0.5) * side / 16.0)
		var py: = y0 + int((i / 16 + 0.5) * side / 16.0)
		var c: = shot.get_pixel(px, py)
		screen.append(roundi((c.r + c.g + c.b) / 3.0 * 255.0))
	var atlas: = []
	for i in range(256): atlas.append(i)
	var f: = FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify({"atlas": atlas, "screen": screen, "note": "tools/calibrate_cards.gd"}))
	f.close()
	print("card tonemap LUT: ", screen.slice(0, 256, 32))
	return true
