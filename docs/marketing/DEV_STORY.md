# Pixel Pickleball: the development story and reel scripts

The development story told in the developer's voice, a "Day N" episode plan, and scene-by-scene
reel scripts. Every date and number comes from git history or the project docs (2026-11-25);
the commit is named so the before/after footage can be rebuilt. Lines marked **[you]** are yours
to fill: only you know them, and the reels shouldn't invent them.

Rules for all of it come from the viral-reel skill: real gameplay as a player sees it, real
numbers, your voice, no freezes, no staged play passed off as real
(`~/.claude/skills/viral-reel/SKILL.md`, Believability).

---

## Part 1: The story

### 1. It started with a paddle (April 2026)

The first commit is dated 13 April 2026. There was no match yet, only a player standing on a
court and a tool to pose him: drag the paddle, drag the elbow, save. In the first two weeks I
built that posture editor twice. Version one grew to a single 1,866-line file and had to be split
into five. Version two learned to save without snapping back.

Before I could make a game about hitting a ball, I needed a body that could hold a paddle.

**[you]** Why pickleball? Who do you play with, where, since when?
**[you]** What happened between April and November? (The history picks up again on 18 November.)

### 2. Doubles, on an iPhone (18 November)

Build 31, version 0.3.28: four players, doubles, on an iPhone. The first thing I did that day
was delete 447 scripts the game never loaded. The second was to find out where every
millisecond went: a performance monitor that logs every spike and blames the system that caused
it.

Then a big decision: run the physics at 30 ticks a second instead of 60, with interpolation
smoothing the picture. On the Mac a rally frame went from 9.4 ms to 3.9 ms. It changed how the
ball behaves, slightly, so I measured that too.

### 3. Becoming pixel art (18-24 November)

The players were 3D models. I wanted the game to look like pixel art. So each player became a set
of flat pixel-art cards, rendered from 3D shapes and pinned to the same invisible 3D skeleton: the game still plays with the
3D body, you only see the cards. On 21 November I retired the 3D look for good. On 24 November the
whole world started rendering at one third of the screen's resolution, so the court, the players
and the effects sit on one pixel grid.

### 4. Teaching them to play (18-25 November)

- The AI used to give up on balls it could almost reach. It now commits to a contact up to
  0.45 m away, a lunge. Before: 0.12 m.
- A lob used to freeze the game for a moment: the shot planner checked the same rule hundreds
  of times. Worst case went from 143 ms to 8 ms, with the same choices.
- I built Pose Studio: an editor for each stroke's wind-up, contact and finish, with the
  paddle's path and its speed drawn as a curve.
- Then I noticed the paddle was stopping at the ball. Measured, the AI's paddle was moving at
  1% to 19% of its top speed at the moment of contact. Real players swing through. After the
  fix, the low strokes and volleys hit at 85-99% of top speed.
- The AI learned to jump-smash, to lob from the back, to block hard drives. Partners tap paddles
  between points. Players jog to the other end at the change of ends.

### 5. Finding home (22 November)

On 22 November the court got a world around it: a beach, with sand, ocean and palms. It lasted
one day. That evening it became a barangay court: a cracked cement slab with faded basketball
lines, a red curb, bamboo net poles in hollow blocks, the barangay hall and its flag, a
sari-sari store, tricycles, banderitas on the power poles, a hen with her chicks. A pandesal cart,
rebuilt as a motor sidecar like the real ones, rolls in and stays five minutes. A crowd that
reacts to every hit, bounce and point.

**[you]** Why the barangay? Which court is it based on?

### 6. A name (23-24 November)

An app icon: a neon yellow-green ball on court blue. A menu where you can flick the ball and
watch it roll. On 24 November it got its name: Pixel Pickleball.

### 7. What's next (open, true today)

- It has never been measured on a real iPhone. The goal is a steady 60 fps with four players.
- No one but me has played it.
- **[you]** When do you want to ship? TestFlight? Price?

---

## Part 2: The "Day N" series

Post 2-3 a week, all four apps the same day. Number by days since the first commit
(13 April 2026 is day 1; 25 November 2026 is day 227), or start a fresh count at the first post:
pick one and keep it.

