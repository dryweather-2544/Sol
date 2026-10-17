class_name BodyImpostors
extends Node3D
## Draws every body that is not the active planet (other planets, moons, the star) as a sphere
## placed along the true direction at a fixed render distance, scaled so its angular size is
## correct. The active planet has real terrain instead. Lit by the same sun as everything else,
## so moons show phases.

var system: StarSystem
var runtime: WorldRuntime
## Where the camera is, in render space (the ship, or the walker).
var viewer_local := Vector3.ZERO
## Distance at which far bodies are drawn (kept inside the camera's far plane by the scene).
var placement_distance := 1.0e6

var _nodes := {} # body id -> MeshInstance3D


func _ready() -> void:
	for body_id in system.bodies:
		var body: BodyDef = system.bodies[body_id]
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		mesh.radial_segments = 48
		mesh.rings = 24
		var material := StandardMaterial3D.new()
		material.albedo_color = body.color
		material.roughness = 1.0
		if body.is_star:
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_nodes[body_id] = node


func _process(_delta: float) -> void:
	var viewer := runtime.session.player_world_position()
	var viewer_system := system.convert_position(viewer, StarSystem.SYSTEM_FRAME, runtime.time_seconds)
	for body_id in _nodes:
		var node: MeshInstance3D = _nodes[body_id]
		var body: BodyDef = system.bodies[body_id]
		node.visible = body_id != runtime.active_frame
		if not node.visible:
			continue
		var center := system.body_position(body_id, runtime.time_seconds)
		var offset := Vector3(center.x - viewer_system.x, center.y - viewer_system.y, center.z - viewer_system.z)
		var distance := offset.length()
		if distance <= placement_distance:
			node.position = viewer_local + offset
			node.scale = Vector3.ONE * body.radius
		else:
			var scale_factor := placement_distance / distance
			node.position = viewer_local + offset * scale_factor
			node.scale = Vector3.ONE * (body.radius * scale_factor)
