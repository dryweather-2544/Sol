class_name InventoryMenu
extends CanvasLayer
## Inventory screen (Tab): what you carry, with Use buttons. Pauses the game while open.

signal closed

var session: GameSession
var audio: AudioService
var _panel := PanelContainer.new()
var _box := VBoxContainer.new()
var _status := Label.new()


func _init() -> void:
	name = "InventoryMenu"
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
	if audio != null:
		audio.play_sample("rod_inventory_open")
	visible = true
	get_tree().paused = true
	_rebuild()


func close() -> void:
	if audio != null:
		audio.play_sample("rod_inventory_close")
	visible = false
	get_tree().paused = false
	closed.emit()


func _rebuild() -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.text = "Inventory   (%d / %d slots)" % [session.inventory.slots_used(), session.inventory.slot_limit]
	title.add_theme_font_size_override("font_size", 28)
	_box.add_child(title)
	var status_line := Label.new()
	status_line.text = "Ship fuel %d%%   hull %d%%   suit oxygen %d%%   discovered %d   crates opened %d" % [
		session.ship.state.fuel * 100.0, session.ship.state.hull * 100.0, session.suit.oxygen * 100.0, session.discovery_log.count(), session.loot_log.to_array().size()]
	_box.add_child(status_line)
	if session.inventory.item_ids().is_empty():
		var empty := Label.new()
		empty.text = "(nothing yet - search wrecks, beacons and outposts)"
		_box.add_child(empty)
	for item_id in session.inventory.item_ids():
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%dx %s  - %s" % [session.inventory.count(item_id), ItemDefinition.display_name(item_id), ItemDefinition.ITEMS[item_id]["help"]]
		label.custom_minimum_size = Vector2(520, 0)
		row.add_child(label)
		if ItemDefinition.is_usable(item_id):
			var button := Button.new()
			button.text = "Use"
			button.pressed.connect(func():
				if audio != null:
					audio.play_sample("rod_gui_click")
				_status.text = session.use_item(item_id)
				_rebuild())
			row.add_child(button)
		_box.add_child(row)
	_box.add_child(_status)
	var close_button := Button.new()
	close_button.text = "Close (Tab)"
	close_button.pressed.connect(close)
	_box.add_child(close_button)
