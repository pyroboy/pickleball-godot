# Reel tools: planned cinematic camera

Tools for a cinematic reel of one AI rally: the camera knows where the ball and players are
going, moves on eased curves, and the game's speed ramps (down to bullet time). Visual only:
nothing here changes the game's own files. First reel: "Barangay Smash", seed 4, 2026-11-24.

| Tool | What it does |
|---|---|
| `tools/track_match.gd` | Plays the match at normal speed; writes every frame's tick, ball and players (as drawn) plus every hit to a track file. |
| `tools/cine.gd` | Films the rally: shot list, eased camera moves, framing, speed curve and bullet time, with photo mode's lens blur. Writes its own track and a shot log. |
| `tools/reel_cut.py` | Cuts the shots from the movie by the shot log, adds a fade-in, the wordmark and the sound. |

## How it works

- **Game clock G.** Godot's `time_scale` keeps 30 physics ticks a second and shrinks each tick's
  step, so slow motion is still one tick per frame. G advances by the time scale every tick; every
  shot and the speed curve are functions of G.
- **Planning from the future.** `cine.gd --plan=<track>` reads an earlier run's track, so tracking
  leads the ball (gaussian-smoothed over ticks ahead) and moves ease on screen time (`uf()`).
- **Same speed curve, same match.** Slow motion changes the physics a little, so the plan must
  come from a run with the same speed curve. The speed curve is a fixed function of G and bullet
  time starts at a fixed G (`BULLET_G`), so a second run replays the first exactly (ball within
  1 mm in every shot; the shot log's `err` column shows it).
- **A film camera.** The game's own camera keeps running untouched: between points the game
  tests what that camera can see (`between_point_controller.gd`, lines ~368 and ~1110), so moving
  it changes the next serve. `cine.gd` films with a copy.
- **Framing.** A shot can give `subject` with `sx`/`sy`: the camera turns so that point sits
  there on screen (the shot log's `scr` column confirms it).
- **Hidden while filming:** HUD layers, shot-name callouts (billboard labels), identity cues,
  reach rings, the ball readability cue, smash flashes, and the ball trail in slow shots (it
  piles into a blob).

## Run

Godot is not on PATH (see `tools/bench.sh` for the binary); `G` below is that binary.

```bash
# 1. Plan: normal-speed track of the match
"$G" --path . --resolution 1080x1920 --fixed-fps 30 -s tools/track_match.gd -- \
  --mobile-runtime --autoplay --doubles --seed=4 --track-out=/tmp/reel/track1.jsonl --track-ticks=4500
# 2. Pass 2: the slowed rally (no movie), planned from step 1; writes the slowed track
"$G" --path . --resolution 1080x1920 --fixed-fps 30 -s tools/cine.gd -- \
  --mobile-runtime --autoplay --doubles --seed=4 --plan=/tmp/reel/track1.jsonl \
  --track-out=/tmp/reel/p2/track.jsonl --shots-out=/tmp/reel/p2/shots.jsonl
# 3. Film, planned from pass 2 (same speed curve, so it replays it exactly)
"$G" --path . --resolution 1080x1920 --write-movie /tmp/reel/p3/match.avi --fixed-fps 30 -s tools/cine.gd -- \
  --mobile-runtime --autoplay --doubles --seed=4 --plan=/tmp/reel/p2/track.jsonl \
  --track-out=/tmp/reel/p3/track.jsonl --shots-out=/tmp/reel/p3/shots.jsonl
# 4. Cut (offset 0 when the movie has one more frame than the last logged frame)
python3 tools/reel_cut.py /tmp/reel/p3 0 reel.mp4 434
```

Each run takes 2 to 4 minutes on the Mac. Camera-only changes (positions, lenses, framing, shot
ranges) need only step 3 again with the same plan; changing the speed curve or `BULLET_G` needs
step 2 again. The project's `window_width_override` / `window_height_override` (540x960) cap the
movie size: for 1080x1920, run from a copy with those set to 1080 and 1920.

## Known limits

- The shot list is written for the seed-4 rally (its ticks are constants in `cine.gd`); another
  rally needs new ranges. The lob/smash/counter/point ticks are read from the plan.
- Exact replays were proven in a scratch copy where two wall-clock reads in gameplay used game time
  instead: `game_serve.gd` `tick_presents_waiting()` (120 ms) and `match_erne_action.gd` AI retry
  (`Time.get_ticks_msec()`). Heavy rendering makes frames slower than real time, so with the
  originals a filmed run may drift from its plan. Those are gameplay files: fix them deliberately.
- In bullet time the ball sits about a ball-width off the paddle at contact (the planned shot wins
  over strict paddle geometry).
- Player outfits differ between runs; the match itself is identical.
