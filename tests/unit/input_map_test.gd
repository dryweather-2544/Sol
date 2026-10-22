extends "res://tests/test_case.gd"

const REQUIRED_ACTIONS := [
	"thrust_forward", "thrust_back", "strafe_left", "strafe_right", "move_up", "move_down",
	"roll_left", "roll_right", "pitch_up", "pitch_down", "yaw_left", "yaw_right",
	"boost", "brake", "interact", "toggle_view", "gear_up", "gear_down", "clutch", "pause", "quicksave", "quickload", "nav_next", "inventory", "fire", "crew_fix", "crew_turret", "crew_power", "gunner_station", "scan", "journal"]


func test_every_flight_action_exists_and_has_a_key() -> void:
	for action_name in REQUIRED_ACTIONS:
		assert_true(InputMap.has_action(action_name), "missing action %s" % action_name)
		if InputMap.has_action(action_name):
			assert_true(InputMap.action_get_events(action_name).size() > 0, "%s has no key" % action_name)


func test_key_bindings_resolve_to_expected_keys() -> void:
	var forward_event: InputEventKey = InputMap.action_get_events("thrust_forward")[0]
	assert_eq(forward_event.physical_keycode, KEY_W)
	var boost_event: InputEventKey = InputMap.action_get_events("boost")[0]
	assert_eq(boost_event.physical_keycode, KEY_SHIFT)
	var up_event: InputEventKey = InputMap.action_get_events("pitch_up")[0]
	assert_eq(up_event.physical_keycode, KEY_UP)
	var pause_event: InputEventKey = InputMap.action_get_events("pause")[0]
	assert_eq(pause_event.physical_keycode, KEY_ESCAPE)
