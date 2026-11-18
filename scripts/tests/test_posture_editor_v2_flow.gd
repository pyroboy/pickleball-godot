class_name TestPostureEditorV2Flow extends TestBase

## Thorough tests for the posture editor v2 flow:
##   - Gizmo appearance (handles vs sphere)
##   - Gizmo raycast & selection
##   - Axis-constrained drag math
##   - Save / dirty-tracking / round-trip
##   - Gizmo controller lifecycle

const _PostureDefinition := preload("res://scripts/posture_definition.gd")
const _PositionGizmoV2 := preload("res://scripts/posture_editor_v2/position_gizmo_v2.gd")
const _RotationGizmoV2 := preload("res://scripts/posture_editor_v2/rotation_gizmo_v2.gd")
const _GizmoControllerV2 := preload("res://scripts/posture_editor_v2/gizmo_controller_v2.gd")

## Minimal fake player/posture for testing editor open() auto-select.
class _FakePosture extends RefCounted:
	var editor_preview_mode: bool = false
	var transition_pose_blend = null
	var posture_ghosts: Dictionary = {}
	var _posture_zone_bounds: Dictionary = {}
	func force_posture_update(_def) -> void:
		pass
	func set_editor_solo_posture_id(_id: int) -> void:
		pass

class _FakePlayer extends Node:
	enum PaddlePosture {
		FOREHAND, FORWARD, BACKHAND, MEDIUM_OVERHEAD, HIGH_OVERHEAD,
		LOW_FOREHAND, LOW_FORWARD, LOW_BACKHAND,
		CHARGE_FOREHAND, CHARGE_BACKHAND,
		WIDE_FOREHAND, WIDE_BACKHAND,
		VOLLEY_READY,
		MID_LOW_FOREHAND, MID_LOW_BACKHAND, MID_LOW_FORWARD,
		MID_LOW_WIDE_FOREHAND, MID_LOW_WIDE_BACKHAND,
		LOW_WIDE_FOREHAND, LOW_WIDE_BACKHAND,
		READY,
	}
	var paddle_posture: int = PaddlePosture.FOREHAND
	var posture: _FakePosture = _FakePosture.new()
	var skeleton = null
	var global_position: Vector3 = Vector3.ZERO
	var global_transform: Transform3D = Transform3D.IDENTITY
	var COURT_FLOOR_Y: float = 0.075
	func _get_forward_axis() -> Vector3:
		# Match player 0 (blue) — faces -Z
		return Vector3(0.0, 0.0, -1.0)
	func _get_forehand_axis() -> Vector3:
		# Match player 0 (blue) — forehand is +X
		return Vector3(1.0, 0.0, 0.0)
	func _get_swing_sign() -> float:
		return 1.0

func run_all(totals: Dictionary) -> void:
	var tests: Array[Callable] = [
		# Gizmo appearance
		test_paddle_gizmo_has_axis_handles,
		test_paddle_gizmo_rgb_colors,
		test_paddle_gizmo_has_cylinder_shafts_and_cone_heads,
		test_zone_gizmo_is_sphere_only,
		test_rotation_gizmo_has_rgb_rings,
		# Raycast
		test_raycast_hits_sphere_center,
		test_raycast_hits_axis_handle,
		test_raycast_hits_cone_tip,
		test_raycast_misses_when_aimed_away,
		test_axis_handle_priority_over_sphere,
		# Highlight states
		test_highlight_axis_dims_others,
		test_clear_highlight_restores_base,
		# Hover glow
		test_hover_highlight_boosts_emission,
		test_hover_clear_restores_emission,
		test_hover_switch_axis_updates_glow,
		test_hover_on_cone_glows_whole_arrow,
		# Drag math
		test_axis_constrained_x_only_moves_x,
		test_axis_constrained_y_only_moves_y,
		test_axis_constrained_z_only_moves_z,
		# Handle clickability
		test_axis_handle_clickable_from_off_axis,
		test_axis_handle_generous_hit_radius,
		# Controller drag integration
		test_controller_drag_start_sets_axis_state,
		test_controller_drag_math_constrains_x,
		test_controller_drag_math_constrains_y,
		test_controller_drag_math_constrains_z,
		# Save flow
		test_save_round_trip_paddle_fields,
		test_paddle_position_save_load_exact,
		test_paddle_forehand_no_drift_after_ten_saves,
		test_paddle_position_reconstructs_exactly,
		test_mark_dirty_tracks_posture_id,
		test_verify_save_matches_disk,
		test_save_creates_file_on_disk,
		# Drag smoothness / no-drift
		test_drag_ghost_position_no_drift,
		# Harmonious pipeline
		test_paddle_position_harmonious_pipeline,
		test_ghost_rotation_syncs_to_definition,
		# Gizmo controller
		test_controller_adds_position_gizmo,
		test_controller_adds_rotation_gizmo,
		test_controller_clears_all_gizmos,
		test_controller_adds_zone_handle,
		test_controller_drag_state_exposed,
		# Editor open auto-select
		test_open_auto_selects_current_posture,
		# One source of truth
		test_disk_file_is_source_of_truth,
		# Zone gizmos
		test_zone_handle_positions_follow_mesh,
		test_zone_face_drag_updates_definition,
		test_zone_face_drag_updates_forward_offset,
		test_zone_mesh_resizes_from_definition,
		test_zone_handle_raycast_hits_sphere,
		test_zone_face_has_axis_handles,
		test_zone_face_planes_exist_with_colors,
		test_zone_face_planes_follow_mesh_size,
		test_zone_center_drag_moves_whole_zone,
		test_zone_world_bounds_matches_mesh,
		test_committed_zone_tracks_ghost_when_ball_incoming,
		test_ghost_does_not_freeze_at_blue_latch,
	]
	_run_test_list(totals, tests)


## ── Suite 1: Gizmo Appearance ────────────────────────────────────────────────

func test_paddle_gizmo_has_axis_handles() -> void:
	var gizmo := _PositionGizmoV2.new()
	gizmo.show_axis_handles = true
	var parent := Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	var has_x := gizmo._axis_handles.has("x")
	var has_y := gizmo._axis_handles.has("y")
	var has_z := gizmo._axis_handles.has("z")
	_assert_true(has_x and has_y and has_z,
		"paddle gizmo has X/Y/Z axis handle children")
	parent.queue_free()


func test_paddle_gizmo_rgb_colors() -> void:
	var gizmo := _PositionGizmoV2.new()
	gizmo.show_axis_handles = true
	var parent := Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	var x_mat: StandardMaterial3D = gizmo._axis_materials.get("x", null)
	var y_mat: StandardMaterial3D = gizmo._axis_materials.get("y", null)
	var z_mat: StandardMaterial3D = gizmo._axis_materials.get("z", null)
	var ok := x_mat != null and y_mat != null and z_mat != null
	if ok:
		ok = _color_approx(x_mat.albedo_color, Color(1, 0, 0)) and \
			_color_approx(y_mat.albedo_color, Color(0, 1, 0)) and \
			_color_approx(z_mat.albedo_color, Color(0, 0, 1))
	_assert_true(ok, "paddle gizmo axis colors are RGB (X=Red, Y=Green, Z=Blue)")
	parent.queue_free()


