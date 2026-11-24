# Shot quality plan: honest misses, skill mishits, low flights and dinks

Built 2026-11-24 (all steps; see Status at the end). Not yet tuned on the phone. Related: `docs/GAME_MECHANICS_PLAN.md`
(change 3 "occasional real misses" and change 9 "readability" are what this replaces),
`docs/PLAYER_FEEL_PLAN.md`.

## 1. What "FORCED" and "UNFORCED" mean today

When a ball ends in the net or out, the stamp adds one word (`point_ending.gd`,
`fx/rally_moments.gd`):

- **FORCED**: the contact was hard (pressure 0.25 or more: fast incoming ball, little time,
  low ball, running, or your own timing off).
- **UNFORCED**: the contact was easy (pressure under 0.25) and it still missed.

These are tennis statistics words. They say who is to blame, not what went wrong, and
"forced" also covers your own late release, which nobody forced.

## 2. Why a drive from a good position still hits the net

From the phone log of the last session (18 points, 37 rally shots by you): 5 points ended
on your ball in the net, all five on drives.

| # | Situation | What the game did | Stamp |
|---|---|---|---|
| 1 | Drive from the kitchen, ball 0.51 m high | hidden roll "low drive": launch speed up 4.55 -> 2.13 | UNFORCED |
| 2 | Reply to a 14.7 m/s drive, ball 0.18 m high | hidden roll "rushed": 5.97 -> 2.89 | FORCED |
| 3 | Return of serve, 1.9 s to get ready, released 0.062 s late | hidden roll "late": 7.17 -> 3.43 | FORCED |
| 4 | Third-shot drive, ball 0.36 m high | no roll; the planned flight clears the tape by only 8 cm and normal error took it | UNFORCED |
| 5 | Return of serve, 2.0 s to get ready, released 0.061 s late | hidden roll "late": 8.07 -> 4.55 | FORCED |

How the rule works now (`shot_execution_error.gd`, `gameplay_tuning.gd`):

- Pressure = ball facts + half of your timing error (0.10 s late counts as 1.0).
- At pressure 0.25 or more the game rolls a dice: 15% chance at the line, up to 60%.
- A hit on the dice tilts the shot 10 degrees down and takes 12% off the speed. That always
  goes into the net. There is nothing in between: the same swing is either clean or dead.

Why it feels like the game is lying:

1. **It is a dice, not a degree.** Being a little late does not make a slightly worse shot.
   It makes a clean shot most of the time and a net ball sometimes.
2. **Timing alone trips it.** 0.06 s late is already over the line (shots 3 and 5), with two
   seconds to prepare and both feet set. Position gives no protection.
3. **Nothing is shown.** No timing result at contact, no warning that a hard drive from
   0.5 m is risky, and the stamp says FORCED instead of LATE.
4. **Drives are planned 8 cm over the tape** (`shot_physics.gd` `net_margin`), so ordinary
   error nets some with no cause at all (shot 4).

## 3. Proposal A: say what happened, never who "forced" it

Decision (user, 2026-11-24): no FORCED / UNFORCED and no credit line such as "forced it".
How an opponent "forced" a miss cannot be seen on screen, so the game must not claim it.
A stamp may only state a fact the player could have seen and done differently.

Two lines: where the ball went, then the hitter's own cause.

| Line 1 today | Line 1 proposed |
|---|---|
| NET | NET (one word for every net ball; TAPE was not clear) |
| OUT | LONG or WIDE, with JUST in front when under 20 cm out |
| WINNER! | SMASH! (a smash), ACE! (unreturned serve), DROPPED IN (a soft ball nobody reached), WINNER! (any other attack) |

| Line 2 (cause) | Shown when | What the player saw |
|---|---|---|
| LATE / EARLY | release outside the GOOD window | the timing word at contact |
| TOO LOW TO DRIVE | hard hit on a ball below the tape near the net | the hold ring was red (3 in 4 go up as a lob over the net, `LOW_LOB_CHANCE`; the rest net) |
| MOVING | still moving or a foot off the ground at contact | their own player running |
| LOW STAMINA | stamina below the penalty line | the stamina bar |
| (no line) | none of the above: a clean hit that just missed | nothing to learn, so nothing is said |

