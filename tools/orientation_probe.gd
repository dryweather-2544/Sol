extends SceneTree
## Captures the ship through yaw, pitch and roll with the real chase camera. Also checks that
## the camera stays on the ship's centreline and its right axis follows the ship's right axis.

var main: Node
var frames := 0
var step := 0
var states := [
	{"name": "level", "basis": Basis.IDENTITY},
	{"name": "yaw90", "basis": Basis(Vector3.UP, deg_to_rad(90.0))},
	{"name": "pitch30", "basis": Basis(Vector3.RIGHT, deg_to_rad(30.0))},
	{"name": "roll45", "basis": Basis(Vector3.BACK, deg_to_rad(45.0))},
]


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		main.menu.dismiss()
		main.chase_camera.current = true
	if frames < 10:
		return false
	if step >= states.size():
		quit()
		return true
	var record: Dictionary = states[step]
	main.ship.state.basis = record["basis"]
	main.ship.state.velocity = Vector3.ZERO
	main.ship._sync_transform()
	main.chase_camera.snap_to_target()
	if frames % 30 == 0:
		var camera: Camera3D = main.chase_camera
		var ship_basis: Basis = main.ship.global_basis
		var rel: Vector3 = camera.global_position - main.ship.global_position
		print("ORIENT %s lateral=%.4f behind=%.1f right_dot=%.4f up_dot=%.4f ship_up=%s cam_up=%s" % [
			record["name"], rel.dot(ship_basis.x), rel.dot(ship_basis.z), camera.global_basis.x.dot(ship_basis.x),
			camera.global_basis.y.dot(ship_basis.y), ship_basis.y, camera.global_basis.y])
		var image := root.get_viewport().get_texture().get_image()
		image.save_png("artifacts/orientation_%s.png" % record["name"])
		step += 1
	return false