func test_paddle_gizmo_has_cylinder_shafts_and_cone_heads() -> void:
	var gizmo := _PositionGizmoV2.new()
	gizmo.show_axis_handles = true
	var parent := Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	var cyl_count := 0
	var cone_count := 0
	for child in gizmo.get_children():
		if child is MeshInstance3D and child.mesh is CylinderMesh:
			var cyl: CylinderMesh = child.mesh
			if cyl.top_radius > 0.0 and cyl.bottom_radius > 0.0:
				cyl_count += 1
			elif cyl.top_radius == 0.0:
				cone_count += 1

	_assert_true(cyl_count >= 3 and cone_count >= 3,
		"paddle gizmo has cylinder shafts (%d) and cone arrowheads (%d)" % [cyl_count, cone_count])
	parent.queue_free()


func test_zone_gizmo_is_sphere_only() -> void:
	var gizmo := _PositionGizmoV2.new()
	gizmo.show_axis_handles = false
	var parent := Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	var is_sphere := gizmo.mesh is SphereMesh
	var no_handles := gizmo._axis_handles.is_empty()
	_assert_true(is_sphere and no_handles,
		"zone gizmo is sphere-only (show_axis_handles=false)")
	parent.queue_free()


func test_rotation_gizmo_has_rgb_rings() -> void:
	var gizmo := _RotationGizmoV2.new()
	var parent := Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	var ring_x: MeshInstance3D = gizmo._rings.get("x", null)
	var ring_y: MeshInstance3D = gizmo._rings.get("y", null)
	var ring_z: MeshInstance3D = gizmo._rings.get("z", null)
	var ok := ring_x != null and ring_y != null and ring_z != null
	if ok:
		ok = _color_approx(ring_x.material_override.albedo_color, Color(1, 0.3, 0.3)) and \
			_color_approx(ring_y.material_override.albedo_color, Color(0.3, 1, 0.3)) and \
			_color_approx(ring_z.material_override.albedo_color, Color(0.3, 0.3, 1))
	_assert_true(ok, "rotation gizmo has RGB-tinted torus rings")
	parent.queue_free()


## ── Suite 2: Raycast ─────────────────────────────────────────────────────────

func test_raycast_hits_sphere_center() -> void:
	var gizmo := _PositionGizmoV2.new()
	gizmo.gizmo_size = 0.08
	var parent := Node3D.new()
	parent.add_child(gizmo)
	# Keep at origin for reliable test (avoids tree/global_position issues)
	# In Godot: FORWARD = -Z, BACK = +Z. Ray from z=-10 toward +Z hits origin.
	var hit := gizmo.raycast_test(Vector3(0, 0, -10), Vector3.BACK)
	_assert_ge(hit, 0.0, "raycast hits gizmo sphere from front")
	parent.queue_free()


func test_raycast_hits_axis_handle() -> void:
	var gizmo := _PositionGizmoV2.new()
	gizmo.show_axis_handles = true
	gizmo.global_position = Vector3.ZERO
	var parent := Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	# Ray aimed along +X should hit the X-axis handle
	var hit := gizmo.raycast_test(Vector3(-1, 0, 0), Vector3.RIGHT)
	_assert_ge(hit, 0.0, "raycast hits X-axis handle")
	_assert_eq(gizmo.get_selected_axis(), "x", "selected axis is x after X-handle hit")
	parent.queue_free()


func test_raycast_misses_when_aimed_away() -> void:
	var gizmo := _PositionGizmoV2.new()
	gizmo.gizmo_size = 0.08
	var parent := Node3D.new()
	parent.add_child(gizmo)
	# Ray pointing away from origin gizmo (toward -Z)
	var hit := gizmo.raycast_test(Vector3(0, 0, -10), Vector3.FORWARD)
	_assert_lt(hit, 0.0, "raycast misses when aimed away from gizmo")
	parent.queue_free()


func test_axis_handle_priority_over_sphere() -> void:
	var gizmo := _PositionGizmoV2.new()
	gizmo.show_axis_handles = true
	gizmo.global_position = Vector3.ZERO
	var parent := Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	# Ray from (-0.5, 0, 0) toward +X — hits both sphere and X handle
	var hit := gizmo.raycast_test(Vector3(-0.5, 0, 0), Vector3.RIGHT)
	var axis := gizmo.get_selected_axis()
	_assert_ge(hit, 0.0, "raycast returns valid hit")
	_assert_eq(axis, "x", "axis handle takes priority over sphere")
	parent.queue_free()


func test_raycast_hits_cone_tip() -> void:
	var gizmo := _PositionGizmoV2.new()
	gizmo.show_axis_handles = true
	var parent := Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	# Verify cone children exist
	_assert_true(gizmo._axis_cones.has("x"), "X cone exists in _axis_cones")

	# Test cone intersection directly with hardcoded geometry
	# X cone: center (0.31, 0, 0), axis +X, base radius 0.05, height 0.12
	var cone_hit := gizmo._intersect_cylinder(
		Vector3(0.31, -1, 0), Vector3.UP,
		Vector3(0.31, 0, 0), Vector3.RIGHT,
		0.05, 0.12
	)
	_assert_ge(cone_hit, 0.0, "raycast hits X cone tip")
	parent.queue_free()


## ── Suite 3: Highlight States ────────────────────────────────────────────────

func test_highlight_axis_dims_others() -> void:
	var gizmo := _PositionGizmoV2.new()
	gizmo.show_axis_handles = true
	var parent := Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	gizmo.highlight_axis("x")
	var x_a: float = gizmo._axis_materials["x"].albedo_color.a
	var y_a: float = gizmo._axis_materials["y"].albedo_color.a
	_assert_ge(x_a, 0.9, "highlighted X axis is bright")
	_assert_le(y_a, 0.5, "non-selected Y axis is dimmed")
	parent.queue_free()


func test_clear_highlight_restores_base() -> void:
	var gizmo := _PositionGizmoV2.new()
	gizmo.show_axis_handles = true
	var parent := Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	gizmo.highlight_axis("x")
	gizmo.clear_highlight()
	var y_a: float = gizmo._axis_materials["y"].albedo_color.a
	_assert_ge(y_a, 0.5, "clear_highlight restores Y axis visibility")
	parent.queue_free()


## ── Suite 4: Hover Glow ──────────────────────────────────────────────────────

func test_hover_highlight_boosts_emission() -> void:
	var gizmo := _PositionGizmoV2.new()
	gizmo.show_axis_handles = true
	var parent := Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	gizmo.highlight_axis("x")
	var x_em: float = gizmo._axis_materials["x"].emission_energy_multiplier
	var y_em: float = gizmo._axis_materials["y"].emission_energy_multiplier
	_assert_ge(x_em, 2.0, "hovered X axis emission is boosted (glows bright)")
	_assert_le(y_em, 1.0, "non-hovered Y axis emission is dimmed")
	parent.queue_free()


func test_hover_clear_restores_emission() -> void:
	var gizmo := _PositionGizmoV2.new()
	gizmo.show_axis_handles = true
	var parent := Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	gizmo.highlight_axis("x")
	gizmo.clear_highlight()
	var x_em: float = gizmo._axis_materials["x"].emission_energy_multiplier
	var y_em: float = gizmo._axis_materials["y"].emission_energy_multiplier
	_assert_eq_f(x_em, 1.5, 0.01, "clear_highlight restores X emission to base")
	_assert_eq_f(y_em, 1.5, 0.01, "clear_highlight restores Y emission to base")
	parent.queue_free()


