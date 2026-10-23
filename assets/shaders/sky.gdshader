shader_type sky;
render_mode use_half_res_pass;
// Sky: gradient from the time-of-day colours, sun disk and glow from the main light, procedural clouds whose
// coverage/darkness follow the weather, stars and a moon glow at night.
uniform vec3 zenith : source_color = vec3(0.22, 0.42, 0.75);
uniform vec3 horizon : source_color = vec3(0.68, 0.78, 0.9);
uniform vec3 ground : source_color = vec3(0.32, 0.3, 0.28);
uniform float sun_size = 0.9997;
uniform float coverage = 0.35;
uniform float cloud_dark = 0.0;
uniform float night = 0.0;
uniform float exposure = 1.0;
uniform vec2 wind = vec2(0.004, 0.0015);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += noise(p) * a; p = p * 2.03 + 17.1; a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 sun_dir = LIGHT0_DIRECTION;
	vec3 sun_col = LIGHT0_COLOR * LIGHT0_ENERGY;
	vec3 col = mix(horizon, zenith, pow(clamp(h, 0.0, 1.0), 0.55));
	col = mix(col, ground, smoothstep(0.0, -0.08, h));
	// sun glow (also tints the horizon around a low sun)
	float sd = max(dot(d, sun_dir), 0.0);
	float day = clamp(sun_dir.y * 4.0 + 0.4, 0.0, 1.0);
	col += sun_col * (pow(sd, 8.0) * 0.25 + pow(sd, 64.0) * 0.5) * day;
	if (!AT_HALF_RES_PASS) {
		col += sun_col * smoothstep(sun_size, sun_size + 0.00012, sd) * 30.0 * day * (1.0 - coverage);
	}
	// stars + moon glow at night
	if (night > 0.01 && h > 0.0) {
		vec2 sp = vec2(atan(d.x, d.z), asin(d.y)) * 220.0;
		float st = step(0.9975, hash(floor(sp))) * hash(floor(sp) + 3.0);
		col += vec3(st) * night * (1.0 - coverage) * 1.5;
		vec3 moon = normalize(vec3(0.3, 0.55, -0.6));
		col += vec3(0.55, 0.62, 0.8) * pow(max(dot(d, moon), 0.0), 900.0) * 6.0 * night;
		col += vec3(0.1, 0.13, 0.2) * pow(max(dot(d, moon), 0.0), 12.0) * night;
	}
	// clouds on a plane above the city
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12) * 1.6 + TIME * wind;
		float n = fbm(uv * 1.3);
		float c = smoothstep(1.0 - coverage - 0.15, 1.0 - coverage + 0.25, n);
		float thick = smoothstep(0.4, 0.9, fbm(uv * 2.6 + 4.0));
		vec3 lit = mix(vec3(1.0), sun_col * 0.9 + vec3(0.25), 0.5) * mix(1.0, 0.45, cloud_dark);
		vec3 shade = mix(horizon * 0.85, vec3(0.32, 0.34, 0.38), cloud_dark);
		vec3 cc = mix(lit, shade, thick * 0.7 + cloud_dark * 0.3);
		cc = mix(cc, vec3(0.05, 0.06, 0.09), night * 0.85);
		c *= smoothstep(0.0, 0.12, h);
		col = mix(col, cc, c * 0.92);
	}
	COLOR = col * exposure;
}
