extends Node3D
# Dinosaurio de GGmon. Interfaz: pal, looks, base_scale, anim, anim_t, speed, vy,
# facing, shield_on, set_form, hit_flash.
#
# El cuerpo son pieles continuas generadas con creature_mesh.gd (torso, cabeza,
# mandibula, cola, patas y brazos con masa muscular) y pintadas con shaders/skin.gdshader
# (lomo oscuro, panza clara, rayas, escamas, extremidades de otro color). Cuernos,
# garras y puas son conos curvos con degrade de base oscura a punta clara.
# Las evoluciones reutilizan el cuerpo: cambian proporciones, pintura y suman piezas
# propias (alas y cuernos, gola y placas, cresta de plumas y garras en hoz).

const CM = preload("res://scripts/creature_mesh.gd")
const SKIN = preload("res://shaders/skin.gdshader")

const DEF := {
	"by": 0.0, "brz": 0.0, "hrz": 0.0, "hx": 0.0, "jaw": 0.0,
	"ll": 0.0, "lr": 0.0, "arm": 0.0, "tz": 0.15, "ty": 0.0, "lean": 0.0,
}
const TAIL_R := [0.25, 0.19, 0.135, 0.085, 0.02]
# Lomo del torso: [x, y] donde apoyan puas y placas.
const BACK := [[0.25, 0.42], [0.08, 0.41], [-0.1, 0.39], [-0.28, 0.37], [-0.45, 0.29]]
const BONE := [Color(0.5, 0.42, 0.36), Color(1.0, 1.0, 1.0)]

var pal := {"body": Color(0.95, 0.55, 0.12), "belly": Color(1.0, 0.9, 0.6), "spike": Color(0.8, 0.2, 0.1)}
# Aspecto de cada evolucion (forms.gd SPECIES[...].forms); lo setea quien crea el modelo.
var looks := {}
var base_scale := 1.0
# 1 = solido; menos = camuflado (se ve a medias, con trama de puntos)
var ghost := 1.0

# Estado que escribe el luchador en cada frame de fisica.
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
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _tail: Array[Node3D] = []
var _wings: Array[Node3D] = []
var _parts := {1: [], 2: [], 3: []}
var _shield: MeshInstance3D
var _std: Array[StandardMaterial3D] = []
var _ghost_was := 1.0
var _skin: ShaderMaterial
var _m_spike: StandardMaterial3D
var _m_bone: StandardMaterial3D
var _m_wing: StandardMaterial3D
var _m_iris: StandardMaterial3D


