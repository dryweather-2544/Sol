class_name ShipDamage
extends RefCounted
## Hull damage rules (pure). Impacts: harmless below SAFE_IMPACT_SPEED, lethal above LETHAL_IMPACT_SPEED
## (m/s into the ground, smooth in between). Re-entry: flying faster than HEAT_START_SPEED inside an
## atmosphere burns the hull. The shape follows research FLY-30 / `02` §6.2 (damage from speed and
## incidence, and from steep fast re-entry); the numbers are Sol's, scaled to Sol's speeds.

const SAFE_IMPACT_SPEED := 15.0
const LETHAL_IMPACT_SPEED := 90.0
const HEAT_START_SPEED := 12000.0
const HEAT_FULL_SPEED := 22000.0
## Hull fraction lost per second at HEAT_FULL_SPEED inside the atmosphere.
const HEAT_RATE_AT_FULL := 0.1
const REPAIR_PER_SECOND := 0.15


## Fraction of the hull lost in one impact at this speed (into the ground).
static func impact_damage(impact_speed: float) -> float:
	return smoothstep(SAFE_IMPACT_SPEED, LETHAL_IMPACT_SPEED, impact_speed)


## Hull fraction lost per second from atmospheric heating.
static func heating_rate(speed: float, atmosphere_ratio: float) -> float:
	if atmosphere_ratio >= 1.0:
		return 0.0
	return clampf((speed - HEAT_START_SPEED) / (HEAT_FULL_SPEED - HEAT_START_SPEED), 0.0, 1.0) * HEAT_RATE_AT_FULL
