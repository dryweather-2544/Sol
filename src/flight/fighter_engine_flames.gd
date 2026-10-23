class_name FighterEngineFlames
extends Node3D
## Engine flames for a small fighter: a dense burst of hard-edged additive squares at each nozzle (the same look as the
## player ship's pixel exhaust, ShipEffects) that grows with the throttle and changes colour with the gear, plus a soft
## glow on the hull. Shown in every visual style: a fighter is a separate ship, not the mothership's effects.

const PIXEL_SIZE := 0.3 ## metres on the 20 m player ship; scaled by the fighter's size
const PIXEL_LIFETIME := 0.2
const PIXELS_PER_ENGINE := 140
const RESPONSE := 8.0 ## per second
## Engines idle at this strength whenever a pilot (or AI) is flying, so a hovering fighter is visibly alive.
const IDLE_STRENGTH := 0.06
## Flame width at idle as a share of full-thrust width; it widens to 1 as the throttle comes up.
const IDLE_WIDTH := 0.4
## Nozzle radius (m) that burns at flame scale 1.
const NOZZLE_RADIUS_PER_SCALE := 0.45

var ship: Ship
var _plumes: Array[CPUParticles3D] = []
var _light := OmniLight3D.new()
var _strength := 0.0
var _gear := -1
var _scale := 1.0
## Flame size per plume: each flame is drawn as wide as its nozzle (its radius over NOZZLE_RADIUS_PER_SCALE; the length grows more slowly) (FighterDef.engine_radii).
var _plume_scales: Array[float] = []


func _init() -> void:
	name = "EngineFlames"


func setup(def: FighterDef, owner_ship: Ship) -> void:
	ship = owner_ship
	_scale = clampf(def.size / FighterDef.REFERENCE_SIZE, 0.4, 1.0)
	var nozzles: Array[Vector3] = def.engines.duplicate()
	if nozzles.is_empty():
		nozzles.append(Vector3(0.0, 0.0, def.size * 0.5))
	for index in nozzles.size():
		var plume_scale := _scale
		if index < def.engine_radii.size():
			plume_scale = def.engine_radii[index] / NOZZLE_RADIUS_PER_SCALE
		_plume_scales.append(plume_scale)
		var plume := _make_plume(index, plume_scale)
		plume.position = nozzles[index]
		add_child(plume)
		_plumes.append(plume)
	_light.name = "EngineGlow"
	_light.light_color = Color(0.3, 0.65, 1.0)
	_light.omni_range = def.size * 1.6
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	var middle := Vector3.ZERO
	for nozzle in nozzles:
		middle += nozzle
	_light.position = middle / float(nozzles.size()) + Vector3(0.0, 0.0, def.size * 0.12)
	add_child(_light)


func _process(delta: float) -> void:
	if ship == null or _plumes.is_empty():
		return
	var state := ship.state
	var target := 0.0
	if state.hull > 0.0 and not ship.controller.is_parked() and not state.landed:
		var command := ship.last_command
		var throttle := clampf(-command.thrust.z, 0.0, 1.0)
		throttle = maxf(throttle, clampf(command.thrust.length() * 0.5, 0.0, 0.5))
		if command.boost and throttle > 0.0:
			throttle = minf(throttle * 1.4, 1.4)
		target = maxf(IDLE_STRENGTH, throttle)
		_gear = state.gear
	_strength = move_toward(_strength, target, RESPONSE * delta)
	var burning := _strength > 0.02
	var ramp := ShipEffects._pixel_ramp(PilotCommand.GEAR_CRUISE if _gear >= PilotCommand.GEAR_CRUISE else PilotCommand.GEAR_COMBAT)
	for index in _plumes.size():
		var plume := _plumes[index]
		plume.emitting = burning
		if not burning:
			continue
		var plume_scale := _plume_scales[index]
		plume.color_ramp = ramp
		var thrust := clampf(inverse_lerp(IDLE_STRENGTH, 1.0, _strength), 0.0, 1.0)
		var length_scale := pow(plume_scale, 0.75)
		# Idle is a short, narrow, barely-there spit; thrust stretches it hard.
		plume.initial_velocity_min = (3.0 + 21.0 * thrust) * length_scale
		plume.initial_velocity_max = (5.0 + 33.0 * thrust) * length_scale
		var width := lerpf(IDLE_WIDTH, 1.0, thrust)
		plume.scale_amount_min = 0.7 * width
		plume.scale_amount_max = (1.0 + 0.6 * thrust) * width
		plume.emission_sphere_radius = 0.3 * plume_scale * width
	_light.light_energy = _strength * 2.2
	_light.light_color = Color(0.7, 0.45, 1.0) if _gear >= PilotCommand.GEAR_CRUISE else Color(0.3, 0.65, 1.0)


func is_burning() -> bool:
	return _strength > 0.02


func nozzle_count() -> int:
	return _plumes.size()


func _make_plume(index: int, plume_scale: float) -> CPUParticles3D:
	var pixels := CPUParticles3D.new()
	pixels.name = "EnginePixels%d" % (index + 1)
	pixels.amount = PIXELS_PER_ENGINE
	pixels.lifetime = PIXEL_LIFETIME
	pixels.local_coords = true
	pixels.mesh = ShipEffects._pixel_square(PIXEL_SIZE * plume_scale)
	pixels.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	pixels.emission_sphere_radius = 0.3 * plume_scale
	pixels.direction = Vector3(0, 0, 1) # out of the tail
	pixels.spread = 7.0
	pixels.gravity = Vector3.ZERO
	pixels.scale_amount_curve = Curve.new()
	pixels.scale_amount_curve.add_point(Vector2(0.0, 1.0))
	pixels.scale_amount_curve.add_point(Vector2(1.0, 0.25))
	pixels.color_ramp = ShipEffects._pixel_ramp(PilotCommand.GEAR_COMBAT)
	pixels.emitting = false
	return pixels
