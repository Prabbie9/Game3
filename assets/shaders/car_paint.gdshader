shader_type spatial;
// Car body: the pack's baked texture, with its paint areas recoloured. A texel counts as paint when its colour
// is (close to) a multiple of the texture's reference paint colour; its brightness relative to the reference
// carries the baked shading over to the new colour. Trim, rubber, grilles and badges keep their texture.
// Crash dents (car_dents.gdshaderinc) fold the panels and scuff the paint; `burnt` chars a burnt-out wreck.
#include "res://assets/shaders/car_dents.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 ref_color : source_color = vec3(1.0);
uniform vec3 paint : source_color = vec3(1.0);
uniform bool repaint = false;
uniform float dirt = 0.0;
uniform float burnt = 0.0;

varying float v_crumple;
varying vec3 v_pos;

void vertex() {
	v_crumple = apply_dents(VERTEX);
	v_pos = VERTEX;
}

void fragment() {
	vec3 t = texture(albedo_tex, UV).rgb;
	float mask = 0.0;
	vec3 col = t;
	if (repaint) {
		float k = dot(t, ref_color) / max(dot(ref_color, ref_color), 1e-4);
		float off = length(t - ref_color * k) / max(length(t), 1e-3);
		mask = (1.0 - smoothstep(0.1, 0.28, off)) * smoothstep(0.015, 0.06, k);
		col = mix(t, paint * min(k, 1.25), mask);
	} else {
		mask = step(0.12, max(t.r, max(t.g, t.b)));
	}
	col = mix(col, col * vec3(0.62, 0.56, 0.48), dirt * (1.0 - UV.y * 0.3));
	// crumpled metal: darker creases, scraped paint showing grey primer
	float crease = dent_noise(v_pos * vec3(5.0, 14.0, 5.0));
	float scrape = smoothstep(0.6, 0.78, crease) * smoothstep(0.2, 0.7, v_crumple);
	col = mix(col, vec3(0.42, 0.42, 0.43), scrape * 0.7 * mask);
	col *= 1.0 - v_crumple * 0.35 * (1.0 - crease);
	// burnt-out: soot black with rusty patches
	float rust = dent_noise(v_pos * 5.0);
	vec3 soot = mix(vec3(0.018, 0.017, 0.016), vec3(0.05, 0.045, 0.04), dent_noise(v_pos * 23.0));
	col = mix(col, mix(soot, vec3(0.11, 0.05, 0.022), smoothstep(0.72, 0.95, rust) * 0.8), burnt);
	float paint_mask = mask * (1.0 - scrape) * (1.0 - burnt);
	ALBEDO = col;
	METALLIC = mix(0.15, 0.38, paint_mask);
	ROUGHNESS = mix(mix(0.62, 0.26 + dirt * 0.3, paint_mask), 0.95, burnt);
	CLEARCOAT = paint_mask * (1.0 - dirt * 0.6);
	CLEARCOAT_ROUGHNESS = 0.08 + v_crumple * 0.4;
}
