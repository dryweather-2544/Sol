class_name PlayerState
extends RefCounted
## Where the player is and what they control, as three separate facts (research 08 §3):
## posture, location and authority. Every change goes through a try_* method that either
## succeeds or says why not, so the UI can explain and nothing ends up half-changed.
## Interiors, seats and airlocks (M3) add more transitions here.

enum Posture { STANDING, SEATED }
enum Location { EXTERIOR, INTERIOR }
enum Authority { NONE, PILOT }
enum Result { OK, BLOCKED_AUTHORITY, BLOCKED_NOT_LANDED, BLOCKED_MOVING, BLOCKED_TOO_FAR }

const EXIT_MAX_SHIP_SPEED := 4.0
const BOARD_MAX_DISTANCE := 10.0

var posture := Posture.SEATED
var location := Location.INTERIOR
var authority := Authority.PILOT


class TransitionResult extends RefCounted:
	var result := Result.OK
	var message := ""

	func ok() -> bool:
		return result == Result.OK


## Standing up from the pilot seat and stepping out of a landed ship.
func try_exit_ship(ship_state: ShipState) -> TransitionResult:
	var outcome := TransitionResult.new()
	if authority != Authority.PILOT:
		outcome.result = Result.BLOCKED_AUTHORITY
		outcome.message = "You are not piloting the ship"
	elif not ship_state.landed:
		outcome.result = Result.BLOCKED_NOT_LANDED
		outcome.message = "Land before leaving the ship"
	elif ship_state.speed() >= EXIT_MAX_SHIP_SPEED:
		outcome.result = Result.BLOCKED_MOVING
		outcome.message = "Ship is still moving"
	else:
		posture = Posture.STANDING
		location = Location.EXTERIOR
		authority = Authority.NONE
	return outcome


## Walking up to the ship and taking the pilot seat.
func try_board_ship(distance_to_ship: float, ship_state: ShipState) -> TransitionResult:
	var outcome := TransitionResult.new()
	if authority == Authority.PILOT:
		outcome.result = Result.BLOCKED_AUTHORITY
		outcome.message = "Already piloting"
	elif distance_to_ship > BOARD_MAX_DISTANCE:
		outcome.result = Result.BLOCKED_TOO_FAR
		outcome.message = "Too far from the ship"
	elif not ship_state.landed:
		outcome.result = Result.BLOCKED_NOT_LANDED
		outcome.message = "Ship is not landed"
	else:
		posture = Posture.SEATED
		location = Location.INTERIOR
		authority = Authority.PILOT
	return outcome
