class_name PoiPlanner
extends RefCounted
## Plans POIs as data, per lattice cell, on demand (ADR 0004). Same planet seed + same
## generation_version = same POIs, in any process, in any order of planning.

const CELL_SIZE := 4000.0
const GENERATION_VERSION := 1
const CANDIDATE_SITES := 5
const SLOPE_PROBE_METRES := 25.0

var planet: PlanetBody
var planet_seed: int
## Chance that a cell holds a POI.
var density := 0.22
## Put in POI ids so worlds never share ids; empty keeps the original home-planet ids (and saves).
var id_prefix := ""
var _cache := {} # cell id -> PoiInstance or null


func _init(planet_body: PlanetBody, seed_for_planet: int, cell_density: float = 0.22, poi_id_prefix: String = "") -> void:
	id_prefix = poi_id_prefix
	planet = planet_body
	planet_seed = seed_for_planet
	density = cell_density


## All POIs whose cell lies within radius_metres (plus a cell of margin) of the centre.
func plan_region(center: WorldPos, radius_metres: float) -> Array[PoiInstance]:
	var found: Array[PoiInstance] = []
	var reach := radius_metres + CELL_SIZE * 2.0
	var low_i := int(floor((center.x - reach) / CELL_SIZE))
	var high_i := int(floor((center.x + reach) / CELL_SIZE))
	var low_j := int(floor((center.y - reach) / CELL_SIZE))
	var high_j := int(floor((center.y + reach) / CELL_SIZE))
	var low_k := int(floor((center.z - reach) / CELL_SIZE))
	var high_k := int(floor((center.z + reach) / CELL_SIZE))
	for cell_i in range(low_i, high_i + 1):
		for cell_j in range(low_j, high_j + 1):
			for cell_k in range(low_k, high_k + 1):
				if not _cell_can_reach_surface(cell_i, cell_j, cell_k):
					continue
				var instance := plan_cell(cell_i, cell_j, cell_k)
				if instance != null and instance.position.distance_to(center) <= radius_metres:
					found.append(instance)
	return found


func plan_cell(cell_i: int, cell_j: int, cell_k: int) -> PoiInstance:
	var cell_id := _cell_id(cell_i, cell_j, cell_k)
	if _cache.has(cell_id):
		return _cache[cell_id]
	var instance := _build_cell(cell_i, cell_j, cell_k, cell_id)
	_cache[cell_id] = instance
	return instance


func planned_count() -> int:
	var count := 0
	for instance in _cache.values():
		if instance != null:
			count += 1
	return count


## Only cells that the planet-radius sphere passes through can hold a surface POI (each direction has at least one).
func _cell_can_reach_surface(cell_i: int, cell_j: int, cell_k: int) -> bool:
	var center_x := (cell_i + 0.5) * CELL_SIZE
	var center_y := (cell_j + 0.5) * CELL_SIZE
	var center_z := (cell_k + 0.5) * CELL_SIZE
	var distance := sqrt(center_x * center_x + center_y * center_y + center_z * center_z)
	var half_diagonal := CELL_SIZE * 0.87
	return absf(distance - planet.radius) <= half_diagonal


func _cell_id(cell_i: int, cell_j: int, cell_k: int) -> StringName:
	if id_prefix == "":
		return StringName("poi_%d_%d_%d" % [cell_i, cell_j, cell_k])
	return StringName("poi_%s_%d_%d_%d" % [id_prefix, cell_i, cell_j, cell_k])


func _build_cell(cell_i: int, cell_j: int, cell_k: int, cell_id: StringName) -> PoiInstance:
	var cell_seed := SeedHash.combine(SeedHash.combine(SeedHash.combine(planet_seed, cell_i & 0xFFFFFFFF), cell_j & 0xFFFFFFFF), cell_k & 0xFFFFFFFF)
	cell_seed = SeedHash.combine(cell_seed, GENERATION_VERSION)
	var rng := SeedRng.new(cell_seed)
	if rng.next_float() >= density:
		return null
	var type := PoiDefinition.pick_type(rng.next_float())
	var best_position: WorldPos
	var best_slope := INF
	for site in CANDIDATE_SITES:
		var point_x := (cell_i + rng.next_float()) * CELL_SIZE
		var point_y := (cell_j + rng.next_float()) * CELL_SIZE
		var point_z := (cell_k + rng.next_float()) * CELL_SIZE
		var distance := sqrt(point_x * point_x + point_y * point_y + point_z * point_z)
		if distance < 1.0:
			continue
		var direction_x := point_x / distance
		var direction_y := point_y / distance
		var direction_z := point_z / distance
		var slope := _slope_at(direction_x, direction_y, direction_z)
		if slope < best_slope:
			best_slope = slope
			var ground := planet.surface_radius_xyz(direction_x, direction_y, direction_z)
			best_position = WorldPos.new(planet.frame_id, direction_x * ground, direction_y * ground, direction_z * ground)
	if best_position == null:
		return null
	var instance := PoiInstance.new()
	instance.id = cell_id
	instance.type = type
	instance.seed_value = cell_seed
	instance.generation_version = GENERATION_VERSION
	instance.position = best_position
	instance.display_name = "%s %02X-%03d" % [PoiDefinition.TYPE_NAMES[type], cell_seed & 0xFF, (cell_seed >> 8) % 1000]
	return instance


## Steepest height change over SLOPE_PROBE_METRES in four directions around a site (rise / run).
func _slope_at(direction_x: float, direction_y: float, direction_z: float) -> float:
	var direction := Vector3(direction_x, direction_y, direction_z)
	var helper := Vector3.RIGHT if absf(direction_x) < 0.9 else Vector3.UP
	var tangent_a := direction.cross(helper).normalized()
	var tangent_b := direction.cross(tangent_a).normalized()
	var base_height := planet.terrain_height_xyz(direction_x, direction_y, direction_z)
	var step := SLOPE_PROBE_METRES / planet.radius
	var steepest := 0.0
	for tangent in [tangent_a, -tangent_a, tangent_b, -tangent_b]:
		var probe_x: float = direction_x + tangent.x * step
		var probe_y: float = direction_y + tangent.y * step
		var probe_z: float = direction_z + tangent.z * step
		var length := sqrt(probe_x * probe_x + probe_y * probe_y + probe_z * probe_z)
		var height := planet.terrain_height_xyz(probe_x / length, probe_y / length, probe_z / length)
		steepest = maxf(steepest, absf(height - base_height) / SLOPE_PROBE_METRES)
	return steepest
