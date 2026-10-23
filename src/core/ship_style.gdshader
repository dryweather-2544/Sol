shader_type spatial;
render_mode unshaded;
// Valheim-style metallic ship paint. Fine low-res texels, faceted normals, wrapped sun light with teal
// ambient, a palette recolour (dark / mid / light metal plus one accent used for glowing parts and wing-tip livery), and a small
// controlled metal glint. UNSHADED on purpose: it lights itself with a fixed warm key light and teal ambient (the look of the reference
// renders) instead of depending on the scene's lights, which left the ships near-black. Applied by ShipStyle (src/core/ship_style.gd). Off: SOL_SHIP_STYLE=off.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_albedo_tex = false;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D mr_tex : hint_default_white, filter_linear_mipmap, repeat_enable; // glTF: green = roughness, blue = metal
uniform bool has_mr_tex = false;
uniform float metallic_factor = 0.7;
uniform float roughness_factor = 0.3;
uniform sampler2D emission_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform bool has_emission_tex = false;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 1.0;
// How many texture pixels make one chunky "texel" (bigger = chunkier).
uniform float texel_block = 2.0;
uniform float weathering = 0.10;
uniform float desaturate = 0.18;
uniform float facet_mix = 0.10;
// Glint knobs: glint_strength = sun highlight + crease rims, shine_strength = sky reflection on metal. 0 = matte.
uniform float glint_strength = 0.55;
uniform float shine_strength = 0.30;
// Where the key light comes from, in world space (it does not follow the camera).
uniform vec3 key_dir_world = vec3(-0.5, 0.75, 0.45);
uniform vec3 sky_warm = vec3(1.0, 0.80, 0.52);
uniform vec3 sky_teal = vec3(0.04, 0.09, 0.12);
// Palette recolour (palette_on = false keeps the model's own colours). Palette and sky colours are DISPLAY values (what you see in the
// palette sheet), not linear: all the shading maths below runs in display space, like the reference renders, and is converted at the end.
uniform bool palette_on = false;
uniform vec3 pal_dark = vec3(0.08, 0.1, 0.13);
uniform vec3 pal_mid = vec3(0.22, 0.26, 0.31);
uniform vec3 pal_light = vec3(0.48, 0.53, 0.58);
uniform vec3 pal_accent = vec3(0.18, 0.83, 0.93);
uniform float lum_lo = 0.12;
uniform float lum_hi = 0.85;
// Accent paint on the outer 30% of the wings and fins (flat-colour hulls only). 0 = off.
uniform float livery_strength = 0.0;
// The model's own space (set per mesh by ShipStyle): three matrix rows turning a mesh vertex into model space, plus the model's centre and half-size.
instance uniform vec4 root_r0;
instance uniform vec4 root_r1;
instance uniform vec4 root_r2;
instance uniform vec4 root_c;
instance uniform vec4 root_h;

varying vec3 v_root;

vec2 rough_metal(vec2 uv) {
	float rough = roughness_factor;
	float metal = metallic_factor;
	if (has_mr_tex) {
		vec3 mr = texture(mr_tex, uv).rgb;
		rough = mr.g * roughness_factor;
		metal = mr.b * metallic_factor;
	}
	return vec2(clamp(rough * 0.85, 0.12, 1.0), clamp(metal, 0.0, 1.0));
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	vec4 p = vec4(VERTEX, 1.0);
	v_root = vec3(dot(root_r0, p), dot(root_r1, p), dot(root_r2, p));
}

