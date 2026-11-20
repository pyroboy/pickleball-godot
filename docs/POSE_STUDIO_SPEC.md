# Pose Studio: execution spec

Written 2026-11-20 from a planning session with the user. This file is the single source
for the work; a new session should be able to execute from it without the chat history.
Stage 0 is built. Start at stage 1 unless the user says otherwise.

---

## 1. Goal

The animations still feel off. The user wants to refine them personally in a full-screen
Godot editor on the Mac, review on the phone, and have Claude do the analysis and the edits
they ask for.

**Pivot 2026-11-20 (user decision):** the browser editor is dropped. Editing happens in a
full-screen desktop Godot editor (the "Desktop Pose Studio"), because gizmos on the real
solved body with real cards are better than any browser copy. The browser build reached
its stage 1-2 checks before the pivot; its engine-independent parts are kept (section 4).

| Where | Does |
|---|---|
| Desktop Pose Studio (Godot, full screen, Mac) | The only pose editor. Saves to `data/postures/*.tres` and `data/base_poses/*.tres`, the single source of truth. |
| Phone | Pose player, notes, change log. No editing. |
| Claude | Runs the checker, reads the user's notes, edits poses, replies on each note with what changed and the evidence. |

**Target: most poses at 5 stars on the user's own rating** (section 4.1). Working
definition until the user changes it: at least 80% of poses in each pose type rated 5
stars on their current version, and none below 4.

Out of scope: a keyframe curve editor, IK/FK switching (the game has three keys per stroke
and solves limbs itself).

## 2. Hard rules

1. **Test with data, not images.** Verify with the pose checker, metrics JSON, swing
   traces, page text / DOM state and logs. Do not open screenshots, pose sheets or
   browser screenshots. If a check truly needs an image, ask the user first.
2. **No bench.** `tools/bench.sh` is off for this work (user: time waster, token trap).
   Run it only if the user asks. Instead, list which gameplay fields an edit touched.
3. **Keep output small.** Flags only, worst first; full tables go to files under `logs/`.
4. **Pose ownership is unresolved.** 15 files in `data/postures` have uncommitted edits
   from another session. Do not edit any pose file until the user confirms. Reading is fine.
5. **Shared checkout.** Several sessions work on branch `visual-pass`. Stage only your own
   files and hunks, never `git add -A`, never amend. Commit only when the user asks.
   Files of this work so far: `tools/pose_check.py`, `scripts/debug/pose_data.gd`,
   `docs/POSE_STUDIO_SPEC.md`, and one 4-line hunk in `scripts/debug/perf_monitor.gd`
   (the `--pose-data=` hook).
6. **Never add nodes or meshes under a player's `BodyPivot`.** Gameplay scans them.
7. **The studio server listens on 127.0.0.1 only** (it writes files). A paired phone is
   the one exception, in stage 5.
8. Project rules in `CLAUDE.md` still apply: small changes, no per-frame `print()`,
   visuals in `_process` read `get_global_transform_interpolated()`.
9. Reply style the user expects: plain language, short, decisions stated clearly, and say
   plainly what was not verified.

## 3. What exists today

### 3.1 Built in this work (stage 0)

```bash
python3 tools/pose_check.py                 # level A: pose files only, instant
python3 tools/pose_check.py --solve         # + levels B, C: headless Godot, ~10 s, 50 poses
python3 tools/pose_check.py --solve --baseline   # remember this run
python3 tools/pose_check.py --solve --diff       # what an edit fixed / added since baseline
python3 tools/pose_check.py --solve --all s13    # every flag, chosen poses
```

- Output: ranked list (worst 15) in the terminal; everything in
  `logs/pose_check/report.txt`, `latest.json`, `baseline.json`, raw captures in
  `logs/pose_check/raw/<key>_now.json` (`logs/` is git-ignored).
- Keys: `s00`..`s20` strokes (`data/postures`), `b00`..`b21` body stances
  (`data/base_poses`), `v00`..`v06` serves.
- Capture: `scripts/debug/pose_data.gd` extends `scripts/debug/pose_shots.gd`, overrides
  `_capture` to skip screenshots, and adds joint positions plus `timed`: the swing sampled
  on the editor's elapsed-time timeline (Charge -> release, runtime motion, full charge)
  once per game tick (1/30 s). Launched by `perf_monitor.gd` on `--pose-data=<abs dir>`,
  optional `--pose-only=s00,b11`, `--pose-settle=N` (default 12 frames).
- Validated by data: headless values equal the windowed `tools/pose_review.sh` capture
  (s00 and b11 exact, s05 within 0.01 rounding); settle 12 equals settle 60.
- Rule thresholds are constants at the top of `tools/pose_check.py`. They are judgement
  calls; some flags may be too strict (wrist-bend fires on 15 poses).

Checker levels:
- **A (files):** identical / near-identical body blocks, shared timing sets, copied
  weight-shift and turn values, crouch that never changes, fields changed since `HEAD`
  with gameplay fields called out.
- **B (solved pose, per stage):** balance (centre of gravity over the feet), feet
  planted, waist bend, side lean, wrist bend, elbow above shoulder, paddle face at
  contact, hips popping up at contact, arm locked straight, leg fully straight, weight
  transfer wind-up -> finish, shoulder coil, and "lower contact must mean lower hips"
  inside each pose family.
- **C (motion):** path corners, elbow snap / jump, forearm roll step, wrist step,
  elbow-torso clearance, elbow pointing up or tucked in, paddle faster in preparation
  than into contact, shoulders turning after contact, joint pops outside the strike.

Not built yet in stage 0 (do when useful, not blocking):
- Transition table: for ready -> each pose and neighbouring poses, joint travel, paddle
  roll flips over 150 degrees, foot replants.
- Mining the 12 saved `logs/bench_*.pose.jsonl.gz` traces for foot slide and joint pops
  in real play (no new bench run).
- Card view steps: how many 22.5 degree torso / head art steps a swing crosses.

### 3.2 First checker results (2026-11-20, 151 flags)

| Score | Pose | Main problems |
|---|---|---|
| 28 | s17 Mid-low Wide Backhand | Off balance at contact and finish; arm straight all swing (elbow 11/12/8 deg) |
| 40 | s10 Wide Forehand | Off balance (0.35 m off the feet at finish); weight 0.31 > 0.36 > 0.46 |
| 43 | s11 Wide Backhand | Off balance at finish; wrist 128 deg in wind-up; little weight transfer |
| 43 | s16 Mid-low Wide Forehand | Arm straight all swing (elbow 6/6/5 deg) |
| 52 | s01 Forward, s12 Volley Ready | Identical bodies, timing and stage values; wrist bent hard |
| 58 | s13 Mid-low Forehand | Hips 0.56 > 0.78 > 0.64 m (rise 22 cm at contact); face 45 deg off the net |

Across the set: wrist bent hard 15, copied weight-shift / turn values 13, a leg fully
straight at finish 13, paddle faster getting ready than into contact 9, little weight
transfer 9, 10 of 21 strokes share one timing set. This is the starting queue for stage 3.

### 3.3 Facts about the game that the work depends on

**Pose data**
- Stroke: `data/postures/NN_name.tres`, class `PostureDefinition`
  (`scripts/posture_definition.gd`). The `[resource]` block is the contact pose plus
  paddle, zone, charge, follow-through and timing fields. Wind-up and finish are two
  sub-resources (`windup_body`, `follow_through_body`, script
  `scripts/stroke_body_keyframe.gd`) holding a `values = { "field": value }` dictionary
  limited to `FIELDS` in that script. Wind-up / finish paddle placement is stored on the
  main resource as deltas: `charge_paddle_offset`, `charge_paddle_rotation_deg`,
  `ft_paddle_offset`, `ft_paddle_rotation_deg`.
- Body stance: `data/base_poses/NN_name.tres`, class `BasePoseDefinition`, one stage.
- Serves: built in code (`scripts/mobile_serve_pose_store.gd`) and tuned by
  `data/serve_tuning.json` (per style: windup / contact / finish, each with `set` and
  `add`); some fields are locked per stage. Deferred to after stage 6.
- `family`: 0 forehand, 1 backhand, 2 centre, 3 overhead. Several gameplay scripts branch
  on it (`charged_footwork.gd`, `drive_serve_motion.gd`,
  `stroke_preparation_orientation.gd`, `player_arm_ik.gd`).
- Minimal text edits to `.tres`: `tools/pose_set.py` (keeps diffs small; reuse its logic).
- `data/postures_backup/` is an old manual snapshot; nothing reads it.

