# Skill and challenge plan (planning only)

Question: how do we raise the skill ceiling without losing the casual feel?
Answer in one line: **keep the floor soft, make the ceiling real.** A mistimed swing should
never whiff or feel unfair; it should just be a worse shot, and you should see why. Good
timing, good choices and good footwork should visibly pay off.

## Why skill barely shows today

- The shot is solved to your target; skill only adds a small random nudge
  (`shot_execution_error.gd`: at most 4.4 deg sideways, 3.5 deg up/down, 14% speed).
  Timing is 24% of that nudge. So a sloppy and a perfect swing land almost the same.
- The PERFECT / GREAT / GOOD grade is cosmetic: it measures distance to the planned contact
  point, while the error uses timing in seconds. A PERFECT can still miss and nothing
  rewards it (proposal PDF p.36 and p.38, gap 2).
- Heavy assists: 3 s slow-mo aim per ball, feet carry you up to 2.4 m to the contact,
  aim plants your feet 0.85 s early, and the AI rarely punishes a loose ball
  (see `docs/AI_ATTACK_PLAN.md`).

Is timing too hard for casual players? Not if: the window is generous at the bottom,
the timing ring already tells you when (it turns lime), a late or early swing still
returns the ball, and the reward is bigger than the punishment.

## Pillars

1. **Timing that matters (forgiving floor).** One measure for the grade and the error
   (ROADMAP G1). PERFECT: tighter error and a little extra pace ("crisp"). GOOD: today's
   shot. EARLY / LATE: wider error that pushes the ball in a readable direction (late
   goes wide to your side, early pulls across). Never a whiff. Say why on a miss:
   LATE, OFF-CENTRE, OFF-BALANCE, STRETCHED.
2. **Risk you can see.** The aim target ring is drawn at the size of the error you will
   get: big when rushed, stretched or swinging at full charge, small when set and
   timed. Aiming at a line is a real gamble; the middle is safe.
3. **Soft-game touch (the heart of pickleball).** Dink height depends on charge and
   timing: a short tap is low and safe, over-charging or a late dink pops up and gets
   attacked (pairs with the AI attack plan). This is where casual and expert play
   separate.
4. **Footwork rewards.** Being set (split step on time, feet planted, not stretched)
   shrinks the error, shown as a small SET cue. Already part of the error model
   (balance 20%, extension 15%), just invisible today.
5. **Pace with a cost.** Full charge = more pace and a bigger error; full charge with
   PERFECT timing = a power shot with its own effect. Power is earned, not free.

Kept as is (your call): the planned shot wins over paddle geometry and the paddle face
angle never changes the shot. All new error goes through the existing execution-error
model in one place (`match_contact_authority.gd` / `shot_execution_error.gd`), not new
geometry checks. ROADMAP G2 "the paddle matters" is left out for that reason.

## Assist levels (separate from AI difficulty)

One setting, three presets, built from settings that already exist plus two new ones:

| | Casual | Club | Pro |
|---|---|---|---|
| Slow-mo aim budget (`aim_focus_seconds`) | 3 s | 1.5 s | off |
| Feet carry to contact | 2.4 m | 1.6 m | 0.8 m |
| Timing window for GOOD | wide | medium | narrow |
| Error scale (`execution_accuracy`) | soft | normal | full |
| Risk ring on the aim | shown | shown | shown |

Casual stays today's game with better feedback. Pro is where timing and footwork decide points.

## Challenge layer (gives the skill a reason)

- **Drill stars.** The six practice drills get score targets and 1 to 3 stars (e.g.
  "Crosscourt dinks: 15 in a row below the net, 3 stars at 25").
- **Streaks and combos.** "PERFECT x3" shown with the existing effects; a streak of clean
  dinks fills a small meter that powers up your next speed-up. Visual and score only.
- **Daily challenge.** One fixed seed and goal per day ("win a point with a speed-up",
  "no unforced errors for 5 points").
- **Match report.** After a match: PERFECT %, unforced errors, winners, longest rally,
  best streak. Teaches without a tutorial.
- **Ladder.** Beat AI players up the ladder (styles x difficulty already exist), unlocking
  paddles (paddle designs already exist).

## Order

1. **Measure first (no play change).** Log the human's timing error, grade, balance and
   result for every contact to `perf.jsonl`; play a few matches on the phone at today's
   settings to set the baseline (how often PERFECT, how often a miss, rally length).
2. **Timing that matters + miss reasons** (pillar 1). Smallest change with the biggest
   effect on feel.
3. **Risk ring** (pillar 2) and **SET cue** (pillar 4): mostly showing what is already
   computed.
4. **Dink touch** (pillar 3), together with the AI attack plan.
5. **Assist presets** in Settings, Casual as default.
6. **Challenge layer**: match report, drill stars, streaks, then daily challenge and ladder.

Gate for steps 2 to 5 (they change play): ROADMAP Gameplay v2 gate (6 seeds x 300 s bench,
animation rules PASS, the AI side unchanged unless intended) plus hand-played phone checks at
Casual and Pro. Step 6 is presentation and progression only.

## Open questions

- Default preset: Casual for everyone, or ask once on first launch?
- Should PERFECT add pace, or only accuracy? (PDF G1 says accuracy, not power.)
- Daily challenge and ladder need saved progress: OK to add a save file?
