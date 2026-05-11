# Networking & Lobby Foundation — Design Spec

**Project:** Risk Royal (Godot 4.6)
**Sub-project:** #1 of ~7 — Networking & Lobby Foundation
**Date:** 2026-05-10
**Status:** Approved for planning

---

## 1. Context

Risk Royal is a multiplayer party battle casino game (full design in [`docs/RiskRoyal_DesignDoc.md`](../../RiskRoyal_DesignDoc.md)). The MVP scope (design doc §26) covers a 4-player online lobby, three mini-games, a power-card system, an economy, House Twists, and a shop.

That scope is too large for a single spec. The MVP has been decomposed into ~7 sub-projects, each with its own spec → plan → implementation cycle:

1. **Networking & Lobby Foundation** ← this spec
2. Match Loop & Economy Core
3. Rocket Clash (first event, validates the event contract)
4. Power Cards & Bounties
5. Bomb Pot + Card Cannon (events 2 and 3)
6. House Twists
7. Polish pass (announcer, painful reveals, results juice, spectator behavior)

This sub-project delivers the connection layer and the lobby UI that every later sub-project assumes.

## 2. Goals

- A player can host a session and receive a short shareable code.
- Another player can enter that code and join the host's lobby.
- 2–8 players can populate a lobby with name + color, ready up, and have the host start the match.
- Mid-lobby and mid-match disconnects pause for 30s before continuing without the dropped player.
- Host disconnect ends the match cleanly for everyone.
- The lobby produces a well-defined `MatchStart` handoff that sub-project #2 will consume.

## 3. Non-Goals

- No match logic, no events, no economy, no power cards. This sub-project ends at the moment the host clicks Start.
- No mode/rules picker UI. `MatchStart.rules` is a placeholder dict that #2 will populate.
- No TURN server. Strict-NAT cases fail with a clear error message; documented as a known limitation.
- No public lobby browser. Private codes only.
- No in-lobby chat.
- No persistence (no accounts, no save files, no stats).
- No host migration. Host loss = match abandoned.
- No anti-cheat. Host is trusted by design (party game with friends).
- No spectator join. Players in a match are fixed at match start.
- No web export. Desktop only (Windows / Mac / Linux).

## 4. Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Platform | Desktop only | Smallest scope; ENet or WebRTC both viable. Web export deferred. |
| Connectivity | Lightweight signaling server + P2P | Cheap to host, low latency, friends-party-game fit. |
| Transport | `WebRTCMultiplayerPeer` | Built-in ICE/STUN handles most NAT cases; future-proof for web export. |
| Player count | 2–8 from day one | Design relies on 4–6 sweet spot; avoid rework. |
| Lobby scope | Standard | Name + color + ready/start + host-kick. Defer mode picker, chat, public browser. |
| Client drop | Pause for everyone, 30s grace | Preserves dropped player's match for typical flaky-connection reconnects. |
| Host drop | Same pause, abandon if no return | Consistent with client behavior; avoids host-migration complexity. |
| Authority | Host-authoritative | Required by hidden-state design (crash points, bomb timers, vault depths). |
| Signaling tech | Node.js + `ws` | Tiny, well-known, free-tier-friendly. |
| Signaling host | Free PaaS (Fly.io or Render) | $0 at MVP traffic; minimal ops. |

## 5. Architecture

Two deployable artifacts.

### 5.1 Signaling Server (`server/`)

Node.js process running `ws`. Stateless beyond an in-memory `code → host_session` map. Single file, ~200 LOC. Free-tier PaaS deployment.

Responsibilities, in full:
1. Issue/look up 6-character join codes.
2. Relay SDP offers/answers and ICE candidates between the host and each joining peer during connection setup.
3. Drop both connections once peers report `connected`.

**The server never sees match traffic and never knows anything about game state.** It is purely a connection broker. A server restart breaks new joins but does not affect already-established P2P matches.

### 5.2 Godot Client (`game/`)

Single executable. Can act as host or client (same binary). Layered internally:

