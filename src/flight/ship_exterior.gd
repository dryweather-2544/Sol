class_name ShipExterior
extends RefCounted
## The player ship's outer hull and running gear: a heavy VTOL transport / gunship built around the walkable
## interior (InteriorLayout.player_ship). Ship-local metres, nose -z, right +x, up +y.
##
## Design (one vehicle, each part with a job):
## - Pressure hull: one chamfered loft from the canopy to the rear loading face, wrapping the six rooms
##   (rooms reach x +-3.2, ceiling slab top y 1.82, floor slab bottom y -1.02; the hull clears all of it). The roof
##   rises into a dorsal hump over cabin and engineering and the tail narrows round the airlock, so the side and
##   plan silhouettes are shaped, not a constant box. Light ceramic upper hull, blue-grey band, graphite belly.
## - Cockpit: a faceted, raked glass canopy in a tapering nose, replacing the cockpit's flat glass wall; the
##   walkable cockpit floor is unchanged (it ends at z -7.0) and a dash fills the nose in front of it.
## - Propulsion: two tilt-engine pods on stub wings at the rear flanks. They stand upright (nozzles down) when
##   landed or hovering low and slow, and swing level for flight; ventral lift-fan grilles balance the nose.
## - Landing gear: four oleo legs on two chassis rails; the foot pads sit exactly on ShipTuning.support_points.
## - Access: a two-leaf folding ramp hinged at the rear door sill. Stowed, the first leaf closes the doorway and the
##   second folds down over it; deployed, both lie in one line along the walkway slope. Two rams drive it.
## - Dorsal: heat-exchanger spine over cabin/engineering and the turret barbette above the turret room.
## All static parts are merged into one mesh (one draw call per material); the ramp, rams, turret and pods move.

enum Slot { HULL, PANEL, STRUCTURE, GRAPHITE, RECESS, SAFETY, METAL, LIGHT, NAV_PORT, NAV_STARBOARD, GLASS, EXHAUST_IDLE,
	HULL_2S, STRUCTURE_2S, GRAPHITE_2S }
## Two-sided copies for the hull round the cockpit, whose inside is seen from the cockpit through the canopy.
const TWO_SIDED := {Slot.HULL: Slot.HULL_2S, Slot.STRUCTURE: Slot.STRUCTURE_2S, Slot.GRAPHITE: Slot.GRAPHITE_2S}

## Hull stations: z, roof y, roof half width, shoulder x/y, chine x/y (the widest line), lower side x/y, belly
## half width, belly y. The sides lean in above the chine and below it, so no face is a vertical slab.
const STATIONS := [
	[-7.25, 1.98, 1.25, 2.35, 1.86, 2.60, -0.20, 2.35, -0.85, 1.90, -1.25],
	[-5.60, 2.25, 1.75, 2.95, 1.84, 3.20, -0.20, 3.00, -0.85, 2.45, -1.32],
	[-3.80, 2.42, 2.05, 3.40, 1.80, 3.75, -0.20, 3.40, -0.85, 2.85, -1.32],
	[-1.60, 2.78, 1.75, 3.40, 1.86, 3.75, -0.20, 3.40, -0.85, 2.85, -1.32],
	[1.40, 2.78, 1.75, 3.40, 1.86, 3.75, -0.20, 3.40, -0.85, 2.85, -1.32],
	[3.60, 2.30, 2.15, 3.40, 1.80, 3.75, -0.20, 3.40, -0.85, 2.85, -1.32],
	[8.30, 2.28, 2.10, 3.35, 1.80, 3.72, -0.20, 3.38, -0.85, 2.82, -1.32],
	[10.86, 2.05, 1.45, 2.25, 1.74, 2.55, -0.20, 2.35, -0.85, 1.90, -1.28]]
