class_name RodinaSky
extends RefCounted
## The baked Rodina skybox cube map (tools/bake_rodina_skybox.gd -> RodinaSkyBake), or null when it has not been baked here.

const DIRECTORY := "res://assets/generated/rodina_skybox/"

static var _cube: Cubemap
static var _tried := false


static func cubemap() -> Cubemap:
	if _tried:
		return _cube
	_tried = true
	var images: Array[Image] = []
	for face_name in RodinaSkyBake.FACE_NAMES:
		var path: String = DIRECTORY + "face_%s.png" % face_name
		if not FileAccess.file_exists(path):
			return null
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image == null or image.is_empty():
			return null
		image.convert(Image.FORMAT_RGB8)
		images.append(image)
	var cube := Cubemap.new()
	if cube.create_from_images(images) != OK:
		return null
	_cube = cube
	return _cube
