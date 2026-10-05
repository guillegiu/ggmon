extends Node
# Conexion con el servidor de salas (server/index.js) por WebSocket.
# El servidor solo junta a dos jugadores por codigo y reenvia lo que manda cada uno.
# Mensajes de texto (JSON) = control de sala; binarios (var_to_bytes) = trafico del juego.

signal room_created(code: String)       # sos el anfitrion y la sala esta abierta
signal paired                           # ya hay dos jugadores en la sala
signal peer_left
signal failed(reason: String)
signal message(data: Dictionary)

# Direccion del servidor de salas publico (wss://...). Vacia = todavia no hay uno desplegado.
const PUBLIC_URL := ""
const LOCAL_URL := "ws://localhost:8787"

var is_host := false
var code := ""
var is_paired := false
var _ws: WebSocketPeer = null
var _hello := {}
var _open := false


# Donde conectarse si el jugador no escribe otra cosa.
static func default_url() -> String:
	if OS.has_feature("web"):
		var host: String = str(JavaScriptBridge.eval("location.host"))
		var secure: bool = str(JavaScriptBridge.eval("location.protocol")) == "https:"
		# Publicado en GitHub Pages no hay servidor propio: se usa el publico.
		if host.ends_with("github.io"):
			return PUBLIC_URL
		# Si la pagina la sirve el servidor de salas (red local), es esa misma maquina.
		return ("wss://" if secure else "ws://") + host
	return LOCAL_URL


func open(url: String, as_host: bool, room_code: String) -> void:
	close()
	if url.strip_edges() == "":
		failed.emit("No hay servidor de salas configurado")
		return
	is_host = as_host
	code = room_code.to_upper()
	_hello = {"t": "create" if as_host else "join", "code": code}
	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url(url.strip_edges())
	if err != OK:
		_ws = null
		failed.emit("No se pudo conectar al servidor")


func close() -> void:
	if _ws != null:
		_ws.close()
	_ws = null
	_open = false
	is_paired = false


func send(data: Dictionary) -> void:
	if _ws != null and is_paired and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send(var_to_bytes(data))


func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _open:
			_open = true
			_ws.send_text(JSON.stringify(_hello))
		while _ws != null and _ws.get_available_packet_count() > 0:
			var pkt := _ws.get_packet()
			if _ws.was_string_packet():
				_control(pkt.get_string_from_utf8())
			else:
				var data: Variant = bytes_to_var(pkt)
				if data is Dictionary:
					message.emit(data)
	elif state == WebSocketPeer.STATE_CLOSED:
		var was_paired := is_paired
		var was_open := _open
		close()
		if was_paired:
			peer_left.emit()
		else:
			failed.emit("Se corto la conexion con el servidor" if was_open else "No se pudo conectar al servidor")


func _control(text: String) -> void:
	var msg: Variant = JSON.parse_string(text)
	if not msg is Dictionary:
		return
	match msg.get("t", ""):
		"created":
			room_created.emit(code)
		"joined", "peer_joined":
			is_paired = true
			paired.emit()
		"peer_left":
			is_paired = false
			peer_left.emit()
		"error":
			var reason: String = msg.get("msg", "Error del servidor")
			close()
			failed.emit(reason)
