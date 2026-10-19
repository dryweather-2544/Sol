class_name ShipExterior
extends RefCounted
## The player ship's outer hull and running gear: a heavy VTOL transport / gunship built around the walkable
## interior (InteriorLayout.player_ship). Ship-local metres, nose -z, right +x, up +y.
##
## Design (one vehicle, each part with a job):
## - Pressure hull: one chamfered loft from the visor face to the rear loading face, wrapping the six rooms
##   (rooms reach x +-3.2, ceiling slab top y 1.82, floor slab bottom y -1.02; the hull clears all of it).
##   Light ceramic upper hull, blue-grey structural band below a chine step, graphite belly.
## - Visor face: overhanging brow over a recessed, mullioned window in front of the cockpit glass wall, and a
##   sensor chin below it with the landing lights.
## - Propulsion: two tilt-engine pods on structural pylons at the rear flanks (intake forward, the nozzle aft),
##   plus two ventral lift-fan grilles under the cabin for VTOL balance.
## - Landing gear: four short oleo legs in gear sponsons; the foot pads sit exactly on ShipTuning.support_points.
## - Access: a two-leaf folding ramp hinged at the rear door sill. Stowed, the first leaf closes the doorway and the
##   second folds down over it; deployed, both lie in one line along the walkway slope. Two rams drive it.
## - Dorsal: heat-exchanger spine over cabin/engineering and the turret barbette above the turret room.
## All static parts are merged into one mesh (one draw call per material); only the ramp, rams and turret move.

enum Slot { HULL, PANEL, STRUCTURE, GRAPHITE, RECESS, SAFETY, METAL, LIGHT, NAV_PORT, NAV_STARBOARD, GLASS, EXHAUST_IDLE }

## Hull stations: z, roof y, roof half width, shoulder x/y, chine x/y (the widest line), lower side x/y, belly
## half width, belly y. The sides lean in above the chine and below it, so no face is a vertical slab.
const STATIONS := [
	[-7.30, 2.00, 1.30, 2.35, 1.86, 2.60, -0.20, 2.35, -0.85, 1.90, -1.25],
	[-5.60, 2.18, 1.85, 2.95, 1.84, 3.20, -0.20, 3.00, -0.85, 2.45, -1.32],
	[-3.80, 2.25, 2.30, 3.40, 1.80, 3.75, -0.20, 3.40, -0.85, 2.85, -1.32],
	[7.80, 2.25, 2.30, 3.40, 1.80, 3.75, -0.20, 3.40, -0.85, 2.85, -1.32],
	[10.86, 2.08, 1.95, 3.00, 1.78, 3.15, -0.20, 2.90, -0.85, 2.40, -1.28]]
## The chine steps in this far (and 0.1 m down) to the structural band: a shadow line along the whole hull.
const CHINE_STEP := 0.13
const NOSE_Z := -7.30
const TAIL_Z := 10.86
## Window band in the visor face (x, y), in front of the cockpit glass wall at z -7.2; the prow sits below it.
const WINDOW := Rect2(-1.95, 0.15, 3.9, 1.35)
const PROW_TIP_Z := -8.95
## Rear doorway in the loading face, around the airlock outer door (x +-0.7, 2.1 m high from the floor).
const DOORWAY := Rect2(-0.95, -0.95, 1.9, 2.25)
const POD_X := 5.1
const POD_Y := 1.0
const POD_RADIUS := 1.05 # to the flats of the octagon
const POD_FRONT_Z := 4.1
const POD_REAR_Z := 10.0
const NOZZLE_LENGTH := 0.8
const RAMP_THICKNESS := 0.12
## Leaf 2's hinge sits this far below leaf 1's underside so the folded leaves' stiffeners clear each other.
const RAMP_FOLD_GAP := 0.08
const RAMP_RAM_ANCHOR := Vector3(1.0, 0.9, 10.98) # x is mirrored
const RAMP_RAM_LEAF_POINT := Vector3(1.0, -0.06, 0.9) # on leaf 1, leaf-local
const TURRET_DECK_Y := 2.36
const TURRET_PIVOT_Y := 2.64

var materials := {} # Slot -> Material
var turret_pivot := Node3D.new()
var ramp_pivot := Node3D.new()      # leaf 1, hinged at the door sill
var ramp_second_pivot := Node3D.new() # leaf 2, hinged at the far bottom edge of leaf 1
var ramp_light := OmniLight3D.new()
var _rams := [] # [{sleeve, rod, side}]
var _exhaust_discs: Array[MeshInstance3D] = []
var _exhaust_level := 0.0
var _hot_glow: Material
var _layout: InteriorLayout


## Builds everything under `parent`. The two nacelles (nozzle material, one exhaust disc each) are added as
## direct children of `parent`; `nozzle_material` and `exhaust_disc` come from ShipVisuals so the asset switch
## and the engine glow stay where they were.
func build(parent: Node3D, layout: InteriorLayout, turret_muzzle: Vector3, nozzle_material: Material, make_exhaust_disc: Callable) -> void:
	_layout = layout
	_make_materials()
	var hull := HullMeshBuilder.new()
	_build_pressure_hull(hull)
	_build_visor_face(hull)
	_build_loading_face(hull)
	_build_engine_pods(hull)
	_build_landing_gear(hull)
	_build_belly_and_sides(hull)
	_build_dorsal(hull, turret_muzzle)
	parent.add_child(_instance(hull, "HullStatic"))
	_build_window_glass(parent)
	for side in [-1.0, 1.0]:
		var nozzle := CylinderMesh.new()
		nozzle.top_radius = 0.66
		nozzle.bottom_radius = 0.8
		nozzle.height = NOZZLE_LENGTH
		nozzle.radial_segments = 24
		var nacelle := MeshInstance3D.new()
		nacelle.name = "Nozzle_%s" % ("port" if side < 0.0 else "starboard")
		nacelle.mesh = nozzle
		nacelle.material_override = nozzle_material
		var disc: MeshInstance3D = make_exhaust_disc.call(NOZZLE_LENGTH * 0.5 + 0.012, 0.52) # proud of the cap: flush, it z-fought
		if disc != null:
			nacelle.add_child(disc)
			_exhaust_discs.append(disc)
		nacelle.rotation_degrees = Vector3(90, 0, 0) # cylinder +y -> ship +z (aft)
		nacelle.position = Vector3(side * POD_X, POD_Y, POD_REAR_Z + NOZZLE_LENGTH * 0.5)
		parent.add_child(nacelle)
	_build_turret(parent, turret_muzzle)
	_build_ramp(parent)


