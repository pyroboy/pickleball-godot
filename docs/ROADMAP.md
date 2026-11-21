# Arjostyle Pickleball: Roadmap

## North star

A fast, readable 2.5D pickleball game for iPhone that looks like a hand-crafted pixel-art
action game in a 3D world (in the spirit of Alabaster Dawn), runs at a steady 60 fps on
the phone, and plays exactly as the current game does. Look and feel change; the rules,
physics and timing stay locked until a deliberate "Gameplay v2".

### Pillars

1. **Look:** pixel-art players (cards pinned to the posture skeleton), a 3D court and
   effects, a high readable camera, hue-shifted shadows, no black outlines.
2. **Performance:** 60 fps on the target iPhone in 4-player rallies, measured with
   PerfMonitor on device, never guessed.
3. **Gameplay locked:** shot physics, ball flight, scoring, AI decisions, IK and input
   timing do not change during the visual update. Every phase proves it (see Guardrails).

## Next up (suggested)

1. **Test the pixel cards on a real iPhone** and record a PerfMonitor baseline
   (`python3 tools/perf_report.py`). Nothing on device has been measured yet.
2. ~~Expose Classic / Pixel in the Settings panel~~: dropped 2026-11-21, pixel cards are the only
   look (classic 3D meshes stay hidden because gameplay reads them).
3. **Far-court card tier:** bake a 20 degree, half-size card set and pick the tier by distance
   to the camera (far players currently reuse the near set).

## Phases

Status: done, in progress, next, later.

### Phase 0: Performance baseline (in progress)
- [x] PerfMonitor autoload, spike log, F3 graph, `tools/perf_report.py`
- [x] Seeded benchmark + pose trace (`tools/bench.sh`, `tools/pose_diff.py`)
- [x] Physics catch-up cap, IK once per player per tick, READY recheck at 10 Hz, AI re-plan cap
- [x] Human contact planner stutter (2026-11-19): `legal_ball` (NVZ foot / mesh scan) ran per
      posture x per flight segment in the planner fallbacks; now once per bounce count per call.
      Worst planner call on lobs 143 -> 8 ms on the Mac, choices identical (pose diff IDENTICAL).
- [ ] On-device iPhone baseline (fps, frame-time spikes) in 4-player rallies
- [x] 30 Hz physics / AI tick with physics interpolation (decided 2026-11-18, kept after
      playtest). Halves per-frame cost on the Mac bench (rally frame 9.4 -> 3.9 ms). It
      changed ball simulation: 3-seed all-AI bench showed similar rally length but more
      BALL_IN_NET (15 vs 9); watch this. Bench comparisons from here on are 30 Hz vs 30 Hz.
      Anything placed in `_process` must read `get_global_transform_interpolated()`.

### Phase 1: Pixel-card players (prototype done, default on)
- [x] Card rig on the existing joints: `scripts/graphics/pixel_card_rig.gd`
- [x] Card atlases at the game's real limb lengths: `assets/pixel_cards/`
- [x] Fog-free card shader, tonemap-compensated colours: `shaders/pixel_card.gdshader`
- [x] Gameplay identical with cards on and off (seeded bench, pose diff)
- [x] ~~Classic / Pixel toggle in the Settings UI~~: dropped 2026-11-21, pixel cards are the only look
- [ ] Far-court card tier (20 degrees, half size)
- [ ] Hand states (open / grip / reach) from the articulated hand mode
- [ ] Joint seams (elbow, knee) and draw-order polish
- [ ] iPhone check

### Phase 2: Pixel viewport and camera (next)
- [ ] Render 3D into a 1/3-resolution SubViewport with nearest upscale (one pixel grid
      for court, players and effects); UI stays full resolution on top
- [ ] Verify portrait framing and ball-on-screen logic with the SubViewport size
- [ ] Optional: steeper 3/4 camera as an A/B option (keep the current camera by default)

