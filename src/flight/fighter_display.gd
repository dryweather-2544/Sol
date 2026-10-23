extends Control
## One of the fighter cockpit's two readout screens, drawn in 2D inside a SubViewport (FighterCockpit puts the picture on a plate).
## Styled after the mothership's own screens (the CC0 "Sci-Fi interface textures" on its machine screens): dark navy glass, a chamfered
## frame, hex cells, cyan lines, and segmented ring and bar gauges, in the cockpit's cyan and amber. The static parts (frame, hex cells,
## header) are drawn once on a backdrop child; the live gauges are redrawn every frame; scanlines and glare sit on top.
## Left (SYSTEMS): hull ring, fuel bar, guns, and the gear selector. Right (FLIGHT): the radar, then speed, altitude and target.

enum Kind { SYSTEMS, FLIGHT }

const NAVY := Color(0.024, 0.05, 0.095)
const CYAN := Color(0.255, 0.784, 0.753)
const ICE := Color(0.62, 0.84, 1.0)
const AMBER := Color(0.788, 0.541, 0.271)
const ALERT := Color(0.86, 0.27, 0.18)
const WARP_PINK := Color(1.0, 0.5, 0.95)
const SIZE := 512.0
const GEAR_SHORT := ["PRC", "CMB", "CRZ", "WRP"]
const SCREEN_DIR := "res://assets/sol/screens/"
const RADAR_AT := Vector2(116.0, 64.0)
const RADAR_SIZE := Vector2(280.0, 280.0)

var kind := Kind.SYSTEMS
## The colour of the screen's frame, gauges and text (FighterDef.accent); cyan unless the craft sets its own.
var accent := CYAN:
	set(value):
		accent = value
		if _backdrop != null:
			_backdrop.queue_redraw()
var font: Font
## Fed every frame by FighterCockpit.
var hull := 1.0
var fuel := 1.0
## 0 = master switch SAFE, 1 = live but not in the combat gear (standby), 2 = armed.
var guns_state := 0
var radar_range_text := "RNG 2.5 km"
## The pilot's pointer (the cockpit reticle) on this screen, in screen pixels (x < 0: not on it), and the control under it.
var pointer := Vector2(-1.0, -1.0)
var hover_id := ""
var gear := 1
var gear_name := "COMBAT"
var speed_text := "0 m/s"
var speed_fraction := 0.0
var altitude_text := "--"
var target_text := "NONE"
var warning := false

var _clock := 0.0
var _backdrop := Control.new()
var _overlay := Control.new()
var _cursor := Control.new()
var _flash_left := 0.0


func _init() -> void:
	name = "FighterDisplay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(SIZE, SIZE)
	_backdrop.name = "Backdrop"
	_backdrop.show_behind_parent = true
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.size = Vector2(SIZE, SIZE)
	_backdrop.draw.connect(_draw_backdrop)
	add_child(_backdrop)
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.size = Vector2(SIZE, SIZE)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_cursor.name = "Cursor"
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.size = Vector2(SIZE, SIZE)
	_cursor.draw.connect(_draw_cursor)
	add_child(_cursor)


## The right screen's radar sits inside the display, under the scanlines.
func attach_radar(radar: FighterRadar) -> void:
	radar.position = RADAR_AT
	radar.size = RADAR_SIZE # a Control in a SubViewport draws nothing until it is given a size
	add_child(radar)
	move_child(_overlay, -1)
	move_child(_cursor, -1)


func _process(delta: float) -> void:
	var view := get_viewport() as SubViewport
	if view != null and view.render_target_update_mode == SubViewport.UPDATE_DISABLED:
		return # the cockpit is not on screen
	_clock += delta
	_flash_left = maxf(0.0, _flash_left - delta)
	queue_redraw()
	_cursor.queue_redraw()


# --- controls the pilot can click -------------------------------------------------------------------------------

## The clickable controls of a screen: id -> area in screen pixels. Left: the guns master switch and the four gears. Right: the radar (range).
static func regions(screen_kind: Kind) -> Dictionary:
	var result := {"switch": Rect2(Vector2(404.0, 14.0), Vector2(86.0, 62.0))} # the corner hex cells: focus the other screen
	if screen_kind == Kind.SYSTEMS:
		result["guns"] = Rect2(Vector2(116.0, 372.0), Vector2(290.0, 36.0))
		for index in GEAR_SHORT.size():
			result["gear%d" % index] = Rect2(Vector2(36.0 + float(index) * 116.0, 434.0), Vector2(108.0, 50.0))
	else:
		result["radar"] = Rect2(RADAR_AT, RADAR_SIZE)
	return result


