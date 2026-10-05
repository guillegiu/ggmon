extends Node3D
# Bicho de GGmon (la hormiguita). Misma interfaz que dino_model.gd: pal, looks,
# base_scale, anim, anim_t, speed, vy, facing, shield_on, set_form, hit_flash.
#
# Cuerpo de insecto en tres segmentos con cintura (cabeza, torax, abdomen), caparazon
# brillante, mandibulas curvas, antenas acodadas y seis patas articuladas con la
# rodilla arriba. Pieles de creature_mesh.gd pintadas con shaders/skin.gdshader.
# Evoluciones: escarabajo (cuernos en pinza), mariposa (alas con ocelos) y mantis
# (cuello, guadañas dentadas, alas plegadas).

const CM = preload("res://scripts/creature_mesh.gd")
const SKIN = preload("res://shaders/skin.gdshader")

const DEF := {"by": 0.0, "brz": 0.0, "hrz": 0.0, "hx": 0.0, "jaw": 0.15, "leg": 0.0, "arm": 0.6, "lean": 0.0}
const HEAD_POS := Vector3(0.45, 0.15, 0.0)
const BONE := [Color(0.5, 0.42, 0.36), Color(1.0, 1.0, 1.0)]
const DARK := [Color(0.5, 0.5, 0.5), Color(1.0, 1.0, 1.0)]
const SHELL := [Color(0.55, 0.55, 0.6), Color(1.0, 1.0, 1.0)]
# Patas: [x del arranque, cuanto apunta hacia adelante (rad)]
const LEGS := [[0.3, 0.75], [0.1, 0.05], [-0.1, -0.7]]

var pal := {"body": Color(0.7, 0.78, 0.2), "belly": Color(0.98, 0.93, 0.7), "spike": Color(0.5, 0.28, 0.14)}
var looks := {}
var base_scale := 1.0
# 1 = solido; menos = camuflado (se ve a medias, con trama de puntos)
var ghost := 1.0

var anim := "idle"
var anim_t := 0.0
var speed := 0.0
var vy := 0.0
var facing := 1
var shield_on := false

var _form := 0
var _evo := 0.0
var _t := 0.0
var _phase := 0.0
var _flash := 0.0
var _yaw := -0.35
var _p := DEF.duplicate()
var _base_look := {}
var _form_looks := {}

var _flipper: Node3D
var _rig: Node3D
var _body: Node3D
var _abd: Node3D
var _head: Node3D
var _jaws: Array[Node3D] = []
var _antennae: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _wings: Array[Node3D] = []
var _scythes: Array[Node3D] = []
var _parts := {1: [], 2: [], 3: []}
var _shield: MeshInstance3D
var _std: Array[StandardMaterial3D] = []
var _ghost_was := 1.0
var _skin: ShaderMaterial
var _m_shell: StandardMaterial3D
var _m_spike: StandardMaterial3D
var _m_bone: StandardMaterial3D
var _m_wing: StandardMaterial3D
var _m_iris: StandardMaterial3D
var _m_dark: StandardMaterial3D
var _m_white: StandardMaterial3D


