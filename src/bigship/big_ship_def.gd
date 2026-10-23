extends RefCounted
## One of the five big ships: its name and numbers, and the hull model it wears (git-ignored, see ATTRIBUTION.md) and how that model sits.
## No class_name: scripts reach it through a preload, so it needs no class cache refresh.

var id := ""
var display_name := ""
var ship_class := ""
var blurb := ""
## res:// path of the hull model (.gltf or .glb), read from disk when needed. Missing file: a plain stand-in hull is drawn.
var hull_path := ""
## The hull's longest horizontal extent in metres (the model is scaled so it measures this).
var hull_extent := 60.0
## Turns the model so its nose points to -z: PI for models that face +z.
var hull_yaw := 0.0
var crew := 0
var cargo_tons := 0
var speed_class := ""
## Colour of the ship in the menu.
var accent := Color.WHITE
## The licence line the hull's author asks for (empty when the model has no licence to credit).
var credit := ""
## Engine nozzles in ship space (nose -z, tail +z, centred on the hull, hull_extent metres long) and each one's radius, measured from the hull model
## (tools/engine_detect.py). The flames of the flown ship start here.
var engines: Array[Vector3] = []
var engine_radii: Array[float] = []
