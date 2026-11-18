# Visual pass: pixel look, camera, poses, scoring, effects, HUD (performance first)

## Status (2026-11-18)
Branch `visual-pass`. **Step 0 done**; next is **Step 1 (camera)**. The phone has the
f5c5149 build (installed from a clean worktree, without uncommitted pose edits).

Step 0 results:
- Phone baseline: `logs/phone/baseline_perf.jsonl` (32 min, main @ 08667b1): median and
  worst-5% 60 fps, 56 freezes >50 ms (31 in-play shot planner `human.update`, 19 between
  points). After the gates below (`logs/phone/step0_perf.jsonl`, 103 s): 0 between-point
  freezes; serve/in-play freezes need a longer session to judge.
- Pixel cards skip invisible 3D hand work (user OK'd small arm/paddle drift, rallies match
  over 3 seeds): cup-pose search (eb78902), sleeve clearance + carried-cup continuity +
  receiver exit sleeve search (ff24266). Bench worst between-point tick 28.6 -> ~8 ms.
- Fixed: startup `_hands` null (6624c04); rally freeze "Contact simulation paused" on an
  over-budget wrist under pixel cards (b7bff84, 1 in 66 runs before).
- Faster between points (f47d091): walk 2.4 m/s, run from 1.2 m, carry 3.4 m/s, AI serve
  wait 0.8 s (Step 6 item, done early). Between points 8.2 -> ~7.1 s. Pass toss unchanged
  (a flatter toss caused missed catches).
- Skipped: per-frame UI label rewrites (all UI ~0.25 ms/frame on phone, not worth it).
- Debug data (all text, for Claude): `FRAME_LOG=1 tools/bench.sh` frame log with drawn
  positions + events; `tools/court_trace.py` (top-down CSV, position checks, event
  timeline); `tools/motion_report.py`; always-on jitter counts + burst snapshots in
  `perf.jsonl`, shown by `tools/perf_report.py` (f5c5149).

Open items found in Step 0:
- In-play freezes in the human shot planner (`human.update` / `planner.*`, ~70-100 ms).
- Partners walk through each other between points (gap down to 0.23 m).
- Change of ends walk takes ~13 s (Step 8 replaces it with a 3 s banner + fade).
- Camera stalls on ~22% of frames outside rallies (30 Hz camera) -> Step 1.
- The serve path still blocks on "infeasible_actual_arm" (never seen firing).
- Another session ("Game poses improvement and audit") edits poses in this same checkout
  and commits to `visual-pass` (6eab862, 1ef1df5).

## Context
The PDF "Pickleball 2.5D proposal" (~/Downloads) defines the 2.5D pixel look. Pixel cards,
perf tooling and 30 Hz physics + interpolation are done (main @ 08667b1). The user wants the
rest built performance-first, plus fixes to scoring clarity, stiff poses and camera feel, and
an explanation/removal of the "lag behind the baseline". Audits (fx/HUD, scoring, poses,
camera) found: camera updates only at 30 Hz (jitter), ~1000 projections/tick in portrait
framing, no player shadows, card view popping, identical doubles partners, raw rule-name
fault text, up to 5 score displays, a possible stuck "Point settlement pending", hit-stop
that slows physics, per-frame HUD label rewrites.

## Ground rules
- Gameplay locked: shot physics, ball flight, scoring outcomes, AI, input timing, and the
  skeleton/pivots gameplay reads. Pose polish is applied on the **card layer only**
  (pixel_card_rig placement), never to the skeleton, so `pose_diff.py` stays IDENTICAL.
- Target steady 60 fps on iPhone 15 Pro; physics 30 Hz.
- Branch `visual-pass`, one commit per step. After each step: install, user plays ~2 min
  doubles, I pull `Documents/perf.jsonl` and report vs the Step 0 baseline.

## Decisions (from Q&A)
- 3D at fixed 1/2 res, nearest look, no Settings row; pixel cards only (no Classic toggle).
- Subtle grade + vignette; blob shadows only; remove CourtFill light + fog, unshaded court,
  lines, posts; flat gradient sky; net = one pixel-texture quad; big logos only.
