extends Node3D
# Menus de GGmon. Pantallas:
#   inicio     titulo y "presiona Enter"
#   principal  1 jugador / 2 jugadores / Online / Pruebas
#   online     crear sala o unirse con un codigo
#   pick1/2    elegir luchador (uno por jugador humano en esta maquina)
#   sala       espera de la partida online (el estado lo escribe main con set_status)
# Se maneja con flechas o W/S + Enter, o con el mouse. Esc vuelve atras.
# Al terminar emite start(config) para partidas locales u online_request(...) para online.

signal start(config: Dictionary)
signal online_request(as_host: bool, species: String, code: String, url: String)
signal online_cancel

const Forms = preload("res://scripts/forms.gd")
const Net = preload("res://scripts/net.gd")

const SLOT_GAP := 4.3
const CYCLE := 1.7
const ORB_NAMES := {1: "Rojo", 2: "Azul", 3: "Verde"}
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const YELLOW := Color(1.0, 0.88, 0.3)

# Se pueden setear antes de add_child.
var index := 0              # especie en la que abre el selector
var first_screen := "inicio"

var screen := ""
var _mode := "cpu"          # cpu, 2p, test, host, join
var _p1 := ""
var _code := ""
var _url := ""
var _models := {}
var _ring: MeshInstance3D
var _light: OmniLight3D
var _root: Control
var _title: Label
var _subtitle: Label
var _box: VBoxContainer
var _pick: VBoxContainer
var _name: Label
var _desc: Label
var _evos: RichTextLabel
var _hint: Label
var _status: Label
var _code_edit: LineEdit
var _url_edit: LineEdit
var _cycle_t := 0.0
var _cycle_form := 0
var _t := 0.0


func _ready() -> void:
	for i in Forms.ORDER.size():
		var id: String = Forms.ORDER[i]
		var sp: Dictionary = Forms.SPECIES[id]
		var m: Node3D = load(sp.model).new()
		m.pal = sp.pal
		m.looks = sp.forms
		m.base_scale = sp.base.scale
		m.facing = 1 if i * 2 < Forms.ORDER.size() - 1 else -1
		m.position = Vector3(_slot_x(i), 0.05, 0.0)
		add_child(m)
		_models[id] = m

	_ring = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.5
	cyl.bottom_radius = 1.5
	cyl.height = 0.05
	_ring.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = YELLOW
	mat.emission_enabled = true
	mat.emission = YELLOW
	mat.emission_energy_multiplier = 1.5
	_ring.material_override = mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.95, 0.7)
	_light.light_energy = 3.0
	_light.omni_range = 7.0
	add_child(_light)

	_url = Net.default_url()
	_build_ui()
	_select(index, false)
	show_screen(first_screen)


