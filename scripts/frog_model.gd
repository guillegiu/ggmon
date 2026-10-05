extends Node3D
# Rana de GGmon. Misma interfaz que dino_model.gd: pal, looks, base_scale, ghost, anim,
# anim_t, speed, vy, facing, shield_on, set_form, hit_flash.
#
# Cuerpo rechoncho y sin cuello, boca ancha, ojos saltones arriba de la cabeza, patas
# traseras enormes plegadas en Z y pies palmeados. Avanza a los saltos. Tiene lengua.
# Evoluciones: salamandra de fuego (cola, branquias y cresta de llamas), tortuga
# (caparazon con placas y pico) y rana venenosa (saco vocal, cuernos y ventosas).

const CM = preload("res://scripts/creature_mesh.gd")
const SKIN = preload("res://shaders/skin.gdshader")

const DEF := {"by": 0.0, "brz": 0.0, "hrz": 0.0, "hx": 0.0, "jaw": 0.05, "leg": 0.0, "arm": 0.0, "sac": 0.0, "lean": 0.0}
const BONE := [Color(0.5, 0.42, 0.36), Color(1.0, 1.0, 1.0)]
const SHELL := [Color(0.5, 0.52, 0.58), Color(1.0, 1.0, 1.0)]
const FLAME := [Color(1.0, 0.25, 0.0), Color(1.0, 0.95, 0.4)]

var pal := {"body": Color(0.35, 0.72, 0.3), "belly": Color(0.98, 0.95, 0.7), "spike": Color(1.0, 0.8, 0.2)}
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
var _head: Node3D
var _jaw: Node3D
var _tongue: MeshInstance3D
var _sac: MeshInstance3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _tail: Array[Node3D] = []
var _flames: Array[Node3D] = []
var _parts := {1: [], 2: [], 3: []}
var _shield: MeshInstance3D
var _std: Array[StandardMaterial3D] = []
var _ghost_was := 1.0
var _skin: ShaderMaterial
var _m_spike: StandardMaterial3D
var _m_shell: StandardMaterial3D
var _m_flame: StandardMaterial3D
var _m_bone: StandardMaterial3D
var _m_iris: StandardMaterial3D
var _m_dark: StandardMaterial3D
var _m_white: StandardMaterial3D
var _m_pink: StandardMaterial3D


