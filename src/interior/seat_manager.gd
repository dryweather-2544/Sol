class_name SeatManager
extends RefCounted
## One occupant per seat. Sitting takes SIT_SECONDS (the seat is reserved meanwhile, so a second
## person cannot take it), and can be cancelled before it finishes.

enum SeatState { FREE, RESERVED, OCCUPIED }

const SIT_SECONDS := 0.6

signal seat_occupied(seat_id: StringName, actor_id: StringName)
signal seat_released(seat_id: StringName, actor_id: StringName)

var _state := {}    # seat_id -> SeatState
var _occupant := {} # seat_id -> actor_id
var _timer := {}    # seat_id -> seconds left while RESERVED


func _init(seat_ids: Array = []) -> void:
	for seat_id in seat_ids:
		_state[seat_id] = SeatState.FREE


func try_sit(actor_id: StringName, seat_id: StringName) -> bool:
	if not _state.has(seat_id) or _state[seat_id] != SeatState.FREE or seat_of(actor_id) != &"":
		return false
	_state[seat_id] = SeatState.RESERVED
	_occupant[seat_id] = actor_id
	_timer[seat_id] = SIT_SECONDS
	return true


## Gives up a seat that is still being sat in. Returns false if nothing was reserved.
func cancel_sit(actor_id: StringName) -> bool:
	var seat_id := seat_of(actor_id)
	if seat_id == &"" or _state[seat_id] != SeatState.RESERVED:
		return false
	_release(seat_id)
	return true


func stand(actor_id: StringName) -> bool:
	var seat_id := seat_of(actor_id)
	if seat_id == &"" or _state[seat_id] != SeatState.OCCUPIED:
		return false
	_release(seat_id)
	return true


func update(delta: float) -> void:
	for seat_id in _state:
		if _state[seat_id] == SeatState.RESERVED:
			_timer[seat_id] -= delta
			if _timer[seat_id] <= 0.0:
				_state[seat_id] = SeatState.OCCUPIED
				seat_occupied.emit(seat_id, _occupant[seat_id])


## The seat an actor holds (reserved or occupied), or &"".
func seat_of(actor_id: StringName) -> StringName:
	for seat_id in _occupant:
		if _occupant[seat_id] == actor_id:
			return seat_id
	return &""


func state_of(seat_id: StringName) -> int:
	return _state.get(seat_id, SeatState.FREE)


func occupant_of(seat_id: StringName) -> StringName:
	return _occupant.get(seat_id, &"")


func is_seated(actor_id: StringName) -> bool:
	var seat_id := seat_of(actor_id)
	return seat_id != &"" and _state[seat_id] == SeatState.OCCUPIED


func _release(seat_id: StringName) -> void:
	var actor_id: StringName = _occupant[seat_id]
	var was_occupied: bool = _state[seat_id] == SeatState.OCCUPIED
	_state[seat_id] = SeatState.FREE
	_occupant.erase(seat_id)
	_timer.erase(seat_id)
	if was_occupied:
		seat_released.emit(seat_id, actor_id)


## Forget everything (used when a save is loaded).
func reset() -> void:
	for seat_id in _state:
		_state[seat_id] = SeatState.FREE
	_occupant.clear()
	_timer.clear()
