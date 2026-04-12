# Work Plan: Charge + Follow-Through Pairs for All 20 Postures

## TL;DR

> **Quick Summary**: Author per-posture charge wind-up and follow-through data for all 20 paddle postures, then refactor the runtime charge/FT systems to consume authored data instead of hardcoded family-level logic.
>
> **Deliverables**:
> - 20 posture definitions in `posture_library.gd` each with full charge + FT fields populated
> - `player_hitting.gd` refactored to read per-posture charge data (no more posture-switch to `CHARGE_FOREHAND`/`CHARGE_BACKHAND`)
> - `player_hitting.gd` FT system refactored to read per-posture authored FT data
> - Posture editor "Preview Swing" reflects authored charge + FT for all postures
>
> **Estimated Effort**: Medium-Large
> **Parallel Execution**: NO — sequential (data → charge refactor → FT refactor → editor)
> **Critical Path**: posture_library data → charge refactor → FT refactor

---

## Context

### Original Request
Add charge and follow-through pairs for all 20 paddle postures, plus refactor the charge system to use per-posture authored data.

### What Exists Today

**Charge system** (`player_hitting.gd:set_serve_charge_visual`):
- FH postures: switches to `CHARGE_FOREHAND` (ID 8), lerps toward its authored rotation
- BH postures: switches to `CHARGE_BACKHAND` (ID 9), lerps toward its authored rotation
- OVERHEAD: hardcoded offsets (no authored data)
- CENTER: generic fallback (no authored data)
- **Problem**: charge rotation IS per-posture-authorable (`charge_paddle_rotation_deg`) but only for the two dedicated charge postures, not the 18 contact postures

**Follow-through system** (`_get_follow_through_offsets`):
- ALL postures use hardcoded ratio-based offsets (no per-posture authored data)
- `_has_authored_follow_through()` checks `ft_paddle_offset.length_squared() > 0.0001` → always false
- **Problem**: no posture has `ft_paddle_offset` or `ft_paddle_rotation_deg` authored

**PostureDefinition fields to populate** (per posture):
- `charge_paddle_offset: Vector3` — where paddle winds up relative to contact position
- `charge_paddle_rotation_deg: Vector3` — paddle rotation during wind-up
- `charge_body_rotation_deg: float` — body rotation during wind-up
- `charge_hip_coil_deg: float` — hip rotation during wind-up
- `charge_back_foot_load: float` — weight shift during charge
- `ft_paddle_offset: Vector3` — FT paddle displacement
- `ft_paddle_rotation_deg: Vector3` — FT paddle rotation
- `ft_hip_uncoil_deg: float` — hip rotation after contact
- `ft_front_foot_load: float` — weight distribution in FT
- `ft_duration_strike/sweep/settle/hold: float` — FT timing
- `ft_ease_curve: int` — FT easing

**Existing authored data**:
- `CHARGE_FOREHAND` (ID 8): has `charge_paddle_rotation_deg=Vector3(-45, 35, -20)`, `charge_body_rotation_deg=35`
- `CHARGE_BACKHAND` (ID 9): has `charge_paddle_rotation_deg=Vector3(-45, -35, 20)`, `charge_body_rotation_deg=110`

---

## Work Objectives

### Core Objective
Every paddle posture has complete, authored charge wind-up data and follow-through data consumed by the runtime system instead of hardcoded family-level logic.

### Concrete Deliverables
1. All 20 postures have charge + FT fields populated in `posture_library.gd`
2. `player_hitting.gd:set_serve_charge_visual` reads from current posture's authored charge data (no posture switch)
3. `player_hitting.gd:_get_follow_through_offsets` replaced by authored FT data consumption
4. Posture editor "Preview Swing" (transition player) uses authored data for all postures

### Must Have
- Gameplay behavior preserved for existing postures (byte-identical for those with current hardcoded behavior)
- All 20 postures functional in swing system after refactor
- Posture editor shows charge + FT tabs populated for all postures

### Must NOT Have
- Breaking existing FH/BH/OVERHEAD swing feel without documented rationale
- Postures with zeroed/empty charge or FT fields (all must have sensible defaults)

---

## Execution Strategy

### Wave 1: Author all 20 posture definitions (data entry)
Update `_make()` calls in `posture_library.gd:_build_defaults()` for all 20 postures.

**Approach per posture family:**

| Family | Postures | Charge Pattern | FT Pattern |
|--------|----------|---------------|------------|
| FH (0) | FOREHand, LOW_FH, WIDE_FH, MID_LOW_FH, MID_LOW_WIDE_FH, LOW_WIDE_FH | Pull back + rotate away, body coils | Sweep across body, finish low |
| BH (1) | BACKHand, LOW_BH, WIDE_BH, MID_LOW_BH, MID_LOW_WIDE_BH, LOW_WIDE_BH | Pull back opposite side, body coils | Sweep across body other way |
| CENTER (2) | FORWARD, LOW_FORWARD, MID_LOW_FORWARD | Compact pull back | Short forward punch |
| OVERHEAD (3) | MEDIUM_OVERHEAD, HIGH_OVERHEAD | Lift + pull back | Slam down-forward |

