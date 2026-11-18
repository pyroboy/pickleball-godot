extends CanvasLayer
## Presentation-only, archived build28 candidate. The advisor owns legal targets.
## Never interpolates root positions, writes input, or changes gameplay state.
const Advisor = preload("res://scripts/movement_guidance_advisor.gd")
const Layout = preload("res://scripts/ui/mobile_layout.gd")
const FLOOR_LIFT := 0.025
const RING_RADIUS := 0.23
const RING_SEGMENTS := 40
const MOVE_COLOR := Color("63dfed")
const TIGHT_COLOR := Color("f2c375")
const NO_TIME_COLOR := Color("acbbc8")
const BACKING := Color(0.035, 0.075, 0.10, 0.92)
const NO_TIME_ENTRY_SECONDS := 0.05
const DIRECTION_LAYOUT_LATCH := true
static var _edge_strategies: Array = _build_edge_strategies()

class NoTimeEntryGate extends RefCounted:
	var context: Array = []
	var elapsed := 0.0
	var admitted := false
	func reset() -> void:
		context = []
		elapsed = 0.0
		admitted = false
	func observe(valid_proof: bool, key: Array, real_delta: float) -> bool:
		if not valid_proof:
			reset()
			return false
		if context != key:
			context = key.duplicate()
			elapsed = 0.0
		else:
			elapsed += maxf(0.0, real_delta)
		admitted = elapsed + 0.000001 >= NO_TIME_ENTRY_SECONDS
		return admitted

var game
var player
var enabled := true
var advisor = Advisor.new()
var _drawing: Control
var _advice: Dictionary = {}
var _presentation: Dictionary = {}
var _reset_generation := -1
var _label_side := -1
var _label_context: Array = []
var _no_time_entry := NoTimeEntryGate.new()
var _advice_flight_context: Array = []
var _edge_strategy: Array = []
var _direction_context: Array = []
var _direction_preferred := false
var _direction_truth_valid := false

class GuideDrawing extends Control:
	var guide
	func _draw() -> void:
		if is_instance_valid(guide): guide.draw_guide(self)

func setup(owner_game, owner_player = null) -> void:
	game = owner_game
	player = owner_game.player_left if owner_player == null else owner_player
	name = "IncomingMovementGuide"
	layer = 0 # Above focus (-1), below gameplay HUD (1).
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 100 # Read after the normal player predictor.
	process_priority = 1001 # After CameraRig (1000); physics cache ordering stays unchanged.
	if not is_instance_valid(_drawing):
		_drawing = GuideDrawing.new()
		_drawing.guide = self
		_drawing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_drawing.focus_mode = Control.FOCUS_NONE
		_drawing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_drawing)
	_reset_generation = int(game.get("_point_reset_generation"))
	cancel()

func cancel() -> void:
	_direction_context = []
	_direction_preferred = false
	_direction_truth_valid = false
	_no_time_entry.reset()
	_advice_flight_context = []
	_edge_strategy = []
	_label_side = -1
	_label_context = []
	advisor.reset()
	_advice = {}
	_clear_presentation()

func reset() -> void:
	cancel()

func _exit_tree() -> void:
	cancel()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		cancel()

func _physics_process(delta: float) -> void:
	tick(delta)

## If the integrator calls tick explicitly, disable this node's physics process.
## Pass the normal predictor's current cache; no presentation trace is performed.
func tick(delta: float, cached_flight: Dictionary = {}) -> void:
	if _observe_reset() or not _eligible():
		cancel()
		return
	var flight := cached_flight
	if flight.is_empty() and player.debug_visual != null:
		flight = player.debug_visual._last_flight
	_advice = advisor.update(delta, player, game.ball, flight, true)
	_advice_flight_context = _flight_context()
	# Observe once per physics update, never once per render. Slow motion must
	# not turn a brief display stabilization into seconds of hidden feedback.
	_no_time_entry.observe(_valid_no_time_proof(), _no_time_context(), delta / maxf(Engine.time_scale, 0.000001))
	_reproject()

