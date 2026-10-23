shader_type spatial;
// Car light clusters (the model's "Optics" texture). front: headlights glow with `head`.
// rear: red parts glow with tail (lights on) and brake, white parts with reverse.
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform bool rear = false;
uniform float head = 0.0;
uniform float tail = 0.0;
uniform float brake = 0.0;
uniform float reverse = 0.0;

void fragment() {
	vec3 c = texture(tex, UV).rgb;
	float red = step(c.g * 1.5 + 0.05, c.r);
	float bright = smoothstep(0.35, 0.8, max(c.r, max(c.g, c.b)));
	vec3 e = vec3(0.0);
	if (rear) {
		e = c * red * (tail * 0.8 + brake * 4.0) + vec3(1.0, 0.25, 0.15) * red * brake * 0.6;
		e += vec3(1.0, 0.97, 0.92) * (1.0 - red) * bright * reverse * 3.0;
	} else {
		e = mix(c, vec3(1.0, 0.96, 0.88), 0.5) * bright * head * 4.0;
	}
	ALBEDO = c;
	ROUGHNESS = 0.08;
	SPECULAR = 0.8;
	EMISSION = e;
}
