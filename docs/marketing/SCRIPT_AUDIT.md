# Reel script audit (2026-11-25)

An independent short-form growth review of every script (D1-D8, G1-G9, P1-P4, T1-T10, the
barangay A/B pairs), then its factual claims checked against the code. Scores out of 10.

## Verdicts

| ID | Score | Verdict | Main reason |
|---|---|---|---|
| D3 Beach for one day | 8 | **MAKE FIRST** | Real curiosity gap, the barangay reveal pays it off, Filipino sends |
| G4 Dink battle | 8 | **MAKE FIRST** | Live dink counter holds viewers; players tag dink partners |
| P4 Real life vs my game | 8 | MAKE once filmed | Strongest picture in the set; needs your real chest-cam footage |
| G1 Can you beat my AI? | 7 | **MAKE FIRST** (hook swapped) | Lead with "I built it. It beats me." not the generic question |
| G9 Barangay is watching | 7 | MAKE | Good Filipino send; check the dog and hens are readable at 1/3 res |
| G2 Tap. Hold. | 6 | MAKE (support) | Clearest "it's a phone game"; no payoff, so not a lead reel |
| D5 Secretly 3D | 6 | FIX THEN MAKE (fixed) | Was false ("I drew it"); the true version is the better hook |
| G6 My AI partner | 6 | FIX THEN MAKE | Show the middle-ball call, don't just state it |
| G8 Which player are you? | 6 | FIX THEN MAKE (fixed) | Highest tag potential; plain labels, show the Settings menu |
| P2 You have 0.37 s | 6 | FIX THEN MAKE | Good duet loop; 0.37 s vs real 0.2-0.3 s invites "slow" |
| Barangay A/B | 6 | MAKE B (Pairs 1, 2) | B voice sends on Facebook; A lines are weak labels |
| D1 Pickleball for your phone | 5 | FIX THEN MAKE (pin) | Barangay arrives at 6 s; open on it. "Every swing" was false (fixed) |
| D4 My AI watched this go by | 5 | FIX THEN MAKE (fixed) | "Reach 45 cm" sounded like a bug; now opens on the failure |
| D8 Measured on my iPhone | 5 | MAKE when it happens (fixed) | "First time on a real iPhone" was false: it's been on your phone for weeks |
| G3 PERFECT | 5 | FIX THEN MAKE | Cliché hook; one continuous streak beats a montage |
| T-series | 5 | MAKE T3/T4 as quizzes | Rules are safe and searched; T1 and T6 are contested by good players |
| G5 mph at your feet | 4 | FIX THEN MAKE | Same idea as the failed reel; only with your own block |
| P1 Kitchen firefight | 4 | After Hard footage | Firefights are rare on Easy (16 of 756 shots at 35+ mph) |
| T1 Third shot drop | 4 | FIX THEN MAKE | 4.0+ players drive the third and drop the fifth: they'll correct it |
| D2 Paddle stopping | 3 | **CUT** | The stall can't be seen at real speed; devs-only metric |
| D7 Lobs froze | 3 | **CUT** | Fixed-step recording hides the hitch; devs only |
| G7 Easy vs Hard | 3 | **CUT** | Difficulty doesn't show in 7 s clips |
| P3 A whole point | 3 | **CUT** | 25-40 s uncut with no stakes |
| D6 447 scripts | 2 | **CUT** | No game in frame 1; invites "vibe-coded?" |

## Claims checked against the code

| Claim | Finding | Done |
|---|---|---|
| D5 "I just drew pixel cards over it" | False: `tools/bake_pixel_cards.py` renders each part from 3D solids in 16 views and cuts it to 3 tones | Rewritten as "These pixel players are secretly 3D" (D5, DEV_STORY) |
| D1 "I pose every swing by hand" | False: volleys, drops and kitchen shots still use game-built motion | Now "the big swings" (D1, DEV_STORY) |
| D4 "Reach: 12 cm → 45 cm" | Misleading: 0.45 m is the extra lunge it used to give up on, not total reach. The commit's real result: body-hit faults 15 → 9 on seeds 1-5 | Rewritten around the failure and the 15 → 9 (D4, DEV_STORY) |
| D8 "First time on a real iPhone" | False: you've played builds on the iPhone for weeks; only the fps was never measured | Now "I finally measured it on my iPhone" |
| G3 grades | The game also grades EARLY | Added |
| G8 styles | Real and in Settings (partner, opponent 1, opponent 2) | Script now shows the menu, plain labels |

## Problems across the whole set (most damaging first)

1. **Nothing is filmed, and most scripts lean on Mac AI-vs-AI footage.** One 2-hour iPhone
   session (screen recording plus a second phone over your shoulder) covers G1, G2, G3, G6 and
   P2. Do that first.
2. **Overlays that label the picture** ("Same game.", "Timing is everything.", "My partner is an
   AI.", "I added a pandesal cart."). Frame-1 text must open a question.
3. **Stakes you can't see** at real speed on a phone: paddle speed (D2), a hitch (D7), a 0.3 s
   ball (G5), an 11-frame counter (P2), a few-pixel dog (G9).
4. **No face.** Your own research says the developer on camera wins; every script is screen
   plus voiceover. Put yourself in D1 at least.
5. **"Pixel Pickleball" never appears** on screen, and "Follow to see it ship" gives no date or
   reason. Add the wordmark to every last frame and a reason ("Comment to join the beta").
6. **Android.** Most Filipino phones are Android; every Filipino comment section will ask. You
   need an answer before the barangay reels go out.
7. **Dev metrics for the wrong audience.** Percent, milliseconds, centimetres and file counts
   serve devs, who won't buy the game. Moved D2, D6, D7 out.

## Film first

1. **G1** with the hook "I built it. It beats me." (one iPhone session)
2. **D3** beach → barangay
3. **G4** dink battle with the live count
4. **Bantay** (G9 + barangay Pair 2, B voice)
5. **D5** "These pixel players are secretly 3D"

Then pin **D1**, rewritten to open on the barangay with you in frame.

## Rewritten hooks

| ID | Frame 1 | Text |
|---|---|---|
| D1 | You (or the phone in hand) and a rally on the cracked slab, sari-sari store behind | "I'm putting pickleball in a barangay." |
| D4 | The AI standing still as an easy ball goes by | "My AI watched this go by." (applied) |
| D5 | 3D for half a second, snapping to pixel on contact | "These pixel players are secretly 3D." (applied) |
| G3 | One continuous rally, PERFECTs stacking | "PERFECT streak: 4. Watch it end." |
| G8 | A drive into the net player's body | "Tag the banger in your group." |
| T1 | A driven third shot smashed back at your feet | "Why your third shot keeps coming back." |

## Missing from the series (added or still open)

| Idea | Status |
|---|---|
| Basketball vs pickleball over court time | **Added:** `BARANGAY_STORIES.md` (Kwento ng Court, 10 episodes) |
| "Fault or not?" / "In or out?" quizzes with the game's own calls as the payoff | Open: T3/T4 should become these |
| Real people playing it (a tita, a local pickleball group, with their OK) | Open: DEV_STORY episode 11 |
| Your real barangay court beside the game's court, same angle | Open: needs your footage |
| Comment-reply reels (Android? When? Price?) and a glitch log | Open |
| A beta call to action ("Comment to join the TestFlight") | Open: needs a TestFlight plan |
| A paddle-pop sound reel | Open |

## Your calls

- Cut D2, D6, D7, G7, P3? (The audit says cut; nothing is deleted yet.)
- Android: is there a plan, or is it iPhone only?
- A beta list: will there be a TestFlight to invite people to?
