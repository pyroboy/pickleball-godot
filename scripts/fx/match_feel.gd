extends Node3D
## Casual feel, presentation only (no physics, no random numbers):
##  - a quick flash where a strong shot is struck,
##  - a bigger flash on a smash (visual only, never touches Engine.time_scale),
##  - a swing arc ribbon, shot label pop, footwork dust, speed lines, ball height line,
##    landing chevrons and a soft kitchen tint while someone stands in it,
##  - a ring where the incoming ball will land, orange with "OUT" if it is going out,
##  - a red flash over the kitchen on a kitchen fault.
## Lives under Game, never under a player's BodyPivot.

const FLASH_MIN_SPEED := 9.0       # m/s: softer shots get no flash
const FLASH_SECONDS := 0.16
const SMASH_MIN_SPEED := 13.0      # m/s, moving down at least SMASH_MIN_DROP
const SMASH_MIN_DROP := 1.5
const PaddleDimensions = preload("res://scripts/paddle_dimensions.gd")
const ShotNames = preload("res://scripts/shot_names.gd")
const ARC_SECONDS := 0.15          # how much of the paddle path the ribbon shows
const ARC_FADE := 0.28
const ARC_SAMPLES := 16
const ARC_WIDTH := 0.05
const LABEL_SECONDS := 0.55
const TAP_SPARKS := 6              # short lines that fly out from a paddle tap
const TAP_SPARK_SECONDS := 0.26
const DUST_SECONDS := 0.4
const DUST_COUNT := 8
const LINE_SPEED := 5.0            # m/s lateral shuffle that earns speed lines
const SHOT_COLORS := {"DINK": Color("7dff9a"), "DRIVE": Color("ffd24a"), "LOB": Color("6ec8ff"), "SMASH": Color("ff5a4a"), "": Color("ffffff")}
const KITCHEN_GLOW_ALPHA := 0.16
const KITCHEN_FLASH_SECONDS := 1.4
const IN_COLOR := Color("5ff0ff")
const OUT_COLOR := Color("ffab5c")
const CuePriority = preload("res://scripts/ui/player_cue_priority.gd")
const LabelPill = preload("res://scripts/ui/label_pill_3d.gd")
const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
## Incoming landing this frame: 0 none, 1 in, 2 out (read by player_cue_priority.gd).
var landing_state := 0

var _game
var _flashes: Array[MeshInstance3D] = []
var _flash_age: Array[float] = []
var _flash_size: Array[float] = []
var _next_flash := 0
var _pending_hit := false
var _players: Array = []
var _trail_pos: Array = []          # per player: ring of Vector3
var _trail_time: Array = []
var _trail_head: Array = []
var _arcs: Array[MeshInstance3D] = []
var _arc_meshes: Array[ImmediateMesh] = []
var _arc_age: Array[float] = []
var _arc_color: Array[Color] = []
var _arc_material: Array[StandardMaterial3D] = []
var _next_arc := 0
var _clock := 0.0
var _rally_hits := 1   # the serve is hit 1 (served before PLAYING, so not seen here)
var _labels: Array[Label3D] = []
var _label_age: Array[float] = []
var _next_label := 0
var _tap_sparks: Array[MeshInstance3D] = []
var _tap_spark_material: StandardMaterial3D
var _tap_spark_age := TAP_SPARK_SECONDS
var _tap_spark_at := Vector3.ZERO
var _dust: Array[MeshInstance3D] = []
var _dust_age: Array[float] = []
var _dust_size: Array[float] = []
var _next_dust := 0
var _peak_speed: Array[float] = []
var _split_landings: Array[int] = []
var _lines: Array[MeshInstance3D] = []
var _lines_material: StandardMaterial3D
var _chevrons: Array[MeshInstance3D] = []
var _height_line: MeshInstance3D
var _height_material: StandardMaterial3D
var _glow: Array[MeshInstance3D] = []
var _glow_alpha: Array[float] = [0.0, 0.0]
var _landing: MeshInstance3D
var _landing_material: StandardMaterial3D
var _landing_label: Label3D
var _kitchen: MeshInstance3D
var _kitchen_material: StandardMaterial3D
var _kitchen_left := 0.0

