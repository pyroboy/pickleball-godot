# Authoring the forehand

Open the v2 editor with **E** or **Q**, then choose **Forehand**.

1. Select **Wind-up**, **Contact**, or **Follow-through** below the court. These are the three editable keyframes.
2. Choose **Body** to edit feet, knees, weight shift, hips, torso, head and arm controls for that stage.
3. Choose **Paddle position & angle** to edit the paddle head and face angle for that stage. Drag the court arrows to move the selected paddle head.
4. Drag **Scrub swing** to inspect movement between the keyframes, or use **Play swing** at half speed. Scrubbing previews motion; it does not change saved keyframes.
5. Use **Save pose** to keep changes, or **Revert pose** to restore the last saved version, including all three keyframes.

Paddle grip handedness is shared by the stroke. The support-hand mode can vary by keyframe. Position values use forehand-side X, up Y, and net-facing forward Z; negative forward is behind the body.

The reference forehand uses a compact backswing behind the hitting side, contact in front, then an upward finish across the body. The left foot leads, the support hand releases, and the hips and torso turn through the shot while the head stays directed toward contact. A blended curve passes through all three paddle positions. Gameplay uses the same keyframe sampler for its charge and release; after the finish it blends back to ready.

**Wind-up** and **Follow-through** settings sections expose relative paddle offsets, timing and curve controls. Their body rotation/load controls update the matching body keyframe. Contact-area settings always belong to Contact.

Forehand is the reference stroke. All remaining poses now have tuned body and paddle keyframes using the same editing workflow; see [the stroke profiles](ALL_STROKE_POSES.md).

## Files

- `data/postures/00_forehand.tres`: the authored forehand and body keyframes.
- `scripts/stroke_body_keyframe.gd`: optional wind-up and follow-through body values.
- `scripts/stroke_swing_path.gd`: shared procedural position/angle interpolation.
- `scripts/stroke_body_pose.gd`: visible torso, hips, shoulders and head transforms.
- `scripts/posture_editor_v2.gd`: stage selection and editing.

Motion reference: [USA Pickleball basic strokes](https://usapickleball.org/pickleball-skills/level-one/pickleball-basic-terms/) and [beginner fundamentals](https://usapickleball.org/pickleball-skills/level-one/pickleball-fundamentals-for-beginners/). This is a tunable procedural reference, not a captured athlete animation.
