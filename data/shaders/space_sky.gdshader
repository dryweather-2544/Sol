// Sol original: black sky with stars that fades into a simple blue day sky. The stars are the Sol-Assets starfield panorama when
// starfield_amount is 1 (SpaceEnvironment sets it only if the texture loads), otherwise the original hash-placed stars.
// Panorama mapping is the asset's own (lookdev/shaders/space_sky_starfield.gdshader): u = 0.5 + atan(x, -z) / TAU, v = 0.5 - asin(y) / PI.
// The texture is imported WITHOUT mipmaps (it is always magnified, and derivatives would draw a seam where atan wraps), hence textureLod.
shader_type sky;

uniform sampler2D starfield : source_color, filter_linear, repeat_enable;
uniform float starfield_amount : hint_range(0.0, 1.0) = 0.0;
uniform float daylight : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);

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
	vec3 space_color = vec3(0.004, 0.005, 0.012) + stars * (1.0 - daylight);

	float sun_amount = max(dot(EYEDIR, sun_direction), 0.0);
	vec3 day_color = mix(vec3(0.55, 0.7, 0.9), vec3(0.15, 0.32, 0.65), clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0));
	day_color += vec3(1.0, 0.9, 0.7) * pow(sun_amount, 64.0) * 0.8;
	COLOR = mix(space_color, day_color, daylight);
}
