# Notepad: charge-ft-pairs

## Posture Families
- FH (family=0): IDs 0,5,10,13,16,18
- BH (family=1): IDs 2,7,11,14,17,19
- CENTER (family=2): IDs 1,6,15,20
- OVERHEAD (family=3): IDs 3,4
- CHARGE (IDs 8,9): PRESERVE existing data
- READY (ID=20): no swing

## Key file locations
- posture_library.gd: `_build_defaults()` + `_make()` function
- posture_definition.gd: PostureDefinition class with all exported fields
- player_hitting.gd: set_serve_charge_visual, _get_follow_through_offsets, _authored_follow_through_data, animate_serve_release
- player.gd: PaddlePosture enum at line 42-64

## _make() function signature (line 263)
Maps dict keys to PostureDefinition fields. New keys to add:
- "charge_offset" → charge_paddle_offset
- "charge_rot" → charge_paddle_rotation_deg  
- "charge_body_deg" → charge_body_rotation_deg
- "charge_hip_deg" → charge_hip_coil_deg
- "ft_offset" → ft_paddle_offset
- "ft_rot" → ft_paddle_rotation_deg
- "ft_hip_deg" → ft_hip_uncoil_deg
- "ft_load" → ft_front_foot_load

## Design rationale for values
- charge_paddle_offset: offset FROM contact position TO charge position
  - FH: (-0.25 to -0.35, +0.15 to +0.25, +0.08 to +0.12) — pull back, slight lift
  - BH: (-0.25 to -0.35, +0.15 to +0.25, +0.08 to +0.12) — pull back, slight lift
  - OVERHEAD: (-0.15, +0.35 to +0.45, +0.20 to +0.25) — strong lift
  - CENTER: (-0.15, +0.10, +0.05) — compact
- ft_paddle_offset: offset FROM contact TO FT end
  - FH: (+0.10 to +0.15 forehand side, +0.30 to +0.40 forward, -0.15 to -0.20 y)
  - BH: (-0.10 to -0.15 forehand side, +0.30 to +0.40 forward, -0.15 to -0.20 y)
  - OVERHEAD: (+0.40 to +0.50 forward, -0.30 to -0.40 y)
  - CENTER: (+0.30 forward, +0.05 y)
