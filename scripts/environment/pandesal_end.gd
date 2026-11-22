extends RefCounted
## The pandesal end of the barangay court (visual only): the end the camera faces after a
## doubles change of ends. Authored like the hall end ("far" = -z, screen-left = -x) and
## placed by barangay_world.gd in a child node turned half a turn; people and shadows go
## through `w._end_pos`.
##
## Highlight: a malunggay pandesal cart with its vendor (calls out with a bulb horn, opens
## the box in a puff of steam, bags rolls, hands them over) and a queue of passers-by who
## walk off eating. Around it: a two-storey panaderya, a waiting shed with commuters and a
## jeepney that stops there, a capilla with a belfry, a vulcanizing shop with a mechanic,
## a gray concrete electric post plastered with blue and red septic-tank stickers, a poso
## with a kid pumping water, lolos playing dama, cats on a hollow-block wall, a rooster in a
## cage, and an audience with the same personalities as the hall end.

const Kit := preload("res://scripts/environment/env_mesh_kit.gd")
const Fig := preload("res://scripts/environment/env_figures.gd")
const People := preload("res://scripts/environment/env_people.gd")

const CART := Vector3(3.6, 0, -12.0)
const VENDOR := Vector3(3.6, 0, -12.75)
const QUEUE := [Vector3(2.55, 0, -11.7), Vector3(1.95, 0, -11.75), Vector3(1.35, 0, -11.8)]
const LANE := -14.3          # this end's walking lane
const JEEP_LANE := -16.4
const JEEP_STOP := -2.9      # in front of the waiting shed
const POST := Vector3(1.4, 0, -15.0)


# ------------------------------------------------------------------ geometry

static func build_geometry(w, bld: SurfaceTool, props: SurfaceTool, cloth: SurfaceTool) -> void:
	_panaderya(w, bld)
	_waiting_shed(w, bld)
	_capilla(w, bld)
	_vulcanizing(w, bld)
	_wall_and_cage(w, bld, props)
	_sticker_post(w, props, cloth)
	_poso(w, props)
	_dama_table(w, props)
	_cart(w, props, cloth)
	_audience_seats(w, props)
	_side_pieces(w, props)
	w._build_background(bld)
	_jeepney(w)


static func _panaderya(w, st: SurfaceTool) -> void:
	# Two-storey bakery in the corner: open shop front with a glass counter and shelves of
	# bread, striped awning, the sign; peach upper floor with windows and a balcony.
	var x0 := -12.6
	var x1 := -6.8
	var zf := -18.0
	var zb := -23.0
	var cx := (x0 + x1) * 0.5
	var peach: Color = w._c("#e8b98f")
	Kit.box(st, Vector3(cx, 1.5, (zf + zb) * 0.5), Vector3(x1 - x0, 3.0, zf - zb), w._c("#d9d2c2"))
	Kit.box(st, Vector3(cx, 1.4, zf + 0.01), Vector3(4.2, 2.1, 0.04), w._c("#3a3238"))           # open front
	for k in 3:
		Kit.box(st, Vector3(cx, 0.9 + k * 0.5, zf - 0.3), Vector3(3.9, 0.06, 0.3), w._c("#8f6a46"))
		var bx := cx - 1.8
		while bx < cx + 1.8:
			Kit.box(st, Vector3(bx, 0.98 + k * 0.5, zf - 0.25), Vector3(0.12, 0.09, 0.12), w._c(["#d39b55", "#c98a45", "#e0b06a"][(k + int(bx * 7.0)) % 3]))
			bx += 0.17
	Kit.box(st, Vector3(cx, 0.55, zf + 0.35), Vector3(3.6, 1.1, 0.55), w._c("#e6e2d6"))          # glass counter
	Kit.box(st, Vector3(cx, 0.85, zf + 0.63), Vector3(3.4, 0.4, 0.02), w._c("#a9d3e2"))
	var bx2 := cx - 1.55
	while bx2 < cx + 1.6:
		Kit.box(st, Vector3(bx2, 0.8, zf + 0.5), Vector3(0.14, 0.1, 0.14), w._c("#d39b55"))
		bx2 += 0.22
	for i in 9:   # striped awning
		var ax := x0 + 0.3 + i * (x1 - x0 - 0.6) / 9.0
		w._gi_roof(st, ax, ax + (x1 - x0 - 0.6) / 9.0, zf + 1.0, zf, 2.55, 2.85, false)
		Kit.quad(st, Vector3(ax, 2.57, zf + 1.0), Vector3(ax, 2.87, zf), Vector3(ax + (x1 - x0 - 0.6) / 9.0, 2.87, zf), Vector3(ax + (x1 - x0 - 0.6) / 9.0, 2.57, zf + 1.0), w._c("#d23b34") if i % 2 == 0 else w._c("#f2efe6"))
	Kit.box(st, Vector3(cx, 3.15, zf + 0.06), Vector3(4.0, 0.5, 0.06), w._c("#6a4532"))
	w._label("PANADERYA", Vector3(cx, 3.15, zf + 0.1), 0.34, Color(1.0, 0.92, 0.72))
	# upper floor
	Kit.box(st, Vector3(cx, 4.5, (zf + zb) * 0.5 - 0.1), Vector3(x1 - x0, 2.6, zf - zb - 0.2), peach)
	for wx: float in [cx - 1.6, cx + 1.6]:
		w._window(st, Vector3(wx, 4.6, zf - 0.08), Vector2(1.1, 1.0), w._c("#3e6fb2"), false)
	Kit.box(st, Vector3(cx, 3.38, zf + 0.5), Vector3(x1 - x0 - 0.4, 0.12, 1.0), w._c("#a9a59c"))
	Kit.box(st, Vector3(cx, 3.9, zf + 0.98), Vector3(x1 - x0 - 0.4, 0.06, 0.05), w._c("#3e6fb2"))
	var px := x0 + 0.3
	while px < x1 - 0.2:
		Kit.box(st, Vector3(px, 3.65, zf + 0.98), Vector3(0.04, 0.5, 0.04), w._c("#3e6fb2"))
		px += 0.3
	for k in 3: Kit.cylinder(st, Vector3(cx - 1.8 + k * 1.8, 3.44, zf + 0.75), 0.13, 0.17, 0.25, w._c("#b5603e"), 6)
	w._shade_strip(st, x0, x1, zf - 0.09, 5.8, 0.45, peach)
	w._gi_roof(st, x0 - 0.3, x1 + 0.3, zf + 0.5, zb - 0.3, 6.05, 5.45, true)
	w._shadow(Vector3(cx + 0.6, 0, zf - 0.6), Vector2(x1 - x0 + 1.0, 1.6), true)


