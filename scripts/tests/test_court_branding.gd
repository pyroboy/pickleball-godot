extends SceneTree
var checks: = 0
var failures: = 0
func check(ok: bool, label: String):
 checks += 1
 if not ok: failures += 1;push_error(label)
func _initialize(): call_deferred("_run")
func _run():
 var game = load("res://scenes/game.tscn").instantiate()
 root.add_child(game)
 await process_frame
 var brand = game.get_node_or_null("CourtBranding")
 check(brand != null, "branding setup")
 check(brand.get_child_count() == 8, "two baseline marks six subtle tape wordmarks")
 for child in brand.get_children():
  check( not child is CollisionObject3D, "branding has no collision")
  if child is MeshInstance3D:
   check(absf(child.position.z) > 6.7, "mark outside gameplay baseline")
   check(child.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no logo shadow")
  if child is Label3D:
   check(child.text == "ARJOSTYLE", "wordmark accurate")
 var surface = game.find_child("CourtSurface", true, false)
 check(surface.material_override is ShaderMaterial, "court finish applied")
 check(is_equal_approx(surface.global_position.y, 0.072), "physical court position unchanged")
 game.queue_free()
 await process_frame
 print("COURT BRANDING: %d checks, %d failures" % [checks, failures])
 quit(0 if failures == 0 else 1)