func _process(_delta: float) -> void:
	# Physics may be paused while menus/cameras still change. Never retain a
	# positive target through a paused tick or a reset/menu transition.
	if _observe_reset() or not _eligible():
		cancel()
		return
	_reproject()

func _observe_reset() -> bool:
	if not is_instance_valid(game): return false
	var generation := int(game.get("_point_reset_generation"))
	if generation == _reset_generation: return false
	_reset_generation = generation
	return true

func _eligible() -> bool:
	if not enabled or not is_instance_valid(game) or not is_instance_valid(player): return false
	if not is_inside_tree() or get_tree().paused: return false
	var settings := get_node_or_null("/root/Settings")
	if settings != null and not bool(settings.get_value("gameplay.movement_guide", true)): return false
	if game._tool_state_active() or game.match_over or game.game_state != game.GameState.PLAYING: return false
	if game.hud == null or not game.hud._gameplay_visible or game.hud._guide.visible or game.hud._between_point_active: return false
	if game.practice_panel != null and game.practice_panel.visible: return false
	if game.practice_launcher != null and game.practice_launcher.demo_enabled and game.practice_launcher.is_active: return false
	if player.posture != null and player.posture.editor_preview_mode: return false
	var ball = game.ball
	if not is_instance_valid(ball) or not ball.is_in_play or ball.last_hit_by == player.player_num or ball.bounces_since_last_hit >= 2: return false
	if not player.global_position.is_finite() or not ball.global_position.is_finite(): return false
	if player.is_jumping or not ball.linear_velocity.is_finite(): return false
	if ball.wall_practice_active and not ball.wall_return_ready: return false
	return _camera() != null

func _camera() -> Camera3D:
	if not is_inside_tree(): return null
	var camera := get_viewport().get_camera_3d()
	if not is_instance_valid(camera) or not camera.is_inside_tree(): return null
	if not camera.global_transform.is_finite(): return null
	return camera

func _clear_presentation() -> void:
	_presentation = {}
	if is_instance_valid(_drawing):
		_drawing.hide()
		_drawing.queue_redraw()

## Value copy for diagnostics; callers cannot move the actual marker.
func presentation_state() -> Dictionary:
	return _presentation.duplicate(true)

static func visual_metrics(viewport_size: Vector2, pixels_per_unit: float = 1.0) -> Dictionary:
	var scale := Layout.scale_for(viewport_size)
	var pixel := 1.0 / maxf(0.1, pixels_per_unit)
	return {"scale": scale, "stroke": maxf(2.8 * scale, 1.6 * pixel),
		"font_size": ceili(maxf(24.0 * scale, 12.0 * pixel)),
		"min_radius": maxf(12.0 * scale, 8.0 * pixel),
		"head": maxf(9.0 * scale, 5.0 * pixel), "gap": maxf(8.0 * scale, 4.0 * pixel)}

static func court_band(viewport_size: Vector2, safe: Rect2) -> Rect2:
	if Layout.is_portrait(viewport_size): return Layout.court_rect(viewport_size, safe).grow(-8.0 * Layout.scale_for(viewport_size))
	# Desktop/landscape HUD occupies the upper score band and bottom help strip.
	var margin := 16.0 * Layout.scale_for(viewport_size)
	var top := minf(110.0, safe.size.y * 0.22)
	var bottom := minf(90.0, safe.size.y * 0.18)
	return Rect2(safe.position + Vector2(margin, top), Vector2(maxf(1, safe.size.x - 2 * margin), maxf(1, safe.size.y - top - bottom)))

