# Documents the signal contract for any SignalingClient implementation.
# Real SignalingClient (Plan C) and FakeSignalingClient (tests) both honor this.
#
# Signals:
#   code_issued(code: String)
#   peer_arriving(joiner_id: int, reconnect_token: String)
#   match_started_ack()
#   host_left()
#   joiner_left(joiner_id: int)
#   signaling_error(reason: String)
#
# Methods:
#   request_code() -> void
#   connect_to_code(code: String, reconnect_token: String = "") -> void
#   send_signal(to: int, payload: Dictionary) -> void
#   notify_connected(peer_id: int) -> void
#   send_start_match() -> void
#   close() -> void
#
# Not extended at runtime; serves as living documentation.
extends Object
