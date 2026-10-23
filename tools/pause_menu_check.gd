extends SceneTree
## Real-scene check of the title / pause / settings menus (needs a display): drives the real buttons and the real Escape key
## through the viewport and reports what actually happened. Errors from the engine land in the process log: grep it for ERROR.
##   godot --path . -s res://tools/pause_menu_check.gd -- out_prefix
var _main: Node
var _frame := 0
var _step := 0
var _wait := 0
var _results := []
var _prefix := "pause"


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	if OS.get_cmdline_user_args().size() > 0:
		_prefix = OS.get_cmdline_user_args()[0]


func _note(label: String, ok: bool, detail: String = "") -> void:
	_results.append("%s  %s %s" % ["PASS" if ok else "FAIL", label, detail])


func _buttons() -> Array[String]:
	var names: Array[String] = []
	for child in _main.menu._box.get_children():
		if child is Button:
			names.append((child as Button).text)
	return names


func _press(button_text: String) -> bool:
	for child in _main.menu._box.get_children():
		if child is Button and (child as Button).text.begins_with(button_text) and not (child as Button).disabled:
			(child as Button).pressed.emit()
			return true
	return false


func _escape() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_ESCAPE
		event.keycode = KEY_ESCAPE
		event.pressed = pressed
		Input.parse_input_event(event)


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_prefix, name])


func _process(_delta: float) -> bool:
	_frame += 1
	if _wait > 0:
		_wait -= 1
		return false
	var menu: PauseMenu = _main.menu
	match _step:
		0: # title page, world still loading
			if _results.is_empty():
				_note("title page is showing and the game is paused", menu.visible and paused, "buttons %s" % str(_buttons()))
			if menu.world_ready:
				_step = 1
		1:
			_shot("title")
			_note("New game button enabled once the terrain is ready", _press("New game"))
			_step = 2
			_wait = 5
		2:
			_note("New game closes the menu and unpauses", not menu.visible and not paused)
			_step = 3
			_wait = 120
		3: # nothing should open the menu by itself
			_note("menu stayed closed for 2 s of play", not menu.visible)
			_escape()
			_step = 4
			_wait = 5
		4:
			_note("Escape opens the pause page and pauses", menu.visible and paused and menu.page == PauseMenu.Page.PAUSE, "buttons %s" % str(_buttons()))
			_shot("pause")
			_escape()
			_step = 5
			_wait = 5
		5:
			_note("Escape again while open leaves it open (Resume is the way out)", menu.visible and paused)
			_note("Settings opens", _press("Settings"))
			_step = 6
			_wait = 5
		6:
			_note("settings page is showing", menu.page == PauseMenu.Page.SETTINGS and menu.visible)
			_shot("settings")
			var sliders: Array = _main.menu._box.find_children("*", "HSlider", true, false)
			_note("settings has sliders", sliders.size() >= 5, "%d sliders" % sliders.size())
			_note("Back works", _press("Back"))
			_step = 7
			_wait = 5
		7:
			_note("Back returns to the pause page with its buttons", menu.page == PauseMenu.Page.PAUSE and _buttons().size() == 6, "buttons %s" % str(_buttons()))
			_note("Resume works", _press("Resume"))
			_step = 8
			_wait = 5
		8:
			_note("Resume closes the menu and unpauses", not menu.visible and not paused)
			_escape()
			_step = 9
			_wait = 5
		9:
			_note("second open (after a close) works", menu.visible and paused and _buttons().size() == 6, "buttons %s" % str(_buttons()))
			_note("Save works", _press("Save"))
			_step = 10
			_wait = 5
		10:
			_note("Load works and closes the menu", _press("Load"))
			_step = 11
			_wait = 10
		11:
			_note("after Load the game is running", not menu.visible and not paused)
			print("--- pause menu check ---")
			for line in _results:
				print(line)
			quit()
	return false
