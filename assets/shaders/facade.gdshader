shader_type spatial;
// Building facade: tiled PBR wall + procedural windows with interior mapping (fake rooms), frames,
// storefront glazing on the ground floor, base grime, and lit windows at night.
// UV.x = metres along the facade, UV.y = metres above the building base.

global uniform float night;
global uniform float wetness;

uniform sampler2D wall_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 wall_tint : source_color = vec3(1.0);
uniform float wall_tile = 3.0;
uniform float floor_height = 3.3;
uniform float ground_floor = 4.2;
uniform float bay_width = 3.2;
uniform vec2 window_size = vec2(1.5, 1.8);
uniform float sill_height = 0.95;
uniform vec3 frame_color : source_color = vec3(0.9, 0.9, 0.88);
uniform vec3 glass_tint : source_color = vec3(0.55, 0.66, 0.72);
uniform bool storefront = true;
uniform vec3 sign_color : source_color = vec3(0.16, 0.45, 0.42);
uniform float seed = 1.0;
uniform float facade_width = 20.0;
uniform float building_height = 20.0;
uniform float room_depth = 0.9;

float hash(vec2 p) { return fract(sin(dot(p + seed * 1.37, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// Interior mapping: returns room colour seen through a window. p = position in window cell (0..1),
// r = ray direction in tangent space (z into the building).
vec3 room(vec2 p, vec3 r, vec2 id, out float lit) {
	float h = hash(id);
	float h2 = hash(id + 7.3);
	vec3 rp = vec3(p, 0.0);
	vec3 rd = normalize(vec3(r.xy, max(r.z, 0.05)));
	float tx = rd.x > 0.0 ? (1.0 - rp.x) / rd.x : -rp.x / rd.x;
	float ty = rd.y > 0.0 ? (1.0 - rp.y) / rd.y : -rp.y / rd.y;
	float depth = id.y < -0.5 ? room_depth * 1.8 : room_depth;
	float tz = depth / rd.z;
	float t = min(min(tx, ty), tz);
	vec3 hit = rp + rd * t;
	vec3 wallc = mix(vec3(0.62, 0.58, 0.52), vec3(0.45, 0.5, 0.52), h2);
	bool shop = id.y < -0.5;
	vec3 c;
	if (t == tz) {
		c = wallc * 0.9;
		if (shop) {
			// shelving with rows of coloured products
			float rows = step(0.12, hit.y) * step(hit.y, 0.78);
			float shelf_line = step(fract(hit.y * 5.0), 0.12);
			vec2 cell = floor(vec2(hit.x * 14.0, hit.y * 5.0));
			vec3 product = 0.35 + 0.55 * vec3(hash(cell), hash(cell + 3.1), hash(cell + 7.7));
			c = mix(c, mix(product, vec3(0.75, 0.74, 0.72), shelf_line), rows);
		} else {
			// furniture silhouettes / curtains on the back wall
			float shelf = step(0.2, hit.y) * step(hit.y, 0.55) * step(0.15 + h * 0.3, hit.x) * step(hit.x, 0.5 + h * 0.4);
			c = mix(c, vec3(0.2, 0.16, 0.13), shelf * 0.8);
		}
	} else if (t == ty) {
		if (rd.y > 0.0) {
			c = vec3(0.82, 0.8, 0.76);
			if (shop) c += vec3(1.4) * step(fract(hit.z * 3.0), 0.18) * step(abs(hit.x - 0.5), 0.35); // light strips
		} else {
			c = shop ? mix(vec3(0.7, 0.68, 0.64), vec3(0.55, 0.56, 0.58), step(0.5, fract(hit.x * 4.0 + floor(hit.z * 4.0) * 0.5))) : mix(vec3(0.32, 0.24, 0.18), vec3(0.4, 0.4, 0.42), h2);
		}
	} else {
		c = wallc;
	}
	if (shop) {
		// counter / display table in the middle of the shop
		float counter = step(abs(hit.x - 0.35 - h * 0.3), 0.18) * step(hit.y, 0.32) * step(0.25, hit.z / depth);
		c = mix(c, vec3(0.3, 0.22, 0.16), counter * step(t, tz) * 0.0 + counter * 0.6);
		c *= mix(1.0, 0.7, clamp(hit.z / depth, 0.0, 1.0));
		lit = 1.0;
		return c * mix(0.42, 0.3, night) + c * vec3(1.0, 0.9, 0.75) * night * 1.2;
	}
	// depth darkening
	c *= mix(1.0, 0.55, clamp(hit.z / depth, 0.0, 1.0));
	lit = step(1.0 - mix(0.12, 0.45, night), h) * night;
	vec3 lamp = mix(vec3(1.0, 0.78, 0.5), vec3(0.85, 0.9, 1.0), step(0.7, h2));
	float ceiling_glow = 0.6 + 0.4 * smoothstep(0.0, 1.0, hit.y);
	// daylight interiors read dark from outside; lit rooms glow at night
	return c * mix(0.32, 0.12, night) + lit * lamp * c * 2.5 * ceiling_glow;
}

void fragment() {
	vec2 m = UV;
	vec3 tv = normalize(vec3(dot(VIEW, TANGENT), dot(VIEW, BINORMAL), dot(VIEW, NORMAL)));
	vec3 into = vec3(-tv.x, tv.y, tv.z); // view ray into the wall, tangent space (y up)
	vec2 wuv = m / wall_tile;
	vec3 wall = texture(wall_albedo, wuv).rgb * wall_tint;
	vec3 warm = texture(wall_arm, wuv).rgb;
	vec3 nmap = texture(wall_normal, wuv).rgb;
	float rough = warm.g;
	float ao = warm.r;
	float macro = noise(m * 0.15) * 0.5 + noise(m * 0.6) * 0.5;
	wall *= mix(0.88, 1.06, macro);
	// grime at the base and streaks under windows
	float grime = smoothstep(1.4, 0.0, m.y) * 0.35 + smoothstep(0.55, 0.9, noise(vec2(m.x * 1.7, m.y * 0.12))) * 0.12;
	wall *= 1.0 - grime;

	vec3 col = wall;
	vec3 emit = vec3(0.0);
	float metal = 0.0;
	float is_glass = 0.0;
	float edge_margin = 0.6;
	bool in_bounds = m.x > edge_margin && m.x < facade_width - edge_margin;

	if (m.y < ground_floor) {
		if (storefront && in_bounds) {
			// storefront: big glazing between piers, sign band above
			float bay = floor(m.x / bay_width);
			float lx = fract(m.x / bay_width);
			float pier = step(lx, 0.07) + step(0.93, lx);
			float glaze_top = ground_floor - 1.0;
			if (m.y > glaze_top + 0.15 && m.y < ground_floor - 0.15) {
				col = sign_color * (0.8 + 0.2 * macro); rough = 0.4;
				emit = sign_color * night * 0.6;
			} else if (pier < 0.5 && m.y > 0.45 && m.y < glaze_top) {
				vec2 p = vec2((lx - 0.07) / 0.86, (m.y - 0.45) / (glaze_top - 0.45));
				float frame = step(p.x, 0.02) + step(0.98, p.x) + step(p.y, 0.02) + step(0.98, p.y);
				if (frame > 0.0) { col = vec3(0.12); rough = 0.35; metal = 0.8; }
				else {
					float lit;
					vec3 r = room(p, into, vec2(bay, -1.0), lit);
					col = r * glass_tint * 0.9; rough = 0.04; is_glass = 1.0;
					emit = r * (0.06 + 0.55 * night);
				}
			} else if (m.y <= 0.45) {
				col = vec3(0.32, 0.31, 0.3) * (0.8 + 0.3 * macro); rough = 0.8;
			}
		}
	} else if (in_bounds && m.y < building_height - 1.2) {
		float fl = floor((m.y - ground_floor) / floor_height);
		float ly = (m.y - ground_floor) - fl * floor_height;
		float bay = floor(m.x / bay_width);
		float lx = fract(m.x / bay_width) * bay_width - bay_width * 0.5;
		vec2 hw = window_size * 0.5;
		float wy = ly - sill_height;
		float fw = 0.09;
		if (abs(lx) < hw.x + fw && wy > -fw && wy < window_size.y + fw) {
			if (abs(lx) < hw.x && wy > 0.0 && wy < window_size.y) {
				vec2 p = vec2((lx + hw.x) / window_size.x, wy / window_size.y);
				float mullion = step(abs(p.x - 0.5), 0.015);
				if (mullion > 0.0) { col = frame_color * 0.9; rough = 0.45; }
				else {
					float lit;
					vec3 r = room(p, into, vec2(bay, fl), lit);
					// blinds on some windows
					float blind = step(0.75, hash(vec2(bay, fl) + 3.1)) * step(1.0 - hash(vec2(bay, fl) + 5.7) * 0.6, p.y);
					r = mix(r, vec3(0.78, 0.74, 0.66) * (0.6 + 0.4 * night * lit), blind);
					col = r * glass_tint * 0.75; rough = 0.03; is_glass = 1.0;
					emit = r * lit * 0.9;
				}
			} else {
				col = frame_color; rough = 0.45;
			}
		} else if (abs(lx) < hw.x + 0.18 && wy < -fw && wy > -fw - 0.12) {
			col = mix(frame_color, wall, 0.3); rough = 0.6; // sill
		}
		// soft shadow around window reveals
		float d = max(abs(lx) - hw.x - fw, max(-wy - fw, wy - window_size.y - fw));
		col *= mix(0.82, 1.0, smoothstep(0.0, 0.25, d) + step(d, 0.0) * (1.0 - is_glass) * 0.0 + is_glass);
	}

	// wet facades get slightly darker and glossier near the bottom
	col *= mix(1.0, 0.82, wetness * smoothstep(3.0, 0.0, m.y) * (1.0 - is_glass));
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.03, is_glass);
	METALLIC = metal;
	SPECULAR = mix(0.5, 0.9, is_glass);
	AO = mix(ao, 1.0, is_glass);
	NORMAL_MAP = mix(nmap, vec3(0.5, 0.5, 1.0), is_glass);
	EMISSION = emit * 1.4;
}
