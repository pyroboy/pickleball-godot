// 2.5D pixel card: the whole player is ONE mesh (one quad per body part, built by
// pixel_card_rig.gd) sampling a team atlas with exact UVs. Hard alpha cut (scissor,
// no blending), no lighting, no fog. Colours in the atlas are pre-compensated for
// the game's Filmic tonemap (see bake_pixel_cards.py); `gain` lets bright pixels
// reach full white.
//
// Per-actor accent: the team atlas and the other team's atlas differ only on the
// team-coloured pixels (shirt, sleeves, trim). Where they differ and the pixel is
// coloured (a white shirt on one team's atlas is red on the other's: it stays white), the
// pixel is re-tinted with `accent_color` keeping its shade, so one set of art gives partner
// and opponents their own look. accent_mix = 0 keeps the authored art untouched.
//
// Golden-hour sun (scripts/graphics/sun_light.gd, `shading` = 1 set by the rig): stepped,
// not smooth. The sun's direction is taken to screen space; each pixel looks a few atlas
// texels toward the sun and away from it along its own part's silhouette:
//   - 1 render pixel from the sun-side edge: thin warm rim (players only; never the ball),
//   - within SUN_BAND texels of the sun-side edge: lit band,
//   - within SHADE_BAND texels of the far edge: shade band tinted toward the shadow colour,
//   - everything else: the authored (calibrated) colour, unchanged.
// `to_sun` follows SunLight.version (the rig re-reads it when the sun turns at a change of ends).
// The material's next_pass (card_shadow.gdshader) draws the same mesh as the player's ground shadow.
// shading = 0 (the default, tools/calibrate_cards.gd) is the plain calibrated card. No TIME:
// nothing here changes while the game is paused. 4 extra texture reads per card pixel.
//
// Far tier: pixel_card_rig.gd swaps `atlas` / `atlas_other` / `atlas_px` to the profile's
// half-size far set; nothing changes here.
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_opaque;

#include "res://shaders/pixel_card_body.gdshaderinc"
