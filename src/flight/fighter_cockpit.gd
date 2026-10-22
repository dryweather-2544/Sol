class_name FighterCockpit
extends Node3D
## The pilot's cockpit of a small fighter, built from boxes and screens (no model), after the owner's reference picture: an A-frame
## canopy (two big struts leaning in to a header with lamp housings, two slim struts down to the dash), a solid tub (dash, side
## consoles, sills, floor, roof, back wall) with no gaps, and one tilted instrument panel low in front of the pilot that holds everything
## flown by: a hex radar with the hull strip above it, fuel and speed pillars either side, two small readout screens, a gear screen,
## and button banks. Colours are the project's cockpit palette, dark. It sits at the pilot's eye (Ship puts it at FighterDef.cockpit)
## and is drawn only on its own render layer, which only the fighter's cockpit camera includes. While that camera is the current one
## the cockpit is shown and the fighter's hull model hidden (the eye is inside the hull); every other view is unchanged.

const LAYER_MASK := 1 << 9 ## render layer 10; ADR 0013 uses layers 2 to 5
const GRAPHITE := Color("101316")
const WARM_METAL := Color("34332e")
const INTERIOR_GREY := Color("1f2224")
const AMBER := Color("c98a45")
const CYAN := Color("41c8c0")
const GEAR_NAMES := ["PRECISION", "COMBAT", "CRUISE", "WARP"]
const RADAR_RANGE := 2500.0
const FONT_PATH := "res://assets/sol/fonts/Orbitron-Variable.ttf"
## The instrument panel: where it sits (cockpit space, eye at the origin, nose -z) and how far it is tipped up toward the eye.
const PANEL_POSITION := Vector3(0.0, -0.52, -1.0)
const PANEL_TILT_DEGREES := 28.0
## The canopy's key points (cockpit space), shared so the struts, header and sills all meet exactly.
const SILL_Y := -0.45
const FRONT_Z := -1.2
const HEADER_Z := -1.6
const HEADER_Y := 1.4
const SIDE_X := 1.25
## The seat model (Chair_01 as a .glb in metres: facing +z, cushion top at y 0.83, base at y 0.35, armrests and controls left off): turned
## round and set so the cushion is just under the pilot's hips with its base on the floor.
const SEAT_MODEL := "res://assets/cockpit/pilot_seat.glb"
const SEAT_SCALE := 1.0
const SEAT_POSITION := Vector3(0.0, -1.45, -0.08)
## The nose: from the front of the dash it narrows to a point, like a fighter's, instead of ending in a flat square cowl.
## The X-Wing cockpit (converted to a .glb, git-ignored, see ATTRIBUTION.md): when it is present it replaces the canopy, tub, nose, seat and
## console buttons with the model. It is built in metres with the nose along +z; XWING_EYE is the pilot's eye in the model's own space, so
## the model is turned round and shifted until that point is the cockpit's origin. The live readouts stay, as a smaller panel on its console.
const XWING_MODEL := "res://assets/cockpit/xwing_cockpit.glb"
const XWING_EYE := Vector3(0.0, 0.12, -0.05)
## The model has a slanted side panel either side of the pilot's knees, each with an orange-outlined square. The readouts sit on those squares.
## Each entry: the square's centre and the panel's four corners (metres, model space, nose along +z; the pilot's left is model +x).
const XWING_LEFT_SQUARE := Vector3(0.2705, -0.2845, 0.4065)
const XWING_LEFT_PANEL := [Vector3(0.34, -0.39, 0.23), Vector3(0.20, -0.37, 0.44), Vector3(0.25, -0.12, 0.56), Vector3(0.34, -0.28, 0.31)]
const XWING_RIGHT_SQUARE := Vector3(-0.2425, -0.2865, 0.4085)
const XWING_RIGHT_PANEL := [Vector3(-0.31, -0.39, 0.23), Vector3(-0.17, -0.37, 0.45), Vector3(-0.23, -0.12, 0.56), Vector3(-0.31, -0.28, 0.31)]
## The pilot's seat in the X-Wing: Chair_01 scaled down (the model's pilot sits low in a small cockpit) so its base stands on the floor
## (model y -0.92) and its headrest is at head height. It has no armrests or joysticks (they would cover the readout squares).
const XWING_SEAT_SCALE := 0.74
const XWING_SEAT_POSITION := Vector3(0.0, -1.43, 0.12) # the headrest top sits ~0.13 m under the eye, and the seat just behind it
## Each readout plate is designed 0.4 by 0.4 and shrunk to this scale (so about 16 cm square, just over the 12 by 15 cm square).
const XWING_PLATE_SCALE := 0.4
static var _glb_cache := {} ## res:// path -> the scene read from it (null when it could not be read)
const NOSE_BACK_Y := -0.3
const NOSE_TIP := Vector3(0.0, -0.2, -4.4) # higher than the dash's sight line, so the whole wedge shows above the panel
## Struts: where the big and the slim ones meet the header (x), so the windscreen is wide and the view out stays open.
const BIG_STRUT_TOP_X := 0.5
const SLIM_STRUT_TOP_X := 0.28
## Buttons are flat, elongated pads laid on the surface (size: along, across, thickness), not blocks standing off it.
const CONSOLE_TOP_Y := -0.52
const BUTTON_SIZE := Vector3(0.075, 0.022, 0.006)

