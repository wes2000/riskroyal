function createSessionStore({ clock = () => Date.now(), ttlMs = 600000 } = {}) {
  const sessions = new Map(); // code -> session

  function create(code, hostWs) {
    if (sessions.has(code)) return null;
    const session = {
      code,
      hostWs,
      nextJoinerId: 2,         // 1 is the host
      pendingJoiners: new Map(), // joinerId -> joinerWs (during handshake only)
      lastActivityAt: clock(),
      started: false,           // becomes true when host signals match start
    };
    sessions.set(code, session);
    return session;
  }

  function getByCode(code) {
    return sessions.get(code) || null;
  }

  function remove(code) {
    return sessions.delete(code);
  }

  function touch(session) {
    session.lastActivityAt = clock();
  }

  function pruneExpired() {
    const cutoff = clock() - ttlMs;
    const removed = [];
    for (const [code, s] of sessions) {
      if (s.lastActivityAt < cutoff) {
        sessions.delete(code);
        removed.push(code);
      }
    }
    return removed;
  }

  function size() { return sessions.size; }

  return { create, getByCode, remove, touch, pruneExpired, size };
}

module.exports = { createSessionStore };