**Overrides (important)**
- `PostureLibrary` and `BasePoseLibrary` call `MobilePoseStore.apply_overrides`, which
  loads `user://mobile_pose_overrides_v1.json` over the repo files. Serves:
  `user://mobile_serve_pose_overrides_v1.json`. Global grip:
  `user://mobile_paddle_grip_v1.json`.
- This Mac has none of these files (`~/Library/Application Support/Godot/app_userdata/
  Pickleball Game/`), so the Mac game shows the repo poses. The phone may have its own
  saved edits and so show different poses. Ask the user; import before judging the phone.

**Mobile pose editor** (`scripts/ui/mobile_pose_editor.gd`, 1552 lines; helpers
`scripts/ui/mobile_pose_*.gd`). No public API; `pose_shots.gd` already drives its private
members, and the studio does the same.
- Open: `game.open_mobile_pose_editor()`, then `game.mobile_pose_editor` (`ed`).
- Select: `ed._select_workspace(0 strokes | 1 body | 2 serves)`, `ed._select_pose(index
  into ed._definitions)`, `ed._select_stage(0 wind-up | 1 contact | 2 finish)`.
- Edit: `ed._changed(field, value, refresh=true)` is the path the sliders use. It routes
  the value: at stage 1 to the main resource (and freezes the old value into both
  keyframes so wind-up and finish do not shift); at stage 0 / 2 body fields go to the
  keyframe dictionary and paddle position / rotation become the `charge_*` / `ft_*`
  deltas. `ed._set_body_value(descriptor, axis, v)` adds clamping and the foot-plant
  check (`scripts/pose_foot_edit_validator.gd`).
- Scrub: set `ed._progress` (0 wind-up, 0.5 contact, 1 finish) then `ed._refresh_preview()`.
- Real-time timeline: `ed._timeline._seek(0..1)`; `ed._timeline.sequence` has `duration`,
  `prefix_seconds`, `release_seconds`, `stroke_seconds`; `ed._timeline.sample` has
  `progress`, `phase`, `pose`. Options: mode, stance (authored / open / closed), motion
  (runtime / authored keys), speed.
- Play: `ed._toggle_play()`, `ed._play_variant(1 strong | 2 weak)`, `ed._stop()`.
- View: `ed._preview.view("front"|"side"|"back")`, `.zoom(d)`, or set `.yaw`, `.pitch`,
  `.distance` then `.update_camera()`. Ghost count: `ed._ghost_count_changed(n)`.
  `ed._preview.set_arc_visible` / `set_ghosts_visible` exist but the editor never calls
  them.
- Working copies: `ed._copies["stroke:ID" | "base:ID" | "serve:STYLE"]`; erase to reload.
  Also `ed._dirty`, `ed._motion_dirty`, `ed._edit`, `ed._current`, `ed._stage`.
- Save in the editor (`ed._save_current`) writes the `user://` overrides file. The studio
  must NOT use it; the studio writes the `.tres` files.
- Field groups and ranges: `scripts/ui/mobile_pose_fields.gd` (`GROUPS`, `CATEGORIES`,
  `CATEGORY_FIELDS`, `category_fields(i, base)`, `body_input_value`, `axis_label`,
  `WRAPPED_BODY_FIELDS`). Joint -> field mapping for gizmos:
  `scripts/ui/mobile_pose_gizmo_fields.gd` `channels(...)`.
- Preview: `scripts/ui/mobile_pose_preview.gd`, a `TextureRect` owning a `SubViewport`
  ("IsolatedPoseViewport", own world, starts 640x360, follows the control size, renders
  only on change unless `render_target_update_mode = UPDATE_ALWAYS`). Player node
  "IsolatedPreviewPlayer" is a `scripts/player.gd` instance. Frames:
  `ed._preview.viewport.get_texture().get_image()`. The gizmo overlay is drawn on the
  TextureRect, not inside the viewport.
- Pixel cards in the preview: `scripts/player.gd:311` attaches the card rig and the
  paddle skin to every player, and the rig has a branch for `editor_preview_mode`, so the
  preview very likely already shows cards. Verify by data in stage 1 (a `PixelCards_*`
  node exists beside the preview player). An earlier claim in the planning chat that the
  preview shows the classic 3D body was not verified and is probably wrong.
- Headless Godot solves poses but renders nothing: frame streaming needs a window.

**Timing (30 Hz game tick)**
- Drive (forehand): 0.6 s charge (Ready -> wind-up), 0.12 s wind-up -> contact (4 ticks),
  0.28 s sweep. Soft shots: 0.9 s sequence, contact at 0.70 s.

**Movement**
- No authored loops. Feet step procedurally in `scripts/player_leg_ik.gd` from constants
  (`STRIDE_LEN_WALK 0.24`, `STRIDE_LEN_RUN 0.4`, `STEP_DURATION_WALK 0.3`,
  `STEP_DURATION_RUN 0.14`, `STEP_LIFT_HEIGHT 0.035`, `STEP_RUN_LIFT_HEIGHT 0.065`,
  `RUN_ENTER_SPEED 1.65`). Gait choice: `scripts/footwork_motion_state.gd`. The body holds
  one of the 22 stance poses.
- Between points: `scripts/between_point_controller.gd` (walk 2.4 m/s, run 4.4, generated
  pick-up bend 0.42 s down / 0.42 s up, pass / catch). Owned by the other session.
- No celebration, mood or reaction code exists.

**Look**
- Pixel cards: `scripts/graphics/pixel_card_rig.gd`. Body, torso and head art pick one of
  16 views (22.5 degree steps, with hysteresis); limbs are cards stretched between joints
  and follow them continuously. Twist edits under about 11 degrees may not change torso
  art; edits that move joints show most.
- The card baker (`tools/bake_pixel_cards.py`) draws faces (eyes, brows, mouth), so face
  variants for reactions are possible with a baker extension.
- Wrist lag already exists as a simulated loose wrist in
  `scripts/graphics/paddle_skin.gd` (`_wrist_lag`, constants `LAG_HZ_*`, `LAG_ZETA_*`,
  `LAG_GRAVITY`): visual only. Do not add pose-level lag on top of it.

**Roadmap** (`docs/ROADMAP.md`): gameplay is locked and asks for an `IDENTICAL` bench per
change. The user has decided pose refinement goes ahead without the bench (section 6).
The studio is tooling and is not on the roadmap yet; add a short entry when stage 1 lands.

## 4. Architecture

```
Desktop Pose Studio (Godot window, full screen)                     Python (stdlib), no server
  scripts/studio/*.gd  -- reuses the mobile editor engine -->       tools/pose_studio/tres_edit.py  (.tres text writer)
  big 3D preview + gizmos, fields, timeline, notes, ratings  --->   tools/pose_studio/store.py      (notes, versions, ratings, queue)
  scripts/debug/pose_studio_link.gd (TCP 127.0.0.1:8766) <-- Claude tools/pose_notes.py             (CLI for Claude and for Godot)
```

- **Launcher:** `tools/pose_studio.sh` starts Godot windowed, full screen, with
  `-- --pose-studio=8766`. That flag opens the Desktop Pose Studio instead of the title
  flow, skips `user://` pose overrides (`MobilePoseStore.skip_overrides`), and starts the
  TCP link.
- **Editor engine reuse:** the studio creates the existing `mobile_pose_editor.gd` as a
  hidden engine (its own phone UI not shown) and drives it the way
  `pose_studio_link.gd` / `pose_shots.gd` already do (`_select_pose`, `_select_stage`,
  `_changed`, `_set_body_value`, `_timeline`, `_preview`). Its preview control (with the
  existing 3D gizmo `mobile_pose_gizmo.gd`, orbit, zoom, ghosts, arc, contact box) is moved
  into the studio's large centre area. No pose maths is duplicated.
- **TCP link stays** for Claude: drive and check the studio by data (metrics, fields,
  diff) without screenshots. Same protocol, `tools/pose_studio/PROTOCOL.md` section 1.
  Link and UI act on the same engine, so a link `set` shows in the UI and vice versa.
- **Saving:** Godot computes the diff (link `diff` logic: `{stage, field, text}` per file
  section) and runs `python3 tools/pose_notes.py save <key> --changes <json file> -m "..."
  --author user` (OS.execute, Mac only). That applies minimal text edits with
  `tres_edit.py`, writes a version, and Godot reloads the pose ignoring the resource cache.
  Never `ResourceSaver`, never the editor's own `_save_current`.
