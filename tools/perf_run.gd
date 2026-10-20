extends SceneTree
## Frame-time measurement on a real window (not headless):
##   godot --path . -s res://tools/perf_run.gd
## Descends from orbit to the ground with a scripted pilot, then reports frame time statistics for each
## phase. Results are meant to be pasted into tests/perf/results.md.

class DescentPilot extends PilotSource:
	func _init() -> void:
		source_id = &"perf"

	func poll(ship_state: ShipState, _delta: float) -> PilotCommand:
		var command := PilotCommand.new()
		command.move_lock = 1.0 # scripted pilot: holds the velocity it asks for (Rodina AI mover MoveLock)
		command.stop_rotation = true # and holds its attitude (Rodina AI sets its turn rate directly)
		var up := Vector3(ship_state.position.x, ship_state.position.y, ship_state.position.z).normalized()
		ship_state.basis = Basis.looking_at(Vector3.UP.cross(up).normalized(), up)
		var altitude := ship_state.altitude_above_ground
		command.gear = PilotCommand.GEAR_CRUISE if altitude > 2100.0 else (PilotCommand.GEAR_COMBAT if altitude > 250.0 else PilotCommand.GEAR_DOCK)
		command.thrust = Vector3(0, -clampf(altitude / 80.0, 0.04, 1.0), 0)
		return command


var _main: Node
var _frames := 0
var _samples := {"orbit_to_atmosphere": [], "descent_low": [], "ground": []}
var _landed_frames := 0
var _last_ticks := 0


var _max_draw_calls := 0.0
var _max_primitives := 0.0
var _max_physics_ms := 0.0
var _max_process_ms := 0.0


func _initialize() -> void:
	if OS.get_environment("SOL_ASSETS") == "off": # N9 tooling: measure/photograph the placeholder look with the same build
		var settings := GameSettings.instance()
		settings.asset_materials = false
		settings.decals = false
		settings.terrain_detail = false
		settings.starfield = false
		settings.sample_audio = false
	# Optional argument WxH (e.g. 2560x1440) sets the window size: godot ... -s res://tools/perf_run.gd -- 2560x1440
	for argument in OS.get_cmdline_user_args():
		if argument.contains("x") and argument.split("x").size() == 2 and argument.split("x")[0].is_valid_int():
			DisplayServer.window_set_size(Vector2i(int(argument.split("x")[0]), int(argument.split("x")[1])))
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_last_ticks = Time.get_ticks_usec()


func _process(_delta: float) -> bool:
	_frames += 1
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_ticks) / 1000.0
	_last_ticks = now
	if _frames == 2:
		_main.menu.dismiss()
	if _frames == 5:
		_main.session.progress.warp_installed = true
		var pilot := DescentPilot.new()
		_main.ship.controller.release_control(_main.player_source)
		_main.ship.controller.request_control(pilot, &"pilot_seat")
	if _frames < 120:
		return false # let the first terrain load finish before measuring
	var ship: Ship = _main.ship
	var phase := "ground"
	if ship.state.altitude_above_ground > 100000.0:
		phase = "orbit_to_atmosphere"
	elif not ship.state.landed:
		phase = "descent_low"
	_samples[phase].append(frame_ms)
	_max_draw_calls = maxf(_max_draw_calls, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_max_primitives = maxf(_max_primitives, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_max_physics_ms = maxf(_max_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_max_process_ms = maxf(_max_process_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	if _frames % 600 == 0 and OS.get_cmdline_user_args().has("trace"):
		print("t=", _frames, " agl ", ship.state.altitude_above_ground, " speed ", ship.state.speed(), " hull ", ship.state.hull, " fuel ", ship.state.fuel, " gear ", ship.state.gear, " landed ", ship.state.landed, " msg ", ship.state.status_message)
	if ship.state.landed:
		_landed_frames += 1
	if _landed_frames > 180 or _frames > 20000:
		_report()
		quit()
	return false


func _report() -> void:
	print("Godot ", Engine.get_version_info()["string"], "  window ", root.size, "  renderer ", RenderingServer.get_video_adapter_name())
	for phase in _samples:
		var samples: Array = _samples[phase]
		if samples.is_empty():
			print(phase, ": no frames")
			continue
		samples.sort()
		var total := 0.0
		for value in samples:
			total += value
		var average: float = total / samples.size()
		print("%s: %d frames  avg %.2f ms (%.0f fps)  p95 %.2f ms  worst %.2f ms  min fps %.0f" % [phase, samples.size(), average, 1000.0 / average, samples[int(samples.size() * 0.95)], samples[-1], 1000.0 / samples[-1]])
	print("chunks displayed at end: ", _main.terrain.displayed_chunk_count())
	print("max draw calls %d  max primitives %d  max physics tick %.2f ms  max script process %.2f ms" % [_max_draw_calls, _max_primitives, _max_physics_ms, _max_process_ms])
	print("memory: static %.0f MB (peak %.0f MB), video RAM %.0f MB, texture %.0f MB" % [Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0])
