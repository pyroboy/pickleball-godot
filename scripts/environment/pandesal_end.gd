extends RefCounted
## The pandesal end of the barangay court (visual only): the end the camera faces after a
## doubles change of ends. Authored like the hall end ("far" = -z, screen-left = -x) and
## placed by barangay_world.gd in a child node turned half a turn; people and shadows go
## through `w._end_pos`.
##
## Highlight: a "rolling" malunggay pandesal cart, a bright green steel cabinet sidecar on
## one small wheel, pushed by the vendor (wing doors with frosted panels, a glass display,
## stainless warmer drawers, a flat canopy with the signboard and a jingle speaker). It
## drives in along the back lane, stops, the vendor gets off and opens the doors, a queue
## forms, rolls come out of the warmer in a puff of steam, buyers walk off eating; then it
## closes up and drives away, and comes back later (taking turns with the jeepney). Around it: a two-storey panaderya, a waiting shed with commuters and a
## jeepney that stops there, a carinderia with a cook and diners at a long table, a
## vulcanizing shop with a mechanic,
## a gray concrete electric post plastered with blue and red septic-tank stickers, a poso
## with a kid pumping water, lolos playing dama, cats on a hollow-block wall, a rooster in a
## cage, and an audience with the same personalities as the hall end.

const Kit := preload("res://scripts/environment/env_mesh_kit.gd")
const Fig := preload("res://scripts/environment/env_figures.gd")
const People := preload("res://scripts/environment/env_people.gd")

const STOP_X := 4.2              # where the rolling cart parks on the back lane
const CART := Vector3(4.2, 0, -22.4)
const VENDOR := Vector3(2.7, 0, -21.75)
const QUEUE := [Vector3(4.2, 0, -21.45), Vector3(3.55, 0, -21.5), Vector3(2.9, 0, -21.55)]
const LANE := -14.45         # this end's walking lane (between the curb sitters and the standing group)
const JEEP_LANE := -22.4
const JEEP_STOP := -2.9      # in front of the waiting shed
const POST := Vector3(1.4, 0, -15.0)


# ------------------------------------------------------------------ geometry

static func build_geometry(w, bld: SurfaceTool, props: SurfaceTool, cloth: SurfaceTool) -> void:
	_panaderya(w, bld)
	_waiting_shed(w, bld)
	_carinderia(w, bld, props)
	_vulcanizing(w, bld)
	_wall_and_cage(w, bld, props)
	_sticker_post(w, props, cloth)
	_poso(w, props)
	_dama_table(w, props)
	_audience_seats(w, props)
	_side_pieces(w, props)
	w._build_background(bld, -8.0)
	_jeepney(w)
	_rolling_cart(w)


static func _panaderya(w, st: SurfaceTool) -> void:
	# Two-storey bakery in the corner: open shop front with a glass counter and shelves of
	# bread, striped awning, the sign; peach upper floor with windows and a balcony.
	var x0 := -12.6
	var x1 := -6.8
	var zf := -24.0
	var zb := -29.0
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
	var zf := -23.4
	var zb := -24.6
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


