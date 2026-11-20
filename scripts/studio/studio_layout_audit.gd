extends RefCounted
## Desktop Pose Studio: objective layout audit (no images). Walks every visible Control under
## the PoseStudio node and reports measurable layout problems; run by the link command
## `ui_audit` (tools/pose_studio/PROTOCOL.md). Read-only: it never changes a control.
## Units are UI points (the studio canvas; `scale` = window pixels per point).
##
## Issue kinds:
##   text_clipped        text (font + size + icon + stylebox margins) wider than the control
##   wrap_collapse       autowrap label narrower than 2 glyphs or than its widest word
##   tiny                visible text control < 4 pt wide or tall
##   tree_text_clipped   Tree cell text wider than its column
##   tree_column_sparse  Tree column wider than 24 pt that is empty in >= 80 % of rows
##   tabs_overflow       TabContainer tabs do not fit (scroll arrows shown)
##   overlap             siblings in a layout container / plain Control intersect
##   escapes_parent      control extends past its (non-clipping) parent; `over` = other branches it covers
##   foreign_overlay     visible Control outside the studio drawn above it (higher CanvasLayer)
##   extra_viewport      TextureRect / SubViewportContainer showing a viewport other than the main preview
##   off_window          control extends beyond the window
##   small_target        button / slider / option less than 24 pt tall (or wide)
##   toggle_state_unclear toggle button whose pressed look equals its normal look
##   scroll_slack        scroll area with lots of unused height
##   scroll_overflow     scroll area whose content is taller than it (needs scrolling)

const MIN_TARGET := 24.0
const TINY := 4.0
const EPS := 1.0

var studio: Node
var root: Control
var win: Rect2
var issues: Array = []
var fonts: Dictionary = {}
var _clip: Dictionary = {}    # Control -> visible (clipped) global rect
var _visible: Array = []      # visible Controls in tree order
var _main_tex = null
var _button_styles: Dictionary = {}
var _cur_hidden := false
var scrolls: Array = []       # every visible scroll area: {path, content, have} (info, not issues)
var min_target := {}          # smallest shown button / field height: {h, path} (info)

static func run(studio_node: Node) -> Dictionary:
	var a = new()
	return a._run(studio_node)

func _run(s: Node) -> Dictionary:
	studio = s
	root = s.get("_root")
	if root == null: return {"ok": false, "error": "studio has no _root"}
	var vp := root.get_viewport()
	win = vp.get_visible_rect()
	var pv = s.get("preview")
	if pv != null and is_instance_valid(pv) and pv is TextureRect: _main_tex = pv.texture
	_collect(root, win)
	for c in _visible: _check_control(c)
	_check_siblings()
	_check_escapes()
	_check_foreign()
	_check_viewport_textures(s.get_tree().root)
	var counts := {}
	for i in issues: counts[i.kind] = int(counts.get(i.kind, 0)) + 1
	var px: Vector2 = Vector2(DisplayServer.window_get_size()) if DisplayServer.get_name() != "headless" else win.size
	var sizes := fonts.keys(); sizes.sort()
	var f := {}
	for k in sizes: f[str(k)] = fonts[k]
	return {"ok": true, "window": [win.size.x, win.size.y], "window_px": [px.x, px.y],
		"scale": snappedf(px.x / maxf(win.size.x, 1.0), 0.001), "controls": _visible.size(),
		"button_styles": _button_styles.size(), "scrolls": scrolls, "min_target": min_target, "layout": _layout_rects(), "issues": issues, "counts": counts, "fonts": f}

## Rects of the main regions (info for checks without images): [x, y, w, h] in points, or
## null when hidden.
const LAYOUT_NODES := ["TopBar", "Left", "PoseList", "Centre", "ViewToolbar", "Views", "ViewHint", "StatusLine",
	"TimelineControls", "Scrubber", "Right", "Inspector", "FieldScroll", "Panels", "ViewSeg", "GizmoSeg", "OverlaySeg",
	"SecondSeg", "StageSeg", "TransportSeg", "SpeedPicker", "VariantSeg", "TimeLabel", "AutoPoseBar"]

