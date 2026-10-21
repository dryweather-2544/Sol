class_name SpeedEffects
extends CanvasLayer
## Rodina-style speed streak field. The trailer's COMBAT SPEED sequence shows large blue/white
## streaks past a small isolated ship. This is an additive screen layer above the 3D scene and
## below the HUD; it is presentation only and never touches flight state.

const MIN_SPEED := 300.0
const FULL_SPEED := 6000.0

var ship: Ship
var _rect := ColorRect.new()
var _material := ShaderMaterial.new()
var _time := 0.0


func _init() -> void:
	layer = 0
	name = "SpeedEffects"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material.shader = load("res://data/shaders/speed_streaks.gdshader")
	_rect.material = _material
	add_child(_rect)


## Pure gate used by tests and the live layer. Sol-style views and slow flight have no streaks.
static func intensity_for(speed: float, gear: int) -> float:
	# The labelled reference sequence is COMBAT SPEED. CRUISE has the olive exhaust trails, not this
	# blue-white field, so do not leave the two effects layered together.
	if not VisualStyle.is_rodina() or gear != PilotCommand.GEAR_COMBAT:
		return 0.0
	return smoothstep(MIN_SPEED, FULL_SPEED, speed) * 0.58


func _process(delta: float) -> void:
	_time += delta
	var paused := get_tree().paused
	var intensity := 0.0 if paused or ship == null or ship.state.entering_atmosphere or ship.state.in_atmosphere else intensity_for(ship.state.speed(), ship.state.gear)
	_rect.visible = intensity > 0.001
	if _rect.visible:
		_material.set_shader_parameter("intensity", intensity)
		_material.set_shader_parameter("time", _time)
