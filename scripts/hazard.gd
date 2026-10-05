extends Node3D
# Zona que queda un rato (nube de polvo, fuego en el suelo): a quien este adentro,
# menos a su dueño, le saca vida de a poco y puede volverlo lento. No interrumpe.

const Vfx = preload("res://scripts/vfx.gd")

var radius := 1.6
var life := 3.2
var tick_dmg := 3.0
var tick_frames := 24
var slow_frames := 60
var color := Color(0.5, 0.85, 1.0)
var owner_fighter: Node = null
var puppet := false         # partida online, lado del invitado: solo se dibuja

var _frame := 0
var _puffs: Array[MeshInstance3D] = []


func net_state() -> Array:
	return [get_instance_id(), global_position, radius, color]


func apply_net(_s: Array) -> void:
	pass


func _ready() -> void:
	add_to_group("hazards")
	for i in 5:
		var a := TAU * i / 5.0
		var puff := Vfx.glow(self, Color(color.r, color.g, color.b, 0.35), radius * 1.5)
		puff.position = Vector3(cos(a), sin(a) * 0.6, 0.0) * radius * 0.45
		_puffs.append(puff)
	Vfx.sparks(self, Color(1.0, 1.0, 1.0), color, {"amount": 40, "life": 0.9, "size": 0.22, "speed": 0.5, "radius": radius * 0.8, "local": true})
	scale = Vector3.ONE * 0.2
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.25).set_ease(Tween.EASE_OUT)


func _physics_process(delta: float) -> void:
	_frame += 1
	life -= delta
	for i in _puffs.size():
		var a := TAU * i / 5.0 + _frame * 0.02
		_puffs[i].position = Vector3(cos(a), sin(a) * 0.6, 0.0) * radius * 0.45
	if puppet:
		return
	if life <= 0.0:
		queue_free()
		return
	if life < 0.5:
		scale = Vector3.ONE * (life / 0.5)
	if _frame % tick_frames != 0:
		return
	var here := Vector2(global_position.x, global_position.y)
	for f in get_tree().get_nodes_in_group("fighters"):
		if f == owner_fighter:
			continue
		var c: Vector2 = f.hurt_box().get_center()
		if c.distance_to(here) < radius + 0.4:
			f.chip(tick_dmg, slow_frames)
			if is_instance_valid(owner_fighter):
				owner_fighter.add_gauge(tick_dmg * 1.6)