func _valid_no_time_proof() -> bool:
	if not _advice.get("visible", false) or _advice.get("status", "UNKNOWN") != "NO_TIME": return false
	if not _advice.get("no_time_proven", false) or _advice.get("proof_scope", "") != "predicted_legal_flight": return false
	if not is_instance_valid(game) or not is_instance_valid(player): return false
	if int(_advice.get("flight_id", -1)) != game.ball.flight_id: return false
	var remaining := float(_advice.get("remaining_time", 0.0))
	var target: Vector3 = _advice.get("target_root", Vector3.INF)
	if not is_finite(remaining) or remaining <= 0.0 or not Advisor._within_bounds(player, target) or target.z * player.global_position.z <= 0.0: return false
	var solved: Vector3 = _advice.get("solved_root", Vector3.INF)
	var speed := float(_advice.get("proof_speed", -1.0))
	return is_instance_valid(player) and solved.is_finite() and is_finite(speed) and player.global_position.distance_to(solved) < 0.0001 and maxf(player.move_speed, player.current_velocity.length()) <= speed + 0.0001

func _flight_context() -> Array:
	if not is_instance_valid(game) or not is_instance_valid(game.ball): return []
	return [game.ball.flight_id, game.ball.bounces_since_last_hit, game.ball.last_hit_by, game.ball.both_bounces_complete]

func _no_time_context() -> Array:
	var camera := _camera()
	if camera == null or not is_instance_valid(game) or not is_instance_valid(player): return []
	# The proof covers the whole legal flight, independently of which freshly
	# verified marker is selected. Target changes do not restart a valid proof.
	return _flight_context() + [player.get_instance_id(), camera.get_instance_id(), get_viewport().get_visible_rect().size]

func _reproject() -> void:
	_direction_truth_valid = false
	_reproject_current()
	if not _direction_truth_valid:
		_direction_context = []
		_direction_preferred = false

