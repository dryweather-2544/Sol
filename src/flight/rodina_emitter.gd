class_name RodinaEmitter
extends GPUParticles3D
## One Rodina particle effect slot: a port of `Engine:AttachParticles(slot, material, amount, localPos, localDir)`.
## Rodina re-calls AttachParticles every frame with the same slot to keep one live emitter and steer it; drive() does
## the same, and a slot not driven in a frame stops emitting (its live particles finish their lives).
##
## Reading of the engine-side fields (the C++ is not in the recovered files, so this is inferred from how the data is
## used, and kept data-driven so it can be corrected):
## - `amount` (0..1) scales the emission rate (EGDataShipPlayer.lua passes thrust strengths and fade factors).
## - localDir is the emitter's +Y: style vectors are in a frame whose +Y is that direction (an engine passes
##   backwardsDir and its VelocityBase is +400 on Y, so the exhaust leaves backwards).
## - Size is the spawn sphere's radius and the key Size the sprite's diameter: Size 0 is common on small thrusters that
##   are plainly visible, and Size 300 on the warp ring would otherwise make 15 km sprites.
## - BlendStyle missing = alpha blend (both "Add" and "Alpha" are written out in the data, so the default is a third
##   case; alpha is the conservative choice). The sprite is a soft round dot (no particle texture exists in Rodina's
##   Data/Textures, research items_combat_notes §4.1).
## - Yaw/Pitch are not used: on a round, camera-facing sprite a spin is invisible, and reading them as direction
##   spread would turn the straight warp streams (Yaw = Pitch = 1) into random bursts.
## - Lengths (positions, radii, speeds, accelerations, sprite sizes) are multiplied by Sol's ship scale; times are not.

## Sol's hull is ~20 m long; Rodina's player ship spans ~75 m between its rearmost and foremost emitter positions
## (engine at y = -40, front thrusters at y = +35, EGDataShipPlayer.lua:252-283). Inferred: Rodina's mesh is not here.
const SHIP_SCALE := 0.27
## Rodina ship axes (x right, y forward, z up; EGDataShipPlayer.lua drives forward thrust on +y) as Sol ship axes
## (x right, -z forward, y up). Columns: Rodina x, y, z.
const RODINA_TO_SOL := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))

const _SHADER_PATH := "res://data/shaders/rodina_particle.gdshader"

## The limnal (warp) effects are drawn as hard-edged squares, matched to the owner's footage of Rodina's warp: a ring of
## translucent violet-white squares at the start, then big overlapping translucent squares that fill the screen to white
## (Rodina's own sprite sizes, only the soft dot swapped for a hard square), around a dense magenta core of many small
## squares. Per effect: `size` scales the sprite sizes in the key frames and `rate` multiplies the particle count.
## Multiplies the warp squares' violet toward Rodina's magenta-pink.
const MAGENTA := Color(1.0, 0.45, 0.95)
const SQUARE_EFFECTS := {
	# clear/full: the screen-centre mask in screen heights (clear < 0: unmasked). The pink core around the ship stays;
	# the big white-violet squares thin out toward the middle so the pilot can still see ahead.
	"Limnal Startup Ring": {"size": 0.13, "rate": 0.2, "clear": -1.0, "full": 0.0, "tint": MAGENTA},
	"Limnal Drive": {"size": 1.0, "rate": 1.0, "clear": 0.2, "full": 0.6, "tint": MAGENTA},
	"Limnal Drive Air": {"size": 1.0, "rate": 1.0, "clear": 0.2, "full": 0.6, "tint": MAGENTA},
	"Limnal Pink Air": {"size": 0.025, "rate": 15.0, "clear": -1.0, "full": 0.0},
	"LimnalShipBlur": {"size": 0.25, "rate": 2.0, "clear": -1.0, "full": 0.0},
}

var material_name := ""
var _rate := 0.0
var _driven := false

static var _shader: Shader
static var _sprites := {} # blend name -> QuadMesh


