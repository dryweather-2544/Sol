class_name DebugOverlay
extends CanvasLayer
## Top-left text: fps, speed, position, gear, who is flying. Reads state, owns none.

var ship: Ship
var terrain: PlanetTerrain
var session: GameSession
var poi_manager: PoiManager
var frame_text := ""
var _label := Label.new()
var _prompt_label := Label.new()
var _signal_label := Label.new()
var _objective_label := Label.new()
var _alert_label := Label.new()
var _mode_label := Label.new()
var _telemetry_label := Label.new()
var _reticle := FlightReticle.new()
var _gear_hud := GearHud.new() ## Rodina's gear tiles and gear banner (the compact HUD, seated flight)
var _sol_looks := {} # label -> its sol colour and size (restyle)
var _weapon_label := Label.new()


func _ready() -> void:
	_label.position = Vector2(12, 8)
	_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	_prompt_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.position.y -= 120
	_prompt_label.add_theme_font_size_override("font_size", 26)
	_prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt_label.add_theme_constant_override("outline_size", 6)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_prompt_label)
	_signal_label.position = Vector2(12, 560)
	_signal_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_signal_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_signal_label.add_theme_constant_override("outline_size", 4)
	add_child(_signal_label)
	_objective_label.position = Vector2(12, 520)
	_objective_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_objective_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_objective_label.add_theme_constant_override("outline_size", 4)
	add_child(_objective_label)
	_alert_label.position = Vector2(12, 480)
	_alert_label.add_theme_font_size_override("font_size", 24)
	_alert_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
	_alert_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_alert_label.add_theme_constant_override("outline_size", 4)
	var alert_style := StyleBoxFlat.new()
	alert_style.bg_color = Color(0.20, 0.035, 0.025, 0.82)
	alert_style.border_color = Color(0.95, 0.25, 0.12, 0.95)
	alert_style.set_border_width_all(1)
	alert_style.content_margin_left = 14
	alert_style.content_margin_right = 14
	alert_style.content_margin_top = 2
	alert_style.content_margin_bottom = 2
	_alert_label.add_theme_stylebox_override("normal", alert_style)
	_alert_label.visible = false
	add_child(_alert_label)
	# Compact Rodina flight HUD; the developer overlay remains for Sol and paused states.
	_mode_label.visible = false
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_label.add_theme_font_size_override("font_size", 18)
	_mode_label.add_theme_color_override("font_color", Color(0.65, 0.9, 1.0))
	_mode_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_mode_label.add_theme_constant_override("outline_size", 3)
	var mode_style := StyleBoxFlat.new()
	mode_style.bg_color = Color(0.025, 0.10, 0.15, 0.72)
	mode_style.border_color = Color(0.25, 0.75, 0.95, 0.9)
	mode_style.border_width_left = 1
	mode_style.border_width_right = 1
	mode_style.border_width_top = 1
	mode_style.border_width_bottom = 1
	mode_style.content_margin_left = 18
	mode_style.content_margin_right = 18
	mode_style.content_margin_top = 3
	mode_style.content_margin_bottom = 3
	_mode_label.add_theme_stylebox_override("normal", mode_style)
	add_child(_mode_label)
	_telemetry_label.visible = false
	_telemetry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_telemetry_label.add_theme_font_size_override("font_size", 15)
	_telemetry_label.add_theme_color_override("font_color", Color(0.55, 0.86, 0.96))
	_telemetry_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_telemetry_label.add_theme_constant_override("outline_size", 3)
	add_child(_telemetry_label)
	_reticle.visible = false
	add_child(_reticle)
	_gear_hud.visible = false
	add_child(_gear_hud)
	_weapon_label.visible = false
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon_label.add_theme_font_size_override("font_size", 14)
	_weapon_label.add_theme_color_override("font_color", Color(0.55, 0.86, 0.96))
	_weapon_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_weapon_label.add_theme_constant_override("outline_size", 3)
	var weapon_style := StyleBoxFlat.new()
	weapon_style.bg_color = Color(0.025, 0.10, 0.15, 0.66)
	weapon_style.border_color = Color(0.25, 0.75, 0.95, 0.85)
	weapon_style.set_border_width_all(1)
	weapon_style.content_margin_left = 10
	weapon_style.content_margin_right = 10
	weapon_style.content_margin_top = 3
	weapon_style.content_margin_bottom = 3
	_weapon_label.add_theme_stylebox_override("normal", weapon_style)
	add_child(_weapon_label)
	_sol_looks = {}
	for label in [_label, _prompt_label, _signal_label, _objective_label, _alert_label, _mode_label, _telemetry_label]:
		_sol_looks[label] = {"color": label.get_theme_color("font_color"), "size": label.get_theme_font_size("font_size")}
	restyle()


