shader_type spatial;
// Distant stand-in for city cells that aren't loaded in detail: vertex-coloured boxes and roads with a coarse
// window grid on building walls (CUSTOM0.x = 1) that lights up at night. UV = metres along / up the wall.
global uniform float night;
varying float v_windows;

void vertex() {
	v_windows = CUSTOM0.x;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec3 col = COLOR.rgb;
	vec3 emit = vec3(0.0);
	float rough = 0.85;
	if (v_windows > 0.5 && UV.y > 4.2) {
		vec2 cell = vec2(floor(UV.x / 3.2), floor((UV.y - 4.2) / 3.3));
		vec2 f = vec2(fract(UV.x / 3.2), fract((UV.y - 4.2) / 3.3));
		float win = step(0.22, f.x) * step(f.x, 0.78) * step(0.28, f.y) * step(f.y, 0.85);
		float h = hash(cell + floor(UV.x * 0.01));
		col = mix(col, vec3(0.16, 0.2, 0.24), win * 0.85);
		rough = mix(rough, 0.15, win);
		emit = win * step(1.0 - mix(0.0, 0.42, night), h) * vec3(1.0, 0.82, 0.55) * 1.6 * night;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = emit;
}
