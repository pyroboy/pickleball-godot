# Performance plan: steady 60 fps, cooler phone

Goal: hold 60 fps for a whole match on the iPhone 15 Pro without the phone heating up.
Rules that stay: 60 fps is the default, Adaptive drops to 30 only when the phone cannot hold
60 (`settings.gd` video.fps_mode); savings come from doing **less work**, never from fewer
frames. Solvers belong in Pose Studio; matches play back baked poses.

## Where we are (phone data, 2026-11-25)

Source: the phone's `Documents/perf.jsonl` after a 3.7-minute doubles match on build 108
(golden hour, projected shadows, 3D render scale 1/2). Pull it with
`xcrun devicectl device copy from --device 00008130-001675341460001C --domain-type appDataContainer --domain-identifier com.arjomagno.arjostylepickleball.ios --source Documents/perf.jsonl --destination <file>`.

- **60 fps never held.** Adaptive tried 60 three times (start, 0:55, 2:30) and gave up each
  time; slow-frame share 26% -> 49% -> 50% as the phone warmed. Most of the match ran at 30.
- **Throttling:** the same player physics cost 5.5 ms/frame in minute 0 and 7.7 in minute 2.
- **Dropping to 30 fps barely cools it:** physics runs at 30 Hz whatever the frame rate.
- **Hitches:** 64 frames over 50 ms (median 56, max 180), 52 of them mid-rally, almost all
  on a physics tick.
- **Load:** about 1.3 s frozen when the match world is built; the floor / wall bakes also run
  at the title screen. Shadow-mask bake: 10 ms on the phone (fine).

### Steady load: script CPU, ms per second of play (1000 = one core busy)

| Scope | ms/s | Kind |
|---|---|---|
| player.physics (parent of the solver rows below) | 124 | |
| between.physics (walks, pickup, ball kid) | 62 | between-point paths |
| pp.paddle_tracking + pp.align | 77 | solver |
| contact.authority + contact.capture | 69 | contact checks (also between points) |
| human.update | 39 | your player's planner |
| card.rig + card.motion | 49 | drawing |
| leg.ik + leg.solve + leg.live_arm_reach | 62 | solver |
| arm.ik, al.ready, arm.budget, arm.around_body, reach.wrist_budgets_fit | 48 | solver |
| bp.present_arm_path, bp.make_pose, cup.candidate | 34 | between-point solver |
| env.barangay (crowd, flags) | 22 | world animation |
| surface.snapshot | 18 | body shape for the arm checks |
| ai.input + planner.* | ~40 | AI planning |
| proc.input_handler + input.charge | 28 | touch input |

Runtime solvers alone: about 240 ms/s, a quarter of a core all match long.

### Inside the rally hitches (ms per hitch, top scopes)

| Scope | ms |
|---|---|
| pp.paddle_tracking | 6.5 |
| human.update | 6.4 |
| input_handler + input.charge + mobile_controls | 5.2 |
| pp.align | 3.0 |
| planner.select + planner.extended | 2.2 |
| contact.authority | 1.3 |

Your own player re-plans the contact every tick while HIT is held. The bench plays AI only,
so this path has never been measured or tuned there.

### Not measured

GPU time: the log cannot time graphics on this renderer. Render scale went 1/3 -> 1/2 in build
108 (2.25x the 3D pixels). Draw calls about 110; projected shadows add 4.

Engine-side tick time is not measured either: the scopes cover about 9 ms of the average
rally tick; collision, `move_and_slide`, transform updates and interpolation are outside them.

## Review, 2026-11-25 (second look at the same phone log)

### How the hitches really happen: catch-up double ticks

- 46 of the 62 hitch frames after start-up (74%) ran **two physics ticks in one frame**
  (8 `player.physics` calls instead of 4); median frame 56 ms. Only 9 were one heavy tick,
  7 had no player physics at all.
- They come in clusters: 25 of 61 follow the previous hitch within 0.2 s.
- Chain: at the 30 fps cap frames should be 33.3 ms, but the slowest 5% each second average
  42.5 ms (likely cause, not yet verified: `Engine.max_fps` sleeps instead of following the
  120 Hz display, so a frame sometimes lands one refresh late). Late frames pile up time, the engine then runs 2 ticks in
  one frame to catch up (`max_physics_steps_per_frame=2`), that frame takes about 56 ms, which
  piles up more time, and so on.
- Hitches do **not** follow ball hits: 7 of 51 rally hitches fall within 0.25 s after a hit,
  about what chance gives (17% of rally time). Spreading the players' re-planning across
  ticks after a hit would not help; it was checked and dropped.
- Single heavy ticks exist but are the minority: `human.update` up to 22.9 ms in one call,
  `contact.authority` 9.2 ms, `proc.mobile_controls` 67.8 ms once (a one-off, likely first use).

### Frame budget: what 60 fps needs

