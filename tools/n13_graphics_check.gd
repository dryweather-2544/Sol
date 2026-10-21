extends SceneTree
## N13 in-game check of the Rodina graphics port. Needs a display and the rodina style:
##   SOL_VISUAL_STYLE=rodina N13_SCENE=<scene> N13_OUT=<dir> godot --path . -s res://tools/n13_graphics_check.gd
## Scenes: interior (standing in the cabin, then facing the cockpit), ship (the ship against open space),
## combat (engine exhaust, 300 km over Aurelia), cruise (cruise engine + inertia streaks), warp (open space:
## warp entry, sustained warp, then back to cruise), entry (atmospheric entry at 4 km/s), low (900 m over Aurelia).
## Boots the real main scene and flies the ship with a scripted pilot through the real flight model; shots and one
## log line per shot record game time, gear, speed, FOV, warp blend, chase distance factor, shake and live effects.

class Pilot extends PilotSource:
	var gear := PilotCommand.GEAR_COMBAT
	var thrust := Vector3.ZERO
	func _init() -> void:
		source_id = &"n13_check"
	func poll(_ship_state: ShipState, _delta: float) -> PilotCommand:
		var command := PilotCommand.new()
		command.gear = gear
		command.thrust = thrust
		command.stop_rotation = true
		return command


var _main: Node
var _pilot := Pilot.new()
var _scene := "warp"
var _out := "user://n13_shots"
var _frames := 0
var _start_time := -1.0
var _shots: Array = [] # [game seconds after start, label, action Callable or null]
var _next_shot := 0
var _frame_times: Array[float] = []
var _last_ticks := 0
## The cloud renderer draws ~1 frame/s, so particles living 0.03-0.6 s are born and dead between two frames. Before
## each shot the game is slowed to SETTLE_SCALE for SETTLE_FRAMES frames (about 0.4 s of game time at the same
## frame cost), so the shot shows the particles as a 60 fps frame would. Logged values are read after settling.
const SETTLE_SCALE := 0.02
const SETTLE_FRAMES := 25
var _settling := 0


func _initialize() -> void:
	_scene = OS.get_environment("N13_SCENE") if OS.get_environment("N13_SCENE") != "" else "warp"
	var out := OS.get_environment("N13_OUT")
	if out != "":
		_out = out
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	var now := Time.get_ticks_usec()
	if _last_ticks != 0 and _start_time >= 0.0:
		_frame_times.append((now - _last_ticks) / 1000.0)
	_last_ticks = now
	if _frames == 2:
		_main.menu.dismiss()
	if _frames == 10:
		_setup()
		_start_time = _main.runtime.time_seconds
	if _start_time < 0.0:
		return false
	var elapsed: float = _main.runtime.time_seconds - _start_time
	if _settling > 0:
		_settling -= 1
		if _settling == 0:
			_shoot(_shots[_next_shot][1], elapsed)
			Engine.time_scale = 1.0
			_next_shot += 1
		return false
	while _next_shot < _shots.size() and elapsed >= _shots[_next_shot][0]:
		var shot: Array = _shots[_next_shot]
		if shot[2] != null:
			(shot[2] as Callable).call()
		if shot[1] != "":
			Engine.time_scale = SETTLE_SCALE
			_settling = SETTLE_FRAMES
			return false
		_next_shot += 1
	if _next_shot >= _shots.size():
		_finish()
		return true
	return false


