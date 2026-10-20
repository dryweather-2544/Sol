class_name VisualStyle
extends RefCounted
## The game's visual style: "sol" (the original look) or "rodina" (a Rodina-inspired look, docs/RODINA_ART_STYLE_TECHNICAL_SPEC.md).
## Chosen by the SOL_VISUAL_STYLE environment variable (sol|rodina; wins, for tools and tests), else GameSettings.visual_style.
## A style is presentation only: it never touches terrain height, physics, saves or gameplay state.
##
## Ground colours in the rodina profile are design inferences, not samples: no Rodina frame was available when they were
## chosen (spec §0). Families follow docs/RODINA_PLANET_TYPES.md §2. Since N13 the air worlds' sky, sunset, limb and
## haze colours are Rodina's own atmosphere colours (RODINA_ATMOSPHERES, from EGDataPlanets.lua).

const SOL := &"sol"
const RODINA := &"rodina"
const IDS: Array[StringName] = [SOL, RODINA]

## Bumped by set_active(); the main scene re-applies the look when it changes.
static var revision := 0
static var _override := &""
static var _looks := {} # "style/body" -> PlanetLook


static func active() -> StringName:
	if _override != &"":
		return _override
	var from_environment := OS.get_environment("SOL_VISUAL_STYLE").strip_edges().to_lower()
	if from_environment in ["sol", "rodina"]:
		return StringName(from_environment)
	var from_settings := StringName(GameSettings.instance().visual_style)
	return from_settings if from_settings in IDS else SOL


static func is_rodina() -> bool:
	return active() == RODINA


## Switch styles at runtime (pause menu) or in tests. Saves nothing; the caller stores GameSettings.visual_style.
static func set_active(style: StringName) -> void:
	_override = style if style in IDS else SOL
	revision += 1


## The look for one body (star-system body id) under the active style.
static func look_for(body: BodyDef) -> PlanetLook:
	var style := active()
	var key := "%s/%s" % [style, body.id]
	if not _looks.has(key):
		_looks[key] = (_rodina_look(body) if style == RODINA else _sol_look(body)).prepare()
	return _looks[key]


## Between worlds (system frame): no planet, no atmosphere. Sol: the original defaults.
static func deep_space_look() -> PlanetLook:
	var key := "%s/deep_space" % active()
	if not _looks.has(key):
		var look := PlanetLook.new()
		if is_rodina():
			look = _airless(&"deep_space", "#5b4a3e", "#463a31", "#77665a", "#2c2420", "#6e5a48", "#5e5045")
			look.features = []
		_looks[key] = look.prepare()
	return _looks[key]


# --- global (whole-frame) settings -----------------------------------------------------------------------------

static func tonemap_mode() -> int:
	# Rodina has no tonemap, gamma or exposure pass (research rendering_notes §6.6); highlights clip.
	return Environment.TONE_MAPPER_LINEAR if is_rodina() else Environment.TONE_MAPPER_FILMIC


static func glow_enabled() -> bool:
	return is_rodina() # Rodina adds a bloom pass in the same numeric space as lighting


## Sky shader parameters that do not depend on the planet: space colour and how the star panorama is treated.
static func space_parameters() -> Dictionary:
	if is_rodina():
		# Near-black violet base; stars over-bright and blue-shifted so they bloom; a contrast curve darkens the dim,
		# dusty parts of the panorama (Rodina subtracts dust: rendering_notes §6.4). Values are Sol's own.
		return {"space_color": _hex("#0c0418"), "star_gain": 1.8, "star_tint": Vector3(0.85, 0.9, 1.25), "star_gamma": 1.35}
	return {"space_color": Color(0.004, 0.005, 0.012), "star_gain": 1.0, "star_tint": Vector3.ONE, "star_gamma": 1.0}


## Multiplier on the ship's painted hull materials (Sol: none).
static func hull_tint() -> Color:
	return Color(0.74, 0.77, 0.84) if is_rodina() else Color.WHITE


# --- the original Sol look: built from the existing data, so nothing changes --------------------------------------

