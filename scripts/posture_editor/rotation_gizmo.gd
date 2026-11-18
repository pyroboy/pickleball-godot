class_name RotationGizmo extends GizmoHandle



@export var ring_radius: float = 0.2
@export var ring_tube_radius: float = 0.015
@export var ring_segments: int = 64

var _rings: Dictionary = {}
var _ring_materials: Dictionary = {}

enum Axis{X, Y, Z}
var _hovered_ring: Axis = Axis.X

func _ready() -> void :
    gizmo_type = GizmoType.ROTATION
    _create_rings()
    super._ready()

func _create_rings() -> void :
    var axis_data: = {
        "x": {"rotation": Vector3(0, 0, - PI / 2), "color": Color(1, 0, 0)}, 
        "y": {"rotation": Vector3(0, 0, 0), "color": Color(0, 1, 0)}, 
        "z": {"rotation": Vector3(PI / 2, 0, 0), "color": Color(0, 0, 1)}
    }

    for axis_name in ["x", "y", "z"]:
        var ring: = MeshInstance3D.new()
        ring.name = "RotationRing_" + axis_name.to_upper()


        var torus: = TorusMesh.new()
        torus.inner_radius = ring_radius - ring_tube_radius
        torus.outer_radius = ring_radius + ring_tube_radius
        ring.mesh = torus


        ring.rotation = axis_data[axis_name].rotation


        var mat: = StandardMaterial3D.new()
        mat.albedo_color = axis_data[axis_name].color
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        mat.albedo_color.a = 0.6
        mat.no_depth_test = true
        ring.material_override = mat

        _rings[axis_name] = ring
        _ring_materials[axis_name] = mat
        add_child(ring)

func highlight_ring(axis: Axis) -> void :
    _hovered_ring = axis


    for mat in _ring_materials.values():
        mat.albedo_color.a = 0.3


    var axis_name: = ""
    match axis:
        Axis.X: axis_name = "x"
        Axis.Y: axis_name = "y"
        Axis.Z: axis_name = "z"

    if _ring_materials.has(axis_name):
        _ring_materials[axis_name].albedo_color.a = 1.0
        _ring_materials[axis_name].emission_enabled = true
        _ring_materials[axis_name].emission = _ring_materials[axis_name].albedo_color
        _ring_materials[axis_name].emission_energy = 0.5

func clear_ring_highlight() -> void :
    for mat in _ring_materials.values():
        mat.albedo_color.a = 0.6
        mat.emission_enabled = false


func intersect_ray(ray_origin: Vector3, ray_dir: Vector3) -> float:
    var closest_hit: = -1.0
    var closest_axis: = Axis.X

    for axis_name in ["x", "y", "z"]:
        if not _rings.has(axis_name):
            continue

        var ring: MeshInstance3D = _rings[axis_name]
        var ring_hit: = _intersect_torus(
            ray_origin, ray_dir, 
            ring.global_position, 
            ring.global_transform.basis, 
            ring_radius, 
            ring_tube_radius
        )

        if ring_hit >= 0 and (closest_hit < 0 or ring_hit < closest_hit):
            closest_hit = ring_hit
            match axis_name:
                "x": closest_axis = Axis.X
                "y": closest_axis = Axis.Y
                "z": closest_axis = Axis.Z

    if closest_hit >= 0:
        highlight_ring(closest_axis)
    else:
        clear_ring_highlight()

    return closest_hit

func _intersect_torus(ray_origin: Vector3, ray_dir: Vector3, 
                     torus_pos: Vector3, torus_basis: Basis, 
                     major_radius: float, minor_radius: float) -> float:

    var local_origin: = torus_basis.inverse() * (ray_origin - torus_pos)
    var local_dir: = torus_basis.inverse() * ray_dir








    var to_torus: = torus_pos - ray_origin
    var proj: = to_torus.dot(ray_dir)

    if proj < - minor_radius - major_radius:
        return -1.0

    var closest_dist_sq: = to_torus.length_squared() - proj * proj
    var bounds: = major_radius + minor_radius

    if closest_dist_sq > bounds * bounds:
        return -1.0


    var t: float = maxf(0.0, proj - bounds)
    var t_max: = proj + bounds
    var step: = (t_max - t) / 32.0

    for i in range(32):
        var p: = local_origin + local_dir * t
        var dist: = _torus_sdf(p, major_radius, minor_radius)

        if dist < 0.001:
            return t

        t += maxf(step, dist * 0.5)
        if t > t_max:
            break

    return -1.0

func _torus_sdf(p: Vector3, R: float, r: float) -> float:

    var q: = Vector2(Vector2(p.x, p.z).length() - R, p.y)
    return q.length() - r

func get_hovered_axis() -> Axis:
    return _hovered_ring



func calculate_rotation_from_drag(start_pos: Vector3, end_pos: Vector3, camera_pos: Vector3) -> Vector3:
    var result: = Vector3.ZERO

    match _hovered_ring:
        Axis.X:
            result.x = _calculate_ring_rotation(start_pos, end_pos, camera_pos, Vector3.RIGHT)
        Axis.Y:
            result.y = _calculate_ring_rotation(start_pos, end_pos, camera_pos, Vector3.UP)
        Axis.Z:
            result.z = _calculate_ring_rotation(start_pos, end_pos, camera_pos, Vector3.FORWARD)

    return result

func _calculate_ring_rotation(start: Vector3, end: Vector3, _camera: Vector3, axis: Vector3) -> float:

    var center: = global_position
    var to_start: = (start - center).normalized()
    var to_end: = (end - center).normalized()


    to_start = (to_start - to_start.dot(axis) * axis).normalized()
    to_end = (to_end - to_end.dot(axis) * axis).normalized()


    var angle: = atan2(to_start.cross(to_end).dot(axis), to_start.dot(to_end))

    return rad_to_deg(angle)
