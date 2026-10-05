// Servidor de salas de GGmon.
// Hace dos cosas:
//   1. Relay: junta de a dos jugadores por codigo de sala y le reenvia a cada uno lo que
//      manda el otro. No entiende el juego: el que crea la sala es quien lo simula.
//   2. Sirve la version web (build/web) por HTTP, para jugar en red local: los dos
//      entran con el navegador a http://<ip de esta maquina>:8787
// Uso: node index.js            (puerto 8787, o el de la variable PORT)
const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8787;
const WEB = path.join(__dirname, '..', 'build', 'web');
const MIME = {
  '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream', '.png': 'image/png', '.ico': 'image/x-icon', '.json': 'application/json',
};

// codigo -> { host, guest }
const rooms = new Map();

const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0]);
  const file = path.normalize(path.join(WEB, url === '/' ? 'index.html' : url));
  // nada fuera de la carpeta de la version web
  if (!file.startsWith(WEB) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    res.writeHead(url === '/' ? 200 : 404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end(url === '/' ? `Servidor de salas de GGmon activo. Salas abiertas: ${rooms.size}\n` : 'No encontrado\n');
    return;
  }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});

const wss = new WebSocketServer({ server });

function tell(ws, obj) {
  if (ws && ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
}

function other(ws) {
  const room = rooms.get(ws.room);
  if (!room) return null;
  return ws.role === 'host' ? room.guest : room.host;
}

wss.on('connection', (ws) => {
  ws.room = null;
  ws.role = null;
  ws.alive = true;
  ws.on('pong', () => { ws.alive = true; });

  ws.on('message', (data, isBinary) => {
    // Lo binario es trafico del juego: se reenvia tal cual al otro jugador.
    if (isBinary) {
      const peer = other(ws);
      if (peer && peer.readyState === peer.OPEN) peer.send(data, { binary: true });
      return;
    }
    let msg;
    try { msg = JSON.parse(data.toString()); } catch { return; }
    const code = String(msg.code || '').toUpperCase().slice(0, 12);
    if (ws.room || !code) return;
    if (msg.t === 'create') {
      if (rooms.has(code)) return tell(ws, { t: 'error', msg: 'Ya hay una sala con ese codigo' });
      rooms.set(code, { host: ws, guest: null });
      ws.room = code;
      ws.role = 'host';
      tell(ws, { t: 'created', code });
    } else if (msg.t === 'join') {
      const room = rooms.get(code);
      if (!room) return tell(ws, { t: 'error', msg: 'No existe una sala con ese codigo' });
      if (room.guest) return tell(ws, { t: 'error', msg: 'La sala ya esta llena' });
      room.guest = ws;
      ws.room = code;
      ws.role = 'guest';
      tell(ws, { t: 'joined', code });
      tell(room.host, { t: 'peer_joined' });
    }
  });

  ws.on('close', () => {
    const room = rooms.get(ws.room);
    if (!room) return;
    tell(other(ws), { t: 'peer_left' });
    if (ws.role === 'host') {
      // sin quien simule no hay partida: la sala se cierra
      if (room.guest) room.guest.room = null;
      rooms.delete(ws.room);
    } else {
      room.guest = null;
    }
  });
});

// Corta las conexiones que dejaron de responder.
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.alive) { ws.terminate(); continue; }
    ws.alive = false;
    ws.ping();
  }
}, 30000);

server.listen(PORT, () => {
  console.log(`GGmon: servidor de salas en el puerto ${PORT}`);
  console.log(fs.existsSync(WEB) ? `Sirviendo la version web desde ${WEB}` : 'Sin version web exportada (build/web): solo salas.');
});
