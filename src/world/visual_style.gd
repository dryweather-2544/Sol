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
	return from_settings if from_settings in IDS else RODINA


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
		# Rodina's skybox base colour (0.025, 0, 0.05) (RodinaSkybox.fx:33, rendering_notes §6.4), a display value; under a
		# thin air (Jarilo) it shows through the sky, so the earlier, brighter #0c0418 tinted the whole day sky violet.
		# Stars over-bright and blue-shifted so they bloom; a contrast curve darkens the dim, dusty parts of the panorama
		# (Rodina subtracts dust: same section). The star values are Sol's own.
		return {"space_color": Color(0.025, 0.0, 0.05).srgb_to_linear(), "star_gain": 1.8, "star_tint": Vector3(0.85, 0.9, 1.25), "star_gamma": 1.35,
			"galaxy_amount": 0.50, "galaxy_color": Color("#5c466b").srgb_to_linear(), "galaxy_normal": Vector3(0.35, 0.82, 0.25).normalized()}
	return {"space_color": Color(0.004, 0.005, 0.012), "star_gain": 1.0, "star_tint": Vector3.ONE, "star_gamma": 1.0,
		"galaxy_amount": 0.0, "galaxy_color": Color.BLACK, "galaxy_normal": Vector3(0.35, 0.82, 0.25).normalized()}


## Rodina's HUD fonts (Scripts/Render/MenuFonts.lua): face, size (pixels at 1080p) and colour per role. The faces are the
## Google Fonts Rodina names (Orbitron, Michroma, Audiowide; OFL, in assets/sol/fonts); which Sol label takes which role
## is Sol's choice.
const RODINA_HUD_FONTS := {
	&"info": {"face": "Orbitron-Variable", "size": 18, "color": Color(1, 1, 1)},            # InfoFont (35-46)
	&"notification": {"face": "Orbitron-Variable", "size": 20, "color": Color(0.975, 0.975, 0.975)}, # NotificationFont (77-88)
	&"warning": {"face": "Audiowide-Regular", "size": 24, "color": Color(1, 0.25, 0.25)},   # WarningFont (49-60)
	&"discovery": {"face": "Michroma-Regular", "size": 50, "color": Color(1, 1, 1)},        # DiscoveryFont (5-16)
	&"loading": {"face": "Orbitron-Variable", "size": 20, "color": Color(0.75, 0.9, 1)},    # LoadingFont (63-74)
}


## Font, size and colour for one HUD role under the rodina style, or {} under sol (labels keep their own look). The font
## is null when the file is missing (the label then keeps Godot's default face but takes the size and colour).
static func hud_font(role: StringName) -> Dictionary:
	if not is_rodina() or not RODINA_HUD_FONTS.has(role):
		return {}
	var spec: Dictionary = RODINA_HUD_FONTS[role]
	var path := "res://assets/sol/fonts/%s.ttf" % spec["face"]
	var font: Font = load(path) if ResourceLoader.exists(path) else null
	return {"font": font, "size": spec["size"], "color": spec["color"]}


## Camera field of view (degrees) for a field_of_view setting. Rodina's default CameraFOV is 60 (EGOptions.lua:26), so
## the rodina style uses 60 while the setting is still at Sol's default; a value the player chose is kept. Inferred: that
## Rodina's FOV is vertical, like Godot's (the engine call is C++).
static func base_field_of_view(setting_degrees: float) -> float:
	if is_rodina() and is_equal_approx(setting_degrees, GameSettings.DEFAULT_FIELD_OF_VIEW):
		return 60.0
	return setting_degrees


## Multiplier on the ship's painted hull materials (Sol: none). Rodina's ships read as near-black silhouettes in every
## measured frame (DeepSeek's palette_report.csv: #05030d, #0d0916, #171221); the textured hull's base is ~0.7, so a
## 0.25 tint gives an albedo of ~0.17 (N13 palette pass, measured on Sol renders).
static func hull_tint() -> Color:
	return Color(0.24, 0.24, 0.27) if is_rodina() else Color.WHITE


## Multiplier on the ship's interior materials (Sol: none). Rodina interiors measure dark grey/green, HSV value
## 0.11-0.26 (palette_report.csv: #1a1818, #3e3e3e, #0f180f, #1d1c1e).
static func interior_tint() -> Color:
	return Color(0.6, 0.6, 0.6) if is_rodina() else Color.WHITE


