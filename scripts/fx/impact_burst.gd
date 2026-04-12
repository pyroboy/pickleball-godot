extends Node3D
class_name ImpactBurst
## Pooled one-shot particle burst. Created once by FXPool, reused via play().
## Uses CPUParticles3D (Compatibility renderer does not support GPU particles).

const BASE_COUNT: int = 8
const BASE_LIFETIME: float = 0.22
const BASE_SPEED_MIN: float = 0.7
const BASE_SPEED_MAX: float = 1.8
const PARTICLE_RADIUS: float = 0.018

var _particles: CPUParticles3D
var _mesh: SphereMesh
var _mat: StandardMaterial3D
var _timer: float = 0.0
var _active: bool = false

func _ready() -> void:
	name = "ImpactBurst"
	_particles = CPUParticles3D.new()
	_particles.name = "P"
	_particles.amount = BASE_COUNT
	_particles.one_shot = true
	_particles.emitting = false
	_particles.lifetime = BASE_LIFETIME
	_particles.explosiveness = 1.0
	_particles.direction = Vector3(0, 1, 0)
	_particles.spread = 180.0
	_particles.gravity = Vector3(0, -9.0, 0)
	_particles.initial_velocity_min = BASE_SPEED_MIN
	_particles.initial_velocity_max = BASE_SPEED_MAX
	_particles.scale_amount_min = 0.5
	_particles.scale_amount_max = 0.9
	_particles.angular_velocity_min = -180.0
	_particles.angular_velocity_max = 180.0
	_particles.damping_min = 2.0
	_particles.damping_max = 4.0

	# Explicit large AABB so nothing gets culled — the particles are emitted
	# in world space but the node's AABB still drives frustum culling.
	_particles.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))

	_mesh = SphereMesh.new()
	_mesh.radius = PARTICLE_RADIUS
	_mesh.height = PARTICLE_RADIUS * 2.0
	_mesh.radial_segments = 6   # Mobile: reduced from 8
	_mesh.rings = 2            # Mobile: reduced from 4

	# Unshaded + opaque (NOT additive). Additive + bright scene = invisible.
	# We use opaque so the particles read clearly against the court.
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(1, 1, 1, 1)
	_mat.vertex_color_use_as_albedo = true

	# PrimitiveMesh has a direct .material property — most reliable path for
	# particles in the Compatibility renderer.
	_mesh.material = _mat
	_particles.mesh = _mesh
	_particles.material_override = _mat
	add_child(_particles)

## Play the burst at `pos` with the given color and strength (0..1).
func play(pos: Vector3, color: Color, strength: float = 1.0, upward: bool = false) -> void:
	global_position = pos
	var s: float = clampf(strength, 0.0, 1.0)
	_particles.amount = int(BASE_COUNT * (0.6 + 0.8 * s))
	_particles.initial_velocity_min = BASE_SPEED_MIN * (0.6 + 0.6 * s)
	_particles.initial_velocity_max = BASE_SPEED_MAX * (0.6 + 0.8 * s)
	if upward:
		_particles.direction = Vector3(0, 1, 0)
		_particles.spread = 55.0
		_particles.initial_velocity_min = BASE_SPEED_MIN * 0.8
		_particles.initial_velocity_max = BASE_SPEED_MAX * 0.9
	else:
		_particles.direction = Vector3(0, 1, 0)
		_particles.spread = 180.0

	_mat.albedo_color = color

	_particles.restart()
	_particles.emitting = true
	_active = true
	_timer = _particles.lifetime + 0.15
	visible = true

func play_duration() -> float:
	return _particles.lifetime + 0.15

func _process(delta: float) -> void:
	if not _active:
		return
	_timer -= delta
	if _timer <= 0.0:
		_active = false
		_particles.emitting = false
		visible = false

func is_active() -> bool:
	return _active
