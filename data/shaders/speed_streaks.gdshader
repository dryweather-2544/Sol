// Rodina-style high-speed streak field. The trailer's COMBAT SPEED sequence shows large stepped
// blue/white streaks crossing the view. This is an additive screen effect under the HUD, not a
// replacement for the 3D exhaust trails. It is intentionally gated by speed and VisualStyle.
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;
uniform vec3 tint = vec3(0.55, 0.76, 1.0);

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

float streak_layer(vec2 uv, float rows, float speed_scale, float offset) {
	float row = floor(uv.y * rows);
	float seed = hash(row + offset);
	// Long horizontal smears, not short rain dashes: the reference's speed field is a dense
	// blue-white wash with visible length, strongest toward the left edge.
	float x = fract(uv.x * 0.42 - time * (0.18 + seed * 0.40) * speed_scale + seed * 11.0);
	float line = smoothstep(0.62, 0.98, sin((x + row * 0.11) * 6.2831853));
	float dash = smoothstep(0.08, 0.65, sin((x * 5.0 + row * 0.9 + offset) * 3.14159));
	return line * dash;
}

void fragment() {
	vec2 uv = UV;
	// Two line scales keep the field from reading as a regular venetian blind.
	float s = streak_layer(uv, 150.0, 1.0, 0.0) + 0.55 * streak_layer(uv, 83.0, 1.7, 3.0);
	// The reference is strongest away from the exact screen centre, leaving the ship readable.
	float centre_fade = smoothstep(0.05, 0.34, abs(uv.y - 0.5));
	float left_weight = smoothstep(0.00, 0.10, uv.x) * (1.0 - smoothstep(0.32, 0.72, uv.x));
	float edge_fade = smoothstep(0.0, 0.12, uv.y) * (1.0 - smoothstep(0.88, 1.0, uv.y));
	float alpha = clamp(intensity * s * left_weight * centre_fade * edge_fade * 1.55, 0.0, 0.82);
	COLOR = vec4(tint * (0.8 + 0.5 * s), alpha);
}