func setup(game) -> void:
	_game = game
	name = "MatchFeel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index in 3:
		var flash := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		sphere.radial_segments = 8
		sphere.rings = 4
		flash.mesh = sphere
		flash.material_override = _material(Color.WHITE)
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flash.visible = false
		add_child(flash)
		_flashes.append(flash)
		_flash_age.append(FLASH_SECONDS)
		_flash_size.append(0.3)
	_landing = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.2
	ring.outer_radius = 0.27
	ring.rings = 24
	ring.ring_segments = 4
	_landing.mesh = ring
	_landing_material = _material(IN_COLOR)
	_landing.material_override = _landing_material
	_landing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_landing.visible = false
	add_child(_landing)
	_landing_label = Label3D.new()
	_landing_label.text = "OUT"
	_landing_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_landing_label.font_size = 36
	_landing_label.pixel_size = 0.005
	_landing_label.outline_size = 10
	_landing_label.no_depth_test = true
	_landing_label.modulate = OUT_COLOR
	_landing_label.visible = false
	_pixel_label(_landing_label)
	add_child(_landing_label)
	LabelPill.attach(_landing_label)
	_kitchen = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(PickleballConstants.COURT_WIDTH, PickleballConstants.NON_VOLLEY_ZONE)
	_kitchen.mesh = plane
	_kitchen_material = _material(Color(1.0, 0.25, 0.2, 0.0))
	_kitchen.material_override = _kitchen_material
	_kitchen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_kitchen.visible = false
	add_child(_kitchen)
	_build_extras()
	if _game.ball != null: _game.ball.hit_by_paddle.connect(_on_hit)
	if _game.rally_scorer != null: _game.rally_scorer.rally_ended.connect(_on_rally_ended)
	if _game.get("between_point_controller") != null: _game.between_point_controller.partner_tapped.connect(_on_partner_tap)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_fog = true
	material.albedo_color = color
	return material

## Pixel display font, as on the HUD pills (one pixel UI style); thin dark outline.
func _pixel_label(label: Label3D) -> void:
	label.font = UiTheme.pixel_font()
	label.font_size = UiTheme.pixel_size(label.font_size)
	label.outline_size = 6
	label.outline_modulate = UiTheme.PANEL
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

func _human():
	return _game.get_human_actor() if _game != null and _game.has_method("get_human_actor") else null

func _on_hit(_team: int) -> void:
	# Velocity and hitter are final a frame later; the work happens in _process.
	_pending_hit = true

func _handle_hit() -> void:
	var ball = _game.ball
	if ball == null or _game.game_state != _game.GameState.PLAYING: return
	var velocity: Vector3 = ball.linear_velocity
	var speed: float = velocity.length()
	var hitter = _game.get_player_by_actor_id(ball.get_last_hit_actor_id())
	# Name the shot from what it carries (plan / stroke style), consumed per hit so a
	# plain deflection is named from its flight instead of the previous shot.
	_rally_hits += 1
	var profile: Dictionary = ball.get_meta("shot_profile", {}) if ball.has_meta("shot_profile") else {}
	if ball.has_meta("shot_profile"): ball.remove_meta("shot_profile")
	var depth: float = absf(hitter.global_position.z) if hitter != null else 6.0
	# Handled a frame after the hit: step the ball back to its contact height.
	var contact_height: float = ball.global_position.y - velocity.y * get_process_delta_time()
	var name_key: String = ShotNames.classify(profile, velocity, bool(ball.was_volley), _rally_hits, depth, contact_height)
	var kind: String = "SMASH" if name_key == "SMASH" else ""
	PerfMonitor.note("shot_name", {"name": name_key, "hit": _rally_hits, "zone": ShotNames.zone(depth), "h": snappedf(contact_height, 0.01), "v": snappedf(velocity.length(), 0.1), "tactic": str(profile.get("tactic", "")), "type": str(profile.get("shot_type", "")), "motion": str(profile.get("motion_profile", ""))})
	if hitter != null:
		_spawn_arc(hitter, kind, ShotNames.color(name_key))
		_spawn_label(hitter, name_key)
		if Vector2(hitter.current_velocity.x, hitter.current_velocity.z).length() > 3.5:
			_spawn_dust(hitter.global_position, 0.5)   # lunge
	if speed < FLASH_MIN_SPEED: return
	var smash: bool = kind == "SMASH"
	var strength: float = clampf((speed - FLASH_MIN_SPEED) / 9.0, 0.0, 1.0)
	var flash: MeshInstance3D = _flashes[_next_flash]
	_flash_age[_next_flash] = 0.0
	_flash_size[_next_flash] = lerpf(0.28, 0.6, strength) + (0.45 if smash else 0.0)
	_next_flash = (_next_flash + 1) % _flashes.size()
	flash.global_position = ball.global_position
	(flash.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.72, 0.3, 0.6) if smash else Color(1.0, 1.0, 0.9, 0.5)
	flash.visible = true

