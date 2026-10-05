extends CharacterBody3D
# Luchador 2.5D: se mueve solo en el plano XY (z fijo en 0).
# La logica corre a 60 Hz fijos y las duraciones estan en frames.

signal hit_landed(dmg: float)

const Fireball = preload("res://scripts/fireball.gd")
const Hazard = preload("res://scripts/hazard.gd")
const Forms = preload("res://scripts/forms.gd")
const Vfx = preload("res://scripts/vfx.gd")

enum St { FREE, ATTACK, BLOCK, HURT, KO, EVOLVE }

const LAYER_SOLID := 1
const LAYER_ONEWAY := 4
const GRAVITY := 38.0
const MAX_FALL := 30.0
const GLIDE_FALL := 3.0
const RUN_SPEED := 7.0
const JUMP_SPEED := 14.5
const DJUMP_SPEED := 13.0
const MAX_HP := 100.0
const EVO_TIME := 14.0
const EVO_FRAMES := 50
const BUFFER := 7
# Con armadura (triceratops, escarabajo), los golpes por debajo de este daño no interrumpen.
const ARMOR_FLINCH := 9.0
const CAMO_FRAMES := 260
const AMBUSH_MULT := 1.6

# Golpes y habilidades. Cada forma elige dos habilidades (teclas K y L) en forms.gd.
#   box: Rect2 relativo a los pies y mirando a la derecha (x hacia adelante).
#   shot: estilo de proyectil que suelta al terminar el startup (_shoot).
#   stream: suelta proyectiles de a uno durante todos los frames activos.
#   buff: efecto sobre uno mismo.            kind: logica propia (_mv_*).
#   speed: arrastra al luchador durante los frames activos.   lunge: empujon al empezar.
#   ground: solo sale apoyado en el suelo.   radial: empuja hacia afuera.
#   waves: suelta ondas por el suelo al impactar.   cd: frames antes de repetirlo.
const MOVES := {
	"jab1": {"startup": 5, "active": 4, "recovery": 10, "dmg": 6.0, "kb": Vector2(3.5, 3.0), "box": Rect2(0.2, 0.3, 1.7, 1.3), "stop": 4, "lunge": 4.0, "next": "jab2"},
	"jab2": {"startup": 5, "active": 4, "recovery": 11, "dmg": 7.0, "kb": Vector2(4.0, 3.5), "box": Rect2(0.2, 0.3, 1.8, 1.3), "stop": 4, "lunge": 4.0, "next": "tail"},
	"tail": {"startup": 8, "active": 7, "recovery": 16, "dmg": 12.0, "kb": Vector2(11.0, 9.5), "box": Rect2(-1.8, 0.1, 3.6, 1.3), "stop": 8, "radial": true},
	"air": {"startup": 5, "active": 9, "recovery": 10, "dmg": 9.0, "kb": Vector2(6.0, 7.0), "box": Rect2(-0.8, -0.4, 2.4, 1.9), "stop": 5},
	# abajo + golpe en el aire: cae en picada y rebota si pega
	"slam": {"startup": 4, "active": 40, "recovery": 9, "dmg": 9.0, "kb": Vector2(5.0, 9.0), "box": Rect2(-0.7, -0.8, 1.4, 1.4), "stop": 6, "radial": true, "kind": "slam"},
	# disparos
	"fire": {"startup": 12, "active": 0, "recovery": 16, "dmg": 8.0, "shot": "fire", "cd": 20},
	"breath": {"startup": 8, "active": 27, "recovery": 12, "dmg": 1.7, "shot": "flame", "stream": true, "cd": 50},
	"spit": {"startup": 5, "active": 0, "recovery": 8, "dmg": 5.0, "shot": "acid", "cd": 4},
	"bomb": {"startup": 10, "active": 0, "recovery": 14, "dmg": 10.0, "shot": "bomb", "cd": 30},
	"sleep": {"startup": 9, "active": 0, "recovery": 12, "dmg": 4.0, "shot": "cloud", "cd": 150},
	"boomerang": {"startup": 7, "active": 0, "recovery": 10, "dmg": 6.0, "shot": "blade", "cd": 50},
	"gust": {"startup": 6, "active": 0, "recovery": 12, "dmg": 3.0, "shot": "gust", "cd": 40},
	"camo": {"startup": 6, "active": 0, "recovery": 8, "dmg": 0.0, "buff": "camo", "cd": 360},
	"bounce": {"startup": 10, "active": 0, "recovery": 14, "dmg": 9.0, "shot": "bounce", "cd": 28},
	"bubble": {"startup": 10, "active": 0, "recovery": 14, "dmg": 4.0, "shot": "bubble", "cd": 80},
	"dart": {"startup": 5, "active": 0, "recovery": 9, "dmg": 3.0, "shot": "dart", "cd": 24},
	# cuerpo a cuerpo
	"dash": {"startup": 5, "active": 14, "recovery": 12, "dmg": 10.0, "kb": Vector2(9.0, 7.5), "box": Rect2(0.0, 0.2, 1.6, 1.4), "stop": 6, "speed": 17.0, "cd": 40},
	"pounce": {"startup": 3, "active": 12, "recovery": 6, "dmg": 8.0, "kb": Vector2(5.0, 6.5), "box": Rect2(-0.4, 0.1, 2.2, 1.4), "stop": 3, "speed": 26.0, "cd": 14},
	"horn": {"startup": 7, "active": 10, "recovery": 16, "dmg": 12.0, "kb": Vector2(5.0, 16.0), "box": Rect2(0.2, 0.2, 1.9, 1.7), "stop": 8, "speed": 14.0, "cd": 45},
	"stomp": {"startup": 14, "active": 6, "recovery": 22, "dmg": 13.0, "kb": Vector2(6.0, 15.0), "box": Rect2(-2.4, -0.2, 4.8, 1.3), "stop": 9, "radial": true, "ground": true, "waves": true, "cd": 60},
	# lengua: alcance largo y empuje negativo, o sea que trae al rival
	"tongue": {"startup": 8, "active": 5, "recovery": 16, "dmg": 6.0, "kb": Vector2(-11.0, 4.0), "box": Rect2(0.4, 0.6, 4.6, 0.9), "stop": 5, "cd": 45},
	"leap": {"startup": 12, "active": 60, "recovery": 12, "dmg": 12.0, "kb": Vector2(7.0, 11.0), "box": Rect2(-1.6, -0.3, 3.2, 1.6), "stop": 8, "radial": true, "kind": "dive", "up": 17.0, "fwd": 8.0, "plunge": Vector2(9.0, 22.0), "fx": Color(0.6, 0.9, 0.5), "cd": 55},
	# trail: deja fuego en el suelo por donde pasa.   safe: no lo pueden golpear mientras dura.
	"trail": {"startup": 4, "active": 18, "recovery": 10, "dmg": 7.0, "kb": Vector2(6.0, 6.0), "box": Rect2(0.0, 0.2, 1.5, 1.3), "stop": 4, "speed": 15.0, "trail": true, "ground": true, "cd": 85},
	"shell": {"startup": 6, "active": 34, "recovery": 12, "dmg": 9.0, "kb": Vector2(8.0, 8.0), "box": Rect2(-0.9, 0.0, 1.8, 1.3), "stop": 5, "speed": 13.0, "safe": true, "radial": true, "ground": true, "cd": 80},
	"croak": {"startup": 8, "active": 4, "recovery": 16, "dmg": 5.0, "kb": Vector2(14.0, 7.0), "box": Rect2(-2.7, -0.3, 5.4, 2.7), "stop": 4, "radial": true, "ring": true, "cd": 70},
	"blink": {"startup": 5, "active": 5, "recovery": 10, "dmg": 11.0, "kb": Vector2(7.0, 7.0), "box": Rect2(-3.6, 0.1, 4.2, 1.9), "stop": 6, "radial": true, "kind": "blink", "cd": 55},
	"dive": {"startup": 10, "active": 45, "recovery": 16, "dmg": 13.0, "kb": Vector2(7.0, 10.0), "box": Rect2(-1.7, -0.3, 3.4, 1.7), "stop": 8, "radial": true, "kind": "dive", "cd": 60},
	"charge": {"startup": 0, "active": 0, "recovery": 14, "dmg": 8.0, "kb": Vector2(10.0, 8.0), "box": Rect2(0.1, 0.1, 1.9, 1.6), "stop": 8, "kind": "charge", "cd": 50},
	"burrow": {"startup": 8, "active": 5, "recovery": 14, "dmg": 9.0, "kb": Vector2(3.0, 13.0), "box": Rect2(-1.1, -0.2, 2.2, 1.9), "stop": 6, "radial": true, "ground": true, "kind": "burrow", "cd": 70},
}
const ANIM_OF := {
	"jab1": "jab", "jab2": "jab", "tail": "tail", "air": "airatk", "slam": "stomp",
	"fire": "fire", "breath": "fire", "spit": "fire", "bomb": "fire", "sleep": "fire", "boomerang": "fire", "gust": "fire",
	"camo": "block", "dash": "dash", "pounce": "dash", "horn": "dash", "stomp": "stomp", "blink": "slash",
	"dive": "dash", "charge": "dash", "burrow": "airatk",
	"tongue": "tongue", "leap": "dash", "bounce": "fire", "bubble": "fire", "dart": "fire",
	"trail": "dash", "shell": "tail", "croak": "croak",
}

