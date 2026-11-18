extends "res://scripts/tests/cloud_movement_guide_ui.gd"
## Reuse the original UI assertions, with a real NO_TIME flight whose legal
## contact lasts long enough to observe the intentional proof-entry interval.
func prepare(status := "MOVE", mirrored := false) -> Dictionary:
	if status != "NO_TIME": return super.prepare(status,mirrored)
	guide.player = Feeds.prepare(game,status,mirrored)
	guide.player.global_position.x = 3.0 if mirrored else -3.0
	guide.player.current_velocity = Vector3.ZERO
	guide.player.leg_ik.feet_initialized = false
	guide.player._process(0.0)
	game.ball.global_position.y = 1.1
	game.ball.linear_velocity = Vector3(0.0,-0.5,-0.3 if mirrored else 0.3)
	guide.advisor = Guide.Advisor.new()
	guide._reset_generation = game._point_reset_generation
	guide.cancel(); guide.tick(0.0,Feeds.flight(game))
	for frame in range(ceili(Guide.NO_TIME_ENTRY_SECONDS * rate)):
		guide.tick(1.0/rate,Feeds.flight(game))
	return guide.presentation_state()
