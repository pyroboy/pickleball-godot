# DRAFT: Barangay area additions (game ideas)

Status: draft (2026-11-25). Ideas only: nothing here is built. All are visual or sound only, so
gameplay stays locked (`docs/ROADMAP.md`): no collision, nothing under a player's `BodyPivot`,
the environment's own seeded random, the crowd only listening to match events, like the rest of
`scripts/environment/`. Each needs the usual checks when built (motion bench, pose diff
IDENTICAL, no new per-frame cost on the phone).

Ranked by how much story and footage each unlocks.

| # | Addition | Story it unlocks | Size |
|---|---|---|---|
| 1 | **Names board**: next-game board, scorer's chalkboard or a barangay hall bulletin board ("Pabatid") that shows a list of names from a data file | S2E7, the whole community plan | Small: a prop plus a text list |
| 2 | **Old basketball hoop** leaning on the wall behind the court | S2E6; the "court used to be basketball" story in one prop | Small: one prop |
| 3 | **Taho vendor** with his morning call ("Tahooo!"), the two buckets on a pole, kids running to him | S2E4; the morning food war with Kuya Boyet | Medium: a walker with a stop and a queue, like the pandesal cart |
| 4 | **Street sounds**: taho call, sorbetes bell, tricycle, rooster at dawn, jeepney | Identity in every reel, even on small screens | Small to medium: ambient sound events |
| 5 | **Time of day**: morning (taho, pandesal), afternoon, night with court lights (balut vendor) | S2E5 Night game; Season 1's morning/afternoon split shows | Large: lighting presets, lights, vendor swap |
| 6 | **Neighbours**: tambays at the store, kids playing patintero beside the court, a tanod at the hall, the Marites bench | S2E3 and cameos | Medium: new people with traits, like the crowd |
| 7 | **Events**: fiesta (more banderitas, a stage), liga opening, Christmas parols on the poles | S2E8 and seasonal reels | Medium per event |
| 8 | **Sorbetes cart** with its bell | A poll option for "next vendor" | Medium |
| 9 | **Balut vendor** at night | With the night game | Small once night exists |

## Notes

- Pandesal is a morning bread: if time of day is added, Kuya Boyet comes in the morning
  (the stories already say "tuwing umaga").
- Keep each addition readable at the game's 1/3 resolution on a phone; if it's a few pixels at
  the camera's distance, it won't carry a reel.
- Kap, the tanod and the officials stay fictional and non-political.
- The scene-detail work (court-environment) is where these would be built; one at a time,
  each checked on the iPhone.

## Open question for you

Which to build first: the names board (community), the old hoop (story), or the taho vendor
(sound and identity)?
