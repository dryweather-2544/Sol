class_name HumanoidAvatar
extends Node3D
## A person: the low-poly astronaut model when it is present (assets/characters/astronaut.glb, git-ignored, see ATTRIBUTION.md), else a
## stand-in built from primitives (torso, head, arms, legs). Used for the player, the crew and the hostile drones. The model is one
## skinned mesh with "idle", "walk", "run" and "sprint" animations (made by the project's rig script, see ATTRIBUTION.md); the stand-in swings its limbs.
## Feet are at the node's origin, facing -z.

const MODEL_PATH := "res://assets/characters/astronaut.glb"
## The model is read once and each person gets a copy (null when the file is missing, so the stand-in is used).
static var _model_scene: Node3D
static var _model_tried := false

var _left_arm: Node3D
var _right_arm: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _model: Node3D
var _animations: AnimationPlayer
var _clip := ""
var _phase := 0.0
var seat_drop := 0.0
## Colour of the backpack (the stand-in's legs too); crew roles use different ones.
var accent_color := Color(0.9, 0.45, 0.1)
## Colour of the suit (hostiles are given a red one).
var suit_color := Color(0.82, 0.83, 0.86)


func _ready() -> void:
	_model = _make_model()
	if _model != null:
		add_child(_model)
		_tint(_model)
		_animations = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if _animations != null:
			for clip in _animations.get_animation_list():
				_animations.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			_animations.play("idle")
		return
	_left_arm = Node3D.new()
	_right_arm = Node3D.new()
	_left_leg = Node3D.new()
	_right_leg = Node3D.new()
	var suit := _material(suit_color, 0.6)
	var accent := _material(accent_color, 0.6)
	var visor := _material(Color(0.1, 0.15, 0.25), 0.2)
	_add_box(self, Vector3(0.5, 0.62, 0.28), Vector3(0, 1.15, 0), suit)
	_add_box(self, Vector3(0.3, 0.12, 0.18), Vector3(0, 1.1, 0.2), accent) # backpack
	_add_box(self, Vector3(0.3, 0.3, 0.3), Vector3(0, 1.68, 0), suit)
	_add_box(self, Vector3(0.24, 0.14, 0.05), Vector3(0, 1.7, -0.16), visor)
	_limb(_left_arm, Vector3(-0.33, 1.42, 0), Vector3(0.14, 0.58, 0.14), suit)
	_limb(_right_arm, Vector3(0.33, 1.42, 0), Vector3(0.14, 0.58, 0.14), suit)
	_limb(_left_leg, Vector3(-0.13, 0.84, 0), Vector3(0.18, 0.84, 0.18), accent)
	_limb(_right_leg, Vector3(0.13, 0.84, 0), Vector3(0.18, 0.84, 0.18), accent)


## Sitting: legs forward (the model has none to move) and the whole body lowered onto the seat.
func set_seated(seated: bool) -> void:
	if _left_leg != null:
		for leg in [_left_leg, _right_leg]:
			(leg as Node3D).rotation.x = -1.45 if seated else 0.0
	seat_drop = 0.35 if seated else 0.0


## speed in m/s on foot; the gait scales with it and stops when standing still.
func animate(speed: float, delta: float) -> void:
	_phase += delta * clampf(speed, 0.0, 9.0) * 1.7
	var gait := clampf(speed / 6.0, 0.0, 1.0)
	if _model != null:
		if _animations != null:
			var clip := "idle"
			var rate := 1.0
			if seat_drop == 0.0 and speed > 0.4:
				if speed > 5.0:
					clip = "sprint"
					rate = clampf(speed / 5.5, 0.8, 1.6)
				elif speed > 2.8:
					clip = "run"
					rate = clampf(speed / 3.5, 0.7, 1.5)
				else:
					clip = "walk"
					rate = clampf(speed / 1.4, 0.6, 2.0)
			if clip != _clip or not _animations.is_playing():
				_clip = clip
				_animations.play(clip, 0.25)
			_animations.speed_scale = rate
		return
	if _left_arm == null:
		return
	var swing := gait * 0.8
	_left_arm.rotation.x = sin(_phase) * swing
	_right_arm.rotation.x = -sin(_phase) * swing
	_left_leg.rotation.x = -sin(_phase) * swing
	_right_leg.rotation.x = sin(_phase) * swing


## A copy of the astronaut, or null when the file is not there or cannot be read.
static func _make_model() -> Node3D:
	if not _model_tried:
		_model_tried = true
		var path := ProjectSettings.globalize_path(MODEL_PATH)
		if FileAccess.file_exists(path):
			var document := GLTFDocument.new()
			var state := GLTFState.new()
			if document.append_from_file(path, state) == OK:
				_model_scene = document.generate_scene(state) as Node3D
			if _model_scene == null:
				push_warning("HumanoidAvatar: could not read %s" % MODEL_PATH)
	return _model_scene.duplicate() as Node3D if _model_scene != null else null


## The whole suit is tinted (accent colour blended into the suit colour, scaled so a white-ish suit stays untinted); each person gets
## their own materials.
func _tint(root: Node3D) -> void:
	var tint := suit_color.lerp(accent_color, 0.25)
	tint = tint / maxf(maxf(tint.r, tint.g), tint.b)
	tint.a = 1.0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			var source := instance.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var material := source.duplicate() as StandardMaterial3D
			material.albedo_color = tint
			instance.set_surface_override_material(surface, material)


func _limb(pivot: Node3D, pivot_position: Vector3, size: Vector3, material: Material) -> void:
	pivot.position = pivot_position
	add_child(pivot)
	_add_box(pivot, size, Vector3(0, -size.y * 0.5, 0), material)


func _add_box(parent: Node3D, size: Vector3, local_position: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = local_position
	parent.add_child(node)


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
