shader_type canvas_item;
// Velo del menú sobre el fondo animado: oscurece los bordes (viñeta) y un poco el centro,
// donde están los botones, con un tinte azul de noche.

uniform vec4 tint : source_color = vec4(0.02, 0.03, 0.08, 1.0);
uniform float center_dark = 0.35;
uniform float edge_dark = 0.9;

void fragment() {
	vec2 p = UV - 0.5;
	p.x *= 1.6;
	float d = length(p);
	float alpha = mix(center_dark, edge_dark, smoothstep(0.25, 0.85, d));
	COLOR = vec4(tint.rgb, alpha);
}
