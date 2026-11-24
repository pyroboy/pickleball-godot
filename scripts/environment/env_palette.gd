extends RefCounted
## Colour compensation for the environment (visual only).
##
## Environment materials draw unshaded at the player cards' gain (2.2), then the game's
## Filmic tonemap and PixelPost change the colour. `comp(display)` returns the colour to
## store so that it shows on screen as `display`, using the same in-engine measurement as
## the cards (assets/pixel_cards/card_tonemap_lut.json, from tools/calibrate_cards.gd).
## The chain tops out near 218/255, so brighter colours are scaled down keeping their hue.

const LUT_PATH := "res://assets/pixel_cards/card_tonemap_lut.json"
const GAIN := 2.2
const CEIL := 208.0
const POST_SATURATION := 1.08     # shaders/pixel_post.gdshader `saturation`

static var _inverse: PackedFloat32Array = PackedFloat32Array()


static func _build() -> void:
	var f := FileAccess.open(LUT_PATH, FileAccess.READ)
	var lut: Dictionary = JSON.parse_string(f.get_as_text())
	var atlas: Array = lut.atlas
	var screen: Array = lut.screen
	var xs: Array[float] = []
	var ys: Array[float] = []
	for i in atlas.size():
		var s := float(screen[i])
		if xs.is_empty() or s > xs[-1]:
			xs.append(s)
			ys.append(float(atlas[i]))
	_inverse.resize(256)
	for d in 256:
		var v := clampf(float(d), xs[0], xs[-1])
		var j := 0
		while j < xs.size() - 2 and xs[j + 1] < v: j += 1
		var t := (v - xs[j]) / maxf(xs[j + 1] - xs[j], 0.0001)
		_inverse[d] = lerpf(ys[j], ys[j + 1], clampf(t, 0.0, 1.0))


## Display colour (sRGB, as it should look on screen) -> stored colour (sRGB).
static func comp(display: Color) -> Color:
	if _inverse.is_empty(): _build()
	var r := display.r * 255.0
	var g := display.g * 255.0
	var b := display.b * 255.0
	var l := 0.299 * r + 0.587 * g + 0.114 * b
	r = l + (r - l) / POST_SATURATION
	g = l + (g - l) / POST_SATURATION
	b = l + (b - l) / POST_SATURATION
	var m := maxf(r, maxf(g, b))
	if m > CEIL:
		r *= CEIL / m; g *= CEIL / m; b *= CEIL / m
	return Color(_lookup(r) / 255.0, _lookup(g) / 255.0, _lookup(b) / 255.0, display.a)


static func hex(code: String) -> Color:
	return comp(Color(code))


static func _lookup(v: float) -> float:
	var i := clampi(int(v), 0, 254)
	return lerpf(_inverse[i], _inverse[i + 1], clampf(v - i, 0.0, 1.0))
