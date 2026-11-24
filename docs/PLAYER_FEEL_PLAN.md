# Player feel plan (after Gameplay v2)

Feedback from the first phone session on build 34 (2026-11-23): the game now feels too easy
for the human. Lots of drives go unpunished. Targeting is hard to do quickly. The rally
counter is gone, and stamina is hard to see. The old game was hard, but for a bad reason:
the AI never made mistakes and its shots felt predetermined.

Goal: drives are a risk/reward choice, touch shots can be aimed fast, the AI punishes your
habits instead of being perfect, and stamina and the rally counter are always readable.

## What your session shows (phone log, build 34, 33 points)

- **You drove almost everything**: 39 drives, 3 speed-ups, 1 smash and only 2 touch shots
  of 45. Drives are the dominant strategy.
- **The AI mostly absorbed them**: of its 149 shots, 42 resets, 40 dinks, 26 returns, and
  only 16 speed-ups and 4 smashes. A quarter of its kitchen contacts (38 of 156) were above
  the tape, yet most went back soft: a fast incoming ball counts as "rushed", which picks a
  reset, and the counter chance on Easy is only 25%.
- **Points**: you won 16 and lost 17. The AI lost 9 on forced errors and 6 on your winners.
  You lost 10 on your own unforced errors (nets/outs), 2 on body hits and only 2 on AI
  winners: the AI rarely won a point by attacking you.
- **Rallies were short** (median 5), because your drives end them quickly, one way or the other.
- **Stamina never mattered**: your lowest was 67, with no penalty.
- Your carry was about 0 on almost every contact. Your clean shots never float, so the AI
  only gets attackable balls when you drive at it.

So the AI isn't attacking much because (a) its answer to a fast ball is almost always a soft
reset, and (b) your soft shots never pop up. Changes 0 and 3 target that.

### 0. The AI attacks more (the main fix for "too easy")
- **Counter drives**: an incoming fast ball met at or above the tape near the kitchen is
  countered (a speed-up back at your feet or body) much more often: about 45% on Easy,
  65% on Medium and 80% on Hard, instead of 25/42/58%. Below the tape it still blocks.
- **Attack lower balls**: the pop-up attack starts 0.12 m over the tape on Medium and Hard
  (now 0.25 m), so a slightly high dink or drive gets punished.
- **Attack off the bounce**: a dink of yours that bounces up to waist height in the
  kitchen can be rolled (a topspin speed-up), not only volleyed.
- **Your touch shots carry your timing**: a mistimed tap (early or late release) floats a
  little, so a careless dink sits up and gets attacked. A well-timed one stays tight. Skill,
  not a dice roll.

## What the code does today

- **Drive = any hold over 0.18 s** (`human_shot_choice.gd` `TAP_SECONDS`). Full power is
  reached at 0.45 s (`MAX_SERVE_CHARGE_TIME`). A short tap is a touch shot (dink, reset,
  block, drop) and anything longer is a power shot, so a drive costs almost no commitment.
- **Your drives always land where aimed.** The solver aims at 5.0 m deep. Only small
  execution error applies, and the new large miss needs a hard contact (`pressure()`), so a
  hard drive from a low, comfortable ball never misses. Nothing makes hitting hard from below
  the net risky.
- **Aiming**: dragging inside the hit circle moves an aim cursor while you hold
  (`mobile_controls.gd` `_update_shot_drag`). A tap is too short to steer, so touch shots
  keep the cursor's sideways spot and a fixed depth (1.45 m for a dink).
- **AI reply to your drive**: a fast ball raises the receiver's carry, so its block floats a
  little. At kitchen distance a 12 m/s drive gives about 0.4 carry, which is a small float.
- **Rally counter**: it lives in `scripts/fx/rally_moments.gd`, which is the visual-pass
  session's uncommitted work. Build 34 was `court-environment` plus the Gameplay v2 patch
  only, so the counter isn't on the phone.
- **Stamina bars**: only two (you and one opponent), placed over the heads. They fade out
  unless stamina is changing. Your partner and the second opponent have none.
- **Stamina costs**: drive 8, smash 10, speed-up 8, dink or reset 1, plus sprinting. Blocking
  a fast ball costs the same as a dink.

## Proposed changes

### 1. Drive needs a real hold (human)
- Three bands on release: **tap** (under 0.18 s) = touch shot; **punch** (0.18 to 0.35 s) =
  a firm, flatter roll at medium pace, safer, landing mid-court; **drive** (0.35 s and over)
  = full drive, with power growing to the cap.
- The hit circle shows it: the ring fills, turns orange when the drive band is reached, and
  the shot word under HIT changes (PUNCH, then DRIVE).
- Threshold is one constant, to tune on the phone.

### 2. Hitting hard is a risk (same rule for you and the AI)
- A power shot met **below the net tape** has to go up and over. Its contact counts as hard
  for the large-miss rule (net or long), scaled by how low and how much power. It's a cause
  you can see, so it can be called FORCED or UNFORCED fairly. A drive from a ball at or above
  the tape stays safe.
