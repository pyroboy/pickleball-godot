# Proposal: Data-Driven Posture Library + Full-Body Posture Editor

**Status**: Proposal — no code changes yet.
**Author prompt**: Extract hardcoded paddle postures, charges, and follow-throughs into an editable data file. Add an in-game editor so every posture can be tweaked live — paddle offset AND rotation AND feet AND knees AND elbows AND head AND body/torso. Trigger individual poses to preview and refine animation transitions.

---

## 1. Context

Today, 20 paddle postures are spread across four scripts as hardcoded
switch/match blocks:

| File | Lines | What's baked in |
|---|---|---|
| `scripts/player_paddle_posture.gd` | 14-83, 50-76, 1313-1365, 1367-1407 | Paddle position constants, `POSTURE_ZONES`, per-posture offset function, per-posture rotation function |
| `scripts/player_hitting.gd` | 4-14, 101-156, 208-250, 299-348 | Charge target rotations, follow-through per family, swing tween timings, peak/overshoot |
| `scripts/player_body_animation.gd` | 3-24, 75-167 | Crouch amounts, body lean scales, body rotation per posture family |
| `scripts/player_arm_ik.gd` | 11-25 | Left arm grip classification (overhead / backhand / default), pole offsets |

**~315 tunable numeric literals** in total, scattered across ~2100 lines. Any
tweak today means: find the switch block → edit GDScript → save → full game
restart → launch practice ball (`4`) → judge → repeat. There is no way to
**preview one posture in isolation**, **snap the player into it**, or **scrub
a charge → contact → follow-through transition**.

Worse: the paddle offset/rotation is the ONLY body part that's data-driven per
posture. Feet, knees, elbows, head, and torso are driven by separate systems
(gait from `player_leg_ik.gd`, lean from `player_body_animation.gd`, right arm
from `player_arm_ik.gd`) that do not know about the specific posture — they
only see "backhand family" or "low tier". This is why a LOW_WIDE_BACKHAND
doesn't plant the inside foot correctly: no one told the leg IK that *this
specific* posture wants a split stance with the lead knee driving hard to the
side.

### The ask

One JSON file per posture. Every part of the player rig is a field. An
in-game editor lets Arjo click a posture name, snap the blue player into that
pose, drag sliders for every joint, and save. A "play transition" button
scrubs through charge → contact → follow-through so the animation can be
judged end-to-end.

---

## 2. Goals

1. **Full-body posture definitions** — every posture owns position/rotation
   targets for paddle, right hand, left hand, right elbow, left elbow, right
   foot, left foot, right knee pole, left knee pole, hips, torso, head.
2. **Editable data files** — one `.tres` Resource per posture OR one JSON
   library; editor writes back to disk.
3. **In-game editor scene** — separate `scenes/posture_editor.tscn` launched
   from a new hotkey. Shows blue player frozen in pose, sliders for every
   field, live preview.
4. **Pose triggering** — any posture can be invoked standalone from the
   editor (no ball needed). Charge and follow-through previewable as animated
   transitions.
5. **Zero-regression migration** — old hardcoded values become the initial
   `.tres` / JSON content. Game plays identically day-1. Tuning happens
   after.
6. **Runtime hot reload** — editor saves → game reloads library without
   restart. Iteration loop drops from ~60s to ~2s.

### Non-goals

- Animation blending beyond lerp + existing Fitts halflife system.
- Mocap import / FBX. Everything stays procedural.
- Multiplayer / networked posture sync.
- Editing the 20 enum members themselves (add/remove postures). That stays
  in `player.gd` for now.

---

## 3. Data Schema

Godot `.tres` Resource is the recommended format (see §7 for JSON tradeoff).
One Resource type, one file per posture, all in `data/postures/`.

### 3.1 `PostureDefinition.gd` — custom Resource class