| # | Episode | Format | Stake (real) | Footage |
|---|---|---|---|---|
| 1 | "I'm making pickleball for your phone" | Explainer, you on camera | Solo dev, barangay court, doubles | You + iPhone gameplay |
| 2 | "My paddle was stopping at the ball" | Before/after | 1-19% to 85-99% of top speed | Mac gameplay at `e2a4123` vs `f1aeb44` |
| 3 | "My game lived on a beach for one day" | Before/after, identity | Beach `1883960` to barangay `daeff0f` | Mac gameplay at both commits |
| 4 | "The pandesal cart" | Detail, wholesome | Motor sidecar, 5-minute stay | Mac gameplay camera, a match while it passes |
| 5 | "Can you beat my AI?" | Gameplay challenge | Your real score vs the AI | iPhone screen recording |
| 6 | "My AI watched this go by" | Before/after | Body-hit faults 15 to 9 | Mac gameplay at `f1ae695~1` vs `f1ae695` |
| 7 | "3D to pixel art" | Before/after, craft | Same rally, 3D vs cards | Mac at `7c82c37~1` (3D) vs today |
| 8 | "I finally measured it on my iPhone" | Milestone | First fps measurement | iPhone + perf report numbers |
| 9 | "I deleted 447 files" | Confession, dev humour | 447 scripts never loaded | Screen recording of the folder / diff stat |
| 10 | Glitch of the week | Glitch | Whatever broke | Whatever caught it |
| 11 | "A stranger played my game" | Milestone | First playtester's real reaction | Over-the-shoulder phone video, with their OK |

Episodes 8 and 11 need things that haven't happened yet; film them when they do.

---

## Part 3: Scene scripts

Complete, ready-to-film versions (shot lists, voiceover, captions for all four apps):
`SCRIPTS_DEVELOPMENT.md` (D1-D8) and `SCRIPTS_GAMEPLAY.md` (G1-G9).

