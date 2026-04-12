# Posture Editor — Phase 4 Implementation Notes

**Status**: Phase 4 complete (in-game UI). Phase 4b (3D gizmos) pending.

## What shipped

### game.gd changes
- Added `_e_was_pressed: bool` state variable
- Added `posture_editor_ui: PostureEditorUI` reference
- E key handler in `_process()`: toggles `posture_editor_ui.visible`
- `_toggle_posture_editor()` function
- UI instantiated in `_ready()` and added to HUD canvas

### scripts/posture_editor_ui.gd (new)
- **Panel** with VBox layout
- **Left side**: ItemList of all 21 postures from PostureLibrary
- **Right side**: Scrollable property grid
- **Editable fields** (Phase 2 scope only):
  - Paddle Position: forehand_mul, forward_mul, y_offset
  - Paddle Rotation: base_deg, signed_deg, sign_source (None/Swing/Fwd)
- **Buttons**:
  - "Play Transition" (placeholder — Phase 4b will add actual scrub)
  - "Save to .tres" — writes back to `res://data/postures/NN_name.tres`

## UI Layout

```
┌─────────────────────────────────────────────┐
│  Posture Editor [E to close]                │
│  Editing: Low Wide Forehand (ID: 17)        │
├──────────────────┬──────────────────────────┤
│  Forehand        │  Paddle Position         │
│  Backhand        │    Forehand Mul [ 0.90]  │
│  Medium Overhead │    Forward Mult [ 0.60]  │
│  ...             │    Y Offset     [-0.62]  │
│  Low Wide FH  ◄──┤                          │
│  Low Wide BH     │  Paddle Rotation         │
│                  │    Pitch  Base[  0]      │
│                  │          Sign[  0] [None]│
│                  │    Yaw    Base[ 12]      │
│                  │          Sign[  8] [Swing│
│                  │    Roll   Base[180]      │
│                  │          Sign[  0] [None]│
├──────────────────┴──────────────────────────┤
│  [Play Transition]        [Save to .tres]   │
└─────────────────────────────────────────────┘
```

## Known limitations

1. **Transition playback** is a placeholder — actual charge→contact→follow-through scrub requires hooking into the tween system in player_hitting.gd
2. **Full-body fields** (feet, knees, elbows, head, torso) are defined in PostureDefinition but not shown in UI yet — they need Phase 3 (Skeleton3D rig) before they're useful
3. **No live preview** — edits require saving + manual reload or game restart to see effect
4. **No revert/undo** — closing without saving discards changes (by design)

## Testing checklist

- [ ] Press E in game → UI appears
- [ ] Press E again → UI hides
- [ ] Click a posture in left list → right panel populates
- [ ] Edit a value → no crash
- [ ] Click Save → file updates on disk (check `data/postures/`)
- [ ] Restart game → saved values persist

## Next: Phase 4b

3D gizmos showing paddle ghost positions in the viewport while the editor is open. Requires:
- Subclassing EditorPlugin or using a 3D overlay in game
- Drawing gizmos at each posture's offset position
- Highlighting the currently selected posture in 3D space
