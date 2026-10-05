extends Node3D
# Orbe magico: al tocarlo, el luchador evoluciona a la forma de ese color.
# Se arma por capas como los orbes de referencia: nucleo brillante, dos anillos de
# energia que giran cruzados, halo que late, chispas que suben, luz y un charco de
# luz en el piso.

const Forms = preload("res://scripts/forms.gd")
const Vfx = preload("res://scripts/vfx.gd")

var kind := 1
var life := 16.0
var puppet := false         # partida online, lado del invitado: solo se dibuja
var _t := 0.0
var _base_y := 0.0
var _color := Color.WHITE
var _rings: Array[MeshInstance3D] = []
var _halo: MeshInstance3D
var _pool: MeshInstance3D


func net_state() -> Array:
	return [get_instance_id(), kind, Vector3(position.x, _base_y, 0.0), visible]


func apply_net(s: Array) -> void:
	visible = s[3]
	if _pool != null:
		_pool.visible = visible


func _ready() -> void:
	add_to_group("orbs")
	_color = Forms.ORB[kind]
	_base_y = position.y

	var core := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.24
	m.height = 0.48
	core.mesh = m
	# el color tiene que leerse en el nucleo, no solo en el halo: poca emision y bien saturada
	var core_mat := Vfx.emissive(_color, 1.1)
	core_mat.metallic = 0.3
	core_mat.roughness = 0.15
	core.material_override = core_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	Vfx.glow(self, Color(1.0, 1.0, 1.0, 0.45), 0.3).position = Vector3(-0.07, 0.08, 0.2)
	_halo = Vfx.glow(self, _color, 1.9)

	for i in 2:
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.4 + i * 0.1
		t.outer_radius = 0.44 + i * 0.1
		t.rings = 40
		t.ring_segments = 6
		ring.mesh = t
		ring.material_override = Vfx.emissive(_color.lerp(Color.WHITE, 0.25), 1.5)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.rotation = Vector3(0.9 + i * 1.2, 0.0, 0.5 - i * 1.1)
		add_child(ring)
		_rings.append(ring)

	Vfx.sparks(self, Color(1.0, 1.0, 1.0), _color, {"amount": 22, "life": 1.0, "size": 0.16, "speed": 0.35, "radius": 0.45, "gravity": Vector3(0.0, 1.2, 0.0)})

	var light := OmniLight3D.new()
	light.light_color = _color
	light.light_energy = 2.5
	light.omni_range = 5.0
	add_child(light)

	# charco de luz donde apoya (suelo o plataforma)
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3(0.0, -4.0, 0.0), 1 | 4)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_pool = MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(2.2, 2.2)
		_pool.mesh = quad
		var pm := Vfx.glow_material(Color(_color.r, _color.g, _color.b, 0.55))
		pm.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		_pool.material_override = pm
		_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pool.top_level = true
		add_child(_pool)
		_pool.global_position = hit.position + Vector3(0.0, 0.04, 0.0)
		_pool.rotation.x = -PI * 0.5

	scale = Vector3.ONE * 0.05
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not puppet:
		Vfx.ring(get_parent(), global_position, _color, 1.2, 0.4)
		get_tree().call_group("sfx", "play", "orb")


func _physics_process(delta: float) -> void:
	_t += delta
	position.y = _base_y + sin(_t * 2.5) * 0.15
	_rings[0].rotate_y(delta * 2.4)
	_rings[0].rotate_x(delta * 1.1)
	_rings[1].rotate_y(-delta * 1.7)
	_rings[1].rotate_z(delta * 1.4)
	_halo.scale = Vector3.ONE * (1.9 + sin(_t * 5.0) * 0.25)
	if puppet:
		return
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	# Parpadea antes de desaparecer.
	visible = life > 3.0 or fmod(life, 0.3) > 0.12
	if _pool != null:
		_pool.visible = visible
	var here := Vector2(global_position.x, global_position.y)
	for f in get_tree().get_nodes_in_group("fighters"):
		var box: Rect2 = f.hurt_box().grow(0.35)
		if box.has_point(here) and f.collect_orb(kind):
			Vfx.explosion(get_parent(), global_position, _color, 1.6)
			get_tree().call_group("sfx", "play", "pickup")
			queue_free()
			return
