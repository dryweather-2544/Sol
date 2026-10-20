class_name WorkbenchMenu
extends CanvasLayer
## Upgrade screen opened at the cabin workbench. Pauses the game while open.

signal closed

var session: GameSession
var _panel := PanelContainer.new()
var _box := VBoxContainer.new()
var _status := Label.new()


var audio: AudioService

func _init() -> void:
	name = "WorkbenchMenu"
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
		audio.play_sample("rod_menu_open")
	visible = true
	get_tree().paused = true
	_rebuild()


func close() -> void:
	if audio != null:
		audio.play_sample("rod_menu_unhighlight")
	visible = false
	get_tree().paused = false
	closed.emit()


func _rebuild() -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.text = "Workbench - upgrades"
	title.add_theme_font_size_override("font_size", 28)
	_box.add_child(title)
	var stock := Label.new()
	stock.text = "You have: %d scrap, %d data chips" % [session.inventory.count(ItemDefinition.SCRAP), session.inventory.count(ItemDefinition.DATA_CHIP)]
	_box.add_child(stock)
	for upgrade_id in ShipUpgrades.CATALOG:
		var entry: Dictionary = ShipUpgrades.CATALOG[upgrade_id]
		var cost_parts: Array[String] = []
		for item_id in entry["cost"]:
			cost_parts.append("%d %s" % [entry["cost"][item_id], ItemDefinition.display_name(item_id)])
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s - %s  (%s)" % [entry["name"], entry["help"], ", ".join(cost_parts)]
		label.custom_minimum_size = Vector2(640, 0)
		row.add_child(label)
		var button := Button.new()
		button.text = "Installed" if session.ship.upgrades.has(upgrade_id) else "Buy"
		button.disabled = session.ship.upgrades.has(upgrade_id)
		button.pressed.connect(func():
			_status.text = session.buy_upgrade(upgrade_id)
			_rebuild())
		row.add_child(button)
		_box.add_child(row)
	_box.add_child(_status)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	_box.add_child(close_button)
