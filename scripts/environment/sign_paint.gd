extends RefCounted
## Hand-painted shop signs baked into a small pixel texture on a flat board.
##
## The 3D world renders at 1/3 resolution (scripts/graphics/pixel_post.gd). At the far end a
## Label3D with the 9 px UI font (arjo_pixel.fnt) gets about 0.4 render px per font pixel on a
## 720-wide view and 0.7 on an iPhone (1179 wide), so nearest sampling drops letter strokes and
## the words garble. These signs use chunky 3x5 capitals instead: few, big texels. Pick `texel`
## (metres per sign pixel) so one texel stays >= 1 render pixel where the sign is seen.
## Nearest filtering, no mipmaps, unshaded, no fog: the paint keeps its contrast. Built once.

const ROWS := 5

## 3x5 capitals ("#" = ink); I is one column, M, N and W are wider so they stay readable.
const GLYPHS := {
	"A": ["###", "#.#", "###", "#.#", "#.#"],
	"B": ["##.", "#.#", "##.", "#.#", "##."],
	"C": ["###", "#..", "#..", "#..", "###"],
	"D": ["##.", "#.#", "#.#", "#.#", "##."],
	"E": ["###", "#..", "##.", "#..", "###"],
	"F": ["###", "#..", "##.", "#..", "#.."],
	"G": ["###", "#..", "#.#", "#.#", "###"],
	"H": ["#.#", "#.#", "###", "#.#", "#.#"],
	"I": ["#", "#", "#", "#", "#"],
	"J": ["..#", "..#", "..#", "#.#", "###"],
	"K": ["#.#", "#.#", "##.", "#.#", "#.#"],
	"L": ["#..", "#..", "#..", "#..", "###"],
	"M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
	"N": ["#..#", "##.#", "#.##", "#..#", "#..#"],
	"O": ["###", "#.#", "#.#", "#.#", "###"],
	"P": ["###", "#.#", "###", "#..", "#.."],
	"R": ["##.", "#.#", "##.", "#.#", "#.#"],
	"S": ["###", "#..", "###", "..#", "###"],
	"T": ["###", ".#.", ".#.", ".#.", ".#."],
	"U": ["#.#", "#.#", "#.#", "#.#", "###"],
	"V": ["#.#", "#.#", "#.#", "#.#", ".#."],
	"W": ["#...#", "#...#", "#.#.#", "##.##", "#...#"],
	"X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
	"Y": ["#.#", "#.#", ".#.", ".#.", ".#."],
	"Z": ["###", "..#", ".#.", "#..", "###"],
	"-": ["...", "...", "###", "...", "..."],
	" ": ["..", "..", "..", "..", ".."],
}


## Size in sign pixels: a 1 px frame, a 1 px margin and the text.
static func pixel_size(text: String) -> Vector2i:
	var w := 0
	for ch in text:
		w += (GLYPHS[ch][0] as String).length() + 1
	return Vector2i(w - 1 + 4, ROWS + 4)


## A board facing +z, centred on its node. `paint` is the board, `ink` the letters and `frame`
## the painted edge. Letters vary a touch in shade, like brush paint.
static func board(text: String, texel: float, paint: Color, ink: Color, frame: Color) -> MeshInstance3D:
	var size := pixel_size(text)
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(frame)
	img.fill_rect(Rect2i(1, 1, size.x - 2, size.y - 2), paint)
	var x := 2
	var i := 0
	for ch in text:
		var rows: Array = GLYPHS[ch]
		var shade: Color = ink.darkened(0.05 * float(i % 3))
		for r in ROWS:
			var row: String = rows[r]
			for c in row.length():
				if row[c] == "#": img.set_pixel(x + c, 2 + r, shade)
		x += (rows[0] as String).length() + 1
		i += 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.albedo_texture = ImageTexture.create_from_image(img)   # no mipmaps
	mat.disable_fog = true
	var quad := QuadMesh.new()
	quad.size = Vector2(size) * texel
	var mi := MeshInstance3D.new()
	mi.name = "Sign_" + text.replace(" ", "_")
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
