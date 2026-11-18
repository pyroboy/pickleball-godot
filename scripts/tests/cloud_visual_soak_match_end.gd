extends "res://scripts/tests/cloud_visual_soak.gd"
## Coverage supplement: lose normally, use the real Skip retrieval button, and
## wait for actual scoring to finish a match. No score/ball/pose writes.
var skipped_generation := -1
var end_seen_usec := 0
var rematch_seen_usec := 0
func build_schedule() -> void:
	schedule = []
func driver(now: int) -> void:
	if now < next_control or not is_instance_valid(game): return
	next_control = now + 50000
	if rematch_seen_usec > 0:
		if now - rematch_seen_usec > 500000:
			check(not game.match_over and game.game_state == 0 and game.score_left == 0 and game.score_right == 0, "natural rematch did not reset cleanly")
			duration = elapsed()
		return
	if game.match_over:
		if end_seen_usec == 0:
			end_seen_usec = now
			event("natural_match_end", {"score": [game.score_left, game.score_right], "winner": game.match_winner})
		if now - end_seen_usec > 1000000:
			check(game.practice_panel.visible, "natural match end did not show result panel")
			game.practice_panel._rematch()
			count("natural_rematch")
			rematch_seen_usec = now
		return
	if game.hud._between_point_active:
		release_driver()
		if skipped_generation != game._point_reset_generation and game.hud._skip_button.is_visible_in_tree():
			skipped_generation = game._point_reset_generation
			var point: Vector2 = game.hud._skip_button.get_global_rect().get_center()
			touch(43, point, true); touch(43, point, false)
			count("natural_retrieval_skips")
		return
	if game.mobile_controls._blocked(): return
	if driver_hit and game.mobile_controls._charge_id != 41: set_hit(false); return
	if game.game_state == 0 and game.serving_team == 0:
		var held_seconds := float(now - last_hit_change) / 1000000.0
		if not driver_hit and held_seconds > 0.2: set_hit(true)
		elif driver_hit and held_seconds >= 0.55: set_hit(false)
	else:
		set_hit(false)
		set_movement(Vector2.ZERO)
