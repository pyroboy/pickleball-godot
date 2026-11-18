extends SceneTree

const Fixture = preload("res://scripts/tests/fixtures/distant_preparation_fixture.gd")
const AudioTeardown = preload("res://scripts/tests/audio_teardown.gd")
var game
var checks: = 0
var failures: Array[String] = []
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func run() -> void :
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	for side in [-1.0, 1.0]:
		Fixture.prepare(game, {"lateral": 5.0 * side}, false)
		for i in range(3): await physics_frame
		var p = game.player_left; var h = p.posture.human_contact
		var prep: Dictionary = h.preparation_contact()
		check( not prep.is_empty(), "fixture has no preparation")
		await process_frame
		var family: = "Backhand" if side < 0 else "Forehand"
		check(game.hud.state.text.to_lower().contains(family.to_lower()), "passive distant cue omits " + family)
		Fixture.press(game)
		check(h.charge_ratio < 0.1, "fixture is not initial low-power press")
		check(h._charge_target_pose.paddle_forward_mul < - 0.12, "initial distant " + family + " does not choose loaded backswing")
		for frame in range(15): Fixture.tick(game); await physics_frame
		check(h.visual_pose.paddle_forward_mul < 0.15, "visible " + family + " has not entered takeback after 250ms")
		check(game.hud.state.text.to_lower().contains(family.to_lower()), "held distant cue omits " + family)
		Input.action_press("move_left" if side < 0 else "move_right")
		for frame in range(15): Fixture.tick(game); await physics_frame
		check(h.visual_pose.paddle_forward_mul < - 0.1, "manual travel lost loaded " + family)
		Fixture.release(game)
		check(h.phase == 0, "early release did not queue")
		for frame in range(4): await physics_frame
		check(h.visual_pose.paddle_forward_mul < - 0.1, "queued manual travel lost loaded " + family)
		check(game.hud.state.text.to_lower().contains(family.to_lower()), "queued cue lost family")
		h.cancel();Input.action_release("move_left");Input.action_release("move_right")
		game.ball.is_in_play = false
		for frame in range(3): await physics_frame; await process_frame
		check( not game.hud.state.text.to_lower().contains(family.to_lower()), "dead flight leaves stale preparation cue")
		check( not p.hitting.charge_visual_active, "cancel leaves held charge")
	for scenario in [
		{"lateral": 5.0, "height": 0.4, "family": 0, "label": "Low forehand"}, 
		{"lateral": -5.0, "height": 0.4, "family": 1, "label": "Low backhand"}, 
		{"lateral": 5.0, "height": 2.02, "forward": 0.45, "duration": 1.4, "family": 3, "label": "Overhead"}]:
		Fixture.prepare(game, scenario)
		for frame in range(3): await physics_frame
		await process_frame
		var h = game.player_left.posture.human_contact
		check(h.preparation_label() == scenario.label, "selected low/high preparation label wrong")
		check(game.hud.state.text.contains(scenario.label), "passive low/high cue absent")
		Fixture.press(game)
		for frame in range(8): Fixture.tick(game); await physics_frame
		check(h.visual_pose.family == scenario.family, "low/high held pose differs from cue")
		check(game.hud.state.text.contains(scenario.label), "held low/high cue absent")
		h.cancel();Fixture.release(game)
	Fixture.prepare(game, {"lateral": 4.0, "duration": 1.6})
	for frame in range(3): await physics_frame
	Fixture.press(game);Input.action_press("move_right")
	for frame in range(57): Fixture.tick(game); await physics_frame
	Input.action_release("move_right")
	for frame in range(8): Fixture.tick(game); await physics_frame
	check(game.player_left.posture.human_contact.preparation_label() == "Backhand", "cross-body prediction label did not switch")
	check(game.hud.state.text.contains("Backhand"), "cross-body visible cue did not switch")
	game.input_handler.cancel_charge_input();Input.action_release("ui_accept")
	game.queue_free(); await process_frame; await process_frame
	await AudioTeardown.drain(self)
	for failure in failures: push_error(failure)
	print("VISIBLE DISTANT CHARGE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
