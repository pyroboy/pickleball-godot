# Barangay cast and A/B reel scripts

Transitions for each reel below: `TRANSITIONS.md`.

The people (and animals) around the court, named, with what they really do in the game, and
reel scripts in two voices:

- **A: Developer voice.** You, in first person: "I made the pandesal cart a motor sidecar
  because..." Craft, decisions, numbers.
- **B: Barangay storytelling.** "Kwento ni Ate Joy": the sari-sari store tindera, who sees
  everything from her window, introduces her neighbours. Warm, Taglish, chismis tone.

Same footage, same length, two voices: that's the A/B. How to run it is in Part 4.

Every behaviour listed is in the code today (`scripts/environment/barangay_world.gd`,
`pandesal_end.gd`, checked 2026-11-25). The names and backstories are fiction for the
storytelling voice; the behaviour on screen is real.

The Taglish lines are a draft. Rewrite them the way you and your barangay really talk: a line
that sounds translated is the fastest way to lose Filipino viewers (Part 1).

---

## Part 1: How Filipino viewers react to local settings (research, 2026-11-25)

| What we found | Source | What it means here |
|---|---|---|
| *Until Then*, a game set in the Philippines, was praised as one of the most detailed representations of the country in a game; the small local touches got the praise | Video Games Good review; AsAmNews; Rappler interview | Detail is the hook: malunggay pandesal, the jingle, Monobloc chairs, septic-tank stickers on the post, dama, the poso. Show them up close |
| The 2023 "Love the Philippines" tourism video used footage from other countries; Filipinos online caught it, the agency apologised and lost the contract | CNN; Rappler; BenarNews | Viewers check. One wrong detail (a non-Filipino street, a wrong word) gets called out in the comments. Everything shown must be the game and must be right |
| Filipino characters in big games (Josie Rizal in Tekken, Neon in Valorant) were welcomed by many fans, while one academic called Josie "tokenized" | SunStar; Wikipedia (Josie Rizal) | The barangay is the whole world here, not a costume. The cast has dignity: the joke is never that they're poor |
| What goes viral with Filipino audiences: relatable comedy about everyday life, family, exaggerated but recognisable characters, humble-origins stories | Favikon; Spiralytics; Wikipedia (Arman Salon, The Aguinaldos) | The B voice: every barangay has an Ate Joy, a Bantay, a Mang Ben. "Ganito talaga sa amin" is the share |
| Facebook is very strong in the Philippines (one source calls it still no. 1; not confirmed by others) | NGP IMC | The B reels go to Facebook Reels first for Filipino viewers |

Evidence is thin: fan sites, reviews and listicles, not surveys. Nothing measured how Filipinos
react to a barangay in a game specifically. Our own A/B results will be the real answer.

**Rules for the B voice**
- Affection, not mockery. Laugh with them (the dog that barks at every ball), never at being
  poor.
- No stereotypes as punchlines (accents, skin colour, "Filipino time").
- No politics, no religion jokes, no real barangay officials or real people's names.
- Keep it clean: kids are watching, and the cast includes kids.
- Get the words right. If unsure of a word, ask someone from the barangay, not a translator.

---

## Part 2: The cast

One file per character, with lines, episode ideas and a reel log: `cast/README.md`.