func _reproject_current() -> void:
	_clear_presentation()
	if not _advice_flight_context.is_empty() and _advice_flight_context != _flight_context():
		_no_time_entry.reset()
		return
	# This check must precede all target reads. UNKNOWN has no target fields.
	if not bool(_advice.get("visible", false)):
		_no_time_entry.reset()
		return
	var status := str(_advice.get("status", "UNKNOWN"))
	if status not in ["MOVE", "TIGHT", "NO_TIME"]:
		_no_time_entry.reset()
		return
	if status == "NO_TIME":
		if not _advice.get("no_time_proven", false) or _advice.get("proof_scope", "") != "predicted_legal_flight":
			_no_time_entry.reset()
			return
		if not _valid_no_time_proof():
			_no_time_entry.reset()
		elif _no_time_entry.context != _no_time_context():
			_no_time_entry.reset()
		if not _no_time_entry.admitted:
			# A short-lived global proof may accompany a still-valid difficult
			# candidate. Show only that candidate's uncertainty while entry waits.
			var slack := float(_advice.get("slack", INF))
			if not is_finite(slack) or slack >= Advisor.TIGHT_SLACK: return
			status = "TIGHT"
	else:
		_no_time_entry.reset()
	if int(_advice.get("flight_id", -1)) != game.ball.flight_id: return
	if not is_finite(float(_advice.get("remaining_time", 0.0))) or float(_advice.get("remaining_time", 0.0)) <= 0.0: return
	var target: Vector3 = _advice.get("target_root", Vector3.INF)
	if not target.is_finite() or not Advisor._within_bounds(player, target): return
	if target.z * player.global_position.z <= 0.0: return
	var camera := _camera()
	if camera == null: return
	var floor_target := Vector3(target.x, PickleballConstants.FLOOR_Y + FLOOR_LIFT, target.z)
	var floor_root := Vector3(player.global_position.x, floor_target.y, player.global_position.z)
	# No behind-camera point is ever passed to unproject_position. An ambiguous
	# POV-ground direction hides rather than inventing a backwards edge cue.
	if camera.is_position_behind(floor_target) or camera.is_position_behind(floor_root): return
	var target_screen := camera.unproject_position(floor_target)
	var root_screen := camera.unproject_position(floor_root)
	if not target_screen.is_finite() or not root_screen.is_finite(): return
	_direction_truth_valid = true
	var size := get_viewport().get_visible_rect().size
	var direction_context := _flight_context() + [_reset_generation, player.get_instance_id(), camera.get_instance_id(), size]
	if direction_context != _direction_context:
		_direction_context = direction_context
		_direction_preferred = false
	var context := [game.ball.flight_id, player.get_instance_id(), camera.get_instance_id(), size]
	if context != _label_context:
		_label_context = context
		_label_side = -1
		_edge_strategy = []
	var stretch := get_viewport().get_stretch_transform().get_scale().abs()
	var metrics := visual_metrics(size, minf(stretch.x, stretch.y))
	var band := court_band(size, Layout.safe_rect(get_viewport()))
	if band.size.x < 96 * metrics.scale or band.size.y < 70 * metrics.scale: return
	var ball_screen := Vector2.INF
	if not camera.is_position_behind(game.ball.global_position): ball_screen = camera.unproject_position(game.ball.global_position)
	var outline := PackedVector2Array()
	for index in range(RING_SEGMENTS + 1):
		var angle := TAU * float(index) / RING_SEGMENTS
		var point := floor_target + Vector3(cos(angle), 0.0, sin(angle)) * RING_RADIUS
		if camera.is_position_behind(point): return
		outline.append(camera.unproject_position(point))
	var ring_extent := Vector2.ZERO
	for point in outline: ring_extent = ring_extent.max((point - target_screen).abs())
	var ring_scale := maxf(1.0, metrics.min_radius / maxf(1.0, ring_extent.x))
	for index in outline.size(): outline[index] = target_screen + (outline[index] - target_screen) * ring_scale
	ring_extent *= ring_scale
	# Prevent a shallow floor projection becoming an unreadably flat ring.
	if ring_extent.y < metrics.stroke * 1.8:
		var vertical_scale: float = metrics.stroke * 1.8 / maxf(ring_extent.y, 0.01)
		for index in outline.size(): outline[index].y = target_screen.y + (outline[index].y - target_screen.y) * vertical_scale
		ring_extent.y = metrics.stroke * 1.8
	var inset: float = metrics.head * 2.0
	var arrow_band := band.grow(-inset)
	var edge := not band.encloses(Rect2(target_screen - ring_extent - Vector2.ONE * metrics.stroke, (ring_extent + Vector2.ONE * metrics.stroke) * 2))
	var endpoint := target_screen
	if edge:
		var origin := Vector2(clampf(root_screen.x, arrow_band.position.x, arrow_band.end.x), clampf(root_screen.y, arrow_band.position.y, arrow_band.end.y))
		endpoint = _edge_point(origin, target_screen, arrow_band)
		outline = PackedVector2Array() # An edge arrow is not a false floor location.
	# Clipping changes placement only. Both roots may be beyond the same
	# viewport edge; aiming at the clipped point would reverse the cue.
	var direction := (target_screen - root_screen).normalized()
	if direction.length_squared() < 0.01: return
	var arrow_end: Vector2 = endpoint if edge else endpoint - direction * (maxf(ring_extent.x, ring_extent.y) + metrics.gap)
	var length: float = clampf(root_screen.distance_to(arrow_end) - metrics.gap, 0.0, 76.0 * metrics.scale)
	var arrow_start := arrow_end - direction * length
	if not arrow_band.has_point(arrow_start): arrow_start = _edge_point(arrow_end, arrow_start, arrow_band)
	var head: float = metrics.head
	var normal := Vector2(-direction.y, direction.x)
	var arrow := PackedVector2Array([arrow_start, arrow_end])
	var wings := PackedVector2Array([arrow_end - direction * head + normal * head * 0.65, arrow_end, arrow_end - direction * head - normal * head * 0.65])
	var label := "NO TIME" if status == "NO_TIME" else status
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, metrics.font_size)
	var label_size := Vector2(text_size.x + 22.0 * metrics.scale, maxf(text_size.y + 10.0 * metrics.scale, 34.0 * metrics.scale))
	var exclusions := _control_exclusions(metrics.gap)
	var player_exclusions := _player_exclusions(camera, metrics.gap)
	var label_rect: Rect2
	var direction_only := false
	if edge:
		exclusions.append_array(_edge_hud_exclusions(metrics.gap))
		exclusions.append_array(player_exclusions)
		var group := _edge_group(endpoint, direction, label_size, band, ball_screen, metrics, exclusions, minf(stretch.x, stretch.y))
		if group.is_empty(): return
		arrow = group.arrow
		wings = group.wings
		label_rect = group.label_rect
	else:
		# A screen annotation may replace an occluded floor marker, never move it.
		# Retain only a layout preference; all geometry below is current-frame.
		var label_exclusions: Array[Rect2] = exclusions.duplicate()
		label_exclusions.append_array(player_exclusions)
		var floor_label := _place_label(endpoint, ring_extent, label_size, band, ball_screen, metrics, label_exclusions)
		var floor_safe := floor_label.size != Vector2.ZERO and not _overlaps_any(floor_label, exclusions) and not _overlaps_any(Rect2(target_screen - ring_extent, ring_extent * 2), exclusions)
		if _direction_preferred or not floor_safe:
			var group_exclusions: Array[Rect2] = exclusions.duplicate()
			group_exclusions.append_array(_edge_hud_exclusions(metrics.gap))
			group_exclusions.append_array(player_exclusions)
			var group := _edge_group(_direction_anchor(band, metrics), direction, label_size, band, ball_screen, metrics, group_exclusions, minf(stretch.x, stretch.y))
			if not group.is_empty():
				outline = PackedVector2Array()
				arrow = group.arrow
				wings = group.wings
				label_rect = group.label_rect
				exclusions = group_exclusions
				direction_only = true
				_direction_preferred = DIRECTION_LAYOUT_LATCH
			elif floor_safe:
				# Never sacrifice a safe current floor cue to a preferred layout.
				_edge_strategy = []
				label_rect = floor_label
			else: return
		else:
			_edge_strategy = []
			label_rect = floor_label
	if label_rect.size == Vector2.ZERO: return
	if _overlaps_any(label_rect, exclusions): return
	_presentation = {"visible": true, "status": status, "advisor_status": str(_advice.get("status", "UNKNOWN")), "no_time_pending": _advice.get("status", "") == "NO_TIME" and status == "TIGHT", "label": label,
		"color": MOVE_COLOR if status == "MOVE" else TIGHT_COLOR if status == "TIGHT" else NO_TIME_COLOR,
		"target_world": floor_target, "center": target_screen, "ring": outline,
		"arrow": arrow, "wings": wings, "edge": edge, "direction_only": direction_only, "marker_mode": "edge" if edge else "direction" if direction_only else "floor", "label_rect": label_rect, "label_side": _label_side,
		"band": band, "ball_screen": ball_screen, "ball_clearance": maxf(14.0 * metrics.scale, metrics.stroke * 5.0),
		"metrics": metrics, "exclusions": exclusions, "player_exclusions": player_exclusions}
	_drawing.show()
	_drawing.queue_redraw()