## Canopy nose stations (same layout), from the hull's front station forward to the tip. The roof and shoulder
## strips of the first two segments are the canopy glass.
const NOSE_STATIONS := [
	[-8.00, 1.42, 1.05, 1.95, 1.22, 2.32, -0.22, 2.10, -0.85, 1.60, -1.22],
	[-8.70, 0.25, 0.70, 1.45, 0.10, 1.85, -0.26, 1.66, -0.82, 1.18, -1.15],
	[-9.25, -0.15, 0.42, 0.92, -0.22, 1.22, -0.36, 1.08, -0.74, 0.72, -1.00]]
## The chine steps in this far (and 0.1 m down) to the structural band: a shadow line along the whole hull.
const CHINE_STEP := 0.13
const TAIL_Z := 10.86
const NOSE_TIP_Z := -9.25
## Rear doorway in the loading face, around the airlock outer door (x +-0.7, 2.1 m high from the floor).
const DOORWAY := Rect2(-0.95, -0.95, 1.9, 2.25)
## Engine pod tilt pivot (port is -x). Pods are authored intake at local -z, nozzle at +z, and pitch about x:
## 0 = level for flight, 90 degrees = upright (nozzle down) for landing and hover.
const POD_PIVOT := Vector3(5.0, 1.15, 7.0)
const POD_RADIUS := 0.95 # to the flats of the octagon
const POD_HALF_LENGTH := 2.0
const NOZZLE_LENGTH := 0.7
const POD_TILT_RATE := 1.2 # radians per second
const RAMP_THICKNESS := 0.12
## Leaf 2's hinge sits this far below leaf 1's underside so the folded leaves' stiffeners clear each other.
const RAMP_FOLD_GAP := 0.08
const RAMP_RAM_ANCHOR := Vector3(1.0, 0.9, 10.98) # x is mirrored
const RAMP_RAM_LEAF_POINT := Vector3(1.0, -0.06, 0.9) # on leaf 1, leaf-local
const TURRET_DECK_Y := 2.42
const TURRET_PIVOT_Y := 2.7

var materials := {} # Slot -> Material
## Untinted albedo of each painted material, so restyle() can re-apply VisualStyle.hull_tint() in place.
var _paint_base := {} # Slot -> Color
var turret_pivot := Node3D.new()
var ramp_pivot := Node3D.new()      # leaf 1, hinged at the door sill
var ramp_second_pivot := Node3D.new() # leaf 2, hinged at the far bottom edge of leaf 1
var ramp_light := OmniLight3D.new()
var _rams := [] # [{sleeve, rod, side}]
var _exhaust_discs: Array[MeshInstance3D] = []
var _exhaust_level := 0.0
var _hot_glow: Material
var _layout: InteriorLayout
var _pod_pivots: Array[Node3D] = []
var _nacelles: Array[MeshInstance3D] = []
var _pod_tilt := PI * 0.5


## Builds everything under `parent`. The two nacelles (nozzle material, one exhaust disc each) are added as
## direct children of `parent`; `nozzle_material` and `exhaust_disc` come from ShipVisuals so the asset switch
## and the engine glow stay where they were.
func build(parent: Node3D, layout: InteriorLayout, turret_muzzle: Vector3, nozzle_material: Material, make_exhaust_disc: Callable) -> void:
	_layout = layout
	_make_materials()
	var hull := HullMeshBuilder.new()
	_build_pressure_hull(hull)
	_build_canopy_nose(hull)
	_build_loading_face(hull)
	_build_stub_wings(hull)
	_build_landing_gear(hull)
	_build_belly_and_sides(hull)
	_build_dorsal(hull, turret_muzzle)
	parent.add_child(_instance(hull, "HullStatic"))
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "PodPivot_%s" % ("port" if side < 0.0 else "starboard")
		pivot.position = Vector3(side * POD_PIVOT.x, POD_PIVOT.y, POD_PIVOT.z)
		parent.add_child(pivot)
		pivot.add_child(_instance(_engine_pod(side), "Pod"))
		_pod_pivots.append(pivot)
		var nozzle := CylinderMesh.new()
		nozzle.top_radius = 0.6
		nozzle.bottom_radius = 0.74
		nozzle.height = NOZZLE_LENGTH
		nozzle.radial_segments = 24
		var nacelle := MeshInstance3D.new()
		nacelle.name = "Nozzle_%s" % ("port" if side < 0.0 else "starboard")
		nacelle.mesh = nozzle
		nacelle.material_override = nozzle_material
		var disc: MeshInstance3D = make_exhaust_disc.call(NOZZLE_LENGTH * 0.5 + 0.012, 0.48) # proud of the cap: flush, it z-fought
		if disc != null:
			nacelle.add_child(disc)
			_exhaust_discs.append(disc)
		# The nacelle stays a direct child of `parent` (ShipVisuals finds it there) and follows its pod in update_pods.
		parent.add_child(nacelle)
		_nacelles.append(nacelle)
	update_pods(true, 0.0)
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


