class_name PoiDefinition
extends RefCounted
## The kinds of point of interest and their rules. Placeholder-visual types for M5.

enum Type { WRECK, BEACON, OUTPOST }

const TYPE_WEIGHTS := {Type.WRECK: 5, Type.BEACON: 3, Type.OUTPOST: 2}
## How close (metres) a person on foot must get to discover it (scaled from Rodina's 100 m, PRC-05).
const DISCOVER_RADIUS := 120.0
## Visible light beam height by type (0 = none: wrecks must be found by flying/walking over them).
const BEAM_HEIGHT := {Type.WRECK: 0.0, Type.BEACON: 600.0, Type.OUTPOST: 300.0}
const BEAM_COLOR := {Type.WRECK: Color(1.0, 0.5, 0.2), Type.BEACON: Color(0.3, 0.8, 1.0), Type.OUTPOST: Color(0.4, 1.0, 0.5)}
const TYPE_NAMES := {Type.WRECK: "Wreck", Type.BEACON: "Beacon", Type.OUTPOST: "Outpost"}


static func pick_type(roll: float) -> int:
	var total := 0
	for weight in TYPE_WEIGHTS.values():
		total += weight
	var target := roll * total
	var running := 0.0
	for type in TYPE_WEIGHTS:
		running += TYPE_WEIGHTS[type]
		if target < running:
			return type
	return Type.WRECK