## Rodina's HUD fonts in the rodina style (VisualStyle.hud_font: Orbitron info and prompts, Audiowide warnings), the
## labels' own look in sol. Called once built and again on a style switch.
func restyle() -> void:
	var roles := {_label: &"info", _prompt_label: &"notification", _signal_label: &"info", _objective_label: &"info", _alert_label: &"warning", _mode_label: &"info", _telemetry_label: &"info"}
	for label: Label in roles:
		var spec := VisualStyle.hud_font(roles[label])
		if spec.is_empty():
			label.remove_theme_font_override("font")
			label.add_theme_color_override("font_color", _sol_looks[label]["color"])
			label.add_theme_font_size_override("font_size", _sol_looks[label]["size"])
			continue
		if spec["font"] != null:
			label.add_theme_font_override("font", spec["font"])
		label.add_theme_font_size_override("font_size", spec["size"])
		# The info lines keep their own tints (green status, gold signals) so they stay distinguishable; prompts and
		# warnings take Rodina's colours.
		if roles[label] != &"info":
			label.add_theme_color_override("font_color", spec["color"])


func _process(delta: float) -> void:
	if ship == null:
		return
	_prompt_label.text = session.prompt() if session != null else ""
	var alert := session.alert_text() if session != null else ""
	_alert_label.text = alert
	_alert_label.visible = alert != ""
	if alert != "":
		_alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_alert_label.add_theme_font_size_override("font_size", 15)
		_alert_label.position = Vector2(get_viewport().get_visible_rect().size.x * 0.5 - _alert_label.size.x * 0.5, 54.0)
	_objective_label.text = "Objective: " + session.progress.current_text() if session != null else ""
	_signal_label.text = _nearest_signal_text() + ("\n" + frame_text if frame_text != "" else "")
	_prompt_label.position.x = get_viewport().get_visible_rect().size.x * 0.5 - _prompt_label.size.x * 0.5
	if _use_rodina_hud():
		_update_rodina_hud(delta)
		return
	_set_debug_hud_visible(true)
	if session != null and session.mode == GameSession.Mode.OUTSIDE:
		var body := session.exterior_body
		_label.text = "fps %d   chunks %d\nOUTSIDE   speed %.1f m/s   %s\nheight above ground %.2f m%s\nWASD move  Shift run  Space jump  mouse look  click/Ctrl fire\nwalk up the ramp to board  Esc menu" % [
			Engine.get_frames_per_second(), terrain.displayed_chunk_count() if terrain != null else 0,
			body.velocity.length(), "grounded" if body.grounded else "airborne", body.height_above_ground,
			"   (slope too steep)" if body.blocked_by_slope else ""]
		_label.text += "\nO2 %d%%   jetpack %d%%   health %d%%   (hold Space airborne to burn)" % [session.suit.oxygen * 100.0, session.suit.fuel * 100.0, session.suit.health * 100.0]
		return
	if session != null and session.mode == GameSession.Mode.INSIDE:
		var airlock := session.systems.airlock
		_label.text = "fps %d   chunks %d\nINSIDE the ship (%s)   ship speed %.1f m/s   %s\ninner door %.0f%%   outer door %.0f%%   walkway %s\nWASD move  Shift run  mouse look  F use panel / seat\nEsc menu" % [
			Engine.get_frames_per_second(), terrain.displayed_chunk_count() if terrain != null else 0,
			session.systems.layout.room_at(session.interior_body.position.x, session.interior_body.position.z), ship.state.speed(),
			FlightRegime.label(ship.state.regime), airlock.inner.open_factor * 100.0, airlock.outer.open_factor * 100.0,
			WalkwayController.State.keys()[session.systems.walkway.state]]
		_label.text += "\nhull %d%%   O2 %d%%   airlock pressure %d%%   room air %d%%" % [ship.state.hull * 100.0, session.suit.oxygen * 100.0, session.systems.airlock_pressure * 100.0, session.systems.hazards.oxygen_in(session.player_room()) * 100.0]
		_label.text += _power_text()
		return
	var state := ship.state
	var source_text := "PARKED" if ship.controller.is_parked() else String(ship.controller.current_source.source_id)
	var vertical_speed := 0.0
	var altitude_text := "-"
	if ship.planet != null:
		vertical_speed = state.velocity.dot(ship.planet.up_at(state.position))
		altitude_text = "%.0f m AGL" % state.altitude_above_ground if state.altitude_above_ground < 1.0e5 else "%.0f km AGL" % (state.altitude_above_ground / 1000.0)
	var gear_names := ["PRECISION", "COMBAT", "CRUISE", "WARP"]
	var gear_text: String = gear_names[state.gear]
	var top_speed: float = ship.tuning.gear_max_speed[state.gear] * (ship.tuning.boost_multiplier if ship.last_command.boost else 1.0)
	if state.gear == PilotCommand.GEAR_WARP and ship.environment.cruise_speed_limit < INF:
		top_speed = minf(top_speed, ship.environment.cruise_speed_limit * ship.tuning.warp_speed_multiplier)
	if state.gear == PilotCommand.GEAR_CRUISE:
		top_speed = minf(top_speed, ship.environment.cruise_speed_limit)
	gear_text += " (up to %s)" % ("%.0f m/s" % top_speed if top_speed < 1.0e4 else "%.0f km/s" % (top_speed / 1000.0))
	if state.selected_gear != state.gear:
		gear_text += ", %s selected: %s" % [gear_names[state.selected_gear], "no fuel" if state.fuel <= 0.0 else "not available here"]
	elif state.gear < PilotCommand.GEAR_CRUISE and state.altitude_above_ground > 20000.0:
		gear_text += "   - press ] for %s" % ("CRUISE" if state.gear == PilotCommand.GEAR_COMBAT else "COMBAT, then ] again for CRUISE")
	_label.text = "fps %d   chunks %d\nspeed %.1f m/s   vertical %.1f m/s\n%s   %s\ngear %s   pilot: %s\n%s\n\nWASD thrust/strafe  Space/C up/down  Q/E roll\nmouse or arrows pitch/yaw  Shift boost  X brake\n[ ] gear: PRECISION (hovers, stops by itself) / COMBAT / CRUISE / WARP (space, drive installed)   V view  F stand up  F5 save  F9 load  Esc menu" % [
		Engine.get_frames_per_second(), terrain.displayed_chunk_count() if terrain != null else 0,
		state.speed(), vertical_speed, altitude_text, FlightRegime.label(state.regime),
		gear_text, source_text, state.status_message]
	_label.text += "\nfuel %d%%   hull %d%%%s   Tab inventory" % [state.fuel * 100.0, state.hull * 100.0, "   STEEP REENTRY" if ShipDamage.entry_damage_rate(state.atmosphere_resistance) > 0.0 else ""]
	_label.text += _power_text()