## Tilts both pods toward upright (`upright`) or level, and carries the nozzles with them. delta 0 snaps.
func update_pods(upright: bool, delta: float) -> void:
	var target := PI * 0.5 if upright else 0.0
	_pod_tilt = target if delta <= 0.0 else move_toward(_pod_tilt, target, POD_TILT_RATE * delta)
	for index in _pod_pivots.size():
		_pod_pivots[index].rotation.x = _pod_tilt
		# Cylinder +y (its top cap, where the exhaust disc sits) -> pod +z (aft, the nozzle exit).
		var nozzle_local := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, POD_HALF_LENGTH + NOZZLE_LENGTH * 0.5))
		_nacelles[index].transform = _pod_pivots[index].transform * nozzle_local


# --- materials -------------------------------------------------------------------------------------------------

func _make_materials() -> void:
	# An owned copy, so the visual-style tint never reaches the shared asset (other users of mat_hull_plating).
	materials[Slot.HULL] = AssetLibrary.material_or("mat_hull_plating", _paint(Color(0.74, 0.72, 0.67), 0.6, 0.05)).duplicate()
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
	glass.albedo_color = Color(0.08, 0.12, 0.16, 0.82) # tinted, reflective canopy glass from outside
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.85
	glass.roughness = 0.06
	glass.cull_mode = BaseMaterial3D.CULL_BACK # from inside the canopy the pilot looks through the culled back faces
	materials[Slot.GLASS] = glass
	for slot in TWO_SIDED:
		var two_sided := (materials[slot] as Material).duplicate() as BaseMaterial3D
		two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
		materials[TWO_SIDED[slot]] = two_sided
	for slot in [Slot.HULL, Slot.PANEL, Slot.STRUCTURE, Slot.GRAPHITE, Slot.HULL_2S, Slot.STRUCTURE_2S, Slot.GRAPHITE_2S]:
		if materials[slot] is BaseMaterial3D:
			_paint_base[slot] = (materials[slot] as BaseMaterial3D).albedo_color
	restyle()


## Applies the visual style's hull tint to the painted materials (in place, so every part using them follows).
func restyle() -> void:
	var tint := VisualStyle.hull_tint()
	for slot in _paint_base:
		(materials[slot] as BaseMaterial3D).albedo_color = (_paint_base[slot] as Color) * tint


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
	var slots := HullMeshBuilder.mirror_slots(PackedInt32Array(PROFILE_SLOTS))
	# The cockpit's glass wall is gone, so the first segment (round the cockpit's front) is seen from inside too.
	hull.add_loft([rings[0], rings[1]], _two_sided(slots))
	hull.add_loft(rings.slice(1), slots)


