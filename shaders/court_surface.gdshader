shader_type spatial;
render_mode diffuse_burley;
uniform vec4 court_color : source_color = vec4(0.16,0.32,0.52,1.0);
void fragment() {
 vec2 p = floor(UV * 900.0);
 float grain = fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453)-0.5;
 ALBEDO = court_color.rgb + vec3(grain*0.018);
 ROUGHNESS = 0.93;
 METALLIC = 0.0;
}
