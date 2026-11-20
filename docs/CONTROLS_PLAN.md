# Human controls plan (iPhone, doubles)

Goal: shots feel like a paddle, not a menu. One thumb moves, one thumb plays.
The player decides *how hard* and *where*; the game picks the *obvious shot* from
the situation and says what it will be before you play it.

## Today (why it feels clunky)

- Every rally shot aims ~4.6 m deep unless the small DROP button is pressed first
  (`aim_controller.gd`: target z -4.6, DROP -1.15). A quick tap only lowers power,
  so the ball still has to reach the back: a tap reads as a drive.
- Three small buttons (TOPSPIN, SLICE, DROP) around HIT must be chosen before the
  swing; under pressure there is no time.
- Reach / Erne / Dive live in a separate picker that pauses play.
- Status box and labels told you what the *system* is doing, not what *your press*
  will do.

## The idea in one line

**Tap = touch shot · Hold = power shot · Flick = where and what shape.**

## 1. Right thumb: the HIT pad

| Gesture | What happens | Shot by situation |
|---|---|---|
| **Tap** (released < 0.18 s) | Soft, placed short, clears the net with margin | Kitchen + low ball: **DINK** · kitchen + ball above net: **BLOCK** · transition: **RESET** · baseline: **DROP** (3rd shot drop) |
| **Hold, release** (0.18-0.8 s, longer = harder) | Power, placed deep | Baseline/transition: **DRIVE** · kitchen + ball above net: **SPEED-UP** · high ball: **SMASH** |
| **Flick on release** (≥ 40 px) | Aim and shape | Left/right/diagonal = direction (cross-court vs line) · **up = LOB** · **down = slice/dip** |
| Press early | Queues the shot; swing fires on time | Timing ring grades it (PERFECT/GOOD/LATE) as today |

Rules:
- Touch shots go short (1.2-1.8 m into their kitchen); power shots go deep (4-5.8 m).
  Depth comes from the gesture, so a tap can never become a drive.
- Spin is automatic per shot (dink/reset/block: slight slice; drive/speed-up: topspin;
  smash: flat). Flick down adds slice; flick up on a power shot = topspin lob.
- No flick = the smart default target: cross-court for dinks, middle for resets,
  deep middle for drives (where real players aim when unsure).

## 2. Always tell the player what the press will do

- The HIT pad shows two words as the ball comes: **TAP · DINK** / **HOLD · SPEED-UP**
  (or SMASH when it's on). Updated from the predicted contact, not every frame.
- While holding: a small ghost target on the court where the ball will land; it moves
  with the flick direction and slides deeper as power builds.
- After the hit: the shot name over the player (already in, position-based).

## 3. Specials without a menu

- **Out of reach + HIT**: the game offers the move that can make it, shown on the pad
  (**REACH** / **DIVE**); hold HIT to commit. No pause, no picker.
- **ERNE**: when legal (sideline volley), the pad glows **ERNE**; flick sideways.
- The old picker stays reachable from Pause for practice.

## 4. Serve

- Tap = safe deep serve to the middle of the box · hold = power · flick = spot in the box
  · flick down = drop serve. Replaces the serve wheel (wheel kept behind a setting).

## 5. Left thumb

- Movement stick unchanged. Auto-footwork keeps moving you to the ball after you commit.
- Option: **left-handed layout** (mirror the pads).

## 6. Learnability

- First match: three 2-second coach tips at the right moments ("Tap for a dink",
  "Hold for a drive", "Flick up to lob"), each shown once.
- Settings: tap/hold threshold (0.12-0.25 s), flick sensitivity, **Classic controls**
  (today's TOPSPIN/SLICE/DROP buttons) for anyone who prefers them.

## 7. How we check it (data, not guesses)

- Log each human shot once (PerfMonitor note `human_input`): press length, flick
  vector, shot chosen, shot name shown, result (in / net / out / winner).
- Phone sessions answer: do taps at the kitchen become dinks (target: > 90%)?
  Do you net or pop up more than before? How often do you hit HOLD by accident?
- Scripted input test (headless): fake taps/holds/flicks at set moments with a fixed
  seed; assert the shot chosen and the target depth for each zone.
- AI is untouched: `tools/bench.sh` poses stay IDENTICAL.

## 8. Build order

1. **Tap / hold** with contextual touch vs power targets, auto spin, pad preview text.
   Hide TOPSPIN/SLICE/DROP (setting keeps them). Log `human_input`.
2. **Flick** (aim, lob up, slice down) and the ghost landing target; drop the drag-aim.
3. **Specials** on the pad (reach/dive/erne prompts), picker moved to Pause.
4. **Serve gestures**, coach tips, left-handed layout, threshold settings.

Each step ships to the phone on its own; you play, we read the log, then the next.

## Aim: drag and flick together (decided)

One gesture, not two modes:
- The finger's offset from where you pressed is the aim, all the time. **Drag** slowly
  for precision; a **flick** at release is the same motion done fast and nudges the aim
  the same way by a fixed amount.
- The ghost landing target is the truth: it follows the finger while holding.
- **Shape comes only from a fast vertical flick at release** (speed at release, e.g.
  > ~1200 px/s): up = LOB, down = SLICE. A slow vertical drag only moves the target
  deeper/shorter and never changes the shot.
- When a flick is read as LOB/SLICE the pad flashes that word on release.
- Edge case: slow drag up ending in a fast flick = LOB (release speed decides).

## Open choices

- Should a tap ever become a **lob** by itself (e.g. you're pulled deep and late)?
  Plan says no: lobs only on flick up, so nothing surprises you.
