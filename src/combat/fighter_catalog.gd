class_name FighterCatalog
extends RefCounted
## The roster of small fighters (models in res://assets/fighters/) and how encounters pick from it. Picks are
## deterministic from the SeedRng they are given, like all Sol world content.

const MODEL_DIR := "res://assets/fighters/"

static var _defs: Array[FighterDef] = []


static func all() -> Array[FighterDef]:
	if _defs.is_empty():
		_defs = [
			_make(&"dart", "Dart", FighterDef.Role.INTERCEPTOR, "fighter_05.glb", 9.0, 1.3, 1.4, 0.7, 0.008, 6.0, 350.0, 0.045, Color(0.85, 0.12, 0.1), Vector3(0, -0.16, -1.08), [Vector3(0, 0.23, 4.5)]),
			_make(&"wasp", "Wasp", FighterDef.Role.INTERCEPTOR, "fighter_02.glb", 8.0, 1.25, 1.5, 0.6, 0.006, 8.0, 320.0, 0.05, Color(0.85, 0.8, 0.1), Vector3(0, 0.4, -0.96), [Vector3(0, -0.03, 4.0)]),
			_make(&"talon", "Talon", FighterDef.Role.FIGHTER, "fighter_19.glb", 11.0, 1.0, 1.0, 1.0, 0.012, 4.0, 450.0, 0.03, Color(0.8, 0.2, 0.15), Vector3(0, -0.1, -1.32), [Vector3(0, 0.0, 5.5)]),
			_make(&"mantis", "Mantis", FighterDef.Role.FIGHTER, "fighter_12.glb", 11.0, 1.0, 1.0, 1.2, 0.010, 5.0, 450.0, 0.03, Color(0.15, 0.5, 0.2), Vector3(0, -0.23, -1.32), [Vector3(0, -0.98, 5.5)]),
			_make(&"raptor", "Raptor", FighterDef.Role.FIGHTER, "fighter_04.glb", 12.0, 1.1, 1.1, 1.2, 0.012, 5.0, 420.0, 0.028, Color(0.1, 0.12, 0.16), Vector3(0, -0.61, -1.44), [Vector3(0, -0.65, 6.0)]),
			_make(&"bulwark", "Bulwark", FighterDef.Role.HEAVY, "fighter_14.glb", 16.0, 0.75, 0.6, 3.0, 0.020, 3.0, 600.0, 0.03, Color(0.9, 0.55, 0.1), Vector3(0, 2.43, -1.86), [Vector3(0, 0.0, 7.76)]),
			_make(&"brick", "Brick", FighterDef.Role.HEAVY, "fighter_34.glb", 15.0, 0.7, 0.55, 3.5, 0.025, 2.5, 650.0, 0.03, Color(0.45, 0.3, 0.15), Vector3(0, 1.76, -1.8), [Vector3(0, 0.13, 7.5)]),
			_make(&"specter", "Specter", FighterDef.Role.ACE, "fighter_31.glb", 12.0, 1.2, 1.3, 1.5, 0.012, 6.0, 300.0, 0.02, Color(0.05, 0.05, 0.08), Vector3(0, -0.92, -1.44), [Vector3(0, -0.78, 6.0)]),
			_make(&"nova", "Nova", FighterDef.Role.ACE, "fighter_22.glb", 13.0, 1.15, 1.2, 1.8, 0.014, 5.0, 350.0, 0.02, Color(0.1, 0.2, 0.35), Vector3(0, -0.54, -1.56), [Vector3(-3.5, -0.92, 6.5), Vector3(3.5, -0.92, 6.5)]),
		]
	return _defs


static func by_id(id: StringName) -> FighterDef:
	for def in all():
		if def.id == id:
			return def
	return null


static func of_roles(roles: Array) -> Array[FighterDef]:
	var found: Array[FighterDef] = []
	for def in all():
		if def.role in roles:
			found.append(def)
	return found


## One fighter of the given roles, chosen by rng.
static func pick(rng: SeedRng, roles: Array) -> FighterDef:
	var pool := of_roles(roles)
	if pool.is_empty():
		pool = all()
	return pool[rng.next_u32() % pool.size()]


## The roles that can turn up in skirmish wave `wave` (1 = first): heavies from wave 3, aces from wave 5.
static func roles_for_wave(wave: int) -> Array:
	var roles: Array = [FighterDef.Role.INTERCEPTOR, FighterDef.Role.FIGHTER]
	if wave >= 3:
		roles.append(FighterDef.Role.HEAVY)
	if wave >= 5:
		roles.append(FighterDef.Role.ACE)
	return roles


## Fighters in skirmish wave `wave`: two more than the wave number, never more than five.
static func wave_size(wave: int) -> int:
	return clampi(wave + 1, 2, 5)


static func wave(wave_number: int, rng: SeedRng) -> Array[FighterDef]:
	var chosen: Array[FighterDef] = []
	var roles := roles_for_wave(wave_number)
	for index in wave_size(wave_number):
		chosen.append(pick(rng, roles))
	if wave_number >= 5: # from wave 5 every wave carries an ace
		chosen[0] = pick(rng, [FighterDef.Role.ACE])
	return chosen


static func _make(id: StringName, display_name: String, role: FighterDef.Role, file: String, size: float, speed_scale: float, turn_scale: float, toughness: float, gun_damage: float, gun_rate: float, preferred_range: float, aim_error: float, hull_color: Color, cockpit: Vector3, engines: Array[Vector3]) -> FighterDef:
	var def := FighterDef.new()
	def.id = id
	def.display_name = display_name
	def.role = role
	def.model_path = MODEL_DIR + file
	def.size = size
	def.speed_scale = speed_scale
	def.turn_scale = turn_scale
	def.toughness = toughness
	def.gun_damage = gun_damage
	def.gun_rate = gun_rate
	def.preferred_range = preferred_range
	def.fire_range = maxf(1100.0, preferred_range * 2.0)
	def.aim_error = aim_error
	def.hull_color = hull_color
	def.cockpit = cockpit
	def.engines = engines
	return def
