class_name ShipVisuals
extends Node3D
const HullShell = preload("res://src/flight/ship_hull_shell.gd")
## Builds the placeholder ship from the interior layout (so the walls you see are the walls you
## walk between) and animates the doors and ramp from the ship's systems. Nose points to -z.

var ship: Ship
var _door_nodes := {}   # portal id -> {node: MeshInstance3D, base_y: float}
var _room_lights := {} # room id -> OmniLight3D
var _fire_nodes := {}   # room id -> MeshInstance3D
var _station_screens := {} # station id -> StandardMaterial3D (emission shows the station's state)
var _smoke_nodes := {}    # room id -> CPUParticles3D
var _scorch_decals := {}  # room id -> Decal, hidden until the room has had a fire this session (not saved: saves may not change in N9)
var _turret_pivot := Node3D.new()
var _ramp_pivot := Node3D.new()
var _ramp_mesh := MeshInstance3D.new()

var _hull_material := _material(Color(0.55, 0.6, 0.68), 0.55, 0.35)
var _floor_material := _material(Color(0.25, 0.27, 0.3), 0.8, 0.1)
var _accent_material := _material(Color(0.9, 0.35, 0.1), 0.6, 0.2)
var _door_material: Material = AssetLibrary.material_or("mat_ship_brushed_metal", _material(Color(0.75, 0.78, 0.82), 0.4, 0.5))
var _glow_material := _emissive(Color(0.3, 0.7, 1.0), 3.0)
var _panel_material := _emissive(Color(0.2, 1.0, 0.5), 2.5)
# N9: textured versions of the roles above. Each falls back to its code material when the asset is missing or GameSettings.asset_materials
# is off, so the original look is always one switch away. Interiors and exterior hull plating share boxes, so walls use the paint panel.
var _wall_material: Material = AssetLibrary.material_or("mat_ship_paint_panel", _hull_material)
var _exterior_material: Material = AssetLibrary.material_or("mat_hull_plating", _hull_material)
var _floor_slab_material: Material = AssetLibrary.material_or("mat_ship_floor_plate", _floor_material)
var _rubber_floor_material: Material = AssetLibrary.material_or("mat_ship_rubber_mat", _floor_slab_material)
var _console_material: Material = AssetLibrary.material_or("mat_ship_composite_dark", _floor_material)
var _metal_material: Material = AssetLibrary.material_or("mat_ship_brushed_metal", _floor_material)
var _nozzle_material: Material = AssetLibrary.material_or("mat_hull_nozzle", _glow_material)
var _glass_material: Material = AssetLibrary.material_or("mat_ship_glass", _material(Color(0.4, 0.55, 0.7, 0.12), 0.08, 0.2))


func _ready() -> void:
	_tune_materials()
	var layout := ship.systems.layout
	_build_floors_and_ceilings(layout)
	_build_walls(layout)
	_build_doors(layout)
	_build_seat_and_console(layout)
	_build_panels(layout)
	_build_interior_trim(layout)
	_build_cockpit_details(layout)
	_build_exterior_extras(layout)
	_build_ramp(layout)
	_build_turret()
	_build_lights(layout)
	if _wall_material != _hull_material:
		_build_reflection_probe(layout)
	_build_decals(layout)

func _tune_materials() -> void:
	# Private copies: the shared .tres assets stay untouched for other users and for tests.
	if _exterior_material is BaseMaterial3D:
		var hull_copy := (_exterior_material as BaseMaterial3D).duplicate() as BaseMaterial3D
		hull_copy.albedo_color = Color(0.78, 0.80, 0.84)
		hull_copy.roughness = 0.7
		_exterior_material = hull_copy
	if _glass_material is BaseMaterial3D:
		var glass_copy := (_glass_material as BaseMaterial3D).duplicate() as BaseMaterial3D
		glass_copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass_copy.albedo_color = Color(0.34, 0.46, 0.58, 0.055)
		glass_copy.metallic = 0.0
		glass_copy.metallic_specular = 0.18
		glass_copy.roughness = 0.06
		_glass_material = glass_copy