## Places the ramp leaves and rams. progress 0 = stowed (closing the doorway), 1 = deployed at `slope` radians
## below horizontal (positive = down), the same slope the walkway uses.
func update_ramp(progress: float, slope: float) -> void:
	var eased := smoothstep(0.0, 1.0, progress)
	ramp_pivot.rotation.x = lerpf(-PI * 0.5, slope, eased)
	ramp_second_pivot.rotation.x = lerpf(PI, 0.0, eased)
	ramp_light.visible = progress > 0.05
	for ram in _rams:
		var side: float = ram["side"]
		var anchor := Vector3(side * RAMP_RAM_ANCHOR.x, RAMP_RAM_ANCHOR.y, RAMP_RAM_ANCHOR.z)
		var leaf_point := ramp_pivot.transform * Vector3(side * RAMP_RAM_LEAF_POINT.x, RAMP_RAM_LEAF_POINT.y, RAMP_RAM_LEAF_POINT.z)
		_place_along(ram["sleeve"], anchor, leaf_point, 0.0, 0.8)
		var length := anchor.distance_to(leaf_point)
		_place_along(ram["rod"], leaf_point, anchor, 0.0, maxf(length - 0.15, 0.2))


## Exhaust glow follows demand: a cold, dark throat with a faint glow at idle, the engine glow under thrust (faded in
## by the instance's transparency; the glow material itself is shared with ShipVisuals, so it is never edited).
func update_exhaust(demand: float, delta: float) -> void:
	_exhaust_level = move_toward(_exhaust_level, clampf(demand, 0.0, 1.0), delta * 3.0)
	for disc in _exhaust_discs:
		if _hot_glow == null:
			_hot_glow = disc.material_override
		var hot := _exhaust_level > 0.05
		disc.material_override = _hot_glow if hot else materials[Slot.EXHAUST_IDLE]
		disc.transparency = 1.0 - clampf(0.35 + 0.65 * _exhaust_level, 0.0, 1.0) if hot else 0.0


# --- materials -------------------------------------------------------------------------------------------------

func _make_materials() -> void:
	materials[Slot.HULL] = AssetLibrary.material_or("mat_hull_plating", _paint(Color(0.74, 0.72, 0.67), 0.6, 0.05))
	materials[Slot.PANEL] = _tinted_plating(Color(0.84, 0.82, 0.78), Color(0.63, 0.62, 0.58))
	materials[Slot.STRUCTURE] = _tinted_plating(Color(0.52, 0.57, 0.64), Color(0.4, 0.44, 0.49))
	materials[Slot.GRAPHITE] = _tinted_plating(Color(0.36, 0.37, 0.4), Color(0.26, 0.27, 0.29))
	materials[Slot.RECESS] = _paint(Color(0.1, 0.105, 0.11), 0.9, 0.0)
	materials[Slot.SAFETY] = _paint(Color(0.86, 0.42, 0.12), 0.6, 0.0)
	materials[Slot.METAL] = _paint(Color(0.72, 0.74, 0.77), 0.32, 0.55)
	materials[Slot.LIGHT] = _light(Color(0.55, 0.88, 1.0), 2.2)
	materials[Slot.NAV_PORT] = _light(Color(1.0, 0.18, 0.12), 2.0)
	materials[Slot.NAV_STARBOARD] = _light(Color(0.2, 1.0, 0.35), 2.0)
	var idle := _light(Color(0.12, 0.2, 0.26), 0.35) # cold nozzle throat: dark, a faint residual glow
	idle.emission = Color(0.25, 0.6, 0.85)
	materials[Slot.EXHAUST_IDLE] = idle
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.09, 0.13, 0.17, 0.84) # a tinted visor from outside; the pilot looks through its culled back face
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.85
	glass.roughness = 0.06
	materials[Slot.GLASS] = glass


## The hull plating texture (panel seams, fasteners) tinted to a secondary colour, so every painted part shares
## one texture set; falls back to a flat code colour when assets are off.
static func _tinted_plating(tint: Color, fallback_color: Color) -> Material:
	var copy := AssetLibrary.material_copy_or("mat_hull_plating", null)
	if copy is BaseMaterial3D:
		(copy as BaseMaterial3D).albedo_color = tint
		return copy
	return _paint(fallback_color, 0.6, 0.15)


