shader_type spatial;
// Soft rim of a player's shadow while the lens blur is on (serve aim, slow motion). Same mesh
// and code as card_shadow.gdshader (card_shadow_body.gdshaderinc), drawn after every player's
// solid shadow: only the pixels just outside it, darkened by how much of their surroundings
// is shadow. It tests and writes the same stencil, so it never darkens a pixel a solid shadow
// or another rim already did.
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled, blend_mul, world_vertex_coords;
stencil_mode read, write, compare_not_equal, 64;

#define SOFT_EDGE
#include "res://shaders/card_shadow_body.gdshaderinc"
