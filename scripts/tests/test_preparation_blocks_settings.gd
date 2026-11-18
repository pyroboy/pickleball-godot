extends SceneTree

const AudioTeardown = preload("res://scripts/tests/audio_teardown.gd")
const Policy = preload("res://scripts/runtime_policy.gd")
const Regions = preload("res://scripts/preparation_superblocks.gd")
var checks: = 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message)
func run():
	create_timer(30).timeout.connect( func(): quit(2))
	var settings = root.get_node("Settings")
	check(Policy.mobile_runtime and not Policy.developer_tools, "run using --mobile-runtime")
	check(settings.DEFAULTS.get("beta_debug.preparation_blocks", true) == false, "map setting must default off")
	var before = settings.get_value("beta_debug.preparation_blocks", false)
	settings.set_value("beta_debug.preparation_blocks", false)
	settings.set_value("beta_debug.reach_rings", false)
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	game.set_physics_process(false);game.input_handler.set_process(false)
	game.player_left.set_physics_process(false);game.player_right.set_physics_process(false)
	var player = game.player_left
	var guides = player.get_node("ReachRings")
	check(guides.preparation_visual == null and player.get_node_or_null("PreparationBlocks") == null, "off means no geometry node exists")
	var panel = load("res://scripts/ui/settings_panel.gd").new();root.add_child(panel); await process_frame
	var toggle = panel.find_child("beta_debug_preparation_blocks", true, false)
	check(toggle is CheckButton and not toggle.button_pressed, "mobile Beta debug exposes independent checkbox")
	toggle.button_pressed = true; await process_frame
	check(settings.get_value("beta_debug.preparation_blocks", false), "checkbox updates saved preference")
	var visual = guides.preparation_visual
	check(visual != null and visual.visible and visual.is_processing(), "enabled checkbox constructs and runs map")
	check(visual.blocks.size() == 8 and visual.authored.size() == 18, "bounded geometry includes exactly expected displays")
	check(guides._mesh == null and not guides._enabled, "map does not enable or allocate reach rings")
	check(game.game_debug_ui == null and player.awareness_grid == null and player.posture.posture_ghost_root == null, "mobile map never enables desktop tools or awareness grid")
	var count: int = visual.get_child_count()
	for repeat in range(3):
		toggle.button_pressed = false; await process_frame
		check( not visual.visible and not visual.is_processing(), "disabled map does no hidden updates")
		toggle.button_pressed = true; await process_frame
		check(guides.preparation_visual == visual and visual.get_child_count() == count, "repeat toggle reuses bounded resources")
	player.global_position = Vector3(0.8, player.ground_y, 4.0);player.rotation.y = 1.2;visual.sync()
	for item in visual.blocks.values():
		var b: Dictionary = item.bounds
		var expected: Vector3 = Regions.world_point(player, (b.x_min + b.x_max) * 0.5, (b.y_min + b.y_max) * 0.5, b.forward)
		check(item.node.global_position.distance_to(expected) < 1e-05, "debug volume follows real translated root")
		check(item.node.global_basis.x.distance_to(player._get_forehand_axis()) < 1e-05, "debug volume ignores body/root yaw")
	toggle.button_pressed = false; await process_frame
	check( not visual.visible, "final toggle disables map")
	settings.set_value("beta_debug.preparation_blocks", before)
	panel.queue_free();game.queue_free(); await process_frame; await process_frame
	await AudioTeardown.drain(self)
	for failure in failures: push_error(failure)
	print("PREPARATION BLOCKS BETA SETTINGS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