static func _direction_anchor(band: Rect2, metrics: Dictionary) -> Vector2:
	# A current-viewport screen annotation, not a relocated floor target.
	# Recomputing this anchor avoids HIT-driven camera motion moving the card.
	return Vector2(band.get_center().x, clampf(band.end.y - 160.0 * metrics.scale, band.position.y, band.end.y))

func _player_exclusions(camera: Camera3D, gap: float) -> Array[Rect2]:
	# Current visible body/paddle envelopes, never a stored actor position.
	# Authored custom AABBs cover skinned torso/limb deformation conservatively.
	var regions: Array[Rect2] = []
	var viewport := get_viewport().get_visible_rect()
	for actor in [game.player_left, game.player_right]:
		if not is_instance_valid(actor) or not actor.is_visible_in_tree() or not is_instance_valid(actor.body_pivot): continue
		var pending: Array[Node] = [actor.body_pivot]
		var bounds := Rect2()
		var found := false
		while not pending.is_empty():
			var node: Node = pending.pop_back()
			for child: Node in node.get_children(): pending.append(child)
			if not node is MeshInstance3D or not node.is_visible_in_tree() or node.mesh == null or (node.layers & camera.cull_mask) == 0 or node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: continue
			var rect := _project_mesh_bounds(node, camera, viewport)
			if not rect.has_area(): continue
			bounds = bounds.merge(rect) if found else rect
			found = true
		if found: regions.append(bounds.grow(gap))
	return regions

