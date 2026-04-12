# Base Pose System Master Plan

## Goal

Centralize pickleball-specific full-body stance logic in a separate `BasePoseDefinition` asset layer, then compose it at runtime with the existing stroke/contact `PostureDefinition` layer.

This implementation now uses:

- `BasePoseDefinition`
- `BasePoseLibrary`
- `PoseController`
- existing `PostureDefinition` / `PostureLibrary`
- the expanded in-game posture editor for both stroke postures and base poses

## Ownership

- `BasePoseDefinition`
  - owns body stance, foot placement bias, torso/body/head posture, support-arm pose, recovery/jump metadata
  - does not own paddle contact geometry, commit zones, charge, or follow-through contact data

- `PostureDefinition`
  - owns paddle target/orientation, commit zones, charge, and follow-through
  - can still carry body fields for stroke-specific authored shaping, but it is no longer the only runtime source of body posture

- `PoseController`
  - chooses `PoseIntent`
  - chooses `BasePoseState`
  - composes `base pose + stroke posture`
  - exposes the composed runtime posture to body, arm, leg, and skeleton systems

- `PostureEditorUI`
  - authors both stroke postures and base poses in one tool
  - previews stroke postures against base-pose contexts
  - previews base poses against representative stroke contexts

## Blend Precedence

Runtime blend order:

1. `BasePoseDefinition`
2. `PostureDefinition` paddle/stroke/contact data
3. procedural runtime adjustments

Current implementation detail:

- `BasePoseDefinition.blend_onto_stroke()` keeps paddle/contact fields from the stroke posture
- body fields are blended on top using `stroke_overlay_mix`
- procedural systems still run last for lean, ball tracking, foot locking, and hit tween behavior

## Milestones

1. Add the base-pose asset type and library.
2. Add the `PoseController` runtime seam.
3. Route body/arm/leg/skeleton consumers through the composed runtime posture.
4. Expand the posture editor to author base poses in the same UI.
5. Author an initial taxonomy of `.tres` base poses under `res://data/base_poses/`.
6. Add tests for library loading and base/stroke composition.

## Remaining Follow-Ons

- AI jump timing and jump decision logic still needs a dedicated gameplay pass.
- More explicit stroke-body override metadata can be added later if authored contact poses need per-field dominance.
- Timeline/phase authoring in the editor can build on the current preview-state foundation.
