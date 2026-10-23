extends RefCounted
## restyles ship models with ship_style.gdshader: a Valheim-like look, metallic palettes and a small metal glint.
## Preload this script (no class_name) and call apply_fighter(model, role, is_big) or apply_hull(model, ship_id) on a freshly instantiated model.
## Per-instance surface overrides only: the shared imported resources are never changed. SOL_SHIP_STYLE=off restores the original materials.

const SHADER_PATH := "res://src/core/ship_style.gdshader"

## [name, dark, mid, light, accent]
const PALETTES := [
	["Gunmetal + Cyan", Color("#161b22"), Color("#38424f"), Color("#7a8795"), Color("#2fd4ee")],
	["Titanium + Amber", Color("#23252a"), Color("#666b73"), Color("#b4b9c0"), Color("#ff9a2a")],
	["Obsidian + Crimson", Color("#0b0c10"), Color("#23262e"), Color("#555a66"), Color("#e0232f")],
	["Pearl + Teal", Color("#838a94"), Color("#c4c9cf"), Color("#f0f2f4"), Color("#16b8a4")],
	["Brass + Deep Blue", Color("#241f1c"), Color("#7b6a4c"), Color("#d0b573"), Color("#3b78c4")],
	["Chrome + Violet", Color("#201d2b"), Color("#6c6a80"), Color("#c2bfd6"), Color("#9a5cff")],
]
## FighterDef.Role order: INTERCEPTOR, FIGHTER, HEAVY, ACE -> palette index.
const ROLE_PALETTE := [0, 1, 4, 2]
const BIG_SHIP_PALETTE := {"meridian": 4, "talon": 2, "argent": 3, "halo": 0}

static var _shader: Shader
## (source material, palette) -> its styled copy, so every surface using one material shares one styled material.
static var _cache := {}
static var _count := 0


static func enabled() -> bool:
	return OS.get_environment("SOL_SHIP_STYLE").to_lower() != "off"


static func apply_fighter(root: Node, role: int, is_big: bool) -> void:
	var palette: int = 3 if is_big else int(ROLE_PALETTE[clampi(role, 0, ROLE_PALETTE.size() - 1)])
	apply(root, palette, 0.7, 0.3, not is_big)


static func apply_hull(root: Node, ship_id: String) -> void:
	apply(root, int(BIG_SHIP_PALETTE.get(ship_id, 3)), 0.55, 0.35, false)


## palette < 0 keeps the model's own colours. `default_metal` / `default_rough` are for materials with no metal data of their own.
static func apply(root: Node, palette := -1, default_metal := 0.7, default_rough := 0.3, livery := false) -> void:
	if root == null or not enabled():
		return
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
		if _shader == null:
			push_warning("ShipStyle: shader missing, keeping the original materials")
			return
	var boxes: Array = []
	_collect(root, Transform3D.IDENTITY, true, boxes)
	var box: AABB = boxes[0] if not boxes.is_empty() else AABB()
	_walk(root, Transform3D.IDENTITY, true, box, palette, default_metal, default_rough, livery)


static func _collect(node: Node, parent_xf: Transform3D, is_root: bool, out: Array) -> void:
	var xf := parent_xf
	if node is Node3D and not is_root:
		xf = parent_xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var b: AABB = xf * (node as MeshInstance3D).mesh.get_aabb()
		if out.is_empty():
			out.append(b)
		else:
			out[0] = (out[0] as AABB).merge(b)
	for child in node.get_children():
		_collect(child, xf, false, out)


static func _walk(node: Node, parent_xf: Transform3D, is_root: bool, box: AABB, palette: int, default_metal: float, default_rough: float, livery: bool) -> void:
	var xf := parent_xf
	if node is Node3D and not is_root:
		xf = parent_xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		if instance.mesh != null:
			var styled_any := false
			for surface in instance.mesh.get_surface_count():
				var source := instance.get_active_material(surface)
				var styled := _styled(source, palette, default_metal, default_rough, livery)
				if styled != null:
					instance.set_surface_override_material(surface, styled)
					styled_any = true
			if styled_any:
				var b := xf.basis
				var o := xf.origin
				instance.set_instance_shader_parameter("root_r0", Vector4(b.x.x, b.y.x, b.z.x, o.x))
				instance.set_instance_shader_parameter("root_r1", Vector4(b.x.y, b.y.y, b.z.y, o.y))
				instance.set_instance_shader_parameter("root_r2", Vector4(b.x.z, b.y.z, b.z.z, o.z))
				var c := box.get_center()
				var h := box.size * 0.5
				instance.set_instance_shader_parameter("root_c", Vector4(c.x, c.y, c.z, 0.0))
				instance.set_instance_shader_parameter("root_h", Vector4(h.x, h.y, h.z, 0.0))
	for child in node.get_children():
		_walk(child, xf, false, box, palette, default_metal, default_rough, livery)


static func _styled(source: Material, palette: int, default_metal: float, default_rough: float, livery: bool) -> ShaderMaterial:
	if not (source is StandardMaterial3D):
		return null
	var standard := source as StandardMaterial3D
	# glass and other see-through parts keep their own material
	if standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return null
	var key := "%d:%d:%d" % [standard.get_instance_id(), palette, 1 if livery else 0]
	if _cache.has(key):
		return _cache[key]
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("albedo_color", standard.albedo_color)
	if standard.albedo_texture != null:
		material.set_shader_parameter("albedo_tex", standard.albedo_texture)
		material.set_shader_parameter("has_albedo_tex", true)
	var metal := standard.metallic
	var rough := standard.roughness
	if standard.metallic_texture != null:
		material.set_shader_parameter("mr_tex", standard.metallic_texture)
		material.set_shader_parameter("has_mr_tex", true)
	elif metal < 0.05:
		metal = default_metal
		rough = minf(rough, default_rough)
	material.set_shader_parameter("metallic_factor", metal if metal > 0.0 else default_metal)
	material.set_shader_parameter("roughness_factor", rough)
	if standard.emission_enabled:
		material.set_shader_parameter("emission_color", standard.emission)
		material.set_shader_parameter("emission_energy", standard.emission_energy_multiplier)
		if standard.emission_texture != null:
			material.set_shader_parameter("emission_tex", standard.emission_texture)
			material.set_shader_parameter("has_emission_tex", true)
	if palette >= 0 and palette < PALETTES.size():
		var p: Array = PALETTES[palette]
		material.set_shader_parameter("palette_on", true)
		material.set_shader_parameter("pal_dark", Vector3(p[1].r, p[1].g, p[1].b))
		material.set_shader_parameter("pal_mid", Vector3(p[2].r, p[2].g, p[2].b))
		material.set_shader_parameter("pal_light", Vector3(p[3].r, p[3].g, p[3].b))
		material.set_shader_parameter("pal_accent", Vector3(p[4].r, p[4].g, p[4].b))
		material.set_shader_parameter("livery_strength", 1.0 if livery else 0.0)
	_cache[key] = material
	_count += 1
	if _count == 1:
		print("[ShipStyle] styling ship materials (SOL_SHIP_STYLE=off to disable)")
	return material
