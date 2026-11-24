# POV at real intensity, and technique reels

Transitions for each reel below: `TRANSITIONS.md`.

Two series:

- **POV (P1-P4):** the game's own first-person view (Settings > Camera perspective > First
  person), at real speed, so the viewer feels what a point feels like at the kitchen line.
- **Technique (T1-T10):** real pickleball technique, shown and explained in the game. Each reel
  teaches one thing a real player can use, and shows that the game plays by it. These get saved
  and sent: the strongest metrics for growth.

Checked 2026-11-25. Game facts from the code; real-life numbers from coaching and physics
write-ups (sources at the end; none is a peer-reviewed study).

---

## Part 1: How close is the game to real-life intensity?

| | Real life | The game today (AI vs AI, Easy, 6 seeds, 756 hits) |
|---|---|---|
| Kitchen volleys | Most 30-40 mph | Fast shots 25-43 mph; fastest 43.4 mph |
| Fast drives | 40-60 mph | Up to 43.4 mph |
| Time to react at the kitchen | 0.21 s at 45 mph, 0.24 s at 40 mph over about 14 ft; drills train a 240-320 ms window for 30-40 mph speed-ups | Fastest reply 0.37 s (40.8 mph over 5.4 m); median 0.5 s for 35+ mph shots |
| Dinks | Slow, about 1 s apart | Median 1.07 s between dinks |
| Kitchen firefights | Common in good doubles | Rare: 16 of 756 shots were 35+ mph |

**Honest reading:** the speeds are real-life speeds, and the dink rhythm matches. The hands
battle at the kitchen isn't there yet at Easy: fast shots come from further back, so you get
about 0.37 s instead of 0.2-0.3 s. Check Hard on the phone before claiming "as fast as real
life". POV reels can truthfully say "real speed" and show the measured mph and reaction window
of the footage used; they can't say "same as pros".

Measure each reel's numbers on its own footage: mph from the game's shot log or the track
(`mine_moments.py`), the reaction window as the time between the opponent's contact and yours
(count frames at 30 fps: 11 frames = 0.37 s).

---

## Part 2: POV scripts

**Footage for all:** you playing on the iPhone in the first-person view, screen recording,
real speed, no slow motion except the game's own. Sound up: the paddle pops sell the
intensity. No voiceover during the point.

### P1. "POV: kitchen firefight, real speed" (12-18 s)

| Time | Picture | On-screen text |
|---|---|---|
| 0.0-1.5 | First person at the kitchen; the opponent winds up | POV: real speed. |
| 1.5-end-2 | The exchange, continuous, every contact at full speed | [mph of the fastest shot] mph |
| last 2 s | You win or lose it; your partner's paddle tap or the crowd | [reaction window] s to react |

Loop: end on the next ball coming in. Caption: `POV: a firefight at the kitchen in my pickleball game. Real speed, no slow-mo. #pickleball #pov #indiegame`

### P2. "You have [0.37] seconds" (10 s)

| Time | Picture | On-screen text |
|---|---|---|
| 0.0-1.5 | First person, opponent at contact | You have [0.37] seconds. |
| 1.5-3.0 | The ball arrives; you block it | (a counter from [0.37] to 0.00, real time) |
| 3.0-8.0 | The rally continues | Real speed. No slow-mo. |
| 8.0-10.0 | Loop to the opponent's contact | |

Optional second cut (good for a duet): the same clip once more with the text "Again." Caption:
`[0.37] seconds to react. Could you? #pickleball #reactiontime #pov`

### P3. "POV: a whole point" (25-40 s)

Immersion, not a highlight: from your partner's serve to the end of the point, uncut. Show what
the first-person view really gives: your partner playing beside you, your feet, the ball kid,
the crowd.

| Time | Picture | On-screen text |
|---|---|---|
| 0.0-2.0 | The best moment of the point, first | POV: one point. |
| 2.0-end | The whole point from the serve, uncut | [shot count] shots. |
| End | The crowd reacts; the next serve (loop) | |

Caption: `One full point in first person. My pickleball game for iPhone, real speed. #pickleball #pov #mobilegame`

### P4. "Real life vs my game" (20-30 s) (needs your real footage)

The strongest intensity proof: you, playing real pickleball, filmed with a chest or head mount,
and the same kind of point in the game's first person.

| Time | Picture | On-screen text |
|---|---|---|
| 0.0-2.0 | Split: real (top) / game (bottom), both at the moment of contact | Real life vs my game. |
| 2.0-12.0 | Real: a kitchen exchange | REAL |
| 12.0-22.0 | Game: a matching exchange | MY GAME |
| 22.0-26.0 | Split again on a contact | [real mph if known] / [game mph] |

**Rules:** only your own real footage (or footage you have permission to use); never other
people's clips. Faces of other players: get their OK. If the game is clearly slower, don't post
it; that's a gameplay finding.

---

## Part 3: Technique scripts ("Learn pickleball in my game")

Every technique is real, standard pickleball, and is in the game: the shot names (DINK, DROP,
RESET, BLOCK, SPEED-UP, SMASH, LOB) are the game's own, and the rules (KITCHEN_VOLLEY,
FOOT_FAULT, TWO_BOUNCE_RULE) are enforced. Tap = touch shot, hold = power shot; the shot is
picked from where you stand and the ball's height (`scripts/human_shot_choice.gd`).

