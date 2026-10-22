class_name FighterRadar
extends Control
## The round radar drawn onto the fighter cockpit's hex screen (it lives in a SubViewport): range rings, a crosshair, a
## sweep line and one blip per hostile ship. Contacts are ship-local offsets: forward (-z) is up the screen, right is right.

const INK := Color(0.255, 0.784, 0.753) ## display cyan
const AMBER := Color(0.788, 0.541, 0.271) ## safety amber

var contacts: Array = []
var range_m := 2500.0
var _sweep := 0.0


## Where a ship-local offset lands on a radar of `radius` pixels covering `range_m` metres (contacts past the range sit on the rim).
static func to_screen(offset: Vector3, range_m_value: float, radius: float) -> Vector2:
	var flat := Vector2(offset.x, offset.z) / maxf(range_m_value, 1.0) * radius
	if flat.length() > radius:
		flat = flat.normalized() * radius
	return flat


func _process(delta: float) -> void:
	_sweep = fposmod(_sweep + delta * 1.6, TAU)
	queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.4
	# a hexagon (pointy top, like the cockpit's bezel) on a transparent background, so the screen's corners are not drawn
	var hex := PackedVector2Array()
	for corner in 6:
		var angle := -PI * 0.5 + corner * TAU / 6.0
		hex.append(centre + Vector2(cos(angle), sin(angle)) * minf(size.x, size.y) * 0.5)
	draw_colored_polygon(hex, Color(0.02, 0.07, 0.09))
	hex.append(hex[0])
	draw_polyline(hex, Color(INK, 0.8), 3.0)
	for fraction in [0.33, 0.66, 1.0]:
		draw_arc(centre, radius * fraction, 0.0, TAU, 64, Color(INK, 0.75), 2.0)
	draw_line(centre + Vector2(-radius, 0.0), centre + Vector2(radius, 0.0), Color(INK, 0.55), 1.5)
	draw_line(centre + Vector2(0.0, -radius), centre + Vector2(0.0, radius), Color(INK, 0.55), 1.5)
	draw_line(centre, centre + Vector2(cos(_sweep), sin(_sweep)) * radius, Color(INK, 0.45), 3.0)
	draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -9), centre + Vector2(7, 8), centre + Vector2(-7, 8)]), INK)
	for contact in contacts:
		var offset: Vector3 = contact
		var point := centre + to_screen(offset, range_m, radius)
		var beyond := Vector2(offset.x, offset.z).length() > range_m
		draw_circle(point, 4.0 if beyond else 6.0, Color(AMBER, 0.55 if beyond else 1.0))
		var height := clampf(offset.y / range_m, -1.0, 1.0) * radius * 0.25 # a tick up or down: above or below you
		draw_line(point, point + Vector2(0.0, -height), AMBER, 2.0)
