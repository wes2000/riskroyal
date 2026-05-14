extends GutTest

const NetSessionState = preload("res://scripts/data/net_session_state.gd")
const NetConfig = preload("res://scripts/net/net_config.gd")

func test_state_enum_values():
	assert_eq(NetSessionState.State.IDLE, 0)
	assert_eq(NetSessionState.State.LOBBY, 1)
	assert_eq(NetSessionState.State.MATCH, 2)
	assert_eq(NetSessionState.State.PAUSED, 3)

func test_net_config_constants():
	assert_eq(NetConfig.MAX_PLAYERS, 8)
	assert_eq(NetConfig.RECONNECT_GRACE_SEC, 30)
	assert_eq(NetConfig.SIGNALING_URL, "wss://riskroyal.fly.dev")
	assert_eq(NetConfig.STUN_SERVERS, ["stun:stun.l.google.com:19302"])
	assert_eq(NetConfig.HOST_PEER_ID, 1)