func _ready() -> void:
	_base_look = _full(pal)
	for f in looks:
		_form_looks[f] = _full(looks[f])
	_skin = ShaderMaterial.new()
	_skin.shader = SKIN
	_m_spike = _vcolor_mat(pal.spike)
	_m_bone = _vcolor_mat(Color(0.98, 0.95, 0.85))
	_m_wing = _vcolor_mat(pal.belly)
	_m_wing.cull_mode = BaseMaterial3D.CULL_DISABLED
	_m_iris = _flat_mat(Color(1.0, 0.85, 0.1))
	_m_iris.emission_enabled = true
	_m_iris.emission = Color(1.0, 0.7, 0.1)
	_m_iris.emission_energy_multiplier = 0.8
	var m_white := _flat_mat(Color(0.97, 0.97, 0.93))
	var m_dark := _flat_mat(Color(0.04, 0.03, 0.05))
	m_dark.roughness = 0.2

	_flipper = _pivot(self, Vector3(0.0, 0.9, 0.0))
	_rig = _pivot(_flipper, Vector3(0.0, -0.9, 0.0))
	_body = _pivot(_rig, Vector3(0.0, 0.95, 0.0))

	# Torso: del cuello a la raiz de la cola, con pecho y cadera marcados.
	_add(_body, CM.loft([
		[0.66, 0.42, 0.13, 0.13, 0.13],
		[0.52, 0.32, 0.2, 0.2, 0.19],
		[0.3, 0.1, 0.34, 0.4, 0.34],
		[0.0, -0.02, 0.42, 0.47, 0.42],
		[-0.3, 0.0, 0.38, 0.4, 0.37],
		[-0.58, -0.03, 0.26, 0.26, 0.24],
	], {"seg": 20, "u": Vector2(0.22, 0.6)}), _skin)
	for b in BACK:
		_add(_body, CM.spike(0.26, 0.08, 0.3, 0.55), _m_spike, Vector3(b[0], b[1] - 0.04, 0.0), Vector3.ONE, Vector3(0.0, 0.0, 0.25))

	# Cabeza: craneo ancho, ceño marcado y hocico que se afina.
	_head = _pivot(_body, Vector3(0.55, 0.4, 0.0))
	_add(_head, CM.loft([
		[-0.08, 0.02, 0.17, 0.17, 0.18],
		[0.12, 0.12, 0.3, 0.2, 0.3],
		[0.36, 0.1, 0.25, 0.13, 0.27],
		[0.6, 0.04, 0.16, 0.09, 0.2],
		[0.82, 0.0, 0.12, 0.07, 0.16],
		[0.93, -0.02, 0.04, 0.03, 0.06],
	], {"seg": 20, "u": Vector2(0.0, 0.22)}), _skin)
	for s in [-1.0, 1.0]:
		_add(_head, _sphere(0.085), m_white, Vector3(0.33, 0.2, 0.215 * s))
		_add(_head, _sphere(0.052), _m_iris, Vector3(0.375, 0.2, 0.252 * s))
		_add(_head, _sphere(0.028), m_dark, Vector3(0.405, 0.2, 0.275 * s))
		# ceja: le da gesto de pelea
		_add(_head, CM.loft([
			[0.2, 0.33, 0.05, 0.05, 0.07], [0.34, 0.3, 0.06, 0.05, 0.08], [0.5, 0.22, 0.02, 0.02, 0.04],
		], {"seg": 8, "z": 0.2 * s, "u": Vector2(0.05, 0.1)}), _skin)
		_add(_head, _sphere(0.022), m_dark, Vector3(0.87, 0.07, 0.07 * s))
		for i in 4:
			_add(_head, CM.spike(0.1, 0.03, 0.0, 1.0, BONE), _m_bone, Vector3(0.47 + i * 0.1, -0.05, (0.16 - i * 0.015) * s), Vector3.ONE, Vector3(PI, 0.0, 0.0))
	_jaw = _pivot(_head, Vector3(0.2, -0.1, 0.0))
	_add(_jaw, CM.loft([
		[-0.02, 0.02, 0.07, 0.1, 0.19],
		[0.25, -0.02, 0.06, 0.12, 0.21],
		[0.5, -0.01, 0.05, 0.08, 0.16],
		[0.68, 0.01, 0.02, 0.03, 0.06],
	], {"seg": 14, "u": Vector2(0.0, 0.2)}), _skin)
	for s in [-1.0, 1.0]:
		for i in 3:
			_add(_jaw, CM.spike(0.08, 0.025, 0.0, 1.0, BONE), _m_bone, Vector3(0.3 + i * 0.11, 0.03, (0.14 - i * 0.02) * s))

	# Cola: cadena de pivotes; cada tramo se solapa con el siguiente para poder curvarla.
	var parent := _body
	for i in 4:
		var piv := _pivot(parent, Vector3(-0.5 if i == 0 else -0.42, -0.03 if i == 0 else 0.0, 0.0))
		var r0: float = TAIL_R[i]
		var r1: float = TAIL_R[i + 1]
		var rm := (r0 + r1) * 0.5
		_add(piv, CM.loft([
			[0.08, 0.0, r0, r0, r0 * 0.9], [-0.18, 0.0, rm, rm, rm * 0.9], [-0.46, 0.0, r1, r1, r1 * 0.9],
		], {"seg": 14, "sub": 3, "u": Vector2(0.6 + i * 0.1, 0.7 + i * 0.1), "tip": Vector2(i * 0.2, (i + 1) * 0.2)}), _skin)
		_add(piv, CM.spike(0.2, 0.06, 0.3, 0.55), _m_spike, Vector3(-0.2, rm * 0.85, 0.0), Vector3.ONE, Vector3(0.0, 0.0, 0.3))
		_tail.append(piv)
		parent = piv

	_arm_l = _make_arm(0.33)
	_arm_r = _make_arm(-0.33)
	# Las piernas cuelgan del rig y no del torso, asi el rebote del cuerpo no despega los pies.
	_leg_l = _make_leg(0.3)
	_leg_r = _make_leg(-0.3)

	_build_dragon()
	_build_trike()
	_build_raptor()
	for f in _parts:
		for part in _parts[f]:
			part.set_meta("s0", part.scale)
			part.visible = false

	# Escudo de bloqueo
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.4, 0.9, 1.0, 0.28)
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield = _add(self, _sphere(1.15), sm, Vector3(0.0, 0.9, 0.0))
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

