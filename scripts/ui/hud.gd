extends CanvasLayer
class_name Hud
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")



signal pose_editor_requested
signal pause_requested
signal skip_retrieval_requested
signal photo_requested   # the quick Photo button: pause and open photo mode in one tap
const MobileLayout = preload("res://scripts/ui/mobile_layout.gd")
const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
const HudChrome = preload("res://scripts/ui/hud_chrome.gd")
const PixelBanner = preload("res://scripts/ui/pixel_banner.gd")
const PixelStyle = preload("res://scripts/ui/pixel_style_box.gd")
const PixelDraw = preload("res://scripts/ui/pixel_draw.gd")
const AI_DIFFICULTY_COLORS: Array[Color] = [UiTheme.ACCENT, Color("f5d38b"), UiTheme.RED]
const DEMO_CUES: = {"SOFT": "Soft dink · watch the angle", "POPUP": "Loose dink · attack chance", 
	"HIGH_POPUP": "High popup · overhead chance", "SMASH": "Smash · block and reset", 
	"SPEED_UP": "Speed-up · compact block", "RESET": "Soft reset · recover"}

var score: Label
var state: Label
var difficulty: Label
var debug: Label
var fault: Label
var out_text: Label
var zone: Label
var speed: Label
var hittable_dot: Control
var shot_type: Label
var posture_debug: Label
var freeze_indicator: Label
var debug_available: = RuntimePolicy.developer_tools
var debug_mode: = false
var _debug_toolbar: GridContainer
var _debug_button: Button
var _skip_button: Button
var _rec_button: Button            # rally replays: save every rally while on
var _save_rally_button: Button     # asks to save the rally that just ended
var _save_rally_token: int = 0
var _photo_button: Button   # quick way into photo mode; Settings > Video > Photo button (video.photo_button)
var _between_point_active: = false
var _portrait: = false
var _score_panel: Panel
var _status_panel: Panel
var _score_chrome: HudChrome
var _guidance_chrome: HudChrome
var _pill_chrome: HudChrome   # portrait corner score pill: team dots
var _pill_label: Label        # "7-5-2" score-score-server
var _board: DigitalScoreboard  # retro LED score board (replaces the pill / big score)
const SHOW_STATUS_BOX := false   # portrait corner status box (archived; true brings it back)
var _pill_text: = ""
var _toolbar: HBoxContainer
var _guide: PanelContainer
var _guide_scroll: ScrollContainer
var _guide_button: Button
var _pause_button: Button
var _toolbar_icons: Array[Control] = []
var _toolbar_captions: Array[Label] = []
var _pose_button: Button
var _desktop_guide_text: = ""
var _guide_instructions: Label
var _spin_label: Label
var _locked_spin_label: Label
var _spin_locked: = false
var _selected_spin: = "FLAT"
var _selected_intent: = "AUTO"
var _locked_display: = ""
var _spin_enabled: = false
var _serve_ball: Control
var _rally_banner: Panel
var _rally_headline: Label
var _rally_detail: Label
var _rally_reason: Label   # short friendly reason, between the headline and the score line
var _rally_pixel: Control  # pixel_banner.gd: draws the whole result banner (the labels stay hidden)
var _rally_reason_fill: = Color("a3352f")
var _banner_avoid: Array = []   # screen rects the result banner must not cover (e.g. an "Ouch!" bubble)
var _serve_label: Label
var _blue_label: Label
var _red_label: Label
var _controls_hint: Label
var _charge_label: Label
var _charge_bar: ProgressBar
var _match_label: Label
var _gameplay_visible: = true
var _charging: = false
var _aim_mode: = "MOVE"
var _blue_score: = 0
var _red_score: = 0
var _server: = -1
var _rally_active: = false
var _practice_exchange_context: = false
var _wall_context: = false
var _demo_guidance_active: = false
var _font_bold: SystemFont
## Pill labels (serve line, shot name, speed, locked shot): each sits on a dark pixel pill
## sized to its text and aligned (by its horizontal_alignment) inside this region.
var _pill_regions: Dictionary = {}
const TOOLBAR_STYLE_KEYS: = ["normal", "hover", "pressed", "hover_pressed", "disabled"]

class HittabilityDot extends Control:
	var hittable := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		process_mode = Node.PROCESS_MODE_ALWAYS
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		resized.connect(queue_redraw)
	func _process(delta: float) -> void:
		get_parent()._sync_hittability(delta)
	func set_hittable(value: bool) -> void:
		if hittable == value: return
		hittable = value
		queue_redraw()
	func _draw() -> void:
		# Pixel dot (UI kit): whole UI pixels, dark rim, no anti-aliasing.
		var radius := minf(size.x, size.y) * 0.5
		var u: float = maxf(1.0, roundf(radius / 2.0))
		PixelDraw.disc(self, size * 0.5, radius, u, Color("55dc80") if hittable else Color("7d8994"), Color("07131f"), 1, false)

# Prediction is independent of charge, human-contact preparation and slow motion.
# The horizon is the existing aim controller's plant lead; proximity is the
# authored contact zones plus exact wrist/head reach, not a new radial threshold.
class PassiveContact extends RefCounted:
	const Planner = preload("res://scripts/incoming_contact_planner.gd")
	const Flight = preload("res://scripts/ball_flight_predictor.gd")
	const FootState = preload("res://scripts/player_nvz_state.gd")
	const Aim = preload("res://scripts/aim_controller.gd")
	const INTERVAL_USEC := 100000
	const URGENT_INTERVAL_USEC := 50000
	var contact: Dictionary = {}
	var _key: Array = []
	var _next_probe := 0
	var _velocity := Vector3.ZERO
	var _near_bounds := AABB()
	var _forward := Vector3.ZERO
	var _sim_age := 0.0
	var probes := 0
	var probe_usec := 0
	var max_probe_usec := 0
	var _feet = FootState.new()

	func clear() -> void:
		contact = {}
		_key = []

	func volley_allowed(player) -> bool:
		# Updating this private clone preserves the live foot establishment,
		# locomotion, contact controller, poses and swing ownership.
		_feet.established_outside = player._nvz_state.established_outside
		_feet._last_root = player._nvz_state._last_root
		return _feet.can_volley(player)

	func sample(player, ball, now: int, simulation_delta: float = 0.0) -> bool:
		_sim_age += maxf(0.0, simulation_delta)
		if not ball.is_in_play or ball.freeze or ball.last_hit_by == player.player_num or ball.bounces_since_last_hit >= 2:
			clear(); return false
		var relative: Vector3 = ball.global_position - player.global_position
		var forward: Vector3 = player._get_forward_axis()
		if relative.dot(forward) < 0.0 or not Planner.should_track(player, ball):
			clear(); return false
		var key := [player.get_instance_id(), ball.get_instance_id(), ball.flight_id, ball.last_hit_by, ball.bounces_since_last_hit, ball.both_bounces_complete, ball.wall_practice_active, ball.wall_return_ready, player.is_jumping]
		if key != _key or ball.linear_velocity.dot(_velocity) < 0.0 or forward.dot(_forward) < 0.999:
			contact = {}
			_key = key
		if now >= _next_probe:
			# At most20Hz during movement or an imminent arrival,10Hz otherwise.
			# This changes query cadence only; exact contact reach stays unchanged.
			var closing_speed: float = maxf(0.0, ball.linear_velocity.dot(-forward))
			var urgent: bool = relative.dot(forward) <= PaddleReach.MAX_HEAD_DISTANCE + closing_speed * Aim.URGENT_PLANT_LEAD
			var moving: bool = player.current_velocity.length_squared() > 0.01
			_next_probe = now + (URGENT_INTERVAL_USEC if urgent or moving else INTERVAL_USEC)
			_sim_age = 0.0
			var started := Time.get_ticks_usec()
			var flight: Dictionary = Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity, Aim.PLANT_LEAD, 2, true, true)
			# trace rounds to whole physics ticks; clip its last endpoint so
			# the visible promise never extends beyond the stated horizon.
			var samples: Array = flight.get("samples", [])
			while not samples.is_empty() and float(samples.back().time) > Aim.PLANT_LEAD + 0.000001: samples.pop_back()
			_near_bounds = AABB(ball.global_position, Vector3.ZERO)
			for predicted in samples:
				_near_bounds = _near_bounds.expand(predicted.pos)
				if float(predicted.time) >= 0.1: break
			_near_bounds = _near_bounds.grow(Planner.CONTACT_MARGIN)
			contact = Planner.select(player, ball, flight, -1, int(volley_allowed(player)))
			_velocity = ball.linear_velocity
			_forward = forward
			var cost := Time.get_ticks_usec() - started
			probes += 1
			probe_usec += cost
			max_probe_usec = maxi(max_probe_usec, cost)
		if contact.is_empty(): return false
		if not _near_bounds.has_point(ball.global_position):
			contact = {}; return false
		# Cheap current geometry and legality guards clear stale green between
		# probes, including a player moving away or a ball passing the paddle.
		if relative.dot(forward) < (contact.point - player.global_position).dot(forward) - Planner.LIVE_WINDOW: return false
		if _sim_age > float(contact.time) + 0.000001:
			# A spent forecast cannot keep green merely because its old point
			# remains within arm reach. An immediate real contact is still valid.
			if relative.dot(forward) < 0.08: return false
			if not bool(contact.get("extended", false)) and absf(relative.dot(forward) - contact.def.zone_forward_offset) > Planner.LIVE_WINDOW: return false
			if not Planner.point_fits(player, contact.def, ball.global_position): return false
			return Planner.legal_ball(player, ball, 0, int(volley_allowed(player)))
		if not Planner.point_fits(player, contact.def, contact.point): return false
		return Planner.legal_ball(player, ball, int(contact.bounces), int(volley_allowed(player)))

var _passive_contact := PassiveContact.new()

