extends TextureRect
## Own world and actual gameplay player/IK. Illustrative ball only; no live match objects.
const Ghosts = preload("res://scripts/ui/mobile_pose_ghosts.gd")
const ContactPreview = preload("res://scripts/ui/mobile_pose_contact_preview.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const ReadyCurve = preload("res://scripts/ready_windup_curve.gd")
const SpeedRamp = preload("res://scripts/stroke_speed_ramp.gd")
const SwingShape = preload("res://scripts/human_swing_playback.gd")
const HeldHit = preload("res://scripts/held_hit_motion.gd")
const PlaybackClock = preload("res://scripts/stroke_playback_clock.gd")
const ElbowRuntime = preload("res://scripts/elbow_preset_runtime.gd")
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const SelectedGizmo = preload("res://scripts/ui/mobile_pose_gizmo.gd")
const ARC_STEPS := 64
const READY_ARC_STEPS := 24
const LEAD_IN := 1.0   # path handle progress above this = Ready -> Wind-up lead-in (pose_studio.gd LEAD_IN)
const READY_ARC_COLOR := Color("9aa3b5")   # Ready end of the Ready -> Wind-up lead-in
const STAGE_NAMES := ["Wind-up", "Contact", "Finish"]
const GHOST_SCALE := 0.65
const GHOST_ALPHA := 0.12
const STAGE_COLORS := [Color("bd80ff"), Color("ffdc62"), Color("58dfdb")]
signal joint_selected(id: String)
const JOINT_NAMES := {
	"right_elbow": "Right elbow", "left_elbow": "Left elbow",
	"right_knee": "Right knee", "left_knee": "Left knee",
	"right_foot": "Right foot", "left_foot": "Left foot",
	"right_hand": "Right hand", "left_hand": "Left hand",
	"hips": "Hips", "torso": "Upper body", "head": "Head", "paddle": "Paddle",
}
const SELECT_COLOR := Color("71f5da")
var selected_joint := ""
var gizmo
var contact_preview: Node3D
var _contact_definition: PostureDefinition
var _contact_style := -1
var _contact_enabled := false
var _preview_progress := .5
var _joint_nodes: Dictionary = {}
# Every joint shares the paddle's solved sample pass. Selection only swaps a
# cached curve; scrubbing/playback and camera changes never run extra IK.
var joint_samples: Dictionary = {}
# The elapsed preview may use a runtime/variant stroke unlike the editable-key
# ghosts. Cache its solved joints separately; never relabel authored samples as
# the displayed motion or change the editable key/ghost/gizmo coordinate system.
var context_joint_samples: Dictionary = {}
var joint_context_rebuild_count := 0
var _joint_context_signature := ""
var _joint_context_motion_revision := -1
var selected_joint_samples := PackedVector3Array()
var selected_joint_has_motion := false
const JOINT_MOTION_EPSILON_SQUARED := 0.00000001

# All motion geometry belongs to this editor's SubViewport. It is allocated only
# for an enabled stroke and survives scrubbing/camera changes without rebuilding.
var inbetween_count := 0
var inbetween_sample_indices := PackedInt32Array()
var _inbetween_root: Node3D
var _inbetween_dirty := true
var motion_root: Node3D
var sample_heads: PackedVector3Array = PackedVector3Array()
var ready_heads: PackedVector3Array = PackedVector3Array()   # Ready -> Wind-up lead-in, paddle head
var ghost_transforms: Array[Transform3D] = []
var motion_rebuild_count := 0
var motion_sampler: Callable
var _motion_definition: PostureDefinition
var _motion_enabled := false
var _motion_snapshot: PackedByteArray = PackedByteArray()
var _ghosts_visible := true
var _arc_visible := true
var _ghost_root: Node3D
var _ghosts: Array[Node3D] = []
var _arc: MeshInstance3D
var _arc_mesh: ImmediateMesh
var _setup_finished := false
## Momentum arc (Pose Studio): the paddle head at every game tick (1/30 s) of the swing the game
## plays at full charge (Ready -> Wind-up -> Contact -> Finish: mobile_pose_sequence's runtime
## motion), so the dot spacing is the paddle's speed. While on it replaces the authored-key tube.
const Sequence = preload("res://scripts/ui/mobile_pose_sequence.gd")
const TICK := 1.0 / 30.0
var momentum_on := false
var momentum_heads := PackedVector3Array()       # one per tick from Ready
var momentum_keys := PackedVector3Array()        # Wind-up, Contact, Finish heads (exact times)
var momentum_key_times := PackedFloat32Array()   # their seconds from Ready
var momentum_contact_speed := 0.0                # m/s: peak paddle-head speed of the strike
var momentum_rebuild_count := 0
var momentum_progress := PackedFloat32Array()   # stroke progress of each tick (-1 before Wind-up)
const TIMING_PREFIX := "speed_"                  # PostureDefinition fields that change timing only (stroke_speed_ramp.gd)
const RETIME_LEAD := 48                          # table sizes for the speed-only re-time
const RETIME_STROKE := 64
var _geo_snapshot := PackedByteArray()           # the definition without its timing fields
var _retime_lead := PackedVector3Array()         # solved heads over the lead-in blend (0..1)
var _retime_stroke := PackedVector3Array()       # solved heads over the stroke progress (0..1)
var _retime_w := 0.0; var _retime_release := 0.0; var _retime_stroke_s := 0.0
var _retime_finish: PostureDefinition; var _retime_ready: PostureDefinition
var momentum_retime_count := 0
var momentum_retime_dirty := false               # the arc shows re-timed (approximate) heads
var momentum_retime_frame := 0                   # process frame of the last re-time
var _settling := false
var momentum_retime_usec := 0
var momentum_path_tan := PackedVector3Array()   # path handles: solved world direction per unit progress (keys; zero for bend points)
const TAN_STEP := 0.015                            # progress step for that direction (central difference)
var momentum_path_t := PackedFloat32Array()      # path handles: the keys' progress, then bend points
var momentum_path_heads := PackedVector3Array()  # their heads on the arc
var momentum_path_virtual := PackedByteArray()   # 1 = a bend point (no key there yet)
var viewport: SubViewport
var player
var camera: Camera3D
var yaw := 2.8
var pitch := 0.08
var distance := 2.9
# Orbit centre. The phone editor never changes it; the desktop studio moves it (pan, F).
var camera_target := Vector3(0, 1.0, 0)
const CameraFraming = preload("res://scripts/ui/mobile_pose_camera_framing.gd")
var _fitted_distance := 2.9
var _manual_zoom := false
var _camera_fit_pending := false
var _touch := -1
var _mouse := false
var pose: PostureDefinition
func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	viewport = SubViewport.new(); viewport.name = "IsolatedPoseViewport"
	viewport.own_world_3d = true; viewport.gui_disable_input = true
	viewport.physics_object_picking = false; viewport.size = Vector2i(640,360)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport); texture = viewport.get_texture()
	var world := Node3D.new(); world.name = "PosePreviewWorld"; viewport.add_child(world)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("182f3c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b8d0de")
	environment.environment.ambient_light_energy = .8; world.add_child(environment)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45,-35,0)
	sun.light_energy = 1.2; world.add_child(sun)
	var floor_mesh := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size=Vector2(20,20)
	floor_mesh.mesh = plane
	var material:=StandardMaterial3D.new();material.albedo_color=Color("244958");material.roughness=1
	floor_mesh.material_override=material; world.add_child(floor_mesh)
	player = load("res://scripts/player.gd").new(); player.name = "IsolatedPreviewPlayer"; world.add_child(player)
	player.setup(0,{"left":-10.0,"right":10.0,"top":-10.0,"bottom":10.0},Color("3985d9"),Vector3(0,1,0),true)
	player.posture.editor_preview_mode = true
	player.set_meta(ElbowRuntime.PRIVATE_PREVIEW_META,true)
	_disable_simulation(player)
	_cache_joint_nodes()
	camera=Camera3D.new();camera.fov=40;world.add_child(camera);camera.current=true
	gizmo=SelectedGizmo.new();gizmo.preview=self;add_child(gizmo)
	resized.connect(_resize_view); gui_input.connect(_camera_input); _resize_view(); update_camera(); call_deferred("_finish_setup")