static func _waiting_shed(w, st: SurfaceTool) -> void:
	var x0 := -4.6
	var x1 := -1.2
	var zf := -17.4
	var zb := -18.6
	var cx := (x0 + x1) * 0.5
	for px: float in [x0 + 0.1, x1 - 0.1]:
		for pz: float in [zf, zb]:
			Kit.box(st, Vector3(px, 1.2, pz), Vector3(0.14, 2.4, 0.14), w._c("#bdb7aa"))
	Kit.box(st, Vector3(cx, 1.2, zb - 0.05), Vector3(x1 - x0, 1.5, 0.1), w._c("#c9c2b2"))       # back wall
	Kit.box(st, Vector3(cx, 0.42, zb + 0.35), Vector3(x1 - x0 - 0.3, 0.08, 0.45), w._c("#a29d93"))
	Kit.box(st, Vector3(cx, 0.2, zb + 0.35), Vector3(x1 - x0 - 0.5, 0.4, 0.3), w._c("#958f84"))
	w._gi_roof(st, x0 - 0.25, x1 + 0.25, zf + 0.5, zb - 0.3, 2.45, 2.75, true)
	Kit.box(st, Vector3(cx, 2.62, zf + 0.52), Vector3(2.6, 0.36, 0.05), w._c("#f2efe6"))
	w._label("WAITING SHED", Vector3(cx, 2.62, zf + 0.56), 0.22, Color(0.2, 0.3, 0.6))
	w._shadow(Vector3(cx + 0.3, 0, (zf + zb) * 0.5), Vector2(x1 - x0 + 0.6, 1.6), true)


static func _capilla(w, st: SurfaceTool) -> void:
	# Small whitewashed chapel: gable front with a belfry and a cross, arched door, steps.
	var x0 := 0.8
	var x1 := 4.0
	var zf := -24.0
	var zb := -29.0
	var cx := (x0 + x1) * 0.5
	var white: Color = w._c("#efe9da")
	Kit.box(st, Vector3(cx, 2.0, (zf + zb) * 0.5), Vector3(x1 - x0, 4.0, zf - zb), white)
	Kit.tri(st, Vector3(x0, 4.0, zf), Vector3(x1, 4.0, zf), Vector3(cx, 5.6, zf), white, 0.0, true)
	Kit.beam(st, Vector3(x0 - 0.1, 3.95, zf + 0.04), Vector3(cx, 5.7, zf + 0.04), 0.12, w._c("#3e6fb2"))
	Kit.beam(st, Vector3(x1 + 0.1, 3.95, zf + 0.04), Vector3(cx, 5.7, zf + 0.04), 0.12, w._c("#3e6fb2"))
	w._gi_roof(st, x0 - 0.2, cx, zf, zb, 4.0, 5.6, false)
	w._gi_roof(st, cx, x1 + 0.2, zb, zf, 5.6, 4.0, false)
	# belfry on the gable: four posts, a little roof, the bell, a cross above
	for bx: float in [-0.35, 0.35]:
		Kit.box(st, Vector3(cx + bx, 6.05, zf - 0.1), Vector3(0.1, 0.9, 0.1), white)
	Kit.box(st, Vector3(cx, 6.55, zf - 0.1), Vector3(0.95, 0.12, 0.5), w._c("#3e6fb2"))
	Kit.cylinder(st, Vector3(cx, 5.75, zf - 0.1), 0.2, 0.12, 0.45, w._c("#a8843c"), 8)
	Kit.box(st, Vector3(cx, 7.05, zf - 0.1), Vector3(0.08, 0.9, 0.08), w._c("#e8e6e0"))
	Kit.box(st, Vector3(cx, 7.2, zf - 0.1), Vector3(0.45, 0.08, 0.08), w._c("#e8e6e0"))
	# arched door, small windows, steps
	Kit.box(st, Vector3(cx, 1.2, zf + 0.02), Vector3(1.1, 2.4, 0.04), w._c("#6a4532"))
	Kit.box(st, Vector3(cx, 2.48, zf + 0.02), Vector3(0.7, 0.2, 0.04), w._c("#6a4532"))
	for wx: float in [x0 + 0.55, x1 - 0.55]:
		Kit.box(st, Vector3(wx, 2.2, zf + 0.02), Vector3(0.4, 1.0, 0.04), w._c("#34303a"))
		Kit.box(st, Vector3(wx, 2.75, zf + 0.03), Vector3(0.5, 0.1, 0.05), w._c("#3e6fb2"))
	for i in 2: Kit.box(st, Vector3(cx, 0.08 + i * 0.08, zf + 0.5 - i * 0.25), Vector3(1.8, 0.16 + i * 0.16, 0.5), w._c("#a29d93"))
	w._shadow(Vector3(x1 + 0.9, 0, (zf + zb) * 0.5), Vector2(1.8, zf - zb), true)


