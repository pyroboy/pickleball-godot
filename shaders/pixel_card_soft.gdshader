// Soft pass of the pixel card (motion blur): the pixels a moving part covered for only part of
// the exposure, alpha blended over what is behind. Same code as pixel_card.gdshader
// (pixel_card_body.gdshaderinc); pixel_card_rig.gd keeps both materials' values the same.
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_never, blend_mix;

#define SOFT_PASS
#include "res://shaders/pixel_card_body.gdshaderinc"
