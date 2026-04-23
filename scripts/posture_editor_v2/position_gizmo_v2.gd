class_name PositionGizmoV2 extends MeshInstance3D

## Simple spherical position gizmo for v2.

var field_name: String = ""
var gizmo_color: Color = Color(0.3, 0.9, 0.3)
var gizmo_size: float = 0.08

func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = gizmo_size
	sphere.height = gizmo_size * 2.0
	mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = gizmo_color
	mat.emission_enabled = true
	mat.emission = gizmo_color
	mat.emission_energy_multiplier = 1.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_override = mat

## Returns hit distance along ray, or -1 if no hit.
func raycast_test(ray_origin: Vector3, ray_dir: Vector3) -> float:
	var to_center: Vector3 = global_position - ray_origin
	var proj: float = to_center.dot(ray_dir)
	if proj < 0:
		return -1.0
	var closest: Vector3 = ray_origin + ray_dir * proj
	var dist: float = closest.distance_to(global_position)
	if dist > gizmo_size * 1.5:
		return -1.0
	return proj