static func _vulcanizing(w, st: SurfaceTool) -> void:
	var x0 := 5.0
	var x1 := 9.2
	var zf := -18.5
	var zb := -22.0
	var cx := (x0 + x1) * 0.5
	Kit.box(st, Vector3(cx, 1.5, (zf + zb) * 0.5), Vector3(x1 - x0, 3.0, zf - zb), w._c("#9fb8a0"))
	Kit.box(st, Vector3(cx - 0.3, 1.15, zf + 0.01), Vector3(2.8, 2.3, 0.04), w._c("#2f2b30"))     # open bay
	Kit.box(st, Vector3(cx, 2.75, zf + 0.06), Vector3(3.8, 0.5, 0.06), w._c("#f2efe6"))
	w._label("VULCANIZING", Vector3(cx, 2.75, zf + 0.1), 0.3, Color(0.82, 0.16, 0.14))
	w._gi_roof(st, x0 - 0.25, x1 + 0.25, zf + 0.8, zb - 0.3, 3.05, 3.4, true)
	# tyre stacks, an air compressor, a hanging tyre sign
	for t in [[x0 + 0.1, -17.8, 5], [x1 - 0.2, -17.9, 4], [x1 - 0.75, -17.7, 3]]:
		for k in int(t[2]):
			Kit.cylinder(st, Vector3(t[0], k * 0.2, t[1]), 0.32, 0.32, 0.19, w._c("#26232a"), 8)
			Kit.cylinder(st, Vector3(t[0], k * 0.2 + 0.19, t[1]), 0.14, 0.14, 0.01, w._c("#4a4650"), 6)
	Kit.box(st, Vector3(6.3, 0.35, -17.9), Vector3(0.9, 0.42, 0.42), w._c("#c9332c"))
	Kit.box(st, Vector3(6.3, 0.7, -17.9), Vector3(0.3, 0.28, 0.3), w._c("#3a3a40"))
	for wx: float in [5.95, 6.65]: Kit.box(st, Vector3(wx, 0.07, -17.9), Vector3(0.12, 0.14, 0.12), w._c("#26232a"))
	# a bicycle being fixed, the mechanic squats beside it (a person, see build_people)
	var bike := Vector3(7.95, 0, -17.55)
	for bz: float in [-0.45, 0.45]:
		Kit.box(st, bike + Vector3(bz, 0.33, 0), Vector3(0.6, 0.6, 0.06), w._c("#26232a"), Basis(Vector3.FORWARD, PI * 0.25))
		Kit.box(st, bike + Vector3(bz, 0.33, 0), Vector3(0.6, 0.6, 0.06), w._c("#26232a"))
	Kit.beam(st, bike + Vector3(-0.45, 0.33, 0), bike + Vector3(0.0, 0.65, 0), 0.04, w._c("#3e7fd0"))
	Kit.beam(st, bike + Vector3(0.45, 0.33, 0), bike + Vector3(0.0, 0.65, 0), 0.04, w._c("#3e7fd0"))
	Kit.beam(st, bike + Vector3(0.0, 0.65, 0), bike + Vector3(0.35, 0.85, 0), 0.04, w._c("#3e7fd0"))
	w._shadow(Vector3(cx + 0.5, 0, zf - 0.3), Vector2(x1 - x0 + 0.8, 1.2), true)
	w._shadow(bike, Vector2(1.3, 0.4))


static func _wall_and_cage(w, st: SurfaceTool, props: SurfaceTool) -> void:
	# low hollow-block wall in front of the capilla (cats sit on it), a rooster cage
	var y := 0.1
	while y < 1.3:
		var off := 0.0 if int(y * 5.0) % 2 == 0 else 0.2
		var x := 0.2 + off
		while x < 4.55:
			Kit.box(st, Vector3(x + 0.19, y, -19.4), Vector3(0.38, 0.19, 0.2), w._c("#9c988f"))
			x += 0.4
		y += 0.2
	Kit.box(st, Vector3(2.4, 1.33, -19.4), Vector3(4.4, 0.06, 0.24), w._c("#8f8b84"))
	var cage := Vector3(4.3, 0, -18.85)
	Kit.box(props, cage + Vector3(0, 0.05, 0), Vector3(0.7, 0.1, 0.6), w._c("#8a6a46"))
	for cx: float in [-0.33, 0.33]:
		for cz: float in [-0.28, 0.28]:
			Kit.box(props, cage + Vector3(cx, 0.4, cz), Vector3(0.03, 0.7, 0.03), w._c("#c4ae68"))
	var bx := -0.3
	while bx <= 0.31:
		Kit.box(props, cage + Vector3(bx, 0.4, 0.28), Vector3(0.015, 0.68, 0.015), w._c("#d9c48a"))
		bx += 0.1
	Kit.box(props, cage + Vector3(0, 0.77, 0), Vector3(0.72, 0.04, 0.62), w._c("#c4ae68"))
	w._shadow(cage, Vector2(0.9, 0.7), true)