func _process(_delta: float) -> void:
	var layout := ship.systems.layout
	for portal_id in _door_nodes:
		var portal: Portal = layout.portals[portal_id]
		var record: Dictionary = _door_nodes[portal_id]
		(record["node"] as Node3D).position.y = record["base_y"] + portal.open_factor * 2.3
	var aim := ship.systems.turret.aim_local
	if aim.length() > 0.5:
		_turret_pivot.basis = Basis.looking_at(aim, Vector3.UP if absf(aim.y) < 0.99 else Vector3.FORWARD)
	var hazards := ship.systems.hazards
	var flicker := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)
	for room_id in _fire_nodes:
		var intensity := hazards.fire_in(room_id)
		if intensity > 0.0 and _scorch_decals.has(room_id):
			(_scorch_decals[room_id] as Decal).visible = true
		(_fire_nodes[room_id] as Node3D).visible = intensity > 0.0
		(_smoke_nodes[room_id] as CPUParticles3D).emitting = intensity > 0.0
		(_fire_nodes[room_id] as Node3D).scale = Vector3.ONE * (0.4 + 0.8 * intensity) * (0.9 + 0.2 * flicker)
		var light: OmniLight3D = _room_lights[room_id]
		light.light_color = Color(1.0, 0.35 + 0.2 * flicker, 0.2) if intensity > 0.0 else Color.WHITE
		light.light_energy = 1.6 + 2.0 * intensity if intensity > 0.0 else 1.6
	_update_screens()
	var walkway := ship.systems.walkway
	_ramp_pivot.visible = walkway.progress > 0.0
	_ramp_mesh.scale.z = maxf(walkway.progress, 0.001)
	var drop := layout.floor_y - layout.ramp_end_y
	_ramp_pivot.rotation.x = asin(clampf(drop / layout.ramp_rect.size.y, -0.9, 0.9))


func _build_floors_and_ceilings(layout: InteriorLayout) -> void:
	for room_id in layout.rooms:
		var room: Rect2 = layout.rooms[room_id]
		var rubber_floor: bool = room_id == &"airlock" or room_id == &"cargo"
		_slab(room, layout.floor_y - 0.12, layout.floor_y, _rubber_floor_material if rubber_floor else _floor_slab_material)
		_slab(room, layout.ceiling_y, layout.ceiling_y + 0.12, _wall_material)
	for portal in layout.portals.values():
		_slab((portal as Portal).opening, layout.floor_y - 0.12, layout.floor_y, _floor_slab_material)
		_slab((portal as Portal).opening, layout.ceiling_y, layout.ceiling_y + 0.12, _wall_material)


## Walls are the 0.2 m skin just outside each room rectangle, with gaps where a portal opening crosses it.
## The cockpit's nose wall is glass.
func _build_walls(layout: InteriorLayout) -> void:
	var bottom := layout.floor_y
	var top := layout.ceiling_y
	var glass_material: Material = _glass_material
	var thickness := 0.2
	for room_id in layout.rooms:
		var room: Rect2 = layout.rooms[room_id]
		var walls := {
			"nose": [Rect2(room.position.x - thickness, room.position.y - thickness, room.size.x + 2.0 * thickness, thickness), true],
			"tail": [Rect2(room.position.x - thickness, room.end.y, room.size.x + 2.0 * thickness, thickness), true],
			"left": [Rect2(room.position.x - thickness, room.position.y, thickness, room.size.y), false],
			"right": [Rect2(room.end.x, room.position.y, thickness, room.size.y), false]}
		for side in walls:
			var wall: Rect2 = walls[side][0]
			var runs_along_x: bool = walls[side][1]
			if room_id == &"cockpit" and side == "nose":
				# The exterior shell owns the single cockpit pane; a second transparent wall here
				# doubled the reflection and made the view look like an interior corridor.
				continue
			_wall_with_portal_gaps(layout, wall, runs_along_x, bottom, top)


func _wall_with_portal_gaps(layout: InteriorLayout, wall: Rect2, runs_along_x: bool, bottom: float, top: float) -> void:
	var start := wall.position.x if runs_along_x else wall.position.y
	var finish := wall.end.x if runs_along_x else wall.end.y
	var gaps: Array = []
	for portal in layout.portals.values():
		var opening: Rect2 = (portal as Portal).opening
		if opening.intersects(wall):
			gaps.append(Vector2(opening.position.x, opening.end.x) if runs_along_x else Vector2(opening.position.y, opening.end.y))
	gaps.sort_custom(func(first: Vector2, second: Vector2) -> bool: return first.x < second.x)
	var cursor := start
	for gap in gaps:
		_wall_span(wall, runs_along_x, cursor, gap.x, bottom, top)
		_wall_span(wall, runs_along_x, gap.x, gap.y, bottom + 2.1, top) # lintel above the door
		cursor = gap.y
	_wall_span(wall, runs_along_x, cursor, finish, bottom, top)


