class_name DebugOverlay
extends CanvasLayer
## Top-left text: fps, speed, position, gear, who is flying. Reads state, owns none.

var ship: Ship
var terrain: PlanetTerrain
## Set while walking; the overlay then shows on-foot numbers instead of flight numbers.
var on_foot: OnFootController
var prompt_text := ""
var _label := Label.new()
var _prompt_label := Label.new()


func _ready() -> void:
	_label.position = Vector2(12, 8)
	_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	_prompt_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.position.y -= 120
	_prompt_label.add_theme_font_size_override("font_size", 26)
	_prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt_label.add_theme_constant_override("outline_size", 6)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_prompt_label)


func _process(_delta: float) -> void:
	if ship == null:
		return
	_prompt_label.text = prompt_text
	_prompt_label.position.x = get_viewport().get_visible_rect().size.x * 0.5 - _prompt_label.size.x * 0.5
	if on_foot != null:
		var body := on_foot.body
		_label.text = "fps %d   chunks %d\nON FOOT   speed %.1f m/s   %s\nheight above ground %.2f m%s\nWASD move  Shift run  Space jump  mouse look\nF board ship (when close)  Esc release mouse" % [
			Engine.get_frames_per_second(), terrain.displayed_chunk_count() if terrain != null else 0,
			body.velocity.length(), "grounded" if body.grounded else "airborne", body.height_above_ground,
			"   (slope too steep)" if body.blocked_by_slope else ""]
		return
	var state := ship.state
	var source_text := "PARKED" if ship.controller.is_parked() else String(ship.controller.current_source.source_id)
	var vertical_speed := 0.0
	var altitude_text := "-"
	if ship.planet != null:
		vertical_speed = state.velocity.dot(ship.planet.up_at(state.position))
		altitude_text = "%.0f m AGL" % state.altitude_above_ground if state.altitude_above_ground < 1.0e5 else "%.0f km AGL" % (state.altitude_above_ground / 1000.0)
	var gear_names := ["DOCK", "COMBAT", "CRUISE"]
	_label.text = "fps %d   chunks %d\nspeed %.1f m/s   vertical %.1f m/s\n%s   %s\ngear %s   pilot: %s\n%s\n\nWASD thrust/strafe  Space/C up/down  Q/E roll\nmouse or arrows pitch/yaw  Shift boost  X brake\n[ ] gear (cruise above 2 km)  Esc release mouse" % [
		Engine.get_frames_per_second(), terrain.displayed_chunk_count() if terrain != null else 0,
		state.speed(), vertical_speed, altitude_text, FlightRegime.label(state.regime),
		gear_names[state.gear], source_text, state.status_message]
