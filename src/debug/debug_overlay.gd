class_name DebugOverlay
extends CanvasLayer
## Top-left text: fps, speed, position, gear, who is flying. Reads state, owns none.

var ship: Ship
var _label := Label.new()


func _ready() -> void:
	_label.position = Vector2(12, 8)
	_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)


func _process(_delta: float) -> void:
	if ship == null:
		return
	var state := ship.state
	var source_text := "PARKED" if ship.controller.is_parked() else String(ship.controller.current_source.source_id)
	_label.text = "fps %d\nspeed %.1f m/s\ngear %d   pilot: %s\npos %.0f %.0f %.0f\norigin offset %.0f %.0f %.0f\n\nWASD thrust/strafe  Space/C up/down  Q/E roll\nmouse or arrows pitch/yaw  Shift boost  X brake\n[ ] gear   Esc release mouse" % [
		Engine.get_frames_per_second(), state.speed(), state.gear + 1, source_text,
		state.position.x, state.position.y, state.position.z,
		ship.render_origin.x, ship.render_origin.y, ship.render_origin.z]
