## Manages interactive 3D gizmos for posture editing.
## Handles gizmo creation, update, hover detection, procedural meshes.

signal gizmo_selected(gizmo)
signal gizmo_moved(gizmo, new_position: Vector3)
signal gizmo_rotated(gizmo, euler_delta: Vector3)

var _gizmo_controller
var _knee_mesh_nodes: Dictionary = {}
var _elbow_mesh_nodes: Dictionary = {}
var _player: Node3D = null
var _tree: SceneTree

## Injected
var _state  # PostureEditorState
var _tab_container: TabContainer

func init(player: Node3D, state, tab_container: TabContainer, tree: SceneTree) -> void:
	_player = player
	_state = state
	_tab_container = tab_container
	_tree = tree

func create_gizmo_controller() -> void:
	if _gizmo_controller:
		_gizmo_controller.queue_free()
	
	_gizmo_controller = load("res://scripts/posture_editor/gizmo_controller.gd").new()
	_gizmo_controller.name = "GizmoController"
	
	if _player and _player.get_parent():
		_player.get_parent().add_child(_gizmo_controller)
	else:
		_tree.root.add_child(_gizmo_controller)
	
	_gizmo_controller.gizmo_selected.connect(_on_gizmo_selected)
	_gizmo_controller.gizmo_moved.connect(_on_gizmo_moved)
	_gizmo_controller.gizmo_rotated.connect(_on_gizmo_rotated)
	
	var camera := _player.get_viewport().get_camera_3d() if _player else null
	if camera:
		_gizmo_controller.set_camera(camera)
	
	var can_create_gizmos := false
	if _player and _player.is_inside_tree():
		if _player.global_position.length() > 0.01:
			can_create_gizmos = true
	
	if can_create_gizmos:
		update_active_gizmos()
	update_gizmo_visibility()

func set_player(player: Node3D) -> void:
	_player = player

func get_current_paddle_position() -> Vector3:
	if _state.get_current_def() != null and not _state.is_base_pose_mode():
		return _calculate_paddle_world_position(_state.get_current_def())
	return Vector3.INF

func _calculate_paddle_world_position(def):
	if not _player or not _player.is_inside_tree():
		return Vector3.ZERO
	
	var player_pos: Vector3 = _player.global_position
	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	
	if forward_axis.length() < 0.01 or forehand_axis.length() < 0.01:
		return Vector3.ZERO
	
	var offset: Vector3 = forehand_axis * def.paddle_forehand_mul + forward_axis * def.paddle_forward_mul + Vector3(0.0, def.paddle_y_offset, 0.0)
	return player_pos + offset

func _color_for_family(family: int) -> Color:
	match family:
		0: return Color(0.3, 0.9, 0.3)   # Forehand: green
		1: return Color(0.9, 0.3, 0.3)   # Backhand: red
		2: return Color(0.3, 0.3, 0.9)   # Center: blue
		3: return Color(0.9, 0.9, 0.3)   # Overhead: yellow
		_: return Color(0.7, 0.7, 0.7)   # Default: gray

func _on_gizmo_selected(gizmo) -> void:
	gizmo_selected.emit(gizmo)

func _on_gizmo_moved(gizmo, new_position: Vector3) -> void:
	gizmo_moved.emit(gizmo, new_position)

func _on_gizmo_rotated(gizmo, euler_delta: Vector3) -> void:
	gizmo_rotated.emit(gizmo, euler_delta)

func update_active_gizmos() -> void:
	var body_def = _state.current_body_resource()
	if not _gizmo_controller or body_def == null:
		return
	
	_gizmo_controller.clear_all_gizmos()

	if not _state.is_base_pose_mode():
		_create_paddle_gizmos()
	_create_torso_gizmos()
	_create_head_gizmos()
	_create_arm_gizmos()
	_create_leg_gizmos()
	
	update_gizmo_visibility()