**Design rationale for charge offsets:**
- `charge_paddle_offset`: Vector3 representing offset FROM contact position TO charge position
  - FH: negative forward_mul (pull back), slight positive forehand_mul, positive y (lift)
  - BH: negative forward_mul, negative forehand_mul, positive y
  - OVERHEAD: strong positive y (lift), negative forward_mul
  - CENTER: modest pull back, minimal lift

**Design rationale for FT offsets:**
- `ft_paddle_offset`: Vector3 of displacement FROM contact TO FT end
  - FH: +forehand (across body), +forward, -y (drop)
  - BH: -forehand, +forward, -y
  - OVERHEAD: +forward, -y (slam down)
  - CENTER: +forward, +y (slight lift)

**Add to `_make()` call** — new dictionary keys:
```gdscript
"charge_offset": Vector3(x, y, z),      # paddle offset to charge position
"charge_rot": Vector3(pitch, yaw, roll), # paddle rotation during charge
"charge_body_deg": float,               # body rotation during charge
"charge_hip_deg": float,                 # hip coil during charge
"ft_offset": Vector3(x, y, z),            # FT displacement from contact
"ft_rot": Vector3(pitch, yaw, roll),      # FT rotation from contact
"ft_hip_deg": float,                     # hip uncoil in FT
"ft_load": float,                        # front foot load in FT
```

**Update `_make()` function** to consume these new keys:
- Map `"charge_offset"` → `d.charge_paddle_offset`
- Map `"charge_rot"` → `d.charge_paddle_rotation_deg`
- Map `"charge_body_deg"` → `d.charge_body_rotation_deg`
- Map `"charge_hip_deg"` → `d.charge_hip_coil_deg`
- Map `"ft_offset"` → `d.ft_paddle_offset`
- Map `"ft_rot"` → `d.ft_paddle_rotation_deg`
- Map `"ft_hip_deg"` → `d.ft_hip_uncoil_deg`
- Map `"ft_load"` → `d.ft_front_foot_load`

**Postures to update** (20 total, IDs 0-20):
```
0: FOREHand    - FH family, normal tier
1: FORWARD    - CENTER family, normal tier
2: BACKHand   - BH family, normal tier
3: MEDIUM_OV  - OVERHEAD family
4: HIGH_OV    - OVERHEAD family
5: LOW_FH     - FH family, LOW tier
6: LOW_FW     - CENTER family, LOW tier
7: LOW_BH     - BH family, LOW tier
8: CH_FH      - ALREADY HAS charge data (preserve)
9: CH_BH      - ALREADY HAS charge data (preserve)
10: WIDE_FH   - FH family, normal tier
11: WIDE_BH   - BH family, normal tier
12: VOLLEY_RDY - CENTER family, normal tier
13: MID_L_FH  - FH family, MID_LOW tier
14: MID_L_BH  - BH family, MID_LOW tier
15: MID_L_FW  - CENTER family, MID_LOW tier
16: MID_L_WFH - FH family, MID_LOW tier, wide
17: MID_L_WBH - BH family, MID_LOW tier, wide
18: LOW_W_FH  - FH family, LOW tier, wide
19: LOW_W_BH  - BH family, LOW tier, wide
20: READY     - CENTER family, special (no swing, skip)
```

Note: IDs 8 and 9 (CHARGE_FH/BH) are the charge TARGET postures, not contact postures. Their existing charge data should be preserved as their "charge" data IS their contact position (they are the charge).

---

### Wave 2: Refactor charge system to per-posture authored data

**File**: `player_hitting.gd`

**Change `set_serve_charge_visual`** to read from current posture's authored charge data instead of switching to `CHARGE_FOREHAND`/`CHARGE_BACKHAND`.

**Old logic**:
```gdscript
# FH: switch to CHARGE_FOREHAND, read its authored rotation
if _player.paddle_posture in _player.FOREHAND_POSTURES:
    _player.paddle_posture = _player.PaddlePosture.CHARGE_FOREHAND
    var charge_def = posture_lib.get_def(CHARGE_FOREHAND)
    charge_target_rotation = charge_def.charge_paddle_rotation_deg
```

