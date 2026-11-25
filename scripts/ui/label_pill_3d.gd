extends RefCounted
## Dark navy pill behind an in-world Label3D (shot name pops, OUT, aim / smash labels),
## the 3D twin of the HUD's label pills (pixel_style_box.gd label_pill): readable over
## the crowd, the cement and the shop signs. Presentation only. The pill is a child
## quad of the label, so it follows the label's position, scale and visibility; call
## fit() when the text changes (never per frame) and set_alpha() while it fades.
const SHADER = preload("res://shaders/label_pill.gdshader")
const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
const PAD := Vector2(10.0, 6.0)   # label font pixels around the text (x each side, y each side)
const META := &"label_pill"

static func attach(label: Label3D, fill_alpha: float = 0.86) -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	quad.name = "Pill"
	quad.mesh = QuadMesh.new()
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("fill", Color(UiTheme.PANEL, fill_alpha))
	# Drawn before the label's outline and text (Label3D: text at render_priority,
	# outline one below).
	material.render_priority = clampi(label.render_priority - 2, RenderingServer.MATERIAL_RENDER_PRIORITY_MIN, RenderingServer.MATERIAL_RENDER_PRIORITY_MAX)
	quad.material_override = material
	label.add_child(quad)
	label.set_meta(META, quad)
	fit(label)
	return quad

## Size the pill to the label's current text (font metrics x pixel size).
static func fit(label: Label3D) -> void:
	var quad: MeshInstance3D = label.get_meta(META, null)
	if quad == null: return
	quad.visible = not label.text.is_empty()
	if label.text.is_empty(): return
	var font: Font = label.font if label.font != null else ThemeDB.fallback_font
	var text: Vector2 = Vector2(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x, font.get_height(label.font_size))
	var outline: float = float(label.outline_size)
	var px: Vector2 = text + Vector2(outline, outline) + PAD * 2.0 * (float(label.font_size) / 36.0)
	(quad.mesh as QuadMesh).size = px * label.pixel_size
	# One UI pixel = one pixel-font pixel (font size / PIXEL_UNIT): the corner steps
	# match the letters' pixels.
	var cell: float = maxf(1.0, float(label.font_size) / UiTheme.PIXEL_UNIT)
	(quad.material_override as ShaderMaterial).set_shader_parameter("cells", (px / cell).round().max(Vector2(4, 3)))
	# Follow the label's own text offset (Label3D centres on the line box).
	quad.position = Vector3(label.offset.x, label.offset.y, 0.0) * label.pixel_size

static func set_alpha(label: Label3D, alpha: float) -> void:
	var quad: MeshInstance3D = label.get_meta(META, null)
	if quad != null: (quad.material_override as ShaderMaterial).set_shader_parameter("alpha", clampf(alpha, 0.0, 1.0))