static func _carinderia(w, st: SurfaceTool, props: SurfaceTool) -> void:
	# A wide, low neighbourhood eatery: open front with a counter of big pots and a glass
	# food display under a GI awning, the sign, a menu board, a water dispenser; a long
	# table with benches out front where diners eat.
	var x0 := -0.6
	var x1 := 5.0
	var zf := -27.0
	var zb := -31.0
	var cx := (x0 + x1) * 0.5
	var wall: Color = w._c("#e8d9a8")
	Kit.box(st, Vector3(cx, 1.5, (zf + zb) * 0.5), Vector3(x1 - x0, 3.0, zf - zb), wall)
	Kit.box(st, Vector3(cx, 0.35, zf + 0.012), Vector3(x1 - x0, 0.7, 0.02), w._c("#c9a46a"))
	Kit.box(st, Vector3(cx - 0.2, 1.45, zf + 0.01), Vector3(4.4, 2.1, 0.04), w._c("#3a3238"))      # open front
	Kit.box(st, Vector3(cx - 0.2, 0.5, zf + 0.3), Vector3(4.2, 1.0, 0.55), w._c("#b98a5a"))        # counter
	Kit.box(st, Vector3(cx - 0.2, 1.02, zf + 0.3), Vector3(4.3, 0.05, 0.62), w._c("#e6e2d6"))
	for k in 4:   # big pots with lids
		var pp := Vector3(cx - 1.8 + k * 0.6, 1.05, zf + 0.3)
		Kit.cylinder(st, pp, 0.2, 0.2, 0.3, w._c("#c4c9cc"), 8)
		Kit.cylinder(st, pp + Vector3(0, 0.3, 0), 0.21, 0.08, 0.06, w._c("#a9aeb2"), 8)
		Kit.box(st, pp + Vector3(0, 0.38, 0), Vector3(0.06, 0.04, 0.06), w._c("#26232a"))
	Kit.box(st, Vector3(cx + 1.15, 1.25, zf + 0.3), Vector3(1.1, 0.42, 0.5), w._c("#b9dbe6"))      # glass display
	for k in 4: Kit.box(st, Vector3(cx + 0.75 + k * 0.27, 1.12, zf + 0.3), Vector3(0.2, 0.08, 0.3), w._c(["#b5603e", "#e0b06a", "#7a4f3a", "#5f9a45"][k]))
	Kit.box(st, Vector3(x1 - 0.35, 1.0, zf + 0.25), Vector3(0.35, 0.9, 0.35), w._c("#e8e6e0"))     # water dispenser
	Kit.cylinder(st, Vector3(x1 - 0.35, 1.45, zf + 0.25), 0.14, 0.14, 0.4, w._c("#5fa8d8"), 8)
	Kit.box(st, Vector3(x0 + 0.35, 1.6, zf + 0.03), Vector3(0.5, 0.7, 0.04), w._c("#2f4a3a"))      # menu board
	for k in 5: Kit.box(st, Vector3(x0 + 0.33, 1.84 - k * 0.11, zf + 0.06), Vector3(0.36, 0.025, 0.01), w._c("#e6e2d6"))
	# awning out over the front, the sign on its fascia
	w._gi_roof(st, x0 - 0.3, x1 + 0.3, zf + 1.3, zf, 2.55, 2.95, true)
	Kit.box(st, Vector3(cx, 2.62, zf + 1.32), Vector3(x1 - x0 + 0.6, 0.18, 0.05), w._c("#d23b34"))
	Kit.box(st, Vector3(cx, 3.25, zf + 0.06), Vector3(3.4, 0.5, 0.06), w._c("#f2efe6"))
	w._label("CARINDERIA", Vector3(cx, 3.25, zf + 0.1), 0.36, Color(0.82, 0.18, 0.14))
	w._gi_roof(st, x0 - 0.3, x1 + 0.3, zf + 0.3, zb - 0.3, 3.55, 3.0, true)
	w._shade_strip(st, x0, x1, zf + 0.02, 2.55, 0.35, wall)
	w._shadow(Vector3(cx + 0.6, 0, zf - 0.4), Vector2(x1 - x0 + 1.0, 1.4), true)
	w._shadow(Vector3(x1 + 0.9, 0, (zf + zb) * 0.5), Vector2(1.8, zf - zb), true)
	# long table with benches, left of where the pandesal cart parks
	var t := Vector3(1.9, 0, -25.9)
	Kit.box(props, t + Vector3(0, 0.74, 0), Vector3(1.9, 0.05, 0.7), w._c("#9a7048"))
	Kit.box(props, t + Vector3(0, 0.765, 0), Vector3(1.8, 0.01, 0.6), w._c("#e86f6f"))            # oilcloth
	for lx: float in [-0.85, 0.85]:
		for lz: float in [-0.28, 0.28]:
			Kit.box(props, t + Vector3(lx, 0.37, lz), Vector3(0.05, 0.74, 0.05), w._c("#7d5638"))
	for bz: float in [-0.55, 0.55]:
		Kit.box(props, t + Vector3(0, 0.42, bz), Vector3(1.9, 0.05, 0.28), w._c("#9a7048"))
		for lx: float in [-0.85, 0.85]: Kit.box(props, t + Vector3(lx, 0.2, bz), Vector3(0.05, 0.4, 0.24), w._c("#7d5638"))
	for k in 3:   # plates and cups
		Kit.cylinder(props, t + Vector3(-0.6 + k * 0.6, 0.77, -0.15), 0.12, 0.12, 0.02, w._c("#f2efe6"), 8)
		Kit.cylinder(props, t + Vector3(-0.45 + k * 0.6, 0.77, 0.12), 0.04, 0.04, 0.1, w._c("#5fa8d8"), 6)
	w._shadow(t, Vector2(2.1, 1.5), true)