void fragment() {
	vec3 albedo = albedo_color.rgb;
	float block = max(texel_block, 1.0);
	vec2 cell = floor(UV * 256.0);
	float wide_lum = -1.0;
	if (has_albedo_tex) {
		vec2 sz = vec2(textureSize(albedo_tex, 0));
		cell = floor(UV * sz / block);
		vec2 snapped = (cell + 0.5) * block / sz;
		albedo *= textureLod(albedo_tex, snapped, log2(block)).rgb;
		// the same spot averaged over a much wider patch: panel colours are decided from this, so grime and scratches cannot speckle them
		vec3 wide = textureLod(albedo_tex, snapped, log2(block * 8.0)).rgb * albedo_color.rgb;
		wide_lum = dot(pow(max(wide, vec3(0.0)), vec3(1.0 / 2.2)), vec3(0.299, 0.587, 0.114));
	}
	albedo = pow(max(albedo, vec3(0.0)), vec3(1.0 / 2.2)); // to display space
	if (palette_on) {
		float lum = wide_lum >= 0.0 ? wide_lum : dot(albedo, vec3(0.299, 0.587, 0.114));
		float t = clamp((lum - lum_lo) / max(lum_hi - lum_lo, 0.01), 0.0, 1.0);
		t = t * t * (3.0 - 2.0 * t);
		if (!has_albedo_tex) { t = clamp(0.58 + (lum - 0.5) * 0.45, 0.0, 1.0); }
		else { t = t < 0.12 ? 0.0 : (t > 0.80 ? 1.0 : 0.5); } // flat bands: dark / mid / light panels, no grime speckle
		vec3 hull = t < 0.5 ? mix(pal_dark, pal_mid, t * 2.0) : mix(pal_mid, pal_light, (t - 0.5) * 2.0);
		if (lum < 0.05) { hull = pal_dark * 0.55; } // canopies and vents stay dark
		albedo = hull; // uniform: no per-texel brightness noise
		if (livery_strength > 0.0 && !has_emission_tex && root_h.x > 0.0001 && lum >= 0.05) {
			float lateral = abs(v_root.x - root_c.x) / root_h.x;
			// a crisp edge: only as soft as one screen pixel (the old 0.66-0.74 ramp smeared across the whole wing)
			float aa = max(fwidth(lateral), 0.0005);
			float tip = smoothstep(0.70 - aa, 0.70 + aa, lateral) * livery_strength;
			albedo = mix(albedo, pal_accent * 0.85, tip);
		}
	} else {
		albedo *= 1.0 - weathering * 0.5 + weathering * hash21(cell);
		float grey = dot(albedo, vec3(0.299, 0.587, 0.114));
		albedo = mix(vec3(grey), albedo, 1.0 - desaturate) * vec3(1.05, 1.0, 0.93);
	}
	vec3 alb = clamp(albedo, 0.0, 1.0);

	// faceted normals blended with the smooth ones (only a touch: dense meshes turn into broken glass otherwise)
	vec3 facet = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(facet, VIEW) < 0.0) { facet = -facet; }
	vec3 smooth_n = normalize(NORMAL);
	vec3 n = normalize(mix(smooth_n, facet, facet_mix));
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 key = normalize(key_dir_world);

	vec2 rm = rough_metal(UV);
	float rough = rm.x;
	float metal = rm.y;

	float ndl = dot(nw, key);
	float wrap = pow(clamp((ndl + 0.12) / 1.12, 0.0, 1.0), 1.3);
	float up = nw.y * 0.5 + 0.5;
	vec3 sun = vec3(1.0, 0.93, 0.82);
	vec3 amb = vec3(0.20, 0.28, 0.42) * up + vec3(0.20, 0.15, 0.12) * (1.0 - up);
	vec3 diff = alb * (amb * 1.5 + sun * wrap * 1.5);

	// environment for metal: warm sky above, dark teal below, a teal horizon band
	vec3 r = reflect(-vw, nw);
	float sky = smoothstep(-0.35, 0.55, r.y);
	vec3 env = sky_teal * (1.0 - sky) + sky_warm * sky * 1.25;
	env += vec3(0.10, 0.22, 0.30) * exp(-pow(r.y + 0.05, 2.0) * 40.0) * 0.6;
	float k = 30.0 + (1.0 - rough) * 260.0;
	float lobe = exp((clamp(dot(r, key), -1.0, 1.0) - 1.0) * k);
	vec3 metcol = clamp(alb * 0.7 + 0.3, 0.0, 1.0);
	vec3 metal_spec = env * metcol * shine_strength + sun * lobe * 3.0 * glint_strength;
	float ndv = clamp(dot(nw, vw), 0.0, 1.0);
	vec3 hv = normalize(key + vw);
	float spec_d = pow(clamp(dot(nw, hv), 0.0, 1.0), 20.0 + (1.0 - rough) * 260.0);
	vec3 diel = (0.04 + 0.5 * pow(1.0 - ndv, 4.0)) * env * shine_strength + sun * spec_d * 0.5 * glint_strength;

	vec3 col = diff * (1.0 - metal) + metal_spec * metal * (0.55 + 0.45 * wrap) + diel * (1.0 - metal)
		+ metal * alb * (amb * 1.2 + sun * wrap * 0.55);

	vec3 emit = vec3(0.0);
	if (has_emission_tex) {
		vec3 e = texture(emission_tex, UV).rgb;
		if (palette_on) {
			float el = max(e.r, max(e.g, e.b));
			emit = pow(pal_accent, vec3(2.2)) * min(el * 2.2, 1.0) * 2.0;
		} else {
			emit = e * emission_color * emission_energy;
		}
	} else {
		emit = emission_color * emission_energy;
	}
	// the reference renders' tone curve, then back to linear for the engine
	col = vec3(1.0) - exp(-col * 1.25);
	col = pow(col, vec3(0.95));
	ALBEDO = max(pow(col, vec3(2.2)), emit);
}
