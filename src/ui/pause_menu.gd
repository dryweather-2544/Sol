class_name PauseMenu
extends CanvasLayer
## Title screen and pause menu in one: the same buttons, the title screen just adds the game name
## and a "New game" that waits for the terrain to load. Pauses the tree while visible.

signal resume_requested
signal save_requested
signal load_requested
signal continue_requested
signal quit_requested

enum Page { TITLE, PAUSE, SETTINGS }

var page := Page.TITLE
## Set by the scene: false while the first terrain is still loading.
var world_ready := false
var autosave_exists := false

var _panel := PanelContainer.new()
var _box := VBoxContainer.new()
var _return_page := Page.TITLE
var _status := Label.new()


func _init() -> void:
	name = "PauseMenu"
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_box.add_theme_constant_override("separation", 10)
	_panel.add_child(_box)
	add_child(_panel)


func _ready() -> void:
	show_page(Page.TITLE)


func _process(_delta: float) -> void:
	if visible and page == Page.TITLE:
		for child in _box.get_children():
			if child is Button and (child as Button).text.begins_with("New game"):
				(child as Button).disabled = not world_ready
				(child as Button).text = "New game" if world_ready else "New game (loading terrain...)"
			if child is Button and (child as Button).text == "Continue":
				(child as Button).disabled = not (world_ready and autosave_exists)
	_panel.position = (get_viewport().get_visible_rect().size - _panel.size) * 0.5


## Close without emitting anything (used by automation tools).
func dismiss() -> void:
	visible = false
	get_tree().paused = false


func open_pause() -> void:
	show_page(Page.PAUSE)


func show_page(new_page: int) -> void:
	page = new_page
	visible = true
	get_tree().paused = true
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	match page:
		Page.TITLE:
			_add_title("SOL")
			_add_button("New game", func(): _close(resume_requested))
			_add_button("Continue", func(): _close(continue_requested))
			_add_button("Settings", func(): _open_settings(Page.TITLE))
			_add_button("Quit", func(): quit_requested.emit())
		Page.PAUSE:
			_add_title("Paused")
			_add_button("Resume", func(): _close(resume_requested))
			_add_button("Save (quicksave)", func(): save_requested.emit())
			_add_button("Load (quicksave)", func(): _close(load_requested))
			_add_button("Settings", func(): _open_settings(Page.PAUSE))
			_add_button("Quit", func(): quit_requested.emit())
		Page.SETTINGS:
			_build_settings()
	_box.add_child(_status)


func _close(signal_to_emit: Signal) -> void:
	visible = false
	get_tree().paused = false
	signal_to_emit.emit()


func _open_settings(from_page: int) -> void:
	_return_page = from_page
	show_page(Page.SETTINGS)


func _build_settings() -> void:
	var settings := GameSettings.instance()
	_add_title("Settings")
	_add_slider("Mouse sensitivity", settings.mouse_sensitivity, 0.2, 3.0, func(value): settings.mouse_sensitivity = value)
	_add_slider("Field of view", settings.field_of_view, 50.0, 110.0, func(value): settings.field_of_view = value)
	_add_slider("Master volume", settings.master_volume, 0.0, 1.0, func(value): settings.master_volume = value)
	_add_slider("Effects volume", settings.sfx_volume, 0.0, 1.0, func(value): settings.sfx_volume = value)
	_add_slider("Ambience volume", settings.ambience_volume, 0.0, 1.0, func(value): settings.ambience_volume = value)
	var invert := CheckBox.new()
	invert.text = "Invert pitch (mouse back = nose up)"
	invert.button_pressed = settings.invert_pitch
	invert.toggled.connect(func(pressed): settings.invert_pitch = pressed)
	_box.add_child(invert)
	_add_button("Back", func():
		var error := settings.save_to_file()
		_status.text = error
		show_page(_return_page))


func _add_title(text: String) -> void:
	var title := Label.new()
	title.text = text
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(title)


func _add_button(text: String, on_pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 40)
	button.pressed.connect(on_pressed)
	_box.add_child(button)


func _add_slider(label_text: String, value: float, minimum: float, maximum: float, on_changed: Callable) -> void:
	var label := Label.new()
	label.text = label_text
	_box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = (maximum - minimum) / 100.0
	slider.value = value
	slider.custom_minimum_size = Vector2(320, 24)
	slider.value_changed.connect(on_changed)
	_box.add_child(slider)
