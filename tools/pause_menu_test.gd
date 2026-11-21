extends SceneTree
## Headless pause-menu check: opens the pause menu in a match and in the wall drill, checks
## that every action is on screen (inside the panel and the viewport, portrait and
## landscape), then drives Resume, Back (ESC), Restart, and Main menu -> title (unpaused).
## Run: godot --headless --path . --fixed-fps 60 -s tools/pause_menu_test.gd -- --mobile-runtime

var _game: Node
var _t := 0.0
var _step := 0
var _wait := 0.0
var _fails := 0
var _checks := 0

class Driver extends Node:
	var bench
	func _process(delta: float) -> void: bench._tick(delta)

func _initialize() -> void:
	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(_game)
	var d := Driver.new()
	d.bench = self
	d.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child.call_deferred(d)

func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond: _fails += 1
	print("PASS  " if cond else "FAIL  ", label)

func _pc() -> Node: return root.get_node("PauseController")

func _menu() -> Node:
	var m = _pc()._menu
	return m if is_instance_valid(m) else null

func _buttons(node: Node, out: Array) -> Array:
	for c in node.get_children():
		if c is Button and c.is_visible_in_tree(): out.append(c)
		_buttons(c, out)
	return out

func _layout_check(tag: String) -> void:
	var m = _menu()
	if m == null: _check(false, tag + " menu open"); return
	var view: Rect2 = m.get_viewport().get_visible_rect()
	var panel: Rect2 = m._panel.get_global_rect()
	_check(view.encloses(panel), "%s panel inside viewport %s (panel %s)" % [tag, view.size, panel])
	var scroll_rect: Rect2 = m._scroll.get_global_rect()
	var needs_scroll: bool = m._content.get_combined_minimum_size().y > m._scroll.size.y + 0.5
	var names: Array = []
	for b in _buttons(m._content, []):
		names.append(b.text)
		if not needs_scroll:
			_check(scroll_rect.grow(1).encloses(b.get_global_rect()), "%s '%s' fully visible" % [tag, b.text])
		_check(b.size.y >= 44.0, "%s '%s' touch target %.0f px" % [tag, b.text, b.size.y])
	print("  %s buttons: %s  scroll=%s" % [tag, names, needs_scroll])
	_text_fit_check(tag, m._content)

## Every visible button uses the pixel font and its caption fits without clipping.
func _text_fit_check(tag: String, node: Node) -> void:
	var pixel = load("res://scripts/ui/game_ui_theme.gd").pixel_font()
	for b in _buttons(node, []):
		var font: Font = b.get_theme_font("font")
		var fsize: int = b.get_theme_font_size("font_size")
		var text_w: float = font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		var box: StyleBox = b.get_theme_stylebox("normal")
		var room: float = b.size.x - box.get_margin(SIDE_LEFT) - box.get_margin(SIDE_RIGHT)
		_check(font == pixel, "%s '%s' uses the pixel font (size %d)" % [tag, b.text, fsize])
		_check(text_w <= room + 0.5, "%s '%s' caption fits (%.0f of %.0f px)" % [tag, b.text, text_w, room])

func _tick(delta: float) -> void:
	_t += delta
	if current_scene != _game and is_instance_valid(_game) and _game.is_inside_tree() and _step < 9: current_scene = _game
	if _wait > 0: _wait -= delta; return
	match _step:
		0:
			if _t < 1.5: return
			root.size = Vector2i(720, 1280)
			_pc().open(); _wait = 0.3
		1:
			_check(paused and _menu() != null, "pause opens and pauses the tree")
			_layout_check("portrait match")
			var labels: Array = []
			for b in _buttons(_menu()._content, []): labels.append(b.text)
			_check("Main menu" in labels, "Main menu action present")
			root.size = Vector2i(1280, 720); _wait = 0.3
		2:
			_layout_check("landscape match")
			root.size = Vector2i(720, 1280); _wait = 0.2
		3:
			_menu()._resume_button.pressed.emit(); _wait = 0.2
		4:
			_check(not paused and _menu() == null, "Resume closes the menu and unpauses")
			_game.practice_launcher.start_drill("WALL"); _wait = 0.6
		5:
			_pc().open(); _wait = 0.3
		6:
			_layout_check("portrait wall drill")
			_game.practice_panel.open_practice(); _wait = 0.2; _step = 20; return
		20:
			_text_fit_check("practice picker", _game.practice_panel._content)
			_game.practice_panel.close_picker(); _step = 7; _wait = 0.1
			_menu()._confirm("menu"); return
			_check(_menu()._reset_button.text == "Reset ball", "wall drill shows Reset ball")
		7:
			_check(_menu()._confirm_box.visible and not _menu()._main_list.visible, "Main menu asks to confirm in-panel")
			_pc()._handle_back_request(); _wait = 0.1   # ESC / swipe back
		8:
			_check(_menu() != null and not _menu()._confirm_box.visible, "Back cancels the confirmation, menu stays")
			_menu()._confirm("menu"); _menu()._confirm_ok.pressed.emit(); _wait = 0.5; _step = 9; return
		9:
			_check(current_scene != null and current_scene.scene_file_path == "res://scenes/title.tscn", "Main menu returns to the title screen")
			_check(not paused, "title is not paused")
			_check(_menu() == null, "pause menu gone")
			var title = current_scene
			_check(title.get_viewport().get_visible_rect().encloses(title._panel.get_global_rect()), "title panel inside viewport")
			_text_fit_check("title", title._content)
			print("PAUSE MENU  %d checks, %d failed" % [_checks, _fails])
			quit(1 if _fails > 0 else 0)
			return
	_step += 1
