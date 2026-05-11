const { start } = require('../src/server');

async function startTestServer(opts = {}) {
  const wss = start(0, opts); // port 0 = pick a free one
  await new Promise((resolve) => wss.once('listening', resolve));
  const port = wss.address().port;
  return {
    port,
    close: () => new Promise((resolve) => wss.close(resolve)),
    store: wss._store,
  };
}

module.exports = { startTestServer };
