class_name GroundContact
extends RefCounted
## Ship vs terrain, using height queries at the hull's support points (no physics shapes).
## Resolves penetration, removes velocity into the ground, decides LANDED with hysteresis and,
## while landed, tilts the ship to sit flat on the slope. "Landed" is contact-relative
## (research FLY-26): touching ground, slow, and the slope is gentle enough.

const TOUCH_DISTANCE := 0.3
const LIFTOFF_DISTANCE := 1.0
const LANDED_MAX_SPEED := 4.0
const MAX_LANDING_SLOPE_DEGREES := 35.0
## The ship must be roughly upright relative to the ground to count as landed.
const MAX_LANDING_TILT_DEGREES := 40.0
const ALIGN_RATE := 6.0
## Deceleration of sliding along the ground while landed (stops a parked ship drifting downhill).
const LANDED_FRICTION := 25.0
## Hull friction while touching but not landed (Rodina EGShipPlayer.VehiclePhysics Friction 0.4; the terrain's own
## friction is engine-side, taken as 1): sliding slows by this times how hard the hull is pressed into the ground,
## by the impact and by gravity. On slopes steeper than atan(0.4) = 21.8 degrees gravity wins and the ship slides.
const HULL_FRICTION := 0.4
## Rodina player hull restitution (EGDataShipPlayer.lua:26-38). Havok applies it to contact
## impulses; Sol's support-point resolver applies it only to the first non-landed impact so a
## resting ship does not jitter. Small settling impacts are still absorbed.
const HULL_RESTITUTION := 0.8
const MIN_BOUNCE_SPEED := 8.0


static func resolve(ship_state: ShipState, planet: PlanetBody, tuning: ShipTuning, delta: float) -> void:
	var position := ship_state.position
	var up := planet.up_at(position)
	var support_count := tuning.support_points.size()
	var lowest_clearance := INF
	var surface_offsets: Array[Vector3] = []
	for support_index in support_count:
		var world_offset := ship_state.basis * tuning.support_points[support_index]
		var point_x := position.x + world_offset.x
		var point_y := position.y + world_offset.y
		var point_z := position.z + world_offset.z
		var point_distance := sqrt(point_x * point_x + point_y * point_y + point_z * point_z)
		var direction_x := point_x / point_distance
		var direction_y := point_y / point_distance
		var direction_z := point_z / point_distance
		var surface_distance := planet.surface_radius_xyz(direction_x, direction_y, direction_z)
		lowest_clearance = minf(lowest_clearance, point_distance - surface_distance)
		surface_offsets.append(Vector3(direction_x * surface_distance - position.x, direction_y * surface_distance - position.y, direction_z * surface_distance - position.z))

	var ground_normal := up
	if support_count >= 4:
		ground_normal = (surface_offsets[2] - surface_offsets[1]).cross(surface_offsets[3] - surface_offsets[0]).normalized()
		if ground_normal.dot(up) < 0.0:
			ground_normal = -ground_normal
	var slope_degrees := rad_to_deg(acos(clampf(ground_normal.dot(up), -1.0, 1.0)))

	ship_state.last_impact_speed = 0.0
	if lowest_clearance < 0.0:
		# Rodina's OnCollision resets TerrainContactTimer on every planet contact; the engine then
		# ramps velocity control back over 0.2 s (EGVehicle.lua:736-765, 847-884).
		ship_state.terrain_contact_timer = 0.0
		position.x -= up.x * lowest_clearance
		position.y -= up.y * lowest_clearance
		position.z -= up.z * lowest_clearance
		var into_ground_speed := ship_state.velocity.dot(ground_normal)
		if into_ground_speed < 0.0:
			ship_state.last_impact_speed = -into_ground_speed
			var speed := ship_state.velocity.length()
			ship_state.last_impact_incidence = clampf(ground_normal.dot(ship_state.velocity / speed), -1.0, 1.0) if speed > 1e-6 else -1.0
			ship_state.velocity -= ground_normal * into_ground_speed
			if not ship_state.landed and ship_state.last_impact_speed > MIN_BOUNCE_SPEED:
				ship_state.velocity += ground_normal * ship_state.last_impact_speed * HULL_RESTITUTION
	var touching := lowest_clearance < TOUCH_DISTANCE
	var tilt_degrees := rad_to_deg(acos(clampf(ship_state.basis.y.dot(ground_normal), -1.0, 1.0)))

	if ship_state.landed:
		if lowest_clearance > LIFTOFF_DISTANCE or ship_state.speed() >= LANDED_MAX_SPEED:
			ship_state.landed = false
	elif touching and ship_state.speed() < LANDED_MAX_SPEED and slope_degrees <= MAX_LANDING_SLOPE_DEGREES and tilt_degrees <= MAX_LANDING_TILT_DEGREES:
		ship_state.landed = true

	if touching and not ship_state.landed:
		var pressing := ship_state.last_impact_speed + maxf(0.0, -planet.ship_gravity_at(position).dot(ground_normal)) * delta
		var sliding_velocity := ship_state.velocity - ground_normal * ship_state.velocity.dot(ground_normal)
		ship_state.velocity -= sliding_velocity.limit_length(HULL_FRICTION * pressing)

	ship_state.status_message = ""
	if touching and not ship_state.landed and slope_degrees > MAX_LANDING_SLOPE_DEGREES:
		ship_state.status_message = "Too steep to land (%d deg)" % int(slope_degrees)
	if ship_state.landed:
		var normal_speed := maxf(0.0, ship_state.velocity.dot(ground_normal))
		var sliding := ship_state.velocity - ground_normal * ship_state.velocity.dot(ground_normal)
		ship_state.velocity = sliding.move_toward(Vector3.ZERO, LANDED_FRICTION * delta) + ground_normal * normal_speed
		# Resting on its gear the ship cannot pitch or roll (the ground holds it); it can still turn on the spot.
		ship_state.angular_velocity.x = 0.0
		ship_state.angular_velocity.z = 0.0
		_align_to(ship_state, ground_normal, delta)
		# Tilting turns the ship about its centre, which can lift one end's feet; a resting ship stays seated on its
		# lowest foot (unless it is climbing away). Without this a hovering gear could hold it just off the ground.
		if normal_speed <= 0.0:
			var gap := lowest_clearance_of(ship_state, planet, tuning)
			if gap > 0.0:
				var seat_up := planet.up_at(ship_state.position)
				ship_state.position.x -= seat_up.x * gap
				ship_state.position.y -= seat_up.y * gap
				ship_state.position.z -= seat_up.z * gap


## Smallest height of any support point above the terrain (negative = below it).
static func lowest_clearance_of(ship_state: ShipState, planet: PlanetBody, tuning: ShipTuning) -> float:
	var lowest := INF
	for support_point in tuning.support_points:
		var world_offset := ship_state.basis * support_point
		var point_x := ship_state.position.x + world_offset.x
		var point_y := ship_state.position.y + world_offset.y
		var point_z := ship_state.position.z + world_offset.z
		var point_distance := sqrt(point_x * point_x + point_y * point_y + point_z * point_z)
		lowest = minf(lowest, point_distance - planet.surface_radius_xyz(point_x / point_distance, point_y / point_distance, point_z / point_distance))
	return lowest


static func _align_to(ship_state: ShipState, ground_normal: Vector3, delta: float) -> void:
	var current_up := ship_state.basis.y
	var tilt := Quaternion(current_up, ground_normal)
	var partial_tilt := Quaternion.IDENTITY.slerp(tilt, 1.0 - exp(-ALIGN_RATE * delta))
	ship_state.basis = Basis((partial_tilt * Quaternion(ship_state.basis)).normalized())