# Dragon: alas de murcielago, cuernos largos curvados hacia atras y cresta de puas.
func _build_dragon() -> void:
	for b in BACK:
		_part(1, _add(_body, CM.spike(0.5, 0.11, 0.35, 0.6), _m_spike, Vector3(b[0], b[1] - 0.05, 0.0), Vector3.ONE, Vector3(0.0, 0.0, 0.3)))
	for s in [-1.0, 1.0]:
		_part(1, _add(_head, CM.spike(0.8, 0.09, 0.5), _m_spike, Vector3(0.06, 0.26, 0.17 * s), Vector3.ONE, Vector3(0.3 * s, 0.0, 0.9)))
		_part(1, _add(_head, CM.spike(0.3, 0.05, 0.4), _m_spike, Vector3(-0.02, 0.1, 0.24 * s), Vector3.ONE, Vector3(0.9 * s, 0.0, 1.2)))
		_part(1, _add(_jaw, CM.spike(0.2, 0.045, 0.3), _m_spike, Vector3(0.1, -0.1, 0.12 * s), Vector3.ONE, Vector3(0.0, 0.0, PI - 0.5)))

		var wing := _pivot(_body, Vector3(-0.05, 0.3, 0.22 * s))
		var wrist := Vector2(0.05, 1.0)
		var tips := [Vector2(-0.45, 1.6), Vector2(-1.15, 1.25), Vector2(-1.45, 0.6)]
		_add(wing, CM.loft([[0.0, 0.0, 0.07, 0.07, 0.06], [-0.3, 0.55, 0.055, 0.055, 0.05], [wrist.x, wrist.y, 0.045, 0.045, 0.04]], {"seg": 8, "sub": 3}), _skin)
		for tip in tips:
			var mid: Vector2 = wrist.lerp(tip, 0.5) + Vector2(0.03, 0.06)
			_add(wing, CM.loft([[wrist.x, wrist.y, 0.035, 0.035, 0.03], [mid.x, mid.y, 0.025, 0.025, 0.02], [tip.x, tip.y, 0.008, 0.008, 0.008]], {"seg": 6, "sub": 3}), _skin)
		# membrana con borde festoneado entre dedo y dedo
		var edge: Array = [Vector3.ZERO, Vector3(wrist.x, wrist.y, 0.0)]
		var last := Vector2(-0.65, -0.05)
		for i in tips.size():
			var t: Vector2 = tips[i]
			edge.append(Vector3(t.x, t.y, 0.0))
			var nxt: Vector2 = tips[i + 1] if i + 1 < tips.size() else last
			var dip: Vector2 = t.lerp(nxt, 0.5).lerp(wrist, 0.22)
			edge.append(Vector3(dip.x, dip.y, 0.0))
		edge.append(Vector3(last.x, last.y, 0.0))
		_add(wing, CM.membrane(edge), _m_wing)
		_add(wing, CM.spike(0.22, 0.045, 0.3, 1.0, BONE), _m_bone, Vector3(wrist.x, wrist.y, 0.0), Vector3.ONE, Vector3(0.0, 0.0, -0.5))
		_wings.append(wing)
		_part(1, wing)
	_part(1, _add(_head, CM.spike(0.28, 0.06, 0.25), _m_spike, Vector3(0.7, 0.12, 0.0), Vector3.ONE, Vector3(0.0, 0.0, -0.2)))


