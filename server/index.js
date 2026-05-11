const { start } = require('./src/server');

const port = parseInt(process.env.PORT, 10) || 8080;
start(port);