## The id of the control under `point` (screen pixels), or "" when there is none.
static func hit_test(screen_kind: Kind, point: Vector2) -> String:
	var areas := regions(screen_kind)
	for id in areas:
		if (areas[id] as Rect2).has_point(point):
			return id
	return ""


## A click landed on this control: it flashes.
func flash(_id: String) -> void:
	_flash_left = 0.22


# --- pure helpers (tested) ---------------------------------------------------------------------------------------

## The outline of the screen: a rectangle with two cut corners (top-left and bottom-right), like the ship's interface graphics.
static func frame_points(inset: float) -> PackedVector2Array:
	var low := inset
	var high := SIZE - inset
	var cut := 44.0
	var small := 16.0
	return PackedVector2Array([
		Vector2(low + cut, low), Vector2(high - small, low), Vector2(high, low + small), Vector2(high, high - cut),
		Vector2(high - cut, high), Vector2(low + small, high), Vector2(low, high - small), Vector2(low, low + cut)])


static func hex_points(centre: Vector2, radius: float, pointy: bool = true) -> PackedVector2Array:
	var points := PackedVector2Array()
	var start := -PI * 0.5 if pointy else 0.0
	for corner in 6:
		var angle := start + corner * TAU / 6.0
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points


## How many of `count` gauge segments are lit for a 0..1 value: any value above zero lights at least one; full lights all.
static func segments_lit(value: float, count: int) -> int:
	if value <= 0.0:
		return 0
	return clampi(ceili(value * float(count) - 0.001), 1, count)


## Cyan when healthy, amber when low, red when nearly gone.
static func level_color(value: float) -> Color:
	if value > 0.6:
		return CYAN
	if value > 0.3:
		return AMBER
	return ALERT


## level_color, with the healthy colour swapped for this screen's accent.
func _level_colour(value: float) -> Color:
	var colour := level_color(value)
	return accent if colour == CYAN else colour


# --- static layers -----------------------------------------------------------------------------------------------

func _draw_backdrop() -> void:
	var outer := frame_points(4.0)
	_backdrop.draw_colored_polygon(outer, Color(NAVY, 0.97))
	var texture := _screen_texture()
	if texture != null: # the mothership's own screen graphic, faint behind the gauges
		var rect := Rect2(Vector2(SIZE * 0.5 - 148.0, 36.0), Vector2(297.0, 440.0)) if kind == Kind.SYSTEMS else Rect2(Vector2(21.0, 64.0), Vector2(470.0, 275.0))
		_backdrop.draw_texture_rect(texture, rect, false, Color(ICE, 0.12))
	var radius := 21.0
	var step_x := radius * sqrt(3.0)
	var step_y := radius * 1.5
	for row in range(-1, int(SIZE / step_y) + 2):
		for column in range(-1, int(SIZE / step_x) + 2):
			var centre := Vector2(column * step_x + (step_x * 0.5 if row % 2 != 0 else 0.0), row * step_y)
			if centre.x < 30.0 or centre.x > SIZE - 30.0 or centre.y < 30.0 or centre.y > SIZE - 30.0:
				continue
			var cell := hex_points(centre, radius - 1.5)
			cell.append(cell[0])
			_backdrop.draw_polyline(cell, Color(accent, 0.07), 1.0)
	var closed := outer.duplicate()
	closed.append(outer[0])
	_backdrop.draw_polyline(closed, Color(accent, 0.9), 3.0, true)
	var inner := frame_points(14.0)
	inner.append(inner[0])
	_backdrop.draw_polyline(inner, Color(accent, 0.28), 1.5, true)
	# the blue header strip of the ship's screens, with the screen's name
	var strip := PackedVector2Array([Vector2(36.0, 22.0), Vector2(380.0, 22.0), Vector2(352.0, 58.0), Vector2(36.0, 58.0)])
	_backdrop.draw_colored_polygon(strip, Color(0.16, 0.34, 0.78, 0.6))
	_backdrop.draw_line(Vector2(36.0, 22.0), Vector2(380.0, 22.0), Color(ICE, 0.9), 2.0)
	var f := font if font != null else ThemeDB.fallback_font
	_backdrop.draw_string(f, Vector2(52.0, 49.0), "SYSTEMS" if kind == Kind.SYSTEMS else "FLIGHT", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24, Color(0.92, 0.97, 1.0))
	_backdrop.draw_string(f, Vector2(412.0, 73.0), "SWAP", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(ICE, 0.75))
	# two hex cells in the top corner
	for cell_at in [Vector2(452.0, 44.0), Vector2(422.0, 34.0)]:
		var hex := hex_points(cell_at, 17.0)
		_backdrop.draw_colored_polygon(hex, Color(ICE, 0.14))
		hex.append(hex[0])
		_backdrop.draw_polyline(hex, Color(ICE, 0.7), 1.5, true)