static func _two_sided(slots: PackedInt32Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	for slot in slots:
		result.append(TWO_SIDED.get(slot, slot))
	return result


static func _outline_2d(station: Array) -> PackedVector2Array:
	var outline := PackedVector2Array()
	for point in HullMeshBuilder.mirror_ring(_half_profile(station)):
		outline.append(Vector2(point.x, point.y))
	return outline


## The canopy nose: the hull lofted forward to the tip through NOSE_STATIONS. The roof and shoulder strips of the
## first two segments are glass (a raked, faceted canopy) with a structural frame along every glass edge; the rest
## is two-sided so it reads from the cockpit. A dash fills the nose ahead of the cockpit floor (which ends at z -7.0).
func _build_canopy_nose(hull: HullMeshBuilder) -> void:
	var half_rings: Array[PackedVector3Array] = [_half_profile(STATIONS[0])]
	for station in NOSE_STATIONS:
		half_rings.append(_half_profile(station))
	var opaque := _two_sided(HullMeshBuilder.mirror_slots(PackedInt32Array(PROFILE_SLOTS)))
	var canopy := opaque.duplicate()
	for strip in [0, 1, canopy.size() - 1, canopy.size() - 2]: # roof and shoulder strips, both sides
		canopy[strip] = Slot.GLASS
	for segment in 3:
		var rings := [HullMeshBuilder.mirror_ring(half_rings[segment]), HullMeshBuilder.mirror_ring(half_rings[segment + 1])]
		hull.add_loft(rings, canopy if segment < 2 else opaque, Transform3D.IDENTITY, false, -1, Slot.STRUCTURE_2S if segment == 2 else -1)
	# Canopy frame: the three cross-frames and the two longitudinal frames per side along the glass edges.
	for ring_index in 3:
		var ring := half_rings[ring_index]
		for side in [-1.0, 1.0]:
			var mirror := Vector3(side, 1, 1)
			hull.add_bar(ring[0] * mirror, ring[1] * mirror, 0.08, Slot.STRUCTURE)
			hull.add_bar(ring[1] * mirror, ring[2] * mirror, 0.08, Slot.STRUCTURE)
	for side in [-1.0, 1.0]:
		var mirror := Vector3(side, 1, 1)
		for point in [1, 2]:
			hull.add_bar(half_rings[0][point] * mirror, half_rings[1][point] * mirror, 0.07, Slot.STRUCTURE)
			hull.add_bar(half_rings[1][point] * mirror, half_rings[2][point] * mirror, 0.07, Slot.STRUCTURE)
	hull.add_bar(half_rings[0][0], half_rings[1][0], 0.06, Slot.STRUCTURE)
	hull.add_bar(half_rings[1][0], half_rings[2][0], 0.06, Slot.STRUCTURE)
	# Dash: fills the nose floor ahead of the cockpit, below the pilot's sight line.
	hull.add_chamfer_box(Vector3(3.0, 0.8, 1.3), 0.08, Slot.GRAPHITE, Transform3D(Basis.IDENTITY, Vector3(0, -0.55, -7.65)))
	# Nose tip: sensor aperture and the two landing lights.
	var tip_y: float = (NOSE_STATIONS[2][6] + NOSE_STATIONS[2][8]) * 0.5
	hull.add_chamfer_box(Vector3(0.9, 0.18, 0.05), 0.04, Slot.RECESS, Transform3D(Basis.IDENTITY, Vector3(0, tip_y, NOSE_TIP_Z - 0.01)))
	for side in [-1.0, 1.0]:
		hull.add_cylinder(10, 0.08, 0.08, -0.04, 0.0, Slot.LIGHT, Transform3D(Basis.IDENTITY, Vector3(side * 0.78, tip_y, NOSE_TIP_Z)))


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

## One engine pod in its pivot's frame (intake at -z, nozzle mount at +z, outboard is +x * side).
func _engine_pod(side: float) -> HullMeshBuilder:
	var pod := HullMeshBuilder.new()
	var corner := POD_RADIUS / cos(PI / 8.0)
	var start := PI / 8.0
	var front := -POD_HALF_LENGTH
	var rear := POD_HALF_LENGTH
	# Octagon strips, top first, clockwise seen from the intake (outboard for starboard first).
	var pod_slots := PackedInt32Array([Slot.HULL, Slot.HULL, Slot.PANEL, Slot.STRUCTURE, Slot.GRAPHITE, Slot.STRUCTURE, Slot.PANEL, Slot.HULL])
	var rings := [
		HullMeshBuilder.polygon_ring(8, corner * 0.8, front, start),
		HullMeshBuilder.polygon_ring(8, corner, front + 0.35, start),
		HullMeshBuilder.polygon_ring(8, corner, rear - 0.7, start),
		HullMeshBuilder.polygon_ring(8, corner * 0.84, rear, start)]
	pod.add_loft([rings[0], rings[1]], PackedInt32Array([Slot.STRUCTURE]))
	pod.add_loft([rings[1], rings[2], rings[3]], pod_slots, Transform3D.IDENTITY, false, -1, Slot.GRAPHITE)
	# Intake: a short throat inside the lip, a dark face, the fan hub and four stator vanes.
	var throat := [HullMeshBuilder.polygon_ring(8, corner * 0.8, front, start), HullMeshBuilder.polygon_ring(8, corner * 0.72, front + 0.3, start)]
	pod.add_loft(throat, PackedInt32Array([Slot.GRAPHITE]), Transform3D.IDENTITY, true)
	pod.add_cap(throat[1], Slot.RECESS, Vector3(0, 0, -1))
	pod.add_cylinder(12, 0.08, 0.22, front + 0.06, front + 0.29, Slot.METAL, Transform3D.IDENTITY, Slot.METAL)
	for vane in 4:
		var angle := PI * 0.25 + PI * 0.5 * vane
		var tip := Vector3(sin(angle), cos(angle), 0) * corner * 0.7
		pod.add_bar(Vector3(0, 0, front + 0.25) + tip * 0.3, Vector3(0, 0, front + 0.25) + tip, 0.05, Slot.STRUCTURE)
	# Structural collar round the tilt axis, the bearing the stub wing's hub enters, and the outboard actuator.
	pod.add_cylinder(8, corner * 1.05, corner * 1.05, -0.4, 0.4, Slot.STRUCTURE)
	var axis := Basis(Vector3.UP, PI * 0.5) # local z -> pod x
	pod.add_cylinder(10, 0.4, 0.34, 0.0, side * 0.16, Slot.STRUCTURE, Transform3D(axis, Vector3(side * (POD_RADIUS + 0.03), 0, 0)))
	pod.add_cylinder(10, 0.14, 0.14, 0.0, side * 0.2, Slot.SAFETY, Transform3D(axis, Vector3(side * (POD_RADIUS + 0.03), 0, 0)))
	# Nav light on the outboard side near the intake (red port, green starboard).
	pod.add_chamfer_box(Vector3(0.05, 0.12, 0.24), 0.015, Slot.NAV_PORT if side < 0.0 else Slot.NAV_STARBOARD, Transform3D(Basis.IDENTITY, Vector3(side * (POD_RADIUS + 0.02), 0.25, front + 0.7)))
	# Nozzle mount ring between the pod tail and the nozzle.
	pod.add_cylinder(16, 0.82, 0.8, rear - 0.02, rear + 0.08, Slot.GRAPHITE)
	return pod


## Stub wings: a thick tapered wing from each hull side to the pod's tilt bearing, with the bearing hub at its tip.
func _build_stub_wings(hull: HullMeshBuilder) -> void:
	var root_x := 3.3 # inside the hull side (x 3.5..3.6 at these heights)
	var tip_x := POD_PIVOT.x - POD_RADIUS + 0.05
	var root := [Vector2(5.9, 1.15), Vector2(6.3, 1.45), Vector2(7.7, 1.45), Vector2(8.1, 1.2), Vector2(8.0, 0.85), Vector2(6.2, 0.85)]
	var tip := [Vector2(6.35, 1.15), Vector2(6.6, 1.38), Vector2(7.4, 1.38), Vector2(7.65, 1.18), Vector2(7.55, 0.92), Vector2(6.55, 0.92)]
	for side in [-1.0, 1.0]:
		var ring_root := PackedVector3Array()
		var ring_tip := PackedVector3Array()
		for point in root:
			ring_root.append(Vector3(side * root_x, point.y, point.x))
		for point in tip:
			ring_tip.append(Vector3(side * tip_x, point.y, point.x))
		# Strips: leading-edge top, top, trailing top, trailing bottom, bottom, leading bottom.
		hull.add_loft([ring_root, ring_tip], PackedInt32Array([Slot.STRUCTURE, Slot.HULL, Slot.STRUCTURE, Slot.STRUCTURE, Slot.GRAPHITE, Slot.STRUCTURE]))
		# Bearing hub on the tilt axis.
		var hub := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(side * (tip_x - 0.25), POD_PIVOT.y, POD_PIVOT.z))
		hull.add_cylinder(12, 0.42, 0.42, 0.0, side * 0.32, Slot.STRUCTURE, hub)


