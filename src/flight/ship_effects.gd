class_name ShipEffects
extends Node3D
## Rodina ship effects, shown only while the rodina VisualStyle is active (the sol style shows none of this, so its
## look is unchanged). A port of EGShipPlayer:SetMovementEffects and SetAtmoEntryEffects (EGDataShipPlayer.lua:288-449)
## and EGVehicle:UpdateAV (EGVehicle.lua:514-545): every frame each named slot is re-attached with a strength taken
## from the ship's real state, using the particle materials in RodinaParticleDefs (RodinaEmitter reads them).
##
## What drives what (Rodina gear 1..4 = Sol PRECISION, COMBAT, CRUISE, WARP):
## - Warp gear: before LimnalActivation reaches 1, "Limnal Startup Ring" at strength LimnalActivation and "Limnal Drive
##   Air"; from 1 on, "Limnal Drive" and "LimnalShipBlur" (Pink Air is not attached: it drew as dark red squares). The thrusters are off.
## - Other gears, unless the camera is inside the ship: the main engine ("DockAir" in precision on two aft vents; in
##   combat and cruise a blue flame per nozzle, see FLAME_COLORS) at the forward-thrust strength, and twelve thruster
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
## Clutch held (trying to shift): the thrust flame gives way to two long yellow-green streaks of squares, one per nozzle,
## with green squares flickering off their tips (read from the owner's Rodina footage; the real material is not in the
## extracted data). They end when the clutch is released or the shift commits.

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
## A small fighter: only the warp, cruise-trail and atmosphere-entry effects are driven (FighterEngineFlames draws its engines, and
## Rodina's thruster jets sit at the mothership's positions), and the entry fire is placed by `position_scale` times the mothership's.
var fighter_mode := false
var position_scale := 1.0

var _nacelles: Array[MeshInstance3D] = []
var _slots := {} # slot name -> {material name -> RodinaEmitter}
## The main engines are a flame cone per nozzle, not Rodina's CombatEngineMain/CruiseEngineMain sparks: the owner's Rodina
## screenshots and request show a blue flame out of the engines that grows with speed (N13). Colours are those
## materials' key colours (combat cyan -> blue; cruise blue-violet, brightened since Rodina's are near-black additive).
const FLAME_COLORS := {
	PilotCommand.GEAR_COMBAT: [Color(0.25, 0.65, 1.0), Color(0.05, 0.28, 1.0)],
	# Footage: the cruise gear is "the purple gear" - a white-hot core inside a violet plume.
	PilotCommand.GEAR_CRUISE: [Color(0.88, 0.75, 1.0), Color(0.52, 0.12, 1.0)],
}
## The exhaust's tiny squares: many of them, small, short-lived and fast, so the plume is dense and compact.
const PIXEL_COUNT := 220
const PIXEL_SIZE := 0.3 # metres
const PIXEL_LIFETIME := 0.2 # seconds
const PIXEL_SPEED_MIN := [14.0, 14.0] # m/s at no thrust, extra at full thrust
const PIXEL_SPEED_MAX := [22.0, 26.0]
const FLAME_RESPONSE := 8.0 # per second
const FLAME_IDLE := 0.06 # strength with no thrust: a small spit of flame
## Clutch streaks: a thin column of squares left hanging in the world behind the engines.
const STREAK_COUNT := 160
const STREAK_SIZE := 0.28
const STREAK_LIFETIME := 0.4
var _streak_plumes: Array[CPUParticles3D] = []
var _clutch_on := false
var _ship_velocity := Vector3.ZERO # ship frame, m/s
## The streak hangs in the world where it was thrown: each square is given the ship's velocity reversed (capped so it
## stays a streak, not a line across the map), so you pull away from it. Nearly still, it falls back to a short plume.
const STREAK_MIN_SPEED := 10.0
const STREAK_MAX_SPEED := 45.0
const STREAK_STILL := 3.0 # m/s below which the ship counts as still
var _pixel_plumes: Array[CPUParticles3D] = []
var _flame_gear := -1
var _flame_target := 0.0
var _flame_strength := 0.0


## nacelles: the nozzle nodes (cylinder +y is the exhaust direction).
func setup(nacelles: Array[MeshInstance3D]) -> void:
	name = "ShipEffects"
	_nacelles = nacelles


