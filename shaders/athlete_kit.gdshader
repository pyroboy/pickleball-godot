shader_type spatial;
render_mode fog_disabled;
varying vec4 kit_color;
void vertex() {
	// Authored palette values are sRGB; vertex attributes are otherwise linear.
	kit_color = vec4(mix(COLOR.rgb / 12.92, pow((COLOR.rgb + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), COLOR.rgb)), COLOR.a);
}
void fragment() {
	ALBEDO = kit_color.rgb;
	ROUGHNESS = 0.88;
	SPECULAR = 0.15;
	// Small baked fill keeps shaded forearms readable with mobile shadows off.
	// This is material color only: no glow pass or extra real-time light.
	EMISSION = kit_color.rgb * 0.12;
}
