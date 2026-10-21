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
## Rodina chase camera (LimnalWarpView): when follow_distance > 0 the camera sits that far from the ship at
## follow_angle (radians above the ship's back) instead of offset_behind_up; shake is this frame's (yaw, pitch) in
## radians. Rest values (0, 0, zero) leave the Sol camera unchanged.
var follow_distance := 0.0
var follow_angle := 0.0
var shake := Vector2.ZERO
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


## The Rodina-inspired style uses a wider composition; the Sol style keeps the original close camera.
func active_offset() -> Vector3:
	return VisualStyle.chase_camera_offset()


func _apply(_delta: float) -> void:
	var rig_basis := Basis(_smoothed_orientation)
	var offset := active_offset()
	if follow_distance > 0.0:
		offset = Vector3(0.0, sin(follow_angle), cos(follow_angle)) * follow_distance
	var camera_position := target.global_position + rig_basis * offset
	var look_target := target.global_position + rig_basis * Vector3(0.0, 0.0, -look_ahead_distance)
	var view_basis := Basis.looking_at(look_target - camera_position, rig_basis.y)
	if shake != Vector2.ZERO:
		view_basis = view_basis * Basis.from_euler(Vector3(shake.y, shake.x, 0.0))
	global_transform = Transform3D(view_basis, camera_position)
