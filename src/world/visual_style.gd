class_name VisualStyle
extends RefCounted
## Central, reversible presentation profile. The SOL profile is the existing renderer; the
## RODINA profile is a controlled alternate look for sky/space/atmosphere/clouds/lighting.
## Gameplay, physics, saves and ship behaviour must never branch on this value.

const SOL := "sol"
const RODINA := "rodina"
const ALL := [SOL, RODINA]

static var current := SOL


static func normalize(value: String) -> String:
	return RODINA if value.to_lower() == RODINA else SOL


## Refresh from the explicit environment override (used by the reproducible screenshot harness)
## or the player setting. Returns the active profile.
static func refresh_from_settings() -> String:
	var requested := OS.get_environment("SOL_VISUAL_STYLE")
	if requested == "":
		requested = GameSettings.instance().visual_style
	return set_style(requested)


static func set_style(value: String) -> String:
	current = normalize(value)
	return current


static func is_rodina() -> bool:
	return current == RODINA


static func label(value: String) -> String:
	return "Rodina" if normalize(value) == RODINA else "Sol"