static func _sticker_post(w, props: SurfaceTool, cloth: SurfaceTool) -> void:
	# Gray concrete electric post plastered with blue and red septic-tank service stickers.
	var concrete: Color = w._c("#9e9b94")
	Kit.cylinder(props, POST, 0.15, 0.1, 7.8, concrete, 8)
	Kit.box(props, POST + Vector3(0, 7.25, 0), Vector3(1.8, 0.12, 0.12), w._c("#7d5c3e"))
	for ix: float in [-0.75, 0.0, 0.75]:
		Kit.cylinder(props, POST + Vector3(ix, 7.3, 0), 0.04, 0.03, 0.12, w._c("#e8e6e0"), 5)
	Kit.cylinder(props, POST + Vector3(0.28, 5.7, 0), 0.24, 0.24, 0.65, w._c("#7f868a"), 8)
	var blue: Color = w._c("#2f5fb8")
	var red: Color = w._c("#d23b34")
	var white: Color = w._c("#f2efe6")
	var y := 0.85
	var row := 0
	while y < 2.7:
		for col in 2:
			var ang := -0.55 + col * 0.55 + (0.2 if row % 2 else 0.0)
			var n := Vector3(sin(ang), 0, cos(ang))
			var r := 0.15 - (y / 7.8) * 0.05 + 0.006
			var c := POST + n * r + Vector3(0, y, 0)
			var b := Basis(Vector3.UP, ang)
			var faded := (row * 3 + col) % 7 == 0
			var col_c: Color = (blue if (row + col) % 2 == 0 else red) if not faded else w._c("#b8b3aa")
			Kit.box(props, c, Vector3(0.17, 0.12, 0.012), col_c, b)
			Kit.box(props, c + n * 0.007 + Vector3(0, 0.025, 0), Vector3(0.13, 0.025, 0.006), white, b)
			Kit.box(props, c + n * 0.007 + Vector3(0, -0.02, 0), Vector3(0.09, 0.015, 0.006), white, b)
		y += 0.15
		row += 1
	w._shadow(POST, Vector2(0.5, 0.4))
	# the other two posts, wires and banderitas strung through the sticker post
	var wire: Color = w._c("#2e2c30")
	for x: float in [-9.3, 9.3]:
		Kit.cylinder(props, Vector3(x, 0, -15.2), 0.13, 0.09, 7.6, concrete, 6)
		Kit.box(props, Vector3(x, 7.05, -15.2), Vector3(1.6, 0.1, 0.1), w._c("#7d5c3e"))
		w._shadow(Vector3(x, 0, -15.2), Vector2(0.4, 0.3))
	for ix: float in [-0.65, 0.0, 0.65]:
		Kit.rope(props, Vector3(-9.3 + ix, 7.15, -15.2), POST + Vector3(ix, 7.3, 0), 0.4, 0.025, wire, 8)
		Kit.rope(props, POST + Vector3(ix, 7.3, 0), Vector3(9.3 + ix, 7.15, -15.2), 0.4, 0.025, wire, 8)
		Kit.rope(props, Vector3(9.3 + ix, 7.15, -15.2), Vector3(30.0, 7.0, -18.0), 0.6, 0.025, wire, 8)
		Kit.rope(props, Vector3(-9.3 + ix, 7.15, -15.2), Vector3(-30.0, 7.0, -17.0), 0.6, 0.025, wire, 8)
	var flags := [w._c("#e0473b"), w._c("#f2c84b"), w._c("#3e7fd0"), w._c("#f2f0ea"), w._c("#7cc490"), w._c("#f29ac0")]
	for seg in [[Vector3(-9.3, 6.3, -15.15), POST + Vector3(0, 6.3, 0.05)], [POST + Vector3(0, 6.3, 0.05), Vector3(9.3, 6.3, -15.15)]]:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		Kit.rope(cloth, a, b, 0.5, 0.015, w._c("#efe8d8"), 10, 0.0)
		var n := int(a.distance_to(b) / 0.4)
		for i in n:
			var p := Kit.rope_point(a, b, 0.5, (i + 0.5) / n)
			Kit.tri(cloth, p + Vector3(-0.13, 0, 0), p + Vector3(0.0, -0.3, 0.01), p + Vector3(0.13, 0, 0), flags[i % flags.size()], 0.55, true)


static func _poso(w, props: SurfaceTool) -> void:
	var at := Vector3(-0.45, 0, -18.1)
	Kit.box(props, at + Vector3(0, 0.08, 0), Vector3(0.8, 0.16, 0.8), w._c("#a29d93"))
	Kit.cylinder(props, at + Vector3(0, 0.16, 0), 0.09, 0.09, 0.95, w._c("#3f6f5a"), 8)
	Kit.cylinder(props, at + Vector3(0, 1.1, 0), 0.12, 0.12, 0.15, w._c("#3f6f5a"), 8)
	Kit.beam(props, at + Vector3(0, 1.2, 0), at + Vector3(-0.55, 1.35, 0), 0.04, w._c("#3f6f5a"))
	Kit.beam(props, at + Vector3(0.05, 0.85, 0), at + Vector3(0.28, 0.8, 0), 0.05, w._c("#3f6f5a"))
	Kit.cylinder(props, at + Vector3(0.3, 0.16, 0), 0.15, 0.18, 0.32, w._c("#3e7fd0"), 8)
	w._shadow(at, Vector2(0.9, 0.8))


static func _dama_table(w, props: SurfaceTool) -> void:
	var t := Vector3(-6.6, 0, -12.6)
	Kit.box(props, t + Vector3(0, 0.28, 0), Vector3(0.6, 0.56, 0.6), w._c("#a8845a"))
	for i in 3: Kit.box(props, t + Vector3(0, 0.12 + i * 0.16, 0.301), Vector3(0.6, 0.02, 0.01), w._c("#7d5c3e"))
	for gx in 4:
		for gz in 4:
			Kit.box(props, t + Vector3(-0.21 + gx * 0.14, 0.57, -0.21 + gz * 0.14), Vector3(0.14, 0.01, 0.14), w._c("#f2efe6") if (gx + gz) % 2 == 0 else w._c("#3a3238"))
	for k in 5: Kit.cylinder(props, t + Vector3(-0.2 + (k * 37 % 5) * 0.1, 0.58, -0.18 + (k * 23 % 4) * 0.12), 0.035, 0.035, 0.02, w._c("#d23b34") if k % 2 else w._c("#f2c84b"), 6)
	for sx: float in [-0.55, 0.55]:
		Kit.box(props, t + Vector3(sx, 0.18, 0), Vector3(0.32, 0.36, 0.32), w._c("#e0473b") if sx < 0.0 else w._c("#3e7fd0"))
	w._shadow(t, Vector2(1.6, 0.8))


