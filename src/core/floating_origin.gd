class_name FloatingOrigin
extends Node
## Keeps the ship (and so the camera) near Vector3 zero. When the ship drifts more than
## rebase_distance from zero, render_origin moves to the ship and every node in group
## "origin_shift" is told to slide the opposite way. WorldPos in ShipState never changes, so
## nothing authoritative jumps; only the render-space numbers are re-based.

var anchor: Ship
var rebase_distance := 1024.0
var rebase_count := 0


## Returns the render-space offset to re-base by (the anchor's current local position), or ZERO.
static func compute_shift(anchor_local_position: Vector3, threshold: float) -> Vector3:
	if anchor_local_position.length() > threshold:
		return anchor_local_position
	return Vector3.ZERO


func _physics_process(_delta: float) -> void:
	update()


func update() -> void:
	if anchor == null:
		return
	var shift := compute_shift(anchor.position, rebase_distance)
	if shift == Vector3.ZERO:
		return
	anchor.render_origin = anchor.render_origin.offset_by(shift)
	anchor.position -= shift
	rebase_count += 1
	if is_inside_tree():
		anchor.reset_physics_interpolation()
		get_tree().call_group("origin_shift", "apply_origin_shift", shift)