- **Transport layer** — `WebRTCMultiplayerPeer`, hidden behind a thin facade (`WebRTCTransport.gd`). Keeps WebRTC API from leaking through the rest of the codebase; enables future transport swap (ENet, Nakama, Steam) without ripple changes.
- **Signaling layer** — `SignalingClient.gd`. WebSocket to the signaling server. Owns the join-code lifecycle and SDP/ICE exchange. Disconnects from signaling once the peer connection is live.
- **Session layer** — `NetSession.gd` autoload singleton. Owns the active multiplayer peer, player ID assignment, the authoritative player list, and the lobby-vs-match state flag. Single source of truth other systems read from.
- **Lobby UI layer** — `LobbyScene.tscn` + `lobby_scene.gd`. Pure UI consumer of `NetSession`. Knows nothing about WebRTC, signaling, or networking primitives.
- **Match handoff contract** — `MatchStart.gd`, a small data class. The lobby produces it; sub-project #2 consumes it.

### 5.3 Authority Model

Host runs the simulation. Clients send inputs via RPCs to the host; host validates and broadcasts state. Hidden values (crash points, bomb timers, vault depths) live only on the host until reveal. This sub-project doesn't implement any of that simulation — it establishes the channel and ID model that #2 will build on.

## 6. Components

Each component below specifies **what it does**, **public interface**, **what it depends on**.

### 6.1 Signaling Server (`server/index.js`)

**What it does:** Brokers WebRTC handshakes between hosts and joiners using short codes. Holds no game state.

**WebSocket JSON protocol:**

| Direction | Message | Reply / Effect |
|---|---|---|
| Client → server | `{type: "host"}` | `{type: "code", code: "ABC234"}` |
| Client → server | `{type: "join", code: "ABC234", reconnect_token?: "..."}` | Forwarded to host as `{type: "joiner", joinerId: N, reconnect_token?: "..."}`. Replies `{type: "error", reason}` to joiner on `unknown_code` / `full` / `in_progress`. `reconnect_token` is optional and present only on reconnect attempts. |
| Bidirectional | `{type: "signal", to: peerId, payload: {...}}` | Opaque relay. Server does not parse payload. |
| Client → server | `{type: "connected", peerId: N}` | Server stops relaying for that pair. |

**Code format:** 6-char Crockford base32. Excludes ambiguous chars (`0/O`, `1/I`, `L`, `U`). Case-insensitive on input.

**Code lifecycle:** Issued on `host`. Expires after 10 minutes of host-inactivity (no incoming `signal` or `connected`). On host WebSocket close, code freed immediately.

**Capacity:** One Node process easily handles thousands of concurrent handshakes — each is short-lived (seconds), not persistent. No DB, no Redis, no auth.

**Depends on:** `ws` npm package.

### 6.2 `WebRTCTransport.gd` (transport facade)

**What it does:** Wraps `WebRTCMultiplayerPeer` and exposes only what the rest of the game needs. Translates Godot's WebRTC events into the smaller `NetSession` API.

**Public interface:**
- `start_host() -> void`
- `start_client(host_offer: Dictionary) -> void`
- `add_peer_via_signaling(joiner_id: int) -> void`
- Signals: `peer_joined(id: int)`, `peer_left(id: int)`, `transport_failed(reason: String)`

No SDP/ICE structures leak past this boundary.

**Depends on:** Godot's built-in WebRTC module.

### 6.3 `SignalingClient.gd`

**What it does:** Maintains the WebSocket connection to the signaling server during connection setup. Issues `host` or `join` and pipes SDP/ICE between the server and `WebRTCTransport`. Closes itself once `transport_failed` or all peers report `connected`.

**Public interface:**
- `request_code() -> String` (async via signal)
- `connect_to_code(code: String) -> bool` (async via signal)
- Signals: `code_issued(code: String)`, `peer_arriving(joiner_id: int)`, `signaling_error(reason: String)`

**Depends on:** `WebRTCTransport` (to know when to stop relaying), `WebSocketPeer` (Godot built-in).

### 6.4 `NetSession.gd` (autoload singleton)

