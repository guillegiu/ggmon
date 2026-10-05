extends RefCounted
# Escenario de selva armado por codigo. Semilla fija para que siempre salga igual.
# Hay dos variantes:
#   simple   una isla entera y cinco plataformas de madera (menu y sala de pruebas)
#   complex  la isla partida por un rio con corriente, un puente de tablones que se
#            rompen, una cascada de fondo y hojas gigantes que ceden y vuelven a crecer

const Breakable = preload("res://scripts/breakable.gd")
const Vfx = preload("res://scripts/vfx.gd")
const WATER = preload("res://shaders/water.gdshader")

const LAYER_SOLID := 1
const LAYER_ONEWAY := 4

const C_DIRT := Color(0.36, 0.24, 0.14)
const C_GRASS := Color(0.3, 0.62, 0.2)
const C_MOSS := Color(0.36, 0.58, 0.22)
const C_WOOD := Color(0.45, 0.3, 0.17)
const C_BARK := Color(0.3, 0.21, 0.13)
const C_STONE := Color(0.5, 0.52, 0.48)
const C_VINE := Color(0.2, 0.45, 0.15)

const RIVER_HALF := 3.5     # media anchura del rio
const RIVER_BED := -1.7     # donde se apoya quien cae al rio
const RIVER_TOP := -0.85    # superficie del agua


