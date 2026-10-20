class_name ChaseCamera
extends Camera3D
## Follows a ship from behind and above. Translation is rigid (no lag, so speed never makes the
## ship slide away); only the camera's *orientation reference* lags the ship's, so turns swing
## the view around the ship. Updated in the physics tick so physics interpolation smooths it.

@export var offset_behind_up := Vector3(0.0, 3.4, 17.0)
@export var look_ahead_distance := 40.0
## Bigger = camera orientation catches up with the ship faster (per second).
@export var orientation_stiffness := 5.0

var target: Node3D
var _smoothed_orientation := Quaternion.IDENTITY


## Origin shifts move everything by a constant. The ship is shifted first; recompute the camera
## from it and reset interpolation afterwards so no pre-rebase camera sample survives.
func apply_origin_shift(_shift: Vector3) -> void:
	# The ship has already been moved to the new render origin (FloatingOrigin applies it first).
	# Recompute the camera's current transform here as well, then reset its interpolation history:
	# resetting before the next physics update would leave one pre-rebase camera sample to smear.
	if target != null:
		_apply(0.0)
	reset_physics_interpolation()


func _ready() -> void:
	add_to_group("origin_shift")


func snap_to_target() -> void:
	if target == null:
		return
	_smoothed_orientation = Quaternion(target.global_basis.orthonormalized())
	_apply(0.0)
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var follow_amount := 1.0 - exp(-orientation_stiffness * delta)
	_smoothed_orientation = _smoothed_orientation.slerp(Quaternion(target.global_basis.orthonormalized()), follow_amount)
	_apply(delta)


func _apply(_delta: float) -> void:
	var rig_basis := Basis(_smoothed_orientation)
	var camera_position := target.global_position + rig_basis * offset_behind_up
	var look_target := target.global_position + rig_basis * Vector3(0.0, 0.0, -look_ahead_distance)
	global_transform = Transform3D(Basis.looking_at(look_target - camera_position, rig_basis.y), camera_position)
