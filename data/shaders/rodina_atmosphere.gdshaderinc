// Rodina's atmosphere (_atmosphere.h and the RodinaAtmosphereScatter pass), rebuilt from the line-referenced audit in
// research/rodina-starfall-reference/_work/rendering_notes.md §4 (the .fx/.h sources are not in this repository).
// Shared by space_sky.gdshader (looking out from inside or near the air) and atmosphere_rim.gdshader (the shell seen from
// space). Lengths are in planet radii, centred on the planet. Steps, with the audit's _atmosphere.h line numbers:
//   pointAngle = angle between the view ray and the direction to the planet centre (20-34)
//   outHorizon = EaseOutSin(ratio(pointAngle, PlanetRadiusAngle, AtmosphereRadiusAngle))      (37-38)
//   inHorizon  = (pointAngle - PlanetRadiusAngle) / 0.66                                         (41)
//   color      = saturate(1 - Analogue(AltitudeRatio, .25, 1, inHorizon, outHorizon))          (43)
//   depth      = Approach(depth / AtmosphereAltitude, 1, 5)                                      (46)
//   density    = Analogue(AltitudeRatio, .5, 1, depth, color)                                    (48)
//   palette    = lerp(Scatter1, Scatter2, color), lerp(Filter1, Filter2, color)                  (86-103)
//   filter     = saturate(sunset + halo), halo squared and widening through sunset               (58-83)
//   shade      = mean of smoothstep(-.2, .2, dot(toStar, n)) over 10 points along the ray        (223, 284-335)
//   alpha      = density * saturate(AtmosphereDensity) (tint); transmittance 1 - saturate(D - 1) * alpha (8-17, Scatter 20)
// Inferred (not stated in the audit): EaseOutSin's input is clamped to 0..1; the halo/sunset "horizon factor" is color;
// the shade samples run over the part of the ray inside the atmosphere, up to the surface.

uniform bool rodina_atmosphere = false;
uniform vec3 atm_scatter1 = vec3(1.0);
uniform vec3 atm_scatter2 = vec3(1.0);
uniform vec3 atm_filter1 = vec3(1.0);
uniform vec3 atm_filter2 = vec3(1.0);
uniform float atm_density = 1.0;          // AtmosphereDensity
uniform float atm_height = 0.03;          // AtmosphereAltitude / planet radius
uniform float atm_star_halo = 0.05;       // StarHalo
uniform float atm_sunset_star_halo = 0.2; // SunsetStarHalo
uniform float atm_sunset_star_buffer = 0.2; // SunsetStarAngleBuffer
uniform float atm_sunset_horizon_limit = -1.0; // SunsetHorizonLimit
uniform float atm_star_radius_angle = 0.01; // the star's angular radius, radians

float rodina_analogue(float value, float from_low, float from_high, float to_low, float to_high) {
	float ratio = clamp((value - from_low) / (from_high - from_low), 0.0, 1.0);
	return to_low + ratio * (to_high - to_low);
}

float rodina_approach(float x, float limit, float slope_mult) {
	float slope = limit / abs(slope_mult);
	return limit - slope / (x + slope / limit);
}

// Ray (origin, unit dir) against a sphere of radius r at the origin: (near, far) distances; far < 0 = miss.
vec2 rodina_sphere_hits(vec3 origin, vec3 dir, float r) {
	float b = dot(origin, dir);
	float c = dot(origin, origin) - r * r;
	float h = b * b - c;
	if (h < 0.0) {
		return vec2(-1.0, -1.0);
	}
	h = sqrt(h);
	return vec2(-b - h, -b + h);
}

// eye: viewer position, dir: unit view ray, star: unit direction toward the star, depth: distance to what the ray hits
// (a large number for the sky). Returns rgb (shaded) and alpha; filter_amount gets the halo/sunset blend.
vec4 rodina_atmosphere_at(vec3 eye, vec3 dir, vec3 star, float depth, out float filter_amount) {
	float d = max(length(eye), 1.0);
	float outer = 1.0 + atm_height;
	float altitude_ratio = (d - 1.0) / atm_height;
	vec3 to_centre = -eye / d;
	float point_angle = acos(clamp(dot(dir, to_centre), -1.0, 1.0));
	float planet_angle = asin(clamp(1.0 / d, 0.0, 1.0));
	float atmosphere_angle = asin(clamp(outer / d, 0.0, 1.0));
	float out_ratio = (point_angle - planet_angle) / max(atmosphere_angle - planet_angle, 1e-5);
	float out_horizon = sin(clamp(out_ratio, 0.0, 1.0) * 1.5707963);
	float in_horizon = (point_angle - planet_angle) / 0.66;
	float color = clamp(1.0 - rodina_analogue(altitude_ratio, 0.25, 1.0, in_horizon, out_horizon), 0.0, 1.0);
	float depth_factor = rodina_approach(depth / atm_height, 1.0, 5.0);
	float density_factor = rodina_analogue(altitude_ratio, 0.5, 1.0, depth_factor, color);

	vec3 scatter = mix(atm_scatter1, atm_scatter2, color);
	vec3 filter_color = mix(atm_filter1, atm_filter2, color);

	float star_planet_angle = acos(clamp(dot(star, to_centre), -1.0, 1.0));
	float star_horizon = rodina_analogue(abs(planet_angle - star_planet_angle), atm_star_radius_angle + atm_sunset_star_buffer, 0.0, 0.0, 1.0);
	float star_angle = dot(dir, star);
	float halo_max = cos(atm_star_radius_angle);
	float halo_min = rodina_analogue(star_horizon, 0.0, 1.0, halo_max - atm_star_halo, halo_max - atm_sunset_star_halo);
	float halo = rodina_analogue(star_angle, halo_min, halo_max, 0.0, 1.0);
	halo *= halo;
	float sunset = color * star_horizon * rodina_analogue(star_angle, atm_sunset_horizon_limit, 1.0, 0.0, 1.0);
	filter_amount = clamp(sunset + halo, 0.0, 1.0);

	// Day brightness: 10 samples over the stretch of the ray inside the air (and in front of the surface).
	vec2 hits = rodina_sphere_hits(eye, dir, outer);
	float start = max(hits.x, 0.0);
	float finish = min(hits.y, depth);
	float brightness = 0.0;
	if (hits.y > 0.0 && finish > start) {
		for (int i = 0; i < 10; i++) {
			vec3 p = eye + dir * mix(start, finish, (float(i) + 0.5) / 10.0);
			brightness += smoothstep(-0.2, 0.2, dot(star, normalize(p)));
		}
		brightness /= 10.0;
	} else {
		density_factor = 0.0;
	}
	vec3 rgb = mix(scatter, filter_color, filter_amount) * brightness;
	return vec4(rgb, density_factor * clamp(atm_density, 0.0, 1.0));
}
