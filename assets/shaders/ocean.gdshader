shader_type spatial;
render_mode cull_disabled, depth_draw_always;
// Ocean: Gerstner swell (vertex), two scrolling ripple normal maps, refraction with depth absorption
// (turquoise shallows, deep blue offshore), foam where the water meets the shore, Fresnel via PBR specular.
global uniform float wetness;
uniform sampler2D ripple_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 shallow : source_color = vec3(0.55, 0.86, 0.84);
uniform vec3 deep : source_color = vec3(0.015, 0.12, 0.2);
uniform float absorb = 0.16;
uniform float swell = 0.32;
uniform float fade_start = 600.0;

varying vec3 wpos;
varying float crest;

vec3 gerstner(vec2 p, vec2 dir, float wavelength, float amp, float steep, inout vec3 tangent, inout vec3 binormal) {
	float k = 6.2831853 / wavelength;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(dir);
	float f = k * (dot(d, p) - c * TIME * 0.6);
	float a = amp;
	float q = steep / (k * a * 4.0 + 0.0001);
	tangent += vec3(-d.x * d.x * q * a * k * sin(f), d.x * a * k * cos(f), -d.x * d.y * q * a * k * sin(f));
	binormal += vec3(-d.x * d.y * q * a * k * sin(f), d.y * a * k * cos(f), -d.y * d.y * q * a * k * sin(f));
	return vec3(d.x * q * a * cos(f), a * sin(f), d.y * q * a * cos(f));
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 t = vec3(1, 0, 0);
	vec3 b = vec3(0, 0, 1);
	float fade = 1.0 - smoothstep(fade_start, fade_start * 2.5, length(w.xz - CAMERA_POSITION_WORLD.xz));
	float s = swell * (1.0 + wetness);
	vec3 off = gerstner(w.xz, vec2(1.0, 0.35), 61.0, s, 0.5, t, b);
	off += gerstner(w.xz, vec2(0.6, 1.0), 33.0, s * 0.55, 0.45, t, b);
	off += gerstner(w.xz, vec2(-0.4, 1.0), 17.0, s * 0.3, 0.4, t, b);
	off *= fade;
	VERTEX += off;
	crest = clamp(off.y / (s * 1.6), 0.0, 1.0);
	NORMAL = normalize(mix(vec3(0, 1, 0), normalize(cross(b, t)), fade));
	wpos = w + off;
}

void fragment() {
	vec2 uv = wpos.xz * 0.045;
	vec3 na = texture(ripple_a, uv + TIME * vec2(0.010, 0.006)).rgb;
	vec3 nb = texture(ripple_b, uv * 2.3 - TIME * vec2(0.007, 0.012)).rgb;
	vec3 n = normalize(vec3((na.xy - 0.5) + (nb.xy - 0.5) * 0.7, 1.0));
	n.xy *= 1.0 + wetness;
	NORMAL_MAP = normalize(n) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.8;
	vec2 suv = SCREEN_UV + n.xy * 0.02;
	float d = texture(depth_tex, suv).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(suv * 2.0 - 1.0, d, 1.0);
	vp.xyz /= vp.w;
	if (vp.z > VERTEX.z) {
		suv = SCREEN_UV;
		d = texture(depth_tex, suv).r;
		vp = INV_PROJECTION_MATRIX * vec4(suv * 2.0 - 1.0, d, 1.0);
		vp.xyz /= vp.w;
	}
	float thickness = max(VERTEX.z - vp.z, 0.0);
	float t = 1.0 - exp(-thickness * absorb);
	vec3 under = texture(screen_tex, suv).rgb;
	vec3 col = mix(under * shallow, deep, t);
	// shore foam: thin water over the seabed, broken up by the ripples
	float foam = (1.0 - smoothstep(0.0, 1.4, thickness)) * smoothstep(0.35, 0.75, na.r * 0.6 + nb.g * 0.6 + sin(TIME * 1.3 + wpos.x * 0.2) * 0.15);
	foam = max(foam, smoothstep(0.75, 1.0, crest) * 0.25);
	ALBEDO = vec3(foam * 0.85);
	EMISSION = col * (1.0 - foam);
	ROUGHNESS = mix(0.04, 0.8, foam);
	SPECULAR = 0.5;
}