static func build(root: Node3D, complex: bool = false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_environment(root)

	# Suelo: tope en y = 0.
	if complex:
		_island(root, -15.0, -RIVER_HALF)
		_island(root, RIVER_HALF, 15.0)
		_river(root)
		_bridge(root)
	else:
		_island(root, -15.0, 15.0)

	# Bloque de ruina solido a la derecha.
	_collider(root, Vector3(12.5, 0.6, 0.0), Vector3(2.6, 1.2, 3.0), LAYER_SOLID, false)
	_box(root, Vector3(12.5, 0.6, 0.0), Vector3(2.6, 1.2, 3.0), _mat(C_STONE))
	_box(root, Vector3(12.5, 1.23, 0.0), Vector3(2.7, 0.08, 3.1), _mat(C_MOSS))

	# Plataformas atravesables: [x, y del tope, ancho, es hoja en la variante compleja].
	for p in [[-8.0, 2.2, 5.0, false], [8.0, 2.2, 5.0, false], [0.0, 4.2, 6.0, true], [-11.5, 5.8, 3.2, true], [11.5, 5.8, 3.2, true]]:
		if complex and p[3]:
			_leaf_platform(root, p[0], p[1], p[2])
		else:
			_platform(root, rng, p[0], p[1], p[2])

	# Agua alrededor de la isla y suelo de la selva detras.
	var water := _mat(Color(0.1, 0.42, 0.42), 0.08)
	water.metallic = 0.4
	_box(root, Vector3(0.0, -2.6, 2.0), Vector3(160.0, 0.2, 14.0), water)
	_box(root, Vector3(0.0, -1.3, -22.0), Vector3(160.0, 2.2, 38.0), _mat(Color(0.16, 0.36, 0.14)))

	# Detalle sobre la isla, detras y delante del plano de juego.
	for i in 26:
		var x := rng.randf_range(-14.5, 14.5)
		var z := rng.randf_range(-2.8, -1.4) if i % 3 != 0 else rng.randf_range(2.2, 2.9)
		var size := rng.randf_range(0.5, 1.0) if z < 0.0 else 0.35
		# nada flotando sobre el rio
		if not (complex and absf(x) < RIVER_HALF + 0.5):
			_fern(root, rng, Vector3(x, 0.0, z), size)
	for i in 8:
		var r := rng.randf_range(0.25, 0.6)
		var at := Vector3(rng.randf_range(-14.0, 14.0), r * 0.3, rng.randf_range(-2.8, -1.8))
		if not (complex and absf(at.x) < RIVER_HALF + 0.5):
			_ball(root, at, r, _mat(C_STONE), Vector3(1.3, 0.7, 1.0))
	for i in 14:
		var c: Color = [Color(1.0, 0.35, 0.5), Color(1.0, 0.85, 0.2), Color(0.8, 0.5, 1.0)][i % 3]
		var at := Vector3(rng.randf_range(-14.0, 14.0), 0.12, rng.randf_range(-2.6, -1.3))
		if not (complex and absf(at.x) < RIVER_HALF + 0.5):
			_ball(root, at, 0.1, _mat(c))

	# Pilares de ruina cerca del plano.
	for x in [-13.0, -5.5, 5.0, 9.5]:
		var h := rng.randf_range(2.5, 5.5)
		var pil := _box(root, Vector3(x, h * 0.5 - 0.2, -4.2), Vector3(1.1, h, 1.1), _mat(C_STONE))
		pil.rotation.z = rng.randf_range(-0.08, 0.08)
		_box(root, Vector3(x, h - 0.15, -4.2), Vector3(1.35, 0.25, 1.35), _mat(C_MOSS))

	# Arboles en capas: mas lejos, mas chicos en pantalla y mas tapados por la niebla.
	for layer in [[-6.5, 7, 0.7, 16.0], [-11.0, 11, 0.6, 13.0], [-17.0, 15, 0.55, 12.0], [-26.0, 20, 0.5, 11.0]]:
		var count: int = layer[1]
		for i in count:
			var x := lerpf(-34.0, 34.0, (i + rng.randf()) / count)
			_tree(root, rng, Vector3(x, -0.2, layer[0] + rng.randf_range(-1.5, 1.5)), layer[3] * rng.randf_range(0.8, 1.2), layer[2])

	# Lianas colgando del techo de hojas.
	for i in 16:
		var x := rng.randf_range(-18.0, 18.0)
		_vine(root, rng, Vector3(x, 15.0, rng.randf_range(-3.5, -1.6)), rng.randf_range(5.0, 9.5))

	_fireflies(root)


static func _island(root: Node3D, x0: float, x1: float) -> void:
	var w := x1 - x0
	var cx := (x0 + x1) * 0.5
	_collider(root, Vector3(cx, -2.0, 0.0), Vector3(w, 4.0, 6.0), LAYER_SOLID, false)
	_box(root, Vector3(cx, -2.15, 0.0), Vector3(w, 3.7, 6.0), _mat(C_DIRT))
	_box(root, Vector3(cx, -0.15, 0.0), Vector3(w + 0.4, 0.3, 6.4), _mat(C_GRASS))


# Rio entre las dos islas: lecho solido bajo el nivel del suelo y corriente que arrastra
# hacia la derecha. Quien cae por el puente tiene que salir saltando. La cascada del
# fondo es solo decorado.
static func _river(root: Node3D) -> void:
	var w := RIVER_HALF * 2.0
	_collider(root, Vector3(0.0, RIVER_BED - 0.5, 0.0), Vector3(w, 1.0, 6.0), LAYER_SOLID, false)
	_box(root, Vector3(0.0, RIVER_BED - 0.5, 0.0), Vector3(w, 1.0, 6.0), _mat(Color(0.25, 0.27, 0.26)))
	for i in 5:
		_ball(root, Vector3(-2.8 + i * 1.4, RIVER_BED, -1.5 + (i % 2) * 2.4), 0.35, _mat(C_STONE), Vector3(1.4, 0.6, 1.1))

	var surface := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(w + 0.3, 6.2)
	surface.mesh = plane
	surface.material_override = _water(Vector2(1.0, 0.0), Vector2(4.0, 3.0), 0.5)
	surface.position = Vector3(0.0, RIVER_TOP, 0.0)
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(surface)
	var front := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(w, RIVER_TOP - RIVER_BED)
	front.mesh = fq
	front.material_override = _water(Vector2(1.0, 0.0), Vector2(4.0, 0.6), 0.5)
	front.position = Vector3(0.0, (RIVER_TOP + RIVER_BED) * 0.5, 3.02)
	front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(front)

	# pared de roca y cascada detras del puente
	_box(root, Vector3(0.0, 6.0, -4.4), Vector3(w + 1.5, 16.0, 1.6), _mat(C_STONE.darkened(0.25)))
	_box(root, Vector3(0.0, 13.9, -4.2), Vector3(w + 2.2, 0.5, 2.2), _mat(C_MOSS))
	var fall := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(4.6, 15.0)
	fall.mesh = quad
	fall.material_override = _water(Vector2(0.0, -1.0), Vector2(3.0, 5.0), 1.3)
	fall.position = Vector3(0.0, 6.6, -3.5)
	fall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fall)
	var foam: CPUParticles3D = Vfx.sparks(root, Color(1.0, 1.0, 1.0, 0.8), Color(0.7, 0.9, 1.0), {
		"amount": 40, "life": 0.7, "size": 0.6, "speed": 2.5, "dir": Vector3.UP, "spread": 60.0, "gravity": Vector3(0.0, -5.0, 0.0), "radius": 1.8})
	foam.position = Vector3(0.0, RIVER_TOP, -3.0)

	var current := Node3D.new()
	current.name = "Corriente"
	current.add_to_group("currents")
	current.set_meta("rect", Rect2(-RIVER_HALF, RIVER_BED - 0.2, w, RIVER_TOP - RIVER_BED + 0.5))
	current.set_meta("flow", 4.5)
	root.add_child(current)


