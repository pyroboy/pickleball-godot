shader_type spatial;
// Player cast shadow (visual only): the next_pass of a player's card material
// (pixel_card.gdshader), so it reuses that one dynamic mesh as drawn this frame, same
// vertices and UVs, no extra mesh build. Each world vertex is slid along the sun's light
// direction `light_dir` (= -SunLight.to_sun()) down to the court:
//     x' = x - h * (d.x / d.y), z' = z - h * (d.z / d.y), y' = shadow_y, h = y - ground_y
// so the shadow is the exact silhouette of the pose (feet touch it, jumps and dives lift off).
// The atlas alpha cut (nearest, discard) is the card's own: transparent padding never casts.
//
// One layer, never darker where shadows cross: every shadow pixel tests and writes the
// stencil (`stencil_mode`, value STENCIL_REF), so a pixel already darkened by any player's
// shadow this frame is skipped. Multiplies the ground (court lines stay visible) by
// lerp(1, shadow_color, opacity), and only by what the baked static shadows
// (shadow_mask.gd: texel = opacity there) have not already applied, so a player standing in
// a prop's shadow is not darker: output lerp(1,C,op) / lerp(1,C,mask) = the union by max.
// Opaque cards are already in the depth buffer (this pass is transparent), so the shadow
// never darkens a card in front of it. No TIME: nothing here changes while paused.
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled, blend_mul, world_vertex_coords;
stencil_mode read, write, compare_not_equal, 64;

#include "res://shaders/card_shadow_body.gdshaderinc"