func _create_paddle_gizmos() -> void:
	if _state.is_base_pose_mode() or _state.get_current_def() == null:
		return
	if not _player or not _player.paddle_node: return
	if not _player.is_inside_tree() or not _player.paddle_node.is_inside_tree(): return
	var def = _state.get_current_def()
	var pos = _calculate_paddle_world_position(def)
	
	var gizmo = load("res://scripts/posture_editor/position_gizmo.gd").new()
	gizmo.name = "PositionGizmo_Paddle"
	gizmo.posture_id = def.posture_id
	gizmo.field_name = "paddle_position"
	gizmo.tab_name = "Paddle"
	gizmo.gizmo_color = _color_for_family(def.family)
	gizmo.gizmo_size = 0.08
	_gizmo_controller.add_gizmo_handle(gizmo)
	gizmo.global_position = pos

func _create_torso_gizmos() -> void:
	if not _player or not _player.skeleton: return
	
	var hip_idx: int = _player.skeleton.find_bone("hips")
	if hip_idx >= 0:
		var hip_pos: Vector3 = _player.skeleton.to_global(_player.skeleton.get_bone_global_pose(hip_idx).origin)
		var gizmo = load("res://scripts/posture_editor/rotation_gizmo.gd").new()
		gizmo.name = "RotationGizmo_Hips"
		gizmo.posture_id = _state.get_current_id()
		gizmo.field_name = "hip_rotation"
		gizmo.tab_name = "Torso"
		gizmo.body_part_name = "hips"
		gizmo.gizmo_color = Color(0, 1, 1)
		gizmo.ring_radius = 0.3
		_gizmo_controller.add_gizmo_handle(gizmo)
		gizmo.global_position = hip_pos
	
	var chest_idx: int = _player.skeleton.find_bone("chest")
	if chest_idx >= 0:
		var chest_pos: Vector3 = _player.skeleton.to_global(_player.skeleton.get_bone_global_pose(chest_idx).origin)
		var gizmo = load("res://scripts/posture_editor/rotation_gizmo.gd").new()
		gizmo.name = "RotationGizmo_Torso"
		gizmo.posture_id = _state.get_current_id()
		gizmo.field_name = "torso_rotation"
		gizmo.tab_name = "Torso"
		gizmo.body_part_name = "chest"
		gizmo.gizmo_color = Color(1, 0.5, 0)
		gizmo.ring_radius = 0.25
		_gizmo_controller.add_gizmo_handle(gizmo)
		gizmo.global_position = chest_pos

func _create_head_gizmos() -> void:
	if not _player or not _player.skeleton: return
	
	var head_idx: int = _player.skeleton.find_bone("head")
	if head_idx >= 0:
		var head_pos: Vector3 = _player.skeleton.to_global(_player.skeleton.get_bone_global_pose(head_idx).origin)
		var gizmo = load("res://scripts/posture_editor/rotation_gizmo.gd").new()
		gizmo.name = "RotationGizmo_Head"
		gizmo.posture_id = _state.get_current_id()
		gizmo.field_name = "head_rotation"
		gizmo.tab_name = "Head"
		gizmo.body_part_name = "head"
		gizmo.gizmo_color = Color(1, 1, 1)
		gizmo.ring_radius = 0.15
		_gizmo_controller.add_gizmo_handle(gizmo)
		gizmo.global_position = head_pos

