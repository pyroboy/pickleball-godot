# Issues: charge-ft-pairs

## Known issues during refactor
- CHARGE_FH/BH (IDs 8,9) are currently BOTH charge target AND contact posture switch destination
- After refactor: FH/BH postures stay in their own posture during charge, not switching to CH_FH/BH
- Need to ensure CH_FH/BH still look correct (their charge_paddle_rotation_deg IS their appearance)
- BACKWARD COMPAT: fallback when charge_paddle_offset is zero → use existing hardcoded logic
