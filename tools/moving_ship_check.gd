extends SceneTree
## Real-scene check (needs a display): walk inside the ship while it translates ~500 m/s, tumbles and the floating
## origin rebases. Boots main.tscn, stands the player up in orbit, forces a constant angular velocity on the unpiloted ship
## and measures what is actually rendered (interpolated transforms of the interior camera against the ship):
##   A  stand still      -> camera must stay put in ship space (drift), pointing the same way (no roll leak)
##   B  strafe across the cabin with the real input actions -> smooth camera motion (jitter), ship not steered by the walk keys
##   D  sit in the pilot seat -> a different camera takes over and the ship answers the player again
##   godot --path . -s res://tools/moving_ship_check.gd -- out.png
const SPIN := Vector3(0.12, 0.08, 0.5)

var _main: Node
var _frame := 0
var _phase := "setup"
var _phase_start := 0
var _start_velocity := Vector3.ZERO
var _start_local := Vector3.ZERO
var _rebase_count := 0
var _last_origin_x := 0.0
var _rows := {} # phase -> Array of per-render-frame dictionaries
var _max_thrust_seen := 0.0
var _log := []
var _delta := 0.0
var _marks := {} # name -> {t, v}
var _clock := 0.0
var _velocity_after_walking := Vector3.ZERO


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _physics_process(_delta: float) -> bool:
	if _phase in ["A", "B"] and _main != null:
		_main.ship.state.angular_velocity = SPIN # the ship keeps tumbling
		_max_thrust_seen = maxf(_max_thrust_seen, _main.ship.last_command.thrust.length())
	return false


func _process(delta: float) -> bool:
	_frame += 1
	_delta = delta
	_clock += delta
	var session: GameSession = _main.session
	var ship: Ship = _main.ship
	if _frame == 2:
		_main.menu.dismiss()
	if _frame == 20:
		session.interact() # stand up in orbit
		ship.state.velocity = Vector3(150.0, 0.0, -470.0)
		_start_velocity = ship.state.velocity
		session.interior_body.place(Vector3(-2.4, -0.9, -1.8), -PI / 2.0) # cabin, facing +x (yaw -90deg turns right)
		_main._on_mode_changed()
		_last_origin_x = ship.render_origin.x
		_phase = "A"
		_phase_start = _frame
		_log.append("stood up: mode %d, pilot source %s" % [session.mode, str(ship.controller.current_source)])
	if _phase == "A":
		if _frame - _phase_start > 15: # let the camera catch up with the teleport into the cabin first
			_record("A")
		if _frame - _phase_start == 16:
			_start_local = session.interior_body.position
			_marks["A_start"] = {"t": _clock, "v": ship.state.velocity}
		if _frame - _phase_start >= 315:
			_phase = "B"
			_phase_start = _frame
			_marks["A_end"] = {"t": _clock, "v": ship.state.velocity}
			Input.action_press("strafe_right")
	elif _phase == "B":
		_record("B")
		if _frame - _phase_start == 100:
			Input.action_release("strafe_right")
			Input.action_press("strafe_left")
		if _frame - _phase_start >= 200:
			Input.action_release("strafe_left")
			_velocity_after_walking = ship.state.velocity
			_marks["B_end"] = {"t": _clock, "v": ship.state.velocity}
			_phase = "D0"
			_phase_start = _frame
	elif _phase == "D0":
		# Stop the tumble and sit down at the pilot seat.
		ship.state.angular_velocity = Vector3.ZERO
		var seat: Dictionary = session.systems.layout.seats[&"pilot_seat"]
		session.interior_body.place(seat["exit_position"], 0.0)
		session.interact()
		_phase = "D"
		_phase_start = _frame
	elif _phase == "D" and _frame - _phase_start == 90:
		_report(session, ship)
		quit()
	if _phase in ["A", "B"]:
		if absf(ship.render_origin.x - _last_origin_x) > 100.0 or absf(ship.render_origin.y - _last_origin_x) > 1e9:
			_rebase_count += 1
		_last_origin_x = ship.render_origin.x
	return false


func _interior_camera() -> Camera3D:
	return _main.interior_view.camera


func _record(phase: String) -> void:
	var ship: Ship = _main.ship
	var camera := _interior_camera()
	var ship_transform := ship.get_global_transform_interpolated()
	var camera_transform := camera.get_global_transform_interpolated()
	var local_position := ship_transform.affine_inverse() * camera_transform.origin
	var relative_basis := ship_transform.basis.orthonormalized().inverse() * camera_transform.basis.orthonormalized()
	var body: InteriorBody = _main.session.interior_body
	var expected_position := body.position + Vector3(0, InteriorBody.EYE_HEIGHT, 0)
	var expected_basis := Basis(Vector3.UP, body.yaw)
	var current_cameras := 0
	for node in root.find_children("*", "Camera3D", true, false):
		if (node as Camera3D).current:
			current_cameras += 1
	if not _rows.has(phase):
		_rows[phase] = []
	_rows[phase].append({"local": local_position, "position_error": local_position.distance_to(expected_position),
		"roll_leak": absf(relative_basis.x.y), "yaw_error": rad_to_deg((relative_basis * expected_basis.inverse()).get_euler().length()),
		"viewport_camera_is_interior": root.get_camera_3d() == camera, "current_cameras": current_cameras,
		"body": body.position, "ship_speed": ship.state.velocity.length(), "delta": _delta})