static func _sol_look(body: BodyDef) -> PlanetLook:
	var look := PlanetLook.new()
	look.family = &"sol"
	look.rim_color = body.atmosphere_color
	look.impostor_color = body.color
	return look


# --- Rodina-inspired families ----------------------------------------------------------------------------------

static func _rodina_look(body: BodyDef) -> PlanetLook:
	match body.id:
		&"planet":
			return _apply_rodina_atmosphere(_ochre_steppe(), body.id)
		&"cinder":
			return _apply_rodina_atmosphere(_ember_barren(), body.id)
		&"verdant":
			return _apply_rodina_atmosphere(_teal_alien(), body.id)
		&"selene":
			return _airless(&"airless_grey", "#6e6a65", "#4c4946", "#8a8580", "#3a3836", "#5e5a56", "#77736e")
		&"pebble":
			return _airless(&"airless_rust", "#5b4a3e", "#463a31", "#77665a", "#2c2420", "#6e5a48", "#5e5045")
	return _sol_look(body) # stars and anything unknown keep the Sol look


## Shared Rodina-style terrain treatment: large, low-contrast detail (Rodina's texture tiers start at 500 m, not metres),
## crisp triplanar, terrain leaning to its orbit colour from altitude.
static func _rodina_base(family: StringName) -> PlanetLook:
	var look := PlanetLook.new()
	look.family = family
	look.detail_flat_tile = 12.0
	look.detail_steep_tile = 24.0
	look.detail_far_tile = 120.0
	look.detail_tile_period = 120.0 # a multiple of 12, 24 and 120
	look.detail_contrast = 0.45
	look.detail_fade_start = 150.0
	look.detail_fade_end = 900.0
	look.triplanar_sharpness = 10.0
	look.orbit_mix_max = 0.45
	look.legacy_sun_glow = 0.0
	look.sun_disc_gain = 6.0
	look.sun_halo_gain = 1.2
	look.sunset_gain = 0.9
	# Two-colour sky: the horizon colour fills a soft band from ~7 degrees below to well above the horizon line; no hard edge.
	look.gradient_scale = 1.0
	look.gradient_bias = 0.12
	look.gradient_power = 0.7
	look.fog_thins_with_altitude = false
	look.fog_aerial_perspective = 0.7
	look.ambient_energy_space = 0.25
	look.ambient_energy_day = 0.5 # 0.35 left shaded hull faces near-black in the first ground photo
	look.back_energy = 0.28
	return look


## Aurelia (home world; Jarilo-like orbit and atmosphere): salmon and ochre plains, pale sandstone uplands, dark rock on
## slopes, frosted poles; a blue-violet sky with a warm, peachy horizon.
static func _ochre_steppe() -> PlanetLook:
	var look := _rodina_base(&"ochre_steppe")
	look.features = [
		{"color": _hex("#d9d4cc"), "latitude_min": 0.88, "latitude_fade": 0.03, "slope_max": 0.12},
		{"color": _hex("#5a4436"), "slope_min": 0.1, "slope_fade": 0.03},
		{"color": _hex("#c9a27a"), "height_min": 2600.0, "height_fade": 500.0},
		{"color": _hex("#c07a5c"), "mask_scale": 9000.0, "mask_min": 0.25, "mask_fade": 0.12, "mask_seed": 1},
		{"color": _hex("#96643f"), "height_max": 300.0, "height_fade": 350.0},
	]
	look.base_color = _hex("#b8854f")
	look.orbit_color = _hex("#c79a6c")
	look.sky_zenith = _hex("#5f6fb3")
	look.sky_horizon = _hex("#e8c3a6")
	look.sunset_color = _hex("#ff8a4a")
	look.fog_color = _hex("#d9b79c")
	look.fog_density = 1.4e-5
	look.sun_color = _hex("#fff1d6")
	look.back_color = _hex("#6b5a80")
	look.ambient_space = _hex("#2a2236")
	look.ambient_day = _hex("#8a7a86")
	look.rim_color = _hex("#b4a0d0") # the bluer #9fb0ff read as a vivid blue ring round a violet-and-peach sky
	look.impostor_color = _hex("#c79a6c")
	return look


