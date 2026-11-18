extends SceneTree
var checks: = 0
var failures: = 0
func check(ok: bool, label: String):
 checks += 1
 if not ok: failures += 1;push_error(label)
func _initialize(): call_deferred("_run")
func _run():
 var title = load("res://scenes/title.tscn").instantiate()
 root.add_child(title)
 current_scene = title
 await process_frame
 check(title._play.text == "PLAY SINGLES", "primary play action")
 check(title._logo.texture != null, "brand texture loaded")
 check(AudioServer.get_bus_index("SFX") >= 0, "SFX available before game startup")
 check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), float(root.get_node("Settings").get_value("audio.master"))), "saved master level applied at title")
 check( not title._progress.visible, "no fake progress before request")
 for sz in [Vector2i(360, 800), Vector2i(432, 936), Vector2i(720, 1280), Vector2i(1180, 780)]:
  root.size = sz
  await process_frame
  title._fit()
  check(title._panel.position.x >= 0 and title._panel.position.y >= 0, "panel nonnegative")
  check(title._panel.get_global_rect().end.x <= root.get_visible_rect().size.x + 1, "panel inside horizontal")
 title._toggle_controls()
 check(title._hint.text.begins_with("MOVE"), "controls expanded")
 title._toggle_controls()
 check( not title._hint.text.begins_with("MOVE"), "controls collapsible")
 title._open_settings()
 await process_frame
 var settings = title._overlay
 title._open_settings()
 check(title._overlay == settings, "one settings dialog")
 settings._on_close()
 await process_frame
 check( not is_instance_valid(title._overlay), "settings close restores title")
 title._fail("Test retry")
 check( not title._play.disabled, "load failure retry")
 title.start_match()
 title.start_match()
 check(title._loading and title._play.disabled, "start protected against repeat")
 var load_started: = Time.get_ticks_msec()
 while current_scene == title and Time.get_ticks_msec() - load_started < 15000:

  OS.delay_msec(1)
  await process_frame
 check(current_scene != title and current_scene != null, "async loaded actual match")
 if current_scene != null: check(current_scene.get("ball") != null, "match ready with real ball")
 if current_scene != null: current_scene.queue_free()
 await process_frame
 print("TITLE FLOW: %d checks, %d failures" % [checks, failures])
 quit(0 if failures == 0 else 1)
