# Kwento ng Court: barangay story series

Transitions for each reel below: `TRANSITIONS.md`.

A season of short story reels set on the game's barangay court: how pickleball came to a
basketball court, who fought it, who came back to play, and who got more customers. Narrated by
Ate Joy (Voice B, Taglish), with a developer-voice variant (Voice A) for each, for the A/B test in
`BARANGAY_CAST.md`.

**What's real and what's story**
- **Footage is always real gameplay** (gameplay camera, HUD on, real speed; the Believability
  rules in the viral-reel skill). The court really has faded yellow basketball lines under the
  pickleball lines (`shaders/env_floor.gdshader`); there are no hoops.
- **The characters and their stories are fiction.** Ate Joy tells them like neighbourhood
  chismis, so viewers read them as a story.
- **Facts about the real world** (pickleball in the Philippines, health) only come from the
  sources at the end, and only in the A voice or a caption line, said as modestly as the source.
- The Taglish is a draft. Rewrite it the way your barangay talks.

Checked 2026-11-25.

---

## Part 1: The real-world backbone (what the stories rest on)

| Fact | Source | How the series uses it |
|---|---|---|
| Barangay multipurpose courts, subdivision tennis courts and LGU complexes from Baguio to General Santos have added pickleball lines, often through volunteer-led clubs; barangay and LGU courts are often free | Pickleboard (PH guide) | Episode 1: the court gets new lines |
| A village club began in 2024 by lining three makeshift courts on its community basketball area and now has 1,500+ members; the Reclub booking app has 100,000+ Filipino players | Daily Tribune column (Jun 2026, first-person account) | The arc: from tape lines to a whole barangay playing |
| LGUs and private facilities convert unused basketball and tennis courts; a Makati sports centre turns basketball courts into pickleball courts at peak demand | AISAT; Rappler | "Pickleball took the basketball court" is a real Philippine story |
| Malls (SM, Ayala, Robinsons) added pickleball venues to draw people in | Rappler | Business around the courts gains: the pandesal episode's real-world echo |
| Small studies: an hour three times a week for six weeks improved blood pressure, cholesterol and fitness in adults 40-85 (about 15 people); 33 adults 65+ mostly met activity guidelines through pickleball; players over 55 had better balance and leg strength than non-players (14 vs 14); tournament players had lower depression levels (2018) | SilverSneakers and Time (the 6-week study); NC State; Journal of Aging and Physical Activity (PubMed); Time | Episode 3 (Mang Tony) and the benefits episode, said as "small studies suggest", never as medical advice |
| No injury-rate studies found | NC State (future work) | Never say "no injuries" or "safe for everyone" |

**The sensitive part: basketball.** Basketball is the barangay's sport, and "pickleball replaced
basketball" picks a fight with every basketball fan watching. The season uses that tension for
comments, then resolves it: the court is **shared**, and the basketball guys end up playing.
Never mock basketball or its players; the joke is always on the stubborn character, and he wins
something in the end.

---

## Part 2: The players (the six player types in the game, named)

The game's six player looks (`data/sprite_profiles/`, `docs/CHARACTER_VARIANTS_PLAN.md`) become
the barangay's players. Which looks appear in a match is picked per match (yours is your saved
choice), so find the right one in the footage before naming them.

| Game profile | Look | Name | Story |
|---|---|---|---|
| Ace (F) | Athletic, high ponytail, visor | **Carla** | Brought pickleball to the barangay; lined the court with tape herself |
| Power (F) | Strong, top bun, knee brace | **Tess** | The smasher; played volleyball in school |
| Rookie (F) | Petite, short bob, striped socks | **Bea** | College student, picked it up in a week |
| Bruiser (M) | Big, buzz cut, beard | **Kuya Bert** | Basketball centre of the barangay liga; "tennis ng mga lola 'yan" |
| Veteran (M) | Gray crew cut, shades, bucket hat | **Mang Tony** | Ex-MVP of the barangay liga; his knees retired him from basketball |
| Speedster (M) | Lean, curly top fade | **Jomar** | Fastest feet on the street; tricycle driver |

