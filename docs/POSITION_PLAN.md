# Position plan: advantage and disadvantage on the court

User idea (2026-11-23): a smash pushes the defender back, so the AI should see it coming and
give ground to block. That leaves the defender deep, which is a positional disadvantage: the
next short ball into the kitchen makes them run forward and hit up. Difficulty should be how
well the AI uses position (its own and yours), not how fast it runs. Movement speed should be
the same, natural, at every level.

## What the code does today

- **Speed is the difficulty knob**: AI top speed is 4.35 / 5.0 / 5.8 m/s on Easy / Medium /
  Hard (`ai_match_movement.gd` `SPEEDS`), acceleration 12 / 14 / 16, brakes 16 / 18 / 20,
  re-plan every 0.15 / 0.12 / 0.10 s. You move at 5.8 m/s. Easy is easy partly because it
  is physically slow.
- **Fixed recovery spots**: after its own shot, the AI walks back to the kitchen line + 0.75 m
  (4.4 m after a drive), whatever the opponent is about to do (`player_ai_brain.gd`).
- **Nobody braces for a smash**: a defender at the kitchen line stays there while an overhead
  is set up. It either reflex-blocks from 2.5 m or gets beaten.
- **Targets barely read position**: one feet target exists (an opponent caught between 3.0 and
  5.5 m, `FEET_ON`); otherwise lanes and depths come from the roll and the risk level, not
  from where the opponents stand or where they are moving.

## Mechanics

### 1. Same movement at every level
- All AI players run like you: top speed 5.8 m/s, the same acceleration and brakes. The
  low-stamina slowdown stays (it is earned, not a level setting).
- What changes by level is **reading**: reaction time (time to see the shot, about 0.33 /
  0.27 / 0.22 s), how early it re-plans, and the mechanics below.

### 2. Bracing for a smash (defender)
- When an opponent is set up under a high ball (contact predicted at least 0.6 m over the
  tape, the hitter within reach of it), the receiving pair **gives ground**: they step back
  to about 3.5 to 4 m from the net, split to cover both lanes, and lower into a block stance.
- **When they start** is the level: Hard reads it as soon as the high ball is struck, Medium
  half-way through its flight, Easy late or not at all (stays at the line and often gets beaten).
- Backing off buys time to block (more balls come back) but costs position: the blocker is
  deep when the rally goes on.

### 3. Recovering from a deep spot
- A deep AI (beyond 3.5 m, or still moving back) replies with a **reset**: a soft ball into the
  kitchen that buys time, then moves up behind it. It does not try to drive from there unless
  the ball sits up.
- Hard almost always resets and moves up. Easy sometimes drives from deep (risky, and it stays
  back).

### 4. Using the opponent's position (attacker)
Every AI shot first reads both opponents: depth from the net, which way they are moving, and
the gap between them. The shot it picks follows a table:

| Opponent read | Shot |
|---|---|
| Deep (beyond 3.5 m) or moving back | Short soft ball into the kitchen ("drop on them"): they must run forward and hit up, often popping it up |
| Running forward, in transition | At the feet (exists today as `FEET_ON`) |
| Both at the line, close together | Lob over the weaker side, or a sharp angle wide |
| Split wide | Through the middle gap |
| One up, one back | At the back player's feet, or the gap between them |
| Just smashed and still recovering | Behind them (the side they came from) |

How often the read wins over the default roll is the level: about 80% of shots on Hard, 50%
on Medium, 20% on Easy. The roll still adds variety, so it is never fully predictable.

### 5. Position as a fact the game knows
- Each player gets a position score: distance from their ideal spot (kitchen line in a dink
  rally, centre of their half), movement direction, and whether they are recovering. The pair
  gets an advantage value (who owns the kitchen line).
- Uses: the AI's choices (above), the float (a player who runs forward 2 m to dig out a short
  ball already counts as moving), and the bench report.
- The same rules apply to you: smash, and the AI backs off; then a drop short wins the point
  if you follow it in.

### 6. Readable for you
- The AI's shuffle back before a smash and its sprint forward after a drop should read as
  body language (the existing walk and stance poses). No new UI.
- Maybe later: a small arrow on the opponent who is out of position (training aid, off by default).

## How to check (all-AI bench, per level)
- Defender depth when a smash lands: Hard backs off early, Easy late.
- Smashes returned: Hard more than Easy.
- Share of AI shots chosen by position read: about 80 / 50 / 20%.
- After a team is pushed deep: how often it loses the point within the next 2 shots.
- Run-forward contacts (a player covering 1.5 m or more toward the net to reach the ball) and
  their pop-up rate.
- Movement: the same top speed for every level in the motion bench; the pose rules stay PASS.
- Rally lengths stay in the current targets, and Easy is still the easiest (see risk below).

## Risks
- **Easy gets harder** once it runs at 5.8 m/s. Its slower reading, late bracing and 20%
  position read have to make up for that. Check the order Easy < Medium < Hard on points won
  against a fixed opponent.
- **Hard gets too defensive** if it backs off for every high ball. Bracing only triggers on a
  real smash set-up.
- **Animation**: backing off quickly needs the back-pedal walk to look right (motion bench).

## Open questions
- Equal speed for Easy too, or keep Easy a little slower (say 5.3 m/s) as a beginner's aid?
- Should your partner AI also brace and recover by these rules (yes, the same rules is the plan)?
- The out-of-position arrow: wanted, or body language only?
- "Weak link at the kitchen" read here as "a short soft ball into the kitchen that the deep
  player must run up to". Is that what you meant?

## Status (2026-11-23, build 36 on the phone)

Built, all in `gameplay_tuning.gd`: `EQUAL_MOVEMENT` (every level runs at 5.8 m/s with Hard's
acceleration; reaction time stays 18 / 12 / 8 frames), smash bracing (`BRACE_*`: back off to
3.7 m when our ball will reach an opponent within 1.6 m of it, 0.6 m or more over the tape,
volleys legal; Easy reads half of them, late), deep recovery reset (`RESET_FROM_DEEP`), and
the position read (`POSITION_READ`, `ai_match_tactics.position_target`: short in front of a
deep player, at the feet of a runner, the back player's feet, the middle, a sharp angle;
targets offset 0.35-0.6 m to the open side so they are not body shots). Body language only,
no arrow.

All-AI, 6 x 300 s: median rally Easy 7 / Medium 14 / Hard 17 (order holds), p90 35 / 52 / 58;
position-read shots 8 / 16 / 32%; body hits 8 / 4 / 10%; nets/outs 22 / 52 / 52%; stamina p10
64 / 61 / 68, lowest 20-25. Easy rule faults 22% (noisy: 31% / 11% by half). Animation rules
PASS (snap-back 5.9%, limit 6%), tool tests pass.

## Status (2026-11-23, build 40 on the phone)

Drive read (`DRIVE_READ_*`) and fast-ball line reach (`FAST_LINE_*`) are built but off: the
always-drive bench showed the guard depth hurt the defense at 4.8 m (counters 35% -> 22%),
fast-line reach raised fast-ball body hits 0.5 -> 2.1 per 100 shots, and at 3.4 m the guard
step-back left short soft balls uncovered (Medium 0.45 -> 0.83 per 100). New: run them
(`RUN_*`, part of the stamina strategy): 20 / 35 / 50% of soft shots and drives go to the edge of
the more tired opponent's half farther from where they are heading, and 4 / 8 / 12% of soft
shots lob back over them when both are at the line. Smart vs plain on Medium: +11.7 / +11.4
points of share (12 seeds per side).
