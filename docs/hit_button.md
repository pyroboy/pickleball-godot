# Hit Button Pipeline

Authoritative reference for the reaction HIT button, posture commit system, and the grading loop that runs from opponent paddle contact all the way to the ball reaching the committed ghost.

## Pipeline Overview

```
opponent paddle hit
        │
        ▼
ball physics (ball.gd) — is_in_play latches, bounced signal fires on floor contact
        │
        ▼
debug_visual trajectory arc — predicted arc from ball state, sampled as Vector3 points
        │
        ▼
player_paddle_posture.set_trajectory_points(arc)
        │
        ├──► green pool — ghosts within 0.45 m of any arc sample glow green
        │
        ├──► FIRST commit — ghost closest to expected contact point (center bias 0.20 m)
        │
        ├──► TRACE recommit — ghost changes when player moves or current zone drifts off arc
        │
        ├──► LOCK — once BLUE latches (one-shot), no more recommits
        │
        ▼
color stages (TTC-driven)
    PINK    ttc > 0.8 s                       — early prediction
    PURPLE  0.2 s < ttc <= 0.8 s               — committed, closing
    BLUE    ttc < 0.2 s  OR  ball_to_ghost < 0.35 m   — one-shot latch, held 0.35 s
        │
        ▼
incoming_stage_changed(stage, posture, commit_dist, ball_to_ghost, ttc)   — emitted every physics frame
        │
        ▼
ReactionHitButton (game.gd routes the signal)
    ring radius = lerp(RING_RADIUS_MAX, BUTTON_RADIUS, 1 - ttc/TTC_MAX)
    perfect window: stage==2  OR  ttc < 0.15  OR  ring within ±14 px of button edge
        │
        ▼
player swings (manual) OR auto_fire_requested (if flag enabled)
        │
        ▼
game.gd:_perform_player_swing — if reaction_button.is_perfect(), charge_ratio = 1.0
        │
        ▼
posture grade — fires once per ball when BLUE first latches
    grade uses _closest_ball2ghost (tracked minimum across approach)
    grade_flashed signal → ReactionHitButton.show_grade(grade) → HUD flash
```

## Invariants

These hold across the lifetime of a single incoming ball (from `_ball_incoming = true` to `reset_incoming_highlight()`):

1. **Exactly one `[SCORE]` line per ball.** Guarded by `_scored_this_ball`.
2. **Stage is monotonic** PINK → PURPLE → BLUE. Once BLUE latches (`_blue_latched = true`), stage cannot go back.
3. **Ring radius is a pure function of TTC** on the reaction button. Distance does not directly drive the ring; only TTC does.
4. **BLUE ⇒ scored.** The same frame that sets `_blue_latched` also updates `_closest_ball2ghost` and fires the grade (one shot).
5. **Ghost is frozen during BLUE.** When `_blue_latched` is true, `_ghost_frozen_at` is the lerp target; the ghost no longer tracks.
6. **Signal emits every frame while committed** (not only on stage change), so the ring collapses smoothly.
7. **Scoring is independent of `ball_in_front`.** Stretched / behind-the-body contacts still grade.

## Key Functions

| File | Function | Purpose |
|---|---|---|
| `scripts/player_paddle_posture.gd` | `set_trajectory_points(points)` | Arc feed from debug_visual. |
| `scripts/player_paddle_posture.gd` | `_find_closest_trajectory_point()` | Arc point nearest player, hittable height filter 0.08–1.8 m. |
| `scripts/player_paddle_posture.gd` | `_find_closest_ghost_to_point(ref)` | FIRST/TRACE commit picker. Center bias 0.20 m when lateral < 0.4 m. Skips CHARGE postures. |
| `scripts/player_paddle_posture.gd` | `_is_ghost_near_trajectory(posture)` | Green pool membership test, 0.45 m radius. |
| `scripts/player_paddle_posture.gd` | `_compute_ttc(ball, ghost_world)` | Time-to-contact: walk trajectory arc → arc-length/ball-speed; falls back to `dist / ball_speed`. Clamped [0, 3]. |
| `scripts/player_paddle_posture.gd` | committed-ghost block in `_process_ghosts` (~1009) | Phase A measure → B stage → C emit → D score → E recommit. |
| `scripts/player_paddle_posture.gd` | `reset_incoming_highlight()` | Clears all per-ball state; called when ball goes out of play / bounces twice / is hit. |
| `scripts/reaction_hit_button.gd` | `update_from_stage(stage, posture, commit_dist, ball2ghost, ttc)` | Drives ring + perfect window. |
| `scripts/reaction_hit_button.gd` | `is_perfect()` | True when `stage == 2` OR `ttc < 0.15` OR ring at button edge. |
| `scripts/reaction_hit_button.gd` | `show_grade(grade)` | Flashes the grade label for 0.6 s after contact. |
| `scripts/game.gd` | `_on_player_stage_changed(...)` | Forwards posture signal to the reaction button, toggles slow-mo on EASY. |

## Tuning Constants

