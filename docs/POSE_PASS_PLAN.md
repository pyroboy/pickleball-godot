# Pose pass: more reach, more natural bodies (audit + plan)

Scope: the 21 contact postures in `data/postures/`, the 22 footwork base poses in
`data/base_poses/`, and the code that blends them (`scripts/player_paddle_posture.gd`,
`held_preparation_reach.gd`, `backhand_reach_profile.gd`, `pixel_card_rig.gd`).

## Important: "reach more" is a gameplay change

Paddle-head position (`paddle_forehand_mul / forward_mul / y_offset`) and commit zones
(`zone_x/y_*`) decide what the player can hit. Body fields (crouch, stance, torso) move the
hand, torso and foot meshes that gameplay scans. So any change in `data/postures` makes
`tools/pose_diff.py` report a difference. The roadmap locks gameplay, so this plan splits
into a **visual-only track** (card layer, keeps `IDENTICAL`) and a **reach track** (a
deliberate gameplay change that needs your OK and its own bench comparison).

## Scorecard

| Area | Rating | Why |
|---|---|---|
| Architecture (data-driven `PostureDefinition`, editor, per-pose wind-up / follow-through) | 9/10 | Easy to tune, versioned, one resource per pose |
| Coverage (high / mid / mid-low / low × FH / forward / BH / wide, + charge, ready) | 8/10 | Full grid; no "stretch" / lunge-reach tier beyond wide |
| IK safety (link-budget fit, elbow poles, floor clearance) | 8/10 | Never hyper-extends; but fits by *shrinking* the target, not by moving the body |
| Overhead | 6/10 | Off-hand points up (good); torso only −10°, no back arch / side bend |
| Reach distance | 4/10 | See below |
| Body engagement (legs, hips, torso) | 3/10 | See below — main cause of the stiff look |
| Pose variety | 3/10 | 12 of 21 poses share the same copy-pasted body block |
| Transitions | 5/10 | Exponential lerp only (12–22 /s): no anticipation, overshoot or settle |

### What is good
- Charge → contact → follow-through phases exist per posture with sensible weight transfer
  (charge back-foot load 0.65, follow-through front-foot load 0.8).
- Wide forehand turns the body (+41° yaw) and widens stance (0.56).
- Backhands rotate the body (−30° to −50°) and use spine curve on `02_backhand`.
- Low poses lower the paddle hard (`y_offset` −0.56…−0.62) with floor clearance.

### What is bad
1. **Arm-only reach.** Arms are 0.35 + 0.35 m. Normal forehand sits at 0.42 m to the side;
   wide forehand 0.87; wide backhand only −0.65. A real player reaches wide by lunging, so
   the body travels too: stance 0.56 and `weight_shift 0.2` on wide poses means the feet and
   hips stay home and the arm does all the work.
2. **Copy-pasted body block.** `stance_width 0.48, front_foot_forward 0.16, weight_shift 0.2,
   hip_yaw −2, right_shoulder_rotation (0,−8,0)` appears on forward, overheads, low, mid-low,
   wide and volley poses. Different shots look like the same stance with the arm moved.
3. **Waist-bend lows, straight legs.** `05_low_forehand` reaches 0.3 m off the ground with
   crouch 0.23 and torso pitch 6°. Real low balls use knee bend (crouch 0.45+), hip hinge
   20–30°, and a long lead step. `18_low_wide_forehand` (crouch 0.48) vs
   `19_low_wide_backhand` (0.305) is also inconsistent.
4. **Upright torso everywhere.** `torso_pitch` is ±0–10° and `spine_curve` is 0 except
   `02_backhand`. No lean toward the ball, no side bend on wide shots.
5. **Forehand has no unit turn.** `00_forehand` body yaw 0 (turn only lives in the wind-up
   keyframe); `01_forward` / `12_volley_ready` are near-identical.
6. **Off-hand is static.** Most poses use `left_hand_offset (−0.15, 0, −0.22)`; it should
   counter-balance (out wide on forehands, on the throat on backhands, up on overheads).
7. **Same timing for everything.** `ft_duration_sweep 0.2`, `charge_duration 0.24/0.32`
   across shot families; a dink and a drive finish the same way.

## Plan

### Track A: visual-only (card layer, `pose_diff` stays IDENTICAL)
Already sketched as step 4 of `VISUAL_PASS_PLAN.md`; extend it with:
- Lean / side-bend on the torso card toward the paddle head when it is beyond 0.6 m.
- Exaggerate crouch and lead-step on cards for low / wide postures.
- Off-hand card counter-balance driven by the posture family.
- Anticipation hold + overshoot/settle on base-pose changes instead of plain lerp.
Check: `tools/bench.sh` + `pose_diff.py` → IDENTICAL.

