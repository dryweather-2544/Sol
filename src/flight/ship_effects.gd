class_name ShipEffects
extends Node3D
## Rodina ship effects, shown only while the rodina VisualStyle is active (the sol style shows none of this, so its
## look is unchanged). A port of EGShipPlayer:SetMovementEffects and SetAtmoEntryEffects (EGDataShipPlayer.lua:288-449)
## and EGVehicle:UpdateAV (EGVehicle.lua:514-545): every frame each named slot is re-attached with a strength taken
## from the ship's real state, using the particle materials in RodinaParticleDefs (RodinaEmitter reads them).
##
## What drives what (Rodina gear 1..4 = Sol PRECISION, COMBAT, CRUISE, WARP):
## - Warp gear: before LimnalActivation reaches 1, "Limnal Startup Ring" at strength LimnalActivation and "Limnal Drive
##   Air"; from 1 on, "Limnal Drive", "Limnal Pink Air" and "LimnalShipBlur". The thrusters are off.
## - Other gears, unless the camera is inside the ship: the main engine ("DockAir" in precision on two aft vents,
##   "CombatEngineMain" in combat, "CruiseEngineMain" in cruise) at the forward-thrust strength, and twelve thruster
##   jets for back/up/down/left/right thrust ("DockAir"/"DockAirDown" in precision, "CombatEngineSmall" in combat,
##   "CruiseEngineSmall" in cruise); down thrust at 0.75.
## - Cruise above Rodina's 10 km/s cruise speed: "CruiseEngineInertia" along the velocity at
##   EGAnalogue(timeFactor, 1, 30, 0, 1). Rodina's timeFactor is the cruise relative time; Sol has no relative time
##   (its cruise raises the speed limit instead), so speed / 10 km/s stands in for it, which is what the relative
##   time multiplies.
## - Atmospheric entry, from ShipState.atmosphere_resistance: wind = EGAnalogue(r, 0, .5, .1, 1) when r > 0, flames =
##   EGAnalogue(r, .3, .8, .5, 1) when r > .3; "AtmosphereEntry" 15 m and "AtmosphereShockwave" 30 m ahead along the
##   velocity (Rodina metres), or the "...Cockpit" variants when the camera is inside.
## Sol differences: Sol's main engines are two tilting pods, so each engine effect runs at each pod nozzle along the
## nozzle's real axis (Rodina has one aft engine). Rodina's thruster positions are scaled by RodinaEmitter.SHIP_SCALE.
## Rodina's coasting "Wing" trails need its clutch, which Sol does not have.

const RODINA_CRUISE_SPEED := 10000.0 # kPlayerCruiseSpeed, EGVehicle.lua:11

# Rodina emitter positions and directions (EGDataShipPlayer.lua:252-283), Rodina ship axes.
const _BACKWARDS := Vector3(0, -1, 0)
const _DOCK_B := [Vector3(-20, -8, -8), Vector3(20, -8, -8)]
const _JETS := {
	"F": [[Vector3(-15, 35, -8), Vector3(0, 1, 0.05)], [Vector3(15, 35, -8), Vector3(0, 1, 0.05)]],
	"D": [[Vector3(-12, 0, -10), Vector3(-0.1, -0.1, -1)], [Vector3(12, 0, -10), Vector3(0.1, -0.1, -1)], [Vector3(0, 20, -10), Vector3(0, 0.25, -1)]],
	"U": [[Vector3(-12, 0, 0), Vector3(-0.1, -0.1, 1)], [Vector3(12, 0, 0), Vector3(0.1, -0.1, 1)], [Vector3(0, 20, 0), Vector3(0, 0.25, 1)]],
	"R": [[Vector3(20, 12, -8), Vector3(1, 0.4, 0.1)], [Vector3(20, -5, -8), Vector3(1, -0.4, 0.1)]],
	"L": [[Vector3(-20, 12, -8), Vector3(-1, 0.4, 0.1)], [Vector3(-20, -5, -8), Vector3(-1, -0.4, 0.1)]],
}

## Set by the main scene each tick from its LimnalWarpView (Rodina keeps LimnalActivation on the ship).
var limnal_activation := 0.0
## True when the camera is inside the ship (cockpit view, walking the interior): Rodina's IsPlayerAndCameraInsideVehicle.
var camera_inside := false

var _nacelles: Array[MeshInstance3D] = []
var _slots := {} # slot name -> {material name -> RodinaEmitter}


## nacelles: the nozzle nodes (cylinder +y is the exhaust direction).
func setup(nacelles: Array[MeshInstance3D]) -> void:
	name = "ShipEffects"
	_nacelles = nacelles


func update_effects(ship: Ship, _delta: float) -> void:
	var active := VisualStyle.is_rodina()
	visible = active
	for slot in _slots.values():
		for emitter: RodinaEmitter in slot.values():
			emitter.begin_frame()
	if active:
		_drive_all(ship)
	for slot in _slots.values():
		for emitter: RodinaEmitter in slot.values():
			emitter.end_frame()


## Live emitters (strength above zero this frame) by slot, for tests and the effect check tool.
func active_effects() -> Dictionary:
	var result := {}
	for slot_name in _slots:
		for material_name in _slots[slot_name]:
			var emitter: RodinaEmitter = _slots[slot_name][material_name]
			if emitter.is_active():
				result[slot_name] = {"material": material_name, "strength": emitter.amount_ratio}
	return result


