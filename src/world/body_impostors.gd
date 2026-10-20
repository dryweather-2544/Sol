class_name BodyImpostors
extends Node3D
const VisualStyleScript = preload("res://src/world/visual_style.gd")
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
var _shells := {} # body id -> AtmosphereShell (only for worlds with an atmosphere)
var _cloud_shells := {} # body id -> CloudShell (only for worlds with clouds)


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
		if body.atmosphere_height > 0.0:
			var shell := AtmosphereShell.new()
			add_child(shell)
			_shells[body_id] = shell
			if body.cloud_coverage > 0.0:
				var clouds := CloudShell.new()
				add_child(clouds)
				_cloud_shells[body_id] = clouds


func _process(_delta: float) -> void:
	var viewer := runtime.session.player_world_position()
	var viewer_system := system.convert_position(viewer, StarSystem.SYSTEM_FRAME, runtime.time_seconds)
	for body_id in _nodes:
		var node: MeshInstance3D = _nodes[body_id]
		var body: BodyDef = system.bodies[body_id]
		if node.material_override is StandardMaterial3D:
			(node.material_override as StandardMaterial3D).albedo_color = body.rodina_color if VisualStyleScript.is_rodina() else body.color
		node.visible = body_id != runtime.active_frame
		if _shells.has(body_id):
			(_shells[body_id] as Node3D).visible = node.visible
		if _cloud_shells.has(body_id):
			(_cloud_shells[body_id] as Node3D).visible = node.visible and GameSettings.instance().clouds and not VisualStyleScript.is_rodina()
		if not node.visible:
			continue
		var center := system.body_position(body_id, runtime.time_seconds)
		var offset := Vector3(center.x - viewer_system.x, center.y - viewer_system.y, center.z - viewer_system.z)
		var distance := offset.length()
		if distance <= placement_distance:
			node.position = viewer_local + offset
			node.scale = Vector3.ONE * body.radius
			_update_shell(body_id, body, node.position, 1.0)
		else:
			var scale_factor := placement_distance / distance
			node.position = viewer_local + offset * scale_factor
			node.scale = Vector3.ONE * (body.radius * scale_factor)
			_update_shell(body_id, body, node.position, scale_factor)


func _update_shell(body_id: StringName, body: BodyDef, centre: Vector3, scale_factor: float) -> void:
	if not _shells.has(body_id):
		return
	var sun := system.sun_direction_in_frame(runtime.active_frame, runtime.time_seconds) if runtime.active_frame != StarSystem.SYSTEM_FRAME else Vector3(0, 0, -1)
	(_shells[body_id] as AtmosphereShell).update_shell(body.radius * scale_factor, body.atmosphere_height * scale_factor, centre, sun, body.atmosphere_color, body)
	if _cloud_shells.has(body_id):
		(_cloud_shells[body_id] as CloudShell).update_shell(body.radius * scale_factor, body.cloud_altitude * scale_factor, centre, sun, body, runtime.time_seconds)