Colour by whose point it is (gold when your team wins it, red when it loses it). The banner
ribbon uses the same words as the stamp. The bench report keeps forced / unforced as a
private statistic.

## 4. Proposal B: mishits come from skill, not dice

Principle: **no hidden term.** Every part of the mishit score is something the player
controls and is shown. The incoming ball is not a part on its own: a fast or awkward ball
is harder because it is harder to time and to get set for, not because of a secret penalty.

| Part | From | Shown as |
|---|---|---|
| Timing | release vs the ideal moment | timing word at contact |
| Set | feet planted and stopped before contact | the player's own stance; MOVING on a miss |
| Risk | power vs ball height and distance to the net | hold ring colour while charging |
| Stamina | below the penalty line only | stamina bar |

Removed from today's rule: the "pressure" from incoming pace, time since their hit and
ball at the body (`shot_contact_quality.carry` feeding the miss roll), and the "rushed"
cause. Those facts may still make the reply float a little (a block of a hard ball comes
back higher), but they can no longer put a ball in the net by themselves.

Rules:

1. **Degrees.** The score scales the effect smoothly. A small mishit clears the net lower or
   floats a little; only a large one (about 0.7 and up) nets or sails out.
2. **The error follows the cause.** Late: floats up and drifts to the late side (attackable).
   Early: pulled down, into the net when large. Too much power on a low ball: into the tape.
   Not set: short and high (a pop-up).
3. **Good-position promise.** Set feet + timing inside the GOOD window + ring not red =
   never a large miss, whatever the incoming ball. A miss always has one of the four causes
   above, or it is a clean hit that just missed by the small normal error.
4. **Wider, graded timing.** PERFECT (about 0.03 s), GOOD (0.07 s), LATE / EARLY beyond.
   Returns of serve and third shots get the widest window. Window size by difficulty.
5. **Shown before and after.** While holding, the ring turns from green to yellow to red as
   the chosen power gets risky for this ball height. At contact a small word shows the
   timing. After a miss the stamp names the cause (proposal A).
6. **Same rule for the AI.** Its timing and set come from a per-level spread (one draw per
   ball, own random stream), then go through the same score, and its stamp shows the same
   words. No separate AI dice.
7. **Drive net margin** rises from 8 cm to about 15 cm for a clean hit, so a clean drive
   does not clip the tape by chance.

Contact rule unchanged: the pose and paddle face still never change the shot.

## 5. Proposal C: flight quality (net clearance and apex)

Three numbers per shot, taken once at launch from the flight trace the game already
computes (`shot_physics.gd` returns `y_at_net` and `apex_y`):

- **Clearance**: height over the tape where the ball crosses.
- **Apex side**: is the top of the flight on the hitter's side (ball already falling as it
  crosses) or on the receiver's side (still rising as it crosses).
- **Arrival height**: how high the ball is where the receiver can first reach it.

Grades:

| Grade | Clearance | Apex | Meaning for the receiver |
|---|---|---|---|
| Low (good) | about 5 to 20 cm | hitter's side | must be dinked or reset; attacking it is the "too low to drive" risk |
| Loose | 20 to 50 cm | near the net | can be sped up |
| High (smashable) | over 50 cm | receiver's side | smash it |

Lobs are graded by their own rule (apex past the receiver, landing deep).

Uses:

- **AI reply.** Today the AI decides to attack from contact height over the net
  (`ai_kitchen_tactics.gd`, 12 to 18 cm). It would read the grade at launch instead, so it
  prepares the smash pose early for a High ball and dinks a Low one.
- **Feedback.** A plain ball trail coloured by grade (decided 2026-11-24): green Low,
  yellow Loose, red High. Flat colour, no glow. A short word on a good one (LOW DINK,
  CLEAN DRIVE).
- **Stats.** A `flight` note per shot (clearance, apex side, grade) for the bench report
  and the phone log.

## 6. Proposal D: dink system

- **Solver.** For a kitchen target, pick the lowest arc that clears the tape by a margin
  with the apex at or before the net and the bounce inside the kitchen. Today every soft
  shot is simply lifted to 20 cm over the tape (`SOFT_NET_MARGIN`), wherever the apex is.
