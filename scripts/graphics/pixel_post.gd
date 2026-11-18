extends CanvasLayer
## Half-resolution 3D with a hard-pixel upscale, grade and vignette
## (VISUAL_PASS_PLAN step 2). Sits on layer -1: above the 3D world, below all UI.
## Visual only: nothing in gameplay reads the rendered image.

const SCALE := 0.5

func _ready() -> void:
	layer = -1
	var vp := get_viewport()
	vp.scaling_3d_scale = SCALE
	var rect := ColorRect.new()
	rect.name = "PixelPost"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/pixel_post.gdshader")
	mat.set_shader_parameter("block", 1.0 / SCALE)
	rect.material = mat
	add_child(rect)