var ship: Ship
var _font: Font
var _hull_label: Label3D
var _systems_label: Label3D ## left screen: hull, fuel, guns
var _flight_label: Label3D ## right screen: speed, altitude, target
var _gear_label: Label3D ## the small screen under the hex
var _bars := {} ## name -> MeshInstance3D (anchored at its bottom edge)
var _warn_lights: Array[MeshInstance3D] = []
var _stick: Node3D
var _radar_view := SubViewport.new()
var _radar := FighterRadar.new()
## The X-Wing cockpit's two plates are 2D screens (FighterDisplay) drawn in their own viewports, only updated while the cockpit is shown.
const Display := preload("res://src/flight/fighter_display.gd") # preloaded, so it needs no class cache refresh
var _left_display: Display
var _right_display: Display
var _display_views: Array[SubViewport] = []
var _display_quads: Array[MeshInstance3D] = [] ## the quad each display is shown on, same order as _display_views
## The pilot's pointer: main.gd turns it on while the right mouse button is held, and it is the cockpit camera's reticle.
var pointer_enabled := false
var _hover_display: Display
var _hover_id := ""
var _pointed_index := -1 ## the screen the reticle is on while the right button is held (-1: none)
var _focus_index := -1 ## the screen the pilot has focused: the view is zoomed on it and the mouse moves a pointer over it
var _focus_pointer := Vector2(256.0, 256.0)
## How much of the view's height a focused screen fills.
const FOCUS_FILL := 0.62
## Screen pixels the pointer moves per mouse pixel.
const FOCUS_SPEED := 1.1
const RADAR_RANGES := [1000.0, 2500.0, 5000.0, 10000.0]
var _time := 0.0
## Where the build helpers add things (null = the cockpit itself; the panel while it is being built).
var _group: Node3D
var _panel: Node3D


func _init() -> void:
	name = "FighterCockpit"
	visible = false


func setup(owner_ship: Ship, def: FighterDef) -> void:
	ship = owner_ship
	scale = Vector3.ONE * clampf(def.size / 11.0, 0.75, 1.4)
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	_group = null
	var xwing := _build_xwing()
	if not xwing:
		_build_shell()
		_build_tub()
		_build_nose()
	if xwing:
		_build_xwing_readouts()
		_build_seat(XWING_SEAT_SCALE, XWING_SEAT_POSITION)
	else:
		_panel = Node3D.new()
		_panel.name = "InstrumentPanel"
		_panel.position = PANEL_POSITION
		_panel.rotation_degrees = Vector3(-PANEL_TILT_DEGREES, 0.0, 0.0) # its face (+z) tips up toward the eye
		add_child(_panel)
		_group = _panel
		_build_panel()
		_group = null
		_build_button_banks()
		_build_stick(Vector3(0.0, -0.8, -0.5), true)
		_build_seat()
	_build_lights()


func _process(delta: float) -> void:
	if ship == null:
		return
	var active := ship.cockpit_camera != null and ship.cockpit_camera.current and ship.state.hull > 0.0
	visible = active
	var hull_model := ship.get_node_or_null("FighterModel") as Node3D
	if hull_model != null:
		hull_model.visible = not active # the eye is inside the hull: its model would only get in the way
	_radar_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	for view in _display_views:
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if not active:
		_focus_index = -1
	_update_pointer(active and (pointer_enabled or _focus_index >= 0))
	if not active:
		return
	_time += delta
	var state := ship.state
	var speed := state.velocity.length()
	var gear := clampi(state.gear, 0, GEAR_NAMES.size() - 1)
	var gear_max := ship.tuning.gear_max_speed[gear] if gear <= PilotCommand.GEAR_COMBAT else speed
	_set_bar("hull", state.hull)
	_set_bar("fuel", state.fuel)
	_set_bar("speed", speed / maxf(gear_max, 1.0))
	var altitude := "--" if is_inf(state.altitude_above_ground) else ("%d m" % roundi(state.altitude_above_ground) if state.altitude_above_ground < 10000.0 else "%.1f km" % (state.altitude_above_ground / 1000.0))
	var contacts: Array = []
	if ship.radar_contacts.is_valid():
		for contact in ship.radar_contacts.call():
			var offset: Vector3 = contact
			if Vector2(offset.x, offset.z).length() < _radar.range_m * 1.5:
				contacts.append(offset)
	_radar.contacts = contacts
	var nearest := INF
	for contact in contacts:
		var offset: Vector3 = contact
		nearest = minf(nearest, offset.length())
	var warning := state.hull < 0.35 or state.fuel < 0.15
	if _left_display != null:
		_feed_display(_left_display, state, speed, gear, altitude, nearest, warning, speed / maxf(gear_max, 1.0))
		_feed_display(_right_display, state, speed, gear, altitude, nearest, warning, speed / maxf(gear_max, 1.0))
	if _hull_label != null:
		_feed_labels(state, speed, gear, altitude, nearest)
	for light in _warn_lights:
		var material := light.material_override as StandardMaterial3D
		material.emission_energy_multiplier = (1.0 + sin(_time * 9.0)) * 1.2 if warning else 0.15
	var command := ship.last_command
	if _stick != null: # the X-Wing cockpit has no stick
		_stick.rotation.x = lerpf(_stick.rotation.x, -command.turn.x * 0.35, 0.2)
		_stick.rotation.z = lerpf(_stick.rotation.z, -command.turn.z * 0.35, 0.2)