### Phase 3: Art pass (later)
- [ ] Final hand-painted cards over the generated ones (5 drawn views + mirrors)
- [ ] Team palette-swap shader for skins and cosmetics
- [ ] Six player sprite profiles (3 female, 3 male): `docs/CHARACTER_VARIANTS_PLAN.md`
- [ ] Court / arena textures in pixel style, baked lighting

### Phase 4: Effects and feel (later)
- [ ] Effects sprite sheet: impact burst, spark ring, bounce, dust, swing arc, speed lines,
      landing marker, smash flash, out stamp, ball trails (pooled through `fx_pool.gd`)
- [ ] Trajectory restyle: serve preview (gold), incoming guide (red), aim arc (cyan)
- [ ] Slow-mo: lens depth of field focused on the hitter, opponent soft-focused,
      Kawase blur on a half-res copy; restyles the existing aim-focus slow-mo
- [ ] Hit-stop and camera-shake tiers, layered hit sounds
- [ ] **Goal: wrist lag on every swing** (in progress). The paddle head trails the hand
      as the swing speeds up, then releases ("snaps through") so the face is square when
      the ball arrives. Visual only: done in the paddle skin (`scripts/graphics/paddle_skin.gd`,
      `_wrist_lag`), which pivots its copy of the paddle about the main grip. The gameplay
      paddle under `BodyPivot` never moves, so no bench is needed for tuning.
        Tennis / pickleball coaching: lag is passive (hand accelerates, head's inertia trails,
        loose grip = more lag), the relaxed head drops under gravity at the end of the
        backswing, release is a reflex as the hand slows, and dinks / resets keep a firm wrist.
  - [x] Damped pendulum at the grip (spring, damping, gravity), body-relative (running does
        not tilt the paddle), capped at 40 degrees, released only while an incoming ball is
        1.4 m to 0.45 m from the head
  - [x] Wrist looseness from shot charge and shot type (human `charge_ratio` /
        `_swing_shot_type`, AI `_planned_shot`): firm 18 Hz well damped for dinks / drops,
        loose 2.2 Hz underdamped with gravity for charged drives and smashes
  - [x] Whip past the real face after contact (underdamped loose wrist)
  - [x] Pre-lag (deliberate): while preparing for an incoming ball (human stroke, or an AI
        shot planned for this flight) the spring target is laid back along the ball's travel,
        up to 28 degrees on a charged drive, about 5 on dinks; let go from 2.2 m to 1.1 m so
        the spring whips the head through. Probe 2026-11-19: drives ~13 deg held (max 28)
  - [x] Auto lag (passive): forward head speed during a swing (against the incoming ball,
        else court-forward) loosens the wrist, 1.5 to 5 m/s. Repositioning into low poses
        does not count (dinks 0). Rare in all-AI play; check quick volleys by hand
  - [ ] Tune `LAG_HZ_*`, `LAG_ZETA_*`, `LAG_GRAVITY` by eye in play (forehand drive, backhand,
        dink, smash, serve). Autoplay probe 2026-11-19, 2 seeds: drives lag ~10 deg into contact
        (max 28), whip ~16 (max 40), backswing drop ~21; dinks / drops peak ~9 (abrupt pose
        changes in the real paddle, smoothed over a frame or two); 0 deg at every contact
  - [ ] Two-handed backhand: the support hand sits 5.5 cm up the handle and can slip off
        at full lag; reduce lag while the support hand grips
  - [ ] iPhone check (60 fps feel; lag is per frame, so it reads the same at any frame rate)

### Phase 5: UI (later)
- [x] Pixel UI kit (2026-11-21): original 5x7 font `assets/fonts/arjo_pixel.fnt`
      (`tools/make_pixel_font.py`) for display text, sans body copy, bevelled panels and
      press-sink buttons in `scripts/ui/game_ui_theme.gd`; title, pause, practice, settings
      and HUD call-outs use it. Checks: `tools/pause_menu_test.gd`, `tools/wall_drill_test.gd`
