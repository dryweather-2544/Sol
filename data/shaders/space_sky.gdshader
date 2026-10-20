// Sol original: black sky with stars that fades into a simple day sky. The stars are the Sol-Assets starfield panorama when
// starfield_amount is 1 (SpaceEnvironment sets it only if the texture loads), otherwise the original hash-placed stars.
// Panorama mapping is the asset's own (lookdev/shaders/space_sky_starfield.gdshader): u = 0.5 + atan(x, -z) / TAU, v = 0.5 - asin(y) / PI.
// The texture is imported WITHOUT mipmaps (it is always magnified, and derivatives would draw a seam where atan wraps), hence textureLod.
// Visual-style uniforms (VisualStyle / PlanetLook) default to the original constants, so the Sol style is unchanged. The Rodina
// style sets a per-planet two-colour gradient, a sun disc with a squared halo that widens toward the horizon and a sunset tint
// on the sun-facing horizon (technique from research rendering_notes §4.3; constants are Sol's own).
shader_type sky;

uniform sampler2D starfield : source_color, filter_linear, repeat_enable;
uniform float starfield_amount : hint_range(0.0, 1.0) = 0.0;
uniform float daylight : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);

uniform vec3 space_color = vec3(0.004, 0.005, 0.012);
uniform float star_gain = 1.0;
uniform vec3 star_tint = vec3(1.0);
uniform float star_gamma = 1.0; // >1 darkens the dim (dusty) parts of the panorama more than the bright stars
uniform vec3 sky_zenith = vec3(0.15, 0.32, 0.65);
uniform vec3 sky_horizon = vec3(0.55, 0.7, 0.9);
uniform float gradient_scale = 0.5;
uniform float gradient_bias = 0.5;
uniform float gradient_power = 1.0;
uniform vec3 legacy_glow_color = vec3(1.0, 0.9, 0.7);
uniform float legacy_glow = 0.8;
uniform vec3 sun_color = vec3(1.0);
uniform float sun_disc_gain = 0.0;
uniform float sun_halo_gain = 0.0;
uniform float sun_halo_width = 0.12;
uniform float sunset_halo_width = 0.45;
uniform vec3 sunset_color = vec3(1.0, 0.5, 0.2);
uniform float sunset_gain = 0.0;
uniform vec3 up_direction = vec3(0.0, 1.0, 0.0); // local up of the viewer (the sky's horizon follows the planet surface)
uniform float local_up_amount = 0.0; // 0 = the original world-Y gradient, 1 = gradient and sunset measured against up_direction

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 cell = floor(EYEDIR * 260.0);
	float star_roll = hash13(cell);
	float brightness = step(0.994, star_roll) * (0.4 + 0.6 * hash13(cell + 7.7));
	vec3 stars = vec3(brightness);
	if (starfield_amount > 0.5) {
		vec3 direction = normalize(EYEDIR);
		vec2 uv = vec2(0.5 + atan(direction.x, -direction.z) / TAU, 0.5 - asin(clamp(direction.y, -1.0, 1.0)) / PI);
		stars = textureLod(starfield, uv, 0.0).rgb;
	}
	stars = pow(max(stars, vec3(0.0)), vec3(star_gamma)) * star_gain * star_tint;
	vec3 space = space_color + stars * (1.0 - daylight);

	vec3 up = normalize(up_direction);
	float elevation = mix(EYEDIR.y, dot(EYEDIR, up), local_up_amount);
	float sun_amount = max(dot(EYEDIR, sun_direction), 0.0);
	float t = pow(clamp(elevation * gradient_scale + gradient_bias, 0.0, 1.0), gradient_power);
	vec3 day_color = mix(sky_horizon, sky_zenith, t);
	day_color += legacy_glow_color * pow(sun_amount, 64.0) * legacy_glow;

	// Rodina-style sun: how close the sun is to the viewer's horizon drives the halo width and the sunset tint.
	float sun_height = dot(sun_direction, up);
	float near_horizon = 1.0 - smoothstep(0.0, 0.35, abs(sun_height));
	float angle = acos(clamp(dot(normalize(EYEDIR), sun_direction), -1.0, 1.0));
	float halo = 1.0 - smoothstep(0.0, mix(sun_halo_width, sunset_halo_width, near_horizon), angle);
	halo *= halo;
	float disc = 1.0 - smoothstep(0.0085, 0.0105, angle);
	vec3 eye_flat = normalize(EYEDIR - up * dot(EYEDIR, up) + vec3(1e-5));
	vec3 sun_flat = normalize(sun_direction - up * sun_height + vec3(1e-5));
	float facing = smoothstep(-0.2, 0.8, dot(eye_flat, sun_flat));
	float horizon_band = 1.0 - t;
	day_color += sun_color * (halo * sun_halo_gain + disc * sun_disc_gain);
	day_color = mix(day_color, sunset_color, clamp(near_horizon * facing * horizon_band * sunset_gain, 0.0, 1.0));

	// A sun disc on the black sky of airless worlds and space, too (Rodina draws the star there: RodinaStar).
	space += sun_color * disc * sun_disc_gain * (1.0 - daylight) + sun_color * halo * halo * sun_halo_gain * 0.3 * (1.0 - daylight);
	COLOR = mix(space, day_color, daylight);
}