## The fixed-label panel of the home-built cockpit.
func _feed_labels(state: ShipState, speed: float, gear: int, altitude: String, nearest: float) -> void:
	_hull_label.text = "HULL INTEGRITY %d%%" % roundi(state.hull * 100.0)
	_systems_label.text = "HULL %d%%\nFUEL %d%%\nGUNS %s" % [roundi(state.hull * 100.0), roundi(state.fuel * 100.0), "ARMED" if Ship.gear_allows_fire(state.gear) else "SAFE"] # guns work in the combat gear only
	_flight_label.text = "SPD %s\nALT %s\n%s" % [_speed_text(speed), altitude, "NO TARGET" if is_inf(nearest) else "TGT %d m" % roundi(nearest)]
	_gear_label.text = GEAR_NAMES[gear]


func _feed_display(display: Display, state: ShipState, speed: float, gear: int, altitude: String, nearest: float, warning: bool, speed_fraction: float) -> void:
	display.hull = state.hull
	display.fuel = state.fuel
	display.guns_state = 0 if ship.guns_safe else (2 if Ship.gear_allows_fire(state.gear) else 1) # guns work in the combat gear only
	display.radar_range_text = "RNG " + _distance_text(_radar.range_m)
	display.gear = gear
	display.gear_name = GEAR_NAMES[gear]
	display.speed_text = _speed_text(speed)
	display.speed_fraction = speed_fraction
	display.altitude_text = altitude
	display.target_text = "NONE" if is_inf(nearest) else _distance_text(nearest)
	display.warning = warning


static func _distance_text(metres: float) -> String:
	return "%d m" % roundi(metres) if metres < 1000.0 else "%.1f km" % (metres / 1000.0)


static func _speed_text(speed: float) -> String:
	return "%d m/s" % roundi(speed) if speed < 1000.0 else "%.1f km/s" % (speed / 1000.0)


# --- building ---------------------------------------------------------------------------------------------------

## The canopy, as in the reference: two big struts from the sill corners leaning in to the header, two slim struts from the header
## down to the dash centre, a header with two lamp housings, side rails and rear posts, and a roof. Every beam starts and ends on
## another part, so there are no loose ends.
func _build_shell() -> void:
	var frame := _material(GRAPHITE, 0.6, 0.3)
	var trim := _material(WARM_METAL, 0.6, 0.3)
	var lamp_glow := _emissive(Color(1.0, 0.95, 0.85), 0.9)
	_box(Vector3(1.2, 0.09, 0.16), frame, Vector3(0.0, HEADER_Y + 0.03, HEADER_Z)) # header, slim
	_box(Vector3(1.2, 0.03, 0.4), frame, Vector3(0.0, HEADER_Y + 0.08, HEADER_Z + 0.2)) # a small visor over it: the only roof there is
	for side in [-1.0, 1.0]:
		_beam(Vector3(side * SIDE_X, SILL_Y, FRONT_Z), Vector3(side * BIG_STRUT_TOP_X, HEADER_Y, HEADER_Z), 0.06, frame) # big strut
		_beam(Vector3(side * SLIM_STRUT_TOP_X, HEADER_Y - 0.04, HEADER_Z), NOSE_TIP + Vector3(side * 0.04, 0.03, 0.4), 0.03, frame) # slim strut: from the header, angled forward down to the tip of the nose
		_beam(Vector3(side * SIDE_X, SILL_Y, FRONT_Z), Vector3(side * SIDE_X, SILL_Y, 0.9), 0.08, trim) # sill
		_beam(Vector3(side * SIDE_X, SILL_Y, 0.9), Vector3(side * SIDE_X, 1.0, 0.9), 0.06, frame) # rear post
		_beam(Vector3(side * BIG_STRUT_TOP_X, HEADER_Y, HEADER_Z), Vector3(side * SIDE_X, 1.0, 0.9), 0.05, frame) # roof rail
		_box(Vector3(0.16, 0.05, 0.14), trim, Vector3(side * 0.14, HEADER_Y - 0.06, HEADER_Z + 0.06)) # lamp housing under the header, flat and long
		_box(Vector3(0.12, 0.01, 0.08), lamp_glow, Vector3(side * 0.14, HEADER_Y - 0.09, HEADER_Z + 0.06)) # its lamp
	# two cross beams tie the roof rails together (no roof panel: the glass stays open above the pilot)
	var mid_t := (-0.5 - HEADER_Z) / (0.9 - HEADER_Z)
	var mid_x := lerpf(BIG_STRUT_TOP_X, SIDE_X, mid_t)
	var mid_y := lerpf(HEADER_Y, 1.0, mid_t)
	_beam(Vector3(-mid_x, mid_y, -0.5), Vector3(mid_x, mid_y, -0.5), 0.04, frame)
	_beam(Vector3(-SIDE_X, 1.0, 0.9), Vector3(SIDE_X, 1.0, 0.9), 0.05, frame)