---

## Part 3: Season 1 (10 episodes)

Each episode: 20-30 s, real gameplay footage, Ate Joy narrating (B), on-screen text on frame 1,
a comment prompt, and an A-voice hook for the test. Post in order: it's a serial, and each one
ends with a reason to watch the next ("Abangan...").

### E1. "Dati, basketball court lang 'to" (the court changes)

**Footage:** a wide shot of the slab showing the faded yellow basketball lines under the
pickleball lines; a rally; the crowd.

| Time | Picture | Text | Ate Joy (B) |
|---|---|---|---|
| 0-2 | Close on the faded basketball line, a pickleball bounces on it | Dati, basketball court lang 'to. | "Dati, basketball lang dito." |
| 2-8 | Wide: both sets of lines | | "Tapos isang araw, dumating si Carla, may dalang tape at paddle." |
| 8-15 | A rally | | "Bagong linya, bagong laro. Pickleball daw." |
| 15-22 | The crowd, Kuya Bert's look in the queue if he's there | | "Hindi lahat natuwa." |
| 22-25 | Crowd cheers a point | Abangan: si Kuya Bert. | "Abangan n'yo si Kuya Bert." |

A hook: "Barangay courts in the Philippines are getting pickleball lines. So I put my game on one."
Comment prompt (caption): `May pickleball na ba sa court ng barangay n'yo?`

### E2. "Ayaw ni Kuya Bert" (the doubter)

**Footage:** a point where the Bruiser profile loses to the Rookie (find it by mining matches).

| Time | Picture | Text | Ate Joy (B) |
|---|---|---|---|
| 0-2 | Kuya Bert's smash comes back past him | "Tennis ng mga lola lang 'yan." | |
| 2-10 | The rally from the start | | "'Yan ang sabi ni Kuya Bert. Center ng liga, six-two daw." |
| 10-18 | Bea, the rookie, places it past him | | "Tapos tinalo siya ni Bea. Isang linggo pa lang naglalaro." |
| 18-24 | The point ends; crowd reacts | Abangan: rematch. | "Hindi pa raw tapos. Abangan." |

