class_name CameraVibration
extends RefCounted
## Rodina's named camera-shake modules, ported from EGWorldObject:SetCameraVibrate (EGWorldObject.lua:226-256) and
## EGEffectUpdate (EGEffect.lua): each named module keeps its own clock; re-setting it every frame holds it at full
## strength, and once callers stop it fades from 1 to 0 between fade_start and fade_end seconds after the last set.
## Each frame a module adds amplitude * perlin(clock * speed * 0.3) on two axes, scaled by factor * CameraShake * 3,
## then by factor^2 again (both multiplies are in the Lua).
## Inferred, not in the Lua (engine-side): System.GetPerlin's range and what AddCameraDelta's x/y mean (taken as
## yaw/pitch in radians). Godot's Perlin is gradient noise, exactly 0 at whole numbers, and Sol's fixed 60 Hz tick
## samples Rodina's arguments (clock * 125 * 0.3, 20 + clock * 100 * 0.3) on whole numbers every 8th and every 2nd
## tick, which would zero the shake in a 30 Hz buzz; so the 1D noise is read along a line just off the lattice
## (y = NOISE_LANE) of 2D Perlin. The formula's arguments are unchanged.

## Rodina's Options.CameraShake default (EGOptions.lua:114).
const DEFAULT_SHAKE_OPTION := 1.0
const NOISE_LANE := 0.37

var shake_option := DEFAULT_SHAKE_OPTION
var _modules := {} # name -> {clock, set_at, fade_start, fade_end, amplitude, speed}
var _noise := FastNoiseLite.new()


func _init() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 1.0
	_noise.seed = 1


## SetCameraVibrate(name, shakeDegree, shakeSpeed, fadeStart, fadeEnd); amplitude and speed are (x, y).
func set_vibrate(module_name: StringName, amplitude: Vector2, speed: Vector2, fade_start: float, fade_end: float) -> void:
	var module: Dictionary = _modules.get(module_name, {"clock": 0.0})
	module["set_at"] = module["clock"]
	module["fade_start"] = fade_start
	module["fade_end"] = fade_end
	module["amplitude"] = amplitude
	module["speed"] = speed
	_modules[module_name] = module


## Advances every module and returns this frame's summed camera delta (x = yaw, y = pitch, radians).
func update(delta: float) -> Vector2:
	var total := Vector2.ZERO
	for module_name in _modules:
		var module: Dictionary = _modules[module_name]
		module["clock"] += delta
		var clock: float = module["clock"]
		var factor := RodinaMath.analogue(clock, module["set_at"] + module["fade_start"], module["set_at"] + module["fade_end"], 1.0, 0.0)
		if factor <= 0.0:
			continue
		var amplitude: Vector2 = module["amplitude"]
		var speed: Vector2 = module["speed"]
		var shake := Vector2(amplitude.x * _perlin(clock * speed.x * 0.3), amplitude.y * _perlin(20.0 + clock * speed.y * 0.3))
		shake *= factor * shake_option * 3.0
		shake *= factor * factor
		total += shake
	return total


## System.GetPerlin stand-in (see the header).
func _perlin(x: float) -> float:
	return _noise.get_noise_2d(x, NOISE_LANE)


## Strength (0..1) a module would have now, for tests and the debug overlay.
func factor_of(module_name: StringName) -> float:
	if not _modules.has(module_name):
		return 0.0
	var module: Dictionary = _modules[module_name]
	return RodinaMath.analogue(module["clock"], module["set_at"] + module["fade_start"], module["set_at"] + module["fade_end"], 1.0, 0.0)