func _report(session: GameSession, ship: Ship) -> void:
	var rows_a: Array = _rows["A"]
	var drift_camera := 0.0
	for row in rows_a:
		drift_camera = maxf(drift_camera, (row["local"] as Vector3).distance_to(rows_a[0]["local"]))
	var drift_body := (session.interior_body.position).distance_to(_start_local) if false else 0.0
	for row in rows_a:
		drift_body = maxf(drift_body, (row["body"] as Vector3).distance_to(_start_local))
	print("PHASE A (standing still 300 frames, ship %.0f m/s tumbling, %d origin rebases so far)" % [rows_a[0]["ship_speed"], _rebase_count])
	print("  body drift in ship space: max %.6f m;  rendered camera drift in ship space: max %.6f m" % [drift_body, drift_camera])
	_print_phase_stats("A", rows_a)
	var rows_b: Array = _rows["B"]
	_print_phase_stats("B", rows_b)
	# Smoothness: camera speed in ship space (step / frame time) during free strafing (not ramping up, not stopped by a wall); 3 m/s is the walk speed.
	var speeds: Array[float] = []
	var sample := []
	for index in range(1, rows_b.size()):
		var steady := (index > 8 and index < 46) or (index > 108 and index < 189) # free travel; the rest is the start ramp or a wall stop
		if steady:
			var speed: float = (rows_b[index]["local"] as Vector3).distance_to(rows_b[index - 1]["local"]) / maxf(rows_b[index]["delta"], 1e-6)
			speeds.append(speed)
			if sample.size() < 24:
				sample.append("%.2f" % speed)
	var mean := 0.0
	for value in speeds:
		mean += value
	mean /= maxf(speeds.size(), 1.0)
	var variance := 0.0
	var fastest := 0.0
	var slowest := INF
	for value in speeds:
		variance += (value - mean) * (value - mean)
		fastest = maxf(fastest, value)
		slowest = minf(slowest, value)
	print("  steady strafe, camera speed in ship space over %d frames: mean %.3f m/s (walk speed 3.0), min %.3f, max %.3f, stddev %.3f m/s" % [speeds.size(), mean, slowest, fastest, sqrt(variance / maxf(speeds.size(), 1.0))])
	print("  first speeds (m/s): ", " ".join(sample))
	var slow_frames := []
	for index in range(1, rows_b.size()):
		var speed_here: float = (rows_b[index]["local"] as Vector3).distance_to(rows_b[index - 1]["local"]) / maxf(rows_b[index]["delta"], 1e-6)
		if speed_here < 2.0:
			slow_frames.append("%d:%.2f(body x %.2f)" % [index, speed_here, rows_b[index]["body"].x])
	print("  frames below 2 m/s in phase B: ", " ".join(slow_frames))
	var worst_step := 0.0
	for index in range(1, rows_b.size()):
		worst_step = maxf(worst_step, (rows_b[index]["local"] as Vector3).distance_to(rows_b[index - 1]["local"]))
	print("  largest single-frame camera step in phase B (any frame, incl. reversal): %.4f m" % worst_step)
	var accel_a: Vector3 = (_marks["A_end"]["v"] - _marks["A_start"]["v"]) / (_marks["A_end"]["t"] - _marks["A_start"]["t"])
	var accel_b: Vector3 = (_marks["B_end"]["v"] - _marks["A_end"]["v"]) / (_marks["B_end"]["t"] - _marks["A_end"]["t"])
	print("  ship acceleration with no keys (phase A) %.3f m/s^2 vs while strafing (phase B) %.3f m/s^2, difference %.4f m/s^2 (gravity pulls the unpiloted ship; walking must add nothing)" % [accel_a.length(), accel_b.length(), (accel_a - accel_b).length()])
	var velocity_error := (accel_a - accel_b).length()
	print("  DUPLICATE CONTROL: max ship thrust command while walking %.4f; ship had a pilot source: %s" % [_max_thrust_seen, "yes" if _log[0].ends_with("<null>") == false else "no"])
	print("  walking added acceleration: %.4f m/s^2" % velocity_error)
	print("PHASE D (sat down in the pilot seat)")
	print("  player mode %d (0 = seated), pilot source is the player: %s" % [session.mode, str(ship.controller.current_source == _main.player_source)])
	var active := root.get_camera_3d()
	print("  active camera: %s on %s (interior camera current: %s)" % [active.get_script().get_global_name() if active.get_script() != null else active.get_class(), active.get_parent().name, str(active == _interior_camera())])
	var current_cameras := 0
	for node in root.find_children("*", "Camera3D", true, false):
		if (node as Camera3D).current:
			current_cameras += 1
	print("  Camera3D nodes marked current: %d" % current_cameras)
	for line in _log:
		print("  log: ", line)
	var path := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "moving.png"
	root.get_viewport().get_texture().get_image().save_png(path)


func _print_phase_stats(phase: String, rows: Array) -> void:
	var worst_position := 0.0
	var worst_roll := 0.0
	var worst_yaw := 0.0
	var max_cameras := 0
	var interior_active_all := true
	for row in rows:
		worst_position = maxf(worst_position, row["position_error"])
		worst_roll = maxf(worst_roll, row["roll_leak"])
		worst_yaw = maxf(worst_yaw, row["yaw_error"])
		max_cameras = maxi(max_cameras, row["current_cameras"])
		interior_active_all = interior_active_all and row["viewport_camera_is_interior"]
	print("  [%s] %d frames: camera vs body+eye max %.4f m;  roll leaking from the ship into the view max %.5f;  view-yaw error max %.3f deg;  Camera3D 'current' count max %d;  viewport camera is the interior camera every frame: %s" % [phase, rows.size(), worst_position, worst_roll, worst_yaw, max_cameras, str(interior_active_all)])
