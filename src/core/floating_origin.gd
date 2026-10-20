class_name FloatingOrigin
extends Node
## Keeps the ship (and so the camera) near Vector3 zero. When the ship drifts more than
## rebase_distance from zero, render_origin moves to the ship and every node in group
## "origin_shift" is told to apply_origin_shift(shift). WorldPos in ShipState never changes, so
## nothing authoritative jumps; only the render-space numbers are re-based.

## Any Node3D with a render_origin and apply_origin_shift(shift) (Ship, OnFootController).
var anchor: Node3D
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
	rebase_count += 1
	var targets: Array = get_tree().get_nodes_in_group("origin_shift") if is_inside_tree() else []
	# The anchor must move first: the chase camera recomputes its transform from the anchor in
	# apply_origin_shift. Camera-after-ship also matches the order in the main scene.
	targets.erase(anchor)
	targets.push_front(anchor)
	for target in targets:
		target.apply_origin_shift(shift)
