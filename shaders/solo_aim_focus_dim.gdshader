shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/focus_protection.gdshaderinc"

void fragment() {
	// Blur Off has no screen texture dependency and avoids its back-buffer copy.
	COLOR = vec4(0.018, 0.035, 0.065, strength * background_weight(SCREEN_UV));
}