func _on_rally_ended(winner: int, reason: String, _detail: String) -> void:
	_rally_hits = 1
	if reason not in [RallyScorer.FAULT_KITCHEN_VOLLEY, RallyScorer.FAULT_MOMENTUM] or winner not in [0, 1]: return
	var faulting: Array = _game.get_team_players(1 - winner)
	if faulting.is_empty(): return
	var side: float = signf(faulting[0].global_position.z)
	_kitchen.global_position = Vector3(0.0, PickleballConstants.FLOOR_Y + 0.014, side * PickleballConstants.NON_VOLLEY_ZONE * 0.5)
	_kitchen_left = KITCHEN_FLASH_SECONDS
	_kitchen.visible = true

func _process(delta: float) -> void:
	var real: float = delta / maxf(Engine.time_scale, 0.05)
	_clock += real
	if _pending_hit:
		_pending_hit = false
		_handle_hit()
	for index in _flashes.size():
		if not _flashes[index].visible: continue
		_flash_age[index] += real
		var share: float = _flash_age[index] / FLASH_SECONDS
		if share >= 1.0:
			_flashes[index].visible = false
			continue
		_flashes[index].scale = Vector3.ONE * lerpf(0.12, _flash_size[index], sqrt(share))
		var material := _flashes[index].material_override as StandardMaterial3D
		material.albedo_color.a = 0.55 * (1.0 - share)
	if _kitchen.visible:
		_kitchen_left -= real
		if _kitchen_left <= 0.0: _kitchen.visible = false
		else: _kitchen_material.albedo_color.a = 0.42 * (_kitchen_left / KITCHEN_FLASH_SECONDS) * (0.65 + 0.35 * sin(_kitchen_left * 18.0))
	_update_extras(real)
	_update_tap_sparks(real)
	_update_landing()

