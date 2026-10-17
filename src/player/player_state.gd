class_name PlayerState
extends RefCounted
## Where the player is and what they control, as three separate facts (research 08 §3):
## posture, location and authority. Every change goes through a try_* method that either
## succeeds or says why not, so nothing ends up half-changed. (Pure state; the physical checks
## - near the seat, seat free, door open - are made by GameSession before calling these.)

enum Posture { STANDING, SITTING_DOWN, SEATED }
enum Location { EXTERIOR, INTERIOR }
enum Authority { NONE, PILOT }
enum Result { OK, BLOCKED_POSTURE, BLOCKED_LOCATION, BLOCKED_AUTHORITY }

var posture := Posture.SEATED
var location := Location.INTERIOR
var authority := Authority.PILOT


class TransitionResult extends RefCounted:
	var result := Result.OK

	func ok() -> bool:
		return result == Result.OK


func try_begin_sit() -> TransitionResult:
	return _change(location == Location.INTERIOR and posture == Posture.STANDING and authority == Authority.NONE, Posture.SITTING_DOWN, location, authority, _why_not_sit())


func try_finish_sit() -> TransitionResult:
	return _change(posture == Posture.SITTING_DOWN, Posture.SEATED, location, Authority.PILOT, Result.BLOCKED_POSTURE)


func try_cancel_sit() -> TransitionResult:
	return _change(posture == Posture.SITTING_DOWN, Posture.STANDING, location, authority, Result.BLOCKED_POSTURE)


func try_stand_up() -> TransitionResult:
	return _change(posture == Posture.SEATED, Posture.STANDING, location, Authority.NONE, Result.BLOCKED_POSTURE)


func try_go_outside() -> TransitionResult:
	return _change(location == Location.INTERIOR and posture == Posture.STANDING, posture, Location.EXTERIOR, authority, Result.BLOCKED_LOCATION)


func try_go_inside() -> TransitionResult:
	return _change(location == Location.EXTERIOR and posture == Posture.STANDING, posture, Location.INTERIOR, authority, Result.BLOCKED_LOCATION)


func is_legal() -> bool:
	if authority == Authority.PILOT and posture != Posture.SEATED:
		return false
	if posture == Posture.SEATED and location != Location.INTERIOR:
		return false
	if posture == Posture.SITTING_DOWN and location != Location.INTERIOR:
		return false
	return true


func _why_not_sit() -> int:
	if location != Location.INTERIOR:
		return Result.BLOCKED_LOCATION
	if authority != Authority.NONE:
		return Result.BLOCKED_AUTHORITY
	return Result.BLOCKED_POSTURE


func _change(allowed: bool, new_posture: int, new_location: int, new_authority: int, failure: int) -> TransitionResult:
	var outcome := TransitionResult.new()
	if not allowed:
		outcome.result = failure
		return outcome
	posture = new_posture
	location = new_location
	authority = new_authority
	return outcome