- [ ] Compact score pill, one-line coach toast, pixel joystick, HIT and shot wheel
- [ ] Same inputs and touch targets as today

### Phase 6: Ship and retire classic bodies (later)
- [ ] On-device performance pass against the Phase 0 baseline
- [ ] Remove the Classic option only after gameplay stops reading body meshes
      (foot mesh bounds in `player_nvz_state.gd`, `match_grounded_reach.gd`,
      `between_pose_admission.gd`, `fast_point_transition.gd`; hand / torso meshes in
      the between-point and surface-contact code)
- [ ] Release build

### Pose quality: Pose Studio and 5-star poses (started 2026-11-20)
Goal: most poses at 5 stars on the user's own rating (working target: 80% of each pose
type at 5 stars, none below 4). Full spec: `docs/POSE_STUDIO_SPEC.md`.
- [x] Data-only pose checker: `python3 tools/pose_check.py --solve` (10 s, no screenshots,
      no bench). First run: 151 flags across 50 poses
- [x] Desktop Pose Studio on the Mac: a full-screen Godot window (the browser editor was
      dropped 2026-11-20). Pose list, big 3D preview with gizmo drags, inspector, timeline,
      undo/redo, save, and tabs for metrics, notes, rating, versions, queue and bench. Saves to
      `data/postures`, `data/base_poses`. Tooling, not gameplay. Start: `tools/pose_studio.sh`
      (Ctrl+C stops Godot). Checked end to end by data 2026-11-20 (28/28); look and feel not
      yet confirmed by the user
- [x] Human star rating per pose with notes for Claude (`tools/pose_notes.py`), versions and a
      change log, all stored in `pose_studio/` (committed). No real ratings yet
- [ ] Refinement loop: lowest-rated poses first until the 5-star target is met
- [ ] Phone: pose player, ratings, notes and change log (no editing)
- [ ] Later: motion graphs, backhand-face front poses, movement, reactions

Decided 2026-11-20: pose edits in this track go ahead without the seeded bench (they
change gameplay by the Guardrails definition); the checker lists the gameplay fields touched.

### Later: Gameplay v2 (planned 2026-11-19)
Stance: keep the solved shot (pick a target, the game finds the swing); make skill show
in the result. Full inventory, gaps and decisions: Part 2 of the proposal PDF, pages 32-41.
Each package is gated on the 6-seed bench and `tools/shot_report.py`.
- [ ] G0 Safety net (does not change play)
  - [x] Fault rules: `tools/fault_tests.gd` (38 checks: lines, out, serve box, server
        position, two-bounce rule, kitchen volley, momentum, net ball, double bounce, post,
        body hit, double contact, every fault has an explanation)
  - [x] Fixed flight: `tools/flight_tests.gd` (22 checks on the ball predictor: bounce curve,
        78 inch drop test = 33.6 in, flat / topspin / slice / sidespin landings, speed cap,
        batch predictor). Golden values are 30 Hz; change them only on purpose
  - [x] Unreferenced values removed from `scripts/constants.gd` (ball mass, radius 0.06,
        gravity scale 1.5, max speed, serve height, hit reach). `NET_HEIGHT 0.91` stays: HUD
        markers and the unused dink solver read it
  - [x] 30 Hz net result explained (below)
  - [ ] Singles scoring has no test: it is inline in `game.gd` (`_on_point_scored`), not a
        separate ledger like doubles
  - [ ] Known rule gap (reported by the fault test, not failed): a serve landing on the far
        half of the painted kitchen line counts as good; only the nominal 2.134 m is compared
  - [ ] Unused code still present: `shot_physics.compute_shot_velocity` / `solve_ai_launch`,
        `Ball.serve()`, `game._enter_slow_mo()`, `court.create_walls()`, `MIN/MAX_SERVE_SPEED`

  Run all three: `godot --headless --path . -s tools/rule_tests.gd` (then `fault_tests.gd`,
  `flight_tests.gd`). Each exits 1 on a failure.

  **30 Hz against 60 Hz, 2026-11-19** (scratch copies of the same tree, 6 seeds at 300 s):
  the total is the same, 11.8 endings per 100 shots at both rates, but the mix differs.

  | | 30 Hz | 60 Hz |
  |---|---|---|
  | Points / shots | 93 / 785 | 90 / 765 |
  | Ball in net | 30 | 18 |
  | Out of bounds | 20 | 1 |
  | Double contact | 8 | 0 |
  | Soft ball hit the body | 4 | 25 |
  | Soft ball not returned | 16 | 27 |
  | Dropped shots (`shot_dropped`) | 39 | 10 |
  | Drive launch error, average | 7.75 m/s | 0.17 m/s |

  At 30 Hz the planned shot is dropped four times as often (the ball deflects off the paddle
  instead of taking the solved launch), which is where the extra net and out endings come
  from; drives and lobs are worst. The 60 Hz body hits are not a fair reference: the AI was
  tuned at 30 Hz and some windows are counted in ticks (`OWN_SHOT_LEG_TICKS 8`,
  `RECOVERY_MAX_TICKS 24`, `READY_RECHECK_TICKS 6`), so they last half as long at 60 Hz.
  Next target for rally quality: dropped shots at 30 Hz (about 50 of 93 endings are net or out).
