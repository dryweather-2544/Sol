class_name DebugOverlay
extends CanvasLayer
const EntryModel = preload("res://src/flight/atmospheric_entry.gd")
## In-flight HUD. Reads state, owns none. The old debug dump is kept behind a compact, legible
## layout: a status card, a power strip, an objective card and a centred interaction prompt.

var ship: Ship
var terrain: PlanetTerrain
var session: GameSession
var poi_manager: PoiManager
var frame_text := ""

var _hud := Control.new()
var _status_panel := PanelContainer.new()
var _status_label := Label.new()
var _power_label := Label.new()
var _objective_panel := PanelContainer.new()
var _objective_label := Label.new()
var _signal_label := Label.new()
var _prompt_panel := PanelContainer.new()
var _prompt_label := Label.new()
var _alert_panel := PanelContainer.new()
var _alert_label := Label.new()
var _help_panel := PanelContainer.new()
var _help_label := Label.new()
var _help_seconds := 0.0
var _reticle: Control
var _entry_overlay: ColorRect
var _entry_material: ShaderMaterial
var _entry_label: Label


func _ready() -> void:
	layer = 10
	add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var reticle_script := load("res://src/ui/flight_reticle.gd")
	_reticle = reticle_script.new()
	_hud.add_child(_reticle)

	_build_entry_overlay()
	_build_status_card()
	_build_objective_card()
	_build_prompt_card()
	_build_alert_card()
	_build_help_card()


func _build_entry_overlay() -> void:
	_entry_overlay = ColorRect.new()
	_entry_overlay.name = "EntryHeatVignette"
	_entry_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_entry_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_entry_material = ShaderMaterial.new()
	_entry_material.shader = load("res://data/shaders/entry_vignette.gdshader")
	_entry_overlay.material = _entry_material
	_entry_overlay.visible = false
	_hud.add_child(_entry_overlay)


func _build_status_card() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	_status_panel.add_child(box)
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.86, 0.94, 1.0))
	box.add_child(_status_label)
	_power_label.add_theme_font_size_override("font_size", 12)
	_power_label.add_theme_color_override("font_color", Color(0.62, 0.82, 0.92))
	box.add_child(_power_label)
	_entry_label = Label.new()
	_entry_label.add_theme_font_size_override("font_size", 13)
	_entry_label.add_theme_color_override("font_color", Color(1.0, 0.62, 0.24))
	box.add_child(_entry_label)
	_panel_style(_status_panel, Color(0.015, 0.03, 0.045, 0.72), Color(0.24, 0.52, 0.68, 0.42))
	_status_panel.position = Vector2(16, 14)
	_hud.add_child(_status_panel)


func _build_objective_card() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	_objective_panel.add_child(box)
	_objective_label.add_theme_font_size_override("font_size", 13)
	_objective_label.add_theme_color_override("font_color", Color(0.66, 1.0, 0.78))
	box.add_child(_objective_label)
	_signal_label.add_theme_font_size_override("font_size", 12)
	_signal_label.add_theme_color_override("font_color", Color(0.78, 0.84, 0.72))
	box.add_child(_signal_label)
	_panel_style(_objective_panel, Color(0.015, 0.03, 0.045, 0.62), Color(0.22, 0.44, 0.34, 0.36))
	_hud.add_child(_objective_panel)


func _build_prompt_card() -> void:
	_prompt_label.add_theme_font_size_override("font_size", 18)
	_prompt_label.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0))
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_panel.add_child(_prompt_label)
	_panel_style(_prompt_panel, Color(0.015, 0.03, 0.045, 0.78), Color(0.35, 0.65, 0.85, 0.55))
	_hud.add_child(_prompt_panel)


func _build_alert_card() -> void:
	_alert_label.add_theme_font_size_override("font_size", 16)
	_alert_label.add_theme_color_override("font_color", Color(1.0, 0.46, 0.30))
	_alert_panel.add_child(_alert_label)
	_panel_style(_alert_panel, Color(0.10, 0.012, 0.01, 0.78), Color(0.8, 0.16, 0.08, 0.8))
	_alert_panel.visible = false
	_hud.add_child(_alert_panel)