func _layout_rects() -> Dictionary:
	var out := {}
	for n in LAYOUT_NODES:
		var c := root.find_child(n, true, false) as Control
		out[n] = _rect(c.get_global_rect()) if c != null and c.is_visible_in_tree() else null
	return out

# ---------------------------------------------------------------- walk

func _collect(c: Control, parent_clip: Rect2) -> void:
	if not c.visible: return
	var r := c.get_global_rect()
	var vis := r.intersection(parent_clip) if parent_clip.intersects(r, true) else Rect2(r.position, Vector2.ZERO)
	_clip[c] = vis
	_visible.append(c)
	var child_clip := vis if c.clip_contents else parent_clip
	for ch in c.get_children():
		if ch is Control and not ch.top_level: _collect(ch, child_clip)
		elif ch is Control: _collect(ch, win)

func _path(c: Node) -> String: return str(studio.get_path_to(c))

func _rect(r: Rect2) -> Array:
	return [snappedf(r.position.x, 0.1), snappedf(r.position.y, 0.1), snappedf(r.size.x, 0.1), snappedf(r.size.y, 0.1)]

func _add(kind: String, c: Node, text: String, need, have, r: Rect2, extra := {}) -> void:
	var e := {"kind": kind, "path": _path(c) if c != null else "", "text": text.substr(0, 80),
		"need": need, "have": have, "rect": _rect(r)}
	e.merge(extra)
	if _cur_hidden: e["shown"] = false
	issues.append(e)

func _shown(c: Control) -> bool:
	var v: Rect2 = _clip.get(c, Rect2())
	return v.size.x > 0.5 and v.size.y > 0.5

# ---------------------------------------------------------------- per control

func _text_w(font: Font, text: String, fs: int) -> float:
	var w := 0.0
	for line in text.split("\n"): w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return w

func _sb_w(sb: StyleBox) -> float:
	return sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT) if sb else 0.0

func _check_control(c: Control) -> void:
	var r := c.get_global_rect()
	var shown := _shown(c)
	# off window (only the part that is not clipped away by a scroll area)
	if shown:
		var v: Rect2 = _clip[c]
		if v.position.x < win.position.x - EPS or v.position.y < win.position.y - EPS \
				or v.end.x > win.end.x + EPS or v.end.y > win.end.y + EPS:
			_add("off_window", c, _text_of(c), _rect(r), _rect(win), r)
	# Text / size checks run on scrolled-out controls too (layout bugs do not depend on the
	# scroll position); issues of controls not on screen carry shown: false.
	_cur_hidden = not shown
	var text := _text_of(c)
	if text != "":
		var fs := c.get_theme_font_size("font_size")
		fonts[fs] = int(fonts.get(fs, 0)) + 1
		if r.size.x < TINY or r.size.y < TINY:
			_add("tiny", c, text, TINY, [snappedf(r.size.x, 0.1), snappedf(r.size.y, 0.1)], r)
	if c is Button: _check_button(c, r)
	elif c is Label: _check_label(c, r)
	elif c is LineEdit: _check_line_edit(c, r)
	elif c is Tree: _check_tree(c, r)
	elif c is TabContainer: _check_tabs(c, r)
	elif c is ScrollContainer: _check_scroll(c, r)
	if (c is BaseButton or c is SpinBox or c is LineEdit) and shown and (min_target.is_empty() or r.size.y < min_target.h):
		min_target = {"h": snappedf(r.size.y, 0.1), "path": _path(c)}
	if c is BaseButton or c is Slider or c is SpinBox:
		if r.size.y < MIN_TARGET - 0.01 or (c is BaseButton and r.size.x < MIN_TARGET - 0.01):
			_add("small_target", c, text, MIN_TARGET, [snappedf(r.size.x, 0.1), snappedf(r.size.y, 0.1)], r)
	_cur_hidden = false

func _text_of(c: Control) -> String:
	if c is Button or c is Label: return c.text
	if c is LineEdit: return c.text if c.text != "" else c.placeholder_text
	return ""

const _DRAW_SB := {BaseButton.DRAW_NORMAL: "normal", BaseButton.DRAW_PRESSED: "pressed", BaseButton.DRAW_HOVER: "hover",
	BaseButton.DRAW_DISABLED: "disabled", BaseButton.DRAW_HOVER_PRESSED: "hover_pressed"}

