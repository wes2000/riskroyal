const { WebSocketServer } = require('ws');

function start(port) {
  const wss = new WebSocketServer({ port });
  wss.on('connection', (ws) => {
    ws.on('message', (data) => {
      // Filled in by later tasks.
    });
  });
  console.log(`signaling server listening on :${port}`);
  return wss;
}

module.exports = { start };