func _build_help_card() -> void:
	_help_label.add_theme_font_size_override("font_size", 10)
	_help_label.add_theme_color_override("font_color", Color(0.68, 0.74, 0.78, 0.78))
	_help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_help_panel.add_child(_help_label)
	_panel_style(_help_panel, Color(0.01, 0.02, 0.03, 0.34), Color(0.2, 0.3, 0.38, 0.2))
	_hud.add_child(_help_panel)


func _panel_style(panel: PanelContainer, background: Color, border: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", style)


func _process(delta: float) -> void:
	if ship == null:
		return
	_help_seconds += delta
	_status_label.text = _status_text()
	_power_label.text = _power_text()
	_objective_label.text = "OBJECTIVE  " + (session.progress.current_text() if session != null else "")
	_signal_label.text = _nearest_signal_text() + (("\n" + frame_text) if frame_text != "" else "")
	_prompt_label.text = session.prompt() if session != null else ""
	_prompt_panel.visible = _prompt_label.text.strip_edges() != ""
	var alert := session.alert_text() if session != null else ""
	if alert == "" and ship.state.entry_warning != "":
		alert = ship.state.entry_warning
	_alert_label.text = alert
	_alert_panel.visible = alert != ""
	var heat := clampf(ship.state.entry_heat, 0.0, 1.0)
	_entry_overlay.visible = heat > 0.01
	if _entry_overlay.visible:
		_entry_material.set_shader_parameter("intensity", heat)
	_entry_label.text = _entry_text()
	_entry_label.visible = _entry_label.text != ""
	_help_label.text = _help_text()
	_help_panel.modulate.a = clampf(1.0 - maxf(0.0, _help_seconds - 14.0) / 8.0, 0.0, 1.0)
	var flight_view := session != null and session.mode != GameSession.Mode.OUTSIDE and session.mode != GameSession.Mode.INSIDE
	var screen_velocity := Vector2.ZERO
	if flight_view and ship.planet != null and ship.state.velocity.length() > 0.1:
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			var local_velocity := camera.global_basis.inverse() * ship.state.velocity
			screen_velocity = Vector2(local_velocity.x, -local_velocity.y).normalized() * clampf(local_velocity.length() * 0.20, 0.0, 26.0)
	_reticle.set_state(flight_view, screen_velocity)
	_layout()


func _layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	# Let the containers measure their content before placing the bottom cards.
	_status_panel.reset_size()
	_objective_panel.reset_size()
	_prompt_panel.reset_size()
	_alert_panel.reset_size()
	_help_panel.reset_size()
	_objective_panel.position = Vector2(16, viewport_size.y - _objective_panel.size.y - 18)
	_prompt_panel.position = Vector2(viewport_size.x * 0.5 - _prompt_panel.size.x * 0.5, viewport_size.y - _prompt_panel.size.y - 78)
	_alert_panel.position = Vector2(viewport_size.x * 0.5 - _alert_panel.size.x * 0.5, 74)
	_help_panel.position = Vector2(viewport_size.x - _help_panel.size.x - 16, viewport_size.y - _help_panel.size.y - 16)


func _entry_text() -> String:
	if ship == null or ship.state.entry_density <= 0.001:
		return ""
	var state := ship.state
	var speed_km := state.entry_speed / 1000.0
	return "ENTRY %s   path %+d deg   %.1f km/s\nHEAT %d%%   hull %d%%" % [
		EntryModel.corridor_label(state.entry_corridor), int(round(state.entry_angle_deg)),
		speed_km, int(clampf(state.entry_heat, 0.0, 1.5) * 100.0), int(state.hull * 100.0)]


func _status_text() -> String:
	if session != null and session.mode == GameSession.Mode.OUTSIDE:
		var body := session.exterior_body
		return "SOL // ON FOOT\n%s   %0.1f m/s   %.1f m above ground\nO2 %d%%   health %d%%   jetpack %d%%" % [
			"grounded" if body.grounded else "airborne", body.velocity.length(), body.height_above_ground,
			int(session.suit.oxygen * 100.0), int(session.suit.health * 100.0), int(session.suit.fuel * 100.0)]
	if session != null and session.mode == GameSession.Mode.INSIDE:
		var airlock := session.systems.airlock
		return "SOL // INTERIOR  %s\nship %0.1f m/s   %s   inner %d%% / outer %d%%\nhull %d%%   O2 %d%%   pressure %d%%   air %d%%" % [
			String(session.systems.layout.room_at(session.interior_body.position.x, session.interior_body.position.z)).to_upper(),
			ship.state.speed(), FlightRegime.label(ship.state.regime), int(airlock.inner.open_factor * 100.0),
			int(airlock.outer.open_factor * 100.0), int(ship.state.hull * 100.0), int(session.suit.oxygen * 100.0),
			int(session.systems.airlock_pressure * 100.0), int(session.systems.hazards.oxygen_in(session.player_room()) * 100.0)]
	var state := ship.state
	var source_text := "PARKED" if ship.controller.is_parked() else String(ship.controller.current_source.source_id)
	var altitude_text := "-"
	if ship.planet != null:
		altitude_text = "%.0f m AGL" % state.altitude_above_ground if state.altitude_above_ground < 1.0e5 else "%.0f km AGL" % (state.altitude_above_ground / 1000.0)
	var gear_names := ["DOCK", "COMBAT", "CRUISE"]
	var vertical_speed := state.velocity.dot(ship.planet.up_at(state.position)) if ship.planet != null else 0.0
	var speed_text := ("%.1f km/s" % (state.speed() / 1000.0)) if state.speed() >= 1000.0 else ("%.0f m/s" % state.speed())
	var text := "SOL // AURELIA\n%s   %s   vert %+.1f\nalt %s   gear %s   pilot %s\nhull %d%%   fuel %d%%%s" % [
		FlightRegime.label(state.regime).to_upper(), speed_text, vertical_speed, altitude_text,
		gear_names[state.gear], source_text, int(state.hull * 100.0), int(state.fuel * 100.0),
		"   ENTRY HEATING" if state.entry_heat > 0.05 else ""]
	if state.status_message != "":
		text += "\n" + state.status_message
	return text


func _power_text() -> String:
	if ship.systems == null:
		return ""
	var power := ship.systems.power
	return "PWR  E %d   W %d   L %d   T %d%%   coolant %d%%%s\nENG %d%%   WPN %d%%   RCT %d%%   LIFE %d%%" % [
		power.delivered(ShipPower.Conduit.ENGINES), power.delivered(ShipPower.Conduit.WEAPONS),
		power.delivered(ShipPower.Conduit.LIFE_SUPPORT), int(power.temperature * 100.0), int(power.coolant * 100.0),
		"   REACTOR SHUTDOWN" if power.is_shut_down() else "",
		int(ship.systems.subsystems.value(0) * 100.0), int(ship.systems.subsystems.value(1) * 100.0),
		int(ship.systems.subsystems.value(2) * 100.0), int(ship.systems.subsystems.value(3) * 100.0)]


func _help_text() -> String:
	if session != null and session.mode == GameSession.Mode.OUTSIDE:
		return "WASD move   Shift run   Space jump   mouse look   click/Ctrl fire   walk up ramp to board   Esc menu"
	if session != null and session.mode == GameSession.Mode.INSIDE:
		return "WASD move   Shift run   mouse look   F use panel/seat   Esc menu"
	return "WASD thrust/strafe   Space/C up/down   Q/E roll   mouse pitch/yaw   Shift boost   X brake\n[ ] gear   V cockpit/third-person   F stand up   F5 save   F9 load   Esc menu   %d fps" % Engine.get_frames_per_second()


func _nearest_signal_text() -> String:
	if poi_manager == null or session == null:
		return ""
	var discovered := session.discovery_log.count()
	var nearest := poi_manager.nearest_undiscovered(session.discovery_log)
	if nearest == null:
		return "DISCOVERED %d    no signals in range" % discovered
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
		direction_word = "right"
	elif bearing < -45.0:
		direction_word = "left"
	var distance := to_poi.length()
	var distance_text := "%.0f m" % distance if distance < 1000.0 else "%.1f km" % (distance / 1000.0)
	return "DISCOVERED %d    NEAREST  %s  %s %s" % [discovered, nearest.display_name, distance_text, direction_word]
