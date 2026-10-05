shader_type spatial;
// Piel "pintada a mano" para las criaturas, generada sin texturas.
// Reproduce lo que hacen las texturas de los modelos de referencia: lomo oscuro y
// panza clara, rayas que bajan del lomo, escamas, sombra pintada en la parte de
// abajo, extremidades que viran a otro color y un borde de luz.
// Espera las UV de creature_mesh.gd: UV.x a lo largo del cuerpo, UV.y alrededor
// (0 = lomo, 0.5 = panza), UV2.x = cuanto es "extremidad".

uniform vec3 base_color : source_color = vec3(0.95, 0.55, 0.12);
uniform vec3 back_color : source_color = vec3(0.6, 0.25, 0.05);
uniform vec3 belly_color : source_color = vec3(1.0, 0.9, 0.6);
uniform vec3 stripe_color : source_color = vec3(0.4, 0.12, 0.04);
uniform vec3 tip_color : source_color = vec3(0.7, 0.2, 0.15);
uniform float stripe_count = 22.0;
uniform float stripe_amount : hint_range(0.0, 1.0) = 0.7;
uniform float scale_amount : hint_range(0.0, 1.0) = 0.35;
uniform float scale_size = 26.0;
uniform float flash = 0.0;
// Camuflaje: menos de 1 descarta pixeles en trama, asi se ve a medias sin pasar a transparente.
uniform float alpha = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	if (alpha < 1.0 && hash(floor(FRAGCOORD.xy)) > alpha) {
		discard;
	}
	float top = cos(UV.y * TAU);

	// Degrade lomo / costado / panza.
	vec3 col = mix(base_color, back_color, smoothstep(0.25, 0.95, top));
	float belly = smoothstep(-0.3, -0.75, top);
	col = mix(col, belly_color, belly);

	// Rayas triangulares: anchas en el lomo, se afinan hasta desaparecer en el costado.
	float cell = UV.x * stripe_count;
	float tri = abs(fract(cell) - 0.5) * 2.0;
	float reach = smoothstep(-0.25, 1.0, top) * (0.45 + 0.25 * hash(vec2(floor(cell), 3.0)));
	float stripe = smoothstep(reach, reach - 0.1, tri) * step(-0.2, top);
	col = mix(col, stripe_color, stripe * stripe_amount);

	// Escamas: celdas en filas alternadas, mas claras en el centro.
	vec2 g = vec2(UV.x * scale_size * 1.6, UV.y * scale_size);
	g.x += 0.5 * mod(floor(g.y), 2.0);
	vec2 f = fract(g) - 0.5;
	float bump = smoothstep(0.55, 0.2, length(f));
	float tone = 0.8 + 0.28 * bump + 0.08 * (hash(floor(g)) - 0.5);
	col *= mix(1.0, tone, scale_amount * (1.0 - belly * 0.7));

	// Extremidades: manos, pies y punta de la cola viran de color.
	col = mix(col, tip_color, smoothstep(0.35, 1.0, UV2.x));

	// Sombra pintada: la parte de abajo recibe menos luz.
	col *= mix(0.8, 1.0, smoothstep(-1.0, 0.1, top));

	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = col;
	ROUGHNESS = 0.72 - 0.2 * bump * scale_amount;
	SPECULAR = 0.35;
	EMISSION = col * rim * 0.45 + vec3(flash);
}
