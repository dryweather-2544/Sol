class_name PoiManager
extends Node3D
## Keeps POI scenery matched to the viewer: plans nearby POIs as data, and only builds nodes for the
## ones in a ring (marker beams from the proxy ring inward, props from the content ring inward).

const UPDATE_INTERVAL_SECONDS := 0.5
const REPLAN_DISTANCE := 2000.0

var planner: PoiPlanner
var planet: PlanetBody
var render_origin := WorldPos.new(&"planet")
var viewer := WorldPos.new(&"planet")

var _known := {}    # id -> PoiInstance
var _rings := {}    # id -> PoiRings.Ring
var _content := {}  # id -> Node3D
var _markers := {}  # id -> Node3D
var _replan_center: WorldPos
var _seconds_since_update := UPDATE_INTERVAL_SECONDS


func _init(poi_planner: PoiPlanner = null) -> void:
	name = "PoiManager"
	planner = poi_planner
	planet = poi_planner.planet if poi_planner != null else null


func _ready() -> void:
	add_to_group("origin_shift")


func _process(delta: float) -> void:
	_seconds_since_update += delta
	if _seconds_since_update >= UPDATE_INTERVAL_SECONDS:
		_seconds_since_update = 0.0
		update_now()


func apply_origin_shift(shift: Vector3) -> void:
	render_origin = render_origin.offset_by(shift)
	for poi_id in _content:
		_place(_content[poi_id], _known[poi_id])
	for poi_id in _markers:
		_place(_markers[poi_id], _known[poi_id])


## Forget the planned region so the next update plans again (after a POI was pinned by hand).
func invalidate_plan() -> void:
	_replan_center = null


func known_instances() -> Array[PoiInstance]:
	var instances: Array[PoiInstance] = []
	for instance in _known.values():
		instances.append(instance)
	return instances


func content_node_count() -> int:
	return _content.size()


func marker_node_count() -> int:
	return _markers.size()


func ring_of(poi_id: StringName) -> int:
	return _rings.get(poi_id, PoiRings.Ring.NONE)


## Nearest POI the player has not discovered yet, or null.
func nearest_undiscovered(discovery_log: DiscoveryLog) -> PoiInstance:
	var best: PoiInstance
	var best_distance := INF
	for instance in _known.values():
		if discovery_log.is_discovered(instance.id):
			continue
		var distance: float = instance.position.distance_to(viewer)
		if distance < best_distance:
			best = instance
			best_distance = distance
	return best


func update_now() -> void:
	if _replan_center == null or viewer.distance_to(_replan_center) > REPLAN_DISTANCE:
		_replan_center = viewer.duplicate_position()
		for instance in planner.plan_region(viewer, PoiRings.PROXY_EXIT + REPLAN_DISTANCE * 2.0):
			_known[instance.id] = instance
		_forget_distant()
	for poi_id in _known:
		var instance: PoiInstance = _known[poi_id]
		var distance: float = instance.position.distance_to(viewer)
		var previous: int = _rings.get(poi_id, PoiRings.Ring.NONE)
		var ring := PoiRings.update_ring(distance, previous)
		_rings[poi_id] = ring
		_set_marker(instance, ring >= PoiRings.Ring.PROXY, distance)
		_set_content(instance, ring >= PoiRings.Ring.CONTENT)


func _forget_distant() -> void:
	var forget: Array[StringName] = []
	for poi_id in _known:
		if (_known[poi_id] as PoiInstance).position.distance_to(viewer) > PoiRings.PROXY_EXIT * 3.0:
			forget.append(poi_id)
	for poi_id in forget:
		_set_marker(_known[poi_id], false, 0.0)
		_set_content(_known[poi_id], false)
		_known.erase(poi_id)
		_rings.erase(poi_id)


func _set_marker(instance: PoiInstance, wanted: bool, distance: float) -> void:
	if wanted and not _markers.has(instance.id):
		var marker := PoiBuilder.build_marker(instance)
		if marker == null:
			return
		add_child(marker)
		_markers[instance.id] = marker
		_place(marker, instance)
	elif not wanted and _markers.has(instance.id):
		_discard(_markers[instance.id])
		_markers.erase(instance.id)
	if wanted and _markers.has(instance.id):
		# Keep the beam visible from far away: its width grows with distance.
		var width := 1.0 + distance * 0.0015
		(_markers[instance.id] as Node3D).scale = Vector3(width, 1.0, width)


func _set_content(instance: PoiInstance, wanted: bool) -> void:
	if wanted and not _content.has(instance.id):
		var content := PoiBuilder.build_content(instance, planet)
		add_child(content)
		_content[instance.id] = content
		_place(content, instance)
	elif not wanted and _content.has(instance.id):
		_discard(_content[instance.id])
		_content.erase(instance.id)


func _place(node: Node3D, instance: PoiInstance) -> void:
	var kept_scale := node.scale
	node.transform = Transform3D(PoiBuilder.frame_basis(instance), instance.position.to_local_vector3(render_origin))
	node.scale = kept_scale
	node.reset_physics_interpolation()


func _discard(node: Node) -> void:
	if is_inside_tree():
		node.queue_free()
	else:
		node.free()