```gdscript
class_name PostureDefinition extends Resource

# ─── Identity ─────────────────────────────────────────────
@export var posture_id: int              # PaddlePosture enum value
@export var display_name: String         # "Low Wide Forehand"
@export var family: int                  # 0=FH, 1=BH, 2=center, 3=overhead
@export var height_tier: int             # 0=LOW, 1=MID_LOW, 2=NORMAL, 3=OVERHEAD

# ─── Paddle (replaces get_posture_offset_for + rotation) ──
@export_group("Paddle")
@export var paddle_forehand_mul: float   # sideways along forehand axis
@export var paddle_forward_mul: float    # forward along facing axis
@export var paddle_y_offset: float       # vertical relative to player origin
@export var paddle_pitch_deg: float      # applies *swing_sign / fwd_sign
@export var paddle_yaw_deg: float
@export var paddle_roll_deg: float       # e.g. 180 for LOW inverted
@export var paddle_pitch_sign_source: int = 0   # 0=fwd_sign, 1=swing_sign, 2=none
@export var paddle_yaw_sign_source: int = 1
@export var paddle_roll_sign_source: int = 1
@export var paddle_floor_clearance: float = 0.06  # 0.45 for inverted

# ─── Commit zone (replaces POSTURE_ZONES) ─────────────────
@export_group("Zone")
@export var zone_x_min: float
@export var zone_x_max: float
@export var zone_y_min: float
@export var zone_y_max: float

# ─── Right arm (paddle hand) ──────────────────────────────
@export_group("Right Arm IK")
@export var right_hand_offset: Vector3        # from paddle grip
@export var right_elbow_pole: Vector3         # pole target relative to shoulder
@export var right_shoulder_rotation_deg: Vector3

# ─── Left arm (two-handed grip / guard hand) ──────────────
@export_group("Left Arm IK")
@export var left_hand_mode: int = 0       # 0=free, 1=paddle neck, 2=across chest, 3=overhead lift
@export var left_hand_offset: Vector3
@export var left_elbow_pole: Vector3
@export var left_shoulder_rotation_deg: Vector3

# ─── Legs / stance ────────────────────────────────────────
@export_group("Legs")
@export var stance_width: float = 0.35            # foot separation
@export var front_foot_forward: float = 0.12      # lead foot depth
@export var back_foot_back: float = -0.08
@export var right_foot_yaw_deg: float = 0.0       # splay
@export var left_foot_yaw_deg: float = 0.0
@export var right_knee_pole: Vector3              # knee IK pole
@export var left_knee_pole: Vector3
@export var lead_foot: int = 0                    # 0=right, 1=left
@export var crouch_amount: float = 0.0            # 0=upright, 0.28=low
@export var weight_shift: float = 0.0             # -1=back foot, +1=front foot

# ─── Hips / torso ─────────────────────────────────────────
@export_group("Torso")
@export var hip_yaw_deg: float                    # coil
@export var torso_yaw_deg: float                  # shoulder turn
@export var torso_pitch_deg: float                # forward lean
@export var torso_roll_deg: float                 # side lean
@export var spine_curve_deg: float = 0.0          # crouch back curl

# ─── Head ─────────────────────────────────────────────────
@export_group("Head")
@export var head_yaw_deg: float                   # relative to torso
@export var head_pitch_deg: float                 # look at ball
@export var head_track_ball_weight: float = 1.0   # 0=locked, 1=full track

# ─── Charge (replaces per-posture charge blocks) ──────────
@export_group("Charge")
@export var charge_paddle_offset: Vector3         # additional to paddle
@export var charge_paddle_rotation_deg: Vector3
@export var charge_body_rotation_deg: float
@export var charge_hip_coil_deg: float            # extra hip pre-load
@export var charge_back_foot_load: float = 0.7    # 0-1, weight onto back foot

# ─── Follow-through (replaces _get_follow_through_offsets) ─
@export_group("Follow-Through")
@export var ft_paddle_offset: Vector3
@export var ft_paddle_rotation_deg: Vector3
@export var ft_hip_uncoil_deg: float
@export var ft_front_foot_load: float = 0.85
@export var ft_duration_strike: float = 0.09
@export var ft_duration_sweep: float = 0.18
@export var ft_duration_settle: float = 0.15
@export var ft_duration_hold: float = 0.12
@export var ft_ease_curve: int = 0                # 0=EXPO_OUT, 1=QUAD_OUT, 2=SINE_IO

# ─── Metadata ─────────────────────────────────────────────
@export var notes: String = ""                    # tuning comments
@export var last_tuned_by: String = ""
@export var last_tuned_at: String = ""
```

One file per posture: `data/postures/forehand.tres`,
`data/postures/low_wide_backhand.tres`, etc. 20 files total.

### 3.2 `PostureLibrary.gd` — loader + cache