func _wall_span(wall: Rect2, runs_along_x: bool, from_value: float, to_value: float, y_min: float, y_max: float) -> void:
	if to_value - from_value < 0.001:
		return
	if runs_along_x:
		_wall_box(from_value, to_value, wall.position.y, wall.end.y, y_min, y_max)
	else:
		_wall_box(wall.position.x, wall.end.x, from_value, to_value, y_min, y_max)


func _build_doors(layout: InteriorLayout) -> void:
	for portal_id in layout.portals:
		var portal: Portal = layout.portals[portal_id]
		var opening := portal.opening
		var door_height := 2.1
		var base_y := layout.floor_y + door_height * 0.5
		var instance := _box_instance(Vector3(opening.size.x, door_height, opening.size.y * 0.9), _door_material)
		instance.position = Vector3(opening.position.x + opening.size.x * 0.5, base_y, opening.position.y + opening.size.y * 0.5)
		add_child(instance)
		_door_nodes[portal_id] = {"node": instance, "base_y": base_y}


func _build_seat_and_console(layout: InteriorLayout) -> void:
	for seat_id in layout.seats:
		var seat_position: Vector3 = layout.seats[seat_id]["position"]
		var behind := Vector3(0, 0, 0.38) if absf(layout.seats[seat_id]["facing_yaw"]) < 1.0 else Vector3(0, 0, -0.38)
		var seat := _box_instance(Vector3(0.7, 0.5, 0.7), _accent_material)
		seat.position = seat_position + Vector3(0, 0.25, 0)
		add_child(seat)
		var back := _box_instance(Vector3(0.7, 1.0, 0.12), _accent_material)
		back.position = seat_position + Vector3(0, 0.75, 0) + behind
		add_child(back)
	# The cockpit dashboard is built in _build_cockpit_details; the old bright console box
	# here was the large white slab that washed out the cockpit view.


func _build_panels(layout: InteriorLayout) -> void:
	for point in layout.interact_points:
		if layout.seats.has(point["id"]):
			continue
		if point["id"] in [&"reactor_panel", &"engine_station"]:
			# A wall screen that shows the station's state (see _update_screens).
			var screen_material := _emissive(Color(0.2, 1.0, 0.5), 2.0)
			# Reactor screen = west wall (+x face shows), generic = east wall (-x face): the layout puts the reactor panel at x = -2.7 and
			# the engine station at x = +2.7, which is what the assets were authored for (mat_ship_screen SOURCE.md).
			var asset_screen := AssetLibrary.material_copy_or("mat_ship_screen_reactor" if point["id"] == &"reactor_panel" else "mat_ship_screen_generic", null)
			if asset_screen is StandardMaterial3D:
				screen_material = asset_screen as StandardMaterial3D
			var screen := _box_instance(Vector3(0.06, 0.55, 0.8), screen_material)
			var wall_side := 1.0 if point["position"].x > 0.0 else -1.0
			# The wall skin is 0.2 m thick with its inner face 0.3 m behind the panel point, so the old offset of 0.42 put this 0.06 m box
			# inside the wall (hidden). 0.27 puts its back flush with the wall face and its front 0.06 m proud of it.
			screen.position = point["position"] + Vector3(wall_side * 0.27, 1.1, 0)
			add_child(screen)
			_station_screens[point["id"]] = screen_material
			continue
		var panel := _box_instance(Vector3(0.25, 0.35, 0.08), _panel_material)
		panel.position = point["position"] + Vector3(0, 1.1, 0)
		add_child(panel)