func test_hover_switch_axis_updates_glow() -> void:
	var gizmo := _PositionGizmoV2.new()
	gizmo.show_axis_handles = true
	var parent := Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	gizmo.highlight_axis("x")
	var x_em_first: float = gizmo._axis_materials["x"].emission_energy_multiplier
	gizmo.highlight_axis("y")
	var x_em_second: float = gizmo._axis_materials["x"].emission_energy_multiplier
	var y_em_second: float = gizmo._axis_materials["y"].emission_energy_multiplier
	_assert_ge(x_em_first, 2.0, "X glows bright when hovered first")
	_assert_le(x_em_second, 1.0, "X dims when hover switches to Y")
	_assert_ge(y_em_second, 2.0, "Y glows bright after switch")
	parent.queue_free()


func test_hover_on_cone_glows_whole_arrow() -> void:
	var gizmo := _PositionGizmoV2.new()
	gizmo.show_axis_handles = true
	var parent := Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	gizmo.highlight_axis("x")
	# Cylinder and cone share the same material, so both glow
	var cyl_em: float = gizmo._axis_handles["x"].material_override.emission_energy_multiplier
	var cone_em: float = gizmo._axis_cones["x"].material_override.emission_energy_multiplier
	_assert_ge(cyl_em, 2.0, "cylinder glows when axis is hovered")
	_assert_ge(cone_em, 2.0, "cone glows together with cylinder")
	parent.queue_free()


## ── Suite 6: Axis-Constrained Drag Math ──────────────────────────────────────

func test_axis_constrained_x_only_moves_x() -> void:
	var start := Vector3(1, 2, 3)
	var drag_delta := Vector3(0.5, 0.7, -0.3)
	var constrained := _constrain_to_axis(drag_delta, Vector3.RIGHT)
	_assert_eq_v3(constrained, Vector3(0.5, 0, 0), 0.001,
		"X-constrained drag only preserves X component")


func test_axis_constrained_y_only_moves_y() -> void:
	var start := Vector3(1, 2, 3)
	var drag_delta := Vector3(0.5, 0.7, -0.3)
	var constrained := _constrain_to_axis(drag_delta, Vector3.UP)
	_assert_eq_v3(constrained, Vector3(0, 0.7, 0), 0.001,
		"Y-constrained drag only preserves Y component")


func test_axis_constrained_z_only_moves_z() -> void:
	var start := Vector3(1, 2, 3)
	var drag_delta := Vector3(0.5, 0.7, -0.3)
	var constrained := _constrain_to_axis(drag_delta, Vector3.FORWARD)
	_assert_eq_v3(constrained, Vector3(0, 0, -0.3), 0.001,
		"Z-constrained drag only preserves Z component")


## ── Suite 5: Handle Clickability ─────────────────────────────────────────────

func test_axis_handle_clickable_from_off_axis() -> void:
	# Test _intersect_cylinder directly with hardcoded geometry to avoid
	# transform-system quirks when the parent is not in the scene tree.
	var gizmo := _PositionGizmoV2.new()

	# X handle: cylinder along X at (0.125, 0, 0), ray from below slightly offset in Y
	var hit_x := gizmo._intersect_cylinder(
		Vector3(0.125, -1, 0), Vector3.UP,
		Vector3(0.125, 0, 0), Vector3.RIGHT,
		0.02, 0.25
	)
	_assert_ge(hit_x, 0.0, "cylinder-ray hit: X handle from below with Y offset")

	# Y handle: cylinder along Y at (0, 0.125, 0), ray from side slightly offset in X
	var hit_y := gizmo._intersect_cylinder(
		Vector3(-1, 0.125, 0), Vector3.RIGHT,
		Vector3(0, 0.125, 0), Vector3.UP,
		0.02, 0.25
	)
	_assert_ge(hit_y, 0.0, "cylinder-ray hit: Y handle from side with X offset")

	# Z handle: cylinder along Z at (0, 0, 0.125), ray from below slightly offset in X
	var hit_z := gizmo._intersect_cylinder(
		Vector3(0, -1, 0.125), Vector3.UP,
		Vector3(0, 0, 0.125), Vector3.BACK,
		0.02, 0.25
	)
	_assert_ge(hit_z, 0.0, "cylinder-ray hit: Z handle from below with X offset")
	gizmo.queue_free()


func test_axis_handle_generous_hit_radius() -> void:
	var gizmo := _PositionGizmoV2.new()
	gizmo.show_axis_handles = true
	var parent := Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	var x_cyl: MeshInstance3D = gizmo._axis_handles.get("x", null)
	_assert_true(x_cyl != null and x_cyl.mesh is CylinderMesh, "X handle has cylinder mesh")
	if x_cyl and x_cyl.mesh is CylinderMesh:
		var cyl: CylinderMesh = x_cyl.mesh
		_assert_ge(cyl.top_radius, 0.015, "handle cylinder radius is generous (>= 0.015)")
	parent.queue_free()


## ── Suite 6: Controller Drag Integration ─────────────────────────────────────

func test_controller_drag_start_sets_axis_state() -> void:
	var ctrl := _GizmoControllerV2.new()
	var parent := Node3D.new()
	parent.add_child(ctrl)

	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, -5)
	camera.look_at(Vector3.ZERO)
	parent.add_child(camera)
	ctrl.set_camera(camera)

	var gizmo := ctrl.add_position_gizmo("paddle", Vector3.ZERO, Color.GREEN, 0.08, true)
	# Manually set selected axis so _start_drag picks it up
	gizmo._selected_axis = "x"

	# _start_drag is private; call it directly (tests are in the same module)
	ctrl._start_drag(gizmo, Vector2.ZERO, Vector3(0, 0, -5), Vector3.FORWARD)

	_assert_true(ctrl._dragging, "drag state is active after _start_drag")
	_assert_eq(ctrl._drag_axis, "x", "drag axis is set from gizmo's selected axis")
	parent.queue_free()


func test_controller_drag_math_constrains_x() -> void:
	var gizmo_pos := Vector3(1, 2, 3)
	var drag_plane := Plane(Vector3.BACK, gizmo_pos)
	var new_pos := _simulate_drag_update(gizmo_pos, drag_plane, "x", Vector3(2, 5, 3), Vector3.BACK)
	# Drag plane intersect at (2, 5, 3); constrained to X axis from (1, 2, 3)
	# Only X should change: 1 + (2-1) = 2
	_assert_eq_v3(new_pos, Vector3(2, 2, 3), 0.001,
		"X-constrained drag only moves along X axis")


func test_controller_drag_math_constrains_y() -> void:
	var gizmo_pos := Vector3(1, 2, 3)
	var drag_plane := Plane(Vector3.BACK, gizmo_pos)
	var new_pos := _simulate_drag_update(gizmo_pos, drag_plane, "y", Vector3(5, 4, 3), Vector3.BACK)
	# Only Y should change: 2 + (4-2) = 4
	_assert_eq_v3(new_pos, Vector3(1, 4, 3), 0.001,
		"Y-constrained drag only moves along Y axis")


func test_controller_drag_math_constrains_z() -> void:
	var gizmo_pos := Vector3(1, 2, 3)
	var drag_plane := Plane(Vector3.RIGHT, gizmo_pos)
	var new_pos := _simulate_drag_update(gizmo_pos, drag_plane, "z", Vector3(1, 5, 5), Vector3.RIGHT)
	# Only Z should change: 3 + (5-3) = 5
	_assert_eq_v3(new_pos, Vector3(1, 2, 5), 0.001,
		"Z-constrained drag only moves along Z axis")