func _update_landing() -> void:
	var human = _human()
	var ball = _game.ball
	var show: bool = human != null and ball != null and ball.is_in_play and _game.game_state == _game.GameState.PLAYING and not _game.match_over
	show = show and ball.get_last_hit_team_id() != human.team_id and ball.bounces_since_last_hit == 0 and human.debug_visual != null
	var flight: Dictionary = human.debug_visual._last_flight if show else {}
	show = show and not flight.is_empty() and float(flight.get("first_bounce_time", -1.0)) >= 0.0
	var landing: Vector3 = flight.get("first_bounce", Vector3.ZERO) if show else Vector3.ZERO
	# Only a ball coming down on the player's own side.
	show = show and landing.z * human.global_position.z > 0.0
	var out: bool = show and RallyScorer.is_outside_painted_court(landing)
	landing_state = (2 if out else 1) if show else 0
	# One player cue at a time: the landing ring and chevrons only when they are the cue.
	show = show and CuePriority.current(_game) in [CuePriority.LANDING, CuePriority.OUT]
	_landing.visible = show
	if not show:
		_landing_label.visible = false
		for chevron in _chevrons: chevron.visible = false
		return
	var color: Color = OUT_COLOR if out else IN_COLOR
	_landing_material.albedo_color = Color(color, 0.85)
	# The ring closes in as the ball arrives, a simple timing cue.
	var wide: float = 1.0 + clampf(float(flight.first_bounce_time), 0.0, 1.2) * 0.7
	_landing.scale = Vector3(wide, 0.25, wide)
	_landing.global_position = Vector3(landing.x, PickleballConstants.FLOOR_Y + 0.02, landing.z)
	_landing_label.visible = out
	_landing_label.global_position = Vector3(landing.x, PickleballConstants.FLOOR_Y + 0.95, landing.z)
	var pulse: float = fmod(_clock * 2.2, 1.0)
	for index in _chevrons.size():
		var chevron := _chevrons[index]
		chevron.visible = true
		chevron.global_position = Vector3(landing.x, PickleballConstants.FLOOR_Y + 0.3 + 0.17 * index, landing.z)
		var material := chevron.material_override as StandardMaterial3D
		material.albedo_color = Color(color, clampf(0.9 - absf(pulse - float(_chevrons.size() - 1 - index) / 3.0) * 1.6, 0.15, 0.9))

func _add_mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	add_child(node)
	return node

func _additive(color: Color) -> StandardMaterial3D:
	var material := _material(color)
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return material