static func _paint(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


static func _light(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func _instance(builder: HullMeshBuilder, node_name: String) -> MeshInstance3D:
	var committed := builder.commit()
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = committed["mesh"]
	var slots: PackedInt32Array = committed["slots"]
	for surface in slots.size():
		instance.set_surface_override_material(surface, materials[slots[surface]])
	return instance


# --- pressure hull ---------------------------------------------------------------------------------------------

## Half profile at one station, top centre to bottom centre.
static func _half_profile(station: Array) -> PackedVector3Array:
	var z: float = station[0]
	return PackedVector3Array([
		Vector3(0, station[1], z), Vector3(station[2], station[1], z), Vector3(station[3], station[4], z), Vector3(station[5], station[6], z),
		Vector3(station[5] - CHINE_STEP, station[6] - 0.1, z), Vector3(station[7], station[8], z), Vector3(station[9], station[10], z),
		Vector3(0, station[10], z)])


## The x of the hull's upper side (shoulder to chine) at height y, at station index `index`.
static func _upper_side_x(index: int, y: float) -> float:
	var station: Array = STATIONS[index]
	return lerpf(station[5], station[3], (y - station[6]) / (station[4] - station[6]))


## Strips of the half profile: roof, shoulder, upper side (ceramic) | chine step, lower side, lower chamfer (structure) | belly.
const PROFILE_SLOTS := [Slot.HULL, Slot.HULL, Slot.HULL, Slot.STRUCTURE, Slot.STRUCTURE, Slot.STRUCTURE, Slot.GRAPHITE]


func _build_pressure_hull(hull: HullMeshBuilder) -> void:
	var rings := []
	for station in STATIONS:
		rings.append(HullMeshBuilder.mirror_ring(_half_profile(station)))
	hull.add_loft(rings, HullMeshBuilder.mirror_slots(PackedInt32Array(PROFILE_SLOTS)))


static func _outline_2d(station: Array) -> PackedVector2Array:
	var outline := PackedVector2Array()
	for point in HullMeshBuilder.mirror_ring(_half_profile(station)):
		outline.append(Vector2(point.x, point.y))
	return outline


## The visor face: a window band between the prow below and an overhanging brow above. The front cap minus the
## window gives the window pillars; a liner seen from the cockpit through its glass wall hides the hull's back faces.
func _build_visor_face(hull: HullMeshBuilder) -> void:
	var w := WINDOW
	hull.add_cap_with_opening(_outline_2d(STATIONS[0]), w, NOSE_Z, -1.0, Slot.STRUCTURE)
	# Liner just in front of the cockpit glass wall (z -7.2), facing aft, covering the glass outside the window.
	var glass_rect := PackedVector2Array([Vector2(-2.25, -0.95), Vector2(2.25, -0.95), Vector2(2.25, 1.86), Vector2(-2.25, 1.86)])
	hull.add_cap_with_opening(glass_rect, w, -7.215, 1.0, Slot.STRUCTURE)
	# Window reveal: the four sides of the opening between the face and the liner.
	hull.add_loft([
		PackedVector3Array([Vector3(w.position.x, w.end.y, NOSE_Z), Vector3(w.end.x, w.end.y, NOSE_Z), Vector3(w.end.x, w.position.y, NOSE_Z), Vector3(w.position.x, w.position.y, NOSE_Z)]),
		PackedVector3Array([Vector3(w.position.x, w.end.y, -7.215), Vector3(w.end.x, w.end.y, -7.215), Vector3(w.end.x, w.position.y, -7.215), Vector3(w.position.x, w.position.y, -7.215)])],
		PackedInt32Array([Slot.GRAPHITE]), Transform3D.IDENTITY, true)
	# Brow: the roof carried forward over the window as a thick visor, its underside rising toward the front edge.
	var brow_back := PackedVector3Array([Vector3(0, 2.0, NOSE_Z), Vector3(1.3, 2.0, NOSE_Z), Vector3(2.35, 1.86, NOSE_Z), Vector3(_upper_side_x(0, w.end.y), w.end.y, NOSE_Z), Vector3(0, w.end.y, NOSE_Z)])
	var brow_front := PackedVector3Array([Vector3(0, 1.96, -7.62), Vector3(1.2, 1.96, -7.62), Vector3(2.15, 1.84, -7.62), Vector3(2.17, 1.62, -7.62), Vector3(0, 1.62, -7.62)])
	var brow_slots := PackedInt32Array([Slot.HULL, Slot.HULL, Slot.STRUCTURE, Slot.STRUCTURE])
	hull.add_loft([HullMeshBuilder.mirror_ring(brow_back), HullMeshBuilder.mirror_ring(brow_front)], HullMeshBuilder.mirror_slots(brow_slots), Transform3D.IDENTITY, false, -1, Slot.STRUCTURE)
	# Prow: the lower hull carried forward and down under the window to a sensor face at the tip.
	var prow := [
		PackedVector3Array([Vector3(0, w.position.y, NOSE_Z), Vector3(_upper_side_x(0, w.position.y), w.position.y, NOSE_Z), Vector3(2.6, -0.2, NOSE_Z), Vector3(2.6 - CHINE_STEP, -0.3, NOSE_Z),
			Vector3(2.35, -0.85, NOSE_Z), Vector3(1.9, -1.25, NOSE_Z), Vector3(0, -1.25, NOSE_Z)]),
		PackedVector3Array([Vector3(0, 0.02, -8.25), Vector3(1.95, -0.1, -8.25), Vector3(2.0, -0.3, -8.25), Vector3(1.9, -0.4, -8.25),
			Vector3(1.8, -0.82, -8.25), Vector3(1.45, -1.12, -8.25), Vector3(0, -1.12, -8.25)]),
		PackedVector3Array([Vector3(0, -0.26, PROW_TIP_Z), Vector3(1.15, -0.36, PROW_TIP_Z), Vector3(1.2, -0.45, PROW_TIP_Z), Vector3(1.12, -0.52, PROW_TIP_Z),
			Vector3(1.05, -0.78, PROW_TIP_Z), Vector3(0.8, -0.95, PROW_TIP_Z), Vector3(0, -0.95, PROW_TIP_Z)])]
	var mirrored := []
	for ring in prow:
		mirrored.append(HullMeshBuilder.mirror_ring(ring))
	var prow_slots := PackedInt32Array([Slot.HULL, Slot.HULL, Slot.STRUCTURE, Slot.STRUCTURE, Slot.STRUCTURE, Slot.GRAPHITE])
	hull.add_loft(mirrored, HullMeshBuilder.mirror_slots(prow_slots), Transform3D.IDENTITY, false, -1, Slot.STRUCTURE)
	# Sensor aperture and the two landing lights in the prow face.
	hull.add_chamfer_box(Vector3(0.9, 0.2, 0.05), 0.04, Slot.RECESS, Transform3D(Basis.IDENTITY, Vector3(0, -0.62, PROW_TIP_Z - 0.01)))
	for side in [-1.0, 1.0]:
		hull.add_cylinder(10, 0.08, 0.08, -0.04, 0.0, Slot.LIGHT, Transform3D(Basis.IDENTITY, Vector3(side * 0.82, -0.62, PROW_TIP_Z)))
		# Flood lights under the brow, aimed at the ground ahead.
		hull.add_chamfer_box(Vector3(0.5, 0.04, 0.1), 0.015, Slot.LIGHT, Transform3D(Basis.IDENTITY, Vector3(side * 1.2, 1.55, -7.45)))
	# Mullions: three posts splitting the window into four panes.
	for x in [-0.98, 0.0, 0.98]:
		hull.add_chamfer_box(Vector3(0.08, w.size.y, 0.07), 0.015, Slot.STRUCTURE, Transform3D(Basis.IDENTITY, Vector3(x, w.get_center().y, -7.255)))
	# Sill: a ledge where the window meets the prow.
	hull.add_chamfer_box(Vector3(w.size.x + 0.1, 0.06, 0.16), 0.02, Slot.GRAPHITE, Transform3D(Basis.IDENTITY, Vector3(0, w.position.y + 0.03, -7.32)))


func _build_window_glass(parent: Node3D) -> void:
	var pane := MeshInstance3D.new()
	pane.name = "VisorGlass"
	var quad := QuadMesh.new()
	quad.size = WINDOW.size
	pane.mesh = quad
	pane.material_override = materials[Slot.GLASS]
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pane.position = Vector3(WINDOW.get_center().x, WINDOW.get_center().y, -7.235)
	pane.rotation_degrees = Vector3(0, 180, 0) # a QuadMesh faces +z; the window looks forward (-z)
	parent.add_child(pane)


## The rear loading face: the tail cap minus the doorway, a structural door frame with safety-orange edges, the
## ramp hinge barrel and a work light. The ramp itself is built in _build_ramp.
func _build_loading_face(hull: HullMeshBuilder) -> void:
	var tail: Array = STATIONS[STATIONS.size() - 1]
	hull.add_cap_with_opening(_outline_2d(tail), DOORWAY, TAIL_Z, 1.0, Slot.PANEL)
	var depth := 0.12
	var frame_z := TAIL_Z + depth * 0.5
	var d := DOORWAY
	for side in [-1.0, 1.0]:
		var post_x: float = side * (d.end.x + 0.11)
		hull.add_chamfer_box(Vector3(0.22, d.size.y + 0.2, depth), 0.04, Slot.STRUCTURE, Transform3D(Basis.IDENTITY, Vector3(post_x, d.get_center().y + 0.1, frame_z)))
		hull.add_chamfer_box(Vector3(0.06, d.size.y - 0.3, 0.01), 0.004, Slot.SAFETY, Transform3D(Basis.IDENTITY, Vector3(post_x + side * 0.05, d.get_center().y, TAIL_Z + depth + 0.005)))
	hull.add_chamfer_box(Vector3(d.size.x + 0.44, 0.22, depth), 0.04, Slot.STRUCTURE, Transform3D(Basis.IDENTITY, Vector3(0, d.end.y + 0.11, frame_z)))
	# Hinge barrel along the sill.
	hull.add_cylinder(12, 0.085, 0.085, -d.size.x * 0.5, d.size.x * 0.5, Slot.STRUCTURE, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, _layout.floor_y - 0.07, TAIL_Z - 0.02)))
	# Work light over the doorway.
	hull.add_chamfer_box(Vector3(0.7, 0.05, 0.06), 0.015, Slot.LIGHT, Transform3D(Basis.IDENTITY, Vector3(0, d.end.y + 0.08, TAIL_Z + depth + 0.03)))


