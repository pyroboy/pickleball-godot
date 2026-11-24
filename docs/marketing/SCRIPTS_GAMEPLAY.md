# Gameplay reel scripts (complete)

Transitions for each reel below: `TRANSITIONS.md`.

Nine ready-to-film gameplay reels. They sell the game itself: fast, readable doubles you play with
two thumbs on a barangay court. Each has the stake, the footage and how to get it, the full shot
list, sound, the loop, the cover and captions for all four apps.

Facts are from the code and docs (checked 2026-11-25): tap = touch shot, hold = power shot
(`scripts/human_shot_choice.gd`); timing grades PERFECT / GOOD / EARLY / LATE
(`scripts/shot_execution_error.gd`); difficulty Easy / Medium / Hard (Settings); five AI playing
styles (`scripts/ai_playing_styles.gd`); measured smashes from the seed tracks.

**Shared rules**
- Gameplay camera, HUD and score on, real speed. Slow motion only where the game itself slows.
  No freezes, no director camera.
- **Best footage is you playing on the iPhone** (screen recording from Control Center, or a
  second phone filming over your shoulder with your thumbs in shot). Mac footage is AI vs AI:
  say so in the caption.
- Text on frame 1; at most 7 words; nothing in the bottom 20% or right 15%.
- Mostly no voiceover: game sound plus the trending sound you add in the app. Where a line is
  given, it's optional.
- Every number shown is measured on the footage you use. Speeds: run the reel's track through
  `mine_moments.py` (viral-reel skill), or read the shot speed from the game's log.

---

## G1. "Can you beat my AI?" (15-25 s)

**Audience:** pickleball players. **Stake:** your real score against the AI you built.
**Footage:** iPhone screen recording of a whole point you lost (losing to your own AI is the
hook). Medium or Hard. Keep the score in frame.

| Time | Picture | On-screen text |
|---|---|---|
| 0.0-2.0 | The fastest exchange of the point | Can you beat my AI? |
| 2.0-end-2 | The whole point, continuous | I built it. It beats me. (only if true) |
| last 2 s | The score after the point, then the next serve (loops into the rally) | [real score] |

**Optional VO at the end:** "I made it. I still lose."
**Cover:** the exchange at the net; text "I built it. It beats me."
**Captions**
- TikTok: `I built this pickleball AI and it beats me. Could you? #pickleball #indiegame #mobilegame`
- Instagram: `My own AI, on Hard, and I still lost the point. Pickleball game for iPhone, solo dev. Follow to see it ship. #pickleball #indiegame`
- Shorts titles: 1) "Can you beat my pickleball AI?" 2) "I built an AI I can't beat" 3) "Losing to my own game"
- Facebook: `Ako gumawa ng AI na 'to, pero talo pa rin ako. Kaya mo kaya?`

---

## G2. "Tap. Hold." (20 s)

**Audience:** everyone, especially mobile gamers. **Stake:** one thumb moves, the other hits;
tap for a touch shot, hold for power; the game picks the shot from where you stand and how high
the ball is.
**Footage:** a second phone filming your iPhone over your shoulder (thumbs visible; a screen
recording can't show the touches). Get a tap dink at the kitchen, a hold-release
drive from the back, a hold on a high ball (smash).

| Time | Picture | On-screen text | VO (optional) |
|---|---|---|---|
| 0.0-2.0 | Thumb holds, releases: a smash | Hold = power. | |
| 2.0-6.0 | Quick tap at the kitchen: a dink | Tap = soft. | "Tap for a soft shot." |
| 6.0-10.0 | Hold and release from the back: a drive | Hold = drive. | "Hold for power." |
| 10.0-14.0 | Tap from the back: a drop into the kitchen | Same tap, different spot: drop. | "The game picks the shot from where you are." |
| 14.0-18.0 | A sideways swipe on a tap: cross-court dink | Swipe to aim. | "Swipe to aim it." |
| 18.0-20.0 | The smash again (loop) | | |

**Cover:** thumb on the hit pad mid-hold; text "Tap. Hold. That's it."
**Captions**
- TikTok: `Pickleball with two thumbs: tap for soft, hold for power. #pickleball #mobilegame #indiegame`
- Instagram: `No buttons to pick: tap for a dink, hold for a drive. The game reads where you stand. Pickleball for iPhone. #pickleball #mobilegame`
- Shorts titles: 1) "Pickleball with one thumb" 2) "Tap for soft, hold for power" 3) "The controls of my pickleball game"
- Facebook: `Tap para mahina, hold para malakas. Ganun lang.`

---

## G3. "PERFECT" (15 s)

**Audience:** mobile gamers. **Stake:** the timing grade on every hit (PERFECT, GOOD, EARLY, LATE).
**Footage:** iPhone recording; collect 6-8 of your hits with their grade showing, mostly
PERFECT, one LATE that loses the point.

