class_name ShipDamage
extends RefCounted
## Hull damage rules (pure). Impacts: harmless below SAFE_IMPACT_SPEED, lethal above LETHAL_IMPACT_SPEED
## (m/s into the ground, smooth in between); the numbers are Sol's, scaled to Sol's speeds.
## Atmospheric entry follows Rodina 1.6.2 (EGVehicle:UpdateInAtmosphereMovement, EGVehicle.lua:1077-1139): while the
## ship is entering (below the top of the air and not yet half way down, plus the 4 s after), the air resists in
## proportion to how steeply it dives, how fast it goes and how far into the entry band it is; only a strong
## resistance (above ENTRY_DAMAGE_START) burns the hull. Once fully in the air there is no resistance at any speed.

const SAFE_IMPACT_SPEED := 15.0
const LETHAL_IMPACT_SPEED := 90.0
## Rodina kAmosphericEntrySpeed: resistance grows with speed up to 2 at twice this.
const ENTRY_SPEED := 5000.0
## Resistance above which the hull burns, and the hull fraction lost per second at resistance 1 (Rodina: 15% of
## MaxHealth per second at full, scaled by MovementDifficulty, default 1).
const ENTRY_DAMAGE_START := 0.85
const ENTRY_DAMAGE_RATE := 0.15
const REPAIR_PER_SECOND := 0.15


## Fraction of the hull lost in one impact at this speed (into the ground).
static func impact_damage(impact_speed: float) -> float:
	return smoothstep(SAFE_IMPACT_SPEED, LETHAL_IMPACT_SPEED, impact_speed)


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