# --- propulsion ------------------------------------------------------------------------------------------------

func _build_engine_pods(hull: HullMeshBuilder) -> void:
	# Octagon with flats at top and bottom: corner radius from the flat radius.
	var corner := POD_RADIUS / cos(PI / 8.0)
	var pod_slots := PackedInt32Array([Slot.HULL, Slot.HULL, Slot.PANEL, Slot.STRUCTURE, Slot.GRAPHITE, Slot.STRUCTURE, Slot.PANEL, Slot.HULL])
	for side in [-1.0, 1.0]:
		var pod := Transform3D(Basis.IDENTITY, Vector3(side * POD_X, POD_Y, 0))
		var start := PI / 8.0
		var rings := [
			HullMeshBuilder.polygon_ring(8, corner * 0.8, POD_FRONT_Z, start),
			HullMeshBuilder.polygon_ring(8, corner, POD_FRONT_Z + 0.4, start),
			HullMeshBuilder.polygon_ring(8, corner, POD_REAR_Z - 0.9, start),
			HullMeshBuilder.polygon_ring(8, corner * 0.84, POD_REAR_Z, start)]
		var lip_slots := PackedInt32Array([Slot.STRUCTURE])
		hull.add_loft([rings[0], rings[1]], lip_slots, pod)
		hull.add_loft([rings[1], rings[2], rings[3]], pod_slots, pod, false, -1, Slot.GRAPHITE)
		# Intake: a short throat inside the lip, a dark face, the fan hub and four stator vanes.
		var throat := [HullMeshBuilder.polygon_ring(8, corner * 0.8, POD_FRONT_Z, start), HullMeshBuilder.polygon_ring(8, corner * 0.72, POD_FRONT_Z + 0.32, start)]
		hull.add_loft(throat, PackedInt32Array([Slot.GRAPHITE]), pod, true)
		hull.add_cap(throat[1], Slot.RECESS, Vector3(0, 0, -1), pod)
		hull.add_cylinder(12, 0.08, 0.24, POD_FRONT_Z + 0.06, POD_FRONT_Z + 0.31, Slot.METAL, pod, Slot.METAL)
		for vane in 4:
			var angle := PI * 0.25 + PI * 0.5 * vane
			var tip := Vector3(sin(angle), cos(angle), 0) * corner * 0.7
			hull.add_bar(Vector3(0, 0, POD_FRONT_Z + 0.27) + tip * 0.3, Vector3(0, 0, POD_FRONT_Z + 0.27) + tip, 0.05, Slot.STRUCTURE, pod)
		# Structural collar where the pylon carries the pod (the tilt axis) and the tilt actuator housing outboard.
		hull.add_cylinder(8, corner * 1.04, corner * 1.04, 6.6, 7.3, Slot.STRUCTURE, pod)
		var actuator := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(side * (POD_X + POD_RADIUS + 0.02), POD_Y, 6.95))
		hull.add_cylinder(10, 0.36, 0.3, 0.0, side * 0.14, Slot.STRUCTURE, actuator)
		hull.add_cylinder(10, 0.13, 0.13, 0.0, side * 0.18, Slot.SAFETY, actuator)
		# Pylon: a thick swept stub from the hull side into the pod collar.
		_add_pylon(hull, side)
		# Nav light on the outboard front of each pod (red port, green starboard).
		hull.add_chamfer_box(Vector3(0.05, 0.12, 0.24), 0.015, Slot.NAV_PORT if side < 0.0 else Slot.NAV_STARBOARD, Transform3D(Basis.IDENTITY, Vector3(side * (POD_X + POD_RADIUS + 0.02), POD_Y + 0.25, POD_FRONT_Z + 0.75)))
		# Nozzle mount ring between the pod tail and the nozzle.
		hull.add_cylinder(16, 0.88, 0.86, POD_REAR_Z - 0.02, POD_REAR_Z + 0.08, Slot.GRAPHITE, pod)


