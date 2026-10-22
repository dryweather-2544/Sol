class_name ShipDamage
extends RefCounted
## Hull damage rules (pure). Collision damage follows Rodina EGVehicle:OnCollision (EGVehicle.lua:736-785):
## no damage below 150 m/s, a strength factor from the impact angle (.25..-1 -> 0..1) and a speed factor
## from .1 at 150 m/s to 2 at 5000 m/s, with a 0.25 s collision-damage cooldown.
## Atmospheric entry follows Rodina 1.6.2 (EGVehicle:UpdateInAtmosphereMovement, EGVehicle.lua:1077-1139): while the
## ship is entering (below the top of the air and not yet half way down, plus the 4 s after), the air resists in
## proportion to how steeply it dives, how fast it goes and how far into the entry band it is; only a strong
## resistance (above ENTRY_DAMAGE_START) burns the hull. Once fully in the air there is no resistance at any speed.

const IMPACT_DAMAGE_MIN_SPEED := 150.0
const IMPACT_DAMAGE_FULL_SPEED := 5000.0
const IMPACT_DAMAGE_COOLDOWN := 0.25
## Rodina kAmosphericEntrySpeed: resistance grows with speed up to 2 at twice this.
const ENTRY_SPEED := 5000.0
## Resistance above which the hull burns, and the hull fraction lost per second at resistance 1 (Rodina: 15% of
## MaxHealth per second at full, scaled by MovementDifficulty, default 1).
const ENTRY_DAMAGE_START := 0.85
const ENTRY_DAMAGE_RATE := 0.15
const REPAIR_PER_SECOND := 0.15
## A star's heat: nothing beyond one star radius above its surface, ramping up (squared) to STAR_HEAT_RATE of the hull per
## second at the surface, and STAR_CORE_RATE (certain death within a second) once the ship is inside the star.
const STAR_HEAT_REACH := 1.0
const STAR_HEAT_RATE := 0.6
const STAR_CORE_RATE := 10.0


## Fraction of the hull lost in one impact. incidence is the ground-normal dot velocity direction
## (.25 = glancing, -1 = head-on). The default -1 preserves the direct test/legacy call.
static func impact_damage(impact_speed: float, incidence := -1.0) -> float:
	if impact_speed <= IMPACT_DAMAGE_MIN_SPEED:
		return 0.0
	var strength := clampf((0.25 - incidence) / 1.25, 0.0, 1.0)
	var speed_factor := lerpf(0.1, 2.0, clampf((impact_speed - IMPACT_DAMAGE_MIN_SPEED) / (IMPACT_DAMAGE_FULL_SPEED - IMPACT_DAMAGE_MIN_SPEED), 0.0, 1.0))
	return strength * speed_factor


## Atmospheric resistance during entry, 0 when not entering. toward_planet: unit vector to the planet centre.
static func entry_resistance(velocity: Vector3, toward_planet: Vector3, atmosphere_ratio: float, in_atmosphere: bool, entry_complete_timer: float, entry_seconds: float) -> float:
	if atmosphere_ratio >= 1.0 or (in_atmosphere and entry_complete_timer <= 0.0):
		return 0.0
	var strength := clampf((1.0 - atmosphere_ratio) / 0.1, 0.0, 1.0) # 0 at the top of the air, 1 a tenth of the way down
	if entry_complete_timer > 0.0:
		strength *= entry_complete_timer / entry_seconds
	var speed := velocity.length()
	if speed < 1e-6:
		return 0.0
	var into := clampf((velocity.dot(toward_planet) / speed + 0.5) / 1.25, 0.0, 1.0) # -0.5..0.75 -> 0..1
	var speed_factor := clampf(speed / ENTRY_SPEED, 0.0, 2.0)
	return into * strength * speed_factor


## Hull fraction lost per second at this entry resistance.
static func entry_damage_rate(resistance: float) -> float:
	return clampf((resistance - ENTRY_DAMAGE_START) / (1.0 - ENTRY_DAMAGE_START), 0.0, 1.0) * ENTRY_DAMAGE_RATE


## Hull fraction lost per second to a star's heat, from the ship's distance to the star's centre.
static func star_heat_rate(distance_to_centre: float, star_radius: float) -> float:
	var edge := star_radius * (1.0 + STAR_HEAT_REACH)
	if star_radius <= 0.0 or distance_to_centre >= edge:
		return 0.0
	if distance_to_centre <= star_radius:
		return STAR_CORE_RATE
	var closeness := (edge - distance_to_centre) / (star_radius * STAR_HEAT_REACH)
	return STAR_HEAT_RATE * closeness * closeness
