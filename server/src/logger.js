const LEVELS = { error: 0, warn: 1, info: 2, debug: 3 };
const active = LEVELS[process.env.LOG_LEVEL] ?? LEVELS.info;

function log(level, event, fields = {}) {
  if (LEVELS[level] > active) return;
  const entry = { ts: new Date().toISOString(), level, event, ...fields };
  console.log(JSON.stringify(entry));
}

module.exports = {
  debug: (event, fields) => log('debug', event, fields),
  info:  (event, fields) => log('info', event, fields),
  warn:  (event, fields) => log('warn', event, fields),
  error: (event, fields) => log('error', event, fields),
};
