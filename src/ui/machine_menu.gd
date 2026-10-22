class_name MachineMenu
extends CanvasLayer
## The screens of Rodina's ship machines (Items.ShipStatus / Scanners / FTL_Radio / BatteryArray / LimnalDrive) in one panel:
## a live text readout, plus buttons for the kinds that have actions. Like the airlock menu it does not pause the game,
## so the numbers move while it is open. Kinds are the interact point ids: ops_computer, scanners, ftl_radio, battery_array, limnal_drive.

signal closed

const TITLES := {&"ops_computer": "Operations", &"scanners": "Scanners", &"ftl_radio": "Pilot Wave Radio",
	&"battery_array": "Battery Array", &"limnal_drive": "Limnal Drive"}

var session: GameSession
var audio: AudioService
## Set by the scene. scanner_rows() -> Array of {"id": StringName, "name": String, "distance": String}; select_nav_target(id) sets the target.
var scanner_rows: Callable
var select_nav_target: Callable
var current_nav_name: Callable
var kind := &""
var _panel := PanelContainer.new()
var _box := VBoxContainer.new()
var _title := Label.new()
var _body := Label.new()
var _actions := VBoxContainer.new()
var _status := Label.new()


func _init() -> void:
	name = "MachineMenu"
	layer = 40
	visible = false
	_box.add_theme_constant_override("separation", 6)
	_panel.add_child(_box)
	add_child(_panel)
	_title.add_theme_font_size_override("font_size", 28)
	_box.add_child(_title)
	_body.custom_minimum_size = Vector2(460, 0)
	_box.add_child(_body)
	_box.add_child(_actions)
	_box.add_child(_status)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	_box.add_child(close_button)


func _process(_delta: float) -> void:
	if not visible:
		return
	_body.text = body_text(kind)
	_panel.position = (get_viewport().get_visible_rect().size - _panel.size) * 0.5


func open(machine_kind: StringName) -> void:
	kind = machine_kind
	if audio != null:
		audio.play_sample("rod_menu_open")
	_title.text = String(TITLES.get(kind, "Machine"))
	_status.text = ""
	_build_actions()
	_body.text = body_text(kind)
	visible = true


func close() -> void:
	if audio != null:
		audio.play_sample("rod_menu_unhighlight")
	visible = false
	closed.emit()


func _build_actions() -> void:
	for child in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	match kind:
		&"ops_computer":
			_add_button("EMERGENCY: open all doors", func(): _status.text = set_all_doors(true))
			_add_button("Close all doors", func(): _status.text = set_all_doors(false))
		&"scanners":
			if scanner_rows.is_valid():
				for row in scanner_rows.call():
					var body_id: StringName = row["id"]
					_add_button("%s   %s" % [row["name"], row["distance"]], func():
						select_nav_target.call(body_id)
						_status.text = "Nav target: " + String(row["name"]))
				_add_button("Clear nav target", func():
					select_nav_target.call(&"")
					_status.text = "Nav target cleared")


func _add_button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	_actions.add_child(button)


## Opens or closes every plain door (never the airlock's: those obey the pressure rules). Returns the status line.
func set_all_doors(open_them: bool) -> String:
	var changed := 0
	for portal_id in session.systems.layout.portals:
		var portal: Portal = session.systems.layout.portals[portal_id]
		if portal.kind != Portal.Kind.DOOR or portal.target_open == open_them:
			continue
		if not open_them and session.systems.is_portal_occupied(portal_id):
			continue
		portal.target_open = open_them
		portal.idle_open_seconds = 0.0
		changed += 1
	return "%s %d door%s" % ["Opening" if open_them else "Closing", changed, "" if changed == 1 else "s"]


func body_text(machine_kind: StringName) -> String:
	if session == null:
		return ""
	match machine_kind:
		&"ops_computer": return _ops_text()
		&"scanners": return _scanner_text()
		&"ftl_radio": return _radio_text()
		&"battery_array": return _battery_text()
		&"limnal_drive": return _limnal_text()
	return ""


func _ops_text() -> String:
	var systems := session.systems
	var lines: Array[String] = []
	lines.append("Ship health: %d%%" % roundi(session.ship.state.hull * 100.0))
	lines.append("Fuel: %d%%" % roundi(session.ship.state.fuel * 100.0))
	for id in 4:
		lines.append("%s: %d%%" % [String(ShipSubsystems.label(id)).capitalize(), roundi(systems.subsystems.value(id) * 100.0)])
	lines.append("Reactor: %s, core %d%%" % ["TRIPPED" if systems.power.is_shut_down() else "running", roundi(systems.power.temperature * 100.0)])
	lines.append("")
	for room_id in systems.layout.rooms:
		if not systems.hazards.has_room(room_id):
			continue
		var fire := systems.hazards.fire_in(room_id)
		lines.append("%s   air %d%%   %s" % [String(room_id).replace("_", " ").capitalize(), roundi(systems.hazards.oxygen_in(room_id) * 100.0),
			"FIRE %d%%" % roundi(fire * 100.0) if fire > 0.0 else "no fire"])
	return "\n".join(lines)


func _scanner_text() -> String:
	var target := String(current_nav_name.call()) if current_nav_name.is_valid() else ""
	return "Nav target: " + (target if target != "" else "none") + "\nPick a body to target it (T cycles targets too)."


func _radio_text() -> String:
	var progress := session.progress
	var lines: Array[String] = ["Objective: " + progress.current_text()]
	if progress.beacon_direction != Vector3.ZERO and not progress.is_finished():
		lines.append("A Mayday beacon is pinned on Selene.")
	lines.append("Warp coil: " + ("installed" if progress.warp_installed else "not installed"))
	return "\n".join(lines)


func _battery_text() -> String:
	var power := session.systems.power
	var state := "SUPPLYING life support" if power.on_battery() else ("EMPTY - reactor tripped" if power.is_shut_down() else ("charging" if power.battery < 1.0 else "full, standing by"))
	return "Charge: %d%%\nState: %s\nKeeps life support alive if the reactor trips." % [roundi(power.battery * 100.0), state]


func _limnal_text() -> String:
	var systems := session.systems
	var state := "READY"
	if not session.progress.warp_installed:
		state = "OFFLINE - no Warp coil installed"
	elif session.ship.state.fuel <= 0.0:
		state = "NO FUEL"
	elif systems.power.is_shut_down():
		state = "NO POWER - reactor tripped"
	return "Status: %s\nFuel: %d%%\nEngines: %d%%\nSpeed factor: %.1f%%" % [state, roundi(session.ship.state.fuel * 100.0),
		roundi(systems.subsystems.value(ShipSubsystems.Id.ENGINES) * 100.0), session.progress.warp_speed_factor() * 100.0]
