extends CanvasLayer
## Walk a big ship in first person: through the corridors and rooms, sit at any bridge station (the captain's chair is yours), and look at the hull from outside.
## It draws into its own SubViewport with its own world, so nothing of the flight game shows or is touched. While it is open the tree is paused
## (this layer and everything under it keep running). Keys: W A S D move, Shift runs, mouse looks, E sits down / stands up, Tab toggles the hull view, Esc leaves.

const Interior := preload("res://src/bigship/big_ship_interior.gd")
const Plan := preload("res://src/bigship/big_ship_plan.gd")
const Hull := preload("res://src/bigship/big_ship_hull.gd")

signal closed
## The captain (or pilot) took the helm: the menu closes and the scene launches this ship as a craft to fly.
signal fly_requested(ship_def)

const WALK_SPEED := 3.2
const RUN_SPEED := 5.6
const EYE_HEIGHT := 1.65
const SEATED_EYE := 1.18
## How close a seat must be to sit in it.
const REACH := 2.0
## Where the hull is parked for the hull view (far below the interior, which stands at the origin).
const HULL_AT := Vector3(0.0, -900.0, 0.0)
const ROLE_COLOURS := {
	"pilot": Color(0.2, 0.55, 0.9), "copilot": Color(0.25, 0.6, 0.85), "navigator": Color(0.3, 0.75, 0.5), "engineer": Color(0.95, 0.55, 0.1),
	"tactical": Color(0.85, 0.2, 0.2), "weapons": Color(0.85, 0.2, 0.2), "comms": Color(0.7, 0.45, 0.9), "sensors": Color(0.3, 0.8, 0.8),
	"science": Color(0.3, 0.8, 0.8), "gunner": Color(0.85, 0.3, 0.2), "captain": Color(0.9, 0.8, 0.2), "medic": Color(0.9, 0.9, 0.9),
	"doctor": Color(0.9, 0.9, 0.9), "cook": Color(0.95, 0.95, 0.8), "chef": Color(0.95, 0.95, 0.8), "marine": Color(0.4, 0.5, 0.3)}
## An unlit blue planet with soft cloud bands and a bright limb, so the room's ambient light cannot wash it out.
const PLANET_SHADER := """
shader_type spatial;
render_mode unshaded;

void fragment() {
	float limb = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.6);
	float bands = 0.5 + 0.5 * sin(UV.y * 38.0 + sin(UV.x * 11.0) * 1.6);
	vec3 base = mix(vec3(0.07, 0.22, 0.48), vec3(0.55, 0.72, 0.9), bands * 0.18);
	ALBEDO = base + vec3(0.25, 0.5, 1.0) * limb;
}
"""
const SKY_SHADER := """
shader_type sky;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 colour = vec3(0.004, 0.006, 0.012);
	float faint = smoothstep(0.9955, 1.0, hash13(floor(dir * 260.0)));
	float bright = smoothstep(0.9975, 1.0, hash13(floor(dir * 90.0) + 17.0));
	colour += vec3(0.7, 0.8, 1.0) * faint * 0.9 + vec3(1.0, 0.95, 0.85) * bright * 1.6;
	COLOR = colour;
}
"""

var def
var plan: Plan
var interior: Interior

var _container := SubViewportContainer.new()
var _viewport := SubViewport.new()
var _world := Node3D.new()
var _camera: Camera3D
var _hud := Control.new()
var _title_label := Label.new()
var _prompt_label := Label.new()
var _hint_label := Label.new()
var _status_label := Label.new()

var _position := Vector3.ZERO   # feet, ship-local
var _yaw := 0.0
var _pitch := 0.0
var _seat_id := &""
var _seat_avatars := {}         # seat id -> HumanoidAvatar
var _avatars: Array = []
var _hull_holder: Node3D
var _hull_view := false
var _hull_loading := false
## The real game world and where the interior stands in it. When set, the windows look out onto the actual sky, planet and ship instead of a painted backdrop.
var outside_world: World3D = null
var outside_anchor := Transform3D.IDENTITY
var _orbit := 0.6
var _time := 0.0


