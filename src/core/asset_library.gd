class_name AssetLibrary
extends RefCounted
## Loads the integrated art from res://assets/sol/ (copied from Sol-Assets by tools/import_assets.py).
## Everything here is allowed to fail: a missing file, an unimported texture or a switched-off GameSettings toggle gives null (or the
## caller's fallback), the placeholder keeps working, and the problem is logged once, not every frame.

const ROOT := "res://assets/sol/"

## Every distinct problem seen so far (also pushed with push_warning once); tests read this.
static var warnings: Array[String] = []
static var _warned := {}


## Path of a material's .tres, or "" when no such file exists. Variants live in their base material's folder
## (mat_hull_plating_primer is in mat_hull_plating/), so trailing words are stripped until a folder matches.
static func material_path(material_id: String) -> String:
	var candidate := material_id
	while true:
		var path := "%smaterials/%s/%s.tres" % [ROOT, candidate, material_id]
		if ResourceLoader.exists(path):
			return path
		var cut := candidate.rfind("_")
		if cut <= 0:
			return ""
		candidate = candidate.substr(0, cut)
	return ""


## The material, or null (logged once) if the file is missing or does not load.
static func material(material_id: String) -> Material:
	var path := material_path(material_id)
	if path == "":
		warn_once(material_id, "asset material '%s' not found under %smaterials/" % [material_id, ROOT])
		return null
	var loaded := ResourceLoader.load(path)
	if not (loaded is Material):
		warn_once(material_id, "asset material '%s' failed to load (texture not imported yet?)" % material_id)
		return null
	return loaded as Material


## The asset material when the switch is on and it loads, otherwise `fallback` (the original code material).
static func material_or(material_id: String, fallback: Material) -> Material:
	if not GameSettings.instance().asset_materials:
		return fallback
	var found := material(material_id)
	return found if found != null else fallback


## A private copy for materials the game mutates every frame (station screens), or the fallback.
static func material_copy_or(material_id: String, fallback: Material) -> Material:
	var found := material_or(material_id, null)
	return found.duplicate() as Material if found != null else fallback


static func texture(relative_path: String) -> Texture2D:
	var path := ROOT + relative_path
	if not ResourceLoader.exists(path):
		warn_once(relative_path, "asset texture '%s' not found" % relative_path)
		return null
	var loaded := ResourceLoader.load(path)
	if not (loaded is Texture2D):
		warn_once(relative_path, "asset texture '%s' failed to load" % relative_path)
		return null
	return loaded as Texture2D


static func warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	warnings.append(message)
	push_warning(message)


## For tests: forget what has been logged.
static func reset_warnings() -> void:
	_warned.clear()
	warnings.clear()
