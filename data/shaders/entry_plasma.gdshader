// Sol original: a cheap additive plasma envelope. It is driven by entry heat, not by a fixed
// altitude, and is deliberately soft enough to sit over the hull without hiding the planet.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;

uniform float intensity : hint_range(0.0, 1.5) = 0.0;
uniform vec4 plasma_color : source_color = vec4(1.0, 0.34, 0.06, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.78, 0.36, 1.0);

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, 1.7);
	float bands = 0.72 + 0.28 * sin(NORMAL.y * 17.0 + NORMAL.x * 11.0 + TIME * 5.0);
	float flicker = 0.88 + 0.12 * sin(TIME * 19.0 + NORMAL.z * 9.0);
	vec3 colour = mix(plasma_color.rgb, core_color.rgb, clamp(rim * 1.4, 0.0, 1.0));
	ALBEDO = colour;
	ALPHA = clamp(intensity * (0.003 + pow(rim, 2.2) * 0.085) * bands * flicker, 0.0, 0.16);
}
