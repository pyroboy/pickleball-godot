shader_type spatial;
// Beach ground decals (visual only): towels and soft blob shadows lying on the sand,
// from one MultiMesh drawn in instance order (towels first, shadows over them).
// CUSTOM = atlas rect like beach_sprite.gdshader. Shadow texels carry their own
// alpha and are not tonemap-compensated (they only darken what is under them).
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform sampler2D atlas : source_color, filter_nearest;
uniform float gain = 2.2;

varying vec4 rect;

void vertex() {
	rect = INSTANCE_CUSTOM;
}

void fragment() {
	float u = rect.z < 0.0 ? 1.0 - UV.x : UV.x;
	vec4 c = texture(atlas, rect.xy + vec2(u * abs(rect.z), UV.y * rect.w));
	if (c.a < 0.02) discard;
	// opaque texels (towels) are compensated colours; translucent ones (shadows) are raw
	ALBEDO = c.a > 0.99 ? c.rgb * gain : c.rgb * 0.6;
	ALPHA = c.a > 0.99 ? 1.0 : c.a * 1.6;
}