# Configuracion (se setea antes de add_child).
var display_name := "GGmon"
var species := "dino"
var ctrl := "player"        # "player" teclado/mando de pad, "remote" jugador online, otra cosa CPU
# Partida online, del lado del invitado: no simula nada, solo muestra lo que manda el anfitrion.
var puppet := false
var net_pos := Vector3.ZERO
# Partida online, del lado del anfitrion: ultimas teclas mantenidas que mando el invitado.
var remote := {}
var pad := "p1"
var ai_mode := 0            # 0 quieto, 1 bloquea, 2 pelea
var spawn := Vector3.ZERO
var pal := {}
var target: Node3D = null
var show_boxes := false
var stocks := -1            # vidas; -1 = infinitas (modo pruebas)

var state := St.FREE
var facing := 1
var hp := MAX_HP
var gauge := 0.0
# form: 0 base, 1 rojo, 2 azul, 3 verde. Vale desde que empieza la transformacion.
var form := 0
var last_form := 1
var evolved := false
var evo_left := 0.0
var kos := 0
var out := false            # se quedo sin vidas

var move := ""
var move_slot := ""         # "k" o "l" si el movimiento salio de una habilidad
var move_frame := 0
var move_phase := 0
var hold_frames := 0
var power := 0.0            # carga acumulada (0..1) de las habilidades que se mantienen
var hit_active := false
var hit_list: Array = []
var hitstop := 0
var hitstun := 0
var invuln := 0
var ko_timer := 0
var jumps_left := 1
var coyote := 0
var drop_timer := 0
var fire_cd := 0
var dash_cd := 0
var camo := 0               # frames de camuflaje que quedan
var ambush := 0             # frames en los que el proximo golpe pega mas (salio del camuflaje)
var slow := 0
var poison := 0             # frames de veneno que quedan: saca vida de a poco
var burrowed := false

var in_x := 0.0
var in_down := false
var in_jump_held := false
var in_block := false
var in_fire_held := false
var in_dash_held := false
var buf := {"jump": 0, "attack": 0, "fire": 0, "dash": 0, "evolve": 0}

var model: Node3D
var _ai_timer := 40
var _ai_hold_k := 0
var _ai_hold_l := 0
var _rng := RandomNumberGenerator.new()
var _excepted := {}
var _was_grounded := true
var _dbg_hit: MeshInstance3D
var _dbg_hurt: MeshInstance3D


func _ready() -> void:
	add_to_group("fighters")
	collision_layer = 2
	collision_mask = LAYER_SOLID | LAYER_ONEWAY
	axis_lock_linear_z = true
	floor_snap_length = 0.15
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.42
	sh.height = 1.5
	cs.shape = sh
	cs.position.y = 0.75
	add_child(cs)

	var sp: Dictionary = Forms.SPECIES[species]
	model = load(sp.model).new()
	model.pal = sp.pal if pal.is_empty() else pal
	model.looks = sp.forms
	model.base_scale = sp.base.scale
	model.facing = facing
	add_child(model)

	_dbg_hit = _make_debug_box(Color(1.0, 0.15, 0.15, 0.4))
	_dbg_hurt = _make_debug_box(Color(0.2, 1.0, 0.3, 0.22))
	_rng.seed = hash(display_name + pad)
	global_position = spawn


