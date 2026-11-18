// 2.5D pixel card: one cell of a team atlas, hard alpha cut, no lighting, no fog.
// Colours in the atlas are pre-compensated for the game's Filmic tonemap
// (see make_cards.py), and `gain` lets bright pixels reach full white.
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_opaque;

uniform sampler2D atlas : source_color, filter_nearest;
uniform vec2 cell_offset = vec2(0.0);
uniform vec2 cell_scale = vec2(1.0);
uniform float gain = 1.0;

void fragment() {
	vec4 c = texture(atlas, UV * cell_scale + cell_offset);
	if (c.a < 0.5) discard;
	ALBEDO = c.rgb * gain;
}
