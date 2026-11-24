# Development reel scripts (complete)

Transitions for each reel below: `TRANSITIONS.md`.

Eight ready-to-film devlog reels in the developer's voice (Voice A). Each one has the stake and
where it comes from, the footage and how to get it, the full shot list with on-screen text and
voiceover, sound, the loop, the cover, and captions for all four apps.

Facts come from git history and the project docs (checked 2026-11-25). Optional lines marked
**[you]** are personal facts only you can give; every script works without them.

**Shared rules** (viral-reel skill, Believability):
- Footage is the game as a player sees it: gameplay camera, HUD on, real speed. Old builds are
  filmed the same way so before and after match.
- If the footage is AI vs AI, the caption says so.
- Text on frame 1; at most 7 words on screen at once; nothing in the bottom 20% or right 15%.
- Read the voiceover in your own words; the lines below are the meaning, not a script to perform.
- Game sound stays under the voice at about -12 dB; add the trending sound in each app.

**Filming old builds on the Mac** (for before/after):

```bash
git worktree add ../pp-before <commit>
```

Then record a seeded match there from the gameplay camera (movie writer, 1080x1920 window
override in that copy only; see `docs/REEL_TOOLS.md`), and the same seed at `HEAD`. Remove the
worktree after.

---

## D1. "I'm making pickleball for your phone" (35 s)

**Audience:** everyone (series opener; pin it). **Stake:** solo dev, doubles, pixel art, a
barangay court, the big swings posed by hand (volleys, drops and kitchen shots still use
game-built motion, so never say "every swing").
**Footage:** iPhone screen recording of you playing a point (or the phone filmed with your
thumbs in shot); Pose Studio on the Mac (screen recording, dragging a paddle key); barangay pans
from the gameplay camera.

| Time | Picture | On-screen text | Voiceover |
|---|---|---|---|
| 0.0-2.0 | Phone in hand, a fast exchange mid-rally | Pickleball. On your phone. | "I'm making a pickleball game for your phone." |
| 2.0-6.0 | Full rally from the gameplay camera, score visible | Doubles. 4 players. | "Doubles. Four players. You and an AI partner against two more." |
| 6.0-11.0 | The hall, the flag, the sari-sari store, the crowd reacting to a point | On a barangay court. | "It's played on a barangay court, and the whole barangay watches." |
| 11.0-17.0 | Pose Studio: dragging the paddle through a forehand, the speed curve | The big swings, posed by hand. | "I pose the big swings by hand: wind-up, contact, follow-through." |
| 17.0-26.0 | iPhone: you tap a dink, then hold and release a drive | Tap = soft. Hold = power. | "One thumb moves you. The other hits: tap for soft, hold for power." |
| 26.0-33.0 | A big point; the dog barks, the crowd cheers | | **[you]** "I've been building it since April." or your own why |
| 33.0-35.0 | Back to the opening rally (loop) | Follow to see it ship. | |

**Loop:** last shot cuts into the same rally as the opening.
**Cover:** a rally frame with the crowd behind; text "Pickleball on your phone".
**Captions**
- TikTok: `I'm making a pickleball game for iPhone, solo. Doubles, pixel art, a barangay court. #pickleball #indiegame #pixelart #gamedev`
- Instagram: `I'm making a pickleball game for your phone. Doubles, pixel art, and a barangay that watches every point. Solo dev. Follow to see it ship. #pickleball #indiegame #pixelart`
- Shorts titles: 1) "I'm making a pickleball game for your phone" 2) "Pickleball, pixel art and a barangay crowd: my solo game" 3) "Tap for soft, hold for power: my pickleball game"
- Facebook: `Gumagawa ako ng pickleball game para sa phone. Doubles, pixel art, sa barangay court. Follow para makita pag labas na.`

---

## D2. "My paddle was stopping at the ball" (28 s)

**Audience:** pickleball players, devs. **Stake:** AI paddle speed at contact was 1-19% of its
peak; after the fix, low strokes and volleys hit at 85-99% (`tools/swing_speed.gd`, commit
`f1aeb44`).
**Footage:** the same seeded rally at `e2a4123` (before) and `f1aeb44` (after), gameplay
camera. Pick a contact on a low stroke or a volley (those are the strokes the fix covers).
Numbers card: run `godot --headless --path . -s tools/swing_speed.gd` at both commits and
screen-record the table.

