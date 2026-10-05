extends CanvasLayer
# HUD de pelea: vida, medidor de evolucion y vidas arriba; abajo, los controles
# dibujados como teclas, con el nombre de las dos habilidades de la forma actual
# (se atenuan mientras recargan).

const Forms = preload("res://scripts/forms.gd")

const AI_MODES := ["quieto", "bloquea", "pelea"]
const P1_KEYS := {"move": ["A", "D"], "jump": ["W"], "down": ["S"], "block": ["U"], "evolve": ["I"], "attack": ["J"], "k": ["K"], "l": ["L"], "slam": ["S", "J"]}
const P2_KEYS := {"move": ["Izq", "Der"], "jump": ["Arr"], "down": ["Aba"], "block": ["4"], "evolve": ["5"], "attack": ["1"], "k": ["2"], "l": ["3"], "slam": ["Aba", "1"]}
const ROW_A := [["move", "Mover"], ["jump", "Saltar"], ["down", "Bajar"], ["block", "Bloquear"], ["evolve", "Evolucionar"]]
const ROW_B := [["attack", "Golpe x3"], ["k", ""], ["l", ""]]
const ROW_C := [["slam", "en el aire: golpe hacia abajo"]]
const TEST_KEYS := [[["1", "2", "3"], "Crear orbe"], [["G"], "Llenar medidor"], [["T"], "Sparring"], [["H"], "Hitboxes"], [["R"], "Reiniciar"], [["Esc"], "Menu"]]

# Se setean antes de add_child.
var mode := "test"      # "test", "cpu", "2p" u "online"
var me := 0             # online: que luchador maneja esta maquina (0 izquierda, 1 derecha)

var _bars := []         # por luchador: {name, hp, evo, stocks}
var _abilities := []    # por jugador humano: {k: [chip, label], l: [chip, label]}
var _banner: Label
var _sparring: Label


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var left := VBoxContainer.new()
	left.position = Vector2(24.0, 14.0)
	left.custom_minimum_size.x = 420.0
	root.add_child(left)
	_bars.append(_make_bars(left, Color(0.3, 0.85, 0.3), false))
	var right := VBoxContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -444.0
	right.offset_right = -24.0
	right.offset_top = 14.0
	root.add_child(right)
	_bars.append(_make_bars(right, Color(0.9, 0.4, 0.9), true))

	_banner = Label.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 64)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 14)
	root.add_child(_banner)

	# Controles del jugador 1, abajo a la izquierda.
	var mine: String = {"test": "CONTROLES", "online": "VOS: JUGADOR %d  (el de la %s)" % [me + 1, "izquierda" if me == 0 else "derecha"]}.get(mode, "JUGADOR 1")
	var p1 := _panel(root, Control.PRESET_BOTTOM_LEFT, mine)
	_abilities.append(_player_rows(p1, P1_KEYS))
	var p2 := _panel(root, Control.PRESET_BOTTOM_RIGHT, {"test": "PRUEBAS", "cpu": "CPU", "online": "ONLINE", "2p": "JUGADOR 2  (teclado numerico, o  ,  .  -  M  N)"}[mode])
	if mode == "2p":
		_abilities.append(_player_rows(p2, P2_KEYS))
	elif mode == "test":
		var row_a := _row(p2)
		var row_b := _row(p2)
		for i in TEST_KEYS.size():
			var chip := _chip(row_a if i < 3 else row_b, TEST_KEYS[i][0], TEST_KEYS[i][1])
			if TEST_KEYS[i][1] == "Sparring":
				_sparring = chip[1]
	else:
		_chip(_row(p2), ["Esc"], "Menu")


func refresh(p1: Node, p2: Node, info: Dictionary) -> void:
	var fighters := [p1, p2]
	for i in 2:
		var f: Node = fighters[i]
		var b: Dictionary = _bars[i]
		var tag: String = " > " + f.form_name() if f.evolved else ""
		b.name.text = f.display_name + tag
		b.hp.value = f.hp
		b.evo.value = f.gauge
		for s in b.stocks.size():
			b.stocks[s].visible = f.stocks < 0 or s < f.stocks
		b.stock_row.visible = f.stocks >= 0
	for i in _abilities.size():
		# online: el unico panel de controles es el del luchador que maneja esta maquina
		var f: Node = fighters[me if mode == "online" else i]
		var tint: Color = Forms.ORB[f.form] if f.evolved else Color(1.0, 1.0, 1.0)
		for slot in ["k", "l"]:
			var chip: Array = _abilities[i][slot]
			chip[1].text = f.ability_name(slot)
			chip[1].modulate = tint.lightened(0.45)
			chip[0].modulate.a = lerpf(1.0, 0.3, f.ability_wait(slot))
	if _sparring != null:
		_sparring.text = "Sparring: %s%s" % [AI_MODES[info.get("ai_mode", 0)], "   (hitboxes ON)" if info.get("boxes", false) else ""]
	_banner.text = info.get("banner", "")


