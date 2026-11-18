# Arjostyle Pickleball: Roadmap

## North star

A fast, readable 2.5D pickleball game for iPhone that looks like a hand-crafted pixel-art
action game in a 3D world (in the spirit of Alabaster Dawn), runs at a steady 60 fps on
the phone, and plays exactly as the current game does. Look and feel change; the rules,
physics and timing stay locked until a deliberate "Gameplay v2".

### Pillars

1. **Look:** pixel-art players (cards pinned to the posture skeleton), a 3D court and
   effects, a high readable camera, hue-shifted shadows, no black outlines.
2. **Performance:** 60 fps on the target iPhone in 4-player rallies, measured with
   PerfMonitor on device, never guessed.
3. **Gameplay locked:** shot physics, ball flight, scoring, AI decisions, IK and input
   timing do not change during the visual update. Every phase proves it (see Guardrails).

## Next up (suggested)

1. **Test the pixel cards on a real iPhone** and record a PerfMonitor baseline
   (`python3 tools/perf_report.py`). Nothing on device has been measured yet.
2. **Expose Classic / Pixel in the Settings panel** (`video.character_style`, already in
   `scripts/ui/settings.gd`), so playtesters can compare.
3. **Far-court card tier:** bake a 20 degree, half-size card set and pick the tier by distance
   to the camera (far players currently reuse the near set).

## Phases

Status: done, in progress, next, later.

### Phase 0: Performance baseline (in progress)
- [x] PerfMonitor autoload, spike log, F3 graph, `tools/perf_report.py`
- [x] Seeded benchmark + pose trace (`tools/bench.sh`, `tools/pose_diff.py`)
- [x] Physics catch-up cap, IK once per player per tick, READY recheck at 10 Hz, AI re-plan cap
- [ ] On-device iPhone baseline (fps, frame-time spikes) in 4-player rallies
- [ ] Decide on a 30 Hz physics / AI tick. It changes ball simulation, so treat it as a
      gameplay change: separate branch, bench comparison, playtest.

### Phase 1: Pixel-card players (prototype done, default on)
- [x] Card rig on the existing joints: `scripts/graphics/pixel_card_rig.gd`
- [x] Card atlases at the game's real limb lengths: `assets/pixel_cards/`
- [x] Fog-free card shader, tonemap-compensated colours: `shaders/pixel_card.gdshader`
- [x] Gameplay identical with cards on and off (seeded bench, pose diff)
- [ ] Classic / Pixel toggle in the Settings UI
- [ ] Far-court card tier (20 degrees, half size)
- [ ] Hand states (open / grip / reach) from the articulated hand mode
- [ ] Joint seams (elbow, knee) and draw-order polish
- [ ] iPhone check

### Phase 2: Pixel viewport and camera (next)
- [ ] Render 3D into a 1/3-resolution SubViewport with nearest upscale (one pixel grid
      for court, players and effects); UI stays full resolution on top
- [ ] Verify portrait framing and ball-on-screen logic with the SubViewport size
- [ ] Optional: steeper 3/4 camera as an A/B option (keep the current camera by default)

### Phase 3: Art pass (later)
- [ ] Final hand-painted cards over the generated ones (5 drawn views + mirrors)
- [ ] Team palette-swap shader for skins and cosmetics
- [ ] Court / arena textures in pixel style, baked lighting

### Phase 4: Effects and feel (later)
- [ ] Effects sprite sheet: impact burst, spark ring, bounce, dust, swing arc, speed lines,
      landing marker, smash flash, out stamp, ball trails (pooled through `fx_pool.gd`)
- [ ] Trajectory restyle: serve preview (gold), incoming guide (red), aim arc (cyan)
- [ ] Slow-mo: lens depth of field focused on the hitter, opponent soft-focused,
      Kawase blur on a half-res copy; restyles the existing aim-focus slow-mo
- [ ] Hit-stop and camera-shake tiers, layered hit sounds

### Phase 5: UI (later)
- [ ] Pixel UI kit (5x7 font, bevelled panels without black outlines)
- [ ] Compact score pill, one-line coach toast, pixel joystick, HIT and shot wheel
- [ ] Same inputs and touch targets as today

### Phase 6: Ship and retire classic bodies (later)
- [ ] On-device performance pass against the Phase 0 baseline
- [ ] Remove the Classic option only after gameplay stops reading body meshes
      (foot mesh bounds in `player_nvz_state.gd`, `match_grounded_reach.gd`,
      `between_pose_admission.gd`, `fast_point_transition.gd`; hand / torso meshes in
      the between-point and surface-contact code)
- [ ] Release build

### Later: Gameplay v2 (separate plan)
AI difficulty tiers, more shot types (lob, Erne, ATP), practice drills, cosmetics.

## Guardrails (every phase)

- **Gameplay must stay identical.** Run the seeded bench with and without the change and
  diff the poses; the result must be `IDENTICAL`:
  ```bash
  PICKLEBALL_CLASSIC_BODIES=1 tools/bench.sh base 30 1
  tools/bench.sh new 30 1
  python3 tools/pose_diff.py logs/bench_base.pose.jsonl logs/bench_new.pose.jsonl
  ```
- **Never add visuals under a player's `BodyPivot`.** Gameplay scans every mesh there
  (surface contacts, geometry certificates); the first card prototype changed play this way.
- Hide classic meshes from the camera; do not delete them while gameplay reads them.
- Measure performance on device before and after; record it here.

## References

- Design proposal (31-page PDF) and all generated pixel art, UI, effects and the art
  generator scripts: branch `archive/main-wip-2026-11`, folder `docs/`
  (`docs/PICKLEBALL_2.5D_PROPOSAL.pdf`, `docs/pixel_art_test/`).