- Ball: keep halo, add height line, smooth (interpolated) trail. Pixel-styled 3D paddle.
- Camera: per-frame update from interpolated targets; 2-3 fixed zoom steps (serve, rally,
  wide) with eased switches; pixel snapping; shake by shot type (none dink, light drive,
  strong smash), whole-pixel offsets, no roll. Cinematics: serve intro, point won,
  change ends (3 s banner), match point / win.
- Effects: landing ring + chevrons, kitchen glow, swing arc tinted by shot type, footwork
  dust, shot label pop (DINK / DRIVE / LOB / SMASH), hit-stop visual-only.
- Poses (card layer): short cross-fades, bigger split step, anticipation hold, contact pop,
  pose exaggeration; one view cell per body, joint seam overlap, draw order by camera side,
  re-bake cards at the real camera angle; blob shadows under players; partner/opponent accents.
- Scoring: clear concise fault text; corner pill + one banner (score call bubble only before
  the serve); physical pickup stays default, AI serve wait 1.5 s -> 0.8 s; fix the stuck
  settlement state, remove unused rule paths, add rule tests.
- HUD: corner score pill, round icon buttons, one-line state text; aim focus keeps blur.
- ID cue: small pixel marker under the human only.
- Defaults without an answer: hit-stop visual only; lighting flat; net pixel quad.

## Steps

### 0. Baseline, audit, cheap wins
- Phone baseline of current main. `--frame-log` in `scripts/debug/perf_monitor.gd` (per frame:
  state, player positions, scope costs) to find work running behind the baseline / in WAITING
  with no job; gate it (candidates: `carried_cup_continuity.gd`, `between_point_arm_path.gd`,
  `live_ready_clearance.gd`, `footwork_motion_state.gd` lob path, `player_debug_visual.gd`
  release flight trace).
- Startup SCRIPT ERRORs: `live_transition_arm_reach.gd:80` null `_hands` guard (also fixes :217).
- Per-frame UI rewrites only on change: `scoreboard_ui.gd:36-40`, `hud.gd:523-572`,
  `mobile_controls.gd:106-138`, `court_callouts.gd:81-92`; `pixel_card_rig.gd` cull mask
  once, no 0.25 s `find_children`.

### 1. Camera
- Move `camera_rig.update` from `game._physics_process` (game.gd:804) to `_process`, reading
  `get_global_transform_interpolated()` for player/ball targets.
- Replace `_apply_portrait_action_framing` (camera_rig.gd:629-671) with 2-3 precomputed
  framings (reuse `_fit_portrait_at_distance`) and an eased switch.
- Pixel snap after framing; shake rework in `camera_shake.gd` + `fx/hit_feedback.gd`
  (shot type, whole-pixel, no roll); ease `_keep_ball_visible` instead of snapping.

### 2. Pixel rendering + lighting
- Root `scaling_3d_scale = 0.5` + `scripts/graphics/pixel_post.gd` CanvasLayer below UI with
  `shaders/pixel_post.gdshader` (2x2 block-centre sampling = exact nearest; subtle grade,
  vignette). Lighting/environment changes in `game.gd:287-341` and mirrored in
  `aim_presentation_prewarm.gd:124-156`. Court/lines (merge 8 quads)/posts unshaded; net quad
  (`net.gd`, collision untouched); drop small Label3Ds (`court_arena_visual.gd`,
  `court_branding.gd`).

### 3. Players: cards, shadows, colours
- One ArrayMesh + one material per player (`pixel_card_rig.gd`), one body view cell for all
  parts, joint overlap, draw order bias by camera side; re-bake atlases at the measured camera
  elevation. The tool that baked `assets/pixel_cards/` (44 deg, 16 views) is not in the repo,
  so this step adds `tools/bake_pixel_cards.gd` (headless render of each part at N views ->
  atlas + cards_meta.json), committed for future bakes; accent colours per actor via
  shader uniform (partner, opponent 1/2). Blob shadows for players via `fx/ground_shadows.gd`.
- Pixel-styled paddle material; human-only pixel marker (`ui/doubles_identity_cues.gd`).