func _build_interior_trim(layout: InteriorLayout) -> void:
	# Visual-only trim: ribs, floor edge strips, ceiling luminaires, engineering pipes and cargo
	# crates. Nothing here has collision, so the walkable footprint and interaction points are
	# unchanged.
	var warm := _emissive(Color(1.0, 0.82, 0.58), 1.8)
	var cool := _emissive(Color(0.42, 0.72, 1.0), 1.4)
	for room_id in layout.rooms:
		var rect: Rect2 = layout.rooms[room_id]
		var center := Vector3(rect.get_center().x, 0, rect.get_center().y)
		var is_engineering: bool = room_id == &"engineering" or room_id == &"turret_room"
		var ceiling_mat: Material = cool if is_engineering else warm
		# Recessed ceiling strip.
		var strip := _box_instance(Vector3(maxf(0.8, rect.size.x * 0.45), 0.025, 0.10), ceiling_mat)
		strip.position = Vector3(center.x, layout.ceiling_y - 0.035, center.z)
		add_child(strip)
		# Floor edge accent, tucked against both side walls.
		for side in [-1.0, 1.0]:
			var edge := _box_instance(Vector3(0.055, 0.018, maxf(0.5, rect.size.y * 0.86)), _accent_material)
			edge.position = Vector3(center.x + side * (rect.size.x * 0.5 - 0.16), layout.floor_y + 0.02, center.z)
			add_child(edge)
		# Wall ribs every ~1.6 m: thin metal frames that catch the room lights.
		var rib_count := maxi(1, int(rect.size.y / 1.6))
		for rib in range(rib_count + 1):
			var z := rect.position.y + 0.35 + float(rib) * (rect.size.y - 0.7) / float(maxi(1, rib_count))
			for side in [-1.0, 1.0]:
				var rib_mesh := _box_instance(Vector3(0.035, 2.18, 0.075), _metal_material)
				rib_mesh.position = Vector3(center.x + side * (rect.size.x * 0.5 - 0.06), layout.floor_y + 1.12, z)
				add_child(rib_mesh)
		# Low lockers / crates in cargo and the airlock vestibule; kept against the wall.
		if room_id == &"cargo":
			for index in 3:
				var crate := _box_instance(Vector3(0.55, 0.52, 0.62), _metal_material if index != 1 else _accent_material)
				crate.position = Vector3(rect.position.x + 0.42, layout.floor_y + 0.26, rect.position.y + 0.55 + index * 0.75)
				add_child(crate)
				var lid := _box_instance(Vector3(0.50, 0.035, 0.56), _console_material)
				lid.position = crate.position + Vector3(0, 0.275, 0)
				add_child(lid)
		# Engineering conduits along the ceiling.
		if room_id == &"engineering":
			for offset in [-0.22, 0.0, 0.22]:
				var pipe := CylinderMesh.new()
				pipe.top_radius = 0.055
				pipe.bottom_radius = 0.055
				pipe.height = rect.size.y * 0.78
				pipe.radial_segments = 10
				var pipe_node := MeshInstance3D.new()
				pipe_node.mesh = pipe
				pipe_node.material_override = _metal_material if offset != 0.0 else _accent_material
				pipe_node.rotation_degrees = Vector3(90, 0, 0)
				pipe_node.position = Vector3(center.x - 2.25, layout.ceiling_y - 0.28 + offset, center.z)
				add_child(pipe_node)
	# A few hanging cable bundles / junction boxes give the engineering room a silhouette.
	for z in [-1.2, 0.8, 2.4]:
		var box := _box_instance(Vector3(0.32, 0.46, 0.22), _console_material)
		box.position = Vector3(-2.62, layout.ceiling_y - 0.34, z)
		add_child(box)
		var led := _box_instance(Vector3(0.10, 0.035, 0.02), _emissive(Color(0.2, 1.0, 0.55), 2.0))
		led.position = box.position + Vector3(0.0, 0.10, 0.13)
		add_child(led)


