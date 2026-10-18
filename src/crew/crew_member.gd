class_name CrewMember
extends RefCounted
## One person aboard who is not the player: a body that walks the ship interior (the same InteriorBody the
## player uses), an optional seat, and the route they are following. Data only; ShipCrew moves them.

var id: StringName
var role: StringName
var body := InteriorBody.new()
## Seat held (reserved or occupied), or &"".
var seat_id := &""
## Remaining waypoints: {position: Vector2 (x, z), door: StringName (portal to open on the way, or &"")}.
var path: Array = []
## The station the person is heading for or working at, and whether arrival has been dealt with.
var station_id := &""
var arrived := true
## Seconds without making progress on the current waypoint (a stuck person gives up their route).
var blocked_seconds := 0.0
var speed := 0.0
var door_cooldown := 0.0


func _init(member_id: StringName, member_role: StringName) -> void:
	id = member_id
	role = member_role


func position() -> Vector3:
	return body.position
