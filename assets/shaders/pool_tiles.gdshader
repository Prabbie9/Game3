shader_type spatial;
// Small ceramic pool mosaic (procedural): UV is in metres along each face. Per-tile tone variation,
// recessed grout, glossy glaze and a dark lane stripe on the floor.
uniform vec3 tile_a : source_color = vec3(0.42, 0.72, 0.82);
uniform vec3 tile_b : source_color = vec3(0.30, 0.60, 0.74);
uniform vec3 grout : source_color = vec3(0.78, 0.82, 0.82);
uniform vec3 stripe : source_color = vec3(0.07, 0.16, 0.30);
uniform float tile_size = 0.1;
uniform float grout_w = 0.07;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 g = UV / tile_size;
	vec2 id = floor(g);
	vec2 f = fract(g);
	float h = hash(id);
	vec3 col = mix(tile_a, tile_b, smoothstep(0.2, 0.9, h));
	col *= mix(0.92, 1.05, hash(id + 7.3));
	// dark lane stripe down the middle of the floor (floor faces have world-xz UVs: v along z)
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	if (wn.y > 0.9) {
		vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		col = mix(col, stripe, step(abs(fract(wp.z / 6.5 + 0.5) - 0.5) * 6.5, 0.15));
	}
	// sunlight caustics on everything under the water line
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float under = smoothstep(-0.05, -0.25, wpos.y);
	vec2 cp = wpos.xz * 1.6 + vec2(wpos.y * 0.3);
	float cz = 0.0;
	for (int i = 0; i < 3; i++) {
		float k = float(i) + 1.0;
		cp += vec2(sin(cp.y * 1.3 + TIME * 0.7 * k), cos(cp.x * 1.1 - TIME * 0.6 * k)) * 0.45 / k;
		cz += pow(abs(sin(cp.x) * sin(cp.y)), 0.35) / k;
	}
	col *= 1.0 + under * smoothstep(0.85, 1.45, cz) * 0.55;
	vec2 e = min(f, 1.0 - f);
	float edge = min(e.x, e.y);
	float gm = 1.0 - smoothstep(grout_w * 0.5, grout_w, edge);
	ALBEDO = mix(col, grout, gm);
	ROUGHNESS = mix(0.08, 0.7, gm);
	SPECULAR = 0.6;
	// bevel normal towards the tile centre near the grout
	vec2 d = (f - 0.5) * 2.0;
	float bev = 1.0 - smoothstep(0.0, grout_w * 1.6, edge);
	NORMAL_MAP = normalize(vec3(d * bev * 0.5, 1.0)) * 0.5 + 0.5;
}