func _ready() -> void:
	_base_look = _full(pal)
	for f in looks:
		_form_looks[f] = _full(looks[f])
	_skin = ShaderMaterial.new()
	_skin.shader = SKIN
	_skin.set_shader_parameter("stripe_count", 16.0)
	_m_spike = _vcolor_mat(pal.spike, 0.4)
	_m_shell = _vcolor_mat(_base_look.shell, 0.2)
	_m_shell.metallic = 0.3
	_m_flame = _vcolor_mat(Color.WHITE, 0.5)
	_m_flame.emission_enabled = true
	_m_flame.emission = Color(1.0, 0.45, 0.05)
	_m_flame.emission_energy_multiplier = 2.2
	_m_bone = _vcolor_mat(Color(0.98, 0.95, 0.85), 0.4)
	_m_dark = _vcolor_mat(Color(0.05, 0.04, 0.06), 0.2)
	_m_white = _vcolor_mat(Color(0.97, 0.97, 0.9), 0.25)
	_m_pink = _vcolor_mat(Color(1.0, 0.45, 0.55), 0.35)
	_m_iris = _vcolor_mat(Color(1.0, 0.7, 0.1), 0.25)
	_m_iris.emission_enabled = true
	_m_iris.emission = Color(1.0, 0.6, 0.05)
	_m_iris.emission_energy_multiplier = 0.6

	_flipper = _pivot(self, Vector3(0.0, 0.55, 0.0))
	_rig = _pivot(_flipper, Vector3(0.0, -0.55, 0.0))
	_body = _pivot(_rig, Vector3(0.0, 0.5, 0.0))

	# Torso: sentado, mas alto adelante que atras, ancho y chato.
	_add(_body, CM.loft([
		[0.42, 0.22, 0.3, 0.26, 0.4],
		[0.15, 0.14, 0.42, 0.38, 0.52],
		[-0.2, 0.02, 0.4, 0.36, 0.5],
		[-0.5, -0.1, 0.26, 0.22, 0.34],
		[-0.68, -0.16, 0.06, 0.06, 0.1],
	], {"seg": 22, "u": Vector2(0.3, 0.85)}), _skin)

	# Cabeza: ancha y aplastada, sin cuello.
	_head = _pivot(_body, Vector3(0.3, 0.2, 0.0))
	_add(_head, CM.loft([
		[-0.14, 0.0, 0.3, 0.24, 0.42],
		[0.12, 0.05, 0.33, 0.2, 0.47],
		[0.38, 0.02, 0.24, 0.12, 0.4],
		[0.58, -0.02, 0.09, 0.05, 0.22],
	], {"seg": 22, "u": Vector2(0.0, 0.3)}), _skin)
	for s in [-1.0, 1.0]:
		# ojos saltones con parpado y pupila horizontal
		_add(_head, CM.loft([
			[-0.08, 0.2, 0.1, 0.1, 0.12], [0.1, 0.3, 0.17, 0.12, 0.16], [0.26, 0.25, 0.08, 0.08, 0.1],
		], {"seg": 10, "z": 0.25 * s, "u": Vector2(0.05, 0.12)}), _skin)
		_add(_head, _sphere(0.15), _m_white, Vector3(0.15, 0.28, 0.27 * s))
		_add(_head, _sphere(0.1), _m_iris, Vector3(0.2, 0.28, 0.34 * s))
		_add(_head, _sphere(0.06), _m_dark, Vector3(0.23, 0.28, 0.4 * s), Vector3(1.6, 0.55, 1.0))
		_add(_head, _sphere(0.02), _m_dark, Vector3(0.54, 0.06, 0.07 * s))
	_jaw = _pivot(_head, Vector3(-0.05, -0.1, 0.0))
	_add(_jaw, CM.loft([
		[-0.02, 0.02, 0.06, 0.14, 0.4],
		[0.28, -0.02, 0.05, 0.15, 0.43],
		[0.52, 0.0, 0.04, 0.08, 0.32],
		[0.64, 0.02, 0.02, 0.03, 0.14],
	], {"seg": 18, "u": Vector2(0.0, 0.25)}), _skin)
	# lengua: se estira con la habilidad
	_tongue = _add(_head, CM.loft([
		[0.0, 0.0, 0.05, 0.05, 0.08], [0.85, 0.0, 0.04, 0.04, 0.06], [0.93, 0.0, 0.09, 0.09, 0.12], [1.0, 0.0, 0.03, 0.03, 0.05],
	], {"seg": 8, "sub": 3, "colors": [Color(0.8, 0.8, 0.8), Color.WHITE]}), _m_pink, Vector3(0.35, -0.1, 0.0))
	_tongue.visible = false
	# saco vocal: se infla al croar
	_sac = _add(_jaw, _sphere(0.3), _m_white, Vector3(0.2, -0.16, 0.0))
	_sac.visible = false

	# Brazos cortos adelante.
	for s in [-1.0, 1.0]:
		var arm := _pivot(_body, Vector3(0.3, -0.05, 0.38 * s))
		_add(arm, CM.loft([
			[0.0, 0.02, 0.1, 0.1, 0.085], [0.08, -0.2, 0.075, 0.075, 0.07], [0.1, -0.4, 0.055, 0.055, 0.06],
		], {"seg": 10, "u": Vector2(0.3, 0.4), "tip": Vector2(0.0, 0.8)}), _skin)
		_add(arm, CM.loft([
			[0.04, -0.43, 0.04, 0.03, 0.07], [0.2, -0.44, 0.03, 0.02, 0.13], [0.3, -0.45, 0.01, 0.01, 0.1],
		], {"seg": 8, "sub": 3, "u": Vector2(0.4, 0.45), "tip": Vector2(0.9, 1.0)}), _skin)
		_arms.append(arm)

	# Patas traseras: muslo hacia adelante, canilla hacia atras y pie largo palmeado.
	# Cuelgan del rig para que el rebote del cuerpo no despegue los pies.
	for s in [-1.0, 1.0]:
		var leg := _pivot(_rig, Vector3(-0.32, 0.43, 0.42 * s))
		_add(leg, CM.loft([
			[-0.02, 0.02, 0.2, 0.2, 0.15],
			[0.26, 0.1, 0.18, 0.17, 0.14],
			[0.4, -0.04, 0.11, 0.11, 0.11],
			[0.1, -0.27, 0.085, 0.085, 0.085],
			[-0.08, -0.36, 0.075, 0.075, 0.08],
		], {"seg": 12, "u": Vector2(0.45, 0.6), "tip": Vector2(0.0, 0.7)}), _skin)
		_add(leg, CM.loft([
			[-0.14, -0.385, 0.05, 0.04, 0.08], [0.15, -0.39, 0.05, 0.03, 0.15], [0.42, -0.4, 0.03, 0.02, 0.24], [0.55, -0.405, 0.01, 0.01, 0.2],
		], {"seg": 10, "sub": 4, "u": Vector2(0.55, 0.6), "tip": Vector2(0.9, 1.0)}), _skin)
		_legs.append(leg)

	_build_salamander()
	_build_turtle()
	_build_poison()
	for f in _parts:
		for part in _parts[f]:
			part.set_meta("s0", part.scale)
			part.visible = false

	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.4, 0.9, 1.0, 0.28)
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield = _add(self, _sphere(1.05), sm, Vector3(0.0, 0.6, 0.0))
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

