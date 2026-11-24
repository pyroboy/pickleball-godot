extends Node3D
class_name BounceDecal
## Landing ring at a bounce (visual only; pooled by fx_pool.gd, played by hit_feedback.gd
## in the zone tint). A flat ring on the court (shaders/bounce_ring.gdshader) that opens
## from just round the ball's footprint, holds, then fades: crisp pixel line with a dark
## edge so it reads on any court colour. The old thin 3D torus went sub-pixel at a
## distance and flickered. Pauses with the game (its tween is bound to this node).

const DURATION: float = 0.8
const RADIUS: float = 0.35    # plane half size: the ring runs 0.11 -> 0.16 m (shader radii 0.31 -> 0.46)
const HEIGHT: float = 0.006   # above the court and the ball's blob shadow
const RingShader = preload("res://shaders/bounce_ring.gdshader")

var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _active: bool = false
var _tween: Tween

func _ready() -> void :
	name = "BounceDecal"
	# FXPool runs always; a landing ring must stop with the paused game.
	if process_mode == Node.PROCESS_MODE_INHERIT:
		process_mode = Node.PROCESS_MODE_PAUSABLE
	_mesh = MeshInstance3D.new()
	_mesh.name = "M"
	var plane: = PlaneMesh.new()
	plane.size = Vector2.ONE * RADIUS * 2.0
	_mesh.mesh = plane
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = RingShader
	_mesh.material_override = _material
	add_child(_mesh)
	visible = false

func play(pos: Vector3, color: Color) -> void :
	if _tween != null and _tween.is_valid():
		_tween.kill()
	global_position = Vector3(pos.x, maxf(pos.y, Ball.FLOOR_Y) + HEIGHT, pos.z)
	_material.set_shader_parameter("tint", Color(color.r, color.g, color.b, 0.9))
	_material.set_shader_parameter("progress", 0.0)
	visible = true
	_active = true

	_tween = create_tween()
	_tween.tween_property(_material, "shader_parameter/progress", 1.0, DURATION)
	_tween.tween_callback(Callable(self, "_on_fade_done"))

func _on_fade_done() -> void :
	_active = false
	visible = false

func play_duration() -> float:
	return DURATION + 0.1

func is_active() -> bool:
	return _active
