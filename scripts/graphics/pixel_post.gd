extends CanvasLayer
## Pixel viewport (ROADMAP Phase 2): the 3D world renders at 1/3 resolution and is
## upscaled with hard pixels (shaders/pixel_post.gdshader), plus a grade and vignette.
## Sits on layer -1: above the 3D world, below all UI, so UI stays full resolution.
##
## This is the root viewport's own 3D scaling, not a separate SubViewport: the game
## camera, its aspect and every unproject / frustum test keep reading the full-size
## viewport, so framing and gameplay are untouched. Visual only: nothing in gameplay
## reads the rendered image.
## PICKLEBALL_PIXEL_SCALE=0.5 (or any 0.1-1.0) overrides the scale for A/B checks.

const SCALE := 1.0 / 3.0

## The scale in use (shaders that size things in render pixels read this).
static var scale_in_use: float = SCALE

func _ready() -> void:
	layer = -1
	var env := OS.get_environment("PICKLEBALL_PIXEL_SCALE")
	scale_in_use = clampf(float(env), 0.1, 1.0) if env.is_valid_float() else SCALE
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale_in_use
	var rect := ColorRect.new()
	rect.name = "PixelPost"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/pixel_post.gdshader")
	mat.set_shader_parameter("scale", scale_in_use)
	rect.material = mat
	add_child(rect)
