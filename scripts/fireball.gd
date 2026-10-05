extends Node3D
# Proyectil generico. El estilo define como se ve; el resto de las variables, como se
# comporta. Choca contra el escenario solido (capa 1) y contra luchadores.

const Vfx = preload("res://scripts/vfx.gd")
const Hazard = preload("res://scripts/hazard.gd")

var style := "fire"
var dir := 1
var speed := 14.0
var vel_y := 0.0
var gravity := 0.0
var dmg := 8.0
var kb := Vector2(6.0, 5.0)
var stop := 5
var radius := 0.3
var grow := 0.0             # cuanto crece el radio por segundo (llamas)
var life := 1.3
var aoe := 0.0              # la explosion tambien daÃ±a alrededor
var pierce := false         # atraviesa luchadores: golpea una vez a cada uno
var boomerang := false      # a mitad de vida vuelve hacia quien lo tiro y puede golpear de nuevo
var cloud := 0.0            # al terminar deja una nube de este radio
var bounces := 0            # rebotes contra el suelo antes de explotar
var stun := 0               # frames extra sin poder moverse para el que recibe
var poison := 0             # frames de veneno para el que recibe
var color := Color(1.0, 0.5, 0.1)
var shooter: Node = null
# Partida online, del lado del invitado: solo se dibuja; lo mueve el anfitrion.
var puppet := false

var _visual: Node3D
var _halo: MeshInstance3D
var _age := 0.0
var _turned := false
var _hits: Array = []


func net_state() -> Array:
	return [get_instance_id(), style, global_position, dir, radius, color]


func apply_net(s: Array) -> void:
	global_position = global_position.lerp(s[2], 0.6)
	dir = s[3]
	radius = s[4]


func _ready() -> void:
	add_to_group("projectiles")
	_visual = Node3D.new()
	add_child(_visual)
	match style:
		"fire", "big":
			_core(SphereMesh.new(), Color(1.0, 0.9, 0.5), radius * 0.75)
			_halo = Vfx.glow(self, color, radius * 5.0)
			Vfx.sparks(self, Color(1.0, 0.85, 0.3), Color(0.9, 0.1, 0.0), {"amount": 36, "life": 0.45, "size": radius * 2.2, "speed": 1.0, "gravity": Vector3(0.0, 2.5, 0.0)})
		"flame":
			_halo = Vfx.glow(self, color, radius * 4.0)
			Vfx.sparks(self, Color(1.0, 0.8, 0.3), Color(0.8, 0.1, 0.0), {"amount": 8, "life": 0.3, "size": radius * 2.0, "speed": 1.5, "gravity": Vector3(0.0, 4.0, 0.0)})
		"ice":
			var crystal := CylinderMesh.new()
			crystal.top_radius = 0.0
			crystal.bottom_radius = 0.6
			crystal.height = 2.6
			crystal.radial_segments = 5
			_core(crystal, Color(0.75, 0.95, 1.0), radius).rotation.z = -PI * 0.5 * dir
			_halo = Vfx.glow(self, color, radius * 4.0)
			Vfx.sparks(self, Color(0.9, 1.0, 1.0), Color(0.3, 0.6, 1.0), {"amount": 18, "life": 0.4, "size": radius * 1.2, "speed": 0.8, "gravity": Vector3(0.0, -2.0, 0.0)})
		"acid":
			_core(SphereMesh.new(), Color(0.6, 1.0, 0.2), radius).scale *= Vector3(1.5, 0.8, 0.8)
			_halo = Vfx.glow(self, color, radius * 3.5)
			Vfx.sparks(self, Color(0.8, 1.0, 0.3), Color(0.1, 0.5, 0.0), {"amount": 14, "life": 0.4, "size": radius * 1.4, "speed": 0.5, "gravity": Vector3(0.0, -7.0, 0.0)})
		"bomb":
			var rock := _core(SphereMesh.new(), Color(0.12, 0.06, 0.05), radius)
			var rock_mat: StandardMaterial3D = rock.material_override
			rock_mat.emission = Color(1.0, 0.35, 0.05)
			rock_mat.emission_energy_multiplier = 1.2
			rock_mat.roughness = 0.9
			_halo = Vfx.glow(self, color, radius * 4.5)
			Vfx.sparks(self, Color(1.0, 0.7, 0.2), Color(0.3, 0.05, 0.0), {"amount": 30, "life": 0.6, "size": radius * 1.6, "speed": 0.8, "gravity": Vector3(0.0, 1.5, 0.0)})
		"dust":
			_halo = Vfx.glow(self, color, radius * 5.0)
			Vfx.sparks(self, Color(0.9, 1.0, 1.0), color, {"amount": 26, "life": 0.7, "size": radius * 1.6, "speed": 0.9, "radius": radius})
		"blade":
			var disc := TorusMesh.new()
			disc.inner_radius = 0.45
			disc.outer_radius = 1.0
			disc.rings = 5
			disc.ring_segments = 4
			var blade := _core(disc, Color(0.8, 1.0, 0.4), radius)
			blade.rotation.x = PI * 0.5
			blade.scale.y *= 0.15
			_halo = Vfx.glow(self, color, radius * 3.5)
			Vfx.sparks(self, Color(0.9, 1.0, 0.5), Color(0.2, 0.6, 0.1), {"amount": 16, "life": 0.25, "size": radius * 1.3, "speed": 0.3})
		"gust":
			for i in 3:
				var arc := Vfx.glow(_visual, Color(0.85, 1.0, 1.0, 0.5), radius * 2.4)
				arc.position.x = -dir * i * 0.45
				arc.scale = Vector3(radius * 0.9, radius * (3.0 - i * 0.6), 1.0)
			Vfx.sparks(self, Color(1.0, 1.0, 1.0, 0.7), Color(0.6, 0.9, 1.0), {"amount": 20, "life": 0.35, "size": 0.25, "speed": 2.0, "radius": radius})
		"bubble":
			var skin := StandardMaterial3D.new()
			skin.albedo_color = Color(0.7, 0.95, 1.0, 0.3)
			skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			skin.roughness = 0.05
			skin.metallic = 0.3
			skin.rim_enabled = true
			skin.rim = 1.0
			var ball := _core(SphereMesh.new(), Color.WHITE, radius)
			ball.material_override = skin
			Vfx.glow(self, Color(1.0, 1.0, 1.0, 0.7), radius * 0.6).position = Vector3(-radius * 0.35, radius * 0.4, radius * 0.6)
			Vfx.sparks(self, Color(1.0, 1.0, 1.0, 0.8), color, {"amount": 10, "life": 0.6, "size": 0.14, "speed": 0.5, "radius": radius, "gravity": Vector3(0.0, 1.5, 0.0)})
		"dart":
			var needle := CylinderMesh.new()
			needle.top_radius = 0.0
			needle.bottom_radius = 0.5
			needle.height = 5.0
			needle.radial_segments = 6
			_core(needle, Color(0.85, 0.5, 1.0), radius).rotation.z = -PI * 0.5 * dir
			_halo = Vfx.glow(self, color, radius * 4.0)
			Vfx.sparks(self, Color(0.9, 0.6, 1.0), Color(0.3, 0.8, 0.2), {"amount": 14, "life": 0.3, "size": 0.2, "speed": 0.4})
		"wave":
			_halo = Vfx.glow(self, color, radius * 3.0)
			Vfx.sparks(self, Color(0.9, 0.8, 0.6), Color(0.4, 0.3, 0.2), {"amount": 26, "life": 0.4, "size": 0.35, "speed": 4.0, "dir": Vector3.UP, "spread": 35.0, "gravity": Vector3(0.0, -14.0, 0.0)})
	if style != "gust":
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 2.0 if style != "flame" else 0.8
		light.omni_range = 4.5
		add_child(light)