## The closed tub the pilot sits in: floor, back wall, side walls, the front cowl, and the dash body under the instrument panel.
func _build_tub() -> void:
	var grey := _material(INTERIOR_GREY, 0.7, 0.15)
	var dark := _material(GRAPHITE, 0.6, 0.3)
	_box(Vector3(3.5, 0.05, 3.2), dark, Vector3(0.0, -1.05, -0.1)) # floor
	_box(Vector3(3.5, 2.2, 0.06), dark, Vector3(0.0, 0.0, 1.0)) # back wall
	for side in [-1.0, 1.0]:
		_box(Vector3(0.08, SILL_Y + 1.05, 2.2), grey, Vector3(side * (SIDE_X + 0.02), (SILL_Y - 1.05) * 0.5, -0.1)) # side wall, up to the sill
	_box(Vector3(2.5, 0.8, 0.4), dark, Vector3(0.0, -0.68, -1.35)) # front cowl, up to the dash top (y -0.28): only as wide as the cockpit, the nose carries on from it
	_box(Vector3(3.3, 0.23, 1.6), dark, Vector3(0.0, -0.915, -0.7)) # dash body, under the instrument panel
	for side in [-1.0, 1.0]:
		_box(Vector3(0.5, 0.16, 1.4), grey, Vector3(side * 1.02, CONSOLE_TOP_Y - 0.08, -0.55)) # side console, from the panel's edge to the side wall


## The pointed nose ahead of the dash: a flat wedge that starts as wide as the cockpit, slopes gently down and narrows to a tip, with
## a raised spine along its middle. The world is visible down both sides of it.
func _build_nose() -> void:
	var dark := _material(GRAPHITE, 0.6, 0.3)
	dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	var trim := _material(WARM_METAL, 0.6, 0.3)
	var floor_y := -1.05
	var left := Vector3(-SIDE_X, NOSE_BACK_Y, FRONT_Z)
	var right := Vector3(SIDE_X, NOSE_BACK_Y, FRONT_Z)
	var left_low := Vector3(-SIDE_X, floor_y, FRONT_Z)
	var right_low := Vector3(SIDE_X, floor_y, FRONT_Z)
	var tip_low := Vector3(0.0, floor_y, NOSE_TIP.z)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for triangle in [[left, right, NOSE_TIP], [left, NOSE_TIP, tip_low], [left, tip_low, left_low], [right, tip_low, NOSE_TIP], [right, right_low, tip_low]]:
		for vertex in triangle:
			surface.add_vertex(vertex)
	surface.generate_normals()
	_add(surface.commit(), dark, Vector3.ZERO)
	_beam(Vector3(0.0, NOSE_BACK_Y + 0.02, FRONT_Z), NOSE_TIP + Vector3(0.0, 0.03, 0.0), 0.06, trim) # the spine
	for side in [-1.0, 1.0]:
		_beam(Vector3(side * SIDE_X, NOSE_BACK_Y, FRONT_Z), NOSE_TIP, 0.03, trim) # edge trim down each side


## The instrument panel (the helpers add to _panel; coordinates are on its face, x right, y up, z out toward the pilot). Everything
## flown by sits here, low and close together, so it is all in view without turning the head.
func _build_panel() -> void:
	var metal := _material(WARM_METAL, 0.6, 0.3)
	var dark := _material(GRAPHITE, 0.6, 0.3)
	var screen := _emissive(Color(0.03, 0.12, 0.14), 0.5)
	_box(Vector3(1.96, 0.64, 0.06), dark, Vector3(0.0, 0.0, -0.03)) # the panel itself, solid right out to the consoles
	# the hex radar in its bezel: transparent corners so the screen is a hexagon
	var bezel := CylinderMesh.new()
	bezel.top_radius = 0.205
	bezel.bottom_radius = 0.205
	bezel.height = 0.05
	bezel.radial_segments = 6
	_add(bezel, metal, Vector3(0.0, 0.0, 0.025), Vector3(90.0, 0.0, 0.0))
	_radar_view.size = Vector2i(256, 256)
	_radar_view.transparent_bg = true
	_radar_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_radar_view)
	_radar_view.add_child(_radar)
	_radar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_radar.size = Vector2(_radar_view.size) # a Control in a SubViewport starts at size 0 and draws nothing until it is given one
	var radar_material := StandardMaterial3D.new()
	radar_material.albedo_texture = _radar_view.get_texture()
	radar_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	radar_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_add(_quad(Vector2(0.4, 0.4)), radar_material, Vector3(0.0, 0.0, 0.052))
	# the hull-integrity strip above it
	_box(Vector3(0.44, 0.07, 0.04), dark, Vector3(0.0, 0.265, 0.02))
	_hull_label = _label("HULL INTEGRITY 100%", Vector3(0.0, 0.275, 0.042), Vector3.ZERO, 22, CYAN)
	_add_bar("hull", Vector3(0.0, 0.245, 0.044), 0.38, 0.012, true, CYAN)
	# fuel (left) and speed (right) pillars either side of the hex, a lamp on top and a column of buttons under each
	var button_colors := [Color("55c070"), Color("e0c040"), Color("c8483c")]
	for entry in [[-1.0, "fuel", "F"], [1.0, "speed", "S"]]:
		var side: float = entry[0]
		_box(Vector3(0.1, 0.34, 0.05), metal, Vector3(side * 0.31, 0.04, 0.025))
		_add_bar(entry[1], Vector3(side * 0.31, 0.01, 0.052), 0.22, 0.03, false, CYAN)
		_label(entry[2], Vector3(side * 0.31, 0.15, 0.053), Vector3.ZERO, 30, AMBER)
		_warn_lights.append(_box(Vector3(0.09, 0.02, 0.03), _emissive(AMBER, 0.15), Vector3(side * 0.31, 0.235, 0.015)))
		for row in 3:
			_box(BUTTON_SIZE, _emissive(button_colors[row], 0.55), Vector3(side * 0.31, -0.2 - row * 0.04, BUTTON_SIZE.z * 0.5))
	# the two small readout screens, either side of the pillars, and the gear screen under the hex
	for side in [-1.0, 1.0]:
		var at := Vector3(side * 0.6, 0.03, 0.0)
		_box(Vector3(0.32, 0.17, 0.03), dark, at + Vector3(0.0, 0.0, 0.015)) # long, not square
		_add(_quad(Vector2(0.29, 0.14)), screen, at + Vector3(0.0, 0.0, 0.032))
		var text := _label("", at + Vector3(-0.13, 0.0, 0.035), Vector3.ZERO, 24, CYAN, null, true)
		if side < 0.0:
			_systems_label = text
		else:
			_flight_label = text
	_box(Vector3(0.3, 0.09, 0.03), dark, Vector3(0.0, -0.255, 0.015))
	_add(_quad(Vector2(0.27, 0.07)), screen, Vector3(0.0, -0.255, 0.032))
	_gear_label = _label("COMBAT", Vector3(0.0, -0.255, 0.035), Vector3.ZERO, 26, AMBER)
	# button banks at the panel's two ends: two columns of flat, elongated pads
	for side in [-1.0, 1.0]:
		for column in 2:
			for row in 7:
				var color: Color = [AMBER, CYAN, Color("55c070"), Color("c8483c")][(row + column) % 4]
				_box(BUTTON_SIZE, _emissive(color, 0.55), Vector3(side * (0.8 + column * 0.09), 0.17 - row * 0.057, BUTTON_SIZE.z * 0.5))


