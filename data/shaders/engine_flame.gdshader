// Rodina-style engine flame (N13, rodina style only): an additive cone out of each nozzle, bright core at the nozzle
// fading to the edge colour and to nothing at the tip, soft at the silhouette, with a fast flicker. ShipEffects sets the
// colours from Rodina's engine particle keys (EGDataParticles.lua CombatEngineMain/CruiseEngineMain), the length from
// the thrust and gear, and intensity 0 hides it.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 core_color = vec3(0.6, 0.95, 1.0);
uniform vec3 edge_color = vec3(0.0, 0.3, 1.0);
uniform float intensity = 1.0;
uniform float seed = 0.0;

varying float along;

void vertex() {
	along = clamp(VERTEX.y + 0.5, 0.0, 1.0); // the mesh spans y -0.5 (nozzle) .. +0.5 (tip)
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float flicker = 0.85 + 0.15 * sin(TIME * 47.0 + seed) * sin(TIME * 31.0 + seed * 2.0);
	vec3 color = mix(core_color, edge_color, smoothstep(0.0, 0.55, along));
	float fade = pow(1.0 - along, 1.6);
	// Seen down its length (from behind the ship) a cone's sides face away from the eye, so the silhouette softening
	// must not take the flame to zero: keep half its strength edge-on.
	float soft = mix(0.5, 1.0, facing);
	ALBEDO = color;
	ALPHA = clamp(intensity * flicker * fade * soft, 0.0, 1.0);
}
