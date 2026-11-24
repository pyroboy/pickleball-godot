# Transition techniques

Every transition technique for Pixel Pickleball reels: what it is, how to film or edit it, when to
use it, and what it must never do. Which reel uses which: `TRANSITIONS.md`.

Researched 2026-11-25 from editing-tool and creator guides (sources at the end). The timings are
rules of thumb, not measured findings; our own reel log decides in the end.

## The ground rules

1. **Transitions live between clips. Inside a clip, the picture is the game as played.** No speed
   ramps, freezes or fake camera moves on gameplay. The game's own slow motion and camera shake
   are fine: they're the game.
2. **Hard cuts for almost everything.** A clean cut on the action or the beat is the strongest
   transition. Save a visible one for the one or two biggest moments of a reel.
3. **Short.** A visible transition lasts 6-12 frames (0.2-0.4 s at 30 fps). Never stack two.
4. **Sound sells the cut.** The paddle pop, the bark or the beat lands on the exact cut frame.
5. **No glow, no white flashes** (house rule).
6. **Direction matters.** Motion that leaves the frame to the right enters the next shot from the
   left. Keep the ball's direction consistent across a cut.

---

## Part A: In-camera and motion transitions

Made while filming. They need a real camera: you on camera, a second phone over your shoulder
filming the iPhone, or real-court footage. The game camera can't do them.

### W. Whip pan

**What:** a fast pan at the end of one clip and the start of the next; the motion blur hides the
cut.
**Film it:** end clip 1 by swinging the phone fast (left or right). Start clip 2 already moving in
the **same direction** at the same speed, then settle. Shoot 2-3 takes of each half.
**Edit it:** cut in the middle of the blur, where both halves are smeared. In CapCut, trim each clip
to the blurriest frame and butt them together; add a soft whoosh on the cut.
**Use for:** you → the phone screen; the real court → the game (P4); two people playing.
**Don't:** fake a whip on gameplay footage with an effect; use it more than once per reel.

### MC. Match cut

**What:** two shots that share a shape, motion or framing, cut at the same point, so one turns
into the other.
**Film it:** lock the framing (tape a mark on the floor, hold the phone at the same height,
shoot 2-3 takes). For game-to-game, use the same seed and camera so the framing matches exactly.
**Edit it:** cut at the peak of the motion (the contact, the top of the bounce), not before or
after.
**Use for:** beach → barangay (D3); 3D → pixel (D5); real swing ↔ game swing (P4); real court ↔
game court (Court of the week); the old hoop ↔ the net (S2E6).
**Don't:** match two shots whose motion goes in opposite directions.

### OW. Object wipe (object pass)

**What:** something fills the lens, the cut happens while it covers the frame, and the next shot
opens from a similar cover.
**Film it:** on the over-the-shoulder phone, swing the paddle (or walk) past the lens close enough
to fill it. Start clip 2 with the same object moving away from the lens.
**Edit it:** cut on the frame where the object covers the most screen.
**Use for:** a lesson → "In my game" (T-series); real play → the phone.

### HC. Hand cover

**What:** your palm covers the lens, the screen goes dark, the cut happens in the dark.
**Film it:** cover the lens at the end of clip 1; start clip 2 covered and pull the hand away.
**Edit it:** cut on the darkest frame.
**Use for:** the drumroll before a number (D8); before → after; the talking opener → the game.

### SR. Spin reveal

**What:** the phone (or you) turns away; the cut happens mid-turn; the turn lands on the new shot.
**Film it:** say your line to the camera, then turn the phone round to the game screen in one
motion.
**Edit it:** cut where the turn is fastest.
**Use for:** "I'm making a pickleball game" → the game itself (D1).

### PZ. Punch-in (snap zoom)

**What:** a quick zoom into a detail on the beat, then back out.
**Film it:** step in fast, or zoom in the edit (crop) on a real frame.
**Edit it:** 4-6 frames in, hold, 4-6 frames out; on the beat. Over 1.5x, write "zoomed" on screen.
**Use for:** small things at phone size: Bantay barking, the score flip, the pandesal steam, a name
on the board, your thumb on the hit pad (G2).
**Don't:** zoom into the ball at contact (it shows the small gap between ball and paddle).

### CS. Camera shake (the game's own)

**What:** the game shakes its camera by ball speed. That's real and can carry a cut.
**Use for:** cut right after a smash's shake for extra punch.
**Don't:** add shake in the edit.

---

## Part B: Storytelling and rhythm transitions

Made in the edit.

### CA. Cut on action

**What:** cut in the middle of a motion (a contact, a bounce, a step); the motion carries the eye
across the cut so it feels seamless.
**Edit it:** put the cut 1-2 frames after the motion starts; continue the motion in the next clip.
**Use for:** the default for every gameplay cut.

### BC. Beat cut

**What:** cut exactly on a beat of the music.
**Edit it:** add beat markers (CapCut can detect them, or tap them in), snap the cut to the marker.
Use the reel's beat sheet: the biggest contact goes on the drop.
**Use for:** the reveal, the winner, a list of types (G8), a montage (E10).
**Don't:** lock every cut to the beat; only the key ones.

### SC. Smash cut

**What:** a hard jump to a contrasting mood or sound: calm → chaos, quiet → loud, claim → proof.
**Edit it:** no transition effect at all; the contrast is the effect. Often pair with a sound
change (music drops in, or cuts out).
**Use for:** beach silence → barangay noise (D3); dinks → the speed-up (G4); "Tennis ng mga lola
lang 'yan" → he loses (E2); the LATE that ends a streak (G3, cut to silence).

### J. J-cut (sound first)