func _create_arm_gizmos() -> void:
	if not _player or not _player.paddle_node: return
	if not _player.is_inside_tree() or not _player.paddle_node.is_inside_tree(): return
	
	var r_hand_pivot: Node3D = _player.right_arm_node.get_node_or_null("UpperArmPivot/ForearmPivot/HandPivot")
	var r_hand_world: Vector3 = r_hand_pivot.global_position if r_hand_pivot else _player.paddle_node.to_global(Vector3(0, 0.07, 0))
	var r_gizmo = load("res://scripts/posture_editor/position_gizmo.gd").new()
	r_gizmo.name = "PositionGizmo_RightHand"
	r_gizmo.posture_id = _state.get_current_id()
	r_gizmo.field_name = "right_hand_offset"
	r_gizmo.tab_name = "Arms"
	r_gizmo.body_part_name = "right_hand"
	r_gizmo.gizmo_color = Color(1, 1, 0)
	_gizmo_controller.add_gizmo_handle(r_gizmo)
	r_gizmo.global_position = r_hand_world
	
	var l_hand_pivot: Node3D = _player.left_arm_node.get_node_or_null("UpperArmPivot/ForearmPivot/HandPivot")
	var l_hand_world: Vector3 = l_hand_pivot.global_position if l_hand_pivot else Vector3.ZERO
	var l_gizmo = load("res://scripts/posture_editor/position_gizmo.gd").new()
	l_gizmo.name = "PositionGizmo_LeftHand"
	l_gizmo.posture_id = _state.get_current_id()
	l_gizmo.field_name = "left_hand_offset"
	l_gizmo.tab_name = "Arms"
	l_gizmo.body_part_name = "left_hand"
	l_gizmo.gizmo_color = Color(0, 1, 1)
	_gizmo_controller.add_gizmo_handle(l_gizmo)
	l_gizmo.global_position = l_hand_world
	
	var r_elbow_pivot: Node3D = _player.right_arm_node.get_node_or_null("UpperArmPivot/ForearmPivot")
	var r_elbow_world: Vector3 = r_elbow_pivot.global_position if r_elbow_pivot else _player.global_position + _player._get_forehand_axis() * 0.5 + Vector3(0, -1.0, 0) + _player._get_forward_axis() * -0.5
	var r_elbow_gizmo = load("res://scripts/posture_editor/position_gizmo.gd").new()
	r_elbow_gizmo.name = "PositionGizmo_RightElbow"
	r_elbow_gizmo.posture_id = _state.get_current_id()
	r_elbow_gizmo.field_name = "right_elbow_pole"
	r_elbow_gizmo.tab_name = "Arms"
	r_elbow_gizmo.body_part_name = "right_elbow"
	r_elbow_gizmo.gizmo_color = Color(1, 0.5, 0)
	_gizmo_controller.add_gizmo_handle(r_elbow_gizmo)
	r_elbow_gizmo.global_position = r_elbow_world
	
	var l_elbow_pivot: Node3D = _player.left_arm_node.get_node_or_null("UpperArmPivot/ForearmPivot")
	var l_elbow_world: Vector3 = l_elbow_pivot.global_position if l_elbow_pivot else _player.global_position + _player._get_forehand_axis() * -0.5 + Vector3(0, -1.0, 0) + _player._get_forward_axis() * -0.5
	var l_elbow_gizmo = load("res://scripts/posture_editor/position_gizmo.gd").new()
	l_elbow_gizmo.name = "PositionGizmo_LeftElbow"
	l_elbow_gizmo.posture_id = _state.get_current_id()
	l_elbow_gizmo.field_name = "left_elbow_pole"
	l_elbow_gizmo.tab_name = "Arms"
	l_elbow_gizmo.body_part_name = "left_elbow"
	l_elbow_gizmo.gizmo_color = Color(0.5, 0.5, 1)
	_gizmo_controller.add_gizmo_handle(l_elbow_gizmo)
	l_elbow_gizmo.global_position = l_elbow_world