| Name | File | Value | Intent | Safe range |
|---|---|---|---|---|
| `GHOST_CONTACT_MAX_DIST` | `player_paddle_posture.gd` | 3.0 m | Commit distance ceiling | 2.5–4.0 |
| `ZONE_EXIT_MARGIN` | `player_paddle_posture.gd` | 0.3 m | Hysteresis for TRACE recommit | 0.2–0.5 |
| `BLUE_HOLD_DURATION` | `player_paddle_posture.gd` | 0.35 s | How long BLUE stays latched | 0.25–0.6 |
| `INCOMING_GLOW_DURATION` | `player_paddle_posture.gd` | 1.5 s | Max green pool lifetime | 1.0–2.5 |
| `INCOMING_FADE_DURATION` | `player_paddle_posture.gd` | 0.6 s | Green → yellow fade | 0.3–1.0 |
| Green radius | `player_paddle_posture.gd` (`_is_ghost_near_trajectory`) | 0.45 m | Ghost-to-arc membership | 0.35–0.6 |
| Center bias | `player_paddle_posture.gd` (`_find_closest_ghost_to_point`) | 0.20 m | Favors FORWARD / VOLLEY_READY for near-center contacts | 0.10–0.35 |
| PINK TTC threshold | `player_paddle_posture.gd` (stage decision) | 0.8 s | Early prediction window | 0.6–1.2 |
| BLUE TTC threshold | `player_paddle_posture.gd` (stage decision) | 0.2 s | Time-based BLUE latch | 0.1–0.35 |
| BLUE distance fallback | `player_paddle_posture.gd` (stage decision) | 0.35 m | Physical BLUE latch safety net | 0.3–0.5 |
| Grade PERFECT | `player_paddle_posture.gd` | < 0.25 m | Perfect grade | — |
| Grade GREAT | `player_paddle_posture.gd` | < 0.40 m | Great grade | — |
| Grade GOOD | `player_paddle_posture.gd` | < 0.60 m | Good grade | — |
| Grade OK | `player_paddle_posture.gd` | < 0.80 m | OK grade | — |
| `BUTTON_RADIUS` | `reaction_hit_button.gd` | 60 px | Inner button radius | — |
| `RING_RADIUS_MAX` | `reaction_hit_button.gd` | 160 px | Outer ring max radius | — |
| `PERFECT_TOLERANCE` | `reaction_hit_button.gd` | 14 px | Ring-edge perfect window width | 8–20 |
| `TTC_MAX` | `reaction_hit_button.gd` | 1.2 s | Ring starts closing at this TTC | 0.8–1.8 |
| `TTC_PERFECT` | `reaction_hit_button.gd` | 0.15 s | TTC-based perfect window | 0.08–0.25 |
| `auto_fire_on_perfect` | `reaction_hit_button.gd` | false | Auto-swing on perfect | — |

## Debug Log Tags

| Tag | Source | When |
|---|---|---|
| `[TRACK P#]` | posture | Incoming detected (ball entered ~5 m radius). |
| `[COMMIT P#]` | posture | FIRST / TRACE posture picked. |
| `[GREEN P#]` | posture | New ghost entered the green pool. |
| `[COLOR P#]` | posture | Stage transition (PINK→PURPLE→BLUE). |
| `[ZONE_EXIT P#]` | posture | Zone-exit TRACE recommit. |
| `[SCORE P#]` | posture | Grade + per-ball counters. Exactly one per ball. |
| `[TRAJ P#]` | posture | Full arc trace + per-ghost distances. Diagnostic. |
| `[MOVE P#]` | posture | Player moved 0.5 m since last log. |
| `[TTC P#]` | posture | TTC estimator debug (off by default). |
| `[REACT]` | game.gd | Perfect-window swing. |

## How to Test

1. Launch the game. Press `4` to fire a practice ball at PlayerLeft (Blue).
2. Watch the console — expected per ball:
   ```
   [TRACK P0] ...
   [COMMIT P0] FIRST <posture>
   [GREEN P0] +<posture> ...
   [COLOR P0] PINK  <posture> ... ttc=1.xx
   [COLOR P0] PURPLE <posture> ... ttc=0.xx
   [COLOR P0] BLUE  <posture> ... ttc=0.00
   [SCORE P0] <GRADE> <posture> closest=0.xx commits=N poses=M greens=L
   ```
3. The HIT button ring should close smoothly during the ball's flight. Lobs should take ~1.2 s to close; fast drives should close in under 0.5 s.
4. On BLUE latch, the committed ghost should visibly stop moving. The HIT button should flash the grade (PERFECT / GREAT / GOOD / OK / MISS) for ~0.6 s.
5. Swinging during the green perfect window should override to full power and flash the button white (`[REACT]` log line).
6. Cycle AI difficulty with `X` — slow-mo engagement on PINK only runs in EASY mode.
7. Launch several practice balls at stretched positions (ball crossing behind or deep wide) to confirm scoring still fires; historical bug was that these silently skipped the grade.

## Hotkeys (recap)

| Key | Action |
|---|---|
| `4` | Launch a practice ball at the human player. |
| `X` | Cycle AI difficulty (EASY / MEDIUM / HARD). |
| `Z` | Toggle 3D debug visuals (ghosts, trajectory arcs, zones). |
| `P` | Cycle cameras. |