static func _vulcanizing(w, st: SurfaceTool) -> void:
	var x0 := 5.0
	var x1 := 9.2
	var zf := -24.5
	var zb := -28.0
	var cx := (x0 + x1) * 0.5
	Kit.box(st, Vector3(cx, 1.5, (zf + zb) * 0.5), Vector3(x1 - x0, 3.0, zf - zb), w._c("#9fb8a0"))
	Kit.box(st, Vector3(cx - 0.3, 1.15, zf + 0.01), Vector3(2.8, 2.3, 0.04), w._c("#2f2b30"))     # open bay
	Kit.box(st, Vector3(cx, 2.75, zf + 0.06), Vector3(3.8, 0.5, 0.06), w._c("#f2efe6"))
	w._label("VULCANIZING", Vector3(cx, 2.75, zf + 0.1), 0.3, Color(0.82, 0.16, 0.14))
	w._gi_roof(st, x0 - 0.25, x1 + 0.25, zf + 0.8, zb - 0.3, 3.05, 3.4, true)
	# tyre stacks, an air compressor, a hanging tyre sign
	for t in [[x0 + 0.1, -23.8, 5], [x1 - 0.2, -23.9, 4], [x1 - 0.75, -23.7, 3]]:
		for k in int(t[2]):
			Kit.cylinder(st, Vector3(t[0], k * 0.2, t[1]), 0.32, 0.32, 0.19, w._c("#26232a"), 8)
			Kit.cylinder(st, Vector3(t[0], k * 0.2 + 0.19, t[1]), 0.14, 0.14, 0.01, w._c("#4a4650"), 6)
	Kit.box(st, Vector3(6.3, 0.35, -23.9), Vector3(0.9, 0.42, 0.42), w._c("#c9332c"))
	Kit.box(st, Vector3(6.3, 0.7, -23.9), Vector3(0.3, 0.28, 0.3), w._c("#3a3a40"))
	for wx: float in [5.95, 6.65]: Kit.box(st, Vector3(wx, 0.07, -23.9), Vector3(0.12, 0.14, 0.12), w._c("#26232a"))
	# a bicycle being fixed, the mechanic squats beside it (a person, see build_people)
	var bike := Vector3(7.95, 0, -23.55)
	for bz: float in [-0.45, 0.45]:
		Kit.box(st, bike + Vector3(bz, 0.33, 0), Vector3(0.6, 0.6, 0.06), w._c("#26232a"), Basis(Vector3.FORWARD, PI * 0.25))
		Kit.box(st, bike + Vector3(bz, 0.33, 0), Vector3(0.6, 0.6, 0.06), w._c("#26232a"))
	Kit.beam(st, bike + Vector3(-0.45, 0.33, 0), bike + Vector3(0.0, 0.65, 0), 0.04, w._c("#3e7fd0"))
	Kit.beam(st, bike + Vector3(0.45, 0.33, 0), bike + Vector3(0.0, 0.65, 0), 0.04, w._c("#3e7fd0"))
	Kit.beam(st, bike + Vector3(0.0, 0.65, 0), bike + Vector3(0.35, 0.85, 0), 0.04, w._c("#3e7fd0"))
	w._shadow(Vector3(cx + 0.5, 0, zf - 0.3), Vector2(x1 - x0 + 0.8, 1.2), true)
	w._shadow(bike, Vector2(1.3, 0.4))


static func _wall_and_cage(w, st: SurfaceTool, props: SurfaceTool) -> void:
	# a short, low hollow-block wall (cats sit on it) and a rooster cage at its end
	var y := 0.1
	while y < 0.8:
		var off := 0.0 if int(y * 5.0) % 2 == 0 else 0.2
		var x := -1.7 + off
		while x < 0.2:
			Kit.box(st, Vector3(x + 0.19, y, -25.4), Vector3(0.38, 0.19, 0.2), w._c("#9c988f"))
			x += 0.4
		y += 0.2
	Kit.box(st, Vector3(-0.75, 0.83, -25.4), Vector3(2.0, 0.06, 0.24), w._c("#8f8b84"))
	var cage := Vector3(0.55, 0, -25.0)
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
	var at := Vector3(-0.45, 0, -24.1)
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


