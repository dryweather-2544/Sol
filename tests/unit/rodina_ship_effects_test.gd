extends "res://tests/test_case.gd"
## ShipEffects: which Rodina particle material runs in which slot, at what strength, for each ship state
## (EGShipPlayer:SetMovementEffects / SetAtmoEntryEffects). Strength values are worked by hand from the Lua.


func _setup() -> Array:
	var ship := Ship.new()
	var effects := ShipEffects.new()
	var nacelles: Array[MeshInstance3D] = []
	for side in [-1.0, 1.0]:
		var nacelle := MeshInstance3D.new()
		nacelle.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(side * 4.0, 0.0, 9.0)) # +y aft
		effects.add_child(nacelle)
		nacelles.append(nacelle)
	effects.setup(nacelles)
	return [ship, effects]


func _free(objects: Array) -> void:
	(objects[1] as Node).free()
	(objects[0] as Node).free()


func _command(thrust: Vector3) -> PilotCommand:
	var command := PilotCommand.new()
	command.thrust = thrust
	return command


func _with_rodina(body: Callable) -> void:
	var before := VisualStyle.active()
	VisualStyle.set_active(VisualStyle.RODINA)
	body.call()
	VisualStyle.set_active(before)


func test_sol_style_shows_no_rodina_effects() -> void:
	var before := VisualStyle.active()
	VisualStyle.set_active(VisualStyle.SOL)
	var objects := _setup()
	var ship: Ship = objects[0]
	var effects: ShipEffects = objects[1]
	ship.state.gear = PilotCommand.GEAR_CRUISE
	ship.last_command = _command(Vector3(0, 0, -1))
	effects.update_effects(ship, 1.0 / 60.0)
	assert_eq(effects.active_effects().size(), 0)
	assert_true(not effects.visible)
	_free(objects)
	VisualStyle.set_active(before)


func test_gear_engines_follow_thrust_axes() -> void:
	_with_rodina(func() -> void:
		var objects := _setup()
		var ship: Ship = objects[0]
		var effects: ShipEffects = objects[1]
		ship.state.gear = PilotCommand.GEAR_CRUISE
		ship.last_command = _command(Vector3(0, 0, -1)) # full forward
		effects.update_effects(ship, 0.0) # delta 0 snaps the flame to its target
		var active := effects.active_effects()
		assert_eq(active.size(), 0, "full forward fires only the main engine flames, no jets: %s" % str(active.keys()))
		var flame := effects.flame_state()
		assert_eq(flame["gear"], PilotCommand.GEAR_CRUISE)
		assert_near(flame["strength"], 1.0, 1e-6)
		assert_true(flame["visible"])
		# Combat at half thrust: the flame follows the thrust, easing at FLAME_RESPONSE per second.
		ship.state.gear = PilotCommand.GEAR_COMBAT
		ship.last_command = _command(Vector3(0, 0, -0.5))
		effects.update_effects(ship, 1.0 / 60.0)
		assert_near(effects.flame_state()["strength"], 1.0 - ShipEffects.FLAME_RESPONSE / 60.0, 1e-6)
		for tick in 60:
			effects.update_effects(ship, 1.0 / 60.0)
		assert_near(effects.flame_state()["strength"], 0.5, 1e-6)
		assert_eq(effects.flame_state()["gear"], PilotCommand.GEAR_COMBAT)
		# Precision gear, thrust up: three DockAirDown jets; down thrust runs at 0.75; the main engine is off.
		ship.state.gear = PilotCommand.GEAR_DOCK
		ship.last_command = _command(Vector3(0, 1, 0))
		effects.update_effects(ship, 1.0 / 60.0)
		active = effects.active_effects()
		for index in [1, 2, 3]:
			assert_eq(active.get("Engine DockD %d" % index, {}).get("material"), "DockAirDown")
		for tick in 60:
			effects.update_effects(ship, 1.0 / 60.0)
		assert_true(not effects.flame_state()["visible"], "the flame dies out in precision gear")
		ship.last_command = _command(Vector3(0, -1, 0))
		effects.update_effects(ship, 1.0 / 60.0)
		active = effects.active_effects()
		assert_near(active["Engine DockU 1"]["strength"], 0.75, 1e-6)
		assert_true(not active.has("Engine DockD 1"))
		# Strafing right fires the left-side jets (Rodina: DockL at the right strength).
		ship.last_command = _command(Vector3(1, 0, 0))
		effects.update_effects(ship, 1.0 / 60.0)
		active = effects.active_effects()
		assert_true(active.has("Engine DockL 1") and active.has("Engine DockL 2") and not active.has("Engine DockR 1"))
		_free(objects))