### Track B: reach + body pass (gameplay change, needs approval)
1. **Shared body presets.** Replace the copy-pasted block with per-family presets
   (neutral, volley, groundstroke, lunge, low-lunge, overhead) so every pose starts from a
   realistic base. Tooling: a small script that rewrites the `.tres` files from a table.
2. **Lunge tier.** Wide / low-wide poses: stance 0.75–0.85, `front_foot_forward` 0.35–0.45,
   `weight_shift` 0.7–0.8, crouch 0.35–0.5, torso pitch 12–20°, side bend 10–15°. Let the
   paddle head reach ~1.05 m (FH) / ~0.9 m (BH) without exceeding the IK budget, because the
   shoulder now moves toward the ball.
3. **Lows:** crouch ≥ 0.45, hip hinge 20–30°, knees over toes; same paddle height.
4. **Forehand unit turn:** body yaw 15–25° on `00_forehand`, distinct volley stance
   (compact, paddle up, `12_volley_ready`).
5. **Overheads:** torso −20°, slight back arch, off-hand pointing, lead foot back.
6. **Off-hand** per family; **timing** per family (dink short sweep, drive long).
7. **Commit zones** grow with reach, kept in step with `HIT_REACH_DISTANCE` (1.15 m) and the
   AI so the CPU gains the same reach as the player.

Verification for Track B: seeded bench before/after; compare contact rate, missed-reach
count and rally length; screenshot each posture with `tools/capture` + the posture editor;
no IK `preparation_reach_limited` spikes in `logs/game.log`.

## Order
Track A first (safe, ships with the visual pass). Track B after you approve relaxing the
gameplay lock for reach, one family at a time (wide → low → forehand/volley → overhead).

## Per-pose log

Rubric, in priority order: planted feet, centre of gravity over the base, hip/torso rotation,
limb angles, then reach. Loop per pose: `tools/pose_review.sh s00` (sheets + metrics, before/after vs HEAD) →
`python3 tools/pose_set.py s00 stage.field=value ...` → re-run review → `tools/bench.sh`.

### 00 Forehand (topspin drive, medium turn, neutral step-in) — done 2026-11-18
| metric | wind-up | contact | finish |
|---|---|---|---|
| CoG back→front (was) | 0.28 (0.58) | 0.55 (0.55) | 0.87 (0.60) |
| hip / shoulder turn ° | 35 / 65 (30 / 49) | 10 / 10 (2 / 2) | 55 / 75 (26 / 36) |
| knees L / R ° | 26 / 83 | 62 / 65 (30 / 30) | 84 / 20 |
| elbow ° · paddle from shoulder | 46 · 0.72 m | 69 · 0.71 m (123 · 0.48 m) | 140 · 0.48 m |
- Feet planted and CoG over the base in every stage. Paddle drops 0.45 m below contact, rises 0.53 m.
- Weight transfer uses `body_position_offset` (wind-up z −0.28, finish (−0.1, 0, 0.2)): `weight_shift`
  only moves the body 0.1 m per unit, too little to move the CoG between the feet.
- Gameplay change: contact moved forward 0.46 → 0.78 and out 0.42 → 0.55 (zone x 0.35–0.75,
  forward 0.78); wind-up/finish offsets compensated so those ends stay put. Bench: 0 script errors.

### 02 Backhand (two-handed drive, rotate through, stay low) — done 2026-11-18
| metric | wind-up | contact | finish |
|---|---|---|---|
| CoG back→front (was) | 0.28 (0.25) | 0.53 (0.56) | 0.91 (0.63) |
| hip / shoulder turn ° | 50 / 80 | 45 / 45 | −25 / −35 past square (0 / 0) |
| hip height m | 0.68 (0.67) | 0.71 | 0.68 (0.78, stood up) |
| elbow ° · paddle from shoulder | 86 · relaxed (10 · locked straight) | 74 · 0.78 m (107 · 0.67 m) | 98 · 0.63 m |
- Paddle drops 0.45 m below contact (was 0.66, near knee height), rises 0.45 m.
- Gameplay change: contact forward 0.42 → 0.67, side −0.53 → −0.55; zone x −0.68…−0.28,
  forward 0.69. Finish end kept in place; wind-up brought closer to the body. Bench: 0 script errors.
- Backhand side mirrors the sideways body offset: finish `body_position_offset` (0.2, 0, 0.08).

### Serves (all 7 styles) — 2026-11-18
Serves are built in code (`drive_serve_motion.gd`); packaged tuning now lives in
`data/serve_tuning.json` (per style and stage, `add`/`set`), applied in
`mobile_serve_pose_store.gd` `packaged_default()` so gameplay picks it up like the approved Flat import.
- Balance: styles 1–6 had both feet behind the body (front foot −0.12, back −0.27), CoG 0.18–0.25 m
  off the base. Now staggered 0.20 / −0.30 (0.50 m deep), CoG 0.38 → 0.69 → 0.89, over base in all stages.
