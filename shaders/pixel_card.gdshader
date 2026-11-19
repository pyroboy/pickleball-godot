// 2.5D pixel card: the whole player is ONE mesh (one quad per body part, built by
// pixel_card_rig.gd) sampling a team atlas with exact UVs. Hard alpha cut (scissor,
// no blending), no lighting, no fog. Colours in the atlas are pre-compensated for
// the game's Filmic tonemap (see bake_pixel_cards.py); `gain` lets bright pixels
// reach full white.
//
// Per-actor accent: the team atlas and the other team's atlas differ only on the
// team-coloured pixels (shirt, sleeves, trim). Where they differ, the pixel is
// re-tinted with `accent_color` keeping its shade, so one set of art gives partner
// and opponents their own look. accent_mix = 0 keeps the authored art untouched.
//
// Far tier: `snap` > 1 quantises sampling to snap x snap texel blocks, i.e. the same
// atlas at reduced texel density (stands in for a half-size far atlas).
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_opaque;

uniform sampler2D atlas : source_color, filter_nearest;
uniform sampler2D atlas_other : source_color, filter_nearest;
uniform vec2 atlas_px = vec2(640.0, 440.0);
uniform float gain = 1.0;
uniform float snap = 1.0;
uniform float accent_mix = 0.0;
uniform vec3 accent_color : source_color = vec3(1.0);
uniform float team_ref_lum = 0.2;

void fragment() {
	vec2 uv = UV;
	if (snap > 1.5) {
		vec2 p = UV * atlas_px;
		p = (floor(p / snap) + 0.5) * snap;
		uv = p / atlas_px;
	}
	vec4 c = texture(atlas, uv);
	if (c.a < 0.5) discard;
	vec3 rgb = c.rgb;
	if (accent_mix > 0.5) {
		vec3 o = texture(atlas_other, uv).rgb;
		if (distance(rgb, o) > 0.02) {
			float shade = dot(rgb, vec3(0.2126, 0.7152, 0.0722)) / team_ref_lum;
			rgb = accent_color * clamp(shade, 0.25, 1.0);
		}
	}
	ALBEDO = rgb * gain;
}
