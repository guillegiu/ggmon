extends RefCounted
# Especies jugables y sus evoluciones. Cada orbe activa una forma: 1 rojo, 2 azul, 3 verde.
# Aspecto (colores, proporciones) y estadisticas viven juntos para que el modelo
# y la logica de pelea usen los mismos numeros.
#
# Claves de pelea (en "base" y en cada forma):
#   scale, speed, jump, dmg, armor: multiplicadores. armor < 1 ademas da super armadura.
#   air_jumps: saltos extra en el aire. glide: planea manteniendo salto.
#   k, l: id de las dos habilidades (fighter.gd MOVES); k_name, l_name: como se muestran en pantalla.
# Claves de pintura opcionales (shaders/skin.gdshader): back, stripe, tip, shell (colores),
# stripes y scales (0..1). Si faltan, el modelo las deriva del color de cuerpo.

const ORB := {1: Color(1.0, 0.2, 0.12), 2: Color(0.2, 0.5, 1.0), 3: Color(0.25, 1.0, 0.3)}
const ORDER := ["dino", "bug", "frog"]

const SPECIES := {
	"dino": {
		"name": "Dino",
		"desc": "Equilibrado. Tira bolas de fuego y embiste.",
		"model": "res://scripts/dino_model.gd",
		"pal": {"body": Color(0.95, 0.55, 0.12), "belly": Color(1.0, 0.9, 0.6), "spike": Color(0.8, 0.2, 0.1),
			"back": Color(0.7, 0.28, 0.06), "stripe": Color(0.5, 0.14, 0.04), "tip": Color(0.75, 0.22, 0.16), "stripes": 0.75, "scales": 0.3},
		"pal_alt": {"body": Color(0.55, 0.3, 0.75), "belly": Color(0.85, 0.8, 0.95), "spike": Color(0.2, 0.8, 0.6),
			"back": Color(0.28, 0.12, 0.45), "stripe": Color(0.16, 0.06, 0.3), "tip": Color(0.2, 0.45, 0.6), "stripes": 0.75, "scales": 0.3},
		"base": {
			"name": "", "scale": 1.0, "speed": 1.0, "jump": 1.0, "air_jumps": 1, "glide": false, "dmg": 1.0, "armor": 1.0,
			"k": "fire", "l": "dash", "k_name": "Bola de fuego", "l_name": "Embestida",
		},
		"forms": {
			1: {
				"name": "Dragon",
				"body": Color(0.78, 0.1, 0.09), "belly": Color(1.0, 0.72, 0.3), "spike": Color(1.0, 0.8, 0.2),
				"back": Color(0.32, 0.04, 0.1), "stripe": Color(0.2, 0.02, 0.06), "tip": Color(0.3, 0.05, 0.14), "stripes": 0.35, "scales": 0.75,
				"body_s": Vector3(1.05, 1.0, 1.0), "head_s": Vector3(1.05, 1.0, 1.0), "tail_s": Vector3(1.3, 1.0, 1.0), "leg_s": 1.0,
				"scale": 1.35, "speed": 1.05, "jump": 1.0, "air_jumps": 4, "glide": true, "dmg": 1.5, "armor": 1.0,
				"k": "breath", "l": "dive", "k_name": "Aliento de fuego", "l_name": "Picada explosiva",
			},
			2: {
				"name": "Triceratops",
				"body": Color(0.2, 0.45, 0.9), "belly": Color(0.82, 0.92, 1.0), "spike": Color(0.75, 0.88, 1.0),
				"back": Color(0.08, 0.18, 0.5), "stripe": Color(0.05, 0.1, 0.35), "tip": Color(0.32, 0.28, 0.7), "stripes": 0.0, "scales": 0.85,
				"body_s": Vector3(1.15, 1.1, 1.3), "head_s": Vector3(1.0, 1.0, 0.9), "tail_s": Vector3(0.9, 1.1, 1.0), "leg_s": 0.9,
				"scale": 1.5, "speed": 0.8, "jump": 0.92, "air_jumps": 0, "glide": false, "dmg": 1.7, "armor": 0.6,
				"k": "charge", "l": "stomp", "k_name": "Carga (mantener)", "l_name": "Pisoton sismico",
			},
			3: {
				"name": "Raptor",
				"body": Color(0.2, 0.62, 0.25), "belly": Color(0.96, 0.95, 0.6), "spike": Color(0.98, 0.5, 0.1),
				"back": Color(0.04, 0.25, 0.14), "stripe": Color(0.02, 0.12, 0.08), "tip": Color(0.45, 0.18, 0.6), "stripes": 1.0, "scales": 0.3,
				"body_s": Vector3(1.1, 0.8, 0.75), "head_s": Vector3(1.2, 0.85, 0.95), "tail_s": Vector3(1.5, 0.75, 0.75), "leg_s": 1.15,
				"scale": 1.12, "speed": 1.45, "jump": 1.12, "air_jumps": 2, "glide": false, "dmg": 1.15, "armor": 1.0,
				"k": "camo", "l": "pounce", "k_name": "Camuflaje", "l_name": "Salto de caza",
			},
		},
	},
	"bug": {
		"name": "Bicho",
		"desc": "Hormiguita veloz. Escupe acido y excava bajo tierra.",
		"model": "res://scripts/bug_model.gd",
		"pal": {"body": Color(0.72, 0.8, 0.2), "belly": Color(0.98, 0.93, 0.7), "spike": Color(1.0, 0.75, 0.3),
			"back": Color(0.4, 0.5, 0.08), "stripe": Color(0.25, 0.32, 0.05), "tip": Color(0.28, 0.18, 0.08),
			"shell": Color(0.55, 0.27, 0.1), "stripes": 0.6, "scales": 0.12},
		"pal_alt": {"body": Color(0.55, 0.5, 0.8), "belly": Color(0.88, 0.85, 0.95), "spike": Color(0.6, 0.9, 0.9),
			"back": Color(0.3, 0.25, 0.55), "stripe": Color(0.18, 0.14, 0.38), "tip": Color(0.12, 0.1, 0.25),
			"shell": Color(0.2, 0.16, 0.38), "stripes": 0.6, "scales": 0.12},
		"base": {
			"name": "", "scale": 0.9, "speed": 1.12, "jump": 1.05, "air_jumps": 1, "glide": false, "dmg": 0.9, "armor": 1.0,
			"k": "spit", "l": "burrow", "k_name": "Escupitajo acido", "l_name": "Excavar (mantener)",
		},
		"forms": {
			1: {
				"name": "Escarabajo",
				"body": Color(0.75, 0.13, 0.1), "belly": Color(0.95, 0.6, 0.32), "spike": Color(1.0, 0.68, 0.15),
				"back": Color(0.35, 0.04, 0.06), "stripe": Color(0.2, 0.02, 0.04), "tip": Color(0.14, 0.04, 0.07),
				"shell": Color(0.3, 0.04, 0.07), "stripes": 0.4, "scales": 0.45,
				"abd_s": Vector3(1.1, 1.2, 1.3), "head_s": Vector3(1.1, 1.1, 1.1), "head_off": Vector3(0.0, 0.0, 0.0),
				"scale": 1.4, "speed": 0.85, "jump": 0.95, "air_jumps": 1, "glide": false, "dmg": 1.6, "armor": 0.7,
				"k": "bomb", "l": "horn", "k_name": "Bomba de magma", "l_name": "Cornada",
			},
			2: {
				"name": "Mariposa",
				"body": Color(0.22, 0.34, 0.82), "belly": Color(0.9, 0.95, 1.0), "spike": Color(0.3, 0.78, 1.0),
				"back": Color(0.08, 0.12, 0.42), "stripe": Color(0.05, 0.07, 0.3), "tip": Color(0.08, 0.08, 0.28),
				"shell": Color(0.12, 0.18, 0.55), "stripes": 0.8, "scales": 0.05,
				"abd_s": Vector3(1.2, 0.65, 0.65), "head_s": Vector3(0.9, 0.9, 0.9), "head_off": Vector3(0.0, 0.05, 0.0),
				"scale": 1.15, "speed": 1.1, "jump": 1.0, "air_jumps": 5, "glide": true, "dmg": 1.3, "armor": 1.0,
				"k": "sleep", "l": "gust", "k_name": "Nube de polvo", "l_name": "Rafaga",
			},
			3: {
				"name": "Mantis",
				"body": Color(0.3, 0.75, 0.2), "belly": Color(0.9, 0.95, 0.55), "spike": Color(0.9, 0.95, 0.3),
				"back": Color(0.1, 0.42, 0.1), "stripe": Color(0.06, 0.3, 0.08), "tip": Color(0.6, 0.5, 0.1),
				"shell": Color(0.2, 0.55, 0.14), "stripes": 0.5, "scales": 0.1,
				"abd_s": Vector3(1.35, 0.65, 0.65), "head_s": Vector3(0.85, 0.8, 1.3), "head_off": Vector3(0.28, 0.62, 0.0),
				"scale": 1.25, "speed": 1.35, "jump": 1.15, "air_jumps": 2, "glide": false, "dmg": 1.25, "armor": 1.0,
				"k": "boomerang", "l": "blink", "k_name": "Cuchilla bumeran", "l_name": "Tajo relampago",
			},
		},
	},
	"frog": {
		"name": "Rana",
		"desc": "Salta altisimo. Atrae al rival con la lengua y le cae encima.",
		"model": "res://scripts/frog_model.gd",
		"pal": {"body": Color(0.35, 0.72, 0.3), "belly": Color(0.98, 0.95, 0.7), "spike": Color(1.0, 0.8, 0.2),
			"back": Color(0.14, 0.42, 0.16), "stripe": Color(0.08, 0.28, 0.1), "tip": Color(0.75, 0.6, 0.2), "stripes": 0.55, "scales": 0.15},
		"pal_alt": {"body": Color(0.8, 0.5, 0.25), "belly": Color(0.98, 0.9, 0.75), "spike": Color(0.4, 0.9, 0.8),
			"back": Color(0.5, 0.25, 0.1), "stripe": Color(0.3, 0.14, 0.06), "tip": Color(0.4, 0.3, 0.5), "stripes": 0.55, "scales": 0.15},
		"base": {
			"name": "", "scale": 0.95, "speed": 1.0, "jump": 1.28, "air_jumps": 1, "glide": false, "dmg": 1.0, "armor": 1.0,
			"k": "tongue", "l": "leap", "k_name": "Lengua (atrae)", "l_name": "Gran salto",
		},
		"forms": {
			1: {
				"name": "Salamandra",
				"body": Color(0.13, 0.1, 0.12), "belly": Color(1.0, 0.7, 0.2), "spike": Color(1.0, 0.5, 0.1),
				"back": Color(0.05, 0.04, 0.06), "stripe": Color(1.0, 0.6, 0.05), "tip": Color(0.95, 0.3, 0.05), "stripes": 1.0, "scales": 0.3,
				"body_s": Vector3(1.25, 0.88, 0.85), "head_s": Vector3(1.05, 0.9, 0.9), "leg_s": 0.85,
				"scale": 1.3, "speed": 1.15, "jump": 1.1, "air_jumps": 1, "glide": false, "dmg": 1.4, "armor": 1.0,
				"k": "bounce", "l": "trail", "k_name": "Bola saltarina", "l_name": "Rastro ardiente",
			},
			2: {
				"name": "Tortuga",
				"body": Color(0.25, 0.55, 0.75), "belly": Color(0.92, 0.92, 0.72), "spike": Color(0.7, 0.9, 1.0),
				"back": Color(0.1, 0.3, 0.5), "stripe": Color(0.06, 0.18, 0.36), "tip": Color(0.15, 0.3, 0.55), "shell": Color(0.16, 0.32, 0.6), "stripes": 0.2, "scales": 0.7,
				"body_s": Vector3(1.1, 1.05, 1.15), "head_s": Vector3(0.9, 0.95, 0.85), "leg_s": 0.85,
				"scale": 1.45, "speed": 0.75, "jump": 0.92, "air_jumps": 0, "glide": false, "dmg": 1.5, "armor": 0.55,
				"k": "bubble", "l": "shell", "k_name": "Burbuja (atrapa)", "l_name": "Caparazon giratorio",
			},
			3: {
				"name": "Rana venenosa",
				"body": Color(0.1, 0.8, 0.35), "belly": Color(1.0, 0.92, 0.2), "spike": Color(1.0, 0.85, 0.1),
				"back": Color(0.05, 0.5, 0.2), "stripe": Color(0.02, 0.03, 0.05), "tip": Color(0.1, 0.25, 0.95), "stripes": 0.9, "scales": 0.05,
				"body_s": Vector3(0.95, 0.9, 0.9), "head_s": Vector3(1.0, 1.0, 1.0), "leg_s": 1.15,
				"scale": 1.1, "speed": 1.25, "jump": 1.45, "air_jumps": 2, "glide": false, "dmg": 1.1, "armor": 1.0,
				"k": "dart", "l": "croak", "k_name": "Dardo venenoso", "l_name": "Croar (empuja)",
			},
		},
	},
}
