# Pixel Pickleball (iPhone, doubles)

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
- Every bench follows `docs/BENCH_RULES.md` (read it first): state the objective (`OBJ="..."`,
  required), check its datapoints exist (`python3 tools/bench_plan.py <note> [--rate p --detect d]`,
  also sizes the seeds), start with one seed and justify more (`WHY="..."`, required), stop when
  the run can't change the decision, then recalibrate instead of re-running. Each run appends to
  `docs/BENCH_LOG.md`; fill in its Verdict, and check the log before a new bench.
- Performance work follows `docs/PERFORMANCE_PLAN.md` (phone data, budgets, step order) and
  section 6 of `docs/BENCH_RULES.md`:
  - **The phone is the judge** for frame rate and heat. The M5 Mac runs the same work 2-3x
    faster and barely throttles: a Mac number never signs off phone performance. Check on the
    phone with a 3-10 minute match, then pull `Documents/perf.jsonl` (recipe in the plan).
  - **Timing only from serial runs** (`tools/bench.sh` or `SERIAL=1`): side-by-side seeds
    inflate ms/tick by 10-15%. Side-by-side is fine for gameplay results.
  - **Results may change** in performance refactors, cleanups and native ports (user's call,
    2026-11-25): no need for `IDENTICAL`, but the bench reports what moved (hits, misses,
    stretched contacts, rally length, faults, pose rules) and the notes say why the new way is
    better. Visual-only work still expects `IDENTICAL`.
  - **Report the budget** with every gameplay-touching change: serial tick cost and worst
    tick against the plan's budgets; say so when a change raises them.
  - **Switches:** each optimisation that can change results has a switch in `scripts/debug/perf_toggles.gd`;
    `TOGGLES=name=0,other=0` turns some off for one bench run (A/B on the same tree).
  - **Native code:** `native/` is a C++ GDExtension (classes `PickleNative`; `PickleCards`: the card build, twin = the loop in `pixel_card_rig.gd` `_draw_cards`; `PickleReplay`: the rally recorder, twin = the script paths in `scripts/fx/photo_history.gd`) for pure-maths hot loops; rebuild with
    `tools/build_native.sh` after editing `native/src`. Every native function keeps its GDScript twin
    (`scripts/native_math.gd`, switch `native_math`): change both, and bench with the switch on and off.
  - The all-AI bench cannot see the human seat (your player's planning, touch input): use the
    scripted human-seat run (plan, working method) or the phone for those.
- Gameplay or animation calls: `OBJ="..." tools/bench_seeds.sh <name> [secs=120] ["1"]` runs the bench
  per seed (low priority, about 30 s each), sums points, hits and the pose checks below, and prints the
  animation rules as PASS / FAIL (no late pose switch, paddle meets ball, no snap-back, wind-up wobble,
  flutter). `NEED=a,b` names the perf notes it must record, `BASE=<name>` compares poses, `ADD=1` adds
  seeds to a finished run. It stops by itself on script errors, a missing datapoint, or poses
  identical to the base.
- Which poses played: `python3 tools/pose_timeline.py <bench name> [player] [--from S --to S]` lists each
  player's stroke pose + base pose (with blend) over time and marks hits; `--summary` gives poses at contact;
  `--flights` checks AI pose prediction per ball (pose changes, late switches, charge at contact);
  `--swings` checks paddle motion per hit (contact snap-back, wind-up reversals, flutter, head-to-ball gap).
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
  A stroke can have a 4th key, Drop, between Wind-up and Contact (`drop.<field>`, only High Overhead has one),
  and air legs for jumps (`air_*_foot_offset`). `tools/pose_paddle.gd` turns "paddle head here, tip pointing there"
  into the pose_set values.
  Plan and per-pose log: `docs/POSE_PASS_PLAN.md`.
- Headless smoke check:

```bash
godot --headless --path . --quit-after 600 2>&1 | grep -iE "script error|parse error|error:"
```
