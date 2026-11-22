shader_type canvas_item;

varying vec4 v_modulate;
uniform vec4 ink_color : source_color = vec4(0.065, 0.05, 0.06, 1.0);
uniform float edge_ink_strength : hint_range(0.0, 1.0) = 0.65;

void vertex() {
	v_modulate = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float a = smoothstep(0.05, 0.88, tex.a);
	float inner_mask = smoothstep(0.08, 0.58, tex.a);
	vec3 clean_rgb = mix(ink_color.rgb, tex.rgb, mix(1.0, inner_mask, edge_ink_strength));
	COLOR = vec4(clean_rgb * v_modulate.rgb, a * v_modulate.a);
}