- **Notes, ratings, versions** in the studio: read the JSON in `pose_studio/` directly
  (GDScript JSON parse); every write goes through `tools/pose_notes.py` so there is one
  writer with the file lock.
- **Dropped with the browser:** `tools/pose_studio/server.py`, `tools/pose_studio/web/`,
  the HTTP part of PROTOCOL.md. `bench.py` stays as a CLI (`--json`) the studio's Bench
  tab reads. The PDF opens with `OS.shell_open`.
- **Storage** in `pose_studio/` at the repo root with a `.gdignore` file so Godot never
  imports or ships it; committed to git (user decision):
  - `pose_studio/notes/<key>.json`: list of notes.
  - `pose_studio/versions/<key>/v003.tres` plus `v003.json`.
  - `pose_studio/ratings.json`: append-only rating log.
  - `pose_studio/changelog.json`: generated; a copy is bundled for the phone in stage 5.

Note record:
```json
{"id": "n12", "pose": "s13", "kind": "request", "stage": "contact", "field": null, "time": null,
 "author": "user", "text": "hips rise at contact", "status": "open",
 "created": "2026-11-20T10:00:00", "created_version": 3,
 "reply": {"author": "claude", "text": "...", "changes": [{"stage": "contact", "field": "crouch_amount", "from": "0.074", "to": "0.3"}],
           "evidence": "hip 0.78 -> 0.58 m; flag B_pop_up cleared", "version": 4}}
```
`kind`: `request` (one-off; status `open` -> `addressed` -> `verified` or `reopened`) or
`rule` (standing check; may name a checker flag id or a metric with a limit, evaluated
automatically on every checker run).

Rating record, appended to `pose_studio/ratings.json` (a log, never rewritten):
```json
{"pose": "s13", "version": 4, "stars": 3, "aspects": {"body": 2, "arm": 4, "motion": 3, "timing": 4},
 "by": "user", "source": "studio", "time": "2026-11-20T10:05:00", "notes": ["n12"], "comment": "better, still stiff"}
```

Version record: `{"n": 4, "author": "user"|"claude", "message": "...", "time": "...",
"notes": ["n12"], "score": 70, "flags": ["B_wrist_contact"], "approved": false}`.
Version 0 of each pose is `git show HEAD:<file>`; version 1 is the working copy at first
studio start.

### 4.1 Human rating system

The user's stars are the measure of success; the checker score is only a helper.

- **Scale:** 1 to 5 stars per pose, given by the user only. 5 = ship it, 4 = good with a
  small nit, 3 = acceptable but off, 2 = clearly wrong, 1 = broken. Optional aspect stars
  (body, arm and paddle, motion, timing) to say where the problem is.
- **Covers every pose type:** strokes, body stances, serves, and later movement and
  reactions. Each type has its own progress count.
- **A rating belongs to a version.** When a pose gets a new version, its last rating is
  shown as "stale, rate again"; only ratings on the current version count toward the
  target.
- **Works with notes.** Rating below 5 prompts for a note (or links existing open notes)
  so every missing star has a stated reason. A note marked verified suggests re-rating.
- **Log:** every rating is appended to `pose_studio/ratings.json`; nothing is overwritten,
  so progress over time can be shown.
- **Queue for Claude:** poses ordered by current stars (lowest first), then unrated, then
  stale; inside a pose, open notes first, then checker flags. `tools/pose_notes.py queue`
  prints it.
- **Claude's loop per pose:** read rating, aspects and notes -> checker baseline -> edit
  -> checker diff -> save version with evidence -> reply on notes -> pose shows as
  "improved, waiting for your rating". Claude never sets or guesses stars.
- **Calibrating the checker:** on each run compare stars with checker scores. A 5-star
  pose with flags means a rule is too strict (list it for loosening). A pose at 3 or
  below with no flags and no note means a rule is missing (ask the user what is wrong).
- **Progress view:** per pose type, a bar of star counts, the share at 5 stars against the
  target, and a history line from the log. Also in the phone change log.

### 4.2 Desktop UI

Style rules for the studio window (`scripts/studio/studio_theme.gd` holds the numbers).
- **Units and grid:** UI points (window pixels / screen scale). 4 pt grid; spacing scale
  4 / 8 / 12 / 16: 4 inside a group, 8 between controls and around panels, 12 between
  groups, 16 around overlays. Minimum target 28 pt tall (buttons, fields, scrub track).
- **Fonts:** body 15 (fields, lists, buttons), small 13 (keys, units, hints, badges),
  header 16 (panel and group titles). No other sizes.
- **Colour roles** (`scripts/ui/game_ui_theme.gd`): PANEL background, SURFACE controls,
  BORDER lines, INK text, MUTED secondary text, ACCENT green only for an active state
  (pressed toggle, selected tab, current item), BLUE for the primary action (Save), RED
  for unsaved and errors. Stage colours stay: purple wind-up, gold contact, cyan finish.
- **Button kinds:** primary (Save: blue fill, dark text, one per window); standard
  (SURFACE fill, 1 pt border); toolbar toggle (flat; pressed = accent-tinted fill and accent
  text); icon button (28 x 28, flat, tooltip names the action and its key).
- **Layout:** top bar (title, workspace, pose | right: undo/redo, message, Save, Revert,
  PDF, ?, link pill); below, HSplit pose list (~240) | viewport | inspector (~420 at 1920),
  and a VSplit inspector fields / panel tabs. Split sizes persist in
  `user://pose_studio_layout.cfg`. The viewport has a segmented toolbar above, a status
  pill inside its bottom-left corner and the timeline (controls row + scrub track with
  stage markers) below. Window minimum 1280 x 760; nothing clips from 1280 x 800 up.

## 5. Stages

Each stage: build, check by data, update this file's status line, tell the user in a few
plain lines what works and what was not verified.

### Stage 0. Pose checker: DONE (see 3.1)

### Stage 1. Studio core
Build:
1. `scripts/studio/` desktop editor (full screen, desktop layout: pose list left, large
   3D preview centre with gizmos and orbit, timeline under it, fields right, metrics /
   notes / ratings / versions / bench as tabs), `scripts/debug/pose_studio_link.gd`, hook
   in `perf_monitor.gd`, `tools/pose_studio.sh`. Mouse + keyboard first: Blender-style
   camera: left-drag on empty space or middle-drag orbit, Shift+drag pan, wheel / pinch zoom, trackpad two-finger
   orbit, 1 / 3 / 7 views, F frame; left-click on a joint dot / gizmo handle edits instead,
   W / E to switch gizmo move / rotate, click a joint in the preview to select it,
   Space play, comma / period step one tick, Cmd+Z / Shift+Cmd+Z, Cmd+S save.
2. Pose list (strokes, body stances) with badges: unsaved, checker score.
3. Live preview, stage buttons, scrubber, play, loop, slow motion (1x, 1/2, 1/4),
   strong / weak backswing, step one game tick.
4. Fields grouped as in the mobile editor. Each numeric field: slider + typed value +
   arrow-key nudge + fine step (Shift = 0.1x). Track ticks for wind-up / contact / finish
   and last saved. Per-field reset. Hold-to-compare (shows saved value while held).
   Vector fields as three rows labelled forehand side / up / toward net. Angles that wrap
   use `WRAPPED_BODY_FIELDS`. Gameplay fields (`GAMEPLAY` list in `tools/pose_check.py`)
   carry a lock icon. When the foot-plant check stops an edit, show where it stopped.
5. Toggles: ghost count, motion arc, contact box, front / side / back, two views side by
   side.
6. Undo / redo (one drag = one step). Click a joint name to jump to its fields.
7. Metrics panel: live `metrics` plus this pose's checker flags.
8. Save (text edits to `.tres`), revert.
9. Bench page: every `logs/bench_*.perf.jsonl` run with points, how they ended, endings
   per 100 shots, top systems, spikes, jitter (reuse the logic in `tools/perf_report.py`
   and `tools/shot_report.py`); compare two runs; show the pose-diff verdict from
   `tools/pose_diff.py`. It reads existing logs only; no button that starts a bench.
10. PDF link in the nav: serves `docs/PICKLEBALL_2.5D_PROPOSAL.pdf`.

Check by data:
- Writer round trip: change one field through the studio, save, and `git diff` shows only
  that line; save with no change leaves the file byte-identical.
- `metrics` from the link equals `logs/pose_check/raw/<key>_now.json` for the same pose
  and stage.
- After `set`, the `fields` reply shows the new value and `metrics` changes; after undo
  both return.
- `frame` returns a JPEG whose bytes change after a `set`, and a `PixelCards_*` node
  exists in the preview world.
