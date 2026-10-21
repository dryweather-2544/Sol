class_name CrewView
extends Node3D
## Draws the crew: a HumanoidAvatar per person, as a child of the ship so it rides along (positions are ship-local).

const ROLE_COLORS := {&"engineer": Color(0.95, 0.55, 0.1), &"gunner": Color(0.85, 0.2, 0.2), &"scientist": Color(0.2, 0.6, 0.9)}

var crew: ShipCrew
## Bigger on the inside (ADR 0012): people in the layout's pocket rooms are drawn only while the camera is inside.
var layout: InteriorLayout
var pocket_visible := true
var _avatars := {} # member id -> HumanoidAvatar


func _process(delta: float) -> void:
	if crew == null:
		return
	for person in crew.members:
		if not _avatars.has(person.id):
			var avatar := HumanoidAvatar.new()
			avatar.accent_color = ROLE_COLORS.get(person.role, Color(0.9, 0.45, 0.1))
			add_child(avatar)
			_avatars[person.id] = avatar
		var view: HumanoidAvatar = _avatars[person.id]
		view.position = person.body.position - Vector3(0, view.seat_drop, 0)
		view.rotation.y = person.body.yaw
		view.set_seated(person.seat_id != &"")
		view.animate(person.speed, delta)
		view.visible = pocket_visible or layout == null or not layout.is_pocket(layout.room_at(person.body.position.x, person.body.position.z))
	for member_id in _avatars.keys():
		if crew.member(member_id) == null:
			(_avatars[member_id] as Node3D).queue_free()
			_avatars.erase(member_id)
