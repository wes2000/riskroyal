extends GutTest

const MainMenu = preload("res://scripts/ui/main_menu.gd")
const NetSession = preload("res://scripts/net/net_session.gd")
const FakeTransport = preload("res://tests/fakes/fake_transport.gd")
const FakeSignalingClient = preload("res://tests/fakes/fake_signaling_client.gd")

var session
var menu

func before_each():
	var t = FakeTransport.new()
	var s = FakeSignalingClient.new()
	session = NetSession.new(t, s)
	menu = MainMenu.new()
	menu.session = session  # bypass autoload

func test_on_host_pressed_invokes_host_session():
	menu._on_host_pressed()
	assert_true(session.is_host)

func test_on_join_with_code_invokes_join_session():
	menu._on_join_with_code("ABC234")
	assert_eq(session._signaling.connect_to_code_calls[0].code, "ABC234")

func test_normalize_code_input_uppercases():
	assert_eq(MainMenu.normalize_code_input("abc234"), "ABC234")
	assert_eq(MainMenu.normalize_code_input("  AbC234  "), "ABC234")

func test_normalize_code_input_rejects_too_short():
	assert_eq(MainMenu.normalize_code_input("abc"), "")

func test_normalize_code_input_rejects_too_long():
	assert_eq(MainMenu.normalize_code_input("abcdef234"), "")