| Time | Picture | On-screen text |
|---|---|---|
| 0.0-2.0 | A PERFECT drive winner | Timing is everything. |
| 2.0-10.0 | Quick cuts on contact: PERFECT, PERFECT, GOOD, PERFECT | (the game's own grades) |
| 10.0-13.0 | A LATE: the ball goes into the net | Except this one. |
| 13.0-15.0 | Back to the PERFECT (loop) | |

**Rule:** every clip is a real hit; no grade added in the edit.
**Captions**
- TikTok: `How many PERFECTs can you hit? #pickleball #mobilegame #satisfying`
- Instagram: `Every hit is graded: PERFECT, GOOD or LATE. The LATE one cost me. #pickleball #mobilegame`
- Shorts titles: 1) "PERFECT timing in my pickleball game" 2) "One LATE and the point is gone" 3) "Satisfying pickleball hits"
- Facebook: `PERFECT, PERFECT, PERFECT... LATE.`

---

## G4. "The dink battle" (25-30 s)

**Audience:** pickleball players. **Stake:** a long soft exchange at the kitchen that breaks
into a fast attack: patience, then speed. (Dinks and resets are most of the game's shots:
`docs/GAME_MECHANICS_PLAN.md`.)
**Footage:** your iPhone play, or a Mac match: mine seed tracks for the longest dink run that
ends in a smash or drive (`mine_moments.py` "dink run" and "smashes"). Real speed, continuous.

| Time | Picture | On-screen text |
|---|---|---|
| 0.0-2.0 | The speed-up/smash that ends it | [N] dinks. Then this. |
| 2.0-20.0 | The dink exchange from the start, continuous | Dink [count up on each dink] |
| 20.0-25.0 | The pop-up, the attack, the point | [measured mph] |
| 25.0-28.0 | Crowd cheers, dog barks; next serve (loop) | |

**Count the dinks yourself** on the footage; the miner's dink run may not match what's shown.
**Captions**
- TikTok: `[N] dinks, then someone got impatient. #pickleball #dinking #indiegame`
- Instagram: `The dink battle: [N] shots of patience, then one pop-up. Pickleball game for iPhone. #pickleball #indiegame` (+ "AI vs AI" if Mac footage)
- Shorts titles: 1) "[N] dinks, then this" 2) "Who blinks first in a dink battle?" 3) "Patience, then a [mph] mph speed-up"
- Facebook: `Dink nang dink... tapos biglang palo.`

---

## G5. "[mph] mph at your feet" (12-15 s)

**Audience:** pickleball players. **Stake:** a measured smash at real speed and whether it came
back. (The seed-2 rally had a 42.9 mph smash at the near player's feet, blocked back at 17.2 mph,
AI vs AI on Easy; better if it's your own block on the iPhone.)
**Footage:** gameplay camera, real speed, the pop-up, the smash, the block. The game's own slow
motion only if it plays there.

| Time | Picture | On-screen text |
|---|---|---|
| 0.0-2.0 | The smash leaving the paddle | [mph] mph at your feet. |
| 2.0-6.0 | The pop-up that caused it (cut back) | |
| 6.0-10.0 | Smash, block, at real speed | Did it come back? |
| 10.0-13.0 | The block lands; the rally goes on or ends | [yes/no + the block's mph] |
| 13.0-15.0 | Loop to the smash | |

**Captions**
- TikTok: `[mph] mph smash, straight at the feet. Would you have blocked it? #pickleball #indiegame`
- Instagram: `[mph] mph at the feet, blocked back at [mph]. [AI vs AI / my own block]. Pickleball game for iPhone. #pickleball`
- Shorts titles: 1) "Could you block a [mph] mph smash?" 2) "[mph] mph at your feet" 3) "The block that saved the point"
- Facebook: `[mph] mph na smash sa paa. Naibalik!`

---

## G6. "My AI partner" (20 s)

**Audience:** doubles players. **Stake:** your AI partner takes the ball when it's easier for
them, covers the middle, and taps paddles with you between points (`team claim`, partner paddle
tap, both in git history 21-22 Nov).
**Footage:** iPhone recording; a ball down the middle your partner takes; a point won; the
paddle tap after it.

| Time | Picture | On-screen text |
|---|---|---|
| 0.0-2.0 | Partner takes the middle ball and wins the point | My partner is an AI. |
| 2.0-10.0 | The rally that led to it | It takes the ball when it's easier for it. |
| 10.0-14.0 | The point ends | |
| 14.0-18.0 | The two of you tap paddles | And it does this. |
| 18.0-20.0 | Loop | |

**Captions**
- TikTok: `My doubles partner is an AI and it still taps paddles after a point. #pickleball #doubles #indiegame`
- Instagram: `Doubles with an AI partner: it calls the middle ball and taps paddles after the point. #pickleball #doubles`
- Shorts titles: 1) "The best doubles partner I've had is an AI" 2) "My AI partner taps paddles" 3) "Who takes the middle ball?"
- Facebook: `Partner ko, AI. Pero marunong mag-paddle tap.`