func _check_button(b: Button, r: Rect2) -> void:
	var normal := b.get_theme_stylebox("normal")
	_button_styles[normal.get_instance_id() if normal else 0] = true
	if b.toggle_mode: _check_toggle(b, r)
	if b.text == "": return
	var font := b.get_theme_font("font")
	var fs := b.get_theme_font_size("font_size")
	var tw := _text_w(font, b.text, fs)
	var extra := 0.0
	if b.icon != null and not b.expand_icon:
		var iw := float(b.icon.get_width())
		var imax := b.get_theme_constant("icon_max_width")
		if imax > 0: iw = minf(iw, imax)   # Button draws the icon no wider than icon_max_width
		extra += iw + b.get_theme_constant("h_separation")
	if b is CheckBox or b is CheckButton:
		var ic := b.get_theme_icon("unchecked" if b is CheckBox else "unchecked")
		if ic: extra += ic.get_width() + b.get_theme_constant("h_separation")
	if b is OptionButton:
		var ar := b.get_theme_icon("arrow")
		extra += (ar.get_width() if ar else 0) + b.get_theme_constant("arrow_margin")
	# stylebox of the state it is drawn in; toggles also checked pressed (worst state)
	var states := [_DRAW_SB.get(b.get_draw_mode(), "normal")]
	if b.toggle_mode and not "pressed" in states: states.append("pressed")
	var worst := 0.0; var worst_state := ""
	for st in states:
		var need := tw + extra + _sb_w(b.get_theme_stylebox(st))
		if need > worst: worst = need; worst_state = st
	var trims := b.clip_text or b.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING
	if worst > r.size.x + EPS:
		_add("text_clipped", b, b.text, snappedf(worst, 0.1), snappedf(r.size.x, 0.1), r, {"state": worst_state, "trims": trims})

func _check_toggle(b: Button, r: Rect2) -> void:
	var n := b.get_theme_stylebox("normal"); var p := b.get_theme_stylebox("pressed")
	var same := n == p
	if not same and n is StyleBoxFlat and p is StyleBoxFlat:
		same = n.bg_color.is_equal_approx(p.bg_color) and n.border_color.is_equal_approx(p.border_color) \
			and n.border_width_bottom == p.border_width_bottom and n.border_width_left == p.border_width_left
	if same and b.get_theme_color("font_color").is_equal_approx(b.get_theme_color("font_pressed_color")):
		_add("toggle_state_unclear", b, b.text, "pressed != normal", "same", r)