func _add_pylon(hull: HullMeshBuilder, side: float) -> void:
	# Section in (z, y) at the root (hull side) and at the pod; extruded along x.
	var root_x := 3.25 # inside the hull side, which leans in to x 3.31 at the trailing edge top
	var tip_x := POD_X - POD_RADIUS + 0.1
	var root := [Vector2(5.0, 1.0), Vector2(5.6, 1.45), Vector2(8.4, 1.45), Vector2(8.9, 1.15), Vector2(8.8, 0.6), Vector2(5.5, 0.6)]
	var tip := [Vector2(5.7, 1.0), Vector2(6.1, 1.35), Vector2(8.0, 1.35), Vector2(8.4, 1.1), Vector2(8.3, 0.67), Vector2(6.0, 0.67)]
	var ring_root := PackedVector3Array()
	var ring_tip := PackedVector3Array()
	for point in root:
		ring_root.append(Vector3(side * root_x, point.y, point.x))
	for point in tip:
		ring_tip.append(Vector3(side * tip_x, point.y, point.x))
	# Strips: leading-edge top, top, trailing top, trailing bottom, bottom, leading bottom.
	hull.add_loft([ring_root, ring_tip], PackedInt32Array([Slot.STRUCTURE, Slot.HULL, Slot.STRUCTURE, Slot.STRUCTURE, Slot.GRAPHITE, Slot.STRUCTURE]))


# --- landing gear ----------------------------------------------------------------------------------------------

## Rail sections: z, centre x, width, top y, bottom y. The ends taper and tuck into the hull.
const RAIL_STATIONS := [[-6.5, 2.55, 0.5, -0.92, -1.28], [-5.6, 2.85, 0.9, -0.9, -1.5], [9.0, 2.85, 0.9, -0.9, -1.5], [9.8, 2.7, 0.55, -0.92, -1.3]]


