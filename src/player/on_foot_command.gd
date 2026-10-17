class_name OnFootCommand
extends RefCounted
## One tick of on-foot intent (the walking equivalent of PilotCommand).

## x = right, y = forward, each -1..1.
var move := Vector2.ZERO
var run := false
var jump := false
## Radians to turn the heading this tick; positive turns left (counter-clockwise seen from above).
var yaw_delta := 0.0
