extends SceneTree
## Frame time with the ship interior in view and a fire burning (needs a display):
##   godot --path . -s res://tools/interior_perf.gd
## Lands the ship on the ground, stands the player in engineering, lights a fire, and measures 600 frames.
var _main: Node
var _frames := 0
var _samples: Array[float] = []
var _last := 0
var _max_draw := 0.0


func _initialize() -> void:
	if OS.get_environment("SOL_ASSETS") == "off": # N9 tooling: measure/photograph the placeholder look with the same build
		var settings := GameSettings.instance()
		settings.asset_materials = false
		settings.atmosphere_scattering = false
		settings.clouds = false
		settings.decals = false
		settings.terrain_detail = false
		settings.starfield = false
		settings.sample_audio = false
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_last = Time.get_ticks_usec()


func _process(_delta: float) -> bool:
	_frames += 1
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last) / 1000.0
	_last = now
	if _frames == 2:
		_main.menu.dismiss()
		var session: GameSession = _main.session
		var planet: PlanetBody = session.planet
		var direction := Vector3(0.3, 0.5, 0.8).normalized()
		var radius := planet.surface_radius_xyz(direction.x, direction.y, direction.z) + 2.1
		session.ship.state.position = WorldPos.new(planet.frame_id, direction.x * radius, direction.y * radius, direction.z * radius)
		session.ship.state.basis = Basis.looking_at(Vector3.UP.cross(direction).normalized(), direction)
		session.ship.state.velocity = Vector3.ZERO
		_main._recentre_everything_on_ship()
	if _frames == 200:
		var session: GameSession = _main.session
		session.interact() # stand up
		session.interior_body.place(Vector3(0.5, -0.9, 1.4), deg_to_rad(90.0))
		session.systems.hazards.ignite(&"engineering")
		session.systems.hazards.fire[&"engineering"] = 0.8
		_main._on_mode_changed()
	if _frames > 260:
		_samples.append(frame_ms)
		_max_draw = maxf(_max_draw, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	if _frames == 860:
		_samples.sort()
		var total := 0.0
		for value in _samples:
			total += value
		print("interior+fire: %d frames avg %.2f ms p95 %.2f ms worst %.2f ms  max draw calls %d  window %s  mode %d landed %s" % [_samples.size(), total / _samples.size(), _samples[int(_samples.size() * 0.95)], _samples[-1], _max_draw, str(root.size), _main.session.mode, str(_main.ship.state.landed)])
		root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "interior.png")
		quit()
	return false
