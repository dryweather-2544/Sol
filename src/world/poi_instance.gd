class_name PoiInstance
extends RefCounted
## One planned point of interest: just data. Nodes are created only while it is near the viewer.

var id: StringName
var type := PoiDefinition.Type.WRECK
var seed_value := 0
var generation_version := 1
## Where it sits on the terrain (planet frame, 64-bit).
var position: WorldPos
## Short readable name made from the seed, e.g. "Wreck 4F-221".
var display_name := ""


func data_hash() -> int:
	var hashed := SeedHash.combine(seed_value, type)
	hashed = SeedHash.combine(hashed, int(round(position.x * 1000.0)) & 0xFFFFFFFF)
	hashed = SeedHash.combine(hashed, int(round(position.y * 1000.0)) & 0xFFFFFFFF)
	hashed = SeedHash.combine(hashed, int(round(position.z * 1000.0)) & 0xFFFFFFFF)
	return SeedHash.combine(hashed, SeedHash.string_hash(String(id)))
