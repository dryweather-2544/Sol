class_name HangarMenu
extends CanvasLayer
## Fighter hangar (Y while piloting): pick one of the small fighters from a list, look at it on a turntable, and
## take it out (from the helm or on foot; the fighter is a separate ship, main.gd spawns it). Pauses the game while open.

const Spec := preload("res://src/flight/fighter_cockpit_spec.gd") # preloaded, so it needs no class cache refresh

signal closed
signal spawn_requested(def: FighterDef)
signal recall_requested

var audio: AudioService
## True while the player is flying a fighter (shows the return button).
var in_fighter_form := false

var _panel := PanelContainer.new()
var _list := ItemList.new()
var _stats := Label.new()
var _preview_container := SubViewportContainer.new()
var _viewport := SubViewport.new()
var _camera := Camera3D.new()
var _pivot := Node3D.new()
var _spawn_button := Button.new()
var _recall_button := Button.new()
var _defs: Array[FighterDef] = []
var _selected := -1


func _init() -> void:
	name = "HangarMenu"
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_panel.add_child(root)
	add_child(_panel)
	var title := Label.new()
	title.text = "Fighter hangar"
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	root.add_child(row)
	_list.custom_minimum_size = Vector2(220, 340)
	_list.item_selected.connect(_select)
	row.add_child(_list)
	var right := VBoxContainer.new()
	row.add_child(right)
	_preview_container.custom_minimum_size = Vector2(420, 300)
	_preview_container.stretch = true
	_viewport.size = Vector2i(420, 300)
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
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
	_stats.custom_minimum_size = Vector2(420, 120)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_stats)
	var buttons := HBoxContainer.new()
	root.add_child(buttons)
	_spawn_button.text = "Spawn and fly"
	_spawn_button.pressed.connect(_on_spawn)
	buttons.add_child(_spawn_button)
	_recall_button.text = "Return to where I boarded"
	_recall_button.pressed.connect(func():
		_play("rod_gui_click")
		close()
		recall_requested.emit())
	buttons.add_child(_recall_button)
	var close_button := Button.new()
	close_button.text = "Close (Y)"
	close_button.pressed.connect(close)
	buttons.add_child(close_button)


func _process(delta: float) -> void:
	if not visible:
		return
	_panel.position = (get_viewport().get_visible_rect().size - _panel.size) * 0.5
	_pivot.rotation.y += delta * 0.6 # keeps turning while the game is paused (this node ignores pause)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Y):
		get_viewport().set_input_as_handled()
		close()


func open() -> void:
	_defs = FighterCatalog.all()
	_list.clear()
	for def in _defs:
		_list.add_item("%s  (%s)" % [def.display_name, FighterDef.role_name(def.role)])
	_recall_button.visible = in_fighter_form
	visible = true
	get_tree().paused = true
	_play("rod_inventory_open")
	_list.select(0)
	_select(0)


func close() -> void:
	if not visible:
		return
	_play("rod_inventory_close")
	visible = false
	get_tree().paused = false
	closed.emit()


func _select(index: int) -> void:
	_selected = index
	var def := _defs[index]
	for child in _pivot.get_children():
		_pivot.remove_child(child)
		child.queue_free()
	_pivot.rotation = Vector3(0.0, PI, 0.0) # nose toward the camera at first, then turning
	FighterModel.build(_pivot, def)
	var distance := def.size * 1.7
	_camera.transform = Transform3D(Basis.looking_at(Vector3(0, -0.28, -1).normalized(), Vector3.UP), Vector3(0, def.size * 0.35, distance))
	_camera.far = distance * 6.0
	_stats.text = "%s  -  %s, %.0f m\nSpeed x%.2f   Turning x%.2f   Hull x%.1f\nGuns: %.1f shots/s, %.3f damage each\nCockpit: %s\n%s" % [
		def.display_name, FighterDef.role_name(def.role), def.size, def.speed_scale, def.turn_scale, def.toughness, def.gun_rate, def.gun_damage, Spec.by_id(def.cockpit_id).display_name, _blurb(def)]


func _on_spawn() -> void:
	if _selected < 0:
		return
	var def := _defs[_selected]
	_play("rod_gui_click")
	close()
	spawn_requested.emit(def)


func _play(sample: String) -> void:
	if audio != null:
		audio.play_sample(sample)


static func _blurb(def: FighterDef) -> String:
	if def.blurb != "":
		return def.blurb
	match def.role:
		FighterDef.Role.INTERCEPTOR:
			return "Fast and nimble, thin hull. Hit and run."
		FighterDef.Role.HEAVY:
			return "Slow to turn, soaks damage, hits hard."
		FighterDef.Role.ACE:
			return "Quick, accurate and tough: the best of the wing."
		_:
			return "Balanced all-rounder."