func _finish_setup()->void:
	# BodyBuilder wires its hitbox with a deferred call; reassert the private
	# preview after that setup instead of leaving its initial paddle-at-side.
	_disable_simulation(player)
	_setup_finished = true
	if pose:show_pose(pose)
	_refresh_motion()
	_refresh_contact()

func _disable_simulation(node:Node)->void:
	node.set_process(false);node.set_physics_process(false)
	node.set_process_input(false);node.set_process_unhandled_input(false);node.set_process_unhandled_key_input(false)
	if node is CollisionObject3D: node.collision_layer=0;node.collision_mask=0
	if node is Area3D: node.monitoring=false;node.monitorable=false
	for child in node.get_children():_disable_simulation(child)
## Pose Studio: every pose drawn here passes through the rules the game lays over a human swing
## (human_swing_playback.layers: the forehand's forced body turn), so the key view, Hold, Play
## and AutoPose all show what a match shows. Off for the plain mobile editor.
var game_layers := false
func present(value: PostureDefinition) -> PostureDefinition:
	return SwingShape.layers(value) if game_layers and value != null else value

func show_pose(value:PostureDefinition)->void:
	pose=value
	if player==null:return
	var drawn: PostureDefinition = present(value)
	player.posture.transition_pose_blend=drawn
	player.posture.force_posture_update(drawn)
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	queue_redraw()
	if gizmo:gizmo.sync_scene()

func _cache_joint_nodes() -> void:
	# Follow the displayed IK rig, not the separate reference Skeleton3D or
	# authored targets that can differ after reach and floor constraints.
	_joint_nodes = {
		"right_elbow": player.right_arm_node.forearm_pivot,
		"left_elbow": player.left_arm_node.forearm_pivot,
		"right_hand": player.right_arm_node.hand_pivot,
		"left_hand": player.left_arm_node.hand_pivot,
		"right_knee": player.right_leg_node.shin_pivot,
		"left_knee": player.left_leg_node.shin_pivot,
		"right_foot": player.right_leg_node.foot_mesh,
		"left_foot": player.left_leg_node.foot_mesh,
		"hips": player.body_pivot.get_node("HipsMesh"),
		"torso": player.body_pivot.get_node("TorsoMesh"),
		"head": player.body_pivot.get_node("TorsoMesh/HeadMesh"),
		"paddle": player.paddle_node.get_node("Head"),
	}

func select_joint(id: String) -> void:
	if not JOINT_NAMES.has(id) or selected_joint == id: return
	selected_joint = id
	cancel_gesture()
	_refresh_selected_joint_motion()
	queue_redraw()
	joint_selected.emit(id)

func joint_world_position(id: String) -> Vector3:
	var node: Node3D = _joint_nodes.get(id)
	if not is_instance_valid(node): return Vector3.INF
	if player != null and (node == player.right_arm_node.forearm_pivot or node == player.left_arm_node.forearm_pivot):
		return preload("res://scripts/elbow_swivel.gd").visual_elbow_now(player.right_arm_node if node == player.right_arm_node.forearm_pivot else player.left_arm_node)   # drawn elbow
	return node.global_position

