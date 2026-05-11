const { WebSocketServer } = require('ws');
const { createSessionStore } = require('./session-store');
const { generateCode, normalizeCode } = require('./code-generator');

function sendJson(ws, obj) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
}

function sendError(ws, reason) {
  sendJson(ws, { type: 'error', reason });
}

function start(port, opts = {}) {
  const store = opts.store || createSessionStore({});
  const wss = new WebSocketServer({ port });
  wss._store = store;

  wss.on('connection', (ws) => {
    ws._role = null;       // 'host' | 'joiner'
    ws._peerId = null;
    ws._code = null;

    ws.on('message', (data) => {
      let msg;
      try { msg = JSON.parse(data.toString()); }
      catch { return sendError(ws, 'bad_json'); }

      switch (msg.type) {
        case 'host': {
          if (ws._role) return sendError(ws, 'already_host');
          // try a few times in case of (extremely unlikely) collision
          let code = null;
          for (let i = 0; i < 5 && !code; i++) {
            const candidate = generateCode();
            if (!store.getByCode(candidate)) code = candidate;
          }
          if (!code) return sendError(ws, 'server_busy');
          store.create(code, ws);
          ws._role = 'host';
          ws._peerId = 1;
          ws._code = code;
          return sendJson(ws, { type: 'code', code });
        }
        case 'join': {
          if (ws._role) return sendError(ws, 'already_joined');
          const code = normalizeCode(msg.code);
          if (!code) return sendError(ws, 'unknown_code');
          const session = store.getByCode(code);
          if (!session) return sendError(ws, 'unknown_code');
          if (session.started) return sendError(ws, 'in_progress');
          if (session.nextJoinerId > 8) return sendError(ws, 'full');

          const joinerId = session.nextJoinerId++;
          ws._role = 'joiner';
          ws._peerId = joinerId;
          ws._code = code;
          session.pendingJoiners.set(joinerId, ws);
          store.touch(session);

          const forward = { type: 'joiner', joinerId };
          if (typeof msg.reconnect_token === 'string') {
            forward.reconnect_token = msg.reconnect_token;
          }
          return sendJson(session.hostWs, forward);
        }
        case 'signal': {
          if (!ws._code) return sendError(ws, 'no_session');
          const session = store.getByCode(ws._code);
          if (!session) return sendError(ws, 'no_session');
          const to = msg.to;
          let target;
          if (to === 1) target = session.hostWs;
          else target = session.pendingJoiners.get(to);
          if (!target) return sendError(ws, 'unknown_peer');
          store.touch(session);
          return sendJson(target, {
            type: 'signal',
            from: ws._peerId,
            payload: msg.payload,
          });
        }
        default:
          return sendError(ws, 'unknown_type');
      }
    });

    ws.on('close', () => {
      // Filled in by Task 10.
    });
  });

  wss.on('listening', () => {
    console.log(`signaling server listening on :${wss.address().port}`);
  });

  return wss;
}

module.exports = { start };
