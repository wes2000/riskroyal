# Risk Royal Signaling Server

WebSocket server that brokers WebRTC handshakes between game clients using 6-character codes.

## Run locally

    npm install
    npm start          # listens on :8080 by default; PORT env var overrides

Set `LOG_LEVEL=debug` for verbose handshake tracing.

## Run tests

    npm test

## Deploy to Fly.io

One-time setup:

    flyctl auth login
    flyctl apps create riskroyal

Deploy:

    flyctl deploy

Logs:

    flyctl logs

The default `fly.toml` uses the smallest shared VM (256 MB) and auto-stops when idle. WebSocket traffic is upgraded HTTP, so the `http_service` block covers it; TLS terminates at Fly's load balancer.

`kill_timeout = "15s"` gives the server's 10s graceful-shutdown hard-kill timer (in `index.js`) time to drain existing connections before Fly sends SIGKILL.

After deploy, the signaling URL for the Godot client is:

    wss://riskroyal.fly.dev

(The Fly app is named `riskroyal`; URL = `wss://<app>.fly.dev`.)

(Update the Godot client's `NetConfig.SIGNALING_URL` once deployed.)