---

## G7. "Easy vs Hard" (20 s)

**Audience:** mobile gamers, pickleball players. **Stake:** the same kind of point on Easy and
on Hard.
**Footage:** two iPhone recordings, Easy and Hard; or two Mac matches (`DIFF=0` and `DIFF=2`,
same seed); pick the most typical point of each, not the most extreme.

| Time | Picture | On-screen text |
|---|---|---|
| 0.0-2.0 | Hard: the AI wins a fast exchange | Easy vs Hard. |
| 2.0-9.0 | Easy: a point | EASY |
| 9.0-17.0 | Hard: a point | HARD |
| 17.0-20.0 | Loop | Which one are you? |

**Keep honest:** if the two look almost the same, don't post it; that's a gameplay finding, not
a reel.
**Captions**
- TikTok: `Easy vs Hard in my pickleball game. Which one are you playing? #pickleball #mobilegame`
- Instagram: `Same game, two difficulties. Easy, then Hard. #pickleball #mobilegame #indiegame`
- Shorts titles: 1) "Easy vs Hard pickleball AI" 2) "Which level would you play?" 3) "My pickleball AI on Hard"
- Facebook: `Easy o Hard? Ikaw?`

---

## G8. "Which player are you?" (25 s)

**Audience:** pickleball players (tag-a-friend). **Stake:** the AI's five playing styles:
All-Rounder, Power Attacker, Patient Dinker, Counterpuncher, Lob Tactician.
**In the game:** Settings sets the style of your partner and of each opponent
(`gameplay.ai_style_partner`, `..._opponent_one`, `..._opponent_two`). Show that menu for a
second: it proves the styles are real. Use plain labels on screen (THE BANGER, THE DINKER,
THE LOBBER) rather than the code names.
**Footage:** Mac matches where one player has each style (or iPhone matches against each),
one short clip of the habit that defines it (a drive, a long dink run, a counter, a lob).

| Time | Picture | On-screen text |
|---|---|---|
| 0.0-2.0 | Power Attacker drives | Which player are you? |
| 2.0-6.0 | Power Attacker | POWER ATTACKER |
| 6.0-10.0 | Patient Dinker | PATIENT DINKER |
| 10.0-14.0 | Counterpuncher | COUNTERPUNCHER |
| 14.0-18.0 | Lob Tactician | LOB TACTICIAN |
| 18.0-22.0 | All-Rounder | ALL-ROUNDER |
| 22.0-25.0 | Loop | Tag your partner. |

**Captions**
- TikTok: `Every pickleball player is one of these. Tag your partner. #pickleball #pickleballlife #indiegame`
- Instagram: `My pickleball AI has five styles. Which one is your doubles partner? #pickleball #indiegame`
- Shorts titles: 1) "5 types of pickleball players" 2) "Which pickleball player are you?" 3) "My AI plays 5 styles"
- Facebook: `Alin ka dito? I-tag ang partner mo.`

---

## G9. "The barangay is watching" (15-20 s)

**Audience:** Filipino viewers, everyone. **Stake:** the crowd and the barangay react to the real
match: cheers on big points, the dog barks at balls that land near him, hens scatter, the scorer
flips the score, ball kids fetch the ball (`docs/marketing/BARANGAY_CAST.md`).
**Footage:** a point from the gameplay camera where a ball lands near the dog or the hens and
the point ends big.

| Time | Picture | On-screen text |
|---|---|---|
| 0.0-2.0 | Big point: crowd cheers, dog barks | The whole barangay is watching. |
| 2.0-10.0 | The rally, continuous; a ball lands near the hens, they scatter | |
| 10.0-14.0 | Point ends: cheer, the scorer flips the score | |
| 14.0-18.0 | The ball kid fetches the ball, passes to the server (loop into the serve) | |

**Captions**
- TikTok: `In my pickleball game the whole barangay reacts. Even the dog. #pickleball #pinoy #indiegame`
- Instagram: `The crowd cheers, the dog barks, the hens run. Pickleball game on a barangay court. #pickleball #pinoy #pixelart`
- Shorts titles: 1) "The crowd in my pickleball game reacts to everything" 2) "Even the dog watches the match" 3) "Pickleball in the barangay"
- Facebook: `Pati si Bantay nanonood. Sino'ng may ganitong court sa barangay n'yo?`

---

## Weekly mix

Two or three posts a week, alternating: one gameplay (G), one development (D, in
`SCRIPTS_DEVELOPMENT.md`), and every other week a barangay character A/B pair
(`BARANGAY_CAST.md`). Start: D1 (pin), G1, D2, G2, G9, D3, G4...
