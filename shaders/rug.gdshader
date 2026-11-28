shader_type spatial;
// Alfombra (un plano en el suelo, sin colisión): fondo, cenefa y rombos en el centro.

uniform vec3 field_color : source_color = vec3(0.45, 0.14, 0.14);
uniform vec3 border_color : source_color = vec3(0.85, 0.7, 0.45);
uniform vec3 pattern_color : source_color = vec3(0.3, 0.08, 0.1);
uniform vec2 size = vec2(3.0, 2.0);
uniform float border = 0.18;

void fragment() {
	vec2 p = UV * size;
	vec2 d = min(p, size - p);
	float edge = min(d.x, d.y);
	vec3 col = field_color;
	vec2 q = abs(fract((p - size * 0.5) / 0.6) - 0.5);
	if (q.x + q.y < 0.22) {
		col = pattern_color;
	}
	if (edge < border) {
		col = border_color;
	}
	if (edge < border * 0.35 || (edge > border * 0.65 && edge < border * 0.8)) {
		col = field_color * 0.8;
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
