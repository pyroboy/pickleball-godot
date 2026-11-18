extends MeshInstance3D



const MINIMUM_PIXELS: = 8.0
const MAXIMUM_PIXELS: = 12.0
const FADE_START_PIXELS: = 5.0
const FADE_END_PIXELS: = 10.0
const CueShader = preload("res://shaders/ball_readability.gdshader")
var ball_radius: = 0.0375

func _ready() -> void :
	name = "BallReadability"
	var quad: = QuadMesh.new()
	quad.size = Vector2.ONE
	mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material: = ShaderMaterial.new()
	material.shader = CueShader
	material.set_shader_parameter("ball_radius", ball_radius)
	material.set_shader_parameter("minimum_pixels", MINIMUM_PIXELS)
	material.set_shader_parameter("maximum_pixels", MAXIMUM_PIXELS)
	material.set_shader_parameter("fade_start_pixels", FADE_START_PIXELS)
	material.set_shader_parameter("fade_end_pixels", FADE_END_PIXELS)
	material_override = material
