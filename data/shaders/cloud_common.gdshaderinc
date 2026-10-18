// Shared by cloud_shell.gdshader (the layer seen from above) and cloud_volume.gdshader (flying through it), so a cloud keeps its shape
// as you descend into it. The weather is one baked 3D Perlin-fbm texture (NoiseTexture3D, tiles seamlessly) sampled at the unit direction
// of a point on the planet (no poles, no seams) and at metre-scale positions for the fine structure.
uniform sampler3D cloud_noise : repeat_enable, filter_linear, source_color;
uniform float coverage : hint_range(0.0, 1.0) = 0.5;  // 0 = clear, 1 = overcast
uniform float seed = 0.0;                              // per-world offset so every planet has its own weather
uniform float drift = 0.0;                             // slow rotation of the weather, radians

// 0..1 noise. The texture is not mip-mapped, so textureLod keeps derivatives (and the seam where fract wraps) out of it.
float cloud_noise_at(vec3 p) {
	return textureLod(cloud_noise, p, 0.0).r;
}

// Where the weather says there are clouds: 0..1 at a unit direction (the large systems with clear sky between them).
float cloud_density(vec3 direction) {
	float c = cos(drift);
	float s = sin(drift);
	vec3 d = vec3(c * direction.x + s * direction.z, direction.y, -s * direction.x + c * direction.z);
	vec3 p = d * 0.9 + vec3(seed * 0.173, seed * 0.057, seed * 0.113);
	float weather = cloud_noise_at(p) * 0.62 + cloud_noise_at(p * 2.3 + 0.37) * 0.38;
	float detail = cloud_noise_at(p * 7.1 + 0.11) * 0.6 + cloud_noise_at(p * 17.3 + 0.71) * 0.4;
	float shape = weather * 0.7 + detail * 0.3;
	// Summed noise clumps around 0.5, so stretch it: otherwise nearly every point is partly clouded and the layer reads as one flat sheet.
	shape = clamp((shape - 0.5) * 2.6 + 0.5, 0.0, 1.0);
	float threshold = 1.0 - coverage;
	return smoothstep(threshold - 0.03, threshold + 0.15, shape);
}
