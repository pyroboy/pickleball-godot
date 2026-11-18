# Player sprite variants: six profiles

Six pixel-card looks (3 female, 3 male) so the four players on court look like different
people. Visual only: gameplay, skeleton and timing stay locked (`pose_diff.py` IDENTICAL).

## Status (2026-11-18)

- [x] Paddles: `scripts/graphics/paddle_skin.gd` + `data/paddles.json` (6 designs, textures
  generated at load, nearest filter). Default per profile; human override `video.paddle`.
- [x] Bake tool: `tools/bake_pixel_cards.py` (Python + numpy/PIL, ~5 s per profile).
  Profiles in `data/sprite_profiles/*.json`; writes `assets/pixel_cards/profiles/<id>_{blue,red}.png`
  and a `profiles` entry in `cards_meta.json`. Run Godot `--import` after baking.
- [x] Rig: `pixel_card_rig.gd` picks a profile per player (human: `video.player_profile`,
  AI: one nobody else has, own RNG); falls back to the original team atlas.
- [x] All six profiles baked. Seeded bench with profiles + paddles: poses IDENTICAL, same ms/frame.
- Changed from the approach below: **one atlas per team** instead of a grey atlas + mask, so
  colours stay exact through the tonemap compensation and the shader is untouched.
- [x] Polish pass: selective outline on silhouettes (`OUTLINE`), higher hairlines so faces
  read from the 44 deg camera, smaller bucket hat, colour separation (Ace waistband, Rookie
  tiers, Veteran polo/shorts, Bruiser/Power socks). Review with
  `python3 tools/bake_pixel_cards.py --sheet` -> `logs/sprite_profiles_{blue,red}.png`
  (assembled standing players, on-screen colours, views 0/45/90/135/180/270).
- [x] Fidelity pass: profiles use a 2x finer grid (0.014 m texels, 80 px cells; the rig reads
  each profile's `grid`), pixel-exact face and detail marks (eyes with whites, brows, nose,
  mouth, ears, blush, logo, buttons, laces, finger lines, kneecaps, elbow), hair strands,
  collars, seams, cuffs, toe caps; heads 1.15x / hands 1.3x / shoes 1.1x and heads at a
  30 deg view so faces read.
- [x] Chunky pass (user: "more pixelated, higher quality"): back to 0.028 m texels / 40 px
  cells, bold features only (1-px eyes, hairline, beard, glasses; `DETAIL = False` drops the
  fine marks and muscle bulges), heads 1.25x, a stray-pixel cleanup pass so tone bands read
  clean. `DETAIL = True` with `TEXEL = 0.014`, `CELL = 80` restores the fine version.
- [x] Colour calibration: `tools/calibrate_cards.gd` measures atlas -> screen through the card
  shader, environment and PixelPost (`assets/pixel_cards/card_tonemap_lut.json`); the baker
  inverts it. Screen whites top out at ~218. Re-run it after tonemap or post changes.
  The original team atlases were made for the pre-PixelPost pipeline and now show paler.
- [ ] Not checked on iPhone. Next: shape/colour polish per profile, hand paint (step 6),
  picker UI (step 7), far-court half-size tier.

## Profiles (per sprite part)

| Part      | Ace (F)                  | Power (F)                         | Rookie (F)              | Bruiser (M)                | Veteran (M)                    | Speedster (M)              |
|-----------|--------------------------|-----------------------------------|-------------------------|----------------------------|--------------------------------|----------------------------|
| Build     | Athletic, tall           | Strong, curvy                     | Petite, quick           | Big, broad                 | Older, steady                  | Lean, tall                 |
| head      | High ponytail, visor     | Top bun, wide headband            | Short bob, hair clip    | Buzz cut, full beard       | Gray crew cut, shades, bucket hat | Curly top fade, thin headband |
| torso     | Racerback tank, fuller chest, narrow waist | Fitted tee, fullest chest, broad shoulders | Polo, small chest, slim | Muscle tank, big chest, V shape | Loose polo, slight belly | Compression tee, lean chest |
| shorts    | Pleated mini skirt       | A-line mini skirt over compression shorts | Tiered ruffle mini skirt | Long board shorts      | Knee-length cargo shorts       | Short split running shorts |
| upper_arm | Slim, toned              | Muscular                          | Thin                    | Big biceps, tattoo band    | Average, tan line              | Wiry, defined              |
| forearm   | Wristband (paddle arm)   | Elbow sleeve                      | Sports watch            | Thick, sweatband           | Tanned                         | Compression sleeve         |
| hand      | Standard                 | Taped fingers                     | Small                   | Large                      | Single glove                   | Standard                   |
| thigh     | Long, toned              | Thick                             | Slim                    | Thick                      | Average                        | Long, lean                 |
| shin      | No-show socks            | Knee brace (one side), crew socks | Striped knee-high socks | Calf sleeve                | White crew socks pulled high   | Ankle tape                 |
| shoe      | Low court shoe           | Mid-top                           | Chunky two-tone         | Wide court shoe            | Classic white                  | Bright runners             |

