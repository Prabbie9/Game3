shader_type spatial;
// Asphalt road with procedural markings. UV.x = metres across the road (0..road_width), UV.y = metres along.
// Wear: tyre-darkened lanes, faded paint, patch noise. Wetness from the global "wetness" uniform.

global uniform float wetness;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 4.0;
uniform float road_width = 14.0;
uniform int lanes_per_side = 2;
uniform bool center_line = true;
uniform bool lane_lines = true;
uniform bool edge_lines = true;
uniform float crosswalk_start = -1.0; // metres along where a zebra crossing starts (-1 = none)
uniform float crosswalk_end = -1.0;
uniform float stop_line_at = -1.0;
uniform float road_length = 100.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float band(float x, float c, float w) { return step(abs(x - c), w * 0.5); }

void fragment() {
	vec2 uvw = UV / tile;
	vec3 base = texture(albedo_tex, uvw).rgb;
	vec3 arm = texture(arm_tex, uvw).rgb;
	float across = UV.x;
	float along = UV.y;
	float macro = noise(UV * 0.08) * 0.6 + noise(UV * 0.4) * 0.4;
	base *= mix(0.86, 1.08, macro);
	// tyre tracks: darker, smoother strips inside each lane
	float lane_w = road_width / float(lanes_per_side * 2);
	float lane_pos = fract(across / lane_w);
	float tracks = smoothstep(0.12, 0.0, abs(lane_pos - 0.28)) + smoothstep(0.12, 0.0, abs(lane_pos - 0.72));
	base *= 1.0 - tracks * 0.12;
	float rough = arm.g * (1.0 - tracks * 0.15);

	// markings
	float paint = 0.0;
	vec3 paint_col = vec3(0.92, 0.92, 0.88);
	float in_cw = (crosswalk_start >= 0.0 && along > crosswalk_start && along < crosswalk_end) ? 1.0 : 0.0;
	float near_end = (crosswalk_start >= 0.0 && along > crosswalk_start - 1.0 && along < crosswalk_end + 1.0) ? 1.0 : 0.0;
	if (center_line && near_end < 0.5) {
		float y = band(across, road_width * 0.5 - 0.12, 0.12) + band(across, road_width * 0.5 + 0.12, 0.12);
		if (y > 0.0) { paint = 1.0; paint_col = vec3(0.91, 0.72, 0.25); }
	}
	if (lane_lines && near_end < 0.5) {
		for (int i = 1; i < lanes_per_side; i++) {
			float off = lane_w * float(i);
			float dash = step(fract(along / 9.0), 0.33);
			paint = max(paint, (band(across, road_width * 0.5 - off, 0.12) + band(across, road_width * 0.5 + off, 0.12)) * dash);
		}
	}
	if (edge_lines && near_end < 0.5) {
		paint = max(paint, band(across, 0.35, 0.14) + band(across, road_width - 0.35, 0.14));
	}
	if (in_cw > 0.5) {
		float stripe = step(fract(across / 1.2), 0.5) * step(0.6, across) * step(across, road_width - 0.6);
		paint = max(paint, stripe);
	}
	if (stop_line_at >= 0.0) {
		paint = max(paint, band(along, stop_line_at, 0.45) * step(across, road_width * 0.5));
	}
	float wear = smoothstep(0.25, 0.75, noise(UV * vec2(1.3, 0.35) + 17.0));
	paint *= mix(0.55, 1.0, wear) * step(0.18, noise(UV * 6.0));
	base = mix(base, paint_col * (0.85 + 0.15 * macro), clamp(paint, 0.0, 1.0));
	rough = mix(rough, 0.55, paint);

	// wet roads: darker, glossy, puddles in low noise areas
	float puddle = smoothstep(0.62, 0.7, noise(UV * 0.22 + 3.1)) * wetness;
	base *= mix(1.0, 0.55, wetness * 0.8);
	rough = mix(rough, 0.08, max(wetness * 0.65, puddle));

	ALBEDO = base;
	ROUGHNESS = rough;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.4;
	NORMAL_MAP = mix(texture(normal_tex, uvw).rgb, vec3(0.5, 0.5, 1.0), max(paint * 0.6, puddle));
	NORMAL_MAP_DEPTH = 1.2;
}