func _physics_process(delta: float) -> void:
	if puppet:
		global_position = global_position.lerp(net_pos, 0.45)
		return
	if ctrl == "player":
		_read_player()
	elif ctrl == "remote":
		_read_remote()
	else:
		_read_ai()
	for k in buf.keys():
		if buf[k] > 0:
			buf[k] -= 1
	if hitstop > 0:
		hitstop -= 1
		_sync_model()
		return

	_update_oneway()
	for t in ["fire_cd", "dash_cd", "invuln", "camo", "ambush", "slow"]:
		if get(t) > 0:
			set(t, get(t) - 1)
	if poison > 0:
		poison -= 1
		if poison % 30 == 0:
			chip(2.0, 0)
	if evolved and state != St.EVOLVE:
		evo_left -= delta
		gauge = 100.0 * max(evo_left, 0.0) / EVO_TIME
		if evo_left <= 0.0:
			_revert()

	var gravity_on := true
	hit_active = false
	match state:
		St.FREE:
			_free(delta)
		St.ATTACK:
			gravity_on = _attack(delta)
		St.BLOCK:
			velocity.x = move_toward(velocity.x, 0.0, 60.0 * delta)
			if not in_block or not is_on_floor():
				state = St.FREE
		St.HURT:
			velocity.x = move_toward(velocity.x, 0.0, (30.0 if is_on_floor() else 4.0) * delta)
			hitstun -= 1
			if hitstun <= 0:
				state = St.FREE
		St.KO:
			velocity.x = move_toward(velocity.x, 0.0, (25.0 if is_on_floor() else 2.0) * delta)
			ko_timer -= 1
			if ko_timer <= 0 and not out:
				respawn()
		St.EVOLVE:
			gravity_on = false
			velocity = Vector3.ZERO
			move_frame += 1
			if move_frame >= EVO_FRAMES:
				evolved = true
				evo_left = EVO_TIME
				state = St.FREE

	if gravity_on:
		velocity.y = max(velocity.y - GRAVITY * delta, -MAX_FALL)
	velocity.z = 0.0
	# El agua que corre arrastra: se suma solo al desplazamiento de este frame.
	var flow := _water_flow()
	velocity.x += flow
	move_and_slide()
	velocity.x -= flow
	global_position.z = 0.0
	var grounded := is_on_floor()
	if grounded and not _was_grounded and state == St.FREE:
		_snd("land")
	_was_grounded = grounded
	if global_position.y < -10.0 or abs(global_position.x) > 28.0:
		_lose_stock()
		_snd("ko")
		if out:
			# sin vidas: queda fuera de escena
			state = St.KO
			global_position = Vector3(spawn.x, -40.0, 0.0)
			velocity = Vector3.ZERO
			set_physics_process(false)
			model.visible = false
			return
		respawn()
	_sync_model()


# ---------------------------------------------------------------- entrada

func _read_player() -> void:
	in_x = Input.get_axis(pad + "_left", pad + "_right")
	if abs(in_x) < 0.3:
		in_x = 0.0
	in_down = Input.is_action_pressed(pad + "_down")
	in_jump_held = Input.is_action_pressed(pad + "_jump")
	in_block = Input.is_action_pressed(pad + "_block")
	in_fire_held = Input.is_action_pressed(pad + "_fire")
	in_dash_held = Input.is_action_pressed(pad + "_dash")
	for a in buf.keys():
		if Input.is_action_just_pressed(pad + "_" + a):
			buf[a] = BUFFER


# Jugador online: las teclas mantenidas llegan por red; las pulsaciones ya vienen cargadas en buf.
func _read_remote() -> void:
	in_x = remote.get("x", 0.0)
	in_down = remote.get("d", false)
	in_jump_held = remote.get("jh", false)
	in_block = remote.get("b", false)
	in_fire_held = remote.get("fh", false)
	in_dash_held = remote.get("dh", false)


# Lo que el invitado necesita para dibujar a este luchador.
func net_state() -> Array:
	return [global_position, facing, model.anim, model.anim_t, model.speed, model.vy, form, evolved, hp, gauge,
		stocks, out, fire_cd, dash_cd, model.ghost, model.visible, model.shield_on]


func apply_net(s: Array) -> void:
	net_pos = s[0]
	if global_position.distance_to(net_pos) > 5.0:
		global_position = net_pos      # reaparicion o teletransporte: sin deslizar
	facing = s[1]
	model.anim = s[2]
	model.anim_t = s[3]
	model.speed = s[4]
	model.vy = s[5]
	model.facing = facing
	if form != s[6]:
		form = s[6]
		model.set_form(form)
	evolved = s[7]
	hp = s[8]
	gauge = s[9]
	stocks = s[10]
	out = s[11]
	fire_cd = s[12]
	dash_cd = s[13]
	model.ghost = s[14]
	model.visible = s[15]
	model.shield_on = s[16]