func _build_cockpit_details(layout: InteriorLayout) -> void:
	# The cockpit is the first thing the player sees. Build a real dashboard, canopy frame,
	# side consoles and pedals around the existing seat and windshield.
	var screen := _screen(Color(0.16, 0.52, 0.72), 0.55)
	var screen_warm := _screen(Color(0.86, 0.34, 0.10), 0.5)
	var dark := _material(Color(0.030, 0.038, 0.050), 0.64, 0.32)
	# Dashboard body and glare hood.
	var dash := _box_instance(Vector3(2.85, 0.36, 0.56), dark)
	dash.position = Vector3(0, -0.28, -6.52)
	add_child(dash)
	var dash_lower := _box_instance(Vector3(2.45, 0.20, 0.42), _material(Color(0.018, 0.022, 0.030), 0.72, 0.18))
	dash_lower.position = Vector3(0, -0.56, -6.40)
	add_child(dash_lower)
	var hood := _box_instance(Vector3(2.95, 0.045, 0.24), _metal_material)
	hood.position = Vector3(0, 0.055, -6.70)
	add_child(hood)
	# Three raised multi-function displays, angled toward the pilot. They sit above the dash
	# brow so they are actually visible from the eye point.
	for x in [-0.86, 0.0, 0.86]:
		var bezel := _box_instance(Vector3(0.70, 0.32, 0.055), dark)
		bezel.position = Vector3(x, 0.16, -6.62)
		bezel.rotation_degrees = Vector3(-12, 0, 0)
		add_child(bezel)
		var panel := _box_instance(Vector3(0.55, 0.20, 0.025), screen if x != 0.0 else screen_warm)
		panel.position = Vector3(x, 0.17, -6.58)
		panel.rotation_degrees = Vector3(-12, 0, 0)
		add_child(panel)
		# A few bright data strokes break up the solid MFD face without a texture round-trip.
		var line_color := Color(0.55, 0.95, 1.0) if x != 0.0 else Color(1.0, 0.72, 0.32)
		for row in 3:
			var line := _box_instance(Vector3(0.34 if row != 1 else 0.24, 0.010, 0.006), _emissive(line_color, 0.55))
			line.position = Vector3(x - 0.04, 0.235 - row * 0.055, -6.555)
			line.rotation_degrees = Vector3(-12, 0, 0)
			add_child(line)
		var cursor := _box_instance(Vector3(0.035, 0.085, 0.006), _emissive(line_color, 0.8))
		cursor.position = Vector3(x + 0.19, 0.16, -6.555)
		cursor.rotation_degrees = Vector3(-12, 0, 0)
		add_child(cursor)
	# Instrument binnacle and centre stick, raised into the lower field of view.
	var binnacle := _box_instance(Vector3(1.05, 0.18, 0.24), dark)
	binnacle.position = Vector3(0, 0.02, -6.30)
	add_child(binnacle)
	var stick := CylinderMesh.new()
	stick.top_radius = 0.035
	stick.bottom_radius = 0.045
	stick.height = 0.42
	var stick_node := MeshInstance3D.new()
	stick_node.mesh = stick
	stick_node.material_override = _metal_material
	stick_node.position = Vector3(0, -0.32, -5.74)
	add_child(stick_node)
	var grip := _box_instance(Vector3(0.16, 0.10, 0.10), dark)
	grip.position = Vector3(0, -0.12, -5.74)
	add_child(grip)
	# Side consoles and armrests.
	for side in [-1.0, 1.0]:
		var console := _box_instance(Vector3(0.32, 0.30, 0.82), dark)
		console.position = Vector3(side * 1.32, -0.24, -6.18)
		add_child(console)
		var console_led := _box_instance(Vector3(0.16, 0.025, 0.55), screen)
		console_led.position = console.position + Vector3(0, 0.16, 0)
		add_child(console_led)
		# Canopy side frame: masks the edge of the broad windshield.
		var side_frame := _box_instance(Vector3(0.42, 1.52, 0.08), dark)
		side_frame.position = Vector3(side * 1.58, 0.46, -6.95)
		side_frame.rotation_degrees = Vector3(-6, 0, 0)
		add_child(side_frame)
		# Armrest.
		var arm := _box_instance(Vector3(0.18, 0.08, 0.56), _metal_material)
		arm.position = Vector3(side * 0.66, -0.22, -5.68)
		add_child(arm)
	# Pedals and floor mat.
	for side in [-1.0, 1.0]:
		var pedal := _box_instance(Vector3(0.24, 0.07, 0.30), _metal_material)
		pedal.position = Vector3(side * 0.30, layout.floor_y + 0.10, -6.12)
		add_child(pedal)
	var mat := _box_instance(Vector3(1.75, 0.02, 0.92), _rubber_floor_material)
	mat.position = Vector3(0, layout.floor_y + 0.015, -5.55)
	add_child(mat)
	# Throttle quadrant and overhead switch row.
	var throttle_base := _box_instance(Vector3(0.28, 0.22, 0.48), dark)
	throttle_base.position = Vector3(-1.05, -0.32, -6.05)
	add_child(throttle_base)
	var throttle := _box_instance(Vector3(0.10, 0.34, 0.10), _metal_material)
	throttle.position = Vector3(-1.05, -0.10, -6.05)
	throttle.rotation_degrees = Vector3(-18, 0, 0)
	add_child(throttle)
	var overhead := _box_instance(Vector3(1.9, 0.12, 0.30), dark)
	overhead.position = Vector3(0, 1.30, -5.92)
	overhead.rotation_degrees = Vector3(8, 0, 0)
	add_child(overhead)
	for x in [-0.65, -0.32, 0.0, 0.32, 0.65]:
		var toggle := _box_instance(Vector3(0.08, 0.06, 0.06), _metal_material)
		toggle.position = Vector3(x, 1.22, -5.88)
		add_child(toggle)
		var toggle_led := _box_instance(Vector3(0.035, 0.025, 0.02), screen)
		toggle_led.position = Vector3(x, 1.15, -5.90)
		add_child(toggle_led)
	var cockpit_light := OmniLight3D.new()
	cockpit_light.position = Vector3(0, 0.35, -6.20)
	cockpit_light.omni_range = 2.2
	cockpit_light.light_energy = 0.55
	cockpit_light.light_color = Color(1.0, 0.62, 0.34)
	cockpit_light.shadow_enabled = false
	add_child(cockpit_light)