func _create_leg_gizmos() -> void:
	if not _player: return
	if not _player.is_inside_tree(): return
	
	var r_foot_pivot: Node3D = _player.right_leg_node.get_node_or_null("ThighPivot/ShinPivot/FootPivot")
	var r_foot_world: Vector3 = r_foot_pivot.global_position if r_foot_pivot else Vector3.ZERO
	var r_gizmo = load("res://scripts/posture_editor/position_gizmo.gd").new()
	r_gizmo.name = "PositionGizmo_RightFoot"
	r_gizmo.posture_id = _state.get_current_id()
	r_gizmo.field_name = "right_foot_offset"
	r_gizmo.tab_name = "Legs"
	r_gizmo.body_part_name = "right_foot"
	r_gizmo.gizmo_color = Color(0.9, 0.3, 0.9)
	_gizmo_controller.add_gizmo_handle(r_gizmo)
	r_gizmo.global_position = r_foot_world
	
	var l_foot_pivot: Node3D = _player.left_leg_node.get_node_or_null("ThighPivot/ShinPivot/FootPivot")
	var l_foot_world: Vector3 = l_foot_pivot.global_position if l_foot_pivot else Vector3.ZERO
	var l_gizmo = load("res://scripts/posture_editor/position_gizmo.gd").new()
	l_gizmo.name = "PositionGizmo_LeftFoot"
	l_gizmo.posture_id = _state.get_current_id()
	l_gizmo.field_name = "left_foot_offset"
	l_gizmo.tab_name = "Legs"
	l_gizmo.body_part_name = "left_foot"
	l_gizmo.gizmo_color = Color(0.3, 0.3, 0.9)
	_gizmo_controller.add_gizmo_handle(l_gizmo)
	l_gizmo.global_position = l_foot_world
	
	var r_knee_pivot: Node3D = _player.right_leg_node.get_node_or_null("ThighPivot/ShinPivot")
	var r_knee_world: Vector3 = r_knee_pivot.global_position if r_knee_pivot else r_foot_world + Vector3(0, 0.5, 0)
	var r_knee_gizmo = load("res://scripts/posture_editor/position_gizmo.gd").new()
	r_knee_gizmo.name = "PositionGizmo_RightKnee"
	r_knee_gizmo.posture_id = _state.get_current_id()
	r_knee_gizmo.field_name = "right_knee_pole"
	r_knee_gizmo.tab_name = "Legs"
	r_knee_gizmo.body_part_name = "right_knee"
	r_knee_gizmo.gizmo_color = Color(1, 0.3, 0.3)
	_gizmo_controller.add_gizmo_handle(r_knee_gizmo)
	r_knee_gizmo.global_position = r_knee_world
	
	var l_knee_pivot: Node3D = _player.left_leg_node.get_node_or_null("ThighPivot/ShinPivot")
	var l_knee_world: Vector3 = l_knee_pivot.global_position if l_knee_pivot else l_foot_world + Vector3(0, 0.5, 0)
	var l_knee_gizmo = load("res://scripts/posture_editor/position_gizmo.gd").new()
	l_knee_gizmo.name = "PositionGizmo_LeftKnee"
	l_knee_gizmo.posture_id = _state.get_current_id()
	l_knee_gizmo.field_name = "left_knee_pole"
	l_knee_gizmo.tab_name = "Legs"
	l_knee_gizmo.body_part_name = "left_knee"
	l_knee_gizmo.gizmo_color = Color(0.3, 0.9, 0.3)
	_gizmo_controller.add_gizmo_handle(l_knee_gizmo)
	l_knee_gizmo.global_position = l_knee_world

func refresh_live_preview() -> void:
	var preview_def = _state.current_body_resource()
	if preview_def == null:
		return
	if _player and _player.posture and Engine.time_scale < 0.001:
		_player.posture.force_posture_update(preview_def)

