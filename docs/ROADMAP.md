# Pixel Pickleball: Roadmap

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
3. ~~Far-court card tier~~: done 2026-11-24 (half-size, 20 degree set per profile, picked by
   distance to the camera). Look at it on the phone with the 1/3 pixel viewport.

## Phases

Status: done, in progress, next, later.

### Phase 0: Performance baseline (in progress)
Current plan for steady 60 fps and a cooler phone (phone data, solver bake, hitch fixes):
`docs/PERFORMANCE_PLAN.md`.
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
- [x] Far-court card tier (20 degrees, half size): `<id>_<team>_far.png` from
      `tools/bake_pixel_cards.py`, swapped in by `pixel_card_rig.gd` for players beyond the net
- [ ] Hand states (open / grip / reach) from the articulated hand mode
- [ ] Joint seams (elbow, knee) and draw-order polish
- [ ] iPhone check

### Phase 2: Pixel viewport and camera (next)
- [x] Render 3D at 1/3 resolution with nearest upscale (one pixel grid for court, players
      and effects); UI stays full resolution on top. Done 2026-11-24 with the root viewport's
      own 3D scale (`scripts/graphics/pixel_post.gd`), not a SubViewport, so the camera and
      every screen-position test keep the full-size viewport
- [x] Portrait framing and ball-on-screen logic: camera identical at 1/2 and 1/3
      (`tools/pixel_grid_check.gd`); the ball cue is sized in screen pixels and carries a
      2-pixel dot when the ball is under 2 render pixels (far baseline: about 1.2)
- [ ] iPhone check of the 1/3 look and its frame time
- [ ] Optional: steeper 3/4 camera as an A/B option (keep the current camera by default)

### Phase 3: Art pass (later)
- [ ] Final hand-painted cards over the generated ones (5 drawn views + mirrors)
- [ ] Team palette-swap shader for skins and cosmetics
- [ ] Six player sprite profiles (3 female, 3 male): `docs/CHARACTER_VARIANTS_PLAN.md`
- [ ] Court / arena textures in pixel style, baked lighting
- [x] Barangay court world (2026-11-22, branch `court-environment`, replaced a short-lived
      beach): cement slab with cracks, patches, stains, faded basketball lines and a green
      kitchen; red curb with chipped corners and a gutter; bamboo net poles in hollow blocks;
      a two-storey house, barangay hall and flag, sari-sari store, tricycles, power poles with
      banderitas, background houses; a crowd, queue, scorer and animals that react to the match
      (paddle hits, bounces, rally end reasons, serve, post hits, score). All real low-poly 3D
      with three-band toon shading, pixelated by PixelPost: `scripts/environment/`,
      `shaders/env_*.gdshader`. Bench pose diff IDENTICAL; 0.02 ms/frame on the Mac

### Phase 4: Effects and feel (later)
- [ ] Effects sprite sheet: impact burst, spark ring, bounce, dust, swing arc, speed lines,
      landing marker, smash flash, out stamp, ball trails (pooled through `fx_pool.gd`)
- [x] Rally moments (2026-11-23, `scripts/fx/rally_moments.gd`, own RNG): point-won confetti
      (more after long rallies), PERFECT sparks + white card flash (`flash` uniform in
      `pixel_card.gdshader`), rally-end stamp (OUT / NET / KITCHEN / WINNER!), rally counter
      over the far baseline from shot 6 with milestone pops every 5 from 10. Notes
      `rally_moment` in perf.jsonl. On-device look not yet checked
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

## Motion smear (2026-11-25, build 119, not yet judged on the phone)

Fast limbs leave a short trail of their own texels (`shaders/pixel_card.gdshader`, Settings > Video >
Motion smear, `video.motion_smear` 0-1, default 0.6). The motion is real: the per-tick card build already
stores each corner now and one tick ago, so the shader knows how far each part moved. A part moving over
5 texels a tick (about 4 m/s) smears; opaque pixels stay untouched, the trail is dithered on the art's
own texel grid and capped at 6 texels. No full-screen pass and no extra buffers. Off in first person,
pause and pose editors (no tick build there). Next if liked: the same for the paddle (it is a 3D mesh,
it needs its previous transform as a uniform). Not planned: full-screen camera blur (the camera barely
moves, and a screen pass costs fill rate on the phone).