func _setup() -> void:
	var ship: Ship = _main.ship
	var planet: PlanetBody = _main.planet
	_main.session.progress.warp_installed = true
	ship.controller.release_control(_main.player_source)
	ship.controller.request_control(_pilot, &"pilot_seat")
	var up := planet.up_at(ship.state.position).normalized()
	match _scene:
		"combat", "cruise":
			_place_over_planet(300000.0, up, Basis.looking_at(up.cross(Vector3.RIGHT).normalized(), up), Vector3.ZERO)
			_pilot.gear = PilotCommand.GEAR_COMBAT if _scene == "combat" else PilotCommand.GEAR_CRUISE
			_pilot.thrust = Vector3(0, 0, -1)
			if _scene == "combat":
				_shots = [[1.0, "combat_thrust", null], [1.5, "", func(): _pilot.thrust = Vector3(0, 0.6, -0.6)], [2.0, "combat_thrust_up", null]]
			else:
				_shots = [[1.0, "cruise_1s", null], [4.0, "cruise_4s", null], [8.0, "cruise_8s", null]]
		"entry":
			var forward := up.cross(Vector3.RIGHT).normalized()
			var dive := (forward - up * 0.6).normalized()
			_place_over_planet(110000.0, up, Basis.looking_at(dive, up), dive * 4000.0)
			_pilot.gear = PilotCommand.GEAR_CRUISE
			_pilot.thrust = Vector3.ZERO
			_shots = [[0.5, "entry_0_5s", null], [2.0, "entry_2s", null], [4.0, "entry_4s", null]]
		"low":
			var forward := up.cross(Vector3.RIGHT).normalized()
			_place_over_planet(900.0, up, Basis.looking_at(forward, up), forward * 300.0)
			_pilot.gear = PilotCommand.GEAR_COMBAT
			_pilot.thrust = Vector3(0, 0, -0.5)
			_shots = [[1.0, "low_900m", null], [3.0, "low_900m_3s", null]]
		"interior":
			# Walk out of the pilot seat into the cockpit/cabin (Rodina interiors: dark rooms, coloured ceiling lights).
			_place_over_planet(300000.0, up, Basis.looking_at(up.cross(Vector3.RIGHT).normalized(), up), Vector3.ZERO)
			_pilot.gear = PilotCommand.GEAR_DOCK
			_shots = [[0.3, "", func(): _main.session._stand_up(); _main._on_mode_changed()], [1.5, "interior_cabin", null],
				[1.6, "", func(): _main.session.interior_body.yaw += PI], [2.5, "interior_cockpit", null]]
		"ship":
			_place_in_open_space()
			_pilot.gear = PilotCommand.GEAR_COMBAT
			_shots = [[1.0, "ship_space", null]]
		_:
			_place_in_open_space()
			_pilot.gear = PilotCommand.GEAR_CRUISE
			_pilot.thrust = Vector3(0, 0, -1)
			_shots = [
				[1.0, "warp_before_cruise", null],
				[1.1, "", func(): _pilot.gear = PilotCommand.GEAR_WARP],
				[1.6, "warp_entry_0_5s", null],
				[2.9, "warp_entry_1_8s", null],
				[5.1, "warp_4s", null],
				[11.1, "warp_10s_sustained", null],
				[11.2, "", func(): _pilot.gear = PilotCommand.GEAR_CRUISE],
				[11.7, "warp_exit_0_5s", null],
				[13.2, "warp_exit_2s", null],
				[16.2, "warp_exit_5s", null],
			]


func _place_over_planet(altitude: float, up: Vector3, basis: Basis, velocity: Vector3) -> void:
	var ship: Ship = _main.ship
	var planet: PlanetBody = _main.planet
	var radius := planet.radius + altitude
	if altitude < 50000.0:
		radius = planet.surface_radius_xyz(up.x, up.y, up.z) + altitude
	ship.state.position = WorldPos.new(planet.frame_id, up.x * radius, up.y * radius, up.z * radius)
	ship.state.basis = basis
	ship.state.velocity = velocity
	ship.state.landed = false
	_recentre()


## 5 million km above the home planet's orbit plane: outside every sphere of influence, where WARP is allowed.
func _place_in_open_space() -> void:
	var ship: Ship = _main.ship
	var runtime: WorldRuntime = _main.runtime
	var system: StarSystem = runtime.system
	var home := system.body_position(runtime.active_frame, runtime.time_seconds)
	ship.state.position = WorldPos.new(StarSystem.SYSTEM_FRAME, home.x, home.y + 5.0e9, home.z)
	ship.state.velocity = Vector3.ZERO
	ship.state.basis = Basis.IDENTITY
	runtime.force_frame(StarSystem.SYSTEM_FRAME)
	_recentre()


func _recentre() -> void:
	var ship: Ship = _main.ship
	ship.render_origin = ship.state.position.duplicate_position()
	ship.apply_origin_shift(Vector3.ZERO)
	_main.floating_origin.anchor = ship
	_main.chase_camera.target = ship
	_main.chase_camera.snap_to_target()
	_main.chase_camera.current = true


func _shoot(label: String, elapsed: float) -> void:
	var ship: Ship = _main.ship
	var view: LimnalWarpView = _main.warp_view
	var effects: ShipEffects = _main._ship_effects()
	var active := effects.active_effects() if effects != null else {}
	var names: Array = []
	for slot in active:
		names.append("%s=%s@%.2f" % [slot, active[slot]["material"], active[slot]["strength"]])
	names.sort()
	print("N13 %s t=%.2f frame=%s gear=%d speed=%.0f alt=%.0f fov=%.2f warp=%.4f activation=%.3f dist=%.2fm shake=(%.4f,%.4f) resistance=%.3f effects=[%s]" % [
		label, elapsed, str(_main.runtime.active_frame), ship.state.gear, ship.state.speed(), ship.state.altitude_above_ground,
		_main.chase_camera.fov, view.spacewarp, view.activation, _main.chase_camera.follow_distance, view.shake.x, view.shake.y,
		ship.state.atmosphere_resistance, ", ".join(names)])
	var image := root.get_texture().get_image()
	image.save_jpg(_out.path_join("%s.jpg" % label), 0.88)


func _finish() -> void:
	var total := 0.0
	var worst := 0.0
	for frame_ms in _frame_times:
		total += frame_ms
		worst = maxf(worst, frame_ms)
	var mean := total / maxf(1.0, _frame_times.size())
	print("N13 %s DONE frames=%d mean_frame_ms=%.1f worst_frame_ms=%.1f (software renderer: not representative of the Mac)" % [_scene, _frame_times.size(), mean, worst])
	quit(0)