# ---------------------------------------------------------------- piezas

func _make_bars(parent: Control, color: Color, reversed: bool) -> Dictionary:
	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 6)
	if reversed:
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parent.add_child(name_label)
	var hp := _bar(parent, 26.0, color, reversed)
	var evo := _bar(parent, 12.0, Color(0.3, 0.7, 1.0) if not reversed else Color(1.0, 0.4, 0.3), reversed)
	var stock_row := HBoxContainer.new()
	stock_row.alignment = BoxContainer.ALIGNMENT_END if reversed else BoxContainer.ALIGNMENT_BEGIN
	stock_row.add_theme_constant_override("separation", 6)
	parent.add_child(stock_row)
	var stocks := []
	for i in 3:
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(18.0, 18.0)
		var sb := StyleBoxFlat.new()
		sb.bg_color = color.lightened(0.2)
		sb.set_corner_radius_all(9)
		sb.set_border_width_all(2)
		sb.border_color = Color.BLACK
		dot.add_theme_stylebox_override("panel", sb)
		stock_row.add_child(dot)
		stocks.append(dot)
	return {"name": name_label, "hp": hp, "evo": evo, "stocks": stocks, "stock_row": stock_row}


func _bar(parent: Control, height: float, color: Color, reversed: bool) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(420.0, height)
	b.max_value = 100.0
	b.show_percentage = false
	if reversed:
		b.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	bg.set_corner_radius_all(5)
	bg.set_border_width_all(2)
	bg.border_color = Color(0.0, 0.0, 0.0, 0.9)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(5)
	fill.set_border_width_all(2)
	fill.border_color = Color(0.0, 0.0, 0.0, 0.0)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	parent.add_child(b)
	return b


# Recuadro oscuro semitransparente con titulo, anclado a una esquina de abajo.
func _panel(root: Control, preset: int, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.06, 0.05, 0.62)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(10.0)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_and_offsets_preset(preset)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.grow_horizontal = Control.GROW_DIRECTION_END if preset == Control.PRESET_BOTTOM_LEFT else Control.GROW_DIRECTION_BEGIN
	var edge := 14.0 if preset == Control.PRESET_BOTTOM_LEFT else -14.0
	panel.offset_left = edge
	panel.offset_right = edge
	panel.offset_top = -12.0
	panel.offset_bottom = -12.0
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var head := Label.new()
	head.text = title
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	box.add_child(head)
	return box


func _player_rows(box: VBoxContainer, keys: Dictionary) -> Dictionary:
	var row_a := _row(box)
	for item in ROW_A:
		_chip(row_a, keys[item[0]], item[1])
	var row_b := _row(box)
	var out := {}
	for item in ROW_B:
		var chip := _chip(row_b, keys[item[0]], item[1])
		if item[0] == "k" or item[0] == "l":
			out[item[0]] = chip
	var row_c := _row(box)
	for item in ROW_C:
		_chip(row_c, keys[item[0]], item[1])
	return out


func _row(box: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	return row


# Una o mas teclas dibujadas y, al lado, lo que hacen. Devuelve [contenedor, etiqueta].
func _chip(row: HBoxContainer, keys: Array, action: String) -> Array:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 4)
	row.add_child(chip)
	for k in keys:
		var cap := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.96, 0.96, 0.92)
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(1)
		sb.border_width_bottom = 4
		sb.border_color = Color(0.45, 0.47, 0.52)
		sb.content_margin_left = 7.0
		sb.content_margin_right = 7.0
		sb.content_margin_top = 1.0
		sb.content_margin_bottom = 1.0
		cap.add_theme_stylebox_override("panel", sb)
		var kl := Label.new()
		kl.text = k
		kl.custom_minimum_size.x = 13.0
		kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		kl.add_theme_font_size_override("font_size", 15)
		kl.add_theme_color_override("font_color", Color(0.1, 0.1, 0.14))
		cap.add_child(kl)
		chip.add_child(cap)
	var label := Label.new()
	label.text = action
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	chip.add_child(label)
	return [chip, label]
