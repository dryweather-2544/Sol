class_name WalkwayController
extends RefCounted
## The ramp behind the outer door: STOWED, DEPLOYING, DEPLOYED, RETRACTING. Deploys only when
## landed and slow, stows by itself if the ship moves fast, and never stows under a person.
## Speed thresholds follow research FLY-31 (deploy below 75 speed^2, stow above 500).

enum State { STOWED, DEPLOYING, DEPLOYED, RETRACTING }

const MOVE_SECONDS := 2.0
const DEPLOY_MAX_SPEED_SQUARED := 75.0
const STOW_MIN_SPEED_SQUARED := 500.0

var state := State.STOWED
## 0 = stowed, 1 = fully deployed.
var progress := 0.0
## Set by the game each tick: is anyone standing on the ramp?
var occupied := false


func request_deploy(ship_state: ShipState) -> bool:
	if not ship_state.landed or ship_state.velocity.length_squared() >= DEPLOY_MAX_SPEED_SQUARED:
		return false
	if state == State.STOWED or state == State.RETRACTING:
		state = State.DEPLOYING
	return true


## False (and no change) while someone stands on the ramp.
func request_retract() -> bool:
	if occupied:
		return false
	if state == State.DEPLOYED or state == State.DEPLOYING:
		state = State.RETRACTING
	return true


func update(delta: float, ship_state: ShipState) -> void:
	if (state == State.DEPLOYED or state == State.DEPLOYING) and not occupied \
			and ship_state.velocity.length_squared() > STOW_MIN_SPEED_SQUARED:
		state = State.RETRACTING
	match state:
		State.DEPLOYING:
			progress = move_toward(progress, 1.0, delta / MOVE_SECONDS)
			if progress >= 1.0:
				state = State.DEPLOYED
		State.RETRACTING:
			progress = move_toward(progress, 0.0, delta / MOVE_SECONDS)
			if progress <= 0.0:
				state = State.STOWED


func is_deployed() -> bool:
	return state == State.DEPLOYED


func is_stowed() -> bool:
	return state == State.STOWED
