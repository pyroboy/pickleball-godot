# Base Pose Taxonomy

## Canonical Base Pose States

Implemented state ids in `PlayerController.BasePoseState` and `BasePoseLibrary`:

1. `ATHLETIC_READY`
2. `SPLIT_STEP`
3. `RECOVERY_READY`
4. `KITCHEN_NEUTRAL`
5. `DINK_BASE`
6. `DROP_RESET_BASE`
7. `PUNCH_VOLLEY_READY`
8. `DINK_VOLLEY_READY`
9. `DEEP_VOLLEY_READY`
10. `GROUNDSTROKE_BASE`
11. `LOB_DEFENSE_BASE`
12. `FOREHAND_LUNGE`
13. `BACKHAND_LUNGE`
14. `LOW_SCOOP_LUNGE`
15. `OVERHEAD_PREP`
16. `JUMP_TAKEOFF`
17. `AIR_SMASH`
18. `LANDING_RECOVERY`
19. `LATERAL_SHUFFLE`
20. `CROSSOVER_RUN`
21. `BACKPEDAL`
22. `DECEL_PLANT`

## Canonical Pose Intents

Implemented intent ids in `PlayerController.PoseIntent` and resolved by `PoseController`:

- `NEUTRAL`
- `DINK`
- `DROP_RESET`
- `PUNCH_VOLLEY`
- `DINK_VOLLEY`
- `DEEP_VOLLEY`
- `GROUNDSTROKE`
- `LOB_DEFENSE`
- `OVERHEAD_SMASH`

## Runtime Mapping Matrix

### Pre-bounce

- high contact: `OVERHEAD_SMASH -> OVERHEAD_PREP`
- medium overhead contact: `OVERHEAD_SMASH -> OVERHEAD_PREP`
- low kitchen volley: `DINK_VOLLEY -> DINK_VOLLEY_READY`
- kitchen volley: `PUNCH_VOLLEY -> PUNCH_VOLLEY_READY`
- deeper air contact: `DEEP_VOLLEY -> DEEP_VOLLEY_READY`

### Post-bounce

- low kitchen contact: `DINK -> DINK_BASE`
- low non-kitchen contact: `DROP_RESET -> DROP_RESET_BASE`
- very high post-bounce contact: `LOB_DEFENSE -> LOB_DEFENSE_BASE`
- baseline or stronger medium contact: `GROUNDSTROKE -> GROUNDSTROKE_BASE`
- mid-court return without a hard drive cue: `DROP_RESET -> DROP_RESET_BASE`

### Footwork / locomotion overlays

- wide reach: `FOREHAND_LUNGE`, `BACKHAND_LUNGE`, or `LOW_SCOOP_LUNGE`
- incoming committed ball: `SPLIT_STEP`
- in-air overhead: `JUMP_TAKEOFF` then `AIR_SMASH`
- post-landing: `LANDING_RECOVERY`
- fast lateral movement: `LATERAL_SHUFFLE`
- fast run-through: `CROSSOVER_RUN`
- retreat: `BACKPEDAL`
- hard speed drop: `DECEL_PLANT`

## Naming Rules

- base poses are named by pickleball intent or movement phase, not by paddle side alone
- stroke/contact posture names remain paddle/contact oriented
- mirrored gameplay uses the same base pose id; side differences come from stroke posture, movement direction, and runtime mirroring