# Puente colgante: cada tablon cede si alguien se queda parado y reaparece al rato.
static func _bridge(root: Node3D) -> void:
	var planks := int(RIVER_HALF * 2.0)
	for i in planks:
		var plank := Breakable.new()
		plank.kind = "plank"
		plank.width = 1.0
		plank.position = Vector3(-RIVER_HALF + 0.5 + i, 0.0, 0.0)
		root.add_child(plank)
	# barandas de soga y postes: decorado, no se rompen
	var rope := _mat(Color(0.62, 0.5, 0.3))
	for z in [-1.25, 1.25]:
		for side in [-1.0, 1.0]:
			_cyl(root, Vector3(side * (RIVER_HALF + 0.15), 0.55, z), 0.09, 1.3, _mat(C_BARK))
		var line := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.035
		cyl.bottom_radius = 0.035
		cyl.height = RIVER_HALF * 2.0 + 0.3
		line.mesh = cyl
		line.material_override = rope
		line.rotation.z = PI * 0.5
		line.position = Vector3(0.0, 1.05, z)
		root.add_child(line)


# Hoja gigante: aguanta poco peso. Cede rapido y vuelve a crecer.
static func _leaf_platform(root: Node3D, x: float, top: float, w: float) -> void:
	var leaf := Breakable.new()
	leaf.kind = "leaf"
	leaf.width = w
	leaf.depth = 2.6
	leaf.delay = 0.7
	leaf.respawn = 4.0
	leaf.position = Vector3(x, top, 0.0)
	root.add_child(leaf)


static func _water(flow: Vector2, tiling: Vector2, speed: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER
	m.set_shader_parameter("flow", flow)
	m.set_shader_parameter("tiling", tiling)
	m.set_shader_parameter("speed", speed)
	return m


static func _environment(root: Node3D) -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.5, 0.55)
	sky_mat.sky_horizon_color = Color(0.75, 0.9, 0.68)
	sky_mat.ground_horizon_color = Color(0.45, 0.65, 0.45)
	sky_mat.ground_bottom_color = Color(0.05, 0.15, 0.08)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.5, 0.72, 0.5)
	env.fog_density = 0.02
	# Sin SSAO: combinado con MSAA rompe el render (bloques negros) en la Radeon RX 570.
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.8)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	root.add_child(sun)


static func _platform(root: Node3D, rng: RandomNumberGenerator, x: float, top: float, w: float) -> void:
	_collider(root, Vector3(x, top - 0.15, 0.0), Vector3(w, 0.3, 2.4), LAYER_ONEWAY, true)
	_box(root, Vector3(x, top - 0.25, 0.0), Vector3(w, 0.4, 2.2), _mat(C_WOOD))
	_box(root, Vector3(x, top - 0.03, 0.0), Vector3(w + 0.15, 0.08, 2.35), _mat(C_MOSS))
	for s in [-1.0, 1.0]:
		var log_end := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.28
		cyl.bottom_radius = 0.28
		cyl.height = 2.5
		log_end.mesh = cyl
		log_end.material_override = _mat(C_BARK)
		log_end.rotation.x = PI * 0.5
		log_end.position = Vector3(x + s * (w * 0.5 - 0.1), top - 0.28, 0.0)
		root.add_child(log_end)
		# Lianas que sostienen la plataforma.
		for z in [-1.0, 1.0]:
			_cyl(root, Vector3(x + s * (w * 0.5 - 0.1), top + 7.0, z), 0.05, 14.0, _mat(C_VINE))
	for i in int(w):
		_fern(root, rng, Vector3(x + rng.randf_range(-w * 0.45, w * 0.45), top, -0.95), 0.3)


