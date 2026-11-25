extends RefCounted
## Gameplay v2 dials (docs/GAME_MECHANICS_PLAN.md). Constants, not settings.
## Ground rule: with a dial at 0 / false the bench gives IDENTICAL poses against the
## run before it. Every new roll uses its own stream (RuntimePolicy.seed_rng + the
## salt here), made once per incoming flight and kept by flight id.

## Contact difficulty (shot_execution_error envelope, 0..1) at or above which a net or
## out counts as FORCED, and below which no large miss is ever rolled.
const FORCED_LINE := 0.25

## Own random-stream salts (never the global RNG, never an existing stream).
const SALT_FLOAT := 0x6d01
const SALT_RISK := 0x6d02
const SALT_PATIENCE := 0x6d03
const SALT_MISS := 0x6d04

## ---- Change 1: shot quality carries over (step 2) ----
## Carry (0..1) = how hard the incoming ball was to play, from ball and movement facts
## only (shot_contact_quality.carry). The reply floats: vertical launch speed gains
## CARRY_FLOAT_VY * carry (m/s) and horizontal speed loses CARRY_SHORTEN * carry, so a
## rushed, low, fast-ball contact comes back higher and shorter. The error envelope
## widens by CARRY_ERROR_WEIGHT * carry (smaller part).
const CARRY_FLOAT_VY := 2.0
const CARRY_SHORTEN := 0.12
## Soft replies (under CARRY_HARD_SPEED m/s) instead go longer by CARRY_LENGTHEN * carry:
## a loose dink sails up into the receiver's volley zone, where it can be attacked.
const CARRY_LENGTHEN := 0.4
const CARRY_HARD_SPEED := 9.0
const CARRY_ERROR_WEIGHT := 0.12
## AI loose dinks: extra carry rolled once per flight, uniform 0..spread, by difficulty
## (Easy, Medium, Hard). Own stream SALT_FLOAT.
const AI_LOOSE_SPREAD := [0.8, 0.6, 0.5]

## ---- Change 4: rally pressure drives AI patience (step 4) ----
## Pressure counts soft shots in a row (point_ending.soft_run); any attack, drive or lob
## sets it back to 0. With PATIENCE_ON the kitchen AI may speed up a ball from
## net - 0.10 m once the run passes PATIENCE_START, chance rising to PATIENCE_BASE over
## PATIENCE_RAMP more soft shots, times the style's SPEED_UP weight. By difficulty
## (Easy, Medium, Hard). Hard used to wait longest (start 7, ramp 12, base 0.2): its chance
## stayed under 10% in a 300 s bench and it never sped up, so it now attacks early and often.
const PATIENCE_ON := true
const PATIENCE_START := [2, 4, 3]
const PATIENCE_RAMP := [6.0, 8.0, 5.0]
const PATIENCE_BASE := [0.45, 0.32, 0.6]
const PATIENCE_MAX := 0.6
## Lowest ball (m relative to the tape) a patience speed-up is tried from, by difficulty. Hard
## rolls it from a little below the net (bench 2026-11-23: 200 of 267 Hard rally contacts were
## more than 0.10 m below the tape, so the old limit left it almost nothing to attack).
const PATIENCE_MIN_EXCESS := [-0.10, -0.10, -0.25]
## Low speed-up: slower than a high-ball attack, so it can be countered. Aimed at the
## nearest opponent's body this share of the time (Easy rarely).
const LOW_SPEEDUP_CHARGE := [0.34, 0.44, 0.58]
const LOW_SPEEDUP_AT_BODY := [0.15, 0.35, 0.6]
## Firefight replies: a fast ball (>= 9 m/s) met at or above the net near the kitchen
## is countered (SPEED_UP) with this chance; below the tape it is blocked (RESET).
const COUNTER_ON := true
const COUNTER_CHANCE := [0.45, 0.65, 0.8]