Comment prompt: `Basketball o pickleball? Sagot sa comments.` (This is the debate episode: reply to
the comments, don't take sides against basketball.)

### E3. "Bumalik si Mang Tony" (the comeback, benefits)

**Footage:** the Veteran profile playing a long point well; the crowd cheering.

| Time | Picture | Text | Ate Joy (B) |
|---|---|---|---|
| 0-2 | Mang Tony wins a point; crowd up | Ex-MVP. Bad knees. Back on court. | |
| 2-9 | His rally | | "Si Mang Tony, MVP ng liga noong '90s. Tumigil nang sumakit ang tuhod." |
| 9-17 | More of the rally | Smaller court. Shorter runs. | "Sa pickleball, mas maliit ang court. Mas maikli ang takbo." |
| 17-24 | He taps paddles with his partner | | "Ngayon, araw-araw na ulit siya dito." |

Caption line (A-voice facts, modest): `Small studies suggest pickleball helps older players' fitness and balance. Mang Tony just likes winning.`
Court sizes if shown: pickleball 20 x 44 ft; a full basketball court is far bigger. Never say it's
gentle on knees as a medical claim: it's Mang Tony's story.

### E4. "Ang pila ni Kuya Boyet" (more pandesal sales)

**Footage:** the pandesal end after the change of ends; the queue during a match; a spectator
walking over to buy.

| Time | Picture | Text | Ate Joy (B) |
|---|---|---|---|
| 0-2 | The queue at the cart, a rally in front | Sino'ng mas masaya sa pickleball? | |
| 2-8 | The cart, steam from the warmer | | "Hindi si Carla. Hindi si Bea." |
| 8-16 | The queue, buyers walking off eating | Si Kuya Boyet. | "Si Kuya Boyet. Mula nang may laro tuwing umaga, humaba ang pila." |
| 16-22 | A spectator leaves the match to buy | | "Pati mga nanonood, bumibili. Malunggay pandesal, mainit pa." |
| 22-26 | The cart drives off | Abangan: si Ate Joy naman. | "Pero hindi lang siya ang kumikita..." |

A hook: "Malls in the Philippines added pickleball courts to bring people in. In my game, the pandesal man noticed first."
Comment prompt: `Ano'ng binibili n'yo pagkatapos ng laro?`

### E5. "Ubos ang yelo" (Ate Joy's own sales)

**Footage:** the sari-sari store with watchers at the window during a long rally; players
between points.

| Time | Picture | Text | Ate Joy (B) |
|---|---|---|---|
| 0-2 | Ate Joy at the counter, a long rally behind | Ubos na naman ang yelo. | |
| 2-12 | The rally goes on and on | | "Pag mahaba ang rally, alam ko na: ubos ang tubig, ubos ang yelo." |
| 12-20 | Point ends; players walk between points | | "Dati, chichirya lang ang benta ko. Ngayon, tubig, towel, pati tape." |
| 20-24 | Back to her | Abangan: ang schedule. | "Pero may problema. Gusto rin ng basketball ang court." |

Keep it brand-free (no product names).

### E6. "Ang schedule" (the conflict resolves)

**Footage:** the court, the scorer's table, the queue ("next game"), a point.

| Time | Picture | Text | Ate Joy (B) |
|---|---|---|---|
| 0-2 | The queue waiting | Basketball vs pickleball: sino'ng may court? | |
| 2-10 | A rally | | "Nagreklamo ang liga. Sa kanila raw ang court." |
| 10-16 | Mang Ben at the table | Umaga: pickleball. Hapon: basketball. | "Si Mang Ben ang nag-ayos. Umaga, pickleball. Hapon, basketball." |
| 16-24 | The queue; if the Bruiser profile is in it, hold on him | | "At hulaan n'yo kung sino'ng nasa pila ng pickleball tuwing umaga." |

Comment prompt: `Paano hinati ang court sa barangay n'yo?`

### E7. "Rematch" (Kuya Bert converts)

**Footage:** a match where the Bruiser profile wins a point with a big smash (and, if possible,
a point against the Rookie).

| Time | Picture | Text | Ate Joy (B) |
|---|---|---|---|
| 0-2 | Kuya Bert's smash winner | Rematch. | |
| 2-12 | The point | | "Isang buwan nag-ensayo si Kuya Bert. Pati umaga." |
| 12-18 | Smash, the point, the crowd | | "Ayun. Center pa rin, pero sa kitchen na." |
| 18-24 | Paddle tap with his partner | Basketball pa rin daw siya. Weekends. | "Basketball pa rin daw siya. Pag weekend." |

### E8. "Si Bea" (anyone can learn it)

**Footage:** the Rookie profile in a point, dinks and a winner.

| Time | Picture | Text | Ate Joy (B) |
|---|---|---|---|
| 0-2 | Bea's winner | One week. | |
| 2-12 | Her dinks | | "Si Bea, college. Hindi marunong ng kahit anong sport." |
| 12-20 | The winner | | "Isang linggo, kaya na niyang makipag-dink kay Carla." |
| 20-24 | Crowd | | "Ang sabi niya: 'Madali lang pala.'" |

A hook: "Pickleball is easy to start and hard to master. My game is built the same way: tap, hold, that's it." (Then it's a G2 reel.)

### E9. "Laban sa kabilang barangay" (the season climax)

**Footage:** the best rally you have: the longest point, a smash, a counter. Real speed; the
game's own slow motion only.

| Time | Picture | Text | Ate Joy (B) |
|---|---|---|---|
| 0-2 | The peak of the rally | Barangay vs barangay. | |
| 2-20 | The rally, continuous | [real shot count] shots. | "Dumayo ang kabilang barangay. Puno ang Monobloc." |
| 20-26 | The winner, the crowd, Bantay barking, the scorer flipping | | "Si Mang Ben, nanginginig sa score." |
| 26-30 | Freeze-free hold on the crowd | Abangan: sino'ng next? | "Sino'ng nanalo? Sa susunod." |

### E10. "Next game" (season finale)

**Footage:** the queue; a final point; everyone the season introduced.

| Time | Picture | Text | Ate Joy (B) |
|---|---|---|---|
| 0-2 | The queue | Sino'ng next game? | |
| 2-14 | Quick shots of each character during a real match: Carla, Tess, Bea, Jomar, Mang Tony, Kuya Bert | | "Dati, basketball court lang 'to." |
| 14-22 | Kuya Boyet's queue; Ate Joy | | "Ngayon, may pila sa court, may pila sa pandesal." |
| 22-26 | A rally, wide | | "At ako? Ubos pa rin ang yelo." |
| 26-30 | Title | Kwento ng Court. Season 1. | "Follow n'yo kami. Season 2, malapit na." |

---

## Part 4: One-off story ideas (outside the season)

- **"Bakit maliit ang court?"**: Ate Joy explains the kitchen to Kuya Bert (a technique reel,
  T3, in B voice).
- **"Pickleball sa ulan"**: only if the game ever gets rain; never fake it.
- **"Ang unang paddle ni Mang Tony"**: paddle choice (the game has paddle options; check
  `video.paddle` before filming).
- **"Tita Baby's predictions"**: she predicts the winner before each point; post the hits and
  misses honestly.
- **Christmas, Fiesta, Undas specials**: only with things the game really shows; the
  banderitas are already there for the fiesta one.

---

## Part 4b: What's next

Season 2, the "ka-barangay" community plan and the game additions they need are
drafts in `drafts/README.md`.

## Part 5: Running the series

Lessons from the script audit (`SCRIPT_AUDIT.md`), applied to every episode:
- Frame 1 is the story's conflict or a question, never the series name: "Kwento ng Court" means
  nothing to a cold viewer. The series name goes in the caption and the last frame.
- The last frame carries the **Pixel Pickleball** wordmark, and the caption says it's a game for
  iPhone (and answers "Android?" once you've decided).
- The dog, the hens and Ate Joy are small at the game's 1/3 resolution: check each is readable
  on a phone at normal size before building an episode around them; crop in (and say "zoomed")
  if needed.
- A/B results on a new account are noise until views are steady: run the A/B from E4 on, not E1.

- Post one episode a week (with the D/G/T reels around it), same day and hour, so it's a habit.
- Facebook Reels first for Filipino viewers; also TikTok and Reels. Title format on every one:
  `Kwento ng Court, E[N]: [title]`.
- Run the A/B (`BARANGAY_CAST.md`, Part 4) on E1, E4, E6 and E8: they have the clearest A-voice
  hooks.
- Answer the basketball vs pickleball comments warmly, in the voice of the series; never insult
  basketball.
- If an episode pops, the next one should come within 2 days, and pin the season's E1.
- Log `"series": "kwento-ng-court", "episode": N, "variant": "A"|"B"` in `reels.json`.

---

## Sources

- https://pickleboard.co/ph/guides/indoor-vs-outdoor-pickleball-philippines
- https://tribune.net.ph/2026/06/23/the-meteoric-rise-of-pickleball-in-phl
- https://aisat.edu.ph/altitude_articles/pickleball-fever-sweeps-the-philippines-the-paddle-sport-taking-the-nation-by-storm/
- https://www.rappler.com/sports/things-to-know-pickleball/
- https://www.rappler.com/sports/philippine-malls-ride-pickleball-popularity/
- https://www.courtly.ph/courts
- https://en.wikipedia.org/wiki/Philippine_Pickleball_Federation
- https://www.silversneakers.com/blog/pickleball-health-benefits-2/
- https://time.com/6209400/is-pickleball-good-exercise-seniors/
- https://news.ncsu.edu/2023/04/pickleball-helps-older-adults-stay-physically-active/
- https://pubmed.ncbi.nlm.nih.gov/42214694/
- https://journals.humankinetics.com/view/journals/japa/aop/article-10.1123-japa.2024-0176/article-10.1123-japa.2024-0176.xml
- https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8391496/