## ── Suite 7: Save Flow ───────────────────────────────────────────────────────

func test_save_round_trip_paddle_fields() -> void:
	var def := _PostureDefinition.new()
	def.paddle_forehand_mul = 0.123
	def.paddle_forward_mul = 0.456
	def.paddle_y_offset = -0.789
	def.display_name = "TestFlow"

	var path := "user://test_v2_flow_roundtrip.tres"
	var err := ResourceSaver.save(def, path, ResourceSaver.FLAG_CHANGE_PATH)
	_assert_eq(err, OK, "ResourceSaver.save returns OK")

	var loaded := load(path) as PostureDefinition
	_assert_true(loaded != null, "loaded resource is PostureDefinition")
	_assert_true(is_equal_approx(loaded.paddle_forehand_mul, 0.123),
		"round-trip paddle_forehand_mul")
	_assert_true(is_equal_approx(loaded.paddle_forward_mul, 0.456),
		"round-trip paddle_forward_mul")
	_assert_true(is_equal_approx(loaded.paddle_y_offset, -0.789),
		"round-trip paddle_y_offset")

	DirAccess.open("user://").remove(path)


func test_paddle_forehand_no_drift_after_ten_saves() -> void:
	# Simulates iterative edit/save/load cycles that previously caused drift
	# due to library reload replacing _current_def with disk-rounded instances.
	var def := _PostureDefinition.new()
	def.paddle_forehand_mul = 0.753291
	def.paddle_forward_mul = 1.247883
	def.paddle_y_offset = 0.512456
	def.display_name = "DriftTest"

	var path := "user://test_drift.tres"
	var original_fh: float = def.paddle_forehand_mul

	for i in range(10):
		ResourceSaver.save(def, path, ResourceSaver.FLAG_CHANGE_PATH)
		def = load(path) as PostureDefinition
		_assert_true(def != null, "load succeeds on cycle %d" % i)

	var drift: float = absf(def.paddle_forehand_mul - original_fh)
	_assert_le(drift, 0.0001, "forehand_mul drifts < 0.0001 after 10 save/load cycles (got %.6f)" % drift)

	DirAccess.open("user://").remove(path)


func test_paddle_position_reconstructs_exactly() -> void:
	# Verifies that resolve_paddle_offset round-trips correctly through save/load.
	var def := _PostureDefinition.new()
	def.paddle_forehand_mul = 0.85
	def.paddle_forward_mul = 1.15
	def.paddle_y_offset = 0.55
	def.display_name = "Reconstruct"

	var path := "user://test_reconstruct.tres"
	ResourceSaver.save(def, path, ResourceSaver.FLAG_CHANGE_PATH)

	var loaded := load(path) as PostureDefinition
	var forehand_axis := Vector3.RIGHT
	var forward_axis := Vector3.FORWARD
	var reconstructed: Vector3 = loaded.resolve_paddle_offset(forehand_axis, forward_axis)
	var expected: Vector3 = Vector3(0.85, 0.55, -1.15)
	_assert_eq_v3(reconstructed, expected, 0.0001,
		"reconstructed position matches original after save/load")

	DirAccess.open("user://").remove(path)


func test_mark_dirty_tracks_posture_id() -> void:
	var editor = load("res://scripts/posture_editor_v2.gd").new()
	var def := _PostureDefinition.new()
	def.posture_id = 7
	def.display_name = "TestDirty"

	editor._current_def = def
	editor._is_base_pose_mode = false
	editor._mark_dirty()

	_assert_true(editor._dirty_defs.has(7), "_dirty_defs has posture_id 7")
	_assert_true(editor._dirty_defs.get(7) == def, "_dirty_defs[7] is the same def")


func test_verify_save_matches_disk() -> void:
	var def := _PostureDefinition.new()
	def.paddle_forehand_mul = 0.555
	def.paddle_forward_mul = 0.666
	def.paddle_y_offset = 0.777
	def.display_name = "VerifyTest"

	var path := "user://test_v2_verify.tres"
	ResourceSaver.save(def, path, ResourceSaver.FLAG_CHANGE_PATH)
	def.resource_path = path

	var disk := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as PostureDefinition
	var ok := is_equal_approx(disk.paddle_forehand_mul, def.paddle_forehand_mul) and \
			  is_equal_approx(disk.paddle_forward_mul, def.paddle_forward_mul) and \
			  is_equal_approx(disk.paddle_y_offset, def.paddle_y_offset)
	_assert_true(ok, "disk values match memory after save")
	DirAccess.open("user://").remove(path)


func test_save_creates_file_on_disk() -> void:
	var def := _PostureDefinition.new()
	def.display_name = "FileTest"
	var path := "user://test_v2_file.tres"
	ResourceSaver.save(def, path, ResourceSaver.FLAG_CHANGE_PATH)
	var exists := FileAccess.file_exists(path)
	_assert_true(exists, "save creates an actual file on disk")
	DirAccess.open("user://").remove(path)


## ── Suite 6: Gizmo Controller Lifecycle ──────────────────────────────────────

func test_controller_adds_position_gizmo() -> void:
	var ctrl := _GizmoControllerV2.new()
	var parent := Node3D.new()
	parent.add_child(ctrl)

	var gizmo := ctrl.add_position_gizmo("paddle_position", Vector3(1, 2, 3), Color.GREEN, 0.08)
	_assert_true(gizmo is _PositionGizmoV2, "add_position_gizmo returns PositionGizmoV2")
	# global_position requires tree; position is local to controller parent
	_assert_eq_v3(gizmo.position, Vector3(1, 2, 3), 0.001,
		"position gizmo placed at correct position")
	parent.queue_free()


func test_controller_adds_rotation_gizmo() -> void:
	var ctrl := _GizmoControllerV2.new()
	var parent := Node3D.new()
	parent.add_child(ctrl)

	var gizmo := ctrl.add_rotation_gizmo("hip_rotation", Vector3(0, 1, 0))
	_assert_true(gizmo is _RotationGizmoV2, "add_rotation_gizmo returns RotationGizmoV2")
	parent.queue_free()


func test_controller_clears_all_gizmos() -> void:
	var ctrl := _GizmoControllerV2.new()
	var parent := Node3D.new()
	parent.add_child(ctrl)

	ctrl.add_position_gizmo("a", Vector3.ZERO, Color.WHITE)
	ctrl.add_rotation_gizmo("b", Vector3.ZERO)
	_assert_true(ctrl.get_child_count() >= 2, "controller has gizmo children before clear")

	ctrl.clear_all_gizmos()
	# queue_free is deferred in Godot; force immediate free in test context
	for child in ctrl.get_children():
		child.free()
	_assert_true(ctrl.get_child_count() == 0, "clear_all_gizmos removes all children")
	parent.queue_free()


func test_controller_adds_zone_handle() -> void:
	var ctrl := _GizmoControllerV2.new()
	var parent := Node3D.new()
	parent.add_child(ctrl)

	var gizmo := ctrl.add_zone_handle("zone_BLF", Vector3(1, 0, 1), Color.RED, 0.05)
	_assert_true(gizmo is _PositionGizmoV2, "add_zone_handle returns PositionGizmoV2")
	_assert_true(not gizmo.show_axis_handles, "zone handle does NOT show axis handles")
	parent.queue_free()


