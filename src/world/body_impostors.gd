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
var _backdrops := {} # body id -> MeshInstance3D: the active planet as a sphere drawn first, behind its terrain (see _update_backdrop)
var _shells := {} # body id -> AtmosphereShell (only for worlds with an atmosphere)


## Rodina style inside an atmosphere: the sky shader draws the star, tinted by the air's filter colours (Rodina's
## RodinaStar takes the atmosphere filter); the world-space star sphere would be fogged over it, so it is hidden.
var hide_star := false

## How many star radii the corona quad reaches from the centre.
const STAR_CORONA_REACH := 4.0
## The active planet is real terrain, which the camera's far plane cuts off once the viewer is far above it (CameraRange
## caps far/near, so the far plane is only about 2,000 km at the cockpit's near plane). Past this many times the
## impostor distance (0.8 x far plane) of altitude, it is drawn as a sphere like every other body, so a planet never
## vanishes between the end of its terrain and the frame switch at its sphere of influence.
const TERRAIN_HANDOFF := 1.1
## Below this altitude the backdrop sphere is not drawn (the terrain fills the view).
const BACKDROP_MIN_ALTITUDE := 300.0


func _ready() -> void:
	for body_id in system.bodies:
		var body: BodyDef = system.bodies[body_id]
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		mesh.radial_segments = 96 if body.is_star else 48
		mesh.rings = 48 if body.is_star else 24
		var material := StandardMaterial3D.new()
		material.albedo_color = body.color if body.is_star else VisualStyle.look_for(body).impostor_color
		material.roughness = 1.0
		if body.is_star:
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = material
		if body.is_star:
			_dress_star(node)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_nodes[body_id] = node
		if not body.is_star:
			var backdrop := MeshInstance3D.new()
			backdrop.mesh = mesh
			var backdrop_material := ShaderMaterial.new()
			backdrop_material.shader = load("res://data/shaders/planet_backdrop.gdshader")
			backdrop_material.set_shader_parameter("albedo", VisualStyle.look_for(body).impostor_color)
			backdrop_material.render_priority = -128 # first of the transparent things
			backdrop.material_override = backdrop_material
			backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			backdrop.extra_cull_margin = 16384.0
			backdrop.visible = false
			add_child(backdrop)
			_backdrops[body_id] = backdrop
		if body.atmosphere_height > 0.0:
			var shell := AtmosphereShell.new()
			add_child(shell)
			_shells[body_id] = shell


## The star is a boiling plasma sphere with a corona (star_surface / star_corona shaders), not a flat disc.
func _dress_star(node: MeshInstance3D) -> void:
	var surface := ShaderMaterial.new()
	surface.shader = load("res://data/shaders/star_surface.gdshader")
	node.material_override = surface
	var corona := MeshInstance3D.new()
	corona.name = "Corona"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0) * STAR_CORONA_REACH
	corona.mesh = quad
	var glow := ShaderMaterial.new()
	glow.shader = load("res://data/shaders/star_corona.gdshader")
	glow.set_shader_parameter("reach", STAR_CORONA_REACH)
	corona.material_override = glow
	corona.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	corona.extra_cull_margin = 16384.0
	node.add_child(corona)


## Re-colours the far-away spheres after a visual style switch.
func restyle() -> void:
	for body_id in _nodes:
		var body: BodyDef = system.bodies[body_id]
		if not body.is_star:
			((_nodes[body_id] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = VisualStyle.look_for(body).impostor_color
			((_backdrops[body_id] as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("albedo", VisualStyle.look_for(body).impostor_color)


func _process(_delta: float) -> void:
	var viewer := runtime.session.player_world_position()
	var viewer_system := system.convert_position(viewer, StarSystem.SYSTEM_FRAME, runtime.time_seconds)
	for body_id in _nodes:
		var node: MeshInstance3D = _nodes[body_id]
		var body: BodyDef = system.bodies[body_id]
		var center := system.body_position(body_id, runtime.time_seconds)
		var offset := Vector3(center.x - viewer_system.x, center.y - viewer_system.y, center.z - viewer_system.z)
		var distance := offset.length()
		# the active planet is always its real terrain (shrunk toward the camera from high up, PlanetTerrain.squeeze_scale), never a flat stand-in
		var terrain_drawn: bool = body_id == runtime.active_frame
		node.visible = not terrain_drawn and not (body.is_star and hide_star)
		_update_backdrop(body_id, body, terrain_drawn, distance, offset)
		if _shells.has(body_id):
			(_shells[body_id] as Node3D).visible = node.visible
		if not node.visible:
			continue
		if distance <= placement_distance:
			node.position = viewer_local + offset
			node.scale = Vector3.ONE * body.radius
			_update_shell(body_id, body, node.position, 1.0)
		else:
			# Bodies this far out are squeezed in front of the far plane. Keep their true front-to-back order (a moon in front
			# of the star must stay in front of it) by spreading them over a thin band instead of one shared distance.
			var draw_distance := placement_distance * (1.0 + 0.1 * (1.0 - placement_distance / distance))
			var scale_factor := draw_distance / distance
			node.position = viewer_local + offset * scale_factor
			node.scale = Vector3.ONE * (body.radius * scale_factor)
			_update_shell(body_id, body, node.position, scale_factor)


## The terrain is cut off by the camera's far plane in a straight line, well short of the real horizon once the viewer is a few
## kilometres up, leaving sky between the two. Behind it the planet is drawn as a squeezed sphere (true angular size, kept inside the
## far plane); its shader skips every pixel that already has terrain, the ship or the cockpit, so it only shows where the terrain ends.
func _update_backdrop(body_id: StringName, body: BodyDef, terrain_drawn: bool, distance: float, offset: Vector3) -> void:
	var backdrop: MeshInstance3D = _backdrops.get(body_id)
	if backdrop == null:
		return
	var altitude := distance - body.radius
	backdrop.visible = false # retired: the terrain now covers the whole planet (kept for tests that still look it up)
	if not backdrop.visible:
		return
	var scale_factor := minf(1.0, placement_distance * 0.95 / distance)
	backdrop.position = viewer_local + offset * scale_factor
	backdrop.scale = Vector3.ONE * (body.radius * scale_factor)
	# placement_distance is 0.8 x the far plane: a pixel deeper than 99% of the far plane holds nothing.
	(backdrop.material_override as ShaderMaterial).set_shader_parameter("sky_depth", placement_distance * 1.2375)


func _update_shell(body_id: StringName, body: BodyDef, centre: Vector3, scale_factor: float) -> void:
	if not _shells.has(body_id):
		return
	var sun := system.sun_direction_in_frame(runtime.active_frame, runtime.time_seconds) if runtime.active_frame != StarSystem.SYSTEM_FRAME else Vector3(0, 0, -1)
	var look := VisualStyle.look_for(body)
	var shell := _shells[body_id] as AtmosphereShell
	if not shell.update_rodina(body.radius * scale_factor, body.atmosphere_height * scale_factor, centre, sun, 0.01, look.rodina_atmosphere if VisualStyle.is_rodina() else {}):
		shell.update_shell((body.radius + body.atmosphere_height * 1.6) * scale_factor, centre, sun, look.rim_color, look.rim_power, look.rim_haze)