**Build 120:** the user could not see the card-only smear on the phone, so it is bolder (from about 3 m/s,
up to 12 texels, default strength 1) and the ball has its own motion blur: the drawn ball is stretched
back along its flight by one tick of travel (`scripts/fx/ball_trail.gd` `_place_blur`, uniform `motion` in
`shaders/ball_shape.gdshaderinc`), from 3 m/s, at most 0.6 m, never past the last bounce or hit, dithered
out toward the tail. The front of the shape is the real ball. One slider drives both.

**Build 121, realistic motion blur (user asked for a camera-like blur on body, ball and paddle):**
the dithered smear is gone. Body: each card pixel averages 8 reads of the art along the way the part came
during the exposure (half a tick = 1/60 s at strength 1); fully covered pixels are drawn solid, partly
covered ones by a second, alpha-blended pass (`shaders/pixel_card_soft.gdshader`, same code through
`pixel_card_body.gdshaderinc`), chained on only for players with a card moving over 0.9 m/s. Ball: the
ball stays whole and sharp; a third pass (`shaders/ball_tail.gdshader`) draws it stretched back along its
flight, see-through and fading out. Paddle: five see-through copies between last frame's place and this
one (`scripts/graphics/paddle_skin.gd` `_blur`). One slider (Settings > Video, 0-2). Open: GPU cost on
the phone, and whether soft edges on running bodies are wanted or only on swings (BLUR_FROM in the
shader body).

**Build 122, steadier body blur (user: the card blur was sometimes jittery):** the blur's motion no longer
comes from the card's corners (they jump when a limb changes drawing or flips, so the blur vanished for a
tick). Each card's two joints give its motion per tick, eased over a few ticks (55% of the way each tick)
and stored per corner in a second mesh attribute (CUSTOM1; `pickle_cards.cpp` and its script twin). The
shader eases the blur in over 3 texels of blur length, from the sharp sun-shaded pixel to the exposure's
average, instead of switching between two looks. Measured: the blur drops out in 1 of 8,628 moving samples.

