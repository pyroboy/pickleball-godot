shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/focus_protection.gdshaderinc"
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float blur_radius = 1.3;
uniform float effect_mix = 1.0;

void fragment() {
	float weight = background_weight(SCREEN_UV);
	vec3 original = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	vec2 step_uv = vec2(blur_radius) / viewport_size;
	// Bounded five-tap filter: no mip generation, extra viewport or CPU readback.
	vec3 blurred = original * 0.40;
	blurred += textureLod(screen_texture, SCREEN_UV + vec2(step_uv.x, 0.0), 0.0).rgb * 0.15;
	blurred += textureLod(screen_texture, SCREEN_UV - vec2(step_uv.x, 0.0), 0.0).rgb * 0.15;
	blurred += textureLod(screen_texture, SCREEN_UV + vec2(0.0, step_uv.y), 0.0).rgb * 0.15;
	blurred += textureLod(screen_texture, SCREEN_UV - vec2(0.0, step_uv.y), 0.0).rgb * 0.15;
	vec3 focused = mix(original, blurred, weight * effect_mix);
	COLOR = vec4(mix(focused, vec3(0.018, 0.035, 0.065), strength * weight), 1.0);
}
