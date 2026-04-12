# E2E Test: Blue Player Ball Tracking & Blocking Verification

## TL;DR

> **Goal**: Verify the instinctive blocking system works — blue player moves toward ball trajectory and the commit/green-glow scoring system triggers correctly.
>
> **Deliverables**:
> - Updated E2E test where blue player AI moves toward ball trajectory
> - Practice ball launches (key 4)
> - Verify commit logs appear: `[COMMIT]`, `[GREEN]`, `[SCORE]` entries
>
> **Estimated Effort**: Short
> **Parallel Execution**: NO - sequential script
> **Critical Path**: Implement → Test → Verify logs

---

## Context

### Original Request
User wants E2E test where blue player (PlayerLeft/human) moves toward ball trajectory randomly and tests if ball blocking works.

### Current State
- `scripts/tests/test_e2e_playwright.py` exists but:
  - Sends keyboard inputs (WASD, etc.) but doesn't make player actively track ball
  - Launches practice ball but doesn't verify commit/blocking system
  - No feedback on whether blocking actually worked

### What's Needed
The test needs to:
1. Launch multiple practice balls (key 4)
2. Simulate blue player moving toward ball trajectory (WASD toward ball position)
3. Check console output for commit/scoring indicators:
   - `[COMMIT] FIRST/TRACE/LOCK` - posture commitment
   - `[GREEN]` - ghost entering green pool
   - `[SCORE]` - blocking result (PERFECT/GREAT/GOOD/OK/MISS)
   - `[PURPLE]` / `[BLUE]` - stage transitions

---

## Work Objectives

### Must Have
- Blue player moves toward ball trajectory during test
- Practice balls launch multiple times
- Console logs analyzed for commit/green/score patterns
- Test passes if blocking system fires (not necessarily "good" scores - just that system responds)

### Must NOT Have
- Random wander without ball tracking
- No verification of blocking system firing

---

## Execution Strategy

### Single Task
- Update E2E test to implement ball-tracking movement
- Add log verification for instinctive blocking indicators

---

## TODOs

- [ ] 1. Update E2E test with ball-tracking movement

  **What to do**:
  - Read current `scripts/tests/test_e2e_playwright.py`
  - Add logic to track ball position and move WASD toward it
  - Launch multiple practice balls (key 4)
  - After each ball, wait and check for:
    - `[COMMIT]` patterns in stdout
    - `[GREEN]` patterns in stdout
    - `[SCORE]` patterns in stdout
  - Assert that at least one blocking indicator fires per ball

  **Must NOT do**:
  - Change game logic
  - Modify game.gd or player scripts

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: `[]`
  - **Reason**: Simple test update, focused script work

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocks**: None
  - **Blocked By**: None

  **References**:
  - `scripts/tests/test_e2e_playwright.py` - Current E2E test to update
  - `scripts/game.gd:_launch_practice_ball()` - How practice balls work (key 4)
  - `scripts/input_handler.gd` - WASD input handling

  **Acceptance Criteria**:
  - [ ] Updated test runs without errors
  - [ ] Blue player visibly moves toward ball (check position logs or game behavior)
  - [ ] At least 2 practice balls launched
  - [ ] Console shows `[COMMIT]` OR `[GREEN]` OR `[SCORE]` patterns after ball launch

  **QA Scenarios**:

  \`\`\`
  Scenario: E2E with ball tracking and blocking verification
    Tool: Bash (python test_e2e_playwright.py)
    Preconditions: Godot running headless, port 6007 free
    Steps:
      1. Launch game headless with PlayGodot
      2. Wait 2 seconds for game init
      3. Press '4' to launch practice ball
      4. Monitor stdout for 3 seconds
      5. Check if ball is returning (z changes toward player)
      6. Press '4' again for second practice ball
      7. Monitor stdout for commit/green/score patterns
    Expected Result: Test completes without crash, logs show blocking system activity
    Failure Indicators: Test hangs, Godot crash, no blocking logs after 2 balls
    Evidence: .sisyphus/evidence/e2e-blocking-test.log
  \`\`\`

---

## Final Verification Wave

- [ ] F1. **E2E Test Runs** — Run updated test, verify it completes without crash
- [ ] F2. **Blocking System Fires** — Check logs show `[COMMIT]` or `[GREEN]` or `[SCORE]`
- [ ] F3. **Blue Player Tracks** — Verify blue player moves toward ball (position logs or visual)

---

## Success Criteria

```bash
python scripts/tests/test_e2e_playwright.py  # Should exit 0 with blocking logs found
```

### Final Checklist
- [ ] Test runs end-to-end
- [ ] Blue player moves toward ball trajectory
- [ ] At least one practice ball launched
- [ ] Blocking system indicators present in output