static func _tree(root: Node3D, rng: RandomNumberGenerator, pos: Vector3, h: float, r: float) -> void:
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r * 0.65
	cyl.bottom_radius = r * 1.2
	cyl.height = h
	cyl.radial_segments = 10
	trunk.mesh = cyl
	trunk.material_override = _mat(C_BARK.lerp(C_WOOD, rng.randf()))
	trunk.position = pos + Vector3(0.0, h * 0.5, 0.0)
	trunk.rotation.z = rng.randf_range(-0.06, 0.06)
	root.add_child(trunk)
	for i in 5:
		var g := rng.randf_range(0.0, 1.0)
		var col := Color(0.12, 0.42, 0.12).lerp(Color(0.35, 0.68, 0.2), g)
		var cr := rng.randf_range(1.8, 3.2)
		var off := Vector3(rng.randf_range(-2.6, 2.6), h + rng.randf_range(-2.0, 1.2), rng.randf_range(-1.5, 1.5))
		_ball(root, pos + off, cr, _mat(col), Vector3(1.0, 0.7, 1.0))


static func _vine(root: Node3D, rng: RandomNumberGenerator, top: Vector3, length: float) -> void:
	_cyl(root, top - Vector3(0.0, length * 0.5, 0.0), 0.045, length, _mat(C_VINE))
	var n := int(length)
	for i in n:
		var y := top.y - length + i * (length / n) * 0.6
		_ball(root, Vector3(top.x + rng.randf_range(-0.15, 0.15), y, top.z), 0.14, _mat(C_GRASS), Vector3(1.4, 0.5, 1.0))


static func _fern(root: Node3D, rng: RandomNumberGenerator, pos: Vector3, size: float) -> void:
	var col := Color(0.16, 0.5, 0.14).lerp(Color(0.4, 0.72, 0.22), rng.randf())
	var mat := _mat(col)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.13 * size
	cone.height = 1.1 * size
	cone.radial_segments = 6
	for i in 6:
		var piv := Node3D.new()
		piv.position = pos
		piv.rotation = Vector3(rng.randf_range(-0.7, 0.7), 0.0, rng.randf_range(-0.9, 0.9))
		root.add_child(piv)
		var leaf := MeshInstance3D.new()
		leaf.mesh = cone
		leaf.material_override = mat
		leaf.position.y = 0.55 * size
		piv.add_child(leaf)


static func _fireflies(root: Node3D) -> void:
	var p := CPUParticles3D.new()
	p.amount = 70
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(18.0, 4.5, 3.5)
	p.position = Vector3(0.0, 4.5, -1.0)
	p.gravity = Vector3.ZERO
	p.direction = Vector3(1.0, 0.3, 0.0)
	p.spread = 180.0
	p.initial_velocity_min = 0.15
	p.initial_velocity_max = 0.5
	var m := SphereMesh.new()
	m.radius = 0.045
	m.height = 0.09
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 1.0, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 1.0, 0.4)
	mat.emission_energy_multiplier = 5.0
	m.material = mat
	p.mesh = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)


static func _collider(root: Node3D, pos: Vector3, size: Vector3, layer: int, oneway: bool) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = layer
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	b.position = pos
	if oneway:
		b.add_to_group("oneway")
		b.set_meta("top", pos.y + size.y * 0.5)
	root.add_child(b)


static func _box(root: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	root.add_child(mi)
	return mi


static func _ball(root: Node3D, pos: Vector3, r: float, mat: Material, scl := Vector3.ONE) -> void:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 14
	m.rings = 7
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	root.add_child(mi)


static func _cyl(root: Node3D, pos: Vector3, r: float, h: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 6
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	root.add_child(mi)


static func _mat(c: Color, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
