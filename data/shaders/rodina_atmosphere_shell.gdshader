// Rodina's atmosphere seen from outside (rodina style): a sphere the size of the atmosphere drawn over the planet and
// space with Rodina's atmosphere maths (rodina_atmosphere.gdshaderinc), added over the scene with Rodina's transmittance
// (RodinaAtmosphereScatter). Replaces Sol's additive rim (atmosphere_rim.gdshader) in the rodina style. Invisible from inside (back faces culled).
shader_type spatial;
render_mode unshaded, blend_premul_alpha, cull_back, depth_draw_never, shadows_disabled, fog_disabled;
#include "res://data/shaders/rodina_atmosphere.gdshaderinc"

uniform vec3 planet_centre = vec3(0.0); // render space, metres
uniform float planet_radius = 1.0;      // metres
uniform vec3 sun_direction = vec3(0.0, 0.0, -1.0); // direction the light travels

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 eye = (CAMERA_POSITION_WORLD - planet_centre) / planet_radius;
	vec3 dir = normalize(world_position - CAMERA_POSITION_WORLD);
	vec2 ground = rodina_sphere_hits(eye, dir, 1.0);
	float depth = ground.x > 0.0 ? ground.x : 1.0e6;
	float filter_amount;
	vec4 air = rodina_atmosphere_at(eye, dir, -normalize(sun_direction), depth, filter_amount);
	// RodinaAtmosphereScatter: the scatter colour is added, and what lies behind is kept by the transmittance
	// 1 - saturate(AtmosphereDensity - 1) * alpha, so a thin air (Jarilo) tints the ground and a thick one (Veles) hides it.
	// Over the ground the full additive scatter washed Jarilo out to a flat pale disc; the owner's orbit screenshot keeps a
	// tan surface with a soft glow at the limb, so the scatter is scaled down where the ray reaches the ground (inferred:
	// the audit does not give the exact compositing of the scatter and filter passes over terrain).
	float over_ground = ground.x > 0.0 ? 0.35 : 1.0;
	ALBEDO = air.rgb * air.a * over_ground;
	ALPHA = clamp(clamp(atm_density - 1.0, 0.0, 1.0) * air.a, 0.0, 1.0);
}