## ---- Change 2: risk levels and more targets (step 5) ----
## Each AI shot is safe / normal / aggressive (own stream SALT_RISK, one roll per flight).
## Chances by difficulty (Easy, Medium, Hard), aggressive times the style's RISK_STYLE.
const RISK_ON := true
const RISK_AGGRESSIVE := [0.30, 0.22, 0.18]
const RISK_SAFE := [0.20, 0.28, 0.30]
const RISK_STYLE := [1.0, 1.6, 0.5, 0.9, 0.8]     # All-Rounder .. Lob Tactician
## Per level: soft-shot net margin (m), extra lane width (m), drive depth range (m),
## and the legal-landing box valid_launch checks (|x| max, depth max).
const RISK := {
	"safe": {"net": 0.30, "lane": -0.35, "deep": [4.5, 5.1], "x_max": 2.55, "z_max": 6.0},
	"normal": {"net": 0.20, "lane": 0.0, "deep": [4.7, 5.75], "x_max": 2.8, "z_max": 6.4},
	"aggressive": {"net": 0.16, "lane": 0.3, "deep": [5.5, 6.2], "x_max": 2.9, "z_max": 6.5},
}
## Through the middle: share of dinks / resets / drives / speed-ups aimed at the gap
## between the two opponents (needs both positions).
const MIDDLE_ON := false
const MIDDLE_SHARE := 0.30
## Mid-court: a drive / drop at the feet of an opponent caught between 3.0 and 5.5 m.
const FEET_ON := true
## Third-shot and baseline drives: share of deep (beyond 4.5 m) rally contacts driven.
const DRIVES_ON := true
const DRIVE_SHARE := [0.42, 0.46, 0.65]
const DRIVE_MIN_DEPTH := 3.6

## ---- Change 5: stamina rework (step 7) ----
## Recovery first: in-rally recovery standing still and the between-point refill
## become partial, so tiredness carries across points. Then the penalty: below
## STAMINA_PENALTY_AT, move / lunge speed (speed_factor, the only slowdown path) falls
## toward STAMINA_MIN_SPEED and power-shot error (drive, smash, speed-up) widens up to
## STAMINA_POWER_ERROR. Both scale by STAMINA_PENALTY_SCALE per difficulty (Easy light).
const STAMINA_ON := true
const STAMINA_RALLY_RECOVERY := 1.0       # per s standing in a rally (was 7)
## Movement cost per metre in a rally: MOVE_COST_WALK at 2 m/s or slower, rising to
## MOVE_COST_SPRINT at full speed (5.8 m/s). The player who gets run around tires.
const MOVE_COST_WALK := 0.3        # was 0.5
const MOVE_COST_SPRINT := 3.0      # was 1.5
## Between points the refill grows with what is missing: REST_RECOVERY + REST_DEFICIT x (100 - value)
## per s, so a fresh player gains ~4 per point and a tired one ~13: stamina settles near 50 at
## a normal spend, ~70 for a player who conserves, ~40 for one who drives everything (was a flat
## 1.3/s: ~10 per point, everyone sat near 90 and spending never mattered).
const STAMINA_REST_RECOVERY := 0.2        # per s between points (was 1.3 flat)
const STAMINA_REST_DEFICIT := 0.03
const STAMINA_HARD_COST := {"SMASH": 4.0, "SPEED_UP": 3.0, "DRIVE": 3.0, "GROUNDSTROKE": 3.0}   # was 10 / 8 / 8 / 7: the drain is footwork now
const STAMINA_PENALTY_AT := 50.0
const STAMINA_MIN_SPEED := 0.72 
const STAMINA_POWER_ERROR := 0.5
const STAMINA_PENALTY_SCALE := [0.75, 0.9, 1.0]

## ---- Change 7 / step 9: long-rally reward ----
## The team that wins a rally of LONG_RALLY shots or more gets a small refill.
const LONG_RALLY_REFILL_ON := true
const LONG_RALLY := 15
const LONG_RALLY_REFILL := 12.0