func _check_label(l: Label, r: Rect2) -> void:
	if l.text == "": return
	var font := l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	var avail := r.size.x - _sb_w(l.get_theme_stylebox("normal"))
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		var widest := 0.0
		var i := 0
		for ch in l.text:
			if i > 200: break
			i += 1
			if ch == " " or ch == "\n": continue
			widest = maxf(widest, font.get_char_size(ch.unicode_at(0), fs).x)
		var word := 0.0
		for w in l.text.replace("\n", " ").split(" ", false):
			word = maxf(word, font.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		if l.text.length() > 1 and avail < 2.0 * widest:
			_add("wrap_collapse", l, l.text, snappedf(2.0 * widest, 0.1), snappedf(avail, 0.1), r, {"lines": l.get_line_count()})
		elif word > avail + EPS:
			_add("wrap_collapse", l, l.text, snappedf(word, 0.1), snappedf(avail, 0.1), r, {"lines": l.get_line_count(), "word_broken": true})
		return
	var tw := _text_w(font, l.text, fs)
	if tw > avail + EPS:
		_add("text_clipped", l, l.text, snappedf(tw, 0.1), snappedf(avail, 0.1), r,
			{"trims": l.clip_text or l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING})

func _check_line_edit(e: LineEdit, r: Rect2) -> void:
	if e.text != "" or e.placeholder_text == "": return
	var font := e.get_theme_font("font")
	var fs := e.get_theme_font_size("font_size")
	var avail := r.size.x - _sb_w(e.get_theme_stylebox("normal"))
	if e.right_icon: avail -= e.right_icon.get_width()
	var tw := _text_w(font, e.placeholder_text, fs)
	if tw > avail + EPS:
		_add("text_clipped", e, e.placeholder_text, snappedf(tw, 0.1), snappedf(avail, 0.1), r, {"placeholder": true})

func _check_tree(t: Tree, r: Rect2) -> void:
	var font := t.get_theme_font("font")
	var fs := t.get_theme_font_size("font_size")
	var pad := t.get_theme_constant("inner_item_margin_left") + t.get_theme_constant("inner_item_margin_right")
	var hsep := t.get_theme_constant("h_separation")
	var tr := t.get_root()
	if tr == null: return
	var empty: Array = []; empty.resize(t.columns); empty.fill(0)
	var rows := 0
	var clipped := 0
	var worst := {}
	var it := tr.get_first_child() if t.hide_root else tr
	while it != null:
		rows += 1
		for col in t.columns:
			var txt := it.get_text(col)
			var ic := it.get_icon(col)
			if txt == "" and ic == null: empty[col] += 1; continue
			var ifs := it.get_custom_font_size(col)
			var need := _text_w(font, txt, ifs if ifs > 0 else fs) + pad + (ic.get_width() + hsep if ic else 0)
			var have := float(t.get_column_width(col))
			if need > have + EPS:
				clipped += 1
				if not worst.has(col) or need - have > worst[col].need - worst[col].have:
					worst[col] = {"need": snappedf(need, 0.1), "have": have, "text": txt}
		it = it.get_next_in_tree()
	for col in worst:
		_add("tree_text_clipped", t, worst[col].text, worst[col].need, worst[col].have, r,
			{"column": col, "title": t.get_column_title(col), "cells_clipped": clipped, "rows": rows})
	for col in t.columns:
		var w := t.get_column_width(col)
		if rows > 0 and w > 24 and empty[col] >= 0.8 * rows:
			_add("tree_column_sparse", t, t.get_column_title(col), "content", w, r,
				{"column": col, "empty_rows": empty[col], "rows": rows})

func _check_tabs(tc: TabContainer, r: Rect2) -> void:
	var bar := tc.get_tab_bar()
	if bar == null: return
	var last := 0.0
	for i in bar.tab_count:
		if bar.is_tab_hidden(i): continue
		last = maxf(last, bar.get_tab_rect(i).end.x)
	if bar.get_offset_buttons_visible() or last > bar.size.x + EPS:
		var titles: Array = []
		for i in tc.get_tab_count(): titles.append(tc.get_tab_title(i))
		_add("tabs_overflow", tc, ", ".join(titles), snappedf(last, 0.1), snappedf(bar.size.x, 0.1), r,
			{"first_visible": bar.get_tab_offset()})

func _check_scroll(sc: ScrollContainer, r: Rect2) -> void:
	var content: Control = null
	for ch in sc.get_children():
		if ch is Control and not (ch is ScrollBar) and ch.visible: content = ch; break
	if content == null: return
	var ch_h := content.get_combined_minimum_size().y
	var h := r.size.y
	scrolls.append({"path": _path(sc), "content": snappedf(ch_h, 0.1), "have": snappedf(h, 0.1)})
	if not content.find_children("*", "ScrollContainer", true, false).is_empty(): return  # inner scroll owns the slack
	if ch_h > h + EPS:
		_add("scroll_overflow", sc, "", snappedf(ch_h, 0.1), snappedf(h, 0.1), r)
	elif h - ch_h > maxf(80.0, 0.35 * h):
		_add("scroll_slack", sc, "", snappedf(ch_h, 0.1), snappedf(h, 0.1), r, {"unused": snappedf(h - ch_h, 0.1)})

# ---------------------------------------------------------------- geometry between controls

func _layered(c: Control, parent: Control) -> bool:
	# A full-size layer (background, tick overlay) over its parent is intended.
	var a := c.get_global_rect(); var b := parent.get_global_rect()
	return a.position.distance_to(b.position) <= EPS and (a.size - b.size).length() <= EPS

func _check_siblings() -> void:
	for p in _visible:
		var stacks := p is MarginContainer or p is PanelContainer or p is CenterContainer or p is TabContainer \
			or p is ScrollContainer or p is AspectRatioContainer or p is SubViewportContainer
		if stacks: continue
		var kids: Array = []
		for ch in p.get_children():
			if ch is Control and ch.visible and not ch.top_level and _shown(ch):
				if not (p is Container) and _layered(ch, p): continue
				kids.append(ch)
		for i in kids.size():
			for j in range(i + 1, kids.size()):
				var a: Rect2 = _clip[kids[i]].grow(-0.5); var b: Rect2 = _clip[kids[j]].grow(-0.5)
				if a.intersects(b):
					var x := a.intersection(b)
					_add("overlap", kids[i], _text_of(kids[i]), _path(kids[j]), _rect(x), kids[i].get_global_rect(),
						{"with_text": _text_of(kids[j]).substr(0, 60)})

func _check_escapes() -> void:
	for c in _visible:
		var p = c.get_parent()
		if not (p is Control) or c.top_level or not _shown(c): continue
		if p.clip_contents: continue
		var cr: Rect2 = c.get_global_rect(); var pr: Rect2 = p.get_global_rect()
		if cr.position.x < pr.position.x - EPS or cr.position.y < pr.position.y - EPS \
				or cr.end.x > pr.end.x + EPS or cr.end.y > pr.end.y + EPS:
			_add("escapes_parent", c, _text_of(c), _rect(cr), _rect(pr), cr, {"over": _covers(c)})

## Leaf controls in other branches (not ancestors / descendants) that `c`'s visible rect covers.
func _covers(c: Control) -> Array:
	var out: Array = []
	var v: Rect2 = _clip[c].grow(-0.5)
	for o in _visible:
		if o == c or o.get_child_count() > 0 and not (o is Label or o is Button): continue
		if c.is_ancestor_of(o) or o.is_ancestor_of(c) or not _shown(o): continue
		if v.intersects(_clip[o]):
			out.append(_path(o))
			if out.size() >= 5: break
	return out

## Visible Controls outside the studio that draw above it (higher CanvasLayer, or top-level
## Controls on the same/higher layer), intersecting the window.
func _check_foreign() -> void:
	var my_layer: int = studio.layer if studio is CanvasLayer else 0
	for n in studio.get_tree().root.find_children("*", "CanvasLayer", true, false):
		if n == studio or not n.visible or n.layer < my_layer: continue
		if studio.is_ancestor_of(n): continue
		for ch in n.get_children():
			if not (ch is CanvasItem) or not ch.is_visible_in_tree(): continue
			var r: Rect2 = ch.get_global_rect() if ch is Control else Rect2(ch.get_global_transform().origin, Vector2.ONE)
			if ch is Control and not (r.intersects(win) and r.size.x > 0.5 and r.size.y > 0.5): continue
			_add("foreign_overlay", null, _text_of(ch) if ch is Control else "", "hidden", ch.get_class(), r,
				{"node": str(ch.get_path()), "layer": n.layer})
	for w in studio.get_tree().root.find_children("*", "Window", true, false):
		if w.visible and w.is_embedded() and not (w is AcceptDialog and studio.is_ancestor_of(w)):
			_add("foreign_overlay", null, w.title, "hidden", w.get_class(), Rect2(Vector2(w.position), Vector2(w.size)),
				{"node": str(w.get_path()), "window": true})
	for c in _visible:
		if c.top_level and c != root:
			_add("foreign_overlay", c, _text_of(c), "in layout", "top_level", c.get_global_rect(), {"node": str(c.get_path())})

func _check_viewport_textures(scene_root: Node) -> void:
	for n in scene_root.find_children("*", "Control", true, false):
		var c := n as Control
		if c == null or not c.is_visible_in_tree(): continue
		var shows_vp := c is SubViewportContainer or (c is TextureRect and c.texture is ViewportTexture)
		if not shows_vp or (c is TextureRect and c.texture == _main_tex): continue
		var r := c.get_global_rect()
		if not r.intersects(win): continue
		var inside := studio.is_ancestor_of(c)
		_add("extra_viewport", c if inside else null, "", "main preview only", str(c.get_path()), r,
			{"node": str(c.get_path()), "in_studio": inside, "shown": inside and _shown(c)})
