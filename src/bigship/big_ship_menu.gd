extends CanvasLayer
## The big-ship hangar: five ships in a list, a turntable of the chosen hull, its numbers, and a "Board" button that opens the walkable interior
## (BigShipExplorer). Reached from the title and pause menus. Pauses the game while open (the caller's menu is already pausing it).
## `visible` is true while either this list or the walkable view is up.

const Catalog := preload("res://src/bigship/big_ship_catalog.gd")
const Plan := preload("res://src/bigship/big_ship_plan.gd")
const Hull := preload("res://src/bigship/big_ship_hull.gd")
const Explorer := preload("res://src/bigship/big_ship_explorer.gd")

signal closed
## The player took the helm of a big ship (from the walkable view): everything here is put away and the scene flies it.
signal fly_requested(ship_def)

var audio: AudioService

var _panel := PanelContainer.new()
var _list := ItemList.new()
var _stats := Label.new()
var _credit := Label.new()
var _status := Label.new()
var _preview_container := SubViewportContainer.new()
var _viewport := SubViewport.new()
var _camera := Camera3D.new()
var _pivot := Node3D.new()
var _board_button := Button.new()
var _explorer: Explorer
var _defs: Array = []
var _plans := {}
var _selected := -1
var _serial := 0


func _init() -> void:
	name = "BigShipMenu"
	layer = 41
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_panel.add_child(root)
	add_child(_panel)
	var title := Label.new()
	title.text = "Big ships"
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	root.add_child(row)
	_list.custom_minimum_size = Vector2(240, 340)
	_list.item_selected.connect(_select)
	row.add_child(_list)
	var right := VBoxContainer.new()
	row.add_child(right)
	_preview_container.custom_minimum_size = Vector2(520, 300)
	_preview_container.stretch = true
	_viewport.size = Vector2i(520, 300)
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_preview_container.add_child(_viewport)
	right.add_child(_preview_container)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.03, 0.04, 0.07)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.6, 0.7)
	environment.ambient_light_energy = 0.8
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-35, 40, 0)
	key_light.light_energy = 1.6
	_viewport.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(20, -140, 0)
	fill_light.light_energy = 0.6
	_viewport.add_child(fill_light)
	_camera.current = true
	_viewport.add_child(_camera)
	_viewport.add_child(_pivot)
	_stats.custom_minimum_size = Vector2(520, 110)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_stats)
	_credit.custom_minimum_size = Vector2(520, 40)
	_credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_credit.add_theme_font_size_override("font_size", 11)
	_credit.modulate = Color(1, 1, 1, 0.6)
	right.add_child(_credit)
	right.add_child(_status)
	var buttons := HBoxContainer.new()
	root.add_child(buttons)
	_board_button.text = "Board the ship"
	_board_button.pressed.connect(_on_board)
	buttons.add_child(_board_button)
	var close_button := Button.new()
	close_button.text = "Close (Esc)"
	close_button.pressed.connect(close)
	buttons.add_child(close_button)
	_explorer = Explorer.new()
	_explorer.closed.connect(_on_explorer_closed)
	_explorer.fly_requested.connect(_on_fly)
	add_child(_explorer)


func _process(delta: float) -> void:
	if not _panel.visible:
		return
	_panel.position = (get_viewport().get_visible_rect().size - _panel.size) * 0.5
	_pivot.rotation.y += delta * 0.5


func _input(event: InputEvent) -> void:
	if not visible or not _panel.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_ESCAPE or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		close()


## Tells the menu where the real world is and where the ship's interior should stand in it, so the windows show what is really out there.
func set_outside(world: World3D, anchor: Transform3D) -> void:
	_explorer.outside_world = world
	_explorer.outside_anchor = anchor


func open() -> void:
	_defs = Catalog.all()
	_list.clear()
	for def in _defs:
		_list.add_item("%s  (%s)" % [def.display_name, def.ship_class])
	_panel.visible = true
	visible = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_play("rod_inventory_open")
	_list.select(0)
	_select(0)


func close() -> void:
	if not visible:
		return
	_play("rod_inventory_close")
	_serial += 1
	visible = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for child in _pivot.get_children():
		_pivot.remove_child(child)
		child.queue_free()
	closed.emit()


func _on_board() -> void:
	if _selected < 0:
		return
	_play("rod_gui_click")
	var def = _defs[_selected]
	_panel.visible = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if not _explorer.open(def):
		_panel.visible = true
		_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		_status.text = "This ship's interior could not be built."


func _on_fly(ship_def) -> void:
	visible = false # first, so the explorer's own closed signal below changes nothing here
	_serial += 1
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for child in _pivot.get_children():
		_pivot.remove_child(child)
		child.queue_free()
	_explorer.close()
	fly_requested.emit(ship_def)


func _on_explorer_closed() -> void:
	if not visible:
		return
	_panel.visible = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status.text = ""


func _select(index: int) -> void:
	_selected = index
	_serial += 1
	var serial := _serial
	var def = _defs[index]
	for child in _pivot.get_children():
		_pivot.remove_child(child)
		child.queue_free()
	if not _plans.has(def.id):
		var plan := Plan.new()
		plan.load_ship(str(def.id))
		_plans[def.id] = plan
	var plan_for_ship: Plan = _plans[def.id]
	_stats.text = "%s  -  %s, hull %.0f m\nCrew %d   Cargo %s t   Speed: %s\n%d rooms, %d seats (%d on the bridge), %d crew about the ship\n\n%s" % [
		def.display_name, def.ship_class, def.hull_extent, def.crew, str(def.cargo_tons), def.speed_class,
		plan_for_ship.layout.rooms.size(), plan_for_ship.seat_list.size(), plan_for_ship.seats_in(&"bridge"), plan_for_ship.crew.size(), def.blurb]
	_credit.text = str(def.credit)
	if not Hull.has_model(def):
		_status.text = "The hull model is not on this machine (see ATTRIBUTION.md): a plain stand-in is shown."
	else:
		_status.text = "Loading the hull model..."
	_board_button.disabled = false
	await get_tree().process_frame
	if serial != _serial or not visible:
		return
	var holder := Hull.build(_pivot, def)
	holder.name = "PreviewHull"
	_pivot.rotation = Vector3(0.0, PI, 0.0) # nose toward the camera at first, then turning
	var distance := float(def.hull_extent) * 1.5
	_camera.transform = Transform3D(Basis.looking_at(Vector3(0, -0.25, -1).normalized(), Vector3.UP), Vector3(0, float(def.hull_extent) * 0.3, distance))
	_camera.far = distance * 6.0
	if Hull.has_model(def):
		_status.text = ""


func _play(sound_id: String) -> void:
	if audio != null:
		audio.play_sample(sound_id)
