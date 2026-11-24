extends Node3D

const Logo = preload("res://assets/branding/pixel-pickleball.png")
const BrandShader = preload("res://shaders/court_brand.gdshader")
const SurfaceShader = preload("res://shaders/court_surface.gdshader")
const NetProfile = preload("res://scripts/net_profile.gd")
## The baseline logos sit under the bottom HUD (name tags, move stick): while a point is
## set up or played they fade to a faint watermark; between points, in menus and with the
## HUD hidden (photo mode, tools) they show in full. Pausable; no work once settled.
const PLAY_FADE := 0.25
const FADE_PER_SECOND := 2.5
var _game: Node
var _materials: Array[ShaderMaterial] = []
var _fade := 1.0

func _process(delta: float) -> void:
 var target: float = PLAY_FADE if _point_on() else 1.0
 if _fade == target: return
 _fade = move_toward(_fade, target, FADE_PER_SECOND * delta)
 for material in _materials: material.set_shader_parameter("fade", _fade)

func _point_on() -> bool:
 var hud = _game.get("hud")
 if hud == null or not hud._gameplay_visible or hud._between_point_active: return false
 if _game.get("match_over") == true or _game._tool_state_active(): return false
 return int(_game.game_state) != 3   # GameState.POINT_SCORED

func setup(game: Node3D) -> void :
 name = "CourtBranding"
 _game = game
 process_mode = Node.PROCESS_MODE_PAUSABLE
 # Menu courts (menu_ball_scene) have no match state: the logo stays full there.
 set_process("game_state" in game and game.has_method("_tool_state_active"))
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
  _materials.append(mat)
  add_child(mark)


 # Net tape "ARJOSTYLE" labels dropped: 0.75 mm text, unreadable at any size.
 for x in []:
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