# Salamandra de fuego: cola larga, branquias en abanico y llamas por el lomo.
func _build_salamander() -> void:
	var parent := _body
	var radii := [0.24, 0.18, 0.12, 0.07, 0.02]
	for i in 4:
		var piv := _pivot(parent, Vector3(-0.6 if i == 0 else -0.42, -0.14 if i == 0 else 0.0, 0.0))
		var r0: float = radii[i]
		var r1: float = radii[i + 1]
		var rm := (r0 + r1) * 0.5
		_add(piv, CM.loft([
			[0.1, 0.0, r0, r0, r0 * 0.8], [-0.18, 0.0, rm, rm, rm * 0.8], [-0.46, 0.0, r1, r1, r1 * 0.8],
		], {"seg": 12, "sub": 3, "u": Vector2(0.85 + i * 0.04, 0.89 + i * 0.04), "tip": Vector2(i * 0.25, (i + 1) * 0.25)}), _skin)
		var flame := _add(piv, CM.spike(0.34 - i * 0.04, 0.09, 0.3, 0.5, FLAME), _m_flame, Vector3(-0.2, rm * 0.8, 0.0), Vector3.ONE, Vector3(0.0, 0.0, 0.35))
		_flames.append(flame)
		_tail.append(piv)
		if i == 0:
			_part(1, piv)
		parent = piv
	for i in 5:
		var flame := _add(_body, CM.spike(0.4, 0.1, 0.3, 0.5, FLAME), _m_flame, Vector3(0.3 - i * 0.2, 0.5 - i * 0.07, 0.0), Vector3.ONE, Vector3(0.0, 0.0, 0.3))
		_flames.append(flame)
		_part(1, flame)
	for s in [-1.0, 1.0]:
		for i in 3:
			_part(1, _add(_head, CM.spike(0.42, 0.06, 0.4, 0.4, FLAME), _m_flame, Vector3(-0.08, 0.02 + i * 0.1, 0.38 * s), Vector3.ONE, Vector3((1.2 - i * 0.3) * s, 0.0, 0.9)))


# Tortuga: caparazon con placas y borde, pico, puas y cola corta.
func _build_turtle() -> void:
	_part(2, _add(_body, CM.loft([
		[0.42, 0.08, 0.1, 0.0, 0.3],
		[0.2, 0.12, 0.5, 0.02, 0.62],
		[-0.15, 0.08, 0.58, 0.02, 0.68],
		[-0.5, 0.0, 0.42, 0.02, 0.55],
		[-0.74, -0.08, 0.06, 0.0, 0.2],
	], {"seg": 22, "colors": SHELL}), _m_shell))
	# borde del caparazon y placa del pecho
	_part(2, _add(_body, CM.loft([
		[0.44, 0.06, 0.06, 0.06, 0.34], [0.1, 0.06, 0.07, 0.07, 0.7], [-0.3, 0.02, 0.07, 0.07, 0.68], [-0.76, -0.08, 0.05, 0.05, 0.24],
	], {"seg": 14, "colors": BONE}), _m_bone))
	for i in 3:
		for s in [-1.0, 0.0, 1.0]:
			if i == 1 or s != 0.0:
				_part(2, _add(_body, CM.spike(0.22, 0.1, 0.1, 1.0, BONE), _m_bone, Vector3(0.25 - i * 0.32, 0.5 - i * 0.06 - absf(s) * 0.12, 0.3 * s), Vector3.ONE, Vector3(0.5 * s, 0.0, 0.15)))
	_part(2, _add(_head, CM.spike(0.26, 0.13, -0.5, 0.8, BONE), _m_bone, Vector3(0.5, 0.04, 0.0), Vector3.ONE, Vector3(0.0, 0.0, -1.5)))
	_part(2, _add(_body, CM.spike(0.4, 0.1, 0.0, 0.8), _m_spike, Vector3(-0.66, -0.14, 0.0), Vector3.ONE, Vector3(0.0, 0.0, 1.7)))


