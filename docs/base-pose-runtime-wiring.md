# Base Pose Runtime Wiring

## Files And Responsibilities

- `scripts/base_pose_definition.gd`
  - body-only authored pose resource

- `scripts/base_pose_library.gd`
  - loads `res://data/base_poses/*.tres`
  - falls back to built-in defaults when assets are missing

- `scripts/pose_controller.gd`
  - resolves `PoseIntent`
  - resolves `BasePoseState`
  - composes runtime posture data

- `scripts/player.gd`
  - exposes `BasePoseState` and `PoseIntent`
  - owns the `PoseController` child
  - updates pose state during `_physics_process`

- `scripts/player_body_animation.gd`
  - now reads the composed runtime posture for crouch, body pitch/roll, and tracking weight

- `scripts/player_arm_ik.gd`
  - now reads the composed runtime posture for support-arm and pole targets

- `scripts/player_leg_ik.gd`
  - now reads the composed runtime posture for stance width, foot offsets, weight shift, and knee poles

- `scripts/player_paddle_posture.gd`
  - still owns paddle targeting
  - now applies the composed runtime posture to the skeleton instead of the raw stroke posture alone

- `scripts/player_debug_visual.gd`
  - now uses `PoseController` intent classification so debug labels and runtime intent taxonomy match

## Signals / Inputs Used

The current state resolver uses:

- committed posture stage from `player_paddle_posture.gd`
- live ball bounce state from `Ball.ball_bounced_since_last_hit`
- predicted contact points from AI debug/trajectory systems when available
- contact height
- player court depth relative to the kitchen and baseline
- movement speed and direction
- jump state
- landing recovery timer
- lunge recovery timer
- decel timer

## Runtime Flow

1. `player.gd` updates movement and paddle tracking.
2. `PoseController.update_runtime_pose_state()` resolves the base pose state.
3. `PoseController.compose_runtime_posture()` blends the base pose onto the active stroke posture.
4. body/arm/leg/skeleton consumers pull that composed posture.
5. procedural movement and hit systems continue to add runtime adjustments last.

## Current Heuristics

- split-step triggers off committed incoming stages
- lunge is detected from large lateral reach
- landing recovery is timed off the jump flag dropping back to grounded
- volley/dink/drop/groundstroke/smash intent is height and court-depth driven
- debug labels and runtime intent share the same classifier

## Known Next Upgrades

- use richer predicted post-bounce contact selection for human players before the ball actually bounces
- add explicit AI jump state/timing
- formalize per-field stroke-body override metadata when needed