| Time | Picture | On-screen text | Voiceover |
|---|---|---|---|
| 0.0-2.0 | AFTER: a volley hit clean through the ball | My paddle was stopping at the ball. | "My players' paddles were stopping at the ball." |
| 2.0-7.0 | BEFORE: same rally, the swing stalls at contact | BEFORE | "Watch the swing. It slows down right where it should be fastest." |
| 7.0-12.0 | The `swing_speed` table, BEFORE, the contact column highlighted | 1-19% of top speed | "I measured it. At contact the paddle was moving at 1 to 19 percent of its top speed." |
| 12.0-19.0 | AFTER: same rally, the swing accelerates into the ball | AFTER: 85-99% | "Real players hit through the ball. Now the swing speeds up into contact." |
| 19.0-26.0 | Before and after alternating on each contact | | "And the follow-through leaves at full speed." |
| 26.0-28.0 | AFTER contact again (loop) | | |

**Keep honest:** forehands and overheads still peak before contact (0.12-0.60). Don't show one
as AFTER; a comment may ask, and "the big swings are next" is a good follow-up reel.
**Cover:** side-by-side contact frame; text "1% → 99%".
**Captions**
- TikTok: `My pickleball game's paddles stopped at the ball. I measured it: 1-19% speed at contact. Now 85-99%. #gamedev #pickleball #indiegame`
- Instagram: `Real players swing through the ball. Mine didn't: 1 to 19% of top speed at contact. Now 85 to 99%. Solo dev, pickleball game for iPhone. #gamedev #pickleball`
- Shorts titles: 1) "My pickleball game's paddles were stopping at the ball" 2) "I measured my swings: 1% speed at contact" 3) "Fixing the swing in my pickleball game"
- Facebook: `Ang paddle, humihinto sa bola. Inayos ko: ngayon tuloy-tuloy ang palo. Pickleball game para sa iPhone.`

---

## D3. "My game lived on a beach for one day" (24 s)

**Audience:** Filipino viewers, indie fans. **Stake:** beach world `1883960` (22 Nov), replaced
by the barangay `daeff0f` the same day.
**Footage:** gameplay camera at `775ed4c` (beach, last version) and at `HEAD` (barangay), same
seed and moment.

| Time | Picture | On-screen text | Voiceover |
|---|---|---|---|
| 0.0-2.0 | Barangay: point ends, crowd cheers, dog barks | My game lived on a beach for one day. | "My pickleball game lived on a beach for exactly one day." |
| 2.0-7.0 | Beach build, same moment: sand, palms, ocean | 22 Nov, morning | "Sand, palm trees, ocean. It looked fine." |
| 7.0-9.0 | Hold on the beach, no reaction | | "It looked like every other game." |
| 9.0-18.0 | Barangay pan: cracked slab, faded basketball lines, hall and flag, sari-sari store, tricycles, banderitas, hen and chicks | 22 Nov, evening | "So I moved it home. Cracked cement. The hall, the sari-sari store, tricycles, banderitas." |
| 18.0-22.0 | The pandesal cart rolls in during play | | **[you]** "This is the court I grew up next to." (only if true) or "Every barangay has this court." |
| 22.0-24.0 | Crowd cheer (loop into the opening) | Same court. Same day. | |

**Cover:** split frame beach / barangay; text "Beach → barangay".
**Captions**
- TikTok: `My pickleball game lived on a beach for one day. Then I moved it to a barangay. #pickleball #pinoy #indiegame #pixelart`
- Instagram: `Day 1: a beach. Day 1, evening: a barangay court with a sari-sari store, tricycles and a pandesal cart. Solo dev, pickleball game for iPhone. #pickleball #pinoy #indiegame`
- Shorts titles: 1) "My game lived on a beach for one day" 2) "I moved my pickleball game to a barangay" 3) "Beach vs barangay: which court?"
- Facebook: `Isang araw lang sa beach. Inuwi ko sa barangay. Sino'ng may ganitong court sa inyo?`

---

## D4. "My AI watched this go by" (22 s)