- UI checks by data: a debug dump of the studio's control tree (names, values, visibility) through the link, never screenshots.
- Ask the user to look once: does the preview look like the game (cards, paddle)?

### Stage 2. Notes, versions, compare
Build: the rating system in 4.1 (star control with optional aspects on every pose, the
log, stale marking, queue, progress view); notes UI (two kinds, pins to stage / field / scrubber time), status flow, Claude
reply block; a version on every save; restore; diff two versions (field table);
A/B compare (toggle or ghost of another version or `HEAD`); mark approved; changelog;
`tools/pose_notes.py` for Claude: `list --open`, `show <id>`, `reply <id> ...`,
`version <key> -m ...`, `queue`, `ratings`.
Check: a rating is stored against the current version and turns stale after the next
save; the queue order follows 4.1; note and version files parse and match the schema; restoring a version gives a
byte-identical `.tres`; the diff of two versions equals the edits made.

### Stage 3. Refinement loop (the actual goal; needs rule 4 resolved first)
Work the queue from 4.1 (lowest stars first) until the 5-star target is met.
Loop per batch: `pose_check.py --solve --baseline` -> edit (user in the studio, or Claude
with `tools/pose_set.py`) -> `--solve --diff` -> save a version with the evidence -> reply
on the notes. Start from the queue in 3.2 plus the user's notes. State which gameplay
fields changed. Runs alongside all later stages.

### Stage 4. Motion analysis and richer controls
- Motion graphs under the timeline from the `timed` capture: paddle height, paddle
  speed, elbow bend, forearm roll, hip-shoulder separation; flags on snaps; overlay a
  version or variation; click a flag to jump there.
- Transition preview (pose -> pose blend) and the transition table.
- Timing fields as draggable timeline segments (gameplay fields: lock icon).
- Wrist lag tuner for the constants in `scripts/graphics/paddle_skin.gd`.
- Variation plays: strong / weak, charge level slider, A/B ghosted.
- Duplication: copy stage or pose, draft (sandbox) poses that never enter the game until
  promoted onto a real pose, mirror one limb group, apply a change to all three stages.
Check: graph data equals the capture JSON; tuner values round-trip to the file.

### Stage 5. Phone
- Pose player (play, scrub, loop, slow, views, ghosts, variations), notes, change log.
- Star rating in the pose player (same log, `"source": "phone"`), sent with the notes.
- "Flag this moment" during play: records pose, stage and game situation as a note.
- Notes reach the studio over Wi-Fi with a pairing code; fallback copy / paste text.
- One-time import of saved phone edits as versions; then the game stops loading pose
  overrides; the editor entry on the phone is hidden (its preview code stays; the studio
  uses it on the Mac).
- Build and install steps are in the user's memory note "iPhone build and install".
Check: imported overrides equal the source JSON; a note makes the round trip.

### Stage 6. Drag gizmos
Already partly there: the desktop studio reuses the 3D gizmo (`mobile_pose_gizmo.gd`). This stage
adds desktop polish: move /
rotate; elbow and knee swivel arcs instead of raw pole values; reach-limit warning;
draggable wind-up / finish points on the swing arc. Use the `channels(...)` mapping.
Check: a drag of known size changes the expected field by the expected amount.

### Stage 6b. AutoPose (full-body posing, Blender "Blaze AutoPose" style). Decided 2026-11-20
User rule: **posing changes the animation only, never gameplay.** The studio does the dirty work
so the game looks right while playing exactly the same.
- Handles: hands, paddle tip, elbows, knees, feet, hips, chest, head. Dragging one moves it to the
  mouse and the body adapts in order: arm first, then shoulders / chest turn, torso lean, then hips
  shift and knees bend. Feet pinned by default (never slide).
- The solver changes animation fields only (body, torso, head, arm guides, knee guides, wind-up /
  finish paddle offsets). It never changes gameplay fields (`GAMEPLAY` in `tools/pose_check.py`:
  contact paddle position, zones, floor clearance, timing). At Contact the paddle (contact point) is
  always pinned; moving it needs an explicit "Gameplay edit" unlock with a warning. The same lock
  applies to the right-hand / paddle-tip gizmos at Contact.
- Elbow handle carries the chain: dragging the elbow moves it to the mouse with the forearm, hand
  and paddle travelling along (their relation to the elbow kept), and the chest / shoulders turn and
  lean to follow. At Contact the paddle is pinned, so there the elbow drag re-shapes the arm and
  torso around the fixed paddle instead (elbow and body move, hand and paddle stay).
- Pins ("Freeze"): lock icon on any handle; pinned handles hold while others are dragged.
  Built 2026-11-20: the lock sits up-right of a handle (shown when pinned, on hover otherwise);
  click it, or Alt+click the handle. Defaults: both feet; at Contact the paddle hand and tip show
  pinned and unpin only with Gameplay edit on (then a drag may move the contact point; Gameplay
  edit off pins it again). Bar "Pins: n" (tooltip lists them) and Reset pins. A pinned paddle
  hand / tip turns elbow carry off (the elbow reshapes around it).
- Stiffness slider ("Drag sensitivity"), optionally per region (arm, chest, hips, legs).
  Built: AutoPose bar Stiffness (all, 0.25x..4x, double-click = 1.0x) and Regions: Arms (arm +
  paddle), Torso (chest + head), Legs (hips, knees, feet). A hand / paddle-tip drag pulls the
  shoulder along a little (body follow, weight 0.15 x All x Arms), so Arms up = the body follows
  more, Torso / Legs up = that part moves less. Tuned 1.0x (hips 16, legs 8 base): a 15 cm hand
  drag (45 drags, 9 keys) moves the chest 4.1 cm (median), the hips 1.0 cm, the feet 0;
  44 / 45 within 1 cm of the mouse.
