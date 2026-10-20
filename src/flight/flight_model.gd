class_name FlightModel
extends RefCounted
## The only code that turns a PilotCommand into ship motion. Pure and deterministic: the same command stream and
## fixed delta always produce the same state, so flights can be replayed.
##
## Sol's implementation of the rules in Rodina 1.6.2's EGVehicle (Scripts/Gameplay/EGVehicle.lua; line numbers below,
## evidence and the Sol-vs-Rodina differences in docs/RODINA_PHYSICS_AUDIT.md):
## - Thrust steers the velocity toward a target (input x MoveSpeed) at a limited rate (SetDesiredMovement, 1458-1517).
##   With no input nothing is applied: the ship keeps its momentum and gravity keeps acting. Drag only above
##   DragSpeed (1473-1477). Sideways, vertical and reverse input are weaker unless braking (1482-1492).
## - Turn input accelerates the spin (SetDesiredRotation, 1263-1366). Releasing it leaves the ship spinning; rotation
##   friction, zero in space and the planet's AtmosphereFriction deep in its air, slows it only while not turning.
## - AI facing sets the turn rate directly (SetDesiredFacing, 1212-1244), a separate path from the player's.
## - Gravity is planet gravity scaled for ships (SetDesiredMovement 1548-1554; PlanetBody.ship_gravity_at).
## - In the atmosphere the ship's roll (never its pitch) is eased level, by an angular acceleration, unless the nose is
##   steep or the pilot is rolling (UpdateLevel, 1152-1198; EGBehaviorPlayer:UpdateAutolevel).
## Ship-local axes (Sol): x right, y up, -z forward; turn x pitch (+ nose up), y yaw (+ nose left), z roll (+ left wing
## down). Rodina's local axes are x right, y forward, z up, with turn x yaw, y pitch, z roll; the mapping is per axis.

const ENTRY_COMPLETE_SECONDS := 4.0 ## Rodina kAtmoEntryCompleteDuration
## Rodina kAtmospherePushMult (x MovementDifficulty x AtmosphereEntryPush, both 1 by default), per 1/60 s update.
const ENTRY_PUSH_PER_TICK := 0.005
## Rodina's ShipLookSpeed option default (1.25) scales the player's pitch/yaw push (EGOptions.lua:100).
const PLAYER_LOOK_SPEED := 1.25
## Cruise above its (distance-scaled) speed limit sheds the excess at this rate, 1/s: Sol's equivalent of Rodina's
## relative time falling back to its target (relativeTime * dt * 2, EGVehicle.lua:1462-1464).
const CRUISE_EXCESS_DECAY := 2.0
## Rodina's drag is applied twice: to the inertia the next velocity is built from and as an engine acceleration
## (EGVehicle.lua:1474-1476), so the effective rate is twice min(1, Deceleration).
const DRAG_APPLICATIONS := 2.0
const ROLL_SPEED_RATIO := 2.0 ## roll rate cap = 2 x rotation speed
const ROLL_ACCELERATION_GAIN := 3.0
const MAX_ROLL_HARDNESS := 2.0
## Roll levelling (UpdateLevel): gain on the roll error, gain on the acceleration toward the levelling rate, and the
## roll error below which the levelling rate tapers off (radians).
const LEVEL_ROLL_GAIN := 3.0
const LEVEL_ACCELERATION_GAIN := 3.0
const LEVEL_ARRIVAL_ANGLE := 0.3
## Roll input at which levelling is fully held off, and how fast the hold-off fades once rolling stops (per second).
const LEVEL_BLOCK_FULL_INPUT := 0.4
const LEVEL_BLOCK_DECAY := 1.0
## AI facing: within this angle the turn rate eases off so the ship settles (Sol's own; Rodina eases within 0.1 rad/s).
const FACE_SLOWDOWN_ANGLE := 0.5