- Wind-up: paddle back to hip height behind the body (0.58 → 0.85 m high, 0.55 m back), body turned
  12° more; pendulum low point stays just before contact. Flat: wind-up raised the same way only.
- Finish: higher toward the target (Topspin/High Soft +0.30 m, Drop Drive/Banana/Screwball +0.15,
  Slice unchanged), weight 0.89 on the front foot.
- Open: ball hand is held out at shoulder height (real serves hold it at waist height); it sets the
  ball release point, so it is a gameplay change and was left alone.
- Per-serve contact points (`serve_delivery_profile.gd` STYLE_COLUMNS, side/forward m): Flat 0.42/0.62,
  Topspin 0.40/0.68, Slice 0.47/0.64, High Soft 0.45/0.57, Drop Drive 0.41/0.68, Banana 0.46/0.64,
  Screwball 0.36/0.64 — from coaching sources (topspin further in front, slice/banana wider, lob later
  near full extension, screwball brushes the inside). Banana finishes across to the left, Screwball out
  to the right. Pushing contact past ~0.70 m forward made the elbow flip at full stretch.
- Flat twist fixed: its imported wind-up held the paddle face rolled ~57° the other way and the
  elbow flared out/up, so the forearm flipped right before contact. Flat now uses the code-built
  wind-up like the other styles (`code_windup` in serve_tuning.json), keeping its approved contact
  and finish; forearm roll step 58° -> 21°, weight 0.38 -> 0.74 -> 0.72.
- Open: drop serves keep a ~14° elbow re-bend at contact.

### Elbow never above the shoulder (all arms) — 2026-11-18
`ArmAnatomy.conditioned_pole` turns the authored elbow toward the plane implied by the wrist/grip
(up to 135°); on backhands that lifted the elbow up to 0.25 m above the shoulder. It now stops
turning once the elbow would rise above max(shoulder + 0.02 m, authored elbow height). Backhand
0.13 -> 0.02 m, Wide Backhand 0.25 -> 0.02 m; forehands and serves unchanged (already low).
Gameplay effect (4927449 vs 0667f47, bench seed 1, 150 s): not visual-only. The arm result feeds the
live arm-reach body offset, so BodyPivot moves up to 61 mm and the paddle up to 66 mm; the ball
differs by at most 1.8 mm and the match outcome is identical (same 11 points, causes and rally length).
`pose_review.sh --from-rest` traces serves from the held pose and flags "elbow UP" steps.
- Next: Wide Backhand needs a whole-pose rework: its wind-up paddle/wrist angle demands an elbow-up
  arm, so the forearm flips (80° without the guard, 125° with it) at the start of the wind-up.

### 11 Wide Backhand — whole-pose rework — 2026-11-18
Rebuilt from the clean two-handed Backhand (02): its grip (-30°), contact paddle face (no extra
signed roll/yaw twist), wind-up/finish face rotations and elbow guides (lowered so the elbow stays
down), keeping the wide contact point (-0.846) and the lunge body; wind-up turn reduced
(hips 85 -> 56°, shoulders 103 -> 76°), paddle drop 0.60 -> 0.45 m.
Swing trace: forearm roll flip 125° -> smooth (max 6°/step where the arm is bent), elbow jump
0.52 -> 0.07 m, elbow never inward, elbow at most 0.02 m above the shoulder. Paddle corner at contact
33° remains (paddle rotation changes direction at contact; reach is not the cause).
Gameplay: contact paddle face changed, so wide backhands may go elsewhere; seed-1 bench has no wide
backhand and stays IDENTICAL.

### 03 Medium / 04 High Overhead — whole-pose rework — 2026-11-18
Real smash: side-on trophy position (elbow ~90°, off-hand up at the ball, knees loaded, weight back),
contact near full extension in front of the hitting shoulder, follow-through down across the body.
- Wind-up: hips/shoulders 23/37° -> 50/75°, weight 0.45 -> 0.29, off-hand up, elbow guides raised
  (were pointing down), trophy elbow Medium 119° / High 87° (was a straight arm, 36°).
- Contact: Medium elbow 121° -> 74° (paddle 0.37 -> 0.64 m from the shoulder), High 92° -> 62°
  (0.70 -> 0.83 m); legs no longer locked (knees 1° -> 20–41°); weight 0.62.
- Finish: paddle down to the opposite hip, weight 0.82, CoG over base.
- Gameplay: contact moved out to the hitting side and forward (Medium 0.08/0.45 -> 0.30/0.80, High
  -0.02/0.45 -> 0.22/0.55; zones moved). Seed-1 bench has no overhead: IDENTICAL, same points.
- High overhead elbow is above the shoulder from trophy through contact: correct for a smash.