## Rodina's ceiling lights (Scripts/DataGameplay/EGDataItems.lua:212-260): White (1, 1, 1) radius 8, Soft (.7, .6, .6),
## Green (.5, .75, .6), Wide (1, 1, 1) radius 16, Emergency (.9, .2, .2). Which room gets which is Sol's choice.
const RODINA_ROOM_LIGHTS := {
	&"cockpit": {"color": Color(0.7, 0.6, 0.6), "range": 8.0},
	&"cabin": {"color": Color(1.0, 1.0, 1.0), "range": 8.0},
	&"engineering": {"color": Color(0.5, 0.75, 0.6), "range": 8.0},
	&"turret_room": {"color": Color(0.7, 0.6, 0.6), "range": 8.0},
	&"cargo": {"color": Color(1.0, 1.0, 1.0), "range": 16.0},
	&"airlock": {"color": Color(0.9, 0.2, 0.2), "range": 8.0},
	&"living_area": {"color": Color(0.7, 0.6, 0.6), "range": 8.0},
	&"medical": {"color": Color(0.75, 0.95, 0.9), "range": 8.0},
	&"bathroom": {"color": Color(0.8, 0.95, 1.0), "range": 8.0},
}


## Colour, energy and range of one room's ceiling light under the active style.
static func room_light(room_id: StringName) -> Dictionary:
	if is_rodina():
		var light: Dictionary = RODINA_ROOM_LIGHTS.get(room_id, RODINA_ROOM_LIGHTS[&"cabin"])
		return {"color": (light["color"] as Color).srgb_to_linear(), "energy": 1.35, "range": light["range"]}
	return {"color": Color.WHITE, "energy": 1.6, "range": 5.5}


## Ambient light inside the ship as a fraction of the outside ambient: Rodina's scenes use SetAmbientLight(.05, .05, .05)
## (EGSceneSolar.lua:28), so interiors are lit almost only by their lamps.
static func interior_ambient_factor() -> float:
	return 0.3 if is_rodina() else 1.0


## Chase-camera offset for the Rodina-inspired presentation (from the N13 visual pass). The reference keeps the ship as a
## small dark shape with negative space around it; 17 m fills too much of the frame.
static func chase_camera_offset() -> Vector3:
	return Vector3(0.0, 8.0, 85.0) if is_rodina() else Vector3(0.0, 3.4, 17.0)


# --- the original Sol look: built from the existing data, so nothing changes --------------------------------------

static func _sol_look(body: BodyDef) -> PlanetLook:
	var look := PlanetLook.new()
	look.family = &"sol"
	look.rim_color = body.atmosphere_color
	look.impostor_color = body.color
	return look


# --- Rodina-inspired families ----------------------------------------------------------------------------------

## Rodina's own feature-texture terrain colouring (PlanetLook.rodina_feature_colors) per body. Remove a body from this list
## to give it back its hand-made palette below.
const RODINA_FEATURE_COLOR_BODIES: Array[StringName] = [&"planet", &"cinder", &"verdant", &"selene", &"pebble"]


## Sol's brightness gain per world on top of Rodina's colours (see PlanetLook.rodina_albedo_gain).
const RODINA_ALBEDO_GAIN := {&"cinder": 3.2, &"pebble": 1.7}
## Sol's scale on a world's fog density (Rodina's own atmosphere colours stay): Cinder's dark red haze would otherwise
## swallow the ground from a few km away.
const RODINA_FOG_SCALE := {&"cinder": 0.35}
## Patchy colour variation per world (see PlanetLook.rodina_color_variation): Cinder and Pebble have wide, plain ground.
const RODINA_COLOR_VARIATION := {&"cinder": 0.5, &"pebble": 0.4}


static func _rodina_look(body: BodyDef) -> PlanetLook:
	var look := _rodina_look_palette(body)
	if body.id in RODINA_FEATURE_COLOR_BODIES:
		look.rodina_feature_colors = true
		look.rodina_albedo_gain = RODINA_ALBEDO_GAIN.get(body.id, 1.0)
		look.rodina_color_variation = RODINA_COLOR_VARIATION.get(body.id, 0.0)
		look.fog_density *= RODINA_FOG_SCALE.get(body.id, 1.0)
	return look


