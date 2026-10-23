shader_type spatial;
// Terrain: 4-layer splat (sand, dry grass, rock, green grass) from the baked world splat map, world-space
// planar mapping with a second, larger tiling blended in to break repetition; rock is also projected
// sideways on steep slopes. `hole` (x0, z0, x1, z1) discards the region covered by detail chunks (far mesh).
global uniform float wetness;
uniform sampler2D splat : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D sand_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dry_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dry_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lush_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lush_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float world_half = 2048.0;
uniform vec4 hole = vec4(0.0);
uniform vec3 sand_tint : source_color = vec3(1.25, 1.16, 1.0);
uniform vec3 dry_tint : source_color = vec3(0.78, 0.86, 0.6);
uniform float sea_level = -2.0;

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 layer(sampler2D alb, vec2 uv, float tile, float mixv) {
	return mix(texture(alb, uv / tile).rgb, texture(alb, uv / (tile * 3.7) + 0.31).rgb, mixv);
}

void fragment() {
	if (hole.z > hole.x && wpos.x > hole.x && wpos.x < hole.z && wpos.z > hole.y && wpos.z < hole.w) {
		discard;
	}
	vec4 s = texture(splat, (wpos.xz + world_half) / (2.0 * world_half));
	float sum = max(s.r + s.g + s.b + s.a, 0.001);
	s /= sum;
	vec2 uv = wpos.xz;
	float m = vnoise(uv * 0.02) * 0.6 + vnoise(uv * 0.07) * 0.4;
	vec3 sand = layer(sand_alb, uv, 4.0, m * 0.5) * sand_tint;
	vec3 dry = layer(dry_alb, uv, 7.0, m * 0.6) * dry_tint;
	vec3 lush = layer(lush_alb, uv, 6.0, m * 0.6);
	// rock: blend planar projections by the normal (no stretching on cliffs)
	vec3 an = abs(wnrm);
	an /= (an.x + an.y + an.z);
	vec3 rock = texture(rock_alb, wpos.zy / 6.0).rgb * an.x + texture(rock_alb, wpos.xz / 6.0).rgb * an.y + texture(rock_alb, wpos.xy / 6.0).rgb * an.z;
	vec3 col = sand * s.r + dry * s.g + rock * s.b + lush * s.a;
	col *= mix(0.88, 1.08, m);
	// wet sand near the waterline
	float wet_sand = smoothstep(sea_level + 0.9, sea_level + 0.1, wpos.y) * s.r;
	col *= mix(1.0, 0.62, max(wet_sand, wetness * 0.6));
	vec3 nrm = texture(sand_nrm, uv / 4.0).rgb * s.r + texture(dry_nrm, uv / 7.0).rgb * s.g + texture(rock_nrm, wpos.xz / 6.0).rgb * s.b + texture(lush_nrm, uv / 6.0).rgb * s.a;
	ALBEDO = col;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = 0.8;
	ROUGHNESS = mix(0.92, 0.25, max(wet_sand * 0.8, wetness * 0.7));
	SPECULAR = 0.35;
}
