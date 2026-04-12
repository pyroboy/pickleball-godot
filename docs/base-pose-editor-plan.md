# Base Pose Editor Plan

## Implemented Editor Direction

The in-game posture editor now stays as one tool with two workspaces:

- `Stroke Postures`
- `Base Poses`

## Current Workflow

- switch workspace with the workspace toggle in the header
- edit stroke postures with paddle, body, charge, and follow-through tabs
- edit base poses with body tabs only: legs, arms, head, torso
- save base poses to `res://data/base_poses/*.tres`
- save stroke postures to `res://data/postures/*.tres`

## Preview State Support

The editor now includes a `Preview State` selector:

- `Live`
- `Neutral`
- `Incoming`
- `Volley`
- `Post-Bounce`
- `Lunge`
- `Jump`
- `Landing`

How it is used:

- in stroke-posture mode, the selected state blends a representative base pose under the current stroke preview
- in base-pose mode, the selected state chooses a representative stroke posture for previewing the selected base pose

## Gizmo Behavior

- stroke-posture mode keeps paddle, arm, leg, torso, and head gizmos
- base-pose mode hides paddle/charge/follow-through editing and uses body gizmos only

## Next Editor Upgrades

- blend graph / timeline view for `base -> charge -> contact -> follow-through -> recover`
- mirror tools
- per-limb pose locks
- explicit jump/landing scrub preview
- saved preview presets for common pickleball contexts
