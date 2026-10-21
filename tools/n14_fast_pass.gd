extends Node
## N14 in-game fast-pass capture. Run tools/n14_fast_pass.tscn from the editor (Scene > Run Current
## Scene). Boots the real main scene, skips the title, and flies the player's ship over Aurelia
## by holding its velocity each physics tick (the flight model, floating origin, terrain and
## camera are the real ones). Saves a frame every second plus the terrain counters to
## tests/visual/out/fastpass/ and quits.
##
## Segments: settle at 20 km (stationary) -> 20 km at 5 km/s -> dive to 5 km while speeding up ->
## 5 km at 10 km/s -> brake, turn round, retrace at 5 km/s -> descend to 30 m and land.

## Each run gets its own folder (fastpass/<timestamp>), so earlier runs are kept for comparison.
var OUT_DIR := "res://tests/visual/out/fastpass"
const CAPTURE_INTERVAL := 1.0

var _main: Node
var _frames := 0
var _t := 0.0          # seconds since the run started (after the settle phase)
var _settle_t := 0.0
var _phase := "boot"
var _next_capture := 0.0
var _forward := Vector3.ZERO
var _log: Array[String] = []
var _capture_index := 0
var _speed := 0.0
var _target_altitude := 20000.0
var _heading_sign := 1.0
var _turn := 0.0
var _landed_at := -1.0


