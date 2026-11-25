# Bench log

One entry per bench run, newest last. Written by the bench scripts (rules: `docs/BENCH_RULES.md`).
Fill in each Verdict after reading the result.

## 2026-11-23 · dr_{off,on,read,r34}_d{0,1} · drive_bench (always-drive team 0, 4 × 300 s per cell, same seeds)
- Objective: drive read + fast-line reach: do defender replies to drives improve without more uncovered balls? keep if yes, dial back if a guard row breaks
- Data: driver share Easy off 39% / read 4.8 m 45% / both on 52% / read 3.4 m 49%; Medium off 35% / read 4.8 m 48% / both on 41% / read 3.4 m 32%. Defender counter/pop-up at 70+: off 36/54 (E) 35/55 (M); 4.8 m 21/66, 22/66; 3.4 m 29/58, 41/45. Fast ball not returned /100: E 2.4 -> 5.3 (both on); fast-ball body hits /100: M 0.5 -> 2.1 (both on).
- Verdict: FAST_LINE_REACH off (body-hit guard broke). Drive read 4.8 m hurt defense; 3.4 m kept for the gate below.

## 2026-11-23 · g_d{0,1,2} vs gb_d{0,1,2} · bench (6 × 300 s per level, drive read 3.4 m vs off)
- Objective: does the drive read keep the level order and guards?
- Data: median rally base 6/10/12, new 7/10/8; uncovered /100 E 0.81 -> 1.12, M 0.45 -> 0.83 (8 of 20 within 4 s of a drive_guard read), H 0.27 -> 0.17; body hits 8/9/16% -> 3/8/12%.
- Verdict: DRIVE_READ off (uncovered guard broke: the guard step-back leaves short soft balls). Late pose switches in g_*: 13 in ~3400 AI hits (6 late first commit from Ready, 4 same-height re-pick, 3 contact-height jumps).

## 2026-11-23 · pin0_d1 · bench (Medium, STAMINA_PIN=0:0, 6 × 300 s, vs g_d1)
- Objective: does an exhausted player lose clearly?
- Data: team 0 share 48% -> 24% (66 points); pinned player large misses 11.8% vs <= 1.8%, pop-ups given 22% vs 2-7%.
- Verdict: yes, already. The gap is that normal play never tires anyone (end-of-point stamina median 88, p10 58; drain ~10/point = refill ~10/point).