| Name | Who | What they really do in the game | Where |
|---|---|---|---|
| **Ate Joy** | Tindera of the sari-sari store; the B narrator | Stands behind the counter with two watchers at the window | Hall end |
| **Kuya Boyet** | Malunggay pandesal vendor | Drives in on a motorcycle with a bright green steel sidecar cart, gets off, opens the wing doors; a queue forms; rolls come out of the warmer in a puff of steam; buyers walk off eating. Busy spells come and go. He closes up, drives off, comes back later, taking turns with the jeepney. Spectators sometimes walk over to buy | Pandesal end (seen after the change of ends) |
| **Mang Ben** | Scorer at the table | Flips the score cards every time the score changes | Beside the far half |
| **Migs** | Ball kid | Fetches the ball between points and passes it to the server | Around the court |
| **Bantay** | The court dog | Barks when the ball lands within 4 m of him, and on every big point | Hall end |
| **Inday** | The hen | Walks with her chicks trailing in a line; scatters when a ball lands near; her chicks run | Hall end |
| **Lolo Pido and Lolo Andoy** | Lolos playing dama | Play dama all match | Pandesal end |
| **Bunso** | Kid at the poso | Pumps water at the poso | Pandesal end |
| **Aling Nena** | Carinderia cook | Cooks for diners at the long table | Pandesal end |
| **Kuya Rey** | Vulcanizing shop mechanic | Works at the shop | Pandesal end |
| **Pogi** | The rooster | In his cage | Pandesal end |
| The wall cats | Cats on the hollow-block wall | Sit on the wall | Pandesal end |
| **Tito Nonoy** | The nonchalant spectator | On his phone the whole match, even during the rally | Crowd |
| **Tita Baby** | The chatty spectator | Chats with whoever sits next to her; cheers on big points | Crowd |
| **Kuya Tolits** | The sleepy spectator | Dozes off in his seat, rally or not | Crowd |
| **Mang Celso** | The grumpy spectator | Arms crossed | Crowd |
| "Next game" | The queue beside the court | Waiting their turn | Beside the far half |

The crowd's personalities (fan, calm, nonchalant, grumpy, sleepy, chatty) are real traits in the
code. Which seat each named one has is random per match, so find them in the footage before
naming them on screen. Crowd members flinch when a ball lands within 2.6 m; on a big point the
crowd cheers and passers-by stop to clap.

---

## Part 3: A/B scripts

Each pair uses the **same footage cut** (gameplay camera, real speed, HUD on; the
Believability rules in `~/.claude/skills/viral-reel/SKILL.md`) and changes only the voice,
the overlay text and the caption. 15-25 s each.

### Pair 0: "Meet the barangay" (series opener)

Footage: a point at the hall end; pan of the store, the court dog, the scorer, the crowd; a ball
lands near Bantay; the score flips.

| Time | Picture | A: developer | B: Kwento ni Ate Joy |
|---|---|---|---|
| 0-2 | A rally, the crowd behind | Text: "I put my pickleball game in a barangay." VO: "I set my pickleball game on a barangay court." | Text: "Kwento ni Ate Joy" VO: "Uy, may laro na naman sa court!" |
| 2-7 | The sari-sari store, Ate Joy at the counter | "Everything here is real 3D, drawn as pixel art." | "Ako si Joy, sa sari-sari. Dito ko nakikita lahat." |
| 7-12 | Ball lands near Bantay, he barks | "The dog barks when a ball lands near him." | "'Yan si Bantay. Bawat bola, tinatahulan." |
| 12-17 | Point ends, Mang Ben flips the score | "The scorer flips the cards on every point." | "Si Mang Ben, hindi pa nagkakamali sa score. Ever." |
| 17-22 | Crowd cheers | "Every one of them reacts to the match." | "Abangan n'yo sila. Marami pa akong kwento." |

Captions. A: `I set my pickleball game on a barangay court. Everyone here reacts to the match. #pickleball #indiegame #pixelart` B: `Kwento ni Ate Joy, part 1. Sino'ng may ganitong court sa barangay n'yo? #pickleball #pinoy #barangay`

### Pair 1: Kuya Boyet, the pandesal man

Footage: after the change of ends; the cart driving in during a rally, the queue, steam, buyers
walking off eating, a spectator walking over to buy.

