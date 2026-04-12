# Decisions: charge-ft-pairs

## Wave 1 data entry strategy
- Parallelize by family: 4 agents working simultaneously
- Each agent handles one family's postures in posture_library.gd
- CH_FH/BH (IDs 8,9) preserve existing charge data — no changes needed
- READY (ID=20) has ft only (no charge, no swing)

## Per-posture value approach
- Base contact position (pfw, pfy) already defined in existing _make() calls
- charge_paddle_offset is relative TO contact position
- For each posture: derive charge offset from its own contact position
- FH charge: pull back (negative forward), slight forehand side, lift up
- BH charge: pull back, opposite side, lift up  
- OVERHEAD charge: strong lift, pull back
- CENTER charge: compact, minimal movement

## Runtime consumption
- If charge_paddle_offset.length_squared() < 0.0001: fallback to hardcoded behavior
- This allows incremental adoption — postures with zero charge data still work

## FT consumption
- If ft_paddle_offset.length_squared() < 0.0001: fallback to hardcoded behavior
- ft_paddle_rotation_deg for authored rotation in FT