## ---- Change 3: occasional large misses (step 6) ----
## Rolled once per contact on the hitter's own stream (SALT_MISS), only when the contact
## difficulty is at or above FORCED_LINE (a visible cause: late, stretched, off-balance,
## rushed) or the hitter is tired. Chance grows from MISS_CHANCE_AT_LINE at the line to
## MISS_CHANCE_MAX at difficulty 1; a miss adds MISS_PITCH_DEG (net or long) and
## MISS_YAW_DEG (wide) on top of the normal error. "Perfect training" removes it.
const MISS_ON := true
const MISS_CHANCE_AT_LINE := 0.15
const MISS_CHANCE_MAX := 0.6
const MISS_TIRED_BONUS := 0.06            # extra chance at 0 stamina, from STAMINA_PENALTY_AT down
const MISS_PITCH_DEG := 10.0
const MISS_YAW_DEG := 6.0
const MISS_SPEED_FRACTION := 0.12
const MISS_DOWN_SHARE := 0.85             # share of large misses that go down (net)
## AI large-miss chance scale by difficulty (Easy, Medium, Hard). Hard bench 2026-11-23: 37 of
## 55 points ended in the net, 43 large misses in 1004 contacts (36 "rushed").
const MISS_AI_SCALE := [1.0, 1.0, 0.5]

## ---- Step 3: take the ball earlier (AI attack step 2) ----
## A rally ball that can be volleyed near the kitchen at or above the net tape scores
## better than letting it drop (seconds-equivalent bonus in the AI's contact choice),
## so a floated dink is met high, where the attack rule can use it.
const EARLY_VOLLEY_ON := false
const EARLY_VOLLEY_BONUS := 0.35
const EARLY_VOLLEY_BELOW := 0.05          # m under the tape that still counts

## ---- Change 8: specials (step 8) ----
## The Erne's own switch (MATCH_SPECIAL_ACTIONS also turns on the grounded reach).
const ERNE_ON := true
## Aggressive cross-court dinks go wide (lane 2.35-2.75 m): the play that creates Erne chances.
const WIDE_DINKS := true
const WIDE_DINK_LANE := Vector2(2.2, 2.5)
## AI Erne as an attack: when the flight allows one (the Erne's own geometry check:
## a wide volley beside the post), try it with this chance per flight, by difficulty.
const ERNE_CHANCE := [0.35, 0.55, 0.7]
const SALT_SPECIAL := 0x6d05
## Pop-up attack: a kitchen ball at least POPUP_MIN_EXCESS over the tape, within
## POPUP_REACH m, is attacked even when the hitter is moving or not yet balanced.
## Chance by difficulty at full height (reached POPUP_FULL m over the tape).
const POPUP_ATTACK_ON := true
const POPUP_MIN_EXCESS := [0.25, 0.12, 0.12]
const POPUP_FULL := 0.6
const POPUP_REACH := 1.2
const POPUP_ATTACK_PROB := [0.65, 0.82, 0.95]
## Attack pace on real pop-ups (charge, by difficulty): today's smash averaged 13 m/s
## and 95% of attacks came back as soft dinks. Low speed-ups keep LOW_SPEEDUP_CHARGE.
const ATTACK_CHARGE_ON := true
const SMASH_CHARGE := [0.85, 0.93, 1.0]
const SPEEDUP_CHARGE := [0.62, 0.72, 0.82]
## Pop-up attacks at the feet: lateral offset (x) and how far in front of them it lands (y).
const ATTACK_FEET_OFFSET := Vector2(0.5, 0.6)

## Kitchen guard: the AI does not volley a rally ball met more than KITCHEN_GUARD_REACH
## inside the kitchen plane (it lets it bounce), so pop-up volleys stop ending in
## momentum / kitchen-volley faults.
const KITCHEN_GUARD_ON := true
const KITCHEN_GUARD_REACH := -0.05

