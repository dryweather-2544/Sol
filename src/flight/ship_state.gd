class_name ShipState
extends RefCounted
## Pure flight data for one ship. Position is a WorldPos (64-bit); the rest is small enough
## for Vector3.

var position := WorldPos.new(&"space")
## World-frame velocity, metres per second.
var velocity := Vector3.ZERO
## Ship orientation in its frame; columns are the ship's right, up and back axes.
var basis := Basis.IDENTITY
## Ship-local angular velocity, radians per second about local x (pitch), y (yaw), z (roll).
var angular_velocity := Vector3.ZERO
## Gear in effect this tick (the selected one, or lower where the environment allows less, e.g. an empty tank).
var gear := PilotCommand.GEAR_DOCK
## Gear the pilot chose. Kept while a lower gear is forced, so the choice comes back (Rodina keeps the player's gear in
## EGBehaviorPlayer and the vehicle clamps to the allowed one every update, EGBehaviorPlayer.lua:97-156).
var selected_gear := PilotCommand.GEAR_DOCK

## Planet-relative telemetry, written by PlanetBody.fill_environment and GroundContact.
var landed := false
var altitude_above_ground := INF
var atmosphere_ratio := INF
var regime := FlightRegime.SPACE
var status_message := ""

## 1 = undamaged, 0 = destroyed.
var hull := 1.0
## 1 = full tank. Cruise and boost burn it; with none left the ship is limited to combat gear.
var fuel := 1.0
## Speed (m/s) into the ground on the latest tick; 0 when nothing was hit.
var last_impact_speed := 0.0
## Ground-normal dot velocity direction on the latest impact; used by Rodina's collision damage.
var last_impact_incidence := -1.0
## Rodina CollisionDamageTimer: impact damage is limited to once per 0.25 s.
var impact_damage_cooldown := 0.0
## Rodina EGVehicle movement-control authority. ControlTimer ramps the engine's velocity drive back
## from 0 to 1 over 0.5–1.5 s after a contact (EGVehicle.lua:847-884); TerrainContactTimer ramps the
## terrain-specific drive back over 0.2 s. Both are transient and read by FlightModel.
var control_timer := 10.0
var terrain_contact_timer := 10.0
var control_authority := 1.0
var terrain_control_authority := 1.0

## Atmosphere entry state (Rodina EGVehicle:UpdateInAtmosphereState): entering below ratio 1, "in" below 0.5 (which
## starts the 4 s entry timer), both cleared above 1. Derived from position, so not saved; the first update after a
## load (atmosphere_state_known false) adopts the current state without replaying an entry.
var entering_atmosphere := false
var in_atmosphere := false
var entry_complete_timer := 0.0
var atmosphere_state_known := false
## Atmospheric resistance on this tick (ShipDamage.entry_resistance): drives entry damage, the nose push and the heat effect.
var atmosphere_resistance := 0.0
## Roll input smoothing (Rodina BarrelRollFactor, 0..1) and the hold-off on roll levelling after the pilot rolls
## (Rodina AutoLevelBlock, 0..1). Transient.
var barrel_roll_factor := 0.0
var auto_level_block := 0.0
## Seconds the warp gear has been engaged (Rodina EGShipPlayer.LimnalTimer); 0 outside warp. Transient, like Rodina's.
var limnal_timer := 0.0
## Rodina EGBehaviorPlayer.LimnalDrift: a small slow steering bias that exists only after the
## warp drive has fully spun up. Transient, not saved.
var limnal_drift := Vector2.ZERO
## Rodina CancelLimnalDrive moves the pilot's gear down to cruise; Sol keeps the pilot's selection, so a cancelled warp
## stays off (this latch) until the pilot selects a lower gear and shifts up again. Transient.
var warp_cancelled := false


func speed() -> float:
	return velocity.length()
