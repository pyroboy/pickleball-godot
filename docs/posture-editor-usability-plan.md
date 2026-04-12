# Posture Editor Usability Improvement Plan

## Goal

Make the posture editor feel like a pose tool instead of a debug panel:

- fewer visible controls by default
- direct manipulation in the 3D viewport
- clear separation between selecting a posture, previewing a pose, and previewing a swing
- fast access to the controls that matter most

---

## Why it feels confusing today

### 1. Selection, preview, and freeze are mixed together

Right now, selecting a posture immediately triggers the pose and freezes the game. That means "I clicked a posture to inspect it" and "I activated preview mode" are the same action. This makes the editor feel unpredictable.

### 2. "Trigger Pose", "Release Pose", and "Play Transition" are not a clear mental model

The current controls are action labels, but they do not explain the editor state:

- is the player frozen or live?
- is the current pose static or animated?
- does changing the selection affect playback?

The result is that the user has to remember hidden state instead of reading the UI.

### 3. Transition preview is likely using the wrong posture IDs

The current transition setup hardcodes posture IDs that do not match the enum names:

- `0` is `FOREHAND`, not `READY`
- `17` is `MID_LOW_WIDE_BACKHAND`, not `CHARGE_FOREHAND`
- `[18, 19, 20]` are `LOW_WIDE_FOREHAND`, `LOW_WIDE_BACKHAND`, and `READY`

So even the transition button is likely previewing the wrong sequence, which would make the feature feel arbitrary and untrustworthy.

### 4. The editor is organized around tabs of numbers, not around body parts

The current UI exposes seven tabs with many sliders and vector editors. Even when gizmos exist, they are hidden behind tab changes and field names. That makes the editor feel like a property spreadsheet instead of a pose editor.

### 5. The UI copy does not match the controls

The title says `E to close`, but the editor input handler uses `E` to toggle solo mode while open. Mismatched copy like this makes users doubt what the editor will do next.

### 6. Important controls are not prioritized

The most common tuning tasks are probably:

- move paddle target
- rotate torso / hips
- move feet
- move hands
- adjust crouch / stance
- preview pose
- preview swing
- save

Those actions should be visible at all times, but today they are spread across tabs and mixed with lower-frequency settings like sign sources, commit zones, and follow-through timing.

---

## Design principles for the redesign

### 1. Viewport-first editing

The default workflow should be: click body part -> drag / rotate -> see result immediately.

The panel should support the viewport, not compete with it.

### 2. Explicit modes

The editor should always show one clear mode:

- `Select`
- `Preview Pose`
- `Preview Swing`

The user should never need to infer whether the game is frozen.

### 3. Progressive disclosure

Show only the important controls by default. Move technical fields into an `Advanced` section.

### 4. Anatomy-first organization

Users think in terms of paddle, hips, torso, head, hands, feet. The UI should match that mental model.

### 5. Family-aware transitions

Transition preview should be built from the selected posture's family and actual related charge / contact / follow-through definitions, not from hardcoded unrelated IDs.

---

## Proposed UX redesign

## A. Replace the current bottom-panel mental model with a workspace model

Use a 3-part editor layout:

- left: posture library
- center: large 3D viewport with always-visible direct-manipulation handles
- right: compact inspector for selected body part or selected posture

The editor should feel like:

1. pick a posture
2. pick a body part
3. move or rotate it
4. save or preview transition

Not:

1. pick a tab
2. hunt for a field
3. edit numbers
4. switch tabs

## B. Replace the current buttons with explicit mode controls

Rename and restructure the top action bar:

- `Preview Pose`
- `Resume Live`
- `Preview Swing`
- `Pause Swing`
- `Save`
- `Revert`

Behavior:

- selecting a posture should only select it
- `Preview Pose` should freeze and snap the player into the posture
- `Resume Live` should unfreeze and return control to gameplay
- `Preview Swing` should enter timeline mode and animate the full sequence

This removes the hidden "selection also triggers pose" behavior.

## C. Make body-part editing the default interaction

Always show manipulators for the key editable targets:

- paddle target
- right hand
- left hand
- right foot
- left foot
- hips rotation
- torso rotation
- head rotation
- shoulder rotation handles if feasible

Expected interaction:

- click handle to select body part
- drag to move
- hold modifier to rotate
- selected body part shows a compact inspector with only its key fields

Example:

- select `Right Foot`
- right panel shows `position`, `yaw`, `lead foot`, `weight shift`
- no need to look through the entire Legs tab

## D. Replace most tabs with two layers: Quick and Advanced

### Quick layer