static func step(ship_state: ShipState, command: PilotCommand, tuning: ShipTuning, environment: FlightEnvironment, delta: float) -> void:
	ship_state.gear = clampi(command.gear, 0, mini(tuning.gear_count() - 1, environment.max_gear))
	_update_atmosphere_state(ship_state, environment, delta)
	_step_linear(ship_state, command, tuning, environment, delta)
	_step_angular(ship_state, command, tuning, environment, delta)
	_entry_push(ship_state, environment, delta)


## Rodina EGVehicle:UpdateInAtmosphereState (977-1037).
static func _update_atmosphere_state(ship_state: ShipState, environment: FlightEnvironment, delta: float) -> void:
	var ratio := environment.atmosphere_ratio
	if not ship_state.atmosphere_state_known:
		ship_state.atmosphere_state_known = true
		ship_state.in_atmosphere = ratio < 0.5
		ship_state.entering_atmosphere = ratio >= 0.5 and ratio < 1.0
	if ratio < 0.5:
		if not ship_state.in_atmosphere:
			ship_state.entering_atmosphere = false
			ship_state.in_atmosphere = true
			ship_state.entry_complete_timer = ENTRY_COMPLETE_SECONDS
	elif ratio < 1.0:
		if not ship_state.in_atmosphere:
			ship_state.entering_atmosphere = true
	else:
		ship_state.entering_atmosphere = false
		ship_state.in_atmosphere = false
	ship_state.entry_complete_timer = maxf(0.0, ship_state.entry_complete_timer - delta)


static func _step_linear(ship_state: ShipState, command: PilotCommand, tuning: ShipTuning, environment: FlightEnvironment, delta: float) -> void:
	var gear := ship_state.gear
	var boost_factor := tuning.boost_multiplier if command.boost else 1.0
	var move_speed := tuning.gear_max_speed[gear] * boost_factor
	if gear == PilotCommand.GEAR_CRUISE:
		move_speed = minf(move_speed, environment.cruise_speed_limit)
	var acceleration_factor: float = tuning.gear_acceleration[gear]
	var deceleration_factor: float = tuning.gear_deceleration[gear]
	var velocity := ship_state.basis.transposed() * ship_state.velocity # ship-local
	if not command.lock_linear:
		var speed := velocity.length()
		var direction := velocity / speed if speed > 1e-9 else Vector3.ZERO
		# Engine drag only well over the gear's speed (e.g. 1500 m/s in dock and combat; none in cruise).
		if speed > tuning.gear_drag_speed_ratio[gear] * move_speed:
			velocity *= maxf(0.0, 1.0 - DRAG_APPLICATIONS * minf(1.0, deceleration_factor) * delta)
		var wish := command.thrust.limit_length(1.0)
		var braking := 0.0
		var target := Vector3.ZERO
		var strength := 0.0
		if command.brake:
			# Sol's brake key: drive the velocity to zero at full strength, with Rodina's braking rate.
			braking = 1.0
			strength = 1.0
		else:
			braking = clampf(-wish.dot(direction), 0.0, 1.0)
			target = wish
			if braking <= 0.0:
				target.x *= tuning.gear_lateral_strength[gear]
				target.y *= tuning.gear_vertical_strength[gear]
				if target.z > 0.0: # backwards
					target.z *= tuning.gear_reverse_strength[gear]
			strength = target.length()
			target *= move_speed
		var rate := acceleration_factor * move_speed
		if speed > move_speed and braking > 0.0:
			rate = maxf(acceleration_factor, deceleration_factor) * speed
		if command.brake:
			rate *= tuning.brake_multiplier
		var to_target := target - velocity
		var gap := to_target.length()
		var change := minf(gap, rate * strength * delta)
		if command.move_lock > 0.0:
			change = maxf(change, gap * clampf(command.move_lock, 0.0, 1.0))
		if gap > 1e-9:
			velocity += to_target * (change / gap)
		if gear == PilotCommand.GEAR_CRUISE and environment.cruise_speed_limit < INF:
			var over := velocity.length() - environment.cruise_speed_limit * boost_factor
			if over > 0.0:
				velocity = velocity.normalized() * (velocity.length() - over * (1.0 - exp(-CRUISE_EXCESS_DECAY * delta)))
	ship_state.velocity = ship_state.basis * velocity
	ship_state.velocity += environment.gravity * delta
	ship_state.position.x += ship_state.velocity.x * delta
	ship_state.position.y += ship_state.velocity.y * delta
	ship_state.position.z += ship_state.velocity.z * delta