`phys_ms` and `cpu_ms` in the log are the **worst** tick and the worst process + draw frame of
each second (Godot reports the maximum, not the mean).

| Phone, rallies | Average (scopes) | Worst each second: mean / p90 |
|---|---|---|
| Physics tick | about 9 ms + engine time | 16.4 / 22.1 ms |
| Process + draw | about 5 ms + draw | 9.6 / 13.8 ms |
| Between points: tick | | 9.3 / 13.7 ms |

At 60 fps a frame is 16.7 ms and every other frame carries a tick. The average tick frame is
already near the limit (9 + 5 + draw) and the worst one each second is 26 ms, so 26-50% slow
frames is what the numbers predict. 60 fps holds only when the **worst** tick plus the worst
process + draw fit in the frame, hot. Proposed budgets (phone, after minute 3):

| | Budget |
|---|---|
| Worst tick each second | 6 ms (average 3) |
| Worst process + draw each second | 7 ms |
| Headroom for throttling | 3.7 ms |
| Between points, tick + process | under a quarter of the rally cost, so the phone cools between rallies (40% of match time is between points) |

**Done when:** a 10-minute doubles match on the phone holds 60 with under 2% slow frames, no
frame over 50 ms in rallies, Adaptive never drops, and the same work costs under 15% more in
minute 10 than in minute 1.

### Checked and fine (no step needed)

- Node count: 655 on the phone (the hidden 3D body is 48 nodes per player).
- The real sun's shadow pass is already off on the phone (`video.shadow_quality` 0).
- Profiler overhead: 165 `PerfMonitor.record` calls per frame at 0.3 microseconds each on the
  Mac (measured), about 0.05 ms per frame there and a few times that on the phone; perf notes
  are 1.3 rows per second.
- Shadow-mask bake: 10 ms on the phone.
- Godot 4.6.3 has no nearest-neighbour 3D scaling mode, so the PixelPost pass (one
  full-screen copy plus the upscale shader at native resolution) cannot simply be dropped.

## Remaining work: Mac-checked (user, 2026-11-25)

The user is not in the loop per step: every step is measured on the Mac, and the phone is
only a final check (a build installed when a batch of steps is done; the user plays when
convenient and `tools/phone_perf.sh` reads the log). Phone cost is about 2-3x the Mac's.

**Mac checks per step** (all switches in `PerfToggles`, A/B on the same tree, back to back):
- Tick cost, all-AI: `SERIAL=1 tools/bench_seeds.sh` budget line (scoped tick, worst tick) and
  per-scope ms per rally frame, against a run with the step's switch off.