func show_screen(id: String) -> void:
	screen = id
	for c in _box.get_children():
		c.queue_free()
	var picking := id.begins_with("pick")
	_box.visible = not picking
	_pick.visible = picking
	_ring.visible = picking
	_light.visible = picking
	_title.add_theme_font_size_override("font_size", 120 if id == "inicio" else 72)
	_models[Forms.ORDER[index]].set_form(0)
	_cycle_form = 0
	_cycle_t = 0.0
	var focus: Control = null
	match id:
		"inicio":
			_subtitle.text = "Criaturas que evolucionan y pelean"
			_hint.text = ""
			var go := _button("Presiona Enter para empezar", func(): show_screen("principal"))
			go.name = "Empezar"
			focus = go
		"principal":
			_subtitle.text = "Menu principal"
			_hint.text = "Flechas o W / S para elegir   |   Enter para confirmar   |   tambien con el mouse"
			focus = _button("1 jugador", func(): _choose_mode("cpu"), "Vos contra la CPU, a 3 vidas")
			_button("2 jugadores", func(): _choose_mode("2p"), "Los dos en este teclado: WASD y flechas")
			_button("Online", func(): show_screen("online"), "Crea una sala o unite a la de un amigo")
			_button("Pruebas", func(): _choose_mode("test"), "Sala libre con sparring, orbes y hitboxes")
		"online":
			_subtitle.text = "Online"
			_hint.text = "El que crea la sala le pasa el codigo al otro   |   Esc para volver"
			focus = _button("Crear sala", func(): _online(true), "Te da un codigo para compartir")
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 10)
			_box.add_child(row)
			_code_edit = _edit(row, "CODIGO", 150.0, 8)
			_code_edit.text_submitted.connect(func(_text): _online(false))
			var join := _make_button("Unirse a una sala", func(): _online(false))
			join.custom_minimum_size.x = 250.0
			row.add_child(join)
			if Net.default_url() == "":
				_small("Todavia no hay un servidor de salas publico configurado.")
			var srv := HBoxContainer.new()
			srv.alignment = BoxContainer.ALIGNMENT_CENTER
			_box.add_child(srv)
			var tag := Label.new()
			tag.text = "Servidor: "
			tag.add_theme_font_size_override("font_size", 15)
			srv.add_child(tag)
			_url_edit = _edit(srv, "ws://...", 330.0, 120)
			_url_edit.text = _url
			_url_edit.add_theme_font_size_override("font_size", 15)
			_button("Volver", func(): show_screen("principal"))
		"pick1":
			_subtitle.text = {"cpu": "Elegi tu luchador", "2p": "Jugador 1: elegi tu luchador", "test": "Pruebas: elegi tu luchador",
				"host": "Sala %s: elegi tu luchador" % _code, "join": "Sala %s: elegi tu luchador" % _code}[_mode]
			_hint.text = "A / D o flechas para cambiar   |   Enter para confirmar   |   Esc para volver"
		"pick2":
			_subtitle.text = "Jugador 2: elegi tu luchador"
			_hint.text = "A / D o flechas para cambiar   |   Enter para confirmar   |   Esc para volver"
		"sala":
			_subtitle.text = "Sala %s" % _code
			_hint.text = "Esc para cancelar"
			_status = Label.new()
			_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_status.add_theme_font_size_override("font_size", 26)
			_status.add_theme_color_override("font_outline_color", Color.BLACK)
			_status.add_theme_constant_override("outline_size", 8)
			_status.text = "Conectando..."
			_box.add_child(_status)
			focus = _button("Cancelar", func(): _back())
	if picking:
		var held := get_viewport().gui_get_focus_owner()
		if held != null:
			held.release_focus()
		_refresh_pick()
	elif focus != null:
		focus.grab_focus.call_deferred()


# Lo llama main mientras se arma la partida online.
func set_status(text: String, is_error: bool = false) -> void:
	if screen == "sala" and is_instance_valid(_status):
		_status.text = text
		_status.modulate = Color(1.0, 0.5, 0.45) if is_error else Color.WHITE


func _choose_mode(mode: String) -> void:
	_mode = mode
	show_screen("pick1")


func _online(as_host: bool) -> void:
	_url = _url_edit.text.strip_edges()
	if as_host:
		_code = ""
		for i in 4:
			_code += CODE_CHARS[randi() % CODE_CHARS.length()]
	else:
		_code = _code_edit.text.strip_edges().to_upper()
		if _code == "":
			_code_edit.placeholder_text = "ESCRIBI EL CODIGO"
			_code_edit.grab_focus()
			return
	_mode = "host" if as_host else "join"
	show_screen("pick1")


func _confirm_pick() -> void:
	_snd("evolve")
	var chosen: String = Forms.ORDER[index]
	if screen == "pick2":
		start.emit({"mode": "2p", "p1": _p1, "p2": chosen})
		return
	_p1 = chosen
	match _mode:
		"2p":
			show_screen("pick2")
		"cpu":
			start.emit({"mode": "cpu", "p1": _p1, "p2": Forms.ORDER[randi() % Forms.ORDER.size()]})
		"test":
			start.emit({"mode": "test", "p1": _p1, "p2": Forms.ORDER[(index + 1) % Forms.ORDER.size()]})
		_:
			show_screen("sala")
			online_request.emit(_mode == "host", _p1, _code, _url)