**Audience:** pickleball players, devs. **Stake:** the AI let balls hit its body when they were
just out of its step range (it gave up when only 0.12-0.51 m short); now it lunges and reaches the
last 0.45 m. Seeds 1-5: body-hit faults 15 to 9 (commit `f1ae695`). Never show "reach: 45 cm" as
its total reach: a lunge covers far more, and players would call it a bug.
**Footage:** the same seed at `f1ae695~1` and `f1ae695`. Find a ball the old AI let pass that the
new one lunges for (track both matches with `tools/track_match.gd` and compare where the
rallies diverge).

| Time | Picture | On-screen text | Voiceover |
|---|---|---|---|
| 0.0-2.0 | BEFORE: the AI stands still as an easy ball goes by | My AI watched this go by. | "My AI used to just watch balls like this go by." |
| 2.0-8.0 | BEFORE again: a ball that hits its body | Point lost. | "If the ball was a step away, it gave up. Sometimes the ball just hit it." |
| 8.0-16.0 | AFTER: the same ball, the lunge, the return, rally continues | Now it lunges. | "Now it lunges for the last bit. Balls hitting its body went from 15 to 9 in my test matches." |
| 16.0-20.0 | The rally goes on several more shots | | "Points got longer. And it got annoying to play against." |
| 20.0-22.0 | Back to the BEFORE (loop) | | |

**Cover:** the lunge frame; text "It used to give up."
**Captions**
- TikTok: `My pickleball AI used to watch easy balls go by. Now it lunges. #gamedev #pickleball #indiegame`
- Instagram: `My AI gave up on balls one step away. Now it lunges for them. Pickleball game for iPhone, solo dev. #gamedev #pickleball`
- Shorts titles: 1) "My AI wouldn't reach for the ball" 2) "Teaching my AI to lunge" 3) "Making my pickleball AI annoying"
- Facebook: `Dati, hinahayaan lang ng AI ang bola. Ngayon, hinahabol na.`

---

## D5. "These pixel players are secretly 3D" (18 s)

**Audience:** indie and pixel-art fans. **Stake:** each player is a set of pixel-art cards
rendered from 3D shapes in 16 views and cut to 3 tones (`tools/bake_pixel_cards.py`), pinned to
the same 3D skeleton. Not hand-drawn: never say "I drew it"; the 3D look was retired on 21 Nov (`7c82c37`); the game plays the same (the
cards are visual only).
**Footage:** one seeded moment at `7c82c37~1` (check the 3D bodies show there; if the cards are
already default, turn them off in that build's settings) and at `HEAD`.

| Time | Picture | On-screen text | Voiceover |
|---|---|---|---|
| 0.0-2.0 | The 3D frame for half a second, snapping to pixel on contact | These pixel players are secretly 3D. | |
| 2.0-5.0 | 3D look: the same smash | Before: 3D | "This was my game in 3D." |
| 5.0-12.0 | Hard cuts between the two on each contact | After: pixel art | "Same skeleton, same physics. Each body part is rendered from 3D shapes, cut to three tones, and pinned to the skeleton as a flat card." |
| 12.0-16.0 | Full rally in the pixel look, crowd behind | | "Now the whole world renders at a third of the screen and sits on one pixel grid." |
| 16.0-18.0 | The smash again (loop) | | |

**Cover:** split 3D / pixel; text "Secretly 3D".
**Captions**
- TikTok: `My pixel-art players are secretly 3D. Same game, same physics. #pixelart #gamedev #indiegame`
- Instagram: `My pickleball players were 3D. Now they're pixel-art cards on the same skeleton: the game plays exactly the same. #pixelart #gamedev #indiegame`
- Shorts titles: 1) "My pixel players are secretly 3D" 2) "3D to pixel art, same game" 3) "My pickleball game's new look"
- Facebook: `Dati 3D, ngayon pixel art. Parehong laro.`

---

## D6. "I deleted 447 scripts from my game" (15 s)

**Audience:** devs, indie fans. **Stake:** 447 scripts the game never loaded, removed on 18 Nov
(`9e67eff`).
**Footage:** screen recording of the deleted file list scrolling (`git show --name-only
--format= 9e67eff | grep '\.gd$'`), then gameplay. The commit removed 447 `.gd` scripts, their
447 `.uid` files, one scene and one JSON: 896 files, 54,206 lines. Say "447 scripts"; if you show
the stat line, say "896 files, 54,206 lines" instead.

