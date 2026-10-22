class_name AIPilotSource
extends PilotSource
## An AI that flies a ship through the same PilotCommand a player does (research FLY-02: AI fills the
## shared pilot interface). It only chooses intent: where to face, how to thrust, when to fire.

enum Mode { IDLE, GOTO, ATTACK, ORBIT }

var mode := Mode.IDLE
## Returns the WorldPos to go to / attack, or null (then the AI idles). Set by whoever creates it.
var target_provider := Callable()
## Optional: returns the target's velocity (planet frame) for lead aiming; ZERO if unset.
var target_velocity_provider := Callable()
var preferred_range := 450.0
var fire_range := 1100.0
## cos of the largest angle off-target at which the AI will pull the trigger.
var fire_cone_cos := 0.996
var projectile_speed := 10000.0 # the ship gun's muzzle speed (Weapon.ship_gun)
## How far off (radians, random) its aim is, so it does not hit with every shot.
var aim_error := 0.03
## 0..1 per tick (PilotCommand.move_lock): how hard the AI snaps its velocity to the one it wants. 1 is instant (the old
## behaviour); the small fighters use less so they accelerate and brake instead of jumping between speeds.
var move_lock_strength := 1.0
## When true the AI only closes in as fast as its nose points at the target, so a fighter that has just flown past the player
## turns round first instead of racing off along its old heading.
var turn_before_thrust := false
var _rng := SeedRng.new(99)
var _clock := 0.0


func _init(initial_mode: int = Mode.IDLE) -> void:
	source_id = &"ai"
	mode = initial_mode


func poll(ship_state: ShipState, delta: float) -> PilotCommand:
	_clock += delta
	var command := PilotCommand.new()
	command.gear = PilotCommand.GEAR_COMBAT
	# Rodina's AI hands the flight model a velocity to match (the engine mover's MoveLock, EGBehavior.lua:68-82)
	# rather than stick input; the lock value Rodina's mover uses is engine-side, 1 is Sol's choice.
	command.move_lock = move_lock_strength
	var target = target_provider.call() if target_provider.is_valid() else null
	if mode == Mode.IDLE or target == null:
		command.brake = true
		return command
	var offset: Vector3 = (target as WorldPos).vector_from(ship_state.position)
	var distance := offset.length()
	if distance < 0.001:
		command.brake = true
		return command
	var aim_direction := offset / distance
	if mode == Mode.ATTACK and target_velocity_provider.is_valid():
		var relative_velocity: Vector3 = (target_velocity_provider.call() as Vector3) - ship_state.velocity
		var flight_time := distance / projectile_speed
		aim_direction = (offset + relative_velocity * flight_time).normalized()
	aim_direction = (aim_direction + Vector3(_rng.next_float() - 0.5, _rng.next_float() - 0.5, _rng.next_float() - 0.5) * aim_error * 2.0).normalized()
	command.face_direction = aim_direction
	var forward := -ship_state.basis.z
	match mode:
		Mode.GOTO:
			command.gear = PilotCommand.GEAR_COMBAT if distance > 3000.0 else PilotCommand.GEAR_DOCK
			if distance < 25.0:
				command.brake = true
			else:
				command.thrust = Vector3(0, 0, -clampf(distance / 300.0, 0.0, 1.0))
		Mode.ATTACK:
			if distance > preferred_range * 1.25:
				var drive := 1.0
				if turn_before_thrust:
					drive = clampf(forward.dot(aim_direction) * 1.5 - 0.4, 0.0, 1.0) # full from about 25 degrees off, none past 75
				command.thrust = Vector3(0, 0, -drive)
			elif distance < preferred_range * 0.6:
				command.thrust = Vector3(0, 0, 0.6)
			command.thrust.x = 0.7 * sin(_clock * 0.9) # weave so it is harder to hit
			command.fire = distance < fire_range and forward.dot(aim_direction) > fire_cone_cos
		Mode.ORBIT:
			command.thrust = Vector3(1.0, 0, -clampf((distance - preferred_range) / 200.0, -1.0, 1.0))
	return command