func _read_ai() -> void:
	in_x = 0.0
	in_down = false
	in_jump_held = true
	in_block = false
	in_fire_held = _ai_hold_k > 0
	in_dash_held = _ai_hold_l > 0
	_ai_hold_k = max(_ai_hold_k - 1, 0)
	_ai_hold_l = max(_ai_hold_l - 1, 0)
	if ai_mode == 0 or target == null or state == St.KO:
		return
	var to_target: Vector3 = target.global_position - global_position
	if ai_mode == 1:
		if state == St.FREE or state == St.BLOCK:
			facing = 1 if to_target.x >= 0.0 else -1
		in_block = true
		return
	if target.state == St.KO:
		return
	_ai_timer -= 1
	if gauge >= 100.0 and not evolved:
		buf.evolve = BUFFER

	# Bajo tierra o cargando: solo corrige el rumbo hacia el rival.
	if burrowed or (state == St.ATTACK and move == "charge"):
		in_x = sign(to_target.x)
		return

	# Si no esta evolucionado y hay un orbe cerca, va por el.
	if not evolved:
		var best := 9.0
		var orb_at := Vector3.ZERO
		for o in get_tree().get_nodes_in_group("orbs"):
			var d: float = (o.global_position - global_position).length()
			# los que estan muy arriba no los alcanza saltando desde aca
			if d < best and o.global_position.y - global_position.y < 3.4:
				best = d
				orb_at = o.global_position
		if best < 9.0:
			var dxo := orb_at.x - global_position.x
			var dyo := orb_at.y - 1.0 - global_position.y
			if abs(dxo) > 0.3:
				in_x = sign(dxo)
			_ai_jump_towards(dyo)
			return

	# Rival camuflado: no sabe donde esta.
	if target.camo > 0:
		return

	var adx: float = abs(to_target.x)
	var ady: float = abs(to_target.y)
	if adx > 1.6:
		in_x = sign(to_target.x)
	if _ai_timer <= 0 and state == St.FREE:
		var roll := _rng.randf()
		facing = 1 if to_target.x >= 0.0 else -1
		if adx <= 1.8 and ady < 1.5:
			if roll < 0.75:
				buf.attack = BUFFER
				_ai_timer = 14
			else:
				buf.dash = BUFFER
				_ai_hold_l = 30
				_ai_timer = 50
		elif adx < 6.5 and ady < 1.3 and dash_cd <= 0 and roll < 0.45:
			buf.dash = BUFFER
			_ai_hold_l = 25 + _rng.randi_range(0, 25)
			_ai_timer = 45 + _rng.randi_range(0, 30)
		elif ady < 1.6 and fire_cd <= 0:
			buf.fire = BUFFER
			_ai_hold_k = 15 + _rng.randi_range(0, 35)
			_ai_timer = 45 + _rng.randi_range(0, 40)
		else:
			_ai_timer = 20
	elif state == St.ATTACK and move.begins_with("jab") and _ai_timer <= 0:
		buf.attack = BUFFER
		_ai_timer = 14
	_ai_jump_towards(to_target.y)
	# Si quedo justo arriba del rival, cae con el golpe hacia abajo.
	if not is_on_floor() and state == St.FREE and adx < 0.9 and to_target.y < -1.5 and velocity.y < 2.0:
		in_down = true
		buf.attack = BUFFER
	# No se tira al vacio.
	if abs(global_position.x) > 14.2 and sign(in_x) == sign(global_position.x):
		in_x = -in_x


func _ai_jump_towards(dy: float) -> void:
	if dy > 1.4 and is_on_floor() and _ai_timer % 18 == 0:
		buf.jump = BUFFER
	elif dy > 1.0 and not is_on_floor() and velocity.y < 0.0 and jumps_left > 0 and _ai_timer % 8 == 0:
		buf.jump = BUFFER
	elif dy < -1.5 and is_on_floor() and _ai_timer % 30 == 0:
		in_down = true


# ---------------------------------------------------------------- estados

func _free(delta: float) -> void:
	var grounded := is_on_floor()
	if grounded:
		jumps_left = _stat("air_jumps")
		coyote = 6
	elif coyote > 0:
		coyote -= 1
	var sp: float = RUN_SPEED * _stat("speed") * (0.55 if slow > 0 else 1.0)
	velocity.x = move_toward(velocity.x, in_x * sp, (70.0 if grounded else 38.0) * delta)
	if in_x != 0.0:
		facing = 1 if in_x > 0.0 else -1
	if grounded and in_down:
		drop_timer = 12
	if buf.jump > 0:
		if coyote > 0:
			velocity.y = JUMP_SPEED * _stat("jump")
			coyote = 0
			buf.jump = 0
			_snd("jump")
		elif jumps_left > 0:
			velocity.y = DJUMP_SPEED * _stat("jump")
			jumps_left -= 1
			buf.jump = 0
			_snd("flap" if _stat("glide") else "djump")
			Vfx.ring(get_parent(), global_position, Color(1.0, 1.0, 1.0, 0.6), 0.6, 0.25, true)
	# Salto variable: soltar el boton corta el ascenso.
	if not in_jump_held and velocity.y > 7.0:
		velocity.y = 7.0
	# Planeo (dragon, mariposa): mantener salto frena la caida.
	if in_jump_held and not grounded and _stat("glide") and velocity.y < -GLIDE_FALL:
		velocity.y = -GLIDE_FALL

	if buf.evolve > 0 and gauge >= 100.0 and not evolved:
		buf.evolve = 0
		start_evolve(last_form)
	elif buf.attack > 0:
		buf.attack = 0
		if grounded:
			_start_move("jab1", "")
		else:
			_start_move("slam" if in_down else "air", "")
	elif buf.fire > 0 and fire_cd <= 0 and _can_start(_stat("k"), grounded):
		buf.fire = 0
		_start_move(_stat("k"), "k")
	elif buf.dash > 0 and dash_cd <= 0 and _can_start(_stat("l"), grounded):
		buf.dash = 0
		_start_move(_stat("l"), "l")
	elif in_block and grounded:
		state = St.BLOCK


func _can_start(id: String, grounded: bool) -> bool:
	return grounded or not MOVES[id].has("ground")


func _start_move(id: String, slot: String) -> void:
	state = St.ATTACK
	move = id
	move_slot = slot
	move_frame = 0
	move_phase = 0
	hold_frames = 0
	power = 0.0
	hit_list.clear()
	# Atacar rompe el camuflaje, pero el primer golpe pega mas.
	if camo > 0 and id != "camo":
		camo = 0
		ambush = 45
	var m: Dictionary = MOVES[id]
	if m.has("speed") or m.get("kind", "") == "dive":
		_snd("dash")
	elif m.has("box") and not m.has("kind"):
		_snd("swing")


func _end_move() -> void:
	var cd: int = MOVES[move].get("cd", 0)
	if move_slot == "k":
		fire_cd = cd
	elif move_slot == "l":
		dash_cd = cd
	burrowed = false
	state = St.FREE