func update_effects(ship: Ship, delta: float) -> void:
	var active := VisualStyle.is_rodina()
	visible = active
	for slot in _slots.values():
		for emitter: RodinaEmitter in slot.values():
			emitter.begin_frame()
	_flame_target = 0.0
	_clutch_on = false
	if active:
		_drive_all(ship)
	for slot in _slots.values():
		for emitter: RodinaEmitter in slot.values():
			emitter.end_frame()
	_update_flames(delta)
	_update_streaks()


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
	_clutch_on = state.clutch and state.gear < PilotCommand.GEAR_WARP and not camera_inside and not fighter_mode
	var thrust := command.thrust.limit_length(1.0)
	var right_strength := maxf(thrust.x, 0.0)
	var left_strength := maxf(-thrust.x, 0.0)
	var forward_strength := maxf(-thrust.z, 0.0)
	var back_strength := maxf(thrust.z, 0.0)
	var up_strength := maxf(thrust.y, 0.0)
	var down_strength := maxf(-thrust.y, 0.0)
	var velocity_local := state.basis.transposed() * state.velocity
	var speed := velocity_local.length()
	_ship_velocity = velocity_local
	if state.gear == PilotCommand.GEAR_WARP:
		if limnal_activation >= 1.0:
			_attach("Limnal Drive", "Limnal Drive", 1.0, Vector3.ZERO, RodinaEmitter.from_rodina(Vector3(1, 0, 0), false))
			_attach("Limnal Blur", "LimnalShipBlur", 1.0, Vector3.ZERO, RodinaEmitter.from_rodina(Vector3(0, -1, 0), false))
		else:
			_attach("Limnal Drive", "Limnal Startup Ring", limnal_activation, Vector3.ZERO, RodinaEmitter.from_rodina(Vector3(1, 0, 0), false))
			_attach("Limnal Air", "Limnal Drive Air", 1.0, Vector3.ZERO, RodinaEmitter.from_rodina(Vector3(0, 1, 0), false))
	elif not camera_inside and not fighter_mode:
		var small := "DockAirDown"
		var medium := "DockAir"
		if state.gear == PilotCommand.GEAR_DOCK:
			for index in _DOCK_B.size():
				_attach("Engine DockB %d" % (index + 1), medium, forward_strength, RodinaEmitter.from_rodina(_DOCK_B[index]), RodinaEmitter.from_rodina(_BACKWARDS, false))
		else:
			small = "CombatEngineSmall" if state.gear == PilotCommand.GEAR_COMBAT else "CruiseEngineSmall"
			medium = small
			_flame_gear = state.gear
			# The pods vector, so any fore/aft/up/down thrust burns; the engines never go fully dark, they idle.
			_flame_target = maxf(minf(Vector2(thrust.y, thrust.z).length(), 1.0), FLAME_IDLE)
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
		_attach("Atmosphere Entry", "AtmosphereEntry" + suffix, flames, heading * 15.0 * RodinaEmitter.SHIP_SCALE * position_scale, heading)
		_attach("Atmosphere Entry2", "AtmosphereShockwave" + suffix, wind, heading * 30.0 * RodinaEmitter.SHIP_SCALE * position_scale, heading)


func _update_flames(delta: float) -> void:
	_flame_strength = move_toward(_flame_strength, _flame_target, FLAME_RESPONSE * delta) if delta > 0.0 else _flame_target
	if not FLAME_COLORS.has(_flame_gear):
		_flame_strength = 0.0
	var active := _flame_strength > 0.01
	if active and _pixel_plumes.is_empty():
		for index in _nacelles.size():
			_pixel_plumes.append(_make_pixel_plume(index))
	for index in _pixel_plumes.size():
		var pixels := _pixel_plumes[index]
		if not active:
			pixels.emitting = false
			continue
		# The exhaust is only a dense, compact burst of tiny hard-edged squares at each nozzle: no flame beam, no glow orb.
		var nozzle := _nacelles[index].transform
		pixels.transform = nozzle * Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0))
		pixels.direction = Vector3(0, 1, 0)
		pixels.emitting = true
		pixels.color_ramp = _pixel_ramp(_flame_gear)
		var thrust := clampf(inverse_lerp(FLAME_IDLE, 1.0, _flame_strength), 0.0, 1.0)
		var width := lerpf(0.4, 1.0, thrust)
		pixels.initial_velocity_min = 3.0 + (PIXEL_SPEED_MIN[0] + PIXEL_SPEED_MIN[1] - 3.0) * thrust
		pixels.initial_velocity_max = 5.0 + (PIXEL_SPEED_MAX[0] + PIXEL_SPEED_MAX[1] - 5.0) * thrust
		pixels.scale_amount_min = 0.7 * width
		pixels.scale_amount_max = (1.2 + 0.5 * thrust) * width
		pixels.emission_sphere_radius = 0.32 * width