## ---- Player feel pass (docs/PLAYER_FEEL_PLAN.md) ----
## Habit read: each power shot in a row by the same team past the first raises the
## receiving AI's counter chance by this much (up to 3 steps) and braces its block (less float).
const HABIT_COUNTER_STEP := 0.12
const HABIT_BRACE_STEP := 0.15
## Pop-up attack also off the bounce (a dink that sits up waist-high in the kitchen).
const POPUP_OFF_BOUNCE := true
## Timing floats touch and power shots alike: carry += TIMING_FLOAT * timing (0 = perfect,
## 1 = 0.1 s off). A careless tap sits up.
const TIMING_FLOAT := 0.6
## Blocking a fast ball (12 m/s or more) met at or below the waist floats more.
const BLOCK_FLOAT := 0.45
## ... scaled by the blocker's stamina: a fresh blocker (at or above BLOCK_TIRED_AT) floats
## only BLOCK_FRESH_SHARE of it, the full amount at 0 stamina. A drive into a fresh player
## comes back fast (counter-block) or as a reset into the kitchen.
const BLOCK_FRESH_SHARE := 0.15
const BLOCK_TIRED_AT := 60.0
## Counter chance scales with the defender's stamina: x COUNTER_STAMINA_MIN at 0, x1 at 100.
const COUNTER_STAMINA_MIN := 0.5
## Float from a fast incoming ball (12 m/s or more) for a fresh blocker: this share of the
## ball-fact float, rising to all of it as the blocker tires (below BLOCK_TIRED_AT).
const FRESH_BLOCK_FLOAT_SCALE := 0.45
## Hitting hard from below the tape: large-miss basis += LOW_DRIVE_RISK * how far below
## (0..1 over 0.4 m) * power. Counts as the hitter's own choice (unforced if it misses).
const LOW_DRIVE_RISK := 0.55
## ... full within LOW_DRIVE_FAR - 1.5 m of the net, none from LOW_DRIVE_FAR m back, and never
## on the return of serve or the third shot (phone 2026-11-23: two full-hold returns from
## 0.8 m went into the net on this rule).
const LOW_DRIVE_FAR := 4.5
## Tired (below the stamina penalty line): power shots lose up to TIRED_POWER_LOSS of
## their horizontal speed and every shot floats by up to TIRED_FLOAT (more pop-ups).
const TIRED_POWER_LOSS := 0.35
const TIRED_FLOAT := 0.35
## Stamina: each power shot in a row by the same player costs STREAK_COST more; a block or
## volley of a fast ball costs FAST_BLOCK_COST (FAST_BLOCK_COST_HARD from 16 m/s).
const STREAK_COST := 1.0   # was 2
const FAST_BLOCK_COST := 1.0   # was 3
const FAST_BLOCK_COST_HARD := 1.5   # was 4

## ---- Position plan (docs/POSITION_PLAN.md) ----
## Same movement at every level: AI runs like the human (PLAYER_SPEED, Hard's acceleration
## and brakes). Difficulty is reading: reaction time (player_ai_brain REACTION_LATENCY_*),
## smash bracing and the position read below.
const EQUAL_MOVEMENT := true
## Smash bracing: when the other team will meet our ball at least BRACE_MIN_OVER m over the
## tape (a smash set-up), our players back off to BRACE_DEPTH m from the net. Start of the
## read, as a share of the ball's flight to the smasher (Easy, Medium, Hard); Easy reads
## only BRACE_EASY_READS of them at all.
const BRACE_ON := true
const BRACE_MIN_OVER := 0.6
const BRACE_DEPTH := 3.7
const BRACE_REACH := 1.6           # m from an opponent to the high ball for it to count
const BRACE_READ_AT := [0.75, 0.45, 0.1]
const BRACE_EASY_READS := 0.5
## Deep recovery: a contact beyond RESET_DEEP_FROM m with an opponent at the net is reset
## into the kitchen this often (then the AI moves up behind it).
const RESET_FROM_DEEP := [0.45, 0.7, 0.6]   # Hard was 0.9: it now drives more from deep
const RESET_DEEP_FROM := 3.6
## Position read: share of shots whose target follows the opponents' position (Easy,
## Medium, Hard). Own stream SALT_POSITION, one roll per flight.
const POSITION_READ := [0.2, 0.5, 0.8]
const SALT_POSITION := 0x6d06
const SALT_BRACE := 0x6d07

## Your hold ring is capped when tired: full power = 1 - TIRED_CHARGE_CAP * tiredness (the ring
## shows the cap). Phone 2026-11-23: at stamina 0 nothing felt different.
const TIRED_CHARGE_CAP := 0.35

