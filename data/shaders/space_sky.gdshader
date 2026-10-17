// Sol original: near-black sky with hash-placed star points.
shader_type sky;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 cell = floor(EYEDIR * 260.0);
	float star_roll = hash13(cell);
	float brightness = step(0.994, star_roll) * (0.4 + 0.6 * hash13(cell + 7.7));
	COLOR = vec3(0.004, 0.005, 0.012) + vec3(brightness);
}