static func _audience_seats(w, props: SurfaceTool) -> void:
	# A looser crowd than the hall end's rows: people on the painted curb, on upside-down
	# plastic crates, perched on a parked motorbike, one on a chair under a beach umbrella.
	for cr in [[Vector3(-5.2, 0, -12.9), 0.4, "#f2c84b"], [Vector3(-4.55, 0, -13.15), -0.3, "#e0473b"]]:
		var b := Basis(Vector3.UP, cr[1])
		var at: Vector3 = cr[0]
		Kit.box(props, at + Vector3(0, 0.17, 0), Vector3(0.46, 0.34, 0.34), w._c(cr[2]), b)
		for k in 3: Kit.box(props, at + b * Vector3(-0.15 + k * 0.15, 0.17, 0.172), Vector3(0.05, 0.22, 0.01), w._c(cr[2]).darkened(0.3), b)
		w._shadow(at, Vector2(0.6, 0.45), true)
	# parked motorbike, side-on (two teens sit on it)
	var mb := Vector3(-2.55, 0, -13.25)
	for wx: float in [-0.6, 0.6]:
		Kit.box(props, mb + Vector3(wx, 0.3, 0), Vector3(0.56, 0.56, 0.09), w._c("#26232a"), Basis(Vector3.BACK, PI * 0.25))
		Kit.box(props, mb + Vector3(wx, 0.3, 0), Vector3(0.56, 0.56, 0.09), w._c("#26232a"))
		Kit.box(props, mb + Vector3(wx, 0.3, 0.02), Vector3(0.18, 0.18, 0.1), w._c("#b9bcc0"))
	Kit.box(props, mb + Vector3(0.0, 0.52, 0), Vector3(0.9, 0.22, 0.22), w._c("#3e7fd0"))
	Kit.box(props, mb + Vector3(0.15, 0.7, 0), Vector3(0.8, 0.1, 0.26), w._c("#26232a"))
	Kit.box(props, mb + Vector3(-0.55, 0.72, 0), Vector3(0.2, 0.42, 0.26), w._c("#3e7fd0"))
	Kit.box(props, mb + Vector3(-0.62, 1.0, 0), Vector3(0.05, 0.04, 0.62), w._c("#26232a"))
	w._shadow(mb, Vector2(1.7, 0.5))
	# a chair under a striped beach umbrella
	w._monobloc(props, Vector3(0.3, 0, -12.65), -0.2, w._c("#e8e7e0"))
	var top := Vector3(0.75, 2.1, -12.95)
	Kit.beam(props, Vector3(0.75, 0, -12.95), top, 0.035, w._c("#d8d6cf"))
	for i in 8:
		var a0 := TAU * i / 8.0
		var a1 := TAU * (i + 1) / 8.0
		Kit.tri(props, top + Vector3(0, 0.1, 0), top + Vector3(cos(a0) * 1.0, -0.25, sin(a0) * 1.0), top + Vector3(cos(a1) * 1.0, -0.25, sin(a1) * 1.0), w._c("#f29ac0") if i % 2 == 0 else w._c("#f2efe6"), 0.0, true)
	w._shadow(Vector3(0.95, 0, -12.75), Vector2(1.9, 1.2))


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


