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

## Settings > Video > Resolution (`video.resolution`): which share of the screen's resolution
## the 3D world is drawn at. 0 = this build's default (SCALE); the others are fixed shares.
## Lower is more pixelated and cheaper for the graphics chip; higher is sharper and costs
## more (the pixel count grows with the square of the share). UI is always full resolution.
const RESOLUTION_KEY := "video.resolution"
const RESOLUTION_SCALES := [0.0, 1.0 / 3.0, 1.0 / 2.0, 2.0 / 3.0, 1.0]
const RESOLUTION_NAMES := ["Default", "Low: 1/3 (most pixelated, fastest)", "Medium: 1/2", "High: 2/3 (slower)", "Full (sharpest, slowest)"]

## The scale in use (shaders that size things in render pixels read this).
static var scale_in_use: float = SCALE
var _material: ShaderMaterial
var _env_scale: float = -1.0   # PICKLEBALL_PIXEL_SCALE, which wins over the setting

func _chosen_scale() -> float:
	if _env_scale > 0.0: return _env_scale
	var settings: Node = get_node_or_null("/root/Settings")
	var choice: int = int(settings.call("get_value", RESOLUTION_KEY, 0)) if settings != null and settings.has_method("get_value") else 0
	var share: float = float(RESOLUTION_SCALES[clampi(choice, 0, RESOLUTION_SCALES.size() - 1)])
	return share if share > 0.0 else SCALE

func _apply_scale() -> void:
	scale_in_use = _chosen_scale()
	get_viewport().scaling_3d_scale = scale_in_use
	if _material != null: _material.set_shader_parameter("scale", scale_in_use)

## Settings > Video: the picture's finishing touches, each its own switch.
const VIGNETTE_KEY := "video.vignette"       # darker, cooler corners
const GRADE_KEY := "video.color_grade"       # contrast, saturation, warm light, split tones
const GRADE_NEUTRAL := {"contrast": 1.0, "saturation": 1.0, "warm": Vector3.ONE, "split": Vector2.ZERO}
var _look: Dictionary = {}   # the look's own values, kept while a switch is off

func _setting(key: String, fallback: Variant) -> Variant:
	var settings: Node = get_node_or_null("/root/Settings")
	return settings.call("get_value", key, fallback) if settings != null and settings.has_method("get_value") else fallback

func _apply_look() -> void:
	if _material == null: return
	var wanted: Dictionary = {}
	if not bool(_setting(GRADE_KEY, true)): wanted.merge(GRADE_NEUTRAL)
	if not bool(_setting(VIGNETTE_KEY, true)): wanted["vignette"] = 0.0
	for param in ["contrast", "saturation", "warm", "split", "vignette"]:
		if wanted.has(param):
			if not _look.has(param): _look[param] = _material.get_shader_parameter(param)   # null = the shader's own default
			_material.set_shader_parameter(param, wanted[param])
		elif _look.has(param):
			_material.set_shader_parameter(param, _look[param])
			_look.erase(param)

func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == RESOLUTION_KEY: _apply_scale()
	elif key == VIGNETTE_KEY or key == GRADE_KEY: _apply_look()

func _ready() -> void:
	layer = -1
	var env := OS.get_environment("PICKLEBALL_PIXEL_SCALE")
	if env.is_valid_float(): _env_scale = clampf(float(env), 0.1, 1.0)
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_apply_scale()
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null and settings.has_signal("settings_changed") and not settings.settings_changed.is_connected(_on_setting_changed):
		settings.settings_changed.connect(_on_setting_changed)
	var rect := ColorRect.new()
	rect.name = "PixelPost"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/pixel_post.gdshader")
	mat.set_shader_parameter("scale", scale_in_use)
	rect.material = mat
	_material = mat
	_apply_look()
	add_child(rect)