# Triceratops: gola con puntas, dos cuernos largos y uno nasal, placas en el lomo y maza en la cola.
func _build_trike() -> void:
	_part(2, _add(_head, CM.loft([
		[-0.07, 0.0, 0.04, 0.04, 0.04], [-0.03, 0.0, 0.5, 0.26, 0.56], [0.03, 0.0, 0.56, 0.3, 0.64], [0.08, 0.0, 0.04, 0.04, 0.04],
	], {"seg": 22, "sub": 3, "u": Vector2(0.0, 0.08)}), _skin, Vector3(-0.08, 0.22, 0.0), Vector3.ONE, Vector3(0.0, 0.0, 0.45)))
	for i in 5:
		var a := -1.2 + i * 0.6
		# sobre el borde de la gola, que esta inclinada 0.45 rad hacia atras
		var rim := 0.5 * cos(a)
		_part(2, _add(_head, CM.spike(0.26, 0.075, 0.0, 1.0, BONE), _m_bone, Vector3(-0.08 - 0.435 * rim, 0.22 + 0.9 * rim, 0.58 * sin(a)), Vector3.ONE, Vector3(a, 0.0, 0.45)))
	for s in [-1.0, 1.0]:
		_part(2, _add(_head, CM.spike(0.85, 0.095, 0.3, 1.0, BONE), _m_bone, Vector3(0.3, 0.26, 0.17 * s), Vector3.ONE, Vector3(-0.2 * s, 0.0, -1.2)))
	_part(2, _add(_head, CM.spike(0.38, 0.09, 0.2, 1.0, BONE), _m_bone, Vector3(0.72, 0.1, 0.0), Vector3.ONE, Vector3(0.0, 0.0, -0.55)))
	for i in 4:
		var b: Array = BACK[i]
		_part(2, _add(_body, _lens(0.17, 0.07, 0.3), _m_spike, Vector3(b[0] - 0.05, b[1], 0.0)))
		for s in [-1.0, 1.0]:
			_part(2, _add(_body, _lens(0.13, 0.05, 0.14), _m_spike, Vector3(b[0] - 0.05, b[1] - 0.14, 0.3 * s), Vector3.ONE, Vector3(0.7 * s, 0.0, 0.0)))
	var tip := _tail[3]
	_part(2, _add(tip, _lens(0.26, 0.22, 0.22), _m_spike, Vector3(-0.42, 0.0, 0.0)))
	for a in [0.0, PI * 0.5, PI, PI * 1.5]:
		_part(2, _add(tip, CM.spike(0.26, 0.07, 0.0, 1.0, BONE), _m_bone, Vector3(-0.42, 0.2 * cos(a), 0.2 * sin(a)), Vector3.ONE, Vector3(a, 0.0, 0.0)))


# Raptor: cresta y plumas aplanadas, garras en hoz. Las rayas las pone el shader.
func _build_raptor() -> void:
	for i in 5:
		_part(3, _add(_head, CM.spike(0.62, 0.06, 0.5, 0.3), _m_spike, Vector3(0.06 - i * 0.04, 0.27, (i - 2) * 0.07), Vector3.ONE, Vector3((i - 2) * 0.14, 0.0, 0.85 + abs(i - 2) * 0.12)))
	for arm in [_arm_l, _arm_r]:
		for i in 3:
			_part(3, _add(arm, CM.spike(0.46, 0.05, 0.3, 0.3), _m_spike, Vector3(0.04 + i * 0.09, -0.1 - i * 0.03, 0.0), Vector3.ONE, Vector3(0.0, 0.0, 2.3)))
	for i in 3:
		_part(3, _add(_tail[3], CM.spike(0.55, 0.07, 0.0, 0.3), _m_spike, Vector3(-0.4, 0.0, 0.0), Vector3.ONE, Vector3(0.0, 0.0, 1.57 + (i - 1) * 0.45)))
	for leg in [_leg_l, _leg_r]:
		_part(3, _add(leg, CM.spike(0.36, 0.055, 0.6, 1.0, BONE), _m_bone, Vector3(0.26, -0.52, 0.0), Vector3.ONE, Vector3(0.0, 0.0, -0.4)))


func _part(form: int, node: Node3D) -> void:
	_parts[form].append(node)


# ---------------------------------------------------------------- animacion

func _process(delta: float) -> void:
	_t += delta
	_flash = max(0.0, _flash - delta * 5.0)
	if anim == "run" or anim == "dash":
		_phase += delta * (6.0 + 9.0 * speed) * (1.6 if anim == "dash" else 1.0)
	var tg := _target_pose()
	var k := 1.0 - exp(-22.0 * delta)
	for key in tg:
		_p[key] = lerpf(float(_p[key]), float(tg[key]), k)
	_apply(delta)