func _build_exterior_extras(layout: InteriorLayout) -> void:
	# Original code-built hull shell: tapered loft, swept wings, engine cowls, panel seams,
	# cockpit frame/dashboard and landing gear. Collision and gameplay are untouched.
	HullShell.build(self, _exterior_material, _console_material, _accent_material, _glass_material, _nozzle_material, _metal_material, _glow_material)


## Station screens: reactor green -> red with core heat (dark when tripped); engine screen red -> green with engine health.
func _update_screens() -> void:
	var systems := ship.systems
	if _station_screens.has(&"reactor_panel"):
		var material: StandardMaterial3D = _station_screens[&"reactor_panel"]
		var shade := Color(0.15, 0.15, 0.15) if systems.power.is_shut_down() else Color(0.2, 1.0, 0.5).lerp(Color(1.0, 0.2, 0.1), clampf(systems.power.temperature, 0.0, 1.0))
		material.albedo_color = shade
		material.emission = shade
	if _station_screens.has(&"engine_station"):
		var material: StandardMaterial3D = _station_screens[&"engine_station"]
		var shade := Color(1.0, 0.2, 0.1).lerp(Color(0.2, 1.0, 0.5), systems.subsystems.value(ShipSubsystems.Id.ENGINES))
		material.albedo_color = shade
		material.emission = shade


## The dorsal gun above the turret room; the barrel follows ShipTurret's aim.
func _build_turret() -> void:
	_turret_pivot.position = ship.systems.turret.muzzle_offset - Vector3(0, 0.15, 0)
	add_child(_turret_pivot)
	var base := _box_instance(Vector3(0.7, 0.3, 0.7), _metal_material)
	base.position = Vector3(0, -0.05, 0)
	_turret_pivot.add_child(base)
	var barrel := _box_instance(Vector3(0.14, 0.14, 1.1), _accent_material)
	barrel.position = Vector3(0, 0.1, -0.6)
	_turret_pivot.add_child(barrel)


func _build_ramp(layout: InteriorLayout) -> void:
	_ramp_pivot.position = Vector3(layout.ramp_rect.position.x + layout.ramp_rect.size.x * 0.5, layout.floor_y - 0.04, layout.ramp_rect.position.y)
	add_child(_ramp_pivot)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(layout.ramp_rect.size.x, 0.08, layout.ramp_rect.size.y)
	_ramp_mesh.mesh = mesh
	_ramp_mesh.material_override = _door_material
	_ramp_mesh.position = Vector3(0, 0, layout.ramp_rect.size.y * 0.5)
	_ramp_pivot.add_child(_ramp_mesh)
	_ramp_pivot.visible = false


