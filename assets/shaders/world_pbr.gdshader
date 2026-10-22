shader_type spatial;
// Generic world-space tiled PBR (sidewalks, curbs, roofs) with macro variation and wetness.
global uniform float wetness;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 3.0;
uniform vec3 tint = vec3(1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV / tile;
	vec3 arm = texture(arm_tex, uv).rgb;
	float macro = noise(UV * 0.1) * 0.6 + noise(UV * 0.5) * 0.4;
	vec3 col = texture(albedo_tex, uv).rgb * tint * mix(0.86, 1.08, macro);
	ALBEDO = col * mix(1.0, 0.6, wetness * 0.8);
	ROUGHNESS = mix(arm.g, 0.12, wetness * 0.6);
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.3;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
}
