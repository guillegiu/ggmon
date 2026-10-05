shader_type spatial;
render_mode unshaded, cull_disabled;
// Agua que corre: vetas de espuma estiradas en la direccion del flujo. Se usa para el
// rio (flujo horizontal) y para la cascada (flujo vertical).

uniform vec3 deep : source_color = vec3(0.1, 0.45, 0.6);
uniform vec3 foam : source_color = vec3(0.85, 0.97, 1.0);
uniform vec2 flow = vec2(1.0, 0.0);     // direccion en UV
uniform float speed = 0.6;
uniform float alpha : hint_range(0.0, 1.0) = 0.78;
uniform vec2 tiling = vec2(4.0, 3.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV * tiling - flow * TIME * speed;
	vec2 across = vec2(-flow.y, flow.x);
	float along = dot(uv, flow);
	float side = dot(uv, across);
	float streak = smoothstep(0.5, 0.85, noise(vec2(along * 0.7, side * 5.0)));
	float ripple = noise(vec2(along * 2.0, side * 2.0)) * 0.25;
	ALBEDO = mix(deep * (0.85 + ripple), foam, streak * 0.85);
	ALPHA = alpha;
}
