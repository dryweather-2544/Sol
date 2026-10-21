extends SceneTree
## Bakes Rodina's skybox (stars, Milky Way, dust) into assets/generated/rodina_skybox/ as six cube-map faces.
## Usage: tools/bake_rodina_skybox.sh [size]   (default 1024, Rodina's SkyboxResolution; a few minutes on 8+ cores)


func _init() -> void:
	var size := 1024
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--size="):
			size = int(argument.substr(7))
	var started := Time.get_ticks_msec()
	var baker := RodinaSkyBake.new(size)
	baker.bake_stars()
	print("stars placed in %.1f s" % [float(Time.get_ticks_msec() - started) / 1000.0])
	baker.bake_all()
	var error := baker.save(ProjectSettings.globalize_path(RodinaSky.DIRECTORY))
	print("skybox %d px x 6 faces -> %s (%s) in %.1f s" % [size, RodinaSky.DIRECTORY, error_string(error), float(Time.get_ticks_msec() - started) / 1000.0])
	quit(0 if error == OK else 1)
