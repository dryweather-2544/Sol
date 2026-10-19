// Sol original: a screen-space heat vignette for the cockpit and chase views.
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 heat_color : source_color = vec4(1.0, 0.30, 0.04, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float edge = smoothstep(0.35, 1.05, length(p));
	float bands = 0.85 + 0.15 * sin(UV.y * 45.0 + TIME * 4.0);
	COLOR = vec4(heat_color.rgb, edge * intensity * 0.52 * bands);
}
