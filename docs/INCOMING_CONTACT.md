# Incoming ball, pose and held Space

Normal gameplay chooses a timed impact from the live flight prediction and the saved pose contact areas. The human predictor uses the same gravity, drag, Magnus force, spin decay, ball radius, floor bounce and physics step as the AI/live ball.

The selected paddle ghost marks that exact predicted impact. Its approach colour and the HIT ring use the same arrival time. The trajectory is lifted slightly for drawing; the contact calculation receives unmodified ball positions. Other diagnostic intercept pools no longer choose separate human targets.

Hold **Space** to blend into the selected stroke's wind-up. Moving to the other side of the ball's path, or a changed flight, can select another valid stroke while Space remains held. Each stroke keeps its saved paddle hand, support hand, body values and wind-up offsets. The swing is anchored at the selected impact; contact settings on disk are unchanged.

Release **Space** to queue the strike toward that arrival. The strike advances on physics time and applies a ball hit only when the live ball is within 0.10 m of the actual paddle head, on the legal side, within anatomical reach and after any required bounce. Release no longer hits a ball through the old large reach allowance. A changed flight cancels a queued strike. Finish/hold/recovery play after the strike, and only one return is allowed for that flight.

Move into reach before releasing. If no saved contact area intersects the reachable flight, the game clears the selected contact and asks you to move when you attempt the swing. It does not manufacture an impact on an unreachable ball. A volley in the kitchen or before the two-bounce requirement is rejected.

## Implementation

- `scripts/incoming_contact_planner.gd`: timed pose-plane intersections, saved contact areas, reach/legal checks and pose hysteresis.
- `scripts/human_contact_controller.gd`: selected target, charge, queued strike, actual contact, recovery and indicators.
- `scripts/player_debug_visual.gd`: the shared flight samples and trajectory drawing.
- `scripts/game.gd`: shot velocity/spin applied at actual contact.
- `scripts/input_handler.gd`: Space press/hold/release polling.
- `scripts/tests/test_human_incoming_contact.gd`: actual-scene regression sweep.
