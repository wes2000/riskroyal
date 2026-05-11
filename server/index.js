const { start } = require('./src/server');

const port = parseInt(process.env.PORT, 10) || 8080;
const wss = start(port);

function shutdown(signal) {
  console.log(`received ${signal}, shutting down`);
  wss.close(() => {
    console.log('signaling server stopped');
    process.exit(0);
  });
  // Hard kill after 10s if close hangs
  setTimeout(() => process.exit(1), 10000).unref();
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