```gdscript
class_name PostureLibrary extends Resource

@export var postures: Array[PostureDefinition] = []

var _by_id: Dictionary = {}

func rebuild_index() -> void:
    _by_id.clear()
    for p in postures:
        _by_id[p.posture_id] = p

func get(id: int) -> PostureDefinition:
    return _by_id.get(id, null)

func reload_from_disk() -> void:
    postures.clear()
    var dir := DirAccess.open("res://data/postures/")
    for f in dir.get_files():
        if f.ends_with(".tres"):
            postures.append(load("res://data/postures/" + f))
    rebuild_index()
```

Loaded once in `player.gd:_ready()`, passed to all modules that currently
have hardcoded switches.

---

## 4. Migration Path

**Zero regression is critical** — the game must play identically after the
extraction, then diverge only through explicit tuning.

### Phase 1: Extract constants (mechanical)
1. Write `PostureDefinition.gd` Resource class.
2. Script a one-shot Godot editor tool (`tools/extract_postures.gd`) that
   reads the current hardcoded functions and produces 20 `.tres` files with
   the exact current values. This is the source of truth for the migration —
   it eliminates the risk of hand-transcription errors across ~315 numbers.
3. Verify byte-identical gameplay: run a scripted practice-ball sequence
   before and after extraction, compare `[SCORE]` logs. Grades should match
   exactly.

### Phase 2: Wire loader into existing systems
Replace the hardcoded blocks with library lookups:

| Current callsite | New implementation |
|---|---|
| `get_posture_offset_for(p)` | `library.get(p).paddle_forehand_mul * fh + ...` |
| `_get_posture_rotation_offset_for(p)` | `Vector3(def.paddle_pitch_deg * sign, ...)` |
| `POSTURE_ZONES[p]` | `{"x_min": def.zone_x_min, ...}` |
| `player_hitting.gd` charge blocks | `def.charge_paddle_offset`, `def.charge_body_rotation_deg` |
| `player_hitting.gd` follow-through | `def.ft_paddle_offset`, `def.ft_duration_*` |
| `player_body_animation.gd` crouch | `def.crouch_amount` |
| `player_body_animation.gd` body rotation | `def.torso_yaw_deg`, `def.hip_yaw_deg` |
| `player_arm_ik.gd` grip selection | `def.left_hand_mode` |

At this point paddle behavior is unchanged. New fields (feet, knees, head,
hips) exist in the Resource but are not yet consumed.

### Phase 3: Wire full-body fields
This is where feet / knees / elbows / head / torso actually start obeying
posture data. Changes by subsystem:

- **`player_leg_ik.gd`**: the gait system currently generates step targets
  procedurally. Override: if `crouch_amount > 0.05`, instead of a walking
  gait, snap to `stance_width` + `front_foot_forward` + `back_foot_back`
  with the specified knee poles. This is a *pose*, not a gait — gait resumes
  when crouch_amount returns to 0.
- **`player_body_animation.gd`**: replace the scalar `body_pivot.rotation.y`
  with a two-joint rig — hips (yaw only) and torso (yaw + pitch + roll).
  Drive both from `def.hip_yaw_deg` and `def.torso_*_deg`.
- **`player_body_builder.gd`**: add a head bone + neck joint if missing.
  Drive head from `def.head_yaw_deg` / `def.head_pitch_deg`, blended with
  ball-tracking by `def.head_track_ball_weight`.
- **`player_arm_ik.gd`**: elbow poles (`right_elbow_pole`, `left_elbow_pole`)
  replace the current hardcoded `forehand_axis * 0.5 + Vector3(0, -1.0, 0)`.
- **Spine curl**: `def.spine_curve_deg` becomes a small rotation on a mid-
  spine bone during crouch (LOW / MID_LOW postures only).

Each full-body field ships behind a `use_full_body_posture: bool` flag on
`PlayerController` so it can be toggled off per-player during rollout.
Default: off for Phase 2, on for Phase 3.

### Phase 4: Editor

See §5.

---

## 5. In-Game Posture Editor

### 5.1 Launch

New hotkey `E` in `game.gd`. Pauses gameplay (time_scale = 0), spawns
`PostureEditor` UI overlay, freezes the blue player at its current position,
and loads `PostureLibrary` in editable mode.

Alternative: standalone `scenes/posture_editor.tscn` launched from a main-menu
button or CLI flag (`godot --editor-mode`). Cleaner but more work. Recommend
in-game overlay for Phase 4, standalone for Phase 5 if needed.

### 5.2 Layout