func _sync_hittability(simulation_delta: float = 0.0) -> void:
	if hittable_dot == null: return
	var reachable := false
	var game = get_parent()
	if _gameplay_visible and not get_tree().paused and game != null and "player_left" in game and game.player_left != null and game.game_state == 2 and not game.match_over and not game._tool_state_active() and not _guide.visible and game.ball.is_in_play and not game.ball.freeze:
		var human = game.player_left.posture.human_contact
		if human == null or human.phase < 0:
			reachable = _passive_contact.sample(game.player_left, game.ball, Time.get_ticks_usec(), simulation_delta)
		else:
			_passive_contact.clear()
	else:
		_passive_contact.clear()
	hittable_dot.set_hittable(reachable)

func _ready() -> void :
	name = "UI"
	_font_bold = SystemFont.new()
	_font_bold.font_names = PackedStringArray(["Inter", "Segoe UI", "DejaVu Sans", "Arial", "sans-serif"])
	_font_bold.font_weight = 700
	_build_panels()
	_build_labels()
	_build_singles_feedback()
	_build_toolbar()
	get_viewport().size_changed.connect(_layout_desktop)
	_layout_desktop()
	set_match_context(0, false)
	if OS.get_cmdline_user_args().has("--ui-rects"):
		# Debug only: once a second (pausable timer), log HUD rects for the overlap check.
		var timer: = Timer.new()
		timer.wait_time = 1.0
		timer.autostart = true
		timer.timeout.connect(_note_ui_rects)
		add_child(timer)

## --ui-rects: screen rects of the HUD pieces that must not overlap, to perf.jsonl
## (note "ui_rects"). Only what is drawn: visible and not faded out.
func _note_ui_rects() -> void:
	var rects: = {}
	var named: Array = [["serve", _serve_label], ["shot", shot_type], ["speed", speed], ["locked", _locked_spin_label], ["board", _board], ["dot", hittable_dot]]
	var toolbar_names: = ["debug", "skip", "guide", "pause"]
	if _photo_button != null and _photo_button.visible: named.append(["photo", _photo_button])
	for i in _toolbar.get_child_count(): named.append([toolbar_names[i] if i < toolbar_names.size() else "tool%d" % i, _toolbar.get_child(i)])
	var game: = get_parent()
	for extra in game.get("extra_touch_buttons") if game != null and game.get("extra_touch_buttons") != null else []:
		if is_instance_valid(extra): named.append(["tips", extra])
	for pair in named:
		var c: Control = pair[1]
		if is_instance_valid(c) and c.is_visible_in_tree() and c.modulate.a > 0.01 and c.self_modulate.a > 0.01:
			var r: Rect2 = c.get_global_rect()
			rects[pair[0]] = [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]
	var controls = game.get("mobile_controls") if game != null else null
	if controls != null and controls.enabled and controls.visible:
		for key in ["stick_zone", "hit_zone"]:
			var r: Rect2 = controls.get(key)
			rects[key] = [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]
	var cues = game.get_node_or_null("DoublesIdentityCues") if game != null else null
	if cues != null and cues.has_method("screen_rects"):
		var labels: Dictionary = cues.screen_rects()
		for key in labels:
			var r: Rect2 = labels[key]
			rects[key] = [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]
	var branding = game.get_node_or_null("CourtBranding") if game != null else null
	PerfMonitor.note("ui_rects", {"rects": rects, "view": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"logo_fade": snappedf(float(branding.get("_fade")), 0.01) if branding != null else -1.0, "between": _between_point_active,
		"serve": _serve_label.text, "speed": speed.text if speed.modulate.a > 0.01 else "", "shot": shot_type.text if shot_type.modulate.a > 0.01 else "",
		"state": int(game.get("game_state")) if game != null and game.get("game_state") != null else -1})

func _label(text: String, font_size: int, color: Color = UiTheme.INK, bold: bool = false) -> Label:
	var label: = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if bold:
		label.add_theme_font_override("font", _font_bold)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func _panel() -> Panel:
	var panel: = Panel.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	return panel

func _build_panels() -> void :
	_score_panel = _panel()
	_score_panel.name = "ScorePanel"
	_status_panel = _panel()
	_status_panel.name = "StatusPanel"
	_score_chrome = HudChrome.new()
	_score_chrome.name = "ScoreWings"
	_score_chrome.kind = HudChrome.Kind.SCOREBOARD
	_score_panel.add_child(_score_chrome)
	_score_chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_score_chrome.hide()
	_pill_chrome = HudChrome.new()
	_pill_chrome.name = "ScorePillDots"
	_pill_chrome.kind = HudChrome.Kind.PILL
	_score_panel.add_child(_pill_chrome)
	_pill_chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pill_chrome.hide()
	_board = DigitalScoreboard.new()
	_board.name = "DigitalScoreboard"
	add_child(_board)
	_board.hide()
	_guidance_chrome = HudChrome.new()
	_guidance_chrome.name = "GuidanceIcons"
	_guidance_chrome.kind = HudChrome.Kind.GUIDANCE
	add_child(_guidance_chrome)
	_guidance_chrome.hide()

func _build_labels() -> void :
	_match_label = _label("SINGLES  /  FIRST TO 11", 13, UiTheme.MUTED, true)
	_match_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blue_label = _label("YOU · BLUE", 14, UiTheme.BLUE, true)
	_red_label = _label("AI · RED", 14, UiTheme.RED, true)
	_red_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score = _label("0   :   0", 40, UiTheme.INK, true)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pill_label = _label("0-0", 30, UiTheme.INK, true)
	_pill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pill_label.hide()
	_serve_label = _label("YOU SERVE", 13, UiTheme.ACCENT, true)
	_serve_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	difficulty = _label("AI: EASY  [X]", 16, UiTheme.ACCENT, true)
	_spin_label = _label("SPIN · FLAT  [Q]", 16, UiTheme.INK, true)
	_spin_label.name = "SelectedSpin"
	_spin_label.hide()
	_locked_spin_label = _label("", 12, UiTheme.MUTED, true)
	_locked_spin_label.hide()
	state = _label("Hold SPACE to charge serve", 21, UiTheme.INK, true)
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_controls_hint = _label("WASD / arrows  Move     SPACE  Hold & release     ESC  Pause", 14, UiTheme.MUTED)
	_charge_label = _label("SHOT POWER", 12, UiTheme.MUTED, true)
	_charge_bar = ProgressBar.new()
	_charge_bar.name = "ChargeMeter"
	_charge_bar.max_value = 1.0
	_charge_bar.show_percentage = false
	_charge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background: = UiTheme.button_style(UiTheme.SURFACE)
	background.content_margin_top = 0
	background.content_margin_bottom = 0
	background.border_width_bottom = 0
	var fill: = background.duplicate() as StyleBoxFlat
	fill.bg_color = UiTheme.ACCENT
	_charge_bar.add_theme_stylebox_override("background", background)
	_charge_bar.add_theme_stylebox_override("fill", fill)
	add_child(_charge_bar)
	debug = _label("", 16, UiTheme.MUTED)
	posture_debug = _label("", 16, UiTheme.MUTED)
	posture_debug.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	freeze_indicator = _label("BALL FROZEN", 16, UiTheme.BLUE, true)
	freeze_indicator.hide()
	fault = _label("", 34, UiTheme.RED, true)
	fault.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fault.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fault.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	out_text = _label("OUT", 58, UiTheme.RED, true)
	out_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone = _label("", 18, UiTheme.BLUE, true)
	zone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed = _label("", 20, UiTheme.INK, true)
	speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hittable_dot = HittabilityDot.new()
	hittable_dot.name = "BallHittability"
	hittable_dot.tooltip_text = "Green: a legal incoming ball reaches your paddle range within 0.85 seconds. Gray: no reachable contact from here."
	add_child(hittable_dot)
	shot_type = _label("", 19, UiTheme.ACCENT, true)
	shot_type.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for label in [fault, out_text, zone, speed, shot_type]:
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		label.add_theme_constant_override("shadow_offset_y", 2)
	# Semi pixel art HUD: scores and call-outs in the pixel display font (hard shadow),
	# body/status text stays in the clean sans.
	for label in [score, _pill_label, fault, out_text, shot_type, speed, _serve_label, _locked_spin_label]:
		label.add_theme_font_override("font", UiTheme.pixel_font())
		UiTheme.crisp(label)
	# Legibility over any backdrop (light cement, the crowd, the shop sign): the floating
	# lines sit on dark pixel pills like the scoreboard, sized to their text.
	for label in [_serve_label, shot_type, speed, _locked_spin_label]:
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.add_theme_color_override("font_shadow_color", PixelDraw.SHADOW)
		label.add_theme_constant_override("shadow_offset_x", 0)
		label.add_theme_constant_override("shadow_offset_y", 2)
	fault.hide()
	out_text.hide()
	zone.hide()
	speed.modulate.a = 0.0
	shot_type.modulate.a = 0.0

func _build_singles_feedback() -> void:
	_serve_ball = preload("res://scripts/ui/scoreboard_ball.gd").new()
	_serve_ball.name = "ServingBall"
	add_child(_serve_ball)
	_rally_banner = _panel()
	_rally_banner.name = "RallyResult"
	# Kit banner (proposal PDF p.23-24): the PixelBanner child draws plate, headline and
	# ribbon; the panel is only the box scoreboard_ui fades. Old labels kept, never shown.
	_rally_banner.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_rally_headline = _label("", 34, Color("effa92"), true)
	_rally_detail = _label("", 17, UiTheme.INK, true)
	_rally_reason = _label("", 22, UiTheme.INK, true)
	for label in [_rally_headline, _rally_reason, _rally_detail]:
		remove_child(label)
		_rally_banner.add_child(label)
		label.hide()
	_rally_pixel = PixelBanner.new()
	_rally_pixel.name = "PixelBanner"
	_rally_banner.add_child(_rally_pixel)
	_rally_banner.hide()

