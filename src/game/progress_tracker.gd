class_name ProgressTracker
extends RefCounted
## The story spine (research FLY-13: Rodina gates gears behind story progress and items). A fixed list of
## typed objectives; each completes when its test passes, in order. Types: discover, clear_outposts, flag,
## land_on (a world), have_item, orbit_of (in space around a world). The warp drive is a ship upgrade: the ship
## cannot cross open space quickly until a Warp coil (a reward for clearing an outpost) is installed.
## The "Mayday on Selene" mission (objectives 4-7) sits inside the spine: arriving at Selene springs an ambush
## and pins a beacon a few km below; its wreck holds the engine coupling the ambush burns out.

signal objective_completed(index: int)
## Emitted once, when the ship first arrives at Selene during the mission; carries the beacon's direction from the moon's centre.
signal ambush_triggered(beacon_direction: Vector3)

const BEACON_ID: StringName = &"poi_mayday_beacon"
const BEACON_DISTANCE_METRES := 6000.0

const OBJECTIVES := [
	{"id": "explore", "type": "discover", "count": 3, "text": "Land on Aurelia and discover 3 points of interest"},
	{"id": "clear_outpost", "type": "clear_outposts", "count": 1, "text": "Destroy the guards of an outpost - its salvagers carry a Warp coil"},
	{"id": "install_warp", "type": "flag", "flag": "warp_installed", "text": "Install the Warp coil (Tab, Use, next to your ship)"},
	{"id": "mayday_go", "type": "land_on", "frame": "selene", "text": "Mayday from Selene! Fly there (press T to target it) and land near the beacon"},
	{"id": "mayday_retrieve", "type": "have_item", "item": "engine_coupling", "text": "Walk to the beacon on Selene and open its crate for an engine coupling"},
	{"id": "mayday_install", "type": "flag", "flag": "coupling_installed", "text": "Install the coupling at the engine station"},
	{"id": "mayday_return", "type": "orbit_of", "frame": "planet", "text": "Take off and return to orbit above Aurelia"},
	{"id": "reach_far_world", "type": "land_on", "frame": "verdant", "text": "Reach Verdant, the far world, and land"},
]

var current := 0
var warp_installed := false
var coupling_installed := false
var ambush_started := false
## Unit direction from Selene's centre to the mission beacon; ZERO until the ambush starts.
var beacon_direction := Vector3.ZERO


func is_finished() -> bool:
	return current >= OBJECTIVES.size()


func current_text() -> String:
	return "All objectives complete - explore freely" if is_finished() else OBJECTIVES[current]["text"]


func current_id() -> String:
	return "" if is_finished() else OBJECTIVES[current]["id"]


## Check the current objective against the game; advances at most one per call.
func update(session: GameSession, active_frame: StringName) -> void:
	if is_finished():
		return
	if current_id() == "mayday_go" and active_frame == &"selene" and not ambush_started:
		_start_ambush(session)
	var objective: Dictionary = OBJECTIVES[current]
	var done := false
	match objective["type"]:
		"discover":
			done = session.discovery_log.count() >= int(objective["count"])
		"clear_outposts":
			done = session.cleared_log.to_array().size() >= int(objective["count"])
		"flag":
			done = bool(get(objective["flag"]))
		"land_on":
			done = active_frame == StringName(objective["frame"]) and session.ship.state.landed
		"have_item":
			done = session.inventory.count(StringName(objective["item"])) > 0 or coupling_installed
		"orbit_of":
			done = active_frame == StringName(objective["frame"]) and session.ship.state.regime == FlightRegime.SPACE
	if done:
		current += 1
		objective_completed.emit(current - 1)


func _start_ambush(session: GameSession) -> void:
	ambush_started = true
	var up := Vector3(session.ship.state.position.x, session.ship.state.position.y, session.ship.state.position.z).normalized()
	var helper := Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.UP
	var tangent := up.cross(helper).normalized()
	var body_radius := maxf(session.planet.radius if session.planet != null else 1.7e6, 1.0)
	beacon_direction = (up + tangent * (BEACON_DISTANCE_METRES / body_radius)).normalized()
	ambush_triggered.emit(beacon_direction)


## Installs the warp coil if the player has one. Returns a message.
func install_warp_coil(session: GameSession) -> String:
	if warp_installed:
		return "The warp drive is already installed"
	if session.inventory.count(ItemDefinition.WARP_COIL) <= 0:
		return "You need a Warp coil"
	session.inventory.remove(ItemDefinition.WARP_COIL, 1)
	warp_installed = true
	return "Warp drive installed - open space is yours"


## Installs the engine coupling: lifts the engines' repair cap and restores them. Returns a message.
func install_engine_coupling(session: GameSession) -> String:
	if session.inventory.count(ItemDefinition.ENGINE_COUPLING) <= 0:
		return "You need an engine coupling"
	session.inventory.remove(ItemDefinition.ENGINE_COUPLING, 1)
	coupling_installed = true
	session.systems.subsystems.cap[ShipSubsystems.Id.ENGINES] = 1.0
	session.systems.subsystems.health[ShipSubsystems.Id.ENGINES] = 1.0
	return "Engine coupling installed - the engines are as good as new"


## Multiplier on cruise speed limits between worlds: the drive is dead until installed.
func warp_speed_factor() -> float:
	return 1.0 if warp_installed else 0.0005
