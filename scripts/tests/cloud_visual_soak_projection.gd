extends "res://scripts/tests/cloud_visual_soak.gd"
## Nonmutating mirror of movement guide projection gates. Captured binary
## frame snapshots preserve Godot vectors, rects and camera transforms for
## deterministic presentation-only replay, without forging gameplay states.
const GuideScript = preload("res://scripts/ui/incoming_movement_guide.gd")
const LayoutScript = preload("res://scripts/ui/mobile_layout.gd")
var projection_file: FileAccess
var snapshot_file: FileAccess
var projection_rows := 0
var mirror_mismatches := 0

func observe(delta: float) -> void:
	super.observe(delta)
	if not monitor or changing_scene or not is_instance_valid(game): return
	if projection_file == null:
		projection_file = FileAccess.open(output.path_join("projection_trace.jsonl"), FileAccess.WRITE)
		snapshot_file = FileAccess.open(output.path_join("projection_snapshots.bin"), FileAccess.WRITE)
	var guide = game.movement_guide
	var diagnostic: Dictionary = projection_gate(guide)
	var camera: Camera3D = root.get_camera_3d()
	var row := {"elapsed": elapsed(), "usec": Time.get_ticks_usec(), "scene": scene_number,
		"flight": game.ball.flight_id, "physics_frame": Engine.get_physics_frames(),
		"actual_visible": not guide._presentation.is_empty(), "diagnostic": diagnostic,
		"advice": guide._advice.duplicate(true), "presentation": guide.presentation_state(),
		"player_transform": game.player_left.global_transform, "opponent_transform": game.player_right.global_transform,
		"contact_point": game.player_left.posture.human_contact.contact.get("point", Vector3.INF),
		"contact_time": game.player_left.posture.human_contact.contact.get("time", -1.0),
		"arc_world_path": game.aim_focus._world_path, "arc_screen_path": game.aim_focus._screen_path,
		"ball_transform": game.ball.global_transform, "ball_velocity": game.ball.linear_velocity,
		"camera_transform": camera.global_transform if camera != null else Transform3D.IDENTITY,
		"camera_fov": camera.fov if camera != null else 0.0,
		"camera_projection": camera.get_camera_projection() if camera != null else Projection(),
		"viewport": root.get_visible_rect(), "label_side": guide._label_side,
		"controls_visible": game.mobile_controls.visible, "state": last_state.duplicate(true)}
	if bool(diagnostic.get("visible", false)) != row.actual_visible:
		mirror_mismatches += 1
		row["mirror_mismatch"] = true
	var bytes := var_to_bytes(row)
	var offset: int = snapshot_file.get_position()
	snapshot_file.store_32(bytes.size()); snapshot_file.store_buffer(bytes)
	projection_file.store_line(JSON.stringify({"elapsed": row.elapsed, "usec": row.usec, "scene": scene_number, "flight": row.flight, "actual_visible": row.actual_visible, "gate": diagnostic.get("gate", ""), "diagnostic": diagnostic, "snapshot_offset": offset, "snapshot_bytes": bytes.size(), "mirror_mismatch": row.get("mirror_mismatch", false)}))
	projection_rows += 1
	if projection_rows % rate == 0:
		projection_file.flush(); snapshot_file.flush()

static func scalar_rect_gap(a: Rect2, b: Rect2) -> float:
	return maxf(maxf(b.position.x - a.end.x, a.position.x - b.end.x), maxf(b.position.y - a.end.y, a.position.y - b.end.y))