func _physics_process(delta: float) -> void:
	_age += delta
	if grow > 0.0:
		radius += grow * delta
		if _halo != null:
			_halo.scale = Vector3.ONE * radius * 4.0
	if style == "blade" or style == "bomb":
		_visual.rotation.z -= dir * delta * (22.0 if style == "blade" else 6.0)
	if _halo != null and style != "flame":
		_halo.scale = Vector3.ONE * radius * (4.5 + sin(_age * 30.0) * 0.5)

	if puppet:
		return
	if boomerang and not _turned and _age >= life * 0.45:
		_turned = true
		_hits.clear()
	if _turned and is_instance_valid(shooter):
		# vuelve derecho a quien lo tiro
		var home: Vector3 = shooter.global_position + Vector3(0.0, 1.0, 0.0) - global_position
		if home.length() < 0.8:
			queue_free()
			return
		var v := home.normalized() * speed
		dir = 1 if v.x >= 0.0 else -1
		global_position += Vector3(v.x, v.y, 0.0) * delta
	else:
		vel_y -= gravity * delta
		var from := global_position
		var to := from + Vector3(dir * speed * delta, vel_y * delta, 0.0)
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			if bounces > 0 and hit.normal.y > 0.5:
				bounces -= 1
				vel_y = maxf(absf(vel_y) * 0.75, 7.0)
				global_position = hit.position + Vector3(0.0, radius + 0.05, 0.0)
				Vfx.ring(get_parent(), hit.position, color, 0.6, 0.2, true)
				return
			if boomerang:
				_turned = true
				_hits.clear()
			else:
				_explode(null)
			return
		global_position = to

	var here := Vector2(global_position.x, global_position.y)
	for f in get_tree().get_nodes_in_group("fighters"):
		if f == shooter or _hits.has(f):
			continue
		var box: Rect2 = f.hurt_box().grow(radius)
		if box.has_point(here):
			_hits.append(f)
			_damage(f, dmg)
			if not pierce:
				_explode(f)
				return
	life -= delta
	if life <= 0.0:
		_explode(null)


func _core(mesh: Mesh, c: Color, size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Vfx.emissive(c, 3.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * size * 2.0 if mesh is SphereMesh else Vector3.ONE * size
	_visual.add_child(mi)
	return mi


func _damage(f: Node, amount: float) -> void:
	if not f.take_hit(shooter, amount, kb, dir, stop):
		return
	if stun > 0:
		f.add_stun(stun)
	if poison > 0:
		f.add_poison(poison)
	if is_instance_valid(shooter):
		shooter.add_gauge(amount * 1.6)
		shooter.hit_landed.emit(amount)


func _explode(direct: Node) -> void:
	if aoe > 0.0:
		for f in get_tree().get_nodes_in_group("fighters"):
			if f == shooter or f == direct:
				continue
			var c: Vector2 = f.hurt_box().get_center()
			if c.distance_to(Vector2(global_position.x, global_position.y)) < aoe:
				_damage(f, dmg * 0.6)
		get_tree().call_group("sfx", "play", "explode")
		Vfx.explosion(get_parent(), global_position, color, aoe)
	elif style == "flame" or style == "gust":
		pass    # se desvanecen sin estallar
	else:
		Vfx.explosion(get_parent(), global_position, color, radius * 1.6)
	if cloud > 0.0:
		var h := Hazard.new()
		h.radius = cloud
		h.color = color
		h.owner_fighter = shooter
		h.position = global_position
		get_parent().add_child(h)
	queue_free()