func test_controller_drag_state_exposed() -> void:
	var ctrl := _GizmoControllerV2.new()
	var parent := Node3D.new()
	parent.add_child(ctrl)

	_assert_true(not ctrl.is_dragging(), "is_dragging() returns false initially")
	ctrl._dragging = true
	_assert_true(ctrl.is_dragging(), "is_dragging() returns true when drag state is active")
	parent.queue_free()


func test_paddle_position_save_load_exact() -> void:
	var def := _PostureDefinition.new()
	def.paddle_forehand_mul = 0.753
	def.paddle_forward_mul = 1.247
	def.paddle_y_offset = 0.512
	def.display_name = "ExactPos"

	var path := "user://test_paddle_exact.tres"
	var err := ResourceSaver.save(def, path, ResourceSaver.FLAG_CHANGE_PATH)
	_assert_eq(err, OK, "ResourceSaver.save returns OK")

	var loaded := load(path) as PostureDefinition
	_assert_true(loaded != null, "loaded resource is PostureDefinition")
	_assert_eq_f(loaded.paddle_forehand_mul, 0.753, 0.0001,
		"forehand_mul is exact after save/load")
	_assert_eq_f(loaded.paddle_forward_mul, 1.247, 0.0001,
		"forward_mul is exact after save/load")
	_assert_eq_f(loaded.paddle_y_offset, 0.512, 0.0001,
		"y_offset is exact after save/load")

	DirAccess.open("user://").remove(path)


func test_drag_ghost_position_no_drift() -> void:
	# Simulates the ghost-position math from _on_gizmo_moved to verify
	# the fixed formula does NOT drift the head offset.
	var head_offset := Vector3(0.5, 1.2, 0.3)
	var scale_y: float = 0.92
	var basis_y: Vector3 = Vector3.UP * scale_y

	# BUGGY formula (double-scaled): ghost = head - basis.y * 0.4 * scale
	var ghost_pos_buggy: Vector3 = head_offset - basis_y * 0.4 * scale_y
	var recovered_head_buggy: Vector3 = ghost_pos_buggy + basis_y * 0.4
	var drift_buggy: float = recovered_head_buggy.distance_to(head_offset)

	# FIXED formula (normalized first): ghost = head - basis.y.normalized() * 0.4 * scale
	var ghost_pos_fixed: Vector3 = head_offset - basis_y.normalized() * 0.4 * scale_y
	var recovered_head_fixed: Vector3 = ghost_pos_fixed + basis_y.normalized() * 0.4 * scale_y
	var drift_fixed: float = recovered_head_fixed.distance_to(head_offset)

	_assert_gt(drift_buggy, 0.02, "buggy formula drifts by > 2 cm")
	_assert_le(drift_fixed, 0.001, "fixed formula preserves head offset within 1 mm")


func test_paddle_position_harmonious_pipeline() -> void:
	# Simulates the full definition → ghost → gizmo pipeline to prove
	# all three agree on the same head position.
	var def := _PostureDefinition.new()
	def.paddle_forehand_mul = 0.75
	def.paddle_forward_mul = 1.25
	def.paddle_y_offset = 0.5
	def.paddle_pitch_base_deg = 15.0
	def.paddle_yaw_base_deg = -20.0
	def.paddle_roll_base_deg = 5.0

	var forehand_axis := Vector3.RIGHT
	var forward_axis := Vector3.FORWARD
	var scale_y: float = 0.92

	# Step 1: Definition → head offset
	var offset: Vector3 = def.resolve_paddle_offset(forehand_axis, forward_axis)

	# Step 2: Definition → rotation → basis
	var rot_deg: Vector3 = def.resolve_paddle_rotation_deg(1.0, -1.0)
	var b: Basis = Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))

	# Step 3: Ghost handle position (what _sync_ghost_to_definition computes)
	var ghost_pos: Vector3 = offset - b.y.normalized() * 0.4 * scale_y

	# Step 4: Ghost head position (what _refresh_gizmos / _process compute)
	var ghost_head: Vector3 = ghost_pos + b.y.normalized() * 0.4 * scale_y

	# The head must round-trip back to the original offset
	_assert_eq_v3(ghost_head, offset, 0.001,
		"definition → ghost → gizmo head position is harmonious")


func test_ghost_rotation_syncs_to_definition() -> void:
	# Verify that resolve_paddle_rotation_deg produces deterministic rotation
	# that would make the ghost's basis.y point in the expected direction.
	var def := _PostureDefinition.new()
	def.paddle_pitch_base_deg = 0.0
	def.paddle_yaw_base_deg = 0.0
	def.paddle_roll_base_deg = 0.0

	# With zero rotation, the ghost should point straight up (no tilt)
	var rot_deg: Vector3 = def.resolve_paddle_rotation_deg(1.0, -1.0)
	var b: Basis = Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	_assert_eq_v3(b.y.normalized(), Vector3.UP, 0.001,
		"zero-rotation definition gives upright ghost basis")


func test_open_auto_selects_current_posture() -> void:
	# Verify that open() auto-selects the player's current posture so the
	# ghost immediately snaps to the saved definition position.
	var editor := PostureEditorV2.new()
	# Manually initialise UI so _posture_list and tabs exist without needing
	# a scene tree (headless test runner has no root window).
	editor._ready()

	# Stub a player whose current posture is FOREHAND (id=0)
	var player := _FakePlayer.new()
	player.paddle_posture = _FakePlayer.PaddlePosture.FOREHAND
	editor._player = player

	editor.open()

	_assert_true(editor._current_def != null,
		"open() auto-selects a posture definition")
	if editor._current_def != null:
		_assert_eq(editor._current_def.posture_id, _FakePlayer.PaddlePosture.FOREHAND,
			"auto-selected posture matches player's current posture")
	_assert_true(player.posture.editor_preview_mode,
		"editor_preview_mode is enabled on posture")

	editor.queue_free()


func test_disk_file_is_source_of_truth() -> void:
	# Verify that PostureLibrary loads from disk .tres files, not hardcoded defaults.
	# FOREHAND hardcoded default has paddle_forehand_mul = 0.55;
	# the disk file has a hand-tuned value (~0.732).
	var lib = load("res://scripts/posture_library.gd").new()
	lib.load_or_default()
	var def = lib.get_def(0)  # FOREHAND
	_assert_true(def != null, "library has FOREHAND definition")
	if def == null:
		return
	_assert_true(absf(def.paddle_forehand_mul - 0.55) > 0.01,
		"disk file overrides hardcoded default for FOREHAND")