- Head looks at the ball / contact point by default (toggle). Built: bar "Look at ball" (on):
  after each drag move and after Relax the head turn / tilt fields aim the head at the preview's
  ball at this key (wind-up: the incoming ball 1.65 m out along the face, contact: the contact
  point, finish: the outgoing ball 1.8 m toward the net; the game's gaze limits). Body stances
  have no ball (off there). A drag then also writes the two head fields at that key.
- Balance (centre of gravity over the feet) is a soft goal while dragging (bar Balance, on) and
  enforced by Relax.
- Relax (built: bar Relax, link `autopose {relax}`): one undo step at this key; fields both arms,
  chest, hips, knee guides (head by look-at); goals with a margin inside the checker (balance 9 cm,
  knees >= 25 deg, lean <= 32 / 18 deg, swung strokes: paddle elbow >= 18 deg, wrist flex <= 52 /
  angle <= 96, elbow <= 2 cm over the shoulder, no pop-up (hips <= 7 cm over both other keys,
  from the motion samples), wind-up coil >= 12 deg); a step never raises a checker flag that was
  not there; pins and gameplay fields held; finite differences with a wider probe where the
  engine has a dead zone (crouch does nothing until it passes the legs' reach clamp). Not
  handled: cross-key rules (weight transfer), level C (swing). Before / after (level B on link
  metrics, in memory, never saved): s00 97 -> 100, b11 97 -> 100, s10 64 -> 82, s17 52 -> 67,
  s16 76 -> 82, no new flags. (Planned as "Start fresh": re-settle with pins held by the checker
  rules: balance, no locked leg, wrist bend, hips not popping up at contact.)
- Method: no new rig maths. Damped least squares over the pose fields, measuring joint positions
  from the game's own IK solve (finite differences), clamped by field ranges and the foot-plant
  check. One drag = one undo step. First build step: measure solve cost per mouse move; fallback is
  arm live during the drag and body settling on release.
- Prototype solver rules (`scripts/studio/autopose_solver.gd`, link `autopose`): evaluations are
  pure (the rig's float noise in the arm pivots and foot mesh is reset first), so the same drag
  replays identically; a field at a one-sided limit is held, never stalls the step; balance on =
  the centre of gravity never ends further off the ankle line than max(5 cm, where the drag
  started) (+0.5 mm), so a drag that needs more stops there (turn balance off to allow it); arm
  reach (the engine's torso-turn check) is soft and only while the torso turn is free, with no
  pull on an arm that is already fully stretched. Tip aim (paddle tip drag): a mouse held still
  settles the tip on the mouse and then stays (no creep); a 1 px move turns the paddle under 1
  degree (0.9 degree per pixel for moves under 3 px).
- Drag UI (built 2026-11-20, `scripts/studio/studio_viewport.gd`): an **AutoPose mode** (toolbar
  AutoPose, key P) rather than mixing with the joint dots: in it the joint dots, the paddle tip
  diamond and the gizmo are replaced by AutoPose handles (rings: arm blue, legs green, hips / chest /
  head violet, paddle tip an orange diamond ring, grey with a slash = locked); out of it the joint
  dots, the right-hand XYZ gizmo and tip aim work exactly as before. Left-drag a handle: it follows
  the mouse in the camera-facing plane through it (grabbed where pressed, no jump), Shift held =
  mouse up / down pushes it away from / pulls it toward the camera; the body follows live (solver
  per mouse move, 6 ms budget; only motion with the left button held moves it). Release = one undo
  step; Esc or a right-click during the drag cancels back to the pose before it; a stage / pose
  switch or play mid-drag keeps the drag as one undo step on the key it began on. The AutoPose bar
  (under the view toolbar, shown in the mode): Balance (on by default) = the solver's balance
  option, Look at ball, Stiffness (+ Regions), Pins, Relax (below). At Contact the paddle hand and tip handles are
  locked (Gameplay edit does not unlock them: AutoPose only changes animation; the hand gizmo moves
  the contact point with Gameplay edit on). A handle no animation field can move at that pose (a
  body stance's paddle hand) refuses the drag with a status message. Commit: when the engine's
  foot-plant / reach check would stop a field, the largest fraction of the drag that passes is
  kept instead (status says how much), so the committed pose is always one between the start and
  what the drag showed. Elbow carry at wind-up / finish keeps hand - elbow and tip - elbow as at
  grab, so forearm, hand and paddle go with the elbow as far as it really goes (the chest
  follows); at Contact the paddle stays and the arm and torso reshape around it. Hint pill and
  help overlay list the controls; link `autopose_handles` and `mouse {handle}` drive it for tests.

### Stage 6c. Queue after AutoPose (agreed with the user 2026-11-20 evening)
Where it stopped: the AutoPose handles and bar were built, then QA was cut off halfway when
the user ended the day. Neither QA reviewer reported; the fix and recheck passes did not run.
Pose files matched the backup; nothing committed. Run in this order (each step edits
`autopose_solver.gd`, `pose_studio.gd`, `studio_viewport.gd`, so one builder at a time):
1. **QA of AutoPose (done 2026-11-21, see status table).** Two reviewers (correctness of solver + handles; controls / UX by link
   data), then fix and recheck. Known open items from the solver step: balance guard stops
   hips / foot / torso drags short on s10, s16, s17 (they start 12-16 cm off the feet);
   balance may worsen up to +1.9 cm inside the 5 cm zone (b11) — ask the user whether
   "never worse than the start" is wanted; s17 contact torso-turn refusal 1 / 48; s16 slow
   end 8.2 ms (target 8).
2. **Elbow swivel (user: "the arm is sometimes bent inwards", 2026-11-21).** Checker data:
   elbow jumps 0.3-0.55 m in one tick on s00, s03, s04, s10, s11; tucked in all swing on
   s00, s05, s06, s07, s13, s14. Likely causes (from code, trace per pose first): (a) the
   authored pole is player-relative (`stance_offset` with forehand / forward axes), so it
   does not turn with the torso; (b) `ArmAnatomy.conditioned_pole` (`scripts/arm_anatomy.gd`)
   turns the bend plane toward the hand by up to 135 deg after the authored pole, so the
   edit is overridden; (c) `PostureDefinition.blend_elbow_pole` lerps pole points, and
   opposite poles pass near the shoulder-wrist axis, where the bend plane flips.
   Decision: no FK (the hand must stay on the gameplay paddle); control the one free IK
   value, the swivel angle around the shoulder-wrist line.
   Traced 2026-11-21 (`pose_data.gd` now captures the authored pole, the stabilized and the
   wrist-conditioned pole per tick; replay matches the solved elbow on 535 / 535 bent-arm
   frames within 5 deg). Checker rule `C_elbow_flip` (> 30 deg swivel per tick with the elbow
   > 8 cm off the shoulder-wrist line) flags s00, s02, s03, s04, s08, s10, s17. Cause: almost
   always the game's wrist conditioning (`ArmAnatomy.conditioned_pole`, up to 135 deg, blend
   by hand bend 42-90 deg): the authored pole moves 1-34 deg on those ticks while the elbow
   swings 31-177 deg. The blend itself flips only on s10 (0.93 s) and partly s00 / s03 / s04 /
   s08. Stabilize does almost nothing. On average the shown elbow is 24-79 deg away from the
   authored pole on s00, s02, s03, s04, s07, s14, s15, s17, so editing the pole field feels
   loose. Not measured: `LiveArmBudget` (re-picks the elbow among 72 candidates in real play;
   off in the editor preview), so the game may differ from the studio there too.
   Swivel ranges in use (bent frames, 0 = down, + = out from the body; backhands need their
   own reference): s13 -20..51, s01 -20..32, s12 -20..36, s05 -51..13 (no flips); s00 -111..103,
   s08 -101..145 (flips). Limits wait until the user marks poses that look right.
   User 2026-11-21: the elbow matters more than the wrist in 2.5D; remove the wrist correction
   so elbow controls work. Experiment switch `PlayerArmIk.paddle_elbow_wrist_correction`
   (default true = game unchanged; `pose_check.py --solve --elbow-authored` turns it off).
   Off, as the poses are today: stroke flips 6 -> 4 poses (s02, s17 fixed; s00, s03, s04, s10
   left, all from the authored blend, 74-92 deg instead of 145-177); but keys move (elbow up to
   58-59 cm on s00 / s10 finish, 54 on s03 wind-up), elbow-torso clearance flags 1 -> 5, joint
   pops 5 -> 11, wrist flags 11 -> 15. The authored poles were tuned with the correction on.
   So removal needs, in order: (a) bake: write each key's shown elbow into its authored pole
   (keys look as today), (b) blend the pole as a chest-relative swivel angle (no blend flips),
   (c) then turn the correction off; bench once for (b) + (c). Serves v00-v06 flip in their
   blend either way (built in code; deferred).
   Tried 2026-11-21, then rolled back (game and pose files exactly as before: 50 / 50 poses,
   0 cm, same checker flags):
   - (a) Bake works: studio `elbow_bake()` / link `elbow {bake}` writes the shown elbow into the
     key's pole (shoulder rotation undone); with the correction off every key of 21 strokes and
     22 stances matched within 0.1 cm. The baked files were saved as studio versions
     (`pose_studio/versions/*`), then replaced by the backup; the versions stay as history.
   - (b) Turning the elbow around the arm between two fixed end poles does not work: on big
     swings the arm line sweeps past the end poles (s04: the start pole goes -83 -> +10 deg
     around the arm in three ticks), so the swivel still jumps 100-175 deg (s00, s02, s03, s04).
   - Correction off globally also breaks serves (built in code, not baked): r_elbow jumps
     0.60 m at 0.33 s on v00-v06. s10's finish flip is a pose problem (hand passes 8 cm from the
     shoulder, arm folded; the game's stabilizer swings the elbow).
   BUILT 2026-11-21 (user OK; "correct poses as you go, make them natural"):
   - Fields `right_elbow_swivel_deg`, `left_elbow_swivel_deg`, `elbow_swivel_weight` on strokes,
     stances and wind-up / finish keys (PostureDefinition, BasePoseDefinition, keyframe FIELDS,
     MobilePoseStore, inspector "Arms & elbow guides"). Maths in `scripts/elbow_swivel.gd`:
     0 = elbow down for an arm pointing forward-and-out, follows the arm by the smallest
     rotation and the chest by the pose's yaw; + = out from the body. Blend: angles lerp; a
     blend with a weight-0 pose (serves, code-built poses) uses weight 0, so it plays as before.
   - VISUAL ONLY: the solved arm (what gameplay reads: reach body shift, clearance, reach
     profiles) keeps the guide-point elbow; the arm IK records the turn to the swivel elbow
     (`ElbowSwivel.record_visual_turn`) and the pixel cards draw the elbow turned by it
     (interpolated). Bench seed 1, 60 s: IDENTICAL to swivel off (A/B with
     `PICKLEBALL_ELBOW_SWIVEL=0`). Classic 3D bodies do not show it. Studio metrics, AutoPose
     (new param: the swivel), preview joint dots and the checker capture read the drawn elbow.
   - Bake: all 21 strokes and 22 stances, swivel from the shown elbow (studio link
     `elbow {swivel}`), weight 1; every key unchanged (0 cm), serves unchanged (0 cm).
   - Checker vs before: stroke elbow flips 7 -> 3 poses (s03, s04, s08, s17 fixed; s00 145 ->
     48 deg, s02 65 -> 42), pops 5 -> 4, forearm-roll and wrist-step flags gone, total score
     4133 -> 4184. Flip rule now also needs a real elbow jump (> 12 cm; the angle is unreliable
     where the arm points straight down).
   - Left: s10 (hand passes 7 cm from the shoulder in the charge and the finish: the drive
     code's paddle path, gameplay, so not a posing fix; ask the user), s00 / s02 (fast strike,
     probably natural; user to judge). Wrist correction switch stays default on.
   - FOUND: for dinks, volleys, drops and smashes (and charge <= 0.58 or height tier <= 1)
     `drive_serve_motion.gd` builds wind-up and finish from the CONTACT pose and ignores the
     authored keys; only full-charge drives use the authored wind-up / finish (plus code
     changes by strength). Studio edits to wind-up / finish keys do not reach those shots.
     Measured 2026-11-21 (two 2-minute AI matches, seeds 1 and 2, calls of drive_definition by
     path): DINK 139 / 223, DROP 348 / 105, SMASH 32 / 21, VOLLEY 22 / 0, two-hand backhand
     30 / 31, full-charge DRIVE 0 / 0, tactical profiles 0 / 0. In AI play the authored wind-up
     and finish keys are never used. Compact shots: contact pose with the paddle 7.5-13 cm back
     (wind-up) and 1.5-13 cm forward (finish), body nearly still; smashes: fixed numbers in code.
     The swing keys are read by the AI brain, incoming-contact planner and reach systems, so a
     paddle-path change is likely gameplay; a body-only change may not be (bench decides).
     Tried 2026-11-21 (user chose "body only, scaled": dink 40 %, drop 35 %, volley 20 % of the
     authored wind-up / finish body: turns, leans, spine, shoulder, crouch, weight, head, elbow
     swivel; feet, body position and paddle path untouched). Bench seed 1 vs before: paddle
     differs from tick 70, ball from tick 75, feet from 129. Cause: the paddle head is clamped
     to reach from the SHOULDER (`StrokeSwingPath.world_transform` -> `PaddleReach.clamp_head_with_floor`
     with `BodyPose.shoulder_world`), and the arm reach shift moves bodies. Any body change is
     gameplay. Reverted. Needs the visual-only body layer (stage 8) first: cards drawn from a
     display-only solve, the gameplay skeleton untouched. Cost reference: posing 4 players is
     ~1.4 ms / frame on the Mac today (legs 1.1, arms 0.3).
   - Studio (no game change): swivel arc handle on each elbow (0 = down, + = out) that
     writes the pole field; ghost of the effective elbow after the game's conditioning,
     warning when it differs from the authored one; checker rule for flips between keys
     (sampled blend), reported per transition.
   - Game (animation only; ask the user before; needs a bench since arm meshes sit under
     the scanned body): pole relative to the chest and blended as an angle, so it turns
     with the torso and cannot cross the flip point.
   - Rotation limits (user asked 2026-11-21): soft limits (ease in over the last 10-15
     deg, not a hard clamp) on elbow swivel, wrist bend, forearm roll, and elbow above /
     behind the shoulder. Ranges measured from the poses that look right, shown to the
     user before enforcing. Studio: allowed range on the arc, drags / Relax respect it,
     checker flags keys and blend samples outside it. Game: same clamp on the blended
     swivel, part of the game step above (cost: one smoothstep per arm per frame).
3. **User tries it** (Pose Studio app in `~/Applications`). Collect notes before building on.
4. **More handles.** Paddle side dots (rim, one per edge): drag rolls the face around the
   grip; wrist turns first, then forearm / elbow; locked at Contact unless Gameplay edit.
   Shoulder dots: twist / tilt / lean the upper body (`torso_yaw_deg`, `torso_roll_deg`,
   `torso_pitch_deg`), hips and feet held; check whether any shoulder-shrug field exists,
   do not invent one. Hip dots or ring: `hip_yaw_deg`, feet planted, show hip-shoulder
   separation live. Head arrow, shown only when the head is selected: aims
   `head_yaw_deg` / `head_pitch_deg` and turns look-at-ball off for that key.
5. **Clipping.** Body capsules (chest, belly, thighs) + head sphere from the solved joints;
   arm segments (upper arm, forearm, hand, paddle) keep >= ~3 cm in the solver (one-sided
   term) and in Relax. Transitions: read the game's blend first, sample ~10 points per
   transition, report the smallest gap; fix via the elbow pole on the keys. Ready on the
   timeline (shared pose: warning, own undo) and a Pass-around point between Ready and
   Wind-up, preferably written as an existing baked elbow path
   (`scripts/elbow_preset_runtime.gd`; read-only check first). Clearance per key and per
   transition in the metrics panel and in `tools/pose_check.py`. The in-game live check
   (`scripts/live_ready_clearance.gd`) stays; only measure its frame cost; switching it off
   is a gameplay change: ask the user, and that one needs a bench.
6. **Game-view preview and slow-motion loop.** Toggle (and small always-on inset) showing
   the pose through the game camera as the pixel card; loop Ready -> Wind-up -> Contact ->
   Finish at 0.25x / 0.5x / 1x with the game's blend, clearance shown along the way.
Later, not queued: reference image overlay, mirror forehand -> backhand animation,
copy / paste a key across poses ("paste as change"), A/B snapshots.

### Stage 6d. Contact points in AutoPose and serves in the studio (built 2026-11-21, user asked; no bench by user decision)
- Contact points: with Gameplay edit on, the Contact paddle hand and paddle-tip handles are free
  (re-pin with their lock). Dragging one of them moves the contact point (paddle position and face
  fields, gameplay); dragging any other handle keeps the paddle fixed and reshapes the body.
  Checked by link on s13 / s00 / s05: hand and tip within 1 mm of the mouse, other handles
  0 mm paddle drift; Gameplay edit off locks them again.
- Serves: workspace "Serves" (keys v00-v06). The diff is against the code-built serve plus
  `data/serve_tuning.json`; Save writes each changed field as a "set" value in its stage of that
  file (`tools/pose_studio/serve_tuning.py`, which also removes an "add" for the same field);
  charge_* go to windup, ft_* to finish; no versions for serves yet. Checked by link: serves open
  with 0 changes, a wind-up and a finish edit save, the diff is empty after save and reselect.
- Fixed in `scripts/mobile_serve_pose_store.gd`: `packaged_default` shared the wind-up / finish
  key values with the cached code default, so tuning "add" values piled up on every rebuild and
  editor edits leaked into the cache. Each copy now owns its key values. May change how serves
  look in game if a rebuild happened during play (not measured; no bench by user decision).

### Stage 7. Backhand-face variation of the front poses
Poses s01 Forward, s15 Mid-low Forward, s06 Low Forward (ask about s12 Volley Ready).
Paddle rolled 180 degrees so the backhand face meets the ball; same contact point and
commit zone; own arm, grip, wind-up and finish values; stored on the same pose, family
stays centre. Order:
1. Read-only: what gameplay reads from the paddle face
   (`scripts/shot_contact_quality.gd`, `scripts/match_contact_authority.gd`), how a centre
   pose is chosen, whether the turn is best expressed as paddle roll or grip rotation.
2. Draft in the studio (no game change); check the forearm roll graph for a spin through
   the ball when blending from Ready.
3. User approves the look.
4. Rule for when the game uses it (recommended: ball on the backhand side of the body's
   centre line), hookup behind a setting.
5. Extend to the other poses.

Step 1 findings (read-only, 2026-11-21):
- The contact face normal is geometric: from the touched paddle triangle toward the ball
  (`player_surface_history.gd:124,170`). There is no forehand / backhand face sign anywhere, so
  a 180 degree roll just makes the other face the hitting face. `contact_launch`
  (`match_contact_authority.gd:1354`) and `shot_contact_quality.gd:9-11` are unaffected.
- Centre pose choice: human `posture_commit_selector.gd:121` scores by `local_lat` (signed
  offset along the forehand axis, + = forehand side) and height; AI `player_ai_brain.gd:496`.
  The sign of `local_lat` is the natural input for the step 4 rule.
- Use `paddle_roll_base_deg` (`posture_definition.gd:53`), not grip: it rolls the paddle in
  world space and keeps the contact point; grip moves the hand seat. Current bases: s01 0,
  s15 115, s06 180 (already backhand face, so its variant is about 0), s12 -30. Wind-up and
  finish need their own `charge_paddle_rotation_deg` / `ft_paddle_rotation_deg` and keys.
- No pose can hold a variant today (one `.tres` per id, `posture_library.gd:54`). Needed: an
  optional override block on `PostureDefinition` (roll, grip, arm fields, wind-up and finish
  keys), a resolver at selection behind a setting, studio handling, and a check that
  `MobilePoseStore` overrides carry it.
- Real risk: the blend from Ready sweeping the head through the ball (step 2 roll graph).

Variant data built 2026-11-21: `PostureDefinition.backhand_face_variant` (field -> value
overrides) and `backhand_face_def()` (cached copy with them applied; unknown fields warn and are
skipped). No pose has one yet and nothing in the game reads it. Bench seed 1, 40 s: IDENTICAL.
Next: step 2, draft s01 in the studio (needs a studio toggle to show and edit the variant).

### Stage 8. Visual-only body layer (design note first)
Cards follow their own copy of the pose, as the paddle skin does for the paddle, so idle
motion, arm swing and reactions never move gameplay meshes. Stages 9 and 10 depend on it.

Design note (2026-11-21, from a read-only audit):
- Today the card rig (`pixel_card_rig.gd`, a sibling node, priority 1000) reads interpolated
  pivot transforms of torso, head, hips, arm and leg pivots. Every read goes through `_xf()` /
  `_pos()` (:404-413); `_pos()` already bends the elbow for drawing only (`elbow_visual_turn`).
- The paddle skin (`paddle_skin.gd:164-254`) is the pattern: read the interpolated gameplay
  transform, add a delta held in its own state (wrist lag), write only to the skin node.
- Plan: a per-joint visual delta table on the rig, applied in `_xf()` / `_pos()` after the
  interpolated read, each delta turning about its parent joint (hips, torso, shoulder, hip).
  A small `CardMotionLayer` owns it and integrates idle, arm swing and reactions in the rig's
  `_process`. The paddle skin applies the same hand delta in `_follow` (:192) so the paddle
  stays in the hand. Route `body_pivot.global_position` (:493) and `_cell_for` through it too.
- Gameplay fields untouched; no nodes under BodyPivot. New motion is visual-only by design, so
  `pose_diff.py` must stay IDENTICAL.
- Not visual-only today: idle sway, breath bob, lean and crouch bob write BodyPivot directly
  (`player_body_animation.gd:39-135`) and so move gameplay meshes. Moving them into the layer
  is a gameplay change: ask the user, bench it.

Built 2026-11-21: `scripts/graphics/card_motion_layer.gd`, applied in `PixelCardRig._xf()`;
`paddle_skin._follow` applies `rig.paddle_delta()`. `PICKLEBALL_CARD_MOTION=0` turns it off.
Bench seed 1, 40 s, motion off vs on: 0 script errors, poses IDENTICAL. Idle sway, lean and
crouch bob still write BodyPivot (not moved; that needs the user's go-ahead and a bench).

### Stage 9. Movement
- Read-only audit by data first: do arms and torso move while walking and running; does
  any idle motion exist.
- Movement workspace: treadmill preview (speed 0 to 4.4 m/s, direction), foot contact
  strip, foot slide, hip bob, stride, step time; transition buttons (stand -> run,
  run -> stop, shuffle -> lunge).
- Order by screen time: ready stances and idle, strafe and split step, lunge, run and
  stop, walk, pick up, throw, jump. "Stride" means the long step into a shot.
- Gait constants moved to a data file with identical values, then tuned.
- One-shot actions (pick up, throw, jump, lunge) authored as three keys like strokes.

Audit findings (read-only, 2026-11-21):
- Legs: procedural IK in `player_leg_ik.gd` (constants :20-41 and :129-145, plus inline values
  at :628-658); gait choice in `footwork_motion_state.gd:80-139` (stance, walk, jog, run,
  shuffle, crossover, drop_step). Stride constants are duplicated in
  `player_body_animation.gd:20-25`.
- Arms: frozen in the active pose while moving; no arm swing. Torso: velocity lean up to
  14 degrees and ball tracking, no counter-rotation with the stride.
- Idle: small sway and breath bob below 0.1 m/s (`player_body_animation.gd:122-135`).
- Already exist: split step (`split_step_timing.gd`, `player_leg_ik.gd:327`), lunge, jump,
  air smash, landing poses (`base_pose_library.gd:116-151`), pick up
  (`between_point_controller.gd:317-343`).
- Gameplay reads feet: planted-foot balance penalty (`shot_contact_quality.gd:15-45`), reach
  limits (`held_preparation_reach.gd`, `stroke_body_pose.gd`), `is_support_ready`. So leg and
  gait tuning is a gameplay change (bench); arm swing and torso counter-rotation should go in
  the Stage 8 layer and stay visual-only.

Built 2026-11-21 in the Stage 8 layer: free-arm swing (26 deg at a full stride) and a shoulder
counter-turn (8 deg), driven by the real front-back foot split so they stay in step, faded in
from 0.35 to 3.0 m/s. Off during strokes (charge / follow-through), between-point (ball carry)
and pose editors; the paddle arm only turns with the shoulders. Probe, autoplay seed 1, 40 s,
4 players: weight reaches 1.0, free hand moves up to 0.20-0.21 m, the swing flips side 12-26
times, active on 10-22% of frames. Look not yet checked by the user. Leg and gait tuning
(gameplay) not started.

Motion bench (built 2026-11-21): `tools/motion_bench.sh <name> [base]`, about 5 s. One player walks
stand, walk, stop, run, stop, backpedal, shuffle right / left / right, diagonal, settle on a
frozen court (AI, ball and scoring stopped; the player moves through its own physics step via a
stand-in for the special-movement hook). Report per segment: speed, card-motion weight, free-hand
swing, shoulder twist, in-step %, steps, planted-foot slide, drawn-hand pop; with a base run, the
changes and gameplay joints IDENTICAL / DIVERGED. Repeat runs match exactly.
First findings, fixed: arms swung in a side shuffle (now off unless travelling along the facing);
the drawn hand popped 78 mm a frame while running (now a sprung swing: 20 mm, same as with motion
off); swing 26 -> 20 deg, twist 8 -> 7 deg. Still open for the user's eye: 20-29 cm swing on the
diagonal run and while stopping from it, in-step 72-80% there (spring lag).

### Stage 10. Reactions and no more "always ready"
- Relaxed stand (upright, paddle down), relaxed walk, small idle changes; ready only when
  a serve is near.
- Reactions as three-key moves in a Reactions workspace. First batch: fist pump, head drop
  and slump, bounce on toes, paddle twirl, relaxed stand. Later: both arms up, hop, wave,
  look at the paddle, hands on hips, hands on knees, mild anger, paddle tap with partner,
  match-end sequence. Moods: victory, excited, cute, tense, frustrated, anger, tired, team.
- Big readable shapes; face variants through the baker; emote icons above the head.
- Chosen from a per-player mood value (streak, margin, who erred); no repeats; its own
  random source (the seeded AI shares the main one); only while the ball is dead; fits the
  existing between-point time; skippable; sound and camera framing included.
- Coordinate with the session that owns between-point code.
Check: reaction start and end times stay inside the between-point window (from logs).

Built 2026-11-21 (first batch, card layer, visual only): `scripts/graphics/card_reactions.gd`,
played by `CardMotionLayer._react`. Reactions: fist_pump, bounce, paddle_twirl (winners),
head_drop (the player who erred), head_drop_small (losing side). Channels: paddle-arm lift and
elbow bend, torso lean, head nod, body bob, paddle spin (the paddle skin applies it). Only the
paddle arm moves (the other hand carries the ball). Picked on `rally_scorer.rally_ended` from won /
lost, who hit last, team streak and score margin; never the same twice in a row; own fixed-seed
RNG per actor (no global RNG draws); 0.12-0.32 s staggered start; fades out in 0.15 s when the ball
is next in play. Duration 0.95-1.45 s.
Checks: motion bench react:<name> segments (paddle hand 11-52 cm, bob up to 3.5 cm, gameplay
joints IDENTICAL); autoplay seed 1, 150 s, 8 points: reactions start at every point end and end
within 1.1-1.9 s, next ball in play 7-8.5 s later, none cut off, no back-to-back repeats.
Not done: relaxed stand / no more "always ready", later reactions (arms up, hop, wave, hands on
hips or knees, partner paddle tap, match-end sequence), face variants, emote icons, sound and
camera framing, a Reactions workspace in the studio. Look not yet checked by the user.

Partner paddle tap (built 2026-11-21, card layer, visual only): `scripts/graphics/card_partner_tap.gd`.
Starts when partners are within 1.5 m now and still at the tap moment (velocity look-ahead), ball
dead, within 5 s of the point end, neither bending for / lifting / passing / catching the ball;
replaces both partners' reactions; once per team per point; both start on the same frame.
0.7 s: chest turns up to 35 deg toward the partner, lean up to 16 deg when farther, the paddle hand
stops a paddle short of the meeting point (midpoint, 1.15 m up) and the paddle turns to point at
it, a 5 cm push at 0.3 s. Autoplay seed 1, 150 s, 7 points: 3 taps, in sync, none during a live
ball; paddle heads met at 4 and 10 cm, one near-miss at 29 cm (partners crossing fast). Partners
usually end a point 2-3 m apart, so most points have no tap: making partners walk to each other
is a gameplay change (between-point movement, owned by the between-point session): ask the user.
Bench seed 1 60 s and motion bench, motion on vs off: IDENTICAL.

Standing expressions (built 2026-11-21, card layer, visual only): `scripts/graphics/card_expressions.gd`.
Context: idle (ball dead between points), waiting (WAITING / SERVING), live (ball in play). Mood per
player: frustration (own error +0.5, team loss +0.15, x0.55 per team win), confidence (team streak),
tension (both >= 7 within 2, or anyone at 10+), fatigue (stamina speed factor). Expressions: idle,
idle_tired, idle_frustrated, idle_confident, ready, ready_waiting, ready_tense, ready_frustrated,
ready_tired; looping channels (paddle-arm lift / elbow, torso lean, head nod, head look, shoulder
shrug, body bob, paddle twirl); 0.45 s crossfades; fade with travel speed (0.3-1.2 m/s); give way to
reactions (fade under them), taps, strokes and hands busy with the ball.
Rule: while the ball is in play the paddle and every hand on it (grip, and the support hand on the
throat) stay exactly where gameplay has them: no expression, swing or shoulder turn on those arms
(eased over 0.1 s as a hand comes on or off the paddle). Autoplay seed 1, 150 s: largest move of a
paddle hand by card motion while the ball is live and the player stands: 1.3 mm. The running shoulder
turn used to move the paddle arm in live play (up to 4-5 cm); now it does not.
Seen in that match: idle and idle_frustrated between points, ready_waiting / ready_frustrated before
serves, ready / ready_frustrated in rallies; tension, confidence and fatigue did not come up (low
scores, full stamina), so those show only in the motion bench expr:<name> segments.
Bench seed 1 60 s and motion bench: IDENTICAL.

Stand straight between points (built 2026-11-21, card layer, visual only; "relaxed stand" above):
the gameplay legs keep the athletic crouch (balance and reach read them). Between points (ball
dead, POINT_SCORED), standing still (fades out 0.3-1.0 m/s), not bending for / passing the ball and
not swinging, the cards shift the hips over the middle of the feet (up to 15 cm), lift the body
until the straighter leg is at 99.7% of its length (about 9 deg of knee, up to 20 cm) and place each
knee on a two-bone solve from the lifted hip to the planted ankle, bending the way it did. Rises and
sinks over 0.35 s; sinks back to the athletic stance when the game goes to WAITING (serve coming).
Autoplay seed 1, 150 s: fully standing frames knee p50 8.9 deg, p90 29.7, max 47.8 (wide or
staggered feet: straight legs would need the feet to step in, a gameplay change); gameplay legs
69 deg between points; every player back to the athletic stance when SERVING starts.
Motion bench: knee / knee game / raise columns. Bench seed 1 60 s and motion bench: IDENTICAL.

Relaxed stand in gameplay (2026-11-21, user's call: no ball in play, no athletic stance needed):
`between_point_controller._perf_make_pose` now stands players up between points: crouch 0 (was
0.16), stance 0.28 m (was 0.36), feet 2 cm front / back (was READY's stagger); a pickup still
bends from there; SET_SERVE blends everyone back to READY as before. The cards treat SET_SERVE as
"serve coming" too (athletic, ready-waiting expression). Autoplay seed 1, 150 s: gameplay knees
between points 69 -> 30 deg (average incl. pickups); fully standing drawn knees p50 8.9, p90 8.9
(was 29.7) deg. Bench 3 seeds x 90 s, before / after: poses DIVERGED from the first between-point
(BodyPivot 8 mm, expected); seeds 2 and 3 same points, endings and phase times; seed 1 3 points
instead of 4 (between 7.2 s vs 6.7 s, rally 17.1 vs 14.6 s). Per 100 shots: point endings 3.4 vs
4.1, shot-plan mix unchanged within noise.

## 6. Decisions

Decided by the user:
- The full-screen desktop Godot studio is the only editor (browser dropped 2026-11-20); the phone gets the player, notes and change log.
- This work owns `data/postures` and `data/base_poses`; notes, versions and ratings are committed to git.
- Pose edits go ahead without the bench.
- Test with data only; ask before using images.
- A human star rating per pose drives the work; goal is most poses at 5 stars.
- "Stride" = the long step into a shot.

Dropped after the controls audit: forehand -> backhand whole-pose mirror, full variation
matrix with "play all", batch paste to many poses, named wrist-lag presets, maths typing
in fields, draw-over annotations.

Open (ask the user; recommended default in brackets):
1. Is the other session still editing poses, or can this work take over `data/postures`?
   Blocks stage 3.
2. Has the user saved pose edits in the phone editor? [import them in stage 5; sooner if
   the phone is where things feel off]
3. Notes and versions committed to git [yes] or local only.
4. Next step after reading this spec: studio core [recommended] or fix the worst poses
   from 3.2 first.
5. Serves in the studio after stage 6 [yes].
7. The exact 5-star target [80% at 5 stars per pose type, none below 4].
6. Backhand-face variation: include Volley Ready? When should the game use it?

## 7. Status

| Stage | Status |
|---|---|
| 0 Pose checker | Done 2026-11-20 (transition table, trace mining, card steps still to add) |
| 1 Studio core | Desktop Pose Studio built 2026-11-20 (`scripts/studio/`, launch `tools/pose_studio.sh`); the browser version was built and dropped the same day (section 1). Checked end to end by data through the link (28/28): pose list 21 strokes / 22 stances, s13 metrics equal the checker capture on all 3 stages, inspector edit + undo + redo (field and metrics), save writes only the edited line and a no-change save is byte-identical, real mouse clicks on the pose list, a gizmo drag on the hips (one undo step), keys Space, comma/period, Cmd+Z, Shift+Cmd+Z, Cmd+S, ?, Esc, pixel cards present. Also: `.tres` writer and CLI unit tests 36/36, headless smoke check clean, the phone editor unchanged in a plain run. Not checked: how it looks (no screenshots), real OS mouse/keyboard (tests push events into the Godot window), `--window full`, second view drawing, the foot-plant stop path in the UI. Not yet used by the user. |
| 2 Notes, versions, compare | Built into the studio as tabs; checked by data in a scratch store: a 5-star rating lands on the current version and shows stale after the next save, a note goes open -> addressed, the versions tab lists every version, its v001 vs v002 table equals the edit, and restore is byte-identical. Not checked: the history chart, a DIVERGED bench compare. |
| Ratings (in stage 2) | System built; current count: 0 of 43 poses rated |
| 6b AutoPose | Built and QA'd 2026-11-21 (2 reviewers, 384 UI drags + 16 Relax keys; gameplay fields 0 changes, pinned feet 0 drift, undo exact). Fixed: Stiffness double-click reset, undo label for multi-field steps, undo / redo / revert refused mid-drag, Relax reports the committed pose (not the prediction) when the reach check cuts it short, per-move time budget predicts the next iteration (s16 p95 8.7 -> 5.1 ms, max 15 -> 9.3), Contact paddle never unpins in AutoPose, display names and plain-click message. Still open: torso-turn reach refusals on s16 / s17 (Relax on s17 contact keeps 3%), balance guard limits on s10 / s16 / s17, balance may worsen inside 5 cm (b11 +1.4 cm), UI drags not bit-repeatable under the 6 ms budget (up to 0.6 deg), s00 finish paddle tip off screen in the default view. Next: stage 6c step 2 |
| 6c step 2 Elbow | Elbow swivel field built (visual only, bench IDENTICAL), all poses baked; stroke flips 7 -> 3. Next: limits, s10 decision, authored keys vs code-built keys |
| 3 to 10 | Not started |

Nothing from this work is committed.