func test_main_engine_flame_runs_along_each_nozzle() -> void:
	_with_rodina(func() -> void:
		var objects := _setup()
		var ship: Ship = objects[0]
		var effects: ShipEffects = objects[1]
		ship.state.gear = PilotCommand.GEAR_COMBAT
		ship.last_command = _command(Vector3(0, 0, -1))
		effects.update_effects(ship, 0.0)
		var flame := effects.get_node("EngineFlame1") as MeshInstance3D
		assert_true(flame != null and flame.visible)
		var aft := flame.transform.basis.y.normalized()
		assert_true(aft.dot(Vector3(0, 0, 1)) > 0.999, "flame runs along the nozzle's +y (aft): %s" % str(aft))
		var length := flame.transform.basis.y.length()
		assert_near(length, 2.0 + 10.0, 1e-4, "combat flame at full thrust")
		assert_true(flame.transform.origin.z > 9.0, "starts at the nozzle and extends aft")
		_free(objects))


func test_warp_runs_the_limnal_effects_and_silences_the_engines() -> void:
	_with_rodina(func() -> void:
		var objects := _setup()
		var ship: Ship = objects[0]
		var effects: ShipEffects = objects[1]
		ship.state.gear = PilotCommand.GEAR_WARP
		ship.last_command = _command(Vector3(0, 0, -1))
		effects.limnal_activation = 0.5
		effects.update_effects(ship, 1.0 / 60.0)
		var active := effects.active_effects()
		assert_eq(active["Limnal Drive"]["material"], "Limnal Startup Ring")
		assert_near(active["Limnal Drive"]["strength"], 0.5, 1e-6, "ring strength = LimnalActivation")
		assert_eq(active["Limnal Air"]["material"], "Limnal Drive Air")
		assert_eq(active.size(), 2, "no engines or jets in warp: %s" % str(active.keys()))
		# The ring's Offset (-1000, 0, 0) is on the style X axis; with the drive direction (1, 0, 0) it lands ahead.
		var ring := effects.get_node("Rodina_LimnalStartupRing") as RodinaEmitter
		var offset: Vector3 = (ring.process_material as ShaderMaterial).get_shader_parameter("offset")
		var ahead := ring.transform.basis * offset
		assert_near(ahead.z, -1000.0 * RodinaEmitter.SHIP_SCALE, 1e-3, "ring ahead of the ship: %s" % str(ahead))
		effects.limnal_activation = 1.0
		effects.update_effects(ship, 1.0 / 60.0)
		active = effects.active_effects()
		assert_eq(active["Limnal Drive"]["material"], "Limnal Drive")
		assert_eq(active["Limnal Air"]["material"], "Limnal Pink Air")
		assert_eq(active["Limnal Blur"]["material"], "LimnalShipBlur")
		assert_true(not ring.is_active(), "the startup ring stops once the drive is fully active")
		# Leaving warp: all limnal slots stop.
		ship.state.gear = PilotCommand.GEAR_CRUISE
		ship.last_command = _command(Vector3.ZERO)
		effects.update_effects(ship, 1.0 / 60.0)
		assert_eq(effects.active_effects().size(), 0, "nothing left on: %s" % str(effects.active_effects().keys()))
		_free(objects))