func team_name(team: int) -> String:
	var game := get_parent()
	if game != null and game.get("doubles_mode") == true: return "Your team" if team == 0 else "Opponents"
	var pvp: bool = game != null and game.get("pvp_mode") == true
	return ("Blue" if team == 0 else "Red") if pvp else ("You" if team == 0 else "AI")

func _team_label_text(team: int) -> String:
	var game := get_parent()
	var pvp: bool = game != null and game.get("pvp_mode") == true
	var owner := ("P1" if team == 0 else "P2") if pvp else ("YOU" if team == 0 else "AI")
	if game != null and game.get("doubles_mode") == true: owner = "YOUR TEAM" if team == 0 else "OPPONENTS"
	return owner + ("\n" if _portrait else " · ") + ("BLUE" if team == 0 else "RED")

## headline_color is the banner's fill (team blue / red, gold for a second server).
func show_rally_result(headline: String, detail: String, headline_color: Color = UiTheme.TEAM_BLUE) -> void:
	_rally_headline.text = headline
	_rally_detail.text = detail
	# The reason (show_fault -> set_rally_reason) arrives BEFORE this call: keep it on
	# the ribbon; the detail line is only used when there is no reason.
	var has_reason: bool = not _rally_reason.text.is_empty()
	_rally_pixel.present(headline.to_upper(), _rally_reason.text.to_upper() if has_reason else detail.to_upper(),
		headline_color, _rally_reason_fill if has_reason else UiTheme.PANEL)
	_rally_banner.modulate.a = 1.0
	_rally_banner.visible = _gameplay_visible
	_place_rally_banner()
	PerfMonitor.note("rally_banner", {"headline": headline, "detail": detail, "ribbon": _rally_pixel.ribbon, "rect": [_rally_banner.position.x, _rally_banner.position.y, _rally_banner.size.x, _rally_banner.size.y], "board": [_board._scores[0], _board._scores[1]] if is_instance_valid(_board) else []})

## One banner for the whole result: the reason replaces the detail line on the ribbon
## (gold when it went your way, deep red when it didn't).
func set_rally_reason(text: String, color: Color) -> void:
	_rally_reason.text = text
	_rally_reason_fill = color
	_rally_pixel.set_ribbon(text.to_upper(), color)
	if _rally_banner.visible: _place_rally_banner()

## Keep the result banner clear of these screen rects (body_hit_fx.gd: the "Ouch!"
## bubble pops right after the banner, often over the far players at banner height).
func avoid_for_banner(rects: Array) -> void:
	_banner_avoid = rects
	if _rally_banner.visible: _place_rally_banner()

func clear_rally_result() -> void:
	_banner_avoid = []
	_rally_banner.hide()
	_rally_headline.text = ""
	_rally_detail.text = ""
	_rally_reason.text = ""

func _layout_singles_feedback() -> void:
	if not is_instance_valid(_serve_ball): return
	var rect := _score_panel.get_global_rect()
	var view := get_viewport().get_visible_rect().size
	var s := MobileLayout.scale_for(view) if _portrait else 1.0
	var ball_size := 46.0 * s if _portrait else 30.0
	var center := Vector2(rect.position.x + (50.0 * s if _server == 0 else rect.size.x - 50.0 * s), rect.position.y + (52.0 * s if _portrait else 84.0))
	_place(_serve_ball, Rect2(center - Vector2.ONE * ball_size * 0.5, Vector2.ONE * ball_size))
	_place_rally_banner()

func _place_rally_banner() -> void:
	if not is_instance_valid(_rally_banner) or not is_instance_valid(_score_panel): return
	var rect := _score_panel.get_global_rect()
	var view := get_viewport().get_visible_rect().size
	var s := MobileLayout.scale_for(view) if _portrait else 1.0
	_rally_pixel.s = s
	_rally_pixel.max_width = view.x - 32.0 * s
	_rally_pixel.resize_to_fit()
	var banner_size: Vector2 = _rally_pixel.size
	var top := rect.end.y + 198.0 * s if _portrait else view.y * 0.35 + 136.0
	# Sit in the middle of the screen with the bottom edge just above the net.
	var camera: Camera3D = get_viewport().get_camera_3d()
	var net_top := Vector3(0.0, PickleballConstants.FLOOR_Y + PickleballConstants.NET_HEIGHT, 0.0)
	if camera != null and not camera.is_position_behind(net_top):
		top = maxf(rect.end.y + 8.0 * s, camera.unproject_position(net_top).y - banner_size.y - 12.0 * s)
	var banner_x := (view.x - banner_size.x) * 0.5
	if not _portrait and view.x < 1100.0:
		banner_x = _status_panel.position.x + (_status_panel.size.x - banner_size.x) * 0.5
	# Step below anything it must not cover (a live "Ouch!" bubble).
	for avoid in _banner_avoid:
		if Rect2(Vector2(banner_x, top), banner_size).intersects(avoid):
			top = minf(avoid.end.y + 10.0 * s, view.y - banner_size.y - 8.0 * s)
	_place(_rally_banner, Rect2(Vector2(banner_x, top).round(), banner_size))
	_rally_pixel.position = Vector2.ZERO

func _build_toolbar() -> void :
	_toolbar = HBoxContainer.new()
	# Guide/Pause retain the rightmost slots as transient Skip appears or hides.
	_toolbar.alignment = BoxContainer.ALIGNMENT_END
	_toolbar.theme = UiTheme.create()
	_toolbar.add_theme_constant_override("separation", 8)
	add_child(_toolbar)
	for caption in ["Debug", "Skip", "Guide", "Pause"]:
		var button: = Button.new()
		button.text = caption
		button.custom_minimum_size.y = 44
		button.add_theme_font_size_override("font_size", 16)
		_toolbar.add_child(button)
		match caption:
			"Debug":
				_debug_button = button
				button.visible = debug_available
				button.tooltip_text = "Toggle debug tools · F3"
				button.pressed.connect(toggle_debug_mode)
			"Guide":
				_guide_button = button
				button.pressed.connect(_toggle_guide)
			"Skip":
				_skip_button = button
				button.name = "SkipRetrieval"
				button.hide()
				button.tooltip_text = "Skip ball retrieval"
				button.pressed.connect( func(): skip_retrieval_requested.emit())
			"Pause":
				_pause_button = button
				button.tooltip_text = "Pause match · Escape"
				button.pressed.connect( func(): pause_requested.emit())
		if caption in ["Guide", "Pause"]:
			var icon: = HudChrome.new()
			icon.kind = HudChrome.Kind.GUIDE if caption == "Guide" else HudChrome.Kind.PAUSE
			icon.hide()
			button.add_child(icon)
			_toolbar_icons.append(icon)
			var label: = Label.new()
			label.text = caption
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.hide()
			button.add_child(label)
			_toolbar_captions.append(label)
	# Quick Photo button: a small camera button beside the HIT pad on the touch layout (under
	# the toolbar's right end where there is no HIT pad), so one tap pauses the match and opens
	# photo mode. Shown with the gameplay HUD while Settings > Video > Photo button is on.
	_photo_button = Button.new()
	_photo_button.name = "QuickPhoto"
	_photo_button.icon = _camera_icon()
	_photo_button.expand_icon = true
	_photo_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_photo_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	_photo_button.theme = UiTheme.create()
	_photo_button.focus_mode = Control.FOCUS_NONE
	_photo_button.tooltip_text = "Pause and open photo mode"
	_photo_button.pressed.connect(func(): photo_requested.emit())
	add_child(_photo_button)
	# Rally replays (scripts/fx/photo_history.gd): REC above the camera saves every rally by
	# itself while it is on; while it is off, a SAVE RALLY? button comes up for a few seconds
	# after each point (Settings > Video > Ask to save rally).
	_rec_button = Button.new()
	_rec_button.name = "RallyRecord"
	_rec_button.text = "REC"
	_rec_button.theme = UiTheme.create()
	_rec_button.focus_mode = Control.FOCUS_NONE
	_rec_button.tooltip_text = "Save every rally (keeps the 10 newest)"
	_rec_button.pressed.connect(_toggle_rally_record)
	add_child(_rec_button)
	_save_rally_button = Button.new()
	_save_rally_button.name = "SaveRally"
	_save_rally_button.theme = UiTheme.create()
	_save_rally_button.focus_mode = Control.FOCUS_NONE
	_save_rally_button.visible = false
	_save_rally_button.pressed.connect(_save_rally_pressed)
	add_child(_save_rally_button)
	_toolbar.item_rect_changed.connect(_place_photo_button)
	get_viewport().size_changed.connect(func(): _place_photo_button.call_deferred())
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null and settings.has_signal("settings_changed"):
		settings.settings_changed.connect(func(key: String, _value: Variant) -> void:
			if key in ["video.photo_button", "video.rally_record"]: _place_photo_button())
	_place_photo_button.call_deferred()
	_debug_toolbar = GridContainer.new()
	_debug_toolbar.columns = 3
	_debug_toolbar.theme = UiTheme.create()
	_debug_toolbar.add_theme_constant_override("h_separation", 8)
	_debug_toolbar.add_theme_constant_override("v_separation", 8)
	_debug_toolbar.hide()
	add_child(_debug_toolbar)
	for caption in ["Edit poses", "Sound", "Launch", "Freeze", "Visuals", "Drop test"]:
		var tool: = Button.new()
		tool.text = caption
		tool.custom_minimum_size = Vector2(128, 48)
		tool.add_theme_font_size_override("font_size", 16)
		_debug_toolbar.add_child(tool)
		if caption == "Edit poses":
			_pose_button = tool
			tool.tooltip_text = "Edit stroke and body poses · F2"
			tool.pressed.connect( func(): pose_editor_requested.emit())
		else:
			tool.pressed.connect(_run_debug_tool.bind(caption))
	_guide = PanelContainer.new()
	_guide.theme = UiTheme.create()
	_guide.add_theme_stylebox_override("panel", UiTheme.panel_style())
	_guide.hide()
	add_child(_guide)
	_guide_scroll = ScrollContainer.new()
	_guide_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_guide.add_child(_guide_scroll)
	var content: = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	_guide_scroll.add_child(content)
	var title: = Label.new()
	title.text = "Make your next shot"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_font_override("font", _font_bold)
	content.add_child(title)
	var instructions: = Label.new()
	_guide_instructions = instructions
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.add_theme_font_size_override("font_size", 18)
	instructions.text = "SINGLES SCORING\nOnly the server can score. The ball in the scoreboard marks that player. Win a rally while receiving to get a Sideout: the serve changes, the score does not. Serve right at 0/even, left at odd. First to 11, win by 2.\n\nMOVE INTO REACH\nWASD / arrow keys move your player. Let the serve bounce before returning it.\n\nCHARGE & RELEASE\nHold Space to prepare and build power. Keep moving to reach the ball. When in reach, let go of directions to plant your feet. Then WASD / arrows move the landing marker left, right, short or deep. Release Space to lock the marker and swing. Movement returns at contact.\n\nSERVE PLACEMENT\nHold Space and use WASD / arrows to move the landing marker within the diagonal service box. [ / ] also aim left or right. R / F adjust the arc while holding Space.\n\nREAD THE CONTACT POINT\nPink: move into reach. Purple: load your swing. Blue: contact is close.\n\nEASY-MODE TIMING RING\nRelease Space as the outer ring meets the center. You still need to be within paddle reach.\n\nP  Camera     X  Difficulty     N  Indicators\nE / Q  Edit poses     M  Sound tuning\nEscape closes the active panel, then pauses."
	content.add_child(instructions)
	var close: = Button.new()
	close.text = "Back to game"
	close.custom_minimum_size.y = 44
	close.pressed.connect( func(): _guide.hide();get_viewport().gui_release_focus())
	content.add_child(close)