## ---- Stamina strategy (AI spends when fresh, conserves when tired) ----
## Attack chances (pop-up attack, counter, patience speed-up) and the drive share are scaled
## by the AI's own stamina: x STRATEGY_FRESH at 100, x1 at STRATEGY_EVEN, x STRATEGY_TIRED
## at 0. Power shots aim at a tired opponent (below the penalty line) when there is one.
const STAMINA_STRATEGY_ON := true
const STRATEGY_FRESH := 1.35
const STRATEGY_EVEN := 60.0
const STRATEGY_TIRED := 0.45
## Lowest the tired scale may go on attack chances, by difficulty. Hard keeps attacking when
## tired (bench 2026-11-23: tired Hard players dinked pop-ups 0.5-1.0 m over the tape).
const ATTACK_STAMINA_FLOOR := [0.0, 0.0, 0.9]
## Run them (stamina strategy, needs the movement drain): on RUN_SHARE of soft shots and drives
## the AI puts the ball on the edge of the more tired opponent's half that is farther from where
## they are heading (RUN_WIDE_LANE at the sideline or RUN_INNER_LANE near the middle), and on
## RUN_LOB of soft shots with both opponents at the line it lobs over the tired one.
const RUN_ON := true
const RUN_SHARE := [0.2, 0.35, 0.5]
const RUN_LOB := [0.04, 0.08, 0.12]
const RUN_WIDE_LANE := 2.3
const RUN_INNER_LANE := 0.6
const SALT_RUN := 29.0
## Open court: on this share (Easy, Medium, Hard) of dinks, resets, drops, drives and returns
## with no other aim, the lane is the one farthest from where both opponents will be, so they
## have to move (Hard bench 2026-11-23: 67% of un-aimed dinks / resets landed within 0.6 m
## sideways of an opponent). Lane half-width for kitchen shots and for deep ones.
const OPEN_COURT_SHARE := [0.75, 0.8, 0.85]   # was [0, 0, 0.85]: on Easy and Medium the open-court aim never fired
## Make them run (user's call, 2026-11-24): the AI no longer aims at or near a player (at the
## feet, at the body, at the tired player, at a running player's feet). Its shots go where the
## opponents are not, so every ball has to be run to. false restores the old aims.
const AIM_AWAY := true
## ... and on this share of returns of serve it plays a short, soft, high ball that lands near
## the kitchen line: the serving team has to stay back for the bounce, then run forward.
const SHORT_RETURN_SHARE := [0.1, 0.2, 0.3]
## How far to the side of the nearest opponent a ball may land, by level (user's call,
## 2026-11-24): Easy keeps it near (a step), Medium a bit farther, Hard anywhere (the open
## court). A target farther to the side than this is pulled in toward that opponent, on the
## side it was aimed at. Depth is left alone (a short ball is still short).
const AIM_MAX_SIDEWAYS := [0.5, 0.9, 99.0]   # Hard, uncapped, lands a median 1.0 m to the side (up to 1.5 m)
const SHORT_RETURN_DEPTH := Vector2(1.6, 2.6)   # m from the net (the kitchen line is at 2.13)
const SALT_SHORT_RETURN := 29.0
const OPEN_LANE_SOFT := 2.3
const OPEN_LANE_DEEP := 2.1
const SALT_OPEN := 23.0