func _init() -> void:
	name = "BigShipExplorer"
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_container.add_child(_viewport)
	add_child(_container)
	_viewport.add_child(_world)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	_style_label(_title_label, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, 24)
	_style_label(_prompt_label, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 22)
	_prompt_label.offset_top = 70.0
	_style_label(_hint_label, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_BOTTOM, 18)
	_hint_label.offset_bottom = -14.0
	_style_label(_status_label, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 26)
	_hint_label.text = "W A S D move   Shift run   mouse look   E sit / stand   Tab hull view   Esc leave"


func _style_label(label: Label, horizontal: HorizontalAlignment, vertical: VerticalAlignment, size: int) -> void:
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = horizontal
	label.vertical_alignment = vertical
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.offset_left = 18.0
	label.offset_right = -18.0
	label.offset_top = 12.0
	label.offset_bottom = -12.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(label)


## Boards the ship: builds its interior and crew in a fresh world, starts at the spawn point looking along the way in.
func open(ship_def) -> bool:
	def = ship_def
	_clear_world()
	_viewport.own_world_3d = outside_world == null
	if outside_world != null:
		_viewport.world_3d = outside_world
	_world.transform = outside_anchor if outside_world != null else Transform3D.IDENTITY
	plan = Plan.new()
	if not plan.load_ship(str(def.id)):
		push_error("BigShipExplorer: no interior for %s" % str(def.id))
		plan = null
		return false
	interior = Interior.new()
	_world.add_child(interior)
	interior.build(plan)
	if outside_world == null:
		_add_environment()
	else:
		_add_fill_light()
	_add_crew()
	_camera = Camera3D.new()
	_camera.fov = GameSettings.instance().field_of_view
	_camera.near = 0.05
	_camera.far = 6000.0
	_world.add_child(_camera)
	_camera.current = true
	if outside_world != null and outside_world.environment != null:
		# the real sky and stars, but with the room's own even ambient light so the sun's side of the room is not the only lit one
		var lit := outside_world.environment.duplicate() as Environment
		lit.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		lit.ambient_light_color = Color(0.62, 0.66, 0.76)
		lit.ambient_light_energy = 0.7
		_camera.environment = lit
	_position = plan.spawn
	_yaw = plan.spawn_yaw
	_pitch = 0.0
	_seat_id = &""
	_hull_view = false
	_status_label.text = ""
	visible = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_camera()
	_update_hud()
	return true


func close() -> void:
	if not visible:
		return
	visible = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_clear_world()
	plan = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	closed.emit()


func _clear_world() -> void:
	for child in _world.get_children():
		_world.remove_child(child)
		child.queue_free()
	_seat_avatars.clear()
	_avatars.clear()
	_hull_holder = null
	_hull_loading = false
	interior = null


## Inside the real world the room only gets what the real sun gives it through the glass, so a soft fill keeps it readable.
func _add_fill_light() -> void:
	for yaw in [0.0, 90.0, 180.0, 270.0]:
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(-35.0, yaw, 0.0)
		fill.light_energy = 0.4
		fill.shadow_enabled = false
		fill.light_cull_mask = 1
		_world.add_child(fill)


func _hull_at() -> Vector3:
	return HULL_AT if outside_world == null else Vector3(0.0, 400.0, 0.0)


func _add_environment() -> void:
	var sky_shader := Shader.new()
	sky_shader.code = SKY_SHADER
	var sky_material := ShaderMaterial.new()
	sky_material.shader = sky_shader
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.55, 0.65)
	environment.ambient_light_energy = 0.9
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_world.add_child(world_environment)
	# a planet and its sun, on render layer 2 so the sun lights only the planet and the hull, never the rooms
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-14.0, -22.0, 0.0)
	sun.light_energy = 2.2
	sun.light_cull_mask = 2
	_world.add_child(sun)
	var planet := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 700.0
	sphere.height = 1400.0
	sphere.radial_segments = 64
	sphere.rings = 32
	var planet_shader := Shader.new()
	planet_shader.code = PLANET_SHADER
	var planet_material := ShaderMaterial.new()
	planet_material.shader = planet_shader
	sphere.material = planet_material
	planet.mesh = sphere
	planet.position = Vector3(-500.0, -420.0, -2600.0)
	planet.layers = 2
	_world.add_child(planet)


