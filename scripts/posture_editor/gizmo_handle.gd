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

# Metadata for the editor
var posture_id: int = -1
var field_name: String = ""
var is_right_side: bool = true  # For paired gizmos (left/right)

func _ready() -> void:
	_setup_visuals()

func _setup_visuals() -> void:
	_base_material = StandardMaterial3D.new()
	_base_material.albedo_color = gizmo_color
	_base_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_base_material.albedo_color.a = 0.7
	_base_material.no_depth_test = true
	material_override = _base_material
	_update_visual_state()

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
	elif _is_hovered:
		_base_material.albedo_color = hover_color
		_base_material.albedo_color.a = 0.8
		scale = Vector3.ONE * 1.1
	else:
		_base_material.albedo_color = gizmo_color
		_base_material.albedo_color.a = 0.7
		scale = Vector3.ONE

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
