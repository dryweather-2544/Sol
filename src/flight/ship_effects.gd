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
## The main engines are a flame cone per nozzle, not Rodina's CombatEngineMain/CruiseEngineMain sparks: the owner's Rodina
## screenshots and request show a blue flame out of the engines that grows with speed (N13). Colours are those
## materials' key colours (combat cyan -> blue; cruise blue-violet, brightened since Rodina's are near-black additive).
const FLAME_COLORS := {
	PilotCommand.GEAR_COMBAT: [Color(0.0, 0.7, 1.0), Color(0.0, 0.3, 1.0)],
	PilotCommand.GEAR_CRUISE: [Color(0.5, 0.55, 1.0), Color(0.25, 0.12, 1.0)],
}
## Flame length in metres at no thrust and the extra at full forward thrust; cruise burns longer than combat.
const FLAME_LENGTH := {PilotCommand.GEAR_COMBAT: [2.0, 10.0], PilotCommand.GEAR_CRUISE: [3.0, 18.0]}
## A soft glow billboard at each nozzle, so the flame reads from behind as well as from the side (metres across).
const FLAME_GLOW_SIZE := {PilotCommand.GEAR_COMBAT: [1.5, 3.5], PilotCommand.GEAR_CRUISE: [2.0, 5.0]}
const FLAME_RESPONSE := 8.0 # per second
var _flames: Array[MeshInstance3D] = []
var _flame_glows: Array[MeshInstance3D] = []
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
	if active:
		_drive_all(ship)
	for slot in _slots.values():
		for emitter: RodinaEmitter in slot.values():
			emitter.end_frame()
	_update_flames(delta)


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
			small = "CombatEngineSmall" if state.gear == PilotCommand.GEAR_COMBAT else "CruiseEngineSmall"
			medium = small
			_flame_gear = state.gear
			_flame_target = forward_strength
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


func _update_flames(delta: float) -> void:
	_flame_strength = move_toward(_flame_strength, _flame_target, FLAME_RESPONSE * delta) if delta > 0.0 else _flame_target
	if _flames.is_empty() and _flame_strength > 0.0:
		for index in _nacelles.size():
			_flames.append(_make_flame(index))
			_flame_glows.append(_make_flame_glow(index))
	if not FLAME_COLORS.has(_flame_gear):
		_flame_strength = 0.0
	for index in _flames.size():
		var flame := _flames[index]
		flame.visible = _flame_strength > 0.01
		_flame_glows[index].visible = flame.visible
		if not flame.visible:
			continue
		var lengths: Array = FLAME_LENGTH[_flame_gear]
		var length: float = lengths[0] + lengths[1] * _flame_strength
		var colors: Array = FLAME_COLORS[_flame_gear]
		var material := flame.material_override as ShaderMaterial
		material.set_shader_parameter("core_color", (colors[0] as Color).lerp(Color.WHITE, 0.35))
		material.set_shader_parameter("edge_color", colors[1])
		material.set_shader_parameter("intensity", 0.35 + 0.65 * _flame_strength)
		var nozzle := _nacelles[index].transform
		# Cone from the nozzle exit (cylinder +y = exhaust) outwards, centred half a length aft.
		flame.transform = nozzle * Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, length, 1.0)), Vector3(0, 0.4 + length * 0.5, 0))
		var glow := _flame_glows[index]
		var sizes: Array = FLAME_GLOW_SIZE[_flame_gear]
		var glow_size: float = sizes[0] + sizes[1] * _flame_strength
		glow.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * glow_size), nozzle * Vector3(0, 0.6, 0))
		var glow_color: Color = (colors[0] as Color).lerp(Color.WHITE, 0.2)
		glow_color.a = 0.35 + 0.5 * _flame_strength
		(glow.material_override as StandardMaterial3D).albedo_color = glow_color
		# Hard-edged pixel layer on top of the source-derived flame cone. The owner asked for the
		# same stepped language as the entry fire; the cone remains the smooth volumetric base.
		if index >= _pixel_plumes.size():
			var pixel := _make_pixel_plume(index)
			_pixel_plumes.append(pixel)
		var pixels := _pixel_plumes[index]
		pixels.transform = nozzle * Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0))
		pixels.direction = Vector3(0, 1, 0)
		pixels.emitting = flame.visible
		pixels.color_ramp = _pixel_ramp(_flame_gear)
		pixels.scale_amount_min = 0.6 + 0.5 * _flame_strength
		pixels.scale_amount_max = 1.3 + 0.8 * _flame_strength


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
	pixels.amount = 30
	pixels.lifetime = 0.32
	pixels.local_coords = true
	pixels.mesh = _pixel_square(1.2)
	pixels.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	pixels.spread = 14.0
	pixels.gravity = Vector3.ZERO
	pixels.initial_velocity_min = 25.0
	pixels.initial_velocity_max = 42.0
	pixels.scale_amount_curve = Curve.new()
	pixels.scale_amount_curve.add_point(Vector2(0.0, 1.0))
	pixels.scale_amount_curve.add_point(Vector2(1.0, 0.3))
	pixels.color_ramp = _pixel_ramp(PilotCommand.GEAR_COMBAT)
	pixels.emitting = false
	add_child(pixels)
	return pixels


static func _pixel_ramp(gear: int) -> Gradient:
	var gradient := Gradient.new()
	if gear == PilotCommand.GEAR_CRUISE:
		gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		gradient.colors = PackedColorArray([Color(0.75, 0.9, 1.0, 0.95), Color(0.35, 0.3, 1.0, 0.7), Color(0.05, 0.02, 0.3, 0.0)])
	else:
		gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		gradient.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 0.95), Color(0.0, 0.7, 1.0, 0.7), Color(0.0, 0.2, 0.6, 0.0)])
	return gradient


func _make_flame(index: int) -> MeshInstance3D:
	var cone := CylinderMesh.new()
	cone.bottom_radius = 0.6 # at the nozzle (mesh y = -0.5)
	cone.top_radius = 0.05
	cone.height = 1.0
	cone.radial_segments = 20
	cone.rings = 6
	var flame := MeshInstance3D.new()
	flame.name = "EngineFlame%d" % (index + 1)
	flame.mesh = cone
	var material := ShaderMaterial.new()
	material.shader = load("res://data/shaders/engine_flame.gdshader")
	material.set_shader_parameter("seed", float(index) * 3.7)
	flame.material_override = material
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.visible = false
	add_child(flame)
	return flame


func _make_flame_glow(index: int) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = soft_dot()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var glow := MeshInstance3D.new()
	glow.name = "EngineGlow%d" % (index + 1)
	glow.mesh = quad
	glow.material_override = material
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.visible = false
	add_child(glow)
	return glow


## Main engine flames now (for tests and the check tool): gear and 0..1 strength.
func flame_state() -> Dictionary:
	return {"gear": _flame_gear, "strength": _flame_strength, "visible": not _flames.is_empty() and _flames[0].visible}


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