func _use_rodina_hud() -> bool:
	return VisualStyle.is_rodina() and session != null and not get_tree().paused


func _set_debug_hud_visible(visible: bool) -> void:
	_label.visible = visible
	_signal_label.visible = visible
	_mode_label.visible = false
	_telemetry_label.visible = false
	_reticle.visible = false
	_gear_hud.visible = false
	_prompt_label.add_theme_font_size_override("font_size", 26)
	_prompt_label.add_theme_constant_override("outline_size", 6)
	_prompt_label.add_theme_color_override("font_color", Color.WHITE)


func _update_rodina_hud(delta: float) -> void:
	_label.visible = false
	_signal_label.visible = false
	_mode_label.visible = true
	_telemetry_label.visible = true
	var viewport := get_viewport().get_visible_rect().size
	_reticle.visible = true
	_reticle.position = viewport * 0.5 - _reticle.size * 0.5
	var mode := session.mode
	var seated := mode == GameSession.Mode.SEATED or mode == GameSession.Mode.SITTING
	_reticle.visible = session.gunner_station or not seated # no crosshair at the helm: the gun is on the gunner station
	if seated:
		var state := ship.state
		# Rodina shows no standing mode tab in flight: the gear tiles (top right) and a fading gear banner replace it.
		_mode_label.text = ""
		_gear_hud.size = viewport
		_gear_hud.position = Vector2.ZERO
		var hud_font := VisualStyle.hud_font(&"notification")
		if not hud_font.is_empty() and hud_font["font"] != null:
			_gear_hud.font = hud_font["font"]
		_gear_hud.apply(state.gear, state.shift_pending, delta)
		_gear_hud.visible = true
		_telemetry_label.text = "HULL %d%%    FUEL %d%%    SPEED %s" % [
			roundi(state.hull * 100.0), roundi(state.fuel * 100.0),
			("%.0f m/s" % state.speed()) if state.speed() < 10000.0 else ("%.1f km/s" % (state.speed() / 1000.0))]
	else:
		var suit := session.suit
		_reticle.visible = false
		_reticle.target_positions = PackedVector2Array()
		_gear_hud.visible = false
		_mode_label.text = "ON FOOT" if mode == GameSession.Mode.OUTSIDE else "INSIDE SHIP"
		_telemetry_label.text = "O2 %d%%    JETPACK %d%%    HEALTH %d%%" % [
			roundi(suit.oxygen * 100.0), roundi(suit.fuel * 100.0), roundi(suit.health * 100.0)]
	_mode_label.visible = not seated
	_mode_label.position = Vector2(viewport.x * 0.5 - _mode_label.size.x * 0.5, 12.0)
	_telemetry_label.position = Vector2(viewport.x * 0.5 - _telemetry_label.size.x * 0.5, viewport.y - 38.0)
	_objective_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.9))
	_objective_label.add_theme_font_size_override("font_size", 14)
	_objective_label.position = Vector2(14, viewport.y - 64.0)
	_prompt_label.add_theme_font_size_override("font_size", 18)
	_prompt_label.add_theme_constant_override("outline_size", 4)
	_prompt_label.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0))
	_prompt_label.position.y = viewport.y - 120.0
	if seated:
		_update_target_brackets()
	else:
		_reticle.target_positions = PackedVector2Array()
		_reticle.queue_redraw()
	if _alert_label.text != "":
		_alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_alert_label.add_theme_font_size_override("font_size", 15)
		_alert_label.position = Vector2(viewport.x * 0.5 - _alert_label.size.x * 0.5, 54.0)