static func _project_mesh_bounds(mesh: MeshInstance3D, camera: Camera3D, viewport: Rect2) -> Rect2:
	var aabb: AABB = mesh.custom_aabb if mesh.custom_aabb.has_volume() else mesh.get_aabb()
	var view := camera.get_camera_transform()
	var inverse_view := view.affine_inverse()
	var points: Array[Vector3] = []
	var corners: Array[Vector3] = []
	for index in range(8):
		var point: Vector3 = inverse_view * (mesh.global_transform * aabb.get_endpoint(index))
		if not point.is_finite(): return Rect2()
		corners.append(point)
		if point.z <= -camera.near: points.append(point)
	# Clip box edges before projection. Never unproject behind-camera points.
	for first in range(8):
		for bit in [1, 2, 4]:
			var second: int = first ^ bit
			if second <= first: continue
			var a: Vector3 = corners[first]
			var b: Vector3 = corners[second]
			if (a.z <= -camera.near) == (b.z <= -camera.near): continue
			points.append(a.lerp(b, (-camera.near - a.z) / (b.z - a.z)))
	var rect := Rect2()
	var found := false
	for point: Vector3 in points:
		var projected := camera.unproject_position(view * point)
		if not projected.is_finite(): return Rect2()
		rect = rect.expand(projected) if found else Rect2(projected, Vector2.ZERO)
		found = true
	return rect.intersection(viewport) if found and rect.intersects(viewport) else Rect2()

func _edge_hud_exclusions(gap: float) -> Array[Rect2]:
	# Read visible leaf panels every frame; never exclude a whole HUD canvas.
	# This is edge-only so ordinary floor-ring presentation stays unchanged.
	var result: Array[Rect2] = []
	var parts: Array = [game.reaction_button]
	for key in ["_score_panel", "_status_panel", "_guidance_chrome", "_toolbar", "_rally_banner", "_debug_toolbar"]:
		parts.append(game.hud.get(key))
	for part in parts:
		if part is Control and is_instance_valid(part) and part.is_visible_in_tree():
			var rect: Rect2 = part.get_global_rect()
			if rect.position.is_finite() and rect.size.is_finite() and rect.has_area():
				result.append(rect.grow(gap))
	return result

static func _build_edge_strategies() -> Array:
	# Shared read-only choices preserve the original candidate/tie-break order.
	var strategies: Array = []
	for side in range(4):
		for x in range(-4, 5):
			for y in range(-4, 5):
				if abs(x) + abs(y) > 6: continue
				strategies.append([side, Vector2(x, y)])
	return strategies