static func _rolling_cart(w) -> void:
	# Cart-local: cabinet centred on x = 0, its front (doors, display) facing +z, the
	# push handle on its +x side; it is pushed toward -x.
	var green: Color = w._c("#46c83a")
	var green_dk: Color = w._c("#34a32c")
	var steel: Color = w._c("#c4c9cc")
	var frost: Color = w._c("#cfdade")
	var alu: Color = w._c("#dde1e3")
	var tyre: Color = w._c("#26232a")
	var st := Kit.begin()
	var black: Color = w._c("#2a2730")
	# --- wheel: a deep tyre with tread, a grey rim with a yellow stripe, and a fender
	var hub := Vector3(0.0, 0.28, 0.0)
	for k in 2:
		Kit.box(st, hub, Vector3(0.56, 0.56, 0.24), tyre, Basis(Vector3.BACK, PI * 0.25 * k))
	Kit.box(st, hub, Vector3(0.4, 0.4, 0.26), black, Basis(Vector3.BACK, PI * 0.125))
	for face: float in [1.0, -1.0]:
		Kit.box(st, hub + Vector3(0, 0, 0.13 * face), Vector3(0.3, 0.3, 0.02), w._c("#8a8f94"), Basis(Vector3.BACK, PI * 0.25))
		Kit.box(st, hub + Vector3(0, 0, 0.135 * face), Vector3(0.12, 0.12, 0.02), w._c("#3a3640"))
		Kit.box(st, hub + Vector3(0.11, -0.05, 0.14 * face), Vector3(0.07, 0.2, 0.015), w._c("#f2d23a"), Basis(Vector3.BACK, 0.55))
	Kit.box(st, Vector3(0, 0.62, 0), Vector3(0.68, 0.06, 0.34), green_dk)                    # fender
	for fx: float in [-0.32, 0.32]:
		Kit.box(st, Vector3(fx, 0.5, 0), Vector3(0.05, 0.22, 0.34), green_dk)
	# --- chassis: a welded tube frame with a stand leg at each end
	Kit.box(st, Vector3(0, 0.5, 0.39), Vector3(1.26, 0.08, 0.08), green_dk)
	Kit.box(st, Vector3(0, 0.5, -0.39), Vector3(1.26, 0.08, 0.08), green_dk)
	for fx: float in [-0.59, 0.59]:
		Kit.box(st, Vector3(fx, 0.5, 0), Vector3(0.08, 0.08, 0.86), green_dk)
		Kit.box(st, Vector3(fx, 0.24, 0.3), Vector3(0.06, 0.48, 0.06), green_dk)              # stand legs
		Kit.box(st, Vector3(fx, 0.02, 0.3), Vector3(0.14, 0.04, 0.14), black)
	# --- cabinet: corner posts, top and bottom rails, panels set in between
	var y0 := 0.54
	var y1 := 1.86
	var cy := (y0 + y1) * 0.5
	var h := y1 - y0
	Kit.box(st, Vector3(0, cy, 0), Vector3(1.14, h, 0.8), green)                               # panels (set in)
	for px: float in [-0.585, 0.585]:
		for pz: float in [-0.415, 0.415]:
			Kit.box(st, Vector3(px, cy, pz), Vector3(0.08, h, 0.08), green_dk)                 # corner posts
	for ry: float in [y0 + 0.03, y1 - 0.03]:
		for pz: float in [-0.415, 0.415]:
			Kit.box(st, Vector3(0, ry, pz), Vector3(1.2, 0.06, 0.07), green_dk)
		for px: float in [-0.585, 0.585]:
			Kit.box(st, Vector3(px, ry, 0), Vector3(0.07, 0.06, 0.86), green_dk)
	# left side: a small window; right side: a louvred vent (the oven breathes there)
	Kit.box(st, Vector3(-0.575, 1.42, 0), Vector3(0.03, 0.42, 0.5), alu)
	Kit.box(st, Vector3(-0.59, 1.42, 0), Vector3(0.02, 0.34, 0.42), frost)
	for k in 6: Kit.box(st, Vector3(0.59, 0.85 + k * 0.08, 0.05), Vector3(0.04, 0.03, 0.46), green_dk)
	# --- front centre: a framed glass display that sticks out, stainless warmer drawers
	Kit.box(st, Vector3(0, 1.6, 0.44), Vector3(0.58, 0.4, 0.1), alu)
	for gx: float in [-0.135, 0.135]:
		Kit.box(st, Vector3(gx, 1.6, 0.495), Vector3(0.23, 0.32, 0.02), frost)
	Kit.box(st, Vector3(0, 1.6, 0.5), Vector3(0.03, 0.36, 0.03), alu)
	Kit.box(st, Vector3(0, 1.1, 0.43), Vector3(0.52, 0.42, 0.08), steel)
	Kit.box(st, Vector3(0, 0.77, 0.43), Vector3(0.52, 0.18, 0.08), steel)
	for hy: float in [1.22, 0.79]:   # stand-off handles
		Kit.box(st, Vector3(0, hy, 0.5), Vector3(0.3, 0.035, 0.035), green_dk)
		for hx: float in [-0.14, 0.14]: Kit.box(st, Vector3(hx, hy, 0.48), Vector3(0.03, 0.03, 0.05), green_dk)
	Kit.box(st, Vector3(0.21, 1.38, 0.43), Vector3(0.07, 0.09, 0.03), w._c("#3e7fd0"))
	Kit.box(st, Vector3(0.21, 1.27, 0.43), Vector3(0.07, 0.06, 0.03), w._c("#f2d23a"))
	# --- canopy: a thick roof with a fascia, on struts from the cabinet's front corners
	Kit.box(st, Vector3(0, 2.08, 0.2), Vector3(1.94, 0.08, 1.5), green)
	Kit.box(st, Vector3(0, 2.02, 0.95), Vector3(1.96, 0.14, 0.05), green_dk)
	for fx: float in [-0.97, 0.97]: Kit.box(st, Vector3(fx, 2.02, 0.2), Vector3(0.05, 0.14, 1.52), green_dk)
	for fx: float in [-0.55, 0.55]:
		Kit.beam(st, Vector3(fx, 1.86, 0.4), Vector3(fx * 1.5, 2.0, 0.9), 0.04, green_dk)
	Kit.box(st, Vector3(0, 1.98, 0.2), Vector3(1.94, 0.02, 1.5), green.darkened(0.35))          # canopy underside in shade
	# --- signboard: a framed box on two posts
	for sx: float in [-0.7, 0.7]: Kit.box(st, Vector3(sx, 2.17, 0.72), Vector3(0.05, 0.12, 0.05), green_dk)
	Kit.box(st, Vector3(0, 2.4, 0.72), Vector3(1.8, 0.4, 0.1), green_dk)
	Kit.box(st, Vector3(0, 2.4, 0.74), Vector3(1.72, 0.32, 0.08), w._c("#f4f1e8"))
	for sx: float in [-0.76, 0.76]:   # malunggay leaves and a roll painted at each end
		for k in 4: Kit.box(st, Vector3(sx + (k % 2) * 0.05 * signf(sx), 2.33 + k * 0.05, 0.785), Vector3(0.05, 0.035, 0.01), w._c("#4f9a3a"))
		Kit.box(st, Vector3(sx - 0.07 * signf(sx), 2.31, 0.785), Vector3(0.08, 0.05, 0.01), w._c("#d39b55"))
	# --- jingle speaker: a horn on a bracket at the canopy corner
	Kit.box(st, Vector3(-0.82, 2.16, 0.78), Vector3(0.1, 0.1, 0.1), w._c("#8a8f94"))
	Kit.box(st, Vector3(-0.82, 2.2, 0.86), Vector3(0.2, 0.18, 0.06), w._c("#b9bcc0"))
	Kit.box(st, Vector3(-0.82, 2.2, 0.9), Vector3(0.14, 0.12, 0.02), black)
	# --- push handle on the +x side (the vendor walks behind, pushing)
	for hz: float in [-0.3, 0.3]:
		Kit.beam(st, Vector3(0.62, 0.8, hz), Vector3(1.15, 1.02, hz), 0.05, green_dk)
	Kit.beam(st, Vector3(1.15, 1.02, -0.34), Vector3(1.15, 1.02, 0.34), 0.06, black)
	var root := Node3D.new()
	root.name = "RollingPandesal"
	root.position = Vector3(40.0, 0.0, CART.z)
	root.visible = false
	w._near.add_child(root)
	var body := MeshInstance3D.new()
	body.mesh = st.commit()
	body.material_override = w._toon_n
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var sign := Label3D.new()
	sign.text = "ROLLING MALUNGGAY PANDESAL"
	sign.font = w.PixelFont
	sign.font_size = 9
	sign.pixel_size = 0.095 / 9.0
	sign.modulate = Color(0.2, 0.62, 0.22)
	sign.shaded = false
	sign.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sign.position = Vector3(0, 2.41, 0.79)
	root.add_child(sign)
	# wing doors on hinges at the cabinet's front corners (frosted panels, aluminium frames)
	var doors := []
	for side: float in [-1.0, 1.0]:
		var dst := Kit.begin()
		var dir := -side          # closed, the door runs from its hinge toward the middle
		Kit.box(dst, Vector3(dir * 0.2, 1.2, 0.0), Vector3(0.4, 1.3, 0.05), green)
		for ry: float in [0.57, 1.2, 1.83]: Kit.box(dst, Vector3(dir * 0.2, ry, 0.0), Vector3(0.42, 0.05, 0.07), green_dk)
		for rx: float in [0.01, 0.39]: Kit.box(dst, Vector3(dir * rx, 1.2, 0.0), Vector3(0.04, 1.3, 0.07), green_dk)
		for py: float in [0.89, 1.52]:
			for face: float in [1.0, -1.0]:   # glass shows from both sides (open, the back faces the street)
				Kit.box(dst, Vector3(dir * 0.2, py, face * 0.03), Vector3(0.3, 0.54, 0.012), alu)
				Kit.box(dst, Vector3(dir * 0.2, py, face * 0.037), Vector3(0.25, 0.48, 0.01), frost)
		Kit.box(dst, Vector3(dir * 0.36, 1.2, 0.05), Vector3(0.025, 0.14, 0.03), steel)        # latch
		var hinge := Node3D.new()
		hinge.position = Vector3(side * 0.6, 0, 0.5)
		root.add_child(hinge)
		var door := MeshInstance3D.new()
		door.mesh = dst.commit()
		door.material_override = w._toon_n
		door.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hinge.add_child(door)
		doors.append(hinge)
	# jingle pulse: two little "sound" blocks beside the speaker
	var pulse := MeshInstance3D.new()
	var pst := Kit.begin()
	Kit.box(pst, Vector3(-0.16, 0, 0), Vector3(0.04, 0.12, 0.02), w._c("#f2efe6"))
	Kit.box(pst, Vector3(-0.26, 0, 0), Vector3(0.04, 0.2, 0.02), w._c("#f2efe6"))
	pulse.mesh = pst.commit()
	pulse.material_override = w._toon_n
	pulse.position = Vector3(-0.82, 2.2, 0.92)
	pulse.visible = false
	root.add_child(pulse)
	var nst: Dictionary = w._near_state
	nst.cart = root
	nst.cart_doors = doors
	nst.cart_pulse = pulse
	nst.cart_state = "away"
	nst.cart_next = 3.0
	nst.cart_x = 40.0
	nst.cart_speed = 0.0
	nst.cart_open = 0.0
	nst.cart_shadow = w._shadow(CART + Vector3(0.1, 0, 0), Vector2(2.1, 1.3), true)


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
	# audience: on the curb, on crates, on the motorbike, under the umbrella, and a loose
	# standing group by the sticker post (one leans on it)
	for cs in [[-4.05, 0.2, "knee_up"], [-3.15, -0.1, "wide"], [-0.95, 0.35, "tucked"]]:
		var c: Dictionary = w._person(Vector3(cs[0], 0, -14.05), cs[1], true)
		c.seat_h = 0.15
		c.posture = cs[2]
	for cr in [[Vector3(-5.2, 0, -12.95), 0.4], [Vector3(-4.55, 0, -13.2), -0.3]]:
		var c2: Dictionary = w._person(cr[0], cr[1], true)
		c2.seat_h = 0.34
	for bx: float in [-2.8, -2.25]:
		var b: Dictionary = w._person(Vector3(bx, 0, -13.2), 0.15 if bx < -2.5 else -0.2, true)
		b.seat_h = 0.72
		b.posture = "wide" if bx < -2.5 else "crossed"
	w._person(Vector3(0.3, 0, -12.65), -0.2, true)
	var leaner: Dictionary = w._person(Vector3(1.15, 0, -14.85), 0.5, false)
	leaner.posture = "cross_ankles"
	leaner.trait = "nonchalant"
	w._person(Vector3(1.95, 0, -14.95), -0.35, false)
	w._person(Vector3(-1.7, 0, -14.9), 0.15, false)
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
		var c: Dictionary = w._person(Vector3(cx, 0, -24.25), 0.0, true, false)
		c.seat_h = 0.46
		c.trait = "nonchalant"
		c.posture = "figure_four" if cx < -3.0 else "crossed"
		c.role = "crowd"
		c.base_seated = true
		w._crowd.append(c)
	var stand: Dictionary = w._person(Vector3(-1.6, 0, -23.7), 0.3, false, false)
	stand.trait = "nonchalant"
	stand.posture = "cross_ankles"
	w._crowd.append(stand)
	# the carinderia: a cook at the pots, diners at the long table
	var cook: Dictionary = w._person(Vector3(1.6, 0, -27.75), 0.0, false, false)
	cook.role = "cook"
	for d in [[Vector3(1.3, 0, -26.45), 0.0, false], [Vector3(2.4, 0, -26.45), 0.0, false], [Vector3(1.9, 0, -25.35), PI, true]]:
		var diner: Dictionary = w._person(d[0], d[1], true, false)
		diner.role = "diner"
		diner.seat_h = 0.44
		diner.posture = "normal"
		diner.eat_phase = w._rng.randf() * 3.0
	# kid at the poso, mechanic at the bike
	var kid: Dictionary = w._person(Vector3(-0.95, 0, -24.1), PI * 0.5, false, false, 0.72)
	kid.role = "pump"
	var mech: Dictionary = w._person(Vector3(7.95, 0, -23.0), PI, true, false)
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
	for cat in [[Vector3(-1.3, 0.86, -25.4), "#d98a3e"], [Vector3(-0.2, 0.86, -25.4), "#3a3238"]]:
		out.append({"kind": "cat", "pos": w._end_pos(cat[0], 1), "c": w._c(cat[1]), "yaw": PI + 0.3, "base": 0, "step": 0})
	return out