func _update_streaks() -> void:
	if _clutch_on and _streak_plumes.is_empty():
		for index in _nacelles.size():
			_streak_plumes.append(_make_streak(index))
	for index in _streak_plumes.size():
		var streak := _streak_plumes[index]
		streak.emitting = _clutch_on
		if not _clutch_on:
			continue
		var nozzle := _nacelles[index].transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0))
		streak.transform = nozzle
		# Particle motion is in the emitter's frame (local_coords): reversing the ship's own velocity there leaves the
		# squares standing still in the world while the ship moves on.
		var relative := nozzle.basis.inverse() * (-_ship_velocity)
		var speed := relative.length()
		if speed < STREAK_STILL:
			streak.direction = Vector3(0, 1, 0)
			streak.initial_velocity_min = STREAK_MIN_SPEED * 0.5
			streak.initial_velocity_max = STREAK_MIN_SPEED
		else:
			var capped := clampf(speed, STREAK_MIN_SPEED, STREAK_MAX_SPEED)
			streak.direction = relative / speed
			streak.initial_velocity_min = capped * 0.97
			streak.initial_velocity_max = capped


func _make_streak(index: int) -> CPUParticles3D:
	var streak := CPUParticles3D.new()
	streak.name = "ClutchStreak%d" % (index + 1)
	streak.amount = STREAK_COUNT
	streak.lifetime = STREAK_LIFETIME
	streak.local_coords = true
	streak.mesh = _pixel_square(STREAK_SIZE)
	streak.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	streak.emission_sphere_radius = 0.2
	streak.direction = Vector3(0, 1, 0)
	streak.spread = 1.0
	streak.gravity = Vector3.ZERO
	streak.scale_amount_min = 0.8
	streak.scale_amount_max = 1.1
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.98, 0.2, 0.95), Color(0.9, 0.95, 0.15, 0.85), Color(0.35, 0.95, 0.15, 0.0)])
	streak.color_ramp = ramp
	streak.emitting = false
	add_child(streak)
	return streak


func clutch_streaks_active() -> bool:
	return _clutch_on


## A hard-edged additive square. Used by the owner-requested pixel engine layer; the entry fire
## uses hard blocks for the same reason, so engine and atmospheric flames share a visual language.
static func _pixel_square(size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = material
	return quad


func _make_pixel_plume(index: int) -> CPUParticles3D:
	var pixels := CPUParticles3D.new()
	pixels.name = "EnginePixels%d" % (index + 1)
	pixels.amount = PIXEL_COUNT
	pixels.lifetime = PIXEL_LIFETIME
	pixels.local_coords = true
	pixels.mesh = _pixel_square(PIXEL_SIZE)
	pixels.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	pixels.emission_sphere_radius = 0.32
	pixels.spread = 7.0
	pixels.gravity = Vector3.ZERO
	pixels.scale_amount_curve = Curve.new()
	pixels.scale_amount_curve.add_point(Vector2(0.0, 1.0))
	pixels.scale_amount_curve.add_point(Vector2(1.0, 0.25))
	pixels.color_ramp = _pixel_ramp(PilotCommand.GEAR_COMBAT)
	pixels.emitting = false
	add_child(pixels)
	return pixels


static func _pixel_ramp(gear: int) -> Gradient:
	var gradient := Gradient.new()
	if gear == PilotCommand.GEAR_CRUISE:
		gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		gradient.colors = PackedColorArray([Color(0.92, 0.82, 1.0, 0.95), Color(0.55, 0.2, 1.0, 0.7), Color(0.15, 0.02, 0.4, 0.0)])
	else:
		gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		gradient.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 0.95), Color(0.0, 0.7, 1.0, 0.7), Color(0.0, 0.2, 0.6, 0.0)])
	return gradient


## Main engine flames now (for tests and the check tool): gear and 0..1 strength.
func flame_state() -> Dictionary:
	return {"gear": _flame_gear, "strength": _flame_strength, "visible": _flame_strength > 0.01}


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
