// Logical-pixel protection keeps the ball, both players and the aim target
// sharp. HUD and controls are drawn later on their own CanvasLayers.
uniform vec2 viewport_size = vec2(720.0, 1280.0);
uniform vec2 target_uv = vec2(-2.0);
uniform vec2 blue_uv = vec2(-2.0);
uniform vec2 blue_head_uv = vec2(-2.0);
uniform vec2 red_uv = vec2(-2.0);
uniform vec2 red_head_uv = vec2(-2.0);
uniform vec2 ball_uv = vec2(-2.0);
uniform float radius = 70.0;
uniform float strength = 0.14;

float segment_distance(vec2 pixel, vec2 start, vec2 end) {
	vec2 segment = end - start;
	float along = clamp(dot(pixel - start, segment) / max(dot(segment, segment), 0.001), 0.0, 1.0);
	return length(pixel - start - segment * along);
}

float background_weight(vec2 uv) {
	vec2 pixel = uv * viewport_size;
	float target = smoothstep(radius * 0.40, radius, length(pixel - target_uv * viewport_size));
	float blue = smoothstep(radius * 0.38, radius * 0.70, segment_distance(pixel, blue_uv * viewport_size, blue_head_uv * viewport_size));
	float red = smoothstep(radius * 0.32, radius * 0.60, segment_distance(pixel, red_uv * viewport_size, red_head_uv * viewport_size));
	float ball = smoothstep(radius * 0.16, radius * 0.34, length(pixel - ball_uv * viewport_size));
	return target * blue * red * ball;
}
