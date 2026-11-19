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
2. **Expose Classic / Pixel in the Settings panel** (`video.character_style`, already in
   `scripts/ui/settings.gd`), so playtesters can compare.
3. **Far-court card tier:** bake a 20 degree, half-size card set and pick the tier by distance
   to the camera (far players currently reuse the near set).

## Phases

Status: done, in progress, next, later.

### Phase 0: Performance baseline (in progress)
- [x] PerfMonitor autoload, spike log, F3 graph, `tools/perf_report.py`
- [x] Seeded benchmark + pose trace (`tools/bench.sh`, `tools/pose_diff.py`)
- [x] Physics catch-up cap, IK once per player per tick, READY recheck at 10 Hz, AI re-plan cap
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
- [ ] Classic / Pixel toggle in the Settings UI
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
  - [ ] Classic 3D bodies (`video.character_style` = 0) show the skin too? Check
  - [ ] iPhone check (60 fps feel; lag is per frame, so it reads the same at any frame rate)

### Phase 5: UI (later)
- [ ] Pixel UI kit (5x7 font, bevelled panels without black outlines)
- [ ] Compact score pill, one-line coach toast, pixel joystick, HIT and shot wheel
- [ ] Same inputs and touch targets as today

### Phase 6: Ship and retire classic bodies (later)
- [ ] On-device performance pass against the Phase 0 baseline
- [ ] Remove the Classic option only after gameplay stops reading body meshes
      (foot mesh bounds in `player_nvz_state.gd`, `match_grounded_reach.gd`,
      `between_pose_admission.gd`, `fast_point_transition.gd`; hand / torso meshes in
      the between-point and surface-contact code)
- [ ] Release build

### Later: Gameplay v2 (planned 2026-11-19)
Stance: keep the solved shot (pick a target, the game finds the swing); make skill show
in the result. Full inventory, gaps and decisions: Part 2 of the proposal PDF, pages 32-41.
Each package is gated on the 6-seed bench and `tools/shot_report.py`.
- [ ] G0 Safety net (does not change play, can start now): rule tests for faults, kitchen,
      serve and singles; a fixed-flight test; remove stale values in `scripts/constants.gd`
      (ball radius 0.06, net 0.91, gravity scale 1.5); explain the 30 Hz BALL_IN_NET rise
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
  PICKLEBALL_CLASSIC_BODIES=1 tools/bench.sh base 30 1
  tools/bench.sh new 30 1
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