## Button banks on the two side consoles, on a holder tipped up and turned toward the pilot.
func _build_button_banks() -> void:
	var colors := [AMBER, CYAN, Color("55c070"), Color("c8483c")]
	for side in [-1.0, 1.0]:
		for column in 2:
			for row in 6:
				var color: Color = colors[(row + column) % colors.size()]
				var pad := Vector3(0.12, BUTTON_SIZE.z, 0.05) # long across the console, thin, laid flat on its top
				_box(pad, _emissive(color, 0.55), Vector3(side * (1.04 + column * 0.15), CONSOLE_TOP_Y + pad.y * 0.5, -0.95 + row * 0.16))


func _build_stick(base_at: Vector3, full: bool) -> void:
	var grey := _material(INTERIOR_GREY, 0.7, 0.15)
	var dark := _material(GRAPHITE, 0.6, 0.3)
	if full:
		_box(Vector3(0.4, 0.2, 1.0), grey, Vector3(0.0, -0.92, -0.35)) # centre tunnel, from the dash body back to the seat
	var base := CylinderMesh.new()
	base.top_radius = 0.05
	base.bottom_radius = 0.07
	base.height = 0.05
	_add(base, dark, base_at)
	_stick = Node3D.new()
	_stick.position = base_at + Vector3(0.0, 0.02, 0.0)
	add_child(_stick)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.016
	shaft.bottom_radius = 0.018
	shaft.height = 0.2
	_add(shaft, dark, Vector3(0.0, 0.1, 0.0), Vector3.ZERO, _stick)
	_box(Vector3(0.05, 0.09, 0.06), dark, Vector3(0.0, 0.24, 0.0), Vector3.ZERO, _stick) # the grip
	_box(Vector3(0.016, 0.016, 0.016), _emissive(Color("c8483c"), 0.8), Vector3(0.0, 0.3, -0.03), Vector3.ZERO, _stick) # the trigger button
	if full:
		_box(Vector3(0.05, 0.05, 0.22), dark, Vector3(-0.42, -0.78, -0.62)) # the throttle lever, ahead of the seat's armrest


## The model's own hull (left out: it is a 14 m exterior that would block the view ahead) used to close the cockpit in. This fills what it
## covered, in model space under the model: a wall down each side from the canopy's lower rail, the floor, a bulkhead under the front of the
## console, and a flat pointed nose running on ahead of it, so no sky or planet shows through below the frame.
func _build_xwing_fill(model: Node3D) -> void:
	var material := _material(Color(0.2, 0.25, 0.25), 0.85, 0.35)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var bottom := -0.93
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		_fill_quad(surface, Vector3(side * 0.62, -0.22, -0.32), Vector3(side * 0.40, -0.13, 1.74), Vector3(side * 0.40, bottom, 1.74), Vector3(side * 0.62, bottom, -0.32))
	_fill_quad(surface, Vector3(-0.62, bottom, -0.32), Vector3(0.62, bottom, -0.32), Vector3(0.62, bottom, 1.74), Vector3(-0.62, bottom, 1.74))
	_fill_quad(surface, Vector3(-0.40, -0.2, 1.74), Vector3(0.40, -0.2, 1.74), Vector3(0.40, bottom, 1.74), Vector3(-0.40, bottom, 1.74))
	for vertex in [Vector3(-0.42, -0.2, 1.74), Vector3(0.42, -0.2, 1.74), Vector3(0.0, -0.45, 5.8)]:
		surface.add_vertex(vertex)
	surface.generate_normals()
	var node := MeshInstance3D.new()
	node.name = "XWingFill"
	node.mesh = surface.commit()
	node.material_override = material
	model.add_child(node)


