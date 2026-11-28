shader_type spatial;
// Jardín alrededor de la casa (solo se ve, no tiene colisión): césped con franjas de corte.

uniform vec3 color_a : source_color = vec3(0.2, 0.34, 0.17);
uniform vec3 color_b : source_color = vec3(0.13, 0.24, 0.12);
// Luz de luna: fuera no hay lámparas, sin esto el jardín se vería negro.
uniform float moonlight = 0.35;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float n = noise(p * 1.3) * 0.5 + noise(p * 6.0) * 0.3 + noise(p * 25.0) * 0.2;
	float stripe = step(0.5, fract(p.x / 3.0)) * 0.12;
	vec3 col = mix(color_a, color_b, clamp(n + stripe, 0.0, 1.0));
	ALBEDO = col;
	EMISSION = col * vec3(0.6, 0.75, 1.0) * moonlight;
	ROUGHNESS = 1.0;
}
