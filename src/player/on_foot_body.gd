class_name OnFootBody
extends RefCounted
## Walking on a planet without physics shapes: horizontal motion in the tangent plane, height
## from the same terrain function the mesh uses. Pure and deterministic. Positions are WorldPos
## (64-bit); everything is computed in doubles so a 6,000 km planet does not blur the ground.

const WALK_SPEED := 4.0
const RUN_SPEED := 8.0
const JUMP_SPEED := 5.0
const GROUND_ACCELERATION := 40.0
const AIR_ACCELERATION := 5.0
## Steepest ground that can be walked up, degrees. Measured over a 1 m probe ahead.
const MAX_WALKABLE_SLOPE_DEGREES := 45.0
const SLOPE_PROBE_DISTANCE := 1.0
## Walking off a ledge higher than this starts a fall; below it the feet follow the ground.
const STEP_DOWN_DISTANCE := 0.6
const EYE_HEIGHT := 1.65
## Upward push of the jetpack, m/s^2 (at least 1.5 g so it can lift on any world), and its climb speed cap.
const JETPACK_MIN_ACCELERATION := 18.0
const JETPACK_MAX_CLIMB_SPEED := 12.0

var position := WorldPos.new(&"planet")
## Unit vector in the tangent plane the body faces.
var heading := Vector3.FORWARD
## World-frame horizontal velocity (always tangent to the planet).
var velocity := Vector3.ZERO
var vertical_speed := 0.0
var grounded := true
## Metres above the terrain directly below (0 while grounded).
var height_above_ground := 0.0
var blocked_by_slope := false
## Set by the game: does the suit have fuel? jetpack_burning reports whether it fired this tick.
var jetpack_fuel_available := true
var jetpack_burning := false


func place_on_ground(planet: PlanetBody, new_position: WorldPos, facing: Vector3) -> void:
	var up := planet.up_at(new_position)
	# Direction in 64-bit (up is only 32-bit): a 0.4 m rounding at 6,000 km would put the feet a few cm off the ground.
	var distance := planet.distance_from_center(new_position)
	var direction_x := new_position.x / distance
	var direction_y := new_position.y / distance
	var direction_z := new_position.z / distance
	var ground_distance := planet.surface_radius_xyz(direction_x, direction_y, direction_z)
	position = WorldPos.new(new_position.frame_id, direction_x * ground_distance, direction_y * ground_distance, direction_z * ground_distance)
	heading = _tangent_unit(facing, up)
	velocity = Vector3.ZERO
	vertical_speed = 0.0
	grounded = true
	height_above_ground = 0.0


func step(command: OnFootCommand, planet: PlanetBody, delta: float) -> void:
	var up := planet.up_at(position)
	heading = _tangent_unit(heading, up).rotated(up, command.yaw_delta)
	var right := heading.cross(up)
	var wish_direction := (right * command.move.x + heading * command.move.y).limit_length(1.0)
	var target_velocity := wish_direction * (RUN_SPEED if command.run else WALK_SPEED)
	velocity -= up * velocity.dot(up)
	velocity = velocity.move_toward(target_velocity, (GROUND_ACCELERATION if grounded else AIR_ACCELERATION) * delta)

	blocked_by_slope = false
	if grounded and velocity.length() > 1e-4 and _slope_ahead_degrees(planet, velocity.normalized()) > MAX_WALKABLE_SLOPE_DEGREES:
		blocked_by_slope = true
		velocity = Vector3.ZERO

	var moved_x := position.x + velocity.x * delta
	var moved_y := position.y + velocity.y * delta
	var moved_z := position.z + velocity.z * delta
	var moved_distance := sqrt(moved_x * moved_x + moved_y * moved_y + moved_z * moved_z)
	var direction_x := moved_x / moved_distance
	var direction_y := moved_y / moved_distance
	var direction_z := moved_z / moved_distance
	var ground_distance := planet.surface_radius_xyz(direction_x, direction_y, direction_z)
	var height := moved_distance - ground_distance

	if grounded:
		if height > STEP_DOWN_DISTANCE:
			grounded = false
			vertical_speed = 0.0
		else:
			height = 0.0
		if command.jump and grounded:
			grounded = false
			vertical_speed = JUMP_SPEED
	jetpack_burning = false
	if not grounded:
		var gravity_strength := planet.gravity_at(position).length()
		vertical_speed -= gravity_strength * delta
		if command.jetpack and jetpack_fuel_available:
			vertical_speed = minf(vertical_speed + maxf(JETPACK_MIN_ACCELERATION, gravity_strength * 1.5) * delta + gravity_strength * delta, JETPACK_MAX_CLIMB_SPEED)
			jetpack_burning = true
		height += vertical_speed * delta
		if height <= 0.0 and vertical_speed <= 0.0:
			height = 0.0
			vertical_speed = 0.0
			grounded = true
	height_above_ground = height
	var final_distance := ground_distance + height
	position = WorldPos.new(position.frame_id, direction_x * final_distance, direction_y * final_distance, direction_z * final_distance)


## Slope of the ground over SLOPE_PROBE_DISTANCE in the direction of travel, in degrees (uphill positive).
func _slope_ahead_degrees(planet: PlanetBody, travel_direction: Vector3) -> float:
	var probe_x := position.x + travel_direction.x * SLOPE_PROBE_DISTANCE
	var probe_y := position.y + travel_direction.y * SLOPE_PROBE_DISTANCE
	var probe_z := position.z + travel_direction.z * SLOPE_PROBE_DISTANCE
	var probe_distance := sqrt(probe_x * probe_x + probe_y * probe_y + probe_z * probe_z)
	var ahead_ground := planet.surface_radius_xyz(probe_x / probe_distance, probe_y / probe_distance, probe_z / probe_distance)
	var here_distance := planet.distance_from_center(position)
	var here_ground := planet.surface_radius_xyz(position.x / here_distance, position.y / here_distance, position.z / here_distance)
	return rad_to_deg(atan2(ahead_ground - here_ground, SLOPE_PROBE_DISTANCE))


static func _tangent_unit(vector: Vector3, up: Vector3) -> Vector3:
	var tangent := vector - up * vector.dot(up)
	if tangent.length_squared() < 1e-12:
		tangent = up.cross(Vector3.RIGHT) if absf(up.dot(Vector3.RIGHT)) < 0.9 else up.cross(Vector3.UP)
	return tangent.normalized()


## A short offset along local up (for placing a visual above the feet).
func position_up_offset(metres: float) -> Vector3:
	return Vector3(position.x, position.y, position.z).normalized() * metres