static func _cart(w, props: SurfaceTool, cloth: SurfaceTool) -> void:
	# Malunggay pandesal pushcart: wooden body on bicycle wheels, a glass display box of
	# golden rolls flecked green, the painted sign, a striped umbrella, paper bags on a
	# string, a thermos and coffee sachet strips.
	var c := CART
	var wood: Color = w._c("#9a6a40")
	for wz: float in [-0.38, 0.38]:
		var hub := c + Vector3(-0.15, 0.26, wz)
		Kit.box(props, hub, Vector3(0.5, 0.5, 0.04), w._c("#2a2730"), Basis(Vector3.FORWARD, PI * 0.25))
		Kit.box(props, hub, Vector3(0.5, 0.5, 0.04), w._c("#2a2730"))
		Kit.box(props, hub + Vector3(0, 0, 0.01 * signf(wz)), Vector3(0.38, 0.38, 0.03), w._c("#8a8f94"), Basis(Vector3.FORWARD, PI * 0.25))
		Kit.box(props, hub + Vector3(0, 0, 0.012 * signf(wz)), Vector3(0.32, 0.32, 0.03), w._c("#2a2730"))
		Kit.box(props, hub + Vector3(0, 0, 0.02 * signf(wz)), Vector3(0.32, 0.025, 0.02), w._c("#b9bcc0"))
		Kit.box(props, hub + Vector3(0, 0, 0.02 * signf(wz)), Vector3(0.025, 0.32, 0.02), w._c("#b9bcc0"))
	Kit.beam(props, c + Vector3(0.55, 0.62, 0.0), c + Vector3(0.6, 0.0, 0.0), 0.05, wood)          # stand leg
	Kit.box(props, c + Vector3(0, 0.78, 0), Vector3(1.4, 0.42, 0.66), wood)
	Kit.box(props, c + Vector3(0, 1.0, 0), Vector3(1.46, 0.04, 0.72), w._c("#7d5638"))
	Kit.box(props, c + Vector3(0, 0.75, 0.335), Vector3(1.2, 0.3, 0.01), w._c("#f4f1e8"))
	w._label("MALUNGGAY\nPANDESAL", c + Vector3(0, 0.76, 0.345), 0.12, Color(0.85, 0.15, 0.12))
	# open tray of rolls (golden, flecked green) under a framed glass lid
	Kit.box(props, c + Vector3(0, 1.06, 0), Vector3(1.22, 0.08, 0.58), w._c("#7d5638"))
	for gx in 6:
		for gz in 3:
			var p := c + Vector3(-0.5 + gx * 0.2, 1.15, -0.18 + gz * 0.18)
			Kit.box(props, p, Vector3(0.15, 0.1, 0.14), w._c(["#d39b55", "#c98a45", "#e0b06a"][(gx + gz) % 3]))
			Kit.box(props, p + Vector3(0.02, 0.055, 0.01), Vector3(0.03, 0.01, 0.03), w._c("#5f9a45"))
	for fx: float in [-0.6, 0.6]:
		Kit.box(props, c + Vector3(fx, 1.3, 0), Vector3(0.03, 0.42, 0.58), w._c("#c9ccd0"))
	Kit.box(props, c + Vector3(0, 1.3, -0.28), Vector3(1.2, 0.42, 0.02), w._c("#b9dbe6"))       # back glass
	Kit.quad(props, c + Vector3(-0.6, 1.52, -0.28), c + Vector3(-0.6, 1.62, 0.1), c + Vector3(0.6, 1.62, 0.1), c + Vector3(0.6, 1.52, -0.28), w._c("#c9e3ec"))   # lid, propped open
	Kit.box(props, c + Vector3(0, 1.51, -0.28), Vector3(1.24, 0.03, 0.04), w._c("#7d5638"))
	for hz: float in [-0.25, 0.25]:   # push handles at the back
		Kit.beam(props, c + Vector3(-0.7, 0.8, hz), c + Vector3(-1.25, 1.0, hz), 0.04, wood)
	# thermos and sachet strips
	Kit.cylinder(props, c + Vector3(0.55, 1.51, -0.15), 0.08, 0.08, 0.3, w._c("#c9332c"), 8)
	Kit.cylinder(props, c + Vector3(0.55, 1.81, -0.15), 0.05, 0.05, 0.05, w._c("#e8e6e0"), 6)
	# umbrella: pole, striped canopy, paper bags and sachets hanging from its edge
	Kit.beam(props, c + Vector3(-0.45, 1.0, -0.2), c + Vector3(-0.45, 2.3, -0.2), 0.035, w._c("#d8d6cf"))
	var top := c + Vector3(-0.45, 2.35, -0.2)
	for i in 8:
		var a0 := TAU * i / 8.0
		var a1 := TAU * (i + 1) / 8.0
		var p0 := top + Vector3(cos(a0) * 0.95, -0.3, sin(a0) * 0.95)
		var p1 := top + Vector3(cos(a1) * 0.95, -0.3, sin(a1) * 0.95)
		Kit.tri(props, top + Vector3(0, 0.05, 0), p0, p1, w._c("#3e7fd0") if i % 2 == 0 else w._c("#f2efe6"), 0.0, true)
	for i in 5:
		var hp := top + Vector3(-0.6 + i * 0.3, -0.33, 0.72)
		Kit.beam(cloth, hp, hp + Vector3(0, -0.12, 0), 0.01, w._c("#efe8d8"), 0.3)
		if i % 2 == 0: Kit.box(cloth, hp + Vector3(0, -0.24, 0), Vector3(0.12, 0.17, 0.05), w._c("#b9895a"), Basis.IDENTITY, false, 0.5)
		else:
			for k in 3: Kit.box(cloth, hp + Vector3(0, -0.18 - k * 0.07, 0), Vector3(0.06, 0.06, 0.01), w._c(["#e0473b", "#3a2a20", "#f2c84b"][k]), Basis.IDENTITY, false, 0.5)
	w._shadow(c + Vector3(0.1, 0, 0), Vector2(1.6, 0.9), true)


