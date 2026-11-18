# All stroke poses

All 21 resources in `data/postures/` now have body/paddle settings for Wind-up, Contact and Follow-through. Forehand remains the reference. The other 20 were tuned on 2026-09-30.

## Motion profiles

| Poses | Motion |
| --- | --- |
| Forehand, Backhand, wide variants | Load behind the hitting side; meet the ball in front; finish upward across the body. |
| Low and mid-low side/wide variants | Bend the knees, use an inverted paddle with an open face, prepare compactly, then lift toward the target. |
| Forward, Volley Ready | Small preparation and a short forward block; avoid a large backswing. |
| Low Forward, Mid-Low Forward | Centered stance and a compact underhand lift. |
| Medium and High Overhead | Prepare above/behind the shoulder; raise the support hand to track the ball; contact in front and finish downward. |
| Charge Forehand, Charge Backhand | Compact side/back preparation. These have no contact area and cannot be selected as receiving strokes. |
| Ready | Centered paddle in front, neutral weight, knees slightly bent and support hand near the paddle neck. No receiving contact area. |

Backhand-family poses use the **left paddle hand** and release the right support hand, following the game's requested hand-switching design. Forehand uses the right paddle hand and releases the left. This is a custom game convention; the pose editor can change the paddle hand and support mode.

Feet remain planted throughout authored motion. Wind-up loads the back foot; contact and finish transfer weight forward. Hips, torso, head, elbow poles and support-hand offsets are authored at each stage. Overhead contact planes were moved closer to the body so the grip remains within arm reach.

Open **E / Q**, select a stroke, and choose **Wind-up / Contact / Follow-through**. Body and Paddle controls edit that stage. Scrub or Play swing shows the same sampler used in gameplay. Save pose persists all three stages.

## Validation

- `test_all_stroke_poses.gd`: all 21 resources, both court directions, sampled paddle and support-arm reach, floor clearance, planted feet, editor stage alignment and serialization.
- `test_all_stroke_contacts.gd`: all 18 receiving poses at 30%, 65% and 100% charge using real Space polling and gameplay hits.
- Existing forehand, incoming spin/speed, UI, serve and AI rally checks remain separate regression tests.

Motion reference: [USA Pickleball basic strokes](https://usapickleball.org/pickleball-skills/level-one/pickleball-basic-terms/). These are procedural game animations, with editable keyframes rather than captured athlete motion.