func update_gizmo_positions() -> void:
	var body_def = _state.current_body_resource()
	if not _gizmo_controller or not _player or body_def == null:
		return
	if not _player.skeleton: return
	
	for gizmo in _gizmo_controller.get_children():
		if not gizmo.has_method("get_posture_id"): continue
		if _gizmo_controller.get_selected_gizmo() == gizmo: continue
		
		match gizmo.field_name:
			"paddle_position":
				if _state.get_current_def():
					gizmo.global_position = _calculate_paddle_world_position(_state.get_current_def())
			"hip_rotation":
				var idx: int = _player.skeleton.find_bone("hips")
				if idx >= 0: gizmo.global_position = _player.skeleton.to_global(_player.skeleton.get_bone_global_pose(idx).origin)
			"torso_rotation":
				var idx: int = _player.skeleton.find_bone("chest")
				if idx >= 0: gizmo.global_position = _player.skeleton.to_global(_player.skeleton.get_bone_global_pose(idx).origin)
			"head_rotation":
				var idx: int = _player.skeleton.find_bone("head")
				if idx >= 0: gizmo.global_position = _player.skeleton.to_global(_player.skeleton.get_bone_global_pose(idx).origin)
			"right_hand_offset":
				var r_hand_pivot: Node3D = _player.right_arm_node.get_node_or_null("UpperArmPivot/ForearmPivot/HandPivot")
				if r_hand_pivot: gizmo.global_position = r_hand_pivot.global_position
			"left_hand_offset":
				var l_hand_pivot: Node3D = _player.left_arm_node.get_node_or_null("UpperArmPivot/ForearmPivot/HandPivot")
				if l_hand_pivot: gizmo.global_position = l_hand_pivot.global_position
			"right_elbow_pole":
				var r_elbow_pivot: Node3D = _player.right_arm_node.get_node_or_null("UpperArmPivot/ForearmPivot")
				if r_elbow_pivot: gizmo.global_position = r_elbow_pivot.global_position
			"left_elbow_pole":
				var l_elbow_pivot: Node3D = _player.left_arm_node.get_node_or_null("UpperArmPivot/ForearmPivot")
				if l_elbow_pivot: gizmo.global_position = l_elbow_pivot.global_position
			"right_foot_offset":
				var r_foot_pivot: Node3D = _player.right_leg_node.get_node_or_null("ThighPivot/ShinPivot/FootPivot")
				if r_foot_pivot: gizmo.global_position = r_foot_pivot.global_position
			"left_foot_offset":
				var l_foot_pivot: Node3D = _player.left_leg_node.get_node_or_null("ThighPivot/ShinPivot/FootPivot")
				if l_foot_pivot: gizmo.global_position = l_foot_pivot.global_position
			"right_knee_pole":
				var r_knee_pivot: Node3D = _player.right_leg_node.get_node_or_null("ThighPivot/ShinPivot")
				if r_knee_pivot: gizmo.global_position = r_knee_pivot.global_position
			"left_knee_pole":
				var l_knee_pivot: Node3D = _player.left_leg_node.get_node_or_null("ThighPivot/ShinPivot")
				if l_knee_pivot: gizmo.global_position = l_knee_pivot.global_position

func update_gizmo_visibility() -> void:
	if _gizmo_controller:
		_gizmo_controller.visible = true  # Visibility managed by shell
		var current_tab_name := ""
		if _tab_container:
			var current_tab_control = _tab_container.get_child(_tab_container.current_tab)
			if current_tab_control:
				current_tab_name = current_tab_control.name
		
		for gizmo in _gizmo_controller.get_children():
			if not gizmo.has_method("get_posture_id"): continue
			var gh: GizmoHandle = gizmo as GizmoHandle
			if gh.body_part_name in ["chest", "head", "hips", "right_hand", "left_hand", "right_foot", "left_foot", "right_elbow", "left_elbow", "right_knee", "left_knee"]:
				gizmo.visible = false
				continue
			var posture_match: bool = (_state.get_current_id() < 0) or (gh.posture_id == _state.get_current_id())
			var tab_match: bool = (gh.tab_name == "") or (gh.tab_name == current_tab_name)
			gizmo.visible = posture_match and tab_match

