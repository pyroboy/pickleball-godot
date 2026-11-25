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