func projection_gate(g) -> Dictionary:
	var out := {"visible": false, "gate": "ineligible", "eligible": g._eligible()}
	if not out.eligible: return out
	var a: Dictionary = g._advice
	out["advice_visible"] = a.get("visible", false)
	out["advice_reason"] = a.get("reason", "")
	if not bool(a.get("visible", false)): out.gate = "advisor_hidden"; return out
	var status := str(a.get("status", "UNKNOWN"))
	if status not in ["MOVE", "TIGHT", "NO_TIME"]: out.gate = "unknown_status"; return out
	if status == "NO_TIME" and (not bool(a.get("no_time_proven", false)) or str(a.get("proof_scope", "")) != "predicted_legal_flight"):
		out.gate = "unproven_no_time"; return out
	if int(a.get("flight_id", -1)) != game.ball.flight_id: out.gate = "stale_flight"; return out
	if float(a.get("remaining_time", 0.0)) <= 0.0: out.gate = "expired"; return out
	var target: Vector3 = a.get("target_root", Vector3.INF)
	if not target.is_finite() or not g.Advisor._within_bounds(g.player, target): out.gate = "target_bounds"; return out
	if target.z * g.player.global_position.z <= 0: out.gate = "across_net"; return out
	var camera: Camera3D = g._camera()
	if camera == null: out.gate = "no_camera"; return out
	var floor_target := Vector3(target.x, PickleballConstants.FLOOR_Y + g.FLOOR_LIFT, target.z)
	var floor_root := Vector3(g.player.global_position.x, floor_target.y, g.player.global_position.z)
	if camera.is_position_behind(floor_target) or camera.is_position_behind(floor_root): out.gate = "behind_camera"; return out
	var center: Vector2 = camera.unproject_position(floor_target)
	var root_screen: Vector2 = camera.unproject_position(floor_root)
	if not center.is_finite() or not root_screen.is_finite(): out.gate = "nonfinite_projection"; return out
	var size: Vector2 = root.get_visible_rect().size
	var stretch: Vector2 = root.get_stretch_transform().get_scale().abs()
	var metrics: Dictionary = g.visual_metrics(size, minf(stretch.x, stretch.y))
	var band: Rect2 = g.court_band(size, LayoutScript.safe_rect(root))
	out.merge({"target_root": target, "center": center, "root_screen": root_screen, "band": band, "metrics": metrics})
	if band.size.x < 96 * metrics.scale or band.size.y < 70 * metrics.scale: out.gate = "tiny_court_band"; return out
	var ball_screen := Vector2.INF
	if not camera.is_position_behind(game.ball.global_position): ball_screen = camera.unproject_position(game.ball.global_position)
	var outline := PackedVector2Array()
	for index in range(g.RING_SEGMENTS + 1):
		var angle: float = TAU * float(index) / g.RING_SEGMENTS
		var point: Vector3 = floor_target + Vector3(cos(angle), 0.0, sin(angle)) * g.RING_RADIUS
		if camera.is_position_behind(point): out.gate = "ring_behind_camera"; return out
		outline.append(camera.unproject_position(point))
	var extent := Vector2.ZERO
	for point in outline: extent = extent.max((point - center).abs())
	var ring_scale := maxf(1.0, metrics.min_radius / maxf(1.0, extent.x))
	extent *= ring_scale
	if extent.y < metrics.stroke * 1.8: extent.y = metrics.stroke * 1.8
	var arrow_band: Rect2 = band.grow(-metrics.head * 2.0)
	var edge: bool = not band.encloses(Rect2(center - extent - Vector2.ONE * metrics.stroke, (extent + Vector2.ONE * metrics.stroke) * 2))
	var endpoint := center
	if edge:
		var origin := Vector2(clampf(root_screen.x, arrow_band.position.x, arrow_band.end.x), clampf(root_screen.y, arrow_band.position.y, arrow_band.end.y))
		endpoint = g._edge_point(origin, center, arrow_band)
	var direction := (center - root_screen).normalized()
	if direction.length_squared() < 0.01: out.gate = "zero_direction"; return out
	var font := ThemeDB.fallback_font
	var text_size: Vector2 = font.get_string_size("NO TIME" if status == "NO_TIME" else status, HORIZONTAL_ALIGNMENT_LEFT, -1, metrics.font_size)
	var label_size := Vector2(text_size.x + 40.0 * metrics.scale, maxf(text_size.y + 10.0 * metrics.scale, 34.0 * metrics.scale))
	var exclusions: Array[Rect2] = g._control_exclusions(metrics.gap)
	var gap: float = metrics.gap * 1.5
	var candidates := [endpoint + Vector2(-label_size.x * 0.5, extent.y + gap), endpoint - Vector2(label_size.x * 0.5, extent.y + gap + label_size.y), endpoint + Vector2(extent.x + gap, -label_size.y * 0.5), endpoint - Vector2(extent.x + gap + label_size.x, label_size.y * 0.5)]
	var order: Array[int] = [0, 1, 2, 3]
	if g._label_side in order: order.erase(g._label_side); order.push_front(g._label_side)
	var chosen := Rect2()
	var candidate_rows: Array = []
	for index in order:
		var candidate: Vector2 = candidates[index]
		var origin := Vector2(clampf(candidate.x, band.position.x, maxf(band.position.x, band.end.x - label_size.x)), clampf(candidate.y, band.position.y, maxf(band.position.y, band.end.y - label_size.y)))
		var rect := Rect2(origin, label_size)
		var ball_overlap: bool = rect.grow(metrics.gap * 2).has_point(ball_screen)
		var target_overlap: bool = rect.grow(metrics.gap * 0.5).has_point(endpoint)
		var control_overlap: bool = g._overlaps_any(rect, exclusions)
		candidate_rows.append({"side": index, "rect": rect, "ball_overlap": ball_overlap, "target_overlap": target_overlap, "control_overlap": control_overlap})
		if chosen.size == Vector2.ZERO and not ball_overlap and not target_overlap and not control_overlap: chosen = rect
	var ring_rect := Rect2(center - extent, extent * 2)
	var ring_gap := INF
	for exclusion in exclusions: ring_gap = minf(ring_gap, scalar_rect_gap(ring_rect, exclusion))
	out.merge({"edge": edge, "endpoint": endpoint, "ring_rect": ring_rect, "exclusions": exclusions, "candidate_labels": candidate_rows, "chosen_label": chosen, "ball_screen": ball_screen, "ring_control_signed_gap_px": ring_gap})
	if chosen.size == Vector2.ZERO: out.gate = "no_safe_label"; return out
	if g._overlaps_any(chosen, exclusions): out.gate = "label_control_overlap"; return out
	if not edge and g._overlaps_any(ring_rect, exclusions): out.gate = "ring_control_overlap"; return out
	out.gate = "visible"; out.visible = true
	return out
