# Documents the signal contract for any SignalingClient implementation.
# Real SignalingClient (Plan C) and FakeSignalingClient (tests) both honor this.
#
# Signals:
#   code_issued(code: String)
#   peer_arriving(joiner_id: int, reconnect_token: String)
#   peer_id_assigned(peer_id: int)
#   match_started_ack()
#   host_left()
#   joiner_left(joiner_id: int)
#   signaling_error(reason: String)
#   signal_received(from_peer: int, payload: Dictionary)
#
# Methods:
#   request_code() -> void
#   connect_to_code(code: String, reconnect_token: String = "") -> void
#   send_signal(to: int, payload: Dictionary) -> void
#   notify_connected(peer_id: int) -> void
#   send_start_match() -> void
#   close() -> void
#   pump() -> void  # called per-tick by the autoload to drain inbound packets
#
# Not extended at runtime; serves as living documentation.
extends Object