func _fill_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for vertex in [a, b, c, a, c, d]:
		surface.add_vertex(vertex)


## A model-space point (metres, nose +z) as a point in the cockpit's space: the model is turned round and shifted so XWING_EYE is the origin.
func _from_model(point: Vector3) -> Vector3:
	return Vector3(-point.x + XWING_EYE.x, point.y - XWING_EYE.y, -point.z + XWING_EYE.z)


## A readout plate lying on one of the model's slanted side panels, centred on its square and facing the pilot. Designed 0.4 by 0.4
## (x right, y up, z out of the panel) and scaled down by XWING_PLATE_SCALE.
func _make_plate(square: Vector3, corners: Array) -> Node3D:
	var centre := _from_model(square)
	var first := _from_model(corners[0])
	var normal := (_from_model(corners[1]) - first).cross(_from_model(corners[2]) - first).normalized()
	if normal.dot(-centre) < 0.0:
		normal = -normal # the face points at the eye, which is the origin
	var up := (Vector3.UP - normal * normal.dot(Vector3.UP)).normalized()
	var right := up.cross(normal)
	var plate := Node3D.new()
	plate.transform = Transform3D(Basis(right, up, normal).scaled(Vector3.ONE * XWING_PLATE_SCALE), centre + normal * 0.004)
	add_child(plate)
	return plate


## The live readouts on the two squares, as 2D screens (FighterDisplay) in the style of the mothership's own. Left (the pilot's left): hull,
## fuel, guns and the gear. Right: the hex radar, speed, altitude and target.
func _build_xwing_readouts() -> void:
	var dark := _material(GRAPHITE, 0.6, 0.3)
	_group = _make_plate(XWING_LEFT_SQUARE, XWING_LEFT_PANEL)
	_box(Vector3(0.4, 0.4, 0.01), dark, Vector3(0.0, 0.0, 0.005))
	_left_display = _build_display(Display.Kind.SYSTEMS)
	_group = _make_plate(XWING_RIGHT_SQUARE, XWING_RIGHT_PANEL)
	_box(Vector3(0.4, 0.4, 0.01), dark, Vector3(0.0, 0.0, 0.005))
	_right_display = _build_display(Display.Kind.FLIGHT)
	_right_display.attach_radar(_radar)
	_group = null


## One 512 px screen in its own viewport, shown on a quad lying on the current plate (_group).
func _build_display(kind: Display.Kind) -> Display:
	var view := SubViewport.new()
	view.size = Vector2i(1024, 1024) # drawn at twice the 512 px layout, so text stays sharp when the pilot zooms in
	view.size_2d_override = Vector2i(512, 512)
	view.size_2d_override_stretch = true
	view.transparent_bg = true
	view.msaa_2d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(view)
	_display_views.append(view)
	var display := Display.new()
	display.kind = kind
	display.font = _font
	view.add_child(display)
	var material := StandardMaterial3D.new()
	material.albedo_texture = view.get_texture()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_display_quads.append(_add(_quad(Vector2(0.385, 0.385)), material, Vector3(0.0, 0.0, 0.0115)))
	return display


# --- the pointer: the reticle clicks the screens ---------------------------------------------------------------

## True while the reticle is on a control of a cockpit screen (the guns must not fire then: the click selects it).
func is_pointing() -> bool:
	return _hover_id != ""


## The screen under the reticle while the right button is held (-1: none). Letting go of the button on a screen focuses it.
func pointed_screen() -> int:
	return _pointed_index


func in_focus() -> bool:
	return _focus_index >= 0


## Zooms in on the screen the reticle is on; the mouse then moves a pointer over it.
func begin_focus() -> void:
	if _pointed_index < 0:
		return
	var display: Display = [_left_display, _right_display][_pointed_index]
	_focus_pointer = display.pointer if display.pointer.x >= 0.0 else Vector2(256.0, 256.0)
	_focus_index = _pointed_index


func end_focus() -> void:
	_focus_index = -1


func move_focus_pointer(relative: Vector2) -> void:
	_focus_pointer = (_focus_pointer + relative * FOCUS_SPEED).clamp(Vector2.ZERO, Vector2(512.0, 512.0))


## Focuses the other screen (the pointer starts in its middle). Returns what to tell the pilot.
func swap_focus() -> String:
	if _focus_index < 0:
		return ""
	_focus_index = 1 - _focus_index
	_focus_pointer = Vector2(256.0, 256.0)
	return "Screen: %s" % ("SYSTEMS" if _focus_index == 0 else "FLIGHT")


## The control under the focus pointer ("" when it is over empty glass).
func focus_hover() -> String:
	return _hover_id if _focus_index >= 0 else ""


