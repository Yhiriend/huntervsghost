shader_type spatial;
// Suelo de una habitación, sin texturas (barato en móvil): madera, baldosas o moqueta,
// en coordenadas de mundo, y sombra suave junto a las paredes (room_min/room_max = rectángulo XZ).

uniform int pattern = 0; // 0 madera, 1 baldosas, 2 moqueta
uniform vec3 color_a : source_color = vec3(0.55, 0.40, 0.26);
uniform vec3 color_b : source_color = vec3(0.42, 0.29, 0.18);
uniform float tile_size = 1.0;
uniform float plank_width = 0.33;
uniform float plank_length = 1.6;
uniform vec2 room_min = vec2(-10.0, -10.0);
uniform vec2 room_max = vec2(10.0, 10.0);
uniform float edge_shadow = 0.4;

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
	vec3 col;
	float rough = 0.8;
	if (pattern == 0) {
		float row = floor(p.y / plank_width);
		float offset = hash(vec2(row, 7.0)) * plank_length;
		float column = floor((p.x + offset) / plank_length);
		vec2 local = vec2(fract((p.x + offset) / plank_length), fract(p.y / plank_width));
		float tone = hash(vec2(row, column));
		float grain = noise(vec2(p.x * 2.0, p.y * 40.0 + tone * 10.0));
		col = mix(color_a, color_b, tone * 0.65 + grain * 0.35);
		float seam = max(1.0 - smoothstep(0.0, 0.05, local.y), smoothstep(0.985, 1.0, local.x));
		col *= 1.0 - 0.4 * seam;
		rough = 0.55;
	} else if (pattern == 1) {
		vec2 g = p / tile_size;
		vec2 cell = floor(g);
		vec2 f = fract(g);
		col = mix(color_a, color_b, mod(cell.x + cell.y, 2.0));
		col *= 0.94 + 0.12 * hash(cell);
		float grout = max(1.0 - smoothstep(0.0, 0.035, min(f.x, f.y)), smoothstep(0.975, 1.0, max(f.x, f.y)));
		col = mix(col, col * 0.5, grout);
		rough = 0.3;
	} else {
		float n = noise(p * 9.0) * 0.6 + noise(p * 31.0) * 0.4;
		col = mix(color_a, color_b, n);
		rough = 1.0;
	}
	vec2 d = min(p - room_min, room_max - p);
	float edge = min(d.x, d.y);
	col *= mix(1.0 - edge_shadow, 1.0, smoothstep(0.05, 0.9, edge));
	ALBEDO = col;
	ROUGHNESS = rough;
}
