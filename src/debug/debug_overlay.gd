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


func _process(_delta: float) -> void:
	if ship == null:
		return
	_prompt_label.text = session.prompt() if session != null else ""
	_objective_label.text = "Objective: " + session.progress.current_text() if session != null else ""
	_signal_label.text = _nearest_signal_text() + ("\n" + frame_text if frame_text != "" else "")
	_prompt_label.position.x = get_viewport().get_visible_rect().size.x * 0.5 - _prompt_label.size.x * 0.5
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
		_label.text += "\nhull %d%%   O2 %d%%   airlock pressure %d%%" % [ship.state.hull * 100.0, session.suit.oxygen * 100.0, session.systems.airlock_pressure * 100.0]
		return
	var state := ship.state
	var source_text := "PARKED" if ship.controller.is_parked() else String(ship.controller.current_source.source_id)
	var vertical_speed := 0.0
	var altitude_text := "-"
	if ship.planet != null:
		vertical_speed = state.velocity.dot(ship.planet.up_at(state.position))
		altitude_text = "%.0f m AGL" % state.altitude_above_ground if state.altitude_above_ground < 1.0e5 else "%.0f km AGL" % (state.altitude_above_ground / 1000.0)
	var gear_names := ["DOCK", "COMBAT", "CRUISE"]
	_label.text = "fps %d   chunks %d\nspeed %.1f m/s   vertical %.1f m/s\n%s   %s\ngear %s   pilot: %s\n%s\n\nWASD thrust/strafe  Space/C up/down  Q/E roll\nmouse or arrows pitch/yaw  Shift boost  X brake\n[ ] gear (cruise above 2 km)  V cockpit/third-person view  F stand up  F5 save  F9 load  Esc menu" % [
		Engine.get_frames_per_second(), terrain.displayed_chunk_count() if terrain != null else 0,
		state.speed(), vertical_speed, altitude_text, FlightRegime.label(state.regime),
		gear_names[state.gear], source_text, state.status_message]
	_label.text += "\nfuel %d%%   hull %d%%%s   Tab inventory" % [state.fuel * 100.0, state.hull * 100.0, "   REENTRY HEAT" if ShipDamage.heating_rate(state.speed(), state.atmosphere_ratio) > 0.0 else ""]


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