func _draw_overlay() -> void:
	var y := 8.0
	while y < SIZE - 8.0:
		_overlay.draw_line(Vector2(8.0, y), Vector2(SIZE - 8.0, y), Color(0.0, 0.0, 0.0, 0.13), 1.0)
		y += 4.0
	_overlay.draw_colored_polygon(PackedVector2Array([Vector2(10.0, 10.0), Vector2(250.0, 10.0), Vector2(10.0, 240.0)]), Color(1.0, 1.0, 1.0, 0.035))


## The pointer and the highlight of the control under it, above everything (the radar, the scanlines).
func _draw_cursor() -> void:
	if hover_id != "":
		var areas := regions(kind)
		if areas.has(hover_id):
			var area := (areas[hover_id] as Rect2).grow(5.0)
			_cursor.draw_rect(area, Color(ICE, 0.12 + (0.3 if _flash_left > 0.0 else 0.0)))
			_cursor.draw_rect(area, Color(ICE, 0.95), false, 3.0)
	if pointer.x >= 0.0:
		_cursor.draw_circle(pointer, 5.0, Color(1.0, 1.0, 1.0, 0.95))
		_cursor.draw_arc(pointer, 12.0, 0.0, TAU, 24, Color(ICE, 0.95), 2.0, true)


func _screen_texture() -> Texture2D:
	var path := SCREEN_DIR + ("scr_interface_3.png" if kind == Kind.SYSTEMS else "scr_interface_1.png")
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


# --- live layer --------------------------------------------------------------------------------------------------

func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_clock * 8.0)
	var frame_colour := Color(ALERT, 0.5 + 0.5 * pulse) if warning else Color(accent, 0.0)
	if warning: # a red edge that breathes while hull or fuel is low
		var outer := frame_points(4.0)
		outer.append(outer[0])
		draw_polyline(outer, frame_colour, 4.0, true)
	if kind == Kind.SYSTEMS:
		_draw_systems(pulse)
	else:
		_draw_flight(pulse)


func _text(text: String, at: Vector2, size_px: int, colour: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var f := font if font != null else ThemeDB.fallback_font
	draw_string(f, at, text, align, width, size_px, colour)


func _status_chip(text: String, colour: Color) -> void:
	_text(text, Vector2(186.0, 48.0), 20, colour, HORIZONTAL_ALIGNMENT_RIGHT, 160.0)


func _slanted(rect: Rect2, slant: float) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position + Vector2(slant, 0.0), rect.position + Vector2(rect.size.x, 0.0),
		rect.position + Vector2(rect.size.x - slant, rect.size.y), rect.position + Vector2(0.0, rect.size.y)])


func _segment_bar(rect: Rect2, value: float, colour: Color, count: int) -> void:
	var gap := 3.0
	var cell_width := (rect.size.x - gap * float(count - 1)) / float(count)
	var lit := segments_lit(value, count)
	for index in count:
		var cell := Rect2(rect.position + Vector2(float(index) * (cell_width + gap), 0.0), Vector2(cell_width, rect.size.y))
		draw_rect(cell, colour if index < lit else Color(accent, 0.12))