func _target_pose() -> Dictionary:
	var d := DEF.duplicate()
	var breath := sin(_t * 2.6)
	match anim:
		"idle":
			d.by = breath * 0.025
			d.hrz = breath * 0.04
			d.ty = sin(_t * 1.8) * 0.25
			d.arm = breath * 0.1
		"run":
			var s := sin(_phase)
			d.ll = s * 0.9
			d.lr = -s * 0.9
			d.by = abs(cos(_phase)) * 0.07
			d.brz = -0.16
			d.hrz = 0.1
			d.ty = s * 0.3
			d.arm = s * 0.5
			d.tz = 0.25
		"air":
			var up: float = clamp(vy / 14.0, -1.0, 1.0)
			d.ll = 0.55
			d.lr = -0.35
			d.brz = up * 0.18
			d.tz = 0.1 - up * 0.4
			d.arm = -0.6
			d.jaw = 0.25 if up < 0.0 else 0.0
		"jab":
			var lunge := sin(clamp(anim_t / 0.5, 0.0, 1.0) * PI)
			d.hx = lunge * 0.4
			d.brz = -0.25 * lunge
			d.hrz = -0.1 * lunge
			d.jaw = 0.75 if anim_t < 0.25 else 0.0
			d.tz = 0.35
		"tail":
			d.brz = -0.2
			d.by = -0.08
			d.tz = -0.05
		"airatk":
			d.ll = 0.6
			d.lr = 0.6
			d.tz = -0.2
		"fire":
			if anim_t < 0.42:
				d.hrz = 0.45
				d.brz = 0.15
				d.jaw = 0.2
			else:
				d.hrz = -0.15
				d.brz = -0.2
				d.hx = 0.15
				d.jaw = 0.9
		"dash":
			var s2 := sin(_phase)
			d.ll = s2 * 1.0
			d.lr = -s2 * 1.0
			d.brz = -0.55
			d.hrz = 0.35
			d.tz = 0.5
			d.arm = -0.9
		"stomp":
			# Se para en dos patas y cae con todo el peso.
			if anim_t < 0.34:
				d.by = 0.35
				d.brz = 0.4
				d.hrz = 0.2
				d.arm = -1.2
				d.ll = -0.4
			else:
				d.by = -0.16
				d.brz = -0.3
				d.hrz = 0.2
				d.jaw = 0.5
				d.tz = 0.5
		"block":
			d.by = -0.14
			d.brz = 0.12
			d.hrz = -0.3
			d.arm = 1.2
			d.tz = 0.5
		"hurt":
			d.brz = 0.45
			d.hrz = 0.3
			d.jaw = 0.6
			d.arm = -1.0
			d.ty = 0.5
		"ko":
			d.lean = 1.45
			d.jaw = 0.5
			d.arm = -1.0
		"evolve":
			d.by = 0.25
			d.hrz = 0.5
			d.arm = -1.2
			d.jaw = 0.8
			d.tz = 0.6
	return d


func _apply(delta: float) -> void:
	var target_yaw := -0.35 if facing == 1 else PI + 0.35
	_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-18.0 * delta))
	var spin := 0.0
	if anim == "tail":
		spin = smoothstep(0.15, 0.75, anim_t) * TAU
	rotation.y = _yaw + spin

	# Proporciones y pintura: mezcla entre la forma base y la evolucion activa.
	var body_s := Vector3.ONE
	var head_s := Vector3.ONE
	var tail_s := Vector3.ONE
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
		tail_s = Vector3.ONE.lerp(look.tail_s, e)
		leg_s = lerpf(1.0, look.leg_s, e)
	scale = Vector3.ONE * size
	_body.scale = body_s
	_head.scale = head_s
	_tail[0].scale = tail_s
	_leg_l.scale.y = leg_s
	_leg_r.scale.y = leg_s

	_flipper.rotation.z = -anim_t * TAU if anim == "airatk" else 0.0
	_rig.position.y = -0.9 + 0.72 * (leg_s - 1.0)
	_rig.rotation.z = _p.lean
	_body.position.y = 0.95 + _p.by
	_body.rotation.z = _p.brz
	_head.position.x = 0.55 + _p.hx
	_head.rotation.z = _p.hrz
	_jaw.rotation.z = -_p.jaw
	_leg_l.rotation.z = _p.ll
	_leg_r.rotation.z = _p.lr
	_arm_l.rotation.z = _p.arm
	_arm_r.rotation.z = -_p.arm * 0.6
	for i in _tail.size():
		_tail[i].rotation.z = -_p.tz * 0.5
		_tail[i].rotation.y = _p.ty * 0.5 + sin(_t * 3.0 + i * 0.7) * 0.08
	var flap := sin(_t * 16.0) * 0.55 if anim == "air" or anim == "dash" else sin(_t * 2.2) * 0.08
	_wings[0].rotation.x = -(0.5 + flap)
	_wings[1].rotation.x = 0.5 + flap

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
	_m_wing.albedo_color = look.body.lerp(look.belly, 0.3)
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
		out["stripe"] = body.darkened(0.7)
	if not out.has("tip"):
		out["tip"] = body.lerp(spike, 0.5).darkened(0.2)
	if not out.has("stripes"):
		out["stripes"] = 0.6
	if not out.has("scales"):
		out["scales"] = 0.35
	return out


