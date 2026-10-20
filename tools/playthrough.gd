extends SceneTree
## Plays the whole loop through the REAL main scene (cameras, overlay, audio, POIs, director all running),
## using actual input events for the use key and held movement actions; only aiming is a test cheat
## (the bot sets the walking yaw directly and flies the descent with a scripted pilot).
##   godot --path . -s res://tools/playthrough.gd
## Needs a display. Prints one line per stage and a final verdict; look for SCRIPT ERROR lines too.

class Bot extends PilotSource:
	var phase := 0 # 0 descend, 1 hold, 2 take off
	func _init() -> void:
		source_id = &"playthrough"
	func poll(ship_state: ShipState, _delta: float) -> PilotCommand:
		var command := PilotCommand.new()
		command.move_lock = 1.0 # scripted pilot: holds the velocity it asks for (Rodina AI mover MoveLock)
		command.stop_rotation = true # and holds its attitude (Rodina AI sets its turn rate directly)
		var altitude := ship_state.altitude_above_ground
		match phase:
			0:
				var up := Vector3(ship_state.position.x, ship_state.position.y, ship_state.position.z).normalized()
				ship_state.basis = Basis.looking_at(Vector3.UP.cross(up).normalized(), up)
				command.gear = PilotCommand.GEAR_CRUISE if altitude > 2100.0 else (PilotCommand.GEAR_COMBAT if altitude > 250.0 else PilotCommand.GEAR_DOCK)
				command.thrust = Vector3(0, -clampf(altitude / 80.0, 0.04, 1.0), 0)
			2:
				command.gear = PilotCommand.GEAR_CRUISE if altitude > 2500.0 else PilotCommand.GEAR_COMBAT
				command.thrust = Vector3(0, 1, 0)
			_:
				command.gear = ship_state.gear
		return command


var _main: Node
var _bot := Bot.new()
var _frames := 0
var _step := 0
var _wait := 0
var _log := []
## Cockpit to airlock: a door panel (press use), then the two points that line up with and pass through the doorway.
var _waypoints_inside := [Vector2(0.8, -4.0), Vector2(0.0, -3.9),
	Vector2(1.0, -0.5), Vector2(0.0, -0.6), Vector2(0.0, 0.6),
	Vector2(1.0, 2.9), Vector2(0.0, 3.0), Vector2(0.0, 3.9),
	Vector2(1.0, 5.3), Vector2(0.0, 5.4), Vector2(0.0, 6.4),
	Vector2(1.0, 7.6), Vector2(0.0, 7.9), Vector2(0.0, 9.3), Vector2(1.2, 8.9)]
const _PANEL_WAYPOINTS := [0, 2, 5, 8, 11, 14]
var _waypoint := 0


func _initialize() -> void:
	Engine.time_scale = 3.0
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _press_use() -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	Input.parse_input_event(event)


func _say(text: String) -> void:
	print("[%5d] %s" % [_frames, text])


func _walk_to(target: Vector2) -> bool:
	var body: InteriorBody = _main.session.interior_body
	var to_target := target - Vector2(body.position.x, body.position.z)
	if to_target.length() < 0.25:
		Input.action_release("thrust_forward")
		return true
	body.yaw = atan2(-to_target.x, -to_target.y)
	Input.action_press("thrust_forward")
	return false


func _process(_delta: float) -> bool:
	_frames += 1
	var session: GameSession = _main.session
	if _wait > 0:
		_wait -= 1
		return false
	if _frames == 2:
		_main.menu.dismiss()
		_main.session.progress.warp_installed = true
		_main.ship.controller.release_control(_main.player_source)
		_main.ship.controller.request_control(_bot, &"pilot_seat")
		_say("descending")
		return false
	match _step:
		0: # descend and land
			if session.ship.state.landed:
				_bot.phase = 1
				_say("landed, hull %.0f%%" % (session.ship.state.hull * 100.0))
				_step = 1
				_wait = 60
		1:
			_press_use()
			_step = 2
			_wait = 30
		2:
			if session.mode != GameSession.Mode.INSIDE:
				_say("FAIL: could not stand up")
				return _finish()
			_say("standing inside the ship")
			_step = 3
		3: # walk the waypoint list, using doors at the door panels
			if _walk_to(_waypoints_inside[_waypoint]):
				if _waypoint in _PANEL_WAYPOINTS:
					_press_use()
					_wait = 100
				_say("waypoint %d reached at %s" % [_waypoint, str(session.interior_body.position)])
				_waypoint += 1
				if _waypoint >= _waypoints_inside.size():
					_step = 10
		10: # outer door
			if _walk_to(Vector2(1.2, 9.8)):
				_press_use()
				_wait = 220
				_step = 11
		11: # out the door and down the ramp
			if session.mode == GameSession.Mode.OUTSIDE:
				_say("outside on foot")
				_step = 12
			else:
				_walk_to(Vector2(0.0, 16.6))
		12: # back to the ramp
			var target_world := ShipFrame.world_from_local(session.ship.state, Vector3(0, -2.0, 12.6))
			var to_target := target_world.vector_from(session.exterior_body.position)
			var up := session.planet.up_at(session.exterior_body.position)
			to_target -= up * to_target.dot(up)
			if session.mode == GameSession.Mode.INSIDE:
				Input.action_release("thrust_forward")
				_say("back inside")
				_step = 13
			else:
				if to_target.length() > 0.05:
					session.exterior_body.heading = to_target.normalized()
				Input.action_press("thrust_forward")
		13:
			var targets := [Vector2(0.0, 11.2), Vector2(0.0, 9.6), Vector2(1.2, 9.8)]
			if _walk_to(targets[_sub]):
				_sub += 1
				if _sub >= targets.size():
					_press_use() # close the outer door
					_wait = 300
					_step = 14
					_sub = 0
		14:
			var path := [Vector2(1.2, 8.9), Vector2(0.0, 7.6), Vector2(0.0, 5.0), Vector2(0.0, 2.0), Vector2(0.0, 0.0), Vector2(0.0, -3.0), Vector2(0.0, -4.95)]
			if _sub == 1 and not session.systems.airlock.inner.is_passable() and not session.systems.airlock.inner.target_open:
				pass
			if _walk_to(path[_sub]):
				if _sub == 0:
					_press_use() # inner door
					_wait = 140
				_sub += 1
				if _sub >= path.size():
					_step = 15
					_sub = 0
		15:
			_press_use() # sit
			_wait = 90
			_step = 16
		16:
			if session.mode != GameSession.Mode.SEATED:
				_say("FAIL: not seated (mode %d)" % session.mode)
				return _finish()
			_say("seated in the pilot seat, takeoff block: '%s'" % session.systems.takeoff_block_reason())
			_bot.phase = 2
			ship_reset()
			_step = 17
		17:
			if session.ship.state.regime == FlightRegime.SPACE:
				_say("back in space: PLAYTHROUGH OK")
				return _finish()
	if _frames % 600 == 0:
		_say("step %d mode %d pos %s speed %s" % [_step, session.mode, str(session.interior_body.position), str(session.interior_body.velocity)])
	if _frames > 40000:
		_say("FAIL: timed out in step %d (mode %d)" % [_step, session.mode])
		return _finish()
	return false


var _sub := 0


func ship_reset() -> void:
	_main.ship.controller.release_control(_main.player_source) # sitting re-granted control to the player; hand it to the bot
	_main.ship.controller.request_control(_bot, &"pilot_seat")


func _finish() -> bool:
	Input.action_release("thrust_forward")
	quit()
	return true
