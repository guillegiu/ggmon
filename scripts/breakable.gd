extends StaticBody3D
# Plataforma que se rompe si alguien se queda parado encima y vuelve a aparecer al rato.
# Se usa para los tablones del puente y para las hojas gigantes. Es atravesable desde
# abajo, igual que las demas plataformas (grupo "oneway").

const Vfx = preload("res://scripts/vfx.gd")

const LAYER_ONEWAY := 4

# Se setean antes de add_child.
var kind := "plank"         # "plank" tablon de madera, "leaf" hoja
var width := 1.0
var depth := 2.4
var delay := 0.45           # segundos parado encima hasta que cede
var respawn := 5.0

var broken := false
var puppet := false         # partida online, lado del invitado: el estado lo manda el anfitrion
var _visual: Node3D
var _stand := 0.0
var _timer := 0.0
var _t := 0.0


func _ready() -> void:
	collision_layer = LAYER_ONEWAY
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(width, 0.25, depth)
	cs.shape = sh
	cs.position.y = -0.125
	add_child(cs)
	add_to_group("oneway")
	add_to_group("breakables")
	set_meta("top", position.y)

	_visual = Node3D.new()
	add_child(_visual)
	if kind == "leaf":
		_leaf()
	else:
		_plank()


func _physics_process(delta: float) -> void:
	_t += delta
	if puppet:
		return
	if broken:
		_timer -= delta
		if _timer <= 0.0:
			_restore()
		return
	var stood := false
	for f in get_tree().get_nodes_in_group("fighters"):
		var p: Vector3 = f.global_position
		if f.is_on_floor() and absf(p.y - global_position.y) < 0.15 and absf(p.x - global_position.x) < width * 0.5 + 0.25:
			stood = true
	_stand = _stand + delta if stood else maxf(_stand - delta * 0.5, 0.0)
	# avisa temblando cada vez mas antes de ceder
	var k := _stand / delay
	_visual.position = Vector3(sin(_t * 70.0) * 0.03 * k, -0.06 * k, 0.0)
	_visual.rotation.z = sin(_t * 55.0) * 0.05 * k
	if _stand >= delay:
		_break()


func _break() -> void:
	broken = true
	_timer = respawn
	_stand = 0.0
	collision_layer = 0
	_visual.visible = false
	var color := Color(0.3, 0.7, 0.2) if kind == "leaf" else Color(0.5, 0.32, 0.16)
	Vfx.burst(get_parent(), global_position, color, 14 if kind == "leaf" else 10, 3.5, 0.35)
	get_tree().call_group("sfx", "play", "land", 0.6 if kind == "plank" else 1.5)


func _restore() -> void:
	broken = false
	collision_layer = LAYER_ONEWAY
	_visual.visible = true
	_visual.position = Vector3.ZERO
	_visual.rotation = Vector3.ZERO
	_visual.scale = Vector3.ONE * 0.2
	create_tween().tween_property(_visual, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Vfx.ring(get_parent(), global_position, Color(0.8, 1.0, 0.6, 0.6), width * 0.7, 0.3, true)


# Lado del invitado: copia el estado sin efectos (los efectos llegan aparte).
func net_set(is_broken: bool) -> void:
	if is_broken == broken:
		return
	broken = is_broken
	_visual.visible = not broken
	if not broken:
		_visual.scale = Vector3.ONE * 0.2
		create_tween().tween_property(_visual, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _plank() -> void:
	var wood := _mat(Color(0.5, 0.33, 0.17).lerp(Color(0.38, 0.25, 0.13), randf()))
	_mesh(_box(Vector3(width * 0.92, 0.14, depth)), wood, Vector3(0.0, -0.07, 0.0))
	# travesaños por debajo
	for z in [-depth * 0.32, depth * 0.32]:
		_mesh(_box(Vector3(width, 0.08, 0.14)), _mat(Color(0.28, 0.18, 0.1)), Vector3(0.0, -0.18, z))


func _leaf() -> void:
	var green := _mat(Color(0.25, 0.62, 0.18))
	var dark := _mat(Color(0.14, 0.42, 0.12))
	var blade := SphereMesh.new()
	blade.radius = 0.5
	blade.height = 1.0
	blade.radial_segments = 20
	blade.rings = 8
	# hoja grande, ancha y chata, con nervadura central y tallo
	_mesh(blade, green, Vector3(0.0, -0.06, 0.0), Vector3(width * 1.04, 0.14, depth))
	_mesh(blade, dark, Vector3(0.0, -0.035, 0.0), Vector3(width * 1.0, 0.12, depth * 0.07))
	for i in 4:
		var x := (i - 1.5) * width * 0.22
		_mesh(blade, dark, Vector3(x, -0.04, 0.0), Vector3(width * 0.02, 0.11, depth * 0.85)).rotation.y = 0.5 if i % 2 == 0 else -0.5
	var stem := CylinderMesh.new()
	stem.top_radius = 0.07
	stem.bottom_radius = 0.1
	stem.height = 12.0
	_mesh(stem, dark, Vector3(0.0, -6.1, -depth * 0.45))


func _mesh(mesh: Mesh, mat: Material, pos: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	_visual.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m