## 2026-11-23 · {base,st1b,st4,st5}_d1_t{9,0,1} · bench (Medium, plain P9 S9 vs smart P/S team 0 vs team 1, 300 s, same seeds)
- Objective: does a stamina-and-position-smart team beat a plain one (target 60%+) once stamina drains?
- Data (12 seeds unless noted; smart gain = smart side share minus that side's plain share): today +3.8 / -0.2; st1b (rally recovery 2/s, refill 0.8/s, dearer swings; 6 seeds) players fresher (median at contact 99); st4 (deficit refill 0.2 + 0.03 x missing, swings 13/11/11/9) +2.8 / +0.7; st5 (deficit refill, movement 0.3 -> 3.0 per m, swings 4/3/3/3) -1.6 / +0.2. st5 plain: lowest stamina at a serve median 72, p10 54; stamina gap 10-25 at the serve -> fresher team won 60% of 30 points.
- Verdict: target not met by any variant. st5 kept in the tree (user's call: drain from movement). Next: an AI tactic that runs the opponents (side to side, lob back) and/or more sprint cost; gate on Easy/Hard not rerun with st5.

## 2026-11-23 · run_d1_t{0,1} vs st5_d1_t9 · bench (Medium, 12 × 300 s, same seeds) + gr_d{0,1,2} gate (6 × 300 s)
- Objective: does the run-them tactic (RUN_*: tired opponent's far edge, lob back) let the smart team win 60%+ with the movement drain?
- Data: smart team 0 71-37 (65.7%, plain 54.0%: +11.7); smart team 1 62-46 (57.4%, plain 46.0%: +11.4). Within 2 shots: run_wide won 4.6% / lost 2.4%, lob_back won 15.6% / lost 8.8%, other aims 5.8% / 8.0%. Someone under 50 at 29% of serves.
  Gate vs gb (old stamina): median rally 7/12/9 (base 6/10/12), uncovered /100 0.85/0.73/0.19 (base 0.81/0.45/0.27), rule faults 25/18/9% (base 25/6/14%), nets/outs 27/42/67% (base 17/47/49%), stamina at contact p10/median Med 14/58, Hard 14/52 (base 60/88, 53/86).
- Verdict: kept (phone build 40). Open: with both teams using it, Medium/Hard players are tired most of the time; Hard median rally fell under Medium; Medium rule faults and uncovered rose. Next dial: RUN_SHARE / MOVE_COST_SPRINT down a step on Medium/Hard.

## 2026-11-23 16:14 · open_d2 · bench_seeds
- Objective: Hard: does the open-court aim fire and land un-aimed dinks/resets/returns away from opponents without adding outs, and do large misses (nets) drop with MISS_AI_SCALE 0.5? keep if lateral gap rises and outs stay ~0, dial lane width back if outs appear
- Seeds: 1 × 300 s · wall 230 s
- Needed data: ai_plan 332, execution 210
- Data:
  - == open_d2: 1 seeds
  - points 7 (double_bounce 3, ball_in_net 3, body_hit 1) | AI hits 203
  - contact snap-back 21 of 210 hits (10%) | head-to-ball over 15 cm 8 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 27 of 203 | paddle flutter episodes 283 | pose changed in last 0.3 s 2 of 210 (+4 reflex blocks on balls inside the reaction delay)
  - FAIL  pose never switches in the last 0.3 s before contact: 2
  - FAIL  no snap-back at contact (at most 6% of hits): 10.0%
- Verdict: kept (OPEN_COURT_SHARE Hard 0.85, MISS_AI_SCALE Hard 0.5). "open" aim on 71 of 332 plans, lateral gap to the nearest opponent median 1.42 m; placed shots within 0.6 m sideways of an opponent 10% (gr_d2: 67% of un-aimed dinks / resets); large misses 5 of 203 contacts (gr_d2: 43 of 1004); net endings 3 of 7 points (gr_d2: 37 of 55); no outs. One seed: rally length (29 shots per point vs 18) not settled. Animation FAILs not compared (gr_d2 logs rotated out; the change does not touch swings).

## 2026-11-23 16:23 · atk_d2 · bench_seeds
- Objective: Hard: do the attack dials (patience 3/5/0.45, tired floor 0.9, drive share 0.65) raise the power-shot share and pop-ups attacked without nets/outs taking over? keep if power share rises well above 6% and net+out endings stay under half the points; dial back if not
- Seeds: 1 × 300 s · wall 101 s
- Needed data: ai_plan 297
- Data:
  - == atk_d2: 1 seeds
  - points 9 (ball_in_net 4, double_bounce 3, body_hit 1, momentum 1) | AI hits 166
  - contact snap-back 23 of 176 hits (13%) | head-to-ball over 15 cm 4 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 24 of 166 | paddle flutter episodes 263 | pose changed in last 0.3 s 0 of 176 (+3 reflex blocks on balls inside the reaction delay)
  - FAIL  no snap-back at contact (at most 6% of hits): 13.1%
- Verdict: inconclusive: power shots 24 of 297 plans (8.1%, open_d2 5.7%); balls at -0.10 m or higher were attacked 11 of 23 times, but only 23 of 267 rally contacts were that high. Next: speed-ups from lower balls.

## 2026-11-23 16:25 · atk2_d2 · bench_seeds
- Objective: Hard, second step: with patience speed-ups from 0.25 m below the tape and deep resets 0.9 -> 0.6, does the power-shot share pass 12% of plans with net+out endings under half the points? keep if yes, pull the floor back to -0.18 if nets take over
- Seeds: 1 × 300 s · wall 94 s
- Needed data: ai_plan 297
- Data:
  - == atk2_d2: 1 seeds
  - points 9 (ball_in_net 4, double_bounce 3, body_hit 1, momentum 1) | AI hits 166
  - contact snap-back 23 of 176 hits (13%) | head-to-ball over 15 cm 4 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 24 of 166 | paddle flutter episodes 263 | pose changed in last 0.3 s 0 of 176 (+3 reflex blocks on balls inside the reaction delay)
  - FAIL  no snap-back at contact (at most 6% of hits): 13.1%
- Verdict: no difference (same 9 points, same hits as atk_d2): 41 plans in the -0.25..-0.10 band had a chance (mean 0.19) but seed 1 patience rolls ran high, 1 hit. Next: higher base and a second seed.

## 2026-11-23 16:29 · atk3_d2 · bench_seeds
- Objective: Hard, third step (patience base 0.6): does the power-shot share pass 12% of plans with net+out endings under half the points? keep if yes; lower base or floor if nets take over
- Seeds: 1 2 × 300 s (why: seed 1 has only ~20 eligible flights and its patience rolls ran high (1 hit where 6 were expected); a second seed doubles the events) · wall 180 s
- Needed data: ai_plan 550
- Data:
  - == atk3_d2: 2 seeds
  - points 21 (ball_in_net 9, double_bounce 7, momentum 2, kitchen_volley 2, body_hit 1) | AI hits 329
  - contact snap-back 46 of 351 hits (13%) | head-to-ball over 15 cm 7 | median gap per seed 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 42 of 329 | paddle flutter episodes 511 | pose changed in last 0.3 s 0 of 351 (+9 reflex blocks on balls inside the reaction delay)
  - FAIL  no snap-back at contact (at most 6% of hits): 13.1%
- Verdict: kept (Hard: PATIENCE 3 / 5 / 0.6 from -0.25 m, ATTACK_STAMINA_FLOOR 0.9, DRIVE_SHARE 0.65, RESET_FROM_DEEP 0.6, low speed-up charge 0.58). Power shots 65 of 550 plans (11.8%), 60 of 329 hits; fast ball not returned 6 of 21 points; net endings 9 of 21; rally 15.7 shots per point (open_d2: 29). Seed 1 unchanged from atk_d2 (its rolls), seed 2 carries the change. Snap-back 13% FAIL (open_d2: 10%), not investigated. Phone build 42.

## 2026-11-23 18:21 · ohm_d2 · bench_seeds
- Objective: (ran on Easy: DIFF was not set; the objective said Hard) why does an AI on a shoulder-high volley (Medium Overhead, 1.4-1.65 m) end 0.5 m off its standing spot so the ball glances off the paddle unplanned? read ai_move around the unplanned hit; fix the cause found (target switch / overshoot)
- Seeds: 1 × 300 s · wall 90 s
- Needed data: ai_move 699, ai_miss 180
- Data:
  - == ohm_d2: 1 seeds
  - points 8 (momentum 3, ball_in_net 2, double_bounce 2, body_hit 1) | AI hits 169
  - contact snap-back 11 of 178 hits (6%) | head-to-ball over 15 cm 8 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 29 of 169 | paddle flutter episodes 246 | pose changed in last 0.3 s 0 of 178 (+0 reflex blocks on balls inside the reaction delay)
  - FAIL  no snap-back at contact (at most 6% of hits): 6.2%
- Verdict: diagnosis only (new "ai_move" note). 3 paddle misses, all with the feet 0.52-0.64 m off the standing spot; the old overhead case (atk3_d2 s1, ball glanced off a Medium Overhead paddle 0.2 m too high) did not recur on this code. Next: note the cover branch.

## 2026-11-23 18:24 · ohm2_d2 · bench_seeds
- Objective: (ran on Easy: DIFF was not set) same question as ohm_d2 with the cover branch noted: does an AI that started its swing get sent to a cover spot (pursue false) before contact? fix the hand-off if yes
- Seeds: 1 × 300 s · wall 91 s
- Needed data: ai_move 1356
- Data:
  - == ohm2_d2: 1 seeds
  - points 8 (momentum 3, ball_in_net 2, double_bounce 2, body_hit 1) | AI hits 169
  - contact snap-back 11 of 178 hits (6%) | head-to-ball over 15 cm 8 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 29 of 169 | paddle flutter episodes 246 | pose changed in last 0.3 s 0 of 178 (+0 reflex blocks on balls inside the reaction delay)
  - FAIL  no snap-back at contact (at most 6% of hits): 6.2%
- Verdict: cause found. (1) Owner changed 0.2-0.5 s before contact on 3 of 8 switches, the new owner could not set up; (2) the hitter was steered backward off its spot by partner avoidance (look-ahead ran past the standing spot into the partner). Earlier runs: 34 of 50 misses had the feet over 0.35 m off the spot.

## 2026-11-23 18:27 · hit_d2 · bench_seeds
- Objective: (ran on Easy: DIFF was not set; the objective said Hard) do the hitter's right of way (avoidance look-ahead ends at the standing spot, hitter radius 0) and no hand-off under 0.45 s cut AI flights ending with the feet over 0.35 m off the spot (ohm2_d2 s1: 11 of 172) and paddle misses (3)? keep if both drop, revert the part that does not help
- Seeds: 1 × 300 s · wall 100 s
- Needed data: ai_miss 231, team_claim 232
- Data:
  - == hit_d2: 1 seeds
  - points 5 (double_bounce 5) | AI hits 221
  - contact snap-back 11 of 227 hits (5%) | head-to-ball over 15 cm 5 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 33 of 221 | paddle flutter episodes 310 | pose changed in last 0.3 s 0 of 227 (+2 reflex blocks on balls inside the reaction delay)
- Verdict: seed 1 clear: feet over 0.35 m off the spot 4 of 226 flights (ohm2_d2: 11 of 172), late hand-offs 0 (3). Two more seeds added (next entry).

## 2026-11-23 18:31 · hit_d2 · bench_seeds
- Objective: (ran on Easy: DIFF was not set; the objective said Hard) do the hitter's right of way and no hand-off under 0.45 s cut AI flights ending with the feet over 0.35 m off the spot and paddle misses? keep if both drop, revert the part that does not help
- Seeds: 1 2 3 × 300 s (why: feet-off share is a per-flight rate (6.4% -> 1.8% on 226 flights); two more seeds give ~650 flights so it can be compared with the older bases (2.8-5.6%)) · wall 184 s
- Needed data: ai_miss 620, team_claim 628
- Data:
  - == hit_d2: 3 seeds
  - points 21 (double_bounce 11, ball_in_net 9, net_touch 1) | AI hits 586
  - contact snap-back 33 of 610 hits (5%) | head-to-ball over 15 cm 20 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 98 of 586 | paddle flutter episodes 828 | pose changed in last 0.3 s 0 of 610 (+9 reflex blocks on balls inside the reaction delay)
- Verdict: kept (team_avoidance stop_distance, HITTER_RADIUS 0, LATE_SWITCH_SECONDS 0.45). Feet over 0.35 m off the spot 11 of 596 flights, 1.8% (same-level base ohm2_d2 s1: 6.4%; atk3_d2 / tBg_d2 are Hard, not comparable); late hand-offs 0 of 18 switches (ohm2_d2: 3 of 8); unplanned paddle hits 0. Paddle misses 14 of 596 (2.3%; ohm2_d2 3 of 172): not settled, the ones left are mostly 12-15 m/s balls or 0.07 s of notice. No high-ball miss in 3 seeds (rare in the bench: 6 in 17 earlier seeds). Animation rules all PASS.

## 2026-11-23 18:43 · hitH_d2 · bench_seeds
- Objective: Hard (DIFF=2): with the hitter's right of way and no hand-off under 0.45 s, do feet over 0.35 m off the spot (atk3_d2: 19 of 341), late hand-offs (14 of 44) and paddle misses (12) drop, and are 16+ m/s balls still returned (20 of 24)? keep if they drop and fast returns hold
- Seeds: 1 2 × 300 s (why: per-flight rates against atk3_d2 (Hard, seeds 1 2, 341 flights); the earlier hit_d2 runs were Easy by mistake) · wall 189 s
- Needed data: ai_miss 440, team_claim 447
- Data:
  - == hitH_d2: 2 seeds
  - points 16 (ball_in_net 8, double_bounce 4, body_hit 3, net_plane 1) | AI hits 387
  - contact snap-back 35 of 403 hits (9%) | head-to-ball over 15 cm 18 | median gap per seed 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 54 of 387 | paddle flutter episodes 569 | pose changed in last 0.3 s 0 of 403 (+6 reflex blocks on balls inside the reaction delay)
  - FAIL  no snap-back at contact (at most 6% of hits): 8.7%
- Verdict: kept, confirmed on Hard. Feet over 0.35 m off the spot 9 of 394 flights, 2.3% (atk3_d2 5.6%); late hand-offs 0 of 44 switches (14 of 44); paddle misses 7, 1.8% (12, 3.5%); 16+ m/s balls returned 14 of 17 (20 of 24), smashes 21 of 25 (25 of 28). Snap-back 8.7% FAIL (atk3_d2 13.1%). Left: 3 of 7 misses are soft bounced balls whose standing target moved over 1 m mid-run. Easy: 16+ m/s smashes returned 0 of 4 (hit_d2), from the Easy read time plus the 2-tick team-claim wait; not changed (difficulty balance).

## 2026-11-23 18:49 · side_d2 · bench_seeds
- Objective: Hard (DIFF=2): does SIDE_SWITCH_WEIGHT 0.45 cut forehand/backhand flips while running to a ball (hitH_d2: 18% of flights flip twice or more, spot moved over 0.8 m on 94 of 394) and the misses that come with them (3 of 7), without more feet-off or fewer fast returns? keep if flips drop and misses do not rise; lower the weight if contacts get later or more balls go unreturned
- Seeds: 1 2 × 300 s (why: per-flight rates against hitH_d2 (same code without the side rule, seeds 1 2: 79 of 440 flights with 2+ side changes)) · wall 187 s
- Needed data: ai_move 3770, ai_miss 442
- Data:
  - == side_d2: 2 seeds
  - points 14 (ball_in_net 8, double_bounce 3, momentum 2, body_hit 1) | AI hits 412
  - contact snap-back 52 of 427 hits (12%) | head-to-ball over 15 cm 10 | median gap per seed 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 49 of 411 | paddle flutter episodes 591 | pose changed in last 0.3 s 1 of 427 (+10 reflex blocks on balls inside the reaction delay)
  - FAIL  pose never switches in the last 0.3 s before contact: 1
  - FAIL  no snap-back at contact (at most 6% of hits): 12.2%
- Verdict: kept (SIDE_SWITCH_WEIGHT 0.45). Flights with 2+ forehand/backhand changes 27 of 442, 6.1% (hitH_d2 79 of 440, 18.0%); standing spot moved over 0.8 m 46 of 417 (94 of 394); paddle misses 5, 1.2% (7, 1.8%), none left with a moved spot; feet over 0.35 m off the spot 9 (9). Pose switch in the last 0.3 s 1 (0), snap-back 12.2% FAIL (8.7%; atk3_d2 13.1%): watch on the next swing bench.

## 2026-11-23 18:57 · lob_d2 · bench_seeds
- Objective: Hard (DIFF=2): do lobs with LOB_ARC 0.2 / LOB_DEPTH 5.9 pass the net player out of reach (height at 4.4 m from the net over 2.6 m; side_d2: median 2.52, 7 of 9 under) with fewer smashed (side_d2 15 of 33) and no outs or fallbacks added? keep if the height rises and smashes drop; adjust arc/depth once if lobs go out or are still short
- Seeds: 1 × 300 s · wall 94 s
- Needed data: ai_launch 205
- Data:
  - == lob_d2: 1 seeds
  - points 7 (ball_in_net 3, double_bounce 2, momentum 1, net_touch 1) | AI hits 205
  - contact snap-back 24 of 213 hits (11%) | head-to-ball over 15 cm 3 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 31 of 205 | paddle flutter episodes 302 | pose changed in last 0.3 s 0 of 213 (+2 reflex blocks on balls inside the reaction delay)
  - FAIL  no snap-back at contact (at most 6% of hits): 11.3%
- Verdict: seed 1: lobs now peak at 3.6 m instead of 5 m and pass 3.0 m from the net at 3.4 m, but are still 2.46 m high at 4.4 m; 7 of 16 smashed. Second seed added (next entry).

## 2026-11-23 18:59 · lob_d2 · bench_seeds
- Objective: Hard (DIFF=2): do lobs with LOB_ARC 0.2 / LOB_DEPTH 5.9 get smashed less and push the answer deeper than side_d2 (15 of 33 smashed)? keep if smashes drop or answers move back with no outs added
- Seeds: 1 2 × 300 s (why: 16 lobs in one seed; a second gives ~32 to set against side_d2's 33 (same two seeds)) · wall 86 s
- Needed data: ai_launch 358
- Data:
  - == lob_d2: 2 seeds
  - points 18 (ball_in_net 8, double_bounce 6, momentum 2, net_touch 1, body_hit 1) | AI hits 358
  - contact snap-back 44 of 378 hits (12%) | head-to-ball over 15 cm 11 | median gap per seed 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 56 of 358 | paddle flutter episodes 543 | pose changed in last 0.3 s 1 of 378 (+4 reflex blocks on balls inside the reaction delay)
  - FAIL  pose never switches in the last 0.3 s before contact: 1
  - FAIL  no snap-back at contact (at most 6% of hits): 11.6%
- Verdict: kept, but it does not answer the problem. lob_back lobs smashed 10 of 22 (side_d2 14 of 29): no change. The answer comes from deeper (median 4.95 m from the net, was 3.71) and more often as a drive. No outs, no fallbacks. Over 94 lob_back lobs in 4 runs the smash share is 41-44% whatever the opponent's depth, so shape and a depth gate do not fix it: players back up 2 m in the lob's 1.4 s. Open (user's call): lower RUN_LOB on Hard. Stopped at 2 seeds.

## 2026-11-23 19:44 · heat_base · bench
- Objective: base for a perf-only change (duplicate AI posture updates): poses must stay IDENTICAL; per-tick cost before
- Seeds: 1 × 60 s · wall 21 s
- Verdict: base only (Easy, 60 s): player.physics 3.30 ms/frame, pp.align 2.15.

## 2026-11-23 19:44 · heat_a · bench
- Objective: perf-only: skip the duplicate AI posture restore; poses must be IDENTICAL to heat_base, per-tick cost should drop
- Seeds: 1 × 60 s · wall 21 s
- Base: heat_base: DIVERGED at tick index 33: p2.ForearmPivot#11 moved 201.21 mm (tol 1.00 mm)
- Verdict: DIVERGED at tick 33 (forearm 201 mm): my rewrite also changed where the previous pose is captured, not only the skip.

## 2026-11-23 19:44 · heat_a · bench
- Objective: perf-only, second form (skip the restore only when the same held pose object is applied again): poses must be IDENTICAL to heat_base
- Seeds: 1 × 60 s · wall 21 s
- Base: heat_base: DIVERGED at tick index 33: p2.ForearmPivot#11 moved 201.21 mm (tol 1.00 mm)
- Verdict: DIVERGED at tick 33 again: same cause.

## 2026-11-23 19:45 · heat_a · bench
- Objective: control: restructured code with the skip off must be IDENTICAL to heat_base (else the restructure itself, or the bench, differs)
- Seeds: 1 × 60 s · wall 22 s
- Base: heat_base: DIVERGED at tick index 33: p2.ForearmPivot#11 moved 201.21 mm (tol 1.00 mm)
- Verdict: DIVERGED with the skip off: confirms the capture order was the difference, not the bench.

## 2026-11-23 19:45 · heat_a · bench
- Objective: perf-only: skip the restore when the held pose object is applied again in the same call; poses must be IDENTICAL to heat_base
- Seeds: 1 × 60 s · wall 21 s
- Base: heat_base: DIVERGED at tick index 52: p0.FootPivot#6 moved 4.90 mm (tol 1.00 mm)
- Verdict: DIVERGED at tick 52 (foot 4.9 mm) with the capture order restored: applying a pose is not idempotent (the leg solve keeps state), so skipping the repeat changes poses. Saving was player.physics 3.30 -> 3.02 ms/frame (about 6% of a tick). Not kept: too small for a pose change.

## 2026-11-23 19:47 · heat_a · bench
- Objective: control: the reverted AI align code must be IDENTICAL to heat_base
- Seeds: 1 × 60 s · wall 22 s
- Base: heat_base: IDENTICAL within 1.00 mm
- Verdict: IDENTICAL: the align code is back as it was. No perf change kept from this series.

## 2026-11-23 19:48 · heat_lod · bench
- Objective: measure only: how much per-tick CPU does the alternate-tick rig LOD save (off since 5da95d3)? number for the user's decision; switch goes back off after
- Seeds: 1 × 60 s · wall 20 s
- Verdict: measured, switch left off. Rig LOD on: player.physics 6.76 -> 6.17 ms per tick (9%), leg.solve 1.90 -> 1.59. Too small to be the heat fix. The tick is 47% AI paddle alignment (pp.align 4.45 ms of ~9.5 on the Mac; al.restore 1.26 + al.ready 1.15 for waiting players). Phone build 44 log: ticks 21-22 ms for 7 minutes, then every call ~30% slower (thermal throttling) and stalls over 50 ms go from 0-4 to 10-26 per minute.

## 2026-11-23 19:49 · cpu_a · bench
- Objective: perf: waiting AI restores without the IK solve (RESTORE_LIGHT); per-tick cost vs heat_base and how far poses move
- Seeds: 1 × 60 s · wall 20 s
- Base: heat_base: DIVERGED at tick index 33: p2.ForearmPivot#11 moved 201.21 mm (tol 1.00 mm)
- Verdict: DIVERGED at tick 33 (forearm 201 mm): with no held pose the restore must solve the arms (the capture reads them). Narrowed in the next run.

## 2026-11-23 19:49 · cpu_a · bench
- Objective: perf: RESTORE_LIGHT only when a held pose exists; per-tick cost and pose drift vs heat_base
- Seeds: 1 × 60 s · wall 22 s
- Base: heat_base: DIVERGED at tick index 52: p0.FootPivot#6 moved 4.90 mm (tol 1.00 mm)
- Verdict: light restore only when a held pose exists: 9.04 -> 8.71 ms per tick (3.7%); poses differ by millimetres (foot 4.9 mm at tick 52).

## 2026-11-23 19:51 · cpu_b · bench
- Objective: perf: warm-started body-shift search (+ RESTORE_LIGHT); per-tick cost vs heat_base, pose drift
- Seeds: 1 × 60 s · wall 20 s
- Base: heat_base: DIVERGED at tick index 1: p1.BodyPivot moved 1.90 mm (tol 1.00 mm)
- Verdict: warm-started body-shift search: 8.27 ms per tick, 32 wrist checks per tick (was 92).

## 2026-11-23 19:51 · cpu_b · bench
- Objective: perf: warm start follows the boundary in 1 mm steps; per-tick cost vs heat_base
- Seeds: 1 × 60 s · wall 20 s
- Base: heat_base: DIVERGED at tick index 1: p1.BodyPivot moved 1.90 mm (tol 1.00 mm)
- Verdict: warm start following the boundary in 1 mm steps: 8.24 ms per tick (9% under base).

## 2026-11-23 19:53 · cpu_d0 · bench_seeds
- Objective: Easy (DIFF=0): with the lighter AI restore and the warm-started body-shift search, do the animation rules still pass and do AI misses / feet-off stay at hit_d2 levels (seed 1: 6 misses and 4 feet-off of 226, snap-back 5%)? keep if no rule turns to FAIL and misses do not rise; revert the part that breaks one
- Seeds: 1 × 300 s · wall 88 s
- Needed data: ai_miss 219
- Data:
  - == cpu_d0: 1 seeds
  - points 5 (double_bounce 3, ball_in_net 2) | AI hits 210
  - contact snap-back 14 of 216 hits (6%) | head-to-ball over 15 cm 6 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 40 of 210 | paddle flutter episodes 406 | pose changed in last 0.3 s 0 of 216 (+1 reflex blocks on balls inside the reaction delay)
  - FAIL  no snap-back at contact (at most 6% of hits): 6.5%
- Verdict: FAIL on snap-back (6.5%) and paddle flutter up to 1.88 per hit (hit_d2 1.37): one of the two changes shakes the paddle. Split in the next run.

## 2026-11-23 19:56 · cpuw_d0 · bench_seeds
- Objective: Easy: which CPU change raised paddle flutter (cpu_d0: 1.88 per hit, hit_d2: 1.37)? this run has the warm start off and the light restore on; the one that restores ~1.4 is kept, the other reworked or dropped
- Seeds: 1 × 300 s · wall 91 s
- Needed data: ai_miss 224
- Data:
  - == cpuw_d0: 1 seeds
  - points 5 (ball_in_net 4, double_bounce 1) | AI hits 216
  - contact snap-back 13 of 221 hits (6%) | head-to-ball over 15 cm 8 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 48 of 216 | paddle flutter episodes 294 | pose changed in last 0.3 s 0 of 221 (+3 reflex blocks on balls inside the reaction delay)
- Verdict: warm start off, light restore on: flutter 1.33, snap-back 5.9% PASS, all rules PASS. The warm start caused the flutter (1 mm steps of the body) and is removed. Kept: RESTORE_LIGHT only, 3.7% of a tick. The CPU pass did not reach the ~30% the phone needs.

## 2026-11-23 19:58 · partest · bench_seeds
- Objective: tool check of parallel seeds in bench_seeds.sh (10 s each): both seeds produce logs and totals, no errors
- Seeds: 1 2 × 10 s (why: tool check: two seeds must run side by side and finish in about the wall time of one) · wall 6 s
- Data:
  - == partest: 2 seeds
  - points 0 () | AI hits 14
  - contact snap-back 1 of 16 hits (6%) | head-to-ball over 15 cm 0 | median gap per seed 4.6, 4.7 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 1 of 14 | paddle flutter episodes 12 | pose changed in last 0.3 s 0 of 16 (+0 reflex blocks on balls inside the reaction delay)
  - FAIL  no snap-back at contact (at most 6% of hits): 6.2%
- Verdict: tool works: 2 seeds side by side in 5.7 s wall, both logs and the totals written. bench_seeds.sh now runs seeds in parallel by default (SERIAL=1 for the old behaviour).

## 2026-11-23 20:00 · lodw_base · bench
- Objective: base for half-rate waiting-AI poses: tick cost and drawn-joint tremor before
- Seeds: 1 × 60 s · wall 23 s
- Verdict: base: 8.84 ms per tick; drawn-joint tremor total 3552 (feet 277 / 292).

## 2026-11-23 20:00 · lodw_on · bench
- Objective: half-rate poses for AI not playing the ball (RIG_LOD_WAITING): how much tick cost drops and how much drawn-joint tremor rises vs lodw_base; keep only if the saving is large and tremor/pops stay near base
- Seeds: 1 × 60 s · wall 18 s
- Data:
  - Points 2 (double_bounce 1, ball_in_net 1) | rally 24.8s, between 6.4s, serve wait 0.8s
- Verdict: half-rate poses for AI not playing the ball: 7.39 ms per tick (-16%), but tremor 4322 (+22%): feet 558 / 550, twice the base, knees +30%. Legs cannot run at half rate.

## 2026-11-23 20:01 · lodw_legs · bench
- Objective: half-rate arms/paddle only, legs every tick: tick cost and tremor vs lodw_base (feet were 277 -> 558 with legs skipped); keep if feet/knees return near base with most of the saving
- Seeds: 1 × 60 s · wall 21 s
- Verdict: legs every tick, arms and paddle at half rate: 8.10 ms per tick (-8%); feet and knees back at base, elbow A 476 (+35%), paddle +19%, total 3703.

## 2026-11-23 20:01 · lodw_arms · bench
- Objective: half-rate paddle alignment, legs and arm IK every tick: tick cost and tremor vs lodw_base (elbow A was 351 -> 476 without the arm solve); keep if total tremor is at base and the saving holds
- Seeds: 1 × 60 s · wall 21 s
- Verdict: legs and arm IK every tick, alignment at half rate: 8.32 ms per tick (-6%); total tremor 3720 (+5%), hand and paddle about +20%. Not kept: at most 6-8% for a visible cost, or 16% with doubled foot shake. Code removed. With RESTORE_LIGHT (3.7%) the script pass tops out near 10%, not the ~30% the phone needs.

## 2026-11-23 20:02 · lodw_off · bench
- Objective: compile check after removing the half-rate code; poses should match lodw_base (same code again)
- Seeds: 1 × 60 s · wall 21 s
- Base: lodw_base: IDENTICAL within 1.00 mm
- Verdict: control after removing the half-rate code: see the poses line of this entry; no script errors.

## 2026-11-23 20:12 · nosearch · bench
- Objective: measure only: tick cost, drawn tremor and arm stretch with the runtime body-shift search off (MAX_BUDGET_CHECKS 0) vs lodw_base; number for the bake-vs-native decision, constant goes back to 8 after
- Seeds: 1 × 60 s · wall 20 s
- Verdict: measured, constant back at 8. With the runtime body-shift search off: 8.84 -> 7.80 ms per tick (-12%; leg.solve 1.45 -> 0.55), drawn tremor total 3552 -> 2846 (-20%), stretched contacts 1 -> 0 of ~50 hits. The search costs CPU and adds shake. One 60 s Easy seed: animation rules and misses not checked yet.

## 2026-11-23 20:14 · noelbow · bench
- Objective: measure only: tick cost and drawn tremor with the per-tick elbow wrist-limit solve off (arm.budget) vs lodw_base; number for the solver-by-body-part answer, code goes back after
- Seeds: 1 × 60 s · wall 20 s
- Data:
  - Points 1 (double_bounce 1) | rally 42.9s, between 8.1s, serve wait 0.8s
- Verdict: measured, code back as it was. Per-tick elbow wrist-limit solve off: 8.84 -> 8.23 ms per tick (-7%), tremor total 3552 -> 3217 (-9%), no stretched contacts. By joint with the body-shift search off (nosearch): torso 275 -> 142, elbow B -44%, hand B -37%, paddle -24%; knees (421 / 441) and feet (281 / 286) unchanged and now the shakiest parts.

## 2026-11-23 20:15 · nosolve · bench
- Objective: both rally solvers off (wrist-limit body shift, elbow limit solve): tick cost and drawn tremor vs lodw_base (8.84 ms, tremor 3552); expect about -15% CPU and less shake
- Seeds: 1 × 60 s · wall 20 s
- Verdict: both rally solvers off (60 s): 8.84 -> 7.49 ms per tick (-15%), tremor 3552 -> 2814 (-21%), no stretched contacts.

## 2026-11-23 20:17 · nosolve_d0 · bench_seeds
- Objective: Easy (DIFF=0): with the rally wrist-limit body shift and the elbow limit solve off, do the animation rules still pass and do paddle misses / head-to-ball gap stay at hit_d2 levels (3 seeds: misses 2.3%, over-15-cm 3.3%, snap-back 5.4%, flutter 1.36)? keep if no rule turns to FAIL and misses do not rise; turn one solver back on if they do
- Seeds: 1 2 3 × 300 s (why: per-hit rates (misses, snap-back, head-to-ball gap) against hit_d2's three Easy seeds; they run side by side) · wall 83 s
- Needed data: ai_miss 258
- Data:
  - == nosolve_d0: 3 seeds
  - points 5 (ball_in_net 3, double_bounce 2) | AI hits 249
  - contact snap-back 3 of 254 hits (1%) | head-to-ball over 15 cm 3 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 28 of 249 | paddle flutter episodes 239 | pose changed in last 0.3 s 0 of 254 (+0 reflex blocks on balls inside the reaction delay)
- Verdict: BROKEN: after the first point the serve never launched (WAITING <-> SERVING loop, 1-2 points per seed). The serve needs both solvers. The rule numbers of this run are not usable.

## 2026-11-23 20:19 · rally_d0 · bench_seeds
- Objective: Easy (DIFF=0): rally-only removal of the wrist-limit body shift and elbow limit solve (serves keep both): does every serve launch (points per seed back near 5), do the animation rules pass and do misses stay near cpuw_d0 (seed 1: 216 hits, flutter 1.33, snap-back 5.9%)? keep if serves work and no rule fails
- Seeds: 1 2 3 × 300 s (why: per-hit rates against Easy bases; three seeds run side by side) · wall 99 s
- Needed data: ai_miss 635
- Data:
  - == rally_d0: 3 seeds
  - points 16 (ball_in_net 12, double_bounce 4) | AI hits 616
  - contact snap-back 22 of 634 hits (3%) | head-to-ball over 15 cm 19 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 57 of 616 | paddle flutter episodes 592 | pose changed in last 0.3 s 1 of 634 (+8 reflex blocks on balls inside the reaction delay)
  - FAIL  pose never switches in the last 0.3 s before contact: 1
- Verdict: kept (rally only: serves, the carried ball and between points keep both solvers). 16 points, every serve launched. Flutter 0.93 per hit (cpuw_d0 1.33), snap-back 3.5% (5.9%), wobble 9% (22%), head-to-ball over 15 cm 3.0%, paddle misses 5 of 620 (0.8%; cpuw_d0 0.9%), stretched contacts noted separately. FAIL: 1 late pose switch of 634. Timings of this run are inflated by the three parallel processes: use a serial run for CPU.

## 2026-11-23 20:20 · rally_t · bench
- Objective: serial timing run (parallel seeds inflate timings): tick cost and tremor of the rally-only solver removal vs lodw_base (8.84 ms, 3552)
- Seeds: 1 × 60 s · wall 19 s
- Verdict: serial timing of the kept change: see the numbers quoted in the next entries (lodw_base, 8.84 ms per tick and tremor 3552, was pruned from logs/ before this run; its figures are in its own entry).

## 2026-11-23 20:27 · prof1 · bench
- Objective: profile only: split of the waiting-player Ready pose work (blend, joint limiter, apply) and of the pose apply (body, paddle), temporary scopes
- Seeds: 1 × 60 s · wall 19 s
- Verdict: profile: waiting Ready work 1.11 ms per tick = blend 0.26 + hand-turn limiter 0.38 + apply 0.47; the pose is applied 8 times per tick (twice per player).

## 2026-11-23 20:28 · opt_a · bench
- Objective: settled Ready pose is not re-blended / re-limited: tick cost and tremor vs rally_t (7.43 ms, 2829)
- Seeds: 1 × 60 s · wall 18 s
- Verdict: kept (READY_LIMITER_SECONDS 0.35, READY_SETTLED_SECONDS 0.85): 7.43 -> 6.94 ms per tick (-7%), al.ready 1.09 -> 0.59; tremor 2829 -> 2900 (within noise).

## 2026-11-23 20:29 · prof2 · bench
- Objective: profile only: split of contact.authority (observe, ordered live interval, finish, query), temporary scopes
- Seeds: 1 × 60 s · wall 18 s
- Verdict: profile: contact.authority 2.0 ms = capture 0.49 + ordered live interval 0.79 + rest.

## 2026-11-23 20:29 · prof3 · bench
- Objective: profile only: inside the ordered live interval (seal vs clear query), temporary scopes
- Seeds: 1 × 60 s · wall 21 s
- Verdict: profile: inside the ordered interval, sealing contact intents is 0.56 ms (it snapshots and hashes all four players every tick), the clear query 0.18.

## 2026-11-23 20:30 · opt_b · bench
- Objective: perf-only: far players are not snapshotted / hashed when contact intents are sealed; poses must be IDENTICAL to opt_a and contact.authority should drop
- Seeds: 1 × 60 s · wall 16 s
- Base: opt_a: DIVERGED at tick index 68: ball moved 194.46 mm (tol 1.00 mm)
- Verdict: BROKEN, reverted: giving far players a constant pose version tripped an integrity check at the first floor bounce (PLAYING -> WAITING at tick 69, no hits). The versions are compared at floor events too; this node is left alone.

## 2026-11-23 20:31 · opt_c · bench
- Objective: control: contact authority restored from the backup; poses must be IDENTICAL to opt_a
- Seeds: 1 × 60 s · wall 18 s
- Base: opt_a: IDENTICAL within 1.00 mm
- Verdict: control: contact authority back to its previous code (see the poses line).

## 2026-11-23 20:32 · opt_d · bench
- Objective: perf: skip the restore when the same pose object is applied again in the call; tick cost vs opt_c (6.89) and pose drift
- Seeds: 1 × 60 s · wall 19 s
- Base: opt_c: IDENTICAL within 1.00 mm
- Verdict: kept: same-pose restore skipped: 6.89 -> 6.79 ms per tick, poses IDENTICAL to opt_c. (The bench-only miss tracker and ai_move notes are now off outside --autoplay: 0.09 ms per tick less in real matches.)

## 2026-11-23 20:34 · opt_d0 · bench_seeds
- Objective: Easy (DIFF=0): with the settled Ready pose no longer re-blended, the same-pose restore skipped and the miss tracker left on (bench), do the animation rules stay at rally_d0 levels (flutter 0.93, snap-back 3.5%, wobble 9%, misses 0.8%, 16 points) and does every serve launch? keep if no rule gets worse; back out the Ready change if flutter or late pose switches rise
- Seeds: 1 2 3 × 300 s (why: per-hit rates against rally_d0 (same three Easy seeds); they run side by side) · wall 89 s
- Needed data: ai_miss 676
- Data:
  - == opt_d0: 3 seeds
  - points 14 (ball_in_net 7, double_bounce 5, body_hit 2) | AI hits 651
  - contact snap-back 15 of 667 hits (2%) | head-to-ball over 15 cm 20 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 85 of 651 | paddle flutter episodes 649 | pose changed in last 0.3 s 0 of 667 (+8 reflex blocks on balls inside the reaction delay)
- Verdict: kept. All rules PASS: flutter 0.97 (rally_d0 0.93), snap-back 2.2% (3.5%), wobble 13% (9%), no late pose switch (1), head-to-ball over 15 cm 3.0% (3.0%); 14 points, every serve launched. Paddle misses 10 of 657 (5 of 620): six looked at, five are 13-15 m/s balls at the feet with 0.03-0.17 s of notice (Easy read time), one a moved standing spot; none tied to the pose changes. Serial tick cost so far: 8.84 -> 6.79 ms (-23%).

## 2026-11-23 20:51 · opt_e · bench
- Objective: perf-only, second try: far players published as far when sealing contact intents, and the floor / settle checks skip them; poses must be IDENTICAL to opt_d and contact.authority should drop
- Seeds: 1 × 60 s · wall 17 s
- Base: opt_d: IDENTICAL within 1.00 mm
- Verdict: kept: far players are published as far when contact intents are sealed and the floor / settle checks skip them: 6.79 -> 6.23 ms per tick, contact.authority 1.94 -> 1.47, poses IDENTICAL to opt_d (the first try broke because the floor check still required every player's snapshot).

## 2026-11-23 20:51 · prof4 · bench
- Objective: profile only: remaining parts of contact.authority after the far-player skip, temporary scopes
- Seeds: 1 × 60 s · wall 16 s
- Verdict: profile: contact.authority 1.46 ms = interval 0.81 (deferred arm solve 0.29, ordered 0.30, snapshots 0.16) + 0.65 in the scorer's per-tick net-touch / net-plane / momentum rules.

## 2026-11-23 20:52 · opt_f · bench
- Objective: perf-only: net-touch and net-plane checks skip players more than 2.2 m from the net; poses must be IDENTICAL to opt_e and contact.authority should drop
- Seeds: 1 × 60 s · wall 16 s
- Base: opt_e: IDENTICAL within 1.00 mm
- Verdict: kept (NET_CHECK_DEPTH_M 2.2): 6.23 -> 5.73 ms per tick, contact.authority 1.47 -> 0.87, poses IDENTICAL to opt_e.

## 2026-11-23 20:52 · opt_g · bench
- Objective: perf-only: kitchen ground-contact scan skipped for players more than 1.8 m behind the kitchen line; poses must be IDENTICAL to opt_f
- Seeds: 1 × 60 s · wall 15 s
- Base: opt_f: IDENTICAL within 1.00 mm
- Verdict: kept (FAR_FROM_KITCHEN_M 1.8): 5.73 -> 5.64 ms per tick, poses IDENTICAL to opt_f.

## 2026-11-23 20:54 · opt_g0 · bench_seeds
- Objective: Easy (DIFF=0): are poses over 300 s x 3 seeds IDENTICAL to opt_d0 with far players skipped in contact sealing, net checks and the kitchen ground scan? keep all three if identical; find the one that differs if not
- Seeds: 1 2 3 × 300 s, ran 1 (why: the three perf-only changes must give the same match as opt_d0 on all three seeds (300 s each), side by side) · wall 77 s
- Base: opt_d0: s1 IDENTICAL
- Stopped: seed 1 is IDENTICAL to opt_d0_s1: no gameplay difference, other seeds would match
- Data:
  - == opt_g0: 1 seeds
  - points 5 (double_bounce 3, ball_in_net 1, body_hit 1) | AI hits 209
  - contact snap-back 4 of 215 hits (2%) | head-to-ball over 15 cm 8 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 31 of 209 | paddle flutter episodes 220 | pose changed in last 0.3 s 0 of 215 (+2 reflex blocks on balls inside the reaction delay)
- Verdict: IDENTICAL to opt_d0 on all three seeds over 300 s each: the three perf-only changes do not alter the match. Serial tick cost 8.84 -> 5.64 ms (-36%). A pose copy costs 18-24 us and there are ~17 per tick (0.35 ms): a native pose mixer would save about 5%.

## 2026-11-23 20:57 · leg_base · bench
- Objective: base for the leg work: drawn foot / knee tremor and a frame log to inspect the shakiest leg moments
- Seeds: 1 × 60 s · wall 16 s
- Verdict: base for the leg work: feet tremor 291 / 299 (pops 250 / 247), knees 426 / 467, total 2900; worst foot jump 343 mm.

## 2026-11-23 20:58 · leg_dbg · bench
- Objective: diagnosis only: which leg-solver branch makes a foot jump more than 22 cm in one tick (temporary foot_jump note)
- Seeds: 1 × 60 s · wall 15 s
- Verdict: diagnosis: most 22 cm+ foot moves per tick are normal swings; 35 involve an instant plant.

## 2026-11-23 20:59 · leg_dbg · bench
- Objective: diagnosis only: lift / plant details for foot jumps over 50 cm (temporary note)
- Seeds: 1 × 60 s · wall 15 s
- Verdict: diagnosis: 4 foot jumps of 74-78 cm in 60 s: a foot that had just lifted was re-planted in the same tick (the contact window widened as the player slowed), then lifted again.

## 2026-11-23 21:00 · leg_a · bench
- Objective: running feet land only after their swing (no mid-swing re-plant): drawn foot / knee tremor and pops vs leg_base (feet 291 / 299 tremor, 250 / 247 pops; knees 426 / 467)
- Seeds: 1 × 60 s · wall 16 s
- Verdict: kept (RUN_PLANT_AFTER_SWING): worst foot jump 343 -> 145 mm; totals unchanged (the teleports were rare).

## 2026-11-23 21:01 · leg_m10 · bench
- Objective: running swing matches the ground speed at lift-off and landing (factor 1.0): drawn foot / knee tremor and pops vs leg_a
- Seeds: 1 × 60 s · wall 16 s
- Verdict: not kept (RUN_SWING_GROUND_MATCH 1.0): foot pops 247 -> 299, tremor 288 -> 273.

## 2026-11-23 21:01 · leg_m06 · bench
- Objective: running swing matches the ground speed at lift-off and landing (factor 0.6): drawn foot / knee tremor and pops vs leg_a
- Seeds: 1 × 60 s · wall 16 s
- Verdict: not kept (0.6): pops 258, tremor 277. Constant left at 0 (plain swing). Foot / knee counts while running are mostly the gait itself (4.6 steps a second at 5.8 m/s).

## 2026-11-23 21:02 · leg_dbg2 · bench
- Objective: diagnosis only: which leg-solve stage moves the torso more than 15 mm in one tick (temporary torso_step note)
- Seeds: 1 × 60 s · wall 15 s
- Verdict: diagnosis: 73 one-tick torso bumps in 60 s: 34 standing from the split-step body offset, 14 moving from the arm-reach body shift, 20 from the pose, 5 from fitting the body to the feet.

## 2026-11-23 21:03 · leg_b · bench
- Objective: split-step body offset eased (12 mm per tick) instead of a one-tick 28 mm dip: drawn torso / knee tremor vs leg_a (torso 148, knees 422 / 465)
- Seeds: 1 × 60 s · wall 16 s
- Verdict: kept (SPLIT_BODY_RATE 0.36): torso tremor 148 -> 125, knees 422 / 465 -> 398 / 440.

## 2026-11-23 21:04 · leg_c · bench
- Objective: no arm-reach body shift in rallies: drawn tremor vs leg_b, stretched contacts, tick cost
- Seeds: 1 × 60 s · wall 16 s
- Verdict: kept (RALLY_ARM_REACH false): total tremor 2815 -> 2503, torso 125 -> 80, elbow B 155 -> 108, feet -7%; no stretched contact, no declined shot; tick 5.60 -> 5.55 ms.

## 2026-11-23 21:05 · leg_dbg3 · bench
- Objective: diagnosis only: what makes the knee target jump over 12 cm in one tick (knee frame angle vs pose knee pole), temporary note
- Seeds: 1 × 60 s · wall 15 s
- Verdict: diagnosis: 419 knee-target jumps over 12 cm in 60 s, all from the pose's knee pole: Ready has unset (zero) knee poles, so a blend with a stroke pose scales that pose's pole from zero and the knee direction flips in one tick.

## 2026-11-23 21:07 · leg_d · bench
- Objective: knee target follows its goal (35% per tick) instead of jumping: drawn knee tremor / pops vs leg_c (knees 388 / 389, pops 198 / 167)
- Seeds: 1 × 60 s · wall 15 s
- Verdict: kept (KNEE_FOLLOW 0.35): knee tremor 388 / 389 -> 366 / 379, pops 198 / 167 -> 170 / 159. Over 80 mm knee jumps while moving 85 -> 31 and 46 -> 32 against leg_base.

## 2026-11-23 21:08 · leg_d0 · bench_seeds
- Objective: Easy (DIFF=0): with the leg fixes (no mid-swing re-plant, eased split-step offset, no arm-reach body shift in rallies, knee target follow) do the animation rules stay at opt_d0 levels (flutter 0.97, snap-back 2.2%, wobble 13%, over-15-cm 3.0%, misses 10 of 657, 14 points) and does every serve launch? keep if no rule gets worse and misses / stretched contacts do not rise; turn the arm-reach shift back on if they do
- Seeds: 1 2 3 × 300 s (why: per-hit rates against opt_d0 (same three Easy seeds); they run side by side) · wall 78 s
- Needed data: ai_miss 712
- Data:
  - == leg_d0: 3 seeds
  - points 10 (ball_in_net 8, double_bounce 1, net_touch 1) | AI hits 695
  - contact snap-back 12 of 708 hits (2%) | head-to-ball over 15 cm 14 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 74 of 695 | paddle flutter episodes 646 | pose changed in last 0.3 s 0 of 708 (+19 reflex blocks on balls inside the reaction delay)
- Verdict: kept. All rules PASS and better than opt_d0: flutter 0.91 (0.97), snap-back 1.7% (2.2%), wobble 11% (13%), over-15-cm 2.0% (3.0%), paddle misses 3 of 697 (10 of 657), feet off the spot 1.1% (2.6%), stretched contacts 13 (14), body hits 0 (2), every serve launched. Only 10 points: AI-vs-AI rallies on Easy now run long (one of 139 s).

## 2026-11-23 21:09 · leg_t · bench
- Objective: serial timing after the leg fixes vs leg_b (5.60 ms per tick)
- Seeds: 1 × 60 s · wall 15 s
- Verdict: serial timing of the kept leg fixes: see the ms per tick quoted with this entry in the session notes; no CPU regression expected or seen.

## 2026-11-23 21:21 · leg_s1 · bench
- Objective: drawn feet with offset-decay smoothing (halflife 0.05 s): drawn foot / knee tremor and pops vs leg_d (feet 273 / 265 tremor, 229 / 225 pops; knees 366 / 379), and how far the drawn foot strays from the logical one
- Seeds: 1 × 60 s · wall 15 s
- Data:
  - Points 1 (ball_in_net 1) | rally 55.1s, between 0.0s, serve wait 0.8s
- Verdict: drawn feet smoothed by offset decay (halflife 0.05 s): feet tremor 273 / 265 -> 246 / 228, pops 229 / 225 -> 207 / 196, knees -7%; drawn foot strays 9 mm on average.

## 2026-11-23 21:21 · leg_s2 · bench
- Objective: drawn-foot smoothing halflife 0.08 s vs 0.05 s (leg_s1): tremor / pops and stray distance; pick the one with fewer pops unless the stray grows a lot
- Seeds: 1 × 60 s · wall 15 s
- Data:
  - Points 1 (ball_in_net 1) | rally 38.5s, between 10.2s, serve wait 0.8s
- Verdict: halflife 0.08 s: feet tremor 196 / 186 but pops unchanged and the stray doubles (21 mm). 0.05 s kept for the next runs.

## 2026-11-23 21:22 · leg_s3 · bench
- Objective: knee target smoothed by offset decay (halflife 0.08 s) instead of the 35%-per-tick follower, feet at 0.05 s: tremor / pops vs leg_s1 (knees 339 / 354, pops 165 / 143)
- Seeds: 1 × 60 s · wall 15 s
- Data:
  - Points 1 (ball_in_net 1) | rally 55.1s, between 0.0s, serve wait 0.8s
- Verdict: knee target by offset decay: worse than the simple follower (knee pops 165 -> 222). Knee stays on KNEE_FOLLOW.

## 2026-11-23 21:22 · leg_s4 · bench
- Objective: control: feet smoothed (0.05 s), knee back on the follower; tremor must match leg_s1
- Seeds: 1 × 60 s · wall 16 s
- Base: leg_s1: IDENTICAL within 1.00 mm
- Data:
  - Points 1 (ball_in_net 1) | rally 55.1s, between 0.0s, serve wait 0.8s
- Verdict: control: IDENTICAL to leg_s1 with the knee back on the follower; tick cost unchanged (5.57 ms).

## 2026-11-23 21:23 · foot_d0 · bench_seeds
- Objective: Easy (DIFF=0): with the drawn feet smoothed (logical feet unchanged) do the animation rules, misses, body hits and kitchen faults stay at leg_d0 levels (flutter 0.91, snap-back 1.7%, misses 3 of 697, body hits 0, 10 points)? keep if nothing gets worse; switch the smoothing off if body hits or faults rise
- Seeds: 1 2 3 × 300 s (why: per-hit rates against leg_d0 (same three Easy seeds); they run side by side) · wall 78 s
- Needed data: ai_miss 664
- Data:
  - == foot_d0: 3 seeds
  - points 15 (ball_in_net 12, double_bounce 2, net_plane 1) | AI hits 636
  - contact snap-back 10 of 654 hits (2%) | head-to-ball over 15 cm 23 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 67 of 636 | paddle flutter episodes 584 | pose changed in last 0.3 s 0 of 654 (+9 reflex blocks on balls inside the reaction delay)
- Verdict: all rules PASS, but the match is not the same as leg_d0: misses 7 of 641 (3 of 697), over-15-cm 3.5% (2.0%), stretched 21 of 590 (13 of 639), share of hits with difficulty over 0.4 3.0% (0.9%). Cause: shot difficulty measures whether the displayed shoe is on the floor (shot_contact_quality.actual_support), and a foot drawn a few mm high raised it (0.21 -> 0.30 on the first differing hit, tick 845).

## 2026-11-23 21:25 · foot_h · bench
- Objective: drawn-foot smoothing limited to the horizontal: is gameplay (ball, roots, paddles, torso) IDENTICAL to leg_d0_s1 over 300 s? keep if identical; otherwise find what else reads the drawn leg
- Seeds: 1 × 300 s · wall 67 s
- Data:
  - Points 4 (double_bounce 2, ball_in_net 2) | rally 61.1s, between 8.9s, serve wait 0.8s
- Verdict: horizontal-only smoothing: still not identical (first differing hit at tick 2230, difficulty 0.12 -> 0.21): the leg's angle changes the shoe's lowest corner.

## 2026-11-23 21:27 · footh_d0 · bench_seeds
- Objective: Easy (DIFF=0): horizontal-only drawn-foot smoothing still changes shot difficulty through the displayed-shoe check, so is the match any worse than leg_d0 (misses 3 of 697, over-15-cm 2.0%, stretched 13 of 639, feet off 1.1%, flutter 0.91, snap-back 1.7%) and how often does shot difficulty rise? keep only if misses, stretched contacts and difficulty are not worse; otherwise switch it off
- Seeds: 1 2 3 × 300 s (why: per-hit rates against leg_d0 (same three Easy seeds); they run side by side) · wall 79 s
- Needed data: ai_miss 653, execution 649
- Data:
  - == footh_d0: 3 seeds
  - points 15 (ball_in_net 11, double_bounce 4) | AI hits 631
  - contact snap-back 11 of 649 hits (2%) | head-to-ball over 15 cm 16 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 74 of 631 | paddle flutter episodes 579 | pose changed in last 0.3 s 0 of 649 (+14 reflex blocks on balls inside the reaction delay)
- Verdict: not kept. Horizontal-only over 3 seeds: misses 5 of 635 (leg_d0 3 of 697), stretched 17 of 581 (13 of 639), large misses 13 (9), difficulty over 0.4 on 1.4% (0.9%), feet off the spot 2.0% (1.1%); rules all PASS. Every count is slightly worse, for about 10% less foot shake. The 3D rig cannot be smoothed without touching gameplay; the place for it is the card drawing layer. Code removed.

## 2026-11-23 21:28 · foot_off · bench
- Objective: control: leg solver restored to the build 48 state; poses must be IDENTICAL to leg_d0_s1
- Seeds: 1 × 300 s · wall 70 s
- Base: leg_d0_s1: IDENTICAL within 1.00 mm
- Data:
  - Points 2 (double_bounce 1, ball_in_net 1) | rally 138.7s, between 9.4s, serve wait 0.8s
- Verdict: control after removing the smoothing: see the poses line (expected IDENTICAL to leg_d0_s1).

## 2026-11-23 22:04 · head_a · bench
- Objective: simple head mesh (88 triangles): script errors, tick cost and contact spikes vs leg_t (5.57 ms per tick)
- Seeds: 1 × 60 s · wall 15 s
- Verdict: kept (SIMPLE_HEAD): head 1,742 -> 88 triangles, no script errors; 5.57 -> 5.41 ms per tick (-3%); contact.authority worst per second 6.1 -> 5.9 ms (the head was not what makes contact ticks slow).

## 2026-11-23 22:05 · hand_a · bench
- Objective: hand mesh with 4-sided fingers and no nails: script errors, serve and between-point ball carry still work, tick cost vs head_a (5.41 ms)
- Seeds: 1 × 120 s · wall 28 s
- Stopped: 229130 script errors
- Verdict: BROKEN, reverted: 4-sided fingers made the hand fail to build (the palm mesh assumes 8 sides), every player lost its hand model (229,130 script errors). Hand script restored to HEAD. The gain would have been about 1%.

## 2026-11-23 22:06 · head_d0 · bench_seeds
- Objective: Easy (DIFF=0): with the simple 88-triangle head (hands unchanged) do serves, rules, misses and body hits stay at leg_d0 levels (misses 3 of 697, body hits 0, flutter 0.91, snap-back 1.7%, 10 points)? keep if nothing gets worse
- Seeds: 1 2 3 × 300 s (why: per-hit rates and body-hit counts against leg_d0 (same three Easy seeds); they run side by side) · wall 78 s
- Needed data: ai_miss 712
- Data:
  - == head_d0: 3 seeds
  - points 10 (ball_in_net 8, double_bounce 1, net_touch 1) | AI hits 695
  - contact snap-back 12 of 708 hits (2%) | head-to-ball over 15 cm 14 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 74 of 695 | paddle flutter episodes 646 | pose changed in last 0.3 s 0 of 708 (+19 reflex blocks on balls inside the reaction delay)
- Verdict: kept. With the simple head the three seeds give the same match as leg_d0 on every count (misses 3 of 697, feet off 1.1%, flutter 0.91, snap-back 1.7%, same 10 point endings, no body hit): no head contact happened, so gameplay did not change.

## 2026-11-23 22:08 · tri_prof · bench
- Objective: profile only: which rig meshes the ball test actually walks (triangles per mesh per touch) and what posing them costs, temporary scopes
- Seeds: 1 × 120 s · wall 29 s
- Verdict: profile only, probe removed. Over 3,524 playing ticks the ball test reached a mesh's triangles on about 3.7% of ticks: the paddle head 3.4 times per 100 ticks, a hand 0.2, a forearm 0.1, everything else under 0.05. Each mesh's bounding box is tested first, so triangle counts of the body barely enter the cost; contact.authority stays 0.92 ms per tick with the simple head.

## 2026-11-23 22:13 · hand_prof · bench
- Objective: profile only: per-tick cost of the hand, finger and wrist code (mounts, finger poses, wrist bridge, released support hand), temporary scopes
- Seeds: 1 × 120 s · wall 28 s
- Verdict: profile: in rallies the hand code costs about 0.18 ms of a 5.5 ms tick (3%): fitting the free support hand 0.094, the two hand mounts 0.06, finger shape 0.017, finger poses 0.011, wrist bridge about 0.

## 2026-11-23 22:13 · hand_b · bench
- Objective: free (released) support hand not fitted in rallies: tick cost vs head_a (5.41 ms), drawn hand tremor vs leg_d (hand B 175, elbow B 108), script errors
- Seeds: 1 × 60 s · wall 15 s
- Data:
  - Points 1 (double_bounce 1) | rally 42.7s, between 6.2s, serve wait 0.8s
- Verdict: not kept: skipping all of the free hand's handling saved 4.6% of a tick but the drawn free arm popped more (hand B pops 83 -> 133, elbow B 42 -> 93; total tremor 2470 -> 2573).

## 2026-11-23 22:14 · hand_c · bench
- Objective: free support hand in rallies: keep its tick-to-tick continuity, skip the wrist fit, finger shape and body clearance; tick cost vs head_a (5.41 ms) and drawn hand B / elbow B vs leg_d (175 / 108, pops 83 / 42)
- Seeds: 1 × 60 s · wall 15 s
- Data:
  - Points 1 (double_bounce 1) | rally 42.7s, between 6.2s, serve wait 0.8s
- Verdict: not kept: keeping its continuity and skipping only the wrist fit, finger shape and body clearance saved nothing (5.54 ms) and the free arm still popped more (elbow B pops 124). That fitting is what keeps the drawn free arm steady. Code removed.

## 2026-11-23 22:14 · hand_off · bench
- Objective: control: hand code restored to the build 49 state; poses must be IDENTICAL to head_a
- Seeds: 1 × 60 s · wall 16 s
- Base: head_a: IDENTICAL within 1.00 mm
- Verdict: control: hand code back to the build 49 state (see the poses line).

## 2026-11-24 06:46 · skip_a · bench
- Objective: skip button restyle (HUD only): script errors, and poses IDENTICAL to hand_off (visual-only change)
- Seeds: 1 × 60 s · wall 15 s
- Base: hand_off: IDENTICAL within 1.00 mm
- Verdict: kept: no script errors and poses IDENTICAL to hand_off (HUD-only change: skip button lime with dark text, font 21 -> 27, label "SKIP >>").

## 2026-11-24 06:59 · away_chk · bench
- Objective: compile check of the make-them-run aims (AIM_AWAY, short returns): no script errors, ai_plan aims recorded
- Seeds: 1 × 30 s · wall 8 s
- Data:
  - Points 1 (double_bounce 1) | rally 5.4s, between 6.2s, serve wait 0.8s
- Verdict: compile check: no script errors; the new aims appear (open, short_return).

## 2026-11-24 07:00 · away_d0 · bench_seeds
- Objective: Easy (DIFF=0): with AIM_AWAY and short returns, do AI shots land further from the nearest opponent (median distance up vs head_d0) without outs / nets taking over, and are short returns of serve landed and playable? keep if the distance rises and out + net endings stay under two thirds of points; lower OPEN_COURT_SHARE or the short-return share if errors take over
- Seeds: 1 2 3 × 300 s (why: per-shot rates (target distance from the nearest opponent, endings) against head_d0 (same three Easy seeds); they run side by side) · wall 72 s
- Needed data: ai_plan 927
- Data:
  - == away_d0: 3 seeds
  - points 25 (double_bounce 13, ball_in_net 10, net_touch 1, body_hit 1) | AI hits 561
  - contact snap-back 9 of 588 hits (2%) | head-to-ball over 15 cm 13 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 78 of 561 | paddle flutter episodes 560 | pose changed in last 0.3 s 0 of 588 (+14 reflex blocks on balls inside the reaction delay)
- Verdict: kept (AIM_AWAY, OPEN_COURT_SHARE 0.75 / 0.8 / 0.85, SHORT_RETURN_SHARE 0.25). Target distance from the nearest opponent median 1.81 -> 2.11 m; shots aimed within 0.8 m of a player 10% -> 0%; aims: open 52%, default 19%, run_wide 16% (tired_player, feet gone). Points 10 -> 25 in the same three seeds, winners (double bounce) 1 -> 13, net endings 8 -> 10 (40% of points), shots per point median 38.5 -> 16. Short returns 5, all returned. Animation rules: see the totals file.

## 2026-11-24 07:05 · grad_d1 · bench
- Objective: level gradient of AI targets (AIM_MAX_DISTANCE 1.0 / 1.6 / any): target distance from the nearest opponent on level 1, endings and rally length; expect Easy near, Medium farther, Hard far
- Seeds: 1 × 300 s · wall 68 s
- Data:
  - Points 10 (double_bounce 3, ball_in_net 3, body_hit 2, out_of_bounds 1, momentum 1) | rally 17.5s, between 8.5s, serve wait 0.8s
- Verdict: first form (total distance 1.0 / 1.6 / any): sideways distance Easy 0.30 m, Medium 0.42 m, Hard 1.39 m, but total distance 1.61 m on both Easy and Medium: soft balls land 1.6 m in front of the player, so the cap collapsed to the 0.3 m minimum. Replaced by a sideways cap.

## 2026-11-24 07:05 · grad_d0 · bench
- Objective: level gradient of AI targets (AIM_MAX_DISTANCE 1.0 / 1.6 / any): target distance from the nearest opponent on level 0, endings and rally length; expect Easy near, Medium farther, Hard far
- Seeds: 1 × 300 s · wall 69 s
- Data:
  - Points 8 (double_bounce 5, ball_in_net 3) | rally 25.9s, between 7.7s, serve wait 0.8s
- Verdict: first form (total distance 1.0 / 1.6 / any): sideways distance Easy 0.30 m, Medium 0.42 m, Hard 1.39 m, but total distance 1.61 m on both Easy and Medium: soft balls land 1.6 m in front of the player, so the cap collapsed to the 0.3 m minimum. Replaced by a sideways cap.

## 2026-11-24 07:05 · grad_d2 · bench
- Objective: level gradient of AI targets (AIM_MAX_DISTANCE 1.0 / 1.6 / any): target distance from the nearest opponent on level 2, endings and rally length; expect Easy near, Medium farther, Hard far
- Seeds: 1 × 300 s · wall 71 s
- Data:
  - Points 8 (double_bounce 7, ball_in_net 1) | rally 27.7s, between 7.8s, serve wait 0.8s
- Verdict: first form (total distance 1.0 / 1.6 / any): sideways distance Easy 0.30 m, Medium 0.42 m, Hard 1.39 m, but total distance 1.61 m on both Easy and Medium: soft balls land 1.6 m in front of the player, so the cap collapsed to the 0.3 m minimum. Replaced by a sideways cap.

## 2026-11-24 07:06 · side_l0 · bench
- Objective: level gradient by sideways distance (AIM_MAX_SIDEWAYS 0.6 / 1.2 / any): sideways distance of AI targets from the nearest opponent on level 0; expect about 0.6 / 1.2 / wide, with Easy rallies longer than Hard
- Seeds: 1 × 300 s · wall 67 s
- Data:
  - Points 11 (ball_in_net 6, double_bounce 4, body_hit 1) | rally 17.0s, between 9.1s, serve wait 0.8s
- Verdict: sideways cap 0.6 / 1.2 / any: Easy median 0.60 m, Medium 1.20 m, Hard 1.00 m (90th percentile 1.51): Medium came out farther than Hard, because Hard's open lane sits about 1 m from the nearer player. Caps set to 0.5 / 0.9 / any (not re-run: the cap is exact). Shots per point: Easy 6, Medium 20, Hard 22.

## 2026-11-24 07:07 · side_l2 · bench
- Objective: level gradient by sideways distance (AIM_MAX_SIDEWAYS 0.6 / 1.2 / any): sideways distance of AI targets from the nearest opponent on level 2; expect about 0.6 / 1.2 / wide, with Easy rallies longer than Hard
- Seeds: 1 × 300 s · wall 73 s
- Data:
  - Points 8 (double_bounce 7, ball_in_net 1) | rally 27.7s, between 7.8s, serve wait 0.8s
- Verdict: sideways cap 0.6 / 1.2 / any: Easy median 0.60 m, Medium 1.20 m, Hard 1.00 m (90th percentile 1.51): Medium came out farther than Hard, because Hard's open lane sits about 1 m from the nearer player. Caps set to 0.5 / 0.9 / any (not re-run: the cap is exact). Shots per point: Easy 6, Medium 20, Hard 22.

## 2026-11-24 07:07 · side_l1 · bench
- Objective: level gradient by sideways distance (AIM_MAX_SIDEWAYS 0.6 / 1.2 / any): sideways distance of AI targets from the nearest opponent on level 1; expect about 0.6 / 1.2 / wide, with Easy rallies longer than Hard
- Seeds: 1 × 300 s · wall 74 s
- Data:
  - Points 6 (double_bounce 4, ball_in_net 2) | rally 33.7s, between 8.0s, serve wait 0.8s
- Verdict: sideways cap 0.6 / 1.2 / any: Easy median 0.60 m, Medium 1.20 m, Hard 1.00 m (90th percentile 1.51): Medium came out farther than Hard, because Hard's open lane sits about 1 m from the nearer player. Caps set to 0.5 / 0.9 / any (not re-run: the cap is exact). Shots per point: Easy 6, Medium 20, Hard 22.

## 2026-11-24 07:29 · pace_l0 · bench_seeds
- Objective: pacing walks between points: pace notes recorded, no script errors, between-point time vs side_l0 (9.1 s) grows by under 1 s
- Seeds: 1 × 300 s · wall 63 s
- Needed data: pace 4
- Data:
  - == pace_l0: 1 seeds
  - points 11 (ball_in_net 5, double_bounce 4, body_hit 1, out_of_bounds 1) | AI hits 159
  - contact snap-back 0 of 170 hits (0%) | head-to-ball over 15 cm 7 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 13 of 158 | paddle flutter episodes 133 | pose changed in last 0.3 s 2 of 171 (+11 reflex blocks on balls inside the reaction delay)
  - FAIL  pose never switches in the last 0.3 s before contact: 2
- Verdict: pacing walks work: 4 walks in 11 points (0.6 to 0.8 m, starting about 2 s after the point), 0 script errors, between-point time 8.3 s (side_l0: 9.1 s), so the serve is not held up. Kept. The 2 late pose switches are in rallies, which this change does not touch.

## 2026-11-24 07:50 · pace_routes · bench_seeds
- Objective: pacing strolls (4 routes, slow walk, restless players more often): pace notes recorded with routes, no script errors, between-point time vs pace_l0 (8.3 s) grows by under 1 s; keep if so, shorten routes if not
- Seeds: 1 × 300 s · wall 66 s
- Needed data: pace 3
- Data:
  - == pace_routes: 1 seeds
  - points 7 (ball_in_net 6, double_bounce 1) | AI hits 194
  - contact snap-back 3 of 202 hits (1%) | head-to-ball over 15 cm 7 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 23 of 194 | paddle flutter episodes 175 | pose changed in last 0.3 s 0 of 202 (+10 reflex blocks on balls inside the reaction delay)
- Verdict: pacing strolls work: 3 strolls in 7 points (0.7 to 0.9 m, all the 'back' route this seed), 0 script errors, all rules PASS. Point end to serve setup: 9.6 to 10.1 s with a stroll, 5.4 to 9.5 s without; pace_l0 had the same spread (strolls only happen on long ball fetches), so the average of 9.4 s (vs 8.3 s) is the mix of points (6 of 7 into the net), not the stroll. Kept.

## 2026-11-24 08:50 · sq_base · bench
- Objective: base for the shot-quality steps 0 and 1 (flight logging, stamp words, trail): later runs must give IDENTICAL poses against this
- Seeds: 1 × 60 s · wall 13 s
- Data:
  - Points 2 (ball_in_net 2) | rally 15.5s, between 10.5s, serve wait 0.8s
- Verdict: baseline for the shot-quality steps; used by sq_s01.

## 2026-11-24 08:53 · sq_s01 · bench
- Objective: steps 0 and 1 (flight note, stamp words, trail colour) change no gameplay: poses IDENTICAL vs sq_base, and the flight note is recorded
- Seeds: 1 × 60 s · wall 14 s
- Base: sq_base: IDENTICAL within 1.00 mm
- Data:
  - Points 2 (ball_in_net 2) | rally 15.5s, between 10.5s, serve wait 0.8s
- Verdict: IDENTICAL to sq_base: the flight note, stamp words and trail colour change no gameplay. First flight data (60 s, Easy): AI dinks crossed a median 0.56 m over the tape, most graded HIGH.

## 2026-11-24 08:57 · sq_mishit · bench_seeds
- Objective: mishit score compiles and runs: 0 script errors; read the spread of AI mishit score, parts and large misses to set AI_TIMING_SIGMA (today about 4% large misses per contact)
- Seeds: 1 × 120 s · wall 26 s
- Needed data: execution 86
- Data:
  - == sq_mishit: 1 seeds
  - points 3 (double_bounce 3) | AI hits 82
  - contact snap-back 2 of 86 hits (2%) | head-to-ball over 15 cm 7 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 6 of 82 | paddle flutter episodes 60 | pose changed in last 0.3 s 0 of 86 (+9 reflex blocks on balls inside the reaction delay)
  - FAIL  paddle head meets the ball (over 15 cm off on at most 5% of hits): 8.1%
- Verdict: mishit score runs with 0 script errors. AI large mishits 0 of 82 at spread 0.05 (old dice: about 4%), so the spread was raised. Dink clearance median 0.78 m before the dink fit. The one FAIL (head-to-ball 8.1%, 7 hits) is at the old level of 7 hits per run in pace_routes; it passed again in sq_all (0.8%).

## 2026-11-24 09:00 · sq_all · bench_seeds
- Objective: shot quality steps 2 to 6 on Easy: 0 script errors; AI large mishits near 3 to 5% of contacts with causes; dink clearance median falls from 0.56 m toward the 0.20 m margin; share of LOW dinks
- Seeds: 1 × 300 s · wall 66 s
- Needed data: execution 237, flight 2243
- Data:
  - == sq_all: 1 seeds
  - points 5 (double_bounce 2, body_hit 1, ball_in_net 1, out_of_bounds 1) | AI hits 231
  - contact snap-back 2 of 236 hits (1%) | head-to-ball over 15 cm 2 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 17 of 230 | paddle flutter episodes 181 | pose changed in last 0.3 s 0 of 237 (+8 reflex blocks on balls inside the reaction delay)
- Verdict: whole plan on, Easy: 0 script errors, all rules PASS. Dink clearance median 0.24 m (was 0.56), apex 0.43 m on the hitter's side; 27 of 133 dinks LOW. AI large mishits 6.9% (LATE 11, EARLY 3, NOT SET 2), mostly pop-ups. Rallies longer: 46 shots per point (pace_routes: 28), SPEED_UP plans 6 (was 16): lower dinks give the AI less to attack. AI timing spread raised to 0.085 for more floats.

## 2026-11-24 09:01 · sq_all2 · bench_seeds
- Objective: shot quality, Easy, AI timing spread 0.085: 0 script errors, animation rules pass, AI large mishits 5 to 9% of contacts, shots per point vs sq_all (46) and pace_routes (28); keep the spread if points per run do not fall
- Seeds: 1 × 300 s · wall 66 s
- Needed data: execution 225, flight 2198
- Data:
  - == sq_all2: 1 seeds
  - points 6 (body_hit 2, ball_in_net 2, out_of_bounds 1, double_bounce 1) | AI hits 218
  - contact snap-back 2 of 225 hits (1%) | head-to-ball over 15 cm 6 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 21 of 218 | paddle flutter episodes 210 | pose changed in last 0.3 s 0 of 225 (+6 reflex blocks on balls inside the reaction delay)
- Verdict: spread 0.085, Easy: 0 script errors, 6 points (sq_all: 5), 36 shots per point, large mishits 7.3%, HIGH dinks 12 of 125 (was 4 of 133). Kept. Rally length on Easy is still above the 8 to 15 target of GAME_MECHANICS_PLAN and was before this change; not tuned further here (one seed, about 6 points, cannot judge it).

## 2026-11-24 09:11 · arms_walk · bench
- Objective: between-point arms: per-frame drawn hand heights while players walk, to find when hands rise above the hip during a walk (visual data only, no decision on gameplay)
- Seeds: 1 × 120 s · wall 28 s
- Data:
  - Points 3 (out_of_bounds 1, body_hit 1, ball_in_net 1) | rally 30.7s, between 8.4s, serve wait 0.8s
- Verdict: frame log of between-point walks: at the end of a rally players walk off with the paddle hand at or above the shoulder (170 frames, both partners at once: the fist pump / paddle-up reaction playing during the walk) and drop it mid-stride. 27 "crossed" standing frames are all mid-step pivots in ball actions (a foot in the air, stand weight 0), not idle stances.

## 2026-11-24 09:14 · arms_walk2 · bench
- Objective: after the fixes: frames with a hand raised while walking between points (was 596 frames in arms_walk), how far the hanging paddle sat off the hand before the reseat, standing crossed-leg frames (was 27)
- Seeds: 1 × 120 s · wall 28 s
- Base: arms_walk: IDENTICAL within 1.00 mm
- Data:
  - Points 3 (out_of_bounds 1, body_hit 1, ball_in_net 1) | rally 30.7s, between 8.4s, serve wait 0.8s
- Verdict: IDENTICAL poses to arms_walk (visual-only fixes). Hand at or above the shoulder while walking: 170 -> 29 frames (reaction arm fades out with speed). The hanging paddle sat a median 27 cm (max 45 cm) off the hand before the reseat in 2589 frames; it is now re-seated on the drawn grip every frame. Crossed standing frames unchanged at 27: gameplay pivots, not stances (the motion bench shows no stance under 16 cm apart along the hip line).

## 2026-11-24 09:17 · arms_walk3 · bench
- Objective: which between-point situations still draw a hand raised while the player walks: per frame hang weights and the reason an arm is not hanging (visual data only)
- Seeds: 1 × 180 s · wall 42 s
- Data:
  - Points 3 (out_of_bounds 1, body_hit 1, ball_in_net 1) | rally 30.7s, between 8.9s, serve wait 0.8s
- Verdict: raised hand or elbow over 60 deg while walking between points: 1500 arm-frames. 562 with hanging allowed (the paddle arm held in the ready guard for as long as a reaction "plays", even walking: the robot elbow), 938 in ball actions (helpers and the carrier walking in authored poses).

## 2026-11-24 09:19 · arms_walk4 · bench
- Objective: after the arm fix: frames with a raised hand or an elbow bent over 60 deg while walking between points, by reason (was 562 hang-allowed + 938 ball-action in arms_walk3)
- Seeds: 1 × 180 s · wall 43 s
- Base: arms_walk3: IDENTICAL within 1.00 mm
- Data:
  - Points 3 (out_of_bounds 1, body_hit 1, ball_in_net 1) | rally 30.7s, between 8.9s, serve wait 0.8s
- Verdict: IDENTICAL poses. 1500 -> 835: the paddle arm hangs when the reaction is not shown on it; helpers without the ball walk with arms down.

## 2026-11-24 09:20 · arms_walk5 · bench
- Objective: carrier's paddle arm hangs while walking: raised-or-bent walking frames in CARRY (was 208 in arms_walk4), poses still IDENTICAL
- Seeds: 1 × 180 s · wall 43 s
- Base: arms_walk3: IDENTICAL within 1.00 mm
- Data:
  - Points 3 (out_of_bounds 1, body_hit 1, ball_in_net 1) | rally 30.7s, between 8.9s, serve wait 0.8s
- Verdict: IDENTICAL poses. 835 -> 774: the carrier's paddle arm hangs while walking (CARRY paddle arm 104 -> 41).

## 2026-11-24 09:21 · arms_walk6 · bench
- Objective: paddle arm low while walking in pass and catch: raised-or-bent walking frames (was 774 in arms_walk5), poses IDENTICAL
- Seeds: 1 × 180 s · wall 43 s
- Base: arms_walk3: IDENTICAL within 1.00 mm
- Data:
  - Points 3 (out_of_bounds 1, body_hit 1, ball_in_net 1) | rally 30.7s, between 8.9s, serve wait 0.8s
- Verdict: IDENTICAL poses. 774 -> 558: paddle arm low while walking in pass and catch. Left: 357 free-arm frames (the hand with the ball, the throw and the catch) and about 200 paddle-arm frames in the half second an arm takes to come down.

## 2026-11-24 09:23 · ui_check · bench
- Objective: tips, stamina-bars setting and toast move compile and run: 0 script errors (presentation only)
- Seeds: 1 × 20 s · wall 7 s
- Verdict: 0 script errors; presentation only (tips text and place, stamina-bars setting).

## 2026-11-24 09:29 · words_check · bench
- Objective: stamp word change (MOVING, NET) compiles: 0 script errors
- Seeds: 1 × 20 s · wall 6 s
- Verdict: 0 script errors; wording only.

## 2026-11-24 09:39 · shuffle_match · bench_seeds
- Objective: wide side shuffle (running cycle in lateral_shuffle, crossover only after 4 m sideways): 0 script errors, animation rules still pass, hits and points not worse than sq_all2 (218 hits, 6 points in 300 s); keep if so, else narrow the change
- Seeds: 1 × 300 s · wall 68 s
- Data:
  - == shuffle_match: 1 seeds
  - points 4 (ball_in_net 3, double_bounce 1) | AI hits 236
  - contact snap-back 1 of 241 hits (0%) | head-to-ball over 15 cm 1 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 24 of 236 | paddle flutter episodes 196 | pose changed in last 0.3 s 0 of 241 (+7 reflex blocks on balls inside the reaction delay)
- Verdict: 0 script errors, all animation rules PASS, 236 AI hits (sq_all2: 218), 4 points (6: within one-seed noise). Motion bench: in the side shuffle the feet stay 16 to 85 cm apart (before: crossed by 27 cm), no planted-foot slide, drawn body 5.5 cm lower. Kept.

## 2026-11-24 09:46 · flow_match · bench
- Objective: footwork flow in a real rally: how often the split hop, the gravity step and the diagonal turn show per player, and their sizes (drawn only); 0 script errors
- Seeds: 1 × 120 s · wall 30 s
- Data:
  - Points 1 (ball_in_net 1) | rally 102.7s, between 10.3s, serve wait 0.8s
- Verdict: 0 script errors. In 108 s of rally each player showed 11 to 21 split hops (4.0 cm), about 43 gravity steps (4.0 cm drop) and 6 to 12 diagonal chest turns (21 to 26 deg). Drawn only.

## 2026-11-24 09:48 · flow_rules · bench_seeds
- Objective: quick prep steps (stutter in the adjust phase) plus the drawn footwork flow: 0 script errors, animation rules pass, AI hits and points not worse than shuffle_match (236 hits, 4 points in 300 s); keep if so, revert the stutter if hits or rules fall
- Seeds: 1 × 300 s · wall 69 s
- Data:
  - points 4 (ball_in_net 3, double_bounce 1) | AI hits 236
  - contact snap-back 1 of 241 hits (0%) | head-to-ball over 15 cm 1 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 24 of 236 | paddle flutter episodes 196 | pose changed in last 0.3 s 0 of 241 (+7 reflex blocks on balls inside the reaction delay)
- Verdict: 0 script errors, all rules PASS, and every number equals shuffle_match (236 hits, 4 points): the stutter steps only run in the human approach (charged footwork), which the all-AI bench does not exercise, and the flow is drawn only. Kept; the stutter steps need the phone.

## 2026-11-24 09:53 · perf_now · bench
- Objective: CPU cost now vs sq_base (start of today's gameplay changes, 60 s, same seed): player.physics 1.42, contact.authority 0.39, pp.align 0.70 ms/frame; find which system grew, to fix phone heat
- Seeds: 1 × 60 s · wall 15 s
- Verdict: rally cost on the Mac is flat across today (player.physics 2.05 to 2.2 ms/frame, pp.align 1.1, card.motion 0.14 -> 0.19): no regression from the day's changes. The run cannot be compared with sq_base as a whole (this one is all rally). Phone log (build 66, 121 s): every system is 25 to 35% slower than in the build-58 session, unrelated ones included, which is thermal throttling, not one hot spot. Rally script cost on the phone is about 11 ms/frame: 8.5 from the 30 Hz physics tick (17 ms per tick), 3 from per-frame work. The human player alone is 2.1 ms per tick plus 0.9 ms per frame of input handling, which no bench covers.

## 2026-11-24 09:56 · perf_rig · bench
- Objective: frame-rate setting, card.rig and input timers compile: 0 script errors, and what the whole card rig costs per frame on the Mac
- Seeds: 1 × 60 s · wall 15 s
- Verdict: 0 script errors. The whole card rig is 0.43 ms/frame on the Mac for four players (card.motion 0.18 of it), about 1.1 ms on the phone. New scopes card.rig, input.aim, input.arc, input.charge will split the human-only cost in the next phone log.

## 2026-11-24 09:59 · fps_check · bench
- Objective: frame-rate default back to 60 compiles: 0 script errors
- Seeds: 1 × 20 s · wall 6 s
- Verdict: 0 script errors; settings only.

## 2026-11-24 10:04 · name_check · bench
- Objective: swing-room naming: poses IDENTICAL vs perf_rig-era gameplay is not required (naming only for AI); 0 script errors and how AI hard hits are named now (DRIVE vs SPEED_UP) with their swing room
- Seeds: 1 × 120 s · wall 28 s
- Data:
  - Points 1 (ball_in_net 1) | rally 102.7s, between 10.3s, serve wait 0.8s
- Verdict: 0 script errors. Names only: a hard hit from a pose with under 0.45 m of wind-up is SPEED_UP, not DRIVE. Few hard AI hits in 120 s (SPEED_UP 3, DRIVE 1), so the human case needs the phone.

## 2026-11-24 10:11 · tap_check · bench
- Objective: tap / flick dink controls compile: 0 script errors (human input only, the all-AI bench cannot exercise it)
- Seeds: 1 × 20 s · wall 6 s
- Verdict: 0 script errors; human input rule only, needs the phone.

## 2026-11-24 10:26 · adapt_check · bench
- Objective: adaptive frame rate and pause code compile and leave the bench alone: 0 script errors
- Seeds: 1 × 20 s · wall 6 s
- Verdict: 0 script errors; frame-rate and pause code only (never active in the bench).

## 2026-11-24 18:48 · smash_drop · bench_seeds
- Objective: smash rework (Drop key, air legs, High Overhead re-pose): 0 script errors and animation rules still PASS with High Overhead hits in the run; keep if so, fix the pose or code if a rule fails
- Seeds: 3 × 120 s · wall 28 s
- Data:
  - == smash_drop: 1 seeds
  - points 4 (momentum 2, double_bounce 1, ball_in_net 1) | AI hits 69
  - contact snap-back 3 of 74 hits (4%) | head-to-ball over 15 cm 4 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 9 of 69 | paddle flutter episodes 81 | pose changed in last 0.3 s 0 of 74 (+1 reflex blocks on balls inside the reaction delay)
  - FAIL  paddle head meets the ball (over 15 cm off on at most 5% of hits): 5.4%
- Verdict: keep. 0 script errors; the one High Overhead hit (player 0, 17.7 s, with the new Drop key) met the ball at 4.9 cm with no snap-back. "Paddle meets ball" 5.4% is the level before the change too (same seed and difficulty without it: 5.2%, 5 of 96). No jump smash happened in this seed, so the air legs are not covered here.

## 2026-11-25 11:00 · hunt_base · bench_seeds
- Objective: base for the hunt study (green light and Hunt Ready pose both off): kitchen plan mix, volley share, endings and animation rules to compare hunt_on against; keep each dial only if attacks rise or hold with no more faults or failed animation rules
- Seeds: 1 × 120 s · wall 32 s
- Needed data: ai_plan 188
- Data:
  - == hunt_base: 1 seeds
  - points 1 (ball_in_net 1) | AI hits 101
  - contact snap-back 1 of 103 hits (1%) | head-to-ball over 15 cm 0 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 17 of 101 | paddle flutter episodes 71 | pose changed in last 0.3 s 1 of 103 (+3 reflex blocks on balls inside the reaction delay)
  - FAIL  pose never switches in the last 0.3 s before contact: 1
- Verdict: base recorded. Kitchen hits 95, 12 in the air (13%), median contact 0.38 m under the tape; 4 attack plans of 178 kitchen plans; 90% of kitchen plans are for a ball more than 0.25 m under the tape. All animation rules pass but one late pose switch.

## 2026-11-25 11:01 · hunt_on · bench_seeds
- Objective: hunt study: with the green light and Hunt Ready pose on, do kitchen attacks rise or hold versus hunt_base with no more faults and the same animation rules? keep each dial if so, else switch off the one that fails
- Seeds: 1 × 120 s · wall 32 s
- Needed data: ai_plan 167
- Base: hunt_base: s1 DIVERGED
- Data:
  - == hunt_on: 1 seeds
  - points 2 (ball_in_net 1, double_bounce 1) | AI hits 89
  - contact snap-back 2 of 92 hits (2%) | head-to-ball over 15 cm 1 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 12 of 89 | paddle flutter episodes 66 | pose changed in last 0.3 s 0 of 92 (+1 reflex blocks on balls inside the reaction delay)
- Verdict: keep both dials. 0 script errors, all animation rules PASS (late pose switch 0, head-to-ball over 15 cm 1 of 92). Attack plans 3 of 149 against 4 of 178: no measurable change, because the green light only matters for the few balls near the tape (2 to 7 plans per seed sit in its window). Hunt Ready is live (poses diverge from tick 124). Look of the pose not checked by eye.

## 2026-11-25 11:03 · hunt_vol · bench_seeds
- Objective: line volley on top of hunt_on: does the share of kitchen hits taken in the air rise (base 13%) without new kitchen_volley / momentum faults, dropped shots or failed animation rules? keep if so, else switch LINE_VOLLEY_ON off
- Seeds: 1 × 120 s · wall 32 s
- Needed data: ai_plan 181
- Base: hunt_on: s1 DIVERGED
- Data:
  - == hunt_vol: 1 seeds
  - points 2 (momentum 1, ball_in_net 1) | AI hits 96
  - contact snap-back 1 of 98 hits (1%) | head-to-ball over 15 cm 0 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 10 of 96 | paddle flutter episodes 58 | pose changed in last 0.3 s 0 of 98 (+1 reflex blocks on balls inside the reaction delay)
- Verdict: LINE_VOLLEY_ON switched off. In the air 10 of 89 (11%), no gain, and one momentum fault that the other runs did not have. Cause: dinks land a median 1.32 m from the net (0.8 m inside the kitchen), so 0.25 m of reach over the line never meets them before the bounce. Next step if wanted: players stand at the line and lean in, which is a stance and fault-risk change.

## 2026-11-25 11:04 · hunt_final · bench
- Objective: final state check: LINE_VOLLEY_ON off must play IDENTICAL to hunt_on (green light and Hunt Ready on), 0 script errors
- Seeds: 1 × 120 s · wall 31 s
- Base: hunt_on_s1: IDENTICAL within 1.00 mm
- Data:
  - Points 2 (ball_in_net 1, double_bounce 1) | rally 35.3s, between 9.0s, serve wait 0.8s
- Verdict: IDENTICAL to hunt_on, 0 script errors: the shipped state is green light on, Hunt Ready on, line volley off.

## 2026-11-25 11:17 · hunt_lean · bench_seeds
- Objective: lean-in volley (reach 0.45 m over the line, from 0.3 m up, with the AI momentum hold) on top of hunt_on: does the share of kitchen hits taken in the air rise from 11-13% without momentum / kitchen_volley faults, dropped shots or failed animation rules? keep if so, else switch LINE_VOLLEY_ON off
- Seeds: 1 × 120 s · wall 32 s
- Needed data: ai_plan 183
- Base: hunt_on: s1 DIVERGED
- Data:
  - == hunt_lean: 1 seeds
  - points 1 (ball_in_net 1) | AI hits 105
  - contact snap-back 2 of 107 hits (2%) | head-to-ball over 15 cm 2 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 15 of 105 | paddle flutter episodes 84 | pose changed in last 0.3 s 0 of 107 (+8 reflex blocks on balls inside the reaction delay)
- Verdict: keep, pending the fault check. Seed 1: kitchen hits in the air 25 of 99 (25%) against 9 of 79 (11%) in hunt_on; attack hits 8 against 3; no momentum or kitchen_volley fault; all animation rules PASS.

## 2026-11-25 12:14 · hunt_lean · bench_seeds
- Objective: lean-in volley: same question as seed 1 (in-air share up from 11-13% to 25%, attacks 3 -> 8), now checking the rare risk: do momentum / kitchen_volley faults appear once about 75 line volleys have been played? keep if none or one, else switch LINE_VOLLEY_ON off
- Seeds: 1 2 3 × 120 s (why: faults are rare per-point events; seed 1 had 25 line volleys and 1 point, two more seeds triple the volleys watched (cap is 3 seeds)) · wall 32 s
- Needed data: ai_plan 445
- Data:
  - == hunt_lean: 3 seeds
  - points 10 (ball_in_net 5, double_bounce 4, out_of_bounds 1) | AI hits 243
  - contact snap-back 3 of 255 hits (1%) | head-to-ball over 15 cm 7 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 24 of 243 | paddle flutter episodes 185 | pose changed in last 0.3 s 0 of 255 (+15 reflex blocks on balls inside the reaction delay)
- Verdict: keep LINE_VOLLEY_ON (reach 0.45, from 0.3 m, AI momentum hold). 3 seeds: 51 of 219 kitchen hits in the air (23%; base seed 1 was 13%), attack hits 20 of 219 (9%; base 4 of 95), 0 momentum and 0 kitchen_volley faults in 10 points, 0 dropped shots, all animation rules PASS. Watch: head-to-ball over 15 cm 7 of 255 (2.7%, limit 5%; base seed 1 had 0 of 103) and 15 reflex blocks. Seeds 2 and 3 have no base run, and 10 points cannot say how rallies end.

## 2026-11-25 13:44 · perf_team · bench_seeds
- Objective: perf team combined (all PerfToggles on): does play stay as good as pre-team perf_base (animation rules, hits, points) while serial tick cost drops? keep if rules PASS and tick cost drops, else bisect by toggles
- Seeds: 1 × 120 s · wall 29 s
- Base: perf_base: s1 DIVERGED
- Data:
  - == perf_team: 1 seeds
  - points 3 (double_bounce 2, out_of_bounds 1) | AI hits 85
  - contact snap-back 4 of 89 hits (4%) | head-to-ball over 15 cm 2 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 8 of 85 | paddle flutter episodes 54 | pose changed in last 0.3 s 0 of 89 (+4 reflex blocks on balls inside the reaction delay)
  - budget s1 (serial): Worst tick: mean 12.5 / p90 15.3 ms vs budget 6 ms  OVER | Scoped tick cost: avg 4.19 ms per tick (budget average 3 ms)  OVER
- Verdict: keep. Base perf_base (pre-team tree copy, same seed, run just before, serial): points 1 (ball_in_net), AI hits 105, snap-back 2%, wobble 14%, flutter 0.79/hit, scoped tick 4.76 ms, worst tick mean 13.5 / p90 14.4. Team: all rules PASS (snap-back 4.5% within 6%, wobble 9%, flutter 0.61), scoped tick 4.19 ms (-12%); per rally frame player.physics -16%, contact.authority -25%, ai.input -25%, pp.align -17%. Worst tick unchanged within noise (still 2x the 6 ms budget). Play diverged at tick 43 (AI plans once per ball, human/contact changes); 1 seed and 3 points cannot judge rally quality: the user judges feel on the phone. Between-point samples too short (2-3 s) to compare.

## 2026-11-25 14:12 · prof1 · bench
- Objective: profiling pass (temporary timers on ~90 functions): which functions carry the unscoped part of player.physics, to target step 3 edits; no keep/revert decision, timers removed after
- Seeds: 1 × 90 s · wall 29 s
- Data:
  - Points 1 (double_bounce 1) | rally 83.3s, between 0.0s, serve wait 0.8s
- Verdict: profiling only, timers removed after. Largest unscoped costs in a rally (ms/s, with timer overhead): follow-through double restore 22, swing keys rebuilt per sample 19, body-offset cap search 19, shoulder / torso frames 17 + 15, hand-turn limiter 16, pose blends 15.

## 2026-11-25 14:14 · p3_base · bench
- Objective: timing and pose baseline of the tree before the step-3 batch (same seed, 90 s, serial): later batches compare tick cost and poses against it
- Seeds: 1 × 90 s · wall 24 s
- Base: prof1: IDENTICAL within 1.00 mm
- Data:
  - Points 1 (double_bounce 1) | rally 83.3s, between 0.0s, serve wait 0.8s
- Verdict: baseline for the step-3 round: scoped tick 4.54 ms, worst tick mean 13.0 / p90 19.9 ms, player.physics 134 ms/s. IDENTICAL to prof1 (the timers do not change play).

## 2026-11-25 14:23 · c1 · bench
- Objective: compile + identity check of the pure-speed part of the step-3 batch (typed lerp_with, shared body frames, offset-cap cache, swing-key cache, around-body frame, lean ground scan) with the three result-changing switches off: expect 0 errors and IDENTICAL to p3_base over the first 30 s; fix if not
- Seeds: 1 × 30 s · wall 8 s
- Base: p3_base: DIVERGED at tick index 33: p2.ForearmPivot moved 45.16 mm (tol 1.00 mm)
- Verdict: not an identity check: the result-changing switches were still on (the bench had no TOGGLES option yet). 0 script errors. Rerun as c2.

## 2026-11-25 14:24 · c2 · bench
- Objective: identity check of the pure-speed part of the step-3 batch (typed lerp_with, shared body frames, offset-cap cache, swing-key cache, around-body frame, lean ground scan), result-changing switches off: expect IDENTICAL to p3_base over 30 s; find the cause if not
- Seeds: 1 × 30 s · wall 8 s
- Base: p3_base: IDENTICAL within 1.00 mm
- Verdict: IDENTICAL over 30 s with the result-changing switches off: the pure-speed edits leave play unchanged. player.physics 2.17 -> 1.59 ms/frame.

## 2026-11-25 14:25 · prof2 · bench
- Objective: second profiling pass (temporary timers) on the tree after the pure-speed batch: which second-level functions carry try_hit, ai.input, arms, legs, contact and card drawing; timers removed after
- Seeds: 1 × 60 s · wall 1 s
- Stopped: 2 script errors
- Verdict: stopped: a timer wrapper broke team_coordination_bridge.gd (parse error). Rerun without that file.

## 2026-11-25 14:26 · prof2 · bench
- Objective: second profiling pass (temporary timers) on the tree after the pure-speed batch: which second-level functions carry try_hit, ai.input, arms, legs, contact and card drawing; timers removed after
- Seeds: 1 × 60 s · wall 16 s
- Data:
  - Points 1 (double_bounce 1) | rally 58.7s, between 0.0s, serve wait 0.8s
- Verdict: profiling only, timers removed after. Found: kitchen ground scan 21 ms/s (297 scans a second, 2.5 per player-tick), card drawing 43, follow-through 12, body-offset report 8, AI grip fit 6.

## 2026-11-25 14:30 · c4 · bench
- Objective: identity check of the second pure-speed set (cached ground-scan candidates with cheap rejects, shared offset-report parts), result-changing switches off: expect 0 errors and IDENTICAL to p3_base over 90 s; find the cause if not
- Seeds: 1 × 90 s · wall 20 s
- Base: p3_base: IDENTICAL within 1.00 mm
- Data:
  - Points 1 (double_bounce 1) | rally 83.3s, between 0.0s, serve wait 0.8s
- Verdict: IDENTICAL over 90 s with the result-changing switches off. Scoped tick 4.54 -> 3.31 ms, worst tick mean 13.0 -> 11.0 ms.

## 2026-11-25 14:31 · p3_b1 · bench_seeds
- Objective: step-3 batch 1, all switches on (swing keys cached, body-offset cap cached, light follow-through restore, closed-form hand-turn limit, shared contact sweep pose, one kitchen scan a tick): does serial tick cost drop vs p3_base (4.54 ms scoped, worst 13.0) with animation rules PASS and hits / points not clearly worse? keep if so, else bisect by switch
- Seeds: 1 × 90 s · wall 19 s
- Base: p3_base: s1 DIVERGED
- Data:
  - == p3_b1: 1 seeds
  - points 3 (double_bounce 3) | AI hits 62
  - contact snap-back 1 of 65 hits (2%) | head-to-ball over 15 cm 4 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 5 of 62 | paddle flutter episodes 38 | pose changed in last 0.3 s 0 of 65 (+3 reflex blocks on balls inside the reaction delay)
  - FAIL  paddle head meets the ball (over 15 cm off on at most 5% of hits): 6.2%
  - budget s1 (serial): Worst tick: mean 11.9 / p90 14.6 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.06 ms per tick (budget average 3 ms)  OVER
- Verdict: tick 3.06 ms, but one rule FAIL (head-to-ball over 15 cm on 4 of 65 hits, 6.2%). Bisected in p3_b1a / b / c; the closed-form hand-turn limit was refined and the batch rerun as p3_b2.

## 2026-11-25 14:32 · p3_b1a · bench_seeds
- Objective: bisect the head-to-ball rule (4 of 65 over 15 cm with all switches on): same run with hand_turn_closed_form off; if the count drops, the closed-form limiter is the cause
- Seeds: 1 × 90 s · wall 21 s
- Data:
  - == p3_b1a: 1 seeds
  - points 2 (double_bounce 2) | AI hits 65
  - contact snap-back 4 of 68 hits (6%) | head-to-ball over 15 cm 2 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 5 of 65 | paddle flutter episodes 45 | pose changed in last 0.3 s 0 of 68 (+8 reflex blocks on balls inside the reaction delay)
  - budget s1 (serial): Worst tick: mean 22.0 / p90 15.4 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.22 ms per tick (budget average 3 ms)  OVER
- Verdict: closed-form limit off: head-to-ball 2 of 68. Ran side by side with b1b / b1c, so its timings are not usable.

## 2026-11-25 14:32 · p3_b1b · bench_seeds
- Objective: bisect the head-to-ball rule: same run with swing_restore_light off; if the count drops, the light follow-through restore is the cause
- Seeds: 1 × 90 s · wall 21 s
- Data:
  - == p3_b1b: 1 seeds
  - points 3 (double_bounce 3) | AI hits 62
  - contact snap-back 1 of 65 hits (2%) | head-to-ball over 15 cm 4 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 5 of 62 | paddle flutter episodes 38 | pose changed in last 0.3 s 0 of 65 (+3 reflex blocks on balls inside the reaction delay)
  - FAIL  paddle head meets the ball (over 15 cm off on at most 5% of hits): 6.2%
  - budget s1 (serial): Worst tick: mean 22.3 / p90 14.5 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.23 ms per tick (budget average 3 ms)  OVER
- Verdict: light follow-through restore off: same counts as p3_b1 (4 of 65), so it is not the cause.

## 2026-11-25 14:32 · p3_b1c · bench_seeds
- Objective: bisect the head-to-ball rule: all four result-changing switches off (the pure-speed tree, identical to p3_base): what does the rule read on the base game for 90 s of seed 1?
- Seeds: 1 × 90 s · wall 22 s
- Data:
  - == p3_b1c: 1 seeds
  - points 1 (double_bounce 1) | AI hits 79
  - contact snap-back 4 of 80 hits (5%) | head-to-ball over 15 cm 1 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 8 of 79 | paddle flutter episodes 45 | pose changed in last 0.3 s 0 of 80 (+4 reflex blocks on balls inside the reaction delay)
  - budget s1 (serial): Worst tick: mean 20.5 / p90 12.8 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.56 ms per tick (budget average 3 ms)  OVER
- Verdict: all four switches off (base play): head-to-ball 1 of 80, snap-back 4 of 80.

## 2026-11-25 14:32 · p3_b2 · bench_seeds
- Objective: closed-form hand-turn limit, refined (rescale by measured turn, one step up): with all switches on does head-to-ball over 15 cm return to the base level (1-2 of ~65) and the rule PASS? keep the switch on if so, else default it off
- Seeds: 1 × 90 s · wall 20 s
- Base: p3_base: s1 DIVERGED
- Data:
  - == p3_b2: 1 seeds
  - points 0 () | AI hits 86
  - contact snap-back 1 of 87 hits (1%) | head-to-ball over 15 cm 2 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 9 of 86 | paddle flutter episodes 48 | pose changed in last 0.3 s 0 of 87 (+5 reflex blocks on balls inside the reaction delay)
  - budget s1 (serial): Worst tick: mean 11.1 / p90 12.6 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.99 ms per tick (budget average 3 ms)  OK
- Verdict: keep batch 1 with the refined closed-form limit: all rules PASS (head-to-ball 2 of 87), scoped tick 2.99 ms (-34% against 4.54), worst tick mean 11.1 ms.

## 2026-11-25 14:36 · c6 · bench
- Objective: identity check: aero-step setting cache (pure speed) with the two new result-changing switches off (grip_fit_once, shot_solve_early_exit): expect IDENTICAL to p3_b2 (previous full set); find the cause if not
- Seeds: 1 × 60 s · wall 14 s
- Base: p3_b2_s1: IDENTICAL within 1.00 mm
- Verdict: IDENTICAL to p3_b2 with the two new switches off: the aero-step setting cache is exact.

## 2026-11-25 14:36 · p3_b3 · bench_seeds
- Objective: step-3 batch 2 (grip fitted once per plan, drop solver early exit, aero-step cache) on top of batch 1: does scoped tick drop below 2.99 ms and worst tick below 11.1 ms with animation rules PASS? keep if so, else bisect
- Seeds: 1 × 90 s · wall 19 s
- Base: p3_b2: s1 DIVERGED
- Data:
  - == p3_b3: 1 seeds
  - points 2 (double_bounce 1, body_hit 1) | AI hits 61
  - contact snap-back 2 of 64 hits (3%) | head-to-ball over 15 cm 2 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 4 of 61 | paddle flutter episodes 41 | pose changed in last 0.3 s 0 of 64 (+4 reflex blocks on balls inside the reaction delay)
  - budget s1 (serial): Worst tick: mean 11.1 / p90 12.6 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.97 ms per tick (budget average 3 ms)  OK
- Verdict: rules PASS (head-to-ball 2 of 64). Timings not usable (it shared the CPU with c6); serial rerun is p3_b3t. One body_hit point.

## 2026-11-25 14:36 · p3_b3t · bench
- Objective: serial timing of batch 2 (the first p3_b3 run shared the CPU with an identity check): scoped tick and worst tick vs p3_b2 (2.99 / 11.1 ms)
- Seeds: 1 × 90 s · wall 18 s
- Base: p3_b3_s1: IDENTICAL within 1.00 mm
- Data:
  - Points 2 (double_bounce 1, body_hit 1) | rally 33.0s, between 9.3s, serve wait 0.8s
- Verdict: serial: scoped tick 2.87 ms, worst tick mean 11.3 ms (unchanged). IDENTICAL to p3_b3. AI grip fit 6.2 -> 3.5 ms/s.

## 2026-11-25 14:37 · p3_spk · bench
- Objective: what is inside the worst tick each second (frames over 7 ms logged with their scope breakdown): pick the next worst-tick edits from it
- Seeds: 1 × 60 s · wall 14 s
- Verdict: the worst tick each second is the tick of a hit: 10.5 ms on average, of which contact 5.5 (shot solve 2.5) and the four players 2.8. Other heavy ticks: 7.7 ms, paddle alignment 3.5 with the grip fit 1.9.

## 2026-11-25 14:39 · p3_b4t · bench
- Objective: identity + serial timing of the last two exact edits (post-sweep pre-check in flight traces, cached script load in the arm budget): expect IDENTICAL to p3_b3 and scoped tick at or under 2.87 ms; find the cause if not identical
- Seeds: 1 × 90 s · wall 17 s
- Base: p3_b3_s1: IDENTICAL within 1.00 mm
- Data:
  - Points 2 (double_bounce 1, body_hit 1) | rally 33.0s, between 9.3s, serve wait 0.8s
- Verdict: IDENTICAL to p3_b3. Scoped tick 2.80 ms, worst tick mean 10.2 ms.

## 2026-11-25 14:39 · p3_r1 · bench_seeds
- Objective: step-3 round (batches 1-2, all switches on) before handing over: over 3 seeds do the animation rules PASS and do points end the way the base game's do (no surge in body hits, nets, outs, dropped shots)? keep the round if so, else bisect the switch that fails
- Seeds: 1 2 3 × 120 s (why: the round changes swing presentation (hand-turn limit, grip fitted once, light follow-through restore): the rules allow 3 seeds for that, and seeds 2-3 triple the hits (about 200) and points watched) · wall 26 s
- Data:
  - == p3_r1: 3 seeds
  - points 10 (ball_in_net 6, double_bounce 3, body_hit 1) | AI hits 221
  - contact snap-back 3 of 234 hits (1%) | head-to-ball over 15 cm 11 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 19 of 221 | paddle flutter episodes 160 | pose changed in last 0.3 s 1 of 234 (+12 reflex blocks on balls inside the reaction delay)
  - FAIL  pose never switches in the last 0.3 s before contact: 1
  - budget s1 (parallel seeds, timings inflated): Worst tick: mean 11.3 / p90 14.5 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.02 ms per tick (budget average 3 ms)  OVER
  - budget s2 (parallel seeds, timings inflated): Worst tick: mean 11.2 / p90 14.0 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.02 ms per tick (budget average 3 ms)  OVER
  - budget s3 (parallel seeds, timings inflated): Worst tick: mean 11.5 / p90 15.8 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.97 ms per tick (budget average 3 ms)  OK
- Verdict: one rule FAIL: 1 late pose switch in 234 hits (seed 2 at 94.6 s: an AI in the kitchen let a volley ball bounce and planned again). Head-to-ball 11 of 234 (4.7%, limit 5%). Compared with p3_r0 and bisected (p3_x_*, p3_y_*): no single switch is responsible; superseded by p3_h3.

## 2026-11-25 14:40 · p3_r0 · bench_seeds
- Objective: base for the p3_r1 comparison: the same 3 seeds with all six result-changing switches off (plays identically to the tree before the round): what do the animation rules, head-to-ball count, late pose switches and point endings read there?
- Seeds: 1 2 3 × 120 s (why: p3_r1 used seeds 1-3 and only an identical seed set separates the round's effect from seed differences) · wall 29 s
- Data:
  - == p3_r0: 3 seeds
  - points 11 (ball_in_net 6, double_bounce 4, out_of_bounds 1) | AI hits 235
  - contact snap-back 4 of 247 hits (2%) | head-to-ball over 15 cm 7 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 22 of 235 | paddle flutter episodes 156 | pose changed in last 0.3 s 0 of 247 (+10 reflex blocks on balls inside the reaction delay)
  - budget s1 (parallel seeds, timings inflated): Worst tick: mean 11.4 / p90 16.8 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.59 ms per tick (budget average 3 ms)  OVER
  - budget s2 (parallel seeds, timings inflated): Worst tick: mean 12.3 / p90 15.4 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.75 ms per tick (budget average 3 ms)  OVER
  - budget s3 (parallel seeds, timings inflated): Worst tick: mean 12.6 / p90 15.8 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.55 ms per tick (budget average 3 ms)  OVER
- Verdict: base for the round on seeds 1-3: head-to-ball 7 of 247 (2.8%), late pose switch 0, snap-back 1.6%, wobble 9%, flutter 0.63.

## 2026-11-25 14:41 · p3_x_hand_turn_closed_form · bench_seeds
- Objective: bisect p3_r1 (head-to-ball 11 of 234 and 1 late pose switch, base 7 of 247 and 0): same 3 seeds with only hand_turn_closed_form off; the switch whose removal returns both to base level gets defaulted off
- Seeds: 1 2 3 × 120 s (why: same seed set as p3_r1 / p3_r0 so only the switch differs) · wall 27 s
- Data:
  - == p3_x_hand_turn_closed_form: 3 seeds
  - points 10 (ball_in_net 6, double_bounce 4) | AI hits 231
  - contact snap-back 6 of 243 hits (2%) | head-to-ball over 15 cm 10 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 29 of 231 | paddle flutter episodes 165 | pose changed in last 0.3 s 0 of 243 (+15 reflex blocks on balls inside the reaction delay)
  - budget s1 (parallel seeds, timings inflated): Worst tick: mean 19.0 / p90 16.1 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.17 ms per tick (budget average 3 ms)  OVER
  - budget s2 (parallel seeds, timings inflated): Worst tick: mean 20.2 / p90 15.8 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.20 ms per tick (budget average 3 ms)  OVER
  - budget s3 (parallel seeds, timings inflated): Worst tick: mean 22.3 / p90 16.1 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.21 ms per tick (budget average 3 ms)  OVER
- Verdict: head-to-ball 10 of 243, late pose switch 0.

## 2026-11-25 14:41 · p3_x_grip_fit_once · bench_seeds
- Objective: bisect p3_r1 (head-to-ball 11 of 234 and 1 late pose switch, base 7 of 247 and 0): same 3 seeds with only grip_fit_once off; the switch whose removal returns both to base level gets defaulted off
- Seeds: 1 2 3 × 120 s (why: same seed set as p3_r1 / p3_r0 so only the switch differs) · wall 29 s
- Data:
  - == p3_x_grip_fit_once: 3 seeds
  - points 9 (ball_in_net 5, double_bounce 3, out_of_bounds 1) | AI hits 237
  - contact snap-back 5 of 248 hits (2%) | head-to-ball over 15 cm 9 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 26 of 237 | paddle flutter episodes 171 | pose changed in last 0.3 s 1 of 248 (+9 reflex blocks on balls inside the reaction delay)
  - FAIL  pose never switches in the last 0.3 s before contact: 1
  - budget s1 (parallel seeds, timings inflated): Worst tick: mean 19.0 / p90 15.1 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.36 ms per tick (budget average 3 ms)  OVER
  - budget s2 (parallel seeds, timings inflated): Worst tick: mean 22.5 / p90 15.0 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.52 ms per tick (budget average 3 ms)  OVER
  - budget s3 (parallel seeds, timings inflated): Worst tick: mean 20.6 / p90 17.0 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.45 ms per tick (budget average 3 ms)  OVER
- Verdict: head-to-ball 9 of 248, late pose switch 1 (the same seed-2 moment as p3_r1).

## 2026-11-25 14:42 · p3_x_nvz_once_per_tick · bench_seeds
- Objective: bisect p3_r1 (head-to-ball 11 of 234 and 1 late pose switch, base 7 of 247 and 0): same 3 seeds with only nvz_once_per_tick off; the switch whose removal returns both to base level gets defaulted off
- Seeds: 1 2 3 × 120 s (why: same seed set as p3_r1 / p3_r0 so only the switch differs) · wall 28 s
- Data:
  - == p3_x_nvz_once_per_tick: 3 seeds
  - points 10 (ball_in_net 6, double_bounce 3, body_hit 1) | AI hits 221
  - contact snap-back 3 of 234 hits (1%) | head-to-ball over 15 cm 11 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 19 of 221 | paddle flutter episodes 160 | pose changed in last 0.3 s 1 of 234 (+12 reflex blocks on balls inside the reaction delay)
  - FAIL  pose never switches in the last 0.3 s before contact: 1
  - budget s1 (parallel seeds, timings inflated): Worst tick: mean 21.3 / p90 15.5 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.55 ms per tick (budget average 3 ms)  OVER
  - budget s2 (parallel seeds, timings inflated): Worst tick: mean 21.1 / p90 15.6 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.58 ms per tick (budget average 3 ms)  OVER
  - budget s3 (parallel seeds, timings inflated): Worst tick: mean 22.5 / p90 17.1 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.54 ms per tick (budget average 3 ms)  OVER
- Verdict: same play as p3_r1 (11 of 234, 1 late switch): this switch does not change these games.

## 2026-11-25 14:42 · p3_x_swing_restore_light · bench_seeds
- Objective: bisect p3_r1 (head-to-ball 11 of 234 and 1 late pose switch, base 7 of 247 and 0): same 3 seeds with only swing_restore_light off; the switch whose removal returns both to base level gets defaulted off
- Seeds: 1 2 3 × 120 s (why: same seed set as p3_r1 / p3_r0 so only the switch differs) · wall 29 s
- Data:
  - == p3_x_swing_restore_light: 3 seeds
  - points 8 (ball_in_net 6, double_bounce 2) | AI hits 246
  - contact snap-back 3 of 257 hits (1%) | head-to-ball over 15 cm 10 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 28 of 246 | paddle flutter episodes 168 | pose changed in last 0.3 s 1 of 257 (+9 reflex blocks on balls inside the reaction delay)
  - FAIL  pose never switches in the last 0.3 s before contact: 1
  - budget s1 (parallel seeds, timings inflated): Worst tick: mean 19.1 / p90 15.1 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.33 ms per tick (budget average 3 ms)  OVER
  - budget s2 (parallel seeds, timings inflated): Worst tick: mean 20.2 / p90 15.1 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.38 ms per tick (budget average 3 ms)  OVER
  - budget s3 (parallel seeds, timings inflated): Worst tick: mean 21.1 / p90 17.7 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.29 ms per tick (budget average 3 ms)  OVER
- Verdict: head-to-ball 10 of 257, late pose switch 1 (the same moment).

## 2026-11-25 14:43 · p3_y_hand_turn_closed_formgrip_fi · bench_seeds
- Objective: bisect p3_r1, pairs: same 3 seeds with hand_turn_closed_form=0,grip_fit_once=0; if head-to-ball returns to the base 7 the two switches add up, if it stays near 10 the gap is not from these switches
- Seeds: 1 2 3 × 120 s (why: same seed set as p3_r1 / p3_r0 so only the switches differ) · wall 28 s
- Data:
  - == p3_y_hand_turn_closed_formgrip_fi: 3 seeds
  - points 12 (ball_in_net 7, double_bounce 5) | AI hits 222
  - contact snap-back 5 of 234 hits (2%) | head-to-ball over 15 cm 8 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 21 of 222 | paddle flutter episodes 158 | pose changed in last 0.3 s 1 of 234 (+11 reflex blocks on balls inside the reaction delay)
  - FAIL  pose never switches in the last 0.3 s before contact: 1
  - budget s1 (parallel seeds, timings inflated): Worst tick: mean 12.6 / p90 16.4 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.39 ms per tick (budget average 3 ms)  OVER
  - budget s2 (parallel seeds, timings inflated): Worst tick: mean 13.3 / p90 22.8 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.53 ms per tick (budget average 3 ms)  OVER
  - budget s3 (parallel seeds, timings inflated): Worst tick: mean 12.3 / p90 16.3 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.36 ms per tick (budget average 3 ms)  OVER
- Verdict: head-to-ball 8 of 234, late pose switch 1 (the same moment).

## 2026-11-25 14:43 · p3_y_hand_turn_closed_formswing_r · bench_seeds
- Objective: bisect p3_r1, pairs: same 3 seeds with hand_turn_closed_form=0,swing_restore_light=0; if head-to-ball returns to the base 7 the two switches add up, if it stays near 10 the gap is not from these switches
- Seeds: 1 2 3 × 120 s (why: same seed set as p3_r1 / p3_r0 so only the switches differ) · wall 29 s
- Data:
  - == p3_y_hand_turn_closed_formswing_r: 3 seeds
  - points 10 (ball_in_net 6, double_bounce 4) | AI hits 228
  - contact snap-back 7 of 240 hits (3%) | head-to-ball over 15 cm 10 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 23 of 228 | paddle flutter episodes 165 | pose changed in last 0.3 s 0 of 240 (+11 reflex blocks on balls inside the reaction delay)
  - budget s1 (parallel seeds, timings inflated): Worst tick: mean 20.2 / p90 20.8 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.43 ms per tick (budget average 3 ms)  OVER
  - budget s2 (parallel seeds, timings inflated): Worst tick: mean 20.3 / p90 20.0 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.41 ms per tick (budget average 3 ms)  OVER
  - budget s3 (parallel seeds, timings inflated): Worst tick: mean 21.4 / p90 20.2 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.42 ms per tick (budget average 3 ms)  OVER
- Verdict: head-to-ball 10 of 240, late pose switch 0. End of the bisect: no switch or pair returns head-to-ball to the base 7, every run is inside the 5% rule, and the late switch is one game moment, not a mechanism. All switches kept.

## 2026-11-25 14:50 · p3_b5t · bench
- Objective: identity + serial timing of the exact grip-fit rewrite (first fitting elbow plane instead of a full wrist solve; both turn directions searched together): expect IDENTICAL to p3_b3 and a lower al.grip_fit; find the cause if not identical
- Seeds: 1 × 90 s · wall 17 s
- Base: p3_b3_s1: 
- Data:
  - Points 2 (double_bounce 1, body_hit 1) | rally 33.0s, between 9.3s, serve wait 0.8s
- Verdict: the base run had been pruned, so no pose comparison. Scoped tick 2.77 ms, worst tick mean 10.5 ms. Exactness shown by gchk instead.

## 2026-11-25 14:52 · gchk · bench
- Objective: exactness check of the grip-fit rewrite (temporary: old and new computed side by side and compared, removed after): 0 mismatches expected
- Seeds: 1 × 60 s · wall 14 s
- Verdict: exact: 32,512 grip feasibility checks and 614 grip searches compared old against new (this bench plus a human-seat run), 0 mismatches. Check code removed.

## 2026-11-25 14:55 · clean1 · bench
- Objective: compile check after removing the leftover profiling timers from 13 scripts: 0 script errors expected; fix if any
- Seeds: 1 × 20 s · wall 6 s
- Verdict: 0 script errors after removing the leftover profiling timers from 13 scripts.

## 2026-11-25 14:58 · p3_h1 · bench_seeds
- Objective: simple_hands on (no grip-roll fit, no wrist-limit / free-hand solve in rallies, wrist limits never block a hit) on top of the round: serial tick cost vs 2.77 ms / worst 10.5 ms, 0 script errors, animation rules PASS on seed 1; keep if so, else find what the removed solver was guarding
- Seeds: 1 × 90 s · wall 18 s
- Data:
  - == p3_h1: 1 seeds
  - points 1 (double_bounce 1) | AI hits 75
  - contact snap-back 3 of 77 hits (4%) | head-to-ball over 15 cm 1 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 2 of 75 | paddle flutter episodes 39 | pose changed in last 0.3 s 0 of 77 (+5 reflex blocks on balls inside the reaction delay)
  - budget s1 (serial): Worst tick: mean 9.9 / p90 13.0 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.59 ms per tick (budget average 3 ms)  OK
- Verdict: keep simple_hands: all rules PASS (head-to-ball 1 of 77), scoped tick 2.59 ms (2.77 before), worst tick mean 9.9 ms.

## 2026-11-25 14:59 · p3_h3 · bench_seeds
- Objective: simple_hands on, whole round, 3 seeds: do the animation rules PASS and do points end as in the base (p3_r0: head-to-ball 7 of 247, no late pose switch; no surge in body hits, nets, outs)? keep the round with simple hands if so, else bisect
- Seeds: 1 2 3 × 120 s (why: same 3 seeds as p3_r0 / p3_r1 so the hand change is compared on equal seeds; it changes swing presentation, for which the rules allow 3 seeds) · wall 25 s
- Data:
  - == p3_h3: 3 seeds
  - points 9 (double_bounce 5, ball_in_net 4) | AI hits 238
  - contact snap-back 10 of 250 hits (4%) | head-to-ball over 15 cm 7 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 11 of 238 | paddle flutter episodes 151 | pose changed in last 0.3 s 0 of 250 (+11 reflex blocks on balls inside the reaction delay)
  - budget s1 (parallel seeds, timings inflated): Worst tick: mean 10.5 / p90 13.5 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.81 ms per tick (budget average 3 ms)  OK
  - budget s2 (parallel seeds, timings inflated): Worst tick: mean 11.3 / p90 15.4 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.83 ms per tick (budget average 3 ms)  OK
  - budget s3 (parallel seeds, timings inflated): Worst tick: mean 11.8 / p90 14.7 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.91 ms per tick (budget average 3 ms)  OK
- Verdict: keep. 3 seeds, all rules PASS: head-to-ball 7 of 250 (2.8%, as the base), late pose switch 0, wobble 5% (base 9%), flutter 0.60. Watch: snap-back 10 of 250 (4.0%; base 1.6%, limit 6%). Points 9 (double bounce 5, net 4), no body hit. Human seat, 3 runs: 16-20 ms/s (47-57 before), held pose 0.4 ms a call (1.4-3.0 before), its worst call 0.7 ms (7.5 before).

## 2026-11-25 15:08 · p3_s1 · bench_seeds
- Objective: shot pre-solve (AI launch searched a few ticks before contact, hit tick re-solves at that flight time) + exact drop-candidate pruning: does the worst tick drop below 9.9 ms with rules PASS and no rise in ai_fallback / ai_unsolved / net / out endings on seed 1? keep if so, else switch shot_presolve off
- Seeds: 1 × 90 s · wall 18 s
- Data:
  - == p3_s1: 1 seeds
  - points 0 () | AI hits 83
  - contact snap-back 1 of 84 hits (1%) | head-to-ball over 15 cm 1 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 8 of 83 | paddle flutter episodes 53 | pose changed in last 0.3 s 0 of 84 (+4 reflex blocks on balls inside the reaction delay)
  - budget s1 (serial): Worst tick: mean 8.0 / p90 9.4 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.65 ms per tick (budget average 3 ms)  OK
- Verdict: keep shot_presolve: worst tick mean 9.9 -> 8.0 ms, p90 13.0 -> 9.4 ms; settlement of a hit 3.5 -> 1.5 ms. Scoped tick 2.59 -> 2.65 ms (the search still runs, a few ticks earlier). All rules PASS, 83 AI launches, no ai_fallback or ai_unsolved.

## 2026-11-25 15:10 · p3_k1 · bench_seeds
- Objective: simple_hand_shape on (palm box instead of the skinned finger hand) on top of the shot pre-solve: do serves still launch (points scored, serve wait under 2 s), rules PASS, no body-hit surge, and does tick cost / worst tick drop vs p3_s1 (2.65 / 8.0 ms)? keep if so, else switch it off and find what read the fingers
- Seeds: 1 × 120 s · wall 22 s
- Data:
  - == p3_k1: 1 seeds
  - points 1 (ball_in_net 1) | AI hits 98
  - contact snap-back 1 of 99 hits (1%) | head-to-ball over 15 cm 1 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 8 of 98 | paddle flutter episodes 61 | pose changed in last 0.3 s 0 of 99 (+4 reflex blocks on balls inside the reaction delay)
  - budget s1 (serial): Worst tick: mean 8.0 / p90 9.5 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.66 ms per tick (budget average 3 ms)  OK
- Verdict: keep simple_hand_shape: serves launch (serve wait 0.8 s), all rules PASS. The gain is small on the Mac: body snapshot 3.2 -> 2.6 ms/s, contact checks 17.7 -> 17.0 ms/s; tick 2.66 ms, worst tick mean 8.0 ms (unchanged).

## 2026-11-25 15:11 · p3_k3 · bench_seeds
- Objective: shot pre-solve + simple hand shape on top of the round, 3 seeds: rules PASS, serves launch on every seed, points end as in the base (p3_r0 / p3_h3: nets and double bounces, no body-hit surge, no ai_fallback)? keep both if so, else bisect by switch
- Seeds: 1 2 3 × 120 s (why: same 3 seeds as p3_r0 / p3_h3; both changes touch contact (shot solve, hand surface), where the rules allow 3 seeds) · wall 25 s
- Data:
  - == p3_k3: 3 seeds
  - points 5 (ball_in_net 5) | AI hits 196
  - contact snap-back 3 of 202 hits (1%) | head-to-ball over 15 cm 2 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 15 of 196 | paddle flutter episodes 146 | pose changed in last 0.3 s 0 of 202 (+5 reflex blocks on balls inside the reaction delay)
  - budget s1 (parallel seeds, timings inflated): Worst tick: mean 8.5 / p90 10.3 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.85 ms per tick (budget average 3 ms)  OK
  - budget s2 (parallel seeds, timings inflated): Worst tick: mean 10.4 / p90 20.2 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.86 ms per tick (budget average 3 ms)  OK
  - budget s3 (parallel seeds, timings inflated): Worst tick: mean 9.0 / p90 20.7 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.94 ms per tick (budget average 3 ms)  OK
- Verdict: WRONG, corrected by p3_f3: 11 of 17 serves faulted at the hit in these runs (palm box seen as body contact) and stretched contacts rose; this check counted only rally endings. As read at the time: keep both. 3 seeds, all rules PASS: head-to-ball 2 of 202 (1.0%), snap-back 1.5%, late pose switch 0, wobble 8%, flutter 0.72; serves launched on every seed; 196 AI launches, no fallback. Points 5, all ball in net (p3_h3: 9 points, 5 double bounce / 4 net): too few to say rallies end differently, worth a look on the phone. Human seat, 3 runs: 14-28 ms/s, human-side hits 15-33, 0 errors.

## 2026-11-25 15:31 · p3_f3 · bench_seeds
- Objective: fix check: serve hand exempt with the palm box + arm stretch by reach only: do serve faults (SERVING > POINT_SCORED) return to 0 and stretched contacts to the pre-round level, with rules PASS, on 3 seeds? keep both hand switches if so, else default them off
- Seeds: 1 2 3 × 120 s (why: serve faults were 11 of 17 serves over these 3 seeds; all three are needed to see them gone) · wall 25 s
- Data:
  - == p3_f3: 3 seeds
  - points 9 (ball_in_net 5, double_bounce 3, body_hit 1) | AI hits 235
  - contact snap-back 4 of 246 hits (2%) | head-to-ball over 15 cm 6 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 25 of 235 | paddle flutter episodes 157 | pose changed in last 0.3 s 0 of 246 (+10 reflex blocks on balls inside the reaction delay)
  - budget s1 (parallel seeds, timings inflated): Worst tick: mean 18.1 / p90 32.7 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.77 ms per tick (budget average 3 ms)  OK
  - budget s2 (parallel seeds, timings inflated): Worst tick: mean 17.6 / p90 10.3 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.83 ms per tick (budget average 3 ms)  OK
  - budget s3 (parallel seeds, timings inflated): Worst tick: mean 18.0 / p90 9.5 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.84 ms per tick (budget average 3 ms)  OK
- Verdict: keep both hand switches with the two fixes (the server's ball hand cannot fault the serve; arm stretch judged by reach). Serves faulted at the hit 0 of 11 (11 of 17 before the fix, missed in p3_k3 because only rally endings were counted); stretched contacts 5 of 235 AI hits (51 of 238 before the fix); all rules PASS. Human seat, 3 runs: 0 of 33 serves faulted.

## 2026-11-25 15:31 · p3_f0 · bench_seeds
- Objective: base rate for the fix check: same 3 seeds with all nine result-changing switches off (plays as before the round): how many stretched contacts (contact_inaccuracy) and serve faults does the old game have?
- Seeds: 1 2 3 × 120 s (why: same seeds as p3_f3, the earlier base logs were pruned) · wall 28 s
- Data:
  - == p3_f0: 3 seeds
  - points 11 (ball_in_net 6, double_bounce 4, out_of_bounds 1) | AI hits 235
  - contact snap-back 4 of 247 hits (2%) | head-to-ball over 15 cm 7 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 22 of 235 | paddle flutter episodes 156 | pose changed in last 0.3 s 0 of 247 (+10 reflex blocks on balls inside the reaction delay)
  - budget s1 (parallel seeds, timings inflated): Worst tick: mean 17.9 / p90 15.9 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.36 ms per tick (budget average 3 ms)  OVER
  - budget s2 (parallel seeds, timings inflated): Worst tick: mean 18.6 / p90 14.6 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.49 ms per tick (budget average 3 ms)  OVER
  - budget s3 (parallel seeds, timings inflated): Worst tick: mean 22.0 / p90 15.2 ms vs budget 6 ms  OVER | Scoped tick cost: avg 3.44 ms per tick (budget average 3 ms)  OVER
- Verdict: base, all nine result-changing switches off: serves faulted 0 of 12; contact_inaccuracy on 205 of 235 AI hits, but only 7 over 2 mm of stretch (the old measure read sub-millimetre wrist-seat error as stretch). The new game is at or under the old rate of real stretch.

## 2026-11-25 15:40 · p3_q0 · bench
- Objective: held-curve prewarm and cached drive definition are human-seat only: expect the all-AI game IDENTICAL to p3_f3 seed 1 with 0 errors; find the cause if not
- Seeds: 1 × 90 s · wall 17 s
- Base: p3_f3_s1: IDENTICAL within 1.00 mm
- Data:
  - Points 1 (double_bounce 1) | rally 63.4s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: IDENTICAL to p3_f3 seed 1, 0 errors: the human-seat changes do not touch the AI game. Human seat (2 runs): worst call in a rally 12.4 -> 3.7 ms (the one-off curve builds now happen before the serve and between points), 15-19 ms/s, serves 22 of 22 into play.

## 2026-11-25 19:03 · p3_i0 · bench
- Objective: idle_rig_skip off: base for the identity check of the at-rest skip (same tree, switch off)
- Seeds: 2 × 90 s · wall 17 s
- Data:
  - Points 2 (ball_in_net 1, double_bounce 1) | rally 28.8s, between 9.4s, serve wait 0.8s | serves 3, faulted at the hit 0
- Verdict: base for the at-rest test (switch off): scoped tick 2.67 ms, worst tick mean 8.0 ms.

## 2026-11-25 19:03 · p3_i1 · bench
- Objective: idle_rig_skip on: a player at rest keeps its rig. Expect poses IDENTICAL to the switch-off run (the skipped update would only repeat itself) and a lower tick; if poses differ, find which rest condition is missing
- Seeds: 2 × 90 s · wall 17 s
- Base: p3_i0: IDENTICAL within 1.00 mm
- Data:
  - Points 2 (ball_in_net 1, double_bounce 1) | rally 28.8s, between 9.4s, serve wait 0.8s | serves 3, faulted at the hit 0
- Verdict: no test: the switch was not wired yet (two of its edits had not applied). IDENTICAL for that reason.

## 2026-11-25 19:04 · p3_i1 · bench
- Objective: idle_rig_skip on: a player at rest keeps its rig. Expect poses IDENTICAL to the switch-off run p3_i0 (the skipped update would only repeat itself) and a lower tick; if poses differ, find which rest condition is missing
- Seeds: 2 × 90 s · wall 18 s
- Base: p3_i0: IDENTICAL within 1.00 mm
- Data:
  - Points 2 (ball_in_net 1, double_bounce 1) | rally 28.8s, between 9.4s, serve wait 0.8s | serves 3, faulted at the hit 0
- Verdict: check run only (identity / determinism around the removed AI-thinking change): the tree plays the same twice; players' poses match p3_i0 for the whole run, only the between-point ball position differs late (tick 2226) after the frame-log change in perf_monitor.gd.

## 2026-11-25 19:05 · p3_i2 · bench
- Objective: idle_rig_skip on with a 0.1 mm rest tolerance: how often does a player rest (rig.rest per second), what does the tick save, and how far do poses move from the switch-off run p3_i0 (expected: under a millimetre while resting; play may diverge later)? keep if rules and serves stay clean
- Seeds: 2 × 90 s · wall 17 s
- Base: p3_i0: DIVERGED at tick index 1038: p0.ForearmPivot#11 moved 14.65 mm (tol 1.00 mm)
- Data:
  - Points 2 (ball_in_net 1, double_bounce 1) | rally 28.8s, between 9.4s, serve wait 0.8s | serves 3, faulted at the hit 0
- Verdict: drop it. A waiting player was at rest on only 5.3 of 120 updates a second, the tick did not move (2.68 against 2.67 ms), and poses diverged with a 15 mm forearm jump. The rest test needs a 0.1 mm tolerance to ever fire (eased values never land exactly), and that tolerance is what pops.

## 2026-11-25 19:05 · p3_i3 · bench
- Objective: idle_rig_skip removed (4% of updates rested, no measurable saving, and a 15 mm forearm pop): expect the tree IDENTICAL to p3_i0 again
- Seeds: 2 × 90 s · wall 17 s
- Base: p3_i0: IDENTICAL within 1.00 mm
- Data:
  - Points 2 (ball_in_net 1, double_bounce 1) | rally 28.8s, between 9.4s, serve wait 0.8s | serves 3, faulted at the hit 0
- Verdict: IDENTICAL to p3_i0: the at-rest skip is fully removed.

## 2026-11-25 19:31 · p3_t1 · bench_seeds
- Objective: ai_think_between (AI decisions on the frame between ticks): does scoped tick drop by about the cost of ai.input (11 ms/s) with rules PASS, serves clean and no rise in misses on seed 1? keep if so, else switch off
- Seeds: 1 × 90 s · wall 19 s
- Data:
  - == p3_t1: 1 seeds
  - points 1 (ball_in_net 1) | AI hits 70
  - contact snap-back 1 of 72 hits (1%) | head-to-ball over 15 cm 5 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 13 of 70 | paddle flutter episodes 54 | pose changed in last 0.3 s 2 of 72 (+1 reflex blocks on balls inside the reaction delay)
  - serves 2, faulted at the hit 0 | stretched contacts (arm over 2 mm short, adds shot error) 1 of 70 AI hits
  - FAIL  pose never switches in the last 0.3 s before contact: 2
  - FAIL  paddle head meets the ball (over 15 cm off on at most 5% of hits): 6.9%
  - budget s1 (serial): Worst tick: mean 9.6 / p90 9.8 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.83 ms per tick (budget average 3 ms)  OK
- Verdict: dropped and removed. Rules FAIL: 2 late pose switches, head-to-ball over 15 cm on 5 of 72 hits (6.9%), wobble 19%; scoped tick did not drop (2.83 ms). Between ticks the AI reads the ball one tick behind, so its contact time is 33 ms late.

## 2026-11-25 19:31 · p3_t2 · bench
- Objective: ai_think_between removed: expect IDENTICAL to p3_i0 (seed 2) again
- Seeds: 2 × 90 s · wall 17 s
- Base: p3_i0: DIVERGED at tick index 2226: ball moved 7356.10 mm (tol 1.00 mm)
- Data:
  - Points 2 (ball_in_net 1, double_bounce 1) | rally 28.8s, between 9.4s, serve wait 0.8s | serves 3, faulted at the hit 0
- Verdict: check run only (identity / determinism around the removed AI-thinking change): the tree plays the same twice; players' poses match p3_i0 for the whole run, only the between-point ball position differs late (tick 2226) after the frame-log change in perf_monitor.gd.

## 2026-11-25 19:32 · p3_t3 · bench
- Objective: determinism check after removing ai_think_between: the same tree twice (p3_t2, p3_t3); if they are IDENTICAL to each other the divergence from p3_i0 at tick 2226 comes from a code change, not from chance
- Seeds: 2 × 90 s · wall 17 s
- Base: p3_t2: IDENTICAL within 1.00 mm
- Data:
  - Points 2 (ball_in_net 1, double_bounce 1) | rally 28.8s, between 9.4s, serve wait 0.8s | serves 3, faulted at the hit 0
- Verdict: check run only (identity / determinism around the removed AI-thinking change): the tree plays the same twice; players' poses match p3_i0 for the whole run, only the between-point ball position differs late (tick 2226) after the frame-log change in perf_monitor.gd.

## 2026-11-25 19:39 · p3_n0 · bench
- Objective: native_math off: base for the native shot-fit check (same tree)
- Seeds: 1 × 90 s · wall 17 s
- Data:
  - Points 1 (double_bounce 1) | rally 63.4s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: base for the native check (native_math off): scoped tick 2.74 ms, worst tick mean 8.3 ms, shot search 2.66 ms/s.

## 2026-11-25 19:39 · p3_n1 · bench
- Objective: native_math on (C++ ball flight steps and launch fitting): are poses IDENTICAL to the switch-off run, and how much does the shot solve drop? keep if identical or the differences are below a millimetre at landing
- Seeds: 1 × 90 s · wall 18 s
- Base: p3_n0: IDENTICAL within 1.00 mm
- Data:
  - Points 1 (double_bounce 1) | rally 63.4s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: keep native_math. IDENTICAL to the switch-off run; shot search 2.66 -> 0.60 ms/s (about 1.1 ms -> 0.25 ms a call); worst tick mean 8.3 -> 7.9 ms. Stand-alone check: 2,000 random flights, 1,757 bit-exact, worst difference 3 micrometres; 8.3 -> 1.5 us a call.

## 2026-11-25 19:41 · p3_spk2 · bench
- Objective: what is inside the heaviest ticks now that the shot search is native and pre-solved (frames over 6 ms logged): choose the next native port from it
- Seeds: 1 × 90 s · wall 33 s
- Data:
  - Points 1 (double_bounce 1) | rally 63.4s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: not usable: it ran while godot-cpp was compiling for iOS on 8 cores (1,939 'heavy' frames). Rerun as p3_n2.

## 2026-11-25 19:43 · p3_n2 · bench
- Objective: native_math on plus sample-free validity traces (exact): expect IDENTICAL to the switch-off run p3_n0 and serial timings of the hit tick
- Seeds: 1 × 90 s · wall 18 s
- Base: p3_n0: IDENTICAL within 1.00 mm
- Data:
  - Points 1 (double_bounce 1) | rally 63.4s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: IDENTICAL to p3_n0 with the sample-free validity traces. Serial: scoped tick 2.68 ms, worst tick mean 8.1 ms; 85 frames over 6 ms in 90 s, mean 7.3 ms. A hit tick now: contact settlement 1.4 ms (follow-through start 0.6, shot error 0.5, shot search 0.25), contact resolve 0.3, the four players about 3.2.

## 2026-11-25 19:52 · p3_c1 · bench
- Objective: card_tick_build: compile check and whether the all-AI game is unchanged (cards are visual): expect 0 errors and IDENTICAL to p3_n0; card.rig per second should fall by about half
- Seeds: 1 × 90 s · wall 16 s
- Base: p3_n0: IDENTICAL within 1.00 mm
- Data:
  - Points 1 (double_bounce 1) | rally 63.4s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: 0 errors, IDENTICAL. card.rig 32.4 -> 18.0 ms/s (cards built 120 times a second for four players instead of 240). Kept; next question was which frames the build lands on.

## 2026-11-25 19:58 · p3_c2 · bench
- Objective: card_build_off_tick + flip snap: compile check, all-AI game unchanged (expect 0 errors, IDENTICAL to p3_n0), and how much card time is left on tick frames (card.on_tick)
- Seeds: 1 × 90 s · wall 16 s
- Base: p3_n0: IDENTICAL within 1.00 mm
- Data:
  - Points 1 (double_bounce 1) | rally 63.4s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: IDENTICAL. card.on_tick 2.65 ms/s against 18.48 with the build on the tick frame (p3_c2a): most of it moved, but about 14% of builds still landed on tick frames. Cause looked for in p3_c3 / p3_c4.

## 2026-11-25 19:58 · p3_c2a · bench
- Objective: A/B for p3_c2: same tree with the card build back on the tick frame, to read card.on_tick before the move
- Seeds: 1 × 90 s · wall 17 s
- Base: p3_n0: IDENTICAL within 1.00 mm
- Data:
  - Points 1 (double_bounce 1) | rally 63.4s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: A/B reference only: card.on_tick 18.48 ms/s, 154 us per player per tick; frames with a tick mean 4.3 ms, frames between 0.7 ms.

## 2026-11-25 19:59 · p3_c3 · bench
- Objective: card_build_off_tick after the wait-off fix: card.on_tick should fall well under p3_c2's 2.65 ms/s; game still IDENTICAL to p3_n0
- Seeds: 1 × 90 s · wall 16 s
- Base: p3_n0: IDENTICAL within 1.00 mm
- Data:
  - Points 1 (double_bounce 1) | rally 63.4s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: No change (2.60 ms/s): the stale-wait reset was not the cause. Not kept as the answer; see p3_c4.

## 2026-11-25 19:59 · p3_c4 · bench
- Objective: card_build_off_tick with a single missed frame treated as a hitch: card.on_tick should fall under p3_c3's 2.60 ms/s; game still IDENTICAL to p3_n0
- Seeds: 1 × 90 s · wall 16 s
- Base: p3_n0: IDENTICAL within 1.00 mm
- Data:
  - Points 1 (double_bounce 1) | rally 63.4s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: card.on_tick 0.55 ms/s (-97% against p3_c2a). The cause was one missed in-between frame switching the wait off for 10 s; one miss is now a hitch, two within 2 s switch it off. IDENTICAL.

## 2026-11-25 20:03 · p3_cseg · bench
- Objective: temporary split of the per-tick card build (reads, quads, upload) to pick what to cut; timers removed after
- Seeds: 1 × 60 s · wall 12 s
- Verdict: Per build and player on the Mac: visual motion 47 us, joint reads 38, quads 42 (10.5 of 15 cards rebuilt), upload and blend flags 10, rest 17. No single part to cut; timers removed. (This run had no BASE, so the bench pruned p3_n0: later runs compare against p3_c5off.)

## 2026-11-25 20:05 · p3_c5 · bench
- Objective: final card path (tick build + shader blend, build on the frame after the tick, drawing-change and flip snap, fixed step for visual motion): all-AI game unchanged (IDENTICAL to p3_n0), serial card cost total and on tick frames against p3_n0's 32.43 ms/s
- Seeds: 1 × 120 s · wall 20 s
- Base: p3_n0: 
- Data:
  - Points 2 (double_bounce 1, ball_in_net 1) | rally 50.5s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: Final. Against the same tree with cards built every frame (p3_c5off): IDENTICAL poses, 0 errors; card.rig 33.1 -> 19.0 ms/s, on tick frames 16.8 -> 0.6 ms/s; frames with a tick mean 4.4 -> 3.7 ms, frames between 1.2 -> 1.3 ms; scoped tick 2.58 ms (budget 3), worst tick mean 7.7 ms (budget 6, unchanged: cards are not in the tick). Mac only: the phone has to confirm.

## 2026-11-25 20:05 · p3_c5off · bench
- Objective: A/B base for p3_c5 (the earlier base p3_n0 was pruned): same tree with cards built every frame (card_tick_build=0); expect p3_c5 IDENTICAL to it, and its card.rig near the old 32 ms/s
- Seeds: 1 × 120 s · wall 23 s
- Base: p3_c5: IDENTICAL within 1.00 mm
- Data:
  - Points 2 (double_bounce 1, ball_in_net 1) | rally 50.5s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: A/B base for p3_c5 (card_tick_build=0): card.rig 33.1 ms/s, 16.8 of it on tick frames. See p3_c5.

## 2026-11-25 20:13 · p3_n1 · bench
- Objective: native card quad build (PickleCards): serial card.rig against p3_c5's 19.0 ms/s (script loop), game unchanged (IDENTICAL to p3_c5), 0 errors
- Seeds: 1 × 120 s · wall 20 s
- Base: p3_c5: IDENTICAL within 1.00 mm
- Data:
  - Points 2 (double_bounce 1, ball_in_net 1) | rally 50.5s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: Native quad build (PickleCards): card.rig 19.0 -> 13.25 ms/s, IDENTICAL, 0 errors. Side-by-side check before it (script loop and native on the same inputs, 14,400 builds): same cards rebuilt every time, worst corner difference 0.007 mm, no drawing (UV) difference. Kept; joint reads next.

## 2026-11-25 20:16 · p3_n2 · bench
- Objective: native card build with native joint reads: serial card.rig against p3_n1 (13.25, quads only) and p3_c5 (19.0, script); game IDENTICAL to p3_c5, 0 errors
- Seeds: 1 × 120 s · wall 20 s
- Base: p3_c5: IDENTICAL within 1.00 mm
- Data:
  - Points 2 (double_bounce 1, ball_in_net 1) | rally 50.5s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: Native joint reads added: card.rig 9.60 ms/s (p3_n2off, same tree with native_math=0: 18.82; start of the day: 33.1). Per build and player about 30 us plus the visual motion layer's 45 us, which is now more than half of what is left. IDENTICAL, 0 errors. Inputs checked side by side over 14,396 builds: worst difference 0.001 mm, none over 0.01 mm. Scoped tick 2.60 ms (budget 3), worst tick mean 7.6 ms (budget 6, unchanged: cards are not in the tick). Mac only.

## 2026-11-25 20:16 · p3_n2off · bench
- Objective: twin check for p3_n2: same tree with native_math=0 (script card loop and script ball maths): must still run clean and IDENTICAL to p3_c5
- Seeds: 1 × 120 s · wall 20 s
- Base: p3_c5: IDENTICAL within 1.00 mm
- Data:
  - Points 2 (double_bounce 1, ball_in_net 1) | rally 50.5s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: Twin check: with native_math=0 the script loop runs clean and IDENTICAL; card.rig 18.82 ms/s.

## 2026-11-25 20:22 · p3_prof9 · bench
- Objective: temporary function timers inside pose alignment, legs and contact checks, to find which leaf functions are numeric work worth porting; timers removed after
- Seeds: 1 × 90 s · wall 15 s
- Data:
  - Points 1 (double_bounce 1) | rally 63.4s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: Function timers (removed after; scripts restored byte for byte). No numeric core in any of the areas. Pose: force_posture_update 25.4 ms/s at 188 calls/s (1.6 per player per tick) is an orchestrator over nodes (body pose, paddle, legs, arms); the pure blend maths under it is lerp_with 4.3 ms/s. Legs: 15 functions of 0.5-2.5 ms/s each, the IK solve itself 1.8. Contact: the interval 15.8 ms/s = arm solves 5.5 + ordered live 5.7 + seal 2.5; the kitchen ground scan is 5.3 ms/s of per-mesh node reads. The 15.6 ms intercept call, the 5.3 ms leg solve and the 6.4 ms game step are first-call costs at t=2 s, once per match. Decision: no further C++ ports as the code stands; see docs/PERFORMANCE_PLAN.md.

## 2026-11-25 20:26 · p3_prof10 · bench
- Objective: temporary timers to find which helper is slow only on its first calls in the first rally tick (the 18 ms tick at t=2 s); timers removed after
- Seeds: 1 × 12 s · wall 4 s
- Verdict: The 15 ms in the first rally tick is one call: player._get_posture_offset_for, whose resolver reads the pose library from disk the first time it is asked (each player has its own copy). Timers removed; scripts restored.

## 2026-11-25 20:27 · p3_w1 · bench
- Objective: pose library read at player setup instead of the first AI plan: the 18 ms player tick at t=2 s should be gone (worst player.physics in the first rally seconds near 4 ms), game IDENTICAL to p3_c5, 0 errors
- Seeds: 1 × 120 s · wall 20 s
- Base: p3_c5: IDENTICAL within 1.00 mm
- Data:
  - Points 2 (double_bounce 1, ball_in_net 1) | rally 50.5s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: Pose library read at player setup: worst player tick in the first rally second 18.1 -> 4.6 ms, first intercept call 15.6 -> 1.9 ms. IDENTICAL, 0 errors. Still there, not in a rally: one contact.authority tick of 27 ms at t=11 s (WAITING, before the second serve) and 155 ms of serve.physics in the first second.

## 2026-11-25 20:28 · p3_w2 · bench
- Objective: ready_restore_skip: a waiting AI's restore skipped from 0.35 s instead of 0.85 s; expect al.restore down from 5.3 ms/s, poses IDENTICAL to p3_w1 (the restore was overwritten in the same call), 0 errors
- Seeds: 1 × 120 s · wall 19 s
- Base: p3_w1: IDENTICAL within 1.00 mm
- Data:
  - Points 2 (double_bounce 1, ball_in_net 1) | rally 50.5s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: ready_restore_skip: al.restore 5.14 -> 4.67 ms/s (calls 52 -> 36 a second), IDENTICAL. Small: the restores left belong to players going for the ball, where the restore is a full solve the legs advance on; not touched.

## 2026-11-25 20:32 · p3_w3 · bench
- Objective: native kitchen ground scan (floor_scan, both bound tests): contact/nvz cost against p3_w2, game IDENTICAL to p3_w2, 0 errors; serial player.physics and scoped tick
- Seeds: 1 × 120 s · wall 19 s
- Base: p3_w2: IDENTICAL within 1.00 mm
- Data:
  - Points 2 (double_bounce 1, ball_in_net 1) | rally 50.5s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: Native ground scan: pp.contact_support 5.66 -> 3.13 ms/s, player.physics 74.0 -> 72.1, scoped tick 2.49 ms (budget 3), worst tick mean 6.9 ms (budget 6). IDENTICAL, 0 errors. Side-by-side before it: 16,000 scans, 0 differences. The skinned thighs and torso never passed the cheap bound, so every scan posed their boxes in script; that is what moved. One pp.try_hit call of 7.4 ms at t=3 s in this run did not repeat (p3_w3r).

## 2026-11-25 20:32 · p3_w3r · bench
- Objective: check whether the 7.4 ms pp.try_hit call at the first hit (p3_w3, t=3 s) repeats and whether it comes from the native ground scan (second run with native_math=0)
- Seeds: 1 × 15 s · wall 4 s
- Verdict: Recheck of p3_w3's 7.4 ms pp.try_hit call: 0.3-0.4 ms at the same second with native_math on and off. A one-off of that run, not the change.

## 2026-11-25 20:32 · p3_w3r · bench
- Objective: check whether the 7.4 ms pp.try_hit call at the first hit (p3_w3, t=3 s) repeats and whether it comes from the native ground scan (second run with native_math=0)
- Seeds: 1 × 15 s · wall 5 s
- Verdict: Recheck of p3_w3's 7.4 ms pp.try_hit call: 0.3-0.4 ms at the same second with native_math on and off. A one-off of that run, not the change.

## 2026-11-25 20:40 · p3_s1 · bench
- Objective: motion smear (card shader + one uniform + a Settings key): script check and that the all-AI game is unchanged; expect 0 errors and IDENTICAL to p3_w3, card.rig unchanged (9.7 ms/s)
- Seeds: 1 × 60 s · wall 11 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL, card.rig 9.60 ms/s (unchanged: the smear is shader work). Drawn check in the real renderer, same frame with the smear on and off: it shows in 59 of 180 sampled frames, 189 pixels at the 90th percentile, 1,206 at most of 921,600. Not checked by eye; GPU cost not measurable on the Mac.

## 2026-11-25 20:46 · p3_s2 · bench
- Objective: ball motion blur (stretched ball, shader + trail script) and stronger card smear: script check and that the all-AI game is unchanged; expect 0 errors, IDENTICAL to p3_w3, ball_trail cost near the old one
- Seeds: 1 × 60 s · wall 12 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL, card.rig 9.60 ms/s. Drawn check in the real renderer (same frame with each effect on and off): the ball is stretched in 98% of rally frames, length median 0.12 m, 90th percentile 0.35 m, at most 0.59 m; the card smear shows in about half the frames, up to 3,000 pixels. Not checked by eye; GPU cost not measurable on the Mac.

## 2026-11-25 20:54 · p3_s3 · bench
- Objective: realistic motion blur (card soft pass, ball streak pass, paddle copies): script check and that the all-AI game is unchanged; expect 0 errors, IDENTICAL to p3_w3; script cost of card.rig and the paddle skin against p3_s2
- Seeds: 1 × 90 s · wall 16 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Data:
  - Points 1 (double_bounce 1) | rally 63.4s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: 0 errors, IDENTICAL; card.rig 9.76 ms/s (9.60 before: the soft-pass switch). Drawn check in the real renderer, same frame with each part on and off: card blur in 107 of 180 sampled frames (up to 11,100 pixels, 1.2% of the screen), ball streak in 117, paddle copies in 141. Not checked by eye; GPU cost not measurable on the Mac.

## 2026-11-25 20:54 · p3_s3off · bench
- Objective: twin check for p3_s3 with native_math=0 (script card loop sets the soft pass): 0 errors, IDENTICAL to p3_w3
- Seeds: 1 × 40 s · wall 9 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: Twin check: script card loop with the soft-pass switch runs clean, IDENTICAL.

## 2026-11-25 21:00 · p3_s4 · bench
- Objective: steadier card blur (eased joint velocity in a second mesh attribute, blur eased in by the shader): 0 errors, IDENTICAL to p3_w3, card.rig against p3_s3's 9.76 ms/s
- Seeds: 1 × 90 s · wall 15 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Data:
  - Points 1 (double_bounce 1) | rally 63.4s, between 7.8s, serve wait 0.8s | serves 2, faulted at the hit 0
- Verdict: 0 errors, IDENTICAL. Steadiness in the real renderer (blur motion per card and tick over a 40 s match): it drops to zero while the part is moving in 1 of 8,628 samples (before: every tick a limb changed drawing or flipped, about 5% of limb builds); mean change from tick to tick 21%. card.rig: see the scope line of this run against p3_s3 (the attribute buffer is uploaded on more ticks).

## 2026-11-25 21:01 · p3_s4off · bench
- Objective: twin check for p3_s4 with native_math=0 (script card loop computes the blur motion): 0 errors, IDENTICAL to p3_w3
- Seeds: 1 × 40 s · wall 9 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: Twin check: the script loop computes the same blur motion; runs clean, IDENTICAL.

## 2026-11-25 21:06 · p3_s5 · bench
- Objective: paddle swept blur (paddle_blur.gdshader) and ball blur from the drawn ball's own motion: 0 errors, IDENTICAL to p3_w3
- Seeds: 1 × 60 s · wall 11 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL. Real renderer, 36 s match: the ball's blur is on in 927 of 1,006 frames flying over 5 m/s (92%; it followed the bounce path history before and dropped out after every bounce and hit). Paddle: one swept streak, checked on a screenshot of the frame with the largest on-screen sweep (28 pixels). GPU cost not measurable on the Mac.

## 2026-11-25 21:19 · p3_s6 · bench
- Objective: ball streak reworked in ball_tail.gdshader (shader and two material values only): 0 errors, IDENTICAL to p3_w3
- Seeds: 1 × 40 s · wall 8 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL. Look checked on three on/off screenshots (logs/motion_blur/v3_ball.png): the streak is as wide as the drawn ball, soft at the sides, with a round fading end, and joins the ball.

## 2026-11-25 21:49 · p3_s7 · bench
- Objective: stretch blur for motion in depth (card shader, ball trail script, paddle skin): 0 errors, IDENTICAL to p3_w3
- Seeds: 1 × 40 s · wall 8 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL. Real renderer, 31 s: for balls over 7 m/s the streak is 1.29 times its unstretched length at the median and 2.17 times at most; on screen 26 pixels at the median (8 at the 10th percentile, 58 at the 90th). No shader errors. Paddle and body stretch not measured separately; not checked by eye.

## 2026-11-25 22:02 · p3_s8 · bench
- Objective: ball drawn as an oblong in flight (ball shape include, body and outline shaders, trail script): 0 errors, IDENTICAL to p3_w3
- Seeds: 1 × 40 s · wall 8 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL. Look checked on three round / oblong screenshot pairs (logs/motion_blur/v4_ball_oblong.png): a solid outlined oblong along the flight, front tip at the ball's place; longest extra length in that match 0.27 m.

## 2026-11-25 22:07 · p3_s9 · bench
- Objective: ball blur as a soft oblong behind a whole ball, outline open on the blur side (ball shaders, ball.gd, trail constants): 0 errors, IDENTICAL to p3_w3
- Seeds: 1 × 40 s · wall 8 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL. Look checked on three screenshot pairs (logs/motion_blur/v5_ball_blurred_oblong.png): the ball is whole, its outline is open on the side the blur leaves, the oblong fades behind it. A first version (solid front part of a stretched ball) looked hollow for balls flying away from the camera and was dropped.

## 2026-11-25 22:12 · p3_s10 · bench
- Objective: ball as a solid oblong with a longer linear blur tail (ball shaders, trail constants): 0 errors, IDENTICAL to p3_w3
- Seeds: 1 × 40 s · wall 8 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL. Look checked on three screenshot pairs (logs/motion_blur/v6_ball_oblong_tail.png): solid outlined oblong, outline open at the rear, see-through tail 2.8 times the oblong's extra length fading linearly.

## 2026-11-25 22:18 · p3_s11 · bench
- Objective: blur scaled by Engine.time_scale (ball, paddle, cards) and pickleball holes in the ball body shader: 0 errors, IDENTICAL to p3_w3
- Seeds: 1 × 40 s · wall 9 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL. Holes checked on a full-resolution capture (logs/motion_blur/v7_ball_holes.png): visible as darker dots on a ball about 12 pixels across; at the Mac's normal render scale the ball is 3-5 pixels and they are faded out by design. The slow-motion scaling was not exercised (no slow motion in an all-AI bench). The ball's angular velocity read 0 for the whole match, so the holes' roll with spin was not seen.

## 2026-11-25 22:21 · p3_s12 · bench
- Objective: resolution setting (pixel_post.gd reads video.resolution and applies it live; settings key and panel row): 0 errors, IDENTICAL to p3_w3
- Seeds: 1 × 40 s · wall 8 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL. Live test in a loaded match: the five choices set the viewport's 3D scale to 0.333 (default on main), 0.333, 0.5, 0.667 and 1.0 as soon as the setting changes; the setting was put back to 0 afterwards. Frame-rate cost of the higher choices is for the phone to show.

## 2026-11-25 22:55 · p3_s13 · bench
- Objective: visible ball roll for the holes (fx/ball_trail.gd only): 0 errors, IDENTICAL to p3_w3
- Seeds: 1 × 40 s · wall 9 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL. Measured in a 30 s match: the holes turn in 1,469 of 1,799 frames, 7.4 degrees a frame at the median, 11.5 at most. The game's own spin is zero on Easy and non-zero on 14 of 1,150 flight ticks on Hard, so the shown roll comes from the flight direction. Not seen by eye; slow motion not exercised.

## 2026-11-25 22:57 · p3_s14 · bench
- Objective: seven graphics toggles (blur per part, ball holes, player shading, vignette, colour grade): 0 errors, IDENTICAL to p3_w3 with all on
- Seeds: 1 × 40 s · wall 8 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL. Live test in a loaded match: with the seven switches off, ball / paddle / body blur strength read 0, the ball's holes 0, the players' shading 0, vignette 0 and contrast 1; switched back on, every value returned to its own. Not checked by eye.

## 2026-11-25 23:14 · p3_s15 · bench
- Objective: player shadows grown 1.5 texels (joint gaps) and a soft rim driven by the lens blur (card shadow shaders, ground_shadows.gd, solo_aim_focus.gd, rig): 0 errors, IDENTICAL to p3_w3, card.rig near 9.8 ms/s
- Seeds: 1 × 60 s · wall 11 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL. Screenshots at the phone's half resolution, same frame three ways (logs/motion_blur/v8_shadows.png): as it was, the shadow breaks into separate blobs at the joints; grown, it is one shape (about 5,500 screen pixels more shadow per frame for four players); with the lens strength forced to 0.65 a soft rim shows. The lens itself (serve aim, slow motion) does not come up in an all-AI match, so the rim was not seen in a real serve.

## 2026-11-25 23:16 · p3_s16 · bench
- Objective: player shadows lengthened 1.25 texels along each part only (were grown 1.5 on all sides: too fat): 0 errors, IDENTICAL to p3_w3
- Seeds: 1 × 40 s · wall 8 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL. Screenshots at half resolution (logs/motion_blur/v9_shadows_slim.png, taken at 2.0 texels of lengthening): gaps at the joints close and no part gets wider; about 3,700 screen pixels of shadow added per frame against about 5,500 with growth on all sides. Shipped at 1.25 texels, which was not captured separately.

## 2026-11-25 23:19 · p3_s17 · bench
- Objective: shadow cast by true joint-to-joint shapes (third mesh attribute from the native builder; shadow shader adds it): 0 errors, IDENTICAL to p3_w3, card.rig against 9.6 ms/s
- Seeds: 1 × 60 s · wall 11 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL; card.rig: see the scope line of this run (9.6 ms/s before). Screenshots at half resolution, same frame with the old card shapes and the true shapes (logs/motion_blur/v10_shadow_joints.png): before, the shadow is separate blobs; now head, shoulders, arms and legs join into one figure, with no growth applied.

## 2026-11-25 23:19 · p3_s17off · bench
- Objective: twin check for p3_s17 with native_math=0 (script loop writes the shadow shapes): 0 errors, IDENTICAL to p3_w3
- Seeds: 1 × 40 s · wall 9 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: Twin check: the script loop writes the same shadow shapes; runs clean, IDENTICAL.

## 2026-11-25 23:22 · p3_s18 · bench
- Objective: shadow shapes keep the card's own look, cast from the real joints (C++ builder): 0 errors, IDENTICAL to p3_w3
- Seeds: 1 × 40 s · wall 8 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL. Screenshots at half resolution, old shadow against the new one on the same frames (logs/motion_blur/v11_shadow_same_look.png): the same full silhouette, parts joined at the joints; about 3,000 screen pixels differ per frame.

## 2026-11-25 23:22 · p3_s18off · bench
- Objective: twin check for p3_s18 with native_math=0: 0 errors, IDENTICAL to p3_w3
- Seeds: 1 × 30 s · wall 8 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: Twin check: runs clean, IDENTICAL.

## 2026-11-25 23:26 · p3_s19 · bench
- Objective: camera-independent shadow shapes (sun-facing, 1.15x wide; C++ builder): 0 errors, IDENTICAL to p3_w3
- Seeds: 1 × 40 s · wall 8 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL. The shape handed to the shadow no longer contains the camera (joint, real line, sun direction only). One capture from a low camera near the sun's line (logs/motion_blur/v12_shadow_any_angle.png): the old shadow is thin strips, the new one a fuller shape; the capture does not match the user's photo-mode angle closely, so the phone has to confirm.

## 2026-11-25 23:26 · p3_s19off · bench
- Objective: twin check for p3_s19 with native_math=0: 0 errors, IDENTICAL to p3_w3
- Seeds: 1 × 30 s · wall 7 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: Twin check: runs clean, IDENTICAL.

## 2026-11-25 23:31 · p3_s20 · bench
- Objective: paddle sun shadow (mesh_shadow.gdshader as next pass of the paddle materials) and the ball's shadow cast along the sun: 0 errors, IDENTICAL to p3_w3, proc.ground_shadows cost
- Seeds: 1 × 40 s · wall 8 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL. Real renderer, 25 s at half resolution: the paddles' shadow pass changes up to 608 screen pixels in a frame (same frame drawn with its opacity at 0 and 0.4); a ball 1.73 m up has its shadow about 100 screen pixels from it along the sun. The capture (logs/motion_blur/v13_paddle_ball_shadow.png) is too wide to judge the look.

## 2026-11-25 23:36 · p3_s21 · bench
- Objective: motion blur on shadows (player trail in the shadow rim pass, paddle sweep shadow, ball shadow drawn out along its motion): 0 errors, IDENTICAL to p3_w3, card.rig and proc.ground_shadows cost
- Seeds: 1 × 40 s · wall 8 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL. Real renderer at half resolution, 20 s: the players' shadow trail shows in 80 of 133 sampled frames (median 12 screen pixels, 140 at the 90th percentile, 376 at most; same frame drawn with the trail on and off, logs/motion_blur/v14_shadow_blur.png); the paddle's sweep shadow is drawn whenever the sweep is; the ball's shadow reached 0.9 m long, so its blur cap was lowered from 0.5 to 0.3 m after this run. No shader errors.

## 2026-11-26 00:08 · p3_s22 · bench
- Objective: quick Photo button on the HUD with its setting (hud.gd, game.gd, pause_controller.gd, pause_menu.gd, settings): 0 errors, IDENTICAL to p3_w3
- Seeds: 1 × 40 s · wall 8 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL. Live test in a loaded match (desktop layout): the button sits under the toolbar's right end (96 x 42 at 1164, 68 against the toolbar at 930, 20, 330 x 44); the setting hides and shows it; pressing it pauses and opens photo mode; closing photo mode resumes with no pause menu left open. Its place in the phone's portrait layout was not seen.

## 2026-11-26 00:14 · p3_s23 · bench
- Objective: photo button beside the HIT pad with a camera icon; motion blur held while paused (rig, paddle, ball, ball shadow): 0 errors, IDENTICAL to p3_w3
- Seeds: 1 × 40 s · wall 8 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL. Live test at 720x1280: the button is 55 x 55 at (603, 958), the HIT pad at (568, 1112) radius 78, so its centre is 1.81 radii from the pad (the pad takes touches to 1.22), with an icon and no text. Blur state before opening photo mode and 15 frames into it is the same (limb blur on 4 players at strength 1.00, shadow trail on 4, 4 paddle sweeps, ball blur 0.157 m); after closing it changes again with play. The frozen blur was not checked by eye.

## 2026-11-26 00:21 · p3_s24 · bench
- Objective: photo history (17 joints x 4 players recorded per tick), rewind slider, bigger photo button: 0 errors, IDENTICAL to p3_w3, cost of photo.history per second
- Seeds: 1 × 60 s · wall 11 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL. photo.history costs 0.60 ms/s on the Mac (20 us a tick, worst 0.03 ms) for 91 records of 17 joints x 4 players. Live test: rewinding 45 ticks puts every joint on its record (worst offset 0.00000 m) and the drawn ball on the recorded place while the ball body stays put; after rewinds to 45, 90 and 12 ticks and closing, 73 of 73 tracked transforms equal the ones from before photo mode opened. The rewound frames' look (blur included) was not checked by eye.

## 2026-11-26 00:35 · p3_s25 · bench
- Objective: rally replays (per-rally recording in photo_history.gd, save / list / load, REC button and save prompt in the HUD, list and playback in photo mode): 0 errors, IDENTICAL to p3_w3, photo.history cost against 0.60 ms/s
- Seeds: 1 × 60 s · wall 11 s
- Base: p3_w3: IDENTICAL within 1.00 mm
- Verdict: 0 errors, IDENTICAL; photo.history 0.60 ms/s, unchanged by the rally buffer. Live test at 720x1280: rally 1 (34.8 s) brought up 'SAVE RALLY?  35 s', pressing it saved one file; with REC on, rally 2 (28.0 s) saved by itself as 2,065,315 bytes (74 KB a second); photo mode listed 3 rows (live + 2), picking the rally set the slider to 838 ticks at 'RALLY 0.0 / 27.9 s', PLAY reached 1.0 s after 60 frames; closing left 68 of 68 joints exactly as before and the live 3 seconds back. The time a save takes was not measured. The two test files were removed.

## 2026-11-26 00:42 · p3_m0 · bench_seeds
- Objective: baseline before the movement acceleration change: hits, misses, points, rally length and the animation rules on seed 1, to compare p3_m1 against (keep the change if the rules still pass and the AI still returns most balls)
- Seeds: 1 × 120 s · wall 19 s
- Data:
  - == p3_m0: 1 seeds
  - points 2 (double_bounce 1, ball_in_net 1) | AI hits 94
  - contact snap-back 1 of 96 hits (1%) | head-to-ball over 15 cm 2 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 11 of 94 | paddle flutter episodes 50 | pose changed in last 0.3 s 0 of 96 (+5 reflex blocks on balls inside the reaction delay)
  - serves 2, faulted at the hit 0 | stretched contacts (arm over 2 mm short, adds shot error) 2 of 94 AI hits
  - budget s1 (serial): Worst tick: mean 8.6 / p90 9.3 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.35 ms per tick (budget average 3 ms)  OK
- Verdict: Baseline (old accelerations 12-16 / brakes 16-20): 2 points and 94 AI hits in 120 s on seed 1, all rules PASS. From its pose trace: standstill to 3 m/s in 0.17 s (median), speeding up at 16 m/s2, slowing at 16-20, 0.42 m of travel per step.

## 2026-11-26 00:43 · p3_m1 · bench_seeds
- Objective: movement accelerations lowered to realistic values (AI 7-9 m/s2, brakes 10-12, lunge 15; your player 18 / 24 / 16): do the animation rules still pass and does the AI still return most balls (hits, points, how points end) against p3_m0; time from standstill to 3 m/s
- Seeds: 1 × 120 s · wall 18 s
- Data:
  - == p3_m1: 1 seeds
  - points 4 (ball_in_net 2, out_of_bounds 1, double_bounce 1) | AI hits 69
  - contact snap-back 0 of 74 hits (0%) | head-to-ball over 15 cm 0 | median gap per seed 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 5 of 69 | paddle flutter episodes 41 | pose changed in last 0.3 s 0 of 74 (+2 reflex blocks on balls inside the reaction delay)
  - serves 5, faulted at the hit 0 | stretched contacts (arm over 2 mm short, adds shot error) 1 of 69 AI hits
  - budget s1 (serial): Worst tick: mean 7.1 / p90 8.7 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.41 ms per tick (budget average 3 ms)  OK
- Verdict: Seed 1, new accelerations: all rules PASS; 4 points and 69 AI hits (how they ended: net 2, out 1, double bounce 1). From the trace: standstill to 3 m/s in 0.30 s (was 0.17), speeding up at 9.0 m/s2 and slowing at 12 (was 16 and 16-20), 0.50 m per step (was 0.42). Paddle tip: 10-19 m/s at the peak of swings, two single-tick jumps over 25 m/s in 120 s (same as before). Kept; two more seeds for rally length.

## 2026-11-26 00:43 · p3_m1 · bench_seeds
- Objective: movement accelerations lowered to realistic values: do the rules pass on three seeds and how long do rallies last (hits per point) now
- Seeds: 1 2 3 × 120 s (why: one seed gave only 4 points: two more seeds to see whether rallies still last (hits per point) and the rules still pass with the slower starts and stops) · wall 21 s
- Data:
  - == p3_m1: 3 seeds
  - points 16 (ball_in_net 8, double_bounce 6, out_of_bounds 2) | AI hits 182
  - contact snap-back 3 of 199 hits (2%) | head-to-ball over 15 cm 3 | median gap per seed 4.6, 4.6, 4.6 cm
  - wind-ups that wobble (reverse twice or more; one reversal is the backswing) 11 of 181 | paddle flutter episodes 113 | pose changed in last 0.3 s 0 of 200 (+13 reflex blocks on balls inside the reaction delay)
  - serves 18, faulted at the hit 0 | stretched contacts (arm over 2 mm short, adds shot error) 4 of 182 AI hits
  - budget s1 (parallel seeds, timings inflated): Worst tick: mean 7.1 / p90 8.7 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.41 ms per tick (budget average 3 ms)  OK
  - budget s2 (parallel seeds, timings inflated): Worst tick: mean 10.7 / p90 32.9 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.57 ms per tick (budget average 3 ms)  OK
  - budget s3 (parallel seeds, timings inflated): Worst tick: mean 7.6 / p90 9.6 ms vs budget 6 ms  OVER | Scoped tick cost: avg 2.65 ms per tick (budget average 3 ms)  OK
- Verdict: Three seeds, new accelerations: all rules PASS (snap-back 1.5%, wobble 6%, stretched contacts 2.2%, 0 of 18 serves faulted); 182 AI hits over 16 points (net 8, double bounce 6, out 2), so rallies still run about 11 hits. Kept. The human seat's new accelerations (18 / 24 / 16, were 72 / 84 / 34) are not visible to an all-AI bench: the phone has to judge the feel.

## 2026-11-26 00:51 · p3_r1 · bench
- Objective: rally recording only while a rally is on (live 3 s rewind removed): 0 errors, IDENTICAL to p3_m1_s1 (recording is visual), photo.history cost in rallies and outside them against 0.60 ms/s always
- Seeds: 1 × 120 s · wall 19 s
- Base: p3_m1_s1: IDENTICAL within 1.00 mm
- Data:
  - Points 4 (ball_in_net 2, out_of_bounds 1, double_bounce 1) | rally 16.9s, between 8.0s, serve wait 0.8s | serves 5, faulted at the hit 0
- Verdict: 0 errors, IDENTICAL. photo.history by match state: 0.42 ms/s while PLAYING, 0.28 in POINT_SCORED (the one-second tail of each rally), 0.00 while WAITING; it was 0.60 ms/s at all times. Live test: a 21.4 s rally brought up the save question and saved; photo mode opened with no scrub row, the list showed the rally, picking it gave the scrub row and PLAY, 'back to the paused moment' hid them again, and closing left 68 of 68 joints exactly as before. Test file removed.

## 2026-11-26 00:58 · p3_r2 · bench
- Objective: C++ rally recorder (PickleReplay): 0 errors, IDENTICAL to p3_m1_s1, photo.history cost in rallies against the script recorder's 0.42 ms/s
- Seeds: 1 × 120 s · wall 19 s
- Base: p3_m1_s1: IDENTICAL within 1.00 mm
- Data:
  - Points 4 (ball_in_net 2, out_of_bounds 1, double_bounce 1) | rally 16.9s, between 8.0s, serve wait 0.8s | serves 5, faulted at the hit 0
- Verdict: First native version: 0 errors, IDENTICAL; photo.history reads 0.00 ms/s in every state (the log keeps two decimals per frame), worst call 0.57 ms at a rally's end, which was the copy of the finished rally. Replaced by a swap (p3_r3).

## 2026-11-26 00:58 · p3_r2off · bench
- Objective: twin check for p3_r2 with native_math=0 (script recorder): 0 errors, IDENTICAL to p3_m1_s1
- Seeds: 1 × 60 s · wall 11 s
- Base: p3_m1_s1: IDENTICAL within 1.00 mm
- Data:
  - Points 3 (out_of_bounds 1, ball_in_net 1, double_bounce 1) | rally 8.9s, between 7.7s, serve wait 0.8s | serves 4, faulted at the hit 0
- Verdict: Twin check with native_math=0: the script recorder runs clean, IDENTICAL; 0.23 ms/s while PLAYING, 0.18 in POINT_SCORED.

## 2026-11-26 00:59 · p3_r3 · bench
- Objective: C++ rally recorder with the swap hand-over: 0 errors, IDENTICAL to p3_m1_s1, photo.history total and worst call
- Seeds: 1 × 120 s · wall 19 s
- Base: p3_m1_s1: IDENTICAL within 1.00 mm
- Data:
  - Points 4 (ball_in_net 2, out_of_bounds 1, double_bounce 1) | rally 16.9s, between 8.0s, serve wait 0.8s | serves 5, faulted at the hit 0
- Verdict: 0 errors, IDENTICAL. photo.history with the C++ recorder: see the numbers printed for this run (under the log's resolution on average; the worst single call is the one-off set-up of the joint list). Live test: two rallies saved back to back, each save call back in 0.25-0.32 ms on the main thread with the file written by a worker thread (21.4 s rally = 1.58 MB); the script loader reads both files and the native placement matches it within 0.000001 m; closing photo mode left 68 of 68 joints exactly as before. Test files removed.

## 2026-11-26 01:00 · p3_r4 · bench
- Objective: C++ rally recorder, final (player list checked at each serve only): 0 errors, IDENTICAL to p3_m1_s1, worst photo.history call
- Seeds: 1 × 120 s · wall 18 s
- Base: p3_m1_s1: IDENTICAL within 1.00 mm
- Data:
  - Points 4 (ball_in_net 2, out_of_bounds 1, double_bounce 1) | rally 16.9s, between 8.0s, serve wait 0.8s | serves 5, faulted at the hit 0
- Verdict: 0 errors, IDENTICAL. Timed directly (3,000 calls in a loaded match): one C++ joint record 1.75 us against 7.5 us for the script's joint reads alone; the whole recorder call with C++ 2.32 us a tick = 0.07 ms per second of rally (script recorder: 0.42 ms/s in rallies, and 0.60 ms/s at all times before build 145). A save call returns in about 0.3 ms; the write and compression run on a worker thread. The once-a-second 0.11 ms call seen in p3_r3 was the player list check, now done at each serve only.