## Cinder (innermost; Perun-like position): rust and ochre barrens, dark basalt cliffs, bright orange streaks; a dusty
## mauve sky with an orange-pink horizon and a white-gold sun.
static func _ember_barren() -> PlanetLook:
	var look := _rodina_base(&"ember_barren")
	look.features = [
		{"color": _hex("#3d2420"), "slope_min": 0.09, "slope_fade": 0.03},
		{"color": _hex("#7a3b26"), "height_min": 2000.0, "height_fade": 500.0},
		{"color": _hex("#c4572c"), "mask_scale": 5000.0, "mask_min": 0.3, "mask_fade": 0.1, "mask_seed": 2},
		{"color": _hex("#6e2f1f"), "height_max": 200.0, "height_fade": 300.0},
	]
	look.base_color = _hex("#9c4426")
	look.orbit_color = _hex("#a85636")
	look.sky_zenith = _hex("#8a4a52")
	look.sky_horizon = _hex("#f0a070")
	look.sunset_color = _hex("#ff6a2a")
	look.fog_color = _hex("#d9906a")
	look.fog_density = 1.8e-5
	look.sun_color = _hex("#ffe2b0")
	look.sun_energy = 1.45
	look.back_color = _hex("#5a2e2a")
	look.ambient_space = _hex("#2a1614")
	look.ambient_day = _hex("#7a5048")
	look.rim_color = _hex("#ff9a6a")
	look.impostor_color = _hex("#a85636")
	return look


## Verdant (thickest atmosphere; Veles-like): deep teal lowlands, mossy olive uplands, slate cliffs, frosted teal
## poles; a dense blue-green haze and a sun filtered toward cyan.
static func _teal_alien() -> PlanetLook:
	var look := _rodina_base(&"teal_alien")
	look.features = [
		{"color": _hex("#a9c9c2"), "latitude_min": 0.88, "latitude_fade": 0.03, "slope_max": 0.12},
		{"color": _hex("#2e3d3a"), "slope_min": 0.1, "slope_fade": 0.03},
		{"color": _hex("#6f7a52"), "height_min": 2400.0, "height_fade": 500.0},
		# Olive moss in broad patches breaks up the teal (the first photo pass was one flat teal from ground to sky).
		{"color": _hex("#5b6b3a"), "mask_scale": 12000.0, "mask_min": 0.3, "mask_fade": 0.12, "mask_seed": 5},
		{"color": _hex("#2f6f62"), "mask_scale": 7000.0, "mask_min": 0.2, "mask_fade": 0.12, "mask_seed": 3},
		{"color": _hex("#1f4440"), "height_max": 300.0, "height_fade": 350.0},
	]
	look.base_color = _hex("#2b5a4f")
	look.orbit_color = _hex("#3f7a6c")
	look.sky_zenith = _hex("#3a6f9e") # bluer than the ground, so sky and land separate
	look.sky_horizon = _hex("#bcdccc")
	look.sunset_color = _hex("#ffb070")
	look.fog_color = _hex("#9cc4b8")
	look.fog_density = 2.2e-5
	look.sun_color = _hex("#d6fff0")
	look.back_color = _hex("#22404a")
	look.ambient_space = _hex("#14262a")
	look.ambient_day = _hex("#4a6a68")
	look.rim_color = _hex("#86c9b4") # the vivid #7fffd0 read as neon in the orbit photo
	look.impostor_color = _hex("#3f7a6c")
	return look


