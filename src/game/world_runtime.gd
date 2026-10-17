class_name WorldRuntime
extends RefCounted
## Owns the star system, the game clock and which frame the player is in (a planet's own
## frame, or the star-centred system frame between worlds). When the ship crosses a sphere of
## influence it re-expresses every position and velocity in the new frame (continuous in the
## system frame, so nothing jumps) and tells the scene to rebuild terrain and POIs.

signal frame_changed(old_frame: StringName, new_frame: StringName)

var system: StarSystem
var session: GameSession
var navigator: SystemNavigator
var time_seconds := 0.0
var active_frame: StringName
var _planets := {} # body id -> PlanetBody (cached)


func _init(star_system: StarSystem, game_session: GameSession, start_frame: StringName) -> void:
	system = star_system
	session = game_session
	navigator = SystemNavigator.new(system)
	active_frame = start_frame
	_apply_bodies(planet_for(start_frame))


func planet_for(frame_id: StringName) -> PlanetBody:
	if frame_id == StarSystem.SYSTEM_FRAME:
		return null
	if not _planets.has(frame_id):
		_planets[frame_id] = system.build_planet_body(frame_id)
	return _planets[frame_id]


## Advance the clock; call before the session ticks.
func advance(delta: float) -> void:
	time_seconds += delta
	navigator.time_seconds = time_seconds


## Check whether the ship has crossed into another frame and switch if so. Returns true if it did.
func update_frame() -> bool:
	var wanted := system.frame_for(session.ship.state.position, time_seconds, active_frame)
	if wanted == active_frame:
		return false
	switch_frame(wanted)
	return true


func switch_frame(new_frame: StringName) -> void:
	var old_frame := active_frame
	var ship_state := session.ship.state
	ship_state.velocity = system.convert_velocity(ship_state.velocity, old_frame, new_frame, time_seconds)
	ship_state.position = system.convert_position(ship_state.position, new_frame, time_seconds)
	if session.mode == GameSession.Mode.OUTSIDE:
		session.exterior_body.position = system.convert_position(session.exterior_body.position, new_frame, time_seconds)
		session.exterior_body.velocity = system.convert_velocity(session.exterior_body.velocity, old_frame, new_frame, time_seconds)
	active_frame = new_frame
	_apply_bodies(planet_for(new_frame))
	_recentre_ship()
	frame_changed.emit(old_frame, new_frame)


## Used when loading a save: jump to a frame without converting (the save is already in it).
func force_frame(new_frame: StringName) -> void:
	var old_frame := active_frame
	active_frame = new_frame
	_apply_bodies(planet_for(new_frame))
	_recentre_ship()
	frame_changed.emit(old_frame, new_frame)


## The ship's render origin lives in a frame too: restart it at the ship's (converted) position.
func _recentre_ship() -> void:
	var ship := session.ship
	ship.render_origin = ship.state.position.duplicate_position()
	ship.apply_origin_shift(Vector3.ZERO)


func _apply_bodies(planet: PlanetBody) -> void:
	session.planet = planet
	session.ship.planet = planet
	session.ship.free_space = navigator if planet == null else null