func setup(effect_name: String) -> void:
	var definition: Dictionary = RodinaParticleDefs.MATERIALS[effect_name]
	var style: Dictionary = definition["Styles"][0]
	material_name = effect_name
	name = "Rodina_" + effect_name.replace(" ", "")
	_rate = style["Rate"]
	lifetime = style["Lifetime"]
	var square: Dictionary = SQUARE_EFFECTS.get(effect_name, {})
	amount = maxi(1, ceili(_rate * lifetime * float(square.get("rate", 1.0))) + 1)
	amount_ratio = 0.0
	emitting = false
	explosiveness = 0.0
	randomness = 0.0
	fixed_fps = 0
	interpolate = false
	fract_delta = true
	var orientation: String = definition.get("OrientationType", "")
	var world_rotation := orientation != "EG_PARTICLE_ORIENTATION_LOCAL"
	local_coords = not world_rotation
	if _shader == null:
		_shader = load(_SHADER_PATH)
	var process := ShaderMaterial.new()
	process.shader = _shader
	var s := SHIP_SCALE
	process.set_shader_parameter("offset", _vector(style["Offset"]) * s)
	process.set_shader_parameter("spawn_radius", float(style["Size"]) * s)
	process.set_shader_parameter("velocity_base", _vector(style["VelocityBase"]) * s)
	process.set_shader_parameter("velocity_range", _vector(style["VelocityRange"]) * s)
	process.set_shader_parameter("velocity_normal_base", float(style["VelocityNormalBase"]) * s)
	process.set_shader_parameter("velocity_normal_range", float(style["VelocityNormalRange"]) * s)
	process.set_shader_parameter("acceleration", _vector(style["Acceleration"]) * s)
	process.set_shader_parameter("acceleration_normal", float(style["AccelerationNormal"]) * s)
	process.set_shader_parameter("world_rotation", 1 if world_rotation else 0)
	var keys: Array = style["Keys"]
	var times := PackedFloat32Array()
	var colors: Array[Vector4] = []
	var sizes := PackedFloat32Array()
	for key: Dictionary in keys:
		var color: Vector3 = key["Color"]
		times.append(key["Time"])
		# Rodina has no gamma pass, so its colours are display values: convert to linear (exact for one layer; Rodina
		# adds layers in display space, Godot in linear, so dense additive overlaps differ).
		var linear := Color(color.x, color.y, color.z).srgb_to_linear()
		colors.append(Vector4(linear.r, linear.g, linear.b, key["Alpha"]))
		sizes.append(float(key["Size"]) * s * float(square.get("size", 1.0)))
	while times.size() < 5:
		times.append(times[times.size() - 1])
		colors.append(colors[colors.size() - 1])
		sizes.append(sizes[sizes.size() - 1])
	process.set_shader_parameter("key_count", keys.size())
	process.set_shader_parameter("key_time", times)
	process.set_shader_parameter("key_color", colors)
	process.set_shader_parameter("key_size", sizes)
	process_material = process
	draw_pass_1 = _sprite(definition.get("BlendStyle", "Alpha"), not square.is_empty())
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not square.is_empty():
		set_instance_shader_parameter("clear_radius", float(square.get("clear", 0.2)))
		set_instance_shader_parameter("full_radius", float(square.get("full", 0.6)))
		set_instance_shader_parameter("tint", square.get("tint", Color.WHITE))
	# Live particles reach up to Offset + Size + speed * lifetime away from the emitter (the warp streams travel kilometres).
	var reach := (_vector(style["Offset"]).length() + float(style["Size"]) + (_vector(style["VelocityBase"]).length() + _vector(style["VelocityRange"]).length() + absf(style["VelocityNormalBase"]) + absf(style["VelocityNormalRange"])) * lifetime + 0.5 * (_vector(style["Acceleration"]).length() + absf(style["AccelerationNormal"])) * lifetime * lifetime) * s
	var biggest := 0.0
	for size in sizes:
		biggest = maxf(biggest, size)
	visibility_aabb = AABB(Vector3.ONE * -(reach + biggest), Vector3.ONE * 2.0 * (reach + biggest))


## Mark the start of a frame: slots not driven again before end_frame() stop emitting.
func begin_frame() -> void:
	_driven = false


## AttachParticles(slot, material, amount, local_position, local_direction), in the parent's (ship's) frame.
func drive(strength: float, local_position: Vector3, local_direction: Vector3) -> void:
	_driven = true
	# The style frame turns Rodina's +Y onto the direction by the shortest arc in Rodina's axes, then converts to Sol's
	# axes, so a style's X and Z land where they did on Rodina's ship (the warp ring's Offset is on X).
	var direction := local_direction.normalized() if local_direction.length() > 1e-6 else -Vector3.FORWARD
	var rodina_direction := RODINA_TO_SOL.inverse() * direction
	transform = Transform3D(RODINA_TO_SOL * Basis(Quaternion(Vector3.UP, rodina_direction)), local_position)
	amount_ratio = clampf(strength, 0.0, 1.0)
	emitting = amount_ratio > 0.0


func end_frame() -> void:
	if not _driven:
		amount_ratio = 0.0
		emitting = false


func is_active() -> bool:
	return emitting


## A Rodina ship-local position or direction (metres) in Sol's ship frame, at Sol's scale.
static func from_rodina(rodina_vector: Vector3, scaled: bool = true) -> Vector3:
	return RODINA_TO_SOL * rodina_vector * (SHIP_SCALE if scaled else 1.0)


static func _vector(value: Variant) -> Vector3:
	return value as Vector3


const _SQUARE_SHADER_PATH := "res://data/shaders/rodina_square_particle.gdshader"
static var _additive_shader: Shader


static func _additive_square_shader() -> Shader:
	if _additive_shader == null:
		_additive_shader = Shader.new()
		_additive_shader.code = (load(_SQUARE_SHADER_PATH) as Shader).code.replace("blend_mix", "blend_add")
	return _additive_shader


static func _sprite(blend_style: String, square: bool = false) -> QuadMesh:
	var cache_key := blend_style + ("_square" if square else "")
	if _sprites.has(cache_key):
		return _sprites[cache_key]
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material: Material
	if square:
		# Hard squares keep the middle of the screen clear: the shader fades them out toward the centre.
		var screen_material := ShaderMaterial.new()
		screen_material.shader = load(_SQUARE_SHADER_PATH)
		if blend_style == "Add":
			screen_material.shader = _additive_square_shader()
		material = screen_material
	else:
		var standard := StandardMaterial3D.new()
		standard.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		standard.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if blend_style == "Add" else BaseMaterial3D.BLEND_MODE_MIX
		standard.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		standard.vertex_color_use_as_albedo = true
		standard.albedo_texture = ShipEffects.soft_dot()
		standard.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		standard.billboard_keep_scale = true
		standard.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		material = standard
	quad.material = material
	_sprites[cache_key] = quad
	return quad
