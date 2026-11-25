# Bench rules

A bench costs wall time and tokens. Run one only when it can change a decision, and stop it
the moment it can't. Every run is logged in `docs/BENCH_LOG.md`.

## 1. Before the run

State these four things. If one is missing, don't run yet.

1. **Objective**: the one question the bench answers, and what you do for each answer
   ("does the new claim rule cut double-takes? keep it if they drop, revert if not").
   No decision hanging on it = no bench.
2. **Datapoints**: the perf notes or report lines that answer it. Check they exist first:
   `python3 tools/bench_plan.py <note> [...]` (or `NEED=a,b` on the bench, which refuses to
   start when no script records the note). A missing datapoint is added before the bench, not
   discovered after it.
3. **Cheapest tool** that gives those datapoints:

   | Question | Tool | Cost |
   |---|---|---|
   | Scripts compile, no errors | `tools/bench.sh x 20` | ~5 s |
   | Card motion, movement, reactions | `tools/motion_bench.sh` | ~5 s |
   | Pose shape | `tools/pose_review.sh` | no bench |
   | Change is visual only | `BASE=<base> tools/bench.sh x 60` | ~15 s |
   | Gameplay / AI / contact behaviour | `tools/bench_seeds.sh` | ~30 s per seed |

4. **Seeds and why** (next section).

## 2. How many seeds

Seeds are not the unit: **events** are. One 120 s seed gives about 160 AI hits and 280 AI
plans, but only about 9 points. Get real counts for your datapoint with `tools/bench_plan.py`.

| Objective | Seeds | Why |
|---|---|---|
| Errors, compile, "does it run" | 1 (20-30 s) | deterministic |
| Visual only (expect `IDENTICAL`) | 1 with `BASE` | deterministic: seed 2 would say the same |
| "Does X ever happen / never happen" | 1, add one only if X is rare | count of events, not a rate |
| Per-hit rate (snap-back, miss, pose switch) | 1-4, sized with `bench_plan.py` | ~160 hits per seed |
| Animation rules PASS / FAIL | 1, 3 only before a commit that touches swings | limits sit near today's levels |
| Per-point outcome (who wins, how points end) | many, and usually not worth it | ~9 points per seed |

Hard cap: 3 seeds per bench (user's call, 2026-11-23). `tools/bench_seeds.sh` runs the seeds side by
side, so 3 seeds take the wall time of one (`SERIAL=1` runs them one after another). Timing numbers
(ms per tick, spikes) from seeds run side by side are inflated by 10-15%: compare CPU cost only
between serial runs (`tools/bench.sh`, or `SERIAL=1`). The bench is
already headless: nothing is drawn (no crowd, no background), and it runs as fast as the game
scripts allow, about 3x real time (300 game-seconds in ~95 s); 91% of that is ball play.

Start with seed 1. More than one seed needs a written reason (`WHY=`), based on events:

- Rate A/B: events per side ≈ `16 · p · (1 − p) / d²` (p = today's rate, d = smallest change
  that would alter the decision). `tools/bench_plan.py <note> --rate p --detect d` does the
  sum and turns it into seeds and minutes.
- If the answer is over ~6 seeds, don't run it. Pick a denser datapoint (per hit instead of
  per point), force the situation (`PRESSURE`, `STAMINA_PIN`, `POSITION_TEAM`), or accept a
  larger `d`.
- Add seeds one batch at a time with `ADD=1` (keeps finished seeds, runs only the new ones)
  and re-read the totals after each batch. Only with unchanged code.

## 3. Stop early

`tools/bench_seeds.sh` stops by itself after a seed when:

- it had script errors;
- a `NEED` datapoint was never recorded (the bench can't answer the objective);
- poses are `IDENTICAL` to `BASE` (no gameplay difference; other seeds would match).

Stop it yourself (kill the run, log it as stopped) when:

- after two seeds the number you care about moved less than it moves between seeds of the
  base: more seeds of the same setup won't settle it;
- the answer is already clear either way;
- the objective changed while it ran.

## 4. Recalibrate after a stop

Don't re-run the same thing. Pick one:

- No difference: the change isn't reached. Check the code path fires (a note count), or use a
  forcing option so it does.
- Difference inside noise: denser datapoint, or a forced situation, or drop the question.
- Missing datapoint: add the note, check with a 20 s run, then bench.
- Errors: fix, 20 s run, then bench.

## 5. Log

`bench.sh`, `bench_seeds.sh` and `drive_bench.sh` need `OBJ="..."` and append an entry to
`docs/BENCH_LOG.md`: objective, seeds and reason, datapoints gathered, base result, why it
stopped, wall time. Fill in the **Verdict** line after reading the result (what was decided,
or "inconclusive: <next step>"). Check the log before a new bench: the answer may be there.
`motion_bench.sh` and `pose_review.sh` are not logged.

## 6. Performance benches

Plan and budgets: `docs/PERFORMANCE_PLAN.md`. Sections 1-5 still apply (objective, datapoints,
one seed first, stop early, log).

- **Where the answer lives.** Frame rate, hitches and heat are answered on the phone only (a
  3-10 minute match, then the perf log). The Mac answers "how much work does a tick do" and
  "what did gameplay do". The M5 runs the same work 2-3x faster than the phone and barely
  throttles, so a Mac saving is a prediction until a phone log confirms it.
- **Timing runs are serial.** `tools/bench.sh` or `bench_seeds.sh` with `SERIAL=1`; never compare
  ms per tick from seeds run side by side (inflated 10-15%). Run a timing A/B back to back on
  the same code base and repeat once: single runs vary.
- **Gameplay may move.** A performance refactor, cleanup or native port need not read
  `IDENTICAL` (user's call, 2026-11-25). The bench compares against the version before the
  change and reports what moved: hits, misses, stretched contacts, rally length, faults and
  the animation rules. The change notes say why the new way is better; the user judges feel
  on the phone. Visual-only changes still expect `IDENTICAL`, and when a change is meant to be
  pure speed, `IDENTICAL` is the quickest proof.
- **Budget line.** Every gameplay-touching bench prints serial tick cost and worst tick per
  second against the plan's budgets. A change that raises them says so in its log entry.
- **Human seat.** The all-AI bench never runs your player's planner or touch input. Use the
  scripted human-seat run for those (see the plan's working method), and the phone for feel.
- **Keep the cost table current.** The costs in section 1 (about 30 s per seed) shrink as the
  plan lands. Update them from real runs, and recheck the seed sizing with
  `tools/bench_plan.py`: cheaper seeds make more events affordable, but the 3-seed cap stays
  until the user changes it.