# Rana venenosa: cuernos sobre los ojos, crestas a los costados y ventosas en los dedos.
func _build_poison() -> void:
	for s in [-1.0, 1.0]:
		_part(3, _add(_head, CM.spike(0.3, 0.07, 0.3), _m_spike, Vector3(0.1, 0.42, 0.26 * s), Vector3.ONE, Vector3(0.3 * s, 0.0, 0.3)))
		_part(3, _add(_body, CM.loft([
			[0.38, 0.38, 0.03, 0.03, 0.03], [0.1, 0.42, 0.07, 0.05, 0.05], [-0.25, 0.3, 0.07, 0.05, 0.05], [-0.55, 0.08, 0.02, 0.02, 0.02],
		], {"seg": 8, "z": 0.3 * s, "colors": SHELL}), _m_spike))
	for arm in _arms:
		_part(3, _add(arm, _sphere(0.08), _m_spike, Vector3(0.3, -0.45, 0.07)))
		_part(3, _add(arm, _sphere(0.08), _m_spike, Vector3(0.3, -0.45, -0.07)))
	for leg in _legs:
		for i in 3:
			_part(3, _add(leg, _sphere(0.085), _m_spike, Vector3(0.55, -0.4, (i - 1) * 0.17)))


func _part(form: int, node: Node3D) -> void:
	_parts[form].append(node)


# ---------------------------------------------------------------- animacion

func _process(delta: float) -> void:
	_t += delta
	_flash = max(0.0, _flash - delta * 5.0)
	if anim == "run" or anim == "dash":
		_phase += delta * (7.0 + 7.0 * speed)
	var tg := _target_pose()
	var k := 1.0 - exp(-22.0 * delta)
	for key in tg:
		_p[key] = lerpf(float(_p[key]), float(tg[key]), k)
	_apply(delta)


func _target_pose() -> Dictionary:
	var d := DEF.duplicate()
	var breath := sin(_t * 2.4)
	match anim:
		"idle":
			d.by = breath * 0.02
			d.sac = 0.25 + breath * 0.2
		"run":
			# avanza a los saltitos
			var hop := absf(sin(_phase))
			d.by = hop * 0.22
			d.leg = hop * 0.9
			d.brz = 0.12 - hop * 0.25
			d.arm = hop * 0.5
		"air":
			var up: float = clamp(vy / 14.0, -1.0, 1.0)
			d.leg = 1.1
			d.arm = 0.7
			d.brz = up * 0.25
		"jab":
			var lunge := sin(clamp(anim_t / 0.5, 0.0, 1.0) * PI)
			d.hx = lunge * 0.3
			d.brz = -0.2 * lunge
			d.jaw = 0.8 if anim_t < 0.25 else 0.0
		"tongue":
			d.jaw = 0.75
			d.hrz = 0.1
			d.brz = -0.08
		"croak":
			d.jaw = 0.5
			d.by = 0.1
			d.brz = 0.2
			d.sac = 1.6
		"tail":
			d.by = -0.08
			d.leg = 0.4
		"airatk":
			d.leg = 1.0
		"fire":
			if anim_t < 0.42:
				d.hrz = 0.3
				d.brz = 0.15
				d.sac = 1.0
			else:
				d.hrz = -0.1
				d.brz = -0.15
				d.jaw = 0.9
		"dash":
			d.brz = -0.35
			d.leg = 1.0
			d.arm = 0.8
			d.jaw = 0.4
		"stomp":
			d.by = -0.1
			d.leg = -0.2
			d.brz = -0.2
		"block":
			d.by = -0.1
			d.hrz = -0.25
			d.arm = -0.4
		"hurt":
			d.brz = 0.4
			d.jaw = 0.7
			d.leg = 0.6
		"ko":
			d.lean = 1.5
			d.jaw = 0.6
			d.leg = 0.9
		"evolve":
			d.by = 0.25
			d.hrz = 0.35
			d.jaw = 0.8
			d.leg = 0.7
	return d


