shader_type spatial;
// Beach world geometry (fence, pier, banner frame): vertex colours that are already
// tonemap-compensated sRGB (tools/bake_beach_sprites.py palette), drawn unshaded with
// the sprites' gain so built pieces and sprites match.
render_mode unshaded, fog_disabled, shadows_disabled;

uniform float gain = 2.2;

void fragment() {
	vec3 s = COLOR.rgb;
	vec3 lin = mix(s / 12.92, pow((s + 0.055) / 1.055, vec3(2.4)), step(0.04045, s));
	ALBEDO = lin * gain;
}