static func _audience_seats(w, props: SurfaceTool) -> void:
	var white: Color = w._c("#e8e7e0")
	w._monobloc(props, Vector3(-4.6, 0, -12.0), 0.15, white)
	w._monobloc(props, Vector3(-3.8, 0, -11.9), -0.05, w._c("#7fa4d8"))
	w._monobloc(props, Vector3(0.0, 0, -12.0), -0.2, w._c("#d36a5c"))
	var wood: Color = w._c("#9a7048")
	Kit.box(props, Vector3(-2.0, 0.43, -12.4), Vector3(2.7, 0.06, 0.4), wood)
	for lx: float in [-3.2, -0.8]:
		Kit.box(props, Vector3(lx, 0.2, -12.4), Vector3(0.08, 0.4, 0.34), wood.darkened(0.15))
	w._shadow(Vector3(-2.0, 0, -12.4), Vector2(2.9, 0.6), true)


static func _side_pieces(w, props: SurfaceTool) -> void:
	# beside this end's half: a water station and a queue bench for the next game
	var t := Vector3(6.15, 0, -3.6)
	Kit.box(props, t + Vector3(0, 0.74, 0), Vector3(0.6, 0.05, 1.0), w._c("#9a7048"))
	for lz: float in [-0.42, 0.42]:
		for lx: float in [-0.25, 0.25]:
			Kit.box(props, t + Vector3(lx, 0.36, lz), Vector3(0.05, 0.72, 0.05), w._c("#7d5638"))
	for k in 2:
		Kit.cylinder(props, t + Vector3(0, 0.77, -0.25 + k * 0.4), 0.13, 0.13, 0.36, w._c("#5fa8d8"), 8)
		Kit.cylinder(props, t + Vector3(0, 1.13, -0.25 + k * 0.4), 0.05, 0.05, 0.05, w._c("#3e7fd0"), 6)
	for k in 4: Kit.cylinder(props, t + Vector3(0.18, 0.77, 0.25 + k * 0.05), 0.03, 0.035, 0.08, w._c("#f2efe6"), 5)
	w._shadow(t, Vector2(0.8, 1.1), true)
	var wood: Color = w._c("#9a7048")
	Kit.box(props, Vector3(-6.55, 0.43, -6.2), Vector3(0.4, 0.06, 2.2), wood)
	for lz: float in [-7.1, -5.3]:
		Kit.box(props, Vector3(-6.55, 0.2, lz), Vector3(0.34, 0.4, 0.08), wood.darkened(0.15))
	Kit.box(props, Vector3(-6.55, 0.6, -6.2), Vector3(0.3, 0.28, 0.4), w._c("#7a3b2e"))
	w._shadow(Vector3(-6.55, 0, -6.2), Vector2(0.6, 2.3), true)


static func _jeepney(w) -> void:
	# Built facing -x (the way it drives) in its own mesh so it can move along the lane.
	var st := Kit.begin()
	var body: Color = w._c("#e8e4da")
	var stripe := [w._c("#d23b34"), w._c("#3e7fd0"), w._c("#f2c84b")]
	Kit.box(st, Vector3(0.3, 1.15, 0), Vector3(3.6, 1.3, 1.8), body)
	Kit.box(st, Vector3(-1.95, 0.85, 0), Vector3(0.9, 0.75, 1.6), w._c("#c9ccd0"))                 # hood
	Kit.box(st, Vector3(-2.42, 0.8, 0), Vector3(0.06, 0.55, 1.4), w._c("#9ea3a8"))                 # grille
	for k in 3: Kit.box(st, Vector3(-2.45, 0.6 + k * 0.17, 0), Vector3(0.02, 0.04, 1.3), w._c("#e8eaec"))
	Kit.box(st, Vector3(-2.5, 1.35, 0), Vector3(0.1, 0.25, 0.08), w._c("#c9ccd0"))                 # horse ornament
	Kit.box(st, Vector3(-1.55, 1.55, 0), Vector3(0.06, 0.5, 1.5), w._c("#5a8fb8"))                 # windshield
	for i in 3:
		Kit.box(st, Vector3(0.3, 0.75 + i * 0.12, 0.905), Vector3(3.6, 0.07, 0.01), stripe[i])
		Kit.box(st, Vector3(0.3, 0.75 + i * 0.12, -0.905), Vector3(3.6, 0.07, 0.01), stripe[i])
	var wx := -1.1
	while wx < 1.9:
		Kit.box(st, Vector3(wx, 1.45, 0.905), Vector3(0.48, 0.42, 0.01), w._c("#3a3640"))
		wx += 0.55
	Kit.box(st, Vector3(0.3, 1.86, 0), Vector3(3.8, 0.1, 1.9), w._c("#d23b34"))                   # roof
	Kit.box(st, Vector3(-1.3, 2.05, 0), Vector3(0.12, 0.3, 1.4), w._c("#f2efe6"))                 # route sign
	for wpos in [Vector3(-1.75, 0.35, 0.85), Vector3(-1.75, 0.35, -0.85), Vector3(1.3, 0.35, 0.85), Vector3(1.3, 0.35, -0.85)]:
		Kit.box(st, wpos, Vector3(0.7, 0.7, 0.2), w._c("#26232a"), Basis(Vector3.BACK, PI * 0.25))
		Kit.box(st, wpos, Vector3(0.7, 0.7, 0.2), w._c("#26232a"))
		Kit.box(st, wpos + Vector3(0, 0, 0.11 * signf(wpos.z)), Vector3(0.25, 0.25, 0.02), w._c("#c9ccd0"))
	var mi := MeshInstance3D.new()
	mi.name = "Jeepney"
	mi.mesh = st.commit()
	mi.material_override = w._toon_n
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(40.0, 0.0, JEEP_LANE)
	mi.visible = false
	w._near.add_child(mi)
	w._near_state.jeep = mi
	w._near_state.jeep_state = "away"
	w._near_state.jeep_next = 12.0
	w._near_state.jeep_x = 40.0
	w._near_state.jeep_speed = 0.0


