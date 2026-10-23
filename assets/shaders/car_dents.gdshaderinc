// Shared crash deformation for car body, glass and light shaders. Dents are in the car frame (forward -Z);
// part_xf takes the mesh's vertices into that frame. Each dent pushes vertices within its radius along its
// push vector, with a crumple noise so panels fold rather than bulge smoothly.
uniform mat4 part_xf = mat4(1.0);
uniform vec4 dents[8];      // xyz centre, w radius (0 = unused)
uniform vec4 dent_push[8];  // xyz displacement at the centre

float dent_hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float dent_noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(dent_hash(i), dent_hash(i + vec3(1, 0, 0)), f.x), mix(dent_hash(i + vec3(0, 1, 0)), dent_hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(dent_hash(i + vec3(0, 0, 1)), dent_hash(i + vec3(1, 0, 1)), f.x), mix(dent_hash(i + vec3(0, 1, 1)), dent_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// returns the crumple amount (0..1) and moves `v` (mesh space) in place
float apply_dents(inout vec3 v) {
	vec3 c = (part_xf * vec4(v, 1.0)).xyz;
	vec3 off = vec3(0.0);
	float crumple = 0.0;
	for (int i = 0; i < 8; i++) {
		float r = dents[i].w;
		if (r <= 0.0) { continue; }
		float d = length(c - dents[i].xyz);
		float k = clamp(1.0 - d / r, 0.0, 1.0);
		k = k * k * (3.0 - 2.0 * k);
		float n = 0.45 + 1.1 * dent_noise(c * 6.0 + float(i) * 3.1);
		float push = length(dent_push[i].xyz);
		off += dent_push[i].xyz * k * n;
		// panels buckle: folds sideways and up across the crushed area
		vec3 fold = vec3(dent_noise(c * 4.0 + 11.0) - 0.5, dent_noise(c * 4.0 + 23.0) - 0.35, dent_noise(c * 4.0 + 37.0) - 0.5);
		off += fold * push * k * 0.9;
		crumple = max(crumple, k * min(length(dent_push[i].xyz) * 6.0, 1.0));
	}
	// back into mesh space (part_xf is rigid)
	v += (inverse(mat3(part_xf[0].xyz, part_xf[1].xyz, part_xf[2].xyz)) * off);
	return crumple;
}
