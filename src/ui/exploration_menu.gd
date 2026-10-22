class_name ExplorationMenu
extends CanvasLayer
## The exploration log (J): every site discovered, what kind it is, where, whether it is investigated and what was found,
## plus how many scanner signals are still unidentified. Pauses the game while open, like the inventory.

signal closed

var session: GameSession
var audio: AudioService
var _panel := PanelContainer.new()
var _box := VBoxContainer.new()


func _init() -> void:
	name = "ExplorationMenu"
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
	rebuild()


func close() -> void:
	if audio != null:
		audio.play_sample("rod_menu_unhighlight")
	visible = false
	get_tree().paused = false
	closed.emit()


func rebuild() -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.text = "Exploration log"
	title.add_theme_font_size_override("font_size", 28)
	_box.add_child(title)
	_add_line(ExplorationLog.summary(session.discovery_log, session.loot_log))
	var rows := ExplorationLog.rows(session.discovery_log, session.loot_log)
	if rows.is_empty():
		_add_line("(nothing discovered yet - press N to scan, then walk to a signal)")
	for row in rows:
		_add_line("%s  -  %s  -  %s" % [row["name"], row["type_name"], row["status"]])
		if row["location"] != "":
			_add_line("    " + row["location"])
		if row["detail"] != "":
			_add_line("    " + row["detail"])
		if row["reward"] != "":
			_add_line("    Recovered: " + row["reward"])
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	_box.add_child(close_button)


func _add_line(text: String) -> void:
	var label := Label.new()
	label.text = text
	_box.add_child(label)
