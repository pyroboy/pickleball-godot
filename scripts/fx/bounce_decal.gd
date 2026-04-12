extends Node3D
class_name BounceDecal
## Pooled flat glow disc spawned at ball bounce spots.
## Compatibility renderer has no Decal node, so we use a thin cylinder mesh
## with an additive unshaded material and tween its alpha to fake glow.

const DURATION: float = 0.7
const RADIUS: float = 0.10
const HEIGHT: float = 0.004

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _active: bool = false
var _tween: Tween

func _ready() -> void:
	name = "BounceDecal"
	_mesh = MeshInstance3D.new()
	_mesh.name = "M"
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = RADIUS
	cyl.bottom_radius = RADIUS
	cyl.height = HEIGHT
	cyl.radial_segments = 8   # Mobile: reduced from 18
	cyl.rings = 1
	_mesh.mesh = cyl

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_material.albedo_color = Color(1, 1, 1, 1)
	_material.disable_receive_shadows = true
	_material.no_depth_test = false
	_mesh.material_override = _material
	add_child(_mesh)
	visible = false

func play(pos: Vector3, color: Color) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	global_position = Vector3(pos.x, maxf(pos.y, 0.08), pos.z)
	_material.albedo_color = Color(color.r, color.g, color.b, 1.0)
	_mesh.scale = Vector3(0.6, 1.0, 0.6)
	visible = true
	_active = true

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_mesh, "scale", Vector3(1.4, 1.0, 1.4), DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_material, "albedo_color:a", 0.0, DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_callback(Callable(self, "_on_fade_done"))

func _on_fade_done() -> void:
	_active = false
	visible = false

func play_duration() -> float:
	return DURATION + 0.1

func is_active() -> bool:
	return _active