func _toggle_guide() -> void :
	if _desktop_guide_text.is_empty(): _desktop_guide_text = _guide_instructions.text
	_guide_instructions.text = "SINGLES SCORING\nOnly the server can score. The scoreboard ball marks that player. Win while receiving for a Sideout: serve changes, score stays. Right at 0/even, left at odd. First to 11, win by 2.\n\nMOVE & PREPARE\nDrag the left stick to move. Hold the right button to build power while getting into reach.\n\nAIM THE LANDING TARGET\nHold and drag HIT with your right thumb to move the landing target. The left stick always moves your player, including while aiming. Release HIT to lock your target and commit the swing; contact still depends on timing and reach.\n\nSERVE\nBefore serving, rotate the small middle wheel to choose a serve type. Hold HIT to charge and drag HIT to aim in the diagonal service box. Release HIT to commit the serve. The timing ring then counts down to paddle contact.\n\nSPIN & DROP\nHold Topspin, Slice or Drop outside the upper-left of HIT, drag to aim, then release to commit that shot. HIT prepares Flat. Each button uses the same charge and paddle-contact timing. Drop is for rallies; serves stay normal.\n\nCANCEL\nDrag into the separate CANCEL circle, then release to cancel. Drag out of CANCEL to resume aiming. Pause, backgrounding and opening a panel also cancel held touches safely.\n\nTIMING\nOn Easy, release as the ring reaches HIT. You still need to reach the incoming ball." if _portrait else _desktop_guide_text
	var game := get_parent()
	if game != null and game.get("doubles_mode") == true:
		var section_end := _guide_instructions.text.find("\n\n")
		var controls := _guide_instructions.text.substr(section_end) if section_end >= 0 else ""
		var target: int = game.doubles_state.target_score if "doubles_state" in game and game.doubles_state != null else 11
		_guide_instructions.text = "DOUBLES SCORING\nOnly the serving team scores. The call is serving score, receiving score, then server 1 or 2. Start at 0-0-2: the opening team has one server before the first sideout. After that, both teammates serve before a sideout. Follow the HUD for the server. Serve to the correct receiver in the diagonal service court. Let both the serve and its return bounce. First to %d, win by 2." % target + controls
	_guide.visible = not _guide.visible
	if _guide.visible:
		# A hidden PanelContainer can retain the older font minimum while the
		# viewport changes under Pause. Reapply after queued container updates.
		_layout_desktop.call_deferred()
		_guide_scroll.scroll_vertical = 0
	else:
		get_viewport().gui_release_focus()

func set_score(left: int, right: int) -> void :
	_blue_score = left
	_red_score = right
	score.text = "%d   :   %d" % [left, right]
	if is_instance_valid(_board): _board.set_scores(left, right)
	_refresh_pill()

## Corner pill text: serving score, receiving score, server number (e.g. 7-5-2).
## Only written when it changes.
func _refresh_pill() -> void :
	if _pill_label == null: return
	var game: = get_parent()
	var first: int = _server if _server in [0, 1] else 0
	var mine: int = _blue_score if first == 0 else _red_score
	var theirs: int = _red_score if first == 0 else _blue_score
	var text: = "%d-%d" % [mine, theirs]
	if game != null and game.get("doubles_mode") == true and game.get("doubles_state") != null:
		var ds = game.doubles_state
		mine = int(ds.scores[ds.serving_team])
		theirs = int(ds.scores[1 - ds.serving_team])
		text = "%d-%d-%d" % [mine, theirs, int(ds.server_number)]
		first = int(ds.serving_team)
	if _practice_exchange_context or _wall_context: text = score.text.replace("   ", "")
	_pill_chrome.first_team = first
	if is_instance_valid(_board):
		var doubles: bool = game != null and game.get("doubles_mode") == true and game.get("doubles_state") != null
		_board.set_server(_server if not doubles else int(game.doubles_state.serving_team), int(game.doubles_state.server_number) if doubles else 0)
		_board.set_names(_board_name(0), _board_name(1))
	if text != _pill_text:
		_pill_text = text
		_pill_label.text = text

func _board_name(team: int) -> String:
	if _wall_context: return "RET" if team == 0 else "TGT"
	var game := get_parent()
	if game != null and game.get("pvp_mode") == true: return "P1" if team == 0 else "P2"
	if game != null and game.get("doubles_mode") == true: return "YOU" if team == 0 else "OPP"
	return "YOU" if team == 0 else "AI"

## "right" / "left" service side for the current server, or "" when unknown.
func _serve_side_text(game: Node) -> String:
	if game == null: return ""
	if game.get("doubles_mode") == true and game.get("doubles_state") != null:
		var ds = game.doubles_state
		var court: int = int(ds.service_context().get("serving_court", -1))
		return "" if court < 0 else ("RIGHT" if court == ds.RIGHT else "LEFT")
	var points: int = int(game.get("score_left")) if _server == 0 else int(game.get("score_right"))
	return "RIGHT" if points % 2 == 0 else "LEFT"

func set_spin_selection(mode: String, locked_mode: String = "", intent: String = "AUTO", locked_intent: String = "") -> void :

	_selected_spin = mode.to_upper()
	if _selected_spin not in ["FLAT", "TOPSPIN", "SLICE"]:
		_selected_spin = "FLAT"
	_selected_intent = "DROP" if intent.to_upper() == "DROP" else "AUTO"
	var display_mode: = "DROP" if _selected_intent == "DROP" else _selected_spin
	var locked: = "DROP" if locked_intent.to_upper() == "DROP" else locked_mode.to_upper()
	_spin_locked = locked in ["FLAT", "TOPSPIN", "SLICE", "DROP"] and locked != display_mode
	_locked_display = locked
	_refresh_shot_label()
	if not _spin_enabled:
		_spin_enabled = true
		_pose_button.tooltip_text = "Edit stroke and body poses · F2"
		_guide_instructions.text = _guide_instructions.text.replace("E / Q  Edit poses", "Q  Cycle spin: Flat / Topspin / Slice\nE  Drop shot (rallies)     F2  Edit poses")
		_guide_instructions.text = _guide_instructions.text.replace("SERVE PLACEMENT", "DROP SHOTS\nE selects Drop for rallies. Aim the marker inside the kitchen. Q returns to Flat, then cycles spin. Serves stay normal.\n\nSERVE PLACEMENT")
		_layout_desktop()

func _refresh_shot_label() -> void :
	if _selected_intent == "DROP":
		_spin_label.text = "%s · DROP  [E]" % ("NEXT" if _spin_locked else "SHOT") if _rally_active else "DROP · RALLY  [E]"
	else:
		_spin_label.text = "%s · %s  [Q]" % ["NEXT" if _spin_locked else "SPIN", _selected_spin]
	_spin_label.visible = _gameplay_visible and not _portrait
	_locked_spin_label.text = "THIS SHOT · %s" % _locked_display if _spin_locked else ""
	_locked_spin_label.visible = _gameplay_visible and _spin_locked
	_fit_pill(_locked_spin_label)

func set_match_context(server: int, rally_active: bool) -> void :
	_apply_match_context(server, rally_active)
	_fit_pill(_serve_label)