## Two chassis rails along the lower hull carry the four legs; the foot pads' undersides are the ground-contact
## support points (the first four ShipTuning.support_points), so what you see is what lands.
func _build_landing_gear(hull: HullMeshBuilder) -> void:
	for side in [-1.0, 1.0]:
		var rings := []
		for station in RAIL_STATIONS:
			var octagon := HullMeshBuilder._octagon(station[2] * 0.5, (station[3] - station[4]) * 0.5, 0.12)
			var ring := PackedVector3Array()
			for point in octagon:
				ring.append(Vector3(side * station[1] + point.x, (station[3] + station[4]) * 0.5 + point.y, station[0]))
			rings.append(ring)
		# Octagon strips: top, chamfer, side, chamfer, bottom, chamfer, side, chamfer.
		var rail_slots := PackedInt32Array([Slot.STRUCTURE, Slot.STRUCTURE, Slot.STRUCTURE, Slot.STRUCTURE, Slot.GRAPHITE, Slot.STRUCTURE, Slot.STRUCTURE, Slot.STRUCTURE])
		hull.add_loft(rings, rail_slots, Transform3D.IDENTITY, false, Slot.GRAPHITE, Slot.GRAPHITE)
	var feet := ShipTuning.new().support_points
	for index in 4:
		var foot: Vector3 = feet[index]
		var side := signf(foot.x)
		var rail_bottom: float = RAIL_STATIONS[1][4]
		# Gear bay in the rail's underside.
		hull.add_chamfer_box(Vector3(0.62, 0.02, 1.2), 0.008, Slot.RECESS, Transform3D(Basis.IDENTITY, Vector3(foot.x, rail_bottom - 0.005, foot.z)))
		var top := Vector3(foot.x, rail_bottom + 0.05, foot.z)
		var knee := Vector3(foot.x, -1.72, foot.z)
		var ankle := Vector3(foot.x, foot.y + 0.18, foot.z)
		# Oleo: graphite cylinder above, polished piston below, orange torque link in front.
		hull.add_cylinder(10, 0.2, 0.19, 0.0, top.distance_to(knee), Slot.GRAPHITE, _along(top, knee))
		hull.add_cylinder(10, 0.12, 0.12, 0.0, knee.distance_to(ankle), Slot.METAL, _along(knee, ankle))
		hull.add_bar(Vector3(foot.x, rail_bottom - 0.02, foot.z - 0.24), Vector3(foot.x, -1.8, foot.z - 0.17), 0.07, Slot.SAFETY)
		# Drag brace from the rail to the knee, angled toward the nearer end of the ship.
		var outward := -1.0 if foot.z < 0.0 else 1.0
		hull.add_bar(Vector3(foot.x, rail_bottom + 0.02, foot.z + outward * 0.8), knee + Vector3(0, 0.03, outward * 0.12), 0.09, Slot.STRUCTURE)
		# Foot pad: chamfered octagonal disc whose underside is the support point.
		var pad := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(foot.x, foot.y, foot.z))
		var start := PI / 8.0
		var pad_rings := [HullMeshBuilder.polygon_ring(8, 0.5, 0.0, start), HullMeshBuilder.polygon_ring(8, 0.56, 0.06, start), HullMeshBuilder.polygon_ring(8, 0.56, 0.11, start), HullMeshBuilder.polygon_ring(8, 0.36, 0.18, start)]
		hull.add_loft(pad_rings, PackedInt32Array([Slot.GRAPHITE]), pad, false, Slot.GRAPHITE, Slot.STRUCTURE)
		hull.add_cylinder(10, 0.17, 0.17, 0.0, 0.1, Slot.STRUCTURE, _along(ankle - Vector3(0, 0.02, 0), ankle + Vector3(0, 0.08, 0)))


## A transform whose local +z runs from `from` toward `to` (for cylinders authored along z).
static func _along(from: Vector3, to: Vector3) -> Transform3D:
	var direction := (to - from).normalized()
	var up := Vector3.UP if absf(direction.y) < 0.95 else Vector3.RIGHT
	return Transform3D(Basis.looking_at(-direction, up), from)


# --- belly, sides, roof ----------------------------------------------------------------------------------------

func _build_belly_and_sides(hull: HullMeshBuilder) -> void:
	# Ventral lift-fan grilles under the cabin: recessed face, slats, frame.
	for side in [-1.0, 1.0]:
		var grille := Transform3D(Basis.IDENTITY, Vector3(side * 1.25, -1.33, -1.9))
		hull.add_chamfer_box(Vector3(1.5, 0.03, 2.0), 0.01, Slot.RECESS, grille)
		for slat in 7:
			hull.add_chamfer_box(Vector3(1.36, 0.05, 0.05), 0.01, Slot.STRUCTURE, grille * Transform3D(Basis.IDENTITY, Vector3(0, -0.02, -0.84 + slat * 0.28)))
		for edge in [-1.0, 1.0]:
			hull.add_chamfer_box(Vector3(1.66, 0.06, 0.08), 0.02, Slot.GRAPHITE, grille * Transform3D(Basis.IDENTITY, Vector3(0, -0.02, edge * 1.04)))
			hull.add_chamfer_box(Vector3(0.08, 0.06, 2.16), 0.02, Slot.GRAPHITE, grille * Transform3D(Basis.IDENTITY, Vector3(edge * 0.79, -0.02, 0)))
	# Keel strip along the belly centre line.
	hull.add_chamfer_box(Vector3(0.36, 0.05, 13.5), 0.02, Slot.STRUCTURE, Transform3D(Basis.IDENTITY, Vector3(0, -1.335, 1.25)))
	for side in [-1.0, 1.0]:
		# Rub strake: a protective bumper along the chine, between the cockpit and the pylon root.
		hull.add_chamfer_box(Vector3(0.1, 0.12, 9.6), 0.035, Slot.GRAPHITE, Transform3D(Basis.IDENTITY, Vector3(side * 3.77, -0.22, 0.5)))
		# Engineering service hatch on the upper side band: a hull-colour door in a structural frame, following the
		# side's lean (local x along the hull, y up the side, z out of it).
		var lean := atan2(STATIONS[2][5] - STATIONS[2][3], STATIONS[2][4] - STATIONS[2][6])
		var normal := Vector3(side * cos(lean), sin(lean), 0)
		var up_side := Vector3(-side * sin(lean), cos(lean), 0)
		var hatch_y := 0.7
		var hatch := Transform3D(Basis(up_side.cross(normal), up_side, normal), Vector3(side * _upper_side_x(2, hatch_y), hatch_y, 0.6) + normal * 0.012)
		hull.add_chamfer_box(Vector3(1.8, 0.9, 0.025), 0.012, Slot.HULL, hatch)
		for edge in [[Vector3(-0.93, -0.48, 0), Vector3(0.93, -0.48, 0)], [Vector3(-0.93, 0.48, 0), Vector3(0.93, 0.48, 0)], [Vector3(-0.93, -0.48, 0), Vector3(-0.93, 0.48, 0)], [Vector3(0.93, -0.48, 0), Vector3(0.93, 0.48, 0)]]:
			hull.add_bar(edge[0], edge[1], 0.05, Slot.STRUCTURE, hatch)
		hull.add_chamfer_box(Vector3(0.24, 0.05, 0.03), 0.01, Slot.GRAPHITE, hatch * Transform3D(Basis.IDENTITY, Vector3(0.6, 0, 0.02)))
		# Forward RCS blocks on the shoulders, nozzle slots facing outboard.
		var rcs := Transform3D(Basis.IDENTITY, Vector3(side * 3.25, 1.95, -3.3))
		hull.add_chamfer_box(Vector3(0.42, 0.24, 0.6), 0.06, Slot.STRUCTURE, rcs)
		for offset in [-0.13, 0.13]:
			hull.add_chamfer_box(Vector3(0.02, 0.1, 0.12), 0.01, Slot.RECESS, rcs * Transform3D(Basis.IDENTITY, Vector3(side * 0.21, 0, offset)))


