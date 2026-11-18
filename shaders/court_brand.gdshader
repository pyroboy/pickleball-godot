shader_type spatial;
render_mode unshaded,cull_disabled,depth_draw_never;
uniform sampler2D logo_texture : source_color,filter_linear_mipmap;
uniform vec4 ink : source_color = vec4(0.82,0.88,0.86,1.0);
void fragment() {
 vec4 mark = texture(logo_texture,UV);
 ALBEDO = ink.rgb;
 ALPHA = mark.a * ink.a;
}