```
┌──────────────────────────────────────────────────────────────┐
│ POSTURE EDITOR                              [Save] [Revert]  │
├────────────┬─────────────────────────────────────────────────┤
│ Posture    │  [3D viewport — blue player in pose]            │
│ List:      │                                                 │
│ > FOREHAND │   ghost outline = current saved                 │
│   BACKHAND │   solid = live edits                            │
│   WIDE_FH  │                                                 │
│   ...      │                                                 │
│            │                                                 │
│ [+ Clone]  │                                                 │
├────────────┴─────────────────────────────────────────────────┤
│ PADDLE          LEGS          TORSO         FOLLOW-THROUGH   │
│ ├ forehand_mul  ├ stance_w    ├ hip_yaw     ├ paddle offset  │
│ │ ◀─●──▶ 0.50   │ ◀──●─▶ 0.35 │ ◀─●──▶ 25°  │ ... sliders    │
│ ├ forward_mul   ├ front_fwd   ├ torso_yaw   │                │
│ ├ y_offset      ├ right_knee  ├ torso_pitch │ [▶ Play]       │
│ ├ pitch/yaw/roll│ ├ left_knee │ ...         │ duration: 0.5s │
│ ...             │ ├ crouch    │ ...         │                │
├──────────────────────────────────────────────────────────────┤
│ [Trigger Pose] [Trigger Charge] [Trigger Follow-Through]     │
│ [Play Transition: charge → contact → FT]                      │
└──────────────────────────────────────────────────────────────┘
```

### 5.3 Trigger buttons (the core of "animate the character accordingly")

- **Trigger Pose** — snap the player instantly to the edited definition.
  Every joint updates. No ball, no AI, no gravity on the player. Used for
  static inspection.
- **Trigger Charge** — tween from current pose into charge pose over
  `ft_duration_strike` (or a dedicated charge duration). Shows the pre-swing
  wind-up.
- **Trigger Follow-Through** — tween through strike → sweep → settle → hold
  using the four duration fields. Shows the post-contact arc.
- **Play Transition** — full cycle: ready → charge → contact → follow-through
  → back to ready. This is the "animate accordingly to the paddle posture
  perfectly" button. Loops on a toggle.

Every trigger emits a log line so the existing `[COMMIT]` / `[COLOR]` /
`[SCORE]` debug format still works — grades become meaningful even in editor
mode if you launch a ball mid-edit.

### 5.4 Widgets per field

- Scalars → slider with numeric input and reset button
- Vector3 → three sliders, side-by-side, labeled X/Y/Z
- Degrees → slider in degrees (never radians in the UI)
- Enums (left_hand_mode, ft_ease_curve) → dropdown
- Boolean (lead_foot) → toggle

All edits are live — the 3D viewport reflects the latest slider value every
frame. Save writes back to the `.tres` on disk. Revert reloads from disk.

### 5.5 Gizmos in the 3D viewport

- Paddle position → draggable sphere (X/Y/Z handles)
- Paddle rotation → ring gizmo
- Zone rectangle → wireframe box in local space
- Knee poles → small diamond gizmos
- Foot positions → flat disc gizmos
- Head aim → forward arrow

Dragging a gizmo updates the corresponding slider and writes the field. This
is the fast-iteration path for Arjo — sliders for fine numbers, gizmos for
"grab the elbow and yank it up 10cm".

### 5.6 Clone / new posture flow

Right-click posture list → "Clone as new name". Useful when experimenting
with a variation before deciding to promote it. Clones are written to
`data/postures/_experimental/` to keep them out of the main library until
promoted.

---

## 6. File Layout

```
data/
  postures/
    _schema.md                       # human-readable schema reference
    forehand.tres
    wide_forehand.tres
    low_wide_forehand.tres
    ...
    charge_forehand.tres
    charge_backhand.tres
    _experimental/                   # clones / WIP
      forehand_v2.tres

scripts/
  posture_definition.gd              # Resource class (§3.1)
  posture_library.gd                 # Loader (§3.2)
  posture_applier.gd                 # Applies a PostureDefinition to player rig
  posture_editor/
    posture_editor.gd                # Main editor scene script
    posture_slider_panel.gd          # Sliders for one group
    posture_gizmo.gd                 # 3D handles
    posture_transition_player.gd     # Play Transition button logic

scenes/
  posture_editor.tscn                # Editor overlay

tools/
  extract_postures.gd                # One-shot migration tool (§4 phase 1)
```

---

## 7. JSON vs `.tres` Tradeoff

