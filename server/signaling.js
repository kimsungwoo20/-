// 개미 RTS 연결 중개 서버.
// 게임 자체는 방장 브라우저가 계산하고, 참가자는 방장과 브라우저끼리 직접(WebRTC) 연결한다.
// 이 서버는 처음 연결할 때 서로의 연결 정보(offer / answer / candidate)를 전달하는 일만 한다.
//
// 실행: npm install && PORT=9080 node signaling.js
//
// 메시지(JSON):
//   방장 → {t:"host"}                     ← {t:"room", code, id:1}
//   참가자 → {t:"join", code}              ← {t:"joined", id}   (방장에게는 {t:"peer", id})
//   서로 → {t:"offer"|"answer"|"cand", to, ...}  → 받는 쪽에 from 을 붙여 그대로 전달
//   방장이 나가면 참가자에게 {t:"closed"}, 참가자가 나가면 방장에게 {t:"peer_left", id}
const { WebSocketServer } = require("ws");

const PORT = Number(process.env.PORT || 9080);
const MAX_PEERS = 5;
const rooms = new Map();   // code -> {host: ws, peers: Map(id -> ws), next: 2}

function code4() {
  const letters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let c;
  do {
    c = Array.from({ length: 4 }, () => letters[Math.floor(Math.random() * letters.length)]).join("");
  } while (rooms.has(c));
  return c;
}

function send(ws, msg) {
  if (ws && ws.readyState === 1) ws.send(JSON.stringify(msg));
}

const wss = new WebSocketServer({ port: PORT });
wss.on("connection", (ws) => {
  ws.room = null;
  ws.id = 0;
  ws.on("message", (raw) => {
    let m;
    try { m = JSON.parse(raw); } catch { return; }
    if (m.t === "host" && !ws.room) {
      const code = code4();
      rooms.set(code, { host: ws, peers: new Map(), next: 2 });
      ws.room = code;
      ws.id = 1;
      send(ws, { t: "room", code, id: 1 });
    } else if (m.t === "join" && !ws.room) {
      const code = String(m.code || "").toUpperCase().trim();
      const room = rooms.get(code);
      if (!room) return send(ws, { t: "error", msg: "방을 찾을 수 없습니다" });
      if (room.peers.size >= MAX_PEERS - 1) return send(ws, { t: "error", msg: "방이 가득 찼습니다" });
      const id = room.next++;
      room.peers.set(id, ws);
      ws.room = code;
      ws.id = id;
      send(ws, { t: "joined", id, code });
      send(room.host, { t: "peer", id });
    } else if (["offer", "answer", "cand"].includes(m.t) && ws.room) {
      const room = rooms.get(ws.room);
      if (!room) return;
      const target = m.to === 1 ? room.host : room.peers.get(m.to);
      send(target, { ...m, from: ws.id });
    }
  });
  ws.on("close", () => {
    const room = rooms.get(ws.room);
    if (!room) return;
    if (ws.id === 1) {
      for (const p of room.peers.values()) send(p, { t: "closed" });
      rooms.delete(ws.room);
    } else {
      room.peers.delete(ws.id);
      send(room.host, { t: "peer_left", id: ws.id });
    }
  });
});
console.log(`signaling server on :${PORT}`);
