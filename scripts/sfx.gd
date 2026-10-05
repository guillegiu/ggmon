extends Node
# Sonido sintetizado al arrancar: no hay archivos de audio en el proyecto.
# Cada efecto es una o mas ondas con barrido de frecuencia y envolvente.
# Otros nodos lo usan con get_tree().call_group("sfx", "play", "<id>").

const Vfx = preload("res://scripts/vfx.gd")

const RATE := 22050
enum W { SINE, SQUARE, SAW, TRI, NOISE }

var streams := {}
var played := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("sfx")
	_rng.seed = 1234
	_build()
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	var amb := AudioStreamPlayer.new()
	amb.stream = _ambient()
	amb.volume_db = -10.0
	add_child(amb)
	amb.play()


func play(id: String, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	if not streams.has(id):
		push_warning("sfx desconocido: " + id)
		return
	played[id] = played.get(id, 0) + 1
	Vfx.note(["sfx", id, pitch])
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = streams[id]
	p.pitch_scale = pitch * _rng.randf_range(0.94, 1.06)
	p.volume_db = vol_db - 4.0
	p.play()


func _build() -> void:
	streams["jump"] = _stream(_tone(0.16, 300.0, 620.0, W.SINE, 0.5))
	streams["djump"] = _stream(_tone(0.14, 480.0, 960.0, W.TRI, 0.5))
	streams["flap"] = _stream(_tone(0.16, 900.0, 250.0, W.NOISE, 0.4, 1.5, 0.03))
	streams["land"] = _stream(_tone(0.09, 420.0, 140.0, W.NOISE, 0.35))
	streams["swing"] = _stream(_tone(0.11, 1900.0, 600.0, W.NOISE, 0.25, 1.5, 0.02))
	streams["hit"] = _stream(_mix([[_tone(0.12, 950.0, 200.0, W.NOISE, 0.7), 0.0], [_tone(0.12, 180.0, 70.0, W.SQUARE, 0.35), 0.0]]))
	streams["heavy"] = _stream(_mix([[_tone(0.28, 700.0, 90.0, W.NOISE, 0.8), 0.0], [_tone(0.28, 130.0, 40.0, W.SQUARE, 0.45), 0.0]]))
	streams["block"] = _stream(_mix([[_tone(0.09, 950.0, 720.0, W.TRI, 0.5), 0.0], [_tone(0.05, 1500.0, 1400.0, W.SQUARE, 0.2), 0.0]]))
	streams["fire"] = _stream(_mix([[_tone(0.24, 520.0, 140.0, W.SAW, 0.35), 0.0], [_tone(0.24, 1400.0, 300.0, W.NOISE, 0.35), 0.0]]))
	streams["ice"] = _stream(_mix([[_tone(0.16, 1400.0, 2500.0, W.SINE, 0.35), 0.0], [_tone(0.12, 2100.0, 3300.0, W.TRI, 0.25), 0.05]]))
	streams["spit"] = _stream(_tone(0.07, 950.0, 380.0, W.SQUARE, 0.3))
	streams["explode"] = _stream(_mix([[_tone(0.42, 520.0, 55.0, W.NOISE, 0.8), 0.0], [_tone(0.3, 90.0, 35.0, W.SINE, 0.5), 0.0]]))
	streams["dash"] = _stream(_tone(0.2, 600.0, 2500.0, W.NOISE, 0.4, 1.0, 0.05))
	streams["stomp"] = _stream(_mix([[_tone(0.5, 110.0, 32.0, W.SINE, 0.9), 0.0], [_tone(0.3, 320.0, 60.0, W.NOISE, 0.6), 0.0]]))
	streams["ko"] = _stream(_tone(0.6, 420.0, 55.0, W.SQUARE, 0.4, 1.0))
	streams["pickup"] = _stream(_mix([[_tone(0.1, 880.0, 880.0, W.SINE, 0.45), 0.0], [_tone(0.18, 1320.0, 1320.0, W.SINE, 0.45), 0.08]]))
	streams["orb"] = _stream(_mix([[_tone(0.3, 660.0, 660.0, W.SINE, 0.25, 1.5, 0.05), 0.0], [_tone(0.3, 990.0, 990.0, W.SINE, 0.15, 1.5, 0.05), 0.0]]))
	var arp := []
	var notes := [392.0, 523.3, 659.3, 784.0, 1046.5, 1318.5]
	for i in notes.size():
		arp.append([_tone(0.22, notes[i], notes[i], W.TRI, 0.35, 1.5), i * 0.08])
	arp.append([_tone(0.7, 300.0, 2600.0, W.NOISE, 0.12, 0.6, 0.3), 0.0])
	streams["evolve"] = _stream(_mix(arp))
	streams["revert"] = _stream(_tone(0.35, 900.0, 220.0, W.TRI, 0.35, 1.2))


# Barrido exponencial de f0 a f1. decay es el exponente de la caida de volumen.
func _tone(dur: float, f0: float, f1: float, wave: int, vol: float, decay: float = 2.0, attack: float = 0.004) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var held := 0.0
	var ratio := f1 / f0
	for i in n:
		var t := float(i) / n
		phase += f0 * pow(ratio, t) / RATE
		if phase >= 1.0:
			phase = fmod(phase, 1.0)
			held = _rng.randf_range(-1.0, 1.0)
		var s := 0.0
		match wave:
			W.SINE:
				s = sin(phase * TAU)
			W.SQUARE:
				s = 1.0 if phase < 0.5 else -1.0
			W.SAW:
				s = phase * 2.0 - 1.0
			W.TRI:
				s = absf(phase * 4.0 - 2.0) - 1.0
			W.NOISE:
				s = held
		var env := minf(float(i) / (attack * RATE), 1.0) * pow(1.0 - t, decay)
		out[i] = s * env * vol
	return out


# parts: lista de [muestras, desfase en segundos].
func _mix(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for part in parts:
		var src: PackedFloat32Array = part[0]
		var off := int(float(part[1]) * RATE)
		if out.size() < off + src.size():
			out.resize(off + src.size())
		for i in src.size():
			out[off + i] += src[i]
	return out


func _stream(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = data
	if loop:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = samples.size()
	return st


# Ambiente de selva en bucle de 6 s: viento, grillos y algunos pajaros.
# Los periodos dividen exacto la duracion para que el bucle no haga clic.
func _ambient() -> AudioStreamWAV:
	var n := int(6.0 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.04
		var wind := lp * (0.55 + 0.25 * sin(t * TAU / 3.0))
		var gate := 1.0 if fmod(t * 22.0, 1.0) < 0.5 else 0.0
		var burst := 1.0 if fmod(t, 2.0) < 1.1 else 0.0
		out[i] = wind * 0.5 + sin(t * TAU * 4300.0) * gate * burst * 0.03
	var chirps := [[0.6, 2100.0, 3000.0], [0.75, 2300.0, 3200.0], [0.9, 2100.0, 3000.0], [3.4, 1500.0, 2500.0], [3.62, 2600.0, 1800.0], [4.9, 2800.0, 3600.0], [5.02, 2800.0, 3600.0]]
	for c in chirps:
		var src := _tone(0.09, c[1], c[2], W.SINE, 0.1, 1.0, 0.01)
		var off := int(float(c[0]) * RATE)
		for i in src.size():
			out[off + i] += src[i]
	return _stream(out, true)