static func _rodina_look_palette(body: BodyDef) -> PlanetLook:
	match body.id:
		&"planet":
			return _apply_rodina_atmosphere(_ochre_steppe(), body.id)
		&"cinder":
			return _apply_rodina_atmosphere(_ember_barren(), body.id)
		&"verdant":
			return _apply_rodina_atmosphere(_teal_alien(), body.id)
		&"selene":
			return _apply_rodina_atmosphere(_airless(&"airless_grey", "#6e6a65", "#4c4946", "#8a8580", "#3a3836", "#5e5a56", "#77736e"), body.id)
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


## Aurelia (home world; Jarilo-like orbit and atmosphere): ochre-brown plains and dunes, darker rock on slopes and
## uplands, grey-white poles. Colours are Jarilo's own: each JariloTerrain layer's DiffuseColor (EGEditorData.lua:1277-1600:
## PolarIceCaps .89 grey, Mountains (.577, .539, .461), Dunes (.788, .717, .606), BaseB (.714, .635, .516)) times Jarilo's
## PlanetFeatureColor1a HSV(45, .5, .61) or 1b HSV(30, .5, 1) (EGDataPlanets.lua:548-551; the later lines win in Lua).
## Inferred: that the shader multiplies the two (PlanetJarilo.fx is not available) and which layer each Sol feature
## takes. Measured Rodina ground is this dark: #4c3422 and #2b1808 (palette_report.csv, steam01_salmon_sky_mountains).
## Calibrated: those products are hue ~40 (olive in a render) while the measured ground is hue 26, so every hue here is
## turned 15 degrees toward red, keeping saturation and value (what reddens it in Rodina is in the missing shader).
static func _ochre_steppe() -> PlanetLook:
	var look := _rodina_base(&"ochre_steppe")
	look.features = [
		{"color": _hex("#e3e3e3"), "latitude_min": 0.88, "latitude_fade": 0.03, "slope_max": 0.12}, # PolarIceCaps
		{"color": _hex("#5a3b24"), "slope_min": 0.1, "slope_fade": 0.03}, # Mountains x 1a
		{"color": _hex("#93513b"), "height_min": 2600.0, "height_fade": 500.0}, # Mountains x 1b
		{"color": _hex("#b65c42"), "mask_scale": 9000.0, "mask_min": 0.25, "mask_fade": 0.12, "mask_seed": 1}, # BaseB x 1b
		{"color": _hex("#7b4f2f"), "height_max": 300.0, "height_fade": 350.0}, # Dunes x 1a
	]
	look.base_color = _hex("#6f4428") # BaseB x 1a
	# Calibrated from orbit: Rodina's Jarilo reads ochre there (#aa7d4e, steam06_orbit_ochre) once the pale scatter is
	# added, which needs a more saturated orange under it than the ground colours above (measured on Sol renders).
	look.orbit_color = _hex("#b07428")
	look.orbit_mix_max = 0.85
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
	&"planet": {"source": "Jarilo (EGDataPlanets.lua:503-506)", "density": 0.75, "scatter1": [20.0, 0.6, 1.0], "scatter2": [20.0, 0.2, 1.0], "filter1": [192.0, 0.31, 1.0], "filter2": [210.0, 0.5, 1.0], "halo": [0.02, 0.02, 0.2, 0.0],  "terminator": [0.2, -0.2], "surface_ambient": [32.0, 0.2, 0.25], "sky_desaturate": 0.4},
	&"cinder": {"source": "Veles (EGDataPlanets.lua:386-390)", "density": 2.0, "scatter1": [10.0, 0.87, 0.3], "scatter2": [10.0, 0.87, 0.25], "filter1": [25.0, 0.7, 0.7], "filter2": [15.0, 1.0, 0.7], "halo": [0.1, 0.1, 0.2, 0.0],  "terminator": [0.2, -0.5], "ground_distance": 2.0},
	&"selene": {"source": "Morena (EGDataPlanets.lua:657-690)", "density": 1.2, "scatter1": [150.0, 0.4, 0.9], "scatter2": [165.0, 0.14, 0.95], "filter1": [205.0, 0.1, 0.95], "filter2": [205.0, 0.3, 0.95], "halo": [0.01, 0.02, 0.2, 0.5], "terminator": [0.2, -0.5]},
	&"verdant": {"source": "Zosia (EGDataPlanets.lua:111-114)", "density": 1.5, "scatter1": [167.0, 0.8, 0.5], "scatter2": [167.0, 0.425, 0.7], "filter1": [1.0, 0.31, 1.0], "filter2": [80.0, 0.8, 1.0], "halo": [0.05, 0.2, 0.2, -1.0],  "terminator": [0.2, -0.5], "ground_distance": 1.5},
}