func joint_screen_position(id: String) -> Vector2:
	return _world_screen_position(joint_world_position(id))

func _world_screen_position(world_position: Vector3) -> Vector2:
	if camera == null or viewport == null or not world_position.is_finite(): return Vector2.INF
	if camera.is_position_behind(world_position): return Vector2.INF
	# GUI events and drawing use TextureRect-local units. The viewport texture
	# stretches independently on each axis, including during rotation/resizing.
	return camera.unproject_position(world_position) * size / Vector2(viewport.size)

func _draw() -> void:
	if camera == null: return
	_draw_selected_joint_motion()
	if gizmo and gizmo.visible and gizmo.enabled: return
	var rect := Rect2(Vector2.ZERO, size)
	var selected_point: Vector2 = joint_screen_position(selected_joint)
	if not selected_point.is_finite() or not rect.has_point(selected_point): return
	draw_arc(selected_point, 17.0, 0.0, TAU, 40, Color("122630"), 6.0, true)
	draw_arc(selected_point, 17.0, 0.0, TAU, 40, SELECT_COLOR, 3.0, true)
	# Keep the selection ring; viewport annotations intentionally stay absent.

func _refresh_selected_joint_motion() -> void:
	var samples: Dictionary = context_joint_samples if not _joint_context_signature.is_empty() else joint_samples
	selected_joint_samples = samples.get(selected_joint, PackedVector3Array()) if _motion_enabled else PackedVector3Array()
	selected_joint_has_motion = false
	if selected_joint_samples.is_empty(): return
	var first: Vector3 = selected_joint_samples[0]
	for point in selected_joint_samples:
		if first.is_finite() and point.is_finite() and first.distance_squared_to(point) > JOINT_MOTION_EPSILON_SQUARED:
			selected_joint_has_motion = true
			break

func set_joint_motion_context(sampler: Callable, signature: String) -> void:
	# The caller's signature describes the pose, preview options and accepted
	# candidate, never elapsed time or camera. Reuse this cache while scrubbing.
	if signature == _joint_context_signature and _joint_context_motion_revision == motion_rebuild_count: return
	_joint_context_signature = signature
	_joint_context_motion_revision = motion_rebuild_count
	context_joint_samples.clear()
	if not signature.is_empty() and sampler.is_valid() and _motion_enabled and _setup_finished:
		var displayed_pose: PostureDefinition = pose
		for id in JOINT_NAMES: context_joint_samples[id] = PackedVector3Array()
		for index in range(ARC_STEPS + 1):
			var sample: PostureDefinition = sampler.call(float(index) / ARC_STEPS)
			player.posture.transition_pose_blend = present(sample)
			player.posture.force_posture_update(present(sample))
			for id in JOINT_NAMES: context_joint_samples[id].append(joint_world_position(id))
		if displayed_pose != null: show_pose(displayed_pose)
		joint_context_rebuild_count += 1
	_refresh_selected_joint_motion()
	queue_redraw()

func _draw_selected_joint_motion() -> void:
	if not _arc_visible or not _motion_enabled or not selected_joint_has_motion: return
	# Screen-space thickness stays legible on a phone at every zoom. Each point
	# is still the actual 3D solved joint, projected through the orbit camera.
	var points := PackedVector2Array()
	for point in selected_joint_samples: points.append(_world_screen_position(point))
	for index in range(points.size() - 1):
		if not points[index].is_finite() or not points[index + 1].is_finite(): continue
		draw_line(points[index], points[index + 1], Color("122630"), 6.5, true)
	for index in range(points.size() - 1):
		if not points[index].is_finite() or not points[index + 1].is_finite(): continue
		draw_line(points[index], points[index + 1], SELECT_COLOR, 3.0, true)
	for stage in range(3):
		var point: Vector2 = points[stage * ARC_STEPS / 2]
		if not point.is_finite() or not Rect2(Vector2.ZERO, size).has_point(point): continue
		_draw_joint_stage_marker(point, stage)

func _draw_joint_stage_marker(point: Vector2, stage: int) -> void:
	# Different silhouettes as well as colors distinguish coincident phases.
	var radius: float = 5.0 + stage * 1.0
	if stage == 0:
		draw_arc(point, radius, 0.0, TAU, 24, Color(Color("122630"), 0.35), 3.0, true)
		draw_arc(point, radius, 0.0, TAU, 24, Color(STAGE_COLORS[stage], 0.48), 1.5, true)
	else:
		var outline := PackedVector2Array()
		var offset: float = 0.0 if stage == 1 else PI * .25
		for corner in range(5): outline.append(point + Vector2.from_angle(offset + corner * PI * .5) * radius)
		draw_polyline(outline, Color(Color("122630"), 0.35), 3.0, true)
		draw_polyline(outline, Color(STAGE_COLORS[stage], 0.48), 1.5, true)

func set_motion(def: PostureDefinition, enabled: bool = true) -> void:
	_motion_definition = def
	# Ready is a single stance even though it lives in the stroke library. Body
	# stances are passed with enabled=false by the editor.
	_motion_enabled = enabled and def != null and def.posture_id != 20
	_refresh_motion()

func set_motion_sampler(value: Callable) -> void:
	if motion_sampler == value: return
	motion_sampler = value
	_motion_snapshot = PackedByteArray(); _geo_snapshot = PackedByteArray()

