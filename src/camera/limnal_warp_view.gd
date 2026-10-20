class_name LimnalWarpView
extends RefCounted
## Rodina's warp ("Limnal drive") and speed camera, ported from EGShipPlayer:SetMovementEffects
## (EGDataShipPlayer.lua:293-348), EGBehaviorPlayer:UpdateLimnalWarp (EGBehaviorPlayer.lua:162-182), the atmosphere
## shake in EGVehicle:UpdateAV (EGVehicle.lua:533-543) and the firing shake (EGVehicle.lua:1673-1675).
##
## Two clocks drive everything. LimnalTimer counts up while the ship is in the warp gear (Rodina gear 4, Sol WARP) and
## resets the moment it leaves it. LimnalSpacewarp is the camera blend: in warp it is max(itself,
## EGApproach(LimnalTimer, 0.95, 0.25)), so it climbs slowly toward 0.95 (0.30 after 1.8 s, 0.63 after 8 s); out of
## warp it decays by EGInterpolate(dt * 1.5, warp, 0) each frame. The Lua tests an undefined global
## (`limnalActivation == 1`, always false) before taking the approach branch, so the "warp = 1" branch never runs;
## that is reproduced. LimnalActivation = LimnalTimer / LimnalStartTime (1.8 s), clamped, gates the drive effects.
##
## From the blend: FOV = base .. min(175, base + 30); chase distance 200 -> 125 m; chase angle 10 -> 15 degrees
## (EGVehicle.CameraFollowDistance/Angle at rest). The main scene scales the distance by Sol's ship size
## (RodinaEmitter.SHIP_SCALE): Sol's own chase camera is under one hull length back, so shortening it by Rodina's
## 0.625 put the camera inside the hull; Rodina's camera is ~2.7 hull lengths back.

const LIMNAL_START_TIME := 1.8 # EGShipPlayer.LimnalStartTime
const FOV_WIDEN_DEGREES := 30.0
const FOV_MAX_DEGREES := 175.0
const RODINA_FOLLOW_DISTANCE := 200.0
const RODINA_WARP_FOLLOW_DISTANCE := 125.0
const RODINA_FOLLOW_ANGLE := 10.0
const RODINA_WARP_FOLLOW_ANGLE := 15.0
## Rodina Options.MovementDifficulty default 1 -> EGAnalogue(1, 0, 1, .75, 1) = 1.
const DIFFICULTY_FACTOR := 1.0
const LIMNAL_VIBRATION := &"LIMNAL WARP VIBRATION"
const ATMOSPHERE_VIBRATION := &"ATMOSPHERE VIBRATION"
const FIRE_VIBRATION := &"FIRE LASERS VIBRATION"

var limnal_timer := 0.0
var spacewarp := 0.0
var activation := 0.0
var vibration := CameraVibration.new()
## This frame's camera shake (yaw, pitch in radians), from update().
var shake := Vector2.ZERO


## in_warp: the ship's gear is WARP now (not just selected). atmosphere_resistance: ShipState.atmosphere_resistance.
## fired: the player's ship tried to fire its guns this tick.
func update(in_warp: bool, atmosphere_resistance: float, fired: bool, delta: float) -> void:
	# UpdateLimnalWarp runs in ComputeMovement, before SetMovementEffects advances the timer: it uses last tick's activation.
	if in_warp:
		var vibrate := 0.0125 * DIFFICULTY_FACTOR * activation
		vibration.set_vibrate(LIMNAL_VIBRATION, Vector2(vibrate, vibrate), Vector2(125.0, 100.0), 0.0, 0.25)
	if atmosphere_resistance > 0.0:
		var vibrate := 0.075 * atmosphere_resistance
		vibration.set_vibrate(ATMOSPHERE_VIBRATION, Vector2(vibrate, vibrate), Vector2(18.0, 18.0), 0.0, 0.25)
	if fired:
		vibration.set_vibrate(FIRE_VIBRATION, Vector2(0.002, 0.002), Vector2(125.0, 100.0), 0.0, 0.25)
	if in_warp:
		limnal_timer += delta
		spacewarp = maxf(spacewarp, RodinaMath.approach(limnal_timer, 0.95, 0.25))
	else:
		limnal_timer = 0.0
		spacewarp = RodinaMath.interpolate(delta * 1.5, spacewarp, 0.0)
	activation = RodinaMath.analogue(limnal_timer, 0.0, LIMNAL_START_TIME, 0.0, 1.0)
	shake = vibration.update(delta)


func field_of_view(base_degrees: float) -> float:
	return RodinaMath.analogue(spacewarp, 0.0, 1.0, base_degrees, minf(FOV_MAX_DEGREES, base_degrees + FOV_WIDEN_DEGREES))


## Rodina chase distance in Rodina metres (200 at rest, 125 at full warp).
func follow_distance() -> float:
	return RodinaMath.analogue(spacewarp, 0.0, 1.0, RODINA_FOLLOW_DISTANCE, RODINA_WARP_FOLLOW_DISTANCE)


## Rodina chase angle in degrees (10 at rest, 15 at full warp).
func follow_angle_degrees() -> float:
	return RodinaMath.analogue(spacewarp, 0.0, 1.0, RODINA_FOLLOW_ANGLE, RODINA_WARP_FOLLOW_ANGLE)


## Back to rest at once (load, respawn): Rodina's state is not saved either.
func reset() -> void:
	limnal_timer = 0.0
	spacewarp = 0.0
	activation = 0.0
	shake = Vector2.ZERO
	vibration = CameraVibration.new()
