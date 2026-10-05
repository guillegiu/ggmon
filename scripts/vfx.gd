extends RefCounted
# Efectos visuales. Siguen la receta de los efectos de referencia (tools/hots_fx.py):
# casi nada de malla y muchas capas de luz sumada: un nucleo, un resplandor suave,
# anillos de energia, chispas, estela y una luz. Todo sin texturas de archivo: el
# resplandor es un degrade radial generado al vuelo.

static var _glow: GradientTexture2D

# Partida online: el anfitrion anota cada efecto y sonido que dispara y se los manda al
# invitado, que los repite con replay(). Asi no hay que sincronizar los efectos uno por uno.
static var recording := false
static var events: Array = []


static func note(event: Array) -> void:
	if recording:
		events.append(event)


static func replay(parent: Node, event: Array) -> void:
	match event[0]:
		"spark":
			spark(parent, event[1], event[2], event[3])
		"ring":
			ring(parent, event[1], event[2], event[3], event[4], event[5])
		"burst":
			burst(parent, event[1], event[2], event[3], event[4], event[5])
		"light":
			flash_light(parent, event[1], event[2], event[3], event[4])
		"number":
			number(parent, event[1], event[2], event[3])


static func glow_texture() -> GradientTexture2D:
	if _glow == null:
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		g.add_point(0.35, Color(1.0, 1.0, 1.0, 0.45))
		_glow = GradientTexture2D.new()
		_glow.gradient = g
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 64
		_glow.height = 64
	return _glow


# Material de luz sumada. for_particles: el tamaño lo maneja el emisor.
static func glow_material(color: Color, for_particles: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = glow_texture()
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if for_particles else BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# Resplandor que siempre mira a la camara.
static func glow(parent: Node, color: Color, size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mi.mesh = q
	mi.material_override = glow_material(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * size
	parent.add_child(mi)
	return mi


# Solido que emite luz (nucleos, cristales).
static func emissive(color: Color, energy: float = 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.25
	return m


# Emisor de chispas. Sirve de estela (sigue al padre y deja las chispas atras) o de aura.
static func sparks(parent: Node, from: Color, to: Color, opts: Dictionary = {}) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = opts.get("amount", 24)
	p.lifetime = opts.get("life", 0.5)
	p.local_coords = opts.get("local", false)
	p.direction = opts.get("dir", Vector3.UP)
	p.spread = opts.get("spread", 180.0)
	p.initial_velocity_min = opts.get("speed", 0.6) * 0.4
	p.initial_velocity_max = opts.get("speed", 0.6)
	p.gravity = opts.get("gravity", Vector3.ZERO)
	if opts.has("radius"):
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = opts.radius
	var size: float = opts.get("size", 0.3)
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, from)
	ramp.set_color(1, Color(to.r, to.g, to.b, 0.0))
	p.color_ramp = ramp
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = glow_material(Color.WHITE, true)
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if opts.get("one_shot", false):
		p.one_shot = true
		p.explosiveness = 1.0
	parent.add_child(p)
	return p


# Estallido de chispas que se libera solo.
static func burst(parent: Node, pos: Vector3, color: Color, count: int = 16, speed: float = 5.0, size: float = 0.3) -> void:
	note(["burst", pos, color, count, speed, size])
	var p := sparks(parent, Color.WHITE.lerp(color, 0.4), color, {
		"amount": count, "life": 0.45, "speed": speed, "size": size, "one_shot": true, "gravity": Vector3(0.0, -6.0, 0.0)})
	p.global_position = pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(0.9)
	tw.tween_callback(p.queue_free)


# Destello redondo que crece y se apaga.
static func spark(parent: Node, pos: Vector3, color: Color, size: float = 0.6) -> void:
	note(["spark", pos, color, size])
	var mi := glow(parent, color, size * 0.6)
	mi.global_position = pos
	var mat: StandardMaterial3D = mi.material_override
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size * 3.2, 0.22).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.22)
	tw.chain().tween_callback(mi.queue_free)


# Onda expansiva: anillo fino de frente a la camara.
static func ring(parent: Node, pos: Vector3, color: Color, size: float = 1.5, time: float = 0.3, flat: bool = false) -> void:
	note(["ring", pos, color, size, time, flat])
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.42
	t.outer_radius = 0.5
	t.rings = 32
	t.ring_segments = 6
	mi.mesh = t
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	if not flat:
		mi.rotation.x = PI * 0.5
	mi.scale = Vector3.ONE * size * 0.2
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size * 2.0, time).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, time)
	tw.chain().tween_callback(mi.queue_free)


static func flash_light(parent: Node, pos: Vector3, color: Color, energy: float = 4.0, time: float = 0.25) -> void:
	note(["light", pos, color, energy, time])
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = 7.0
	parent.add_child(l)
	l.global_position = pos + Vector3(0.0, 0.0, 1.0)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, time)
	tw.tween_callback(l.queue_free)


# Explosion completa: destello, onda, chispas y luz.
static func explosion(parent: Node, pos: Vector3, color: Color, size: float = 1.5) -> void:
	spark(parent, pos, Color.WHITE.lerp(color, 0.5), size * 0.7)
	ring(parent, pos, color, size)
	burst(parent, pos, color, int(10 + size * 8), 3.0 + size * 2.5, 0.2 + size * 0.12)
	flash_light(parent, pos, color, 2.0 + size * 2.0)


static func number(parent: Node, pos: Vector3, value: float, color: Color) -> void:
	note(["number", pos, value, color])
	var l := Label3D.new()
	l.text = str(int(round(value)))
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 72
	l.outline_size = 16
	l.pixel_size = 0.007
	l.modulate = color
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position", pos + Vector3(0.0, 1.3, 0.0), 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(l.queue_free)