func _ready() -> void:
	_base_look = _full(pal)
	for f in looks:
		_form_looks[f] = _full(looks[f])
	_skin = ShaderMaterial.new()
	_skin.shader = SKIN
	_skin.set_shader_parameter("stripe_count", 14.0)
	_m_shell = _vcolor_mat(_base_look.shell, 0.18)
	_m_shell.metallic = 0.35
	_m_spike = _vcolor_mat(pal.spike, 0.4)
	_m_bone = _vcolor_mat(Color(0.98, 0.95, 0.85), 0.4)
	_m_wing = _vcolor_mat(pal.spike, 0.5)
	_m_wing.cull_mode = BaseMaterial3D.CULL_DISABLED
	_m_dark = _vcolor_mat(Color(0.09, 0.08, 0.11), 0.3)
	_m_white = _vcolor_mat(Color(0.97, 0.97, 0.93), 0.3)
	_m_iris = _vcolor_mat(Color(0.2, 0.9, 0.5), 0.3)
	_m_iris.emission_enabled = true
	_m_iris.emission = Color(0.1, 0.8, 0.4)
	_m_iris.emission_energy_multiplier = 0.6

	_flipper = _pivot(self, Vector3(0.0, 0.6, 0.0))
	_rig = _pivot(_flipper, Vector3(0.0, -0.6, 0.0))
	_body = _pivot(_rig, Vector3(0.0, 0.62, 0.0))

	# Abdomen: gota que se afina hacia la cola, con cintura contra el torax.
	_abd = _pivot(_body, Vector3(-0.15, 0.0, 0.0))
	_add(_abd, CM.loft([
		[0.06, 0.02, 0.09, 0.09, 0.09],
		[-0.15, 0.05, 0.3, 0.28, 0.3],
		[-0.45, 0.06, 0.4, 0.36, 0.4],
		[-0.75, 0.0, 0.3, 0.28, 0.3],
		[-0.96, -0.06, 0.05, 0.05, 0.05],
	], {"seg": 20, "u": Vector2(0.5, 1.0), "tip": Vector2(0.0, 0.7)}), _skin)
	# Caparazon: media cascara brillante sobre el lomo, con la linea donde se abren los elitros.
	_add(_abd, CM.loft([
		[0.0, 0.1, 0.1, 0.0, 0.12],
		[-0.2, 0.13, 0.3, 0.03, 0.34],
		[-0.48, 0.13, 0.38, 0.03, 0.44],
		[-0.78, 0.05, 0.27, 0.03, 0.33],
		[-0.98, -0.03, 0.04, 0.0, 0.05],
	], {"seg": 20, "colors": SHELL}), _m_shell)
	_add(_abd, CM.loft([
		[-0.02, 0.12, 0.1, 0.0, 0.012], [-0.48, 0.15, 0.385, 0.0, 0.012], [-0.97, -0.02, 0.05, 0.0, 0.012],
	], {"seg": 6, "colors": DARK}), _m_dark)

	# Torax
	_add(_body, CM.loft([
		[0.44, 0.13, 0.12, 0.12, 0.13],
		[0.26, 0.1, 0.26, 0.24, 0.26],
		[0.05, 0.05, 0.28, 0.26, 0.27],
		[-0.14, 0.02, 0.1, 0.1, 0.1],
	], {"seg": 18, "u": Vector2(0.25, 0.5)}), _skin)
	_add(_body, CM.loft([
		[0.36, 0.14, 0.2, 0.0, 0.2], [0.16, 0.1, 0.29, 0.02, 0.29], [-0.06, 0.06, 0.2, 0.0, 0.22],
	], {"seg": 16, "colors": SHELL}), _m_shell)

	# Cabeza: ojos grandes, mandibulas curvas que cierran en pinza y antenas acodadas.
	_head = _pivot(_body, HEAD_POS)
	_add(_head, CM.loft([
		[-0.1, 0.0, 0.11, 0.11, 0.13],
		[0.08, 0.04, 0.27, 0.22, 0.28],
		[0.25, 0.02, 0.24, 0.2, 0.26],
		[0.39, -0.03, 0.1, 0.09, 0.15],
	], {"seg": 18, "u": Vector2(0.0, 0.25)}), _skin)
	for s in [-1.0, 1.0]:
		_add(_head, _sphere(0.115), _m_white, Vector3(0.2, 0.12, 0.2 * s))
		_add(_head, _sphere(0.075), _m_iris, Vector3(0.25, 0.125, 0.245 * s))
		_add(_head, _sphere(0.04), _m_dark, Vector3(0.29, 0.13, 0.285 * s))
		_add(_head, CM.loft([
			[0.08, 0.26, 0.04, 0.04, 0.06], [0.22, 0.25, 0.05, 0.04, 0.07], [0.34, 0.18, 0.02, 0.02, 0.03],
		], {"seg": 8, "z": 0.2 * s, "colors": SHELL}), _m_shell)
		var jaw := _pivot(_head, Vector3(0.33, -0.1, 0.12 * s))
		_add(jaw, CM.spike(0.42, 0.085, 0.6, 0.7, BONE), _m_bone, Vector3.ZERO, Vector3.ONE, Vector3(-PI * 0.5 * s, 0.0, -PI * 0.5))
		jaw.set_meta("side", s)
		_jaws.append(jaw)
		var ant := _pivot(_head, Vector3(0.1, 0.2, 0.1 * s))
		_add(ant, CM.loft([
			[0.0, 0.0, 0.03, 0.03, 0.03], [0.1, 0.32, 0.022, 0.022, 0.022], [0.36, 0.44, 0.018, 0.018, 0.018],
			[0.55, 0.36, 0.035, 0.035, 0.035], [0.6, 0.33, 0.008, 0.008, 0.008],
		], {"seg": 6, "sub": 4, "colors": DARK}), _m_dark)
		ant.set_meta("side", s)
		_antennae.append(ant)

	# Seis patas. Cuelgan del rig para que el rebote del cuerpo no despegue los pies.
	for i in 3:
		for s in [-1.0, 1.0]:
			var leg := _pivot(_rig, Vector3(LEGS[i][0], 0.52, 0.17 * s))
			_add(leg, CM.loft([
				[0.0, 0.0, 0.1, 0.1, 0.085],
				[0.17, 0.2, 0.095, 0.095, 0.08],
				[0.3, 0.3, 0.085, 0.085, 0.07],
				[0.42, 0.06, 0.06, 0.06, 0.055],
				[0.5, -0.34, 0.042, 0.042, 0.04],
				[0.57, -0.49, 0.04, 0.035, 0.045],
				[0.69, -0.505, 0.015, 0.015, 0.03],
			], {"seg": 8, "sub": 3, "u": Vector2(0.3, 0.42), "tip": Vector2(0.25, 1.0)}), _skin)
			_add(leg, CM.spike(0.1, 0.025, 0.0, 1.0, BONE), _m_bone, Vector3(0.31, 0.33, 0.0), Vector3.ONE, Vector3(0.0, 0.0, -0.4))
			_add(leg, CM.spike(0.08, 0.02, 0.0, 1.0, BONE), _m_bone, Vector3(0.48, -0.12, 0.0), Vector3.ONE, Vector3(0.0, 0.0, -1.3))
			leg.set_meta("side", s)
			leg.set_meta("fwd", LEGS[i][1])
			leg.set_meta("phase", (i % 2) * PI + (0.0 if s > 0.0 else PI))
			_legs.append(leg)

	_build_beetle()
	_build_butterfly()
	_build_mantis()
	for f in _parts:
		for part in _parts[f]:
			part.set_meta("s0", part.scale)
			part.visible = false

	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.4, 0.9, 1.0, 0.28)
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield = _add(self, _sphere(1.05), sm, Vector3(0.0, 0.7, 0.0))
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shield.visible = false

	_yaw = -0.35 if facing == 1 else PI + 0.35
	_apply(0.0)