**Shape of each:** hook (the mistake or the question) → the real technique in one sentence →
shown in the game → "In my game: [the gesture]". 20-30 s. Voice A (you). Not a coach: say
"what I learned" or "the rule is", never "do this or you're bad".

**Footage:** your iPhone play where you can (you doing it is the point); AI-vs-AI clips from the
Mac for the AI doing it (say so). Pick frames where the pose looks right: players will check the
paddle, and the ball sits a little off the paddle at contact in slow frames, so keep these at real
speed.

| # | Hook (on screen) | The technique (VO, one sentence) | Shown in the game | "In my game" |
|---|---|---|---|---|
| T1 | "Stop driving the third shot" | The third shot drop: from the back, land it soft in their kitchen so your team can come to the net | Serve, return, then a soft drop that lands in the kitchen; the team moves up | Tap from the baseline = drop |
| T2 | "Dink cross-court" | Cross-court dinks go over the low middle of the net and give you more court | A cross-court dink exchange | Tap at the kitchen; swipe sideways to go cross-court |
| T3 | "You can't volley here" | No volleys inside the kitchen, and your momentum can't carry you in after one | A kitchen-volley fault called in the game | The game calls it (KITCHEN_VOLLEY) |
| T4 | "Let it bounce. Twice." | Two-bounce rule: the return and the third shot must bounce before anyone volleys | The serve bounces, the return bounces, then volleys start; or a TWO_BOUNCE_RULE fault | The game calls it |
| T5 | "Stuck in no man's land?" | Reset: in the transition zone, block the ball soft into the kitchen and keep moving up | A RESET from mid-court, then the player reaches the line | Tap from mid-court = reset |
| T6 | "Wait for the high ball" | Speed up only a ball above the net; attacking low balls pops them up | A patient dink run, then a speed-up on a ball above the net | Hold at the kitchen on a high ball = speed-up |
| T7 | "Put away the pop-up" | A ball that pops up high is a smash: hit down, at the feet | Pop-up, then smash at the feet | Hold on a high ball = smash |
| T8 | "Don't swing at a drive" | Block a hard drive: firm paddle, short motion, soft into the kitchen | A hard drive blocked back at the kitchen | Tap at the kitchen on a fast high ball = block |
| T9 | "Lob over the kitchen" | A lob over players at the net: high and deep, it pushes them back | A lob and the team scrambling back | (check the gesture for a human lob before filming; the AI lobs) |
| T10 | "Who takes the middle?" | In doubles, agree who takes the middle ball (often the forehand); hesitation loses the point | The AI partner taking the middle ball (team claim) | Your AI partner takes the ball when it's the easier one for them |

**Full script, T1 as the model** (25 s; the others follow the same timing):

| Time | Picture | On-screen text | Voiceover |
|---|---|---|---|
| 0.0-2.0 | A third shot driven into the net | Stop driving the third shot. | "Most beginners drive the third shot." |
| 2.0-7.0 | The serve and return, at real speed | The third shot drop | "The third shot is the drop." |
| 7.0-13.0 | The drop lands soft in the kitchen; the team walks up | Land it in their kitchen. | "Land it soft in their kitchen, and your team gets to the net." |
| 13.0-19.0 | The dink rally that follows | Now you're at the net. | "Now it's a dink game, on your terms." |
| 19.0-23.0 | Your thumb taps (over-shoulder footage) or the TAP overlay | In my game: tap from the back. | "In my game, that's a tap from the baseline." |
| 23.0-25.0 | Loop to the driven third shot | Save this. | |

**Captions (pattern for all ten)**
- TikTok: `[The technique] in 20 seconds, shown in the pickleball game I'm making. #pickleball #pickleballtips #indiegame`
- Instagram: `[One-line technique]. Save this for your next game. Shown in my pickleball game for iPhone. #pickleball #pickleballtips`
- Shorts titles: 1) "[Technique] explained in my pickleball game" 2) "[The mistake]? Do this instead" 3) "Learn pickleball in a video game"
- Facebook: `[Technique in Taglish]. I-save para sa susunod na laro.`

**Before posting a technique reel:** run it past someone who plays well (or a coach). One wrong
tip in front of pickleball players costs more than a good one earns.

---

## Sources

- https://newsletter.thedinkpickleball.com/p/can-physics-improve-your-pickleball
- https://pickleballdaily.com/pickleball-court-dimensions-why-a-20x44-court-feels-so-fast/
- https://heliospickleball.com/blogs/news/master-pickleball-kitchen-line-strategy
- https://picklevine.com/how-fast-does-a-pickleball-go/
- https://research.poin-t-go.com/en/exercises/pickleball-dink-volley-reaction-time-drill
- https://picklepedia.org/picki/fast-hands-formula/
- https://pickleguide.org/pickleball-hand-speed-kitchen-training/
- Game numbers: seed tracks 1-6 at commit `f1aeb44` (AI vs AI, Easy), hit pairs from opposite
  teams, 30 Hz ticks.
