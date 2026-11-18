extends Node3D

const Logo = preload("res://assets/branding/arjostyle-pickleball.png")
const BrandShader = preload("res://shaders/court_brand.gdshader")
const SurfaceShader = preload("res://shaders/court_surface.gdshader")
const NetProfile = preload("res://scripts/net_profile.gd")
func setup(game: Node3D) -> void :
 name = "CourtBranding"
 preload("res://scripts/court_arena_visual.gd").new().setup(game)
 var surface = game.find_child("CourtSurface", true, false)
 if surface is MeshInstance3D:
  var material: = ShaderMaterial.new()
  material.shader = SurfaceShader
  surface.material_override = material
 for side in [-1.0, 1.0]:
  var mark: = MeshInstance3D.new()
  mark.name = "BaselineBrand" + str(int(side))
  var plane: = PlaneMesh.new()
  plane.size = Vector2(3.0, 1.0)
  mark.mesh = plane
  mark.position = Vector3(0, 0.079, side * 7.6)
  if side < 0: mark.rotation.y = PI
  mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  var mat: = ShaderMaterial.new()
  mat.shader = BrandShader
  mat.set_shader_parameter("logo_texture", Logo)
  mat.set_shader_parameter("ink", Color(0.72, 0.82, 0.84, 0.8))
  mark.material_override = mat
  add_child(mark)


 for x in [-2.0, 0.0, 2.0]:
  for side in [-1.0, 1.0]:
   var label: = Label3D.new()
   label.name = "NetBrand_%s_%s" % [x, side]
   label.text = "ARJOSTYLE"
   label.font_size = 32
   label.pixel_size = 0.00075
   label.outline_size = 0
   label.modulate = Color(0.1, 0.18, 0.21)
   label.position = Vector3(x, NetProfile.top_y_at(x) - 0.021, side * 0.007)
   if side > 0: label.rotation.y = PI
   label.no_depth_test = false
   label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
   add_child(label)
