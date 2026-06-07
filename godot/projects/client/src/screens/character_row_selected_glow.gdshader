shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(0.68, 0.18, 1.0, 0.9);
uniform float border_strength : hint_range(0.0, 1.0) = 0.85;
uniform float fill_strength : hint_range(0.0, 1.0) = 0.06;

void fragment() {
	float edge_x = 1.0 - smoothstep(0.0, 0.045, min(UV.x, 1.0 - UV.x));
	float edge_y = 1.0 - smoothstep(0.0, 0.07, min(UV.y, 1.0 - UV.y));
	float border = max(edge_x, edge_y);
	float pulse = 0.78 + 0.22 * sin(TIME * 3.0);
	float alpha = fill_strength + border * border_strength * pulse;
	COLOR = vec4(glow_color.rgb, glow_color.a * alpha);
}