- **Margin is the skill.** Clean-hit margin by level: Hard about 6 to 10 cm, Medium 10 to
  15, Easy 15 to 25. For the human it follows timing: PERFECT gives the lowest margin, GOOD
  a little more.
- **Dink mishits go up more than down.** A late or rushed dink gains height and its apex
  moves across the net (Loose, then High), so the punishment is getting attacked. Only a
  large mishit goes into the net.
- **Limits are real.** From a low contact right at the net the apex cannot be on the
  hitter's side; the solver then gives the best it can and the grade says Loose. That is
  the reason to step back or take the ball earlier.

## 7. Build order

Each step is small and checked on its own.

| Step | What | Check |
|---|---|---|
| 0 | `flight` note: clearance, apex side, grade, per shot. No behaviour change | bench poses IDENTICAL; one seed gives today's spread, plus one phone session |
| 1 | Stamp words (proposal A), the timing word at contact, and the trail colour by grade | presentation only; IDENTICAL |
| 2 | Human mishit score with degrees and the good-position promise; drive margin 15 cm | phone log: no large miss on set + GOOD timing; your netted share under an agreed limit |
| 3 | Hold ring risk colour | phone |
| 4 | Dink solver with per-level margins and the apex rule | one seed per level: dink clearance median and share of Low grade |
| 5 | AI reads the grade for attack vs dink | bench: smashes follow High balls, attacks on Low balls rare |
| 6 | AI mishits through the same score | bench targets table of `GAME_MECHANICS_PLAN.md` |

Steps 2, 4, 5 and 6 change gameplay and follow `docs/BENCH_RULES.md`.

## 8. Decisions (user, 2026-11-24)

- No forced / unforced wording, no credit line, no hidden pressure term.
- Cause words: LATE, EARLY, TOO LOW TO DRIVE, MOVING, LOW STAMINA.
- Winner words are split: SMASH!, ACE!, DROPPED IN, WINNER!.
- A set, well-timed, sensible shot never has a large miss.
- Dink mishits mostly pop up; only a large one nets.
- Ball trail coloured by flight grade.

Still to tune on the phone: timing windows (start PERFECT 0.03 s, GOOD 0.07 s) and the
trail colours.

## Status (2026-11-24)

All seven steps are in. Dials: `gameplay_tuning.gd` ("Shot quality" block). Report:
`python3 tools/sq_report.py logs/bench_<name>.perf.jsonl` (mishits, flight grades, stamp lines).

- **Timing is the release, not the swing.** The swing times itself to the ball, so the old
  "timing error" (swing vs contact) was system noise of 0.02 to 0.06 s; two of the five
  netted drives in section 2 were that. Timing is now when HIT is released against the ring
  cue (`human_contact_controller.release_error`): PERFECT from 0.08 s early to 0.05 s late,
  GOOD from 0.35 s early to 0.14 / 0.12 / 0.10 s late (Easy / Medium / Hard). Early is wide
  because an early release only queues the swing. The word shows above the ring at release.
- **Mishit score** (`shot_execution_error.mishit`): timing 1.0, not set 0.5, risk 0.9, stamina
  0.4; large from 0.7. Soft shots pop up, late goes long or wide, early / too low / no stamina
  goes into the net, not set is a short pop-up. The old dice and the "rushed" cause are gone.
- **AI** draws its release error once per ball (spread 0.085 / 0.060 / 0.042 s, wider on a
  hard ball) and its random loose-dink roll is off.
- **Dink fit** (`dink_solver.gd`) runs at contact for DINK / RESET / DROP / BLOCK to the
  kitchen from within 4.6 m. Easy bench: dink clearance median 0.56 m -> 0.22 m, apex 0.4 m
  on the hitter's side.
- **Grade** (`flight_grade.gd`) also uses the height at the receiver's kitchen line and the
  ball's speed, so a smash coming down is not graded High.
- **Not done:** the banner ribbon still uses its own lines ("Into the net!"); the AI does not
  yet set its smash pose earlier from the grade (it only weighs attack vs dink with it).
- **Open:** Easy AI rallies are long (36 shots per point in one seed; they were 28 before).
  Lower dinks give the AI less to attack. Needs the phone first: against a human the rally
  ends on the human's choices.