## Sol's own tuning of the atmosphere seen from orbit (Rodina's are very dark from space): brighter glow colours for the
## shell only (display values; the sky from inside keeps Rodina's colours) and a gain on the glow against space.
## Selene's scatter/filter above are also softened from Morena's (hue 145 sat .6 and a red filter gave a garish mint sky and
## pink ground): a pale cold green sky and a cold blue-white sun tint.
const RODINA_GLOW_TWEAKS := {
	&"planet": {"shell_glow_gain": 1.3},
	&"cinder": {"shell_scatter1": "#ff5a2a", "shell_scatter2": "#ff9a5a", "shell_glow_gain": 2.6},
	&"verdant": {"shell_scatter1": "#2fe0c0", "shell_scatter2": "#8ff0dc", "shell_glow_gain": 2.2},
	&"selene": {"shell_scatter1": "#7fe8c8", "shell_scatter2": "#c8fff0", "shell_glow_gain": 1.8},
}


## Rodina's atmosphere colour as a Godot (linear) colour. Rodina has no gamma pass (rendering_notes §6.6), so its
## values are what reaches the screen: they are treated as display (sRGB) values, like the hex colours here.
static func rodina_atmosphere_color(body_id: StringName, key: String) -> Color:
	var hsv: Array = RODINA_ATMOSPHERES[body_id][key]
	return RodinaMath.hue_saturate_value(hsv[0], hsv[1], hsv[2]).srgb_to_linear()


static func _raw_atmosphere_color(body_id: StringName, key: String) -> Color:
	var hsv: Array = RODINA_ATMOSPHERES[body_id][key]
	return RodinaMath.hue_saturate_value(hsv[0], hsv[1], hsv[2])