func _build_lights(layout: InteriorLayout) -> void:
	for room_id in layout.rooms:
		var rect: Rect2 = layout.rooms[room_id]
		var light := OmniLight3D.new()
		light.position = Vector3(rect.get_center().x, 1.18, rect.get_center().y)
		light.omni_range = 5.2
		light.light_energy = 1.05
		light.omni_attenuation = 1.15
		light.light_specular = 0.35
		light.light_color = Color(0.58, 0.76, 1.0) if room_id == &"engineering" else Color(1.0, 0.82, 0.63)
		light.shadow_enabled = false
		add_child(light)
		_room_lights[room_id] = light
		if ship.systems.hazards.has_room(room_id):
			var flames := _box_instance(Vector3(0.9, 1.0, 0.9), _emissive(Color(1.0, 0.45, 0.1), 4.0))
			flames.position = Vector3((rect as Rect2).get_center().x, layout.floor_y + 0.5, (rect as Rect2).get_center().y)
			flames.visible = false
			add_child(flames)
			_fire_nodes[room_id] = flames
			var smoke := CPUParticles3D.new()
			smoke.position = flames.position + Vector3(0, 0.4, 0)
			smoke.amount = 28
			smoke.lifetime = 1.6
			smoke.direction = Vector3.UP
			smoke.spread = 25.0
			smoke.initial_velocity_min = 0.6
			smoke.initial_velocity_max = 1.2
			smoke.gravity = Vector3.ZERO
			var puff := SphereMesh.new()
			puff.radius = 0.12
			puff.height = 0.24
			smoke.mesh = puff
			smoke.material_override = _emissive(Color(1.0, 0.55, 0.15), 3.0)
			smoke.emitting = false
			add_child(smoke)
			_smoke_nodes[room_id] = smoke


## Decals from the Sol-Assets sets: room names above the doors, hazard stripes at the airlock and reactor, station IDs on the walls, and
## hidden scorch marks that appear in a room once it has burned. Positions come from the layout, never from hard-coded numbers.
func _build_decals(layout: InteriorLayout) -> void:
	if not GameSettings.instance().decals:
		return
	var plate_height := layout.floor_y + 2.3 # the lintel above a 2.1 m door spans 2.1 m up to the ceiling
	# [decal, door, true = the wall face on the door's tail side (looks toward +z, into the room behind the door)]
	var plates := [["room_cockpit", &"cockpit_door", false], ["room_cabin", &"cockpit_door", true], ["room_engineering", &"engineering_door", true],
		["room_turret", &"turret_door", true], ["room_cargo", &"cargo_door", true], ["room_airlock", &"airlock_inner", true]]
	for plate in plates:
		var opening: Rect2 = (layout.portals[plate[1]] as Portal).opening
		var tail_side: bool = plate[2]
		var wall_z := opening.end.y if tail_side else opening.position.y
		_add_decal("dec_ship_markings", plate[0], Vector3(opening.get_center().x, plate_height, wall_z), _wall_decal_basis(Vector3(0, 0, 1) if tail_side else Vector3(0, 0, -1)))
	var airlock_door: Rect2 = (layout.portals[&"airlock_inner"] as Portal).opening
	for offset_x in [-0.5, 0.5]:
		_add_decal("dec_ship_markings", "hazard_stripe", Vector3(airlock_door.get_center().x + offset_x, layout.floor_y, airlock_door.get_center().y), Basis.IDENTITY)
	var station_ids := {&"reactor_panel": "id_reactor", &"engine_station": "id_engine", &"repair_panel": "id_repair", &"workbench": "id_workbench", &"extinguisher_locker": "id_extinguisher"}
	for point in layout.interact_points:
		if not station_ids.has(point["id"]):
			continue
		var position: Vector3 = point["position"]
		for room_id in layout.rooms:
			var rect: Rect2 = layout.rooms[room_id]
			if not rect.has_point(Vector2(position.x, position.z)):
				continue
			var on_west_wall := position.x < rect.get_center().x
			var wall_x := rect.position.x if on_west_wall else rect.end.x
			_add_decal("dec_ship_markings", station_ids[point["id"]], Vector3(wall_x, layout.floor_y + 1.5, position.z), _wall_decal_basis(Vector3.RIGHT if on_west_wall else Vector3.LEFT))
			if point["id"] == &"reactor_panel":
				_add_decal("dec_ship_markings", "hazard_stripe", Vector3(position.x + 0.4, layout.floor_y, position.z), Basis(Vector3.UP, PI * 0.5))
	var scorch_index := 0
	for room_id in layout.rooms:
		if not ship.systems.hazards.has_room(room_id):
			continue
		var rect: Rect2 = layout.rooms[room_id]
		var scorch := _add_decal("dec_ship_damage", "scorch_01" if scorch_index % 2 == 0 else "scorch_02", Vector3(rect.get_center().x, layout.floor_y, rect.get_center().y), Basis.IDENTITY)
		scorch_index += 1
		if scorch != null:
			scorch.visible = false
			_scorch_decals[room_id] = scorch


