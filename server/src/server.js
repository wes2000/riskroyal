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
        // Filled in by Tasks 5–8.
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