func _build_dorsal(hull: HullMeshBuilder, turret_muzzle: Vector3) -> void:
	var roof_y: float = STATIONS[2][2]
	# Heat-exchanger spine over cabin and engineering: a raised fairing with two louvred grilles.
	hull.add_chamfer_box(Vector3(2.1, 0.34, 6.2), 0.14, Slot.PANEL, Transform3D(Basis.IDENTITY, Vector3(0, roof_y + 0.15, -0.5)))
	for grille_z in [-2.0, 0.9]:
		var grille := Transform3D(Basis.IDENTITY, Vector3(0, roof_y + 0.32, grille_z))
		hull.add_chamfer_box(Vector3(1.4, 0.02, 1.9), 0.005, Slot.RECESS, grille)
		for fin in 8:
			hull.add_chamfer_box(Vector3(1.3, 0.05, 0.04), 0.01, Slot.STRUCTURE, grille * Transform3D(Basis.IDENTITY, Vector3(0, 0.025, -0.78 + fin * 0.223)))
	# Spine tail: a short ramp from the fairing down to the roof.
	var tail_back := PackedVector3Array([Vector3(0, roof_y + 0.32, 2.6), Vector3(0.9, roof_y + 0.32, 2.6), Vector3(1.05, roof_y + 0.17, 2.6), Vector3(1.05, roof_y - 0.02, 2.6), Vector3(0, roof_y - 0.02, 2.6)])
	var tail_end := PackedVector3Array([Vector3(0, roof_y + 0.0, 3.35), Vector3(0.75, roof_y + 0.0, 3.35), Vector3(0.85, roof_y - 0.01, 3.35), Vector3(0.85, roof_y - 0.02, 3.35), Vector3(0, roof_y - 0.02, 3.35)])
	hull.add_loft([HullMeshBuilder.mirror_ring(tail_back), HullMeshBuilder.mirror_ring(tail_end)], HullMeshBuilder.mirror_slots(PackedInt32Array([Slot.PANEL, Slot.PANEL, Slot.PANEL, Slot.PANEL])))
	# Turret barbette: an armoured ring on the roof around the gun's mount point.
	var barbette := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(turret_muzzle.x, roof_y - 0.02, turret_muzzle.z))
	hull.add_cylinder(12, 0.95, 0.85, 0.0, TURRET_DECK_Y - roof_y + 0.02, Slot.STRUCTURE, barbette, -1)
	hull.add_cylinder(12, 0.84, 0.84, TURRET_DECK_Y - roof_y + 0.02, TURRET_DECK_Y - roof_y + 0.03, Slot.GRAPHITE, barbette)
	# Cargo roof hatch aft of the turret, with orange lift points at its corners.
	var hatch := Transform3D(Basis.IDENTITY, Vector3(0, roof_y + 0.02, 6.8))
	hull.add_chamfer_box(Vector3(2.4, 0.05, 1.7), 0.025, Slot.PANEL, hatch)
	for corner_x in [-1.05, 1.05]:
		for corner_z in [-0.7, 0.7]:
			hull.add_chamfer_box(Vector3(0.14, 0.05, 0.14), 0.02, Slot.SAFETY, hatch * Transform3D(Basis.IDENTITY, Vector3(corner_x, 0.03, corner_z)))
	# Tail light at the roof's rear edge.
	hull.add_chamfer_box(Vector3(0.3, 0.05, 0.08), 0.015, Slot.LIGHT, Transform3D(Basis.IDENTITY, Vector3(0, 2.03, TAIL_Z - 0.05)))


# --- moving parts ----------------------------------------------------------------------------------------------

## The dorsal gun. The pivot sits on the barbette above the gameplay muzzle point (Ship/ShipTurret keep their
## muzzle_offset; the visual is raised so the gun clears the new roof).
func _build_turret(parent: Node3D, turret_muzzle: Vector3) -> void:
	turret_pivot.name = "TurretPivot"
	turret_pivot.position = Vector3(turret_muzzle.x, TURRET_PIVOT_Y, turret_muzzle.z)
	parent.add_child(turret_pivot)
	var head := HullMeshBuilder.new()
	head.add_chamfer_box(Vector3(1.0, 0.44, 1.15), 0.12, Slot.PANEL, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.05)), Slot.HULL)
	head.add_chamfer_box(Vector3(0.36, 0.2, 0.06), 0.03, Slot.RECESS, Transform3D(Basis.IDENTITY, Vector3(0.24, 0.06, -0.53))) # sight
	head.add_cylinder(10, 0.13, 0.13, -0.5, -1.0, Slot.STRUCTURE, Transform3D.IDENTITY)
	head.add_cylinder(10, 0.065, 0.065, -1.0, -1.75, Slot.METAL, Transform3D.IDENTITY)
	head.add_cylinder(10, 0.095, 0.095, -1.75, -1.95, Slot.GRAPHITE, Transform3D.IDENTITY)
	turret_pivot.add_child(_instance(head, "TurretHead"))