- **Drive streak**: each power shot in a row by the same player costs +2 stamina more
  (8, 10, 12 ...), resetting on any touch shot. Spamming drives drains you into the
  below-50 penalty (slower moves, wider power-shot error).
- "Perfect training" still removes the misses.

### 3. Good drives force pop-ups, bad drives get punished
- **Blocking a drive floats more**: a block of a ball of 12 m/s or more, met at or below
  the waist, gets extra carry (more lift and depth). A low, fast drive then earns you a
  pop-up to attack. The same rule applies when the AI drives at you.
- **The AI counters high drives**: a drive arriving above the tape at the kitchen is
  countered (speed-up at your feet) more often; the counter chance rises by difficulty.
- **The AI reads your habit** (answers "predetermined"): after 2 or more drives in a row
  from you, the receiving AI stands a step deeper and sets earlier for the next one, so the
  third drive is blocked cleanly, and a drop or dink then catches it out of position. Its
  choice of reply still rolls (risk level, loose dinks, patience), so it isn't a script.

### 4. Flick targeting in the hit circle
- On a **tap**, the swipe direction at release picks the lane: flick left or right = cross
  court to that side (wide, near the sideline), straight up = through the middle or down the
  line, no flick = current aim.
- **Flick length = pace**: a short flick is a soft dink landing 1.2 to 1.5 m deep, a long
  quick flick is a **fast dink**, flatter and landing 1.8 to 2.1 m, harder to attack but
  riskier (lower net clearance).
- Hold-and-drag aiming for power shots stays as it is.
- Works the same in the aim-focus hold.

### 5. Rally counter back
- Either put the visual-pass session's work (`rally_moments.gd`, `pixel_draw.gd`, its
  `game.gd` and UI-theme edits) into the next phone build, like build 33 had, or commit that
  work first so it is on a branch. The FORCED / UNFORCED stamp lives in the same file.

### 6. Stamina you can read, and costs that make sense
- **A small bar over every player** (all four), shown the whole rally, amber below 50 (the
  penalty line), with a brief flash when it drops. It hides between points except for the
  tired ones.
- **Fast blocks cost stamina**: blocking or volleying a ball of 12 m/s or more costs 3
  (a smash return costs 4). A firefight then drains both sides, not only the attacker.
- Keep the long-rally refill (+12 to the winner of a 15+ shot rally).
- Check: in a normal match on Medium your stamina dips below 50 at least once and never
  sits under 25 for long (the human rows in `shot_report.py --human`).

### 7. Difficulty
- Easy is now soft for a regular player (it pops up the most and attacks the least).
  Consider making Medium the default.
- Later: per-opponent ratings (DUPR-like) that set each AI's pop-up rate, patience, attack
  chance, risk mix and reaction time.

## How to check
- Changes 2, 3 and 6 change gameplay: all-AI bench per difficulty with
  `shot_report.py --targets` (rally length, nets/outs, unforced share), as before.
- Changes 1, 4 and 5 are about your input and the screen: no bench can check them. A phone
  build plus `shot_report.py --human` on the phone log (your large misses from a clean
  contact must stay 0).

## Open questions
- Drive threshold: 0.35 s, or longer?
- Should the punch band exist, or only tap vs drive?
- Flick: cross-court by swipe direction, or should the flick aim exactly where it points?
- Stamina bars on all four players, or only your team?
- Include the visual-pass session's work in the next phone build?

## Status (2026-11-23, build 35 on the phone)

Built: rally hold up to 1 s with power growing with the hold (`RALLY_FULL_HOLD`); the AI
counters drives more (by difficulty, defender stamina and your drive streak); pop-up attack
from 0.12 m on Medium and Hard, and off the bounce; timing float on every shot; low drives
risk a large miss; tired power shots come off slower and every shot floats more when tired;
the block float and all float on balls of 12 m/s or more scale with the blocker's stamina
(a fresh block sends the pace back); stamina: drive streak +2 per drive, fast blocks 3/4,
slower recovery; bars over all four players; flick aiming on taps; rally counter back (build
35 = `court-environment` + all of this branch's uncommitted work); kitchen guard tightened.

Drive bench (`tools/drive_bench.sh`, team 0 drives every ball, Easy, 4 x 180 s):
drive speed 16.8 / 14.1 / 13.1 / 13.2 m/s for drive 1 / 2 / 3 / 4+ in a row; the 3rd drive
misses big 31% of the time; drivers drop to stamina 35 (median), 0 at worst; fresh
defenders counter 37% of drives (was 20%) and pop up 49% (was 65%).

All-AI (6 x 300 s): Easy median 11 / p90 61, Medium 11 / 68, Hard 12 / 80; nets/outs
33-49%, unforced share 12-20%, rule faults 10-14%. Animation rules all PASS, tool tests pass.
