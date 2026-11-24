# Diagonal footwork plan

Asked 2026-11-24: are the flow split step, gravity step, crossover, V-cut and prep steps in
the game? Mostly not. This is what was there, what was built, and what is left.

## What the code had

- `split_step_timing.gd`: one neutral split per opponent strike: load, a 2.5 cm unweight, land
  on the same spots, then `push_off` once the ball's direction is read, then recover. Both feet
  together; under one card pixel (2.8 cm), so it does not show.
- `footwork_motion_state.gd`: travel is forward, sideways, backward or backward-sideways,
  always facing the net. No forward-diagonal state, no hip turn.
- `charged_footwork.gd`: approach to the hitting spot is shuffle, crossover (over 0.85 m, not at
  the kitchen), then slow `adjust` steps inside 0.3 m, plant, load.
- A drop step exists only for a lob behind the player.

## Limits that shape the build

- **The cards cannot show a foot turning.** The shoe card is drawn along the shin, so "the
  inside foot pivots open" has to be shown as where the foot lands, not which way it points.
- **Direction is not known mid-air.** The hop lands 25 ms after the opponent's strike and the
  AI reads direction after its reaction delay, so "land outside foot first" is shown at
  `push_off` (the moment the direction is read): the inside foot is the one that moves.
- **Ball in play: hands and paddle stay where gameplay has them.** Body moves are drawn on
  hips, torso, head, shoulders and legs only.

## Built

| # | Move | Where | Kind |
|---|---|---|---|
| 1 | Flow split step: a hop that shows, landing wider | `card_motion_layer.gd` `_footwork_flow` | drawn only |
| 2 | Gravity step: on the read, the inside foot lifts and lands toward the ball while the body drops and leans into the move | same | drawn only |
| 3 | Diagonal travel and V-cut: hips and chest turn toward a forward-diagonal run | same | drawn only |
| 4 | Prep steps: quick small stutter steps inside 0.3 m of the hitting spot | `player_leg_ik.gd` (`STUTTER_*`) | gameplay feet |
| - | Side shuffle: feet wide, never crossing, body lower | `player_leg_ik.gd` (`SHUFFLE_*`), `_shuffle_low` | gameplay feet + drawn |

Dials are constants at the top of each file. Check with `tools/motion_bench.sh` (columns
`hop`, `drop`, `turn`) and, for the split, a match frame log (`flow` in the drawn joints).

## Not built

- A real diagonal crossover in the gameplay legs (outside leg driving across with the hips
  turned). The legs still run facing the net; only the drawn hips and chest turn.
- A semi-open or neutral hitting stance chosen on arrival. Drives already pick open or closed
  (`drive_preparation_state.gd`); other strokes use the authored pose.
- Uneven landing in the air (see the second limit).