func _build_ramp(parent: Node3D) -> void:
	var ramp := _layout.ramp_rect
	var leaf_length := ramp.size.y * 0.5
	ramp_pivot.name = "RampLeaf1"
	ramp_pivot.position = Vector3(ramp.get_center().x, _layout.floor_y, ramp.position.y)
	parent.add_child(ramp_pivot)
	ramp_pivot.add_child(_instance(_ramp_leaf(ramp.size.x, leaf_length, false), "Leaf1"))
	ramp_second_pivot.name = "RampLeaf2"
	ramp_second_pivot.position = Vector3(0, -RAMP_THICKNESS - RAMP_FOLD_GAP, leaf_length)
	ramp_pivot.add_child(ramp_second_pivot)
	var second := _ramp_leaf(ramp.size.x, leaf_length, true)
	ramp_second_pivot.add_child(_instance(second, "Leaf2"))
	for side in [-1.0, 1.0]:
		var sleeve := _ram_part(0.07, materials[Slot.STRUCTURE])
		var rod := _ram_part(0.035, materials[Slot.METAL])
		parent.add_child(sleeve)
		parent.add_child(rod)
		_rams.append({"sleeve": sleeve, "rod": rod, "side": side})
	ramp_light.name = "RampLight"
	ramp_light.position = Vector3(0, DOORWAY.end.y - 0.1, TAIL_Z + 0.5)
	ramp_light.light_color = Color(0.8, 0.92, 1.0)
	ramp_light.light_energy = 0.9
	ramp_light.omni_range = 5.0
	ramp_light.shadow_enabled = false
	parent.add_child(ramp_light)
	update_ramp(0.0, 0.0)


## One ramp leaf in its pivot's frame. Leaf 1 (hinged at the sill): deck top at y 0, spanning y -t..0, z 0..length.
## Leaf 2 hangs from a hinge RAMP_FOLD_GAP below leaf 1's far edge: deck spanning y gap..gap+t, so its top lines up
## with leaf 1's when unfolded.
func _ramp_leaf(width: float, length: float, second: bool) -> HullMeshBuilder:
	var leaf := HullMeshBuilder.new()
	var t := RAMP_THICKNESS
	var deck_top := t + RAMP_FOLD_GAP if second else 0.0
	var at := func(point: Vector3) -> Transform3D: return Transform3D(Basis.IDENTITY, point)
	leaf.add_chamfer_box(Vector3(width, t, length), 0.03, Slot.STRUCTURE, at.call(Vector3(0, deck_top - t * 0.5, length * 0.5)), Slot.STRUCTURE)
	# Treads across the deck.
	for tread in 5:
		leaf.add_chamfer_box(Vector3(width - 0.3, 0.025, 0.07), 0.008, Slot.GRAPHITE, at.call(Vector3(0, deck_top + 0.012, length * (0.12 + 0.19 * tread))))
	# Side curbs with safety-orange tops.
	for side in [-1.0, 1.0]:
		var curb_x: float = side * (width * 0.5 - 0.04)
		leaf.add_chamfer_box(Vector3(0.08, 0.09, length - 0.02), 0.015, Slot.GRAPHITE, at.call(Vector3(curb_x, deck_top + 0.045, length * 0.5)))
		leaf.add_chamfer_box(Vector3(0.082, 0.006, length - 0.1), 0.002, Slot.SAFETY, at.call(Vector3(curb_x, deck_top + 0.091, length * 0.5)))
		# Underside stiffeners.
		leaf.add_chamfer_box(Vector3(0.08, 0.07, length - 0.1), 0.015, Slot.GRAPHITE, at.call(Vector3(side * 0.5, deck_top - t - 0.035, length * 0.5)))
	if second:
		# Toe plate at the ground end.
		leaf.add_chamfer_box(Vector3(width, 0.035, 0.16), 0.01, Slot.SAFETY, at.call(Vector3(0, deck_top - 0.06, length + 0.06)))
	else:
		# Hinge knuckles at the fold, and the ram brackets.
		leaf.add_cylinder(10, 0.07, 0.07, -width * 0.42, width * 0.42, Slot.METAL, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, -t - RAMP_FOLD_GAP, length)))
		for side in [-1.0, 1.0]:
			leaf.add_chamfer_box(Vector3(0.12, 0.14, 0.24), 0.02, Slot.STRUCTURE, at.call(Vector3(side * (width * 0.5 + 0.04), RAMP_RAM_LEAF_POINT.y, RAMP_RAM_LEAF_POINT.z)))
	return leaf


func _ram_part(radius: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 1
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	return instance


## Stretches a unit cylinder (along y, centred) from `from` toward `to`, covering `start`..`length` metres.
static func _place_along(node: MeshInstance3D, from: Vector3, to: Vector3, start: float, length: float) -> void:
	var direction := (to - from).normalized()
	var side := direction.cross(Vector3.RIGHT if absf(direction.x) < 0.9 else Vector3.FORWARD).normalized()
	var basis := Basis(direction.cross(side), direction * length, side) # x, y (along, stretched), z: right-handed
	node.transform = Transform3D(basis, from + direction * (start + length * 0.5))
