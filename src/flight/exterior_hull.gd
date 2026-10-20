class_name ExteriorHull
extends Node3D
## Prototype: a Cargo Spaceship (CC-BY, blaice) shown as the ship's outside while the blockout keeps being the ship for flight,
## collision and walking. The hull sits on render layer 3 and is seen only by the outside cameras (chase, on foot); the blockout
## moves to layer 2 and is seen only by the inside cameras (cockpit, interior). The ramp and the outer door stay on layer 1
## (seen by every camera) because the player stands on or at them; the hull has its own legs, so the blockout's gear is hidden outside. Flight, thrust and turning are untouched. What does follow
## the hull: ShipHullCollision's width (HullSilhouette, measured from the hull) and ShipTuning.support_points (four short visible legs
## of the hull plus nose and tail points), because the hull's belly is not flat (about 1 m above ground at the nose, level at the tail).

const SCENE_PATH := "res://assets/third_party/ships/cargo_spaceship/scene.gltf"
const INTERIOR_LAYER := 2
const HULL_LAYER := 3
const ALL_LAYERS := 0xFFFFF
## Marks a blockout piece that outside cameras must keep seeing.
const SHARED_META := &"shared_with_outside"
## ShipTuning's landing-gear contact height: the hull's lowest point rests there.
const BOTTOM_Y := -2.0

## Landing legs: x offset and z of the front and rear pairs, chosen where the hull's belly is solid.
const GEAR_FRONT := Vector2(1.0, -2.0)
const GEAR_REAR := Vector2(3.0, 8.0)
const LEG_WIDTH := 0.35
const LEG_META := &"landing_leg"
## How far a leg reaches up into the hull so no gap shows at its top.
const LEG_OVERLAP := 0.15
## The nose underside point of the blockout's support points, which sits where the hull's nose underside is.
const NOSE_POINT := Vector3(0.0, -0.9, -7.3)

var active := false
## Seen-from-above width of the hull (null when not active); used by ShipHullCollision.
var silhouette: HullSilhouette
## The hull's bounds in ship-local metres once placed (empty when not active).
var bounds_in_ship := AABB()
var _rodina_materials := false
var _saved_surface_overrides := {} # MeshInstance3D -> Array[Material]
var _rodina_material_cache := {} # original Material -> Material


static func layer_bit(layer_number: int) -> int:
	return 1 << (layer_number - 1)


static func mask_hiding(layer_number: int) -> int:
	return ALL_LAYERS & ~layer_bit(layer_number)


func _ready() -> void:
	name = "ExteriorHull"
	if not GameSettings.instance().exterior_hull:
		return
	var packed: PackedScene = ResourceLoader.load(SCENE_PATH) as PackedScene if ResourceLoader.exists(SCENE_PATH) else null
	if packed == null:
		AssetLibrary.warn_once("exterior_hull", "exterior hull '%s' missing or not imported (keeping the blockout exterior)" % SCENE_PATH)
		return
	var hull := packed.instantiate() as Node3D
	add_child(hull)
	var native := _native_bounds(hull)
	# Sized to the blockout's hull box: nose (the narrow end, low z in the model) at HULL_FRONT_Z, the wide rear block at HULL_REAR_Z,
	# so the airlock (z 8.2 to 10.6) and the ramp behind it meet the rear block.
	var factor := (ShipHullCollision.HULL_REAR_Z - ShipHullCollision.HULL_FRONT_Z) / native.size.z
	hull.scale = Vector3.ONE * factor
	hull.position = Vector3(-native.get_center().x * factor, BOTTOM_Y - native.position.y * factor, ShipHullCollision.HULL_FRONT_Z - native.position.z * factor)
	bounds_in_ship = AABB(native.position * factor + hull.position, native.size * factor)
	for instance in hull.find_children("*", "GeometryInstance3D", true, false):
		(instance as GeometryInstance3D).layers = layer_bit(HULL_LAYER)
	var points := _ship_local_points(hull)
	silhouette = HullSilhouette.from_points(points, ShipHullCollision.HULL_FRONT_Z, ShipHullCollision.HULL_REAR_Z, BOTTOM_Y - 0.1, bounds_in_ship.end.y + 0.1)
	for gear in [GEAR_FRONT, GEAR_REAR]:
		for side in [-1.0, 1.0]:
			_add_leg(points, side * gear.x, gear.y)
	active = true


## Rodina profile: keep the cargo hull geometry and collision, but replace its yellow PBR surfaces
## with a restrained dark industrial material. Emissive maps/normal detail are retained so small
## accents and panel shape still read; the original surface overrides are restored for Sol.
func apply_visual_style(rodina: bool) -> void:
	if not active or rodina == _rodina_materials:
		return
	_rodina_materials = rodina
	for instance in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := instance as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		if rodina:
			if not _saved_surface_overrides.has(mesh_instance):
				var saved: Array[Material] = []
				for surface in mesh_instance.mesh.get_surface_count():
					saved.append(mesh_instance.get_surface_override_material(surface))
				_saved_surface_overrides[mesh_instance] = saved
			for surface in mesh_instance.mesh.get_surface_count():
				var original := mesh_instance.get_surface_override_material(surface)
				if original == null:
					original = mesh_instance.mesh.surface_get_material(surface)
				var dark_material := _rodina_material(original)
				mesh_instance.set_surface_override_material(surface, dark_material)
		else:
			var saved_overrides: Array = _saved_surface_overrides.get(mesh_instance, [])
			for surface in mesh_instance.mesh.get_surface_count():
				mesh_instance.set_surface_override_material(surface, saved_overrides[surface] if surface < saved_overrides.size() else null)
	_saved_surface_overrides.clear() if not rodina else null


