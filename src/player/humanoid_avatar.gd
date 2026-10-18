class_name HumanoidAvatar
extends Node3D
## A simple stand-in person built from primitives (no third-party model): torso, head, arms, legs. Arms and
## legs swing with walking speed. Feet are at the node's origin, facing -z.

var _left_arm := Node3D.new()
var _right_arm := Node3D.new()
var _left_leg := Node3D.new()
var _right_leg := Node3D.new()
var _phase := 0.0


func _ready() -> void:
	var suit := _material(Color(0.85, 0.85, 0.88), 0.6)
	var accent := _material(Color(0.9, 0.45, 0.1), 0.6)
	var visor := _material(Color(0.1, 0.15, 0.25), 0.2)
	_add_box(self, Vector3(0.5, 0.62, 0.28), Vector3(0, 1.15, 0), suit)
	_add_box(self, Vector3(0.3, 0.12, 0.18), Vector3(0, 1.1, 0.2), accent) # backpack
	_add_box(self, Vector3(0.3, 0.3, 0.3), Vector3(0, 1.68, 0), suit)
	_add_box(self, Vector3(0.24, 0.14, 0.05), Vector3(0, 1.7, -0.16), visor)
	_limb(_left_arm, Vector3(-0.33, 1.42, 0), Vector3(0.14, 0.58, 0.14), suit)
	_limb(_right_arm, Vector3(0.33, 1.42, 0), Vector3(0.14, 0.58, 0.14), suit)
	_limb(_left_leg, Vector3(-0.13, 0.84, 0), Vector3(0.18, 0.84, 0.18), accent)
	_limb(_right_leg, Vector3(0.13, 0.84, 0), Vector3(0.18, 0.84, 0.18), accent)


## speed in m/s on foot; swing scales with it and stops when standing still.
func animate(speed: float, delta: float) -> void:
	_phase += delta * clampf(speed, 0.0, 9.0) * 1.7
	var swing := clampf(speed / 6.0, 0.0, 1.0) * 0.8
	_left_arm.rotation.x = sin(_phase) * swing
	_right_arm.rotation.x = -sin(_phase) * swing
	_left_leg.rotation.x = -sin(_phase) * swing
	_right_leg.rotation.x = sin(_phase) * swing


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
