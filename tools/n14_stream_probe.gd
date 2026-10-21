extends Node
## N14 terrain streaming probe: flies a scripted viewer over a planet in real time, with the real
## PlanetTerrain and its worker threads, and samples streaming health every 0.25 s.
##
## Usage (command line, wraps this node):
##   godot --headless --path . -s res://tools/n14_stream_probe_cli.gd -- <scenario> [planet_id] [out.json]
## In the editor/game: tools/n14_mac_runner.tscn runs "all" and then the unit tests.
## Scenarios: cold20 cruise20 low10 brake_turn approach landing all
##
## Coverage terms used in the output (per desired leaf chunk):
##   exact   the desired chunk itself is displayed at full grid
##   preview the desired chunk is displayed, but with a reduced preview grid
##   finer   finer displayed chunks fully cover it (left over from before)
##   coarse  only a displayed ancestor covers it (smooth-patch risk; deficit = level difference)
##   hole    nothing covers it at all: a blank patch on screen
## "near" = desired leaves whose centre is within NEAR_FACTOR * altitude (>= 8 km) of the point under the ship.
## "ahead" = leaves the planner would want at the true position LOOKAHEAD_S seconds later.

const SAMPLE_INTERVAL := 0.25
const NEAR_FACTOR := 3.0
const LOOKAHEAD_S := 3.0

var _planet: PlanetBody
var _terrain: PlanetTerrain
var _scenario := ""
var _scenarios: Array[String] = []
var _out_path := ""
var _t := 0.0
var _next_sample := 0.0
var _duration := 0.0
var _warm_seconds := 0.0
var _warming := false
var _warm_elapsed := 0.0
var _samples: Array = []
var _results := {}
var _start_dir := Vector3(0.31, 0.82, 0.48).normalized()
var _forward := Vector3.ZERO
var _first_full_coverage := -1.0
var _first_near_detail := -1.0
var _completed_at_start := 0
var _frames := 0
var _frame_time_max := 0.0
var _frame_times: Array[float] = []


signal finished(results: Dictionary)

var which := "cruise20"
var planet_id := &"planet"
var out_path := ""
var quit_when_done := true
var log_lines: Array[String] = []


func _log(line: String) -> void:
	print(line)
	log_lines.append(line)


func _ready() -> void:
	_out_path = out_path
	Engine.max_fps = 60
	var system := StarSystem.default_system()
	_planet = system.build_planet_body(planet_id)
	_scenarios.clear()
	if which == "all":
		_scenarios.append_array(["cold20", "cruise20", "low10", "brake_turn", "approach", "landing"])
	else:
		_scenarios.append(which)
	_log("probe planet=%s radius=%.0f finest=%d threads=%d os=%s" % [planet_id, _planet.radius, _planet.finest_lod_level(), OS.get_processor_count(), OS.get_name()])
	_start_next()


func _start_next() -> void:
	if _terrain != null:
		_terrain.queue_free()
		_terrain = null
	if _scenarios.is_empty():
		_finish()
		return
	_scenario = _scenarios.pop_front()
	_t = 0.0
	_next_sample = 0.0
	_samples = []
	_first_full_coverage = -1.0
	_first_near_detail = -1.0
	_frame_times = []
	_frame_time_max = 0.0
	var tangent := _start_dir.cross(Vector3.UP).normalized()
	_forward = tangent
	match _scenario:
		"cold20": _duration = 20.0; _warm_seconds = 0.0
		"cruise20": _duration = 30.0; _warm_seconds = 12.0
		"low10": _duration = 25.0; _warm_seconds = 12.0
		"brake_turn": _duration = 32.0; _warm_seconds = 12.0
		"approach": _duration = 40.0; _warm_seconds = 6.0
		"landing": _duration = 40.0; _warm_seconds = 12.0
		_:
			push_error("unknown scenario %s" % _scenario)
			_finish()
			return
	_terrain = PlanetTerrain.new(_planet)
	var state := _state_at(0.0)
	_terrain.viewer = state[0]
	_terrain.render_origin = state[0].duplicate_position()
	_terrain.viewer_velocity = Vector3.ZERO
	add_child(_terrain)
	_warming = _warm_seconds > 0.0
	_warm_elapsed = 0.0
	_log("--- scenario %s (warm %.0fs, run %.0fs)" % [_scenario, _warm_seconds, _duration])


