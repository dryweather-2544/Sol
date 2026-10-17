class_name FlightModel
extends RefCounted
## The only code that turns a PilotCommand into ship motion. Pure and deterministic: the same
## command stream and fixed delta always produce the same state, so flights can be replayed.
##
## Assisted 6DOF: thrust on an axis accelerates toward a target speed for that axis; with no
## thrust the assist damps the axis to zero (unless lock_linear); brake damps everything.

const OVERSPEED_BLEED_RATE := 3.0


static func step(ship_state: ShipState, command: PilotCommand, tuning: ShipTuning, environment: FlightEnvironment, delta: float) -> void:
	ship_state.gear = clampi(command.gear, 0, mini(tuning.gear_count() - 1, environment.max_gear))
	_step_linear(ship_state, command, tuning, environment, delta)
	_step_angular(ship_state, command, tuning, delta)


static func _step_linear(ship_state: ShipState, command: PilotCommand, tuning: ShipTuning, environment: FlightEnvironment, delta: float) -> void:
	var boost_factor := tuning.boost_multiplier if command.boost else 1.0
	var max_speed := tuning.gear_max_speed[ship_state.gear] * boost_factor
	if ship_state.gear == PilotCommand.GEAR_CRUISE:
		max_speed = minf(max_speed, environment.cruise_speed_limit)
	else:
		max_speed *= environment.max_speed_factor
	var acceleration := tuning.gear_acceleration[ship_state.gear] * boost_factor
	var deceleration := tuning.gear_deceleration[ship_state.gear] * (tuning.brake_multiplier if command.brake else 1.0)
	var thrust := command.thrust.limit_length(1.0)
	var target_velocity := thrust * tuning.axis_strength * max_speed
	var local_velocity := ship_state.basis.transposed() * ship_state.velocity
	if not command.lock_linear or command.brake or thrust != Vector3.ZERO:
		for axis in 3:
			var current_speed: float = local_velocity[axis]
			var target_speed: float = target_velocity[axis]
			if command.brake or (thrust[axis] == 0.0 and not command.lock_linear):
				local_velocity[axis] = move_toward(current_speed, 0.0, deceleration * delta)
			elif thrust[axis] != 0.0:
				var speeding_up := signf(target_speed) == signf(current_speed) and absf(target_speed) > absf(current_speed) or current_speed == 0.0
				local_velocity[axis] = move_toward(current_speed, target_speed, (acceleration if speeding_up else deceleration) * delta)
		ship_state.velocity = ship_state.basis * local_velocity
	ship_state.velocity += environment.gravity * delta
	# Over the cap (gear shifted down, entering atmosphere, nearing ground): bleed the excess
	# off with a ~0.33 s time constant instead of snapping.
	var overspeed := ship_state.velocity.length() - max_speed
	if overspeed > 0.0 and not command.lock_linear:
		ship_state.velocity = ship_state.velocity.normalized() * (max_speed + overspeed * exp(-OVERSPEED_BLEED_RATE * delta))
	ship_state.position.x += ship_state.velocity.x * delta
	ship_state.position.y += ship_state.velocity.y * delta
	ship_state.position.z += ship_state.velocity.z * delta


static func _step_angular(ship_state: ShipState, command: PilotCommand, tuning: ShipTuning, delta: float) -> void:
	var turn := Vector3(clampf(command.turn.x, -1.0, 1.0), clampf(command.turn.y, -1.0, 1.0), clampf(command.turn.z, -1.0, 1.0))
	var target_rate := turn * tuning.max_turn_rate
	for axis in 3:
		var rate_change := (tuning.turn_acceleration if turn[axis] != 0.0 else tuning.turn_damping) * delta
		ship_state.angular_velocity[axis] = move_toward(ship_state.angular_velocity[axis], target_rate[axis], rate_change)
	var turn_angle := ship_state.angular_velocity.length() * delta
	if turn_angle > 1e-9:
		var rotation_step := Quaternion(ship_state.angular_velocity.normalized(), turn_angle)
		ship_state.basis = Basis((Quaternion(ship_state.basis) * rotation_step).normalized())
