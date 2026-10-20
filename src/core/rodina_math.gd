class_name RodinaMath
extends RefCounted
## Rodina's small math helpers, ported line for line from Scripts/EGUtility.lua so effect formulas that use them keep
## their exact shape. Reference only: the Lua is not shipped with Sol.


## EGAnalogue (EGUtility.lua:126): remap value from [from_low, from_high] to [to_low, to_high], clamped to the range.
static func analogue(value: float, from_low: float, from_high: float, to_low: float, to_high: float) -> float:
	var ratio := clampf((value - from_low) / (from_high - from_low), 0.0, 1.0)
	return to_low + ratio * (to_high - to_low)


## EGInterpolate (EGUtility.lua:152).
static func interpolate(t: float, from: float, to: float) -> float:
	return from + t * (to - from)


## EGApproach (EGUtility.lua:158): a rectangular hyperbola from 0 at x = 0 toward `limit`, starting with slope
## limit * slope_mult.
static func approach(x: float, limit: float, slope_mult: float) -> float:
	var slope := limit / absf(slope_mult)
	return limit - slope / (x + slope / limit)


## EGDeltaTo (EGUtility.lua:259): step current toward target by at most delta.
static func delta_to(current: float, target: float, delta: float) -> float:
	return move_toward(current, target, delta)


## EGHueSaturateValue (EGUtility.lua:90): Rodina's own HSV to RGB (hue in degrees). Values above 1 or below 0 pass
## through unclamped, as in the Lua.
static func hue_saturate_value(hue: float, saturation: float, value: float) -> Color:
	var high := value
	var low := value * (1.0 - saturation)
	var h := fmod(hue, 360.0)
	if h < 60.0:
		return Color(high, analogue(h, 0.0, 60.0, low, high), low)
	elif h < 120.0:
		return Color(analogue(h, 60.0, 120.0, high, low), high, low)
	elif h < 180.0:
		return Color(low, high, analogue(h, 120.0, 180.0, low, high))
	elif h < 240.0:
		return Color(low, analogue(h, 180.0, 240.0, high, low), high)
	elif h < 300.0:
		return Color(analogue(h, 240.0, 300.0, low, high), low, high)
	return Color(high, low, analogue(h, 300.0, 360.0, high, low))