func _drive_all(ship: Ship) -> void:
	var state := ship.state
	var command := ship.last_command
	if state.hull <= 0.0:
		return
	# Rodina movement axes: x right, y forward, z up. Sol thrust: x right, y up, z backwards.
	var thrust := command.thrust.limit_length(1.0)
	var right_strength := maxf(thrust.x, 0.0)
	var left_strength := maxf(-thrust.x, 0.0)
	var forward_strength := maxf(-thrust.z, 0.0)
	var back_strength := maxf(thrust.z, 0.0)
	var up_strength := maxf(thrust.y, 0.0)
	var down_strength := maxf(-thrust.y, 0.0)
	var velocity_local := state.basis.transposed() * state.velocity
	var speed := velocity_local.length()
	if state.gear == PilotCommand.GEAR_WARP:
		if limnal_activation >= 1.0:
			_attach("Limnal Drive", "Limnal Drive", 1.0, Vector3.ZERO, RodinaEmitter.from_rodina(Vector3(1, 0, 0), false))
			_attach("Limnal Air", "Limnal Pink Air", 1.0, Vector3.ZERO, RodinaEmitter.from_rodina(Vector3(0, 1, 0), false))
			_attach("Limnal Blur", "LimnalShipBlur", 1.0, Vector3.ZERO, RodinaEmitter.from_rodina(Vector3(0, -1, 0), false))
		else:
			_attach("Limnal Drive", "Limnal Startup Ring", limnal_activation, Vector3.ZERO, RodinaEmitter.from_rodina(Vector3(1, 0, 0), false))
			_attach("Limnal Air", "Limnal Drive Air", 1.0, Vector3.ZERO, RodinaEmitter.from_rodina(Vector3(0, 1, 0), false))
	elif not camera_inside:
		var small := "DockAirDown"
		var medium := "DockAir"
		if state.gear == PilotCommand.GEAR_DOCK:
			for index in _DOCK_B.size():
				_attach("Engine DockB %d" % (index + 1), medium, forward_strength, RodinaEmitter.from_rodina(_DOCK_B[index]), RodinaEmitter.from_rodina(_BACKWARDS, false))
		else:
			var main := "CombatEngineMain" if state.gear == PilotCommand.GEAR_COMBAT else "CruiseEngineMain"
			small = "CombatEngineSmall" if state.gear == PilotCommand.GEAR_COMBAT else "CruiseEngineSmall"
			medium = small
			for index in _nacelles.size():
				var nozzle := _nacelles[index].transform
				_attach("Engine Fire Effect %d" % (index + 1), main, forward_strength, nozzle * Vector3(0, 0.4, 0), nozzle.basis.y)
		_jets("F", medium, back_strength)
		_jets("D", small, up_strength)
		_jets("U", small, down_strength * 0.75)
		_jets("R", small, left_strength)
		_jets("L", small, right_strength)
	var time_factor := speed / RODINA_CRUISE_SPEED if state.gear == PilotCommand.GEAR_CRUISE else 1.0
	if state.gear != PilotCommand.GEAR_WARP and time_factor > 1.05 and not camera_inside:
		var warp_factor := RodinaMath.analogue(time_factor, 1.0, 30.0, 0.0, 1.0)
		var speed_factor := RodinaMath.analogue(speed, 0.0, RODINA_CRUISE_SPEED * time_factor, 0.0, 1.0)
		_attach("Cruise Limnal Inertia", "CruiseEngineInertia", warp_factor * speed_factor, RodinaEmitter.from_rodina(Vector3(0, 0, -5)), velocity_local)
	var resistance := state.atmosphere_resistance
	if resistance > 0.0 and speed > 1e-3:
		var wind := RodinaMath.analogue(resistance, 0.0, 0.5, 0.1, 1.0)
		var flames := RodinaMath.analogue(resistance, 0.3, 0.8, 0.5, 1.0) if resistance > 0.3 else 0.0
		var heading := velocity_local / speed
		var suffix := "Cockpit" if camera_inside else ""
		_attach("Atmosphere Entry", "AtmosphereEntry" + suffix, flames, heading * 15.0 * RodinaEmitter.SHIP_SCALE, heading)
		_attach("Atmosphere Entry2", "AtmosphereShockwave" + suffix, wind, heading * 30.0 * RodinaEmitter.SHIP_SCALE, heading)


func _jets(group: String, material_name: String, strength: float) -> void:
	var jets: Array = _JETS[group]
	for index in jets.size():
		_attach("Engine Dock%s %d" % [group, index + 1], material_name, strength, RodinaEmitter.from_rodina(jets[index][0]), RodinaEmitter.from_rodina(jets[index][1], false))


## AttachParticles(slot, material, strength, position, direction). A slot that changes material (e.g. the warp ring
## giving way to the drive stream) keeps one emitter per material so the old one's particles finish their lives.
func _attach(slot_name: String, material_name: String, strength: float, local_position: Vector3, local_direction: Vector3) -> void:
	var slot: Dictionary = _slots.get(slot_name, {})
	_slots[slot_name] = slot
	var emitter: RodinaEmitter = slot.get(material_name)
	if emitter == null:
		if strength <= 0.0:
			return # nothing to show yet; build the emitter the first time it is needed
		emitter = RodinaEmitter.new()
		emitter.setup(material_name)
		add_child(emitter)
		slot[material_name] = emitter
	emitter.drive(strength, local_position, local_direction)


## A round dot, bright in the middle and fading to nothing at the edge (Rodina's particle sprite is engine-supplied).
static func soft_dot() -> GradientTexture2D:
	if _dot == null:
		_dot = GradientTexture2D.new()
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		_dot.width = 64
		_dot.height = 64
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
		_dot.gradient = gradient
	return _dot


static var _dot: GradientTexture2D