- [ ] G1 Contact skill: one measure for the on-screen grade and the execution error;
      PERFECT narrows the error (accuracy, not power); show why a shot missed
- [ ] G2 The paddle matters: face angle and swing speed bend the solved shot inside limits;
      prototype behind a setting, keep only if playtests prefer it
- [ ] G3 Spin and pace: sidespin rally shots, AI reads spin, test a higher speed cap for smashes
- [ ] G4 Body and stamina: low stamina widens the error; enable the dive; split-step bonus
- [ ] G5 Shots, rules, modes: around-the-post shot, full Erne, difficulty menu (three levels
      and five styles already exist), singles options, rally scoring, serve-motion rule

## AI rally quality (bench)

Goal: fewer faults per shot in all-AI doubles. Compare changes with 6 seeds at 300 s
(about 120 points); 3 seeds at 150 s is about 30 points and too noisy to judge one change.

```bash
for s in 1 2 3 4 5 6; do KEEP=40 tools/bench.sh <name>$s 300 $s; done
python3 tools/shot_report.py logs/bench_<name>[1-6].perf.jsonl
```

Or with a small progress window and log (same runs, 3 at a time, report at the end):
`tools/bench_gui.sh <name> [seconds=300] [seeds=1-6] [jobs=3]`.

Baseline 2026-11-18 (0da2468 plus the arm-recovery, soft-shot pace, net-margin,
cross-court dink and overhead-reach changes): 119 points, 586 shots, 4.9 shots per point.

| Point ending | Points | Per 100 shots |
|---|---|---|
| Net: low kitchen contact (met <= 0.65 m up, within 2.6 m of the net) | 42 | 7.2 |
| Fast ball (>= 10 m/s) not returned | 17 | 2.9 |
| Net: other contact | 15 | 2.6 |
| Fast ball hit the body | 14 | 2.4 |
| Soft ball hit the body | 13 | 2.2 |
| Soft ball not returned | 12 | 2.0 |
| Two-bounce rule | 3 | 0.5 |
| Out of bounds | 3 | 0.5 |
| All | 119 | 20.3 |

Netted resets, drops and lobs left the paddle 7 to 15 m/s lower in upward speed than
planned: the planned shot was not applied and the ball deflected off the paddle.
Keep a change only if its own row drops and no other row rises.

Cause of the low-contact net faults: turning the blade from up (ready) to down (low
reception) is a 0.32 s joined grip change, and the AI started it 0.35 s before contact, so
the paddle was often edge-on when the ball arrived and the planned shot was dropped
(`shot_dropped` notes in the perf log: 53 in the baseline, 51 of the 57 net faults).