# Devuelve si la gravedad aplica este frame.
func _attack(delta: float) -> bool:
	var m: Dictionary = MOVES[move]
	move_frame += 1
	match m.get("kind", ""):
		"dive":
			return _mv_dive(m)
		"slam":
			return _mv_slam(m)
		"charge":
			return _mv_charge(m, delta)
		"burrow":
			return _mv_burrow(m, delta)
	var su: int = m.startup
	var ac: int = m.active
	var rc: int = m.recovery
	var grounded := is_on_floor()
	var gravity_on := true
	if m.has("speed"):
		if move_frame <= su:
			velocity.x = move_toward(velocity.x, 0.0, 60.0 * delta)
		elif move_frame <= su + ac:
			velocity.x = facing * float(m.speed)
			velocity.y = 0.0
			gravity_on = false
		else:
			velocity.x = move_toward(velocity.x, 0.0, 90.0 * delta)
	elif move == "air":
		velocity.x = move_toward(velocity.x, in_x * RUN_SPEED, 30.0 * delta)
		if grounded and move_frame > 2:
			_end_move()
			return true
	else:
		if move_frame == 1 and grounded and m.has("lunge"):
			velocity.x = facing * float(m.lunge)
		velocity.x = move_toward(velocity.x, 0.0, (40.0 if grounded else 8.0) * delta)

	var in_active := move_frame > su and move_frame <= su + ac
	if m.has("shot"):
		if m.has("stream"):
			if in_active and (move_frame - su) % 3 == 1:
				_shoot(m)
		elif move_frame == su:
			_shoot(m)
	if m.has("buff") and move_frame == su:
		camo = CAMO_FRAMES
		_snd("revert", 1.4)
		Vfx.ring(get_parent(), global_position + Vector3(0.0, 0.8, 0.0), Color(0.5, 1.0, 0.6, 0.8), 1.4, 0.4)
	if m.get("kind", "") == "blink" and move_frame == su:
		_blink()
	if m.has("waves") and move_frame == su + 1:
		_stomp_impact(m)
	if m.has("safe") and in_active:
		invuln = max(invuln, 2)
	if m.has("trail") and in_active and (move_frame - su) % 4 == 1:
		var fire := Hazard.new()
		fire.radius = 0.75
		fire.life = 2.6
		fire.tick_dmg = 2.0 * dmg_mult()
		fire.tick_frames = 20
		fire.slow_frames = 0
		fire.color = Color(1.0, 0.45, 0.05)
		fire.owner_fighter = self
		fire.position = global_position + Vector3(0.0, 0.5, 0.0)
		get_parent().add_child(fire)
	if m.has("ring") and move_frame == su + 1:
		_snd("stomp", 1.6)
		var at := global_position + Vector3(0.0, 0.9 * form_scale(), 0.5)
		for i in 3:
			Vfx.ring(get_parent(), at, Color(0.6, 1.0, 0.5, 0.8), 1.6 + i * 1.0, 0.25 + i * 0.1)
	hit_active = m.has("box") and in_active
	if hit_active:
		_check_hits(m)
	if move_frame > su + ac and m.has("next") and buf.attack > 0:
		buf.attack = 0
		_start_move(m.next, "")
	elif move_frame >= su + ac + rc:
		_end_move()
	return gravity_on


# Golpe hacia abajo (todos): frena un instante en el aire y cae derecho. Si pega, rebota.
func _mv_slam(m: Dictionary) -> bool:
	var su: int = m.startup
	if move_phase == 0:
		velocity.x = move_toward(velocity.x, 0.0, 1.5)
		velocity.y = 1.5
		if move_frame >= su:
			move_phase = 1
			_snd("swing", 0.7)
		return false
	if move_phase == 1:
		velocity.x = in_x * 3.0
		velocity.y = -27.0
		hit_active = true
		_check_hits(m)
		if not hit_list.is_empty():
			velocity.y = 11.0
			jumps_left = max(jumps_left, 1)
			_end_move()
		elif is_on_floor():
			move_phase = 2
			move_frame = 0
			velocity.x = 0.0
			_snd("land", 0.8)
			Vfx.ring(get_parent(), global_position + Vector3(0.0, 0.1, 0.0), Color(1.0, 1.0, 1.0, 0.6), 1.0, 0.25, true)
		elif move_frame > su + int(m.active):
			_end_move()
		return false
	if move_frame >= int(m.recovery):
		_end_move()
	return true


# Picada (dragon): toma altura y cae en diagonal; explota al tocar el suelo.
func _mv_dive(m: Dictionary) -> bool:
	var su: int = m.startup
	if move_phase == 0:
		if move_frame == 1:
			velocity.y = m.get("up", 13.0)
			velocity.x = facing * float(m.get("fwd", 4.0))
		if move_frame > su:
			move_phase = 1
		return true
	if move_phase == 1:
		var plunge: Vector2 = m.get("plunge", Vector2(15.0, 24.0))
		velocity.x = facing * plunge.x
		velocity.y = -plunge.y
		if is_on_floor():
			move_phase = 2
			move_frame = 0
			velocity = Vector3.ZERO
			hit_active = true
			_check_hits(m)
			var at := global_position + Vector3(0.0, 0.3, 0.5)
			Vfx.explosion(get_parent(), at, m.get("fx", Color(1.0, 0.4, 0.1)), 2.2)
			_snd("explode")
			hit_landed.emit(12.0)
		elif move_frame > su + int(m.active):
			_end_move()
		return false
	velocity.x = move_toward(velocity.x, 0.0, 1.0)
	if move_frame >= int(m.recovery):
		_end_move()
	return true


# Carga (triceratops): mantener junta fuerza, soltar embiste. Mas carga = mas lejos y mas daño.
func _mv_charge(m: Dictionary, delta: float) -> bool:
	if move_phase == 0:
		hold_frames += 1
		velocity.x = move_toward(velocity.x, 0.0, 60.0 * delta)
		if in_x != 0.0:
			facing = 1 if in_x > 0.0 else -1
		power = clampf((hold_frames - 8) / 52.0, 0.0, 1.0)
		if hold_frames % 8 == 0:
			Vfx.spark(get_parent(), global_position + Vector3(-facing * 0.6, 0.15, 0.5), Color(0.6, 0.85, 1.0, 0.7), 0.5 + power)
		if (hold_frames >= 8 and not _held()) or hold_frames >= 60:
			move_phase = 1
			move_frame = 0
			_snd("dash", 0.8)
		return true
	if move_phase == 1:
		velocity.x = facing * (13.0 + 9.0 * power)
		hit_active = true
		_check_hits(m)
		if move_frame % 4 == 0:
			Vfx.spark(get_parent(), global_position + Vector3(-facing * 0.8, 0.2, 0.4), Color(0.8, 0.9, 1.0, 0.6), 0.7)
		if move_frame >= 10 + int(16.0 * power):
			move_phase = 2
			move_frame = 0
		return true
	velocity.x = move_toward(velocity.x, 0.0, 70.0 * delta)
	if move_frame >= int(m.recovery):
		_end_move()
	return true


