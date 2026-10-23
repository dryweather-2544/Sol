class_name FighterCockpitSpec
extends RefCounted
## The cockpit interiors a fighter's pilot can sit in: ten models (res://assets/cockpit/, git-ignored, see ATTRIBUTION.md) from the Open-Galaxy
## cockpit set, each turned into a .glb by tools/fbx_to_glb.py (metres, nose along +z, the pilot's left is +x, the exterior hull and the glass left
## out). FighterDef.cockpit_id names the one a fighter uses; FighterCockpit builds it around the pilot's eye and puts two live readout screens on it.
## Every number is in the model's own space, measured from its meshes with tools/fbx_probe.py and checked with tools/glb_preview.py.
## "xwing" is the first interior that was fitted (its readouts sit on two squares printed on the model's side panels, see FighterCockpit);
## the others place their readouts by `plate_x/y/z` and `plate_size`, floating just above the console.

const DIR := "res://assets/cockpit/"

var id: StringName
var display_name := ""
var model_path := ""
## The pilot's eye in the model's space.
var eye := Vector3.ZERO
## One readout plate's centre in the model's space for the pilot's left (+x); the right plate is its mirror image. Edge length of a plate in metres.
var plate_centre := Vector3.ZERO
var plate_size := 0.17
## What the removed hull used to cover, so no sky shows through below the frame: the floor and the wall's top (y), half the cockpit's width,
## and where the cabin starts and ends along z (the fill carries on from the front end as a flat pointed nose).
var floor_y := -1.0
var sill_y := -0.2
var half_width := 0.6
var back_z := -0.5
var front_z := 1.5
## True for the first interior, which has its own hand-fitted readout squares.
var legacy := false

static var _all := {}


static func all() -> Dictionary:
	if _all.is_empty():
		for spec in [
			_make(&"xwing", "Strike cockpit", "xwing_cockpit.glb", Vector3(0.0, 0.12, -0.05), Vector3(0.27, -0.28, 0.41), 0.16, -0.918, -0.22, 0.62, -0.32, 1.74, true),
			_make(&"xwing2", "Strike cockpit, wide canopy", "cockpit_xwing2.glb", Vector3(0.0, 0.116, -0.05), Vector3(0.27, -0.28, 0.42), 0.16, -1.018, -0.284, 0.62, -0.525, 1.52),
			_make(&"awing", "Needle cockpit", "cockpit_awing2.glb", Vector3(0.0, 0.08, 0.0), Vector3(0.3, -0.26, 0.75), 0.2, -0.509, -0.15, 0.6, -0.251, 2.585),
			_make(&"ewing", "Escort cockpit", "cockpit_ewing.glb", Vector3(0.0, 0.08, 0.0), Vector3(0.26, -0.3, 0.55), 0.17, -0.963, -0.2, 0.52, -0.405, 2.098),
			_make(&"bwing", "Gunship cockpit", "cockpit_bwing.glb", Vector3(0.0, 0.17, 0.0), Vector3(0.3, -0.18, 0.62), 0.2, -0.751, -0.223, 0.8, -0.424, 1.7),
			_make(&"cloudcar", "Skiff cockpit", "cockpit_cloudcar.glb", Vector3(0.0, 0.06, 0.0), Vector3(0.27, -0.3, 0.6), 0.17, -1.29, -0.21, 0.47, -0.525, 1.328),
			_make(&"z95", "Patrol cockpit", "cockpit_z95.glb", Vector3(0.0, 0.16, 0.0), Vector3(0.28, -0.26, 0.55), 0.17, -0.933, -0.168, 0.5, -0.413, 1.848),
			_make(&"ywing1", "Bomber cockpit", "cockpit_ywing1.glb", Vector3(0.0, 0.24, 0.0), Vector3(0.3, -0.18, 0.6), 0.19, -0.924, -0.18, 0.52, -0.546, 1.0),
			_make(&"ywing2", "Bomber cockpit, compact", "cockpit_ywing2.glb", Vector3(0.0, 0.1, 0.0), Vector3(0.28, -0.3, 0.55), 0.17, -0.702, -0.131, 0.6, -0.869, 0.723),
			_make(&"sentinel", "Heavy shuttle bridge", "cockpit_sentinel.glb", Vector3(0.0, -0.05, 0.0), Vector3(0.62, -0.28, 0.66), 0.26, -0.889, -0.219, 1.3, -0.948, 2.063),
		]:
			_all[spec.id] = spec
	return _all


## The interior with that id; the first one when the id is unknown.
static func by_id(spec_id: StringName) -> FighterCockpitSpec:
	var specs := all()
	return specs[spec_id] if specs.has(spec_id) else specs[&"xwing"]


static func _make(spec_id: StringName, label: String, file: String, eye_point: Vector3, plate_at: Vector3, plate_edge: float, floor_value: float, sill_value: float, half: float, back: float, front: float, is_legacy := false) -> FighterCockpitSpec:
	var spec := FighterCockpitSpec.new()
	spec.id = spec_id
	spec.display_name = label
	spec.model_path = DIR + file
	spec.eye = eye_point
	spec.plate_centre = plate_at
	spec.plate_size = plate_edge
	spec.floor_y = floor_value
	spec.sill_y = sill_value
	spec.half_width = half
	spec.back_z = back
	spec.front_z = front
	spec.legacy = is_legacy
	return spec