**Build 123 (user: the paddle blur read as ghost copies, and the ball's blur was sometimes missing):**
Paddle: no copies any more. Its parts are drawn once more through `shaders/paddle_blur.gdshader`, which
puts every vertex on the trailing side back where it was at the start of the exposure (the part's whole
earlier transform, so turn and travel are both followed) and fades the stretched faces out: one
continuous streak. The edge band takes the face's average colour, since the face is what passed through.
Ball: the blur now follows the drawn ball's own frame-to-frame motion instead of the trail's path history,
which restarted at every bounce and hit; it is on in 92% of frames flying over 5 m/s (hit stops and the
ease-in below 7 m/s are the rest).

**Build 124 (user: make the ball's blur realistic):** the streak in `shaders/ball_tail.gdshader` is now as
wide as the drawn ball (outline included, so it meets the ball's silhouette), falls off toward the sides,
is evenly exposed along its length (more see-through the longer it is) with a round fading end, and uses
the ball's mid tone with a little of its shading. Before it was a thinner flat-colour strip that faded
linearly from the ball.

**Build 125, stretch blur (user asked for it for forward motion):** motion toward or away from the camera
hardly crosses the screen, so forward swings and flights blurred less than sideways ones. Its on-screen
length is now given back 70% of the way to what the same speed would show sideways, at most 2.5 times
longer, direction unchanged: in the card shader (`DEPTH_STRETCH`), the ball's streak
(`BLUR_DEPTH_STRETCH` in `fx/ball_trail.gd`) and the paddle's sweep (`paddle_skin.gd`). A deliberate
exaggeration: a real camera does not do this.

**Build 126 (user: the ball should look like an oblong in flight, not a ball with a streak):** the streak
pass is gone (`ball_tail.gdshader` removed). The ball's own body and outline are lengthened back along
the flight into an ellipsoid (`shaders/ball_shape.gdshaderinc`): front tip at the real ball's front, rear
tip one exposure behind. Extra length = travel in 1/80 s at strength 1, from 3 m/s, at most 0.2 m (0.32 m
with the depth stretch); the drawn ball is 0.11 m across. Round when slow, held or frozen.

**Build 127 (user: add blur to the oblong, and no outline along the part that lengthens):** the ball is
again drawn whole and round at its real place. Behind it `shaders/ball_soft.gdshader` draws the ball
lengthened into an ellipsoid along the flight, see-through, fading to the rear tip and thinning toward
its sides, pushed a ball's width back in depth so the round ball always covers it. The outline
(`ball_readability.gdshader`) is left open on the side of the screen the blur comes out of. Extra length:
travel in 1/55 s at strength 1, at most 0.3 m. Tried and dropped: making the front part of one stretched
ball solid and the rest see-through; for a ball flying away the see-through rear faces the camera and the
ball looked hollow.

**Build 128 (user: the oblong back, with a linear blur along the direction and more stretch on the tail):**
the ball in flight is a solid oblong again (body and outline lengthened into an ellipsoid, front tip at the
real ball's front; extra length = travel in 1/95 s, at most 0.14 m). The outline is open at its rear.
Behind it `shaders/ball_soft.gdshader` draws the same shape 2.8 times longer (`tail_lengthen`),
see-through, its opacity falling in a straight line along the flight from 0.85 at the ball to 0 at the
rear tip, pushed back in depth so the solid oblong covers it. Open: motion blur does not yet shrink in
slow motion (all three effects measure game time); the user was asked and has not decided.

**Build 129:** (1) Motion blur shrinks with slow motion: ball, paddle and card blur are multiplied by
`Engine.time_scale` (the exposure is real time; at 30% speed the blur is 30% as long, gone near a freeze).
(2) Pickleball holes on the ball (`shaders/ball_body.gdshader`): 32 darker dots fixed to the ball's
surface, turned by the ball's real angular velocity (`fx/ball_trail.gd` `_turn_holes`; the drawn mesh
itself never rotates). They fade out as the ball lengthens in flight and only show when the ball is drawn
more than 6.5 pixels across (full from 11): smaller than that a hole is one stray dark pixel. In normal
play the ball is mostly below that size, so the holes show in close views. Not verified: the slow-motion
scaling in a real slow-motion moment, and the holes rolling (the ball had no spin in the test match).

**Build 130, resolution setting:** Settings > Video > Resolution of the 3D view (`video.resolution`):
Default (the build's own: 1/3 on main, 1/2 in the phone builds), Low 1/3, Medium 1/2, High 2/3, Full.
`scripts/graphics/pixel_post.gd` applies it at once (viewport 3D scale, the upscale shader, and the size
other effects read). UI stays full resolution. Pixel count grows with the square of the share: Full draws
four times the pixels of 1/2. Its cost on the phone's frame rate is not measured yet.

**Build 131, the ball's holes roll:** the game's own spin is zero on most shots, so the holes never turned.
The shown ball now rolls forward along its flight like a ball with a little topspin (`fx/ball_trail.gd`
`_turn_holes`: 1.6 rad/s per m/s of speed, between 2.5 and 12 rad/s, so under two turns a second and about
7 degrees a frame), or with the shot's real spin when it has any. It runs on game time, so it turns slowly
in slow motion. It is not turned while the ball is lengthened by blur (user: on a fast ball the spin cannot
be seen, so it is useless there); the holes are faded out then anyway.

**Build 132, more graphics switches (Settings > Video, all on by default):** motion blur on the ball, on the
paddle and on the players, each its own checkbox (the slider stays the common strength); ball holes;
sun shading on the players (the stepped light and shade bands and rim); colour grade (contrast,
saturation, warm light, split tones in `pixel_post.gd`); vignette. They apply while playing: the post
ones at once, the others within two seconds (they are read on the 2 s sweep each effect already has).

**Build 133, player shadows:** (1) Gaps at the joints: each card is a flat picture turned to the camera and
set nearer or further for draw order, so slid along the sun the cards of one body landed apart and the
shadow broke into blobs at knees, elbows and hips. Every card's shadow is now grown by 1.5 atlas texels
(`shaders/card_shadow_body.gdshaderinc` `grow`), which joins them. (2) Lens blur: the serve-aim and
slow-motion lens blurs what is drawn before it; player shadows are drawn after it and stayed sharp on a
blurred court. While the lens is on (`ground_shadows.gd` `lens_soften`, set by `solo_aim_focus.gd`) a
second pass (`card_shadow_soft.gdshader`) adds a soft rim up to 2.5 texels wide outside each shadow. Not
yet softened the same way: the ball's blob shadow and the motion blur passes.

**Build 134 (user: the shadows are too fat):** the growth that closes the joint gaps is no longer on all
sides. Each part's shadow is only lengthened, 1.25 texels (3.5 cm) at both ends along the part's own
length, so limbs reach into the next part and nothing gets wider. If gaps come back at this size, the
root fix is to give the shadow pass true joint-to-joint positions instead of the camera-facing cards'.

**Build 135, shadow joints fixed at the root (user: the joints of the shadows are what is broken):** the
shadow is no longer the camera-facing cards slid along the sun. Each part casts its true shape: from its
joint, along its real joint-to-joint length, as wide as its art, turned to face the sun. The card
builders (`native/src/pickle_cards.cpp` and the loop in `pixel_card_rig.gd`) store that per corner as an
offset from the card's corner in a third mesh attribute (CUSTOM2), and the shadow shader adds it, so limbs
meet exactly at knees, elbows, hips and shoulders. No growth or lengthening any more (`grow` 0). Card
cost on the Mac 9.6 -> 10.05 ms/s.

**Build 136 (user picked the old shadow's look from the build-135 comparison):** the shadow shapes are no
longer turned to face the sun, which made a thinner, stick-like figure. Each part's shadow keeps the
card's own picture, turn and width, and is only moved to where the part really is: its real joint, its real
joint-to-joint line, and without the draw-order push along the view. Same full silhouette as before the
shadow work, with the parts joined at their joints.

**Build 137 (user's photo-mode screenshot: the shadow breaks into a fan of thin lines from another
angle):** build 136 kept the cards' camera-facing turn for the shadow, so with the camera near the sun's
line every card was edge-on to the light and its shadow collapsed. The shadow shape now contains no
camera at all: the part's real joint, its real line (its own up for head, chest and hips), turned to
face the sun, 1.15 times the art's width (`SHADOW_WIDEN`) so it stays about as full as the old shadow
read from the match camera. The shader flattens it onto the court, so it is the same from every angle.

**Build 138, paddle and ball shadows by the sun:** (1) The paddle casts a shadow: its materials draw the
mesh once more flattened onto the court along the light (`shaders/mesh_shadow.gdshader`, one shared
material from `ground_shadows.gd` `mesh_shadow_material`), with the players' shadow stencil so paddle,
hand and arm darken the court once. (2) The ball's shadow follows the sun like the players' (user's
request; it was straight under the ball by the earlier spec): its oval is placed where the light from
the ball meets the court and drawn out along the light (up to 2.2 times its width). It still shrinks and
lightens with height. The ball's spot directly below it, which read as a landing and height cue, is gone.

**Build 139, motion blur on the shadows:** players: the soft shadow pass that already made the lens rim
also draws a trail behind a fast limb's shadow, as dark as the share of the exposure the shadow covered
that spot (`card_shadow_body.gdshaderinc` `smear`; the solid shadow itself is unchanged, so overlaps
still darken once). Paddle: the motion-blur sweep casts its own fading shadow
(`shaders/paddle_blur_shadow.gdshader`). Ball: its oval is drawn out along the way the shadow moves over
the court and lightened to match (`ground_shadows.gd`, at most 0.3 m longer). All three follow the blur
slider, the per-part switches and the slow-motion scaling.

**Build 140, quick Photo button:** a small PHOTO button under the Guide / Pause buttons on the match
screen (`scripts/ui/hud.gd`). One tap pauses the match and opens photo mode
(`PauseController.open_photo`); DONE in photo mode resumes the match instead of stopping at the pause
menu. Settings > Video > Photo button on the match screen (`video.photo_button`, on by default) hides it.
Photo mode from the pause menu works as before.

**Build 141:** (1) The quick photo button is a pixel camera icon above and to the right of the HIT pad on
the touch layout (1.8 pad radii from its centre, outside its touch circle); without touch controls it
stays under the toolbar. (2) Motion blur is frozen in photo mode and under the pause menu: pausing used
to drop the limb blur, its shadow trail and the paddle sweep, and let the ball's decay. Each effect now
keeps the state it had at the moment of pausing; the limb and shadow blur follow the photo camera as it
moves, since their shaders read the stored motion in view space every frame.

**Build 142, rewind in photo mode:** a REWIND slider steps back through the last 3 seconds, one physics tick
per notch (30 a second). `scripts/fx/photo_history.gd` records, each tick, the joints every player's cards
and paddle are drawn from and the ball's place, blur and spin. Showing a past tick places only the joints
under each player and the drawn ball (the players' bodies and the ball's physics body never move), draws
the two ticks before it first so the cards carry that moment's motion blur and shadow trail, and gives the
paddle its sweep from the tick before. Closing photo mode puts every joint back exactly (verified: 73 of
73 transforms identical) and play resumes from the moment it was paused. The camera button is bigger
(as wide as the HIT pad's radius). Not in the history: the crowd and background animation, UI, particles.

**Build 143, rally replays:** every rally is kept in memory from the start of the serve to a second after
the point (`scripts/fx/photo_history.gd`, the same per-tick records as the rewind). Saving: the REC button
above the camera icon saves every rally by itself while it is on; while it is off a SAVE RALLY? button
comes up for 6 seconds after each point (Settings > Video: Save every rally, Ask to save the rally after
each point). Files: `user://rallies`, compressed, about 74 KB per second of rally (a 28 s rally is 2.1 MB),
the 10 newest kept. Watching: photo mode > RALLIES lists them (newest first, scrollable) with the live 3
seconds on top; the slider scrubs the whole rally and PLAY runs it at match speed, with the photo camera
free. A rally only plays in a match with the same players (same joint lists); rows that do not fit are
greyed. Open: the save itself may take a noticeable moment for a long rally (not measured), and the file
format stores full transforms where position + rotation would halve it.

**Build 144, realistic starts and stops (user: players speed-glide, wants realistic footwork and paddle
speeds):** measured from a bench trace, a player went from standing to 3 m/s in 0.17 s and stopped as
hard, which the legs cannot show: that is the glide. Accelerations are now 7 / 8 / 9 m/s2 for the AI by
level (were 12 / 14 / 16), brakes 10 / 11 / 12 (16 / 18 / 20), lunge push 15 (26); your own player 18 to
speed up, 24 to reverse, 16 to stop (72 / 84 / 34). Top speeds are unchanged. Now: 0.30 s to 3 m/s, 0.50 m
per step (0.42). The AI plans its reach with the same numbers. Three seeds: all animation rules pass, 16
points and 182 hits (about 11 hits a rally). Paddle speed was already in a real range (swings peak at
10-19 m/s at the tip); two single-tick jumps over 25 m/s per 120 s remain. Open: 0.30 s to 3 m/s is still
quicker than a person (about 0.5 s); going further shortens rallies. Your player's feel is for the phone
to judge (the all-AI bench cannot see it).

**Build 145 (user: the 3-second rewind in photo mode gone; save performance while recording rallies):**
the always-on 3-second history is removed. `scripts/fx/photo_history.gd` now reads the players' joints only
while a rally is on (serve to one second after the point), and only if a rally could be saved at all (REC
on, or the save question on): 0.42 ms/s on the Mac in rallies, 0 while waiting, against 0.60 ms/s always
before. Photo mode opens on the paused moment as it used to; the scrub slider and PLAY appear when a
saved rally is picked from RALLIES, with a row to go back to the paused moment. Further savings not
done: record every second tick and blend on playback (half the cost and file size), store position +
rotation instead of full transforms (about 40% smaller files), write the file over several frames.

**Build 146, rally recording in C++ (user: no performance loss from creating replays):**
`native/src/pickle_replay.cpp` (class PickleReplay) records a rally tick in 2.3 microseconds: 0.07 ms per
second of rally on the Mac (the script recorder: 0.42; before build 145: 0.60 at all times), and nothing
outside rallies. The rally is kept as one flat block in the file's own layout, handed over by a swap when
the point ends, and written and compressed on a worker thread, so a save costs the match about 0.3 ms.
Playback places the joints straight from the block. `scripts/fx/photo_history.gd` keeps the script
recorder as the twin and fallback; both write and read the same file (checked: the script loader reads
the C++ files, positions within a micrometre).