Times are reel seconds. "Picture" is what's on screen, "Text" the overlay (sound-off safe, at
most 7 words), "Voice" what you say (first person, natural; read it, don't perform it). Keep the
game's sound under your voice. Add the trending sound in the app.

### Script 1: "I'm making pickleball for your phone" (episode 1, 30-40 s)

Audience: all three. Goal: the premise in one breath, then proof.

| Time | Picture | Text | Voice |
|---|---|---|---|
| 0-2 | iPhone in your hand, a fast exchange already playing | Pickleball. On your phone. | "I'm making a pickleball game for your phone." |
| 2-6 | Gameplay camera, a full rally at real speed, HUD on | Doubles. Pixel art. | "Doubles, four players, pixel art." |
| 6-11 | The barangay: hall, flag, tricycle, crowd reacting to a point | On a barangay court. | "And it's played on a barangay court, with a crowd that reacts." |
| 11-16 | Pose Studio on the Mac: dragging a paddle, the swing arc | The big swings, posed by hand. | "I pose the big swings myself." |
| 16-24 | Back to iPhone gameplay, a smash, a point won | | **[you]** one honest line: how long, why |
| 24-30 | You, or your hands, playing; the score on screen | Day 1 of showing it. | "Follow and I'll show you how it's made." |

Caption: `I'm building a pickleball game for iPhone, solo. Doubles, pixel art, a barangay court. Day 1 of showing it. #pickleball #indiegame #pixelart`

### Script 2: "My paddle was stopping at the ball" (episode 2, 25-30 s)

Audience: pickleball players and devs. Stake: 1-19% to 85-99% of top speed.
Footage: the same seed and the same rally at `e2a4123` (before) and `f1aeb44` (after), gameplay
camera at real speed, then the game's own slow-motion lens if a shot needs it. No freezes.

| Time | Picture | Text | Voice |
|---|---|---|---|
| 0-2 | After: a drive hit clean through the ball | My paddle was stopping at the ball. | "My players' paddles were stopping at the ball." |
| 2-7 | Before: same rally, the swing visibly stalls at contact | Before | "Look: the swing slows right where it should be fastest." |
| 7-12 | Paddle-speed numbers on screen (from `tools/swing_speed.gd`) | 1-19% of top speed at contact | "I measured it. At contact the paddle had 1 to 19 percent of its top speed." |
| 12-20 | After: same rally, swing through | After: 85-99% | "Now it speeds up into the ball and follows through." |
| 20-28 | Before and after side by side, same contact | | "Real players swing through. Now mine do too." |

Honest limit to keep: the fix reached 85-99% on low strokes and volleys; forehands and
overheads are lower (0.12-0.60). Don't show one of those as "after".

### Script 3: "My game lived on a beach for one day" (episode 3, 20-25 s)

Audience: Filipino viewers and indie fans. Stake: beach `1883960`, barangay `daeff0f`, same day.

| Time | Picture | Text | Voice |
|---|---|---|---|
| 0-2 | Barangay court, a point ends, crowd reacts | My game lived on a beach for one day. | "My pickleball game lived on a beach for exactly one day." |
| 2-7 | Beach build, same camera: sand, palms, ocean | Day 1: the beach | "It looked fine. It looked like every other game." |
| 7-17 | Barangay: pan across hall, flag, sari-sari, tricycle, banderitas, hen with chicks | Day 2: our barangay | "So I moved it home. Cracked cement, the hall, the sari-sari store, tricycles." |
| 17-23 | The pandesal cart rolling in during play | | **[you]** one line on why the barangay |

Facebook caption (Taglish only if natural to you): `Sino'ng naglalaro ng pickleball sa barangay n'yo? I'm making this game for iPhone.`

### Script 4: "The pandesal cart" (episode 4, 15-20 s)

Audience: Filipino viewers. Wholesome. No numbers needed beyond what's true: a motor sidecar,
a five-minute stay, a queue.

| Time | Picture | Text | Voice |
|---|---|---|---|
| 0-2 | Gameplay camera, rally on, the cart rolling past the end of the court | Nobody asked for this. | (game sound only) |
| 2-8 | Rally continues; the queue forms at the cart | I added a pandesal cart. | |
| 8-14 | The cart stays; a point ends, the crowd cheers | It stays 5 minutes. Like real ones. | |
| 14-18 | The cart leaves as the next serve starts | | "Every barangay court needs one." |

### Script 5: "Can you beat my AI?" (episode 5, 15-30 s)

Audience: pickleball players. Footage: your iPhone screen recording, real play. Use a point you
lost if it's the better clip: losing to your own AI is the hook.

| Time | Picture | Text | Voice |
|---|---|---|---|
| 0-2 | The fastest moment of the point, real speed | Can you beat my AI? | |
| 2-20 | The whole point, continuous, score visible | I made it. It beats me. (only if true) | **[you]** optional |
| End | The score after the point, then the next serve (loops) | | |

Caption: `I built this AI and it still beats me. Pickleball game for iPhone, coming soon. #pickleball #indiegame`

### Script 6: "My AI wouldn't reach for the ball" (episode 6, 20 s)

Stake: the AI now lunges the last 0.45 m it used to give up on; body-hit faults 15 to 9 on seeds 1-5 (`f1ae695`). Not its total reach. Footage: the same seed at `f1ae695~1` and
`f1ae695`, find a ball the old AI let go (mine tracks for misses at both commits).

| Time | Picture | Text | Voice |
|---|---|---|---|
| 0-2 | After: AI lunges and gets it | My AI used to give up. | "My AI used to just watch balls go by." |
| 2-8 | Before: same ball, the AI stands, the ball passes | Point lost. | "If the ball was a step away, it gave up." |
| 8-16 | After: lunge, return | Now it lunges. | "Now it lunges for the last bit." |
| 16-20 | The rally continues | | "Now it's annoying." |

### Script 7: "3D to pixel art" (episode 7, 15-20 s)

Audience: indie and pixel-art fans. Footage: one moment from a seeded match at `7c82c37~1`
(3D bodies; check the 3D look is shown there) and at HEAD.

| Time | Picture | Text | Voice |
|---|---|---|---|
| 0-2 | Today's pixel look, a smash | Same game. | |
| 2-6 | The same moment in 3D | Before | |
| 6-12 | Hard cut back and forth on each contact | After | "Same skeleton, same physics. Each card is rendered from 3D shapes." |
| 12-18 | A full rally in the pixel look | | |

### Script 8: "I finally measured it on my iPhone" (episode 8, 20-30 s, when it happens)

Stake: the first PerfMonitor reading on the phone (`python3 tools/perf_report.py`). Use the real
number, good or bad; a bad one is a better story ("it ran at N fps; here's what I cut").

| Time | Picture | Text | Voice |
|---|---|---|---|
| 0-2 | The game running on the phone in your hand | Is it really 60 fps? | |
| 2-12 | Four-player rally on the phone | Goal: 60 fps | "The goal is 60 frames a second with four players." |
| 12-20 | The report on the Mac | **[real number]** | "It ran at... [real]." |
| 20-28 | What you'll fix, or the celebration | | **[you]** |

### Script 9: "I deleted 447 files" (episode 9, 15 s)

| Time | Picture | Text | Voice |
|---|---|---|---|
| 0-2 | Terminal / Finder: the file count dropping | I deleted 447 files from my game. | |
| 2-8 | Gameplay running | It never used them. | "The game never loaded a single one of them." |
| 8-15 | A rally | | "It still plays exactly the same." |

---

## Part 4: Filming checklist (every script)

- [ ] The stake is real: number, commit, or your own fact.
- [ ] Footage is the game as a player sees it: gameplay camera, HUD on, real speed. Old builds
      are filmed the same way so before and after match.
- [ ] Any AI-vs-AI footage is said so on screen or in the caption.
- [ ] Text is on frame 1; nothing in the bottom 20% or the right 15%.
- [ ] Your voice is yours. Read the line in your own words.
- [ ] Captions for each app, 3-5 hashtags, the searched words in the caption and the text.
- [ ] Logged in `~/viral-reel-log/reels.json` with the 24 h and 7 d numbers.
- [ ] If you use AI to build the game and someone asks, say so plainly: hiding it backfires
      more than using it.