**New logic**:
```gdscript
# Read charge data from CURRENT posture definition
var current_def = posture_lib.get_def(_player.paddle_posture)
if current_def != null and current_def.charge_paddle_offset.length_squared() > 0.0001:
    # Use authored charge data
    var charge_pos = _player.paddle_rest_position + current_def.charge_paddle_offset * clamped_ratio
    var charge_rot = current_def.resolve_paddle_rotation_deg(swing_sign, fwd_sign)
    # (apply signed yaw if needed)
else:
    # Fallback to existing hardcoded behavior for postures without authored data
```

**Key changes**:
1. Remove `_player.paddle_posture = CHARGE_FOREHAND/BACKHAND` switches — keep current posture
2. Read `charge_paddle_offset` from current posture definition (Vector3 offset from contact position)
3. Read `charge_paddle_rotation_deg` from current posture definition (with signed-yaw applied)
4. Body rotation: use `current_def.charge_body_rotation_deg` instead of global `BODY_CHARGE_ROTATION_DEGREES`
5. Add hip coil: `current_def.charge_hip_coil_deg`
6. Keep OVERHEAD and CENTER fallback for postures with zeroed charge data (backward compat)

**For `CHARGE_FOREHAND` and `CHARGE_BACKHAND`** (IDs 8, 9):
- These ARE the charge target — their "charge" data should be interpreted as the wind-up FROM their contact position TO their current position
- Since they have no separate "contact position" (they ARE the charged state), their `charge_paddle_offset` = `(0, 0, 0)` which is correct
- Their `charge_paddle_rotation_deg` already defines their appearance

**Backward compatibility**: if `charge_paddle_offset.length_squared() < 0.0001`, fall back to existing hardcoded behavior. This lets us ship incrementally.

---

### Wave 3: Refactor FT system to per-posture authored data

**File**: `player_hitting.gd`

**Replace `_has_authored_follow_through` + `_get_follow_through_offsets`** with authored data consumption.

**Change `animate_serve_release`**:
- Instead of calling `_get_follow_through_offsets(ratio, fwd, fh, swing_sign, posture)`, read authored FT data from posture definition
- Use `_authored_follow_through_data(posture_id, charge_ratio)` which already exists and checks `ft_paddle_offset.length_squared() > 0.0001`

**Change `_get_follow_through_offsets`**:
- Keep as FALLBACK for postures without authored FT data
- When authored data exists, return it directly instead of computing

**New authored FT path** (when `ft_paddle_offset.length_squared() > 0.0001`):
```gdscript
# From _authored_follow_through_data:
target_pos = _player.paddle_rest_position + def.ft_paddle_offset * clamped_ratio
target_rot = _player.paddle_rest_rotation + def.ft_paddle_rotation_deg * clamped_ratio
```

**For the 4-phase FT animation** (`animate_serve_release`):
- `ft_duration_strike/sweep/settle/hold` from authored data
- `ft_ease_curve` from authored data
- `ft_hip_uncoil_deg` applied to body pivot in FT
- `ft_front_foot_load` applied to weight distribution

---

### Wave 4: Editor integration

**Files**: `posture_editor_ui.gd`, `pose_trigger.gd`

**Preview Swing** (`_setup_transition_player`):
- `_build_charge_preview_def` already uses `charge_paddle_offset` and `charge_body_rotation_deg` from the contact posture — this now works for all postures
- `_build_follow_through_preview_defs` already uses `ft_paddle_offset` etc. — now works for all postures
- No change needed if Wave 1 data is correct

**Tab visibility**:
- `Charge` and `Follow-Through` tabs already exist in the editor UI
- They are shown/hidden based on `STROKE_POSTURES` workspace mode (not base poses)
- All 20 contact postures already see these tabs — no UI change needed

**Transition player** (`transition_player.gd`):
- Already supports multiple FT keyframes via `_follow_through_defs` array
- `_build_follow_through_preview_defs` builds FT preview from authored `ft_paddle_offset` and `ft_paddle_rotation_deg` — now functional for all postures

---

## Wave Dependency

```
Wave 1 (data) ──► Wave 2 (charge refactor) ──► Wave 3 (FT refactor) ──► Wave 4 (editor, verify)
                          │
                          └── Wave 3 can start after Wave 1 + Wave 2 (independent)
```

Wave 3 (FT refactor) depends on Wave 1 data but can run parallel to Wave 2 after data exists.

---

## Success Criteria

1. All 20 postures have non-zero `charge_paddle_offset` + `charge_paddle_rotation_deg` + `ft_paddle_offset` + `ft_paddle_rotation_deg`
2. FH/BH swing in game uses per-posture authored charge rotation (not CHAnge_FH/BH switch)
3. FT animation uses authored `ft_paddle_offset`/`ft_paddle_rotation_deg` when available
4. Posture editor "Preview Swing" shows distinct charge/FT motion for each posture family
5. Existing gameplay behavior (FH, BH, OVERHEAD) is preserved — only the data source changes, not the values for existing well-tuned postures