## A Decal projects along its local -y with the texture's top at local -z. For a vertical wall the basis is: local y = the wall normal
## (toward the viewer), local -z = up, local x = the viewer's right.
static func _wall_decal_basis(normal: Vector3) -> Basis:
	var right := -normal.cross(Vector3.UP).normalized()
	return Basis(right, normal, -Vector3.UP)


## Adds one catalogue decal at `center`, or returns null (decal skipped, logged once) when its texture is missing.
func _add_decal(set_id: String, decal_name: String, center: Vector3, orientation: Basis) -> Decal:
	var entry: Dictionary = DecalCatalog.SETS[set_id][decal_name]
	var albedo := AssetLibrary.texture("decals/%s/%s_%s_albedo.png" % [set_id, set_id, decal_name])
	if albedo == null:
		return null
	var decal := Decal.new()
	decal.name = "Decal_" + decal_name
	decal.set_meta("catalog_name", decal_name)
	decal.size = Vector3(entry["size_x"], entry["depth"], entry["size_z"])
	decal.texture_albedo = albedo
	var maps: String = entry["maps"]
	if maps.contains("normal"):
		decal.texture_normal = AssetLibrary.texture("decals/%s/%s_%s_normal.png" % [set_id, set_id, decal_name])
	if maps.contains("orm"):
		decal.texture_orm = AssetLibrary.texture("decals/%s/%s_%s_orm.png" % [set_id, set_id, decal_name])
	decal.modulate = Color.html(entry["modulate"])
	decal.albedo_mix = entry["albedo_mix"]
	decal.transform = Transform3D(orientation, center)
	add_child(decal)
	return decal


## The nozzle texture covers the whole nacelle, so the engine glow becomes a thin emissive disc in the exhaust mouth: the cylinder's top
## cap (+y before the nacelle is rotated 90 degrees about x, which sends +y to +z, the rear).
func _exhaust_disc() -> MeshInstance3D:
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 0.5
	disc_mesh.bottom_radius = 0.5
	disc_mesh.height = 0.04
	var disc := MeshInstance3D.new()
	disc.mesh = disc_mesh
	disc.material_override = _glow_material
	disc.position = Vector3(0.0, 1.19, 0.0)
	return disc


## Bare metal (metallic 1) reflects the sky, which is black space, so the textured interior would render near-black. One interior
## probe over the ship, captured once, gives metal something to reflect.
func _build_reflection_probe(layout: InteriorLayout) -> void:
	var height := layout.ceiling_y - layout.floor_y
	var probe := ReflectionProbe.new()
	probe.size = Vector3(8.0, height + 0.5, 20.0)
	probe.position = Vector3(0.0, layout.floor_y + height * 0.5, 1.8)
	probe.interior = true
	probe.box_projection = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 0.6
	add_child(probe)


func _slab(area: Rect2, bottom_y: float, top_y: float, material: Material) -> void:
	var instance := _box_instance(Vector3(area.size.x, top_y - bottom_y, area.size.y), material)
	instance.position = Vector3(area.position.x + area.size.x * 0.5, (bottom_y + top_y) * 0.5, area.position.y + area.size.y * 0.5)
	add_child(instance)


func _wall_box(x_min: float, x_max: float, z_min: float, z_max: float, y_min: float, y_max: float, material: Material = null) -> void:
	var first_z := minf(z_min, z_max)
	var last_z := maxf(z_min, z_max)
	var instance := _box_instance(Vector3(x_max - x_min, y_max - y_min, last_z - first_z), material if material != null else _wall_material)
	instance.position = Vector3((x_min + x_max) * 0.5, (y_min + y_max) * 0.5, (first_z + last_z) * 0.5)
	add_child(instance)


func _box_instance(size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	return instance


static func _screen(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.008, 0.018, 0.026)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.roughness = 0.24
	material.metallic = 0.1
	return material


static func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


static func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material
