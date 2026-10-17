class_name ProgressTracker
extends RefCounted
## The story spine (research FLY-13: Rodina gates gears behind story progress and items). A fixed list of
## objectives; each completes when its test passes, in order. The warp drive is a ship upgrade: the ship
## cannot cross open space quickly until a Warp coil (a reward for clearing an outpost) is installed.

signal objective_completed(index: int)

const OBJECTIVES := [
	{"id": "explore", "text": "Land on Aurelia and discover 3 points of interest"},
	{"id": "clear_outpost", "text": "Destroy the guards of an outpost - its salvagers carry a Warp coil"},
	{"id": "install_warp", "text": "Install the Warp coil (Tab, Use, next to your ship)"},
	{"id": "reach_moon", "text": "Fly to Selene (press T to target it) and land"},
	{"id": "reach_far_world", "text": "Reach Verdant, the far world, and land"},
]

var current := 0
var warp_installed := false


func is_finished() -> bool:
	return current >= OBJECTIVES.size()


func current_text() -> String:
	return "All objectives complete - explore freely" if is_finished() else OBJECTIVES[current]["text"]


## Check the current objective against the game; advances at most one per call.
func update(session: GameSession, active_frame: StringName) -> void:
	if is_finished():
		return
	var done := false
	match OBJECTIVES[current]["id"]:
		"explore":
			done = session.discovery_log.count() >= 3
		"clear_outpost":
			done = session.cleared_log.to_array().size() >= 1
		"install_warp":
			done = warp_installed
		"reach_moon":
			done = active_frame == &"selene" and session.ship.state.landed
		"reach_far_world":
			done = active_frame == &"verdant" and session.ship.state.landed
	if done:
		current += 1
		objective_completed.emit(current - 1)


## Installs the warp coil if the player has one. Returns a message.
func install_warp_coil(session: GameSession) -> String:
	if warp_installed:
		return "The warp drive is already installed"
	if session.inventory.count(ItemDefinition.WARP_COIL) <= 0:
		return "You need a Warp coil"
	session.inventory.remove(ItemDefinition.WARP_COIL, 1)
	warp_installed = true
	return "Warp drive installed - open space is yours"


## Multiplier on cruise speed limits between worlds: the drive is dead until installed.
func warp_speed_factor() -> float:
	return 1.0 if warp_installed else 0.0005
