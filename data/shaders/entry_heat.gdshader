// Sol original: atmospheric-entry heat sheath round the ship's nose (ShipEffects, rodina visual style only). Additive,
// strongest at grazing angles and on the forward (-z) side, fading in with `heat`.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;

uniform float heat : hint_range(0.0, 1.0) = 0.0;

varying vec3 model_position;

void vertex() {
	model_position = VERTEX;
}

void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.5);
	float forward = smoothstep(0.1, -1.0, model_position.z); // brightest at the nose (model -z), gone by mid-hull
	forward *= forward;
	float cap = smoothstep(-0.55, -1.0, model_position.z); // the nose cap itself glows, not just the outline
	vec3 hot = mix(vec3(1.0, 0.3, 0.05), vec3(1.0, 0.75, 0.4), heat);
	ALBEDO = hot * (1.0 + cap);
	ALPHA = clamp((rim + cap * 0.6) * forward * heat * 2.0, 0.0, 1.0);
}
