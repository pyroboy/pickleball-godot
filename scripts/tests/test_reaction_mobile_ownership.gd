extends SceneTree
var game
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func run() -> void:
	root.get_node("PauseController").set_process_input(false)
	root.content_scale_size=Vector2i(720,1560);root.size=Vector2i(720,1560)
	game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game
	await process_frame;await physics_frame
	game.set_physics_process(false);game.input_handler.set_process(false)
	var reaction=game.reaction_button
	var mobile=game.mobile_controls
	for size in [Vector2i(720,1560),Vector2i(600,960),Vector2i(360,640)]:
		root.content_scale_size=size;root.size=size;await process_frame;mobile._layout()
		check(mobile.enabled,"portrait timing belongs to touch deck")
		for state in [game.GameState.WAITING,game.GameState.SERVING,game.GameState.PLAYING]:
			game.game_state=state
			mobile._process(0)
			# Reproduce the exact late physics callback which formerly reopened it.
			reaction.enter_idle()
			check(not reaction.visible,"late idle callback overlapped mobile shot control")
			reaction.update_from_stage(2,"FOREHAND",0.0,0.0,0.1)
			check(not reaction.visible,"stage callback exposed keyboard guide on mobile")
			check(reaction.is_perfect(),"suppression changed timing computation")
			reaction.show_grade("PERFECT")
			check(reaction._grade_label=="PERFECT" and reaction._grade_flash_t>0,"mobile grade handoff lost")
			reaction.update_from_stage(-1,"",0.0,0.0,0.0)
			check(not reaction.visible and not reaction.is_perfect(),"idle transition lost hide/timing reset")
		game._deactivate_reaction_button()
		check(not reaction.visible,"release/deactivate reopened keyboard guide")
	root.content_scale_size=Vector2i(1280,720);root.size=Vector2i(1280,720);await process_frame;mobile._layout()
	reaction.enter_idle();check(reaction.visible and reaction._presentation_allowed(),"desktop idle keyboard guide not restored")
	reaction.update_from_stage(2,"FOREHAND",0.0,0.0,0.1)
	check(reaction.visible and reaction.is_perfect(),"desktop active guide changed")
	reaction.hide_button();check(not reaction.visible,"explicit desktop hide ignored")
	print("REACTION MOBILE OWNERSHIP: %d checks, %d failures" % [checks,failures.size()])
	for failure in failures: push_error(failure)
	current_scene=null;game.queue_free();await process_frame;await process_frame
	var drain_until: int = Time.get_ticks_usec() + 150000
	while Time.get_ticks_usec() < drain_until:
		OS.delay_msec(5);await process_frame
	quit(0 if failures.is_empty() else 1)