# Excavar (hormiga): se mete bajo tierra, avanza sin que la puedan golpear y sale pegando hacia arriba.
func _mv_burrow(m: Dictionary, delta: float) -> bool:
	var su: int = m.startup
	if move_phase == 0:
		velocity.x = move_toward(velocity.x, 0.0, 60.0 * delta)
		if move_frame >= su:
			move_phase = 1
			burrowed = true
			_snd("land", 0.7)
			Vfx.burst(get_parent(), global_position + Vector3(0.0, 0.1, 0.4), Color(0.5, 0.35, 0.2), 14, 4.0, 0.3)
		return true
	if move_phase == 1:
		hold_frames += 1
		velocity.x = in_x * 9.0
		if hold_frames % 4 == 0:
			Vfx.burst(get_parent(), global_position + Vector3(0.0, 0.05, 0.4), Color(0.55, 0.4, 0.22), 5, 2.5, 0.28)
		if (hold_frames >= 12 and not _held()) or hold_frames >= 75 or not is_on_floor():
			move_phase = 2
			move_frame = 0
			burrowed = false
			velocity.x = 0.0
			velocity.y = 8.0
			_snd("heavy", 1.3)
			Vfx.burst(get_parent(), global_position + Vector3(0.0, 0.2, 0.4), Color(0.5, 0.35, 0.2), 22, 6.0, 0.35)
		return true
	hit_active = move_frame <= int(m.active)
	if hit_active:
		_check_hits(m)
	if move_frame >= int(m.active) + int(m.recovery):
		_end_move()
	return true


# Tajo relampago (mantis): aparece adelante y corta todo lo que quedo en el camino.
func _blink() -> void:
	var dist := 4.2
	var from := global_position + Vector3(0.0, 0.8, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(facing * (dist + 0.6), 0.0, 0.0), LAYER_SOLID)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		dist = max(abs(hit.position.x - from.x) - 0.6, 0.0)
	Vfx.spark(get_parent(), from, Color(0.7, 1.0, 0.4, 0.8), 1.6)
	global_position.x += facing * dist
	invuln = max(invuln, 8)
	Vfx.ring(get_parent(), global_position + Vector3(0.0, 0.8, 0.0), Color(0.8, 1.0, 0.4, 0.9), 1.6, 0.25)
	_snd("dash", 1.5)


func _stomp_impact(m: Dictionary) -> void:
	_snd("stomp")
	hit_landed.emit(14.0)
	var s := form_scale()
	for side in [-1, 1]:
		Vfx.ring(get_parent(), global_position + Vector3(side * 0.8 * s, 0.1, 0.0), Color(0.7, 0.9, 1.0, 0.8), 2.0, 0.35, true)
		var wave := _projectile(global_position + Vector3(side * 1.2 * s, 0.45, 0.0), float(m.dmg) * 0.5 * dmg_mult(), Color(0.75, 0.6, 0.4), "wave")
		wave.dir = side
		wave.speed = 11.0
		wave.life = 0.6
		wave.radius = 0.5
		wave.kb = Vector2(4.0, 12.0)


func _held() -> bool:
	return in_fire_held if move_slot == "k" else in_dash_held


func _check_hits(m: Dictionary) -> void:
	var box := world_box(m.box)
	for f in get_tree().get_nodes_in_group("fighters"):
		if f == self or hit_list.has(f):
			continue
		if not box.intersects(f.hurt_box()):
			continue
		hit_list.append(f)
		var dir := facing
		if m.has("radial"):
			dir = 1 if f.global_position.x >= global_position.x else -1
		# la carga suma daño y empuje segun cuanto se mantuvo
		var dmg: float = (float(m.dmg) + 14.0 * power) * dmg_mult()
		var kb: Vector2 = m.kb * (1.0 + 0.6 * power)
		if f.take_hit(self, dmg, kb, dir, m.stop):
			hitstop = m.stop
			ambush = 0
			add_gauge(dmg * 1.6)
			hit_landed.emit(dmg)