func test_cruise_inertia_streaks_above_rodina_cruise_speed() -> void:
	_with_rodina(func() -> void:
		var objects := _setup()
		var ship: Ship = objects[0]
		var effects: ShipEffects = objects[1]
		ship.state.gear = PilotCommand.GEAR_CRUISE
		ship.last_command = _command(Vector3.ZERO)
		ship.state.velocity = Vector3(0, 0, -9000.0)
		effects.update_effects(ship, 1.0 / 60.0)
		assert_true(not effects.active_effects().has("Cruise Limnal Inertia"), "below 1.05 x 10 km/s: none")
		ship.state.velocity = Vector3(0, 0, -150000.0) # time factor 15
		effects.update_effects(ship, 1.0 / 60.0)
		var active := effects.active_effects()
		assert_near(active["Cruise Limnal Inertia"]["strength"], 14.0 / 29.0, 1e-5, "EGAnalogue(15, 1, 30, 0, 1)")
		var streak := effects.get_node("Rodina_CruiseEngineInertia") as RodinaEmitter
		assert_true(streak.transform.basis.y.normalized().dot(Vector3(0, 0, -1)) > 0.999, "aligned with the velocity")
		_free(objects))


func test_atmospheric_entry_follows_resistance_and_camera() -> void:
	_with_rodina(func() -> void:
		var objects := _setup()
		var ship: Ship = objects[0]
		var effects: ShipEffects = objects[1]
		ship.state.gear = PilotCommand.GEAR_CRUISE
		ship.last_command = _command(Vector3.ZERO)
		ship.state.velocity = Vector3(0, -3000, -3000)
		ship.state.atmosphere_resistance = 0.6
		effects.update_effects(ship, 1.0 / 60.0)
		var active := effects.active_effects()
		assert_near(active["Atmosphere Entry"]["strength"], 0.8, 1e-6, "flames = EGAnalogue(.6, .3, .8, .5, 1)")
		assert_near(active["Atmosphere Entry2"]["strength"], 1.0, 1e-6, "wind = EGAnalogue(.6, 0, .5, .1, 1)")
		assert_eq(active["Atmosphere Entry"]["material"], "AtmosphereEntry")
		ship.state.atmosphere_resistance = 0.2
		effects.update_effects(ship, 1.0 / 60.0)
		active = effects.active_effects()
		assert_true(not active.has("Atmosphere Entry"), "no flames at or below .3")
		assert_near(active["Atmosphere Entry2"]["strength"], 0.1 + 0.4 * 0.9, 1e-6)
		effects.camera_inside = true
		ship.state.atmosphere_resistance = 0.6
		effects.update_effects(ship, 1.0 / 60.0)
		active = effects.active_effects()
		assert_eq(active["Atmosphere Entry"]["material"], "AtmosphereEntryCockpit")
		assert_eq(active["Atmosphere Entry2"]["material"], "AtmosphereShockwaveCockpit")
		_free(objects))


func test_particle_data_is_rodinas() -> void:
	# Spot checks against EGDataParticles.lua as read by hand.
	var pink: Dictionary = RodinaParticleDefs.MATERIALS["Limnal Pink Air"]["Styles"][0]
	assert_eq(pink["Rate"], 100.0)
	assert_eq(pink["VelocityBase"], Vector3(0, 10000, 0))
	assert_eq(pink["Offset"], Vector3(0, -1000, 0))
	var combat: Dictionary = RodinaParticleDefs.MATERIALS["CombatEngineMain"]["Styles"][0]
	assert_eq(combat["Rate"], 5000.0)
	assert_near(combat["Lifetime"], 0.09, 1e-9)
	assert_eq(combat["Keys"][0]["Color"], Vector3(0, 0.7, 1))
	assert_eq(RodinaParticleDefs.MATERIALS.size(), 16)