**What it does:** Authoritative client-side view of "who is in this session." Owns the player list, `is_host`, `local_peer_id`, `state` (one of `idle` / `lobby` / `match` / `paused`). Provides RPCs for lobby actions.

**Public interface:**
- Properties:
  - `players: Array[PlayerSlot]`
  - `is_host: bool`
  - `local_peer_id: int`
  - `state: State` (enum: `IDLE`, `LOBBY`, `MATCH`, `PAUSED`)
  - `pre_pause_state: State` (which state to return to when `PAUSED` resolves; only meaningful while `state == PAUSED`)
- Methods:
  - `host_session() -> void`
  - `join_session(code: String) -> void`
  - `leave_session() -> void`
  - `set_ready(value: bool) -> void`
  - `set_color(index: int) -> void`
  - `kick(peer_id: int) -> void` (host-only)
  - `start_match() -> void` (host-only)
- Signals:
  - `players_changed()`
  - `state_changed(new_state: State)`
  - `match_starting(match_start: MatchStart)`
  - `session_ended(reason: String)`

**Depends on:** `WebRTCTransport`, `SignalingClient`. Nothing else in the project depends on Godot's `MultiplayerAPI` directly — only through `NetSession`.

### 6.5 `PlayerSlot.gd` (data class)

**What it does:** One player's lobby/match identity.

**Fields:** `peer_id: int`, `name: String`, `color_index: int`, `ready: bool`, `is_host: bool`, `connected: bool`, `seat_index: int`.

Plain data, no logic. Serializable via Godot's built-in dictionary conversion for RPC transport.

### 6.6 `LobbyScene.tscn` + `lobby_scene.gd`

**What it does:** UI for the lobby.