func _back() -> void:
	match screen:
		"principal":
			show_screen("inicio")
		"online":
			show_screen("principal")
		"pick1":
			show_screen("online" if _mode == "host" or _mode == "join" else "principal")
		"pick2":
			show_screen("pick1")
		"sala":
			online_cancel.emit()
			show_screen("online")


func _unhandled_key_input(event: InputEvent) -> void:
	# Solo llega aca lo que no uso un campo de texto, asi escribir el codigo no mueve el menu.
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var picking := screen.begins_with("pick")
	match key.physical_keycode:
		KEY_ESCAPE:
			_back()
		KEY_A, KEY_LEFT:
			if picking:
				_select(index - 1, true)
		KEY_D, KEY_RIGHT:
			if picking:
				_select(index + 1, true)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_J:
			if picking:
				_confirm_pick()
		KEY_W, KEY_S:
			# W / S mueven el foco igual que las flechas
			var held := get_viewport().gui_get_focus_owner()
			if held != null and not picking:
				var next := held.find_valid_focus_neighbor(SIDE_TOP if key.physical_keycode == KEY_W else SIDE_BOTTOM)
				if next != null:
					next.grab_focus()
		_:
			return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_t += delta
	_cycle_t += delta
	if screen.begins_with("pick") and _cycle_t >= CYCLE:
		_cycle_t = 0.0
		_cycle_form = (_cycle_form + 1) % 4
		_models[Forms.ORDER[index]].set_form(_cycle_form)
		_refresh_pick()
	_ring.rotation.y += delta
	_ring.scale = Vector3.ONE * (1.0 + sin(_cycle_t * 6.0) * 0.03)
	_title.modulate = Color(1.0, 0.95 + sin(_t * 2.0) * 0.05, 0.75 + sin(_t * 2.0) * 0.1)
	if screen == "inicio" and _box.get_child_count() > 0:
		_box.get_child(0).modulate.a = 0.65 + sin(_t * 4.0) * 0.35


func _select(i: int, with_sound: bool) -> void:
	var n := Forms.ORDER.size()
	_models[Forms.ORDER[index]].set_form(0)
	index = (i % n + n) % n
	_cycle_t = 0.0
	_cycle_form = 0
	_ring.position = Vector3(_slot_x(index), 0.03, 0.0)
	_light.position = Vector3(_slot_x(index), 3.5, 2.5)
	_refresh_pick()
	if with_sound:
		_snd("pickup")


func _refresh_pick() -> void:
	var sp: Dictionary = Forms.SPECIES[Forms.ORDER[index]]
	_name.text = "<  %s  >" % sp.name
	_desc.text = sp.desc
	var parts := []
	for f in [1, 2, 3]:
		var c: Color = Forms.ORB[f]
		var kit: Dictionary = sp.forms[f]
		var label := "%s: %s" % [ORB_NAMES[f], kit.name]
		if f == _cycle_form:
			label = "[u]%s[/u]" % label
		parts.append("[color=#%s]%s[/color]" % [c.lightened(0.25).to_html(false), label])
	# habilidades de la forma que se esta mostrando
	var shown: Dictionary = sp.forms[_cycle_form] if _cycle_form != 0 else sp.base
	var shown_name: String = shown.name if _cycle_form != 0 else "Forma base"
	_evos.text = "[center]%s\n[color=#dddddd]%s:  %s  +  %s[/color][/center]" % ["      ".join(parts), shown_name, shown.k_name, shown.l_name]


func _slot_x(i: int) -> float:
	return (i - (Forms.ORDER.size() - 1) * 0.5) * SLOT_GAP


func _snd(id: String) -> void:
	get_tree().call_group("sfx", "play", id)