func _add_crew() -> void:
	for entry in plan.seat_list:
		var avatar := _make_avatar(str(entry["role"]))
		_world.add_child(avatar)
		avatar.set_seated(true)
		var seat_position: Vector3 = entry["position"]
		avatar.position = Vector3(seat_position.x, seat_position.y - avatar.seat_drop, seat_position.z)
		avatar.rotation.y = float(entry["yaw"])
		_seat_avatars[entry["id"]] = avatar
		_avatars.append(avatar)
	for entry in plan.crew:
		var avatar := _make_avatar(str(entry["role"]))
		_world.add_child(avatar)
		avatar.position = entry["position"]
		avatar.rotation.y = float(entry["yaw"])
		_avatars.append(avatar)


func _make_avatar(role: String) -> HumanoidAvatar:
	var avatar := HumanoidAvatar.new()
	avatar.accent_color = ROLE_COLOURS.get(role, Color(0.9, 0.45, 0.1))
	return avatar


# ------------------------------------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if not visible or plan == null:
		return
	_time += delta
	for avatar in _avatars:
		(avatar as HumanoidAvatar).animate(0.0, delta)
	if _hull_view:
		_orbit += delta * 0.22
		_update_hull_camera()
		_update_hud()
		return
	if _seat_id == &"":
		_walk(delta)
	interior.update(_position, delta)
	_update_camera()
	_update_hud()


func _walk(delta: float) -> void:
	var command := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		command.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		command.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		command.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		command.x += 1.0
	if command == Vector2.ZERO:
		return
	command = command.normalized()
	var speed := RUN_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else WALK_SPEED
	var forward := Vector2(-sin(_yaw), -cos(_yaw))
	var right := Vector2(cos(_yaw), -sin(_yaw))
	var step := (forward * -command.y + right * command.x) * speed * delta
	_try_move(step)


## Moves by `step` (x, z) if the floor there is clear; otherwise slides along whichever axis still is.
func _try_move(step: Vector2) -> void:
	var layout := plan.layout
	var radius := InteriorBody.RADIUS
	if layout.is_position_walkable(_position.x + step.x, _position.z + step.y, radius):
		_position.x += step.x
		_position.z += step.y
	elif layout.is_position_walkable(_position.x + step.x, _position.z, radius):
		_position.x += step.x
	elif layout.is_position_walkable(_position.x, _position.z + step.y, radius):
		_position.z += step.y


func _update_camera() -> void:
	var seated := _seat_id != &""
	var eye := plan.layout.floor_y + (SEATED_EYE if seated else EYE_HEIGHT)
	_camera.position = Vector3(_position.x, eye, _position.z)
	_camera.rotation = Vector3(_pitch, _yaw, 0.0)


func _update_hull_camera() -> void:
	var radius := float(def.hull_extent) * 1.05 + 14.0
	var centre := _hull_at()
	var eye := centre + Vector3(sin(_orbit) * radius, radius * 0.3, cos(_orbit) * radius)
	_camera.transform = Transform3D(Basis.looking_at(centre - eye, Vector3.UP), eye)