**What:** the next shot's sound starts before its picture, 0.3-1 s early.
**Edit it:** extend the next clip's audio to the left under the current picture.
**Use for:** the pandesal jingle before the cart appears; the bark before Bantay; the crowd roar
before the winner; Ate Joy's voice before her store; the opponent's paddle pop before a smash
(G5).

### L. L-cut (sound carries over)

**What:** the current shot's sound continues over the next picture.
**Edit it:** extend the current clip's audio to the right under the next picture.
**Use for:** your voice over gameplay (devlogs); Bantay's bark over the next shot; the cheer over
the walk back or the next serve.

### JC. Jump cut

**What:** cut time out of one continuous shot; the subject skips forward.
**Edit it:** remove pauses and dead time; keep the camera the same.
**Use for:** talking to camera (D1, D8, technique reels); the walk back between points.
**Don't:** jump-cut inside a rally: it breaks "real speed".

### SS. Split screen

**What:** two clips at once, top and bottom (9:16).
**Edit it:** stack the clips (CapCut overlay, or ffmpeg `vstack`); line them up on the same
moment (the same contact).
**Use for:** before / after (D4); real life vs the game (P4); a follower's court vs the game court.

### RW. Rewind

**What:** a short reverse (0.5 s or less) after the hook, with "earlier..." text, back to the start
of the moment.
**Edit it:** reverse a few frames of the hook clip, then cut to the build-up.
**Use for:** peak-first reels (G1, G4, G5, E2, E7, E9).
**Don't:** play gameplay backwards for longer than half a second.

### LS. Loop seam

**What:** the last frame leads back into the first, so the reel replays without a bump.
**Edit it:** end on a moment that leads into the opening (the next serve, the ball arriving); cut
the last 0.2 s of sound so the opening hit lands cleanly.
**Use for:** every reel.

### PI. Pattern interrupt

**What:** something changes every 3-5 s: the text, a new angle, a punch-in, a counter tick.
**Use for:** long continuous rallies, which must stay uncut: change the text instead (dink counter
in G4, streak counter in G3, Ate Joy's lines in E5).

### DB. Dip to black

**What:** 2-4 black frames between two chapters.
**Use for:** before → after; the end of a story episode into the "Abangan" card; day → night
(S2E5).
**Don't:** open a reel with it (the first frame is the hook).

### Sound bridges

**What:** a sound effect placed exactly on the cut.
**Use for:** every visible transition: a whoosh on a whip, the paddle pop on a match cut, the bark on
a punch-in. Keep the game's own sounds; add few extra effects.

---

## Part C: Matching transitions to the story

| Story shape | Transitions | Reels |
|---|---|---|
| Challenge / speed | CA everywhere, one BC on the winning contact, SC from calm to fast, LS | G1, G4, G5, P1, P2 |
| Before / after | MC or SS on the same frame, DB or HC between them, BC on the reveal | D3, D4, D5 |
| Explainer / devlog with you | JC on your lines, L of your voice over gameplay, W or SR from you to the phone | D1, D8, technique reels |
| Barangay story | J of the character's sound before they appear, L for reactions, SC for the punchline, DB into the end card | Kwento ng Court, A/B pairs |
| POV | Almost none: CA, J of the paddle pop, LS on the ball arriving | P-series |
| Community | MC real court ↔ game court, PZ on names | Court of the week, ka-barangay |
| List / types | BC on each item, one W into the last | G8, E10 |

## Part D: Not for us (and why)

| Technique | Why not |
|---|---|
| Speed ramp on gameplay | Changes the game's real speed: viewers can't get that picture by playing |
| Freeze frame on contact | Shows the small ball-to-paddle gap; reads as a render |
| Bullet time, orbit, director camera | The reels that failed the believability bar |
| White flash, glow, light leak | House rule: no glow |
| Glitch / RGB split | Reads as cheap; hides the pixel art |
| Spinning 3D cube, page turn, star wipes | Template looks; they say "edited", not "played" |
| Long cross-dissolves | Slow; mush two pixel-art frames together |

## Part E: How to make them

| Tool | What it does |
|---|---|
| CapCut (phone or desktop) | All of them by hand; beat markers for BC; audio extend for J/L; overlay for SS |
| `tools/reel_cut.py` (this repo) | Hard cuts and fades today |
| ffmpeg `xfade` | `fadeblack` (DB), `hblur` / `slideleft` (a whip feel between gameplay clips, rarely); `vstack` for SS; J/L by offsetting the audio from the picture cut |

## Sources

- https://www.usevyra.com/ideas/transition-ideas
- https://getmatchframe.com/blog/transition-video-ideas
- https://filmora.wondershare.com/video-editing-tips/in-camera-transition-technique.html
- https://www.insta360.com/blog/tips/how-to-create-film-transitions.html
- https://kling.ai/blog/video-transitions
- https://videowizardtools.com/capcut-transitions-for-reels-tiktok/
- https://foxy-it.com/blog/how-to-create-smooth-transitions-between-clips-on-tiktok/
- https://cutsio.com/blog/j-cut-vs-l-cut-video-editing-guide
- https://adobevideoworld.com/jump-cuts-l-cuts-editing/
- https://captions.ai/blog/six-common-types-of-cuts-in-film
- https://blitzcutai.com/blog/jump-cuts-vs-cross-dissolves-vs-smash-cuts
- https://en.wikipedia.org/wiki/Smash_cut
- https://en.wikipedia.org/wiki/Cut_(transition)
- https://www.kometmedia.com/tutorials/pacing-and-cuts-for-high-retention-short-video
- https://www.capcut.com/create/sports-highlight-editing-beat-synced-ai-reels
- https://cursa.app/en/page/beat-based-editing-in-capcut-syncing-cuts-transitions-and-motion-to-music
- https://blog.frame.io/2023/03/27/editing-game-promo-trailer/
- https://nofilmschool.com/how-to-edit-trailer-music
