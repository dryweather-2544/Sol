class_name AlarmSchedule
extends RefCounted
## Which alarm the ship's PA plays and when. One alarm voice only: fire beats reactor beats hull. A new alarm sounds at once, repeats
## every 2 s three times, then every 8 s until the condition clears (so a long fire does not nag). Pure logic; AudioService plays it.

enum Kind { NONE, HULL, REACTOR, FIRE } ## a higher value wins

const FAST_REPEATS := 3
const FAST_INTERVAL_SECONDS := 2.0
const SLOW_INTERVAL_SECONDS := 8.0

var active := Kind.NONE
var _plays_in_this_alarm := 0
var _seconds_until_next_play := 0.0


static func pick(fire: bool, reactor_down: bool, hull_critical: bool) -> Kind:
	if fire:
		return Kind.FIRE
	if reactor_down:
		return Kind.REACTOR
	if hull_critical:
		return Kind.HULL
	return Kind.NONE


## Advances by `delta` seconds with `wanted` as the current highest-priority alarm; true means "play the alarm sound now".
func step(wanted: Kind, delta: float) -> bool:
	if wanted != active:
		active = wanted
		_plays_in_this_alarm = 0
		_seconds_until_next_play = 0.0
	if active == Kind.NONE:
		return false
	_seconds_until_next_play -= delta
	if _seconds_until_next_play > 0.0:
		return false
	_plays_in_this_alarm += 1
	_seconds_until_next_play = FAST_INTERVAL_SECONDS if _plays_in_this_alarm < FAST_REPEATS else SLOW_INTERVAL_SECONDS
	return true