# ------------------------------------------------------------------ runtime

## Pandesal end runtime (only while the camera faces this end): queue, jeepney, cats.
static func step(w, dt: float) -> void:
	var st: Dictionary = w._near_state
	_step_queue(w, st)
	_step_jeep(w, st, dt)
	_step_cart(w, st, dt)


static func cart_selling(w) -> bool:
	return str(w._near_state.get("cart_state", "")) == "selling"


## Steam rises from the open warmer drawer (world-node space).
static func steam_origin(w) -> Vector3:
	return w._end_pos(CART + Vector3(0, 1.15, 0.6), 1)


static func _step_cart(w, st: Dictionary, dt: float) -> void:
	var cart: Node3D = st.cart
	var t: float = w._t
	var v: Dictionary = st.vendor
	match str(st.cart_state):
		"away":
			cart.visible = false
			v.visible = false
			if t > float(st.cart_next) and str(st.jeep_state) == "away":
				st.cart_state = "in"
				st.cart_x = 18.0
		"in":
			cart.visible = true
			v.visible = true
			var to_stop: float = float(st.cart_x) - STOP_X
			st.cart_speed = clampf(to_stop * 0.8, 0.5, 1.3)
			st.cart_x = float(st.cart_x) - float(st.cart_speed) * dt
			if to_stop < 0.05:
				st.cart_x = STOP_X
				st.cart_state = "opening"
		"opening":
			st.cart_open = minf(float(st.cart_open) + dt / 0.8, 1.0)
			if float(st.cart_open) >= 1.0:
				st.cart_state = "selling"
				st.cart_until = t + w._rng.randf_range(22.0, 32.0)
				v.vstate = "call"
				v.until = t + 2.5
		"selling":
			if t > float(st.cart_until) and str(v.vstate) == "idle":
				st.cart_state = "closing"
				for i in st.queue.size():   # anyone still waiting gives up
					var q = st.queue[i]
					if q != null:
						st.queue[i] = null
						leave(w, q)
		"closing":
			st.cart_open = maxf(float(st.cart_open) - dt / 0.8, 0.0)
			if float(st.cart_open) <= 0.0:
				st.cart_state = "out"
				st.cart_speed = 0.6
		"out":
			st.cart_speed = minf(float(st.cart_speed) + 1.0 * dt, 1.3)
			st.cart_x = float(st.cart_x) - float(st.cart_speed) * dt
			if float(st.cart_x) < -18.0:
				st.cart_state = "away"
				st.cart_next = t + w._rng.randf_range(20.0, 40.0)
	cart.position = Vector3(round(float(st.cart_x) * 20.0) / 20.0, 0.0, CART.z)
	w._move_shadow(int(st.cart_shadow), w._end_pos(Vector3(cart.position.x + 0.15, 0, CART.z - 0.05), 1), not cart.visible)
	var doors: Array = st.cart_doors
	var opened := smoothstep(0.0, 1.0, float(st.cart_open))
	(doors[0] as Node3D).rotation.y = round(deg_to_rad(170.0) * opened * 8.0) / 8.0
	(doors[1] as Node3D).rotation.y = -round(deg_to_rad(170.0) * opened * 8.0) / 8.0
	var playing_jingle: bool = str(st.cart_state) in ["in", "out"] or str(v.vstate) == "call"
	var pulse: MeshInstance3D = st.cart_pulse
	pulse.visible = playing_jingle and int(t * 4.0) % 2 == 0


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
		"cook":
			# stirring the pots, now and then a taste from the ladle
			p.arm_r = "reach_down" if int(t * 2.0) % 2 == 0 else "counter"
			p.arm_l = "counter"
			p.lean = 0.3
			p.head_pitch = 0.35
			if int(t / 6.0) % 4 == 0:
				p.arm_r = "drink"
				p.head_pitch = 0.0
		"diner":
			# eating: spoon to mouth, chatting in between
			var e := fmod(t + float(p.eat_phase), 3.0)
			p.arm_l = "counter"
			p.arm_r = "drink" if e < 0.5 else "counter"
			p.lean = 0.25
			p.head_pitch = 0.3 if e > 0.5 else 0.0
			if e > 2.0: p.head_yaw = 0.6
		"mechanic":
			var beat := int(t * 3.0) % 2
			p.arm_l = "reach_down"
			p.arm_r = "reach_down" if beat == 0 else "lean_in"
			p.lean = 0.5
			p.head_pitch = 0.4