| Time | Picture | A: developer | B: Kwento ni Ate Joy |
|---|---|---|---|
| 0-2 | The cart rolls in behind a rally | Text: "I added a pandesal cart." | Text: "Nandiyan na si Kuya Boyet!" VO: (the cart's jingle, game sound) |
| 2-8 | He parks, opens the doors | "It's a motor sidecar, like the real ones. Malunggay pandesal." | "Tuwing umaga, dumadaan 'yan. Malunggay pandesal, mainit pa." |
| 8-14 | Queue forms, steam from the warmer | "A queue forms. Sometimes it gets busy." | "Pag may laro, mas mahaba ang pila. Pati mga nanonood, bumibili." |
| 14-20 | A spectator leaves to buy; the rally goes on | "Even the crowd walks over to buy." | "'Yan si Tita Baby, kunwari manonood. Pandesal lang pala ang pakay." (only if the buyer is the chatty one) |
| 20-24 | Cart drives off | "Then he drives away and comes back later." | "Bukas ulit, Kuya Boyet!" |

### Pair 2: Bantay, the court dog

Footage: two or three balls landing near Bantay, a big point and his bark, the hen scattering.

| Time | Picture | A: developer | B: Kwento ni Ate Joy |
|---|---|---|---|
| 0-2 | Ball lands near him, he barks | Text: "My game's dog has one rule." | Text: "Si Bantay, referee daw." |
| 2-10 | It happens again | "If a ball lands within 4 metres, he barks." | "Bawat bola na malapit, tahol. Akala mo siya ang nag-o-out." |
| 10-16 | Big point: he barks, the hens scatter | "On a big point he barks anyway." | "Pag maganda ang palo, mas malakas ang tahol. Pati si Inday, takbo." |
| 16-20 | Bantay settles | "Nobody asked for this feature." | "Walang sweldo, pero nandiyan araw-araw." |

### Pair 3: Mang Ben, the scorer

Footage: a close point, then the score flip; the HUD score and Mang Ben's cards agree.

| Time | Picture | A: developer | B: Kwento ni Ate Joy |
|---|---|---|---|
| 0-2 | Mang Ben flips the cards | Text: "The scorer is real." | Text: "Si Mang Ben, scorer since forever." |
| 2-12 | A rally, close finish | "He reads the actual score from the game." | "Hindi 'yan nanonood ng phone. Sa laro lang ang mata." |
| 12-18 | Score changes, flip | "Every point, he flips the cards." | "Kahit sino pa ang mananalo, tama ang score." |
| 18-22 | Back to Tito Nonoy on his phone, if in frame | | "Hindi tulad ni Tito Nonoy." |

### Pair 4: Migs, the ball kid

Footage: between points; Migs runs around the court (not through it), picks up the ball and
passes it to the server.

| Time | Picture | A: developer | B: Kwento ni Ate Joy |
|---|---|---|---|
| 0-2 | Migs passes the ball to the server | Text: "My game has ball kids." | Text: "Si Migs, pinakamabilis sa barangay." |
| 2-10 | He runs around the court for the ball | "They go around the court, never across it." | "Alam niya ang rules: 'wag dadaan sa gitna ng court." |
| 10-16 | Pass to the server, the serve | "The pass he makes is the real ball." | "Isang pasa, tapos serve na. Walang sayang na oras." |

### Pair 5: Inday and her chicks

Footage: Inday walking with the chicks in a line; a ball lands near, they scatter and regroup.

| Time | Picture | A: developer | B: Kwento ni Ate Joy |
|---|---|---|---|
| 0-2 | The hen with chicks trailing | Text: "The chicks follow their mother." | Text: "Si Inday at ang mga anak niya." |
| 2-10 | A ball lands near, they scatter | "When a ball lands near them, they run." | "Pag may bola, takbo lahat. Pero babalik din." |
| 10-16 | They line up behind her again | "Then they fall back in line behind her." | "Sumusunod pa rin sa nanay. Ganyan dapat." |

### Pair 6: The lolos and their dama

Footage: the pandesal end; the lolos at dama while a big rally plays in front. Check in the
footage that they really don't react to the crowd's cheer before using the last line.

| Time | Picture | A: developer | B: Kwento ni Ate Joy |
|---|---|---|---|
| 0-2 | The lolos, not looking up, during a fast rally | Text: "Two lolos who don't care about pickleball." | Text: "Lolo Pido at Lolo Andoy." |
| 2-12 | The rally goes on; they keep playing | "They play dama the whole match." | "Kahit may laban sa court, may sarili silang laban." |
| 12-16 | The crowd cheers; the lolos still don't look | | "Sino kaya mananalo? Doon, o dito?" |

### More episodes, when ready

Aling Nena's carinderia, Kuya Rey's shop, Bunso at the poso, Pogi the rooster, the wall cats,
Tito Nonoy who never looks up, Kuya Tolits asleep, "Next game" waiting forever. Film each only
once you've checked what it does on screen.

---

## Part 4: Running the A/B

The question: does the barangay storytelling voice (B) bring more follows and shares than the
developer voice (A)? And does it differ by audience?

**Setup**
- Same footage cut, same length, same cover frame; only the voice, the overlay and the caption
  change.
- Instagram **Trial Reels** show a reel to non-followers first: post A and B both as trial
  reels, a day apart, at the same hour; share the winner to your followers.
- TikTok has no organic A/B: alternate. Week 1 A on Pair 0, week 2 B on Pair 1, and so on, at
  the same hour. Don't post the same footage twice on one account.
- YouTube Shorts can A/B test titles and thumbnails, not the video; use it for the caption
  hook only.
- Facebook Reels: post B first (Filipino audience).

**Measure** (each app's own analytics, at 24 h and 7 d; log in `~/viral-reel-log/reels.json`
with `"variant": "A"` or `"B"` and `"cast": "Kuya Boyet"`)
- Viewers who stayed past 3 seconds (the hook).
- Average percentage watched.
- Shares and sends per 1,000 views (the main one for B).
- Follows per 1,000 views (the main one overall).
- Comments in Filipino or Taglish vs English (who it reached).

**Decide**
- Don't call it on one pair: run at least four pairs before choosing.
- If B wins with Filipino viewers and A with pickleball players, keep both: B on Facebook and for
  the Filipino audience, A on TikTok, Shorts and Reels for players.
- If a character does well, give them a second episode the next week.

**Who voices B**
- Your voice, or a friend from the barangay. A real voice is part of what makes it believable.
- An AI-generated voice must carry the platform's AI label (TikTok AIGC label, YouTube's
  altered or synthetic content toggle), and Filipino viewers may react badly to it. Not
  recommended.

