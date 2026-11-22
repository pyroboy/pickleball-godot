# Arjostyle Pickleball (iPhone, doubles)

Pickleball game in Godot 4.6.3 (GDScript), shipped to iPhone. Version 0.3.28 build 31.
Moving to a 2.5D pixel-art look with gameplay locked: north star, phases and next steps
are in `docs/ROADMAP.md`. Read it before planning work.

- Entry scene: `scenes/title.tscn` · gameplay: `scripts/game.gd`
- iOS export settings: `export_presets.cfg` (bundle id `com.arjomagno.arjostylepickleball.ios`)
- Players render as 2.5D pixel cards (the only look): `scripts/graphics/pixel_card_rig.gd`,
  `assets/pixel_cards/`, `shaders/pixel_card.gdshader`. The classic 3D meshes stay under
  `BodyPivot`, hidden, because gameplay reads them (contacts, reach, fingers for hand rules).

## Working rules

- Keep changes small; read only the files the task needs.
- Don't add per-frame `print()` logging — Godot output floods quickly.
- Run on Mac: `tools/run_mac.sh` (log in `logs/game.log`), then `tools/game_errors.sh` for a deduplicated error summary.
- Performance: every run writes `logs/perf.jsonl` (PerfMonitor autoload, `scripts/debug/perf_monitor.gd`). Read it with `python3 tools/perf_report.py`, not by opening the log. F3 toggles the in-game frame graph. Time new hot spots with `PerfMonitor.record("label", usec)`.
- iOS Simulator is not usable: Godot 4.6.3's official simulator library is x86_64-only.
- Physics runs at 30 Hz with physics interpolation (`project.godot`). Visuals placed in
  `_process` must read `get_global_transform_interpolated()`, not `global_position`.
- Contact rule (user's call): the ball must really meet the paddle, but the planned
  trajectory wins over strict paddle geometry. The pose is an approximation: the paddle
  face angle never changes the shot (no face error, no face pop-up). Only arm stretch adds
  small deliberate error. All in `match_contact_authority.gd` (`contact_launch`); don't
  re-tighten it elsewhere.
- Don't run `tools/bench.sh` by default. Run it only when required: the change could
  alter gameplay (shot physics, ball flight, AI, contact, input timing, anything gameplay
  reads), or the user asks. Then compare runs with `python3 tools/pose_diff.py` (expect
  `IDENTICAL` for visual-only work). Never add nodes or meshes under a player's
  `BodyPivot`; gameplay scans every mesh there.
- Animation-only work (card motion, movement, reactions): `tools/motion_bench.sh <name> [base]`
  (about 5 s): one player walks a fixed course on a frozen court; per-segment arm swing, twist,
  steps, foot slide, hand pops, and gameplay joints vs base (`IDENTICAL` = visual only). Use it
  instead of `tools/bench.sh` when the change can't alter gameplay.
- The headless smoke check below starts at the title screen, so it does not compile
  gameplay scripts; `tools/bench.sh` loads the match and catches those errors.
- Pose work: `tools/pose_review.sh s00 [b11 ...]` captures poses in the mobile editor preview
  (wind-up/contact/finish, paddle trace) with before/after vs `HEAD` and a metrics table (feet,
  centre of gravity, hip/shoulder turn, knees, elbow, paddle path) in `logs/pose_review/`.
  Edit values with `python3 tools/pose_set.py s00 windup.body_yaw_deg=32 contact.crouch_amount=0.2`.
  Plan and per-pose log: `docs/POSE_PASS_PLAN.md`.
- Headless smoke check:

```bash
godot --headless --path . --quit-after 600 2>&1 | grep -iE "script error|parse error|error:"
```
