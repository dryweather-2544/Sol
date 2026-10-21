class_name FlightReticle
extends Control
## Minimal cyan flight reticle matching the reference's small central ring/cross. Pure drawing; it
## has no input or gameplay authority.

var tint := Color(0.55, 0.88, 1.0, 0.9)
## Screen positions of visible hostile targets (filled by DebugOverlay; package-free array).
var target_positions := PackedVector2Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(56, 56)
	pivot_offset = size * 0.5


func _draw() -> void:
	var c := size * 0.5
	draw_arc(c, 14.0, 0.0, TAU, 32, tint, 1.2)
	draw_circle(c, 1.4, tint)
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var d := Vector2(cos(angle), sin(angle))
		draw_line(c + d * 18.0, c + d * 24.0, tint, 1.2)
	var enemy := Color(1.0, 0.42, 0.24, 0.95)
	for target in target_positions:
		var local := target - global_position
		var half := 18.0
		var step := 7.0
		# Four open corner brackets, the standard flight target marker.
		draw_line(local + Vector2(-half, -half), local + Vector2(-half + step, -half), enemy, 1.5)
		draw_line(local + Vector2(-half, -half), local + Vector2(-half, -half + step), enemy, 1.5)
		draw_line(local + Vector2(half, -half), local + Vector2(half - step, -half), enemy, 1.5)
		draw_line(local + Vector2(half, -half), local + Vector2(half, -half + step), enemy, 1.5)
		draw_line(local + Vector2(-half, half), local + Vector2(-half + step, half), enemy, 1.5)
		draw_line(local + Vector2(-half, half), local + Vector2(-half, half - step), enemy, 1.5)
		draw_line(local + Vector2(half, half), local + Vector2(half - step, half), enemy, 1.5)
		draw_line(local + Vector2(half, half), local + Vector2(half, half - step), enemy, 1.5)