# ------------------------------------------------------------------ people

static func build_people(w) -> void:
	var st: Dictionary = w._near_state
	# the vendor behind the cart
	var v: Dictionary = w._person(VENDOR, 0.0, false, false)
	v.role = "vendor"
	v.trait = "chatty"
	v.vstate = "idle"
	v.until = 0.0
	v.next_call = 4.0
	st.vendor = v
	st.queue = [null, null, null]
	st.served_at = 0.0
	# audience
	w._person(Vector3(-4.6, 0, -12.0), 0.15, true)
	w._person(Vector3(-3.8, 0, -11.9), -0.05, true)
	w._person(Vector3(0.0, 0, -12.0), -0.2, true)
	for bx: float in [-2.9, -2.0, -1.1]:
		w._person(Vector3(bx, 0, -12.45), 0.0, true)
	for sx: float in [-4.2, -1.2, 0.6]:
		w._person(Vector3(sx, 0, -13.4), w._rng.randf_range(-0.2, 0.2), false)
	# lolos at dama and a kibitzer
	for side: float in [-1.0, 1.0]:
		var l: Dictionary = w._person(Vector3(-6.6 + side * 0.55, 0, -12.6), -side * PI * 0.5, true, false)
		l.role = "dama"
		l.seat_h = 0.36
		l.posture = "wide"
		l.trait = "calm"
		l.dama_next = w._rng.randf_range(2.0, 6.0)
	var kib: Dictionary = w._person(Vector3(-6.6, 0, -13.25), 0.0, false, false)
	kib.role = "dama"
	kib.kibitzer = true
	kib.posture = "contrapposto"
	# commuters at the waiting shed: on their phones, not watching
	for cx: float in [-3.9, -2.6]:
		var c: Dictionary = w._person(Vector3(cx, 0, -18.25), 0.0, true, false)
		c.seat_h = 0.46
		c.trait = "nonchalant"
		c.posture = "figure_four" if cx < -3.0 else "crossed"
		c.role = "crowd"
		c.base_seated = true
		w._crowd.append(c)
	var stand: Dictionary = w._person(Vector3(-1.6, 0, -17.7), 0.3, false, false)
	stand.trait = "nonchalant"
	stand.posture = "cross_ankles"
	w._crowd.append(stand)
	# kid at the poso, mechanic at the bike
	var kid: Dictionary = w._person(Vector3(-0.95, 0, -18.1), PI * 0.5, false, false, 0.72)
	kid.role = "pump"
	var mech: Dictionary = w._person(Vector3(7.95, 0, -17.0), PI, true, false)
	mech.role = "mechanic"
	mech.seat_h = 0.2
	mech.posture = "tucked"
	# next-game queue on this end's side bench
	for qz: float in [-6.9, -5.5]:
		var q: Dictionary = w._person(Vector3(-6.55, 0, qz), PI * 0.5, true)
		q.trait = "fan"
		w._pick_posture(q)
		q.prop = "paddle"
		q.role = "queue"
	# passers-by on this end's lane
	for k in 6:
		var p: Dictionary = w._walker("near")
		p.end = 1


static func build_animals(w) -> Array:
	# two cats on the wall (one curled, one sitting) and the rooster in its cage
	var out := []
	for cat in [[Vector3(1.3, 1.36, -19.4), "#d98a3e"], [Vector3(3.8, 1.36, -19.4), "#3a3238"]]:
		out.append({"kind": "cat", "pos": w._end_pos(cat[0], 1), "c": w._c(cat[1]), "yaw": PI + 0.3, "base": 0, "step": 0})
	return out


# ------------------------------------------------------------------ runtime

## Pandesal end runtime (only while the camera faces this end): queue, jeepney, cats.
static func step(w, dt: float) -> void:
	var st: Dictionary = w._near_state
	_step_queue(w, st)
	_step_jeep(w, st, dt)


static func _local(w, p: Dictionary) -> Vector3:
	return w._end_pos(Vector3(p.pos), 1)


static func step_person(w, p: Dictionary) -> void:
	var t: float = w._t
	p.walk = -1.0
	p.bounce = 0.0
	p.sway = 0.0
	p.lean = 0.0
	p.head_yaw = 0.0
	p.head_pitch = 0.0
	p.prop = ""
	match str(p.role):
		"vendor": _step_vendor(w, p)
		"dama":
			if p.get("kibitzer", false):
				p.arm_l = "hands_hips"
				p.arm_r = "hands_hips"
				p.lean = 0.3
				p.head_pitch = 0.5
				p.posture = "contrapposto"
			else:
				p.arm_l = "arm_on_knee"
				p.arm_r = "arm_on_knee"
				p.lean = 0.3
				p.head_pitch = 0.45
				if t > float(p.dama_next):
					p.dama_move_until = t + 0.7
					p.dama_next = t + w._rng.randf_range(4.0, 9.0)
				if t < float(p.get("dama_move_until", 0.0)):
					p.arm_r = "reach_down"
					p.lean = 0.4
		"pump":
			var up := int(t * 2.5) % 2 == 0
			p.arm_l = "reach_up" if up else "hold_ball"
			p.arm_r = p.arm_l
			p.lean = 0.1 if up else 0.25
		"mechanic":
			var beat := int(t * 3.0) % 2
			p.arm_l = "reach_down"
			p.arm_r = "reach_down" if beat == 0 else "lean_in"
			p.lean = 0.5
			p.head_pitch = 0.4


