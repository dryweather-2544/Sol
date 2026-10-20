class_name EntryEffects
extends CanvasLayer
## A purple exposure wash for the Rodina-style entry fire. The trailer's entry frames are dominated
## by large orange/purple blocks over a violet scene, not a neutral orange glow. This layer sits
## below the HUD and is driven by the flight model's actual atmosphere resistance.

const MAX_ALPHA := 0.30

var ship: Ship
var _rect := ColorRect.new()
var _strength := 0.0


func _init() -> void:
	layer = 0
	name = "EntryEffects"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.color = Color(0.20, 0.025, 0.26, 0.0)
	add_child(_rect)


static func intensity_for(resistance: float) -> float:
	if not VisualStyle.is_rodina():
		return 0.0
	return clampf(resistance / ShipDamage.ENTRY_DAMAGE_START, 0.0, 1.0)


func _process(delta: float) -> void:
	if ship == null or get_tree().paused:
		_rect.visible = false
		return
	var target := intensity_for(ship.state.atmosphere_resistance) * MAX_ALPHA
	# Ease the tint in/out; the particles have their own fade, and a hard screen tint would flash.
	_strength = move_toward(_strength, target, delta * 0.20)
	_rect.visible = _strength > 0.001
	_rect.color.a = _strength