func _edge_group(endpoint: Vector2, direction: Vector2, label_size: Vector2, band: Rect2, ball_screen: Vector2, metrics: Dictionary, exclusions: Array[Rect2], pixels_per_unit: float) -> Dictionary:
	# Edge glyphs are screen annotations, never replacement floor locations.
	# Their size and attached card must not inherit a huge offscreen floor ring.
	var pixel := 1.0 / maxf(0.1, pixels_per_unit)
	# A physical-pixel inset also absorbs floating-point border rounding.
	var placement_band := band.grow(-pixel)
	var head := maxf(13.4 * metrics.scale, 8.0 * pixel)
	var shaft := maxf(24.0 * metrics.scale, 14.0 * pixel)
	var gap := maxf(7.0 * metrics.scale, 4.0 * pixel)
	var step := maxf(label_size.y + gap, head + shaft)
	var best: Dictionary = {}
	var best_score := INF
	var preferred_card := Vector2.INF
	var preferred_glyph := Vector2.INF
	var normal := Vector2(-direction.y, direction.x)
	var ball_clearance := maxf(14.0 * metrics.scale, metrics.stroke * 5.0)
	# Test the cached strategy before even traversing the shared fallback table.
	# Strategies contain only side/offset choices, never target or screen geometry.
	var strategy_index := -1
	while strategy_index < _edge_strategies.size():
		var strategy: Array = _edge_strategy if strategy_index < 0 else _edge_strategies[strategy_index]
		strategy_index += 1
		if strategy.is_empty(): continue
		var tip: Vector2 = endpoint + strategy[1] * step
		var start := tip - direction * (head + shaft)
		var first := tip - direction * head + normal * head * 0.65
		var second := tip - direction * head - normal * head * 0.65
		var glyph := Rect2(tip, Vector2.ZERO).expand(start).expand(first).expand(second).grow(metrics.stroke + metrics.scale)
		var card := Rect2(Vector2.ZERO, label_size)
		match int(strategy[0]):
			0: card.position = Vector2(glyph.get_center().x - label_size.x * 0.5, glyph.end.y + gap)
			1: card.position = Vector2(glyph.get_center().x - label_size.x * 0.5, glyph.position.y - gap - label_size.y)
			2: card.position = Vector2(glyph.end.x + gap, glyph.get_center().y - label_size.y * 0.5)
			3: card.position = Vector2(glyph.position.x - gap - label_size.x, glyph.get_center().y - label_size.y * 0.5)
		var bounds := glyph.merge(card)
		if bounds.size.x > placement_band.size.x or bounds.size.y > placement_band.size.y: continue
		var placed := Vector2(clampf(bounds.position.x, placement_band.position.x, placement_band.end.x - bounds.size.x), clampf(bounds.position.y, placement_band.position.y, placement_band.end.y - bounds.size.y))
		var shift := placed - bounds.position
		glyph.position += shift; card.position += shift
		var group_bounds := glyph.merge(card)
		# Rebuild the preferred strategy with current geometry, even if now unsafe.
		# This is a scoring reference only; every displayed choice passes all guards.
		if strategy == _edge_strategy:
			preferred_card = card.get_center()
			preferred_glyph = glyph.get_center()
		if _overlaps_any(group_bounds, exclusions): continue
		if ball_screen.is_finite() and group_bounds.grow(ball_clearance).has_point(ball_screen): continue
		var score: float = (tip + shift).distance_squared_to(endpoint) + strategy[1].length_squared() * 0.001
		if preferred_card.is_finite():
			score = card.get_center().distance_squared_to(preferred_card) + glyph.get_center().distance_squared_to(preferred_glyph) + score * 0.000001
		var result := {"arrow": PackedVector2Array([start + shift, tip + shift]),
			"wings": PackedVector2Array([first + shift, tip + shift, second + shift]),
			"label_rect": card, "glyph_rect": glyph, "strategy": strategy}
		# Retain only a safe layout strategy relative to THIS frame's edge point.
		# Neither the old target nor any old screen position is ever retained.
		if strategy == _edge_strategy: return result
		if score < best_score:
			best_score = score
			best = result
	if not best.is_empty(): _edge_strategy = best.strategy.duplicate()
	return best

static func _edge_point(origin: Vector2, target: Vector2, rect: Rect2) -> Vector2:
	var delta := target - origin
	var fraction := 1.0
	if delta.x > 0.0: fraction = minf(fraction, (rect.end.x - origin.x) / delta.x)
	elif delta.x < 0.0: fraction = minf(fraction, (rect.position.x - origin.x) / delta.x)
	if delta.y > 0.0: fraction = minf(fraction, (rect.end.y - origin.y) / delta.y)
	elif delta.y < 0.0: fraction = minf(fraction, (rect.position.y - origin.y) / delta.y)
	return origin + delta * clampf(fraction, 0.0, 1.0)

