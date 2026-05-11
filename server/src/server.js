const { WebSocketServer } = require('ws');
const { createSessionStore } = require('./session-store');
const { generateCode, normalizeCode } = require('./code-generator');
const log = require('./logger');

function sendJson(ws, obj) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
}

function sendError(ws, reason) {
  sendJson(ws, { type: 'error', reason });
}

function start(port, opts = {}) {
  const store = opts.store || createSessionStore({});
  const wss = new WebSocketServer({ port, maxPayload: 64 * 1024 });
  wss._store = store;
  const pruneInterval = setInterval(() => store.pruneExpired(), 60000);
  wss.on('close', () => clearInterval(pruneInterval));

  wss.on('connection', (ws) => {
    ws._role = null;       // 'host' | 'joiner'
    ws._peerId = null;
    ws._code = null;

    // Swallow socket-level errors (e.g. oversized payload triggers a
    // RangeError that ws emits as 'error' before closing the connection).
    // The 'close' handler below still runs and does the real cleanup.
    ws.on('error', (err) => {
      log.warn('socket_error', { message: err && err.message });
    });

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
          log.info('host_issued', { code });
          return sendJson(ws, { type: 'code', code });
        }
        case 'join': {
          if (ws._role) {
            log.warn('join_rejected', { code: msg.code, reason: 'already_joined' });
            return sendError(ws, 'already_joined');
          }
          const code = normalizeCode(msg.code);
          if (!code) {
            log.warn('join_rejected', { code: msg.code, reason: 'unknown_code' });
            return sendError(ws, 'unknown_code');
          }
          const session = store.getByCode(code);
          if (!session) {
            log.warn('join_rejected', { code: msg.code, reason: 'unknown_code' });
            return sendError(ws, 'unknown_code');
          }
          if (session.started) {
            log.warn('join_rejected', { code: msg.code, reason: 'in_progress' });
            return sendError(ws, 'in_progress');
          }
          if (session.nextJoinerId > 8) {
            log.warn('join_rejected', { code: msg.code, reason: 'full' });
            return sendError(ws, 'full');
          }

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
          log.info('join_accepted', { code, joinerId, reconnect: !!msg.reconnect_token });
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
          log.debug('signal_relayed', { from: ws._peerId, to: msg.to });
          return sendJson(target, {
            type: 'signal',
            from: ws._peerId,
            payload: msg.payload,
          });
        }
        case 'connected': {
          if (!ws._code) return; // silently ignore
          const session = store.getByCode(ws._code);
          if (!session) return;

          log.debug('connected', { peerId: ws._peerId });
          if (ws._role === 'joiner') {
            session.pendingJoiners.delete(ws._peerId);
            ws.close();
          } else if (ws._role === 'host') {
            const target = session.pendingJoiners.get(msg.peerId);
            if (target) {
              session.pendingJoiners.delete(msg.peerId);
              target.close();
            }
          }
          return;
        }
        case 'start_match': {
          if (ws._role !== 'host') return sendError(ws, 'not_host');
          const session = store.getByCode(ws._code);
          if (!session) return sendError(ws, 'no_session');
          session.started = true;
          log.info('match_started', { code: session.code });
          return sendJson(ws, { type: 'match_started' });
        }
        default:
          return sendError(ws, 'unknown_type');
      }
    });

    ws.on('close', () => {
      if (!ws._code) return;
      const session = store.getByCode(ws._code);
      if (!session) return;

      if (ws._role === 'host') {
        log.info('host_disconnect', { code: ws._code });
        // Notify any pending joiners (they're mid-handshake; tell them it's over)
        for (const [, jWs] of session.pendingJoiners) {
          sendJson(jWs, { type: 'host_left' });
          jWs.close();
        }
        store.remove(session.code);
      } else if (ws._role === 'joiner') {
        if (session.pendingJoiners.delete(ws._peerId)) {
          log.info('joiner_disconnect', { code: ws._code, joinerId: ws._peerId });
          sendJson(session.hostWs, { type: 'joiner_left', joinerId: ws._peerId });
        }
      }
    });
  });

  wss.on('listening', () => {
    log.info('listening', { port: wss.address().port });
  });

  return wss;
}

module.exports = { start };