func _rodina_material(original: Material) -> Material:
	if _rodina_material_cache.has(original):
		return _rodina_material_cache[original]
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.16, 0.17, 0.19)
	dark.metallic = 0.22
	dark.roughness = 0.84
	if original is BaseMaterial3D:
		var source := original as BaseMaterial3D
		dark.albedo_texture = source.albedo_texture
		dark.normal_enabled = source.normal_enabled
		dark.normal_texture = source.normal_texture
		dark.normal_scale = source.normal_scale
		dark.ao_enabled = source.ao_enabled
		dark.ao_texture = source.ao_texture
		dark.emission_enabled = source.emission_enabled
		dark.emission_texture = source.emission_texture
		dark.emission = source.emission
		dark.emission_energy_multiplier = source.emission_energy_multiplier * 0.02
	_rodina_material_cache[original] = dark
	return dark


## The four gear contacts (same order GroundContact fits its ground plane to: -x-z, +x-z, -x+z, +x+z), then the nose and tail points that
## stop the hull passing through terrain. All gear contacts rest at the hull's lowest height, so the legs make up the belly's differences.
func support_points() -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(-GEAR_FRONT.x, BOTTOM_Y, GEAR_FRONT.y), Vector3(GEAR_FRONT.x, BOTTOM_Y, GEAR_FRONT.y),
		Vector3(-GEAR_REAR.x, BOTTOM_Y, GEAR_REAR.y), Vector3(GEAR_REAR.x, BOTTOM_Y, GEAR_REAR.y),
		NOSE_POINT, Vector3(0.0, BOTTOM_Y, ShipHullCollision.HULL_REAR_Z - 0.5)])


## A short strut from the hull's belly at (x, z) down to BOTTOM_Y, on the hull layer.
func _add_leg(points: PackedVector3Array, x: float, z: float) -> void:
	var belly := BOTTOM_Y + 0.5 # fallback if the hull has no geometry there
	var lowest := INF
	for point in points:
		if absf(point.x - x) < 0.8 and absf(point.z - z) < 1.0:
			lowest = minf(lowest, point.y)
	if lowest != INF:
		belly = lowest
	var height := belly - BOTTOM_Y + LEG_OVERLAP
	if height <= LEG_OVERLAP + 0.02:
		return # the hull already reaches the ground here
	var leg := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(LEG_WIDTH, height, LEG_WIDTH)
	leg.mesh = box
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = Color(0.16, 0.17, 0.18)
	fallback.metallic = 0.8
	fallback.roughness = 0.5
	leg.material_override = AssetLibrary.material_or("mat_ship_brushed_metal", fallback)
	leg.layers = layer_bit(HULL_LAYER)
	leg.position = Vector3(x, BOTTOM_Y + height * 0.5, z)
	leg.set_meta(LEG_META, true) # Godot renames duplicate node names, so tests and tools find legs by this
	add_child(leg)


## Moves the blockout's own pieces to the inside layer (and off the sun's shadow pass, so outside views show only the hull's shadow).
## Pieces flagged SHARED_META stay on layer 1.
static func hide_blockout_from_outside(visuals: Node) -> void:
	for node in visuals.find_children("*", "", true, false):
		if node.has_meta(SHARED_META):
			continue
		if node is GeometryInstance3D:
			(node as GeometryInstance3D).layers = layer_bit(INTERIOR_LAYER)
			(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif node is Decal:
			(node as Decal).layers = layer_bit(INTERIOR_LAYER)


static func apply_camera_masks(outside_cameras: Array, inside_cameras: Array) -> void:
	for camera in outside_cameras:
		(camera as Camera3D).cull_mask = mask_hiding(INTERIOR_LAYER)
	for camera in inside_cameras:
		(camera as Camera3D).cull_mask = mask_hiding(HULL_LAYER)


## Bounds of every mesh under root_node in root_node's own frame (root_node's transform excluded), without needing the tree.
static func _native_bounds(root_node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh_instance in root_node.find_children("*", "MeshInstance3D", true, false):
		var to_root := Transform3D.IDENTITY
		var node: Node = mesh_instance
		while node != root_node:
			to_root = (node as Node3D).transform * to_root
			node = node.get_parent()
		var box := to_root * (mesh_instance as MeshInstance3D).get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


## Every mesh vertex under hull in ship-local space (hull's own placement included), without needing the tree.
func _ship_local_points(hull: Node3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	for mesh_instance in hull.find_children("*", "MeshInstance3D", true, false):
		var to_hull := Transform3D.IDENTITY
		var node: Node = mesh_instance
		while node != hull:
			to_hull = (node as Node3D).transform * to_hull
			node = node.get_parent()
		var to_ship := hull.transform * to_hull
		var mesh := (mesh_instance as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			for vertex in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
				result.append(to_ship * vertex)
	return result
