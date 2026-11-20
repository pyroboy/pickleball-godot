# Pose Studio protocol (shared contract)

Contract between the parts of the studio. Spec: `docs/POSE_STUDIO_SPEC.md` (sections 4, 4.1, 5 stages 1–2).
Change this file first if a part needs a different shape, and say so in your report.

```
Claude / scripts  --TCP 127.0.0.1:8766, JSON lines-->  scripts/debug/pose_studio_link.gd  -->  Desktop Pose Studio (scripts/studio/pose_studio.gd)
Desktop Pose Studio  --OS.execute-->  tools/pose_notes.py (writes .tres via tres_edit.py, versions, notes, ratings)
```
Launch: `tools/pose_studio.sh [--port 8766] [--window max|full]` (Godot windowed with `res://scenes/game.tscn -- --pose-studio=<port>
--studio-window=max|full`; log `logs/pose_studio_godot.log`; prints `Pose Studio ready`; Ctrl+C stops Godot).

## 1. Godot link (TCP, one JSON object per line each way)

Request: `{"id": 7, "cmd": "set", ...args}`. Reply: `{"id": 7, "ok": true, ...}` or `{"id": 7, "ok": false, "error": "text"}`.
A line that is not a JSON object gets one `{"id": null, "ok": false, "error": "bad JSON: connection closed"}` and the
connection is dropped with every line queued behind it (a web page POSTing to 127.0.0.1 never reaches a command).
One client at a time. Started by `perf_monitor.gd` on user arg `--pose-studio=<port>`. In studio mode the
`user://` pose overrides (`MobilePoseStore.apply_overrides`) are NOT applied, so the preview shows the repo files.