# Pata de dinosaurio: muslo grueso, rodilla adelantada, tobillo fino y pie largo con garras.
func _make_leg(z: float) -> Node3D:
	var leg := _pivot(_rig, Vector3(-0.05, 0.72, z))
	_add(leg, CM.loft([
		[0.02, 0.12, 0.17, 0.17, 0.13],
		[0.06, -0.1, 0.2, 0.2, 0.16],
		[0.15, -0.32, 0.12, 0.13, 0.11],
		[0.0, -0.5, 0.08, 0.08, 0.075],
		[0.02, -0.64, 0.09, 0.09, 0.09],
	], {"seg": 12, "u": Vector2(0.4, 0.55), "tip": Vector2(0.0, 0.75)}), _skin)
	_add(leg, CM.loft([
		[-0.1, -0.65, 0.06, 0.05, 0.09],
		[0.1, -0.63, 0.09, 0.05, 0.13],
		[0.3, -0.66, 0.06, 0.04, 0.14],
		[0.4, -0.675, 0.03, 0.03, 0.1],
	], {"seg": 12, "sub": 4, "u": Vector2(0.5, 0.55), "tip": Vector2(0.85, 1.0)}), _skin)
	for i in 3:
		_add(leg, CM.spike(0.17, 0.045, -0.4, 1.0, BONE), _m_bone, Vector3(0.37, -0.67, (i - 1) * 0.09), Vector3.ONE, Vector3(0.0, 0.0, -1.75))
	return leg


func _make_arm(z: float) -> Node3D:
	var arm := _pivot(_body, Vector3(0.38, -0.02, z))
	_add(arm, CM.loft([
		[0.0, 0.02, 0.09, 0.09, 0.08],
		[0.1, -0.15, 0.075, 0.075, 0.07],
		[0.24, -0.16, 0.06, 0.06, 0.06],
		[0.33, -0.2, 0.05, 0.05, 0.07],
	], {"seg": 10, "sub": 4, "u": Vector2(0.3, 0.4), "tip": Vector2(0.2, 1.0)}), _skin)
	for i in 3:
		_add(arm, CM.spike(0.11, 0.03, -0.3, 1.0, BONE), _m_bone, Vector3(0.35, -0.22, (i - 1) * 0.05), Vector3.ONE, Vector3(0.0, 0.0, -2.2))
	return arm


# Placa ovalada (armadura, maza de la cola).
func _lens(rx: float, ry: float, rz: float) -> ArrayMesh:
	return CM.loft([
		[-rx, 0.0, 0.0, 0.0, 0.0], [-rx * 0.6, 0.0, ry * 0.8, ry * 0.8, rz * 0.8], [0.0, 0.0, ry, ry, rz],
		[rx * 0.6, 0.0, ry * 0.8, ry * 0.8, rz * 0.8], [rx, 0.0, 0.0, 0.0, 0.0],
	], {"seg": 12, "sub": 3, "colors": [Color(0.4, 0.42, 0.5), Color(0.85, 0.88, 0.95)]})


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
func _vcolor_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.vertex_color_use_as_albedo = true
	_std.append(m)
	m.roughness = 0.45
	return m


func _flat_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.4
	_std.append(m)
	return m


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 20
	m.rings = 10
	return m
