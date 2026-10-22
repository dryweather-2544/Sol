class_name AirlockMenu
extends CanvasLayer
## The airlock computer (Rodina's EGMenuAirlock): a live pressure bar, the state of both doors and three buttons -
## Open Airlock In, Close Airlock, Open Airlock Out. The doors cycle by themselves (ShipSystems.request_airlock).
## Unlike the other menus it does not pause the game, so the doors and the air keep moving while it is open.

signal closed

var session: GameSession
var audio: AudioService
var _panel := PanelContainer.new()
var _box := VBoxContainer.new()
var _pressure := ProgressBar.new()
var _inner_label := Label.new()
var _outer_label := Label.new()
var _status := Label.new()


func _init() -> void:
	name = "AirlockMenu"
	layer = 40
	visible = false
	_box.add_theme_constant_override("separation", 6)
	_panel.add_child(_box)
	add_child(_panel)
	var title := Label.new()
	title.text = "Airlock"
	title.add_theme_font_size_override("font_size", 28)
	_box.add_child(title)
	var pressure_title := Label.new()
	pressure_title.text = "Air pressure"
	_box.add_child(pressure_title)
	_pressure.min_value = 0.0
	_pressure.max_value = 100.0
	_pressure.custom_minimum_size = Vector2(420, 24)
	_box.add_child(_pressure)
	_box.add_child(_inner_label)
	_box.add_child(_outer_label)
	_box.add_child(_status)
	for entry in [["<- Open Airlock In", &"in"], ["Close Airlock", &"close"], ["Open Airlock Out ->", &"out"]]:
		var button := Button.new()
		button.text = entry[0]
		var goal: StringName = entry[1]
		button.pressed.connect(func(): _command(goal))
		_box.add_child(button)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	_box.add_child(close_button)


func _process(_delta: float) -> void:
	if not visible:
		return
	_panel.position = (get_viewport().get_visible_rect().size - _panel.size) * 0.5
	var systems := session.systems
	_pressure.value = systems.airlock_pressure * 100.0
	_inner_label.text = "Inner door: " + door_state_text(systems.airlock.inner)
	_outer_label.text = "Outer door: " + door_state_text(systems.airlock.outer)
	if systems.airlock_status != "" and _status.text != systems.airlock_status:
		_status.text = systems.airlock_status


func open() -> void:
	if audio != null:
		audio.play_sample("rod_menu_open")
	_status.text = ""
	visible = true


func close() -> void:
	if audio != null:
		audio.play_sample("rod_menu_unhighlight")
	visible = false
	closed.emit()


func _command(goal: StringName) -> void:
	var refused := session.airlock_command(goal)
	_status.text = refused if refused != "" else session.systems.airlock_status


static func door_state_text(door: Portal) -> String:
	if door.open_factor >= 0.99:
		return "OPEN"
	if door.open_factor <= 0.01 and not door.target_open:
		return "CLOSED"
	return "OPENING" if door.target_open else "CLOSING"
