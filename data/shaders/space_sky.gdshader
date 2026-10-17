// Sol original: black sky with hash-placed stars that fades into a simple blue day sky.
shader_type sky;

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
	vec3 space_color = vec3(0.004, 0.005, 0.012) + vec3(brightness) * (1.0 - daylight);

	float sun_amount = max(dot(EYEDIR, sun_direction), 0.0);
	vec3 day_color = mix(vec3(0.55, 0.7, 0.9), vec3(0.15, 0.32, 0.65), clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0));
	day_color += vec3(1.0, 0.9, 0.7) * pow(sun_amount, 64.0) * 0.8;
	COLOR = mix(space_color, day_color, daylight);
}