# form 0 vuelve a la forma base.
func set_form(form: int) -> void:
	var tw := create_tween()
	if form == 0:
		tw.tween_property(self, "_evo", 0.0, 0.5)
		return
	if form != _form:
		_evo = 0.0
	_form = form
	tw.tween_property(self, "_evo", 1.0, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hit_flash() -> void:
	_flash = 1.0


# ---------------------------------------------------------------- piezas por forma

# Escarabajo hercules: dos cuernos que se cierran en pinza (el del torax baja, el de la
# cabeza sube), puas en el caparazon y hombreras.
func _build_beetle() -> void:
	_part(1, _add(_body, CM.spike(1.25, 0.13, -0.28), _m_spike, Vector3(0.2, 0.3, 0.0), Vector3.ONE, Vector3(0.0, 0.0, -1.2)))
	_part(1, _add(_head, CM.spike(0.85, 0.1, 0.4), _m_spike, Vector3(0.28, -0.02, 0.0), Vector3.ONE, Vector3(0.0, 0.0, -1.45)))
	for s in [-1.0, 1.0]:
		_part(1, _add(_body, CM.spike(0.3, 0.05, 0.2), _m_spike, Vector3(0.75, 0.58, 0.0), Vector3.ONE, Vector3(0.9 * s, 0.0, -0.9)))
		_part(1, _add(_body, CM.spike(0.34, 0.09, 0.3), _m_spike, Vector3(0.2, 0.3, 0.2 * s), Vector3.ONE, Vector3(0.7 * s, 0.0, 0.2)))
		for i in 3:
			_part(1, _add(_abd, CM.spike(0.24, 0.07, 0.3), _m_spike, Vector3(-0.2 - i * 0.24, 0.42 - i * 0.04, 0.2 * s), Vector3.ONE, Vector3(0.45 * s, 0.0, 0.35)))


# Mariposa: cuatro alas con nervaduras y ocelos, antenas largas enruladas.
func _build_butterfly() -> void:
	var upper := [Vector2(0.12, 0.15), Vector2(0.3, 0.85), Vector2(0.12, 1.5), Vector2(-0.45, 1.8), Vector2(-1.05, 1.55), Vector2(-1.3, 0.95), Vector2(-1.0, 0.45), Vector2(-0.4, 0.15), Vector2(-0.1, 0.02)]
	var lower := [Vector2(-0.1, 0.05), Vector2(-0.55, 0.15), Vector2(-1.05, 0.25), Vector2(-1.3, -0.15), Vector2(-1.2, -0.7), Vector2(-0.8, -0.45), Vector2(-0.3, -0.25), Vector2(0.0, -0.08)]
	for s in [-1.0, 1.0]:
		var wing := _pivot(_body, Vector3(0.05, 0.22, 0.1 * s))
		_add(wing, CM.wing(Vector2.ZERO, upper), _m_wing)
		_add(wing, CM.wing(Vector2.ZERO, lower), _m_wing)
		# pocas nervaduras finas
		for tip in [Vector2(0.1, 1.2), Vector2(-0.4, 1.45), Vector2(-0.9, 1.2), Vector2(-1.0, 0.7), Vector2(-1.0, 0.1), Vector2(-0.95, -0.4)]:
			_add(wing, CM.loft([[0.0, 0.0, 0.022, 0.022, 0.014], [tip.x * 0.55, tip.y * 0.55, 0.014, 0.014, 0.01], [tip.x, tip.y, 0.004, 0.004, 0.004]], {"seg": 5, "sub": 2, "colors": DARK}), _m_dark)
		# ocelos, de los dos lados del ala
		for spot in [[-0.5, 1.2, 0.2], [-0.9, 0.85, 0.12], [-0.9, -0.15, 0.15]]:
			_add(wing, _sphere(spot[2]), _m_white, Vector3(spot[0], spot[1], 0.0), Vector3(1.0, 1.0, 0.06))
			_add(wing, _sphere(spot[2] * 0.62), _m_dark, Vector3(spot[0], spot[1], 0.0), Vector3(1.0, 1.0, 0.1))
			_add(wing, _sphere(spot[2] * 0.25), _m_iris, Vector3(spot[0] + spot[2] * 0.15, spot[1] + spot[2] * 0.15, 0.0), Vector3(1.0, 1.0, 0.14))
		_wings.append(wing)
		_part(2, wing)
		_part(2, _add(_head, CM.loft([
			[0.12, 0.2, 0.025, 0.025, 0.025], [0.3, 0.7, 0.02, 0.02, 0.02], [0.6, 0.95, 0.018, 0.018, 0.018],
			[0.82, 0.8, 0.02, 0.02, 0.02], [0.78, 0.62, 0.035, 0.035, 0.035], [0.72, 0.6, 0.01, 0.01, 0.01],
		], {"seg": 6, "sub": 4, "z": 0.14 * s, "colors": DARK}), _m_dark))
	# collar de pelusa
	for i in 5:
		var a := -1.0 + i * 0.5
		_part(2, _add(_body, _sphere(0.11), _m_white, Vector3(0.36, 0.14 + 0.2 * cos(a), 0.22 * sin(a))))


# Mantis: cuello largo, guadañas con dientes y alas plegadas sobre el abdomen.
func _build_mantis() -> void:
	_part(3, _add(_body, CM.loft([
		[0.28, 0.1, 0.14, 0.14, 0.14], [0.46, 0.42, 0.1, 0.1, 0.1], [0.7, 0.78, 0.09, 0.09, 0.1],
	], {"seg": 12, "u": Vector2(0.15, 0.3)}), _skin))
	for s in [-1.0, 1.0]:
		var arm := _pivot(_body, Vector3(0.36, 0.2, 0.2 * s))
		_add(arm, CM.loft([
			[0.0, 0.0, 0.075, 0.075, 0.06], [0.15, 0.25, 0.065, 0.065, 0.055], [0.28, 0.46, 0.05, 0.05, 0.045],
		], {"seg": 8, "u": Vector2(0.3, 0.4)}), _skin)
		_add(arm, CM.spike(0.9, 0.1, -0.3, 0.4), _m_spike, Vector3(0.28, 0.46, 0.0), Vector3.ONE, Vector3(0.0, 0.0, PI + 0.78))
		for i in 4:
			var f := 0.15 + i * 0.17
			_add(arm, CM.spike(0.13, 0.03, 0.0, 1.0, BONE), _m_bone, Vector3(0.28 + 0.6 * f - 0.03, 0.46 - 0.6 * f - 0.03, 0.0), Vector3.ONE, Vector3(0.0, 0.0, 2.36))
		_scythes.append(arm)
		_part(3, arm)
		_part(3, _add(_abd, CM.loft([
			[0.0, 0.2, 0.02, 0.02, 0.08], [-0.5, 0.3, 0.03, 0.03, 0.2], [-1.0, 0.2, 0.02, 0.02, 0.13], [-1.25, 0.12, 0.0, 0.0, 0.0],
		], {"seg": 10, "z": 0.1 * s, "colors": SHELL}), _m_spike, Vector3.ZERO, Vector3.ONE, Vector3(0.25 * s, 0.0, 0.0)))
	# cabeza triangular: mejillas en punta
	for s in [-1.0, 1.0]:
		_part(3, _add(_head, CM.spike(0.2, 0.09, 0.0, 0.6), _m_spike, Vector3(0.12, 0.05, 0.22 * s), Vector3.ONE, Vector3(1.35 * s, 0.0, 0.0)))


func _part(form: int, node: Node3D) -> void:
	_parts[form].append(node)


# ---------------------------------------------------------------- animacion

func _process(delta: float) -> void:
	_t += delta
	_flash = max(0.0, _flash - delta * 5.0)
	if anim == "run" or anim == "dash":
		_phase += delta * (9.0 + 12.0 * speed)
	var tg := _target_pose()
	var k := 1.0 - exp(-22.0 * delta)
	for key in tg:
		_p[key] = lerpf(float(_p[key]), float(tg[key]), k)
	_apply(delta)


func _target_pose() -> Dictionary:
	var d := DEF.duplicate()
	var breath := sin(_t * 3.0)
	match anim:
		"idle":
			d.by = breath * 0.02
			d.hrz = breath * 0.05
		"run":
			d.leg = 0.5
			d.by = abs(sin(_phase)) * 0.04
			d.brz = -0.1
		"air":
			var up: float = clamp(vy / 14.0, -1.0, 1.0)
			d.brz = up * 0.2
			d.jaw = 0.4 if up < 0.0 else 0.15
		"jab":
			var lunge := sin(clamp(anim_t / 0.5, 0.0, 1.0) * PI)
			d.hx = lunge * 0.35
			d.brz = -0.2 * lunge
			d.jaw = 0.9 if anim_t < 0.25 else -0.1
			d.arm = 0.9 if anim_t < 0.25 else -0.9
		"slash":
			d.brz = -0.25
			d.hrz = -0.1
			d.arm = 1.3 if anim_t < 0.2 else -1.2
			d.jaw = 0.6
		"tail":
			d.brz = -0.15
			d.by = -0.06
		"fire":
			if anim_t < 0.42:
				d.hrz = 0.5
				d.brz = 0.12
				d.jaw = 0.3
			else:
				d.hrz = -0.2
				d.brz = -0.15
				d.hx = 0.12
				d.jaw = 1.0
		"dash":
			d.leg = 0.55
			d.brz = -0.35
			d.hrz = -0.3
			d.jaw = 0.5
		"block":
			d.by = -0.1
			d.hrz = -0.4
			d.arm = 1.4
		"hurt":
			d.brz = 0.45
			d.hrz = 0.3
			d.jaw = 0.9
		"ko":
			d.lean = 1.6
			d.jaw = 0.7
		"evolve":
			d.by = 0.25
			d.hrz = 0.4
			d.jaw = 0.9
			d.arm = 1.3
	return d


func _apply(delta: float) -> void:
	var target_yaw := -0.35 if facing == 1 else PI + 0.35
	_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-18.0 * delta))
	var spin := 0.0
	if anim == "tail":
		spin = smoothstep(0.15, 0.75, anim_t) * TAU
	rotation.y = _yaw + spin

	var abd_s := Vector3.ONE
	var head_s := Vector3.ONE
	var head_off := Vector3.ZERO
	var size := base_scale
	var e := 0.0
	var look: Dictionary = _base_look
	if _form != 0:
		look = _form_looks[_form]
		e = clampf(_evo, 0.0, 1.0)
		size = lerpf(base_scale, look.scale, _evo)
		abd_s = Vector3.ONE.lerp(look.abd_s, e)
		head_s = Vector3.ONE.lerp(look.head_s, e)
		head_off = Vector3.ZERO.lerp(look.head_off, e)
	scale = Vector3.ONE * size
	_abd.scale = abd_s
	_head.scale = head_s

	# Voltereta en el golpe aereo; la forma base ademas rueda hecha bolita al embestir.
	var flip := 0.0
	if anim == "airatk":
		flip = -anim_t * TAU
	elif anim == "dash" and _evo < 0.5:
		flip = -anim_t * TAU * 3.0
	_flipper.rotation.z = flip
	_rig.rotation.z = _p.lean
	_body.position.y = 0.62 + _p.by
	_body.rotation.z = _p.brz
	_head.position = HEAD_POS + head_off + Vector3(_p.hx, 0.0, 0.0)
	_head.rotation.z = _p.hrz
	for jaw in _jaws:
		var side: float = jaw.get_meta("side")
		jaw.rotation.y = -side * (float(_p.jaw) - 0.3)
	for ant in _antennae:
		var side: float = ant.get_meta("side")
		ant.rotation.z = sin(_t * 4.0 + side) * 0.15
		ant.rotation.x = side * 0.3
	# Patas: se abren hacia el costado; al caminar se balancean en tripode y se levantan al avanzar.
	var droop := 0.0
	if anim == "air":
		droop = -0.35
	elif anim == "ko":
		droop = 0.45
	for leg in _legs:
		var side: float = leg.get_meta("side")
		var fwd: float = leg.get_meta("fwd")
		var ph: float = leg.get_meta("phase")
		var swing := sin(_phase + ph) * float(_p.leg)
		leg.rotation.y = -side * PI * 0.5 + side * (fwd + swing)
		leg.rotation.z = maxf(cos(_phase + ph), 0.0) * float(_p.leg) * 0.5 + droop
	var flap := sin(_t * 18.0) * 0.6 if anim == "air" or anim == "dash" else sin(_t * 2.5) * 0.15
	if _wings.size() == 2:
		_wings[0].rotation.x = -(0.55 + flap)
		_wings[1].rotation.x = 0.55 + flap
	for arm in _scythes:
		arm.rotation.z = _p.arm

	var glow := _flash
	if anim == "evolve":
		glow = 0.6 + 0.4 * sin(_t * 30.0)
	for key in ["body", "back", "belly", "stripe", "tip"]:
		var c: Color = _base_look[key].lerp(look[key], e)
		_skin.set_shader_parameter({"body": "base_color"}.get(key, key + "_color"), c)
	_skin.set_shader_parameter("stripe_amount", lerpf(_base_look.stripes, look.stripes, e))
	_skin.set_shader_parameter("scale_amount", lerpf(_base_look.scales, look.scales, e))
	_skin.set_shader_parameter("flash", glow * 0.28)
	_m_shell.albedo_color = _base_look.shell.lerp(look.shell, e)
	_m_spike.albedo_color = _base_look.spike.lerp(look.spike, e)
	_m_wing.albedo_color = look.spike
	for f in _parts:
		var on: bool = f == _form and _evo > 0.02
		for part in _parts[f]:
			part.visible = on
			if on:
				var s0: Vector3 = part.get_meta("s0")
				part.scale = s0 * maxf(_evo, 0.02)
	_shield.visible = shield_on

	_skin.set_shader_parameter("alpha", ghost)
	if ghost != _ghost_was:
		_ghost_was = ghost
		for m in _std:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH if ghost < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	for m in _std:
		m.albedo_color.a = ghost


# ---------------------------------------------------------------- construccion

# Completa los colores de pintura que la paleta no define, derivandolos del color de cuerpo.
func _full(p: Dictionary) -> Dictionary:
	var out := p.duplicate()
	var body: Color = p.body
	var spike: Color = p.spike
	if not out.has("back"):
		out["back"] = body.darkened(0.45)
	if not out.has("stripe"):
		out["stripe"] = body.darkened(0.65)
	if not out.has("tip"):
		out["tip"] = body.darkened(0.75)
	if not out.has("shell"):
		out["shell"] = spike
	if not out.has("stripes"):
		out["stripes"] = 0.5
	if not out.has("scales"):
		out["scales"] = 0.15
	return out


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _add(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	parent.add_child(mi)
	return mi


# Material que toma el degrade por vertice (base oscura, punta clara) y lo tiñe.
func _vcolor_mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.vertex_color_use_as_albedo = true
	_std.append(m)
	m.roughness = rough
	return m


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 20
	m.rings = 10
	return m