func test_zone_handle_positions_follow_mesh() -> void:
	# Verify the geometric computation that places zone face handles on the mesh.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.0, 1.0, 0.15)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(1.0, 0.5, 2.0)

	var half_size := mesh.size / 2.0
	var basis := mi.transform.basis
	var center := mi.position

	var left   := center + basis * Vector3(-half_size.x, 0.0, 0.0)
	var right  := center + basis * Vector3( half_size.x, 0.0, 0.0)
	var bottom := center + basis * Vector3(0.0, -half_size.y, 0.0)
	var top    := center + basis * Vector3(0.0,  half_size.y, 0.0)
	var front  := center + basis * Vector3(0.0, 0.0, -half_size.z)
	var back   := center + basis * Vector3(0.0, 0.0,  half_size.z)

	_assert_eq_v3(left,   Vector3(0.0, 0.5, 2.0), 0.001, "left face position")
	_assert_eq_v3(right,  Vector3(2.0, 0.5, 2.0), 0.001, "right face position")
	_assert_eq_v3(bottom, Vector3(1.0, 0.0, 2.0), 0.001, "bottom face position")
	_assert_eq_v3(top,    Vector3(1.0, 1.0, 2.0), 0.001, "top face position")
	_assert_eq_v3(front,  Vector3(1.0, 0.5, 1.925), 0.001, "front face position")
	_assert_eq_v3(back,   Vector3(1.0, 0.5, 2.075), 0.001, "back face position")
	mi.queue_free()


func test_zone_face_drag_updates_definition() -> void:
	# Verify dragging a zone face handle updates the correct definition fields.
	var editor := PostureEditorV2.new()
	editor._ready()

	var player := _FakePlayer.new()
	player.global_position = Vector3.ZERO
	editor._player = player

	var def := _PostureDefinition.new()
	def.posture_id = 0
	def.display_name = "TestPosture"
	def.has_zone = true
	def.zone_x_min = -0.5
	def.zone_x_max = 0.5
	def.zone_y_min = 0.0
	def.zone_y_max = 1.0
	editor._current_def = def

	# Drag left face to x = -1.0
	editor._on_gizmo_moved("zone_left", Vector3(-1.0, 0.5, 0.0))
	_assert_eq_f(def.zone_x_min, -1.0, 0.001, "zone_left drag updates zone_x_min")

	# Drag right face to x = 2.0
	editor._on_gizmo_moved("zone_right", Vector3(2.0, 0.5, 0.0))
	_assert_eq_f(def.zone_x_max, 2.0, 0.001, "zone_right drag updates zone_x_max")

	# Drag bottom face to y = 0.5 (world Y = 0.5 → def value = 0.5 - COURT_FLOOR_Y)
	editor._on_gizmo_moved("zone_bottom", Vector3(0.0, 0.5, 0.0))
	_assert_eq_f(def.zone_y_min, 0.425, 0.001, "zone_bottom drag updates zone_y_min")

	# Drag top face to y = 1.5
	editor._on_gizmo_moved("zone_top", Vector3(0.0, 1.5, 0.0))
	_assert_eq_f(def.zone_y_max, 1.425, 0.001, "zone_top drag updates zone_y_max")

	editor.queue_free()


func test_zone_face_drag_updates_forward_offset() -> void:
	# Verify dragging a zone face handle updates zone_forward_offset.
	var editor := PostureEditorV2.new()
	editor._ready()

	var player := _FakePlayer.new()
	player.global_position = Vector3.ZERO
	editor._player = player

	var def := _PostureDefinition.new()
	def.posture_id = 0
	def.has_zone = true
	def.zone_forward_offset = 0.0
	editor._current_def = def

	# Create zone mesh so half-depth can be read
	var zone_mesh := BoxMesh.new()
	zone_mesh.size = Vector3(1.0, 1.0, 0.15)
	var zone_mi := MeshInstance3D.new()
	zone_mi.mesh = zone_mesh
	player.posture._posture_zone_bounds[0] = zone_mi

	# Front face drag: with fwd_axis = (0,0,-1), offset.dot(fwd) = -0.5
	# def.zone_forward_offset = -0.5 - 0.075 = -0.575
	editor._on_gizmo_moved("zone_front", Vector3(0.0, 0.0, 0.5))
	_assert_eq_f(def.zone_forward_offset, -0.575, 0.001,
		"zone_front drag updates zone_forward_offset")

	# Back face drag: with fwd_axis = (0,0,-1), offset.dot(fwd) = 0.5
	# def.zone_forward_offset = 0.5 + 0.075 = 0.575
	editor._on_gizmo_moved("zone_back", Vector3(0.0, 0.0, -0.5))
	_assert_eq_f(def.zone_forward_offset, 0.575, 0.001,
		"zone_back drag updates zone_forward_offset")

	editor.queue_free()


func test_zone_mesh_resizes_from_definition() -> void:
	# Verify _update_zone_mesh_from_def resizes the BoxMesh to match definition.
	var editor := PostureEditorV2.new()
	editor._ready()

	var player := _FakePlayer.new()
	player.global_position = Vector3(1.0, 0.5, 2.0)
	editor._player = player

	var def := _PostureDefinition.new()
	def.posture_id = 0
	def.has_zone = true
	def.zone_x_min = -0.5
	def.zone_x_max = 1.5
	def.zone_y_min = 0.0
	def.zone_y_max = 1.0
	def.zone_forward_offset = 0.3

	var zone_mesh := BoxMesh.new()
	zone_mesh.size = Vector3(1.0, 1.0, 0.15)
	var zone_mi := MeshInstance3D.new()
	zone_mi.mesh = zone_mesh
	var zone_parent := Node3D.new()
	zone_parent.add_child(zone_mi)
	player.posture._posture_zone_bounds[0] = zone_mi

	editor._update_zone_mesh_from_def(def)
	zone_parent.queue_free()

	# width = zone_x_max - zone_x_min = 2.0
	# height = (COURT_FLOOR_Y + zone_y_max - player_y) - (COURT_FLOOR_Y + zone_y_min - player_y)
	#        = zone_y_max - zone_y_min = 1.0
	_assert_eq_v3(zone_mesh.size, Vector3(2.0, 1.0, 0.15), 0.001,
		"zone mesh size matches definition")

	# position = fh * zone_cx + UP * zone_cy + fwd * zone_cz
	# zone_cx = 0.5, zone_cy = 0.075, zone_cz = 0.3
	# fwd_axis = (0,0,-1)  →  z = -0.3
	_assert_eq_v3(zone_mi.position, Vector3(0.5, 0.075, -0.3), 0.001,
		"zone mesh position matches definition")

	editor.queue_free()


func test_zone_handle_raycast_hits_sphere() -> void:
	# Verify zone handles (plain PositionGizmoV2 spheres) are raycast-clickable.
	var gizmo := _PositionGizmoV2.new()
	gizmo.gizmo_size = 0.05
	var parent := Node3D.new()
	parent.add_child(gizmo)
	if not gizmo.is_node_ready():
		gizmo._ready()

	# Ray aimed directly at the sphere center
	var hit := gizmo.raycast_test(Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0))
	_assert_true(hit >= 0.0, "zone handle sphere is raycast-hittable")
	parent.queue_free()


func test_zone_face_has_axis_handles() -> void:
	# Verify zone face gizmos are created with axis handles enabled.
	var ctrl := _GizmoControllerV2.new()
	var parent := Node3D.new()
	parent.add_child(ctrl)

	var gizmo := ctrl.add_zone_handle("zone_left", Vector3.ZERO, Color.RED, 0.05, true)
	if not gizmo.is_node_ready():
		gizmo._ready()
	_assert_true(gizmo is _PositionGizmoV2, "add_zone_handle returns PositionGizmoV2")
	_assert_true(gizmo.show_axis_handles, "zone face handle shows axis handles")
	# Verify axis handles actually exist (cylinders were created)
	_assert_true(gizmo._axis_handles.has("x"), "zone face has X axis handle")
	_assert_true(gizmo._axis_handles.has("y"), "zone face has Y axis handle")
	_assert_true(gizmo._axis_handles.has("z"), "zone face has Z axis handle")
	parent.queue_free()


