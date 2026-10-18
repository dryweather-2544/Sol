class_name FlightRegime
extends RefCounted
## Where the ship is relative to a planet. Derived each tick from atmosphere ratio, height above
## ground and the landed flag; the HUD (and later audio/camera) read it. The 4 s entry timer
## from research FLY-27 is not modelled yet.

enum { SPACE, ENTERING, ATMOSPHERE, NEAR_GROUND, LANDED }

const NEAR_GROUND_ALTITUDE := 2000.0


static func classify(atmosphere_ratio: float, altitude_above_ground: float, landed: bool) -> int:
	if landed:
		return LANDED
	if altitude_above_ground < NEAR_GROUND_ALTITUDE:
		return NEAR_GROUND
	if atmosphere_ratio < 0.5:
		return ATMOSPHERE
	if atmosphere_ratio < 1.0:
		return ENTERING
	return SPACE


static func label(regime: int) -> String:
	return ["SPACE", "ENTERING", "ATMOSPHERE", "NEAR GROUND", "LANDED"][regime]