| Time | Picture | On-screen text | Voiceover |
|---|---|---|---|
| 0.0-2.0 | The script list scrolling fast | I deleted 447 scripts. | "I deleted 447 scripts from my game. 54,000 lines." |
| 2.0-7.0 | Gameplay, a rally | It never used them. | "The game never loaded a single one of them." |
| 7.0-13.0 | Rally continues, a point | Still plays the same. | "It still plays exactly the same." |
| 13.0-15.0 | Back to the stat line (loop) | | |

**Captions**
- TikTok: `Deleted 447 scripts from my game. 54,000 lines it never used. #gamedev #indiedev #godot`
- Instagram: `447 scripts my game never loaded. Gone. Still plays the same. #gamedev #godot #indiegame`
- Shorts titles: 1) "I deleted 447 scripts from my game" 2) "54,000 lines my game never used" 3) "Spring cleaning my pickleball game"
- Facebook: `447 files na hindi naman ginagamit. Binura ko lahat.`

---

## D7. "Lobs froze my game" (20 s)

**Audience:** devs. **Stake:** on a lob, the human shot planner checked the same legality rule
per pose per flight segment; the worst planner call went from 143 ms to 8 ms on the Mac, with
the same choices (19 Nov, `6d83d64`; `docs/ROADMAP.md`).
**Footage:** gameplay of a lob reaching you (human slot); the F3 frame graph on, before
(`6d83d64~1`, the spike) and after (flat).

| Time | Picture | On-screen text | Voiceover |
|---|---|---|---|
| 0.0-2.0 | AFTER: a lob, smooth, the frame graph flat | Lobs froze my game. | "Every time someone lobbed, my game froze for a moment." |
| 2.0-8.0 | BEFORE: the lob, the graph spikes | 143 ms | "143 milliseconds. You feel that." |
| 8.0-13.0 | The commit diff, one line highlighted | | "It was checking the same rule for every pose and every piece of the ball's flight." |
| 13.0-18.0 | AFTER: the lob, flat graph | 8 ms | "Once per bounce is enough. Now it's 8." |
| 18.0-20.0 | Loop | | |

**Captions**
- TikTok: `Every lob froze my pickleball game for 143 ms. Now it's 8. #gamedev #godot #indiedev`
- Instagram: `My game re-checked the same rule for every pose on every lob. 143 ms to 8 ms, same shots. #gamedev #godot`
- Shorts titles: 1) "Lobs froze my game" 2) "143 ms to 8 ms" 3) "Finding a stutter in my pickleball game"
- Facebook: `Tuwing may lob, naglo-lag. Naayos na.`

---

## D8. "I finally measured it on my iPhone" (25 s, film when it happens)

**Audience:** everyone. **Stake:** the first PerfMonitor reading on the phone
(`python3 tools/perf_report.py`); goal 60 fps in four-player rallies (`docs/ROADMAP.md`). Use
the real number, good or bad: a bad one makes the better story.

| Time | Picture | On-screen text | Voiceover |
|---|---|---|---|
| 0.0-2.0 | The game on the phone in your hand | Is it really 60 fps? | "I've played it on my iPhone for weeks. Today I measured it." |
| 2.0-10.0 | A four-player rally on the phone | Goal: 60 fps | "The goal: 60 frames a second, four players, every rally." |
| 10.0-16.0 | The report on the Mac, the fps line | [real number] fps | "It ran at [real number]." |
| 16.0-23.0 | If short: the costliest system in the report. If 60: the rally again | [the cause] / 60. | "[what's eating the frames]" or "Locked." |
| 23.0-25.0 | Loop | | |

**Captions** (fill the number): `First real iPhone test of my pickleball game: [N] fps. Goal is 60. #gamedev #indiegame #pickleball`

---

## Posting order

D1 (pin) → D2 → D3 → D4 → D5 → D6 → D7, two or three a week, alternating with the gameplay
scripts (`SCRIPTS_GAMEPLAY.md`). D8 when the iPhone test happens.
