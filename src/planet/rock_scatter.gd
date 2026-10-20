class_name RockScatter
extends MultiMeshInstance3D
## Visual-only boulders around the player on a planet surface. Positions come from a fixed
## planet-frame cell grid, so rocks do not slide when the camera moves; they stream in/out at
## the edge of a short radius. No collision, no gameplay state, no persistence.

const CELL := 22.0
const RADIUS := 175.0
const MAX_ROCKS := 220
const MIN_DISTANCE := 9.0
const REBUILD_DISTANCE := 9.0

var planet: PlanetBody
var density_scale := 1.0
var _last_viewer := WorldPos.new(&"planet")
var _last_origin := WorldPos.new(&"planet", INF, INF, INF)
var _built := false
var _rock_mesh: SphereMesh
var _rock_material: Material


func _ready() -> void:
	name = "RockScatter"
	_rock_mesh = SphereMesh.new()
	_rock_mesh.radius = 0.52
	_rock_mesh.height = 1.04
	_rock_mesh.radial_segments = 6
	_rock_mesh.rings = 3
	_rock_material = AssetLibrary.material_or("mat_terrain_rock_fractured", _fallback_material())
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _rock_mesh
	multimesh.instance_count = 0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _fallback_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.22, 0.20)
	material.roughness = 0.95
	return material


## Rodina mode keeps rocks as sparse landmarks rather than a dense scatter.
func set_density_scale(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if not is_equal_approx(clamped, density_scale):
		density_scale = clamped
		_built = false


## viewer: current player/ship position in the planet frame. origin: render-space origin.
func update_rocks(viewer: WorldPos, origin: WorldPos) -> void:
	if planet == null:
		visible = false
		return
	if _built and viewer.distance_to(_last_viewer) < REBUILD_DISTANCE and origin.is_approximately_equal(_last_origin):
		return
	_last_viewer = viewer.duplicate_position()
	_last_origin = origin.duplicate_position()
	_built = true
	visible = true
	_build(viewer, origin)


func _build(viewer: WorldPos, origin: WorldPos) -> void:
	var viewer_position := Vector3(viewer.x, viewer.y, viewer.z)
	var origin_vec := Vector3(origin.x, origin.y, origin.z)
	var up := viewer_position.normalized()
	var axis := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var right := up.cross(axis).normalized()
	var forward := right.cross(up).normalized()
	var base_x := floori(viewer.x / CELL)
	var base_y := floori(viewer.y / CELL)
	var base_z := floori(viewer.z / CELL)
	var transforms: Array[Transform3D] = []
	var span := int(ceil(RADIUS / CELL))
	for ix in range(-span, span + 1):
		for iy in range(-span, span + 1):
			for iz in range(-span, span + 1):
				if transforms.size() >= MAX_ROCKS:
					break
				var cx := base_x + ix
				var cy := base_y + iy
				var cz := base_z + iz
				var cell_center := Vector3(cx * CELL, cy * CELL, cz * CELL)
				var offset := cell_center - viewer_position
				var tangent := Vector3(offset.dot(right), offset.dot(up), offset.dot(forward))
				var distance := sqrt(tangent.x * tangent.x + tangent.z * tangent.z)
				if distance < MIN_DISTANCE or distance > RADIUS:
					continue
				var rng := RandomNumberGenerator.new()
				rng.seed = SeedHash.string_hash("rock:%d:%d:%d" % [cx, cy, cz])
				if rng.randf() > 0.34 * density_scale:
					continue
				var jitter := Vector3(rng.randf_range(-CELL * 0.42, CELL * 0.42), 0.0, rng.randf_range(-CELL * 0.42, CELL * 0.42))
				var local := tangent + right * jitter.x + forward * jitter.z
				var direction := (up + right * (local.x / planet.radius) + forward * (local.z / planet.radius)).normalized()
				var height := planet.terrain_height_xyz(direction.x, direction.y, direction.z)
				var surface := planet.radius + height
				var world := direction * surface
				var scale_value := Vector3(rng.randf_range(1.1, 4.2), rng.randf_range(0.55, 2.0), rng.randf_range(1.0, 3.4))
				var rotation := Basis.from_euler(Vector3(rng.randf_range(-0.18, 0.18), rng.randf_range(0.0, TAU), rng.randf_range(-0.18, 0.18)))
				var place := world + up * (0.18 * scale_value.y) - origin_vec
				transforms.append(Transform3D(rotation.scaled(scale_value), place))
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
	material_override = _rock_material