Skin and hair colours are fixed per profile; clothing takes the team colour.

## Outfits

(T) = painted grey in the atlas and tinted with the team colour by the mask; everything
else is a fixed colour.

| Profile   | Top                                      | Bottom                                                   | Socks                              | Shoes                          | Extras                                   |
|-----------|------------------------------------------|----------------------------------------------------------|------------------------------------|--------------------------------|------------------------------------------|
| Ace       | (T) racerback tank, white side panels    | (T) pleated mini skirt, white hem stripe                 | White no-show, team heel tab       | White low court, team stripe   | White visor, (T) wristband               |
| Power     | (T) fitted tee, charcoal raglan sleeves  | Charcoal A-line mini skirt, (T) side panel, black compression shorts | Black crew                | Black mid-top, team sole       | (T) headband, black elbow sleeve, grey knee brace |
| Rookie    | White polo, (T) collar and cuffs         | (T) tiered ruffle mini skirt, white tiers                | White knee-high, team double stripe | Chunky white/pastel           | Hair clip, sports watch                  |
| Bruiser   | (T) muscle tank, dark armholes           | Charcoal long board shorts, (T) side stripe              | Short black + black calf sleeve    | Black wide court, gum sole     | (T) sweatband, tattoo armband            |
| Veteran   | Stone loose polo, (T) chest stripe       | Khaki knee-length cargo shorts                           | White crew pulled high, retro team stripes | Classic white leather  | (T) bucket hat, sunglasses, one glove    |
| Speedster | (T) compression tee, black mesh shoulders | Black split running shorts, (T) hem                     | Low black, ankle tape              | White runners, team heel       | Thin headband, black compression sleeve  |

## Paddles

Today the paddle is one flat yellow mesh (`scenes/paddle.tscn`, head built in
`scripts/paddle_model.gd` with no UVs) and a dark cylinder handle. Replace the look with
realistic paddles; the shape stays the regulation outline in `paddle_dimensions.gd`
because the hitbox uses it (no elongated or wide-body shapes).

Anatomy of each paddle:
- **Face** (front and back surfaces): material + optional graphic. Back can mirror the
  front or carry a smaller logo.
- **Edge guard**: the rim around the head, its own colour.
- **Throat/neck**: where the head meets the handle, usually the edge-guard colour.
- **Grip**: spiral-wrapped tape (visible diagonal seams), sometimes a contrasting overgrip.
- **End cap**: small cap at the butt of the handle.

| Paddle       | Face                                        | Graphic                         | Edge guard | Grip                         | Default for |
|--------------|---------------------------------------------|---------------------------------|------------|------------------------------|-------------|
| Raw carbon   | Charcoal carbon twill weave, matte          | Small silver wordmark           | Black      | Black, white overgrip        | Ace         |
| Graphite red | Gunmetal fine-grit graphite                 | Red diagonal slash, lower third | Red        | Red                          | Power       |
| Lilac print  | Lilac fiberglass                            | Dot pattern, white band         | White      | Off-white                    | Rookie      |
| Ember edge   | Black carbon, cross weave                   | Large grey outline block mark   | Burnt orange | Black                      | Bruiser     |
| Walnut       | Wood grain (classic wood paddle)            | Burned circle stamp             | Thin dark wood edge | Worn brown          | Veteran     |
| Sunset fade  | Navy                                        | Stepped coral/amber bands, bottom | Amber    | Navy                         | Speedster   |

Names are generic; no real brand logos. Paddles don't take team colours, and any player can
use any paddle.

Implementation (visual only):
- The paddle is a child of `BodyPivot` (`player_body_builder.gd:81`), so no meshes may be
  added there. Add a `PaddleSkin` node beside the card rig (outside `BodyPivot`) that copies
  the paddle's interpolated transform every frame, like `pixel_card_rig.gd`. Move the
  original paddle meshes to the hidden classic layer; leave its collision shapes untouched.
- Skin mesh: rebuild the head from the same `D.head_outline()` with UVs and three surfaces
  (front face, back face, edge guard). The handle is a cylinder with a spiral-tape texture,
  plus a neck piece and an end cap.
- Textures: small (64 x 128 face, 32 x 64 grip), nearest filter so they sit in the pixel
  look; unshaded or lightly shaded to match the cards. One material set per design, cached.
