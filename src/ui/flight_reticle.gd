class_name FlightReticle
extends Control
## Small, original flight reticle: centre brackets, a velocity tick and a soft outer ring.
## It is deliberately understated so the cockpit geometry and planet stay readable.

var _velocity := Vector2.ZERO
var _active := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_state(active: bool, velocity: Vector2) -> void:
	_active = active
	_velocity = velocity
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var centre := size * 0.5
	var cyan := Color(0.42, 0.86, 1.0, 0.48)
	var dim := Color(0.42, 0.86, 1.0, 0.20)
	draw_arc(centre, 30.0, 0.0, TAU, 48, dim, 1.0)
	draw_arc(centre, 3.0, 0.0, TAU, 12, cyan, 1.2)
	# Four corner brackets.
	for direction in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var corner: Vector2 = centre + direction * 23.0
		draw_line(corner, corner + Vector2(-direction.x * 8.0, 0), cyan, 1.4)
		draw_line(corner, corner + Vector2(0, -direction.y * 8.0), cyan, 1.4)
	# Velocity tick: a short line away from the centre, clamped to the ring.
	if _velocity.length() > 0.5:
		var tick := _velocity.limit_length(26.0)
		draw_line(centre + tick * 0.35, centre + tick, Color(1.0, 0.72, 0.36, 0.55), 1.6)
