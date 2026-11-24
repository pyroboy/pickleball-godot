# AI attack plan (Gameplay v2 package)

Goal: the AI attacks like real kitchen players, so rallies end in 5 to 20 shots instead of
100, speed-ups and firefights happen, and a loose dink gets punished (yours too).
This changes AI decisions, which `docs/ROADMAP.md` keeps locked until Gameplay v2, so it
runs under that package's gate (below).

## What the data says (all-AI bench, 6 runs, 2026-11-22)

- Rallies: 105, 104, 74, 44, 41 shots (some 3 to 25). Real doubles rallies average under 10.
- Shot mix: DINK 255, RESET 169, LOB 20, SMASH 7, SPEED_UP 1 (of ~485).
- **Kitchen contacts above the net: 1%.** Median contact is **0.39 m below** the net top.
- The only route to a speed-up (`ai_kitchen_tactics.gd` `attack_probability`, reached from
  `ai_match_tactics.gd` `_choose_base`) needs the ball **0.18 m above** the net. So it
  almost never fires: the AI's dinks are too perfect (planned 0.2 m over the net and landing
  deep in the kitchen) and the receiving AI lets every ball drop below the net.

So nothing ever "goes wrong" in a dink rally, and nobody tries to make it go wrong.

## Changes (smallest first; bench after each)

1. **Loose dinks (pop-ups).** Not every dink is perfect: give the planned net clearance
   (`SOFT_NET_MARGIN`, 0.2 m) a spread. Mostly tight, sometimes 0.35 to 0.6 m, more often
   when the hitter is stretched, moving or rushed, and on easier difficulty. Rolled from
   the AI's own tactic RNG (`_tactic_rng`), never the global one. Those balls arrive
   attackable, so the existing attack rule starts working.
2. **Take the ball earlier.** When a dink can be volleyed above net height, the receiving
   AI picks that earlier, higher contact instead of letting it drop (contact choice in
   `player_ai_brain.gd`). Real players attack the ball out of the air.
3. **Low speed-ups (patience runs out).** Allow a riskier `SPEED_UP` from a ball near net
   height (from net -0.1 to +0.18 m) with a small chance that grows with the dinks
   already in the rally (patience), by difficulty and style (Power Attacker most,
   Patient Dinker least, using `ai_playing_styles.gd` weights). Aimed at the body or
   the off-hand hip; flatter and slower than a high-ball attack, so it can be countered.
4. **Firefight replies.** A fast ball at the kitchen is answered by a block / counter
   (counter-attack if it arrives high, reset if low). The `RESET` branch exists in
   `response_kind`; add the counter so exchanges can go 2 to 4 hard shots.
5. **Shot names.** Make sure speed-ups, counters and firefight volleys are named in the
   shot label and logged, so the effects (labels, rally counter) show them.

Not changed: shot physics, ball flight, scoring, the contact rule (planned shot wins),
the execution-error model, input timing for the human.

## Targets (all-AI bench, 6 seeds x 300 s)

| Measure | Today | Target |
|---|---|---|
| Mean rally length | ~45 shots | 8 to 15 |
| Longest rally (p90) | 100+ | under 30 |
| Kitchen contacts above the net | 1% | 8 to 15% |
| Speed-ups per 100 kitchen shots | ~0.3 | 5 to 10 |
| DINK share of all shots | ~53% | 35 to 50% |
| Points ending in an attack winner or forced error | rare | at least 1 in 3 |

## Gate (from ROADMAP Gameplay v2)

- `tools/bench_seeds.sh attack_base 300 "1 2 3 4 5 6"` before, the same after each step.
  The targeted rows improve and no other row gets worse; the animation rules stay PASS
  (no late pose switch, paddle meets ball, no snap-back, wind-up wobble, flutter).
- `python3 tools/pose_timeline.py <name> --summary` for poses at contact on speed-ups.
- A short hand-played check on the iPhone at each difficulty: you should get attacked
  when you dink high, and get chances to attack when the AI pops one up.

## Open questions

- How hard should Easy be? Plan: Easy pops up more and attacks less.
- Should the human's own loose dinks get punished as often as the AI's? Plan: yes, at
  the same rate per difficulty.