**Sub-views:**
- Main menu: Host button, Join button (opens code-entry dialog).
- Join dialog: code text field (6 chars, auto-uppercase), Join/Cancel.
- Lobby view: shows the issued code prominently (host only), 8 player slots (occupied or empty — slot count is fixed at 8 for MVP, matching the design doc's 2–8 range), local player's name field + color picker, ready toggle, Start button (host only, disabled unless ≥2 players and all ready), per-slot Kick button (host only, not on host's own slot).
- Pause overlay: shown when `state == PAUSED`, displays which player dropped and a 30s countdown.

All state read from `NetSession` signals. Pure consumer.

**Depends on:** `NetSession`. Nothing else.

### 6.7 Test-support files (deliverables alongside production code)

- `tests/fakes/FakeTransport.gd` — implements the same signals as `WebRTCTransport` (`peer_joined`, `peer_left`, `transport_failed`) without a real WebRTC peer. Used by Tier 2 tests.
- `tests/fakes/FakeSignalingClient.gd` — same signals as `SignalingClient`, no real WebSocket.

### 6.8 `MatchStart.gd` (data class, contract for sub-project #2)

**What it does:** Handoff payload from lobby to match scene.

**Fields:**
- `seats: Array[PlayerSlot]` (locked seat indices, names, colors, peer IDs)
- `host_peer_id: int`
- `rng_seed: int` (host generates via `randi()`)
- `mode: String` (placeholder — for MVP, hardcoded `"quick_clash"`)
- `rules: Dictionary` (empty for MVP, ready for #2 to populate)

## 7. Data Flow

### 7.1 Hosting a session

```
Player clicks "Host"
  → NetSession.host_session()
  → SignalingClient opens WebSocket to signaling server
  → sends {type: "host"}
  → receives {type: "code", code: "QX7K2P"}
  → NetSession.is_host = true, state = LOBBY
  → WebRTCTransport.start_host()
  → LobbyScene displays code "QX7K2P"
```

### 7.2 Joining a session

```
Player enters code "QX7K2P", clicks "Join"
  → NetSession.join_session("QX7K2P")
  → SignalingClient sends {type: "join", code: "QX7K2P"}
  → Server forwards {type: "joiner", joinerId: 2} to host's WebSocket
  → Host creates SDP offer via WebRTCTransport, sends through signaling
  → Joiner receives offer, creates answer, sends back through signaling
  → ICE candidates relayed both ways until peer connection establishes
  → Both peers send {type: "connected"} to signaling server
  → SignalingClient closes WebSocket on both ends
  → Host: WebRTCTransport.peer_joined(2) fires
  → NetSession appends provisional PlayerSlot for peer 2 (empty name, gray color)
  → Host broadcasts updated player list via RPC to all peers
  → All clients fire players_changed
  → LobbyScene shows the new slot
  → New joiner submits name + color via RPC to host
  → Host validates (no duplicate colors, name length OK), updates list, rebroadcasts
```

### 7.3 Lobby state sync — canonical pattern

The host owns the player list. Clients never mutate it directly; they send intent RPCs to the host, the host validates and broadcasts new state. Same pattern for all lobby actions.

```
Client wants to toggle ready:
  → NetSession.set_ready(true) on client
  → RPC: request_set_ready(true) to host (reliable, host-only)
  → Host validates (player exists, in LOBBY state) and updates list
  → Host broadcasts: rpc_sync_player_list(serialized_list) to all peers
  → All clients (including host) apply, emit players_changed
```

Same pattern for `set_color`, `kick`, `start_match`. Unidirectional flow → host is the only source of truth → no client-side prediction needed for lobby actions.

### 7.4 Match start handoff

```
Host clicks Start (only enabled when all players ready and count ≥ 2):
  → NetSession.start_match()
  → Host builds MatchStart { seats, host_peer_id, rng_seed = randi(), mode, rules }
  → rpc_start_match(MatchStart) to all peers (reliable)
  → All clients receive MatchStart
  → NetSession.state → MATCH, emits match_starting(match_start)
  → LobbyScene unloads
  → Sub-project #2's match scene loads with match_start as input
  → (For this sub-project: a placeholder scene that prints MatchStart contents)
```

### 7.5 Disconnect / pause / reconnect

Same state machine for client and host drops, differing only in who's gone.

**Client disconnect (any non-host peer):**

```
WebRTCTransport.peer_left(peer_id) fires on host
  → NetSession (host) marks PlayerSlot.connected = false
  → NetSession.state → PAUSED, broadcasts state + updated list
  → All clients: LobbyScene / MatchScene shows pause overlay + 30s countdown
  → Host runs a 30s timer
  → If peer reconnects through signaling (joiner sends {type: "join", code, reconnect_token}):
      → Server forwards reconnect_token in {type: "joiner", joinerId, reconnect_token} to host
      → Host inspects token before accepting the SDP exchange; matches to existing disconnected PlayerSlot
      → WebRTCTransport.peer_joined fires with a NEW peer id (ICE sessions don't preserve peer ids)
      → Host updates PlayerSlot.peer_id to the new id, sets connected = true
      → state → pre_pause_state (LOBBY or MATCH)
      → Broadcast resume with refreshed player list

  Note: downstream code must reference PlayerSlot objects (or look up via NetSession on
  players_changed), never cache raw peer_id values across PAUSED transitions.
  → If 30s elapses:
      → Host removes the PlayerSlot
      → state → previous
      → Broadcast resume
      → In-match: dropped player is treated as bust for the current event (sub-project #2 handles bust semantics)
```

**Host disconnect (anyone else's view):**

```
WebRTCTransport.transport_failed or peer_left(host_id) fires on clients
  → NetSession.state → PAUSED locally
  → Show "Host disconnected — waiting 30s" overlay
  → Local timer: if no signaling event from host within 30s:
      → NetSession.session_ended("host_lost")
      → Return to main menu
```

Host reconnect-through-signaling for an existing code is out of MVP scope. If the host's Godot process exits, the match is gone. Future enhancement: allow signaling server to remember a code beyond first use so a host can re-issue.

**Reconnect token:** When a player first joins, the host issues them a `reconnect_token` (random 16 bytes) in the post-join RPC. The client stores it in memory. On reconnect attempt, the joiner sends this token through the signaling payload field; the host matches it to the disconnected slot. Tokens are per-session only, never persisted to disk.

## 8. Error Handling

### 8.1 Signaling layer

| Trigger | User message | System behavior |
|---|---|---|
| Server unreachable (WebSocket fails to open within 5s) | "Couldn't reach the matchmaking server. Check your connection and try again." | `signaling_error("unreachable")`, return to main menu. No auto-retry. |
| Invalid / expired code | "Code QX7K2P not found. Codes expire after 10 minutes of inactivity." | Dialog closes, stays on join screen, code field cleared. |
| Lobby full (host has 8 slots when joiner arrives) | "That lobby is full." | Host rejects via signaling `{type: "error", reason: "full"}` to joiner; drops half-formed connection. |
| Match already in progress | "That match has already started." | Same path as full, reason `in_progress`. |

### 8.2 Transport layer

| Trigger | User message | System behavior |
|---|---|---|
| WebRTC handshake fails (ICE never reaches `connected`, 20s timeout) | "Couldn't connect — your network may be blocking peer-to-peer connections. Try a different network, or ask the host to try a different one." | Both sides close the half-built peer. Joiner returns to main menu; host stays hosting (other peers may still join). |
| Transport drops mid-session | (no error surfaced) | Handled by §7.5 pause/reconnect flow. |

### 8.3 Lobby protocol

| Trigger | Behavior |
|---|---|
| Duplicate color pick (race) | Host validates; first RPC wins. Loser receives `rpc_color_rejected()`, reverts UI, shows toast "That color was just taken." |
| Empty or oversized name | Host validates: 1–16 chars, trimmed. Empty → auto-replaced with "Player N" where N is seat index. Duplicate names allowed. |
| Kick race (client RPC arrives after host kicked them) | Host ignores (peer ID no longer in list). Client's transport drops them within ~1s. |
| Non-host client calls host-only RPC | Host validates `sender_id == self.host_peer_id`; mismatch → silently ignore. Godot's `@rpc("any_peer")` + manual sender check. |

### 8.4 Match start

| Trigger | Behavior |
|---|---|
| Start clicked with <2 players | Button disabled in UI. Host RPC re-validates (defense in depth) and ignores. |
| Start clicked while someone not ready | Start button only enabled when all players `ready`. `ready` defaults to false on join. |

### 8.5 Signaling server resilience

- **Server crashes / restarts during a connecting handshake:** Both sides see WebSocket close → existing handshakes fail with unreachable error. **Already-established peer connections are unaffected** — they're P2P. Server restart only breaks new joins, not active matches. Deliberate property of the design.
- **Server crashes during active match:** No effect.

### 8.6 Out-of-scope failure modes (acknowledged, deferred)

- Host process crash: match lost, no recovery.
- All-strict-NAT scenarios: documented as needing a future TURN server (~$5/mo, post-MVP if real playtests show >5% failure).
- Malicious host: party game with friends, host is trusted by design.

## 9. Testing

### 9.1 Tier 1 — Signaling server unit/integration tests

Node's built-in `node:test`. Tests run against a real `ws` server bound to a random port. No browser, no Godot.

Coverage:
- Hosting issues a unique 6-char Crockford-base32 code, no ambiguous chars.
- Codes are unique across 10k concurrent hosts.
- Joining a known code forwards `joiner` to the host with a monotonic `joinerId`.
- Joining an unknown code returns `error: unknown_code`.
- Signal relay forwards payloads opaquely (server does not parse SDP/ICE).
- Code expires after 10 minutes of inactivity (fake timers).
- `connected` from both peers releases the relay slot.
- Server restart loses codes but does not crash on stale client disconnects.

### 9.2 Tier 2 — Godot unit tests (GUT framework)

Pure GDScript tests. No WebRTC, no real network. Components tested behind their facades using fakes (`FakeTransport.gd`, `FakeSignalingClient.gd` — same signals, no real peer).

Coverage:
- `NetSession` state machine: lobby ↔ match ↔ paused transitions; illegal transitions rejected.
- `NetSession` validation: host-only RPCs reject non-host senders; color collision detection; name normalization.
- `PlayerSlot` serialization round-trips through `MatchStart`.
- Reconnect-token matching: correct token resumes slot; wrong token treated as new joiner; token rejected after 30s window.
- Disconnect timer: client drop pauses; 30s elapsing removes slot; reconnect inside window restores slot.

### 9.3 Tier 3 — Manual playtest checklist

Each row is one checklist item before sub-project is considered done.

| Scenario | Setup | Pass criteria |
|---|---|---|
| Host + 1 join, same LAN | 2 Godot instances on one machine | Both see each other's slots within 5s |
| Host + 1 join, different networks | Two physical machines on different ISPs | Connect within 10s; OR clear NAT-failure error |
| 8-player full lobby | 8 Godot instances across local + LAN peers | All 8 visible, host can kick any, slots reorder cleanly |
| Color collision | Two clients pick same color within 200ms | One reverts; final state agrees across all peers |
| Ready toggle storm | All clients spam ready toggle for 5s | Final state agrees, no stuck "still choosing" |
| Client drop mid-lobby | Kill one Godot client process | Other clients see pause + 30s countdown; slot removed on timeout |
| Client reconnect | Kill client, restart, rejoin with same code | Restored to original slot with name + color |
| Host drop | Kill host process | All clients show "Host disconnected", return to main menu after 30s |
| Match start handoff | All ready, host clicks Start | All clients receive identical `MatchStart` (same seed, same seat order) |
| Invalid code | Type random code | "Code not found" error, can retry |
| Strict-NAT failure | Force symmetric NAT on host (router config) | Joiner sees clear NAT-failure error within 20s, no hang |

### 9.4 Tier 4 — Development affordances

Not tests, but enable testing:

- Godot binary supports `--host-locally` and `--join-code=ABC234` CLI flags. Manual multi-instance testing is one command per window, no clicking.
- Signaling server has `LOG_LEVEL=debug` that prints every code/joiner event.
- Godot client logs every `NetSession` state transition and host-validated RPC outcome behind `net_session.debug = true`.

### 9.5 Out of scope for this sub-project's testing

- Load testing the signaling server (no meaningful load until events ship).
- Automated cross-NAT testing in CI (real network topology required; Tier 3 manual rows cover it).
- Latency/jitter measurements (no real-time gameplay yet; defer to sub-project #3).

## 10. Open Questions / Future Work

- **TURN fallback**: If playtests show >5% strict-NAT failure rate, add a hosted TURN server (~$5/mo, e.g., coturn on a small VPS). The `WebRTCTransport` facade is designed to accept TURN config without rippling changes elsewhere.
- **Host migration**: Out of scope but considered. Future implementation would require: (a) the new host inheriting authoritative state (player list is easy; mid-event hidden RNG state is hard), (b) reissuing a code via signaling server, (c) reconnecting other clients to the new host. Easier to add after sub-projects #2–6 have stabilized the event-state model.
- **Mode/rules picker**: Deferred to a later sub-project. `MatchStart.rules` is already in the contract; the lobby just won't write to it yet.
- **Public lobby browser**: Significant extra infrastructure (server-side persistence of open lobbies, listing API). Out of MVP.
- **Spectator join**: Could be added by allowing the signaling server to accept joiners after match start. Would require all RPCs to handle "state-resync on late join." Out of MVP.

## 11. Contract Summary for Downstream Sub-Projects

Sub-project #2 (Match Loop & Economy Core) should expect to consume:

- A `MatchStart` instance via the `NetSession.match_starting(match_start)` signal.
- An active `MultiplayerAPI` peer (via `NetSession`), with `local_peer_id` and `is_host` set.
- The full `seats: Array[PlayerSlot]` with stable seat indices, names, colors, peer IDs.
- `rng_seed: int` — the authoritative seed for all event randomness. Host uses this to seed event RNG; clients receive determinstic results in resolution payloads.

Sub-project #2 should NOT:

- Talk to the signaling server directly.
- Touch `WebRTCMultiplayerPeer` directly.
- Maintain its own player list — read from `NetSession.players`.
- Handle disconnect/reconnect; that's `NetSession`'s job. Sub-project #2 reacts to `state_changed(PAUSED)` by pausing event timers and showing its own pause overlay if desired.
