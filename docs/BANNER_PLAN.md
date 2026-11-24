# Banner upgrade plan

Goal: the match's banners look like the pixel UI kit in the 2.5D proposal PDF (page 23
"Big banner" / "Banners", page 24 "Point won" mockup). Visual only: same triggers, same
timing, same place on screen. No gameplay change, so no bench.

## Status (2026-11-23)

Built: `scripts/ui/pixel_draw.gd` (pixel discs / rings / plates / pixel text, shared) and
`scripts/ui/pixel_banner.gd`. Rally result banner (team-colour fill, score line dropped,
reason ribbon gold / plum red), fault call without a human, CHANGE COURT / MATCH POINT,
plus the controls (`mobile_controls.gd`, `hud_chrome.gd`: pixel discs, pixel-font captions)
and the pause menu (PAUSED banner, all text in the pixel font). Kit palette stays dark navy /
teal (user's call: no purple, 2026-11-23; `game_ui_theme.gd`); title, settings and practice follow the kit shapes: buttons and
panels have cut corners, a lighter top lip and the dark bevel. All text is the 5x7 pixel font.
Checked: pause_menu_test 132/132, match run seed 3 (banner rect logged), title smoke check.
Not yet judged on the iPhone.

## Before

| Banner | Code | Look now | Problem |
|---|---|---|---|
| Rally result ("YOUR TEAM SCORES", "SIDE OUT", "SECOND SERVER", "YOU WIN!") + reason + score line | `scripts/ui/hud.gd` `_rally_banner`, text from `scripts/scoreboard_ui.gd` `show_rally_result` / `show_fault` | Dark navy panel, thin lime border, rounded corners, pixel headline, sans reason and score lines | Reads as a dialog box, not a moment. Three lines of text. Pops in with no motion, only fades out |
| Fault call when no human plays | `scoreboard_ui.gd` `_place_fault_banner` (`hud.fault` label) | Separate dark panel, sans text | Second style for the same job |
| CHANGE COURT, MATCH POINT | `scripts/ui/cinematic_banner.gd`, called from `scripts/camera/camera_rig.gd` | Plain sans labels with a black outline over a dim | Breaks the kit's "no black outlines" rule; no panel, no pixel font |

The world stamp (OUT / NET / WINNER!) and the rally counter in `scripts/fx/rally_moments.gd`
stay in 3D. This plan only covers the screen banners.

## Target look (PDF page 23)

- **Big banner:** filled plate in the team colour (blue `4f8ee0`, red `e0645a`), one UI
  pixel lighter top edge, chunky darker bottom bevel, cut (45 degree) corners, white 5x7
  pixel text with a 1 px drop shadow. No black outline. "POINT BLUE!" style.
- **Ribbon (small banner):** the line under it, e.g. "SMASH WINNER +1" in gold, or a
  pill like "SIDE OUT" (plum red) / "NICE DINK!" (gold).
- 1 UI pixel = 3 screen pixels on a 720-wide phone; every size snaps to whole UI pixels.
- Gold only for ball / serve / charge moments (winners, match point).

## Steps

1. **Kit piece: `PixelBanner` control** (`scripts/ui/pixel_banner.gd`). Draws the plate
   itself in `_draw()`: fill, top highlight row, bottom bevel, cut corners, all on the UI
   pixel grid (a StyleBoxFlat can't do a lighter top edge plus a darker bottom). Title label
   in the pixel font with `font_shadow_color` and a one-UI-pixel shadow offset. Sizes:
   `big` and `ribbon`. Add `banner_colors()` to `game_ui_theme.gd` (team blue / red, gold,
   plum red, lime) so every banner uses the same palette.
2. **Rally result banner** (`hud.gd`, `scoreboard_ui.gd`):
   - Headline in a big banner filled with the winning team's colour: "YOUR POINT!",
     "THEIR POINT", "SIDE OUT", "2ND SERVER", "YOU WIN!" (short, pixel font fits).
   - One ribbon under it with the reason or the shot: fault reason from
     `fault_explainer.gd` ("Into the net"), or the winning shot name from `shot_names.gd`
     ("SMASH WINNER"). Gold when it went your way, plum red when it didn't.
   - Drop the score line: the score pill already shows it (PDF goal: UI under 10% of the screen).
   - Motion: slams in (scale 1.25 to 1 in 0.12 s with a small settle, ribbon follows 0.06 s
     later), leaves by sliding up 1 UI pixel step at a time and fading. Same 2.8 s on screen.
   - Placement unchanged (bottom edge just above the net, `_place_rally_banner`).
3. **Fault call without a human:** same ribbon piece instead of the separate panel.
4. **Cinematic banner:** CHANGE COURT as a big banner (plum) with the score as a ribbon;
   MATCH POINT / GAME POINT as a gold big banner that sweeps in from the side. Remove
   the black outline; keep the dim and the tap-to-skip.
5. **Checks (data, not screenshots):** each banner already writes a `rally_banner` /
   `banner` note to `logs/perf.jsonl`; add the drawn rect and font size so a run shows
   it stays on screen and clear of the score pill. Run an all-AI match (seed 3 ends a rally
   at tick ~779) at 720x1280 and a wide size; headless title smoke check. Then judge the
   look on the iPhone.

## Open questions

- Banner fill: the team's colour (as in the mockup: blue / red) or your side's view
  (green when you won, red when you lost)? Plan assumes team colour.
- Drop the score line from the result banner? Plan assumes yes.
