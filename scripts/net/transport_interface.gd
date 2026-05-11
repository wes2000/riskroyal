# Documents the signal contract for any Transport implementation.
# Real WebRTCTransport (Plan C) and FakeTransport (tests) both honor this.
#
# Signals:
#   peer_joined(id: int)
#   peer_left(id: int)
#   transport_failed(reason: String)
#
# Methods:
#   start_host() -> void
#   start_client() -> void
#   add_peer(joiner_id: int) -> void
#   close() -> void
#
# Not extended at runtime; serves as living documentation.
extends Object