func set_inbetween_count(value: int) -> void:
	inbetween_count = clampi(value, 0, Ghosts.MAX_PER_GAP)
	_inbetween_dirty = true
	inbetween_sample_indices.clear()
	# Select uniformly spaced samples inside each half of the already solved
	# 65-point motion. Never repeat the three editable anchors (0, 32, 64).
	for gap in range(2):
		for slot in range(inbetween_count):
			inbetween_sample_indices.append(gap * 32 + roundi(float(slot + 1) * 32.0 / float(inbetween_count + 1)))
	_refresh_inbetween()
	_request_redraw()

func _refresh_inbetween() -> void:
	if _inbetween_root:
		_inbetween_root.display_indices(inbetween_sample_indices if _motion_enabled and _ghosts_visible else PackedInt32Array())
		if _motion_enabled: _inbetween_dirty = false

func set_ghosts_visible(value: bool) -> void:
	_ghosts_visible = value
	if _ghost_root: _ghost_root.visible = value
	_refresh_inbetween()
	_request_redraw()

func set_arc_visible(value: bool) -> void:
	_arc_visible = value
	_refresh_selected_joint_motion()
	if _arc: _arc.visible = value
	_request_redraw()

func _refresh_motion() -> void:
	if motion_root: motion_root.visible = _motion_enabled
	if _inbetween_root: _inbetween_root.visible = _motion_enabled and _ghosts_visible and inbetween_count > 0
	if _inbetween_dirty and _motion_enabled: _refresh_inbetween()
	if not _motion_enabled or not _setup_finished:
		momentum_heads.clear(); momentum_keys.clear(); momentum_key_times.clear(); momentum_contact_speed = 0.0
		_refresh_selected_joint_motion()
		_request_redraw()
		return
	var state: Dictionary = _resource_state(_motion_definition)
	var snapshot: PackedByteArray = var_to_bytes(state)
	if motion_root == null or snapshot != _motion_snapshot:
		# Speed ramp fields change when the paddle is where, never the path: when only they
		# changed, re-time the arc from a table of solved heads instead of solving every sample.
		for field in state.keys(): if String(field).begins_with(TIMING_PREFIX): state.erase(field)
		var geometry: PackedByteArray = var_to_bytes(state)
		var timing_only: bool = motion_root != null and geometry == _geo_snapshot and momentum_heads.size() > 1 and not _settling
		if geometry != _geo_snapshot: _retime_lead.clear(); _retime_stroke.clear()
		_ensure_motion_visuals()
		if timing_only and Sequence.swing_hold >= 0.0 and _momentum_supported():
			# My swing (Pose Studio Hold / Play) is a baked sequence, not a table by progress: the
			# tick heads are solved again, but the 65-sample key arc and the ghosts are not.
			var shown: PostureDefinition = pose if pose != null else _motion_definition
			_rebuild_momentum()
			show_pose(shown)
			_rebuild_arc_mesh()
			momentum_retime_dirty = false
		elif timing_only and _retime_momentum():
			momentum_retime_dirty = true; momentum_retime_frame = Engine.get_process_frames()
		else:
			_rebuild_motion()
			momentum_retime_dirty = false
		_motion_snapshot = snapshot; _geo_snapshot = geometry
	_refresh_selected_joint_motion()
	motion_root.visible = true
	_request_redraw()

## The play situation changed (Pose Studio's hold length): every cache built from a played
## sequence is dropped and the arc rebuilt.
func play_context_changed() -> void:
	_motion_snapshot = PackedByteArray(); _geo_snapshot = PackedByteArray()
	_retime_lead.clear(); _retime_stroke.clear()
	_refresh_motion()

## After speed-only re-times (a fast table lookup, a few mm off at kinks): one exact rebuild,
## keeping the tables for the next drag. The speed graph calls it once the edit rests.
func settle_motion() -> void:
	if not momentum_retime_dirty or not _motion_enabled or not _setup_finished: return
	_settling = true
	_motion_snapshot = PackedByteArray()
	_refresh_motion()
	_settling = false