Boot: when the game scene is ready the link creates `scripts/studio/pose_studio.gd` (node `PoseStudio`, child of the game
scene; window maximized, `--studio-window=full` for full screen, `none` to leave it), waits for `studio.engine` (the mobile
editor it opens) and then works on that engine. `select`, `stage`, `set`, `undo`, `redo`, `save`, `revert`, `reload` go through
the studio (`select_pose`, `set_stage`, `set_field`, ...), so the link and the UI always show the same pose; the current pose
is `studio.key` (a pose picked in the UI is the link's pose too). If the studio script is missing or does not create its
engine within ~20 s, the link opens the mobile editor itself (**link-only mode**): every command below works except `ui`,
`ui_action`, `undo`, `redo`, `save`, which reply `{ok: false, error: "studio not running (link-only mode)"}`.

Pose keys: `s00`..`s20` strokes (data/postures), `b00`..`b21` body stances (data/base_poses). Serves are out of scope.
Stage names everywhere: `"windup"` (0), `"contact"` (1), `"finish"` (2). Body stances only have `"contact"`.
Vector3 values travel as `[x, y, z]`; options as int index; bools as bool.

| cmd | args | reply fields |
|---|---|---|
| `poses` | – | `poses: [{key, name, kind: "stroke"\|"base", file: "data/postures/13_x.tres", family, dirty?}]` – optional `dirty: bool` = the pose has an unsaved working copy |
| `select` | `key` | `key, stage, stages: [...]` |
| `stage` | `stage` (name or 0..2) | `stage` |
| `fields` | – | `stage, groups: [{name, fields: [{field, label, type: float\|vector\|option, min, max, step, items?, value, saved, keys: {windup, contact, finish}, wrapped: bool}]}]` – `value` = current resolved value at this stage; `saved` = value in the file on disk; `keys` = resolved value at each stage (for track ticks) |
| `set` | `field, axis (null\|0\|1\|2), value` | `value` (applied, after clamping), `clamped: bool`, `stopped: null \| {reason, at}` (foot-plant check stopped the edit; `at` = value where it stopped), `warning: null \| text` (the field is locked for the studio UI by the Gameplay edit rule: contact paddle position / face, zones, floor clearance, timing; the link still applies it) |
| `scrub` | `progress` 0..1 | `progress` |
| `seek` | `t` 0..1 on real-time timeline | `t, phase, seconds` |
| `timeline` | – | `duration, prefix_seconds, release_seconds, stroke_seconds, tick: 1/30` |
| `play` / `stop` | `loop: bool`, `speed: 1\|0.5\|0.25` | `playing` |
| `step` | `dir: 1\|-1` | one game tick (1/30 s) on the timeline; `t` |
| `variant` | `variant 0 normal\|1 strong\|2 weak` | `variant` |
| `view` | `name: front\|side\|back` or `yaw, pitch, distance` | `yaw, pitch, distance` |
| `toggle` | `what: ghosts\|arc\|contact\|autopose\|autopose_balance\|autopose_look\|autopose_regions\|autopose_pin`, `on: bool`, `count` (ghosts), `handle` (autopose_pin; `on` omitted = flip) | `what, on`; the `autopose*` ones also `config` (= `autopose {config}` reply) and act like the AutoPose bar / lock icons (Stage 6b): `autopose` = mode (key P), `autopose_balance` = soft balance, `autopose_look` = head look-at, `autopose_regions` = show the Arms / Torso / Legs sliders, `autopose_pin` = `studio.set_autopose_pin` reply `{ok, handle, pinned}` (`ok: false, locked: true` when unpinning the Contact paddle hand / tip with Gameplay edit off; refused during an editing drag) |
| `metrics` | – | `stage, metrics` = the `_body_metrics(player)` dictionary from `scripts/debug/pose_shots.gd` |
| `diff` | – | `key, file, changes: [{stage, field, text}]` – every field whose working value differs from the file, `stage` = the FILE SECTION it lives in (`windup` = windup_body dict, `finish` = follow_through_body dict, `contact` = main resource incl. `charge_*`/`ft_*` deltas), `text = var_to_str(value)` (floats as the shortest decimal that reads back within 1e-9, e.g. `0.104`) |
| `revert` | – | drop the working copy, reload from disk |
| `reload` | `key` | reload this pose from disk ignoring the resource cache (after a CLI wrote the file; through `studio.reload` when the studio runs) |
| `frame` | `w, h` optional | `jpeg_b64, w, h, seq` – JPEG of the preview viewport (`ed._preview.viewport`); `seq` increments when the pose/camera changed |
| `nodes` | – | `pixel_cards: bool` (a `PixelCards_*` node exists in the preview world), `player: path` |
| `ping` | – | `version: 1` |
| `ui` | – | `key, stage, tree` – `tree` = `studio.ui_dump()`: `{name, type, visible, text/value/pressed/selected, children}` of the studio's named controls |
| `ui_audit` | `settle` frames (default 4) | layout audit of every visible studio control (`scripts/studio/studio_layout_audit.gd`, read-only): `window [w, h]` (UI points), `window_px`, `scale`, `controls`, `button_styles` (distinct normal styleboxes), `fonts {size: count}`, `scrolls [{path, content, have}]`, `min_target {h, path}` (smallest shown button / field), `counts {kind: n}`, `issues [{kind, path, text, need, have, rect, shown?, ...}]`; kinds: `text_clipped`, `wrap_collapse`, `tiny`, `tree_text_clipped`, `tree_column_sparse`, `tabs_overflow`, `overlap`, `escapes_parent`, `foreign_overlay`, `extra_viewport`, `off_window`, `small_target` (< 24 pt), `toggle_state_unclear`, `scroll_slack`, `scroll_overflow`; `shown: false` = scrolled out of view. Baseline: `logs/pose_studio_audit_baseline.json` |
| `window` | `w, h` (points), `emulate: bool` | windowed at w x h points: `w, h, px, screen_scale, clamped, ui, min_points` (`min_points` = the window minimum, 1280 x 760 in the studio; macOS applies it to user resizing, not to this call); `emulate: true` keeps the window and lays the studio out as that size would (`studio.layout_override`, canvas stretched) for sizes bigger than the screen: `emulated, ui` |
| `ui_action` | `name, action: press\|set\|select, value` | `studio.ui_action(...)` reply (acts on the named control like a user would) |
| `undo` / `redo` | – | `key, stage` + the studio's reply fields; one studio edit (one `set`, one drag) per step |
| `save` | `message` | `studio.save(message, "claude")` reply: `{ok, file, changed_lines, version}` from `tools/pose_notes.py save` (author **claude**: the version credits Claude; the studio's own Save / Cmd+S records author user); the studio then reloads the pose |
| `key` | `key` (Godot key name: `Space`, `Comma`, `Period`, `Z`, `S`, `Question`, `Escape`...), `mods: ["cmd", "shift", "alt"]` | test hook: press + release pushed into the Godot window (same path as a real key) |
| `quit` | – | `unsaved: [key]` – like closing the window: quits at once when nothing is unsaved, else the studio shows Save all / Discard / Cancel (`QuitDialog`). `tools/pose_studio.sh` sends it on Ctrl+C (a second Ctrl+C kills Godot) |
| `mouse` | `events: [{type: down\|up\|move, x, y, button: 1\|2\|3, alt, shift, ctrl, cmd}]` (x / y / button / dx / dy / factor must be numbers when present: else `{ok: false}` and no event is sent), optional `target` (a named studio control) and `item` (a Tree row key), or `handle` (an AutoPose handle id in AutoPose mode, else a joint dot id or `paddle_tip`) | test hook: events pushed into the Godot window; x, y in preview pixels (or relative to `target` / the row centre / the handle's screen point at the start of the command, so `{handle: "left_knee", events: [down 0,0; move 20,0; up 20,0]}` is a full drag of that handle); replies `selected_joint`, `handle_at` (with `handle`), `autopose` (= `last_drag` below, in AutoPose mode). Pushed events carry device id 77; while the link runs `mouse` (and `key`, `ui_action`) the viewport ignores mouse events from any other device (the real OS mouse), so a hover over the window cannot join a test drag |
| `gizmo` | `project: [[x, y, z], ...]` optional | `joints {id: [x, y]}`, `selected_joint`, `enabled`, `mode`, `anchor`, `axes [{axis, bound, binding, grip, end, direction}]` in preview pixels (`grip` = a point to start a drag); also `world_axes` (gizmo axis directions, world), `origin` (gizmo centre, world), `scene_visible` (handles drawn; they stay drawn, dimmed and not editable, between keys), `world {joint: [x, y, z]}`, `projected` (the `project` points in preview pixels), `drag {axis, value, origin0, dir}` during a Move-arrow drag (the gizmo's line parameter, metres), `progress`, `stage_index`, `tip {world, screen, available}` (paddle tip dot), `last_aim {usec, iters, err_px, refresh_usec}` (last tip-aim solve, per mouse move; `refresh_usec` = the engine's once-per-frame preview refresh), `hand_slide` (Alt held: paddle-hand Move = grip slide), `drag_kind` (`pos` / `rot` / empty) |
| `aim_probe` | `x, y` (preview pixels) | test hook, read-only: `{err_px, pitch, yaw}` = the best paddle-tip screen error any paddle pitch / yaw could give for that point (roll and the grip as in the current tip drag), brute-force grid over the tip solver's own model |
| `autopose_handles` | – | AutoPose drag UI (Stage 6b): `on` (AutoPose mode), `dragging`, `handle` (being dragged), `target` / `target_screen` (where the mouse wants it), `at_key`, `handles: [{id, name, x, y, inside, world, locked, reason, hover, pinned, lock: [x, y] (lock icon centre), lock_shown}]`, `hover_lock`, `config` (as `autopose {config}`), `last_relax` (preview pixels, the solver's own points: hands, `paddle_tip`, elbows, knees, feet, `hips`, `chest`, `head`; `locked` + `reason` at Contact for the paddle hand and tip, `no paddle on this pose` for the tip on body stances), `last_drag` = the last UI drag `{handle, key, stage, balance, carry, grab_usec, n_params, contact_excluded, mobility, handle_start, moves, usec: [per mouse move], last: {target_err_m, feet_drift_m, paddle_drift_m, balance_before_m, balance_after_m, stop, iters, evals, usec, clamped, target, handle_at}, result: dragging\|released\|cancelled\|switch\|ended..., release: {committed, changes, stopped, first_stops?, kept, backoff_usec?, commit_vs_prediction_m, ...}, release_usec}`. Also in `ui` as `preview.autopose` (without `last_drag`) |
| `autopose` | `handle` (`right_hand`, `left_hand`, `paddle_tip`, `right_elbow`, `left_elbow`, `right_knee`, `left_knee`, `right_foot`, `left_foot`, `hips`, `torso`/`chest`, `head`) + `target: [x, y, z]` (one mouse move; a new handle / key starts a new drag) or `path: [[x, y, z], ...]` (a fresh drag, one move per point); options `mode: broyden\|fd`, `scope: full\|arm`, `stiffness: {all, arms, torso, legs (bar groups), arm, paddle, chest, head, hips, legs, foot (regions): multiplier}` (multiplied together: all x group x region; groups arms = arm + paddle, torso = chest + head, legs = hips + legs + foot), `pins: [{joint, point?}]` (handle ids; a pinned handle holds its world position at grab, never the dragged one; a pinned paddle hand / tip turns elbow carry off), `unpin: [right_foot, left_foot, paddle]` (default pins off: a foot; `paddle` = the Contact grip + tip, honoured only while the studio's Gameplay edit is on, and then fields that move the paddle are no longer frozen), `look_at: [x, y, z]` or `look: true` (the studio's look point: after each move the head yaw / pitch fields turn the head to it, closed form, like the game's ball gaze; limits 85 deg turn, 70 up / 55 down; move reply `look_err_deg`), `follow` (body-follow weight, default 0.15 x all x arms: hand / paddle-tip drags pull the shoulder along so the chest turns a little), `studio: true` (every option from the AutoPose bar: what a UI drag uses); options other than mode / scope / balance apply when a drag starts, `budget_usec` (per-move time cap, 0 = converge), `balance` (default `true`: soft pull toward the 5 cm zone and a hard rule that the centre of gravity never ends further off the ankle line than max(5 cm, where the drag started) + 0.5 mm; `false` = off; a change starts a new drag); `{release: true, commit: bool, backoff: bool}` ends the drag (commit = one undo step through `set`'s path, written as a batch: no full preview refresh per field, the pose refreshed before each foot-plant-checked field and once at the end; `backoff` (the studio's drag UI always uses it): when the foot-plant / reach check stops a field, the largest fraction `kept` of the whole drag that commits with no stop is written instead, bisection in 6 steps); `{config: {balance, look, stiffness: {all, arms, torso, legs}, reset_pins}}` sets the AutoPose bar and replies `config: {balance, look, stiffness, pins (pinned at this key, incl. the Contact paddle), user_pins, paddle_free, look_point, regions_shown}`; `{relax: true}` = the bar's Relax at this key (`studio.autopose_relax`, one undo step "relax"): reply `stop (natural\|converged\|max_iters), iters, evals, usec, cost_before, cost_after, rules (names), rules_before / rules_after (metrics), violations_before / violations_after (goal margins), flags_before / flags_after (the checker's own thresholds), feet_drift_m, pin_drift_m, paddle_drift_m, fields, look_err_deg?, trace (per iteration), begin, release_usec, release {committed, changes, stopped, first_stops?, kept, commit_vs_prediction_m}`; `{probe: true, handle, samples}` = evaluation cost / determinism (`determinism_m`: same candidate twice; `after_other_m`: same candidate after other candidates, expect 0) / arm-path check / paddle and feet coupling | Stage 6b prototype (`scripts/studio/autopose_solver.gd`): animation fields only, never gameplay fields, at Contact the paddle grip + tip are pinned (paddle hand / tip handles refused there with `locked: true`). Move reply: `usec, evals, iters, stop (reached\|converged\|stalled\|budget\|max_iters), target_err_m, feet_drift_m, paddle_drift_m, balance_before_m, balance_after_m, clamped, eval_usec, arm_eval_usec, handle_at, arm_reach_m, carry_rel_m` (`arm_reach_m`: `[[at grab, now(, limit)] right, left]` shoulder-wrist metres, limit only while the torso turn is free; `carry_rel_m`: elbow carry, how far hand / tip are from their grab offset to the elbow); `begin`: `params, frozen, contact_excluded, validator_refused, seeded_guides, grab_usec, grab_evals, balance, arm_path` (false: the body follows the arm at this pose, so arm / paddle columns use full evaluations); the same drag replays identically (evaluations do not depend on what was solved before); commit release: `changes, stopped, kept, first_stops?, backoff_usec?, commit_vs_prediction_m` (vs the prediction at `kept`). Elbow carry (paddle-hand elbow at wind-up / finish): each move first translates the paddle by the mouse's elbow offset, then the solve holds hand - elbow and tip - elbow at their grab offsets (soft pins, paddle position free, paddle angles frozen), so the forearm, hand and paddle go with the elbow as far as the elbow really goes |

Extras the link sends (2026-11-20 integration; clients may ignore them): `ping` also has `ready: bool` (editor open; every
other command waits for it); `poses` items carry `dirty`; `seek` and `step` reply `{t, seconds, phase, progress}`; `variant`
also returns `playing`; `metrics` takes optional `settle` (frames to wait, default 12, as `pose_check`); `view` accepts
`name: reset`; `diff` rows may be `{stage, field, text: null, removed: true}` for a keyframe key missing from the working copy;
`fields` option rows use `min 0, max items-1, step 1`, and body-stance `keys.windup` / `keys.finish` are null; `metrics` has no
`joints` (that key is added only by `scripts/debug/pose_data.gd`). The preview player node is `Player0`; `nodes` gives its path.
`fields.saved` and `diff` compare with a fresh load of the file on every call (no cache), so they stay right after a CLI write.
`diff` logic lives in `scripts/studio/pose_diff_util.gd` (`PoseDiff.diff(cur, disk, base)`), shared by the link and the studio.
`reload` is for after a CLI wrote a pose file outside the studio (`tools/pose_set.py`, `pose_notes.py restore`). The studio's
Revert also reloads the live pose from disk, so it never brings back an older in-memory pose.
**Claude never rates or verifies.** While the link runs `ui_action`, `key` or `mouse` it sets `studio.link_driving`; the rating
panel's Submit and the notes panel's Verify then refuse (status message, nothing written). Rating also needs the pose saved
(Submit is disabled while `diff` is not empty): a rating belongs to the saved version. `ui` also reports `unsaved: [key]`.

Godot is the authority for every pose value; Python never computes pose values.

## 2. Server HTTP API: removed

The browser editor and `tools/pose_studio/server.py` were dropped on 2026-11-20 (spec section 1); the studio is the Godot window.

## 3. Storage (`pose_studio/` at repo root, has a `.gdignore`, committed to git)

- `pose_studio/notes/<key>.json` – list of note records (spec 4).
- `pose_studio/versions/<key>/v000.tres` (= `git show HEAD:<file>`), `v001.tres` (= working copy at first studio start), then one per save; each with `vNNN.json` version record.
- `pose_studio/ratings.json` – append-only list of rating records (never rewritten except by appending).
- `pose_studio/changelog.json` – generated.

Only `tools/pose_notes.py` writes these files (Claude runs it; the Godot studio runs it with `OS.execute`). Godot panels read the JSON directly.
Writes are atomic (temp file + rename). JSON written with `indent=1, sort_keys=False`, UTF-8, trailing newline.
Every read-modify-write holds `flock` on `logs/.pose_studio.lock` (git-ignored). v000/v001 are created by `init` (or lazily before
the first write to a pose); if the file is not in `HEAD`, v000 is the working copy with message `HEAD (file not in git; working copy)`.
Version records hold exactly the spec keys; `changelog.json` is rewritten only when its content changes.
Ratings are appended so every existing entry keeps its bytes (refused if the file was reformatted by hand).

Environment (tests, other agents): `POSE_STUDIO_ROOT=<dir>` puts the store in `<dir>` instead of `<repo>/pose_studio` (its lock is
then `<dir>/.pose_studio.lock`); pose files are still the repo's. `POSE_STUDIO_REPO=<dir>` reads / writes pose files, `logs/pose_check/latest.json`
and `git HEAD` under `<dir>` instead of the repo (tests use a temp copy of `data/`).

## 4. CLI: `tools/pose_notes.py` (Claude and the Godot studio)

Python stdlib, no Godot needed. Every subcommand takes `--json` (before or after the subcommand): stdout is then exactly one JSON
object, `{"ok": true, ...}` with exit code 0, or `{"ok": false, "error": "text"}` with exit code 1 (bad arguments included).
Without `--json` it prints short text (errors on stderr, exit 1). Pose keys `^[sb]\d\d$` and the pose file must exist; version
numbers are integers 0..9999; note ids `n<digits>`.

| subcommand | args | `--json` reply (besides `ok`) |
|---|---|---|
| `list` | `[--open] [--key s13]` | `notes: [note]` (`--open` = status open / reopened) |
| `show` | `<id>` | `note` |
| `reply` | `<id> --text T [--change stage.field=from:to ...] [--evidence E] [--version N] [--status S]` | `note` (author claude; status `addressed` unless `--status`) |
| `version` | `<key> -m MSG [--note n12 ...]` | `record, version` – records the current file as a new version, author claude, score/flags from `latest.json` |
| `queue` | `[--all]` | `queue: [entry], total` – spec 4.1 order: rated by stars asc (ties: checker score asc), then unrated (score asc), then stale (old stars asc); entry `{key, kind, group: rated\|unrated\|stale, stars, stale_stars, version, rated_version, score, done, items: [{type: note\|flag, id, text, ...}]}`, items = open notes then checker flags; `done` = 5 stars on current version and no open notes (hidden unless `--all`) |
| `ratings` | `[key]` | `ratings: [row]`; with key also `state: {stars, stale, stale_stars, version, rated_version, aspects}`, without key `progress` (as below) |
| `save` | `<key> --changes FILE [-m MSG] --author user\|claude [--note n12 ...]` | `file, changes: [{stage, field, from, to}], changed_lines, version, saved` |
| `note-add` | `<key> --text T [--kind request\|rule] [--stage windup\|contact\|finish] [--field f] [--time 0..1] [--rule-flag F] [--rule-metric M] [--rule-min x] [--rule-max x]` | `note` (author user, status open, `created_version` = current; `rule` object only for `--kind rule`) |
| `note-set` | `<id> [--status open\|addressed\|verified\|reopened] [--text T]` (one needed) | `note` |
| `rate` | `<key> --stars 1..5 --by user [--aspect body=2 ...] [--note n12 ...] [--comment C] [--source studio\|phone]` | `rating` (row as stored; `version` = current version). `--by` is required and anything but `user` is refused: Claude never rates |
| `versions` | `<key>` | `key, current, file_matches_current, versions: [record]` |
| `version-show` | `<key> <n>` | `record, text` (the stored `.tres` text) |
| `version-diff` | `<key> <a> [<b>]` | `key, a, b, changes: [{stage, field, a, b}]` – `a` / `b` = version number or `file` (working copy, default for `b`); value texts, null = missing on that side |
| `restore` | `<key> <n> [--author user\|claude]` | `record, version, file` – writes version n byte-identically to the pose file, then records it as a new version (message `restore vNNN`). Godot must `reload` the pose afterwards |
| `approve` | `<key> <n> [--off]` | `record` |
| `progress` | – | `progress: {stroke, base}` each `{total, counts: {"1".."5"}, unrated, stale, at_5, share_5, below_4, target_share_5: 0.8, target_min_stars: 4, met, history: [{time, pose, stars, at_5, share_5}]}`; `met` also needs no unrated / stale poses |
| `changelog` | – | `file, changelog: {versions: [{pose, n, time, author, message, approved, notes, score, flags, changes: [{stage, field, a, b}]}] newest first, ratings, notes: [{id, pose, kind, status, text, created}]}` – regenerates `changelog.json` |
| `init` | – | `created: [key]` – v000/v001 for every pose without versions |

`save` details: `FILE` is JSON, either the list `[{stage, field, text}]` or the link `diff` reply `{key?, changes: [...]}` (a `key`
other than `<key>` is refused). `text` is the value text (`var_to_str`); a row `{stage, field, text: null, removed: true}` deletes
that key. Every row is validated before the file is touched: stage must exist for the pose (body stances: `contact` only) and the
field must be allowed there (`contact`: the `@export` vars of `PostureDefinition` / `BasePoseDefinition`; `windup` / `finish`:
`StrokeBodyKeyframe.FIELDS`); `script`, `windup_body`, `follow_through_body` are refused; a value is one trimmed line (at most 400 characters, 64 KB for
`Packed*Array` values such as elbow paths). Edits are
minimal text edits (`tools/pose_studio/tres_edit.py`, shared with `tools/pose_set.py`): one changed field = one changed line. No
effective change (empty list or same values, e.g. `0.3` vs `0.30`) = file byte-identical, `saved: false`, no new version, `version`
= current. Otherwise v000/v001 are made first if missing, the file is written atomically and a version is recorded (its
`score` / `flags` come from `latest.json` only when that file is newer than the pose file, else null; a failed changelog
rewrite does not fail the save: the reply carries `changelog_error`). Godot then
reloads the pose ignoring the resource cache.

Bench tab: `python3 tools/pose_studio/bench.py --json` -> `{ok, runs: [{name, file, mtime, seconds, renderer, physics_hz,
fps_median, fps_worst_5, points, shots, shots_per_point, reasons, endings: [{cause, n, per_100_shots}], endings_per_100_shots,
systems / inner_systems: [{name, ms_per_frame}], spikes: {count, threshold_ms, worst_ms, mostly}, jitter: [{state, what, count,
per_1k_frames}], pose_trace}]}`; `--compare a b` -> `{ok, a, b, pose_diff: {verdict: IDENTICAL|DIVERGED|error|no pose traces, text}}`
(runs `tools/pose_diff.py` on the saved `.pose.jsonl.gz`). Reads existing `logs/bench_*` files only; never starts a bench.