## ---- Drive read (positional): play deeper against a driving team ----
## Each team keeps the other team's last DRIVE_READ_WINDOW shots. When at least
## DRIVE_READ_SHARE of them were power shots, its players recover to DRIVE_GUARD_DEPTH m from
## the net instead of the kitchen line (read chance by level, own roll per flight).
## Off (gate 2026-11-23, 6 x 300 s per level): uncovered soft balls per 100 shots Easy
## 0.81 -> 1.12, Medium 0.45 -> 0.83; 8 of the 20 came within 4 s of a guard read (the
## player stepped back and the next soft ball dropped in front). Needs a "come back in on a
## soft ball" rule before it can return.
const DRIVE_READ_ON := false
const DRIVE_READ_WINDOW := 6
const DRIVE_READ_SHARE := 0.5
## 3.4 m, one step off the line (was 4.8: mid-court, drives landed at the feet; always-drive
## bench 2026-11-23: defender counters 35% -> 22%, driver share 35% -> 48% on Medium; at 3.4 m
## counters 41%, pop-ups 45%, driver share 32%).
const DRIVE_GUARD_DEPTH := 3.4
const DRIVE_READ_CHANCE := [0.35, 0.7, 0.95]
## Fast balls at the kitchen line: a player within FAST_LINE_DEPTH m of the net does not chase
## a ball of FAST_BALL_SPEED m/s or more that needs more than FAST_LINE_REACH m of movement
## (only balls at the body are blocked there); from deeper there is time to run them down.
## Off (bench 2026-11-23, drive bench 4 x 300 s): Medium fast-ball body hits 0.5 -> 2.1 per
## 100 shots, Easy fast balls not returned 2.4 -> 5.3; the always-drive team 39% -> 52% (Easy).
const FAST_LINE_REACH_ON := false
const FAST_LINE_DEPTH := 3.0
const FAST_BALL_SPEED := 12.0
const FAST_LINE_REACH := 0.55

## ---- Shot quality (docs/SHOT_QUALITY_PLAN.md): mishits from skill, not dice ----
## One mishit score (0..1) from four parts the player controls and is shown. No hidden term:
## the incoming ball is not a part (it only makes timing and getting set harder).
##   timing   when HIT was released against the ring cue (the swing itself times to the ball)
##   unset    still moving or a foot off the ground at contact
##   risk     a hard hit on a ball below the tape near the net (the hold ring turns red)
##   stamina  below the penalty line
## Below MISHIT_LARGE the shot only floats or loses a little pace. At or above it the error is
## large and follows the cause (late: long or wide; early: into the net; too low: a lob 3 times in
## 4, else into the net; not set: a
## short pop-up). With good timing, set feet and the ring not red the score cannot reach it.
const MISHIT_ON := true
const MISHIT_LARGE := 0.7
const MISHIT_SHOW := 0.3                  # a part this big is named on the stamp when the shot misses
const MISHIT_W_TIMING := 1.0
const MISHIT_W_UNSET := 0.5
const MISHIT_W_RISK := 0.9
const MISHIT_W_STAMINA := 0.4
## Release timing, seconds. The ideal release is TIMING_CENTRE before the swing has to start
## (the ring closes 0.06 s before that). Releasing early only queues the swing, so the early
## side is wide; the late side (the swing gets squeezed) is the tight one, by difficulty.
const TIMING_CENTRE := 0.03
const TIMING_PERFECT_EARLY := 0.08
const TIMING_PERFECT_LATE := 0.05
const TIMING_GOOD_EARLY := 0.35
const TIMING_GOOD_LATE := [0.14, 0.12, 0.10]
const TIMING_FULL := 0.16                 # s past GOOD (late side) where the timing part reaches 1
const TIMING_FULL_EARLY := 0.5            # the same on the early side: a tap far too soon
const TIMING_OPENING_SCALE := 1.3         # return of serve and third shot: wider windows
## AI release error: drawn once per ball on its own stream (SALT_MISS), mostly small, wider when
## the incoming ball is hard to time (x 1 + carry facts). By difficulty (Easy, Medium, Hard).
const AI_TIMING_SIGMA := [0.085, 0.060, 0.042]
const AI_TIMING_GOOD := 0.12
## Balance (shot_contact_quality: run speed share * 0.7 + feet off the ground) where "not set"
## starts and where it is full. A not-set contact also floats by UNSET_FLOAT.
const UNSET_FROM := 0.30
const UNSET_FULL := 0.80
const UNSET_FLOAT := 0.3
## The hold ring is red from this much risk (a full-power drive from 0.4 m under the tape at
## the kitchen line is 1.0).
const RISK_RED := 0.5
const RISK_YELLOW := 0.2
## Large-mishit sizes (at score 1; they start at a third of this at MISHIT_LARGE).
const MISHIT_PITCH_DOWN_DEG := 10.0
const MISHIT_PITCH_UP_DEG := 8.0
const MISHIT_YAW_DEG := 7.0
const MISHIT_SPEED_LOSS := 0.25
const MISHIT_POP_VY := 2.5
## Too low to drive: this share of those large mishits goes up as a lob over the net instead of
## into it, crossing LOW_LOB_CLEAR m over the tape and landing LOW_LOB_DEPTH m past the net.
const LOW_LOB_CHANCE := 0.75
const LOW_LOB_CLEAR := 1.3
const LOW_LOB_DEPTH := 4.5
const LOW_LOB_SPIN := 0.25                # a scooped lob keeps this share of the drive's spin
## Dinks (dink_solver.gd): a clean soft shot to the kitchen crosses this far over the tape.
## AI by difficulty (Easy, Medium, Hard); yours by your release timing.
const DINK_FIT_ON := true
const DINK_MARGIN_AI := [0.20, 0.13, 0.08]
const DINK_MARGIN_PERFECT := 0.08
const DINK_MARGIN_GOOD := 0.14
const DINK_MARGIN_OFF := 0.20             # early or late: higher still, before the mishit float
const DINK_TACTICS := ["DINK", "RESET", "DROP", "BLOCK"]
## With the dink fit on, the AI's random loose roll (AI_LOOSE_SPREAD) is off: its floats come
## from its timing and footing like yours. Ball facts (pace, rush) float a soft reply by this
## share of what they did before.
const SOFT_FACTS_FLOAT := 0.5
## The AI reads the flight grade of the ball coming at it (flight_grade.gd): a LOW ball is
## attacked this much less often (it has to be lifted), a HIGH one this much more.
const GRADE_READ_ON := true
const GRADE_LOW_ATTACK := 0.25
const GRADE_HIGH_ATTACK := 1.3
## A clean drive is planned this far over the tape (was 0.08: normal error clipped it).
const DRIVE_NET_MARGIN := 0.15