---

## Sources

- https://www.rappler.com/technology/interview-until-then-developers-polychroma-games-filipino-representation/
- https://asamnews.com/2024/02/08/filipino-lifestyle-culture-landmarks-in-until-then-polychroma-games/
- https://www.videogamesgood.com/post/review-until-then-beautiful-recreation-of-the-philippines-emotional-metaphysical-journey
- https://www.sunstar.com.ph/cebu/lifestyle/7-filipino-game-characters-that-scream-pinoy-pride
- https://en.wikipedia.org/wiki/Josie_Rizal
- https://www.cnn.com/travel/article/philippines-tourism-ad-intl-hnk
- https://www.rappler.com/business/filipinos-online-reactions-ddb-department-tourism-love-the-philippines-campaign/
- https://www.benarnews.org/english/news/philippine/tourism-project-07032023141940.html
- https://www.favikon.com/blog/top-tiktokers-philippines
- https://www.spiralytics.com/blog/top-tiktok-content-creators-in-the-philippines/
- https://en.wikipedia.org/wiki/Arman_Salon
- https://en.wikipedia.org/wiki/The_Aguinaldos
- https://ngpimc.com/tiktok-influencers-philippines/
- https://interaksyon.philstar.com/trends-spotlights/2021/07/07/195428/the-good-and-the-bad-tiktok-users-trend-welcome-to-the-philippines/
