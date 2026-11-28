shader_type spatial;
// Paredes vistas desde arriba: el canto superior claro dibuja el plano de la casa;
// los lados oscurecen hacia el suelo y llevan rodapié.

uniform vec3 side_color : source_color = vec3(0.62, 0.58, 0.66);
uniform vec3 top_color : source_color = vec3(0.92, 0.89, 0.82);
uniform vec3 base_color : source_color = vec3(0.25, 0.2, 0.18);
uniform float height = 1.2;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = side_color * mix(0.55, 1.0, clamp(world_pos.y / height, 0.0, 1.0));
	if (world_pos.y < 0.14) {
		col = base_color;
	}
	if (world_normal.y > 0.5) {
		col = top_color;
	}
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
