// Manual end-to-end smoke test for the signaling server.
//
// Reproduces the full host -> join -> signal (offer) -> signal (answer) ->
// connected flow against a running server on ws://localhost:8080. Used during
// Task 14 verification of the signaling-server plan.
//
// Usage:
//   1. Start the server in another terminal:  node index.js
//      (set LOG_LEVEL=debug for verbose logs)
//   2. In this directory:  node scripts/smoke.js

const W = require('ws');

async function go() {
  const host = new W('ws://localhost:8080');
  await new Promise((r) => host.once('open', r));
  host.send(JSON.stringify({ type: 'host' }));
  const codeMsg = await new Promise((r) =>
    host.once('message', (d) => r(JSON.parse(d)))
  );
  console.log('host got code', codeMsg.code);

  const j = new W('ws://localhost:8080');
  await new Promise((r) => j.once('open', r));
  j.send(JSON.stringify({ type: 'join', code: codeMsg.code }));
  const joinerMsg = await new Promise((r) =>
    host.once('message', (d) => r(JSON.parse(d)))
  );
  console.log('host got joiner', joinerMsg);

  host.send(
    JSON.stringify({ type: 'signal', to: 2, payload: { sdp: 'OFFER' } })
  );
  const offerMsg = await new Promise((r) =>
    j.once('message', (d) => r(JSON.parse(d)))
  );
  console.log('joiner got offer', offerMsg);

  j.send(
    JSON.stringify({ type: 'signal', to: 1, payload: { sdp: 'ANSWER' } })
  );
  const answerMsg = await new Promise((r) =>
    host.once('message', (d) => r(JSON.parse(d)))
  );
  console.log('host got answer', answerMsg);

  j.send(JSON.stringify({ type: 'connected' }));
  await new Promise((r) => j.once('close', r));
  console.log('joiner closed after connected');

  host.close();
}

go().catch((e) => {
  console.error(e);
  process.exit(1);
});