# --- landing gear ----------------------------------------------------------------------------------------------

## Rail sections: z, centre x, width, top y, bottom y. The ends taper and tuck into the hull.
const RAIL_STATIONS := [[-6.5, 2.55, 0.5, -0.92, -1.28], [-5.6, 2.85, 0.9, -0.9, -1.5], [9.0, 2.85, 0.9, -0.9, -1.5], [9.8, 2.45, 0.5, -0.88, -1.3]]


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
		# Rub strake: a protective bumper along the chine where it is full width (z -3.8 .. 8.3), ahead of the pods.
		hull.add_chamfer_box(Vector3(0.1, 0.12, 9.2), 0.035, Slot.GRAPHITE, Transform3D(Basis.IDENTITY, Vector3(side * 3.77, -0.22, 1.0)))
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
	var hump_y: float = STATIONS[3][1]
	var roof_y: float = STATIONS[5][1] # the flat roof aft of the hump, where the turret and hatch sit
	# Heat exchangers on the flat top of the dorsal hump: two recessed louvred grilles side by side.
	for side in [-1.0, 1.0]:
		var grille := Transform3D(Basis.IDENTITY, Vector3(side * 0.8, hump_y + 0.008, -0.1))
		hull.add_chamfer_box(Vector3(1.25, 0.02, 2.5), 0.005, Slot.RECESS, grille)
		for fin in 10:
			hull.add_chamfer_box(Vector3(1.15, 0.05, 0.04), 0.01, Slot.STRUCTURE, grille * Transform3D(Basis.IDENTITY, Vector3(0, 0.025, -1.08 + fin * 0.24)))
		hull.add_chamfer_box(Vector3(1.33, 0.06, 2.6), 0.02, Slot.GRAPHITE, grille * Transform3D(Basis.IDENTITY, Vector3(0, -0.02, 0)))
	# Turret barbette: an armoured ring on the roof around the gun's mount point.
	var barbette := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(turret_muzzle.x, roof_y - 0.04, turret_muzzle.z))
	hull.add_cylinder(12, 0.95, 0.85, 0.0, TURRET_DECK_Y - roof_y + 0.02, Slot.STRUCTURE, barbette, -1)
	hull.add_cylinder(12, 0.84, 0.84, TURRET_DECK_Y - roof_y + 0.02, TURRET_DECK_Y - roof_y + 0.03, Slot.GRAPHITE, barbette)
	# Cargo roof hatch aft of the turret, with orange lift points at its corners.
	var hatch := Transform3D(Basis.IDENTITY, Vector3(0, roof_y, 6.8)) # half sunk: the roof falls 2 cm over its length
	hull.add_chamfer_box(Vector3(2.4, 0.05, 1.7), 0.025, Slot.PANEL, hatch)
	for corner_x in [-1.05, 1.05]:
		for corner_z in [-0.7, 0.7]:
			hull.add_chamfer_box(Vector3(0.14, 0.05, 0.14), 0.02, Slot.SAFETY, hatch * Transform3D(Basis.IDENTITY, Vector3(corner_x, 0.03, corner_z)))
	# Tail light at the roof's rear edge.
	hull.add_chamfer_box(Vector3(0.3, 0.05, 0.08), 0.015, Slot.LIGHT, Transform3D(Basis.IDENTITY, Vector3(0, STATIONS[STATIONS.size() - 1][1] - 0.02, TAIL_Z - 0.05)))


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