## Returns [WorldPos, velocity] for the scripted path at time t (seconds after the warm-up).
func _state_at(t: float) -> Array:
	var altitude := 20000.0
	var distance := 0.0 # along the ground, metres
	var speed := 0.0
	var direction_sign := 1.0
	match _scenario:
		"cold20":
			altitude = 20000.0; speed = 5000.0; distance = speed * t
		"cruise20":
			altitude = 20000.0; speed = 5000.0; distance = speed * t
		"low10":
			altitude = 5000.0; speed = 10000.0; distance = speed * t
		"brake_turn":
			# 12 s at 5 km/s, 4 s braking to 0, then back the other way accelerating to 5 km/s.
			altitude = 20000.0
			if t < 12.0:
				speed = 5000.0; distance = 5000.0 * t
			elif t < 16.0:
				var tb := t - 12.0
				speed = 5000.0 * (1.0 - tb / 4.0)
				distance = 60000.0 + 5000.0 * tb - 625.0 * tb * tb
			else:
				var tr := t - 16.0
				var back_speed := minf(5000.0, 1250.0 * tr)
				var back_distance := 625.0 * minf(tr, 4.0) * minf(tr, 4.0) + 5000.0 * maxf(0.0, tr - 4.0)
				speed = back_speed; distance = 70000.0 - back_distance; direction_sign = -1.0
		"approach":
			# From 1500 km straight down-ish toward 20 km, slowing exponentially, then cruising.
			var a0 := 1500000.0
			altitude = 20000.0 + (a0 - 20000.0) * exp(-t / 6.0)
			speed = (a0 - 20000.0) / 6.0 * exp(-t / 6.0) + 2000.0
			distance = 2000.0 * t
		"landing":
			# 20 km down to the ground over 30 s while slowing from 3 km/s, then 10 s walking at 5 m/s.
			if t < 30.0:
				var f := t / 30.0
				altitude = lerpf(20000.0, 2.0, f * (2.0 - f))
				speed = 3000.0 * (1.0 - f)
				distance = 3000.0 * (t - t * t / 60.0)
			else:
				altitude = 2.0; speed = 5.0; distance = 45000.0 + 5.0 * (t - 30.0)
	var angle := distance / _planet.radius
	var ground_dir := (_start_dir * cos(angle) + _forward * sin(angle)).normalized()
	var surface := _planet.surface_radius_xyz(ground_dir.x, ground_dir.y, ground_dir.z)
	var p := ground_dir * (surface + altitude)
	var along := (_forward * cos(angle) - _start_dir * sin(angle)).normalized()
	var velocity := along * speed * direction_sign
	if _scenario == "approach":
		velocity += -ground_dir * ((1500000.0 - 20000.0) / 6.0 * exp(-t / 6.0))
	return [WorldPos.new(_planet.frame_id, p.x, p.y, p.z), velocity, altitude]


func _process(delta: float) -> void:
	if _terrain == null:
		return
	_frames += 1
	if _warming:
		_warm_elapsed += delta
		if _warm_elapsed >= _warm_seconds:
			_warming = false
			_completed_at_start = int(_terrain.stream_stats().get("completed", 0))
		return
	_t += delta
	_frame_times.append(delta)
	_frame_time_max = maxf(_frame_time_max, delta)
	var state := _state_at(_t)
	_terrain.viewer = state[0]
	_terrain.viewer_velocity = state[1]
	if _t >= _next_sample:
		_next_sample += SAMPLE_INTERVAL
		_sample(state)
	if _t >= _duration:
		_summarise()
		_start_next()