func _apply_match_context(server: int, rally_active: bool) -> void :
	var game: = get_parent()
	var practice: bool = game != null and game.has_method("_is_practice") and game._is_practice()
	_match_label.text = "PRACTICE %s · NO SCORE" % game.practice_launcher.drill_mode if practice else "SINGLES  /  FIRST TO 11"
	if not practice and game != null and game.get("doubles_mode") == true: _match_label.text = "DOUBLES  /  FIRST TO 11"
	var complete: bool = game != null and game.get("match_over") == true
	var old_server := _server
	_server = server
	_serve_ball.visible = _gameplay_visible and not practice and not complete and server in [0, 1] and not _portrait
	_score_chrome.serving_team = server if _serve_ball.visible else -1
	_serve_ball.tooltip_text = "%s serving · only the server can score" % team_name(server)
	if old_server != server: _layout_singles_feedback()
	_blue_label.text = _team_label_text(0)
	_red_label.text = _team_label_text(1)
	var wall: bool = practice and game.practice_launcher.is_wall()
	if wall:
		_wall_context = true
		_practice_exchange_context = true
		_match_label.text = "WALL PRACTICE · SOLO"
		_blue_label.text = "RETURNS"
		_red_label.text = "TARGETS"
		score.text = "%d   :   %d" % [game.practice_launcher.wall_practice.returns, game.practice_launcher.wall_practice.targets]
		if is_instance_valid(_board): _board.set_scores(game.practice_launcher.wall_practice.returns, game.practice_launcher.wall_practice.targets)
		_refresh_pill()
		_serve_label.text = "SOLO · NO SCORE"
		_serve_label.add_theme_color_override("font_color", UiTheme.MUTED)
		difficulty.visible = false
		return
	if _wall_context:
		_wall_context = false
		_blue_label.text = _team_label_text(0)
		_red_label.text = _team_label_text(1)
	if _practice_exchange_context: score.text = "%d   :   %d" % [_blue_score, _red_score]
	var exchange: bool = practice and game.practice_launcher.is_exchange()
	if exchange:
		_practice_exchange_context = true
		_server = server
		_rally_active = rally_active
		_serve_label.text = "OPENING BOUNCES COMPLETE"
		_serve_label.add_theme_color_override("font_color", UiTheme.MUTED)
		return
	_practice_exchange_context = false
	_server = server
	_rally_active = rally_active
	if _spin_enabled: _refresh_shot_label()
	var owner := team_name(server).to_upper()
	_serve_label.text = "%s SERVE · CAN SCORE" % owner
	if not practice and game != null and game.get("doubles_mode") == true:
		_serve_label.text = "%s SERVE · %s" % [game.actor_label(game.get_server_actor()).to_upper(), game.doubles_state.score_call()]
	var side: = _serve_side_text(game) if not practice else ""
	if not side.is_empty():
		if _portrait:
			var who: String = game.actor_label(game.get_server_actor()).to_upper() if game.get("doubles_mode") == true else team_name(server).to_upper()
			_serve_label.text = "%s %s · %s SIDE" % [who, "SERVE" if who == "YOU" else "SERVES", side]
		else:
			_serve_label.text += " · %s" % side
	_serve_label.add_theme_color_override("font_color", UiTheme.BLUE if server == 0 else UiTheme.RED)
	if practice: _serve_label.text = "PRACTICE · NO SCORE"
	if complete: _serve_label.text = "MATCH OVER"
	_refresh_pill()

func set_status_text(value: String) -> void :
	var display: = value
	if _portrait:
		display = display.replace("SPACE", "HIT").replace("Space", "Hit")
		if _between_point_active: display = display.replace("Hit to skip", "tap Skip").replace("HIT to skip", "tap Skip")
		var game: = get_parent()
		if game and game.get("game_state") == 0 and game.human_may_serve() and not game._is_practice():
			display = "Aim the target · release HIT to serve" if _charging else "Your serve · hold HIT to charge"
		elif display.begins_with("PRACTICE ") and display.contains("\n"):
			display = display.substr(display.find("\n") + 1).get_slice("\n", 0)
		var practice = _active_exchange_practice()
		if practice:
			var mode: String = "Attack" if practice.allow_attacks else ("Hands" if practice.drill_mode == "HANDS" else "Dink")
			var owner: String = "demo" if practice.demo_enabled else "drill"
			display = "%s %s · %d hits · best %d" % [mode, owner, practice.exchange_count, practice.best_exchange_count]
			if practice._attempt_finished: display = "%s · %d hits" % [practice.last_failure.replace("_", " ").capitalize(), practice.exchange_count]
		state.max_lines_visible = 1
		state.autowrap_mode = TextServer.AUTOWRAP_OFF if practice else TextServer.AUTOWRAP_WORD_SMART
	state.text = display

func set_charge(ratio: float, charging: bool) -> void :
	_charging = charging
	_charge_bar.value = clampf(ratio, 0.0, 1.0)
	var intent_label: = "DROP TOUCH" if _selected_intent == "DROP" and _rally_active else "POWER"
	_charge_label.text = "%s  %d%%  ·  RELEASE SPACE" % [intent_label, roundi(_charge_bar.value * 100.0)] if charging else "HOLD SPACE TO BUILD POWER"
	if not charging and intent_label == "DROP TOUCH":
		_charge_label.text = "HOLD SPACE TO PREPARE DROP"
	if _portrait:
		_charge_label.text = "%s · %d%%" % [intent_label, roundi(_charge_bar.value * 100.0)] if charging else "HOLD A SHOT · DRAG TO AIM"
		var game: = get_parent()
		if not charging and game and game.get("game_state") == 0 and game.get("serving_team") == 0:
			_charge_label.text = "ROTATE SERVE WHEEL · HOLD HIT" if game.game_serve and game.game_serve.has_method("get_serve_style_options") else "HOLD HIT TO CHARGE"
		elif not charging and game and game.get("game_state") == 1:
			_charge_label.text = "SERVE LOCKED · WATCH CONTACT RING"
	var owner_game = get_parent()
	if charging and owner_game and "aim_focus" in owner_game and owner_game.aim_focus and owner_game.aim_focus.holding:
		var focus = owner_game.aim_focus
		var short_intent: String = "DROP" if intent_label == "DROP TOUCH" else "POWER"
		if focus.active:
			var remaining: float = maxf(0.0, float(focus.deadline_usec - Time.get_ticks_usec()) / 1000000.0)
			_charge_label.text = "FOCUS %.1fs · %s %d%%" % [remaining, short_intent, roundi(_charge_bar.value * 100.0)]
		elif focus.exhausted:
			_charge_label.text = "REAL TIME · %s %d%%" % [short_intent, roundi(_charge_bar.value * 100.0)]
	_charge_label.add_theme_color_override("font_color", UiTheme.ACCENT if charging else UiTheme.MUTED)
	_charge_bar.modulate.a = (1.0 if charging else 0.45) if SHOW_STATUS_BOX or not _portrait else 0.0
	var practice = _active_exchange_practice()
	var demo: bool = practice != null and practice.demo_enabled
	if demo:
		_demo_guidance_active = true
		_charge_label.text = DEMO_CUES.get(practice.last_response_kind, "Watch the ball and footwork") if practice.allow_attacks else ("Compact blocks · legal feet" if practice.drill_mode == "HANDS" else "Bounce · low contact · recover")
		_charge_label.add_theme_color_override("font_color", UiTheme.MUTED)
		_charge_bar.hide()
		_controls_hint.text = "Pause · repeat or switch drill"
	elif _demo_guidance_active:
		_demo_guidance_active = false
		_charge_bar.visible = _gameplay_visible and not _between_point_active
		set_aim_state(_aim_mode)

func set_end_change_pending(pending: bool) -> void:
	var next_text: String = "Changing ends" if pending else "SKIP >>"
	var text_changed: bool = _skip_button.text != next_text
	_skip_button.disabled = pending
	_skip_button.text = next_text
	_skip_button.tooltip_text = "Players must finish walking to the other end. Pause or reset remains available." if pending else ""
	if text_changed: _layout_desktop()

## A small pixel camera: body, viewfinder bump, lens with a highlight (16 x 13, drawn once).
static var _camera_texture: ImageTexture = null
static func _camera_icon() -> Texture2D:
	if _camera_texture != null: return _camera_texture
	var light := Color(0.95, 0.97, 1.0)
	var dark := Color(0.09, 0.14, 0.2)
	var image := Image.create_empty(16, 13, false, Image.FORMAT_RGBA8)
	for y in 13:
		for x in 16:
			var c := Color(0, 0, 0, 0)
			if y <= 1 and x >= 5 and x <= 9: c = light            # viewfinder bump
			elif y >= 2: c = light                                 # body
			var lens: float = Vector2(x - 7.5, y - 7.5).length()
			if lens <= 3.4: c = dark                               # lens
			if lens <= 1.2: c = light                              # its highlight
			if y == 4 and x >= 12 and x <= 13: c = dark            # flash window
			image.set_pixel(x, y, c)
	_camera_texture = ImageTexture.create_from_image(image)
	return _camera_texture