func process_frame(_delta: float) -> void:
	if not _gizmo_controller or not _player or not _player.is_inside_tree() or not _player.skeleton:
		return
	
	var positions: Dictionary = {}
	var skel = _player.skeleton
	for bone_name in ["chest", "head", "hips"]:
		var idx: int = skel.find_bone(bone_name)
		if idx >= 0:
			positions[bone_name] = skel.to_global(skel.get_bone_global_pose(idx).origin)
	
	var meshes: Dictionary = {}
	if _player.body_pivot:
		var chest_mesh: MeshInstance3D = _player.body_pivot.get_node_or_null("chest_inst")
		var hips_mesh: MeshInstance3D = _player.body_pivot.get_node_or_null("hips_inst")
		var head_mesh: MeshInstance3D
		if chest_mesh:
			head_mesh = chest_mesh.get_node_or_null("head_inst")
		if chest_mesh: meshes["chest"] = chest_mesh
		if head_mesh: meshes["head"] = head_mesh
		if hips_mesh: meshes["hips"] = hips_mesh
		if _player.right_arm_node:
			var r_hand_mesh: MeshInstance3D = _player.right_arm_node.get_node_or_null("UpperArmPivot/ForearmPivot/HandPivot/HandMesh")
			if r_hand_mesh: meshes["right_hand"] = r_hand_mesh
		if _player.left_arm_node:
			var l_hand_mesh: MeshInstance3D = _player.left_arm_node.get_node_or_null("UpperArmPivot/ForearmPivot/HandPivot/HandMesh")
			if l_hand_mesh: meshes["left_hand"] = l_hand_mesh
		if _player.right_leg_node:
			var r_foot_mesh: MeshInstance3D = _player.right_leg_node.get_node_or_null("ThighPivot/ShinPivot/FootPivot/FootMesh")
			if r_foot_mesh: meshes["right_foot"] = r_foot_mesh
		if _player.left_leg_node:
			var l_foot_mesh: MeshInstance3D = _player.left_leg_node.get_node_or_null("ThighPivot/ShinPivot/FootPivot/FootMesh")
			if l_foot_mesh: meshes["left_foot"] = l_foot_mesh
		
		# Knee meshes
		if _player.right_leg_node:
			var r_shin: Node3D = _player.right_leg_node.get_node_or_null("ThighPivot/ShinPivot")
			if r_shin:
				if not _knee_mesh_nodes.has("right_knee"):
					var k_mesh := MeshInstance3D.new()
					k_mesh.name = "KneeMesh_Right"
					var sphere := SphereMesh.new()
					sphere.radius = 0.06
					sphere.height = 0.12
					k_mesh.mesh = sphere
					var mat := StandardMaterial3D.new()
					mat.albedo_color = Color(1, 0.3, 0.3, 0.7)
					k_mesh.material_override = mat
					r_shin.add_child(k_mesh)
					_knee_mesh_nodes["right_knee"] = k_mesh
				meshes["right_knee"] = _knee_mesh_nodes["right_knee"]
		if _player.left_leg_node:
			var l_shin: Node3D = _player.left_leg_node.get_node_or_null("ThighPivot/ShinPivot")
			if l_shin:
				if not _knee_mesh_nodes.has("left_knee"):
					var k_mesh := MeshInstance3D.new()
					k_mesh.name = "KneeMesh_Left"
					var sphere := SphereMesh.new()
					sphere.radius = 0.06
					sphere.height = 0.12
					k_mesh.mesh = sphere
					var mat := StandardMaterial3D.new()
					mat.albedo_color = Color(0.3, 0.9, 0.3, 0.7)
					k_mesh.material_override = mat
					l_shin.add_child(k_mesh)
					_knee_mesh_nodes["left_knee"] = k_mesh
				meshes["left_knee"] = _knee_mesh_nodes["left_knee"]
		
		# Elbow meshes
		if _player.right_arm_node:
			var r_forearm: Node3D = _player.right_arm_node.get_node_or_null("UpperArmPivot/ForearmPivot")
			if r_forearm:
				if not _elbow_mesh_nodes.has("right_elbow"):
					var e_mesh := MeshInstance3D.new()
					e_mesh.name = "ElbowMesh_Right"
					var sphere := SphereMesh.new()
					sphere.radius = 0.05
					sphere.height = 0.10
					e_mesh.mesh = sphere
					var mat := StandardMaterial3D.new()
					mat.albedo_color = Color(1, 0.5, 0, 0.7)
					e_mesh.material_override = mat
					r_forearm.add_child(e_mesh)
					_elbow_mesh_nodes["right_elbow"] = e_mesh
				meshes["right_elbow"] = _elbow_mesh_nodes["right_elbow"]
		if _player.left_arm_node:
			var l_forearm: Node3D = _player.left_arm_node.get_node_or_null("UpperArmPivot/ForearmPivot")
			if l_forearm:
				if not _elbow_mesh_nodes.has("left_elbow"):
					var e_mesh := MeshInstance3D.new()
					e_mesh.name = "ElbowMesh_Left"
					var sphere := SphereMesh.new()
					sphere.radius = 0.05
					sphere.height = 0.10
					e_mesh.mesh = sphere
					var mat := StandardMaterial3D.new()
					mat.albedo_color = Color(0.5, 0.5, 1, 0.7)
					e_mesh.material_override = mat
					l_forearm.add_child(e_mesh)
					_elbow_mesh_nodes["left_elbow"] = e_mesh
				meshes["left_elbow"] = _elbow_mesh_nodes["left_elbow"]
	_gizmo_controller.set_body_part_meshes(meshes)
	
	# Hand and foot positions from current posture definition
	var def = _state.current_body_resource()
	if def:
		var forehand_axis: Vector3 = _player._get_forehand_axis()
		var forward_axis: Vector3 = _player._get_forward_axis()
		if _player.paddle_node and _player.paddle_node.is_inside_tree():
			var r_base = _player.paddle_node.to_global(Vector3(0, 0.07, 0))
			positions["right_hand"] = r_base + load("res://scripts/posture_skeleton_applier.gd").stance_offset(def.right_hand_offset, forehand_axis, forward_axis)
			var l_base: Vector3
			match def.left_hand_mode:
				1: l_base = _player.paddle_node.to_global(Vector3(0, 0.20, 0))
				2: l_base = _player.global_position + forehand_axis * -0.2 + forward_axis * 0.2 + Vector3(0, 0.45, 0)
				3: l_base = _player.global_position + Vector3(0, 1.05, 0) + forward_axis * 0.15
				_: l_base = _player.global_position
			positions["left_hand"] = l_base + load("res://scripts/posture_skeleton_applier.gd").stance_offset(def.left_hand_offset, forehand_axis, forward_axis)
		var gnd_y: float = 0.0
		var base: Vector3 = Vector3(_player.global_position.x, gnd_y, _player.global_position.z)
		var half_excess: float = (def.stance_width - 0.35) * 0.5
		var r_lateral: Vector3 = forehand_axis * (0.14 + half_excess)
		var l_lateral: Vector3 = forehand_axis * -(0.14 + half_excess)
		var r_fwd: float = -0.06
		var l_fwd: float = 0.06
		if def.lead_foot == 0:
			r_fwd += def.front_foot_forward
			l_fwd += def.back_foot_back
		else:
			l_fwd += def.front_foot_forward
			r_fwd += def.back_foot_back
		var r_foot_world: Vector3 = base + r_lateral + forward_axis * r_fwd + load("res://scripts/posture_skeleton_applier.gd").stance_offset(def.right_foot_offset, forehand_axis, forward_axis)
		var l_foot_world: Vector3 = base + l_lateral + forward_axis * l_fwd + load("res://scripts/posture_skeleton_applier.gd").stance_offset(def.left_foot_offset, forehand_axis, forward_axis)
		positions["right_foot"] = r_foot_world
		positions["left_foot"] = l_foot_world
		positions["right_knee"] = r_foot_world + load("res://scripts/posture_skeleton_applier.gd").stance_offset(def.right_knee_pole, forehand_axis, forward_axis)
		positions["left_knee"] = l_foot_world + load("res://scripts/posture_skeleton_applier.gd").stance_offset(def.left_knee_pole, forehand_axis, forward_axis)
		var r_elbow_world: Vector3 = _player.global_position + forehand_axis * 0.5 + Vector3(0, -1.0, 0) + forward_axis * -0.5
		if def.right_elbow_pole.length_squared() > 1e-10:
			r_elbow_world = r_elbow_world + load("res://scripts/posture_skeleton_applier.gd").stance_offset(def.right_elbow_pole, forehand_axis, forward_axis)
		var l_elbow_world: Vector3 = _player.global_position + forehand_axis * -0.5 + Vector3(0, -1.0, 0) + forward_axis * -0.5
		if def.left_elbow_pole.length_squared() > 1e-10:
			l_elbow_world = l_elbow_world + load("res://scripts/posture_skeleton_applier.gd").stance_offset(def.left_elbow_pole, forehand_axis, forward_axis)
		positions["right_elbow"] = r_elbow_world
		positions["left_elbow"] = l_elbow_world
	_gizmo_controller.update_body_part_positions(positions)

func teardown_mesh_nodes() -> void:
	for k_name in _knee_mesh_nodes.keys():
		var k_mesh: MeshInstance3D = _knee_mesh_nodes[k_name]
		k_mesh.queue_free()
	_knee_mesh_nodes.clear()
	for e_name in _elbow_mesh_nodes.keys():
		var e_mesh: MeshInstance3D = _elbow_mesh_nodes[e_name]
		e_mesh.queue_free()
	_elbow_mesh_nodes.clear()

func get_gizmo_controller():
	return _gizmo_controller