func _place_label(center: Vector2, extent: Vector2, size: Vector2, band: Rect2, ball_screen: Vector2, metrics: Dictionary, exclusions: Array[Rect2] = []) -> Rect2:
	var gap: float = metrics.gap * 1.5
	var candidates := [center + Vector2(-size.x * 0.5, extent.y + gap),
		center - Vector2(size.x * 0.5, extent.y + gap + size.y),
		center + Vector2(extent.x + gap, -size.y * 0.5),
		center - Vector2(extent.x + gap + size.x, size.y * 0.5)]
	var order: Array[int] = [0, 1, 2, 3]
	if _label_side in order:
		order.erase(_label_side)
		order.push_front(_label_side)
	for index in order:
		var candidate: Vector2 = candidates[index]
		var origin := Vector2(clampf(candidate.x, band.position.x, maxf(band.position.x, band.end.x - size.x)), clampf(candidate.y, band.position.y, maxf(band.position.y, band.end.y - size.y)))
		var rect := Rect2(origin, size)
		if not rect.grow(metrics.gap * 2).has_point(ball_screen) and not rect.grow(metrics.gap * 0.5).has_point(center) and not _overlaps_any(rect, exclusions):
			# Retain only a placement side, never an old target or unsafe rectangle.
			# A real overlap switches immediately; clearing the ball does not bounce
			# the caption back across the marker at a subpixel threshold.
			_label_side = index
			return rect
	return Rect2()

func _control_exclusions(gap: float) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var controls = game.mobile_controls
	if controls == null or not controls.enabled or not controls.visible: return result
	# The control owner exposes only currently drawn shot/cancel/timing regions.
	# Dormant CANCEL and timing-caption positions must not erase useful advice.
	if controls.has_method("camera_occlusion_regions"):
		for rect: Rect2 in controls.camera_occlusion_regions(): result.append(rect.grow(gap))
	for part in ["_stick", "_charge"]:
		var center: Vector2 = controls.get(part + "_center")
		var radius: float = controls.get(part + "_radius")
		result.append(Rect2(center - Vector2.ONE * radius * 1.35, Vector2.ONE * radius * 2.7).grow(gap))
	return result

static func _overlaps_any(rect: Rect2, others: Array[Rect2]) -> bool:
	for other in others:
		if rect.intersects(other): return true
	return false

func draw_guide(canvas: Control) -> void:
	if _presentation.is_empty(): return
	var state := _presentation
	var color: Color = state.color
	var width: float = state.metrics.stroke
	var ring: PackedVector2Array = state.ring
	# Tiny gaps around the projected live ball keep its silhouette unobstructed.
	for index in range(ring.size() - 1):
		if state.status == "NO_TIME" and index % 5 >= 3: continue
		_draw_segment(canvas, ring[index], ring[index + 1], color, width, state)
	var arrow: PackedVector2Array = state.arrow
	if arrow[0].distance_to(arrow[1]) >= width * 3.0:
		_draw_segment(canvas, arrow[0], arrow[1], color, width, state)
	var wings: PackedVector2Array = state.wings
	for index in range(wings.size() - 1): _draw_segment(canvas, wings[index], wings[index + 1], color, width, state)
	var box: Rect2 = state.label_rect
	var backing := StyleBoxFlat.new()
	backing.bg_color = BACKING
	backing.set_corner_radius_all(roundi(7.0 * state.metrics.scale))
	backing.border_color = Color(color, 0.65)
	backing.set_border_width_all(1)
	canvas.draw_style_box(backing, box)
	var font := ThemeDB.fallback_font
	var font_size: int = state.metrics.font_size
	var baseline := box.position + Vector2(11.0 * state.metrics.scale, (box.size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size))
	canvas.draw_string(font, baseline, state.label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_segment(canvas: Control, a: Vector2, b: Vector2, color: Color, width: float, state: Dictionary) -> void:
	if not state.band.has_point(a) or not state.band.has_point(b): return
	if state.ball_screen.is_finite() and Geometry2D.get_closest_point_to_segment(state.ball_screen, a, b).distance_to(state.ball_screen) < state.ball_clearance: return
	for rect: Rect2 in state.exclusions:
		if rect.has_point(a) or rect.has_point(b) or rect.intersects(Rect2(a, b - a).abs().grow(width)): return
	canvas.draw_line(a, b, Color(0.02, 0.05, 0.07, 0.8), width + 2.0 * state.metrics.scale, true)
	canvas.draw_line(a, b, color, width, true)
