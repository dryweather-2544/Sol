// Sol original: black sky with stars that fades into a simple blue day sky. The stars are the Sol-Assets starfield panorama when
// starfield_amount is 1 (SpaceEnvironment sets it only if the texture loads), otherwise the original hash-placed stars.
// Panorama mapping is the asset's own (lookdev/shaders/space_sky_starfield.gdshader): u = 0.5 + atan(x, -z) / TAU, v = 0.5 - asin(y) / PI.
// The texture is imported WITHOUT mipmaps (it is always magnified, and derivatives would draw a seam where atan wraps), hence textureLod.
shader_type sky;

uniform sampler2D starfield : source_color, filter_linear, repeat_enable;
uniform float starfield_amount : hint_range(0.0, 1.0) = 0.0;
uniform float daylight : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
// 1 = the original gradient day sky; lowered when the scattering atmosphere shell supplies the sky colour.
uniform float gradient_amount : hint_range(0.0, 1.0) = 1.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise21(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm21(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 4; octave++) {
		value += amplitude * noise21(p);
		p *= 2.03;
		amplitude *= 0.5;
	}
	return value;
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
	vec3 space_color = vec3(0.003, 0.004, 0.010) + stars * (1.0 - daylight);

	vec3 eye = normalize(EYEDIR);
	float sun_amount = max(dot(eye, sun_direction), 0.0);
	float up = clamp(eye.y, 0.0, 1.0);
	float horizon = pow(clamp(1.0 - abs(eye.y), 0.0, 1.0), 5.0);
	// A cool zenith, a desaturated horizon and a warm sun-side haze. This is a skybox grade,
	// not a physical atmosphere: the planet's height field and fog still do the local work.
	vec3 day_color = mix(vec3(0.58, 0.66, 0.74), vec3(0.045, 0.14, 0.34), pow(up, 0.38));
	day_color = mix(day_color, vec3(0.88, 0.78, 0.62), horizon * 0.30);
	day_color += vec3(1.0, 0.86, 0.64) * pow(sun_amount, 96.0) * 1.1;
	float sun_disc = smoothstep(0.99955, 0.99992, sun_amount);
	day_color += vec3(1.0, 0.95, 0.86) * sun_disc * 3.2;
	// High, thin cloud bands. Kept subtle: the point is atmospheric depth, not a weather sim.
	vec2 cloud_uv = vec2(atan(eye.x, -eye.z) * 2.2 + TIME * 0.002, eye.y * 5.0 + TIME * 0.003);
	float cloud = fbm21(cloud_uv);
	float cloud_band = smoothstep(0.50, 0.74, cloud) * smoothstep(0.02, 0.22, eye.y) * (1.0 - smoothstep(0.58, 0.88, eye.y));
	day_color = mix(day_color, vec3(0.80, 0.83, 0.86), cloud_band * 0.22);
	COLOR = mix(space_color, day_color * gradient_amount, daylight);
}
