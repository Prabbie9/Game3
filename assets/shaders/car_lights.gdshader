shader_type spatial;
// Car light clusters (the model's "Optics" texture), in the car frame (forward -Z, right +X).
// front: headlights glow with `head`. rear: red parts glow with tail (lights on) and brake, white parts with reverse.
// Indicators blink on the amber lenses of their side, or on the outer part of the cluster when it has none.
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform bool rear = false;
uniform float head = 0.0;
uniform float tail = 0.0;
uniform float brake = 0.0;
uniform float reverse = 0.0;
uniform float ind_left = 0.0;
uniform float ind_right = 0.0;
uniform bool has_amber = true;
uniform float outer_x = 0.6;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 c = texture(tex, UV).rgb;
	vec3 s = pow(c, vec3(0.4545));
	float amber = (s.r > 0.45 && s.g > 0.32 * s.r && s.g < 0.78 * s.r && s.b < 0.55 * s.g) ? 1.0 : 0.0;
	float red = step(c.g * 1.5 + 0.05, c.r) * (1.0 - amber);
	float bright = smoothstep(0.35, 0.8, max(c.r, max(c.g, c.b)));
	vec3 e = vec3(0.0);
	float ind = lp.x < 0.0 ? ind_left : ind_right;
	float zone = has_amber ? amber : step(outer_x, abs(lp.x));
	if (rear) {
		float lamp = has_amber ? red : red * (1.0 - zone * ind);
		e = c * lamp * (tail * 0.8 + brake * 4.0) + vec3(1.0, 0.25, 0.15) * lamp * brake * 0.6;
		e += vec3(1.0, 0.97, 0.92) * (1.0 - red) * (1.0 - amber) * bright * reverse * 3.0;
	} else {
		e = mix(c, vec3(1.0, 0.96, 0.88), 0.5) * bright * head * 4.0 * (1.0 - amber) * (1.0 - zone * ind);
	}
	e += vec3(1.0, 0.5, 0.06) * zone * ind * 5.0;
	ALBEDO = mix(c, vec3(1.0, 0.55, 0.1), zone * ind * 0.5);
	ROUGHNESS = 0.08;
	SPECULAR = 0.8;
	EMISSION = e;
}
