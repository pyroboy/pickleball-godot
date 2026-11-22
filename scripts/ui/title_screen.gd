extends Control

const AimPrewarm = preload("res://scripts/ui/aim_presentation_prewarm.gd")
const MatchEntryGate = preload("res://scripts/ui/match_entry_gate.gd")
var _aim_prewarm_report: Dictionary = {}
var _aim_prewarm_active := false
var _loading_quit_requested := false
var _loading_close_active := false
var _game_load_pending := false
var _loading_close_report: Dictionary = {}

const GAME_PATH: = "res://scenes/game.tscn"
const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")
const Layout = preload("res://scripts/ui/mobile_layout.gd")
const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
const MenuBallScene = preload("res://scripts/ui/menu_ball_scene.gd")
const NEON := Color("2cf06b")          # Barangay Pickleball neon green
const CREAM := Color("f3ead2")
var _word2: Label
var _shade: TextureRect
var _panel: PanelContainer
var _margin: MarginContainer
var _scroll: ScrollContainer
var _word: Label
var _logo_panel: PanelContainer
var _content: VBoxContainer
var _logo: TextureRect
var _play: Button
var _controls: Button
var _settings: Button
var _hint: Label
var _status: Label
var _progress: ProgressBar
var _loading: = false
var _finishing: = false
var _progress_value: = 0.0
var _overlay: Node
var _motion: = 0.0
var _redraw_clock: = 0.0
var _buttons: Array[Button] = []
var _portrait_fit_pending: = false
const CONTROLS_REFLOW_GUARD_MSEC: = 300
var _controls_reflow_until: = 0
var _controls_reflow_rect: = Rect2()
var _controls_reflow_view: = Vector2.ZERO
var _controls_blocked_action: Button

func _ready() -> void :
 get_tree().paused = false
 Engine.time_scale = 1.0
 theme = UiTheme.create()
 UiTheme.crisp(self)
 # 3D backdrop: the neon ball in the lower-right corner, tilt-shifted (menu_ball_scene)
 add_child(MenuBallScene.new())
 # darken the left side so the borderless menu reads over the scene
 _shade = TextureRect.new()
 var grad := Gradient.new()
 grad.set_color(0, Color(0.03, 0.05, 0.07, 0.72))
 grad.set_color(1, Color(0.03, 0.05, 0.07, 0.0))
 grad.set_offset(1, 1.0)
 var gt := GradientTexture2D.new()
 gt.gradient = grad
 gt.fill_from = Vector2(0.0, 0.5)
 gt.fill_to = Vector2(0.78, 0.5)
 gt.width = 64
 gt.height = 8
 _shade.texture = gt
 _shade.stretch_mode = TextureRect.STRETCH_SCALE
 _shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
 _shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
 _shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(_shade)
 _panel = PanelContainer.new()
 _panel.add_theme_stylebox_override("panel", StyleBoxFlat.new())
 (_panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Color(0, 0, 0, 0)
 add_child(_panel)
 var margin: = MarginContainer.new()
 _margin = margin
 for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 26)
 _panel.add_child(margin)
 _scroll = ScrollContainer.new()
 _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 _scroll.mouse_filter = Control.MOUSE_FILTER_STOP
 _scroll.follow_focus = true
 _scroll.hide()
 margin.add_child(_scroll)
 _content = VBoxContainer.new()
 _content.add_theme_constant_override("separation", 16)
 margin.add_child(_content)
 var word: = Label.new()
 _word = word
 word.text = "BARANGAY"
 word.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
 word.add_theme_color_override("font_color", CREAM)
 UiTheme.use_pixel(word, 18)
 _content.add_child(word)
 _word2 = Label.new()
 _word2.text = "PICKLEBALL"
 _word2.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
 _word2.add_theme_color_override("font_color", NEON)
 _word2.add_theme_color_override("font_shadow_color", Color(0.02, 0.2, 0.08, 0.9))
 _word2.add_theme_constant_override("shadow_offset_x", 3)
 _word2.add_theme_constant_override("shadow_offset_y", 3)
 UiTheme.use_pixel(_word2, 36)
 _content.add_child(_word2)
 var logo_panel: = PanelContainer.new()
 _logo_panel = logo_panel
 var paper: = StyleBoxFlat.new()
 paper.bg_color = Color("f6f3ec")
 paper.anti_aliasing = false
 paper.set_corner_radius_all(4)
 paper.border_color = Color("cfc8b6")   # paper bevel
 paper.border_width_bottom = 5
 paper.content_margin_left = 14
 paper.content_margin_right = 14
 paper.content_margin_top = 16
 paper.content_margin_bottom = 16
 logo_panel.add_theme_stylebox_override("panel", paper)
 _content.add_child(logo_panel)
 logo_panel.visible = false   # the wordmark is the two labels above now
 _logo = TextureRect.new()
 _logo.texture = null
 _logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
 _logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
 _logo.custom_minimum_size.y = 140
 logo_panel.add_child(_logo)
 _hint = Label.new()
 _hint.text = "A clean court. Your next point."
 _hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
 _hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 _hint.add_theme_color_override("font_color", UiTheme.MUTED)
 _content.add_child(_hint)
 _play = _button("Play doubles", _start_doubles)
 _button("Play singles", start_match)
 _button("Practice", _start_practice)
 _controls = _button("Controls", _toggle_controls)
 _settings = _button("Settings", _open_settings)
 _status = Label.new()
 _status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
 _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 _status.add_theme_font_size_override("font_size", 14)
 _status.add_theme_color_override("font_color", UiTheme.MUTED)
 _status.text = "Doubles: you + AI partner vs 2 AI"
 _content.add_child(_status)
 _progress = ProgressBar.new()
 _progress.show_percentage = true
 _progress.custom_minimum_size.y = 20
 _progress.visible = false
 _content.add_child(_progress)
 get_viewport().size_changed.connect(_fit)
 resized.connect(_fit)
 _panel.resized.connect(_center_panel)
 _content.minimum_size_changed.connect(_queue_portrait_fit)
 _fit()
 call_deferred("_fit")
 _play.grab_focus()