After starting low and mid-low alignment 0.6 s ahead (`ALIGN_LEAD_SECONDS`, first for low poses only), same 6
seeds: 116 points, 659 shots, 5.7 shots per point, 17.6 endings per 100 shots.
Net: low kitchen contact 7.2 -> 3.6; dropped shots 53 -> 33; high balls smashed 1 of 11
-> 7 of 12. Open: soft ball hit the body rose 2.2 -> 4.1 (13 -> 27 points), not yet
explained; Low Backhand now has the most dropped shots (15 of 33).

Body hits explained (`body_hit` notes): 27 of 40 struck the thigh, 22 of them on an
incoming low ball with the paddle planned centimetres behind it, 8 were the hitter's own
shot clipping a leg. Best-effort chase and the AI lunge call fix changed nothing
measurable (18.2); the "nobody can reach it" case is rare.

After letting the ball pass a player's own thighs and shins during a low reception and
just after their own hit (`_legs_pass` in `match_contact_authority.gd`), same 6 seeds:
109 points, 667 shots, 6.1 shots per point, 16.3 endings per 100 shots. Soft ball hit the
body 3.9 -> 0.9. Open: those balls now reach the paddle and many are dropped into the net
(net: low kitchen contact 2.8 -> 3.9, dropped shots 33 -> 40), so the late paddle turn on
low receptions is the largest remaining cause.

Later the same day, same 6 seeds, each step benched on its own:

| Step | Endings per 100 shots | Shots per point | What moved |
|---|---|---|---|
| Meet a bounced ball higher (`RISE_CONTACT_HEIGHT`) | 14.9 | 6.7 | net faults 42 -> 32 points; soft ball not returned 15 -> 25 |
| Resets land cross-court / middle / line | 17.4 | 5.8 | placement left 203, middle 179, right 168; soft ball not returned 25 -> 42 |
| Prefer contacts with spare run (`RUN_SLACK`) | 14.3 | 7.0 | soft ball not returned 42 -> 10; out of bounds 8 -> 21 |
| Early paddle turn for every pose (`ALIGN_LEAD_SECONDS`) | 11.8 | 8.4 | soft ball hit the body 13 -> 4; dropped shots 47 -> 39 |

Misses on soft balls were footwork: the run bound is optimistic (no braking), so a
contact needing all of it was 0.6-1.4 m short at contact time. Open: 39 dropped shots
remain and cause most out-of-bounds (20) and net (30) endings, mainly the Forward pose on
deep balls met at about 1 m while still rising; double contact 8; `RISE_CONTACT_HEIGHT`
and `RUN_SLACK` weights are first guesses, not tuned.

## Guardrails (every phase)

- **Gameplay must stay identical.** Run the seeded bench with and without the change and
  diff the poses; the result must be `IDENTICAL`:
  ```bash
  tools/bench.sh base 30 1      # on the commit before the change
  tools/bench.sh new 30 1       # with the change
  python3 tools/pose_diff.py logs/bench_base.pose.jsonl logs/bench_new.pose.jsonl
  ```
- **Never add visuals under a player's `BodyPivot`.** Gameplay scans every mesh there
  (surface contacts, geometry certificates); the first card prototype changed play this way.
- Hide classic meshes from the camera; do not delete them while gameplay reads them.
- Measure performance on device before and after; record it here.

## References

- Design proposal (31-page PDF) and all generated pixel art, UI, effects and the art
  generator scripts: branch `archive/main-wip-2026-11`, folder `docs/`
  (`docs/PICKLEBALL_2.5D_PROPOSAL.pdf`, `docs/pixel_art_test/`).
- Proposal with Part 2 (physics and mechanics, 41 pages): `docs/PICKLEBALL_2.5D_PROPOSAL.pdf`
  on this branch. Rebuild with `docs/proposal_pdf/build.sh` (needs reportlab and pypdf).
