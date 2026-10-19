class_name FlightModel
extends RefCounted
## The only code that turns a PilotCommand into ship motion. Pure and deterministic: the same
## command stream and fixed delta always produce the same state, so flights can be replayed.
##
## Assisted 6DOF: thrust on an axis accelerates toward a target speed for that axis; with no
## thrust the assist damps the axis to zero (unless lock_linear); brake damps everything.
## Local axes are +X right, +Y up, -Z forward. The per-gear strengths are the Rodina evidence
## mapped by ShipTuning: right/up/forward -> right/up/-forward.

const OVERSPEED_BLEED_RATE := 3.0
const LEVEL_ASSIST_GAIN := 2.0
const FACE_SLOWDOWN_ANGLE := 0.5


static func step(ship_state: ShipState, command: PilotCommand, tuning: ShipTuning, environment: FlightEnvironment, delta: float) -> void:
	ship_state.gear = clampi(command.gear, 0, mini(tuning.gear_count() - 1, environment.max_gear))
	_step_linear(ship_state, command, tuning, environment, delta)
	_step_angular(ship_state, command, tuning, environment, delta)


static func _step_linear(ship_state: ShipState, command: PilotCommand, tuning: ShipTuning, environment: FlightEnvironment, delta: float) -> void:
	var boost_factor := tuning.boost_multiplier if command.boost else 1.0
	var max_speed := tuning.gear_max_speed[ship_state.gear] * boost_factor
	if ship_state.gear == PilotCommand.GEAR_CRUISE:
		max_speed = minf(max_speed, environment.cruise_speed_limit)
	else:
		max_speed *= environment.max_speed_factor
	var acceleration := tuning.gear_acceleration[ship_state.gear] * boost_factor
	if ship_state.gear == PilotCommand.GEAR_CRUISE:
		# Cruise is a sustained burn, not an instant teleport to the cap. At a 12 km/s limit this
		# reaches the limit in roughly 8 s; at low caps the base acceleration dominates.
		acceleration = maxf(acceleration, max_speed * 0.10)
	var deceleration := tuning.gear_deceleration[ship_state.gear] * (tuning.brake_multiplier if command.brake else 1.0)
	# Cruise is the free-flight regime: leave most of the velocity intact when the pilot releases
	# thrust. DOCK/COMBAT stay assisted for precise low-speed work; X is the explicit brake.
	var damping_scale := 1.0 if ship_state.gear != PilotCommand.GEAR_CRUISE else 0.01
	var thrust := command.thrust.limit_length(1.0)
	var target_velocity := thrust * tuning.axis_strength_for(ship_state.gear) * max_speed
	var local_velocity := ship_state.basis.transposed() * ship_state.velocity
	if not command.lock_linear or command.brake or thrust != Vector3.ZERO:
		for axis in 3:
			var current_speed: float = local_velocity[axis]
			var target_speed: float = target_velocity[axis]
			if command.brake or (thrust[axis] == 0.0 and not command.lock_linear):
				local_velocity[axis] = move_toward(current_speed, 0.0, deceleration * (1.0 if command.brake else damping_scale) * delta)
			elif thrust[axis] != 0.0:
				var speeding_up := signf(target_speed) == signf(current_speed) and absf(target_speed) > absf(current_speed) or current_speed == 0.0
				local_velocity[axis] = move_toward(current_speed, target_speed, (acceleration if speeding_up else deceleration) * delta)
		ship_state.velocity = ship_state.basis * local_velocity
	ship_state.velocity += environment.gravity * delta
	# Atmospheric drag acts on the actual velocity vector. It is the main decelerator during an
	# entry; it also lets the ship carry entry speed after the gear is forced down near the ground.
	if environment.drag_acceleration > 0.0 and not ship_state.landed:
		ship_state.velocity = ship_state.velocity.move_toward(Vector3.ZERO, environment.drag_acceleration * delta)
	# In vacuum, a gear change still needs to shed excess speed. In air, don't snap to the gear cap:
	# the drag model and the pilot's brake do that work. A very high hard cap is only a safety net.
	var overspeed := ship_state.velocity.length() - max_speed
	if overspeed > 0.0 and not command.lock_linear:
		if environment.air_density > 0.001:
			var hard_cap := maxf(max_speed * 8.0, 30000.0)
			var hard_overspeed := ship_state.velocity.length() - hard_cap
			if hard_overspeed > 0.0:
				ship_state.velocity = ship_state.velocity.normalized() * (hard_cap + hard_overspeed * exp(-OVERSPEED_BLEED_RATE * delta))
		else:
			ship_state.velocity = ship_state.velocity.normalized() * (max_speed + overspeed * exp(-OVERSPEED_BLEED_RATE * delta))
	ship_state.position.x += ship_state.velocity.x * delta
	ship_state.position.y += ship_state.velocity.y * delta
	ship_state.position.z += ship_state.velocity.z * delta