static func _step_vendor(w, v: Dictionary) -> void:
	var t: float = w._t
	var st: Dictionary = w._near_state
	v.arm_l = "counter"
	v.arm_r = "counter"
	v.lean = 0.15
	match str(v.vstate):
		"idle":
			if st.queue[0] != null and str(st.queue[0].state) == "queue" and t > float(st.queue[0].get("queued_at", 0.0)) + 1.2:
				v.vstate = "open"
				v.until = t + 1.1
			elif not w._playing and t > float(v.next_call):
				v.vstate = "call"
				v.until = t + 2.2
		"call":
			# "Pandesaaal!": a hand cupped to the mouth, the other squeezes the bulb horn
			v.arm_r = "mouth"
			v.arm_l = "fist_mid" if int(t * 4.0) % 2 == 0 else "hold_ball"
			v.lean = -0.08
			if t > float(v.until):
				v.vstate = "idle"
				v.next_call = t + w._rng.randf_range(9.0, 18.0)
		"open":
			v.arm_l = "reach_down"
			v.arm_r = "reach_down"
			v.lean = 0.35
			v.prop = "steam"
			if t > float(v.until):
				v.vstate = "bag"
				v.until = t + 0.6
		"bag":
			v.arm_l = "clap_shut"
			v.arm_r = "clap_shut"
			v.prop = "steam"
			if t > float(v.until):
				v.vstate = "hand"
				v.until = t + 0.8
		"hand":
			v.arm_r = "point"
			v.yaw = PI - 0.9          # turn toward the queue (the end is turned half a turn)
			if t > float(v.until):
				var buyer = st.queue[0]
				if buyer != null:
					buyer.bread = true
					buyer.state = "served"
				v.vstate = "change"
				v.until = t + 1.0
		"change":
			v.arm_l = "counter"
			v.arm_r = "counter"
			v.head_pitch = 0.35
			if t > float(v.until):
				v.vstate = "idle"
				v.yaw = PI


static func _step_queue(w, st: Dictionary) -> void:
	var q: Array = st.queue
	# the front buyer leaves once served; everyone behind steps up
	if q[0] != null and str(q[0].state) == "served":
		var done: Dictionary = q[0]
		q[0] = null
		leave(w, done)
	for i in range(1, q.size()):
		if q[i - 1] == null and q[i] != null and str(q[i].state) == "queue":
			var p: Dictionary = q[i]
			q[i - 1] = p
			q[i] = null
			p.slot = i - 1
			p.state = "walk"
			p.dest = "pandesal"
			p.path = [w._end_pos(QUEUE[i - 1], 1)]


static func _step_jeep(w, st: Dictionary, dt: float) -> void:
	var jeep: MeshInstance3D = st.jeep
	var t: float = w._t
	match str(st.jeep_state):
		"away":
			jeep.visible = false
			if t > float(st.jeep_next):
				st.jeep_state = "in"
				st.jeep_x = 38.0
				st.jeep_speed = 8.0
		"in":
			jeep.visible = true
			var to_stop: float = float(st.jeep_x) - JEEP_STOP
			st.jeep_speed = clampf(to_stop * 0.9, 1.0, 8.0)
			st.jeep_x = float(st.jeep_x) - float(st.jeep_speed) * dt
			if to_stop < 0.1:
				st.jeep_state = "stop"
				st.jeep_until = t + 4.0
		"stop":
			if t > float(st.jeep_until):
				st.jeep_state = "out"
				st.jeep_speed = 1.0
		"out":
			st.jeep_speed = minf(float(st.jeep_speed) + 3.0 * dt, 8.0)
			st.jeep_x = float(st.jeep_x) - float(st.jeep_speed) * dt
			if float(st.jeep_x) < -38.0:
				st.jeep_state = "away"
				st.jeep_next = t + w._rng.randf_range(25.0, 45.0)
	# step the position in whole 5 cm moves so the pixels jump cleanly
	jeep.position = Vector3(round(float(st.jeep_x) * 20.0) / 20.0, 0.0, JEEP_LANE)


## Passers-by trips at this end (end-local, converted with `w._end_pos`).
static func start_trip(w, p: Dictionary) -> void:
	var side := -1.0 if w._rng.randf() < 0.5 else 1.0
	p.visible = true
	p.state = "walk"
	p.cells = {}
	p.bread = false
	p.speed = w._rng.randf_range(1.0, 1.4) if p.trait != "busy" else w._rng.randf_range(1.6, 1.8)
	var start := Vector3(side * 17.0, 0, LANE)
	p.pos = w._end_pos(start, 1)
	var slot := -1
	if w._rng.randf() < 0.6 and p.trait != "busy":
		for i in QUEUE.size():
			if w._near_state.queue[i] == null:
				slot = i
				break
	if slot >= 0:
		w._near_state.queue[slot] = p
		p.slot = slot
		p.dest = "pandesal"
		var spot: Vector3 = QUEUE[slot]
		p.path = [w._end_pos(Vector3(spot.x, 0, LANE), 1), w._end_pos(spot, 1)]
	else:
		p.dest = "exit"
		p.path = [w._end_pos(Vector3(-side * 17.0, 0, LANE), 1)]


static func arrive(w, p: Dictionary) -> void:
	match str(p.dest):
		"pandesal":
			p.state = "queue"
			p.queued_at = w._t
			p.yaw = PI + PI * 0.5      # face the cart (+x at this end)
		_:
			p.state = "gone"
			p.visible = false
			p.respawn = w._t + w._rng.randf_range(2.0, 8.0)


static func leave(w, p: Dictionary) -> void:
	var side := -1.0 if w._rng.randf() < 0.5 else 1.0
	var here := _local(w, p)
	p.state = "walk"
	p.dest = "exit"
	p.path = [w._end_pos(Vector3(here.x, 0, LANE), 1), w._end_pos(Vector3(side * 17.0, 0, LANE), 1)]