## On the touch layout: above and to the right of the HIT pad, outside its touch circle and
## its timing ring's start. Otherwise under the toolbar's right end.
func _place_photo_button() -> void:
	if _photo_button == null or _toolbar == null: return
	var settings: Node = get_node_or_null("/root/Settings")
	var wanted: bool = bool(settings.call("get_value", "video.photo_button", true)) if settings != null and settings.has_method("get_value") else true
	_photo_button.visible = wanted and _gameplay_visible
	if not _photo_button.visible:
		if _rec_button != null: _rec_button.visible = false
		if _save_rally_button != null: _save_rally_button.visible = false
		return
	var game: Node = get_parent()
	# The touch controls hand taps on these buttons over (mobile_controls._toolbar_at_point).
	if game != null and "extra_touch_buttons" in game and not game.extra_touch_buttons.has(_photo_button): game.extra_touch_buttons.append(_photo_button)
	var touch = game.get("mobile_controls") if game != null else null
	var size: Vector2
	var at: Vector2
	if touch != null and is_instance_valid(touch) and bool(touch.get("enabled")):
		var pad: Vector2 = touch.get("_charge_center")
		var reach: float = float(touch.get("_charge_radius"))
		size = Vector2.ONE * roundf(reach * 1.0)
		at = pad + Vector2(reach * 0.75, -reach * 1.95) - size * 0.5
		at.x = minf(at.x, get_viewport().get_visible_rect().size.x - size.x - 4.0)
	else:
		var bar: Rect2 = _toolbar.get_global_rect()
		var like: Vector2 = _pause_button.size if _pause_button != null and _pause_button.size.x > 1.0 else Vector2(100, 44)
		size = Vector2(maxf(roundf(like.y * 1.2), 48.0), like.y)
		at = Vector2(bar.end.x - size.x, bar.end.y + maxf(roundf(like.y * 0.08), 4.0))
	_photo_button.custom_minimum_size = size
	_photo_button.size = size
	_photo_button.global_position = at.round()
	# REC sits above the camera, the save question to their left.
	var recording: bool = bool(settings.call("get_value", "video.rally_record", false)) if settings != null and settings.has_method("get_value") else false
	var gap: float = maxf(roundf(size.y * 0.12), 4.0)
	_rec_button.visible = true
	_rec_button.custom_minimum_size = Vector2(size.x, roundf(size.y * 0.62))
	_rec_button.size = _rec_button.custom_minimum_size
	_rec_button.global_position = (at - Vector2(0.0, _rec_button.size.y + gap)).round()
	_rec_button.add_theme_font_size_override("font_size", maxi(roundi(_rec_button.size.y * 0.42), 12))
	var rec_color: Color = Color(1.0, 0.32, 0.28) if recording else Color(0.95, 0.97, 1.0, 0.7)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]: _rec_button.add_theme_color_override(state, rec_color)
	_save_rally_button.custom_minimum_size = Vector2(roundf(size.x * 2.7), _rec_button.size.y)
	_save_rally_button.size = _save_rally_button.custom_minimum_size
	_save_rally_button.global_position = (_rec_button.global_position - Vector2(_save_rally_button.size.x + gap, 0.0)).round()
	_save_rally_button.add_theme_font_size_override("font_size", maxi(roundi(_rec_button.size.y * 0.38), 12))
	for button in [_rec_button, _save_rally_button]:
		if game != null and "extra_touch_buttons" in game and not game.extra_touch_buttons.has(button): game.extra_touch_buttons.append(button)

func _toggle_rally_record() -> void:
	var settings: Node = get_node_or_null("/root/Settings")
	if settings == null or not settings.has_method("set_value"): return
	settings.call("set_value", "video.rally_record", not bool(settings.call("get_value", "video.rally_record", false)))
	_place_photo_button()

## A rally just ended (photo_history.gd rally_ready). REC on: save it and say so. REC off: ask,
## for a few seconds, without stopping anything.
func on_rally_ready(seconds: float) -> void:
	var settings: Node = get_node_or_null("/root/Settings")
	var history: Node = get_parent().get("photo_history") if get_parent() != null else null
	if settings == null or history == null or _save_rally_button == null: return
	var recording: bool = bool(settings.call("get_value", "video.rally_record", false))
	if recording:
		_show_rally_note("RALLY SAVED" if history.save_last_rally() else "NOT SAVED", 1.6, true)
	elif bool(settings.call("get_value", "video.rally_prompt", true)) and _gameplay_visible:
		_show_rally_note("SAVE RALLY?  %.0f s" % seconds, 6.0, false)

func _show_rally_note(text: String, seconds: float, done: bool) -> void:
	_save_rally_token += 1
	var token: int = _save_rally_token
	_save_rally_button.text = text
	_save_rally_button.disabled = done
	_save_rally_button.visible = true
	_place_photo_button()
	_save_rally_button.visible = true
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if token == _save_rally_token and is_instance_valid(_save_rally_button): _save_rally_button.visible = false)

func _save_rally_pressed() -> void:
	var history: Node = get_parent().get("photo_history") if get_parent() != null else null
	if history == null: return
	_show_rally_note("RALLY SAVED" if history.save_last_rally() else "NOT SAVED", 1.6, true)

func set_between_point_active(active: bool) -> void :
	_between_point_active = active
	_guidance_chrome.guidance_details = not active
	_skip_button.visible = active and _gameplay_visible
	for control in [_charge_label, _charge_bar, _controls_hint]: control.visible = _gameplay_visible and not active
	if active: _locked_spin_label.hide()
	_layout_desktop()

func set_gameplay_elements_visible(p_visible: bool) -> void :
	_gameplay_visible = p_visible
	_skip_button.visible = p_visible and _between_point_active
	_place_photo_button()
	_debug_toolbar.visible = p_visible and debug_mode
	_spin_label.visible = p_visible and _spin_enabled and not _portrait
	_locked_spin_label.visible = p_visible and _spin_locked
	for widget in [_score_panel, _status_panel, score, state, difficulty, _toolbar, _match_label, _blue_label, _red_label, _serve_label, _controls_hint, _charge_label, _charge_bar, hittable_dot]:
		widget.visible = p_visible
	if _portrait:
		_status_panel.hide()
		difficulty.hide()
	_guidance_chrome.visible = p_visible and _portrait
	if _between_point_active:
		for control in [_charge_label, _charge_bar, _controls_hint, _locked_spin_label]: control.hide()
	set_match_context(_server, _rally_active)
	_apply_score_surface()
	if not p_visible:
		clear_rally_result()
		_guide.hide()
		for label in [fault, out_text, zone, speed, shot_type, posture_debug, debug, freeze_indicator]:
			label.hide()
	else:
		speed.show()
		shot_type.show()

## Portrait shows one score surface (the corner pill): the big score, team and match
## labels and the singles serving ball stay hidden. Landscape keeps the desktop panel.
func _apply_score_surface() -> void :
	# The LED board is the score surface in both layouts; the pill text and the big
	# score label stay hidden (the panel keeps its rect for banner placement).
	_pill_label.visible = false
	_pill_chrome.visible = false
	if is_instance_valid(_board): _board.visible = _gameplay_visible
	_score_panel.self_modulate.a = 0.0 if _portrait else 1.0
	_serve_label.visible = _gameplay_visible
	score.visible = false
	for widget in [_match_label, _blue_label, _red_label]:
		widget.visible = _gameplay_visible and not _portrait
	if is_instance_valid(_serve_ball) and _portrait: _serve_ball.hide()

func _place(control: Control, rect: Rect2) -> void :
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = rect.position
	control.size = rect.size

## A pill label's region (layout only); the pill is fitted to the current text inside it.
func _set_pill_region(label: Label, region: Rect2) -> void:
	_pill_regions[label] = region
	_fit_pill(label)

## Sets a pill label's text and refits its pill; nothing happens when the text is unchanged.
func set_pill_text(label: Label, text: String) -> void:
	if label.text == text: return
	label.text = text
	_fit_pill(label)

## Size the pill to its text (never wider than its region) and align it in the region.
## Runs on text or layout changes only, never per frame.
func _fit_pill(label: Label) -> void:
	if not _pill_regions.has(label): return
	var region: Rect2 = _pill_regions[label]
	var style: StyleBox = label.get_theme_stylebox("normal")
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	var margins: Vector2 = style.get_minimum_size()
	var width: float = minf(ceilf(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + margins.x), region.size.x)
	var left: float = region.position.x
	if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT: left = region.end.x - width
	elif label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER: left = region.position.x + (region.size.x - width) * 0.5
	_place(label, Rect2(Vector2(left, region.position.y).round(), Vector2(width, font.get_height(font_size) + margins.y)))

## Pills scale with the layout: margins and pixel unit follow the mobile scale. Landscape
## keeps the serve line inside its dark score panel (no pill of its own).
var _pill_scale: = -1.0
var _serve_pill: = false
func _style_pills(s: float, serve_pill: bool) -> void:
	var rescale: bool = not is_equal_approx(s, _pill_scale)
	if rescale:
		_pill_scale = s
		for label in [shot_type, speed, _locked_spin_label]:
			label.add_theme_stylebox_override("normal", PixelStyle.label_pill(s))
	if rescale or serve_pill != _serve_pill:
		_serve_pill = serve_pill
		_serve_label.add_theme_stylebox_override("normal", PixelStyle.label_pill(s) if serve_pill else StyleBoxEmpty.new())
		if not serve_pill: _pill_regions.erase(_serve_label)