static func _step_angular(ship_state: ShipState, command: PilotCommand, tuning: ShipTuning, environment: FlightEnvironment, delta: float) -> void:
	if command.stop_rotation:
		ship_state.angular_velocity = ship_state.angular_velocity.move_toward(Vector3.ZERO, tuning.rotation_speed * tuning.gear_rotation_hardness[ship_state.gear] * 4.0 * delta)
	elif command.face_direction != Vector3.ZERO:
		var face := turn_toward(ship_state.basis, command.face_direction)
		ship_state.angular_velocity = Vector3(face.x * tuning.rotation_speed, face.y * tuning.rotation_speed, 0.0)
	else:
		_player_rotation(ship_state, command.turn, tuning, environment, delta)
	_level_roll(ship_state, command.turn.z, environment, delta)
	var turn_angle := ship_state.angular_velocity.length() * delta
	if turn_angle > 1e-9:
		var rotation_step := Quaternion(ship_state.angular_velocity.normalized(), turn_angle)
		ship_state.basis = Basis((Quaternion(ship_state.basis) * rotation_step).normalized())


## Entry resistance (ShipDamage.entry_resistance) and its push: the air turns the nose away from the planet in
## proportion to the resistance (EGVehicle.lua:1126-1131: angles to the up direction x resistance x 0.005 added to the
## spin each update; scaled here to Sol's 60 Hz tick so it does not depend on the tick rate).
static func _entry_push(ship_state: ShipState, environment: FlightEnvironment, delta: float) -> void:
	ship_state.atmosphere_resistance = ShipDamage.entry_resistance(ship_state.velocity, -environment.level_up, environment.atmosphere_ratio, ship_state.in_atmosphere, ship_state.entry_complete_timer, ENTRY_COMPLETE_SECONDS)
	if ship_state.atmosphere_resistance <= 0.0:
		return
	var up_local := ship_state.basis.transposed() * environment.level_up
	var pitch_to_up := atan2(up_local.y, Vector2(up_local.x, up_local.z).length())
	var yaw_to_up := atan2(-up_local.x, -up_local.z)
	var push := ship_state.atmosphere_resistance * ENTRY_PUSH_PER_TICK * delta * 60.0
	ship_state.angular_velocity += Vector3(pitch_to_up * push, yaw_to_up * push, 0.0)


## Rotation friction for this gear here: the planet's AtmosphereFriction at and below the gear's full-friction ratio,
## fading to none at the top of the atmosphere (EGDataShipPlayer.lua:136,152,164).
static func rotation_friction(tuning: ShipTuning, gear: int, environment: FlightEnvironment) -> float:
	var full_ratio: float = tuning.gear_full_friction_ratio[gear]
	var fade := clampf((environment.atmosphere_ratio - full_ratio) / (1.0 - full_ratio), 0.0, 1.0)
	return environment.atmosphere_friction * (1.0 - fade)


