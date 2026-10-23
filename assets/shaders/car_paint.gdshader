shader_type spatial;
// Car body: the pack's baked texture, with its paint areas recoloured. A texel counts as paint when its colour
// is (close to) a multiple of the texture's reference paint colour; its brightness relative to the reference
// carries the baked shading over to the new colour. Trim, rubber, grilles and badges keep their texture.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 ref_color : source_color = vec3(1.0);
uniform vec3 paint : source_color = vec3(1.0);
uniform bool repaint = false;
uniform float dirt = 0.0;

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
	ALBEDO = col;
	METALLIC = mix(0.15, 0.38, mask);
	ROUGHNESS = mix(0.62, 0.26 + dirt * 0.3, mask);
	CLEARCOAT = mask * (1.0 - dirt * 0.6);
	CLEARCOAT_ROUGHNESS = 0.08;
}