## Rodina atmosphere colours (EGDataPlanets.lua), as EGHueSaturateValue(hue, saturation, value) triples, for the
## Rodina world whose sky each Sol air world takes: Aurelia (home, 1 AU) <- Jarilo (1 AU; Mars-like butterscotch sky,
## blue sunset); Cinder (hot, red) <- Veles (hot, acidic, dark red); Verdant (teal) <- Zosia (teal). Paired by sky
## colour now that the colours are known (docs/RODINA_PLANET_TYPES.md paired by orbit before they were); the ground
## palettes are unchanged.
const RODINA_ATMOSPHERES := {
	&"planet": {"source": "Jarilo (EGDataPlanets.lua:503-506)", "scatter1": [20.0, 0.6, 1.0], "scatter2": [20.0, 0.2, 1.0], "filter1": [192.0, 0.31, 1.0], "filter2": [210.0, 0.5, 1.0]},
	&"cinder": {"source": "Veles (EGDataPlanets.lua:386-390)", "scatter1": [10.0, 0.87, 0.3], "scatter2": [10.0, 0.87, 0.25], "filter1": [25.0, 0.7, 0.7], "filter2": [15.0, 1.0, 0.7]},
	&"verdant": {"source": "Zosia (EGDataPlanets.lua:111-114)", "scatter1": [167.0, 0.8, 0.5], "scatter2": [167.0, 0.425, 0.7], "filter1": [1.0, 0.31, 1.0], "filter2": [80.0, 0.8, 1.0]},
}


## Rodina's atmosphere colour as a Godot (linear) colour. Rodina has no gamma pass (rendering_notes §6.6), so its
## values are what reaches the screen: they are treated as display (sRGB) values, like the hex colours here.
static func rodina_atmosphere_color(body_id: StringName, key: String) -> Color:
	var hsv: Array = RODINA_ATMOSPHERES[body_id][key]
	return RodinaMath.hue_saturate_value(hsv[0], hsv[1], hsv[2]).srgb_to_linear()


## Sky, sunset, limb and haze from the Rodina world's atmosphere colours. Rodina's horizon shader blends between
## ScatterColor1 and 2 by its horizon factor and toward FilterColor 1/2 by its sunset/halo factor (rendering_notes
## §4.2-4.3). Inferred, because _atmosphere.h is not in this session: which end each colour takes. Here the more
## saturated ScatterColor1 is the zenith and the limb seen from orbit, the paler ScatterColor2 the horizon and the
## haze, and FilterColor2 the sunset glow.
static func _apply_rodina_atmosphere(look: PlanetLook, body_id: StringName) -> PlanetLook:
	look.sky_zenith = rodina_atmosphere_color(body_id, "scatter1")
	look.sky_horizon = rodina_atmosphere_color(body_id, "scatter2")
	look.sunset_color = rodina_atmosphere_color(body_id, "filter2")
	look.rim_color = rodina_atmosphere_color(body_id, "scatter1")
	look.fog_color = rodina_atmosphere_color(body_id, "scatter2")
	return look


## Airless bodies (Selene, Pebble; Rodina's asteroid family has no atmosphere): dark dust, darker rock, a hard white sun
## on a black-violet sky and almost no fill, so the night side reads as near-black with a faint violet backside fill.
static func _airless(family: StringName, base: String, low: String, high: String, rock: String, mottle: String, orbit: String) -> PlanetLook:
	var look := _rodina_base(family)
	look.features = [
		{"color": _hex(rock), "slope_min": 0.09, "slope_fade": 0.03},
		{"color": _hex(high), "height_min": 1500.0, "height_fade": 400.0},
		{"color": _hex(mottle), "mask_scale": 1500.0, "mask_min": 0.15, "mask_fade": 0.1, "mask_seed": 4},
		{"color": _hex(low), "height_max": 0.0, "height_fade": 250.0},
	]
	look.base_color = _hex(base)
	look.orbit_color = _hex(orbit)
	look.orbit_mix_from = 1500.0
	look.orbit_mix_to = 40000.0
	look.sun_color = Color.WHITE
	look.sun_energy = 1.5
	look.back_color = _hex("#241f30")
	look.back_energy = 0.2
	look.ambient_space = _hex("#120e18")
	look.ambient_day = _hex("#120e18")
	look.ambient_energy_space = 0.18
	look.ambient_energy_day = 0.18
	look.impostor_color = _hex(orbit)
	return look


static func _hex(text: String) -> Color:
	return Color.html(text).srgb_to_linear()
