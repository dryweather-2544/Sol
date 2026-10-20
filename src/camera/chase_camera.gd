class_name ChaseCamera
extends Camera3D
const VisualStyleScript = preload("res://src/world/visual_style.gd")
## Follows a ship from directly behind and above. Position is anchored to the ship centreline;
## orientation follows with the Rodina-style stiffness so turns swing the view instead of
## snapping rigidly. Physics interpolation smooths the rendered result.

## Sol ship-local convention: +X right, +Y up, -Z forward. A chase camera sits on the
## ship centreline behind it; lateral offsets make the vehicle read as flying sideways.
@export var offset_behind_up := Vector3(0.0, 4.2, 22.0)
@export var look_ahead_distance := 18.0
## Rodina profile frames the ship as a small silhouette, not a large hero object. The values are
## derived from the reference's 200 m/10 degree camera on a ship of roughly this size, then checked
## against the in-game screenshots; they remain presentation-only.
@export var rodina_offset_behind_up := Vector3(0.0, 17.6, 100.0)
@export var rodina_look_ahead_distance := 76.0
## Rodina's default third-person camera stiffness.
@export var orientation_stiffness := 5.0

var target: Node3D
var _fill: OmniLight3D
var _smoothed_orientation := Quaternion.IDENTITY
var _speed_intensity := 0.0
var _entry_intensity := 0.0


## Origin shifts move everything by a constant, so the camera just follows the ship; this only
## clears interpolation history so it does not smear across the jump.
func apply_origin_shift(_shift: Vector3) -> void:
	reset_physics_interpolation()


func _ready() -> void:
	add_to_group("origin_shift")
	# A soft camera-side fill reveals the rear hull when the sun is ahead of the ship. It is a
	# presentation light only: no shadows, short range, and it does not affect the terrain.
	var fill := OmniLight3D.new()
	_fill = fill
	fill.name = "ChaseFill"
	fill.position = Vector3(0.0, 1.2, 1.0)
	fill.omni_range = 145.0 if VisualStyleScript.is_rodina() else 32.0
	fill.light_energy = 1.55
	fill.light_color = Color(0.58, 0.72, 0.95)
	fill.light_specular = 0.25
	fill.shadow_enabled = false
	add_child(fill)
	var key_fill := DirectionalLight3D.new()
	key_fill.name = "ChaseKeyFill"
	key_fill.light_energy = 1.15
	key_fill.light_color = Color(0.70, 0.80, 0.95)
	key_fill.light_specular = 0.2
	key_fill.shadow_enabled = false
	add_child(key_fill)


## Called by the scene each frame. Both values are normalised; the camera only uses them for a
## small FOV pull and restrained shake, never for blur or a permanent screen wobble.
func set_flight_effects(speed: float, entry_heat: float) -> void:
	_speed_intensity = clampf(speed / 12000.0, 0.0, 1.0)
	_entry_intensity = clampf(entry_heat, 0.0, 1.0)


func snap_to_target() -> void:
	if target == null:
		return
	_smoothed_orientation = Quaternion(target.global_basis.orthonormalized())
	_apply(0.0)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var follow := 1.0 - exp(-orientation_stiffness * delta)
	_smoothed_orientation = _smoothed_orientation.slerp(
		Quaternion(target.global_basis.orthonormalized()), follow)
	_apply(0.0)


func _apply(_delta: float) -> void:
	if target == null:
		return
	var ship_basis := target.global_basis.orthonormalized()
	var rig_basis := Basis(_smoothed_orientation).orthonormalized()
	var rodina := VisualStyleScript.is_rodina()
	if _fill != null:
		var wanted_range := 170.0 if rodina else 32.0
		if not is_equal_approx(_fill.omni_range, wanted_range):
			_fill.omni_range = wanted_range
	var offset := rodina_offset_behind_up if rodina else offset_behind_up
	var ahead := rodina_look_ahead_distance if rodina else look_ahead_distance
	# Anchor position to the current ship so the vehicle never crabs sideways. Orientation is
	# the lagged basis, producing the soft swing of the Rodina camera without a side offset.
	var camera_position := target.global_position + ship_basis * offset
	var seconds := Time.get_ticks_msec() * 0.001
	var shake := _speed_intensity * 0.010 + _entry_intensity * 0.085
	camera_position += ship_basis * Vector3(
		sin(seconds * 37.0) * shake,
		sin(seconds * 29.0 + 1.7) * shake * 0.7,
		sin(seconds * 43.0 + 3.1) * shake * 0.35)
	var look_target := target.global_position + rig_basis * Vector3(0.0, 0.0, -ahead)
	var camera_basis := Basis.looking_at(look_target - camera_position, rig_basis.y)
	camera_basis = camera_basis.rotated(Vector3(0.0, 0.0, 1.0), sin(seconds * 23.0) * _entry_intensity * 0.008)
	global_transform = Transform3D(camera_basis, camera_position)


## Pure rig calculation for static orientation tests.
func _apply_basis(basis: Basis) -> void:
	var rodina := false
	if is_instance_valid(get_tree()):
		rodina = VisualStyleScript.is_rodina()
	var offset := rodina_offset_behind_up if rodina else offset_behind_up
	var ahead := rodina_look_ahead_distance if rodina else look_ahead_distance
	var camera_position := target.global_position + basis * offset
	var seconds := Time.get_ticks_msec() * 0.001
	var shake := _speed_intensity * 0.010 + _entry_intensity * 0.085
	camera_position += basis * Vector3(
		sin(seconds * 37.0) * shake,
		sin(seconds * 29.0 + 1.7) * shake * 0.7,
		sin(seconds * 43.0 + 3.1) * shake * 0.35)
	var look_target := target.global_position + basis * Vector3(0.0, 0.0, -ahead)
	var camera_basis := Basis.looking_at(look_target - camera_position, basis.y)
	camera_basis = camera_basis.rotated(Vector3(0.0, 0.0, 1.0), sin(seconds * 23.0) * _entry_intensity * 0.008)
	global_transform = Transform3D(camera_basis, camera_position)