func test_zone_face_planes_exist_with_colors() -> void:
	# Verify zone bounds mesh has 6 colored face-plane children.
	var player := _FakePlayer.new()
	player.global_position = Vector3.ZERO

	var def := _PostureDefinition.new()
	def.posture_id = 0
	def.has_zone = true
	def.zone_x_min = -0.5
	def.zone_x_max = 0.5
	def.zone_y_min = 0.0
	def.zone_y_max = 1.0

	var bounds_mesh := BoxMesh.new()
	bounds_mesh.size = Vector3(1.0, 1.0, 0.15)
	var zone_mi := MeshInstance3D.new()
	zone_mi.mesh = bounds_mesh

	# Simulate what _create_posture_zone_bounds does for faces
	var face_configs := [
		{"name": "FaceLeft",   "color": Color(1.0, 0.2, 0.2, 0.30)},
		{"name": "FaceRight",  "color": Color(1.0, 0.2, 0.2, 0.30)},
		{"name": "FaceBottom", "color": Color(0.2, 1.0, 0.2, 0.30)},
		{"name": "FaceTop",    "color": Color(0.2, 1.0, 0.2, 0.30)},
		{"name": "FaceFront",  "color": Color(0.2, 0.2, 1.0, 0.30)},
		{"name": "FaceBack",   "color": Color(0.2, 0.2, 1.0, 0.30)},
	]
	for cfg in face_configs:
		var face_mi := MeshInstance3D.new()
		face_mi.name = cfg["name"]
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = cfg["color"]
		face_mi.material_override = fmat
		zone_mi.add_child(face_mi)

	for cfg in face_configs:
		var face_mi = zone_mi.get_node_or_null(cfg["name"])
		_assert_true(face_mi != null, "face plane %s exists" % cfg["name"])
		if face_mi:
			var mat: StandardMaterial3D = face_mi.material_override as StandardMaterial3D
			_assert_true(mat != null, "face plane %s has material" % cfg["name"])
			if mat:
				_assert_true(_color_approx(mat.albedo_color, cfg["color"]),
					"face plane %s has correct color" % cfg["name"])

	zone_mi.queue_free()


func test_zone_face_planes_follow_mesh_size() -> void:
	# Verify _update_zone_face_planes resizes face planes when the mesh changes.
	var player := _FakePlayer.new()
	player.global_position = Vector3.ZERO

	var def := _PostureDefinition.new()
	def.posture_id = 0
	def.has_zone = true
	def.zone_x_min = -0.5
	def.zone_x_max = 0.5
	def.zone_y_min = 0.0
	def.zone_y_max = 1.0

	var bounds_mesh := BoxMesh.new()
	bounds_mesh.size = Vector3(1.0, 1.0, 0.15)
	var zone_mi := MeshInstance3D.new()
	zone_mi.mesh = bounds_mesh

	# Add face planes
	for face_name in ["FaceLeft", "FaceRight", "FaceBottom", "FaceTop", "FaceFront", "FaceBack"]:
		var face_mi := MeshInstance3D.new()
		face_mi.name = face_name
		zone_mi.add_child(face_mi)

	# Call the helper from player_paddle_posture
	var posture_script = load("res://scripts/player_paddle_posture.gd")
	var posture = posture_script.new()
	posture._player = player
	posture._update_zone_face_planes(zone_mi)

	# Verify face plane sizes match the mesh
	var half_size := bounds_mesh.size / 2.0
	var left_mi = zone_mi.get_node_or_null("FaceLeft")
	if left_mi:
		var left_mesh: BoxMesh = left_mi.mesh as BoxMesh
		_assert_true(left_mesh != null, "FaceLeft has BoxMesh")
		if left_mesh:
			_assert_eq_v3(left_mesh.size, Vector3(0.001, 1.0, 0.15), 0.0001,
				"FaceLeft size matches mesh YZ")

	var top_mi = zone_mi.get_node_or_null("FaceTop")
	if top_mi:
		var top_mesh: BoxMesh = top_mi.mesh as BoxMesh
		_assert_true(top_mesh != null, "FaceTop has BoxMesh")
		if top_mesh:
			_assert_eq_v3(top_mesh.size, Vector3(1.0, 0.001, 0.15), 0.0001,
				"FaceTop size matches mesh XZ")

	var front_mi = zone_mi.get_node_or_null("FaceFront")
	if front_mi:
		var front_mesh: BoxMesh = front_mi.mesh as BoxMesh
		_assert_true(front_mesh != null, "FaceFront has BoxMesh")
		if front_mesh:
			_assert_eq_v3(front_mesh.size, Vector3(1.0, 1.0, 0.001), 0.0001,
				"FaceFront size matches mesh XY")

	# Verify positions
	_assert_eq_v3(left_mi.position, Vector3(-half_size.x, 0, 0), 0.0001,
		"FaceLeft position on left face")
	_assert_eq_v3(top_mi.position, Vector3(0, half_size.y, 0), 0.0001,
		"FaceTop position on top face")
	_assert_eq_v3(front_mi.position, Vector3(0, 0, -half_size.z), 0.0001,
		"FaceFront position on front face")

	zone_mi.queue_free()


func test_zone_center_drag_moves_whole_zone() -> void:
	# Verify dragging zone_center gizmo moves the entire zone while preserving width/height.
	var editor := PostureEditorV2.new()
	editor._ready()

	var player := _FakePlayer.new()
	player.global_position = Vector3.ZERO
	editor._player = player

	var def := _PostureDefinition.new()
	def.posture_id = 0
	def.display_name = "TestPosture"
	def.has_zone = true
	def.zone_x_min = -0.5
	def.zone_x_max = 0.5
	def.zone_y_min = 0.0
	def.zone_y_max = 1.0
	def.zone_forward_offset = 1.0
	editor._current_def = def

	# Drag center to (1.0, 2.0, -3.0)
	# _FakePlayer forward_axis = (0,0,-1), forehand_axis = (1,0,0)
	editor._on_gizmo_moved("zone_center", Vector3(1.0, 2.0, -3.0))

	# Width = 1.0, height = 1.0 — should be preserved
	# new_center_y = 2.0 - COURT_FLOOR_Y(0.075) = 1.925
	_assert_eq_f(def.zone_x_min, 0.5, 0.001, "zone_center drag shifts x_min by center delta")
	_assert_eq_f(def.zone_x_max, 1.5, 0.001, "zone_center drag shifts x_max by center delta")
	_assert_eq_f(def.zone_y_min, 1.425, 0.001, "zone_center drag shifts y_min by center delta")
	_assert_eq_f(def.zone_y_max, 2.425, 0.001, "zone_center drag shifts y_max by center delta")
	_assert_eq_f(def.zone_forward_offset, 3.0, 0.001, "zone_center drag updates forward_offset")

	editor.queue_free()