## Player turn input as angular acceleration with inertia (EGVehicle:SetDesiredRotation).
static func _player_rotation(ship_state: ShipState, turn_input: Vector3, tuning: ShipTuning, environment: FlightEnvironment, delta: float) -> void:
	var demand := Vector3(clampf(turn_input.x, -1.0, 1.0), clampf(turn_input.y, -1.0, 1.0), clampf(turn_input.z, -1.0, 1.0))
	var strength := minf(demand.length(), 1.0)
	var spin := ship_state.angular_velocity
	# Friction slows the spin mostly while coasting: none at full input.
	var friction := clampf(rotation_friction(tuning, ship_state.gear, environment) * delta, 0.0, 1.0) * (1.0 - strength) * (1.0 - strength)
	spin *= 1.0 - friction
	# Roll input is binary (keys), so its push is eased in over a second.
	ship_state.barrel_roll_factor = move_toward(ship_state.barrel_roll_factor, 1.0, delta) if demand.z != 0.0 else 0.0
	# Small inputs are squared for precision (the vector is scaled by its own length).
	if strength > 0.0:
		demand *= strength
	var hardness: float = tuning.gear_rotation_hardness[ship_state.gear]
	var push := tuning.rotation_speed * delta
	var pitch_yaw := Vector2(spin.x + demand.x * PLAYER_LOOK_SPEED * hardness * push, spin.y + demand.y * PLAYER_LOOK_SPEED * hardness * push)
	if pitch_yaw.length() > tuning.rotation_speed:
		pitch_yaw *= tuning.rotation_speed / pitch_yaw.length()
	var roll_cap := tuning.rotation_speed * ROLL_SPEED_RATIO
	var roll := clampf(spin.z + demand.z * minf(MAX_ROLL_HARDNESS, hardness) * ship_state.barrel_roll_factor * ROLL_ACCELERATION_GAIN * push, -roll_cap, roll_cap)
	ship_state.angular_velocity = Vector3(pitch_yaw.x, pitch_yaw.y, roll)


## In-atmosphere roll levelling (EGVehicle:UpdateLevel). Only roll; it fades out as the nose points steeply up or down,
## grows deeper in the air and with stronger gravity, and is held off for a moment after the pilot rolls. During the
## 4 s after entering the air it brings the roll level over the time left, so entry ends level.
static func _level_roll(ship_state: ShipState, roll_input: float, environment: FlightEnvironment, delta: float) -> void:
	ship_state.auto_level_block = maxf(ship_state.auto_level_block - LEVEL_BLOCK_DECAY * delta, clampf(absf(roll_input) / LEVEL_BLOCK_FULL_INPUT, 0.0, 1.0))
	# A landed ship rests on the ground (GroundContact holds its tilt to the slope), as Rodina's hull rests on its contacts.
	if not ship_state.in_atmosphere or environment.horizon_levelling <= 0.0 or ship_state.landed:
		return
	var up := environment.level_up
	var basis := ship_state.basis
	var pitch_angle := asin(clampf(-basis.z.dot(up), -1.0, 1.0))
	# Signed roll that would level the wings (Sol +z rolls the right wing up, so a raised right wing needs -z).
	var roll_to_level := -atan2(basis.x.dot(up), basis.y.dot(up))
	var ratio := environment.atmosphere_ratio
	var altitude_factor := lerpf(1.0, 0.1, clampf((ratio - 0.25) / 0.75, 0.0, 1.0))
	var pitch_limit := lerpf(1.2, 0.7, clampf((ratio - 0.25) / 0.75, 0.0, 1.0))
	var level_factor := clampf(1.0 - absf(pitch_angle) / pitch_limit, 0.0, 1.0)
	var gravity_factor := lerpf(0.2, 1.0, clampf(environment.surface_gravity_g, 0.0, 1.0))
	var max_rate := 0.6 * PI * level_factor * altitude_factor * gravity_factor * environment.horizon_levelling
	if ship_state.entry_complete_timer > 0.0:
		max_rate = absf(roll_to_level) / ship_state.entry_complete_timer
	var arrival := clampf(absf(roll_to_level) / LEVEL_ARRIVAL_ANGLE, 0.0, 1.0)
	var level_rate := clampf(roll_to_level * LEVEL_ROLL_GAIN * arrival, -max_rate, max_rate)
	var acceleration := (level_rate - ship_state.angular_velocity.z) * (1.0 - ship_state.auto_level_block) * LEVEL_ACCELERATION_GAIN
	ship_state.angular_velocity.z += acceleration * delta


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