func _resource_state(resource: Resource) -> Dictionary:
	# Definitions are edited in place, including nested body keyframe dictionaries.
	# Comparing object identity or Resource.changed misses those edits.
	var state: Dictionary = {}
	for property in resource.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_STORAGE): continue
		if not (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
		var value = resource.get(property.name)
		state[property.name] = _resource_state(value) if value is Resource else value
	return state

func _ensure_motion_visuals() -> void:
	if motion_root: return
	motion_root = Node3D.new()
	motion_root.name = "EditorStrokeMotion"
	player.get_parent().add_child(motion_root)
	_inbetween_root = Ghosts.new()
	_inbetween_root.name = "InbetweenBodyGhosts"
	motion_root.add_child(_inbetween_root)
	_inbetween_root.initialize(player)
	_inbetween_root.visible = false
	_ghost_root = Node3D.new()
	_ghost_root.name = "ThreePaddleGhosts"
	motion_root.add_child(_ghost_root)
	_ghost_root.visible = _ghosts_visible
	_arc = MeshInstance3D.new()
	_arc.name = "SampledPaddleHeadArc"
	_arc_mesh = ImmediateMesh.new()
	_arc.mesh = _arc_mesh
	_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var arc_material: StandardMaterial3D = _motion_material(Color.WHITE, 0.86)
	arc_material.vertex_color_use_as_albedo = true
	_arc.material_override = arc_material
	motion_root.add_child(_arc)
	_arc.visible = _arc_visible
	for stage in range(3):
		var ghost := Node3D.new()
		ghost.name = ["WindupPaddleGhost", "ContactPaddleGhost", "FinishPaddleGhost"][stage]
		_ghost_root.add_child(ghost)
		# Reuse the same actual paddle meshes/local transforms as the displayed rig.
		# Never instantiate a physical paddle or retain any collision/script nodes.
		_copy_paddle_meshes(player.paddle_node, ghost, player.paddle_node,
			_motion_material(STAGE_COLORS[stage], GHOST_ALPHA))
		_ghosts.append(ghost)

func _copy_paddle_meshes(source: Node, target: Node3D, paddle: Node3D, material: Material) -> void:
	if source is MeshInstance3D and source.mesh != null:
		var copy := MeshInstance3D.new()
		copy.name = source.name
		copy.mesh = source.mesh
		copy.material_override = material
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		target.add_child(copy)
		copy.transform = paddle.global_transform.affine_inverse() * source.global_transform
	for child in source.get_children():
		_copy_paddle_meshes(child, target, paddle, material)

func _rebuild_motion() -> void:
	var displayed_pose: PostureDefinition = pose if pose != null else _motion_definition
	sample_heads.clear()
	ghost_transforms.clear()
	joint_samples.clear()
	_inbetween_root.begin_samples()
	for id in JOINT_NAMES: joint_samples[id] = PackedVector3Array()
	# The full real preview solver includes reach/floor and body/IK adjustments.
	# An authored-offset curve (or an endpoint-only shortcut) can disagree with
	# the visible paddle, so read the rendered head after every solved sample.
	for index in range(ARC_STEPS + 1):
		var sample: PostureDefinition = motion_sampler.call(_motion_definition, float(index) / ARC_STEPS) if motion_sampler.is_valid() else Path.sample(_motion_definition, float(index) / ARC_STEPS)
		player.posture.transition_pose_blend = present(sample)
		player.posture.force_posture_update(present(sample))
		_inbetween_root.capture_sample()
		var paddle_transform: Transform3D = player.paddle_node.global_transform
		sample_heads.append(paddle_transform * PaddleSize.HEAD_OFFSET)
		for id in JOINT_NAMES: joint_samples[id].append(joint_world_position(id))
		if index in [0, ARC_STEPS / 2, ARC_STEPS]:
			ghost_transforms.append(paddle_transform)
	_rebuild_momentum()
	# Ready -> Wind-up lead-in when the momentum arc (which already starts at Ready) is off.
	# Plain strokes only: serves, variants and ball actions have their own samplers / no Ready
	# start. Same sampler as playback and the held-Hit wind-up.
	ready_heads.clear()
	if momentum_heads.size() <= 1 and not motion_sampler.is_valid() and _motion_definition.posture_id < 90:
		var ready_def: PostureDefinition = PostureLibrary.instance().get_def(20)
		if ready_def != null:
			var windup: PostureDefinition = Path.sample(_motion_definition, 0.0)
			for index in range(READY_ARC_STEPS + 1):
				var sample: PostureDefinition = ReadyCurve.sample(ready_def, windup, float(index) / READY_ARC_STEPS)
				player.posture.transition_pose_blend = present(sample)
				player.posture.force_posture_update(present(sample))
				ready_heads.append(player.paddle_node.global_transform * PaddleSize.HEAD_OFFSET)
	# Sampling is synchronous and invisible between viewport draws. Restore the
	# exact current scrub/play pose, not Contact or the final sampled keyframe.
	show_pose(displayed_pose)
	for stage in range(3):
		# Scale only the render proxy around its head center. Solved transforms,
		# paddle path and joint picking retain their original physical coordinates.
		var actual: Transform3D = ghost_transforms[stage]
		var reduced_basis := actual.basis.scaled(Vector3.ONE * GHOST_SCALE)
		_ghosts[stage].global_transform = Transform3D(reduced_basis,
			actual * PaddleSize.HEAD_OFFSET - reduced_basis * PaddleSize.HEAD_OFFSET)
	_rebuild_arc_mesh()
	_refresh_inbetween()
	motion_rebuild_count += 1

func _rebuild_arc_mesh() -> void:
	_arc_mesh.clear_surfaces()
	var line: Array = _momentum_line() if momentum_heads.size() > 1 else [sample_heads, range(ARC_STEPS + 1).map(func(i): return _motion_color(float(i) / ARC_STEPS))]
	var pts: PackedVector3Array = line[0]
	var has_motion := false
	for index in range(pts.size() - 1):
		if pts[index].distance_squared_to(pts[index + 1]) > 0.00000001:
			has_motion = true
			break
	if has_motion:
		_arc_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in range(pts.size() - 1):
			_add_arc_segment(_arc.to_local(pts[index]), _arc.to_local(pts[index + 1]), line[1][index], line[1][index + 1])
		_arc_mesh.surface_end()
	if ready_heads.size() > 1 and ready_heads[0].distance_squared_to(ready_heads[-1]) > 0.00000001:
		_arc_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in range(ready_heads.size() - 1):
			_add_arc_segment(_arc.to_local(ready_heads[index]), _arc.to_local(ready_heads[index + 1]),
				READY_ARC_COLOR.lerp(STAGE_COLORS[0], float(index) / READY_ARC_STEPS), READY_ARC_COLOR.lerp(STAGE_COLORS[0], float(index + 1) / READY_ARC_STEPS))
		_arc_mesh.surface_end()

## Speed-only change: the tick heads again from dense tables of solved heads (lead-in by blend
## progress, stroke by stroke progress), built once per path shape. No pose is solved per tick,
## so a speed drag stays smooth. False = not a plain stroke: the caller rebuilds everything.
func _retime_momentum() -> bool:
	if not _momentum_supported(): return false
	var t0 := Time.get_ticks_usec()
	if not _ensure_retime_tables(): return false
	var w: float = _retime_w
	var end: float = w + _retime_stroke_s
	var def: PostureDefinition = _motion_definition
	var lead_custom: bool = SpeedRamp.custom(def, SpeedRamp.LEAD)
	momentum_heads.clear(); momentum_progress.clear(); momentum_contact_speed = 0.0
	for i in ceili(end / TICK - 0.001) + 1:
		var t: float = minf(i * TICK, end)
		if i * TICK < w:   # as mobile_pose_sequence.lead_progress
			var u: float = SpeedRamp.lead(def, t / HeldHit.WINDUP_SECONDS) if lead_custom else smoothstep(0.0, HeldHit.WINDUP_SECONDS, t)
			momentum_heads.append(_table_head(_retime_lead, u)); momentum_progress.append(-1.0)
		else:
			var p: float = clampf(float(PlaybackClock.state(def, t - w, _retime_finish, _retime_ready).progress), 0.0, 1.0)
			momentum_heads.append(_table_head(_retime_stroke, p)); momentum_progress.append(p)
	for i in range(floori(w / TICK), mini(ceili((w + _retime_release) / TICK), momentum_heads.size() - 1)):
		momentum_contact_speed = maxf(momentum_contact_speed, momentum_heads[i].distance_to(momentum_heads[i + 1]) / TICK)
	_rebuild_arc_mesh()
	momentum_rebuild_count += 1; momentum_retime_count += 1
	momentum_retime_usec = Time.get_ticks_usec() - t0
	PerfMonitor.record("studio.momentum_retime", momentum_retime_usec)
	return true

## The tables of solved heads along the path (and the durations kept with them); false when
## this is not a plain stroke.
func _ensure_retime_tables() -> bool:
	if not _retime_stroke.is_empty(): return true
	if not _momentum_supported(): return false
	var seq = Sequence.new()
	seq.configure(_motion_definition, Sequence.Mode.STROKE, Sequence.Stance.AUTHORED, 0, true, player)
	if seq.style >= 0 or seq.variant != null or seq.ready == null: return false
	var displayed_pose: PostureDefinition = pose if pose != null else _motion_definition
	var windup: PostureDefinition = seq._stroke_pose(0.0)
	for i in RETIME_LEAD + 1:
		_retime_lead.append(_solved_head(seq.scoped_pose(seq._stance_copy(ReadyCurve.sample(seq.ready, windup, float(i) / RETIME_LEAD)))))
	for i in RETIME_STROKE + 1:
		_retime_stroke.append(_solved_head(seq.scoped_pose(seq._stance_copy(seq._stroke_pose(float(i) / RETIME_STROKE)))))
	show_pose(displayed_pose)
	# Durations and the end poses do not depend on the speed fields: kept with the tables.
	_retime_w = seq.prefix_seconds; _retime_release = seq.release_seconds; _retime_stroke_s = seq.stroke_seconds
	_retime_finish = seq.finish; _retime_ready = seq.ready
	return true

## Paddle-head path length (m) of the three motion parts [Ready -> Wind-up, strike, follow-through]
## and their durations (s): the speed graph's real-speed scale. Empty when not a plain stroke.
func part_lengths() -> Dictionary:
	if not _motion_enabled or not _setup_finished or motion_root == null or not _ensure_retime_tables(): return {}
	var length := func(t: PackedVector3Array, a: int, b: int) -> float:
		var sum := 0.0
		for i in range(a, b): sum += t[i].distance_to(t[i + 1])
		return sum
	var mid: int = RETIME_STROKE / 2
	return {"lengths": [length.call(_retime_lead, 0, RETIME_LEAD), length.call(_retime_stroke, 0, mid), length.call(_retime_stroke, mid, RETIME_STROKE)],
		"seconds": [_retime_w, _retime_release, _retime_stroke_s - _retime_release]}

## Catmull-Rom through the table (uniform in x): follows the curve between entries.
static func _table_head(table: PackedVector3Array, x: float) -> Vector3:
	var n := table.size()
	var f: float = clampf(x, 0.0, 1.0) * float(n - 1)
	var i: int = mini(int(f), n - 2)
	var u: float = f - float(i)
	var p0: Vector3 = table[maxi(i - 1, 0)]; var p1: Vector3 = table[i]; var p2: Vector3 = table[i + 1]; var p3: Vector3 = table[mini(i + 2, n - 1)]
	return 0.5 * ((2.0 * p1) + (p2 - p0) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (3.0 * p1 - p0 - 3.0 * p2 + p3) * u * u * u)

func set_momentum(on: bool) -> void:
	if momentum_on == on: return
	momentum_on = on
	_motion_snapshot = PackedByteArray(); _geo_snapshot = PackedByteArray()   # rebuild the arc either way
	_refresh_motion()

func _momentum_supported() -> bool:
	return momentum_on and _motion_enabled and _motion_definition != null and _motion_definition.get("action_id") == null

func _solved_head(p: PostureDefinition) -> Vector3:
	player.posture.transition_pose_blend = present(p)
	player.posture.force_posture_update(present(p))
	return player.paddle_node.global_transform * PaddleSize.HEAD_OFFSET

func _rebuild_momentum() -> void:
	momentum_heads.clear(); momentum_keys.clear(); momentum_key_times.clear(); momentum_contact_speed = 0.0
	momentum_progress.clear(); momentum_path_t.clear(); momentum_path_heads.clear(); momentum_path_virtual.clear(); momentum_path_tan.clear()
	if not _momentum_supported(): return
	var t0 := Time.get_ticks_usec()
	var seq = Sequence.new()
	seq.configure(_motion_definition, Sequence.Mode.STROKE, Sequence.Stance.AUTHORED, 0, true, player)
	var w: float = seq.prefix_seconds
	var times := [w, w + seq.release_seconds, w + seq.stroke_seconds]
	for i in ceili(times[2] / TICK - 0.001) + 1:
		var smp: Dictionary = seq.sample(minf(i * TICK, times[2]))
		momentum_heads.append(_solved_head(smp.pose))
		momentum_progress.append(float(smp.progress) if i * TICK >= w else -1.0)
	# Path handles (strokes): every key, plus a bend point in the middle of each half without one.
	if seq.style < 0:
		var ks: Array = Array(_motion_definition.paddle_path_times)
		var pts: Array = []
		for k in ks: pts.append([float(k), 0])
		for mid in [0.25, 0.75]:
			if not ks.any(func(k): return absf(float(k) - mid) < 0.08): pts.append([mid, 1])
		for p in pts:
			momentum_path_t.append(p[0]); momentum_path_virtual.append(p[1])
			momentum_path_heads.append(_solved_head(seq._stroke_pose(p[0])))
			# Solved path direction through a key (world metres per unit progress): tangent handles.
			var tan := Vector3.ZERO
			if p[1] == 0:
				var a: float = maxf(p[0] - TAN_STEP, 0.0); var b: float = minf(p[0] + TAN_STEP, 1.0)
				tan = (_solved_head(seq._stroke_pose(b)) - _solved_head(seq._stroke_pose(a))) / maxf(b - a, 0.001)
			momentum_path_tan.append(tan)
		# Ready -> Wind-up lead-in handles (progress LEAD_IN + v, v 0 = Ready .. 1 = Wind-up): its keys,
		# plus a bend point in the middle when it has none.
		if seq.ready != null and seq.variant == null:
			var windup: PostureDefinition = seq._stroke_pose(0.0)
			var lead: Array = []
			for k in _motion_definition.ready_path_times: lead.append([float(k), 0])
			if not lead.any(func(k): return absf(float(k[0]) - 0.5) < 0.15): lead.append([0.5, 1])
			for p in lead:
				momentum_path_t.append(LEAD_IN + p[0]); momentum_path_virtual.append(p[1])
				momentum_path_heads.append(_solved_head(ReadyCurve.sample(seq.ready, windup, p[0])))
				var tan := Vector3.ZERO
				if p[1] == 0:
					var a: float = maxf(p[0] - TAN_STEP, 0.0); var b: float = minf(p[0] + TAN_STEP, 1.0)
					tan = (_solved_head(ReadyCurve.sample(seq.ready, windup, b)) - _solved_head(ReadyCurve.sample(seq.ready, windup, a))) / maxf(b - a, 0.001)
				momentum_path_tan.append(tan)
	for t in times:
		momentum_key_times.append(t); momentum_keys.append(_solved_head(seq.sample(t).pose))
	# Peak paddle-head speed of the strike (Wind-up -> Contact), one tick at a time. (The strike
	# eases into Contact, so the speed at the Contact instant itself says little.)
	for i in range(floori(times[0] / TICK), mini(ceili(times[1] / TICK), momentum_heads.size() - 1)):
		momentum_contact_speed = maxf(momentum_contact_speed, momentum_heads[i].distance_to(momentum_heads[i + 1]) / TICK)
	momentum_rebuild_count += 1
	PerfMonitor.record("studio.momentum_arc", Time.get_ticks_usec() - t0)

## Tube points through the tick heads (Catmull-Rom, 4 per tick) and their colours: grey from
## Ready, then the Wind-up -> Contact -> Finish colours.
func _momentum_line() -> Array:
	var h := momentum_heads
	var pts := PackedVector3Array()
	var cols: Array = []
	var w: float = momentum_key_times[0]; var c: float = momentum_key_times[1]; var f: float = momentum_key_times[2]
	for i in h.size() - 1:
		var p0: Vector3 = h[maxi(i - 1, 0)]; var p1: Vector3 = h[i]; var p2: Vector3 = h[i + 1]; var p3: Vector3 = h[mini(i + 2, h.size() - 1)]
		for k in 4:
			var u := k / 4.0
			pts.append(0.5 * ((2.0 * p1) + (p2 - p0) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (3.0 * p1 - p0 - 3.0 * p2 + p3) * u * u * u))
			var t := minf((i + u) * TICK, f)
			cols.append(Color(0.62, 0.66, 0.70).lerp(STAGE_COLORS[0], t / maxf(w, 0.001)) if t < w else _motion_color(0.5 * (t - w) / maxf(c - w, 0.001) if t < c else 0.5 + 0.5 * (t - c) / maxf(f - c, 0.001)))
	pts.append(h[h.size() - 1]); cols.append(STAGE_COLORS[2])
	return [pts, cols]

func _motion_color(progress: float) -> Color:
	return STAGE_COLORS[0].lerp(STAGE_COLORS[1], progress * 2.0) if progress <= 0.5 else STAGE_COLORS[1].lerp(STAGE_COLORS[2], (progress - 0.5) * 2.0)

func _add_arc_segment(a: Vector3, b: Vector3, ca: Color, cb: Color) -> void:
	var tangent: Vector3 = b - a
	if tangent.length_squared() < 0.00000001: return
	var direction: Vector3 = tangent.normalized()
	var side: Vector3 = direction.cross(Vector3.UP)
	if side.length_squared() < 0.001: side = direction.cross(Vector3.RIGHT)
	side = side.normalized() * 0.007
	var up: Vector3 = direction.cross(side).normalized() * 0.007
	# A small solid tube remains readable from all orbit angles on mobile;
	# hardware line primitives are often only a single device pixel wide.
	for face in range(6):
		var angle: float = TAU * face / 6.0
		var next: float = TAU * (face + 1) / 6.0
		var v0: Vector3 = side * cos(angle) + up * sin(angle)
		var v1: Vector3 = side * cos(next) + up * sin(next)
		for vertex in [[a + v0, ca], [b + v0, cb], [b + v1, cb], [a + v0, ca], [b + v1, cb], [a + v1, ca]]:
			_arc_mesh.surface_set_color(vertex[1])
			_arc_mesh.surface_add_vertex(vertex[0])

func _motion_material(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color, alpha)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = 1
	return material

func _request_redraw() -> void:
	if viewport: viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()
	if gizmo:gizmo.sync_scene()

func request_camera_fit()->void:
	if _manual_zoom or _camera_fit_pending:return
	_camera_fit_pending=true;call_deferred("_fit_camera_to_pose")

func _fit_camera_to_pose()->void:
	_camera_fit_pending=false
	if _manual_zoom or camera==null or player==null or pose==null:return
	# Preserve the authored camera orientation. Only the default distance adapts.
	_fitted_distance=distance;update_camera()
	for iteration in range(3):
		_fitted_distance=CameraFraming.distance_for(self,camera_target,distance)
		update_camera()

func _resize_view()->void:
	if viewport:
		viewport.size=Vector2i(maxi(2,roundi(size.x)),maxi(2,roundi(size.y)))
		viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	queue_redraw();request_camera_fit()
func update_camera()->void:
	if camera==null:return
	var target:=camera_target
	camera.position=target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*(distance if _manual_zoom else maxf(distance,_fitted_distance))
	camera.look_at(target);viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	queue_redraw()
	if gizmo:gizmo.sync_scene()
func view(direction:String)->void:
	cancel_gesture()
	pitch=.08
	match direction:
		"front":yaw=PI
		"side":yaw=PI*.5
		"back":yaw=0
		"reset":yaw=2.8;distance=2.9;_manual_zoom=false
	update_camera();request_camera_fit()
func zoom(amount:float)->void:
	cancel_gesture()
	distance=clampf((distance if _manual_zoom else maxf(distance,_fitted_distance))+amount,1.4,7.0);_manual_zoom=true;update_camera()
func _camera_input(event:InputEvent)->void:
	if gizmo and _touch<0 and not _mouse and gizmo.input(event):
		accept_event();return
	if event is InputEventScreenTouch:
		if event.canceled and event.index==_touch:_touch=-1
		elif event.pressed and _touch<0:_touch=event.index
		elif not event.pressed and event.index==_touch:_touch=-1
		accept_event()
	elif event is InputEventScreenDrag and event.index==_touch:
		_orbit(event.relative);accept_event()
	elif event is InputEventMouseButton:
		if event.device==InputEvent.DEVICE_ID_EMULATION:return
		if event.button_index==MOUSE_BUTTON_LEFT:_mouse=event.pressed
		elif event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_UP:zoom(-.25)
		elif event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_DOWN:zoom(.25)
		accept_event()
	elif event is InputEventMouseMotion and _mouse and _touch<0:
		_orbit(event.relative);accept_event()
func _orbit(relative:Vector2)->void:
	yaw-=relative.x*.008;pitch=clampf(pitch+relative.y*.008,-.35,1.2);update_camera()
func cancel_gesture()->void:
	_touch=-1;_mouse=false
	if gizmo:gizmo.cancel_gesture()

func _input(event:InputEvent)->void:
	# Releases/cancels outside the TextureRect must not leave a stuck handle.
	if event is InputEventScreenTouch and (not event.pressed or event.canceled):
		if event.index==_touch:_touch=-1
		if gizmo and event.index==gizmo._touch:gizmo.cancel_gesture()
	elif event is InputEventMouseButton and not event.pressed and event.button_index==MOUSE_BUTTON_LEFT and event.device!=InputEvent.DEVICE_ID_EMULATION:
		_mouse=false
		if gizmo and gizmo._touch<0:gizmo.cancel_gesture()
	elif event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:cancel_gesture()
func _notification(what:int)->void:
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_WM_WINDOW_FOCUS_OUT]:cancel_gesture()
	elif what==NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():cancel_gesture()

func set_contact_preview(def:PostureDefinition,style:int=-1,enabled:bool=true)->void:
	_contact_definition=def;_contact_style=style;_contact_enabled=enabled and def!=null
	_refresh_contact()

func _refresh_contact()->void:
	if contact_preview:contact_preview.visible=_contact_enabled
	if not _contact_enabled or not _setup_finished:return
	if contact_preview==null:
		contact_preview=ContactPreview.new();contact_preview.name="EditorContactPreview"
		player.get_parent().add_child(contact_preview);contact_preview.initialize(player)
	var contact_transform:Transform3D=ghost_transforms[1] if ghost_transforms.size()==3 else player.paddle_node.global_transform
	contact_preview.configure(_contact_definition,contact_transform,_contact_style)
	contact_preview.visible=true;contact_preview.update_progress(_preview_progress);_request_redraw()

func set_preview_progress(progress:float)->void:
	_preview_progress=progress
	if contact_preview and _contact_enabled:contact_preview.update_progress(progress)
	_request_redraw()

func clear_joint_selection()->void:
	cancel_gesture();selected_joint="";_refresh_selected_joint_motion();queue_redraw()