# Estilos de disparo.
func _shoot(m: Dictionary) -> void:
	var s := form_scale()
	var origin := global_position + Vector3(facing * 1.3 * s, 1.25 * s, 0.0)
	var dmg: float = m.dmg * dmg_mult()
	match m.shot:
		"fire":
			_projectile(origin, dmg, Color(1.0, 0.5, 0.1), "fire")
			_snd("fire")
		"flame":
			# Aliento: bocanadas cortas que crecen, atraviesan y pegan varias veces.
			var puff := _projectile(origin, dmg, Color(1.0, 0.45, 0.08, 0.5), "flame")
			puff.speed = 12.0
			puff.vel_y = _rng.randf_range(-1.8, 1.8)
			puff.life = 0.34
			puff.radius = 0.3
			puff.grow = 1.6
			puff.pierce = true
			puff.kb = Vector2(1.6, 1.2)
			puff.stop = 1
			if (move_frame - int(m.startup)) % 9 == 1:
				_snd("fire", 1.3)
		"acid":
			var sp := _projectile(origin, dmg, Color(0.6, 1.0, 0.2), "acid")
			sp.radius = 0.2
			sp.speed = 24.0
			sp.life = 0.7
			_snd("spit")
		"bomb":
			# Bomba de magma en parabola que explota al caer.
			var bomb := _projectile(origin, dmg, Color(1.0, 0.35, 0.05), "bomb")
			bomb.radius = 0.4
			bomb.speed = 8.0
			bomb.vel_y = 7.0
			bomb.gravity = 26.0
			bomb.life = 2.5
			bomb.aoe = 2.4
			_snd("fire", 0.7)
		"cloud":
			# Polvo de alas: avanza despacio y deja una nube que daña y enlentece.
			var dust := _projectile(origin, dmg, Color(0.45, 0.8, 1.0), "dust")
			dust.radius = 0.4
			dust.speed = 7.0
			dust.vel_y = 0.0 if is_on_floor() else -5.0
			dust.life = 0.45
			dust.cloud = 1.8
			# atraviesa y casi no empuja, asi el rival queda dentro de la nube
			dust.pierce = true
			dust.kb = Vector2(0.5, 0.0)
			dust.stop = 1
			_snd("ice", 0.7)
		"blade":
			# Cuchilla que va, vuelve y corta a la ida y a la vuelta.
			var blade := _projectile(origin, dmg, Color(0.75, 1.0, 0.3), "blade")
			blade.radius = 0.38
			blade.speed = 17.0
			blade.life = 1.1
			blade.pierce = true
			blade.boomerang = true
			blade.kb = Vector2(3.0, 3.0)
			_snd("spit", 0.7)
		"bounce":
			# Bola de fuego que rebota por el suelo.
			var ball := _projectile(origin, dmg, Color(1.0, 0.5, 0.1), "fire")
			ball.radius = 0.36
			ball.speed = 11.0
			ball.vel_y = 3.0
			ball.gravity = 24.0
			ball.bounces = 3
			ball.life = 2.6
			_snd("fire", 1.2)
		"bubble":
			# Burbuja lenta: al que toca lo levanta y lo deja un rato sin poder hacer nada.
			var bubble := _projectile(origin, dmg, Color(0.6, 0.9, 1.0), "bubble")
			bubble.radius = 0.5
			bubble.speed = 6.0
			bubble.life = 2.4
			bubble.kb = Vector2(0.5, 9.0)
			bubble.stun = 45
			_snd("ice", 0.6)
		"dart":
			# Dardo rapido: poco daño al pegar, pero envenena varios segundos.
			var dart := _projectile(origin, dmg, Color(0.75, 0.3, 1.0), "dart")
			dart.radius = 0.18
			dart.speed = 26.0
			dart.life = 0.8
			dart.kb = Vector2(2.0, 2.0)
			dart.stop = 2
			dart.poison = 240
			_snd("spit", 1.3)
		"gust":
			# Rafaga: casi no daña pero empuja lejos.
			var gust := _projectile(origin - Vector3(0.0, 0.3 * s, 0.0), dmg, Color(0.8, 1.0, 1.0), "gust")
			gust.radius = 0.85
			gust.speed = 16.0
			gust.life = 0.5
			gust.pierce = true
			gust.kb = Vector2(17.0, 6.0)
			gust.stop = 2
			_snd("flap", 0.8)


func _projectile(origin: Vector3, dmg: float, color: Color, style: String) -> Node3D:
	var fb := Fireball.new()
	fb.style = style
	fb.dir = facing
	fb.shooter = self
	fb.dmg = dmg
	fb.color = color
	# Se agrega al arbol diferido para poder ajustar radio y velocidad antes de su _ready.
	get_parent().add_child.call_deferred(fb)
	fb.position = origin
	return fb


# ---------------------------------------------------------------- evolucion

func collect_orb(kind: int) -> bool:
	if state == St.KO or state == St.EVOLVE or burrowed:
		return false
	start_evolve(kind)
	return true


func start_evolve(kind: int) -> void:
	form = kind
	last_form = kind
	state = St.EVOLVE
	move_frame = 0
	hit_active = false
	camo = 0
	model.set_form(kind)
	_snd("evolve")
	var c: Color = Forms.ORB[kind]
	var at := global_position + Vector3(0.0, 0.9, 0.0)
	Vfx.explosion(get_parent(), at, c, 2.0)
	Vfx.ring(get_parent(), global_position + Vector3(0.0, 0.1, 0.0), c, 2.4, 0.5, true)


func _revert() -> void:
	evolved = false
	form = 0
	gauge = 0.0
	model.set_form(0)
	_snd("revert")


# ---------------------------------------------------------------- golpes recibidos

func take_hit(_attacker: Node, dmg: float, kb: Vector2, dir: int, stop: int) -> bool:
	if state == St.KO or state == St.EVOLVE or invuln > 0 or burrowed:
		return false
	camo = 0
	var center := global_position + Vector3(0.0, 0.9 * form_scale(), 0.6)
	if state == St.BLOCK:
		dmg *= 0.2
		hp = max(hp - dmg, 1.0)
		velocity.x = dir * 3.0
		hitstop = stop
		add_gauge(dmg)
		_snd("block")
		Vfx.ring(get_parent(), center, Color(0.4, 0.9, 1.0, 0.9), 1.0, 0.2)
		Vfx.number(get_parent(), center + Vector3(0.0, 0.8, 0.0), dmg, Color(0.6, 0.9, 1.0))
		return true
	dmg *= _stat("armor")
	hp -= dmg
	add_gauge(dmg * 0.6)
	hitstop = stop
	model.hit_flash()
	Vfx.note(["flash", name])
	_snd("heavy" if dmg >= 10.0 else "hit")
	Vfx.spark(get_parent(), center, Color(1.0, 0.9, 0.4, 0.9), 0.5 + dmg * 0.05)
	if dmg >= 5.0:
		Vfx.burst(get_parent(), center, Color(1.0, 0.8, 0.3), int(4 + dmg), 4.0 + dmg * 0.3, 0.22)
	Vfx.number(get_parent(), center + Vector3(0.0, 0.8, 0.0), dmg, Color(1.0, 0.95, 0.4))
	if hp <= 0.0:
		_knock_out(dir, kb)
		return true
	# Super armadura: el golpe duele pero no corta lo que estaba haciendo.
	if _stat("armor") < 1.0 and dmg < ARMOR_FLINCH:
		return true
	velocity.x = dir * kb.x
	velocity.y = kb.y
	hitstun = int(10.0 + dmg * 1.4)
	state = St.HURT
	return true


# Extras que pueden traer los proyectiles.
func add_stun(frames: int) -> void:
	if state == St.HURT:
		hitstun += frames


func add_poison(frames: int) -> void:
	if state != St.KO:
		poison = max(poison, frames)