# ---------------------------------------------------------------- interfaz

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_root)

	# franja oscura arriba y abajo para que el texto se lea sobre el escenario
	for top in [true, false]:
		var shade := ColorRect.new()
		shade.color = Color(0.02, 0.06, 0.04, 0.42)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		if top:
			shade.offset_bottom = 190.0
		else:
			shade.offset_top = -330.0
		_root.add_child(shade)

	var head := VBoxContainer.new()
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_top = 10.0
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(head)
	_title = _label(head, 72, "GGmon")
	_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	_title.add_theme_constant_override("shadow_offset_x", 5)
	_title.add_theme_constant_override("shadow_offset_y", 6)
	_title.add_theme_constant_override("outline_size", 14)
	_subtitle = _label(head, 26, "")
	_subtitle.add_theme_color_override("font_color", YELLOW)

	_box = VBoxContainer.new()
	_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_box.offset_top = -322.0
	_box.offset_bottom = -46.0
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", 8)
	_root.add_child(_box)

	_pick = VBoxContainer.new()
	_pick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_pick.offset_top = -250.0
	_pick.offset_bottom = -48.0
	_pick.add_theme_constant_override("separation", 4)
	_root.add_child(_pick)
	_name = _label(_pick, 44, "")
	_desc = _label(_pick, 22, "")
	_evos = RichTextLabel.new()
	_evos.bbcode_enabled = true
	_evos.fit_content = true
	_evos.scroll_active = false
	_evos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_evos.add_theme_font_size_override("normal_font_size", 23)
	_evos.add_theme_color_override("font_outline_color", Color.BLACK)
	_evos.add_theme_constant_override("outline_size", 6)
	_pick.add_child(_evos)
	# para el mouse: los mismos tres comandos que el teclado
	var arrows := HBoxContainer.new()
	arrows.alignment = BoxContainer.ALIGNMENT_CENTER
	arrows.add_theme_constant_override("separation", 12)
	_pick.add_child(arrows)
	for item in [["<", func(): _select(index - 1, true), 70.0], ["Elegir", func(): _confirm_pick(), 220.0], [">", func(): _select(index + 1, true), 70.0]]:
		var b := _make_button(item[0], item[1])
		b.custom_minimum_size = Vector2(item[2], 44.0)
		b.focus_mode = Control.FOCUS_NONE
		arrows.add_child(b)

	_hint = _label(_root, 16, "")
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -34.0
	_hint.offset_bottom = -8.0
	_hint.modulate = Color(1.0, 1.0, 1.0, 0.85)


# Boton del menu, centrado, con una linea de explicacion al costado.
func _button(text: String, action: Callable, note: String = "") -> Button:
	var b := _make_button(text if note == "" else "%s\n%s" % [text, note], action)
	b.custom_minimum_size = Vector2(470.0, 60.0 if note != "" else 46.0)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_box.add_child(b)
	return b


func _make_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_constant_override("line_spacing", -4)
	b.add_theme_color_override("font_focus_color", Color(0.12, 0.1, 0.02))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _style(Color(0.04, 0.1, 0.07, 0.78), Color(1.0, 1.0, 1.0, 0.25)))
	b.add_theme_stylebox_override("hover", _style(Color(0.1, 0.24, 0.16, 0.9), Color(1.0, 1.0, 1.0, 0.7)))
	b.add_theme_stylebox_override("pressed", _style(Color(0.85, 0.7, 0.15, 1.0), Color.WHITE))
	b.add_theme_stylebox_override("focus", _style(YELLOW, Color.WHITE))
	b.pressed.connect(func():
		_snd("pickup")
		action.call())
	return b


func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(6.0)
	return sb


func _edit(parent: Control, placeholder: String, width: float, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.custom_minimum_size = Vector2(width, 44.0)
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.add_theme_font_size_override("font_size", 22)
	parent.add_child(e)
	return e


func _small(text: String) -> void:
	var l := _label(_box, 15, text)
	l.modulate = Color(1.0, 0.75, 0.5)


func _label(parent: Control, size: int, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	parent.add_child(l)
	return l