func _update_hud() -> void:
	var title := "%s - %s" % [str(def.display_name), str(def.ship_class)]
	if _hull_view:
		_title_label.text = title + "   (outside)"
		_prompt_label.text = "Tab - back inside"
		return
	var room_id := plan.layout.room_at(_position.x, _position.z)
	if room_id == &"":
		room_id = plan.layout.room_for_view(_position.x, _position.z)
	var room_text := plan.room_name(room_id)
	_title_label.text = title + ("   |   " + room_text if room_text != "" else "")
	if _seat_id != &"":
		var seated_at := plan.seat(_seat_id)
		var role := str(seated_at.get("role", ""))
		_prompt_label.text = "E - stand up   (seated: %s station)" % role
		if role == "captain" or role == "pilot":
			_prompt_label.text += "\nF - take the helm and fly the %s" % str(def.display_name)
	else:
		var near := _seat_in_reach()
		if near == &"":
			_prompt_label.text = ""
		else:
			var seat_ahead := plan.seat(near)
			var manned := "" if near == &"captain" else " - the crew member steps aside"
			_prompt_label.text = "E - sit at the %s station%s" % [str(seat_ahead.get("role", "")), manned]


# ------------------------------------------------------------------------------------------------ input
func _input(event: InputEvent) -> void:
	if not visible or plan == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var sensitivity := 0.0022 * GameSettings.instance().mouse_sensitivity
		if _hull_view:
			_orbit -= motion.relative.x * sensitivity
		else:
			_yaw -= motion.relative.x * sensitivity
			_pitch = clampf(_pitch - motion.relative.y * sensitivity, -1.45, 1.45)
			_limit_look_when_seated()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.physical_keycode == KEY_ESCAPE or event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			close()
		elif key_event.physical_keycode == KEY_E and not _hull_view:
			get_viewport().set_input_as_handled()
			_toggle_seat()
		elif key_event.physical_keycode == KEY_F and not _hull_view and _seat_id != &"" and str(plan.seat(_seat_id).get("role", "")) in ["captain", "pilot"]:
			get_viewport().set_input_as_handled()
			fly_requested.emit(def)
		elif key_event.physical_keycode == KEY_TAB:
			get_viewport().set_input_as_handled()
			_toggle_hull_view()


## Seated, the head turns about 115 degrees either way from the way the seat faces, not further.
func _limit_look_when_seated() -> void:
	if _seat_id == &"":
		return
	var seat := plan.seat(_seat_id)
	var facing := float(seat.get("yaw", 0.0))
	var relative := wrapf(_yaw - facing, -PI, PI)
	_yaw = facing + clampf(relative, -2.0, 2.0)
	_pitch = clampf(_pitch, -1.0, 1.0)


func _seat_in_reach() -> StringName:
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var best := &""
	var best_score := -INF
	for entry in plan.seat_list:
		var to_seat: Vector3 = (entry["position"] as Vector3) - _position
		to_seat.y = 0.0
		var distance := to_seat.length()
		if distance > REACH:
			continue
		var facing := 1.0
		if distance > 0.01:
			facing = forward.dot(to_seat / distance)
		if facing < 0.35:
			continue
		var score := facing - distance * 0.2
		if score > best_score:
			best_score = score
			best = entry["id"]
	return best


func _toggle_seat() -> void:
	if _seat_id != &"":
		var current := plan.seat(_seat_id)
		var current_avatar: Node3D = _seat_avatars.get(_seat_id)
		if current_avatar != null:
			current_avatar.visible = true
		_position = current["exit"]
		_seat_id = &""
		return
	var near := _seat_in_reach()
	if near == &"":
		return
	var target := plan.seat(near)
	var target_avatar: Node3D = _seat_avatars.get(near)
	if target_avatar != null:
		target_avatar.visible = false
	_seat_id = near
	_position = target["position"]
	_yaw = float(target["yaw"])
	_pitch = 0.0


func _toggle_hull_view() -> void:
	if _hull_view:
		_hull_view = false
		_status_label.text = ""
		return
	if _hull_loading:
		return
	_show_hull_view()


func _show_hull_view() -> void:
	if _hull_holder == null:
		_hull_loading = true
		_status_label.text = "Loading the hull model..."
		await get_tree().process_frame
		if plan == null:
			return
		_hull_holder = Hull.build(_world, def)
		_hull_holder.position = _hull_at()
		Hull.set_layers(_hull_holder, 2)
		_hull_loading = false
		_status_label.text = ""
	_hull_view = true
