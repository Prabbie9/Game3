shader_type spatial;
render_mode cull_disabled, depth_draw_always;
// Water surface: two scrolling ripple normal maps, refraction of what's below with depth-based absorption,
// Fresnel reflection (sky/sun via the PBR specular) and wetness-driven rain ripples.
global uniform float wetness;
uniform sampler2D ripple_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 shallow : source_color = vec3(0.62, 0.9, 0.92);
uniform vec3 deep : source_color = vec3(0.04, 0.28, 0.4);
uniform float absorb = 0.32;
uniform float ripple_scale = 0.35;
uniform float refraction = 0.03;

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = wp.xz * ripple_scale;
	vec3 na = texture(ripple_a, uv + TIME * vec2(0.020, 0.012)).rgb;
	vec3 nb = texture(ripple_b, uv * 1.7 - TIME * vec2(0.014, 0.024)).rgb;
	vec3 n = normalize(vec3((na.xy - 0.5) + (nb.xy - 0.5), 1.0));
	n.xy *= 1.0 + wetness * 1.5;
	NORMAL_MAP = normalize(n) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	// refracted background and the water thickness along the view ray
	vec2 suv = SCREEN_UV + n.xy * refraction;
	float d = texture(depth_tex, suv).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(suv * 2.0 - 1.0, d, 1.0);
	vp.xyz /= vp.w;
	if (vp.z > VERTEX.z) {
		// refracted sample is in front of the surface: fall back to the unrefracted one
		suv = SCREEN_UV;
		d = texture(depth_tex, suv).r;
		vp = INV_PROJECTION_MATRIX * vec4(suv * 2.0 - 1.0, d, 1.0);
		vp.xyz /= vp.w;
	}
	float thickness = max(VERTEX.z - vp.z, 0.0);
	float t = 1.0 - exp(-thickness * absorb);
	vec3 under = texture(screen_tex, suv).rgb;
	vec3 col = mix(under * shallow, deep, t);
	ALBEDO = vec3(0.0);
	EMISSION = col;
	ROUGHNESS = 0.03;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
