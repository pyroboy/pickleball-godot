extends MeshInstance3D



## Cue sizes in output (screen) pixels. The shader works in 3D render pixels, which are
## coarser by the pixel viewport scale (pixel_post.gd), so they are converted in _ready and
## the ring keeps at least MIN_RENDER_PIXELS of the pixel grid so it still reads as a ring.
const MINIMUM_PIXELS: = 16.0
const MAXIMUM_PIXELS: = 24.0
const FADE_START_PIXELS: = 10.0
const FADE_END_PIXELS: = 20.0
const MIN_RENDER_PIXELS: = 6.0
const PixelPost = preload("res://scripts/graphics/pixel_post.gd")
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
	var k: float = PixelPost.scale_in_use
	var smallest: float = maxf(MINIMUM_PIXELS * k, MIN_RENDER_PIXELS)
	material.set_shader_parameter("minimum_pixels", smallest)
	material.set_shader_parameter("maximum_pixels", smallest * MAXIMUM_PIXELS / MINIMUM_PIXELS)
	material.set_shader_parameter("fade_start_pixels", FADE_START_PIXELS * k)
	material.set_shader_parameter("fade_end_pixels", FADE_END_PIXELS * k)
	material_override = material
