extends SceneTree
## Pixel viewport check (ROADMAP Phase 2), by data. Needs a window (not --headless):
##   godot --path . -s tools/pixel_grid_check.gd -- --mobile-runtime --autoplay --doubles --seed=1
## Loads the match, hides the UI layers, grabs one frame and prints one JSON line:
##   grid_uniform   share of low-res blocks whose output pixels are all one colour (want 1.0)
##   shifted_uniform  the same test one pixel off the grid (low = the image has real detail)
##   colours        distinct colours in the frame
##   camera         position, rotation, fov, keep_aspect (must not depend on the pixel scale)
##   ball_render_px ball diameter in 3D render pixels at the near and far baseline
## With --headless --fixed-fps 60 --viewport=720x1280 only the camera numbers print, and they repeat
## exactly, so two scales can be compared.
## PICKLEBALL_PIXEL_SCALE=0.5 runs the same check at another scale.

const WAIT_FRAMES := 240
var _game: Node
var _frame := 0

class Driver extends Node:
	var check
	func _process(_d: float) -> void: check._tick()

func _initialize() -> void:
	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(_game)
	var d := Driver.new()
	d.check = self
	root.add_child.call_deferred(d)

func _tick() -> void:
	_frame += 1
	if _frame == WAIT_FRAMES - 2:
		for layer in root.find_children("*", "CanvasLayer", true, false):
			if layer.name != "PixelPost": layer.visible = false
	if _frame != WAIT_FRAMES: return
	var img: Image = root.get_texture().get_image()
	var scale: float = root.scaling_3d_scale
	var headless: bool = img == null or img.is_empty()   # --headless --fixed-fps 60: camera numbers only (repeatable)
	var size: Vector2i = root.size if headless else img.get_size()
	var lo := Vector2i(maxi(int(size.x * scale), 1), maxi(int(size.y * scale), 1))
	var cam: Camera3D = root.get_camera_3d()
	var out := {"viewport": [size.x, size.y], "scale": snappedf(scale, 0.0001), "render": [lo.x, lo.y]}
	if not headless:
		out["grid_uniform"] = snappedf(_uniform(img, lo, 0), 0.0001)
		out["shifted_uniform"] = snappedf(_uniform(img, lo, 1), 0.0001)
		out["colours"] = _colours(img)
	if cam != null:
		var p := cam.global_position
		var r := cam.global_rotation_degrees
		out["camera"] = {"pos": [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)],
			"rot": [snappedf(r.x, 0.01), snappedf(r.y, 0.01), snappedf(r.z, 0.01)],
			"fov": snappedf(cam.fov, 0.001), "keep_aspect": cam.keep_aspect}
		var px := {}
		for z in [6.7, -6.7]:
			var c := Vector3(0.0, 0.8, z)
			var a := cam.unproject_position(c)
			var b := cam.unproject_position(c + cam.global_basis.x * 0.0375)
			px["z%+.1f" % z] = snappedf(a.distance_to(b) * 2.0 * scale * float(size.x) / root.get_visible_rect().size.x, 0.01)
		out["ball_render_px"] = px
	print("PIXEL_GRID " + JSON.stringify(out))
	quit()

## Share of low-res blocks whose output pixels all match. `shift` moves the block grid.
func _uniform(img: Image, lo: Vector2i, shift: int) -> float:
	var size := img.get_size()
	var data := img.get_data()
	var bpp: int = data.size() / (size.x * size.y)
	var good := 0
	var total := 0
	for by in range(1, lo.y - 1):
		var y0: int = by * size.y / lo.y + shift
		var y1: int = (by + 1) * size.y / lo.y + shift
		for bx in range(1, lo.x - 1):
			var x0: int = bx * size.x / lo.x + shift
			var x1: int = (bx + 1) * size.x / lo.x + shift
			var o: int = (y0 * size.x + x0) * bpp
			var same := true
			for y in range(y0, y1):
				for x in range(x0, x1):
					var q: int = (y * size.x + x) * bpp
					if data[q] != data[o] or data[q + 1] != data[o + 1] or data[q + 2] != data[o + 2]:
						same = false
						break
				if not same: break
			total += 1
			if same: good += 1
	return float(good) / maxf(float(total), 1.0)

func _colours(img: Image) -> int:
	var seen := {}
	var size := img.get_size()
	for y in range(0, size.y, 2):
		for x in range(0, size.x, 2):
			seen[img.get_pixel(x, y).to_rgba32()] = true
	return seen.size()
