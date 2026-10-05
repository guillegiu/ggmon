extends Node3D
# GGmon: platform fighter 2.5D de criaturas que evolucionan.
# Arma el escenario y alterna entre el menu y la pelea. Modos (config.mode):
#   test          sala de pruebas: sparring configurable, orbes a pedido, vidas infinitas
#   cpu           jugador 1 contra la maquina, a 3 vidas
#   2p            dos jugadores en el mismo teclado, a 3 vidas
#   online_host   partida online: esta maquina simula y manda el estado al invitado
#   online_guest  partida online: esta maquina manda sus teclas y dibuja lo que recibe
# El menu y la sala de pruebas usan el escenario simple; las peleas, el complejo.
# Argumentos (despues de "--"):
#   --pick=dino|bug|frog            entra directo a pruebas con esa especie
#   --gallery=dino|bug|frog|fx      primeros planos para revisar el diseño
#   --selftest [--only=<especie>]   secuencia automatica con capturas (o solo las habilidades de una especie)
#   --net-test=host|guest           prueba automatica de la partida online (dos instancias)
#   --shots=<carpeta>               donde guardar las capturas

const Stage = preload("res://scripts/stage.gd")
const Fighter = preload("res://scripts/fighter.gd")
const Fireball = preload("res://scripts/fireball.gd")
const Hazard = preload("res://scripts/hazard.gd")
const Forms = preload("res://scripts/forms.gd")
const Hud = preload("res://scripts/hud.gd")
const Menu = preload("res://scripts/menu.gd")
const Net = preload("res://scripts/net.gd")
const Orb = preload("res://scripts/orb.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Vfx = preload("res://scripts/vfx.gd")

# Donde pueden aparecer los orbes: suelo y encima de cada plataforma.
const ORB_SPOTS := [
	Vector2(-12.0, 1.1), Vector2(-4.0, 1.1), Vector2(0.0, 1.1), Vector2(4.0, 1.1), Vector2(9.5, 1.1),
	Vector2(-8.0, 3.3), Vector2(8.0, 3.3), Vector2(0.0, 5.3), Vector2(-11.5, 6.9), Vector2(11.5, 6.9),
]
const ORB_INTERVAL := 420
const ORB_MAX := 2
const MENU_CAM := Vector3(0.0, 2.3, 9.0)
const STOCKS := 3
# El anfitrion manda el estado cada tantos frames de fisica (2 = 30 veces por segundo).
const SNAPSHOT_EVERY := 2

var cam: Camera3D
var sfx: Node
var net: Node
var stage: Node3D = null
var stage_complex := false
var menu: Node3D = null
# Todo lo de una pelea cuelga de game; liberarlo limpia luchadores, orbes y efectos.
var game: Node3D = null
var hud: CanvasLayer = null
var config := {}
var player: CharacterBody3D
var dummy: CharacterBody3D
var online := ""            # "", "host" o "guest"
var ai_mode := 0
var show_boxes := false
var auto_orbs := true
var winner := ""
var _orb_timer := 150
var _last_pick := ""
var _my_species := ""
var _net_nodes := {}        # invitado: id del anfitrion -> nodo local que lo dibuja
var _frame := 0
var _cam_fixed := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _shake := 0.0


func _ready() -> void:
	_setup_input()
	_rng.randomize()
	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	net = Net.new()
	net.name = "Net"
	add_child(net)
	net.room_created.connect(func(code): _lobby("Sala %s abierta.\nPasale el codigo a tu rival y espera a que entre." % code))
	net.paired.connect(_on_paired)
	net.peer_left.connect(_on_peer_left)
	net.failed.connect(_on_net_failed)
	net.message.connect(_on_net_message)
	_build_stage(false)

	cam = Camera3D.new()
	cam.fov = 50.0
	cam.position = MENU_CAM
	cam.rotation_degrees.x = -6.0
	add_child(cam)
	cam.current = true

	var pick := ""
	var gallery := ""
	var net_test := ""
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--shots="):
			_shots_dir = arg.trim_prefix("--shots=")
		elif arg.begins_with("--pick="):
			pick = arg.trim_prefix("--pick=")
		elif arg.begins_with("--gallery="):
			gallery = arg.trim_prefix("--gallery=")
		elif arg.begins_with("--net-test="):
			net_test = arg.trim_prefix("--net-test=")
	if Forms.SPECIES.has(gallery):
		_gallery(gallery)
	elif gallery == "fx":
		_gallery_fx()
	elif net_test != "":
		_net_test(net_test == "host")
	elif "--selftest" in args:
		_selftest()
	elif Forms.SPECIES.has(pick):
		start_game({"mode": "test", "p1": pick, "p2": Forms.ORDER[(Forms.ORDER.find(pick) + 1) % Forms.ORDER.size()]})
	else:
		show_menu("inicio")


# Arma el escenario si todavia no esta armada esa variante.
func _build_stage(complex: bool) -> void:
	if stage != null:
		if stage_complex == complex:
			return
		# fuera del arbol ya mismo, asi sus plataformas dejan de contar para los luchadores nuevos
		remove_child(stage)
		stage.queue_free()
	stage = Node3D.new()
	stage.name = "Stage"
	add_child(stage)
	stage_complex = complex
	Stage.build(stage, complex)


func show_menu(screen: String = "principal") -> void:
	_end_game()
	net.close()
	_build_stage(false)
	if menu == null:
		menu = Menu.new()
		menu.index = maxi(Forms.ORDER.find(_last_pick), 0)
		menu.first_screen = screen
		menu.start.connect(start_game)
		menu.online_request.connect(open_room)
		menu.online_cancel.connect(net.close)
		add_child(menu)


func _end_game() -> void:
	if game != null:
		game.queue_free()
		game = null
		hud.queue_free()
		hud = null
	online = ""
	winner = ""
	_net_nodes.clear()
	Vfx.recording = false
	Vfx.events.clear()


func start_game(cfg: Dictionary) -> void:
	if menu != null:
		menu.queue_free()
		menu = null
	_end_game()
	config = cfg
	_last_pick = cfg.p1
	_frame = 0
	var mode: String = cfg.mode
	online = {"online_host": "host", "online_guest": "guest"}.get(mode, "")
	game = Node3D.new()
	game.name = "Game"
	add_child(game)
	_build_stage(mode != "test")
	# en el escenario complejo arrancan cada uno en su isla, lejos del puente
	var start_x := 7.0 if stage_complex else 4.0
	var same: bool = cfg.p1 == cfg.p2
	player = _spawn(cfg.p1, Vector3(-start_x, 0.05, 0.0), 1, false)
	dummy = _spawn(cfg.p2, Vector3(start_x, 0.05, 0.0), -1, mode == "test" or same)
	var n1: String = Forms.SPECIES[cfg.p1].name
	var n2: String = Forms.SPECIES[cfg.p2].name
	player.display_name = "J1  " + n1
	dummy.display_name = "J2  " + n2
	match mode:
		"test":
			player.display_name = n1
			dummy.ctrl = "cpu"
			dummy.display_name = "Sparring " + n2
			ai_mode = 0
		"cpu":
			dummy.ctrl = "cpu"
			dummy.ai_mode = 2
			dummy.display_name = "CPU  " + n2
		"2p":
			dummy.pad = "p2"
		"online_host":
			dummy.ctrl = "remote"
			Vfx.recording = true
		"online_guest":
			player.puppet = true
			dummy.puppet = true
			for b in get_tree().get_nodes_in_group("breakables"):
				b.puppet = true
	if mode != "test":
		player.stocks = STOCKS
		dummy.stocks = STOCKS
	player.target = dummy
	dummy.target = player
	player.net_pos = player.spawn
	dummy.net_pos = dummy.spawn
	player.hit_landed.connect(_on_hit)
	dummy.hit_landed.connect(_on_hit)
	_orb_timer = 150
	hud = Hud.new()
	hud.mode = "online" if online != "" else mode
	hud.me = 1 if online == "guest" else 0
	add_child(hud)


func _physics_process(_delta: float) -> void:
	if game == null:
		return
	_frame += 1
	if Input.is_action_just_pressed("gg_back"):
		show_menu()
		return
	if online == "guest":
		_send_input()
		if winner != "" and Input.is_action_just_pressed("gg_confirm"):
			show_menu()
		return

	if config.mode == "test":
		_test_keys()
	elif winner == "":
		if player.out or dummy.out:
			winner = "GANA  " + (dummy.display_name if player.out else player.display_name)
			sfx.play("evolve")
	else:
		if Input.is_action_just_pressed("gg_confirm"):
			show_menu()
			return
		if Input.is_action_just_pressed("gg_reset") and (online == "" or net.is_paired):
			# revancha: el anfitrion le avisa al invitado que arranca de nuevo
			net.send({"k": "start", "p1": config.p1, "p2": config.p2})
			start_game(config)
			return

	if auto_orbs and winner == "":
		_orb_timer -= 1
		if _orb_timer <= 0:
			_orb_timer = ORB_INTERVAL
			if get_tree().get_nodes_in_group("orbs").size() < ORB_MAX:
				_spawn_random_orb()

	if online == "host" and _frame % SNAPSHOT_EVERY == 0:
		net.send(_snapshot())


# Teclas de la sala de pruebas.
func _test_keys() -> void:
	if Input.is_action_just_pressed("gg_fill"):
		player.gauge = 100.0
	if Input.is_action_just_pressed("gg_mode"):
		ai_mode = (ai_mode + 1) % 3
		dummy.ai_mode = ai_mode
	if Input.is_action_just_pressed("gg_boxes"):
		show_boxes = not show_boxes
	player.show_boxes = show_boxes
	dummy.show_boxes = show_boxes
	if Input.is_action_just_pressed("gg_reset"):
		player.reset()
		dummy.reset()
	for kind in [1, 2, 3]:
		if Input.is_action_just_pressed("gg_orb%d" % kind):
			var p := player.global_position
			spawn_orb(kind, Vector2(clampf(p.x + player.facing * 2.5, -14.0, 14.0), p.y + 1.1))


func _process(delta: float) -> void:
	var goal := MENU_CAM
	if _cam_fixed != Vector3.ZERO:
		goal = _cam_fixed
	elif game != null:
		# Encuadra a los dos y se aleja cuando se separan. Si uno quedo fuera, sigue al otro.
		var a := player.global_position
		var b := dummy.global_position
		if player.out:
			a = b
		elif dummy.out:
			b = a
		var mid := (a + b) * 0.5
		var dist: float = abs(a.x - b.x) + abs(a.y - b.y) * 1.3
		goal = Vector3(clampf(mid.x, -9.0, 9.0), clampf(mid.y + 2.6, 2.6, 9.0), clampf(9.0 + dist * 0.6, 11.5, 22.0))
		var banner := ""
		if winner != "":
			var can_rematch: bool = online == "" or (online == "host" and net.is_paired)
			banner = "%s\nEnter: menu%s" % [winner, "     R: revancha" if can_rematch else ""]
		hud.refresh(player, dummy, {"ai_mode": ai_mode, "boxes": show_boxes, "banner": banner})
	cam.position = cam.position.lerp(goal, 1.0 - exp(-4.0 * delta))
	_shake = max(0.0, _shake - delta * 2.5)
	cam.h_offset = randf_range(-1.0, 1.0) * _shake * 0.25
	cam.v_offset = randf_range(-1.0, 1.0) * _shake * 0.25


func spawn_orb(kind: int, at: Vector2) -> void:
	var orb := Orb.new()
	orb.kind = kind
	orb.position = Vector3(at.x, at.y, 0.0)
	game.add_child(orb)


# Elige un lugar libre: lejos de otros orbes y sin un luchador encima.
func _spawn_random_orb() -> void:
	var free_spots := []
	for spot in ORB_SPOTS:
		var ok := true
		for o in get_tree().get_nodes_in_group("orbs"):
			if Vector2(o.position.x, o.position.y).distance_to(spot) < 3.0:
				ok = false
		for f in [player, dummy]:
			if Vector2(f.global_position.x, f.global_position.y + 1.0).distance_to(spot) < 2.5:
				ok = false
		if ok:
			free_spots.append(spot)
	if free_spots.is_empty():
		return
	spawn_orb(_rng.randi_range(1, 3), free_spots[_rng.randi_range(0, free_spots.size() - 1)])


func _on_hit(dmg: float) -> void:
	_shake = min(_shake + dmg * 0.04, 0.8)


func _spawn(species: String, pos: Vector3, facing: int, alt_colors: bool) -> CharacterBody3D:
	var sp: Dictionary = Forms.SPECIES[species]
	var f := Fighter.new()
	f.name = "P1" if facing == 1 else "P2"
	f.species = species
	f.spawn = pos
	f.facing = facing
	f.pal = sp.pal_alt if alt_colors else sp.pal
	game.add_child(f)
	return f


# ---------------------------------------------------------------- online

# El menu pide abrir o entrar a una sala. La partida arranca sola cuando hay dos jugadores:
# el invitado manda "hello" con su especie y el anfitrion contesta "start".
func open_room(as_host: bool, species: String, code: String, url: String) -> void:
	_my_species = species
	_lobby("Conectando...")
	net.open(url, as_host, code)


func _lobby(text: String, is_error: bool = false) -> void:
	if menu != null:
		menu.set_status(text, is_error)


func _on_paired() -> void:
	if net.is_host:
		_lobby("Rival conectado. Empezando...")
	else:
		_lobby("Conectado. Empezando...")
		net.send({"k": "hello", "sp": _my_species})


func _on_net_failed(reason: String) -> void:
	if game != null and online != "":
		winner = "Se corto la conexion"
	else:
		_lobby(reason, true)


func _on_peer_left() -> void:
	if game != null and online != "":
		if not winner.begins_with("GANA"):
			winner = "El rival se desconecto"
	else:
		_lobby("El rival se fue de la sala. Esperando a otro...")


func _on_net_message(d: Dictionary) -> void:
	match d.get("k", ""):
		"hello":
			if net.is_host and Forms.SPECIES.has(d.get("sp", "")):
				net.send({"k": "start", "p1": _my_species, "p2": d.sp})
				start_game({"mode": "online_host", "p1": _my_species, "p2": d.sp})
		"start":
			if not net.is_host and Forms.SPECIES.has(d.get("p1", "")) and Forms.SPECIES.has(d.get("p2", "")):
				start_game({"mode": "online_guest", "p1": d.p1, "p2": d.p2})
		"i":
			if online == "host" and game != null:
				dummy.remote = d
				for a in d.get("p", []):
					if dummy.buf.has(a):
						dummy.buf[a] = Fighter.BUFFER
		"s":
			if online == "guest" and game != null:
				_apply_snapshot(d)


# Invitado: manda sus teclas en cada frame. Usa los controles del jugador 1 de su maquina.
func _send_input() -> void:
	var x := Input.get_axis("p1_left", "p1_right")
	var pressed := []
	for a in ["jump", "attack", "fire", "dash", "evolve"]:
		if Input.is_action_just_pressed("p1_" + a):
			pressed.append(a)
	net.send({"k": "i", "x": x if absf(x) >= 0.3 else 0.0, "d": Input.is_action_pressed("p1_down"),
		"jh": Input.is_action_pressed("p1_jump"), "b": Input.is_action_pressed("p1_block"),
		"fh": Input.is_action_pressed("p1_fire"), "dh": Input.is_action_pressed("p1_dash"), "p": pressed})


# Anfitrion: todo lo que el invitado necesita para dibujar este instante.
func _snapshot() -> Dictionary:
	var lists := {}
	for group in ["projectiles", "orbs", "hazards"]:
		var items := []
		for n in get_tree().get_nodes_in_group(group):
			if not n.is_queued_for_deletion():
				items.append(n.net_state())
		lists[group] = items
	var broken := []
	for b in get_tree().get_nodes_in_group("breakables"):
		broken.append(b.broken)
	var events := Vfx.events.duplicate()
	Vfx.events.clear()
	return {"k": "s", "f": [player.net_state(), dummy.net_state()], "l": lists, "b": broken, "w": winner, "e": events}


func _apply_snapshot(d: Dictionary) -> void:
	player.apply_net(d.f[0])
	dummy.apply_net(d.f[1])
	winner = d.w
	var lists: Dictionary = d.l
	var seen := {}
	for group in lists:
		for s in lists[group]:
			var id: int = s[0]
			seen[id] = true
			var node: Node3D = _net_nodes.get(id)
			if node == null:
				node = _make_puppet(group, s)
				_net_nodes[id] = node
				game.add_child(node)
			node.apply_net(s)
	for id in _net_nodes.keys():
		if not seen.has(id):
			_net_nodes[id].queue_free()
			_net_nodes.erase(id)
	var breakables := get_tree().get_nodes_in_group("breakables")
	for i in mini(breakables.size(), d.b.size()):
		breakables[i].net_set(d.b[i])
	for e in d.e:
		match e[0]:
			"sfx":
				sfx.play(e[1], e[2])
			"flash":
				var f: Node = game.get_node_or_null(str(e[1]))
				if f != null:
					f.model.hit_flash()
			_:
				Vfx.replay(game, e)


# Invitado: nodo que solo dibuja lo que el anfitrion esta simulando.
func _make_puppet(group: String, s: Array) -> Node3D:
	var node: Node3D
	match group:
		"projectiles":
			node = Fireball.new()
			node.style = s[1]
			node.position = s[2]
			node.dir = s[3]
			node.radius = s[4]
			node.color = s[5]
		"orbs":
			node = Orb.new()
			node.kind = s[1]
			node.position = s[2]
		_:
			node = Hazard.new()
			node.position = s[1]
			node.radius = s[2]
			node.color = s[3]
	node.puppet = true
	return node


# ---------------------------------------------------------------- entrada

# p1_* y p2_* son los controles de cada jugador; gg_* los de menu y los de la sala de pruebas.
func _setup_input() -> void:
	_action("p1_left", [KEY_A], 0, [JOY_BUTTON_DPAD_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_action("p1_right", [KEY_D], 0, [JOY_BUTTON_DPAD_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_action("p1_down", [KEY_S], 0, [JOY_BUTTON_DPAD_DOWN], JOY_AXIS_LEFT_Y, 1.0)
	_action("p1_jump", [KEY_W, KEY_SPACE], 0, [JOY_BUTTON_A])
	_action("p1_attack", [KEY_J], 0, [JOY_BUTTON_X])
	_action("p1_fire", [KEY_K], 0, [JOY_BUTTON_Y])
	_action("p1_dash", [KEY_L], 0, [JOY_BUTTON_B])
	_action("p1_block", [KEY_U], 0, [JOY_BUTTON_RIGHT_SHOULDER])
	_action("p1_evolve", [KEY_I], 0, [JOY_BUTTON_LEFT_SHOULDER])

	_action("p2_left", [KEY_LEFT], 1, [JOY_BUTTON_DPAD_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_action("p2_right", [KEY_RIGHT], 1, [JOY_BUTTON_DPAD_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_action("p2_down", [KEY_DOWN], 1, [JOY_BUTTON_DPAD_DOWN], JOY_AXIS_LEFT_Y, 1.0)
	_action("p2_jump", [KEY_UP], 1, [JOY_BUTTON_A])
	_action("p2_attack", [KEY_KP_1, KEY_COMMA], 1, [JOY_BUTTON_X])
	_action("p2_fire", [KEY_KP_2, KEY_PERIOD], 1, [JOY_BUTTON_Y])
	_action("p2_dash", [KEY_KP_3, KEY_MINUS, KEY_SLASH], 1, [JOY_BUTTON_B])
	_action("p2_block", [KEY_KP_4, KEY_M], 1, [JOY_BUTTON_RIGHT_SHOULDER])
	_action("p2_evolve", [KEY_KP_5, KEY_N], 1, [JOY_BUTTON_LEFT_SHOULDER])

	_action("gg_confirm", [KEY_ENTER, KEY_KP_ENTER], -1, [JOY_BUTTON_START])
	_action("gg_back", [KEY_ESCAPE], -1, [JOY_BUTTON_BACK])
	_action("gg_fill", [KEY_G])
	_action("gg_mode", [KEY_T])
	_action("gg_boxes", [KEY_H])
	_action("gg_reset", [KEY_R])
	_action("gg_orb1", [KEY_1])
	_action("gg_orb2", [KEY_2])
	_action("gg_orb3", [KEY_3])


# device: mando al que responde la accion (-1 = cualquiera).
func _action(action: String, keys: Array, device: int = -1, buttons: Array = [], axis: int = -1, axis_value: float = 0.0) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, 0.3)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		jb.device = device
		InputMap.action_add_event(action, jb)
	if axis >= 0:
		var jm := InputEventJoypadMotion.new()
		jm.axis = axis
		jm.axis_value = axis_value
		jm.device = device
		InputMap.action_add_event(action, jm)


# ---------------------------------------------------------------- visores y pruebas automaticas

var _shots_dir := "user://shots"

# Cada habilidad: [especie, forma, distancia al sparring, accion, frames mantenida, espera, nombre]
const ABILITY_TESTS := [
	["dino", 0, 5.0, "fire", 3, 70, "bola de fuego"], ["dino", 0, 3.5, "dash", 3, 70, "embestida"],
	["dino", 1, 3.0, "fire", 3, 80, "aliento"], ["dino", 1, 4.5, "dash", 3, 90, "picada"],
	["dino", 2, 5.5, "fire", 55, 90, "carga"], ["dino", 2, 5.0, "dash", 3, 90, "pisoton a distancia"],
	["dino", 3, 4.0, "dash", 3, 60, "salto de caza"],
	["bug", 0, 4.0, "fire", 3, 50, "escupitajo"], ["bug", 0, 2.5, "dash", 45, 70, "excavar"],
	["bug", 1, 6.0, "fire", 3, 100, "bomba"], ["bug", 1, 2.2, "dash", 3, 90, "cornada"],
	["bug", 2, 4.0, "fire", 3, 230, "nube de polvo"], ["bug", 2, 3.0, "dash", 3, 60, "rafaga"],
	["bug", 3, 4.5, "fire", 3, 100, "bumeran"], ["bug", 3, 3.0, "dash", 3, 60, "tajo relampago"],
	["frog", 0, 4.0, "fire", 3, 60, "lengua"], ["frog", 0, 5.0, "dash", 3, 100, "gran salto"],
	["frog", 1, 5.5, "fire", 3, 100, "bola saltarina"], ["frog", 1, 2.5, "dash", 3, 60, "rastro ardiente"],
	["frog", 2, 4.0, "fire", 3, 140, "burbuja"], ["frog", 2, 3.0, "dash", 3, 80, "caparazon"],
	["frog", 3, 5.0, "fire", 3, 280, "dardo venenoso"], ["frog", 3, 1.6, "dash", 3, 60, "croar"],
]


# Visor de modelos: saca un primer plano de cada forma (parado y mordiendo).
func _gallery(species: String) -> void:
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	var sp: Dictionary = Forms.SPECIES[species]
	var m: Node3D = load(sp.model).new()
	m.pal = sp.pal
	m.looks = sp.forms
	m.base_scale = sp.base.scale
	m.position = Vector3(0.0, 0.05, 0.0)
	add_child(m)
	_cam_fixed = Vector3(0.3, 1.5, 5.2)
	await _wait(40)
	for form in [0, 1, 2, 3]:
		if form != 0:
			m.set_form(form)
			await _wait(70)
		var s: float = sp.forms[form].scale if form != 0 else sp.base.scale
		_cam_fixed = Vector3(0.3, 1.2 * s + 0.3, 3.6 + 1.6 * s)
		await _wait(50)
		await _shot("%s_%d" % [species, form])
		m.anim = "jab"
		m.anim_t = 0.12
		await _wait(12)
		await _shot("%s_%d_ataque" % [species, form])
		m.anim = "idle"
	get_tree().quit()


# Visor de efectos: los tres orbes de cerca.
func _gallery_fx() -> void:
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	auto_orbs = false
	start_game({"mode": "test", "p1": "dino", "p2": "bug"})
	hud.visible = false
	player.global_position.x = -9.0
	dummy.global_position.x = 9.0
	await _wait(5)
	for kind in [1, 2, 3]:
		spawn_orb(kind, Vector2((kind - 2) * 2.2, 1.2))
	_cam_fixed = Vector3(0.0, 1.6, 6.0)
	await _wait(120)
	await _shot("fx_orbes")
	get_tree().quit()


# Prueba local: menus, cada habilidad contra el sparring, CPU, dos jugadores y mapa.
func _selftest() -> void:
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	auto_orbs = false
	show_menu("inicio")
	await _wait(50)
	await _shot("01_inicio")
	for id in ["principal", "online", "pick1", "sala"]:
		menu.show_screen(id)
		await _wait(40)
		await _shot("02_menu_" + id)

	# cada habilidad contra el sparring quieto
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	var last := ""
	for t in ABILITY_TESTS:
		if only != "" and t[0] != only:
			continue
		var key := "%s%d" % [t[0], t[1]]
		if key != last:
			last = key
			start_game({"mode": "test", "p1": t[0], "p2": "dino" if t[0] != "dino" else "bug"})
			await _wait(30)
			if t[1] != 0:
				spawn_orb(t[1], Vector2(player.global_position.x, 1.1))
				await _wait(110)
		else:
			await _tap("gg_reset")
			await _wait(20)
			# la evolucion se pierde al reiniciar: se vuelve a tomar el orbe
			if t[1] != 0:
				spawn_orb(t[1], Vector2(player.global_position.x, 1.1))
				await _wait(110)
		await _walk_to_gap(t[2])
		var hp0: float = dummy.hp
		var x0: float = dummy.global_position.x
		Input.action_press("p1_" + t[3])
		await _wait(t[4])
		Input.action_release("p1_" + t[3])
		await _wait(t[5])
		print("[selftest] %-5s %-14s %-20s daño %5.1f | movio al rival %5.1f" % [t[0], player.form_name(), t[6], hp0 - dummy.hp, dummy.global_position.x - x0])

	if only != "":
		get_tree().quit()
		return

	# golpe hacia abajo
	await _tap("gg_reset")
	await _wait(20)
	player.global_position = dummy.global_position + Vector3(0.0, 4.0, 0.0)
	player.velocity = Vector3.ZERO
	await _wait(2)
	var d1: float = dummy.hp
	Input.action_press("p1_down")
	await _tap("p1_attack")
	await _wait(36)
	Input.action_release("p1_down")
	print("[selftest] golpe hacia abajo: %.1f de daño, rebote a y=%.1f" % [d1 - dummy.hp, player.global_position.y])

	# contra la CPU: sin tocar nada, deberia atacar
	auto_orbs = true
	start_game({"mode": "cpu", "p1": "frog", "p2": "dino"})
	await _wait(420)
	await _shot("03_vs_cpu")
	print("[selftest] vs CPU 7 s: jugador hp=%.0f vidas=%d | mapa complejo=%s rompibles=%d" % [player.hp, player.stocks, stage_complex, get_tree().get_nodes_in_group("breakables").size()])
	auto_orbs = false

	# dos jugadores: teclas del jugador 2, puente, rio y fin de pelea
	start_game({"mode": "2p", "p1": "dino", "p2": "bug"})
	await _wait(40)
	var p2x: float = dummy.global_position.x
	Input.action_press("p2_left")
	await _wait(30)
	Input.action_release("p2_left")
	print("[selftest] J2 se movio %.1f con sus teclas" % (dummy.global_position.x - p2x))
	player.global_position = Vector3(-1.0, 0.1, 0.0)
	player.velocity = Vector3.ZERO
	await _wait(45)
	var rx: float = player.global_position.x
	await _wait(50)
	await _shot("04_rio")
	print("[selftest] puente cedio: y=%.1f | corriente: x de %.1f a %.1f" % [player.global_position.y, rx, player.global_position.x])
	dummy.stocks = 1
	dummy.take_hit(player, 500.0, Vector2(8.0, 8.0), 1, 0)
	await _wait(60)
	await _shot("05_ganador")
	print("[selftest] fin de pelea: \"%s\"" % winner)
	await _tap("gg_confirm")
	await _wait(20)
	print("[selftest] tras Enter: menu=%s juego=%s" % [menu != null, game != null])
	get_tree().quit()


# Prueba de la partida online. Hacen falta el servidor de salas corriendo y dos instancias:
# una con --net-test=host y otra con --net-test=guest. El invitado maneja con sus teclas
# al luchador de la derecha; al final cada lado imprime lo que ve, para comparar.
func _net_test(as_host: bool) -> void:
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	auto_orbs = false
	var side := "anfitrion" if as_host else "invitado"
	net.failed.connect(func(reason): print("[net %s] fallo: %s" % [side, reason]))
	open_room(as_host, "dino" if as_host else "frog", "TEST", Net.LOCAL_URL)
	var waited := 0
	while game == null and waited < 900:
		await _wait(1)
		waited += 1
	if game == null:
		print("[net %s] no arranco la partida" % side)
		get_tree().quit()
		return
	print("[net %s] partida: modo=%s J1=%s J2=%s" % [side, config.mode, config.p1, config.p2])
	await _wait(60)
	if as_host:
		# el anfitrion crea un orbe sobre el invitado y despues le pega con su bola de fuego
		spawn_orb(2, Vector2(dummy.global_position.x, 1.1))
		await _wait(200)
		for i in 3:
			await _tap("p1_fire")
			await _wait(50)
	else:
		# el invitado camina, salta y usa sus dos habilidades
		Input.action_press("p1_left")
		await _wait(40)
		Input.action_release("p1_left")
		await _tap("p1_jump")
		await _wait(60)
		await _tap("p1_fire")
		await _wait(60)
		await _tap("p1_dash")
		await _wait(120)
	await _wait(120 if as_host else 190)
	await _shot("net_" + side)
	print("[net %s] J1 x=%.1f hp=%.0f | J2 x=%.1f hp=%.0f forma=%s | proyectiles=%d orbes=%d" % [
		side, player.global_position.x, player.hp, dummy.global_position.x, dummy.hp, dummy.form_name(),
		get_tree().get_nodes_in_group("projectiles").size(), get_tree().get_nodes_in_group("orbs").size()])
	print("[net %s] sonidos: %s" % [side, sfx.played.keys()])
	await _wait(30)
	get_tree().quit()


func _walk_to_gap(gap: float) -> void:
	var frames := 0
	while frames < 300:
		var d: float = dummy.global_position.x - player.global_position.x
		var want := "p1_right" if d > 0.0 else "p1_left"
		# se acerca si esta lejos, se aleja si esta demasiado cerca
		if absf(d) < gap - 0.4:
			want = "p1_left" if d > 0.0 else "p1_right"
		elif absf(d) <= gap + 0.2:
			break
		Input.action_press(want)
		await _wait(1)
		Input.action_release(want)
		frames += 1
	await _wait(6)
	# queda mirando al sparring
	await _tap("p1_right" if dummy.global_position.x > player.global_position.x else "p1_left")
	await _wait(6)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _tap(action: String) -> void:
	Input.action_press(action)
	await _wait(3)
	Input.action_release(action)
	await _wait(1)


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shots_dir.path_join(shot_name + ".png"))