func _ready() -> void:
	process_physics_priority = -100 # before the ship's own tick
	OUT_DIR = OUT_DIR.path_join(Time.get_datetime_string_from_system().replace(":", "-"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_main)


func _process(delta: float) -> void:
	_frames += 1
	if _frames == 3:
		_main.menu.dismiss()
		_place_ship(20000.0)
		_phase = "settle"
	if _phase == "settle":
		_settle_t += delta
		if _main.terrain.is_settled() or _settle_t > 25.0:
			_note("settled at 20 km after %.1f s (settled=%s)" % [_settle_t, str(_main.terrain.is_settled())])
			_phase = "fly"
			_capture("settled")
		return
	if _phase != "fly":
		return
	_t += delta
	if _t >= _next_capture:
		_next_capture += CAPTURE_INTERVAL
		_capture(_segment())


func _physics_process(delta: float) -> void:
	if _phase != "fly" or _main == null:
		return
	var ship: Ship = _main.ship
	var planet: PlanetBody = _main.planet
	var up := planet.up_at(ship.state.position)
	var segment := _segment()
	match segment:
		"cruise20":
			_speed = 5000.0; _target_altitude = 20000.0
		"dive":
			_speed = lerpf(5000.0, 10000.0, clampf((_t - 20.0) / 6.0, 0.0, 1.0)); _target_altitude = 5000.0
		"low10":
			_speed = 10000.0; _target_altitude = 5000.0
		"brake":
			_speed = maxf(0.0, _speed - 2000.0 * delta); _target_altitude = 5000.0
		"turn":
			_speed = 0.0
			_turn = minf(PI, _turn + PI / 3.0 * delta)
		"retrace":
			_speed = minf(5000.0, _speed + 2500.0 * delta); _target_altitude = 5000.0
		"descend":
			_target_altitude = 30.0
			var altitude := ship.state.altitude_above_ground
			_speed = clampf(altitude * 0.15, 0.0, 3000.0)
		"land":
			_speed = 0.0
	# Heading: a great circle from the start point; turned round by _turn.
	var tangent := (_forward - up * _forward.dot(up)).normalized()
	_forward = tangent
	var heading := tangent.rotated(up, _turn)
	var altitude_error := _target_altitude - ship.state.altitude_above_ground
	var vertical := clampf(altitude_error * 0.8, -1500.0, 800.0)
	if segment == "land":
		vertical = -4.0 if not ship.state.landed else 0.0
	ship.state.velocity = heading * _speed + up * vertical
	var look := heading if _speed > 1.0 or segment == "turn" else heading
	ship.state.basis = Basis.looking_at(look.rotated(heading.cross(up).normalized(), -deg_to_rad(12.0)), up)
	ship.state.angular_velocity = Vector3.ZERO
	ship.state.hull = 1.0 # the harness holds speeds the pilot would not; keep entry heat from ending the run
	if segment == "land" and ship.state.landed and _landed_at < 0.0:
		_landed_at = _t
		_note("landed at t=%.1f" % _t)


func _segment() -> String:
	if _t < 20.0: return "cruise20"
	if _t < 26.0: return "dive"
	if _t < 41.0: return "low10"
	if _t < 46.0: return "brake"
	if _t < 49.0: return "turn"
	if _t < 61.0: return "retrace"
	if _t < 86.0: return "descend"
	if _t < 96.0: return "land"
	_finish()
	return "done"


func _place_ship(altitude: float) -> void:
	var ship: Ship = _main.ship
	var planet: PlanetBody = _main.planet
	var up := planet.up_at(ship.state.position)
	var ground := planet.surface_radius_xyz(up.x, up.y, up.z)
	var target := ground + altitude
	ship.state.position = WorldPos.new(planet.frame_id, up.x * target, up.y * target, up.z * target)
	ship.render_origin = ship.state.position.duplicate_position()
	ship.position = Vector3.ZERO
	_forward = Vector3.UP.cross(up).cross(up).normalized()
	ship.state.basis = Basis.looking_at(_forward, up)
	ship.state.velocity = Vector3.ZERO
	_main.terrain.render_origin = ship.render_origin.duplicate_position()


func _capture(label: String) -> void:
	var terrain: PlanetTerrain = _main.terrain
	var ship: Ship = _main.ship
	var stats := terrain.stream_stats()
	var name := "%03d_%s.png" % [_capture_index, label]
	_capture_index += 1
	var image := get_viewport().get_texture().get_image()
	if image != null and not image.is_empty():
		image.save_png(ProjectSettings.globalize_path(OUT_DIR.path_join(name)))
	_note("%s t=%.1f alt=%.0f v=%.0f fps=%d desired=%d displayed=%d pending=%d queued=%d cached=%d holes=%s fillers=%d previews=%d near_full=%s" % [
		name, _t, ship.state.altitude_above_ground, ship.state.velocity.length(), Engine.get_frames_per_second(),
		stats["desired_count"], stats["displayed_count"], stats["pending_count"], stats["queued_count"], stats["cache_entries"],
		"none" if terrain.desired_has_no_holes() else "YES", int(stats["fillers"]), _count_previews(terrain), _near_full(terrain)])


func _count_previews(terrain: PlanetTerrain) -> int:
	var count := 0
	for key in terrain._displayed:
		if bool(terrain._displayed[key]["preview"]):
			count += 1
	return count


func _near_full(terrain: PlanetTerrain) -> String:
	var viewer := Vector3(terrain.viewer.x, terrain.viewer.y, terrain.viewer.z)
	var altitude := (_main.ship as Ship).state.altitude_above_ground
	var ground := viewer.normalized() * terrain.planet.radius
	var radius := maxf(8000.0, altitude * 3.0)
	var total := 0
	var full := 0
	for key in terrain._desired:
		if terrain.planner.chunk_center(key).distance_to(ground) > radius:
			continue
		total += 1
		var record: Dictionary = terrain._displayed.get(key, {})
		if (not record.is_empty() and int(record["grid"]) >= ChunkMesher.FINE_GRID) or (record.is_empty() and terrain._displayed_prefixes.has(key) and terrain._is_covered(key)):
			full += 1
	return "%d/%d" % [full, total]


func _note(line: String) -> void:
	print("[fastpass] ", line)
	_log.append(line)


func _finish() -> void:
	if _phase == "done":
		return
	_phase = "done"
	var stats := (_main.terrain as PlanetTerrain).stream_stats()
	_note("final stats " + JSON.stringify({"plan_ms_max": float(stats["plan_usec_max"]) / 1000.0, "visibility_ms_max": float(stats["visibility_usec_max"]) / 1000.0, "upload_ms_max": float(stats["upload_usec_max"]) / 1000.0, "cache_peak_kb": int(stats["cache_peak_bytes"]) / 1024, "cache_hits": stats["cache_hits"], "preview_builds": stats["preview_builds"], "full_builds": stats["full_builds"]}))
	var file := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR.path_join("fastpass.log")), FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_log))
		file.close()
	get_tree().quit()