func test_zone_world_bounds_matches_mesh() -> void:
	# Verify _get_zone_world_bounds computes the same positions as the mesh.
	var editor := PostureEditorV2.new()
	editor._ready()

	var player := _FakePlayer.new()
	player.global_position = Vector3(2.0, 0.0, 3.0)
	editor._player = player

	var def := _PostureDefinition.new()
	def.posture_id = 0
	def.has_zone = true
	def.zone_x_min = -0.5
	def.zone_x_max = 0.5
	def.zone_y_min = 0.0
	def.zone_y_max = 1.0
	def.zone_forward_offset = 1.0

	var bounds := editor._get_zone_world_bounds(def)

	# Center: player + forehand*cx + forward*cz, y = COURT_FLOOR_Y + (ymin+ymax)/2
	# player=(2,0,3), fh=(1,0,0), fwd=(0,0,-1), cx=0, cz=1.0
	# center = (2, 0.075+0.5, 3-1.0) = (2, 0.575, 2)
	_assert_eq_v3(bounds.center, Vector3(2.0, 0.575, 2.0), 0.001, "bounds center matches definition")
	_assert_eq_v3(bounds.left,   Vector3(1.5, 0.575, 2.0), 0.001, "bounds left face")
	_assert_eq_v3(bounds.right,  Vector3(2.5, 0.575, 2.0), 0.001, "bounds right face")
	_assert_eq_v3(bounds.bottom, Vector3(2.0, 0.075, 2.0), 0.001, "bounds bottom face (at COURT_FLOOR_Y)")
	_assert_eq_v3(bounds.top,    Vector3(2.0, 1.075, 2.0), 0.001, "bounds top face")
	_assert_eq_v3(bounds.front,  Vector3(2.0, 0.575, 2.075), 0.001, "bounds front face")
	_assert_eq_v3(bounds.back,   Vector3(2.0, 0.575, 1.925), 0.001, "bounds back face")

	editor.queue_free()


func test_committed_zone_tracks_ghost_when_ball_incoming() -> void:
	# Verify _compute_zone_center: committed zone always tracks ghost during incoming ball.
	var PostureScript := preload("res://scripts/player_paddle_posture.gd")

	# Scenario A: ghost within 0.3m of zone center, ball incoming, committed
	# Should return ghost_coord (not zone_coord)
	var result_a: float = PostureScript._compute_zone_center(0.1, 0.0, true, true)
	_assert_eq_f(result_a, 0.1, 0.001, "committed+incoming: tracks ghost within 0.3m")

	# Scenario B: ghost beyond 0.3m, ball incoming, committed
	var result_b: float = PostureScript._compute_zone_center(1.0, 0.0, true, true)
	_assert_eq_f(result_b, 1.0, 0.001, "committed+incoming: tracks ghost beyond 0.3m")

	# Scenario C: no ball incoming, ghost within 0.3m — should snap to zone center
	var result_c: float = PostureScript._compute_zone_center(0.1, 0.0, false, true)
	_assert_eq_f(result_c, 0.0, 0.001, "no incoming: snaps to zone center within 0.3m")

	# Scenario D: no ball incoming, ghost beyond 0.3m — should track ghost
	var result_d: float = PostureScript._compute_zone_center(1.0, 0.0, false, true)
	_assert_eq_f(result_d, 1.0, 0.001, "no incoming: tracks ghost beyond 0.3m")

	# Scenario E: ball incoming but NOT committed — should use normal snap
	var result_e: float = PostureScript._compute_zone_center(0.1, 0.0, true, false)
	_assert_eq_f(result_e, 0.0, 0.001, "incoming+not-committed: snaps to zone center")

	# Scenario F: ball incoming but NOT committed, beyond 0.3m
	var result_f: float = PostureScript._compute_zone_center(1.0, 0.0, true, false)
	_assert_eq_f(result_f, 1.0, 0.001, "incoming+not-committed: tracks ghost beyond 0.3m")


func test_ghost_does_not_freeze_at_blue_latch() -> void:
	# Verify the committed ghost target is computed from contact_local even when
	# _blue_latched is true — the ghost should NOT freeze in mid-air.
	var PostureScript := preload("res://scripts/player_paddle_posture.gd")

	var def := _PostureDefinition.new()
	def.zone_x_min = -0.5
	def.zone_x_max = 0.5
	def.zone_y_min = 0.0
	def.zone_y_max = 1.0
	def.zone_forward_offset = 1.0
	def.has_zone = true

	var head_offset := Vector3(0.0, 0.4, 0.0)
	var contact_local := Vector3(0.2, 0.5, -1.0)

	# Target should be computed from contact_local, not a frozen position
	var target: Vector3 = PostureScript._compute_committed_ghost_target(
		contact_local, def, head_offset,
		Vector3.RIGHT, Vector3.FORWARD,
		0.075, 0.0
	)

	# Contact lat = 0.2, clamped to [-0.5, 0.5] → 0.2
	# Contact ht = 0.5, clamped to [0.075, 1.075] → 0.5
	# Zone fwd = 1.0, fwd_axis = FORWARD = (0,0,-1)
	# clamped_head_pos = (0.2, 0.5, -1.0)
	# target = clamped_head_pos - head_offset = (0.2, 0.1, -1.0)
	_assert_eq_v3(target, Vector3(0.2, 0.1, -1.0), 0.001, "ghost target from contact_local when blue-latched")

	# Test with contact outside zone bounds — should clamp
	var contact_outside := Vector3(2.0, 2.0, -1.0)
	var target_clamped: Vector3 = PostureScript._compute_committed_ghost_target(
		contact_outside, def, head_offset,
		Vector3.RIGHT, Vector3.FORWARD,
		0.075, 0.0
	)
	# Contact lat = 2.0, clamped to 0.5
	# Contact ht = 2.0, clamped to 1.075
	# target = (0.5, 1.075, -1.0) - (0, 0.4, 0) = (0.5, 0.675, -1.0)
	_assert_eq_v3(target_clamped, Vector3(0.5, 0.675, -1.0), 0.001, "ghost target clamps contact to zone bounds")

	# Test without zone definition — falls back to contact_local - head_offset
	var def_no_zone := _PostureDefinition.new()
	def_no_zone.has_zone = false
	var target_no_zone: Vector3 = PostureScript._compute_committed_ghost_target(
		contact_local, def_no_zone, head_offset,
		Vector3.RIGHT, Vector3.FORWARD,
		0.075, 0.0
	)
	_assert_eq_v3(target_no_zone, Vector3(0.2, 0.1, -1.0), 0.001, "ghost target falls back to contact_local")


## ── Helpers ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _color_approx(a: Color, b: Color, tol: float = 0.05) -> bool:
	return absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol and absf(a.b - b.b) <= tol

func _constrain_to_axis(delta: Vector3, axis: Vector3) -> Vector3:
	return axis * delta.dot(axis)

## Simulates the PositionGizmoV2 drag math from _update_drag.
func _simulate_drag_update(gizmo_pos: Vector3, drag_plane: Plane, drag_axis: String,
						   ray_origin: Vector3, ray_dir: Vector3) -> Vector3:
	var intersection: Variant = drag_plane.intersects_ray(ray_origin, ray_dir)
	if intersection == null:
		return gizmo_pos
	var new_pos: Vector3 = intersection
	if drag_axis != "":
		var axis_vec := Vector3.ZERO
		match drag_axis:
			"x": axis_vec = Vector3.RIGHT
			"y": axis_vec = Vector3.UP
			"z": axis_vec = Vector3.FORWARD
		var drag_delta: Vector3 = intersection - gizmo_pos
		var constrained: Vector3 = axis_vec * drag_delta.dot(axis_vec)
		new_pos = gizmo_pos + constrained
	return new_pos