## ---- Hunting at the kitchen line (pro "hunt" study, 2026-11-25) ----
## Green light: the hitter across the net just played under strain (stretched arm, off
## balance, rushed: point_ending.opponent_strain, 0..1), so they cannot counter. From
## GREEN_LIGHT_FROM up, the kitchen AI attacks more often (x GREEN_LIGHT_BOOST at strain 1)
## and from a ball up to GREEN_LIGHT_HEIGHT m lower. Off = IDENTICAL poses.
const GREEN_LIGHT_ON := true
const GREEN_LIGHT_FROM := 0.25
const GREEN_LIGHT_BOOST := 1.6
const GREEN_LIGHT_HEIGHT := 0.08
## Hunting ready pose (data/ready_variants/hunt_ready.tres): paddle down and out in front
## while a soft rally ball is coming and the player stands within HUNT_DEPTH m of the
## kitchen line. Replaces Ready as the waiting / preparing pose there.
const HUNT_POSE_ON := true
const HUNT_MAX_SPEED := 9.0
const HUNT_DEPTH := 0.9
## Line volley: take a soft rally ball (under HUNT_MAX_SPEED) out of the air at the kitchen
## line. The contact may sit up to LINE_VOLLEY_REACH m inside the kitchen plane (the kitchen
## guard otherwise keeps volleys 0.05 m behind it; feet still stand 0.42 m behind the line),
## from LINE_VOLLEY_MIN_HEIGHT m off the floor, and scores LINE_VOLLEY_BONUS (~seconds)
## better than waiting for the bounce. Bench 2026-11-25 without it: 12 of 95 kitchen hits
## in the air, median contact 0.38 m under the tape.
## At 0.25 m reach from 0.4 m up it did nothing (bench hunt_vol): dinks land a median 1.5 m
## from the net. At 0.45 m from 0.3 m up, with the AI momentum hold (player_ai_brain: no step
## into the kitchen while rally_scorer still watches the volley), bench hunt_lean, 3 seeds:
## 51 of 219 kitchen hits in the air (23%), attacks 4% -> 9%, no momentum / kitchen faults.
const LINE_VOLLEY_ON := true
const LINE_VOLLEY_REACH := 0.45
const LINE_VOLLEY_MIN_HEIGHT := 0.3
const LINE_VOLLEY_BONUS := 0.2