| Criterion | `.tres` Resource | JSON |
|---|---|---|
| In-engine editing | ✅ native inspector | ❌ need custom UI only |
| Version control diffs | 🟡 readable but verbose | ✅ compact |
| Hot reload | ✅ `load()` re-reads | ✅ `JSON.parse_string()` |
| Type safety | ✅ typed `@export` fields | ❌ manual validation |
| External editing (VS Code) | 🟡 works, awkward | ✅ ideal |
| Schema migration | ✅ Resource versioning | 🟡 hand-roll |

**Recommendation**: `.tres`. The in-engine inspector is a free fallback if
the custom editor has bugs, and typed fields catch errors at load time. JSON
export is trivial to add later if external editing becomes important — one
button: "Export library as JSON".

---

## 8. Open Questions

1. **Full body IK rig** — does the current player model have enough bones
   for per-posture hips / torso / head control? `player_body_builder.gd` is
   procedural mesh generation; need to verify the Skeleton3D (if any)
   exposes the joints this proposal assumes, or whether this proposal also
   requires extending the procedural body with a proper bone hierarchy.

2. **Gait override model** — the proposal says "when crouch > 0.05, override
   gait with posed stance". Is that the right switch? Maybe gait should
   always blend toward the posed stance proportional to `_ball_incoming`
   and commit stage instead of a hard override.

3. **Per-player or shared library?** — blue and red use the same library
   today. Keep it that way (recommended — simpler, and AI benefits from the
   same tuning), or split into `data/postures/blue/` and `data/postures/red/`
   for future asymmetric balancing?

4. **Editor scope v1** — ship with all fields editable, or paddle + legs +
   torso first (the visible stuff) and arms/head later? Recommend: ship all
   fields as sliders, prioritize gizmos for paddle / feet / knees in v1.

5. **Save format versioning** — add a `schema_version: int` field to each
   `.tres` now, so future field additions can auto-migrate without breaking
   old files?

6. **Undo/redo** — in-editor undo stack, or rely on git + revert button?
   Recommend: git + revert for v1. Undo is a lot of code for one user.

---

## 9. Effort Estimate

| Phase | Scope | Effort |
|---|---|---|
| 1 — Extract to `.tres` | Schema class, migration tool, byte-identical playback | 1-2 days |
| 2 — Wire loader (paddle only) | Replace 4 hardcoded blocks with lookups | 1 day |
| 3 — Full-body wiring | Legs, torso, head, elbow IK overrides | 3-5 days (depends on rig Q1) |
| 4 — Editor UI | Sliders, live preview, trigger buttons | 3-4 days |
| 4b — Gizmos | Draggable handles in 3D viewport | 2-3 days |
| 5 — Polish | Save/revert/clone/experimental folder | 1 day |
| **Total** | | **~11-16 days** |

Phase 1 + 2 alone (extract + paddle-only) is ~3 days and unlocks text-editor
tuning of everything you can tune today, with zero regression risk. Recommend
landing that first, then scoping Phase 3/4 against Q1 (does the rig support
it).

---

## 10. Success Criteria

- All ~315 hardcoded posture numbers live in `data/postures/*.tres`
- `grep -rn "PaddlePosture.FOREHAND\|PaddlePosture.BACKHAND" scripts/` returns
  only enum declarations + the applier — no switch/match blocks left
- Launching the editor (key `E`), clicking `LOW_WIDE_BACKHAND`, and dragging
  the left-foot gizmo visibly moves the foot in the game world in real time
- Pressing "Play Transition" animates the full charge → contact →
  follow-through cycle smoothly, previewable without needing a ball in play
- Save writes to disk; restart loads the same values; gameplay unchanged from
  the previous session
- `[SCORE]` rubric still emits correct grades against the new data-driven
  pipeline

---

## 11. What This Proposal Does NOT Do

- Change the commitment state machine (FIRST/TRACE/LOCK, PINK/PURPLE/BLUE) —
  that stays as documented in `docs/trajectory-commit-system.md`
- Change the trajectory prediction or green pooling — unrelated subsystems
- Add new postures to the enum — the 20 existing ones are the scope
- Replace `player_body_builder.gd` procedural mesh with an FBX import
- Touch ball physics, AI brain logic, or scoring thresholds

The proposal is intentionally scoped to **"extract what exists, add full-body
fields, build an editor"**. Nothing about the play mechanics changes until
tuning happens through the editor.