## Project living hostile targets through the active camera so the reticle can draw corner brackets.
func _update_target_brackets() -> void:
	var camera := get_viewport().get_camera_3d()
	_reticle.target_positions = PackedVector2Array()
	if camera == null or session == null:
		return
	for target in session.enemy_targets:
		if target == null or not target.is_alive() or target.team_id() == ship.team_id:
			continue
		var target_world: WorldPos = target.combat_position()
		if target_world == null:
			continue
		var local: Vector3 = target_world.to_local_vector3(ship.render_origin)
		var world: Vector3 = ship.to_global(local)
		if camera.is_position_behind(world):
			continue
		_reticle.target_positions.append(camera.unproject_position(world))
	_reticle.queue_redraw()


func _power_text() -> String:
	if ship.systems == null:
		return ""

	var power := ship.systems.power
	var crew_text := ""
	if session != null:
		for person in session.crew.members:
			var goal: int = session.crew_brain.goals.get(person.id, CrewBrain.Goal.IDLE)
			crew_text += "   %s (%s): %s" % [String(person.id).capitalize(), person.role, CrewBrain.goal_name(goal)]
	return ("\nCREW" + crew_text if crew_text != "" else "") + "\nPWR E %d  W %d  L %d   T %d%%   coolant %d%%%s" % [
		power.delivered(ShipPower.Conduit.ENGINES), power.delivered(ShipPower.Conduit.WEAPONS),
		power.delivered(ShipPower.Conduit.LIFE_SUPPORT), power.temperature * 100.0, power.coolant * 100.0,
		"   REACTOR SHUTDOWN" if power.is_shut_down() else ""] + "\nENG %d%%  WPN %d%%  RCT %d%%  LIFE %d%%" % [
		ship.systems.subsystems.value(0) * 100.0, ship.systems.subsystems.value(1) * 100.0,
		ship.systems.subsystems.value(2) * 100.0, ship.systems.subsystems.value(3) * 100.0]


func _nearest_signal_text() -> String:
	if poi_manager == null or session == null:
		return ""
	var discovered := session.discovery_log.count()
	var nearest := poi_manager.nearest_undiscovered(session.discovery_log)
	if nearest == null:
		return "Discovered %d    (no signals in range)" % discovered
	var viewer_position := session.player_world_position()
	var to_poi := nearest.position.vector_from(viewer_position)
	var up := session.planet.up_at(viewer_position)
	var forward := session.forward_vector()
	forward = (forward - up * forward.dot(up)).normalized()
	var flat := (to_poi - up * to_poi.dot(up))
	var right := forward.cross(up)
	var bearing := rad_to_deg(atan2(flat.dot(right), flat.dot(forward)))
	var direction_word := "ahead"
	if absf(bearing) > 135.0:
		direction_word = "behind"
	elif bearing > 45.0:
		direction_word = "to the right"
	elif bearing < -45.0:
		direction_word = "to the left"
	var distance := to_poi.length()
	var distance_text := "%.0f m" % distance if distance < 1000.0 else "%.1f km" % (distance / 1000.0)
	return "Discovered %d    Nearest signal: %s, %s %s" % [discovered, nearest.display_name, distance_text, direction_word]
