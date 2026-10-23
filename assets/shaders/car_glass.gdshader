shader_type spatial;
render_mode depth_prepass_alpha, cull_disabled;
// Tinted car glass that follows the body's dents. Hits crack it into a web of pale lines around the impact;
// a shattered pane (shatter = 1) loses most of its glass.
#include "res://assets/shaders/car_dents.gdshaderinc"

uniform vec4 glass_hits[4];   // xyz car-frame point, w radius of the cracked area
uniform float shatter = 0.0;
uniform float burnt = 0.0;

varying vec3 v_car;

void vertex() {
	apply_dents(VERTEX);
	v_car = (part_xf * vec4(VERTEX, 1.0)).xyz;
}

// distance to the nearest edge of a voronoi cell: thin bright lines = cracks
float cracks(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p);
	float d1 = 8.0; float d2 = 8.0;
	for (int x = -1; x <= 1; x++) for (int y = -1; y <= 1; y++) for (int z = -1; z <= 1; z++) {
		vec3 g = vec3(float(x), float(y), float(z));
		vec3 o = vec3(dent_hash(i + g), dent_hash(i + g + 17.0), dent_hash(i + g + 31.0));
		float d = length(g + o - f);
		if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
	}
	return d2 - d1;
}

void fragment() {
	float crack = 0.0;
	for (int i = 0; i < 4; i++) {
		float r = glass_hits[i].w;
		if (r <= 0.0) { continue; }
		float d = length(v_car - glass_hits[i].xyz);
		float k = clamp(1.0 - d / r, 0.0, 1.0);
		float scale = mix(6.0, 22.0, k);
		crack = max(crack, (1.0 - smoothstep(0.0, 0.06, cracks(v_car * scale))) * smoothstep(0.0, 0.35, k));
	}
	ALBEDO = mix(vec3(0.0), vec3(0.8, 0.82, 0.8), crack);
	ROUGHNESS = mix(0.02, 0.5, crack);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = mix(0.68, 0.92, crack) * (1.0 - shatter * 0.85) * (1.0 - burnt);
}