## Yaw and pitch (radians, the cockpit camera's own Euler angles) that put the focused screen in the middle of the view.
func focus_look() -> Vector2:
	if _focus_index < 0 or _focus_index >= _display_quads.size() or ship == null or ship.cockpit_camera == null:
		return Vector2.ZERO
	var target := ship.to_local(_display_quads[_focus_index].global_position) - ship.cockpit_camera.position
	if target.length() < 1e-4:
		return Vector2.ZERO
	return Vector2(atan2(-target.x, -target.z), asin(clampf(target.y / target.length(), -1.0, 1.0)))


## The field of view (degrees) at which the focused screen fills FOCUS_FILL of the view's height.
func focus_fov() -> float:
	if _focus_index < 0 or _focus_index >= _display_quads.size() or ship == null or ship.cockpit_camera == null:
		return 60.0
	var quad := _display_quads[_focus_index]
	var width := 0.385 * quad.global_transform.basis.get_scale().x
	var distance := maxf(ship.cockpit_camera.global_position.distance_to(quad.global_position), 0.05)
	return clampf(rad_to_deg(2.0 * atan(width * 0.5 / distance)) / FOCUS_FILL, 12.0, 60.0)


func _update_pointer(enabled: bool) -> void:
	var displays := [_left_display, _right_display]
	var camera := ship.cockpit_camera if ship != null else null
	_hover_display = null
	_hover_id = ""
	_pointed_index = -1
	for index in displays.size():
		var display: Display = displays[index]
		if display == null:
			continue
		var point := Vector2(-1.0, -1.0)
		var id := ""
		if _focus_index >= 0:
			if index == _focus_index:
				point = _focus_pointer # the mouse drives the pointer while a screen is focused
				id = Display.hit_test(display.kind, point)
		elif enabled and camera != null:
			var hit: Variant = _pick(index, camera)
			if hit != null:
				point = hit
				_pointed_index = index
				id = Display.hit_test(display.kind, point)
		display.pointer = point
		display.hover_id = id
		if id != "":
			_hover_display = display
			_hover_id = id


## Where the camera's centre ray meets screen `index`, in the screen's 512 px (null when it misses the plate).
func _pick(index: int, camera: Camera3D) -> Variant:
	if index >= _display_quads.size():
		return null
	var to_quad := _display_quads[index].global_transform.affine_inverse()
	var origin := to_quad * camera.global_position
	var direction := to_quad.basis * (-camera.global_basis.z)
	if absf(direction.z) < 1e-6:
		return null
	var along := -origin.z / direction.z
	if along <= 0.0:
		return null
	var hit := origin + direction * along
	var side := 0.385 # the quad's size in its own space
	if absf(hit.x) > side * 0.5 or absf(hit.y) > side * 0.5:
		return null
	return Vector2((hit.x / side + 0.5) * 512.0, (0.5 - hit.y / side) * 512.0)


## Clicks the control under the pointer. Returns what to tell the pilot ("" when nothing was under it).
func activate() -> String:
	if _hover_display == null or ship == null:
		return ""
	var id := _hover_id
	_hover_display.flash(id)
	if id == "switch":
		return swap_focus()
	if id.begins_with("gear"):
		var wanted := int(id.substr(4))
		if wanted > ship.state.allowed_gear:
			return "%s gear is not available here" % String(GEAR_NAMES[wanted]).capitalize()
		ship.state.selected_gear = wanted
		return "Gear: %s" % GEAR_NAMES[wanted]
	if id == "guns":
		ship.guns_safe = not ship.guns_safe
		return "Guns SAFE" if ship.guns_safe else "Guns live (they fire in the COMBAT gear)"
	if id == "radar":
		var next := (RADAR_RANGES.find(_radar.range_m) + 1) % RADAR_RANGES.size()
		_radar.range_m = RADAR_RANGES[next]
		return "Radar range %s" % _distance_text(_radar.range_m)
	return ""


## Loads the X-Wing cockpit and puts it around the pilot. False (nothing built) when the model file is not there.
func _build_xwing() -> bool:
	var model := _load_glb(XWING_MODEL)
	if model == null:
		return false
	model.name = "XWingCockpit"
	model.rotation_degrees = Vector3(0.0, 180.0, 0.0) # the model's nose is +z, the cockpit looks down -z
	model.position = Vector3(XWING_EYE.x, -XWING_EYE.y, XWING_EYE.z) # (turned round, so x and z swap sign): the eye lands on the origin
	add_child(model)
	_build_xwing_fill(model)
	_set_layers(model)
	return true


## Reads a .glb straight from disk (no editor import needed) and returns a copy of its scene, or null when it is missing. The scene read
## is kept and each call gets a duplicate of it, so meshes and textures are only loaded once.
func _load_glb(res_path: String) -> Node3D:
	if not _glb_cache.has(res_path):
		var root: Node3D = null
		var path := ProjectSettings.globalize_path(res_path)
		if FileAccess.file_exists(path):
			var document := GLTFDocument.new()
			var state := GLTFState.new()
			if document.append_from_file(path, state) == OK:
				root = document.generate_scene(state) as Node3D
			if root == null:
				push_warning("FighterCockpit: could not read %s" % res_path)
		_glb_cache[res_path] = root
	var cached: Node3D = _glb_cache[res_path]
	return cached.duplicate() as Node3D if cached != null else null