func _layout_desktop() -> void :
	if not is_instance_valid(_toolbar): return
	var viewport_size: = get_viewport().get_visible_rect().size
	_portrait = MobileLayout.is_portrait(viewport_size)
	if _portrait:
		_layout_portrait(viewport_size)
		_layout_singles_feedback()
		return
	_restore_desktop_fonts()
	for control in [_guidance_chrome, state, _charge_label, _charge_bar, _controls_hint, hittable_dot]: control.modulate.a = 1.0   # landscape keeps its status panel
	var width: = viewport_size.x
	var height: = viewport_size.y
	var margin: = 20.0 if width >= 900.0 else 12.0
	var compact: = width < 900.0
	var score_width: = 300.0 if compact else 328.0
	_place(_score_panel, Rect2(margin, margin, score_width, 142))
	_place(_match_label, Rect2(margin + 18, margin + 12, score_width - 36, 20))
	_place(_blue_label, Rect2(margin + 22, margin + 38, 138, 22))
	_place(_red_label, Rect2(margin + score_width - 160, margin + 38, 138, 22))
	_place(score, Rect2(margin + 20, margin + 55, score_width - 40, 55))
	if is_instance_valid(_board): _place(_board, Rect2(margin + 20, margin + 58, score_width - 40, 54))
	_style_pills(1.0, false)
	_place(_serve_label, Rect2(margin + 16, margin + 113, score_width - 32, 20))
	_place(difficulty, Rect2(margin + 4, margin + 150, 270, 26))
	_place(_spin_label, Rect2(margin + 4, margin + 179, 300, 26))
	_locked_spin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_set_pill_region(_locked_spin_label, Rect2(margin + 4, margin + 206, 300, 36))
	var toolbar_width: = 440.0 if _between_point_active else 330.0
	_place(_toolbar, Rect2(width - margin - toolbar_width, margin, toolbar_width, 44))
	_place(_debug_toolbar, Rect2(width - margin - 430, margin + 56, 430, 104))
	_set_pill_region(speed, Rect2(width - margin - 260, margin + 58, 260, 36))
	_place(hittable_dot, Rect2(width - margin - 12, margin + 98, 12, 12))
	if width < 1100:
		shot_type.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_set_pill_region(shot_type, Rect2(width - margin - 320, margin + 114, 320, 36))
	else:
		shot_type.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_set_pill_region(shot_type, Rect2(width * 0.5 - 160, margin + 70, 320, 36))
	_place(freeze_indicator, Rect2(margin + 4, margin + (231 if _spin_enabled else 185), 280, 28))
	var status_width: = minf(720.0, width - margin * 2.0 - 265.0)
	status_width = maxf(status_width, 300.0)
	var status_height: = 152.0 if compact else 142.0
	var status_top: = height - margin - status_height
	_place(_status_panel, Rect2(margin, status_top, status_width, status_height))
	_place(state, Rect2(margin + 18, status_top + 10, status_width - 36, 60))
	state.add_theme_font_size_override("font_size", 18 if compact else 21)
	_place(_charge_label, Rect2(margin + 18, status_top + 76, status_width - 36, 20))
	_place(_charge_bar, Rect2(margin + 18, status_top + 103, status_width - 36, 6))
	_place(_controls_hint, Rect2(margin + 18, status_top + status_height - 27, status_width - 36, 20))
	_controls_hint.text = "WASD  Move    SPACE  Hit    ESC  Pause" if status_width < 560 else "WASD / arrows  Move     SPACE  Hold & release     ESC  Pause"
	if _spin_enabled:
		_controls_hint.text = "WASD  Move    SPACE  Hit    Q  Spin    E  Drop" if status_width < 650 else "WASD / arrows  Move    SPACE  Hit    Q  Spin    E  Drop    ESC  Pause"
	set_aim_state(_aim_mode)
	_controls_hint.add_theme_font_size_override("font_size", 12 if compact else 14)
	_place(fault, Rect2(width * 0.16, height * 0.35, width * 0.68, 130))
	_place(out_text, Rect2(width * 0.25, height * 0.24, width * 0.5, 82))
	_place(zone, Rect2(margin, status_top - 40, status_width, 30))
	_place(debug, Rect2(margin, status_top - 160, status_width, 110))
	_place(posture_debug, Rect2(width - 420 - margin, margin + 120, 420, 150))
	var guide_width: = minf(480.0, width - margin * 2.0)
	_place(_guide, Rect2(width - margin - guide_width, margin + 56, guide_width, minf(680, height - margin * 2.0 - 56)))
	_layout_singles_feedback()


func set_aim_state(mode: String) -> void :
	_aim_mode = mode
	if not is_instance_valid(_controls_hint): return
	var practice = _active_exchange_practice()
	if practice != null and practice.demo_enabled:
		_controls_hint.text = "Pause · repeat or switch drill"
		_controls_hint.add_theme_color_override("font_color", UiTheme.MUTED)
		return
	match mode:
		"AIM": _controls_hint.text = "AIM  ·  WASD / arrows move target  ·  Release SPACE"
		"LOCKED": _controls_hint.text = "LOCKED  ·  Target set  ·  Movement returns at contact"
		"PREPARE": _controls_hint.text = "MOVE  ·  Reach ball, then let go of directions to AIM"
		"SERVE": _controls_hint.text = "MOVE  ·  Hold SPACE to plant & aim  ·  [ / ] also aim"
		_: _controls_hint.text = "MOVE  ·  WASD / arrows  ·  Hold SPACE to prepare  ·  Q Spin  E Drop"
	if _portrait:
		match mode:
			"AIM": _controls_hint.text = "AIM · drag HIT sets target · left stick moves"
			"LOCKED": _controls_hint.text = "LOCKED · target set until contact"
			"PREPARE": _controls_hint.text = "MOVE · left stick moves · drag HIT to aim"
			"SERVE": _controls_hint.text = "SERVE · hold and drag HIT to aim"
			_: _controls_hint.text = "MOVE · left stick   HIT · hold & release"
	var focus_game = get_parent()
	if mode == "AIM" and focus_game and "aim_focus" in focus_game and focus_game.aim_focus and focus_game.aim_focus.active:
		var preview_hint: String = focus_game.aim_focus.preview_hint
		_controls_hint.text = "AIM · estimated arc · release HIT" if _portrait else "AIM · estimated arc · release SPACE"
		if preview_hint != "ESTIMATED ARC":
			_controls_hint.text = preview_hint + " · adjust aim"
			_controls_hint.add_theme_color_override("font_color", UiTheme.RED)
			return
	_controls_hint.add_theme_color_override("font_color", UiTheme.ACCENT if mode == "AIM" else UiTheme.MUTED)


func toggle_debug_mode() -> void :
	set_debug_mode( not debug_mode)

func set_debug_mode(value: bool) -> void :
	debug_mode = value and debug_available and not _portrait and RuntimePolicy.developer_tools
	_debug_button.text = "Debug"
	_debug_button.modulate = UiTheme.ACCENT if debug_mode else Color.WHITE
	_debug_toolbar.visible = debug_mode and _gameplay_visible
	if not debug_mode:
		var game: = get_parent()
		if game.has_method("_set_debug_visuals_visible"): game._set_debug_visuals_visible(false)

func _run_debug_tool(caption: String) -> void :
	if not debug_mode: return
	var game: = get_parent()
	match caption:
		"Sound": game._toggle_sound_panel()
		"Launch": game.practice_launcher.launch_ball()
		"Freeze": game._toggle_ball_freeze()
		"Visuals": game._cycle_debug_visuals()
		"Drop test": game._start_drop_test()

func _restore_desktop_fonts() -> void :
	_toolbar.add_theme_constant_override("separation", 8)
	_skip_button.clip_text = false
	for key in TOOLBAR_STYLE_KEYS: _skip_button.remove_theme_stylebox_override(key)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]: _skip_button.remove_theme_color_override(state)
	_score_panel.modulate.a = 1.0
	_score_panel.add_theme_stylebox_override("panel", UiTheme.panel_style())
	_score_chrome.hide()
	_guidance_chrome.hide()
	_apply_score_surface()
	_serve_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blue_label.text = _team_label_text(0)
	_red_label.text = _team_label_text(1)
	_blue_label.add_theme_color_override("font_color", UiTheme.BLUE)
	_red_label.add_theme_color_override("font_color", UiTheme.RED)
	_guide_button.text = "Guide"
	_pause_button.text = "Pause"
	for icon in _toolbar_icons: icon.hide()
	for caption in _toolbar_captions: caption.hide()
	state.max_lines_visible = -1
	_controls_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	_controls_hint.max_lines_visible = -1
	_charge_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_charge_label.max_lines_visible = -1
	_debug_button.visible = debug_available
	_status_panel.visible = _gameplay_visible
	difficulty.visible = _gameplay_visible
	_spin_label.visible = _gameplay_visible and _spin_enabled
	for button in _toolbar.get_children():
		for style in TOOLBAR_STYLE_KEYS: button.remove_theme_stylebox_override(style)
	_toolbar_pixel_scale = -1.0
	_guide_instructions.add_theme_font_size_override("font_size", 18)
	var guide_content: VBoxContainer = _guide_scroll.get_child(0)
	guide_content.get_child(0).add_theme_font_size_override("font_size", 26)
	var guide_close: Button = guide_content.get_child(guide_content.get_child_count() - 1)
	guide_close.custom_minimum_size.y = 44
	guide_close.add_theme_font_size_override("font_size", 20)
	for pair in [[score, 40], [_match_label, 13], [_blue_label, 14], [_red_label, 14], [_serve_label, 13], [difficulty, 16], [_spin_label, 16], [_locked_spin_label, 18], [_charge_label, 12], [fault, 34], [out_text, 58], [speed, 18], [shot_type, 18]]:
		pair[0].add_theme_font_size_override("font_size", pair[1])
	for button in _toolbar.get_children():
		button.custom_minimum_size = Vector2(0, 44)
		button.add_theme_font_size_override("font_size", 16)

## Portrait toolbar in the kit's pixel style, like the on-screen pads: Guide / Pause are
## pixel discs (navy, bevel, one-UI-pixel rim; blue rim when touched, face sinks one UI
## pixel), Skip a lime stair-cornered plate. Only the drawing: the content margins are the
## old ones, so every button keeps its size, place and touch rect. Built once per scale.
var _toolbar_pixel_scale: = -1.0
func _style_toolbar_pixels(s: float) -> void:
	if is_equal_approx(s, _toolbar_pixel_scale): return
	_toolbar_pixel_scale = s
	var u: float = PixelDraw.unit(s)
	for button in _toolbar.get_children():
		UiTheme.crisp(button)
		for key in TOOLBAR_STYLE_KEYS:
			var touched: bool = key != "normal" and key != "disabled"
			var style   # pixel_style_box.gd
			if button == _skip_button:
				# Skip is the one action on this row and only shows between points: lime
				# with dark ink and larger text, so it reads at a glance.
				var lime: Color = UiTheme.ACCENT if key == "normal" else (UiTheme.ACCENT_HOVER if key == "hover" else UiTheme.ACCENT.darkened(0.08))
				style = PixelStyle.plate(UiTheme.SURFACE_PRESSED if key == "disabled" else lime, s, 2)
			else:
				style = PixelStyle.round_button(Color(UiTheme.PANEL, 1.0 if touched else 0.94), s, UiTheme.BLUE if touched else UiTheme.BORDER)
			style.inset = Vector2(4 * s, 0)
			style.drop = u if key in ["pressed", "hover_pressed"] else 0.0
			PixelStyle.set_margins(style, 16 * s, 10 * s, 16 * s, 10 * s)
			button.add_theme_stylebox_override(key, style)

