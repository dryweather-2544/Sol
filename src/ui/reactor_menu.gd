class_name ReactorMenu
extends CanvasLayer
## The reactor panel in engineering: set how much of the reactor each conduit may draw, vent coolant, restart
## after a shutdown. Every change goes through ShipSystems.request_*(actor_id, ...). Pauses the game while open.

signal closed

var session: GameSession
var _panel := PanelContainer.new()
var _box := VBoxContainer.new()
var _readout := Label.new()
var _status := Label.new()
var _temperature_bar := ProgressBar.new()
var _limit_sliders := {}
var _limit_labels := {}


func _init() -> void:
	name = "ReactorMenu"
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_box.add_theme_constant_override("separation", 6)
	_panel.add_child(_box)
	add_child(_panel)


func _process(_delta: float) -> void:
	if visible:
		_panel.position = (get_viewport().get_visible_rect().size - _panel.size) * 0.5


func open() -> void:
	visible = true
	get_tree().paused = true
	_build()
	_refresh()


func close() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()


func _build() -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	_limit_sliders.clear()
	_limit_labels.clear()
	var title := Label.new()
	title.text = "Reactor"
	title.add_theme_font_size_override("font_size", 28)
	_box.add_child(title)
	_box.add_child(_readout)
	_temperature_bar.custom_minimum_size = Vector2(520, 18)
	_temperature_bar.max_value = 1.0
	_temperature_bar.show_percentage = false
	_box.add_child(_temperature_bar)
	for conduit in [ShipPower.Conduit.ENGINES, ShipPower.Conduit.WEAPONS, ShipPower.Conduit.LIFE_SUPPORT]:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.custom_minimum_size = Vector2(300, 0)
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = session.systems.power.limit(conduit)
		slider.custom_minimum_size = Vector2(220, 24)
		slider.value_changed.connect(func(value: float):
			_status.text = session.systems.request_set_limit(GameSession.ACTOR, conduit, value)
			_refresh())
		row.add_child(slider)
		_box.add_child(row)
		_limit_sliders[conduit] = slider
		_limit_labels[conduit] = label
	var buttons := HBoxContainer.new()
	var vent := Button.new()
	vent.text = "Vent coolant"
	vent.pressed.connect(func():
		_status.text = session.systems.request_vent_coolant(GameSession.ACTOR)
		_refresh())
	buttons.add_child(vent)
	var restart := Button.new()
	restart.text = "Restart reactor"
	restart.pressed.connect(func():
		_status.text = session.systems.request_restart_reactor(GameSession.ACTOR)
		_refresh())
	buttons.add_child(restart)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	buttons.add_child(close_button)
	_box.add_child(buttons)
	_box.add_child(_status)
	_status.text = ""


func _refresh() -> void:
	var power := session.systems.power
	var subsystems := session.systems.subsystems
	_readout.text = "Output %d   Core temperature %d%%   Coolant %d%%%s\nHealth: engines %d%%  weapons %d%%  reactor %d%%  life support %d%%" % [
		power.output(), power.temperature * 100.0, power.coolant * 100.0, "   SHUT DOWN" if power.is_shut_down() else "",
		subsystems.value(0) * 100.0, subsystems.value(1) * 100.0, subsystems.value(2) * 100.0, subsystems.value(3) * 100.0]
	_temperature_bar.value = power.temperature
	for conduit in _limit_labels:
		_limit_labels[conduit].text = "%s  limit %d%%   drawing %d of %d wanted" % [
			ShipPower.Conduit.keys()[conduit].capitalize().replace("_", " "), power.limit(conduit) * 100.0, power.delivered(conduit), power.request(conduit)]