- Data: `data/paddles/<id>.json` (face texture, back texture, edge/grip/cap colours) so new
  designs are data only.

## Constraints from the current rig

- Cards span joint to joint (`pixel_card_rig.gd` `_add`, anchor/end per part), so **limb
  lengths and height come from the gameplay skeleton and cannot differ per profile**.
  "Tall" or "petite" can only be suggested with silhouette width, head/hair size and shoe
  sole. No per-profile scale factor.
- Bulk (bigger arms, chest, belly, skirt flare, ponytail) is painted inside the existing
  40x40 cells; nothing is added under `BodyPivot`.
- The skirt is the `shorts` card on the hips; the ponytail and hat brim stay in the `head` cell.
- `scripts/game.gd:348` seeds the global RNG for benches, so profile picks must use their
  own `RandomNumberGenerator`; global `randi()` would change gameplay.
- The tool that baked `assets/pixel_cards/` is not in the repo
  (`docs/VISUAL_PASS_PLAN.md` step 3 adds `tools/bake_pixel_cards.gd`). Variants build on it.

## Approach

**One neutral atlas per profile plus a team-tint mask**, not 12 team-coloured sheets.

- `assets/pixel_cards/profiles/<id>.png`: same 16 x 9 grid, 40 px cells, clothing painted in
  grey shades, skin/hair/accessories in final colours.
- `assets/pixel_cards/profiles/<id>_mask.png`: same grid, red channel = how much the team
  colour applies (1 on jersey/skirt/shorts, 0 on skin, hair, shoes).
- `shaders/pixel_card.gdshader`: add `mask` sampler and `team_color` uniform:
  `rgb = mix(c.rgb, luma(c.rgb) * team_color, m)`. This also covers the planned per-actor
  accent (partner vs opponents) and Phase 3's "team palette-swap shader".
- `cards_meta.json`: add `"profiles": {"ace": {...}, ...}` with atlas/mask paths and
  optional per-part anchor overrides; shared anchors otherwise (same skeleton).
- Draw calls and card count per player stay the same (9 parts, 15 cards); memory is
  6 x 2 small PNGs (~6 KB each today).

## Steps (one commit each, on `visual-pass`)

1. **Bake tool with body params.** Finish `tools/bake_pixel_cards.gd` (VISUAL_PASS_PLAN
   step 3) and let it take a profile file (`data/sprite_profiles/<id>.json`): limb girth,
   chest, waist/hip, belly, bottom type (shorts/skirt shape), hair/hat mesh, sock/shoe
   style, skin/hair colours. Output atlas + mask + meta entry. Re-bake the current look
   first and check it matches today's cards.
2. **Shader + rig support.** Mask/tint in the shader; rig reads a profile id for each
   player, loads and caches that profile's textures once (static dictionary), sets
   `team_color`. Falls back to today's `cards_blue/red.png` when no profile is set.
   Bench + `pose_diff.py` must say IDENTICAL.
3. **First pair: Ace + Bruiser.** Bake, check in `tools/pose_review.sh` captures and on
   iPhone at gameplay zoom: can you tell the four players apart, does the skirt/ponytail read
   from the far court, any popping between the 16 views.
4. **Remaining four** (Power, Rookie, Veteran, Speedster). Same checks.
5. **Assignment.** Default: four distinct profiles per match, picked with a dedicated
   `RandomNumberGenerator` (visual-only seed), human player keeps a saved choice in
   settings (`video.player_profile`). Partners never share a profile.
5b. **Paddles.** `PaddleSkin` with the six designs; default design per profile, the human
   player's choice saved in settings (`video.paddle`). Bench + `pose_diff.py` IDENTICAL.
   Independent of steps 1-4, so it can ship first.
6. **Hand polish (Phase 3).** Paint over the 5 key views per part (front, 3/4, side,
   3/4 back, back; mirrors fill the rest) where the bake looks generic: faces, hair,
   skirt pleats.
7. **Picker UI (Phase 5, optional).** Profile choice on the title/settings screen.

## Checks every step

- `tools/bench.sh` twice (before/after) -> `python3 tools/pose_diff.py` = IDENTICAL.
- `python3 tools/perf_report.py`: no frame-time change (same card count, one extra texture
  sample per pixel).
- `tools/pose_review.sh` captures per profile for silhouette checks.

## Open questions

- Bake from a parametric 3D body (fast, consistent across 16 views) or hand-paint from the
  start (better look, ~270 cells for 5 views x 9 parts x 6 profiles)? Plan assumes bake,
  then paint over.
- Human player picks their profile now (step 5) or only once the picker UI exists?
- Far-court half-size tier (ROADMAP Phase 1) doubles the bake output; do it in the same
  tool run.