func _apply(delta: float) -> void:
	var target_yaw := -0.35 if facing == 1 else PI + 0.35
	_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-18.0 * delta))
	var spin := 0.0
	if anim == "tail":
		spin = smoothstep(0.1, 0.9, anim_t) * TAU * (3.0 if _form == 2 and _evo > 0.5 else 1.0)
	rotation.y = _yaw + spin

	var body_s := Vector3.ONE
	var head_s := Vector3.ONE
	var leg_s := 1.0
	var size := base_scale
	var e := 0.0
	var look: Dictionary = _base_look
	if _form != 0:
		look = _form_looks[_form]
		e = clampf(_evo, 0.0, 1.0)
		size = lerpf(base_scale, look.scale, _evo)
		body_s = Vector3.ONE.lerp(look.body_s, e)
		head_s = Vector3.ONE.lerp(look.head_s, e)
		leg_s = lerpf(1.0, look.leg_s, e)
	scale = Vector3.ONE * size
	_body.scale = body_s
	_head.scale = head_s
	for leg in _legs:
		leg.scale = Vector3.ONE * leg_s
		leg.rotation.z = -float(_p.leg)
	for arm in _arms:
		arm.rotation.z = float(_p.arm)

	_flipper.rotation.z = -anim_t * TAU if anim == "airatk" else 0.0
	_rig.position.y = -0.55 + 0.43 * (leg_s - 1.0)
	_rig.rotation.z = _p.lean
	_body.position.y = 0.5 + _p.by
	_body.rotation.z = _p.brz
	_head.position.x = 0.3 + _p.hx
	_head.rotation.z = _p.hrz
	_jaw.rotation.z = -_p.jaw
	for i in _tail.size():
		_tail[i].rotation.y = sin(_t * 3.0 + i * 0.8) * 0.25
		_tail[i].rotation.z = -0.08
	for i in _flames.size():
		_flames[i].scale.y = (1.0 + sin(_t * 14.0 + i * 1.7) * 0.25) * maxf(_evo, 0.02)

	# lengua: sale y vuelve durante la habilidad
	_tongue.visible = anim == "tongue"
	if _tongue.visible:
		var reach := sin(clampf(anim_t / 0.6, 0.0, 1.0) * PI)
		_tongue.scale = Vector3(0.2 + reach * 4.3 / size, 1.0, 1.0)
	var sac: float = _p.sac
	_sac.visible = sac > 0.15
	_sac.scale = Vector3.ONE * maxf(sac, 0.15)

	var glow := _flash
	if anim == "evolve":
		glow = 0.6 + 0.4 * sin(_t * 30.0)
	for key in ["body", "back", "belly", "stripe", "tip"]:
		var c: Color = _base_look[key].lerp(look[key], e)
		_skin.set_shader_parameter({"body": "base_color"}.get(key, key + "_color"), c)
	_skin.set_shader_parameter("stripe_amount", lerpf(_base_look.stripes, look.stripes, e))
	_skin.set_shader_parameter("scale_amount", lerpf(_base_look.scales, look.scales, e))
	_skin.set_shader_parameter("flash", glow * 0.28)
	_m_spike.albedo_color = _base_look.spike.lerp(look.spike, e)
	_m_shell.albedo_color = _base_look.shell.lerp(look.shell, e)
	_m_white.albedo_color = Color(0.97, 0.97, 0.9)
	for f in _parts:
		var on: bool = f == _form and _evo > 0.02
		for part in _parts[f]:
			part.visible = on
			if on and not _flames.has(part):
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
		out["tip"] = body.lerp(spike, 0.5)
	if not out.has("shell"):
		out["shell"] = spike
	if not out.has("stripes"):
		out["stripes"] = 0.5
	if not out.has("scales"):
		out["scales"] = 0.2
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
	m.roughness = rough
	_std.append(m)
	return m


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 20
	m.rings = 10
	return m