func _draw_systems(pulse: float) -> void:
	_status_chip("WARNING" if warning else "NOMINAL", Color(ALERT, 0.6 + 0.4 * pulse) if warning else Color(0.85, 0.95, 1.0, 0.9))
	# hull: a 270 degree ring of 20 segments, gap at the bottom
	var centre := Vector2(256.0, 190.0)
	var radius := 104.0
	var colour := _level_colour(hull)
	if hull <= 0.3:
		colour = Color(ALERT, 0.55 + 0.45 * pulse)
	var count := 20
	var start := deg_to_rad(135.0)
	var segment := deg_to_rad(270.0) / float(count)
	var lit := segments_lit(hull, count)
	for index in count:
		var from_angle := start + float(index) * segment + deg_to_rad(1.4)
		var to_angle := start + float(index + 1) * segment - deg_to_rad(1.4)
		draw_arc(centre, radius, from_angle, to_angle, 6, colour if index < lit else Color(accent, 0.13), 22.0, true)
	draw_arc(centre, radius - 22.0, 0.0, TAU, 56, Color(accent, 0.35), 1.5, true)
	draw_arc(centre, radius + 17.0, start, start + deg_to_rad(270.0), 40, Color(accent, 0.35), 1.5, true)
	_text("HULL", centre + Vector2(-60.0, -34.0), 20, Color(accent, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 120.0)
	_text("%d" % roundi(hull * 100.0), centre + Vector2(-90.0, 28.0), 62, Color(0.93, 0.98, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 180.0)
	_text("% INTEGRITY", centre + Vector2(-80.0, 56.0), 16, Color(accent, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 160.0)
	# fuel
	_text("FUEL", Vector2(36.0, 352.0), 20, Color(AMBER, 0.95))
	_segment_bar(Rect2(Vector2(116.0, 334.0), Vector2(290.0, 24.0)), fuel, AMBER if fuel > 0.15 else Color(ALERT, 0.6 + 0.4 * pulse), 20)
	_text("%d%%" % roundi(fuel * 100.0), Vector2(380.0, 354.0), 22, Color(0.93, 0.98, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, 100.0)
	# guns
	_text("GUNS", Vector2(36.0, 398.0), 20, Color(accent, 0.9))
	var chip: Rect2 = regions(Kind.SYSTEMS)["guns"]
	if guns_state == 2:
		draw_colored_polygon(_slanted(chip, 14.0), Color(AMBER, 0.92))
		_text("ARMED", chip.position + Vector2(0.0, 27.0), 24, NAVY, HORIZONTAL_ALIGNMENT_CENTER, chip.size.x)
	else:
		var outline := _slanted(chip, 14.0)
		draw_colored_polygon(outline, Color(accent, 0.1))
		outline.append(outline[0])
		draw_polyline(outline, Color(accent, 0.5), 1.5, true)
		var standby := guns_state == 1 # switched on, but the guns only work in the combat gear
		_text("STANDBY" if standby else "SAFE", chip.position + Vector2(0.0, 27.0), 24, Color(AMBER, 0.75) if standby else Color(accent, 0.6), HORIZONTAL_ALIGNMENT_CENTER, chip.size.x)
	# gear selector
	for index in GEAR_SHORT.size():
		var cell := Rect2(Vector2(36.0 + float(index) * 116.0, 434.0), Vector2(108.0, 50.0))
		var active := index == gear
		var cell_colour := WARP_PINK if index == 3 else ICE
		var shape := _slanted(cell, 12.0)
		if active:
			draw_colored_polygon(shape, Color(cell_colour, 0.88))
			_text(GEAR_SHORT[index], cell.position + Vector2(0.0, 34.0), 26, NAVY, HORIZONTAL_ALIGNMENT_CENTER, cell.size.x)
		else:
			draw_colored_polygon(shape, Color(cell_colour, 0.09))
			shape.append(shape[0])
			draw_polyline(shape, Color(cell_colour, 0.4), 1.5, true)
			_text(GEAR_SHORT[index], cell.position + Vector2(0.0, 34.0), 26, Color(cell_colour, 0.55), HORIZONTAL_ALIGNMENT_CENTER, cell.size.x)


func _draw_flight(pulse: float) -> void:
	_status_chip(gear_name, Color(WARP_PINK, 0.95) if gear == 3 else Color(AMBER, 0.95))
	var rows := [["SPD", speed_text, Color(0.93, 0.98, 1.0)], ["ALT", altitude_text, Color(0.93, 0.98, 1.0)], ["TGT", target_text, AMBER if target_text != "NONE" else Color(accent, 0.5)]]
	for index in rows.size():
		var baseline := 382.0 + float(index) * 38.0
		draw_line(Vector2(36.0, baseline - 31.0), Vector2(476.0, baseline - 31.0), Color(accent, 0.28), 1.5)
		_text(rows[index][0], Vector2(40.0, baseline - 4.0), 22, Color(accent, 0.85))
		var value_colour: Color = rows[index][2]
		if index == 2 and target_text != "NONE":
			value_colour = Color(AMBER, 0.7 + 0.3 * pulse)
		_text(rows[index][1], Vector2(176.0, baseline), 30, value_colour, HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	_segment_bar(Rect2(Vector2(40.0, 474.0), Vector2(432.0, 14.0)), speed_fraction, accent, 28)
	_text(radar_range_text, Vector2(200.0, 338.0), 20, Color(accent, 0.8), HORIZONTAL_ALIGNMENT_RIGHT, 200.0)