### 4. Card-layer pose polish
- In `pixel_card_rig.gd` placement only: cross-fade card joint positions on base-pose changes
  (0.08-0.15 s), split-step hop/crouch exaggeration, anticipation hold before contact,
  contact squash/stretch pop, wind-up/follow-through exaggeration. Driven by existing state
  (`pose_controller.gd` base state, `player_hitting.gd` swing phases, `split_step_timing.gd`).

### 5. Ball readability + effects (pooled, `fx/fx_pool.gd`, no GPU particles)
- Interpolated ball trail (`fx/ball_trail.gd`), height line, keep halo.
- Landing ring + chevrons from `player_debug_visual.gd` `_last_flight.first_bounce`.
- Kitchen glow: court shader uniform per side from `player_nvz_state.gd`.
- Swing arc (paddle-head ribbon, tinted by shot), footwork dust, shot label pop.
- Hit-stop visual-only: drop `Engine.time_scale` in `time_scale_manager.gd` path; freeze card
  placement + camera ~50 ms.

### 6. Scoring clarity + flow
- Fault copy table (rally_scorer reasons -> short text + who): e.g. "Into the net",
  "Out", "Bounced twice", "Volley in the kitchen", "Stepped into the kitchen" (MOMENTUM),
  "Must let it bounce" (TWO_BOUNCE_RULE), "Hit twice", "Hit the player", "Serve short",
  "Wrong service court", "Foot fault", "Touched the net", "Crossed the net", "Hit the post".
  Detail strings use You / Partner / Opponent N, never Blue/Red.
- One banner per point (`scoreboard_ui.gd:67-83`), score call bubble only while waiting
  to serve; remove duplicate surfaces.
- AI serve wait 1.5 s -> 0.8 s (`game.gd:810-817`).
- Stuck settlement: `game_serve.gd:319-321` position fault before `begin_service_attempt`;
  resolve/retry in `game.gd:1324-1327`. Remove unused `position_claim`,
  `correct_completed_wrong_receiver`, `completed_position_error`, `_format_scoreboard`,
  `_check_rally` status spam; single source for game target (ledger).
- Fix doubles wording ("SINGLES / FIRST TO 11", end panel `ui/practice_panel.gd:146-150`).
- Rule tests (repo has no test suite yet): new headless `tools/rule_tests.gd` driving
  `doubles_match_state.gd` directly — side-out, server 1/2 rotation, 0-0-2 start, end change
  at 6, win by 2; run with `godot --headless --path . -s tools/rule_tests.gd`.

### 7. Corner HUD
- `scripts/ui/hud.gd` + `hud_chrome.gd`: corner pill (score-score-server), round icons for
  Skip/Guide/Pause, one-line state text; shrink `mobile_layout.gd` top reserve (320*s); keep
  `_score_panel` / `_status_panel` names (read by `incoming_movement_guide.gd:432`).

### 8. Cinematics
- Serve intro push-in, point-won hold (~1 s with banner), change-ends 3 s banner + fade
  (finish the far-end flip already in `camera_rig._apply_end_flip`), match point / win
  push-in + pixel burst. Built on `between_point_camera.gd`; skippable; no gameplay waits
  longer than today except the 3 s change-ends cut.

### 9. Finish
- 3-seed bench, captures, phone session, merge `visual-pass` -> main, push on request.

## Verification (every step)
- `tools/bench.sh <name> 150 <seed>`: no script errors (Step 0 should reach 0).
- `python3 tools/pose_diff.py` vs previous step -> IDENTICAL for all steps except: Step 5
  hit-stop (old one slowed physics) and Step 6 AI serve wait — for those compare
  points/fault reasons over 3 seeds.
- `python3 tools/perf_report.py` per step; portrait captures via
  `--capture-at=... --capture-out=... [--capture-hide-ui]` at 1012x2194 reviewed before install.
- Phone: install, user plays ~2 min doubles, pull `Documents/perf.jsonl`; report fps,
  worst-5%, spikes by state vs Step 0.
- Step 6: `tools/rule_tests.gd` passes headless.
