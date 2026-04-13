class_name GizmoHandle extends MeshInstance3D

## Base class for interactive 3D gizmos
## Handles visual state (hover, selected) and ray intersection

enum GizmoType { POSITION, ROTATION, SCALE }

@export var gizmo_type: GizmoType = GizmoType.POSITION
@export var gizmo_color: Color = Color.WHITE
@export var hover_color: Color = Color.YELLOW
@export var selected_color: Color = Color.GREEN
@export var gizmo_size: float = 0.08

var _is_hovered: bool = false
var _is_selected: bool = false
var _base_material: StandardMaterial3D
var _name_label: Label3D = null

# Metadata for the editor
var posture_id: int = -1
var field_name: String = ""
var is_right_side: bool = true  # For paired gizmos (left/right)
var tab_name: String = ""  # Which editor tab this gizmo belongs to
var body_part_name: String = ""  # "chest", "head", "hips", "right_hand", etc.

## Custom ray test — body part gizmos return -1 so they never block
## body-mesh hover detection. Paddle gizmos use normal sphere intersection.
func raycast_test(ray_origin: Vector3, ray_dir: Vector3) -> float:
	if body_part_name != "":
		return -1.0  # Body gizmos are invisible to raycasts; body mesh detection is used instead
	# Fall back to sphere intersection for paddle gizmos
	var to_center := global_position - ray_origin
	var proj := to_center.dot(ray_dir)
	if proj < 0:
		return -1.0
	var closest_point: Vector3 = ray_origin + ray_dir * proj
	var dist_sq: float = closest_point.distance_squared_to(global_position)
	var radius: float = gizmo_size * maxf(scale.x, maxf(scale.y, scale.z))
	if dist_sq > radius * radius:
		return -1.0
	var offset: float = sqrt(radius * radius - dist_sq)
	return proj - offset

func _ready() -> void:
	_setup_visuals()

func _setup_visuals() -> void:
	_base_material = StandardMaterial3D.new()
	_base_material.albedo_color = gizmo_color
	_base_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_base_material.albedo_color.a = 0.7
	_base_material.no_depth_test = true
	material_override = _base_material
	
	# Debug name label — always visible above the gizmo, shows field_name
	_name_label = Label3D.new()
	_name_label.name = "NameLabel"
	_name_label.text = field_name if field_name != "" else name
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.font_size = 14
	_name_label.modulate = Color(1.0, 0.85, 0.2, 0.95)  # warm yellow
	_name_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	_name_label.pixel_size = 0.01  # mid: between too-big (0.02) and too-small (0.001)
	_name_label.no_depth_test = true
	_name_label.position = Vector3(0, 0.08, 0)  # offset above gizmo center
	add_child(_name_label)
	
	_update_visual_state()

func _process(_delta: float) -> void:
	# Keep name label in sync — field_name may be set after _ready()
	if _name_label and _name_label.text != field_name:
		_name_label.text = field_name if field_name != "" else name

func set_hovered(hovered: bool) -> void:
	_is_hovered = hovered
	_update_visual_state()

func set_selected(selected: bool) -> void:
	_is_selected = selected
	_update_visual_state()

func is_hovered() -> bool:
	return _is_hovered

func is_selected() -> bool:
	return _is_selected

func _update_visual_state() -> void:
	if not _base_material:
		return
	
	if _is_selected:
		_base_material.albedo_color = selected_color
		_base_material.albedo_color.a = 0.9
		scale = Vector3.ONE * 1.3
		if _name_label:
			_name_label.modulate = Color(1.0, 1.0, 0.3, 1.0)  # bright gold when selected
	elif _is_hovered:
		_base_material.albedo_color = hover_color
		_base_material.albedo_color.a = 0.8
		scale = Vector3.ONE * 1.1
		if _name_label:
			_name_label.modulate = Color(1.0, 1.0, 0.6, 0.95)  # yellow when hovered
	else:
		_base_material.albedo_color = gizmo_color
		_base_material.albedo_color.a = 0.7
		scale = Vector3.ONE
		if _name_label:
			_name_label.modulate = Color(1.0, 0.85, 0.2, 0.95)  # warm yellow at rest

## Ray intersection for selection
## Returns distance along ray if hit, -1 if miss
func intersect_ray(ray_origin: Vector3, ray_dir: Vector3) -> float:
	# Default implementation: ray-sphere intersection
	# Subclasses can override for different shapes
	var to_center := global_position - ray_origin
	var proj := to_center.dot(ray_dir)
	
	if proj < 0:
		return -1.0  # Ray pointing away
	
	var closest_point := ray_origin + ray_dir * proj
	var dist_sq := closest_point.distance_squared_to(global_position)
	var radius := gizmo_size * maxf(scale.x, maxf(scale.y, scale.z))
	
	if dist_sq > radius * radius:
		return -1.0  # Missed sphere
	
	# Calculate entry point distance
	var offset := sqrt(radius * radius - dist_sq)
	return proj - offset

## Called when gizmo starts being dragged
func on_drag_start() -> void:
	pass

## Called when gizmo is being dragged
## delta: movement in world space
func on_drag(delta: Vector3) -> void:
	global_position += delta

## Called when drag ends
func on_drag_end() -> void:
	pass

## Get the posture value this gizmo represents
## Subclasses override to convert world position to posture field
func get_posture_value() -> Variant:
	return global_position

## Set gizmo position from posture value
## Subclasses override to convert posture field to world position
func set_from_posture_value(value: Variant) -> void:
	if value is Vector3:
		global_position = value