static func _step_vendor(w, v: Dictionary) -> void:
	var t: float = w._t
	var st: Dictionary = w._near_state
	var cs := str(st.get("cart_state", "away"))
	if cs in ["in", "out"]:
		# walking behind the cart, pushing the handle, toward -x at this end
		v.pos = w._end_pos(Vector3(float(st.cart_x) + 1.5, 0, CART.z), 1)
		v.yaw = PI * 0.5
		v.seated = false
		v.posture = "stand"
		v.walk = -float(st.cart_x) * PI / 0.65
		v.arm_l = "counter"
		v.arm_r = "counter"
		v.lean = 0.3
		v.vstate = "idle"
		return
	v.pos = w._end_pos(VENDOR, 1)
	v.seated = false
	v.posture = "stand"
	if cs != "selling":
		# swinging the wing doors open or shut
		v.yaw = PI
		v.arm_l = "reach_up"
		v.arm_r = "counter"
		return
	v.arm_l = "counter"
	v.arm_r = "counter"
	v.lean = 0.15
	match str(v.vstate):
		"idle":
			if st.queue[0] != null and str(st.queue[0].state) == "queue" and t > float(st.queue[0].get("queued_at", 0.0)) + 1.2:
				v.vstate = "open"
				v.until = t + 1.1
			elif t > float(v.next_call):
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
			v.yaw = PI + 0.9          # turn toward the buyer at the cabinet (world yaw; the end is turned)
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
			if t > float(st.jeep_next) and str(st.get("cart_state", "away")) == "away":
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
	if w._rng.randf() < 0.7 and p.trait != "busy" and cart_selling(w):
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
			p.yaw = PI + PI            # face the cart's front (toward -z at this end)
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
