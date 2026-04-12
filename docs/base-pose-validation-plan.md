# Base Pose Validation Plan

## Automated Checks

Current automated coverage:

- `scripts/tests/test_base_pose_system.gd`
  - base pose library exposes the authored taxonomy
  - base pose blending preserves paddle/contact fields from the stroke posture
  - base pose preview posture fully overrides authored body support fields when requested

## Manual Acceptance Matrix

### Library loading

- base poses load from `res://data/base_poses/*.tres`
- missing files still fall back cleanly to built-in defaults
- editor lists both stroke postures and base poses in the correct workspace

### Runtime selection

- no-ball neutral settles into `ATHLETIC_READY` / `KITCHEN_NEUTRAL`
- committed incoming volley moment triggers `SPLIT_STEP`
- kitchen low bounce resolves to `DINK_BASE`
- deeper low bounce resolves to `DROP_RESET_BASE`
- baseline medium contact resolves to `GROUNDSTROKE_BASE`
- high air contact resolves to `OVERHEAD_PREP`
- jump/landing transitions resolve to `JUMP_TAKEOFF`, `AIR_SMASH`, `LANDING_RECOVERY`

### Composition correctness

- paddle target stays tied to the selected stroke posture
- body stance, crouch, support-arm pose, and foot placement respond to the base pose
- existing charge/follow-through authored data still works
- current paddle ghost facing rules remain unchanged

### Editor checks

- switching workspaces updates the list and visible tabs
- base poses save to disk
- stroke posture preview respects the selected preview-state base pose
- base pose preview respects the selected representative stroke context

## Current Verification Limitation

Headless execution could not be run in this environment because neither `godot` nor `godot4` is installed on the machine shell path. Manual in-editor verification is still recommended after pulling the changes.
