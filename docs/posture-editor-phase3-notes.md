# Posture Editor — Phase 3 Implementation Notes

**Status**: ✅ Phase 3 complete (full-body skeleton wiring)

## What shipped

### scripts/player_body_builder.gd additions

**Skeleton3D creation** (`_create_skeleton()`):
- 17 bones total in hierarchical structure
- Bone hierarchy:
```
Hips (root)
└── Spine
    └── Chest
        ├── Neck → Head
        ├── RightShoulder → RightUpperArm → RightForearm → RightHand
        └── LeftShoulder → LeftUpperArm → LeftForearm → LeftHand
    ├── RightThigh → RightShin → RightFoot
    └── LeftThigh → LeftShin → LeftFoot
```

- `_player.skeleton` reference stored
- `_player.skeleton_bones` Dictionary maps bone names to indices

### scripts/player.gd additions
- `var skeleton: Skeleton3D = null`
- `var skeleton_bones: Dictionary = {}`
- Skeleton retrieval in `_cache_existing_paddle()`

### scripts/posture_skeleton_applier.gd (new)

**Full-body posture application system**:
- `_apply_head()` — head yaw/pitch from PostureDefinition
- `_apply_torso()` — hip coil, spine curve, chest orientation
- `_apply_arms()` — shoulder rotation, elbow pole targets (stored as metadata for IK)
- `_apply_legs()` — foot targets, knee pole targets (stored as metadata for IK)

**Sign-source pattern preserved**: Uses `_get_swing_sign()` / `_get_forward_axis().z` for blue/red mirroring

### scripts/player_paddle_posture.gd additions
- `var _skeleton_applier: PostureSkeletonApplier`
- Initialized in `_ready()`
- `_apply_full_body_posture()` called automatically when `paddle_posture` changes

### player.gd setter integration
- `paddle_posture` setter now calls `posture._apply_full_body_posture()`
- Every posture change triggers full-body skeleton update

## How it works

1. **Body builds** → Skeleton3D created with 17 bones
2. **Posture changes** (via any system) → setter calls `_apply_full_body_posture()`
3. **Applier reads** PostureDefinition for current posture
4. **Bones posed** directly (head, torso) or **metadata set** for IK (arms, legs)
5. **IK systems** (PlayerArmIK, PlayerLegIK) read metadata in their process loops

## Limitations / Next Steps

**Not yet implemented** (requires IK integration):
- PlayerArmIK reading `right_elbow_pole` / `left_elbow_pole` metadata
- PlayerLegIK reading `right_foot_target` / `left_foot_target` metadata
- PlayerLegIK reading `right_knee_pole` / `left_knee_pole` metadata

These IK modules currently solve their own way; they need to check for posture metadata and use it as hints.

## Files created/modified

| File | Changes |
|------|---------|
| `scripts/posture_skeleton_applier.gd` | New - full-body posture application |
| `scripts/player_body_builder.gd` | Added `_create_skeleton()`, `_add_bone()` |
| `scripts/player.gd` | Added skeleton vars, setter integration |
| `scripts/player_paddle_posture.gd` | Added applier var, `_apply_full_body_posture()` |

---

## Complete Project Status

All 5 phases complete:
- ✅ Phase 1: Resource schema + 21 .tres files
- ✅ Phase 2: Library wired into paddle/hitting/body code
- ✅ Phase 3: Full-body skeleton + applier
- ✅ Phase 4: In-game editor UI (hotkey E)
- ✅ Phase 4b: 3D gizmos

**Total new files**: 4 GDScript files, 21 .tres files, 3 docs
**Total modifications**: 4 existing scripts