## Sky, sunset, limb and haze from the Rodina world's atmosphere colours. Rodina's horizon shader blends between
## ScatterColor1 and 2 by its horizon factor and toward FilterColor 1/2 by its sunset/halo factor (rendering_notes
## §4.2-4.3). Inferred, because _atmosphere.h is not in this session: which end each colour takes. Here the more
## saturated ScatterColor1 is the zenith, the paler ScatterColor2 the horizon, the haze and the limb seen from orbit,
## and FilterColor2 the sunset glow.
static func _apply_rodina_atmosphere(look: PlanetLook, body_id: StringName) -> PlanetLook:
	# saturate(AtmosphereDensity) is Rodina's tint strength (rendering_notes §4.1): the sky is the scatter colour laid over
	# black-violet space at that strength. Jarilo's 0.75 matches the owner's Jarilo screenshot (sky ~77% of the raw colour).
	var tint := clampf(RODINA_ATMOSPHERES[body_id]["density"], 0.0, 1.0)
	var space := Color(0.025, 0.0, 0.05).srgb_to_linear() # RodinaSkybox base colour (rendering_notes §6.4)
	look.sky_zenith = space.lerp(rodina_atmosphere_color(body_id, "scatter1"), tint)
	look.sky_horizon = space.lerp(rodina_atmosphere_color(body_id, "scatter2"), tint)
	look.sunset_color = rodina_atmosphere_color(body_id, "filter2")
	look.rim_color = rodina_atmosphere_color(body_id, "scatter1")
	look.fog_color = rodina_atmosphere_color(body_id, "scatter2")
	# Seen against Rodina screenshots (owner-supplied, N13): the star through the air is large (~9 degrees across on
	# Jarilo) with a wide soft halo, a pale disc of FilterColor1 inside a FilterColor2 halo (blue sun on peach Jarilo);
	# distant ridges sink into the sky colour within a few tens of km.
	look.sun_disc_color = rodina_atmosphere_color(body_id, "filter1").lerp(Color.WHITE, 0.25)
	look.sun_halo_color = rodina_atmosphere_color(body_id, "filter2")
	look.sun_disc_radius = 0.08 # ~9 degrees across, measured on the Jarilo screenshot
	look.sun_halo_width = 0.3
	look.sunset_halo_width = 0.45
	look.sun_halo_gain = 0.85
	look.sun_disc_gain = 1.0
	look.fog_density = 6.0e-5
	look.fog_aerial_perspective = 0.85
	look.fog_thins_with_altitude = true # from orbit and high up the atmosphere shader does the haze, not the fog
	# From orbit Rodina's limb is a soft pale glow (the owner's orbit screenshot), so the paler ScatterColor2 is used there.
	look.rim_color = rodina_atmosphere_color(body_id, "scatter2")
	# Lighting (N13 lighting pass), from Rodina's planet data and lighting model (rendering_notes §6.1-6.3):
	# - the star light is tinted toward FilterColor2 by the atmosphere's tint strength (GetPlanetStarLight): Jarilo's
	#   blue light is why its snow looks lavender and its ochre ground a muted tan in the owner's screenshot;
	# - shade gets the planet's SurfaceAmbientColor (Jarilo's is set: HSV(32, .2, .25), a dim warm grey); a world
	#   without one gets its horizon colour at a quarter (inferred: shaded slopes in the screenshots take the sky tint);
	# - StarBacksideColor is black on Jarilo (and unset elsewhere except Morena), so no back light;
	# - sunlight fades through TerminatorBegin..End by the sun's height; no shadows (Rodina ships none).
	var data: Dictionary = RODINA_ATMOSPHERES[body_id]
	# How far toward FilterColor2 is not in the research (the _lighting.h blend factor); the full tint turned whole
	# scenes one colour, while the Jarilo screenshot keeps warm ground with only bluish snow: 0.3 of the tint strength.
	look.sun_color = Color.WHITE.lerp(rodina_atmosphere_color(body_id, "filter2"), 0.3 * tint)
	if data.has("surface_ambient"):
		look.ambient_day = rodina_atmosphere_color(body_id, "surface_ambient")
	else:
		look.ambient_day = look.sky_horizon * 0.25
	look.ambient_energy_day = 1.0
	look.back_energy = 0.0
	look.terminator_enabled = true
	look.terminator_begin = data["terminator"][0]
	look.terminator_end = data["terminator"][1]
	# StarHalo, SunsetStarHalo, SunsetStarAngleBuffer, SunsetHorizonLimit from the same PlanetDef.
	var halo: Array = data["halo"]
	# Raw (display-space) colours: the atmosphere shaders composite in display space as Rodina does.
	look.rodina_atmosphere = {
		"atm_scatter1": _raw_atmosphere_color(body_id, "scatter1"), "atm_scatter2": _raw_atmosphere_color(body_id, "scatter2"),
		"atm_filter1": _raw_atmosphere_color(body_id, "filter1"), "atm_filter2": _raw_atmosphere_color(body_id, "filter2"),
		"atm_density": float(data["density"]), "atm_star_halo": halo[0], "atm_sunset_star_halo": halo[1],
		"atm_sunset_star_buffer": halo[2], "atm_sunset_horizon_limit": halo[3],
		"atm_ground_distance": float(data.get("ground_distance", 1.0)), # AtmosphereGroundDistance; Jarilo leaves it out
		"atm_sky_desaturate": float(data.get("sky_desaturate", 0.0))} # calibrated (rodina_atmosphere.gdshaderinc)
	for key in RODINA_GLOW_TWEAKS.get(body_id, {}):
		var tweak: Variant = RODINA_GLOW_TWEAKS[body_id][key]
		look.rodina_atmosphere[key] = Color.html(tweak) if tweak is String else tweak
	look.rim_power = 2.5
	look.rim_haze = 0.15
	if body_id != &"planet": # Aurelia's colours are Jarilo's own; the others keep their far colour leaning to the air's tint
		look.orbit_color = look.orbit_color.lerp(look.rim_color, 0.25)
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
	# Airless worlds have no sky to fill shadows; a faint fill (Sol's) keeps cliffs and dune lee sides from going pure black.
	look.ambient_space = _hex("#6a6684")
	look.ambient_day = _hex("#6a6684")
	look.ambient_energy_space = 0.4
	look.ambient_energy_day = 0.4
	look.impostor_color = _hex(orbit)
	return look


static func _hex(text: String) -> Color:
	return Color.html(text).srgb_to_linear()
