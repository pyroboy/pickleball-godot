extends SceneTree
var checks: = 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func run():
	create_timer(10).timeout.connect( func(): push_error("Zone visibility timeout");quit(2))
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	for player in [game.player_left, game.player_right]:
		var pose = player.posture
		pose.editor_preview_mode = false;pose.posture_ghost_root.visible = false
		for zone in pose._posture_zone_bounds.values():
			pose._set_zone_visibility(zone, true)
			check( not zone.visible, "normal game hides zone for both players")
			for child in zone.get_children(): check( not child.visible, "normal game hides colored face planes")
		pose.posture_ghost_root.visible = true
		for zone in pose._posture_zone_bounds.values():
			pose._set_zone_visibility(zone, true)
			check(zone.visible, "explicit debug display permits zone")
		pose.posture_ghost_root.visible = false;pose.editor_preview_mode = true
		for zone in pose._posture_zone_bounds.values():
			pose._set_zone_visibility(zone, true)
			check(zone.visible, "editor preview can inspect zone independently")
		pose.editor_preview_mode = false
		for zone in pose._posture_zone_bounds.values():
			pose._set_zone_visibility(zone, true)
			check( not zone.visible, "closing editor returns to clean normal game")
	game.queue_free(); await process_frame
	print("DEBUG ZONE VISIBILITY: ", checks, " checks; failures=", failures)
	quit(0 if failures.is_empty() else 1)