# Daño que no interrumpe (nubes, fuego, veneno): saca vida y puede enlentecer.
func chip(dmg: float, slow_frames: int) -> void:
	if state == St.KO or state == St.EVOLVE or invuln > 0 or burrowed:
		return
	camo = 0
	hp -= dmg
	slow = max(slow, slow_frames)
	var center := global_position + Vector3(0.0, 0.9 * form_scale(), 0.6)
	Vfx.number(get_parent(), center + Vector3(0.0, 0.8, 0.0), dmg, Color(0.6, 0.9, 1.0))
	if hp <= 0.0:
		_knock_out(0, Vector2(0.0, 6.0))


func _knock_out(dir: int, kb: Vector2) -> void:
	hp = 0.0
	state = St.KO
	ko_timer = 130
	burrowed = false
	velocity.x = dir * kb.x * 1.6
	velocity.y = kb.y * 1.4 + 4.0
	_lose_stock()
	_snd("ko")


func _lose_stock() -> void:
	kos += 1
	if stocks > 0:
		stocks -= 1
		out = stocks == 0


func respawn() -> void:
	hp = MAX_HP
	state = St.FREE
	velocity = Vector3.ZERO
	global_position = spawn + Vector3(0.0, 3.0, 0.0)
	invuln = 90
	hitstop = 0
	camo = 0
	slow = 0
	poison = 0
	burrowed = false


func reset() -> void:
	respawn()
	invuln = 0
	kos = 0
	fire_cd = 0
	dash_cd = 0
	if form != 0:
		_revert()
	gauge = 0.0
	global_position = spawn


func add_gauge(v: float) -> void:
	if not evolved:
		gauge = min(gauge + v, 100.0)


func dmg_mult() -> float:
	return _stat("dmg") * (AMBUSH_MULT if ambush > 0 else 1.0)


func form_scale() -> float:
	return _stat("scale")


func form_name() -> String:
	return _stat("name")


# Para el HUD: nombre de la habilidad y cuanto falta para poder usarla (0 lista, 1 recien usada).
func ability_name(slot: String) -> String:
	return _stat(slot + "_name")


func ability_wait(slot: String) -> float:
	var cd: int = MOVES[_stat(slot)].get("cd", 0)
	var left := fire_cd if slot == "k" else dash_cd
	return clampf(float(left) / max(cd, 1), 0.0, 1.0)


# Estadistica de la evolucion activa, o la de la forma base de la especie.
func _stat(key: String) -> Variant:
	var sp: Dictionary = Forms.SPECIES[species]
	return sp.forms[form][key] if evolved and form != 0 else sp.base[key]


func hurt_box() -> Rect2:
	var s := form_scale()
	return Rect2(global_position.x - 0.5 * s, global_position.y, 1.0 * s, 1.6 * s)


func world_box(r: Rect2) -> Rect2:
	var s := form_scale()
	var x0 := r.position.x if facing == 1 else -(r.position.x + r.size.x)
	return Rect2(global_position.x + x0 * s, global_position.y + r.position.y * s, r.size.x * s, r.size.y * s)


# ---------------------------------------------------------------- auxiliares

# Velocidad con la que arrastra la corriente donde esta parado (0 si no hay agua).
func _water_flow() -> float:
	var here := Vector2(global_position.x, global_position.y + 0.3)
	for c in get_tree().get_nodes_in_group("currents"):
		var rect: Rect2 = c.get_meta("rect")
		if rect.has_point(here):
			if Engine.get_physics_frames() % 6 == 0:
				Vfx.burst(get_parent(), global_position + Vector3(0.0, 0.8, 0.5), Color(0.8, 0.95, 1.0), 3, 2.0, 0.25)
			return c.get_meta("flow")
	return 0.0


func _snd(id: String, pitch: float = 1.0) -> void:
	get_tree().call_group("sfx", "play", id, pitch)


# Plataformas atravesables: se ignoran mientras los pies esten por debajo de su tope
# o mientras dure la orden de bajar.
func _update_oneway() -> void:
	if drop_timer > 0:
		drop_timer -= 1
	for p in get_tree().get_nodes_in_group("oneway"):
		var top: float = p.get_meta("top")
		var skip := drop_timer > 0 or global_position.y < top - 0.05
		if skip != _excepted.get(p, false):
			_excepted[p] = skip
			if skip:
				add_collision_exception_with(p)
			else:
				remove_collision_exception_with(p)


func _sync_model() -> void:
	var a := "idle"
	var t := 0.0
	match state:
		St.FREE:
			if not is_on_floor():
				a = "air"
			elif abs(velocity.x) > 0.6:
				a = "run"
		St.ATTACK:
			var m: Dictionary = MOVES[move]
			a = ANIM_OF[move]
			t = float(move_frame) / float(max(m.startup + m.active + m.recovery, 1))
			match move:
				"breath":
					t = 0.7 if move_frame > m.startup else 0.2
				"charge":
					# junta fuerza echado hacia atras y despues embiste
					a = "stomp" if move_phase == 0 else "dash"
					t = 0.1
				"dive":
					a = "air" if move_phase == 0 else "dash"
				"burrow":
					t = float(move_frame) / float(m.active + m.recovery) if move_phase == 2 else 0.0
		St.BLOCK:
			a = "block"
		St.HURT:
			a = "hurt"
		St.KO:
			a = "ko"
		St.EVOLVE:
			a = "evolve"
			t = float(move_frame) / EVO_FRAMES
	model.anim = a
	model.anim_t = t
	model.speed = abs(velocity.x) / RUN_SPEED
	model.vy = velocity.y
	model.facing = facing
	model.shield_on = state == St.BLOCK
	model.ghost = 0.16 if camo > 0 else 1.0
	model.visible = not burrowed and (invuln <= 0 or (invuln / 4) % 2 == 0)

	_dbg_hurt.visible = show_boxes
	if show_boxes:
		_place_debug(_dbg_hurt, hurt_box())
	_dbg_hit.visible = show_boxes and hit_active and MOVES[move].has("box")
	if _dbg_hit.visible:
		_place_debug(_dbg_hit, world_box(MOVES[move].box))


func _make_debug_box(c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.albedo_color = c
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.visible = false
	add_child(mi)
	return mi


func _place_debug(mi: MeshInstance3D, r: Rect2) -> void:
	var c := r.get_center()
	mi.global_position = Vector3(c.x, c.y, 0.0)
	mi.scale = Vector3(r.size.x, r.size.y, 0.9)