- Your player: `tools/human_seat_bench.sh` (switch off vs on). This bench is NOT deterministic:
  five "all on" runs of seed 1 gave 26-65 ms/s for the seat. Run 3 each way, compare medians and
  ms/call, not one run. (2026-11-25: all off 121 ms/s, all on 26-65: the step-1 switches help;
  the phone's higher human.update in build 110 came from the match, not the switches.)
- Visual-only: `tools/motion_bench.sh` (gameplay joints IDENTICAL) + per-frame card / env scopes.
- Gameplay moved: the bench reports what moved (hits, points, animation rules); keep if the
  rules PASS and nothing got clearly worse.
- Mac budget targets (phone budget / 2.5): worst tick 2.4 ms, scoped tick average 1.2 ms.
  perf_team: worst 12.5 ms, average 4.19 ms. After the step-3 round below (seed 1, 90 s,
  serial): average 2.59 ms, worst 9.9 ms.
- A switch can be turned off for one bench run: `TOGGLES=name=0,other=0 tools/bench.sh ...`
  (or `bench_seeds.sh`); the human-seat bench has the same option.

### Step-3 round, 2026-11-25 (Mac-checked; build 115 is on the phone)

No pose baker exists yet. This round made the runtime solvers cheaper or removed them:

- **Same results, less work (no switch; pose-identical to the tree before, 90 s):** typed pose
  blend (`PostureDefinition.lerp_with`), one stance basis and one travel weight per body frame
  (`stroke_body_pose.gd`), around-body check with one body frame per call, kitchen ground scan
  from a cached mesh list with cheap exact rejects, aero-step setting cache, flight-trace post
  pre-check, grip fit by first fitting elbow plane with both turn directions searched together
  (32,512 checks against the old code, 0 mismatches).
- **Same results, cached (`pose_math_cache`):** body-offset cap per pose and player, swing keys
  (drive definition, Wind-up / Finish keys, the exact Wind-up and Contact samples) per contact
  pose and shot inputs, each checked against `PostureDefinition.content_signature()`.
- **Results move slightly (one switch each, all on):** `swing_restore_light`,
  `hand_turn_closed_form`, `contact_sweep_share`, `nvz_once_per_tick`, `grip_fit_once`,
  `shot_solve_early_exit`, `simple_hands`, `shot_presolve`, `simple_hand_shape`.
- **`shot_presolve` (worst tick):** the AI's launch search for its planned shot runs once, a
  few ticks before contact, from the predicted contact point; only its flight time is kept.
  The hit tick solves that one flight time from the real contact point (full search when it
  is not feasible from there, the plan changed, or contact is over 0.5 m off). The drop search
  also skips, exactly, candidates that cannot beat the best score. Your own shots still search
  on the hit tick.
- **`simple_hand_shape`:** the hand the ball can touch is the palm as one box (12 triangles,
  rigid) instead of the skinned hand (702 triangles on 17 bones); a hand counts as on the
  paddle when its grip point is within 1.2 mm of it. Fingers are no longer a surface. Set when
  a match is built. The finger skeleton is still there: serve, pickup and dive code write it.
- **`simple_hands` (user, 2026-11-25: no 3D fingers, no complicated wrist or fingers; the pixel
  cards draw the hands):** grip as posed (no grip-roll fit for your held pose, the AI's or your
  planned contact), no wrist-budget / free-hand separation / finger re-shaping in rallies, and
  a wrist past its comfort budget no longer refuses a hit or a serve. Serves and between
  points keep their hand path (they hold and release the ball).

| Mac, seed 1, 90 s, serial | Before | After |
|---|---|---|
| Scoped tick, average | 4.54 ms | 2.66 ms |
| Worst tick each second, mean / p90 | 13.0 / 19.9 ms | 8.0 / 9.5 ms |
| player.physics | 134 ms/s | 78 ms/s (71 before the pre-solve moved the shot search into it) |
| Settling a hit (contact.settle_shot) | 3.5 ms | 1.5 ms |
| Human seat (3 runs) | 47-57 ms/s | 14-28 ms/s |
| Held-HIT pose, per call / worst call | 1.4-3.0 / 7.5 ms | 0.4 / 0.7 ms |

3 seeds, everything on (p3_k3), against the same seeds with the result-changing switches off
(p3_r0): all animation rules PASS; paddle-to-ball over 15 cm 2 of 202 (base 7 of 247); late
pose switch 0; snap-back 1.5% (base 1.6%); wobble 8% (base 9%). Points: 5, all ball in net
(9 before the last two switches: 5 double bounce, 4 net). Too few points to judge how rallies
end: look at it on the phone.

**What is left, by Mac cost (ms/s in a rally):** card drawing 44 (every frame), legs about 20,
contact checks about 12 without the arms, AI input 11, crowd 9, pose blends about 10, arms 5.
**The worst tick is still the tick of a hit:** about 8 ms on the Mac.
**Phone, build 111 (first log of this round):** the tick is cheaper but 60 fps still does not
hold, and most slow frames have little script time in them: the next thing to learn is where
the rest of those frames goes (graphics, step 0 / step 4), not more tick work alone. On the
script side your own seat leads: human.pose (30 ms/s, one call up to 23 ms) and the human
planner (planner.select + extended, 21 ms/s at 10 plans a second).
**Where the phone stands (build 112, three sessions):** at 60 the script takes about 30% of a
core: about 6 ms per tick and 2 ms per frame. On the 120 Hz screen the frames alternate: a
frame with a tick runs about 25 ms (three refreshes), the next about 8 ms, 60 fps on average.
A tick frame needs to lose roughly 3-4 ms to fit in two refreshes; that is the target for the
leg model, card drawing and the human seat, and it is why small costs on tick frames matter.
No single script cost stands out any more (legs are ten parts of 5-28 us each on the Mac).
**Native code (step 8), started 2026-11-25:** `native/` holds a GDExtension (C++, godot-cpp
from the toolchain folder, built with `tools/build_native.sh`: a macOS dylib for the editor and
benches, xcframeworks for the iPhone export). `scripts/native_math.gd` hands the library to
callers; each ported function keeps its GDScript version as reference and fallback
(`native_math` off, or no library in the build). Ported: `ball.gd predict_aero_steps` and the
launch-fitting loop of the shot solver. What a port can and cannot do here: a pure numeric loop
got 5 times faster; the costs that are left in the average tick (legs, arms, pose blends, AI
planning) work on PostureDefinition resources and scene nodes, and would have to be rewritten
as plain data before C++ could speed them up.
**Card drawing, 2026-11-25 (switches `card_tick_build`, `card_build_off_tick`):** the cards were
rebuilt on every drawn frame from interpolated joints, although the joints only change on a
physics tick. They are now built once per tick; each corner is stored with where it was one
tick before (mesh attribute CUSTOM0) and the card and shadow shaders blend the two by the
engine's interpolation fraction, so frames between ticks only set one number. Mac (p3_c5
against p3_c5off, same tree): card cost 33.1 -> 19.0 ms/s at 60 fps (at 120 fps the old path
cost twice as much and the new one the same, so about a quarter is left), play pose-identical.
The build also waits for the frame after the tick's (the heavy frame): card time on tick
frames 16.8 -> 0.6 ms/s. That frame is drawn by carrying the last tick's motion on, which is
exact when the frame starts on the tick and drifts after it (a running leg is half a texel
off at 0.2 of a tick), so the build only waits up to 0.12 of a tick (measured there: limbs
about 4 mm off on average, a texel is 28 mm) and stops waiting when no frame comes between
ticks. Found while checking: a limb that changes drawing (tilt row, facing cell) has other
corners for the same picture, so such a card, a mirrored or flipped one and a teleport are
shown without blending (5% of limb builds); the visual-only motion now steps by game time per
tick. Checked by data: mesh read back from the renderer (layout exact), frame-to-frame pixel
change equal to the old path within run-to-run noise. Not checked by eye, and not on the
phone. Not used in first person, pause, pose editors, debug lines. What is left in a build
(154 us per player): visual motion 47, joint reads 38, quads 42, upload 10: no single part.
**Card build in C++, 2026-11-25 (`native/src/pickle_cards.cpp`, class PickleCards, switch
`native_math`):** one object per player does the joint reads (each distinct joint once, with
the motion layer's deltas), the changed-card test, the quad maths with the drawing picks, and
the tick blend. The script loop in `pixel_card_rig.gd` `_draw_cards` stays as the twin and is
what first person, debug lines and recorded frames use. Left in script on purpose: the hand's
drawing (`_hand_row`, reads the ball and the arm) and the drawn elbow. Checked side by side on
the same inputs over 14,400 builds: same cards rebuilt, worst corner 0.007 mm apart, no
drawing differences, inputs within 0.001 mm. Mac (p3_n2 against p3_n2off): card cost 18.8 ->
9.6 ms/s, play pose-identical; 33.1 at the start of the day. What is left is the visual motion
layer (`card_motion_layer.gd`, 5.4 ms/s, 45 us per build): gait, reactions, stances and taps
written against nodes and sub-objects, not a numeric loop. A port means rewriting it as plain
data first; not done.
**More C++ ports looked at and not done, 2026-11-25 (bench p3_prof9, function timers):** the
AI intercept search, contact checks, legs and pose alignment have no numeric core to move.
Pose alignment is `force_posture_update` (25 ms/s on the Mac, 1.6 calls per player per tick):
it writes the body pose, the paddle, the legs and the arms on scene nodes; the blend maths
under it is 4.3 ms/s. Legs are 15 functions of 0.5-2.5 ms/s each (the IK solve itself 1.8).
Contact is arm solves, the ordered live pass and sealing, plus a kitchen ground scan of 5.3
ms/s that reads every body mesh. The intercept search's 15.6 ms call is a first-call cost,
once per match, like the 18 ms first rally tick it sits in. What would pay instead: (1) run
the first-call work at match load (the 18 ms tick at the first rally); (2) one
`force_posture_update` per player per tick; (3) the kitchen ground scan from simple shapes
(the plan's mesh reads item); (4) legs rewritten as plain data, which is the only form C++
could then speed up.
**The three script-side fixes, 2026-11-25 (benches p3_w1 to p3_w3, all pose-identical):**
(1) First rally hitch: each player's offset resolver read the pose library from disk the first
time an AI planned a contact (15 ms on the Mac, inside the first rally tick). It is read at
player setup now: worst player tick of the first rally second 18.1 -> 4.6 ms. (2) Pose update
once per tick: the only repeat that was dead work was a waiting AI's restore between 0.35 and
0.85 s of waiting (`ready_restore_skip`): 5.1 -> 4.7 ms/s. The other repeats are the restore
of a player going for the ball, which the legs advance on; left alone. (3) Kitchen ground
scan: both bound tests per body mesh run in C++ (`PickleNative.floor_scan`, twin = the loop in
`player_surface_contacts.gd` `ground_contacts`): 5.7 -> 3.1 ms/s; 16,000 scans compared, no
difference. Mac after all of today: scoped tick 2.49 ms, player.physics 72 ms/s, cards 9.7.
**Seen, not fixed:** one contact-authority tick of 27 ms before a serve (between points, bench
second 11) and 155 ms of serve set-up in the first second of the match.
**Check serves in every bench:** `bench_seeds.sh` now prints serves faulted at the hit and
stretched contacts and has a PASS / FAIL rule for each; a serve that faults has no rally_end,
so the points line alone does not show it.

**Next, in this order:**
1. Hands, rest: the finger skeleton and its pose writes go once serve, pickup and dive code no
   longer write finger poses; the elbow / knee / torso skins are the other skinned meshes the
   contact snapshot still poses. (The palm box itself saved little on the Mac: 0.7 ms/s.)
2. Hit tick, rest: profile what is left in it (contact settlement 1.5 ms, the players 2.8 ms,
   the frame's own work), the same pre-solve for your shots (game.gd), and a native shot solve
   if the search itself must get cheaper (it still costs 2.5 ms, now on an earlier tick).
3. Legs: the simpler runtime model of step 3.
4. Pose baker in Pose Studio (the grid of finished arm poses per stroke), once 1 has made the
   arm cheap enough to tell what still needs baking.
5. Card drawing: done as a per-tick build blended in the vertex shader (above); the phone has
   to confirm, and the build itself (154 us per player on the Mac) is what is left of it.

**Order from here:**
1. **Step 3, bake the solvers** (the only step big enough for the tick budget; paddle tracking,
   arm and leg solvers are most of the tick). Paddle and arm first (pp.paddle_tracking +
   pp.align, al.*, arm.*), then between-point clips, then legs. Each behind its own switch;
   bench reports what moved.
2. **1b leftovers:** human_contact_controller.gd held-pose solver (human.held_pose ~3 ms/call,
   goes with step 3), ai.update_foot_legality (40% of ai.input), coordination.advise, the
   per-tick incoming trajectory trace (cache per flight; six readers check freshness).
3. **Mesh reads -> simple shapes** (capsules / boxes per joint), then the hidden body can go.
4. **Step 5 rest:** static card mesh placed in the vertex shader if card.rig still matters.
5. **Step 7 rest:** time the match build on the Mac by scope and cut the 1.3 s freeze.
6. **Step 6** (threads) only if the Mac worst tick is still over budget after 1-5.
7. **Step 8** native ports, last, chosen by the Mac profile (scopes over ~8 ms/s on the Mac).
8. **Phone confirmation** of each batch: one build, the user plays, `tools/phone_perf.sh`.
   Step 0 (Instruments) and step 4 (render scale A/B) need the phone: do them at a batch build.

## Steps (in order, original)

Each step: one phone build, a 3-minute match, then compare slow-frame share, hitches over
50 ms, ms/s per scope and whether Adaptive still drops to 30. Gameplay-touching steps also
get a bench per `docs/BENCH_RULES.md`.

**Results need not be identical (user, 2026-11-25).** A refactor, cleanup or native port may
change how the game executes when the new way is better (simpler, cheaper, steadier). Instead
of requiring `IDENTICAL`, each such change gets a bench against the version before it that
reports what moved (hits, misses, stretched contacts, rally length, faults, pose rules), and
the change notes say why it is better. The user judges feel on the phone. A pose-identical
result is still the quickest proof when the change is meant to be pure speed.

0. **Measure what the log cannot (once, before the big steps).** Record a 3-minute match on
   the phone with Instruments from the Mac (`xcrun xctrace record`; templates on this Mac:
   Time Profiler, Game Performance, Metal System Trace, Power Profiler). It gives GPU time per
   frame, the thermal state over time, and where native engine time goes inside a tick
   (script VM, collision, transforms, rendering driver), which the scopes do not cover. This
   settles the graphics question (step 4) with a number instead of an A/B guess and shows
   whether the unscoped part of the tick is worth a step of its own. Add a fixed "canary"
   workload to PerfMonitor (the same small loop timed once a second) so every later phone log
   shows throttling directly, separate from changes in the game's own work.
   **0b. Stop the catch-up double ticks (cheapest hitch fix; try before step 1).** Two
   candidates, A/B on the phone: (a) `physics/common/max_physics_steps_per_frame` 2 -> 1: a
   late frame then loses a few ms of game time instead of producing a 56 ms frame (under
   sustained overload the game runs slightly slow instead of stuttering; the user judges the
   feel); (b) pace the 30 fps cap to the display so frames are 33.3 ms, not 41.7. The bench
   runs at a fixed frame rate, so (a) should not change it (verify). Expected: most of the 46
   double-tick hitches per 3 minutes gone at 30 fps; at 60 fps it stops one late frame from
   turning into a cluster.
1. **Your player's planning and touch input (worst-tick fix).** Plan the contact once per
   incoming ball and re-plan only when the flight changes (new hit, bounce, net), not every
   tick while HIT is held. Touch input does work only when a touch changes. Measure on the
   phone (human seat); the all-AI bench cannot see it. Target: rally hitches mostly gone.
   **1b. Hot-path cleanup, alongside step 1.** One hot file at a time:
   static types on variables, arguments and arrays; no Dictionary / Array literals or
   `.duplicate()` per tick (reuse objects or return small typed values); node lookups cached
   once; tiny helpers inlined in inner loops; a value several systems need computed once per
   tick and shared; engine built-ins (`PackedVector3Array`, `Geometry3D`, `Basis`) instead of
   element-by-element script loops; and where a simpler way to do the job exists, use it
   even if results move (bench reports what moved, see above). Time each file with a serial
   Mac run, then a phone perf log. Expected 20-40% off each file's own cost,
   and fewer allocation hitches. Order, by phone cost and allocation count (grep 2026-11-25:
   Dictionary literals / `.duplicate()` / untyped `var`):
   1. `scripts/match_contact_authority.gd`: contact checks 69 ms/s; 94 / 40 / 36. Runs
      every tick, between points too.
   2. `scripts/human_contact_controller.gd`: your player 39 ms/s, 6.4 ms inside hitches;
      34 / 7 / 21.
   3. `scripts/player_leg_ik.gd`: legs 62 ms/s; 5 / 3 / 27 (types mostly).
   4. `scripts/player.gd`: player physics parent; 4 / 1 / 28.
   The grep counts the files, not which lines run per tick: profile each file's scopes with
   `PerfMonitor.record` first, and clean only the per-tick paths.
2. **Skip contact checks with no ball in play.** contact.authority / capture and
   surface.snapshot pause between points until the next serve. Expected gameplay-neutral
   (bench should read `IDENTICAL`; if not, see what moved). Target: about -75 ms/s between points.
3. **Bake the solvers** (gameplay changes slightly; bench compares hits, misses, stretched
   contacts and rally length against the current game, the user decides if it is acceptable):
   - Paddle and arm: Pose Studio bakes a small grid of finished arm poses per stroke over
     contact points (high / low, near / far, early / late); matches blend the nearest entries.
     Extend the existing baked elbow presets (`elbow_preset_bake.gd`, `elbow_preset_runtime.gd`).
     Allowed by the contact rule: the planned trajectory wins, the pose is an approximation.
   - Between points: walk, pickup, throw, catch and carry as fixed baked clips. Serve toss and
     carry too, before the serve arm solver can go (with it simply off, the game looped
     WAITING <-> SERVING).
   - Legs: baked step cycles by speed and direction plus a closed-form knee (legs follow
     movement, so a simple runtime model, not a full bake). Shot difficulty reads whether the
     shoe is on the floor, so this one changes results too.
   Target: about -240 ms/s.
4. **Graphics A/B.** Two builds locked at 60 fps, render scale 1/3 and 1/2 (maybe 0.4); compare
   slow-frame share after 3 minutes. Keep 1/2 only if it holds.
5. **Card drawing and AI planning.** Redraw a card part only when its pose changed; far players'
   cards at half rate (visual only). AI plans once per ball like step 1. Crowd figures off
   screen skip their steps. Option if `card.rig` (0.84 ms/frame) still matters afterwards:
   keep each player's card mesh static and place the quads in the vertex shader from joint
   transforms sent as uniforms, so no mesh is rebuilt and uploaded per frame. Prewarm the
   materials added in the graphics pass (card shadow, label pill, shadow layer) at load, so
   their first use does not compile a shader mid-rally.
6. **Smooth the tick frames (only if 60 still misses).** Run the four players' physics in
   parallel across cores: same results, shorter tick. Helps the frame rate, not the heat.
   Caveat: GDScript that touches the scene tree is not thread-safe, so this only works for
   the parts that are pure math on plain data after step 3. Cheaper variant to try first:
   move work that is not needed on the tick itself (pose presentation for drawing, AI
   look-ahead) to the frame between ticks, so the two frames carry similar loads.
7. **Load:** bake the floor / walls once (not at the title and again at match start), or ship
   the baked textures.
8. **Native ports (last).** After steps 1-3 and 1b, re-profile on the phone and port to a
   GDExtension (C++ with the godot-cpp already in the toolchain folder, static framework for
   iOS) only pure-math functions that still cost over about 20 ms/s. Port whole loops, not
   small helpers (calls across the boundary cost). Candidates and estimate (phone ms/s now,
   saving if about 10x faster): shot planner candidate search ~32 -> ~28 saved; contact
   authority / capture math ~30 of 69; body surface snapshot ~15 of 18; cup candidate ~8 of 9;
   flight trace + wrist fit ~9 of 10. Total about 90 ms/s: roughly 15% of rally script CPU
   today, about a quarter of what is left after the earlier steps. Start with the planner
   candidate search, time it on the phone, then decide on the rest. Keep the GDScript
   version as the test reference; results may differ (GDScript `float` is 64-bit, `Vector3`
   32-bit) as long as the bench shows nothing got worse. Costs: a C++ build for iOS and Mac in
   every phone build, two languages to maintain.

## Working method (added in the review)

- **One build, several switches.** Put each optimisation behind a hidden debug toggle
  (Settings, developer section) and write the active toggles into perf.jsonl. One phone build
  then tests several steps, and the user can flip one mid-session and feel the difference.
- **A human-seat bench.** The all-AI bench cannot see step 1. Add a fixed-seed run where the
  human seat is played by a script (HIT held and released on a timer, as in the scratch
  probes used for the HUD and first-person work) and report tick cost and worst tick for
  that seat on the Mac. Phone cost is roughly 2-3x the Mac's (2026-11-23: tick 8.8 ms on
  the Mac, 21-22 ms on the phone), more when hot.
- **Keep the phone's logs.** perf.jsonl is overwritten at every launch, so a session is lost
  unless it is pulled before the next start. Keep the last five (perf.1.jsonl ...), add
  `tools/phone_perf.sh` to pull the newest and print this plan's log row, and make
  `tools/perf_report.py` skip a cut-off last line instead of stopping.
- **A budget guard for every session.** Other sessions change performance too (the render
  scale went 1/3 -> 1/2 without a phone measurement). The bench summary should print the
  serial tick cost and worst tick against the budgets above, and a change that raises them
  says so in its notes.
- **Replace mesh reads with simple shapes (prerequisite for deleting the hidden body).**
  Gameplay still reads the hidden 3D body's meshes (shoe corners, hand and torso surfaces;
  `surface.snapshot` 18 ms/s). Capsules and boxes per joint are cheaper to test against and
  let the hidden body go later (ROADMAP note on removing the Classic option). Results move
  slightly; bench reports it.
- **Only if the GPU turns out to be the limit:** the phone runs the Compatibility renderer on
  OpenGL ES, which Apple has deprecated; Godot's Mobile renderer runs on Metal and has MetalFX
  upscaling. Switching is a large job (every colour is calibrated to this renderer's
  tonemapping and blending, and the shadow blend relies on its behaviour), so it stays a
  last resort behind the render-scale choice.

Not again (tried, rejected): half-rate poses (feet and paddles shake), automatic 30 fps between
points (user rejected), smoothing the IK foot target in the 3D rig (not gameplay-neutral).

## Log

| Date | Step | Build | Slow frames | Hitches >50 ms / 3 min | Script ms/s (play) | Notes |
|---|---|---|---|---|---|---|
| 2026-11-25 | baseline | 108 | 26-50% at 60, Adaptive -> 30 | 64 | table above | 1/2 render scale, throttled by minute 2 |
| 2026-11-25 | 0b, 1, 1b, 2, 5, 7 + working method (Mac only) | not built | | | Mac bench perf_team: scoped tick -12%, rally player.physics -16% | All behind `PerfToggles` (Settings > Performance, 7 taps on the title on the phone). Worst tick unchanged on the Mac. Needs a phone build + 3-min match. Not done: 0 (Instruments), 3, 4, 6, 8 |
| 2026-11-25 | perf team, all toggles on | 110 | 36% (Adaptive -> 30 at 0:10 and 1:05, mean 39 fps) | 7 (4 in 104 s of rally, worst 98 ms; 108: ~52 in rallies) | 156 (player.physics, 108: 124) | 2.6 min, scene-detail base. Hitches ~90% fewer. Down: contact 69 -> 41, surface.snapshot 18 -> 3, input 28 -> 4, between.physics 62 -> 41, bp.* 34 -> 21. Up: pp.paddle_tracking+align 77 -> 102, human.update 39 -> 53 (different match, more rally share 67%; needs a same-session toggle A/B). Canary flat (no throttling seen in 2.6 min). Worst tick at 60 in rallies 19.5 ms |
| 2026-11-25 | 3 (first round: caches, exact rewrites, 9 switches incl. simple_hands, shot_presolve, simple_hand_shape) | 111 (installed, no match played yet) | | | Mac bench p3_k1: scoped tick 4.54 -> 2.66 ms, player.physics 134 -> 78 | Worst tick 13.0 -> 8.0 ms, p90 19.9 -> 9.5 (shot search moved off the hit tick). Human seat 47-57 -> 14-28 ms/s. Rules PASS on 3 seeds (p3_k3); all 5 points ended in the net, too few to judge. Needs a phone build + match |
| 2026-11-25 | 3, phone match on build 111 | 111 | 41% at 60 (Adaptive -> 30 at 0:10 and 1:10) | 127 (67 of 69 are 50-60 ms frames with only about 8 ms of script in them) | 179 (player.physics; 110: 219) | 2.8 min. The phone ran the canary 32% slower than in the build-110 session (0.158 vs 0.120 ms: heat or Low Power Mode), so raw numbers understate the change: scoped tick 7.50 -> 6.39 ms (-15% raw, about -35% per canary), worst tick 16.8 -> 14.3 ms. Your seat is still the largest script cost: human.update 55 ms/s, worst call 25.6 ms; human.pose 30 ms/s, worst 22.7 ms. **Broke play:** 4 of 9 serves faulted at the hit (palm box read as body contact) and contacts were read as stretched. Fixed in build 112 (Mac: 0 of 44 serves faulted) |
| 2026-11-25 | 3, three phone sessions on build 112 | 112 | 35% at 60 (Adaptive -> 30 within 10-25 s every session; mean 37-40 fps) | 3 (5 in 357 s of rally over the three sessions; 111: 127) | 161-165 (player.physics; 110: 219) | 10.2 min in all, 357 s of rally. Serves 27 of 27 into play (111: 5 of 9). Stretched contacts 5 of 301 hits. Scoped tick 5.85 ms (110: 7.50), worst tick 11-12 ms (110: 16.8), worst process+draw 9-11 ms. Your seat is the largest script cost: human.update 53 ms/s, human.pose 32-35 ms/s with single calls up to 21 ms (the held-curve prewarm and cached stroke definition are not in 112). 60 fps still does not hold |
| 2026-11-25 | Adaptive verdict by frame rate; crowd step off tick frames; your seat (curves built ahead, stroke definition reused) | 113 (installed, no match yet) | | | Mac human seat: worst call in a rally 12.4 -> 3.4 ms, 15 ms/s | Why: in all three build-112 sessions the first rally ran at 60-80 fps and Adaptive still dropped to 30 (it counted the longer tick frames as misses); that switch is the lag the user saw. Adaptive now drops only when a 2 s window averages under 52 fps. The crowd's 12 Hz step (about 2 ms on the phone) no longer lands on a tick frame. Tried and removed: skipping the rig of players at rest (5 of 120 updates a second, no saving, 15 mm pop) |
| 2026-11-25 | frame log split by kind (frames with a physics tick / frames between, engine physics and process time) | 114 (installed, no match yet) | | | | Same play as 113. `tools/phone_perf.sh` now prints the tick-frame line; it says how many ms a tick frame must lose and whether script, engine or graphics holds them. Tried and removed since 113: AI decisions on the frame between ticks (the AI then reads the ball a tick late: 2 late pose switches, 5 of 72 hits off the ball) |
| 2026-11-25 | 8, first native port: ball flight stepping and shot launch fitting in C++ (`native/`, class PickleNative, switch `native_math`) | 115 (installed, no match yet) | | | Mac: shot search 2.66 -> 0.60 ms/s, worst tick mean 8.3 -> 8.1 ms, scoped tick 2.68 ms | Play pose-identical with the switch on and off. The app binary holds the library (init symbol present); whether it loads on the phone shows in the next log as shot.aimed_solve near 0.5 ms a call (1.6 before). Planners, legs, arms and pose blending are bound to pose objects and scene nodes, so they are not candidates for a port as they stand |
| 2026-11-25 | 5, card drawing: built once per tick, blended in the vertex shader; the build waits for the frame after the tick's (switches `card_tick_build`, `card_build_off_tick`) | 116 (installed, no match yet) | | | Mac p3_c5 against p3_c5off: card.rig 33.1 -> 19.0 ms/s at 60 fps, on tick frames 16.8 -> 0.6 | Play pose-identical. On the phone look for: card.rig per second about 30 builds x 4 players whatever the frame rate, card.on_tick near zero, the tick-frame line of `tools/phone_perf.sh`, and by eye that limbs and shadows move smoothly (not checked by eye here). If cards look wrong, switch `card_tick_build` off in Settings > Performance |
| 2026-11-25 | 5 + 8, card build in C++ (joint reads, quads, tick blend; class PickleCards) | 117 (installed, no match yet) | | | Mac p3_n2: card.rig 18.8 -> 9.6 ms/s (33.1 before the tick build) | Play pose-identical with the switch on and off; native and script builds agree within 0.007 mm. On the phone card.rig should read about a third of build 115's per second at 60 fps and less at higher frame rates. If cards look wrong: `native_math` off gives the script build, `card_tick_build` off the old per-frame build |
| 2026-11-25 | first-rally pose library read moved to setup; waiting-AI restore skipped earlier (`ready_restore_skip`); kitchen ground scan in C++ (`floor_scan`) | 118 | | | Mac p3_w3: player.physics 74.0 -> 72.1, scoped tick 2.60 -> 2.49 ms | Worst player tick in the first rally second 18.1 -> 4.6 ms on the Mac (expect roughly 40 -> 12 ms on the phone). Play pose-identical |
| 2026-11-25 | first phone log of builds 113-119 (short: 14 s of rally, user was checking the motion smear) | 119 | 43% (tick frames 23.5 ms, 97% over 17.5 ms; frames between 10.0 ms) | 1 (worst 93 ms) | 158 (player.physics; 112: 161-165) | card.rig 16.7 ms/s (115 and earlier: about 49), but 15.7 of it is still on tick frames: the off-tick wait does not engage on the phone (to look at: the tick's frame probably starts later than 0.12 of a tick there). Scoped tick 5.71 ms, worst tick 10.6 ms. Engine process time 22.5 ms a frame against 11.3 ms of physics step: the draw side now weighs as much as the scripts. Too short a session to judge; needs a 3-minute match |
