class_name FighterCatalog
extends RefCounted
## The roster of thirty small fighters (models in res://assets/fighters/, numbered after the downloaded pack) and how encounters pick from it.
## Each has its own hull, stat line, gun, cockpit interior (FighterCockpitSpec), screen colour and a line of character. Picks are deterministic
## from the SeedRng they are given, like all Sol world content.

const MODEL_DIR := "res://assets/fighters/"

static var _defs: Array[FighterDef] = []


static func all() -> Array[FighterDef]:
	if _defs.is_empty():
		_defs = [
			_make(&"dart", "Dart", FighterDef.Role.INTERCEPTOR, "fighter_05.glb", 9.0, 1.3, 1.4, 0.7, 0.008, 6.0, 350.0, 0.045, Color(0.85, 0.12, 0.10), Vector3(0, -0.16, -1.08), &"awing", [Vector3(0, 0.23, 4.5)], "Needle-nosed dart: the quickest thing in the wing, and made of tinfoil.", Color(0.90, 0.34, 0.34)),
			_make(&"wasp", "Wasp", FighterDef.Role.INTERCEPTOR, "fighter_02.glb", 8.0, 1.25, 1.5, 0.6, 0.006, 8.0, 320.0, 0.05, Color(0.85, 0.80, 0.10), Vector3(0, 0.4, -0.96), &"ewing", [Vector3(0, -0.03, 4)], "Swarm fighter: a stream of light cannon fire from a hull you can lose in your sleeve.", Color(0.34, 0.50, 0.90)),
			_make(&"needle", "Needle", FighterDef.Role.INTERCEPTOR, "fighter_08.glb", 8.5, 1.35, 1.5, 0.65, 0.007, 7.0, 330.0, 0.045, Color(0.70, 0.75, 0.80), Vector3(0, -0.71, -1.02), &"awing", [Vector3(-1.82, -0.63, 4.25), Vector3(1.82, -0.63, 4.25)], "Twin-boom picket that threads between targets faster than their gunners can swing.", Color(0.67, 0.90, 0.34)),
			_make(&"swift", "Swift", FighterDef.Role.INTERCEPTOR, "fighter_20.glb", 9.5, 1.4, 1.3, 0.7, 0.006, 8.5, 300.0, 0.05, Color(0.90, 0.90, 0.95), Vector3(0, 0.57, -1.14), &"cloudcar", [Vector3(0, -0.37, 4.75)], "Slim courier hull with a racing engine; it dies young and fast.", Color(0.90, 0.34, 0.83)),
			_make(&"kestrel", "Kestrel", FighterDef.Role.INTERCEPTOR, "fighter_35.glb", 10.0, 1.3, 1.35, 0.8, 0.009, 5.5, 380.0, 0.04, Color(0.55, 0.60, 0.35), Vector3(0, 0.32, -1.2), &"z95", [Vector3(0, -0.73, 4.58)], "Patrol interceptor. Not the quickest, but it keeps both eyes on you the whole fight.", Color(0.34, 0.90, 0.81)),
			_make(&"corsair", "Corsair", FighterDef.Role.INTERCEPTOR, "fighter_23.glb", 10.5, 1.2, 1.4, 0.9, 0.01, 5.0, 360.0, 0.04, Color(0.25, 0.30, 0.45), Vector3(0, 1.13, -1.26), &"ewing", [Vector3(0, -0.37, 5.07)], "A raider's sprinter: wide wings, hard turns and a pilot who never fights fair.", Color(0.90, 0.64, 0.34)),
			_make(&"shrike", "Shrike", FighterDef.Role.INTERCEPTOR, "fighter_26.glb", 9.0, 1.25, 1.6, 0.6, 0.008, 6.5, 340.0, 0.05, Color(0.45, 0.15, 0.50), Vector3(0, -0.53, -1.08), &"awing", [Vector3(0, 0.03, 4.5)], "The tightest turner in the yard. Impales anything that stops turning.", Color(0.48, 0.34, 0.90)),
			_make(&"talon", "Talon", FighterDef.Role.FIGHTER, "fighter_19.glb", 11.0, 1.0, 1.0, 1.0, 0.012, 4.0, 450.0, 0.03, Color(0.80, 0.20, 0.15), Vector3(0, -0.1, -1.32), &"xwing", [Vector3(0, 0, 5.5)], "Balanced all-rounder and the yardstick the rest are measured against.", Color(0.37, 0.90, 0.34)),
			_make(&"mantis", "Mantis", FighterDef.Role.FIGHTER, "fighter_12.glb", 11.0, 1.0, 1.0, 1.2, 0.01, 5.0, 450.0, 0.03, Color(0.15, 0.50, 0.20), Vector3(0, -0.23, -1.32), &"xwing2", [Vector3(0, -0.98, 5.5)], "Patient hunter: a little tougher than the Talon and always the last one to blink.", Color(0.90, 0.34, 0.53)),
			_make(&"raptor", "Raptor", FighterDef.Role.FIGHTER, "fighter_04.glb", 12.0, 1.1, 1.1, 1.2, 0.012, 5.0, 420.0, 0.028, Color(0.10, 0.12, 0.16), Vector3(0, -0.61, -1.44), &"z95", [Vector3(0, -0.65, 6)], "Dark, heavy-shouldered strike fighter with a gun for every mood.", Color(0.34, 0.69, 0.90)),
			_make(&"hornet", "Hornet", FighterDef.Role.FIGHTER, "fighter_06.glb", 10.0, 1.05, 1.1, 1.0, 0.011, 4.5, 430.0, 0.032, Color(0.85, 0.65, 0.10), Vector3(0, 0.72, -1.2), &"ewing", [Vector3(0, -0.37, 5)], "Stings early, stings often. Light on armour, heavy on attitude.", Color(0.85, 0.90, 0.34)),
			_make(&"falcon", "Falcon", FighterDef.Role.FIGHTER, "fighter_07.glb", 11.5, 1.1, 1.0, 1.1, 0.012, 4.5, 440.0, 0.03, Color(0.60, 0.60, 0.65), Vector3(0, 0.63, -1.38), &"xwing", [Vector3(-3.6, 0.54, 5.75), Vector3(3.6, 0.54, 5.75)], "Long-wing escort fighter with a clean, steady aim.", Color(0.78, 0.34, 0.90)),
			_make(&"harrier", "Harrier", FighterDef.Role.FIGHTER, "fighter_09.glb", 11.0, 1.0, 1.1, 1.1, 0.014, 3.8, 460.0, 0.03, Color(0.35, 0.40, 0.30), Vector3(0, 0.33, -1.32), &"ywing2", [Vector3(0, -0.83, 5.5)], "Slow-firing but hard-hitting: lines up one shot at a time.", Color(0.34, 0.90, 0.62)),
			_make(&"viper", "Viper", FighterDef.Role.FIGHTER, "fighter_10.glb", 10.5, 1.15, 1.15, 0.9, 0.01, 5.2, 400.0, 0.035, Color(0.20, 0.55, 0.25), Vector3(0, 1.06, -1.26), &"cloudcar", [Vector3(0, 0.27, 5.25)], "Quick, narrow and mean. Strikes from the side and is gone.", Color(0.90, 0.46, 0.34)),
			_make(&"lancer", "Lancer", FighterDef.Role.FIGHTER, "fighter_16.glb", 12.0, 1.05, 0.95, 1.2, 0.016, 3.6, 520.0, 0.028, Color(0.75, 0.75, 0.80), Vector3(0, 1.73, -1.44), &"xwing2", [Vector3(0, 0.5, 6)], "Long-barrelled lance fighter: opens fire from further out than anything else its size.", Color(0.34, 0.39, 0.90)),
			_make(&"condor", "Condor", FighterDef.Role.FIGHTER, "fighter_33.glb", 12.5, 0.95, 0.95, 1.4, 0.013, 4.5, 480.0, 0.03, Color(0.50, 0.40, 0.30), Vector3(0, -0.31, -1.5), &"bwing", [Vector3(-4.12, -0.73, 6.25), Vector3(4.12, -0.73, 6.25)], "Wide-winged gunship-lite. Slow to turn, slow to die.", Color(0.55, 0.90, 0.34)),
			_make(&"stinger", "Stinger", FighterDef.Role.FIGHTER, "fighter_27.glb", 10.0, 1.1, 1.2, 0.95, 0.009, 6.0, 410.0, 0.032, Color(0.80, 0.30, 0.10), Vector3(0, -0.35, -1.2), &"z95", [Vector3(0, -0.37, 5)], "Rapid-fire skirmisher; the volume of its fire makes up for the weight of it.", Color(0.90, 0.34, 0.72)),
			_make(&"ravager", "Ravager", FighterDef.Role.FIGHTER, "fighter_11.glb", 11.5, 1.0, 1.05, 1.3, 0.015, 4.0, 430.0, 0.03, Color(0.30, 0.10, 0.10), Vector3(0, -1.13, -1.38), &"ywing2", [Vector3(0, -0.43, 5.75)], "Scarred brawler that likes to be close enough to smell your reactor.", Color(0.34, 0.88, 0.90)),
			_make(&"bulwark", "Bulwark", FighterDef.Role.HEAVY, "fighter_14.glb", 16.0, 0.75, 0.6, 3.0, 0.02, 3.0, 600.0, 0.03, Color(0.90, 0.55, 0.10), Vector3(0, 2.43, -1.86), &"ywing1", [Vector3(0, 0, 7.76)], "Flying fortress: slow to turn, slower to die.", Color(0.90, 0.76, 0.34)),
			_make(&"brick", "Brick", FighterDef.Role.HEAVY, "fighter_34.glb", 15.0, 0.7, 0.55, 3.5, 0.025, 2.5, 650.0, 0.03, Color(0.45, 0.30, 0.15), Vector3(0, 1.76, -1.8), &"bwing", [Vector3(0, 0.13, 7.5)], "Exactly what it sounds like. Flies like one, hits like one.", Color(0.60, 0.34, 0.90)),
			_make(&"anvil", "Anvil", FighterDef.Role.HEAVY, "fighter_15.glb", 15.5, 0.72, 0.58, 3.2, 0.022, 2.8, 620.0, 0.03, Color(0.35, 0.35, 0.40), Vector3(0, -0.13, -1.86), &"sentinel", [Vector3(0, -0.61, 7.75)], "Armoured ram with a broad, flat prow. Turns like it's thinking about it.", Color(0.34, 0.90, 0.43)),
			_make(&"bastion", "Bastion", FighterDef.Role.HEAVY, "fighter_21.glb", 17.0, 0.68, 0.5, 4.0, 0.018, 3.2, 640.0, 0.03, Color(0.40, 0.50, 0.55), Vector3(0, -1.05, -2.04), &"sentinel", [Vector3(0, -2.28, 8.5)], "The biggest and toughest of the small craft: a shield wall with a gun.", Color(0.90, 0.34, 0.41)),
			_make(&"warhog", "Warhog", FighterDef.Role.HEAVY, "fighter_24.glb", 16.0, 0.8, 0.62, 2.8, 0.024, 2.8, 580.0, 0.032, Color(0.40, 0.45, 0.30), Vector3(0, 0.37, -1.92), &"ywing1", [Vector3(0, -0.83, 8)], "Close-in bruiser, a little more agile than its cousins and a lot meaner.", Color(0.34, 0.58, 0.90)),
			_make(&"mauler", "Mauler", FighterDef.Role.HEAVY, "fighter_30.glb", 14.5, 0.78, 0.65, 3.4, 0.026, 2.6, 560.0, 0.03, Color(0.55, 0.20, 0.15), Vector3(0, 1.3, -1.74), &"bwing", [Vector3(0, -1.16, 7.25)], "Compact brute with the heaviest gun of the line.", Color(0.74, 0.90, 0.34)),
			_make(&"specter", "Specter", FighterDef.Role.ACE, "fighter_31.glb", 12.0, 1.2, 1.3, 1.5, 0.012, 6.0, 300.0, 0.02, Color(0.05, 0.05, 0.08), Vector3(0, -0.92, -1.44), &"xwing2", [Vector3(0, -0.78, 6)], "Black hull, black record: the ace others pray to avoid.", Color(0.90, 0.34, 0.90)),
			_make(&"nova", "Nova", FighterDef.Role.ACE, "fighter_22.glb", 13.0, 1.15, 1.2, 1.8, 0.014, 5.0, 350.0, 0.02, Color(0.10, 0.20, 0.35), Vector3(0, -0.54, -1.56), &"ywing2", [Vector3(-3.5, -0.92, 6.5), Vector3(3.5, -0.92, 6.5)], "Twin-engine star pilot's ship: fast, tough, and everything you wanted to be.", Color(0.34, 0.90, 0.74)),
			_make(&"reaper", "Reaper", FighterDef.Role.ACE, "fighter_03.glb", 12.0, 1.25, 1.3, 1.4, 0.013, 5.6, 320.0, 0.02, Color(0.50, 0.05, 0.10), Vector3(0, 0.9, -1.44), &"awing", [Vector3(0, 0.05, 5.76)], "Sickle-winged killer that cuts across your bow and is gone before you can fire.", Color(0.90, 0.57, 0.34)),
			_make(&"phantom", "Phantom", FighterDef.Role.ACE, "fighter_17.glb", 11.5, 1.3, 1.35, 1.3, 0.011, 6.5, 300.0, 0.018, Color(0.30, 0.30, 0.35), Vector3(0, -0.69, -1.38), &"cloudcar", [Vector3(-1.93, -0.8, 5.75), Vector3(1.93, -0.8, 5.75)], "Stealth-lined prototype; very hard to hit, very hard to forget.", Color(0.41, 0.34, 0.90)),
			_make(&"valkyrie", "Valkyrie", FighterDef.Role.ACE, "fighter_18.glb", 13.0, 1.15, 1.25, 1.7, 0.014, 5.0, 340.0, 0.02, Color(0.75, 0.70, 0.55), Vector3(0, 0.77, -1.56), &"xwing", [Vector3(0, -0.68, 6.5)], "The flagship's escort: gold-trimmed, unflinching and always in formation.", Color(0.44, 0.90, 0.34)),
			_make(&"vandal", "Vandal", FighterDef.Role.ACE, "fighter_29.glb", 12.5, 1.2, 1.4, 1.5, 0.012, 6.0, 330.0, 0.02, Color(0.80, 0.10, 0.10), Vector3(0, -0.05, -1.5), &"ewing", [Vector3(0, 1.31, 4.73)], "Reckless red ace: all aggression, no plan, and somehow it works.", Color(0.90, 0.34, 0.60)),
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


static func _make(id: StringName, display_name: String, role: FighterDef.Role, file: String, size: float, speed_scale: float, turn_scale: float, toughness: float, gun_damage: float, gun_rate: float, preferred_range: float, aim_error: float, hull_color: Color, cockpit: Vector3, cockpit_id: StringName, engines: Array[Vector3], blurb: String, accent: Color) -> FighterDef:
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
	def.cockpit_id = cockpit_id
	def.blurb = blurb
	def.accent = accent
	return def