func _layout_portrait(viewport_size: Vector2) -> void :
	var safe: = MobileLayout.safe_rect(get_viewport())
	var s: = MobileLayout.scale_for(viewport_size)
	var x: = safe.position.x + 16 * s
	var y: = safe.position.y + 12 * s
	var w: = safe.size.x - 32 * s
	_score_panel.modulate.a = 1.0
	_score_panel.add_theme_stylebox_override("panel", UiTheme.pill_style(s))
	_score_chrome.hide()
	_apply_score_surface()
	_guidance_chrome.visible = _gameplay_visible
	_status_panel.hide()
	difficulty.hide()
	_spin_label.hide()
	_debug_button.hide()
	_debug_toolbar.hide()
	debug_mode = false
	# Corner pill (top-left) with the server line under it; the rest of the top is court.
	var pill_w: float = 300 * s
	var pill_h: float = 92 * s
	_place(_score_panel, Rect2(x, y, pill_w, pill_h))
	if is_instance_valid(_board): _place(_board, Rect2(x, y, pill_w, pill_h))
	_place(_pill_label, Rect2(x + 40 * s, y + 4 * s, pill_w - 80 * s, pill_h - 10 * s))
	_pill_label.add_theme_font_size_override("font_size", maxi(12, roundi(34 * s)))
	_place(_match_label, Rect2(x + w * 0.28, y + 10 * s, w * 0.44, 20 * s))
	_blue_label.text = _team_label_text(0)
	_red_label.text = _team_label_text(1)
	_blue_label.add_theme_color_override("font_color", Color("80ceff"))
	_red_label.add_theme_color_override("font_color", Color("ff8392"))
	_place(_blue_label, Rect2(x + 86 * s, y + 29 * s, 100 * s, 58 * s))
	_place(_red_label, Rect2(x + w - 220 * s, y + 29 * s, 134 * s, 58 * s))
	_place(score, Rect2(x + w * 0.28, y + 27 * s, w * 0.44, 50 * s))
	_serve_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toolbar.add_theme_constant_override("separation", maxi(1, roundi(8 * s)))
	for button in _toolbar.get_children():
		button.custom_minimum_size = Vector2(ceilf(100 * s), ceilf(92 * s))
		button.add_theme_font_size_override("font_size", roundi(21 * s))
	_style_toolbar_pixels(s)
	_guide_button.text = ""
	_pause_button.text = ""
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		_skip_button.add_theme_color_override(state, UiTheme.PANEL)
	_skip_button.add_theme_font_size_override("font_size", roundi(27 * s))
	# Size from the actual text/style minimum, then anchor the whole row inside
	# the safe area. A long translation may ellipsize instead of pushing Pause
	# or Skip offscreen; both retain their full touch target and original action.
	var gap: float = _toolbar.get_theme_constant("separation")
	var skip_text_width: float = _skip_button.get_theme_font("font").get_string_size(
		_skip_button.tr(_skip_button.text), HORIZONTAL_ALIGNMENT_LEFT, -1,
		_skip_button.get_theme_font_size("font_size")).x
	# The row shares the top edge with the score pill, so Skip may only grow into the gap.
	var skip_room: float = w - pill_w - 2 * ceilf(100 * s) - 3 * gap - 8 * s
	var skip_width: float = ceilf(clampf(skip_text_width + 32 * s, 100 * s, maxf(100 * s, skip_room)))
	_skip_button.clip_text = true
	_skip_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_skip_button.custom_minimum_size.x = skip_width
	var toolbar_width: float = 2 * ceilf(100 * s) + gap
	if _between_point_active: toolbar_width += skip_width + gap
	var guidance_width: float = w - toolbar_width - 14 * s
	var caption_width: float = guidance_width - 78 * s
	# BoxContainer rounds child offsets. Snap its origin too so fractional
	# mobile scales cannot move the same button by a subpixel when Skip hides.
	# Top-right corner, level with the score pill in the top-left corner.
	_place(_toolbar, Rect2(Vector2(x + w - toolbar_width, y).round(), Vector2(toolbar_width, ceilf(pill_h))))
	for icon in _toolbar_icons:
		_place(icon, Rect2(23 * s, 19 * s, 54 * s, 54 * s))
		icon.show()
	for caption in _toolbar_captions:
		caption.hide()
		_place(caption, Rect2(4 * s, 55 * s, 92 * s, 29 * s))
		# Authored units preserve this small portrait improvement on high-DPI phones.
		caption.add_theme_font_size_override("font_size", maxi(roundi(21 * s), floori(23 * s)))


	_place(_status_panel, Rect2(x, y + 112 * s, guidance_width, 148 * s))
	_place(_guidance_chrome, _status_panel.get_rect())
	# Archived (user's call): the portrait corner status box (guidance icons, state
	# line, charge text/bar, controls hint) distracted from play. Kept, not drawn:
	# alpha 0 so other code toggling visibility cannot bring it back.
	for control in [_guidance_chrome, state, _charge_label, _charge_bar, _controls_hint]:
		control.modulate.a = 1.0 if SHOW_STATUS_BOX else 0.0
	_place(state, Rect2(x + 64 * s, y + 116 * s, caption_width, 41 * s))
	_place(_charge_label, Rect2(x + 64 * s, y + 164 * s, caption_width, 38 * s))
	_place(_charge_bar, Rect2(x + 64 * s, y + 205 * s, caption_width, 3 * s))
	_place(_controls_hint, Rect2(x + 64 * s, y + 215 * s, caption_width, 38 * s))
	state.add_theme_font_size_override("font_size", roundi(21 * s))
	state.max_lines_visible = 1   # one-line state text
	state.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_controls_hint.add_theme_font_size_override("font_size", roundi(18 * s))
	for label in [_charge_label, _controls_hint]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.max_lines_visible = 2
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	for label in [state, _controls_hint, _charge_label]:
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("shadow_offset_y", 2)
	var team_label_size:int=18 if get_parent()!=null and get_parent().get("doubles_mode")==true else 21
	for pair in [[score, 43], [_match_label, 17], [_blue_label, team_label_size], [_red_label, team_label_size], [_charge_label, 18], [fault, 32], [out_text, 52]]:
		pair[0].add_theme_font_size_override("font_size", maxi(10, roundi(float(pair[1]) * s)))
	_place(fault, Rect2(x + 8 * s, safe.position.y + safe.size.y * 0.35, w - 16 * s, 110 * s))
	_place(out_text, Rect2(x, safe.position.y + safe.size.y * 0.28, w, 72 * s))
	_place(zone, Rect2(x, y + 268 * s, w, 28 * s))
	# HUD band under the top row, on dark pills: the serve line under the LED board (left),
	# shot name and speed under Guide / Pause (right). Clear of the board, the toolbar and
	# the bottom controls; each pill is sized to its text when the text changes.
	_style_pills(s, true)
	for label in [_serve_label, _locked_spin_label, speed, shot_type]:
		label.add_theme_font_size_override("font_size", UiTheme.pixel_size(18 * s))
	var line_h: float = UiTheme.pixel_font().get_height(UiTheme.pixel_size(18 * s)) + speed.get_theme_stylebox("normal").get_minimum_size().y
	var row_y: float = y + pill_h + 10 * s
	var gap_y: float = 6 * s
	var right_w: float = 220 * s
	_set_pill_region(_serve_label, Rect2(x, row_y, w - right_w - 12 * s, line_h))
	shot_type.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_set_pill_region(shot_type, Rect2(x + w - right_w, row_y, right_w, line_h))
	_set_pill_region(speed, Rect2(x + w - right_w, row_y + line_h + gap_y, right_w, line_h))
	var dot_y: float = row_y + 2.0 * (line_h + gap_y)
	_place(hittable_dot, Rect2(x + w - 12 * s, dot_y, 12 * s, 12 * s))
	# The reach dot is a desktop status-panel cue (its meaning lives in a hover tooltip):
	# on the phone it read as a stray circle under the speed pill, and the timing ring
	# around HIT already says the ball is reachable. Kept in place, alpha 0 (as the
	# archived status box above), so its rect and sampling are unchanged.
	hittable_dot.modulate.a = 0.0
	_locked_spin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_set_pill_region(_locked_spin_label, Rect2(x + w - right_w, dot_y + 12 * s + gap_y, right_w, line_h))
	_place(debug, Rect2(x, y + 310 * s, w, 100 * s))
	_place(posture_debug, Rect2(x, y + 414 * s, w, 120 * s))
	_place(freeze_indicator, Rect2(x, y + 284 * s, w, 26 * s))
	_place(_guide, Rect2(x, y + 220 * s, w, safe.size.y - 248 * s))
	_guide_instructions.add_theme_font_size_override("font_size", roundi(28 * s))
	var guide_content: VBoxContainer = _guide_scroll.get_child(0)
	guide_content.get_child(0).add_theme_font_size_override("font_size", roundi(34 * s))
	var guide_close: Button = guide_content.get_child(guide_content.get_child_count() - 1)
	guide_close.custom_minimum_size.y = 96 * s
	guide_close.add_theme_font_size_override("font_size", roundi(26 * s))
	set_aim_state(_aim_mode)
	set_charge(_charge_bar.value, _charging)

func _active_exchange_practice():
	var game = get_parent()
	if game == null or not "practice_launcher" in game: return null
	var practice = game.practice_launcher
	return practice if practice != null and practice.is_exchange() else null