func _classify(key: int) -> Array:
	# Returns [kind, deficit]
	if _terrain._displayed.has(key):
		var record: Dictionary = _terrain._displayed[key]
		return ["preview" if bool(record.get("preview", false)) else "exact", 0]
	if _terrain._displayed_prefixes.has(key) and _terrain._is_covered(key):
		return ["finer", 0]
	var ancestor := key
	while ChunkKey.level_of(ancestor) > 0:
		ancestor = ChunkKey.parent_of(ancestor)
		if _terrain._displayed.has(ancestor):
			return ["coarse", ChunkKey.level_of(key) - ChunkKey.level_of(ancestor)]
	return ["hole", 0]


func _sample(state: Array) -> void:
	var viewer: WorldPos = state[0]
	var altitude: float = state[2]
	var vp := Vector3(viewer.x, viewer.y, viewer.z)
	var ground := vp.normalized() * _planet.radius
	var near_radius := maxf(8000.0, altitude * NEAR_FACTOR)
	var counts := {"exact": 0, "preview": 0, "finer": 0, "coarse": 0, "hole": 0}
	var near := {"exact": 0, "preview": 0, "finer": 0, "coarse": 0, "hole": 0, "total": 0, "deficit_max": 0}
	for key in _terrain._desired:
		var c := _classify(key)
		counts[c[0]] += 1
		var center := _terrain.planner.chunk_center(key)
		if center.distance_to(ground) <= near_radius:
			near[c[0]] += 1
			near["total"] += 1
			near["deficit_max"] = maxi(near["deficit_max"], c[1])
	# Ahead: what the planner wants at the true future position, how much of it is on screen now.
	var future: Array = _state_at(_t + LOOKAHEAD_S)
	var future_leaves := _terrain.planner.select_leaves(future[0])
	var fp := Vector3(future[0].x, future[0].y, future[0].z)
	var fground := fp.normalized() * _planet.radius
	var fnear := maxf(8000.0, float(future[2]) * NEAR_FACTOR)
	var ahead_total := 0
	var ahead_ready := 0
	for key in future_leaves:
		if _terrain.planner.chunk_center(key).distance_to(fground) > fnear:
			continue
		ahead_total += 1
		var c := _classify(key)
		if c[0] == "exact" or c[0] == "finer":
			ahead_ready += 1
	var stats := _terrain.stream_stats()
	var sample := {
		"t": snappedf(_t, 0.01), "alt": roundi(altitude), "speed": roundi((state[1] as Vector3).length()),
		"desired": stats["desired_count"], "displayed": stats["displayed_count"], "pending": stats["pending_count"],
		"queued": stats["queued_count"], "cache": _terrain.ready_cache_entries(), "cache_kb": _terrain.ready_cache_bytes() / 1024,
		"completed": int(stats["completed"]) - _completed_at_start,
		"cov": counts, "near": near, "ahead_ready": float(ahead_ready) / maxf(1.0, ahead_total), "ahead_total": ahead_total,
		"desired_by_level": stats["desired_by_level"], "displayed_by_level": stats["displayed_by_level"],
	}
	_samples.append(sample)
	if _first_full_coverage < 0.0 and counts["hole"] == 0:
		_first_full_coverage = _t
	var near_good: int = near["exact"] + near["finer"]
	if _first_near_detail < 0.0 and near["total"] > 0 and near_good == near["total"]:
		_first_near_detail = _t
	if int(_t / SAMPLE_INTERVAL) % 4 == 0:
		_log("t=%5.1f alt=%6d v=%5d des=%3d disp=%3d pend=%d q=%3d cache=%3d | holes=%d coarse=%d prev=%d | near %d/%d exact+finer, coarse %d (deficit<=%d), holes %d | ahead %.0f%%" % [
			_t, sample["alt"], sample["speed"], sample["desired"], sample["displayed"], sample["pending"], sample["queued"], sample["cache"],
			counts["hole"], counts["coarse"], counts["preview"], near_good, near["total"], near["coarse"], near["deficit_max"], near["hole"], sample["ahead_ready"] * 100.0])


func _percentile(values: Array, p: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[clampi(int(round(p * (sorted.size() - 1))), 0, sorted.size() - 1)])


