class_name GearHud
extends Control
## Rodina's gear HUD (MenuGen.HudGears1..4 and the gear notice, EGMenuHUD.lua:512-626, 980-995), drawn to match the
## owner's Rodina footage: four stepped tiles at the top right that grow with the gear and stack upward from the
## smallest (gear 1) at the bottom, and a "COMBAT SPEED" style banner at the top centre that appears whenever the
## gear changes (or is chosen with the clutch) and fades out.
## Tile states: gears at or below the current one are blue; the gear being shifted to is a brighter teal; gears above
## a pending downshift dim; the rest are not drawn. Pure drawing, no input.

const GEAR_NAMES := ["DOCKING SPEED", "COMBAT SPEED", "CRUISING SPEED", "LIMNAL DRIVE"]
const TILE_HEIGHT := 40.0
const TILE_GAP := 2.0
const TILE_WIDTHS := [43.0, 74.0, 105.0, 136.0]
const TILE_BEVEL := Vector2(26.0, 18.0) ## the cut lower-left corner: run, rise
const MARGIN := Vector2(15.0, 24.0) ## from the top right corner of the screen
const BANNER_SIZE := Vector2(410.0, 36.0)
const BANNER_TOP_FRACTION := 0.07
const BANNER_HOLD_SECONDS := 2.5
const BANNER_FADE_SECONDS := 1.0

const TILE_BLUE := Color(0.17, 0.37, 0.62, 0.95)
const TILE_TEAL := Color(0.30, 0.72, 0.72, 0.95)
const TILE_EDGE := Color(0.72, 0.86, 1.0, 0.95)
const BANNER_FILL := Color(0.40, 0.52, 0.64, 0.92)
const BANNER_EDGE := Color(0.72, 0.84, 0.94, 0.95)

var font: Font
var font_size := 15

var _gear := 0
var _pending := -1
var _shown_target := -1
var _banner_gear := -1
var _banner_age := 999.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Call every frame while flying. `gear` is the gear in effect, `pending` the clutch shift not yet committed (-1 none).
func apply(gear: int, pending: int, delta: float) -> void:
	_gear = clampi(gear, 0, GEAR_NAMES.size() - 1)
	_pending = pending
	var target := pending if pending >= 0 else gear
	if target != _shown_target:
		if _shown_target != -1:
			_banner_gear = clampi(target, 0, GEAR_NAMES.size() - 1)
			_banner_age = 0.0
		_shown_target = target
	_banner_age += delta
	queue_redraw()


func banner_alpha() -> float:
	if _banner_gear < 0:
		return 0.0
	if _banner_age <= BANNER_HOLD_SECONDS:
		return 1.0
	return clampf(1.0 - (_banner_age - BANNER_HOLD_SECONDS) / BANNER_FADE_SECONDS, 0.0, 1.0)


func _draw() -> void:
	_draw_tiles()
	_draw_banner()


func _draw_tiles() -> void:
	var right := size.x - MARGIN.x
	for index in GEAR_NAMES.size():
		var color := Color(0, 0, 0, 0)
		if _pending >= 0 and index == _pending and _pending > _gear:
			color = TILE_TEAL
		elif index <= _gear:
			color = TILE_BLUE
			if _pending >= 0 and _pending < _gear and index > _pending:
				color.a = 0.35 # a downshift is pending: the gears about to be left dim
		if color.a <= 0.0:
			continue
		var width: float = TILE_WIDTHS[index]
		var top := MARGIN.y + (GEAR_NAMES.size() - 1 - index) * (TILE_HEIGHT + TILE_GAP)
		_draw_tile(Vector2(right - width, top), width, color)


func _draw_tile(origin: Vector2, width: float, color: Color) -> void:
	var polygon := PackedVector2Array([
		origin, origin + Vector2(width, 0.0), origin + Vector2(width, TILE_HEIGHT),
		origin + Vector2(minf(TILE_BEVEL.x, width), TILE_HEIGHT), origin + Vector2(0.0, TILE_HEIGHT - TILE_BEVEL.y)])
	draw_colored_polygon(polygon, color)
	# Scanlines: the footage's tiles are faintly striped.
	var scan := Color(0.0, 0.0, 0.1, 0.16 * color.a)
	var y := 1.0
	while y < TILE_HEIGHT:
		var left := 0.0
		if y > TILE_HEIGHT - TILE_BEVEL.y:
			left = (y - (TILE_HEIGHT - TILE_BEVEL.y)) * minf(TILE_BEVEL.x, width) / TILE_BEVEL.y
		draw_line(origin + Vector2(left, y), origin + Vector2(width, y), scan, 1.0)
		y += 3.0
	var edge := TILE_EDGE
	edge.a *= color.a
	draw_polyline(PackedVector2Array([origin + Vector2(0.0, 0.0), origin + Vector2(0.0, TILE_HEIGHT - TILE_BEVEL.y),
		origin + Vector2(minf(TILE_BEVEL.x, width), TILE_HEIGHT)]), edge, 1.5)


func _draw_banner() -> void:
	var alpha := banner_alpha()
	if alpha <= 0.0 or _banner_gear < 0:
		return
	var origin := Vector2((size.x - BANNER_SIZE.x) * 0.5, size.y * BANNER_TOP_FRACTION)
	var fill := BANNER_FILL
	fill.a *= alpha
	draw_rect(Rect2(origin, BANNER_SIZE), fill)
	var highlight := Color(1.0, 1.0, 1.0, 0.12 * alpha)
	draw_rect(Rect2(origin, Vector2(BANNER_SIZE.x, BANNER_SIZE.y * 0.45)), highlight)
	var scan := Color(0.0, 0.0, 0.1, 0.10 * alpha)
	var y := 1.0
	while y < BANNER_SIZE.y:
		draw_line(origin + Vector2(0.0, y), origin + Vector2(BANNER_SIZE.x, y), scan, 1.0)
		y += 3.0
	var edge := BANNER_EDGE
	edge.a *= alpha
	draw_rect(Rect2(origin, BANNER_SIZE), edge, false, 1.0)
	var text_font: Font = font if font != null else ThemeDB.fallback_font
	var text_color := Color(0.94, 0.98, 1.0, alpha)
	var baseline := origin.y + BANNER_SIZE.y * 0.5 + text_font.get_ascent(font_size) * 0.5 - 1.0
	draw_string(text_font, Vector2(origin.x, baseline), GEAR_NAMES[_banner_gear], HORIZONTAL_ALIGNMENT_CENTER, BANNER_SIZE.x, font_size, text_color)