static func _step_angular(ship_state: ShipState, command: PilotCommand, tuning: ShipTuning, environment: FlightEnvironment, delta: float) -> void:
	var turn := Vector3(clampf(command.turn.x, -1.0, 1.0), clampf(command.turn.y, -1.0, 1.0), clampf(command.turn.z, -1.0, 1.0))
	if command.face_direction != Vector3.ZERO:
		# Rodina SetDesiredFacing sets angular velocity directly (with arrival scaling near the
		# target); it deliberately bypasses the player's rotational inertia.
		var facing := turn_toward(ship_state.basis, command.face_direction)
		var facing_strength := clampf(facing.length(), 0.0, 1.0)
		ship_state.angular_velocity = facing.normalized() * tuning.rotation_speed * facing_strength if facing_strength > 0.0 else Vector3.ZERO
		_integrate_rotation(ship_state, delta)
		return
	var desired_strength := clampf(turn.length(), 0.0, 1.0)
	# Rodina squares analogue input for precision; binary keys stay at full strength.
	var desired := turn * desired_strength
	var hardness := tuning.rotation_hardness_for(ship_state.gear)
	# Rotation friction is strongest when coasting (strength=0) and vanishes while turning.
	# In vacuum the recovered game uses zero friction and retains angular momentum.
	var friction_rate := tuning.rotation_friction_atmosphere * clampf(environment.air_density * 8.0, 0.0, 1.0)
	var friction := clampf(friction_rate * pow(1.0 - desired_strength, 2.0) * delta, 0.0, 1.0)
	ship_state.angular_velocity *= (1.0 - friction)
	# Rodina: pitch/yaw acceleration = desired * hardness * RotationSpeed; roll uses a larger
	# 3x roll factor and a separate +/-2*RotationSpeed cap.
	var acceleration := Vector3(
		desired.x * hardness,
		desired.y * hardness,
		desired.z * minf(2.0, hardness) * 3.0) * tuning.rotation_speed * delta
	ship_state.angular_velocity += acceleration
	var yaw_pitch := Vector2(ship_state.angular_velocity.x, ship_state.angular_velocity.y)
	if yaw_pitch.length() > tuning.rotation_speed:
		yaw_pitch = yaw_pitch.normalized() * tuning.rotation_speed
	ship_state.angular_velocity.x = yaw_pitch.x
	ship_state.angular_velocity.y = yaw_pitch.y
	ship_state.angular_velocity.z = clampf(ship_state.angular_velocity.z, -2.0 * tuning.rotation_speed, 2.0 * tuning.rotation_speed)
	if environment.level_assist > 0.0:
		var level_in_ship_axes := ship_state.basis.transposed() * environment.level_up
		if turn.x == 0.0:
			ship_state.angular_velocity.x += clampf(level_in_ship_axes.z * LEVEL_ASSIST_GAIN, -tuning.rotation_speed * 0.5, tuning.rotation_speed * 0.5) * environment.level_assist * delta
		if turn.z == 0.0:
			ship_state.angular_velocity.z += clampf(-level_in_ship_axes.x * LEVEL_ASSIST_GAIN, -tuning.rotation_speed * 0.5, tuning.rotation_speed * 0.5) * environment.level_assist * delta
	_integrate_rotation(ship_state, delta)


static func _integrate_rotation(ship_state: ShipState, delta: float) -> void:
	var turn_angle := ship_state.angular_velocity.length() * delta
	if turn_angle > 1e-9:
		var rotation_step := Quaternion(ship_state.angular_velocity.normalized(), turn_angle)
		ship_state.basis = Basis((Quaternion(ship_state.basis) * rotation_step).normalized())


## Turn demand (pitch, yaw, 0) that swings the nose toward a world direction. The demand eases off
## within FACE_SLOWDOWN_ANGLE of the target so the ship settles instead of overshooting.
static func turn_toward(basis: Basis, world_direction: Vector3) -> Vector3:
	var local := (basis.transposed() * world_direction.normalized())
	var pitch_error := atan2(local.y, -local.z)
	var yaw_error := atan2(-local.x, -local.z)
	if local.z > 0.0:
		# Target is behind: turn by the larger error so the ship does not stall at exactly 180 degrees.
		yaw_error = PI if absf(yaw_error) < 0.05 else yaw_error
	return Vector3(clampf(pitch_error / FACE_SLOWDOWN_ANGLE, -1.0, 1.0), clampf(yaw_error / FACE_SLOWDOWN_ANGLE, -1.0, 1.0), 0.0)