func _summarise() -> void:
	var stats := _terrain.stream_stats()
	var all_times: Array = []
	var by_level := {}
	for level in stats["build_times_by_level"]:
		var times: Array = stats["build_times_by_level"][level]
		all_times.append_array(times)
		by_level[level] = {"n": times.size(), "median_ms": snappedf(_percentile(times, 0.5), 0.1), "p95_ms": snappedf(_percentile(times, 0.95), 0.1)}
	var hole_samples := 0
	var max_holes := 0
	var near_fraction_sum := 0.0
	var near_coarse_max := 0
	var ahead_sum := 0.0
	var moving_samples := 0
	for s in _samples:
		var holes: int = s["cov"]["hole"]
		max_holes = maxi(max_holes, holes)
		if holes > 0:
			hole_samples += 1
		var near: Dictionary = s["near"]
		if near["total"] > 0:
			near_fraction_sum += float(near["exact"] + near["finer"]) / near["total"]
		near_coarse_max = maxi(near_coarse_max, near["deficit_max"])
		if s["speed"] > 100:
			ahead_sum += s["ahead_ready"]
			moving_samples += 1
	var frame_sorted := _frame_times.duplicate()
	var summary := {
		"scenario": _scenario,
		"duration_s": _duration,
		"builds_completed": int(stats["completed"]) - _completed_at_start,
		"builds_per_s": snappedf(float(int(stats["completed"]) - _completed_at_start) / _duration, 0.1),
		"build_median_ms": snappedf(_percentile(all_times, 0.5), 0.1),
		"build_p95_ms": snappedf(_percentile(all_times, 0.95), 0.1),
		"build_by_level": by_level,
		"samples_with_holes_pct": snappedf(100.0 * hole_samples / maxf(1, _samples.size()), 0.1),
		"max_holes": max_holes,
		"first_no_hole_s": snappedf(_first_full_coverage, 0.01),
		"first_full_near_detail_s": snappedf(_first_near_detail, 0.01),
		"near_detail_mean_pct": snappedf(100.0 * near_fraction_sum / maxf(1, _samples.size()), 0.1),
		"near_max_level_deficit": near_coarse_max,
		"ahead_ready_mean_pct": snappedf(100.0 * ahead_sum / maxf(1, moving_samples), 0.1),
		"cache_peak_kb": int(stats.get("cache_peak_bytes", 0)) / 1024,
		"cache_hits": stats.get("cache_hits", 0),
		"peak_queue": stats.get("peak_queue", 0),
		"frame_p95_ms": snappedf(_percentile(frame_sorted, 0.95) * 1000.0, 0.1),
		"plan_ms_max": snappedf(float(stats.get("plan_usec_max", 0)) / 1000.0, 0.1),
		"visibility_ms_max": snappedf(float(stats.get("visibility_usec_max", 0)) / 1000.0, 0.1),
		"plan_ms_mean": snappedf(float(stats.get("plan_usec_sum", 0)) / 1000.0 / maxf(1.0, float(stats.get("plan_count", 1))), 0.01),
		"visibility_ms_mean": snappedf(float(stats.get("visibility_usec_sum", 0)) / 1000.0 / maxf(1.0, float(stats.get("visibility_passes", 1))), 0.01),
		"upload_ms_max": snappedf(float(stats.get("upload_usec_max", 0)) / 1000.0, 0.1),
		"preview_builds": stats.get("preview_builds", 0),
		"full_builds": stats.get("full_builds", 0),
		"lookahead_s": snappedf(float(stats.get("lookahead_s", 0.0)), 0.01),
		"latency_ema_s": snappedf(float(stats.get("latency_ema_s", 0.0)), 0.01),
		"workers": stats.get("max_builds_in_flight", 8),
		"frame_max_ms": snappedf(_frame_time_max * 1000.0, 0.1),
	}
	_results[_scenario] = {"summary": summary, "samples": _samples}
	_log("SUMMARY " + JSON.stringify(summary))


func _finish() -> void:
	if _out_path != "":
		var file := FileAccess.open(_out_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(_results, "  "))
			file.close()
			_log("wrote " + _out_path)
	finished.emit(_results)
	if quit_when_done:
		get_tree().quit()