func _button(caption: String, action: Callable) -> Button:
 var button: = Button.new()
 button.text = "  " + caption
 # Borderless, left-aligned menu entries in the pixel font; the focused / hovered one
 # turns neon green with a ">" marker.
 var empty := StyleBoxEmpty.new()
 for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
  button.add_theme_stylebox_override(state, empty)
 button.alignment = HORIZONTAL_ALIGNMENT_LEFT
 button.add_theme_font_override("font", UiTheme.pixel_font())
 button.add_theme_color_override("font_color", CREAM)
 for state in ["font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
  button.add_theme_color_override(state, NEON)
 button.add_theme_color_override("font_pressed_color", NEON.darkened(0.2))
 button.add_theme_color_override("font_disabled_color", UiTheme.MUTED)
 button.set_meta("caption", caption)
 button.focus_entered.connect(_mark_button.bind(button, true))
 button.focus_exited.connect(_mark_button.bind(button, false))
 button.mouse_entered.connect(func(): button.grab_focus())
 button.custom_minimum_size.y = 58
 button.pressed.connect(_dispatch_title_action.bind(button, action))
 _content.add_child(button)
 _buttons.append(button)
 button.gui_input.connect(_guard_controls_reflow.bind(button))
 return button

func _mark_button(button: Button, on: bool) -> void:
 button.text = ("> " if on else "  ") + str(button.get_meta("caption"))

func _fit() -> void :
 if not is_instance_valid(_panel): return
 var safe: = Layout.safe_rect(get_viewport())
 var viewport_size: = get_viewport().get_visible_rect().size
 var portrait: = Layout.is_portrait(viewport_size)
 # Wide windows still use the tall authored canvas. Convert physical pixels
 # back to canvas units so labels and touch targets do not shrink with it.
 var s: = Layout.scale_for(viewport_size) if portrait else viewport_size.y / maxf(1.0, get_window().size.y)
 _fit_content(portrait, s, safe)
 var width: = minf(safe.size.x * (0.7 if portrait else 0.5), 610.0 * s)
 var height: = minf(safe.size.y - 40.0 * s, 600.0 * s)
 _panel.size = Vector2(width, height)
 _panel.position = _panel_origin(safe, _panel.size)
 if portrait:
  _logo.custom_minimum_size.y = clampf(width * 0.27, 76.0 * s, 140.0 * s)
  _queue_portrait_fit()
 call_deferred("_center_panel")
 queue_redraw()

func _fit_content(portrait: bool, s: float, safe: Rect2) -> void:
 # Both layouts use the existing bounded scroller; portrait uses design units
 # so high-density framebuffers retain the same touch/text proportions.
 var parent: Node = _scroll
 var focus: Control = get_viewport().gui_get_focus_owner()
 var restore_focus: = is_instance_valid(focus) and _content.is_ancestor_of(focus)
 if _content.get_parent() != parent:
  _content.reparent(parent, false)
 _scroll.visible = true
 if restore_focus and not focus.has_focus(): focus.grab_focus()
 _content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 theme.default_font_size = roundi(32 * s) if portrait else ceili(20 * s)
 var panel_style: StyleBoxFlat = _panel.get_theme_stylebox("panel")
 panel_style.content_margin_left = 20.0 * s if portrait else 0.0
 panel_style.content_margin_right = 20.0 * s if portrait else 0.0
 panel_style.content_margin_top = 18.0 * s if portrait else 0.0
 panel_style.content_margin_bottom = 18.0 * s if portrait else 0.0
 for side in ["left", "right", "top", "bottom"]:
  _margin.add_theme_constant_override("margin_" + side, roundi(26 * s) if portrait else roundi(20 * s))
 _content.add_theme_constant_override("separation", roundi(16 * s) if portrait else roundi(6 * s))
 _word.add_theme_font_size_override("font_size", UiTheme.pixel_size(36 * s) if portrait else UiTheme.pixel_size(18 * s))
 _word2.add_theme_font_size_override("font_size", UiTheme.pixel_size(72 * s) if portrait else UiTheme.pixel_size(36 * s))
 _status.add_theme_font_size_override("font_size", roundi(26 * s) if portrait else ceili(16 * s))
 theme.set_font_size("font_size", "Button", UiTheme.pixel_size(36 * s) if portrait else UiTheme.pixel_size(18 * s))
 theme.set_font_size("font_size", "ProgressBar", UiTheme.pixel_size(18 * s))
 if portrait:
  _hint.remove_theme_font_size_override("font_size")
  _progress.remove_theme_font_size_override("font_size")
 else:
  _hint.add_theme_font_size_override("font_size", ceili(16 * s))
  _progress.add_theme_font_size_override("font_size", ceili(16 * s))
  _logo.custom_minimum_size.y = clampf(safe.size.y * 0.1, 40 * s, 100 * s)
 _progress.custom_minimum_size.y = 20 * s
 var paper: StyleBoxFlat = _logo_panel.get_theme_stylebox("panel")
 paper.content_margin_left = 14.0 * s if portrait else 8 * s
 paper.content_margin_right = 14.0 * s if portrait else 8 * s
 paper.content_margin_top = 16.0 * s if portrait else 8 * s
 paper.content_margin_bottom = 16.0 * s if portrait else 8 * s
 for button in _buttons:
  button.custom_minimum_size.y = ceili(84 * s) if portrait else ceili(40 * s)
  button.remove_theme_font_size_override("font_size")
  # Let the scroll viewport cancel a pressed button when a finger starts a drag.
  button.mouse_filter = Control.MOUSE_FILTER_PASS

# Content wrapping and the loading row can change after containers lay out.
# Resize only the portrait panel here, keeping it bounded by the safe viewport.
func _queue_portrait_fit() -> void:
 if _portrait_fit_pending or not is_inside_tree(): return
 if not Layout.is_portrait(get_viewport().get_visible_rect().size): return
 _portrait_fit_pending = true
 call_deferred("_fit_portrait_height")

func _fit_portrait_height() -> void:
 _portrait_fit_pending = false
 if not is_instance_valid(_panel) or not is_inside_tree(): return
 var viewport_size: = get_viewport().get_visible_rect().size
 if not Layout.is_portrait(viewport_size): return
 var s: = Layout.scale_for(viewport_size)
 var safe: = Layout.safe_rect(get_viewport())
 var panel_style: StyleBox = _panel.get_theme_stylebox("panel")
 var frame_height: float = panel_style.get_minimum_size().y + _margin.get_theme_constant("margin_top") + _margin.get_theme_constant("margin_bottom")
 var desired_height: float = _content.get_combined_minimum_size().y + frame_height
 _panel.size.y = minf(ceilf(desired_height) + 1.0, safe.size.y - 40 * s)
 _center_panel()
 if not _content.sort_children.is_connected(_reveal_portrait_focus):
  _content.sort_children.connect(_reveal_portrait_focus, CONNECT_DEFERRED | CONNECT_ONE_SHOT)
 _content.queue_sort()

# Focus following normally runs only when focus changes. Wrapping/rotation may
# move the already-focused action, so reveal it after container layout settles.
func _reveal_portrait_focus() -> void:
 if not is_inside_tree(): return
 if not Layout.is_portrait(get_viewport().get_visible_rect().size): return
 var focus: Control = get_viewport().gui_get_focus_owner()
 if is_instance_valid(focus) and _content.is_ancestor_of(focus):
  _scroll.ensure_control_visible(focus)

# A second tap at the old Controls position must not activate an action that
# moved underneath it. Only this rectangle and this short pointer transition
# are guarded; keyboard/gamepad activation and other positions stay immediate.
func _guard_controls_reflow(event: InputEvent, button: Button) -> void:
 _controls_blocked_action = null
 var view: = get_viewport().get_visible_rect().size
 if not Layout.is_portrait(view) or _loading: return
 if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT: return
 if button == _controls:
  if not event.pressed and button.is_pressed() and Rect2(Vector2.ZERO, button.size).has_point(event.position):
   _controls_reflow_rect = button.get_global_rect()
   _controls_reflow_view = view
   _controls_reflow_until = Time.get_ticks_msec() + CONTROLS_REFLOW_GUARD_MSEC
  return
 if view != _controls_reflow_view or Time.get_ticks_msec() >= _controls_reflow_until: return
 if not event.pressed and button.is_pressed() and _controls_reflow_rect.has_point(button.get_global_transform() * event.position):
  # Keep native button cleanup and scroll gestures; suppress only this callback.
  _controls_blocked_action = button
  set_deferred("_controls_blocked_action", null)

func _dispatch_title_action(button: Button, action: Callable) -> void:
 if button == _controls_blocked_action:
  _controls_blocked_action = null
  return
 action.call()

func _center_panel() -> void :
 if not is_instance_valid(_panel) or not is_inside_tree(): return
 var safe: = Layout.safe_rect(get_viewport())
 _panel.position = _panel_origin(safe, _panel.size)

## The menu hugs the left edge, a little above centre (the ball owns the lower right).
func _panel_origin(safe: Rect2, panel_size: Vector2) -> Vector2:
 var s: = Layout.scale_for(get_viewport().get_visible_rect().size)
 return Vector2(safe.position.x + 18.0 * s, safe.position.y + maxf(20.0 * s, (safe.size.y - panel_size.y) * 0.38))

## Pixel-art court backdrop: night court with kitchen zones, a dithered sky band and a
## ball bouncing across. Everything is drawn on a coarse pixel grid (PX) so it reads as
## pixel art at any resolution; no textures, no per-frame allocations beyond the redraw.
const PX: = 6.0
const COURT_DARK: = Color("11303a")
const COURT: = Color("1a4a50")
const KITCHEN: = Color("1f5a5c")
const LINE: = Color(0.86, 0.94, 0.86, 0.32)
const BALL: = Color("e9f56a")

func _snap(v: float) -> float:
 return floorf(v / PX) * PX

func _px_rect(x: float, y: float, w: float, h: float, color: Color) -> void:
 draw_rect(Rect2(_snap(x), _snap(y), maxf(PX, _snap(w)), maxf(PX, _snap(h))), color)

func _draw() -> void :
 draw_rect(Rect2(Vector2.ZERO, size), UiTheme.BACKDROP)
 if _loading:
  var x: = size.x * 0.5 + sin(_motion * 4.0) * 30.0
  _px_rect(x, minf(size.y - 24.0, _panel.position.y + _panel.size.y + 18.0), PX * 2, PX * 2, UiTheme.ACCENT)

func _process(delta: float) -> void:
 var _pt := Time.get_ticks_usec()
 _perf_process(delta)
 PerfMonitor.record("proc.title_screen", Time.get_ticks_usec() - _pt)

func _perf_process(delta: float) -> void:
 # Ambient backdrop motion at ~15 fps (the pixel ball steps anyway; saves redraws).
 _motion += delta
 _redraw_clock += delta
 if _redraw_clock >= 1.0 / 15.0 or _loading:
  _redraw_clock = 0.0
  queue_redraw()
 if not _loading or _finishing or _loading_quit_requested: return
 var progress: Array = []
 var state: = ResourceLoader.load_threaded_get_status(GAME_PATH, progress)
 if not progress.is_empty():
  _progress_value = maxf(_progress_value, clampf(float(progress[0]), 0.0, 1.0))
  _progress.value = _progress_value * 100.0
 if state == ResourceLoader.THREAD_LOAD_LOADED:
  _finishing = true
  _progress.value = 100.0
  _status.text = "Preparing the court…"
  call_deferred("_enter_match")
 elif state == ResourceLoader.THREAD_LOAD_FAILED or state == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
  _fail("The court could not load. Please try again.")

func _start_practice() -> void :
 if _loading or is_instance_valid(_overlay): return
 start_match("practice")

func _start_doubles() -> void:
 start_match("doubles")

func start_match(mode: String = "singles") -> void :
 if _loading or is_instance_valid(_overlay): return
 if mode == "practice": get_tree().set_meta("open_practice", true)
 elif get_tree().has_meta("open_practice"): get_tree().remove_meta("open_practice")
 get_tree().set_meta("local_doubles", mode == "doubles")
 _loading = true
 _finishing = false
 _progress_value = 0.0
 _status.text = "Loading court resources…"
 _progress.visible = true
 for button in _buttons: button.disabled = true
 var error: = ResourceLoader.load_threaded_request(GAME_PATH, "PackedScene", false)
 _game_load_pending = error == OK
 if error != OK: _fail("Loading could not start. Please try again.")

func request_loading_back() -> bool:
 if not _loading:return false
 if _loading_quit_requested:return true
 _loading_quit_requested=true
 _status.text="Closing…"
 if _aim_prewarm_active:AimPrewarm.cancel_for(get_tree().root)
 else:call_deferred("_complete_loading_quit")
 return true

func _complete_loading_quit() -> void:
 if _aim_prewarm_active or _loading_close_active or not _loading_quit_requested:return
 _loading_close_active=true
 var tree := get_tree()
 var start := Time.get_ticks_usec()
 _loading_close_report={"phase":"drain_threaded_load","started_usec":start,"pending_at_start":_game_load_pending,"poll_frames":0,"get_calls":0}
 # ResourceLoader has no cancel API. Keep its worker alive until terminal,
 # then consume the request once; never call get while it would block.
 while _game_load_pending:
  var state := ResourceLoader.load_threaded_get_status(GAME_PATH)
  _loading_close_report["last_load_status"]=state
  if state==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
   _loading_close_report["poll_frames"]+=1
   await tree.process_frame
   if not is_inside_tree():return
   continue
  _game_load_pending=false
  if state==ResourceLoader.THREAD_LOAD_LOADED or state==ResourceLoader.THREAD_LOAD_FAILED:
   var unused_resource: Resource=ResourceLoader.load_threaded_get(GAME_PATH)
   _loading_close_report["get_calls"]+=1
   unused_resource=null
  break
 _loading_close_report["drain_usec"]=Time.get_ticks_usec()-start
 _loading_close_report["phase"]="release_completed_coroutines"
 # Allow the prewarm / held-action coroutine to return and drop PackedScene
 # and private resource references before renderer and loader shutdown.
 for index in 2:await tree.process_frame
 if not is_inside_tree():return
 _loading_close_report["phase"]="quit"
 _loading_close_report["elapsed_usec"]=Time.get_ticks_usec()-start
 tree.quit()

func _enter_match() -> void :
 if not is_inside_tree() or _loading_quit_requested:return
 var packed: = ResourceLoader.load_threaded_get(GAME_PATH) as PackedScene
 _game_load_pending=false
 if packed == null:
  _fail("The court scene is unavailable.")
  return
 # Keep the existing title loading UI/latch until presentation is ready.
 # A resize during warming invalidates the extent key and warms the latest
 # viewport before the Game is created; no live match is paused or reset.
 var viewport := get_viewport()
 var settings := get_node("/root/Settings")
 while is_inside_tree():
  _status.text = "Preparing shot visuals…"
  var extent := Vector2i(viewport.get_visible_rect().size)
  var options := {"external_loading":true,"blur":float(settings.get_value("video.focus_blur",.65)),"dim":float(settings.get_value("video.focus_dim",.14)),"arc_style":int(settings.get_value("video.focus_arc_style",0)),"shadow_quality":int(settings.get_value("video.shadow_quality",1))}
  _aim_prewarm_active=true
  _aim_prewarm_report = await AimPrewarm.prepare(get_tree().root,extent,options)
  _aim_prewarm_active=false
  if not is_inside_tree(): return
  if _loading_quit_requested:
   call_deferred("_complete_loading_quit")
   return
  if str(_aim_prewarm_report.status) not in ["completed","already_warm","headless_skipped"]:
   _fail("Shot visuals could not prepare. Please try again.")
   return
  # Await the existing pause policy as well as an inherited charge action.
  # Do not construct an interactive Game behind a paused title transition.
  while get_tree().paused or Input.is_action_pressed("ui_accept"):
   if _loading_quit_requested:return
   _status.text = "Paused. Return to continue loading." if get_tree().paused else "Release HIT / Space to enter the court."
   await get_tree().process_frame
   if not is_inside_tree(): return
  # A rotation while paused or waiting for release must also revalidate.
  if extent == Vector2i(viewport.get_visible_rect().size): break
 var entry = MatchEntryGate.new()
 get_tree().root.add_child(entry)
 if not entry.arm():
  entry.queue_free()
  _fail("The court entry is already active. Please try again.")
  return
 if not await entry.show_loading(): return
 var error: int = entry.change_scene(packed)
 if error != OK:
  entry.abort_before_scene()
  _fail("The court could not open. Please try again.")

func _fail(message: String) -> void :
 if get_tree().has_meta("local_doubles"): get_tree().remove_meta("local_doubles")
 if get_tree().has_meta("open_practice"): get_tree().remove_meta("open_practice")
 _loading = false
 _finishing = false
 _progress.visible = false
 _status.text = message
 for button in _buttons: button.disabled = false
 _play.grab_focus()

func _toggle_controls() -> void :
 if _loading: return
 if _hint.text.begins_with("MOVE"):
  _hint.text = "A clean court. Your next point."
 else:
  _hint.text = "MOVE with the left stick. Hold and drag HIT to aim with your right thumb. Hold and drag the outer buttons for Topspin, Slice or Drop. Release HIT to commit your swing.\nKeyboard: WASD/arrows + Space · Q Spin · E Drop"
 _fit()

func _open_settings() -> void :
 if _loading or is_instance_valid(_overlay): return
 _overlay = SettingsPanel.new()
 _overlay.process_mode = Node.PROCESS_MODE_ALWAYS
 _overlay.set_meta("on_close", _settings_closed)
 add_child(_overlay)

func _settings_closed() -> void :
 _overlay = null
 if is_instance_valid(_settings): _settings.grab_focus()
