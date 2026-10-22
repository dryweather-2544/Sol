class_name FighterDef
extends RefCounted
## One small single-seat fighter: which model it uses and how it handles, shoots and soaks damage compared with the
## baseline hostile ship. Numbers are Sol's own (Rodina has no such ship); Ship.configure_fighter applies them.

enum Role { INTERCEPTOR, FIGHTER, HEAVY, ACE }

## Length of the player's ship in metres, the yardstick the player-ship tuning (support points) was written for.
const REFERENCE_SIZE := 20.0

var id: StringName
var display_name := ""
var role := Role.FIGHTER
## res:// path of the .glb. The model is optional: without it the fighter falls back to the placeholder ship shape.
var model_path := ""
## Longest dimension of the model in metres (the importer scales every model to this).
var size := 11.0
## Multipliers on the player ship's combat gear: top speed, and turn rate.
var speed_scale := 1.0
var turn_scale := 1.0
## Incoming damage is divided by this: 2.0 takes twice the hits.
var toughness := 1.0
var gun_damage := 0.012
var gun_rate := 4.0
## AI: how close it likes to sit, where it opens fire, and how far off its aim is (radians).
var preferred_range := 450.0
var fire_range := 1100.0
var aim_error := 0.03
## The pilot's eye in the cockpit view and the engine nozzles, both ship-local (nose -z, tail +z) and measured from the model.
var cockpit := Vector3.ZERO
var engines: Array[Vector3] = []
## Only used by the placeholder fallback.
var hull_color := Color(0.75, 0.15, 0.12)


func hit_radius() -> float:
	return maxf(3.0, size * 0.55)


## Where shots leave, ship-local (nose points to -z).
func muzzle_offset() -> Vector3:
	return Vector3(0.0, 0.0, -size * 0.45)


func barrel_x() -> float:
	return size * 0.1


## Damage per second if every shot lands: a rough way to compare fighters.
func nominal_dps() -> float:
	return gun_damage * gun_rate


static func role_name(role_value: int) -> String:
	match role_value:
		Role.INTERCEPTOR:
			return "interceptor"
		Role.HEAVY:
			return "heavy"
		Role.ACE:
			return "ace"
		_:
			return "fighter"