Visible by default. Only high-frequency controls:

- paddle position / rotation
- hips / torso rotation
- feet position
- hand position
- crouch
- stance width
- left-hand mode
- preview pose
- preview swing
- save

### Advanced layer

Collapsed by default. For technical tuning:

- sign sources
- commit zone bounds
- floor clearance
- charge offsets
- follow-through timing
- metadata / notes

This keeps power without overwhelming the main workflow.

## E. Add a selected-body-part inspector

Instead of editing everything at once, the inspector should follow the current selection:

- `Paddle`
- `Torso`
- `Head`
- `Right Hand`
- `Left Hand`
- `Right Foot`
- `Left Foot`

This reduces the number of visible controls and makes the UI feel contextual.

## F. Redesign transition preview as a timeline

The current transition button should become a simple timeline panel with:

- phase chips: `Ready`, `Charge`, `Contact`, `Follow-Through`, `Settle`
- scrubber
- play / pause
- speed selector
- loop toggle

Important rule:

The transition data should come from the selected posture's actual related family entries, not hardcoded IDs.

If the selected posture is a forehand posture:

- ready = ready definition
- charge = charge forehand definition
- contact = selected posture
- follow-through = forehand follow-through chain

If the selected posture is backhand, low, overhead, or center, the mapping should match that family.

## G. Add inline guidance instead of relying on terminology

Small helper text in the UI can remove a lot of confusion:

- `Preview Pose: freezes the player and shows the selected posture`
- `Preview Swing: plays charge -> contact -> follow-through`
- `Advanced: sign sources, zones, and timing`
- `Direct Edit: drag handles in the viewport`

The editor should teach itself.

## H. Clean up keyboard shortcuts

Suggested shortcuts:

- `Esc`: close editor
- `P`: preview / release pose
- `Space`: play / pause swing preview
- `G`: toggle non-selected posture ghosts
- `Ctrl+S`: save
- `F`: frame selected posture / selected body part

`E` should not claim to close the editor if it does something else.

---

## Proposed implementation phases

## Phase 1: Clarify editor state and labels

Low-risk cleanup that should happen first.

- stop auto-triggering pose on posture selection
- rename controls to match editor state
- show explicit mode badge: `Live`, `Pose Preview`, or `Swing Preview`
- fix misleading copy and hotkeys
- disable or hide controls that are not valid in the current mode

### Deliverable

The editor becomes understandable before any major UX rebuild.

## Phase 2: Make direct manipulation the primary workflow

- show persistent viewport handles for core body parts
- allow selecting body parts directly in 3D
- make the right panel context-sensitive to the selected body part
- keep numeric fields as backup, not as the main interaction

### Deliverable

User can directly move and rotate each body part without digging through tabs.

## Phase 3: Simplify the panel into Quick + Advanced

- replace 7 top-level tabs with a compact Quick panel
- move technical fields into collapsible Advanced sections
- group controls by anatomy and editing frequency
- pin key actions at the top: preview, transition, save

### Deliverable

Much lower control count on screen, with the important actions always visible.

## Phase 4: Rebuild transition preview on correct posture relationships

- remove hardcoded transition posture IDs
- map transitions by posture family
- add timeline scrubber and phase labels
- allow slow motion and loop
- show which posture resource is active in each phase

### Deliverable

Transition preview becomes trustworthy and useful instead of mysterious.

## Phase 5: Polish and workflow quality

- add revert / reset selected part
- add mirror from left/right where useful
- add copy posture values between related postures
- add unsaved-change indicator per posture
- add hover labels on viewport handles

### Deliverable

The editor feels production-ready for repeated tuning passes.

---

## Suggested first-pass scope

If we want the highest value for the least implementation risk, I would do this order:

1. stop auto-triggering pose on selection
2. rename the editor states and buttons
3. fix transition posture mapping
4. keep viewport handles always available for key body parts
5. replace tabs with a compact Quick panel plus collapsed Advanced sections

That would solve most of the confusion without requiring a full editor rewrite in one pass.

---

## Success criteria

The redesign is successful if a user can:

1. select a posture without unexpectedly freezing the game
2. understand whether they are in live, static-pose, or swing-preview mode at a glance
3. move and rotate the main body parts directly in the viewport
4. reach the important controls without tab-hunting
5. trust that transition preview is showing the correct posture family

---

## Recommendation

Implement this as a usability-focused refactor, not as a small label tweak. The confusion is not just wording; it comes from the editor mixing three workflows into one UI:

- data selection
- static pose inspection
- transition playback

Those need to become distinct, readable modes, with direct manipulation as the default editing path.