## Puts everything under a node on the cockpit's own render layer, so only the cockpit camera draws it.
func _set_layers(root: Node3D) -> void:
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		geometry.layers = LAYER_MASK
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The pilot's seat: the downloaded Chair_01 model when it is present (git-ignored, see ATTRIBUTION.md), else a plain block seat.
func _build_seat(model_scale: float = SEAT_SCALE, at: Vector3 = SEAT_POSITION) -> void:
	var seat := _load_glb(SEAT_MODEL)
	if seat != null:
		seat.name = "PilotSeat"
		seat.rotation_degrees = Vector3(0.0, 180.0, 0.0) # the model faces +z: turned round to face the windscreen
		seat.position = at
		seat.scale = Vector3.ONE * model_scale
		add_child(seat)
		_set_layers(seat)
		return
	_build_block_seat()


func _build_block_seat() -> void:
	var dark := _material(GRAPHITE, 0.6, 0.3)
	_box(Vector3(0.62, 0.95, 0.14), dark, Vector3(0.0, -0.3, 0.6))
	_box(Vector3(0.36, 0.26, 0.12), dark, Vector3(0.0, 0.3, 0.6))
	for side in [-1.0, 1.0]:
		_box(Vector3(0.1, 0.55, 0.18), _material(WARM_METAL, 0.6, 0.3), Vector3(side * 0.38, -0.4, 0.55))


func _build_lights() -> void:
	# Cockpit-layer lights only. The environment's ambient still reaches the dark surfaces, so the rig is a few soft, coloured pools
	# rather than one bright lamp: a cool overhead fill, a cyan wash from the screens, and amber from the side consoles.
	_add_light(Vector3(0.0, 0.5, -0.4), Color(0.8, 0.9, 1.0), 0.55, 3.0)
	_add_light(Vector3(0.0, -0.5, -0.75), CYAN, 0.6, 1.5)
	for side in [-1.0, 1.0]:
		_add_light(Vector3(side * 0.7, -0.45, -0.45), AMBER, 0.4, 1.2)


func _add_light(at: Vector3, color: Color, energy: float, light_range: float) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.omni_range = light_range
	light.light_energy = energy
	light.light_color = color
	light.light_specular = 0.8
	light.light_cull_mask = LAYER_MASK
	light.shadow_enabled = false
	add_child(light)


# --- helpers -----------------------------------------------------------------------------------------------------

func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func _quad(size: Vector2) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = size
	return quad


func _target() -> Node3D:
	return _group if _group != null else self


func _prepare(node: GeometryInstance3D) -> void:
	node.layers = LAYER_MASK
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add(mesh: Mesh, material: Material, position_value: Vector3, rotation_degrees_value: Vector3 = Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = position_value
	node.rotation_degrees = rotation_degrees_value
	_prepare(node)
	(parent if parent != null else _target()).add_child(node)
	return node


func _box(size: Vector3, material: Material, position_value: Vector3, rotation_degrees_value: Vector3 = Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(mesh, material, position_value, rotation_degrees_value, parent)


## A square beam of the given thickness from a to b.
func _beam(a: Vector3, b: Vector3, thickness: float, material: Material) -> MeshInstance3D:
	var direction := (b - a).normalized()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(thickness, thickness, a.distance_to(b))
	var node := _add(mesh, material, (a + b) * 0.5)
	node.basis = Basis.looking_at(direction, Vector3.RIGHT if absf(direction.y) > 0.99 else Vector3.UP)
	return node


## A bar gauge: a thin emissive box scaled by _set_bar. `horizontal` grows it sideways from its centre-left, else upward from its base.
func _add_bar(bar_name: String, position_value: Vector3, length: float, thickness: float, horizontal: bool, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(length, thickness, 0.012) if horizontal else Vector3(thickness, length, 0.012)
	var node := _add(mesh, _emissive(color, 1.2), position_value)
	node.set_meta("base", position_value)
	node.set_meta("length", length)
	node.set_meta("horizontal", horizontal)
	_bars[bar_name] = node


func _set_bar(bar_name: String, fraction: float) -> void:
	if not _bars.has(bar_name):
		return # the X-Wing cockpit's plates are 2D screens, with no bar nodes
	var node: MeshInstance3D = _bars[bar_name]
	var amount := clampf(fraction, 0.0, 1.0)
	var base: Vector3 = node.get_meta("base")
	var length: float = node.get_meta("length")
	if node.get_meta("horizontal"):
		node.scale = Vector3(maxf(amount, 0.001), 1.0, 1.0)
		node.position = base + Vector3(-length * 0.5 * (1.0 - amount), 0.0, 0.0)
	else:
		node.scale = Vector3(1.0, maxf(amount, 0.001), 1.0)
		node.position = base + Vector3(0.0, -length * 0.5 * (1.0 - amount), 0.0)


func _label(text_value: String, position_value: Vector3, rotation_degrees_value: Vector3, font_size_value: int, color: Color, parent: Node3D = null, align_left: bool = false) -> Label3D:
	var label := Label3D.new()
	label.text = text_value
	label.font_size = font_size_value
	label.pixel_size = 0.0012
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	if _font != null:
		label.font = _font
	label.position = position_value
	label.rotation_degrees = rotation_degrees_value
	_prepare(label)
	if align_left:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	(parent if parent != null else _target()).add_child(label)
	return label
