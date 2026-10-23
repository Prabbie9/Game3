shader_type spatial;
// Emergency light bar: left half flashes red, right half blue, alternating in double bursts while `on`.
// Follows the body's dents like the rest of the car.
#include "res://assets/shaders/car_dents.gdshaderinc"
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec4 base_color : source_color = vec4(1.0);
uniform float on = 0.0;
uniform float phase = 0.0;    // advanced by the vehicle so flashes stay in sync with its lights
uniform float burnt = 0.0;

varying vec3 lp;

void vertex() {
	lp = (part_xf * vec4(VERTEX, 1.0)).xyz;
	apply_dents(VERTEX);
}

void fragment() {
	vec4 t = texture(albedo_tex, UV) * base_color;
	bool left = lp.x < 0.0;
	float ph = fract(phase + (left ? 0.0 : 0.5));
	// two quick flashes per half cycle
	float flash = (step(ph, 0.12) + step(0.2, ph) * step(ph, 0.32)) * on * (1.0 - burnt);
	vec3 lamp = left ? vec3(1.0, 0.05, 0.03) : vec3(0.05, 0.2, 1.0);
	ALBEDO = mix(t.rgb * 0.6 + lamp * 0.25, lamp, flash * 0.6);
	ROUGHNESS = 0.15;
	EMISSION = lamp * flash * 9.0;
}