func _chevron_mesh() -> ArrayMesh:
	# A flat V pointing down, in the XY plane (faces the camera when billboarded).
	var verts := PackedVector3Array([
		Vector3(-0.17, 0.08, 0), Vector3(0, -0.05, 0), Vector3(0, 0.03, 0),
		Vector3(-0.17, 0.16, 0), Vector3(-0.17, 0.08, 0), Vector3(0, 0.03, 0),
		Vector3(0.17, 0.08, 0), Vector3(0, 0.03, 0), Vector3(0, -0.05, 0),
		Vector3(0.17, 0.16, 0), Vector3(0, 0.03, 0), Vector3(0.17, 0.08, 0)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _build_extras() -> void:
	_players = _game.get_players()
	for index in _players.size():
		var positions: Array = []
		var times: Array = []
		for sample in ARC_SAMPLES:
			positions.append(Vector3.ZERO)
			times.append(-100.0)
		_trail_pos.append(positions)
		_trail_time.append(times)
		_trail_head.append(0)
		_peak_speed.append(0.0)
		_split_landings.append(0)
	for index in 3:
		var material := _additive(Color.WHITE)
		material.vertex_color_use_as_albedo = true
		var mesh := ImmediateMesh.new()
		_arcs.append(_add_mesh(mesh, material))
		_arc_meshes.append(mesh)
		_arc_material.append(material)
		_arc_age.append(ARC_FADE)
		_arc_color.append(Color.WHITE)
	for index in 3:
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 48
		label.pixel_size = 0.006
		label.outline_size = 12
		label.no_depth_test = true
		label.shaded = false
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		label.visible = false
		_pixel_label(label)
		add_child(label)
		LabelPill.attach(label)   # shot names sit on the HUD's dark navy pill
		_labels.append(label)
		_label_age.append(LABEL_SECONDS)
	_tap_spark_material = _additive(Color(1.0, 0.93, 0.6, 0.0))
	var spark_box := BoxMesh.new()
	spark_box.size = Vector3.ONE
	for index in TAP_SPARKS:
		_tap_sparks.append(_add_mesh(spark_box, _tap_spark_material))
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1.0
	puff.radial_segments = 8
	puff.rings = 4
	for index in DUST_COUNT:
		_dust.append(_add_mesh(puff, _material(Color(0.86, 0.8, 0.68, 0.0))))
		_dust_age.append(DUST_SECONDS)
		_dust_size.append(0.3)
	_lines_material = _additive(Color(1, 1, 1, 0.0))
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	for index in _players.size() * 2:
		_lines.append(_add_mesh(box, _lines_material))
	var chevron := _chevron_mesh()
	for index in 3:
		var node := _add_mesh(chevron, _material(IN_COLOR))
		(node.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_chevrons.append(node)
	_height_material = _material(Color(1, 1, 1, 0.28))
	_height_line = _add_mesh(box, _height_material)
	var plane := PlaneMesh.new()
	plane.size = Vector2(PickleballConstants.COURT_WIDTH, PickleballConstants.NON_VOLLEY_ZONE)
	for side in 2:
		var node := _add_mesh(plane, _material(Color(1.0, 0.86, 0.35, 0.0)))
		node.global_position = Vector3(0.0, PickleballConstants.FLOOR_Y + 0.012, (1.0 if side == 1 else -1.0) * PickleballConstants.NON_VOLLEY_ZONE * 0.5)
		_glow.append(node)

func _head_of(player) -> Vector3:
	var paddle: Node3D = player.paddle_node
	var transform: Transform3D = paddle.get_global_transform_interpolated()
	return transform.origin + transform.basis.y * PaddleDimensions.HEAD_CENTER_Y

func _spawn_arc(hitter, kind: String, arc_color: Color = Color.WHITE) -> void:
	var player_index: int = _players.find(hitter)
	if player_index < 0: return
	var points := PackedVector3Array()
	var positions: Array = _trail_pos[player_index]
	var times: Array = _trail_time[player_index]
	var head: int = _trail_head[player_index]
	for step in ARC_SAMPLES:
		var slot: int = (head + step) % ARC_SAMPLES   # oldest first
		if _clock - float(times[slot]) <= ARC_SECONDS: points.append(positions[slot])
	if points.size() < 3: return
	var camera := get_viewport().get_camera_3d()
	var eye: Vector3 = camera.global_position if camera != null else points[0] + Vector3(0, 3, 6)
	var slot_index: int = _next_arc
	_next_arc = (_next_arc + 1) % _arcs.size()
	var mesh := _arc_meshes[slot_index]
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var color: Color = arc_color
	var count: int = points.size()
	for index in count:
		var direction: Vector3 = points[mini(index + 1, count - 1)] - points[maxi(index - 1, 0)]
		var side: Vector3 = direction.cross(eye - points[index])
		side = side.normalized() * ARC_WIDTH * (float(index + 1) / count) if side.length_squared() > 1e-8 else Vector3.ZERO
		var tint := Color(color, 0.9 * float(index) / (count - 1))
		mesh.surface_set_color(tint)
		mesh.surface_add_vertex(points[index] + side)
		mesh.surface_set_color(tint)
		mesh.surface_add_vertex(points[index] - side)
	mesh.surface_end()
	_arc_age[slot_index] = 0.0
	_arc_material[slot_index].albedo_color = Color.WHITE
	_arcs[slot_index].visible = true

func _spawn_label(hitter, kind: String) -> void:
	var label := _labels[_next_label]
	_label_age[_next_label] = 0.0
	_next_label = (_next_label + 1) % _labels.size()
	label.text = ShotNames.display(kind)
	label.modulate = ShotNames.color(kind)
	LabelPill.fit(label)
	LabelPill.set_alpha(label, 1.0)
	label.global_position = hitter.global_position + Vector3(0.0, 2.15, 0.0)
	label.visible = true

## Partners tapped paddles between points: the word pops where the paddles met, with a small
## flash and a ring of sparks (fixed directions, no particles: those share the AI's random numbers).
func _on_partner_tap(at: Vector3) -> void:
	var label := _labels[_next_label]
	_label_age[_next_label] = 0.0
	_next_label = (_next_label + 1) % _labels.size()
	label.text = "TAP"
	label.modulate = Color(1.0, 0.92, 0.55)
	LabelPill.fit(label)
	LabelPill.set_alpha(label, 1.0)
	label.global_position = at + Vector3(0.0, 0.35, 0.0)
	label.scale = Vector3.ONE * 1.45
	label.visible = true
	var flash: MeshInstance3D = _flashes[_next_flash]
	_flash_age[_next_flash] = 0.0
	_flash_size[_next_flash] = 0.34
	_next_flash = (_next_flash + 1) % _flashes.size()
	flash.global_position = at
	flash.scale = Vector3.ONE * 0.12
	(flash.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.9, 0.5, 0.55)
	flash.visible = true
	_tap_spark_at = at
	_tap_spark_age = 0.0
	_update_tap_sparks(0.0)

## Sparks fly out in the camera's plane, stretch, then shrink and fade.
func _update_tap_sparks(real: float) -> void:
	if _tap_spark_age >= TAP_SPARK_SECONDS: return
	_tap_spark_age += real
	var share: float = _tap_spark_age / TAP_SPARK_SECONDS
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if share >= 1.0 or camera == null:
		for spark in _tap_sparks: spark.visible = false
		_tap_spark_age = TAP_SPARK_SECONDS
		return
	var right: Vector3 = camera.global_basis.x
	var up: Vector3 = camera.global_basis.y
	var out: float = 1.0 - (1.0 - share) * (1.0 - share)   # fast out, slowing
	_tap_spark_material.albedo_color = Color(1.0, 0.93, 0.6, 0.9 * (1.0 - smoothstep(0.45, 1.0, share)))
	for index in _tap_sparks.size():
		var angle: float = TAU * (float(index) + 0.25) / float(_tap_sparks.size())
		var dir: Vector3 = (right * cos(angle) + up * sin(angle)).normalized()
		var length: float = lerpf(0.05, 0.16, sin(PI * minf(share * 1.4, 1.0)))
		var spark := _tap_sparks[index]
		spark.global_transform = Transform3D(Basis(dir.cross(camera.global_basis.z).normalized() * 0.018, dir * length, camera.global_basis.z * 0.018),
			_tap_spark_at + dir * lerpf(0.07, 0.34, out))
		spark.visible = true

func _spawn_dust(at: Vector3, size: float) -> void:
	for offset in [-0.14, 0.14]:
		var puff := _dust[_next_dust]
		_dust_age[_next_dust] = 0.0
		_dust_size[_next_dust] = size
		_next_dust = (_next_dust + 1) % _dust.size()
		puff.global_position = Vector3(at.x + offset, PickleballConstants.FLOOR_Y + 0.03, at.z)
		puff.visible = true

func _update_extras(real: float) -> void:
	var nvz: float = PickleballConstants.NON_VOLLEY_ZONE
	var kitchen_in: Array[bool] = [false, false]
	var line_alpha := 0.0
	var line_slot := 0
	var playing: bool = _game.game_state == _game.GameState.PLAYING
	for index in _players.size():
		var player = _players[index]
		if not is_instance_valid(player):
			line_slot += 2
			continue
		# paddle path ring buffer
		if player.paddle_node != null:
			var head: int = _trail_head[index]
			_trail_pos[index][head] = _head_of(player)
			_trail_time[index][head] = _clock
			_trail_head[index] = (head + 1) % ARC_SAMPLES
		var velocity: Vector3 = player.current_velocity
		var planar: float = Vector2(velocity.x, velocity.z).length()
		var foot: Vector3 = player.get_global_transform_interpolated().origin
		# hard stop dust
		_peak_speed[index] = maxf(planar, _peak_speed[index] - 12.0 * real)
		if planar < 1.2 and _peak_speed[index] > 4.5:
			_peak_speed[index] = 0.0
			_spawn_dust(foot, 0.4)
		# split-step landing dust
		var controller = player.pose_controller if "pose_controller" in player else null
		if controller != null and controller.split_step != null:
			var landings: int = controller.split_step.landing_serial
			if landings != _split_landings[index]:
				_split_landings[index] = landings
				_spawn_dust(foot, 0.28)
		# kitchen occupancy
		if playing and absf(foot.z) < nvz and absf(foot.x) <= PickleballConstants.COURT_WIDTH * 0.5:
			kitchen_in[1 if foot.z > 0.0 else 0] = true
		# speed lines (dives and fast lateral shuffles)
		var driver = player.special_reach_driver
		var diving: bool = driver != null and driver.owns_movement() and driver.kind == "DIVE"
		var shuffle: bool = absf(velocity.x) > LINE_SPEED and absf(velocity.x) > absf(velocity.z) * 1.2
		var show_lines: bool = (diving or shuffle) and planar > 1.0
		for k in 2:
			var line := _lines[line_slot + k]
			line.visible = show_lines
			if not show_lines: continue
			var direction := Vector3(velocity.x, 0.0, velocity.z).normalized()
			var length := clampf(planar * 0.12, 0.5, 1.3)
			var basis := Basis.looking_at(direction, Vector3.UP).scaled_local(Vector3(0.012, 0.012, length))
			var lift: float = 0.55 + 0.5 * k
			var behind: Vector3 = foot - direction * (0.55 + length * 0.5) + Vector3(0.0, lift, 0.0) + direction.cross(Vector3.UP) * (0.12 if k == 0 else -0.12)
			line.global_transform = Transform3D(basis, behind)
			line_alpha = maxf(line_alpha, clampf((planar - 3.0) / 5.0, 0.2, 0.55))
		line_slot += 2
	_lines_material.albedo_color.a = line_alpha
	# kitchen glow
	for side in 2:
		var target: float = KITCHEN_GLOW_ALPHA if kitchen_in[side] else 0.0
		_glow_alpha[side] = move_toward(_glow_alpha[side], target, real * 0.5)
		_glow[side].visible = _glow_alpha[side] > 0.004 and not (_kitchen.visible and signf(_kitchen.global_position.z) == (1.0 if side == 1 else -1.0))
		(_glow[side].material_override as StandardMaterial3D).albedo_color.a = _glow_alpha[side]
	# swing arcs
	for index in _arcs.size():
		if not _arcs[index].visible: continue
		_arc_age[index] += real
		var share: float = _arc_age[index] / ARC_FADE
		if share >= 1.0: _arcs[index].visible = false
		else: _arc_material[index].albedo_color.a = 1.0 - share
	# label pops
	for index in _labels.size():
		var label := _labels[index]
		if not label.visible: continue
		_label_age[index] += real
		var share: float = _label_age[index] / LABEL_SECONDS
		if share >= 1.0:
			label.visible = false
			continue
		label.position.y += real * 0.5
		label.scale = Vector3.ONE * (1.0 + 0.45 * (1.0 - smoothstep(0.0, 0.25, share)))
		label.modulate.a = 1.0 - smoothstep(0.55, 1.0, share)
		LabelPill.set_alpha(label, label.modulate.a)
	# dust puffs
	for index in _dust.size():
		var puff := _dust[index]
		if not puff.visible: continue
		_dust_age[index] += real
		var share: float = _dust_age[index] / DUST_SECONDS
		if share >= 1.0:
			puff.visible = false
			continue
		var size: float = _dust_size[index] * (0.4 + 0.9 * sqrt(share))
		puff.scale = Vector3(size, size * 0.5, size)
		(puff.material_override as StandardMaterial3D).albedo_color.a = 0.35 * (1.0 - share)
	# ball height line
	var ball = _game.ball
	var show_height: bool = ball != null and ball.is_in_play and playing
	if show_height:
		var at: Vector3 = ball.get_global_transform_interpolated().origin
		var floor_y: float = PickleballConstants.FLOOR_Y + 0.02
		var height: float = at.y - floor_y
		show_height = height > 0.3
		if show_height:
			_height_line.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(0.012, height, 0.012)), Vector3(at.x, floor_y + height * 0.5, at.z))
	_height_line.visible = show_height
